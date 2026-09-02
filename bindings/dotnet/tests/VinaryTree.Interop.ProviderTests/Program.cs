using System.Buffers.Binary;
using VinaryTree.Interop;

internal static unsafe class Program
{
    private static readonly InteropDomainId LatticeDomain = InteropDomainId.FromAscii("tests.lattice.v1");
    private static readonly InteropDomainId SemiringDomain = InteropDomainId.FromAscii("tests.semiringv1");

    private static int Main()
    {
        WfstRoundTrip();
        WfstExceptionsAreContained();
        LatticeRoundTrip();
        InlineSemiringRoundTrip();
        InlineSemiringHotPathDoesNotAllocate();
        HeapSemiringTokensAreOwned();
        Console.WriteLine("managed provider ABI tests passed");
        return 0;
    }

    private static void WfstRoundTrip()
    {
        using HostedResource resource = HostProviders.CreateScalarWfst(
            new TestWfst(),
            ScalarWfstOptions.Default with { Flags = ScalarWfstFlags.Acyclic });
        resource.WithResource(raw =>
        {
            NativeWfstVTable* table = Query<NativeWfstVTable>(raw, NativeAbi.WfstId);
            Assert((table->Flags & NativeAbi.WfstImmutable) != 0, "WFST did not force immutable flag");
            ulong start = ulong.MaxValue;
            Assert(table->Start(raw->Context, &start) == DictionaryInteropStatus.Ok && start == 0, "wrong WFST start state");
            nuint count = 0;
            byte known = 0;
            Assert(table->NumStates(raw->Context, &count, &known) == DictionaryInteropStatus.Ok && known == 1 && count == 2, "wrong WFST state count");
            NativeWfstArc arc = default;
            nuint written = 0;
            nuint total = 0;
            Assert(table->StateArcs(raw->Context, 0, 0, &arc, 1, &written, &total) == DictionaryInteropStatus.Ok, "WFST arc page failed");
            Assert(written == 1 && total == 1 && arc.InputLabel == 'a' && arc.TargetState == 1, "wrong WFST arc");
            NativeResource snapshot = default;
            Assert(table->Snapshot(raw->Context, &snapshot) == DictionaryInteropStatus.Ok, "WFST snapshot failed");
            ((NativeResourceVTable*)snapshot.VTable)->Release(snapshot.Context);
            return 0;
        });
    }

    private static void WfstExceptionsAreContained()
    {
        using HostedResource resource = HostProviders.CreateScalarWfst(new ThrowingWfst());
        resource.WithResource(raw =>
        {
            NativeWfstVTable* table = Query<NativeWfstVTable>(raw, NativeAbi.WfstId);
            ulong output = 0xdeadbeef;
            Assert(table->Start(raw->Context, &output) == DictionaryInteropStatus.ProviderError, "managed exception crossed the WFST ABI");
            Assert(output == 0xdeadbeef, "failed WFST callback modified output");
            return 0;
        });
    }

    private static void LatticeRoundTrip()
    {
        using HostedResource left = HostProviders.CreateLatticeValue(new MaxLattice(4), new(LatticeDomain));
        using HostedResource right = HostProviders.CreateLatticeValue(new MaxLattice(9), new(LatticeDomain));
        left.WithResource(leftRaw => right.WithResource(rightRaw =>
        {
            NativeLatticeVTable* table = Query<NativeLatticeVTable>(leftRaw, NativeAbi.LatticeId);
            NativeResource joined = default;
            Assert(table->Join(leftRaw->Context, rightRaw, &joined) == DictionaryInteropStatus.Ok, "lattice join failed");
            NativeLatticeVTable* joinedTable = Query<NativeLatticeVTable>(&joined, NativeAbi.LatticeId);
            Span<byte> stable = stackalloc byte[4];
            nuint written = 0;
            nuint required = 0;
            fixed (byte* output = stable)
            {
                Assert(joinedTable->StableBytes(joined.Context, output, 4, &written, &required) == DictionaryInteropStatus.Ok, "lattice stable bytes failed");
            }
            Assert(written == 4 && required == 4 && BinaryPrimitives.ReadInt32LittleEndian(stable) == 9, "wrong lattice join result");
            ((NativeResourceVTable*)joined.VTable)->Release(joined.Context);
            return 0;
        }));
    }

