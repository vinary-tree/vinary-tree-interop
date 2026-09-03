package io.vinarytree.interop;

/** Optional numeric projections for specialized algorithms. */
public interface NumericSemiringProvider<T> extends SemiringProvider<T> {
    /** Project a value to a scalar diagnostic. */ double numericalValue(T value);
    /** Quantize a value with a nonnegative tolerance. */ long quantize(T value, double epsilon);
    /** Convert a value to probability space. */ double toProbability(T value);
}
