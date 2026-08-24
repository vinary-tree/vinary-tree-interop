# Vinary Tree interop for .NET

`VinaryTree.Interop` supplies the retained two-word resource handle and the
dictionary collection protocols shared by the independently published Vinary
Tree .NET packages. It contains no dictionary or automaton implementation.

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

The public package version for this release candidate is `4.0.0-rc.2`. The
binary resource ABI remains version 1; package major versions and ABI versions
are deliberately independent.

Build the package from the repository root with:

```sh
dotnet build bindings/dotnet/src/VinaryTree.Interop/VinaryTree.Interop.csproj \
  --configuration Release
```

See the [normative ABI reference](../../docs/abi-reference.md), the
[ownership and security model](../../docs/security-model.md), and the
[release procedure](../../docs/releasing.md).
