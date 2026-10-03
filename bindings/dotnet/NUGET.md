# Vinary Tree interop for .NET

`VinaryTree.Interop` lets a C# or F# program supply native-consumable
dictionary resources, weighted finite-state transducers (WFSTs), lattice
values, and semirings to Vinary Tree libraries. It is an interoperation layer,
not a dictionary or search engine. This package version is `4.0.0-rc.6` for
.NET 8 and .NET 10; the binary ABI remains version 1.

Implement an interface in ordinary C# and export it as a scoped native
resource. A native consumer may retain it independently, so disposing the
managed wrapper releases only its own reference.

```csharp
using System;
using VinaryTree.Interop;

using HostedResource resource = HostProviders.CreateScalarWfst(new OneStateWfst());
// Pass resource through an API accepting IDictionaryResource.

sealed class OneStateWfst : IScalarWfstProvider
{
    public ulong StartState => 0;
    public nuint? StateCount => (nuint)1;
    public ScalarWfstStateInfo GetStateInfo(ulong state) =>
        new(state == 0, state == 0, 0.0);
    public ReadOnlyMemory<ScalarWfstArc> GetStateArcs(ulong state) =>
        ReadOnlyMemory<ScalarWfstArc>.Empty;
}
```

`OneStateWfst` is an immutable weighted finite-state transducer with one
final state and no arcs; see the [compiled C# provider fixture](https://github.com/vinary-tree/vinary-tree-interop/blob/v4.0.0-rc.6/bindings/dotnet/tests/VinaryTree.Interop.ProviderTests/Program.cs)
and the [compiled F# fixture](https://github.com/vinary-tree/vinary-tree-interop/blob/v4.0.0-rc.6/bindings/dotnet/tests/VinaryTree.Interop.FSharpProviders/Program.fs).
The full [C# and F# guide](https://github.com/vinary-tree/vinary-tree-interop/blob/v4.0.0-rc.6/bindings/dotnet/README.md)
explains ownership, domain identity, semiring laws, collection snapshots,
native loading, and concurrency. Browse the
[versioned API reference](https://vinary-tree.github.io/vinary-tree-interop/4.0.0-rc.6/dotnet/)
for every public type and member after its release-gated deployment.
