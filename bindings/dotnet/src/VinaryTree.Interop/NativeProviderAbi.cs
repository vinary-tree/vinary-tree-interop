using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace VinaryTree.Interop;

internal static class NativeAbi
{
    internal const uint AbiVersion = 1;
    internal const uint InterfaceVersion = 1;
    internal const ulong WfstImmutable = 2;
    internal const ulong LatticeStableBytes = 4;
    internal const ulong LatticeBatch = 8;
    internal const ulong SemiringStableBytes = 4;
    internal const ulong SemiringBatch = 8;

    internal static ReadOnlySpan<byte> WfstId => "vt.scalar-wfst.1"u8;
    internal static ReadOnlySpan<byte> LatticeId => "vt.lattice.val.1"u8;
    internal static ReadOnlySpan<byte> SemiringId => "vt.semiring.val1"u8;
    internal static ReadOnlySpan<byte> SemiringDivisionId => "vt.semiring.div1"u8;
    internal static ReadOnlySpan<byte> SemiringStarId => "vt.semiring.str1"u8;
    internal static ReadOnlySpan<byte> SemiringNumericId => "vt.semiring.num1"u8;
    internal static ReadOnlySpan<byte> SemiringPropertiesId => "vt.semiring.prp1"u8;

    internal static unsafe bool IdEquals(byte* actual, ReadOnlySpan<byte> expected)
    {
        if (actual is null || expected.Length != 16) return false;
        for (int index = 0; index < expected.Length; index++)
        {
            if (actual[index] != expected[index]) return false;
        }
        return true;
    }

