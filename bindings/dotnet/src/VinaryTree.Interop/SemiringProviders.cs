using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;

namespace VinaryTree.Interop;

/// <summary>Concurrency promises advertised by a managed semiring provider.</summary>
[Flags]
public enum SemiringProviderFlags : ulong
{
    /// <summary>Calls must remain on the thread that created the provider.</summary>
    ThreadBound = 1,
    /// <summary>Concurrent calls are safe without an external sequential gate.</summary>
    ParallelReentrant = 2,
}

/// <summary>Algebraic laws and capabilities asserted by a semiring provider.</summary>
[Flags]
public enum SemiringProperties : ulong
{
    /// <summary>Canonical stable bytes can serve as a hash key.</summary>
    Hashable = 1,
    /// <summary>Addition is idempotent.</summary>
    IdempotentPlus = 2,
    /// <summary>The semiring has bounded closure.</summary>
    KClosed = 4,
    /// <summary>A sum is zero only when both operands are zero.</summary>
    ZeroSumFree = 8,
    /// <summary>Multiplication is commutative.</summary>
    CommutativeTimes = 16,
    /// <summary>The natural order is total.</summary>
    TotallyOrdered = 32,
    /// <summary>Weights are nonnegative.</summary>
    Nonnegative = 64,
}

/// <summary>The natural-order relationship between two semiring values.</summary>
public enum SemiringOrder
{
    /// <summary>The left value is better than the right value.</summary>
    Better = -1,
    /// <summary>The values are equivalent in the natural order.</summary>
    Equal = 0,
    /// <summary>The left value is worse than the right value.</summary>
    Worse = 1,
    /// <summary>Neither value precedes the other.</summary>
    Incomparable = 2,
}

/// <summary>Domain identity, concurrency promises, and declared laws for a semiring.</summary>
public readonly record struct SemiringProviderOptions(
    InteropDomainId DomainId,
    SemiringProviderFlags Flags = 0,
    SemiringProperties Properties = 0,
    nuint? ClosureBound = null);

/// <summary>A host-defined semiring over immutable values of type <typeparamref name="T"/>.</summary>
public interface ISemiringProvider<T> where T : notnull
{
    /// <summary>Additive identity.</summary>
    T Zero { get; }
    /// <summary>Multiplicative identity.</summary>
    T One { get; }
    /// <summary>Create an independently owned logical copy.</summary>
    T CloneValue(T value);
    /// <summary>Add two values.</summary>
    T Plus(T left, T right);
    /// <summary>Multiply two values.</summary>
    T Times(T left, T right);
    /// <summary>Test exact semantic equality.</summary>
    bool EqualsValue(T left, T right);
    /// <summary>Test equality within a nonnegative tolerance.</summary>
    bool ApproximatelyEquals(T left, T right, double epsilon);
    /// <summary>Compare values in the semiring's natural order.</summary>
    SemiringOrder CompareNatural(T left, T right);
    /// <summary>Return a canonical, deterministic encoding.</summary>
    ReadOnlyMemory<byte> GetStableBytes(T value);
    /// <summary>Return a concise diagnostic representation.</summary>
    string GetDiagnostic(T value);
}

/// <summary>Optional quotient operations for a semiring.</summary>
public interface IDivisibleSemiringProvider<T> : ISemiringProvider<T> where T : notnull
{
    /// <summary>Try to compute a right quotient.</summary>
    bool TryDivide(T dividend, T divisor, out T result);
    /// <summary>Try to compute a left quotient.</summary>
    bool TryLeftDivide(T value, T divisor, out T result);
}

/// <summary>Optional Kleene closure for a semiring.</summary>
public interface IStarSemiringProvider<T> : ISemiringProvider<T> where T : notnull
{
    /// <summary>Try to compute closure; false denotes divergence.</summary>
    bool TryStar(T value, out T result);
}

/// <summary>Optional numeric projections for specialized algorithms.</summary>
public interface INumericSemiringProvider<T> : ISemiringProvider<T> where T : notnull
{
    /// <summary>Project a value to a scalar diagnostic.</summary>
    double GetNumericalValue(T value);
    /// <summary>Quantize a value with the supplied nonnegative tolerance.</summary>
    long Quantize(T value, double epsilon);
    /// <summary>Convert a value to probability space.</summary>
    double ToProbability(T value);
}

