using System.Buffers.Binary;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;

namespace VinaryTree.Interop;

/// <summary>An exact 16-byte identity for one host-defined algebraic domain.</summary>
public readonly record struct InteropDomainId
{
    private readonly ulong low;
    private readonly ulong high;

    /// <summary>Copy an exact 16-byte domain identity.</summary>
    public InteropDomainId(ReadOnlySpan<byte> bytes)
    {
        if (bytes.Length != 16) throw new ArgumentException("a domain identity must contain exactly 16 bytes", nameof(bytes));
        low = BinaryPrimitives.ReadUInt64LittleEndian(bytes);
        high = BinaryPrimitives.ReadUInt64LittleEndian(bytes[8..]);
    }

    /// <summary>Create an identity from exactly 16 single-byte ASCII characters.</summary>
    public static InteropDomainId FromAscii(string value)
    {
        ArgumentNullException.ThrowIfNull(value);
        if (value.Length != 16 || !value.All(static character => character <= 0x7f))
        {
            throw new ArgumentException("a domain identity must contain exactly 16 ASCII characters", nameof(value));
        }
        Span<byte> bytes = stackalloc byte[16];
        for (int index = 0; index < value.Length; index++) bytes[index] = (byte)value[index];
        return new(bytes);
    }

    /// <summary>Return a defensive copy of the 16 identity bytes.</summary>
    public byte[] ToByteArray()
    {
        byte[] bytes = new byte[16];
        CopyTo(bytes);
        return bytes;
    }

    internal void CopyTo(Span<byte> destination)
    {
        if (destination.Length < 16) throw new ArgumentException("destination is shorter than 16 bytes", nameof(destination));
        BinaryPrimitives.WriteUInt64LittleEndian(destination, low);
        BinaryPrimitives.WriteUInt64LittleEndian(destination[8..], high);
    }

    /// <inheritdoc />
    public override string ToString() => Convert.ToHexString(ToByteArray());
}

/// <summary>
/// One owned retain of a managed provider exported through the native resource ABI.
/// Dispose it with <see langword="using"/>; native consumers may independently retain it.
/// </summary>
public sealed unsafe class HostedResource : IDictionaryResource, IDisposable
{
    private ProviderContext? context;

    internal HostedResource(ProviderContext context) => this.context = context;

    /// <inheritdoc />
    public TResult WithResource<TResult>(ResourceCallback<TResult> callback)
    {
        ArgumentNullException.ThrowIfNull(callback);
        ProviderContext? current = Volatile.Read(ref context);
        if (current is null || !current.TryRetain()) throw new ObjectDisposedException(nameof(HostedResource));
        try
        {
            NativeResource resource = current.Resource;
            return callback(&resource);
        }
        finally
        {
            current.Release();
        }
    }

    /// <summary>Release this wrapper's owned retain.</summary>
    public void Dispose()
    {
        DisposeCore();
        GC.SuppressFinalize(this);
    }

    private void DisposeCore() => Interlocked.Exchange(ref context, null)?.Release();

    /// <summary>Releases the managed retain if deterministic disposal was omitted.</summary>
    ~HostedResource() => DisposeCore();
}

internal abstract unsafe class ProviderContext
{
    private static readonly nint ResourceVTable = AllocateResourceVTable();
    private int retains = 1;
    private GCHandle handle;
    private nint rawContext;

    internal NativeResource Resource => new(rawContext, ResourceVTable);

    internal void Export()
    {
        if (rawContext != 0) throw new InvalidOperationException("provider context was already exported");
        try
        {
            handle = GCHandle.Alloc(this, GCHandleType.Normal);
            rawContext = GCHandle.ToIntPtr(handle);
        }
        catch
        {
            retains = 0;
            DisposeNative();
            throw;
        }
    }

    internal bool TryRetain()
    {
        int observed = Volatile.Read(ref retains);
        while (observed != 0)
        {
            int next = checked(observed + 1);
            int prior = Interlocked.CompareExchange(ref retains, next, observed);
            if (prior == observed) return true;
            observed = prior;
        }
        return false;
    }

    internal void Retain()
    {
        if (!TryRetain()) throw new ObjectDisposedException(GetType().Name);
    }

    internal void Release()
    {
        if (Interlocked.Decrement(ref retains) != 0) return;
        DisposeNative();
        rawContext = 0;
        if (handle.IsAllocated) handle.Free();
    }

    internal abstract DictionaryInteropStatus Query(byte* interfaceId, uint minimumVersion, nint* output);

    protected abstract void DisposeNative();

    protected static T* AllocateVTable<T>(T value) where T : unmanaged
    {
        T* table = (T*)NativeMemory.Alloc((nuint)sizeof(T));
        if (table is null) throw new OutOfMemoryException();
        *table = value;
        return table;
    }

    protected static void FreeVTable(void* table) => NativeMemory.Free(table);

    internal static ProviderContext FromRaw(nint context)
    {
        if (context == 0) throw new ArgumentNullException(nameof(context));
        return (ProviderContext)(GCHandle.FromIntPtr(context).Target
            ?? throw new InvalidOperationException("provider context is unavailable"));
    }

    private static nint AllocateResourceVTable()
    {
        NativeResourceVTable* table = AllocateVTable(new NativeResourceVTable
        {
            StructSize = (nuint)sizeof(NativeResourceVTable),
            AbiVersion = NativeAbi.AbiVersion,
            Reserved = 0,
            Retain = &ProviderExports.Retain,
            Release = &ProviderExports.Release,
            QueryInterface = &ProviderExports.QueryInterface,
        });
        return (nint)table;
    }
}

internal static unsafe class ProviderExports
{
    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static void Retain(nint raw)
    {
        try { ProviderContext.FromRaw(raw).Retain(); }
        catch { /* The C retain contract has no error channel. */ }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static void Release(nint raw)
    {
        try { ProviderContext.FromRaw(raw).Release(); }
        catch { /* Foreign exceptions must never cross the ABI. */ }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus QueryInterface(
        nint raw,
        byte* interfaceId,
        uint minimumVersion,
        nint* output)
    {
        if (raw == 0 || interfaceId is null || output is null) return DictionaryInteropStatus.NullPointer;
        try { return ProviderContext.FromRaw(raw).Query(interfaceId, minimumVersion, output); }
        catch (OutOfMemoryException) { return DictionaryInteropStatus.LimitExceeded; }
        catch { return DictionaryInteropStatus.ProviderError; }
    }
}

internal static unsafe class ProviderOutput
{
    internal static DictionaryInteropStatus WriteBytes(
        ReadOnlySpan<byte> source,
        byte* output,
        nuint capacity,
        nuint* written,
        nuint* required)
    {
        if (written is null || required is null || (capacity != 0 && output is null))
        {
            return DictionaryInteropStatus.NullPointer;
        }
        *required = (nuint)source.Length;
        nuint count = Math.Min(capacity, (nuint)source.Length);
        *written = count;
        if (count != 0) source[..checked((int)count)].CopyTo(new Span<byte>(output, checked((int)count)));
        return DictionaryInteropStatus.Ok;
    }

    internal static DictionaryInteropStatus FromException(Exception exception) =>
        exception is OutOfMemoryException
            ? DictionaryInteropStatus.LimitExceeded
            : DictionaryInteropStatus.ProviderError;
}