    private static void InlineSemiringRoundTrip()
    {
        using HostedResource resource = HostProviders.CreateSemiring(
            new TropicalSemiring(),
            new(SemiringDomain, Properties: SemiringProperties.IdempotentPlus | SemiringProperties.TotallyOrdered, ClosureBound: 7));
        resource.WithResource(raw =>
        {
            NativeSemiringVTable* table = Query<NativeSemiringVTable>(raw, NativeAbi.SemiringId);
            NativeSemiringValue zero = default;
            NativeSemiringValue one = default;
            NativeSemiringValue sum = default;
            Assert(table->Zero(raw->Context, &zero) == DictionaryInteropStatus.Ok, "semiring zero failed");
            Assert(table->One(raw->Context, &one) == DictionaryInteropStatus.Ok, "semiring one failed");
            Assert(table->Plus(raw->Context, &zero, &one, &sum) == DictionaryInteropStatus.Ok, "semiring plus failed");
            Assert(BitConverter.UInt64BitsToDouble(sum.Word0) == 0, "wrong inline semiring result");
            NativeSemiringValue* values = stackalloc NativeSemiringValue[3] { zero, one, sum };
            Assert(table->ReleaseValues(raw->Context, values, 3) == DictionaryInteropStatus.Ok, "inline token release failed");
            Assert(values[0].Word1 == 0 && values[2].Word1 == 0, "released inline tokens were not invalidated");
            _ = Query<NativeSemiringDivisionVTable>(raw, NativeAbi.SemiringDivisionId);
            _ = Query<NativeSemiringStarVTable>(raw, NativeAbi.SemiringStarId);
            _ = Query<NativeSemiringNumericVTable>(raw, NativeAbi.SemiringNumericId);
            NativeSemiringPropertiesVTable* properties = Query<NativeSemiringPropertiesVTable>(raw, NativeAbi.SemiringPropertiesId);
            nuint bound = 0;
            byte known = 0;
            Assert(properties->ClosureBound(raw->Context, &bound, &known) == DictionaryInteropStatus.Ok && known == 1 && bound == 7, "wrong semiring properties");
            return 0;
        });
    }

    private static void HeapSemiringTokensAreOwned()
    {
        using HostedResource resource = HostProviders.CreateSemiring(new StringSemiring(), new(SemiringDomain));
        resource.WithResource(raw =>
        {
            NativeSemiringVTable* table = Query<NativeSemiringVTable>(raw, NativeAbi.SemiringId);
            NativeSemiringValue value = default;
            Assert(table->One(raw->Context, &value) == DictionaryInteropStatus.Ok && value.Word0 != 0, "heap token was not created");
            NativeSemiringValue duplicate = value;
            NativeSemiringValue* aliases = stackalloc NativeSemiringValue[2] { value, duplicate };
            Assert(table->ReleaseValues(raw->Context, aliases, 2) == DictionaryInteropStatus.InvalidArgument, "duplicate heap token was accepted");
            Assert(aliases[0].Word0 == value.Word0, "failed release consumed a heap token");
            Assert(table->ReleaseValues(raw->Context, aliases, 1) == DictionaryInteropStatus.Ok && aliases[0].Word0 == 0, "heap token release failed");
            return 0;
        });
    }

    private static void InlineSemiringHotPathDoesNotAllocate()
    {
        using HostedResource resource = HostProviders.CreateSemiring(new TropicalSemiring(), new(SemiringDomain));
        resource.WithResource(raw =>
        {
            NativeSemiringVTable* table = Query<NativeSemiringVTable>(raw, NativeAbi.SemiringId);
            NativeSemiringValue left = default;
            NativeSemiringValue right = default;
            NativeSemiringValue output = default;
            Assert(table->One(raw->Context, &left) == DictionaryInteropStatus.Ok, "semiring warmup value failed");
            Assert(table->One(raw->Context, &right) == DictionaryInteropStatus.Ok, "semiring warmup value failed");
            for (int index = 0; index < 32; index++)
            {
                Assert(table->Times(raw->Context, &left, &right, &output) == DictionaryInteropStatus.Ok, "semiring warmup failed");
                Assert(table->ReleaseValues(raw->Context, &output, 1) == DictionaryInteropStatus.Ok, "semiring warmup release failed");
            }
            long before = GC.GetAllocatedBytesForCurrentThread();
            for (int index = 0; index < 10_000; index++)
            {
                Assert(table->Times(raw->Context, &left, &right, &output) == DictionaryInteropStatus.Ok, "semiring hot path failed");
                Assert(table->ReleaseValues(raw->Context, &output, 1) == DictionaryInteropStatus.Ok, "semiring hot-path release failed");
            }
            long allocated = GC.GetAllocatedBytesForCurrentThread() - before;
            Assert(allocated == 0, $"inline semiring hot path allocated {allocated} bytes");
            NativeSemiringValue* inputs = stackalloc NativeSemiringValue[2] { left, right };
            Assert(table->ReleaseValues(raw->Context, inputs, 2) == DictionaryInteropStatus.Ok, "semiring input release failed");
            return 0;
        });
    }

