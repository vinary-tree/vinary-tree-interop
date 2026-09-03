package io.vinarytree.interop;

/**
 * One immutable host-defined lattice value.
 *
 * <p>Values returned by {@link #join(LatticeOperand)} and {@link #meet(LatticeOperand)} inherit
 * the receiver's exported domain and threading options. An implementation must therefore return
 * objects that satisfy the same concurrency promise.
 */
public interface LatticeProvider {
    /** Return this value joined with a compatible foreign operand. */
    LatticeProvider join(LatticeOperand other);
    /** Return this value met with a compatible foreign operand. */
    LatticeProvider meet(LatticeOperand other);
    /** Compare this value with a compatible foreign operand. */
    boolean equalsValue(LatticeOperand other);
    /** Return a concise diagnostic representation. */
    String diagnostic();
}
