# Scala 3: consume the Vinary Tree interop Java API

Scala uses the Java 22 FFM artifact
`io.vinarytree:vinary-tree-interop:4.0.0-rc.6` directly. There is no separate
Scala package or invented Scala-specific facade. Enable native access before
calling the native boundary. Browse the
[exact-version Javadoc](https://javadoc.io/doc/io.vinarytree/vinary-tree-interop/4.0.0-rc.6/io/vinarytree/interop/package-summary.html)
after publication. The [compiled Scala fixture](src/test/scala/io/vinarytree/interop/ScalaProviderSmoke.scala)
executes WFST, lattice, and semiring provider calls in CI.

```scala
import io.vinarytree.interop.*
import java.util.OptionalLong
import scala.util.Using

@main def example(): Unit =
  val wfst = new ScalarWfstProvider:
    override def startState(): Long = 0L
    override def stateCount(): OptionalLong = OptionalLong.of(1L)
    override def stateInfo(state: Long): ScalarWfstStateInfo =
      ScalarWfstStateInfo(state == 0L, state == 0L, 0.0)
    override def stateArcs(state: Long): java.util.List[ScalarWfstArc] =
      java.util.List.of()

  Using.resource(HostProviders.scalarWfst(wfst)): exported =>
    // Pass exported to a consumer accepting InteropResource.
    assert(exported != null)
```

`Using.resource` closes only the Scala wrapper's owned retain; a native
consumer must use its own ABI retain when it needs an independent lifetime.
The host provider is an immutable revision, not a callback into a mutable
Scala collection. `OptionalLong.empty` represents an epsilon label, while a
zero label is an ordinary token. The [JVM provider guide](../../docs/language-bindings/jvm-host-providers.md)
explains exact domain identities, optional semiring laws, batching, and
parallel-callback capability flags.
