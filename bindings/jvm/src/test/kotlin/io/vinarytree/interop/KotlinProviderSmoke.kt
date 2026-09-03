package io.vinarytree.interop

import java.nio.ByteBuffer
import java.util.OptionalLong
import java.util.function.Function

/** Executable proof that Kotlin implementations fit every JVM provider family naturally. */
object KotlinProviderSmoke {
    @JvmStatic
    fun main(arguments: Array<String>) {
        val wfst = object : ScalarWfstProvider {
            override fun startState() = 0L
            override fun stateCount() = OptionalLong.of(1)
            override fun stateInfo(state: Long) =
                ScalarWfstStateInfo(state == 0L, state == 0L, 0.0)
            override fun stateArcs(state: Long) = emptyList<ScalarWfstArc>()
        }
        val semiring = object : SemiringProvider<Long> {
            override fun zero() = 0L
            override fun one() = 1L
            override fun cloneValue(value: Long) = value
            override fun plus(left: Long, right: Long) = left + right
            override fun times(left: Long, right: Long) = left * right
            override fun equalsValue(left: Long, right: Long) = left == right
            override fun approximatelyEquals(left: Long, right: Long, epsilon: Double) =
                left == right
            override fun compareNatural(left: Long, right: Long) =
                when {
                    left < right -> SemiringOrder.BETTER
                    left > right -> SemiringOrder.WORSE
                    else -> SemiringOrder.EQUAL
                }
            override fun stableBytes(value: Long) = ByteBuffer.allocate(8).putLong(value).array()
            override fun diagnostic() = "Kotlin integer semiring"
            override fun diagnostic(value: Long) = value.toString()
        }

        HostProviders.scalarWfst(wfst).use { resource ->
            check(resource.withResourceSegment(Function { it.address() != 0L }))
            ProviderLanguageProbe.assertWfst(resource, 0L)
        }
        HostProviders.lattice(
            KotlinMaximum(3),
            LatticeOptions(DomainId.fromAscii("kotlin.lattice.1"))
        ).use { resource ->
            check(resource.withResourceSegment(Function { it.address() != 0L }))
            ProviderLanguageProbe.assertLatticeReflexive(resource)
        }
        HostProviders.semiring(
            semiring,
            SemiringOptions(DomainId.fromAscii("kotlin.semiring1"))
        ).use { resource ->
            check(resource.withResourceSegment(Function { it.address() != 0L }))
            ProviderLanguageProbe.assertSemiringOne(resource)
        }
    }

    private data class KotlinMaximum(val value: Int) : StableLatticeProvider {
        override fun join(other: LatticeOperand) =
            KotlinMaximum(maxOf(value, decode(other)))
        override fun meet(other: LatticeOperand) =
            KotlinMaximum(minOf(value, decode(other)))
        override fun equalsValue(other: LatticeOperand) = value == decode(other)
        override fun diagnostic() = value.toString()
        override fun stableBytes() = ByteBuffer.allocate(4).putInt(value).array()

        private fun decode(other: LatticeOperand) =
            other.localProvider(KotlinMaximum::class.java)
                .map(KotlinMaximum::value)
                .orElseGet { ByteBuffer.wrap(other.stableBytes()).int }
    }
}
