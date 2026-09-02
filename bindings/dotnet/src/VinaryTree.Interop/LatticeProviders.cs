using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;

namespace VinaryTree.Interop;

/// <summary>Concurrency promises advertised by a managed lattice value.</summary>
[Flags]
public enum LatticeProviderFlags : ulong
{
    /// <summary>Calls must remain on the thread that created the provider.</summary>
    ThreadBound = 1,
    /// <summary>Concurrent calls are safe without an external sequential gate.</summary>
    ParallelReentrant = 2,
}

/// <summary>Domain identity and concurrency promises for one lattice value.</summary>
public readonly record struct LatticeProviderOptions(InteropDomainId DomainId, LatticeProviderFlags Flags = 0);

/// <summary>
/// A validated foreign lattice operand borrowed only for the duration of one provider callback.
/// Do not retain this object or use it after the callback returns.
/// </summary>
public sealed unsafe class LatticeOperand
{
    private const int MaxProviderBytes = 16 * 1024 * 1024;
    private const int MaxBufferAttempts = 3;
    private readonly NativeResource resource;
    private readonly NativeLatticeVTable* table;

    internal LatticeOperand(NativeResource resource, NativeLatticeVTable* table)
    {
        this.resource = resource;
        this.table = table;
    }

    /// <summary>True when the operand advertises a canonical stable-byte encoding.</summary>
    public bool HasStableBytes =>
        (table->Flags & NativeAbi.LatticeStableBytes) != 0 && table->StableBytes != null;

    /// <summary>Read the bounded, canonical encoding supplied by the operand's own provider.</summary>
    public byte[] GetStableBytes()
    {
        if (!HasStableBytes)
        {
            throw new DictionaryInteropException(DictionaryInteropStatus.Unsupported, "lattice stable bytes are unavailable");
        }
        nuint written = 0;
        nuint required = 0;
        DictionaryInteropStatus status = table->StableBytes(resource.Context, null, 0, &written, &required);
        Check(status, "query lattice stable-byte size");
        if (written != 0) throw new InvalidOperationException("lattice size query wrote a nonzero byte count");
        for (int attempt = 0; attempt < MaxBufferAttempts; attempt++)
        {
            if (required > MaxProviderBytes)
            {
                throw new DictionaryInteropException(DictionaryInteropStatus.LimitExceeded, "lattice stable bytes exceed the defensive limit");
            }
            byte[] bytes = new byte[checked((int)required)];
            nuint nextWritten = nuint.MaxValue;
            nuint nextRequired = nuint.MaxValue;
            fixed (byte* output = bytes)
            {
                status = table->StableBytes(resource.Context, output, (nuint)bytes.Length, &nextWritten, &nextRequired);
            }
            Check(status, "read lattice stable bytes");
            if (nextWritten > (nuint)bytes.Length || nextWritten > nextRequired)
            {
                throw new InvalidOperationException("lattice provider returned impossible byte counts");
            }
            if (nextRequired <= (nuint)bytes.Length)
            {
                if (nextWritten != nextRequired)
                {
                    throw new InvalidOperationException("lattice provider returned an incomplete final buffer");
                }
                if (nextRequired != (nuint)bytes.Length) Array.Resize(ref bytes, checked((int)nextRequired));
                return bytes;
            }
            required = nextRequired;
        }
        throw new InvalidOperationException("lattice stable-byte size did not stabilize");
    }

    private static void Check(DictionaryInteropStatus status, string operation)
    {
        if (status != DictionaryInteropStatus.Ok) throw new DictionaryInteropException(status, operation);
    }
}

/// <summary>An immutable lattice value implemented in managed code.</summary>
public interface ILatticeValueProvider
{
    /// <summary>Return this value joined with a compatible foreign value.</summary>
    ILatticeValueProvider Join(LatticeOperand other);

    /// <summary>Return this value met with a compatible foreign value.</summary>
    ILatticeValueProvider Meet(LatticeOperand other);

    /// <summary>Compare this value with a compatible foreign value.</summary>
    bool EqualsValue(LatticeOperand other);

    /// <summary>Return a concise UTF-8 diagnostic representation.</summary>
    string GetDiagnostic();
}

/// <summary>Optional canonical serialization for a host-defined lattice value.</summary>
public interface IStableLatticeValueProvider : ILatticeValueProvider
{
    /// <summary>Return the canonical bytes used for cross-provider decoding and hashing.</summary>
    ReadOnlyMemory<byte> GetStableBytes();
}

public static partial class HostProviders
{
    /// <summary>Export one managed lattice value.</summary>
    public static HostedResource CreateLatticeValue(
        ILatticeValueProvider provider,
        LatticeProviderOptions options)
    {
        ArgumentNullException.ThrowIfNull(provider);
        LatticeContext context = LatticeContext.Create(provider, options);
        return new(context);
    }
}

