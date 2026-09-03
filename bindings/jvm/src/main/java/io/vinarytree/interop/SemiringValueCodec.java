package io.vinarytree.interop;

/** Allocation-free primitive encoding for a JVM semiring value held by an owned ABI token. */
public interface SemiringValueCodec<T> {
    /** Encode one immutable value into an unsigned 64-bit primitive payload. */ long encode(T value);
    /** Decode a primitive payload previously minted by this codec. */ T decode(long bits);

    /** IEEE-754 binary64 codec for {@link Double}. */
    static SemiringValueCodec<Double> doubles() {
        return new SemiringValueCodec<>() {
            @Override public long encode(Double value) { return Double.doubleToRawLongBits(value); }
            @Override public Double decode(long bits) { return Double.longBitsToDouble(bits); }
        };
    }
}
