# Vinary Tree interop for .NET

`VinaryTree.Interop` supplies the retained two-word resource handle, natural
dictionary collection protocols, and managed host-provider interfaces shared
by independently published Vinary Tree .NET packages. It contains no
dictionary or automaton implementation.

The package targets .NET 8 and .NET 10. A concrete provider owns its native
resource; a managed wrapper retains one reference while it is usable and
releases exactly that reference from `Dispose`. Consumers should therefore use
resource-bearing objects with `using` declarations or `using` statements.

```csharp
using VinaryTree.Interop;

static long CountEntries(DictionaryResource dictionary)
{
    using DictionarySnapshot snapshot = dictionary.Snapshot();
    return snapshot.LongCount();
}
```

The public package version for this release candidate is `4.0.0-rc.6`. The
binary resource ABI remains version 1; package major versions and ABI versions
are deliberately independent.

## Choose the surface that matches your task

| Goal | .NET surface | Native capability |
|---|---|---|
| Read a dictionary as a collection | `SnapshotEntries`, `StreamEntries` | dictionary entries v1 |
| Supply a weighted finite-state transducer (WFST) | `IScalarWfstProvider` | scalar WFST v1 |
| Supply a lattice value | `ILatticeValueProvider` | lattice value v1 |
| Supply a semiring | `ISemiringProvider<T>` | dynamic semiring v1 |
| Add division, closure, or numeric projections | `IDivisibleSemiringProvider<T>`, `IStarSemiringProvider<T>`, `INumericSemiringProvider<T>` | optional semiring v1 interfaces |

A **provider** is managed code that implements an operation for native
consumers. A **resource** is the retained two-word ABI handle that keeps that
provider alive. A **domain identity** is an exact 16-byte value that prevents
operations between unrelated algebras.

