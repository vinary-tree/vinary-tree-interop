# Kotlin: consume the Vinary Tree interop Java API

The Maven artifact `io.vinarytree:vinary-tree-interop:4.0.0-rc.6` is a Java 22
Foreign Function and Memory (FFM) library that Kotlin can call directly. There
is no separate Kotlin artifact or wrapper API. Enable native access for your
classpath or `io.vinarytree.interop` module when making native calls.

The [Javadoc package index](https://javadoc.io/doc/io.vinarytree/vinary-tree-interop/4.0.0-rc.6/io/vinarytree/interop/package-summary.html)
is the authoritative symbol reference after publication. The
[compiled Kotlin provider fixture](src/test/kotlin/io/vinarytree/interop/KotlinProviderSmoke.kt)
uses `ScalarWfstProvider`, `StableLatticeProvider`, and `SemiringProvider` with
actual host-defined implementations; Gradle compiles and executes it in CI.

## Give a consumer a retained provider

```kotlin
import io.vinarytree.interop.*
import java.util.OptionalLong

fun main() {
    val wfst = object : ScalarWfstProvider {
        override fun startState() = 0L
        override fun stateCount() = OptionalLong.of(1L)
        override fun stateInfo(state: Long) =
            ScalarWfstStateInfo(state == 0L, state == 0L, 0.0)
        override fun stateArcs(state: Long) = emptyList<ScalarWfstArc>()
    }
    HostProviders.scalarWfst(wfst).use { exported ->
        // Pass exported to a consumer that accepts InteropResource.
        check(exported != null)
    }
}
```

`use` deterministically closes the wrapper's owned retain. A native consumer
that called the ABI's `retain` owns a separate reference and may outlive the
Kotlin scope. The weighted finite-state transducer (WFST) provider returns
one immutable graph revision; state IDs are scoped to that revision. Do not
advertise parallel reentrancy unless callbacks are thread-safe. For collection
snapshots, domain identities, status handling, and the three additional
provider families, use the [JVM provider guide](../../docs/language-bindings/jvm-host-providers.md).