internal sealed unsafe class LatticeContext : ProviderContext
{
    private readonly ILatticeValueProvider provider;
    private readonly LatticeProviderOptions options;
    private readonly NativeInterfaceId domainId;
    private NativeLatticeVTable* table;

    private LatticeContext(ILatticeValueProvider provider, LatticeProviderOptions options)
    {
        const LatticeProviderFlags known = LatticeProviderFlags.ThreadBound | LatticeProviderFlags.ParallelReentrant;
        if ((options.Flags & ~known) != 0 ||
            (options.Flags & known) == known)
        {
            throw new ArgumentException("lattice provider threading flags are invalid", nameof(options));
        }
        this.provider = provider;
        this.options = options;
        domainId = NativeAbi.ToNative(options.DomainId);
        ulong flags = (ulong)options.Flags | NativeAbi.LatticeBatch;
        bool stable = provider is IStableLatticeValueProvider;
        if (stable) flags |= NativeAbi.LatticeStableBytes;
        table = AllocateVTable(new NativeLatticeVTable
        {
            StructSize = (nuint)sizeof(NativeLatticeVTable),
            InterfaceVersion = NativeAbi.InterfaceVersion,
            Reserved = 0,
            Flags = flags,
            DomainId = domainId,
            Join = &LatticeExports.Join,
            Meet = &LatticeExports.Meet,
            Equal = &LatticeExports.Equal,
            StableBytes = stable ? &LatticeExports.StableBytes : null,
            Diagnostic = &LatticeExports.Diagnostic,
            JoinMany = &LatticeExports.JoinMany,
            MeetMany = &LatticeExports.MeetMany,
        });
    }

    internal static LatticeContext Create(ILatticeValueProvider provider, LatticeProviderOptions options)
    {
        var context = new LatticeContext(provider, options);
        context.Export();
        return context;
    }

    internal ILatticeValueProvider Provider => provider;
    internal LatticeProviderOptions Options => options;
    internal NativeInterfaceId DomainId => domainId;

    internal override DictionaryInteropStatus Query(byte* interfaceId, uint minimumVersion, nint* output)
    {
        if (!NativeAbi.IdEquals(interfaceId, NativeAbi.LatticeId) || minimumVersion > NativeAbi.InterfaceVersion)
        {
            return DictionaryInteropStatus.Unsupported;
        }
        *output = (nint)table;
        return DictionaryInteropStatus.Ok;
    }

    protected override void DisposeNative()
    {
        FreeVTable(table);
        table = null;
    }
}

internal static unsafe class LatticeExports
{
    private static LatticeContext Context(nint raw) => (LatticeContext)ProviderContext.FromRaw(raw);

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus Join(nint raw, NativeResource* other, NativeResource* output) =>
        Binary(raw, other, output, true);

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus Meet(nint raw, NativeResource* other, NativeResource* output) =>
        Binary(raw, other, output, false);

