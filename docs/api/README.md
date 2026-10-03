# Managed-language API references

These are `4.0.0-rc.6` **source-candidate** references. A generated local site
is evidence that documentation can be built, not evidence of publication.

| Consumer language | Shipped API and browsable reference | Verified common use |
|---|---|---|
| Java, Kotlin, Scala | One Java 22 Maven artifact, `io.vinarytree:vinary-tree-interop`; its `-javadoc.jar` contains the Java API reference. There are no distinct Kotlin or Scala wrapper artifacts. | [Kotlin](../../bindings/jvm/kotlin.md) and [Scala](../../bindings/jvm/scala.md) guides link to compiled, executed provider fixtures. |
| C#, F# | One `VinaryTree.Interop` NuGet assembly targeting .NET 8 and .NET 10; XML documentation is packed for each target and [DocFX source](dotnet/index.md) yields browsable pages. | The [C#/F# guide](../../bindings/dotnet/README.md) and F# provider fixture use the public C# interfaces. |
| Swift | SwiftPM product `VinaryTreeInterop` with two public Swift types and the shared C ABI; [DocC overview](../../bindings/swift/vinary-tree-interop/Sources/VinaryTreeInterop/VinaryTreeInterop.docc/VinaryTreeInterop.md). | A producer implements `DictionaryResource`; its two-word handle is borrowed only inside a synchronous closure. |

The [CI workflow](../../.github/workflows/ci.yml) builds strict Javadoc,
DocFX, and DocC sites without publishing them. The source-derived checker
rejects a missing browsable page for any current public type, and Kotlin,
Scala, and F# fixtures compile against the actual facades. The checker is
deliberately inventory-based: adding a public type without a generated page
fails the gate, while private implementation types do not create false
requirements.

The `validate-only` [release graph](../../.github/workflows/release.yml)
stages a deterministic, hashed DocFX archive before the GitHub release
becomes immutable. The protected [manual deploy](../../.github/workflows/dotnet-docs-release.yml)
rebuilds the archive from the reviewed tag, compares exact bytes, preserves
the existing Julia `gh-pages` subtree and earlier versions, then compares
every served .NET page with its immutable archive. The separate
[registry readback](../../.github/workflows/managed-api-registry-readback.yml)
must run only after Maven Central, NuGet, and Swift Package Index expose the
exact version. Neither gate publishes any registry package.
