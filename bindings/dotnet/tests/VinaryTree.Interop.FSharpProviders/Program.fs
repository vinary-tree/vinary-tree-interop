open System
open VinaryTree.Interop

type OneStateWfst() =
    interface IScalarWfstProvider with
        member _.StartState = 0UL
        member _.StateCount = Nullable<unativeint>(1un)
        member _.GetStateInfo(state) =
            let valid = state = 0UL
            ScalarWfstStateInfo(valid, valid, 0.0)
        member _.GetStateArcs(_) = ReadOnlyMemory<ScalarWfstArc>.Empty

type Maximum(value: int) =
    member _.Value = value

    interface IStableLatticeValueProvider with
        member _.Join(other) = Maximum(max value (BitConverter.ToInt32(other.GetStableBytes())))
        member _.Meet(other) = Maximum(min value (BitConverter.ToInt32(other.GetStableBytes())))
        member _.EqualsValue(other) = value = BitConverter.ToInt32(other.GetStableBytes())
        member _.GetDiagnostic() = string value
        member _.GetStableBytes() = ReadOnlyMemory<byte>(BitConverter.GetBytes(value))

type MinPlus() =
    interface ISemiringProvider<int64> with
        member _.Zero = Int64.MaxValue
        member _.One = 0L
        member _.CloneValue(value) = value
        member _.Plus(left, right) = min left right
        member _.Times(left, right) = left + right
        member _.EqualsValue(left, right) = left = right
        member _.ApproximatelyEquals(left, right, _) = left = right
        member _.CompareNatural(left, right) =
            if left < right then SemiringOrder.Better
            elif left > right then SemiringOrder.Worse
            else SemiringOrder.Equal
        member _.GetStableBytes(value) = ReadOnlyMemory<byte>(BitConverter.GetBytes(value))
        member _.GetDiagnostic(value) = string value

[<EntryPoint>]
let main _ =
    use _wfst = HostProviders.CreateScalarWfst(OneStateWfst())
    let latticeDomain = InteropDomainId.FromAscii("fsharp.lattice.1")
    use _lattice = HostProviders.CreateLatticeValue(Maximum(3), LatticeProviderOptions(latticeDomain))
    let semiringDomain = InteropDomainId.FromAscii("fsharp.semiring1")
    use _semiring = HostProviders.CreateSemiring<int64>(MinPlus(), SemiringProviderOptions(semiringDomain))
    printfn "F# provider fixture passed"
    0