![A C# or F# provider is wrapped in an IDisposable HostedResource backed by a provider-scoped GCHandle, atomic retain count, and immutable native vtables. Native consumers discover a capability, retain the context, invoke validated callbacks, and release it; final release frees the tables and handle. There is no global registry or sequential call gate.](../../docs/diagrams/dotnet-provider-lifecycle.svg)

## Export a scalar WFST

`IScalarWfstProvider` presents one immutable revision. State identifiers are
provider-scoped, null labels are epsilon transitions, and returned arc memory
must remain unchanged while the exported resource lives.

```csharp
using VinaryTree.Interop;

sealed class GreetingWfst : IScalarWfstProvider
{
    private static readonly ScalarWfstArc[] StartArcs =
        [new(InputLabel: 'h', OutputLabel: 'h', TargetState: 1, Weight: 0.25)];

    public ulong StartState => 0;
    public nuint? StateCount => 2;

    public ScalarWfstStateInfo GetStateInfo(ulong state) => state switch
    {
        0 => new(IsValid: true, IsFinal: false, FinalWeight: 0),
        1 => new(IsValid: true, IsFinal: true, FinalWeight: 0),
        _ => new(IsValid: false, IsFinal: false, FinalWeight: 0),
    };

    public ReadOnlyMemory<ScalarWfstArc> GetStateArcs(ulong state) =>
        state == 0 ? StartArcs : ReadOnlyMemory<ScalarWfstArc>.Empty;
}

using HostedResource wfst = HostProviders.CreateScalarWfst(
    new GreetingWfst(),
    ScalarWfstOptions.Default with
    {
        Flags = ScalarWfstFlags.Acyclic | ScalarWfstFlags.ParallelReentrant,
    });
```

The facade always advertises `Immutable`. Advertise `ParallelReentrant` only
when all provider methods are safe to call concurrently; the facade never adds
a hidden lock to make an unsafe provider appear safe.

## Export a lattice value

A lattice combines information with join and intersects information with meet.
For values $`a`$ and $`b`$, the implementation is responsible for the lattice
laws, including $`a \mathbin{\sqcup} a = a`$ and
$`a \mathbin{\sqcap} a = a`$. Implement `IStableLatticeValueProvider` when a
foreign implementation must decode the value through canonical bytes.

```csharp
using System.Buffers.Binary;
using VinaryTree.Interop;

sealed record Maximum(int Value) : IStableLatticeValueProvider
{
    public ILatticeValueProvider Join(LatticeOperand other) =>
        new Maximum(Math.Max(Value, Decode(other)));

    public ILatticeValueProvider Meet(LatticeOperand other) =>
        new Maximum(Math.Min(Value, Decode(other)));

    public bool EqualsValue(LatticeOperand other) => Value == Decode(other);
    public string GetDiagnostic() => Value.ToString();

    public ReadOnlyMemory<byte> GetStableBytes()
    {
        byte[] bytes = new byte[4];
        BinaryPrimitives.WriteInt32LittleEndian(bytes, Value);
        return bytes;
    }

    private static int Decode(LatticeOperand other) =>
        BinaryPrimitives.ReadInt32LittleEndian(other.GetStableBytes());
}

InteropDomainId domain = InteropDomainId.FromAscii("example.max.int1");
using HostedResource value = HostProviders.CreateLatticeValue(
    new Maximum(7),
    new LatticeProviderOptions(domain, LatticeProviderFlags.ParallelReentrant));
```

`LatticeOperand` is borrowed only during the provider callback. Do not retain
it. Stable-byte reads have a 16 MiB defensive bound and at most three sizing
attempts, so a malformed foreign provider cannot force unbounded allocation.

## Export a semiring

A semiring has additive identity $`0`$, multiplicative identity $`1`$,
addition $`\oplus`$, and multiplication $`\otimes`$. The provider owns the
law claims it places in `SemiringProperties`.

```csharp
using VinaryTree.Interop;

sealed class Tropical : ISemiringProvider<double>
{
    public double Zero => double.PositiveInfinity;
    public double One => 0;
    public double CloneValue(double value) => value;
    public double Plus(double left, double right) => Math.Min(left, right);
    public double Times(double left, double right) => left + right;
    public bool EqualsValue(double left, double right) => left == right;
    public bool ApproximatelyEquals(double left, double right, double epsilon) =>
        Math.Abs(left - right) <= epsilon;
    public SemiringOrder CompareNatural(double left, double right) =>
        left < right ? SemiringOrder.Better :
        left > right ? SemiringOrder.Worse : SemiringOrder.Equal;
    public ReadOnlyMemory<byte> GetStableBytes(double value) =>
        BitConverter.GetBytes(value);
    public string GetDiagnostic(double value) => value.ToString("R");
}

InteropDomainId domain = InteropDomainId.FromAscii("example.trop.f64");
using HostedResource semiring = HostProviders.CreateSemiring(
    new Tropical(),
    new SemiringProviderOptions(
        domain,
        SemiringProviderFlags.ParallelReentrant,
        SemiringProperties.IdempotentPlus |
            SemiringProperties.TotallyOrdered));
```

Reference-free value types no larger than eight bytes, including `double`, are
stored directly in the ABI token. Larger structs and reference types use
provider-scoped `GCHandle` tokens. Batch folds operate directly over the native
token span and do not materialize an intermediate managed collection.

Optional interfaces are discovered from the interfaces implemented by the
provider. Implement `IDivisibleSemiringProvider<T>`,
`IStarSemiringProvider<T>`, or `INumericSemiringProvider<T>` only when the
corresponding operations are meaningful.

## Implement providers in F#

The provider contracts are ordinary .NET interfaces; F# does not need a
language-specific bridge. Its `use` binding gives the exported resource
deterministic `IDisposable` lifetime.

```fsharp
open System
open VinaryTree.Interop

type MinPlus() =
    interface ISemiringProvider<int64> with
        member _.Zero = Int64.MaxValue
        member _.One = 0L
        member _.CloneValue value = value
        member _.Plus(left, right) = min left right
        member _.Times(left, right) = left + right
        member _.EqualsValue(left, right) = left = right
        member _.ApproximatelyEquals(left, right, _) = left = right
        member _.CompareNatural(left, right) =
            if left < right then SemiringOrder.Better
            elif left > right then SemiringOrder.Worse
            else SemiringOrder.Equal
        member _.GetStableBytes value =
            ReadOnlyMemory<byte>(BitConverter.GetBytes(value))
        member _.GetDiagnostic value = string value

let domain = InteropDomainId.FromAscii("example.minplus1")
use semiring =
    HostProviders.CreateSemiring<int64>(
        MinPlus(), SemiringProviderOptions(domain))
```

## Ownership, failures, and concurrency

- Dispose `HostedResource` deterministically with C# `using` or F# `use`.
  A finalizer is a leak backstop, not the normal lifetime mechanism.
- Native retain and release operations use atomic reference counting. Each
  provider has one private `GCHandle`; there is no process-wide registry.
- Managed exceptions are contained at every unmanaged callback. Memory
  exhaustion becomes `LimitExceeded`; other exceptions become
  `ProviderError`. Failed callbacks preserve output parameters unless the ABI
  contract explicitly says otherwise.
- Domain identities are validated before lattice or semiring values cross a
  provider boundary. Semiring tokens also carry a context cookie, preventing
  accidental use with another operation context.
- `ThreadBound` and `ParallelReentrant` are mutually exclusive. With neither
  flag, callers must assume no concurrency guarantee.

Build the package from the repository root with:

```sh
dotnet build bindings/dotnet/src/VinaryTree.Interop/VinaryTree.Interop.csproj \
  --configuration Release
```

Run both provider fixtures with:

```sh
dotnet run \
  --project bindings/dotnet/tests/VinaryTree.Interop.ProviderTests/VinaryTree.Interop.ProviderTests.csproj \
  --configuration Release
dotnet run \
  --project bindings/dotnet/tests/VinaryTree.Interop.FSharpProviders/VinaryTree.Interop.FSharpProviders.fsproj \
  --configuration Release
```

See the [normative ABI reference](../../docs/abi-reference.md), the
[ownership and security model](../../docs/security-model.md), and the
[release procedure](../../docs/releasing.md).