public static partial class HostProviders
{
    /// <summary>
    /// Export a managed semiring operation context. Unmanaged, reference-free values no larger
    /// than eight bytes are encoded inline; other values use provider-scoped owned tokens.
    /// </summary>
    public static HostedResource CreateSemiring<T>(
        ISemiringProvider<T> provider,
        SemiringProviderOptions options)
        where T : notnull
    {
        ArgumentNullException.ThrowIfNull(provider);
        SemiringContext<T> context = SemiringContext<T>.Create(provider, options);
        return new(context);
    }
}

internal abstract unsafe class SemiringContextBase : ProviderContext
{
    private readonly NativeInterfaceId domainId;
    private readonly bool hasDivision;
    private readonly bool hasStar;
    private readonly bool hasNumeric;
    private readonly nuint? closureBound;
    private NativeSemiringVTable* semiring;
    private NativeSemiringDivisionVTable* division;
    private NativeSemiringStarVTable* star;
    private NativeSemiringNumericVTable* numeric;
    private NativeSemiringPropertiesVTable* properties;

    protected SemiringContextBase(
        SemiringProviderOptions options,
        bool hasDivision,
        bool hasStar,
        bool hasNumeric)
    {
        const SemiringProviderFlags knownFlags =
            SemiringProviderFlags.ThreadBound | SemiringProviderFlags.ParallelReentrant;
        const SemiringProperties knownProperties = SemiringProperties.Hashable |
            SemiringProperties.IdempotentPlus | SemiringProperties.KClosed |
            SemiringProperties.ZeroSumFree | SemiringProperties.CommutativeTimes |
            SemiringProperties.TotallyOrdered | SemiringProperties.Nonnegative;
        if ((options.Flags & ~knownFlags) != 0 ||
            (options.Flags & knownFlags) == knownFlags ||
            (options.Properties & ~knownProperties) != 0)
        {
            throw new ArgumentException("semiring options contain invalid flags or properties", nameof(options));
        }
        this.hasDivision = hasDivision;
        this.hasStar = hasStar;
        this.hasNumeric = hasNumeric;
        closureBound = options.ClosureBound;
        domainId = NativeAbi.ToNative(options.DomainId);
        semiring = null;
        division = null;
        star = null;
        numeric = null;
        properties = null;
        try
        {
            semiring = AllocateVTable(new NativeSemiringVTable
            {
                StructSize = (nuint)sizeof(NativeSemiringVTable),
                InterfaceVersion = NativeAbi.InterfaceVersion,
                Reserved = 0,
                Flags = (ulong)options.Flags | NativeAbi.SemiringStableBytes | NativeAbi.SemiringBatch,
                DomainId = domainId,
                Zero = &SemiringExports.Zero,
                One = &SemiringExports.One,
                CloneValue = &SemiringExports.CloneValue,
                ReleaseValues = &SemiringExports.ReleaseValues,
                Plus = &SemiringExports.Plus,
                Times = &SemiringExports.Times,
                Equal = &SemiringExports.Equal,
                ApproxEqual = &SemiringExports.ApproxEqual,
                NaturalOrder = &SemiringExports.NaturalOrder,
                StableBytes = &SemiringExports.StableBytes,
                Diagnostic = &SemiringExports.Diagnostic,
                PlusMany = &SemiringExports.PlusMany,
                TimesMany = &SemiringExports.TimesMany,
            });
            division = AllocateVTable(new NativeSemiringDivisionVTable
            {
                StructSize = (nuint)sizeof(NativeSemiringDivisionVTable),
                InterfaceVersion = NativeAbi.InterfaceVersion,
                Reserved = 0,
                Divide = &SemiringExports.Divide,
                LeftDivide = &SemiringExports.LeftDivide,
            });
            star = AllocateVTable(new NativeSemiringStarVTable
            {
                StructSize = (nuint)sizeof(NativeSemiringStarVTable),
                InterfaceVersion = NativeAbi.InterfaceVersion,
                Reserved = 0,
                Star = &SemiringExports.Star,
            });
            numeric = AllocateVTable(new NativeSemiringNumericVTable
            {
                StructSize = (nuint)sizeof(NativeSemiringNumericVTable),
                InterfaceVersion = NativeAbi.InterfaceVersion,
                Reserved = 0,
                NumericalValue = &SemiringExports.NumericalValue,
                Quantize = &SemiringExports.Quantize,
                ToProbability = &SemiringExports.ToProbability,
            });
            properties = AllocateVTable(new NativeSemiringPropertiesVTable
            {
                StructSize = (nuint)sizeof(NativeSemiringPropertiesVTable),
                InterfaceVersion = NativeAbi.InterfaceVersion,
                Reserved = 0,
                Properties = options.Properties,
                ClosureBound = &SemiringExports.ClosureBound,
            });
        }
        catch
        {
            DisposeNative();
            throw;
        }
    }

