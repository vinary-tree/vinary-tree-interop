using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace VinaryTree.Interop;

/// <summary>Portable scalar weight encodings supported by the version-1 WFST ABI.</summary>
public enum ScalarWeightDomain : uint
{
    /// <summary>Tropical costs: minimum is addition and numeric addition is multiplication.</summary>
    TropicalF64 = 1,
    /// <summary>Log-domain probabilities.</summary>
    LogF64 = 2,
    /// <summary>Ordinary probabilities.</summary>
    ProbabilityF64 = 3,
    /// <summary>Arctic scores: maximum is addition.</summary>
    ArcticF64 = 4,
    /// <summary>Signed tropical costs.</summary>
    SignedTropicalF64 = 5,
    /// <summary>Counting weights encoded exactly where representable as <see cref="double"/>.</summary>
    CountF64 = 6,
    /// <summary>Boolean weights encoded as zero or one.</summary>
    BooleanF64 = 7,
}

/// <summary>Concurrency and topology promises made by a scalar-WFST provider.</summary>
[Flags]
public enum ScalarWfstFlags : ulong
{
    /// <summary>Concurrent calls are safe without an external sequential gate.</summary>
    ParallelReentrant = 1,
    /// <summary>The exported revision never changes.</summary>
    Immutable = 2,
    /// <summary>States or arcs may be expanded on demand.</summary>
    Lazy = 4,
    /// <summary>The state graph is acyclic.</summary>
    Acyclic = 8,
}

/// <summary>Domains and capability promises for one immutable scalar WFST.</summary>
public readonly record struct ScalarWfstOptions(
    DictionaryUnitDomain UnitDomain,
    ScalarWeightDomain WeightDomain,
    ScalarWfstFlags Flags)
{
    /// <summary>Unicode-scalar labels and tropical weights on an immutable graph.</summary>
    public static ScalarWfstOptions Default { get; } = new(
        DictionaryUnitDomain.UnicodeScalar,
        ScalarWeightDomain.TropicalF64,
        ScalarWfstFlags.Immutable);
}

/// <summary>Validity, finality, and final weight for one provider-scoped state.</summary>
public readonly record struct ScalarWfstStateInfo(bool IsValid, bool IsFinal, double FinalWeight);

/// <summary>One weighted transition; a null label denotes epsilon.</summary>
public readonly record struct ScalarWfstArc(
    ulong? InputLabel,
    ulong? OutputLabel,
    ulong TargetState,
    double Weight);

/// <summary>
/// A managed immutable scalar WFST that can be consumed by any ABI-compatible Vinary Tree package.
/// Returned arc memory must remain immutable for the provider resource's lifetime.
/// </summary>
public interface IScalarWfstProvider
{
    /// <summary>The provider-scoped start state.</summary>
    ulong StartState { get; }

    /// <summary>The exact state count, or null when expansion is lazy or the count is unknown.</summary>
    nuint? StateCount { get; }

    /// <summary>Inspect an arbitrary state identifier without throwing for an unknown state.</summary>
    ScalarWfstStateInfo GetStateInfo(ulong state);

    /// <summary>Borrow the immutable outgoing arcs for a valid state.</summary>
    ReadOnlyMemory<ScalarWfstArc> GetStateArcs(ulong state);
}

/// <summary>Factories that export managed providers through the stable resource ABI.</summary>
public static partial class HostProviders
{
    /// <summary>Export a snapshot-consistent managed scalar WFST.</summary>
    public static HostedResource CreateScalarWfst(
        IScalarWfstProvider provider,
        ScalarWfstOptions? options = null)
    {
        ArgumentNullException.ThrowIfNull(provider);
        var context = new WfstContext(provider, options ?? ScalarWfstOptions.Default);
        context.Export();
        return new(context);
    }
}

internal sealed unsafe class WfstContext : ProviderContext
{
    private readonly IScalarWfstProvider provider;
    private readonly ScalarWfstOptions options;
    private NativeWfstVTable* table;

    internal WfstContext(IScalarWfstProvider provider, ScalarWfstOptions options)
    {
        const ScalarWfstFlags known = ScalarWfstFlags.ParallelReentrant | ScalarWfstFlags.Immutable |
            ScalarWfstFlags.Lazy | ScalarWfstFlags.Acyclic;
        if (options.UnitDomain is not (DictionaryUnitDomain.Byte or DictionaryUnitDomain.UnicodeScalar or DictionaryUnitDomain.U64) ||
            options.WeightDomain is < ScalarWeightDomain.TropicalF64 or > ScalarWeightDomain.BooleanF64 ||
            (options.Flags & ~known) != 0)
        {
            throw new ArgumentException("scalar-WFST options contain an invalid domain or flag", nameof(options));
        }
        this.provider = provider;
        this.options = options with { Flags = options.Flags | ScalarWfstFlags.Immutable };
        table = AllocateVTable(new NativeWfstVTable
        {
            StructSize = (nuint)sizeof(NativeWfstVTable),
            InterfaceVersion = NativeAbi.InterfaceVersion,
            UnitDomain = options.UnitDomain,
            WeightDomain = options.WeightDomain,
            Reserved = 0,
            Flags = (ulong)this.options.Flags,
            Snapshot = &WfstExports.Snapshot,
            Start = &WfstExports.Start,
            NumStates = &WfstExports.NumStates,
            StateInfo = &WfstExports.StateInfo,
            StateArcs = &WfstExports.StateArcs,
        });
    }

