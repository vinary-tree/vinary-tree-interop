package io.vinarytree.interop;

import java.util.Optional;

/** Optional quotient operations for a semiring. */
public interface DivisibleSemiringProvider<T> extends SemiringProvider<T> {
    /** Return a right quotient, or empty when it is undefined. */ Optional<T> divide(T dividend, T divisor);
    /** Return a left quotient, or empty when it is undefined. */ Optional<T> leftDivide(T value, T divisor);
}