    internal override DictionaryInteropStatus Query(byte* interfaceId, uint minimumVersion, nint* output)
    {
        if (minimumVersion > NativeAbi.InterfaceVersion) return DictionaryInteropStatus.Unsupported;
        if (NativeAbi.IdEquals(interfaceId, NativeAbi.SemiringId)) *output = (nint)semiring;
        else if (hasDivision && NativeAbi.IdEquals(interfaceId, NativeAbi.SemiringDivisionId)) *output = (nint)division;
        else if (hasStar && NativeAbi.IdEquals(interfaceId, NativeAbi.SemiringStarId)) *output = (nint)star;
        else if (hasNumeric && NativeAbi.IdEquals(interfaceId, NativeAbi.SemiringNumericId)) *output = (nint)numeric;
        else if (NativeAbi.IdEquals(interfaceId, NativeAbi.SemiringPropertiesId)) *output = (nint)properties;
        else return DictionaryInteropStatus.Unsupported;
        return DictionaryInteropStatus.Ok;
    }

    internal nuint? ClosureBoundValue => closureBound;

    internal abstract DictionaryInteropStatus Zero(NativeSemiringValue* output);
    internal abstract DictionaryInteropStatus One(NativeSemiringValue* output);
    internal abstract DictionaryInteropStatus Clone(NativeSemiringValue* value, NativeSemiringValue* output);
    internal abstract DictionaryInteropStatus ReleaseValues(NativeSemiringValue* values, nuint count);
    internal abstract DictionaryInteropStatus Binary(NativeSemiringValue* left, NativeSemiringValue* right, NativeSemiringValue* output, bool plus);
    internal abstract DictionaryInteropStatus Equal(NativeSemiringValue* left, NativeSemiringValue* right, byte* output, double? epsilon);
    internal abstract DictionaryInteropStatus NaturalOrder(NativeSemiringValue* left, NativeSemiringValue* right, int* output);
    internal abstract DictionaryInteropStatus Bytes(NativeSemiringValue* value, byte* output, nuint capacity, nuint* written, nuint* required, bool diagnostic);
    internal abstract DictionaryInteropStatus Fold(NativeSemiringValue* values, nuint count, NativeSemiringValue* output, bool plus);
    internal abstract DictionaryInteropStatus Divide(NativeSemiringValue* left, NativeSemiringValue* right, NativeSemiringValue* output, bool leftDivide);
    internal abstract DictionaryInteropStatus Star(NativeSemiringValue* value, NativeSemiringValue* output);
    internal abstract DictionaryInteropStatus Numeric(NativeSemiringValue* value, double epsilon, void* output, int operation);

    protected override void DisposeNative()
    {
        FreeVTable(semiring);
        FreeVTable(division);
        FreeVTable(star);
        FreeVTable(numeric);
        FreeVTable(properties);
        semiring = null;
        division = null;
        star = null;
        numeric = null;
        properties = null;
    }
}

internal sealed unsafe class SemiringContext<T> : SemiringContextBase where T : notnull
{
    private static long nextCookie;
    private readonly ISemiringProvider<T> provider;
    private readonly ulong cookie;
    private readonly bool inlineValues;