    private static T* Query<T>(NativeResource* resource, ReadOnlySpan<byte> id) where T : unmanaged
    {
        NativeResourceVTable* baseTable = (NativeResourceVTable*)resource->VTable;
        Span<byte> identifier = stackalloc byte[16];
        id.CopyTo(identifier);
        nint result = 0;
        fixed (byte* rawId = identifier)
        {
            Assert(baseTable->QueryInterface(resource->Context, rawId, 1, &result) == DictionaryInteropStatus.Ok, $"query for {typeof(T).Name} failed");
        }
        Assert(result != 0, $"query for {typeof(T).Name} returned null");
        return (T*)result;
    }

    private static void Assert(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }

    private sealed class TestWfst : IScalarWfstProvider
    {
        private static readonly ScalarWfstArc[] StartArcs = [new('a', 'a', 1, 2)];
        public ulong StartState => 0;
        public nuint? StateCount => 2;
        public ScalarWfstStateInfo GetStateInfo(ulong state) => state switch
        {
            0 => new(true, false, 0),
            1 => new(true, true, 0),
            _ => new(false, false, 0),
        };
        public ReadOnlyMemory<ScalarWfstArc> GetStateArcs(ulong state) => state == 0 ? StartArcs : ReadOnlyMemory<ScalarWfstArc>.Empty;
    }

    private sealed class ThrowingWfst : IScalarWfstProvider
    {
        public ulong StartState => throw new InvalidOperationException("contained");
        public nuint? StateCount => null;
        public ScalarWfstStateInfo GetStateInfo(ulong state) => default;
        public ReadOnlyMemory<ScalarWfstArc> GetStateArcs(ulong state) => default;
    }

    private sealed record MaxLattice(int Value) : IStableLatticeValueProvider
    {
        public ILatticeValueProvider Join(LatticeOperand other) => new MaxLattice(Math.Max(Value, Decode(other)));
        public ILatticeValueProvider Meet(LatticeOperand other) => new MaxLattice(Math.Min(Value, Decode(other)));
        public bool EqualsValue(LatticeOperand other) => Value == Decode(other);
        public string GetDiagnostic() => Value.ToString(System.Globalization.CultureInfo.InvariantCulture);
        public ReadOnlyMemory<byte> GetStableBytes()
        {
            byte[] bytes = new byte[4];
            BinaryPrimitives.WriteInt32LittleEndian(bytes, Value);
            return bytes;
        }
        private static int Decode(LatticeOperand other) => BinaryPrimitives.ReadInt32LittleEndian(other.GetStableBytes());
    }

    private sealed class TropicalSemiring : IDivisibleSemiringProvider<double>, IStarSemiringProvider<double>, INumericSemiringProvider<double>
    {
        public double Zero => double.PositiveInfinity;
        public double One => 0;
        public double CloneValue(double value) => value;
        public double Plus(double left, double right) => Math.Min(left, right);
        public double Times(double left, double right) => left + right;
        public bool EqualsValue(double left, double right) => left == right;
        public bool ApproximatelyEquals(double left, double right, double epsilon) => Math.Abs(left - right) <= epsilon;
        public SemiringOrder CompareNatural(double left, double right) => left.CompareTo(right) switch
        {
            < 0 => SemiringOrder.Better,
            > 0 => SemiringOrder.Worse,
            _ => SemiringOrder.Equal,
        };
        public ReadOnlyMemory<byte> GetStableBytes(double value) => BitConverter.GetBytes(value);
        public string GetDiagnostic(double value) => value.ToString(System.Globalization.CultureInfo.InvariantCulture);
        public bool TryDivide(double dividend, double divisor, out double result) { result = dividend - divisor; return true; }
        public bool TryLeftDivide(double value, double divisor, out double result) { result = value - divisor; return true; }
        public bool TryStar(double value, out double result) { result = 0; return value >= 0; }
        public double GetNumericalValue(double value) => value;
        public long Quantize(double value, double epsilon) => checked((long)Math.Round(value / epsilon));
        public double ToProbability(double value) => Math.Exp(-value);
    }

    private sealed class StringSemiring : ISemiringProvider<string>
    {
        public string Zero => string.Empty;
        public string One => "1";
        public string CloneValue(string value) => value;
        public string Plus(string left, string right) => left + right;
        public string Times(string left, string right) => left + right;
        public bool EqualsValue(string left, string right) => left == right;
        public bool ApproximatelyEquals(string left, string right, double epsilon) => left == right;
        public SemiringOrder CompareNatural(string left, string right) => (SemiringOrder)Math.Sign(string.CompareOrdinal(left, right));
        public ReadOnlyMemory<byte> GetStableBytes(string value) => System.Text.Encoding.UTF8.GetBytes(value);
        public string GetDiagnostic(string value) => value;
    }
}