    internal static unsafe NativeInterfaceId ToNative(InteropDomainId domain)
    {
        NativeInterfaceId result = default;
        domain.CopyTo(new Span<byte>(result.Bytes, 16));
        return result;
    }
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeInterfaceId
{
    internal fixed byte Bytes[16];
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeWfstArc
{
    internal ulong InputLabel;
    internal ulong OutputLabel;
    internal ulong TargetState;
    internal double Weight;
    internal byte HasInput;
    internal byte HasOutput;
    internal unsafe fixed byte Reserved[6];
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeWfstVTable
{
    internal nuint StructSize;
    internal uint InterfaceVersion;
    internal DictionaryUnitDomain UnitDomain;
    internal ScalarWeightDomain WeightDomain;
    internal uint Reserved;
    internal ulong Flags;
    internal delegate* unmanaged[Cdecl]<nint, NativeResource*, DictionaryInteropStatus> Snapshot;
    internal delegate* unmanaged[Cdecl]<nint, ulong*, DictionaryInteropStatus> Start;
    internal delegate* unmanaged[Cdecl]<nint, nuint*, byte*, DictionaryInteropStatus> NumStates;
    internal delegate* unmanaged[Cdecl]<nint, ulong, byte*, byte*, double*, DictionaryInteropStatus> StateInfo;
    internal delegate* unmanaged[Cdecl]<nint, ulong, nuint, NativeWfstArc*, nuint, nuint*, nuint*, DictionaryInteropStatus> StateArcs;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeLatticeVTable
{
    internal nuint StructSize;
    internal uint InterfaceVersion;
    internal uint Reserved;
    internal ulong Flags;
    internal NativeInterfaceId DomainId;
    internal delegate* unmanaged[Cdecl]<nint, NativeResource*, NativeResource*, DictionaryInteropStatus> Join;
    internal delegate* unmanaged[Cdecl]<nint, NativeResource*, NativeResource*, DictionaryInteropStatus> Meet;
    internal delegate* unmanaged[Cdecl]<nint, NativeResource*, byte*, DictionaryInteropStatus> Equal;
    internal delegate* unmanaged[Cdecl]<nint, byte*, nuint, nuint*, nuint*, DictionaryInteropStatus> StableBytes;
    internal delegate* unmanaged[Cdecl]<nint, byte*, nuint, nuint*, nuint*, DictionaryInteropStatus> Diagnostic;
    internal delegate* unmanaged[Cdecl]<nint, NativeResource*, nuint, NativeResource*, DictionaryInteropStatus> JoinMany;
    internal delegate* unmanaged[Cdecl]<nint, NativeResource*, nuint, NativeResource*, DictionaryInteropStatus> MeetMany;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeSemiringValue
{
    internal ulong Word0;
    internal ulong Word1;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeSemiringVTable
{
    internal nuint StructSize;
    internal uint InterfaceVersion;
    internal uint Reserved;
    internal ulong Flags;
    internal NativeInterfaceId DomainId;
    internal delegate* unmanaged[Cdecl]<nint, NativeSemiringValue*, DictionaryInteropStatus> Zero;
    internal delegate* unmanaged[Cdecl]<nint, NativeSemiringValue*, DictionaryInteropStatus> One;
    internal delegate* unmanaged[Cdecl]<nint, NativeSemiringValue*, NativeSemiringValue*, DictionaryInteropStatus> CloneValue;
    internal delegate* unmanaged[Cdecl]<nint, NativeSemiringValue*, nuint, DictionaryInteropStatus> ReleaseValues;
    internal delegate* unmanaged[Cdecl]<nint, NativeSemiringValue*, NativeSemiringValue*, NativeSemiringValue*, DictionaryInteropStatus> Plus;
    internal delegate* unmanaged[Cdecl]<nint, NativeSemiringValue*, NativeSemiringValue*, NativeSemiringValue*, DictionaryInteropStatus> Times;
    internal delegate* unmanaged[Cdecl]<nint, NativeSemiringValue*, NativeSemiringValue*, byte*, DictionaryInteropStatus> Equal;
    internal delegate* unmanaged[Cdecl]<nint, NativeSemiringValue*, NativeSemiringValue*, double, byte*, DictionaryInteropStatus> ApproxEqual;
    internal delegate* unmanaged[Cdecl]<nint, NativeSemiringValue*, NativeSemiringValue*, int*, DictionaryInteropStatus> NaturalOrder;
    internal delegate* unmanaged[Cdecl]<nint, NativeSemiringValue*, byte*, nuint, nuint*, nuint*, DictionaryInteropStatus> StableBytes;
    internal delegate* unmanaged[Cdecl]<nint, NativeSemiringValue*, byte*, nuint, nuint*, nuint*, DictionaryInteropStatus> Diagnostic;
    internal delegate* unmanaged[Cdecl]<nint, NativeSemiringValue*, nuint, NativeSemiringValue*, DictionaryInteropStatus> PlusMany;
    internal delegate* unmanaged[Cdecl]<nint, NativeSemiringValue*, nuint, NativeSemiringValue*, DictionaryInteropStatus> TimesMany;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeSemiringDivisionVTable
{
    internal nuint StructSize;
    internal uint InterfaceVersion;
    internal uint Reserved;
    internal delegate* unmanaged[Cdecl]<nint, NativeSemiringValue*, NativeSemiringValue*, NativeSemiringValue*, DictionaryInteropStatus> Divide;
    internal delegate* unmanaged[Cdecl]<nint, NativeSemiringValue*, NativeSemiringValue*, NativeSemiringValue*, DictionaryInteropStatus> LeftDivide;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeSemiringStarVTable
{
    internal nuint StructSize;
    internal uint InterfaceVersion;
    internal uint Reserved;
    internal delegate* unmanaged[Cdecl]<nint, NativeSemiringValue*, NativeSemiringValue*, DictionaryInteropStatus> Star;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeSemiringNumericVTable
{
    internal nuint StructSize;
    internal uint InterfaceVersion;
    internal uint Reserved;
    internal delegate* unmanaged[Cdecl]<nint, NativeSemiringValue*, double*, DictionaryInteropStatus> NumericalValue;
    internal delegate* unmanaged[Cdecl]<nint, NativeSemiringValue*, double, long*, DictionaryInteropStatus> Quantize;
    internal delegate* unmanaged[Cdecl]<nint, NativeSemiringValue*, double*, DictionaryInteropStatus> ToProbability;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeSemiringPropertiesVTable
{
    internal nuint StructSize;
    internal uint InterfaceVersion;
    internal uint Reserved;
    internal SemiringProperties Properties;
    internal delegate* unmanaged[Cdecl]<nint, nuint*, byte*, DictionaryInteropStatus> ClosureBound;
}