    private SemiringContext(ISemiringProvider<T> provider, SemiringProviderOptions options)
        : base(
            options,
            provider is IDivisibleSemiringProvider<T>,
            provider is IStarSemiringProvider<T>,
            provider is INumericSemiringProvider<T>)
    {
        this.provider = provider;
        cookie = unchecked((ulong)Interlocked.Increment(ref nextCookie) * 0x9e3779b97f4a7c15UL) | 1;
        inlineValues = !RuntimeHelpers.IsReferenceOrContainsReferences<T>() && Unsafe.SizeOf<T>() <= sizeof(ulong);
    }

    internal static SemiringContext<T> Create(ISemiringProvider<T> provider, SemiringProviderOptions options)
    {
        var context = new SemiringContext<T>(provider, options);
        context.Export();
        return context;
    }

    internal override DictionaryInteropStatus Zero(NativeSemiringValue* output) => EncodeProviderValue(output, provider.Zero);
    internal override DictionaryInteropStatus One(NativeSemiringValue* output) => EncodeProviderValue(output, provider.One);

    internal override DictionaryInteropStatus Clone(NativeSemiringValue* value, NativeSemiringValue* output)
    {
        if (value is null || output is null) return DictionaryInteropStatus.NullPointer;
        if (!TryDecode(value, out T decoded)) return DictionaryInteropStatus.InvalidArgument;
        return EncodeProviderValue(output, provider.CloneValue(decoded));
    }

    internal override DictionaryInteropStatus ReleaseValues(NativeSemiringValue* values, nuint count)
    {
        if (count != 0 && values is null) return DictionaryInteropStatus.NullPointer;
        for (nuint index = 0; index < count; index++)
        {
            if (!IsValid(&values[index])) return DictionaryInteropStatus.InvalidArgument;
            if (!inlineValues)
            {
                for (nuint prior = 0; prior < index; prior++)
                {
                    if (values[index].Word0 == values[prior].Word0) return DictionaryInteropStatus.InvalidArgument;
                }
            }
        }
        for (nuint index = 0; index < count; index++)
        {
            if (!inlineValues)
            {
                GCHandle.FromIntPtr(unchecked((nint)values[index].Word0)).Free();
            }
            values[index] = default;
        }
        return DictionaryInteropStatus.Ok;
    }

    internal override DictionaryInteropStatus Binary(
        NativeSemiringValue* left,
        NativeSemiringValue* right,
        NativeSemiringValue* output,
        bool plus)
    {
        if (left is null || right is null || output is null) return DictionaryInteropStatus.NullPointer;
        if (!TryDecode(left, out T lhs) || !TryDecode(right, out T rhs)) return DictionaryInteropStatus.InvalidArgument;
        return EncodeProviderValue(output, plus ? provider.Plus(lhs, rhs) : provider.Times(lhs, rhs));
    }

    internal override DictionaryInteropStatus Equal(
        NativeSemiringValue* left,
        NativeSemiringValue* right,
        byte* output,
        double? epsilon)
    {
        if (left is null || right is null || output is null) return DictionaryInteropStatus.NullPointer;
        if (!TryDecode(left, out T lhs) || !TryDecode(right, out T rhs)) return DictionaryInteropStatus.InvalidArgument;
        bool equal = epsilon.HasValue
            ? provider.ApproximatelyEquals(lhs, rhs, epsilon.Value)
            : provider.EqualsValue(lhs, rhs);
        *output = equal ? (byte)1 : (byte)0;
        return DictionaryInteropStatus.Ok;
    }

    internal override DictionaryInteropStatus NaturalOrder(
        NativeSemiringValue* left,
        NativeSemiringValue* right,
        int* output)
    {
        if (left is null || right is null || output is null) return DictionaryInteropStatus.NullPointer;
        if (!TryDecode(left, out T lhs) || !TryDecode(right, out T rhs)) return DictionaryInteropStatus.InvalidArgument;
        SemiringOrder order = provider.CompareNatural(lhs, rhs);
        if (order is < SemiringOrder.Better or > SemiringOrder.Incomparable)
        {
            return DictionaryInteropStatus.ProviderError;
        }
        *output = (int)order;
        return DictionaryInteropStatus.Ok;
    }

