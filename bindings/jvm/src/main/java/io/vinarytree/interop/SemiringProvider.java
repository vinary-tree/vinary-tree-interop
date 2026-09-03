package io.vinarytree.interop;

/** A host-defined semiring over immutable values of type {@code T}. */
public interface SemiringProvider<T> {
    /** Additive identity. */ T zero();
    /** Multiplicative identity. */ T one();
    /** Create an independently owned logical copy. */ T cloneValue(T value);
    /** Add two values. */ T plus(T left, T right);
    /** Multiply two values. */ T times(T left, T right);
    /** Test exact semantic equality. */ boolean equalsValue(T left, T right);
    /** Test equality within a nonnegative tolerance. */ boolean approximatelyEquals(T left, T right, double epsilon);
    /** Compare values in the semiring's natural order. */ SemiringOrder compareNatural(T left, T right);
    /** Return a canonical, deterministic encoding. */ byte[] stableBytes(T value);
    /** Return a concise diagnostic representation of the operation context. */ String diagnostic();
    /** Return a concise diagnostic representation. */ String diagnostic(T value);
}