    private static DictionaryInteropStatus Binary(nint raw, NativeResource* other, NativeResource* output, bool join)
    {
        if (raw == 0 || other is null || output is null) return DictionaryInteropStatus.NullPointer;
        try
        {
            LatticeContext context = Context(raw);
            DictionaryInteropStatus status = GetOperand(context, other, out LatticeOperand? operand);
            if (status != DictionaryInteropStatus.Ok) return status;
            ILatticeValueProvider result = join
                ? context.Provider.Join(operand!)
                : context.Provider.Meet(operand!);
            if (result is null) return DictionaryInteropStatus.ProviderError;
            *output = LatticeContext.Create(result, context.Options).Resource;
            return DictionaryInteropStatus.Ok;
        }
        catch (Exception exception) { return ProviderOutput.FromException(exception); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus Equal(nint raw, NativeResource* other, byte* output)
    {
        if (raw == 0 || other is null || output is null) return DictionaryInteropStatus.NullPointer;
        try
        {
            LatticeContext context = Context(raw);
            DictionaryInteropStatus status = GetOperand(context, other, out LatticeOperand? operand);
            if (status != DictionaryInteropStatus.Ok) return status;
            bool equal = context.Provider.EqualsValue(operand!);
            *output = equal ? (byte)1 : (byte)0;
            return DictionaryInteropStatus.Ok;
        }
        catch (Exception exception) { return ProviderOutput.FromException(exception); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus StableBytes(
        nint raw,
        byte* output,
        nuint capacity,
        nuint* written,
        nuint* required)
    {
        if (raw == 0) return DictionaryInteropStatus.NullPointer;
        try
        {
            if (Context(raw).Provider is not IStableLatticeValueProvider stable)
            {
                return DictionaryInteropStatus.Unsupported;
            }
            return ProviderOutput.WriteBytes(stable.GetStableBytes().Span, output, capacity, written, required);
        }
        catch (Exception exception) { return ProviderOutput.FromException(exception); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus Diagnostic(
        nint raw,
        byte* output,
        nuint capacity,
        nuint* written,
        nuint* required)
    {
        if (raw == 0) return DictionaryInteropStatus.NullPointer;
        try
        {
            byte[] bytes = Encoding.UTF8.GetBytes(Context(raw).Provider.GetDiagnostic() ?? string.Empty);
            return ProviderOutput.WriteBytes(bytes, output, capacity, written, required);
        }
        catch (Exception exception) { return ProviderOutput.FromException(exception); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus JoinMany(
        nint raw,
        NativeResource* others,
        nuint count,
        NativeResource* output) => Fold(raw, others, count, output, true);

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus MeetMany(
        nint raw,
        NativeResource* others,
        nuint count,
        NativeResource* output) => Fold(raw, others, count, output, false);

    private static DictionaryInteropStatus Fold(
        nint raw,
        NativeResource* others,
        nuint count,
        NativeResource* output,
        bool join)
    {
        if (raw == 0 || output is null || (count != 0 && others is null))
        {
            return DictionaryInteropStatus.NullPointer;
        }
        try
        {
            LatticeContext context = Context(raw);
            if (count == 0)
            {
                context.Retain();
                *output = context.Resource;
                return DictionaryInteropStatus.Ok;
            }
            DictionaryInteropStatus status = GetOperand(context, &others[0], out LatticeOperand? first);
            if (status != DictionaryInteropStatus.Ok) return status;
            ILatticeValueProvider accumulator = join
                ? context.Provider.Join(first!)
                : context.Provider.Meet(first!);
            if (accumulator is null) return DictionaryInteropStatus.ProviderError;
            for (nuint index = 1; index < count; index++)
            {
                status = GetOperand(context, &others[index], out LatticeOperand? next);
                if (status != DictionaryInteropStatus.Ok) return status;
                accumulator = join ? accumulator.Join(next!) : accumulator.Meet(next!);
                if (accumulator is null) return DictionaryInteropStatus.ProviderError;
            }
            *output = LatticeContext.Create(accumulator, context.Options).Resource;
            return DictionaryInteropStatus.Ok;
        }
        catch (Exception exception) { return ProviderOutput.FromException(exception); }
    }

    private static DictionaryInteropStatus GetOperand(
        LatticeContext context,
        NativeResource* resource,
        out LatticeOperand? operand)
    {
        operand = null;
        if (resource is null || resource->Context == 0 || resource->VTable == 0)
        {
            return DictionaryInteropStatus.NullPointer;
        }
        NativeResourceVTable* baseTable = (NativeResourceVTable*)resource->VTable;
        if (baseTable->StructSize < (nuint)sizeof(NativeResourceVTable) ||
            baseTable->AbiVersion != NativeAbi.AbiVersion ||
            baseTable->Reserved != 0 ||
            baseTable->QueryInterface == null)
        {
            return DictionaryInteropStatus.InvalidArgument;
        }
        NativeInterfaceId id = default;
        NativeAbi.LatticeId.CopyTo(new Span<byte>(id.Bytes, 16));
        nint rawTable = 0;
        DictionaryInteropStatus status = baseTable->QueryInterface(
            resource->Context,
            id.Bytes,
            NativeAbi.InterfaceVersion,
            &rawTable);
        if (status != DictionaryInteropStatus.Ok)
        {
            return status == DictionaryInteropStatus.Unsupported ? DictionaryInteropStatus.InvalidArgument : status;
        }
        if (rawTable == 0) return DictionaryInteropStatus.ProviderError;
        NativeLatticeVTable* table = (NativeLatticeVTable*)rawTable;
        if (table->StructSize < (nuint)sizeof(NativeLatticeVTable) ||
            table->InterfaceVersion < NativeAbi.InterfaceVersion ||
            table->Reserved != 0 ||
            table->Join == null ||
            table->Meet == null ||
            table->Equal == null ||
            !SameDomain(&table->DomainId, context.DomainId))
        {
            return DictionaryInteropStatus.InvalidArgument;
        }
        operand = new LatticeOperand(*resource, table);
        return DictionaryInteropStatus.Ok;
    }

    private static bool SameDomain(NativeInterfaceId* left, NativeInterfaceId right)
    {
        for (int index = 0; index < 16; index++)
        {
            if (left->Bytes[index] != right.Bytes[index]) return false;
        }
        return true;
    }
}