    internal override DictionaryInteropStatus Bytes(
        NativeSemiringValue* value,
        byte* output,
        nuint capacity,
        nuint* written,
        nuint* required,
        bool diagnostic)
    {
        if (value is null) return DictionaryInteropStatus.NullPointer;
        if (!TryDecode(value, out T decoded)) return DictionaryInteropStatus.InvalidArgument;
        if (diagnostic)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(provider.GetDiagnostic(decoded) ?? string.Empty);
            return ProviderOutput.WriteBytes(bytes, output, capacity, written, required);
        }
        return ProviderOutput.WriteBytes(provider.GetStableBytes(decoded).Span, output, capacity, written, required);
    }

    internal override DictionaryInteropStatus Fold(
        NativeSemiringValue* values,
        nuint count,
        NativeSemiringValue* output,
        bool plus)
    {
        if (output is null || (count != 0 && values is null)) return DictionaryInteropStatus.NullPointer;
        for (nuint index = 0; index < count; index++)
        {
            if (!IsValid(&values[index])) return DictionaryInteropStatus.InvalidArgument;
        }
        T accumulator;
        if (count == 0) accumulator = plus ? provider.Zero : provider.One;
        else
        {
            _ = TryDecode(&values[0], out accumulator!);
            for (nuint index = 1; index < count; index++)
            {
                _ = TryDecode(&values[index], out T next);
                accumulator = plus ? provider.Plus(accumulator, next) : provider.Times(accumulator, next);
            }
        }
        return EncodeProviderValue(output, accumulator);
    }

    internal override DictionaryInteropStatus Divide(
        NativeSemiringValue* left,
        NativeSemiringValue* right,
        NativeSemiringValue* output,
        bool leftDivide)
    {
        if (left is null || right is null || output is null) return DictionaryInteropStatus.NullPointer;
        if (provider is not IDivisibleSemiringProvider<T> divisible) return DictionaryInteropStatus.Unsupported;
        if (!TryDecode(left, out T lhs) || !TryDecode(right, out T rhs)) return DictionaryInteropStatus.InvalidArgument;
        bool defined = leftDivide
            ? divisible.TryLeftDivide(lhs, rhs, out T result)
            : divisible.TryDivide(lhs, rhs, out result);
        return defined ? EncodeProviderValue(output, result) : DictionaryInteropStatus.End;
    }

    internal override DictionaryInteropStatus Star(NativeSemiringValue* value, NativeSemiringValue* output)
    {
        if (value is null || output is null) return DictionaryInteropStatus.NullPointer;
        if (provider is not IStarSemiringProvider<T> closure) return DictionaryInteropStatus.Unsupported;
        if (!TryDecode(value, out T decoded)) return DictionaryInteropStatus.InvalidArgument;
        return closure.TryStar(decoded, out T result)
            ? EncodeProviderValue(output, result)
            : DictionaryInteropStatus.End;
    }

    internal override DictionaryInteropStatus Numeric(
        NativeSemiringValue* value,
        double epsilon,
        void* output,
        int operation)
    {
        if (value is null || output is null) return DictionaryInteropStatus.NullPointer;
        if (provider is not INumericSemiringProvider<T> numeric) return DictionaryInteropStatus.Unsupported;
        if (!TryDecode(value, out T decoded)) return DictionaryInteropStatus.InvalidArgument;
        switch (operation)
        {
            case 0:
                *(double*)output = numeric.GetNumericalValue(decoded);
                break;
            case 1:
                *(long*)output = numeric.Quantize(decoded, epsilon);
                break;
            case 2:
                *(double*)output = numeric.ToProbability(decoded);
                break;
            default:
                return DictionaryInteropStatus.ProviderError;
        }
        return DictionaryInteropStatus.Ok;
    }

    private DictionaryInteropStatus EncodeProviderValue(NativeSemiringValue* output, T value)
    {
        if (output is null) return DictionaryInteropStatus.NullPointer;
        if (value is null) return DictionaryInteropStatus.ProviderError;
        if (inlineValues)
        {
            ulong bits = 0;
            Unsafe.WriteUnaligned(ref Unsafe.As<ulong, byte>(ref bits), value);
            *output = new NativeSemiringValue { Word0 = bits, Word1 = cookie };
            return DictionaryInteropStatus.Ok;
        }
        GCHandle handle = GCHandle.Alloc(new SemiringToken<T>(this, value), GCHandleType.Normal);
        *output = new NativeSemiringValue
        {
            Word0 = unchecked((ulong)GCHandle.ToIntPtr(handle)),
            Word1 = cookie,
        };
        return DictionaryInteropStatus.Ok;
    }

    private bool IsValid(NativeSemiringValue* value)
    {
        if (value is null || value->Word1 != cookie) return false;
        if (inlineValues) return true;
        if (value->Word0 == 0 || (UIntPtr.Size == 4 && value->Word0 > uint.MaxValue)) return false;
        try
        {
            object? target = GCHandle.FromIntPtr(unchecked((nint)value->Word0)).Target;
            return target is SemiringToken<T> token && ReferenceEquals(token.Owner, this);
        }
        catch (InvalidOperationException) { return false; }
    }

    private bool TryDecode(NativeSemiringValue* value, out T result)
    {
        result = default!;
        if (!IsValid(value)) return false;
        if (inlineValues)
        {
            ulong bits = value->Word0;
            result = Unsafe.ReadUnaligned<T>(ref Unsafe.As<ulong, byte>(ref bits));
            return true;
        }
        result = ((SemiringToken<T>)GCHandle.FromIntPtr(unchecked((nint)value->Word0)).Target!).Value;
        return true;
    }
}

