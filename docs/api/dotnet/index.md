# Vinary Tree interop .NET API — 4.0.0-rc.6

`VinaryTree.Interop` is the resource handoff layer for independently packaged
Vinary Tree dictionaries, weighted automata, and host-defined algebras. It
contains no dictionary implementation. A *provider* is a C# or F# object that
implements a versioned capability; a *resource* is the retained two-word
descriptor through which native consumers invoke it.

## Choose a capability

| Goal | Implement or consume | Key guarantee |
|---|---|---|
| Hand a dictionary to another package | `IDictionaryResource` | Borrowed descriptor is valid only inside `WithResource`. |
| Enumerate dictionary keys | `DictionaryCollectionExtensions.SnapshotEntries` | Immutable, host-owned collection from one revision. |
| Export a weighted automaton | `IScalarWfstProvider` and `HostProviders.CreateScalarWfst` | Stable state IDs and immutable arc views. |
| Export join/meet values | `ILatticeValueProvider` and `HostProviders.CreateLatticeValue` | Exact 16-byte domain identity. |
| Export arithmetic laws | `ISemiringProvider<T>` and `HostProviders.CreateSemiring` | Provider-declared laws; optional division, star, numeric interfaces. |

The [C# guide](https://github.com/vinary-tree/vinary-tree-interop/blob/v4.0.0-rc.6/bindings/dotnet/README.md)
contains tested provider examples and the ownership/error/concurrency model.
The same interfaces are implemented naturally from F#; the
[F# fixture](https://github.com/vinary-tree/vinary-tree-interop/blob/v4.0.0-rc.6/bindings/dotnet/tests/VinaryTree.Interop.FSharpProviders/Program.fs)
compiles and runs as part of CI. Use C# `using` or F# `use` to dispose each
`HostedResource` deterministically; do not rely on its finalizer for ordinary
resource lifetime.
