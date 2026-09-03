package io.vinarytree.interop;

import java.util.Optional;

/** Optional Kleene closure for a semiring. */
public interface StarSemiringProvider<T> extends SemiringProvider<T> {
    /** Return closure, or empty when it diverges. */ Optional<T> star(T value);
}
