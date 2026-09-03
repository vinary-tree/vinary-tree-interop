package io.vinarytree.interop

import java.nio.ByteBuffer
import java.lang.foreign.MemorySegment
import java.util.OptionalLong
import java.util.function.Function
import scala.util.Using

/** Executable proof that Scala implementations fit every JVM provider family naturally. */
object ScalaProviderSmoke:
  def main(arguments: Array[String]): Unit =
    val wfst = new ScalarWfstProvider:
      override def startState(): Long = 0L
      override def stateCount(): OptionalLong = OptionalLong.of(1L)
      override def stateInfo(state: Long): ScalarWfstStateInfo =
        ScalarWfstStateInfo(state == 0L, state == 0L, 0.0)
      override def stateArcs(state: Long): java.util.List[ScalarWfstArc] =
        java.util.List.of()

    val semiring = new SemiringProvider[java.lang.Long]:
      override def zero(): java.lang.Long = 0L
      override def one(): java.lang.Long = 1L
      override def cloneValue(value: java.lang.Long): java.lang.Long = value
      override def plus(left: java.lang.Long, right: java.lang.Long): java.lang.Long =
        left.longValue + right.longValue
      override def times(left: java.lang.Long, right: java.lang.Long): java.lang.Long =
        left.longValue * right.longValue
      override def equalsValue(left: java.lang.Long, right: java.lang.Long): Boolean =
        left == right
      override def approximatelyEquals(
          left: java.lang.Long,
          right: java.lang.Long,
          epsilon: Double
      ): Boolean = left == right
      override def compareNatural(
          left: java.lang.Long,
          right: java.lang.Long
      ): SemiringOrder =
        if left < right then SemiringOrder.BETTER
        else if left > right then SemiringOrder.WORSE
        else SemiringOrder.EQUAL
      override def stableBytes(value: java.lang.Long): Array[Byte] =
        ByteBuffer.allocate(8).putLong(value).array
      override def diagnostic(): String = "Scala integer semiring"
      override def diagnostic(value: java.lang.Long): String = value.toString

    Using.resource(HostProviders.scalarWfst(wfst)): resource =>
      assert(isLive(resource))
      ProviderLanguageProbe.assertWfst(resource, 0L)
    Using.resource(
      HostProviders.lattice(
        ScalaMaximum(3),
        LatticeOptions(DomainId.fromAscii("scala3.lattice.1"))
      )
    ): resource =>
      assert(isLive(resource))
      ProviderLanguageProbe.assertLatticeReflexive(resource)
    Using.resource(
      HostProviders.semiring(
        semiring,
        SemiringOptions(DomainId.fromAscii("scala3.semiring1"))
      )
    ): resource =>
      assert(isLive(resource))
      ProviderLanguageProbe.assertSemiringOne(resource)

  private def isLive(resource: HostedResource): Boolean =
    resource.withResourceSegment(
      new Function[MemorySegment, java.lang.Boolean]:
        override def apply(segment: MemorySegment): java.lang.Boolean =
          java.lang.Boolean.valueOf(segment.address != 0L)
    ).booleanValue

private final case class ScalaMaximum(value: Int) extends StableLatticeProvider:
  override def join(other: LatticeOperand): LatticeProvider =
    ScalaMaximum(math.max(value, decode(other)))
  override def meet(other: LatticeOperand): LatticeProvider =
    ScalaMaximum(math.min(value, decode(other)))
  override def equalsValue(other: LatticeOperand): Boolean = value == decode(other)
  override def diagnostic(): String = value.toString
  override def stableBytes(): Array[Byte] = ByteBuffer.allocate(4).putInt(value).array

  private def decode(other: LatticeOperand): Int =
    other.localProvider(classOf[ScalaMaximum])
      .map(_.value)
      .orElseGet(() => ByteBuffer.wrap(other.stableBytes()).getInt)