internal sealed record SemiringToken<T>(SemiringContext<T> Owner, T Value) where T : notnull;

internal static unsafe class SemiringExports
{
    private static SemiringContextBase Context(nint raw) => (SemiringContextBase)ProviderContext.FromRaw(raw);

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus Zero(nint raw, NativeSemiringValue* output)
    {
        if (raw == 0) return DictionaryInteropStatus.NullPointer;
        try { return Context(raw).Zero(output); }
        catch (Exception exception) { return ProviderOutput.FromException(exception); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus One(nint raw, NativeSemiringValue* output)
    {
        if (raw == 0) return DictionaryInteropStatus.NullPointer;
        try { return Context(raw).One(output); }
        catch (Exception exception) { return ProviderOutput.FromException(exception); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus CloneValue(nint raw, NativeSemiringValue* value, NativeSemiringValue* output)
    {
        if (raw == 0) return DictionaryInteropStatus.NullPointer;
        try { return Context(raw).Clone(value, output); }
        catch (Exception exception) { return ProviderOutput.FromException(exception); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus ReleaseValues(nint raw, NativeSemiringValue* values, nuint count)
    {
        if (raw == 0) return DictionaryInteropStatus.NullPointer;
        try { return Context(raw).ReleaseValues(values, count); }
        catch (Exception exception) { return ProviderOutput.FromException(exception); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus Plus(nint raw, NativeSemiringValue* left, NativeSemiringValue* right, NativeSemiringValue* output)
    {
        if (raw == 0) return DictionaryInteropStatus.NullPointer;
        try { return Context(raw).Binary(left, right, output, true); }
        catch (Exception exception) { return ProviderOutput.FromException(exception); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus Times(nint raw, NativeSemiringValue* left, NativeSemiringValue* right, NativeSemiringValue* output)
    {
        if (raw == 0) return DictionaryInteropStatus.NullPointer;
        try { return Context(raw).Binary(left, right, output, false); }
        catch (Exception exception) { return ProviderOutput.FromException(exception); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus Equal(nint raw, NativeSemiringValue* left, NativeSemiringValue* right, byte* output)
    {
        if (raw == 0) return DictionaryInteropStatus.NullPointer;
        try { return Context(raw).Equal(left, right, output, null); }
        catch (Exception exception) { return ProviderOutput.FromException(exception); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus ApproxEqual(nint raw, NativeSemiringValue* left, NativeSemiringValue* right, double epsilon, byte* output)
    {
        if (raw == 0) return DictionaryInteropStatus.NullPointer;
        try { return Context(raw).Equal(left, right, output, epsilon); }
        catch (Exception exception) { return ProviderOutput.FromException(exception); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus NaturalOrder(nint raw, NativeSemiringValue* left, NativeSemiringValue* right, int* output)
    {
        if (raw == 0) return DictionaryInteropStatus.NullPointer;
        try { return Context(raw).NaturalOrder(left, right, output); }
        catch (Exception exception) { return ProviderOutput.FromException(exception); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus StableBytes(nint raw, NativeSemiringValue* value, byte* output, nuint capacity, nuint* written, nuint* required)
    {
        if (raw == 0) return DictionaryInteropStatus.NullPointer;
        try { return Context(raw).Bytes(value, output, capacity, written, required, false); }
        catch (Exception exception) { return ProviderOutput.FromException(exception); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus Diagnostic(nint raw, NativeSemiringValue* value, byte* output, nuint capacity, nuint* written, nuint* required)
    {
        if (raw == 0) return DictionaryInteropStatus.NullPointer;
        try { return Context(raw).Bytes(value, output, capacity, written, required, true); }
        catch (Exception exception) { return ProviderOutput.FromException(exception); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus PlusMany(nint raw, NativeSemiringValue* values, nuint count, NativeSemiringValue* output)
    {
        if (raw == 0) return DictionaryInteropStatus.NullPointer;
        try { return Context(raw).Fold(values, count, output, true); }
        catch (Exception exception) { return ProviderOutput.FromException(exception); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus TimesMany(nint raw, NativeSemiringValue* values, nuint count, NativeSemiringValue* output)
    {
        if (raw == 0) return DictionaryInteropStatus.NullPointer;
        try { return Context(raw).Fold(values, count, output, false); }
        catch (Exception exception) { return ProviderOutput.FromException(exception); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus Divide(nint raw, NativeSemiringValue* left, NativeSemiringValue* right, NativeSemiringValue* output)
    {
        if (raw == 0) return DictionaryInteropStatus.NullPointer;
        try { return Context(raw).Divide(left, right, output, false); }
        catch (Exception exception) { return ProviderOutput.FromException(exception); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus LeftDivide(nint raw, NativeSemiringValue* left, NativeSemiringValue* right, NativeSemiringValue* output)
    {
        if (raw == 0) return DictionaryInteropStatus.NullPointer;
        try { return Context(raw).Divide(left, right, output, true); }
        catch (Exception exception) { return ProviderOutput.FromException(exception); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus Star(nint raw, NativeSemiringValue* value, NativeSemiringValue* output)
    {
        if (raw == 0) return DictionaryInteropStatus.NullPointer;
        try { return Context(raw).Star(value, output); }
        catch (Exception exception) { return ProviderOutput.FromException(exception); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus NumericalValue(nint raw, NativeSemiringValue* value, double* output)
    {
        if (raw == 0) return DictionaryInteropStatus.NullPointer;
        try { return Context(raw).Numeric(value, 0, output, 0); }
        catch (Exception exception) { return ProviderOutput.FromException(exception); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus Quantize(nint raw, NativeSemiringValue* value, double epsilon, long* output)
    {
        if (raw == 0) return DictionaryInteropStatus.NullPointer;
        try { return Context(raw).Numeric(value, epsilon, output, 1); }
        catch (Exception exception) { return ProviderOutput.FromException(exception); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus ToProbability(nint raw, NativeSemiringValue* value, double* output)
    {
        if (raw == 0) return DictionaryInteropStatus.NullPointer;
        try { return Context(raw).Numeric(value, 0, output, 2); }
        catch (Exception exception) { return ProviderOutput.FromException(exception); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus ClosureBound(nint raw, nuint* output, byte* known)
    {
        if (raw == 0 || output is null || known is null) return DictionaryInteropStatus.NullPointer;
        try
        {
            nuint? bound = Context(raw).ClosureBoundValue;
            *output = bound ?? 0;
            *known = bound.HasValue ? (byte)1 : (byte)0;
            return DictionaryInteropStatus.Ok;
        }
        catch (Exception exception) { return ProviderOutput.FromException(exception); }
    }

}