    internal override DictionaryInteropStatus Query(byte* interfaceId, uint minimumVersion, nint* output)
    {
        if (!NativeAbi.IdEquals(interfaceId, NativeAbi.WfstId) || minimumVersion > NativeAbi.InterfaceVersion)
        {
            return DictionaryInteropStatus.Unsupported;
        }
        *output = (nint)table;
        return DictionaryInteropStatus.Ok;
    }

    internal IScalarWfstProvider Provider => provider;
    internal ScalarWfstOptions Options => options;

    protected override void DisposeNative()
    {
        FreeVTable(table);
        table = null;
    }
}

internal static unsafe class WfstExports
{
    private static WfstContext Context(nint raw) => (WfstContext)ProviderContext.FromRaw(raw);

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus Snapshot(nint raw, NativeResource* output)
    {
        if (raw == 0 || output is null) return DictionaryInteropStatus.NullPointer;
        try
        {
            WfstContext context = Context(raw);
            context.Retain();
            *output = context.Resource;
            return DictionaryInteropStatus.Ok;
        }
        catch (Exception exception) { return ProviderOutput.FromException(exception); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus Start(nint raw, ulong* output)
    {
        if (raw == 0 || output is null) return DictionaryInteropStatus.NullPointer;
        try
        {
            ulong value = Context(raw).Provider.StartState;
            *output = value;
            return DictionaryInteropStatus.Ok;
        }
        catch (Exception exception) { return ProviderOutput.FromException(exception); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus NumStates(nint raw, nuint* count, byte* known)
    {
        if (raw == 0 || count is null || known is null) return DictionaryInteropStatus.NullPointer;
        try
        {
            nuint? value = Context(raw).Provider.StateCount;
            *count = value ?? 0;
            *known = value.HasValue ? (byte)1 : (byte)0;
            return DictionaryInteropStatus.Ok;
        }
        catch (Exception exception) { return ProviderOutput.FromException(exception); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus StateInfo(
        nint raw,
        ulong state,
        byte* valid,
        byte* final,
        double* finalWeight)
    {
        if (raw == 0 || valid is null || final is null || finalWeight is null)
        {
            return DictionaryInteropStatus.NullPointer;
        }
        try
        {
            ScalarWfstStateInfo value = Context(raw).Provider.GetStateInfo(state);
            if ((!value.IsValid && value.IsFinal) || double.IsNaN(value.FinalWeight))
            {
                return DictionaryInteropStatus.ProviderError;
            }
            *valid = value.IsValid ? (byte)1 : (byte)0;
            *final = value.IsFinal ? (byte)1 : (byte)0;
            *finalWeight = value.FinalWeight;
            return DictionaryInteropStatus.Ok;
        }
        catch (Exception exception) { return ProviderOutput.FromException(exception); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    internal static DictionaryInteropStatus StateArcs(
        nint raw,
        ulong state,
        nuint start,
        NativeWfstArc* output,
        nuint capacity,
        nuint* written,
        nuint* total)
    {
        if (raw == 0 || written is null || total is null || (capacity != 0 && output is null))
        {
            return DictionaryInteropStatus.NullPointer;
        }
        try
        {
            WfstContext context = Context(raw);
            if (!context.Provider.GetStateInfo(state).IsValid) return DictionaryInteropStatus.InvalidArgument;
            ReadOnlySpan<ScalarWfstArc> arcs = context.Provider.GetStateArcs(state).Span;
            nuint arcCount = (nuint)arcs.Length;
            nuint count = start >= arcCount ? 0 : Math.Min(capacity, arcCount - start);
            int first = checked((int)Math.Min(start, arcCount));
            int copied = checked((int)count);
            for (int index = 0; index < copied; index++)
            {
                ScalarWfstArc arc = arcs[first + index];
                if ((arc.InputLabel.HasValue && !ValidLabel(context.Options.UnitDomain, arc.InputLabel.Value)) ||
                    (arc.OutputLabel.HasValue && !ValidLabel(context.Options.UnitDomain, arc.OutputLabel.Value)) ||
                    double.IsNaN(arc.Weight))
                {
                    return DictionaryInteropStatus.ProviderError;
                }
            }
            for (int index = 0; index < copied; index++)
            {
                ScalarWfstArc arc = arcs[first + index];
                output[index] = new NativeWfstArc
                {
                    InputLabel = arc.InputLabel ?? 0,
                    OutputLabel = arc.OutputLabel ?? 0,
                    TargetState = arc.TargetState,
                    Weight = arc.Weight,
                    HasInput = arc.InputLabel.HasValue ? (byte)1 : (byte)0,
                    HasOutput = arc.OutputLabel.HasValue ? (byte)1 : (byte)0,
                };
            }
            *total = arcCount;
            *written = count;
            return DictionaryInteropStatus.Ok;
        }
        catch (Exception exception) { return ProviderOutput.FromException(exception); }
    }

    private static bool ValidLabel(DictionaryUnitDomain domain, ulong label) => domain switch
    {
        DictionaryUnitDomain.Byte => label <= byte.MaxValue,
        DictionaryUnitDomain.UnicodeScalar => label <= 0x10ffff && label is not (>= 0xd800 and <= 0xdfff),
        DictionaryUnitDomain.U64 => true,
        _ => false,
    };
}
