package io.vinarytree.interop;

import java.util.Objects;
import java.util.OptionalLong;

/** Domain identity, concurrency promises, and declared laws for a semiring. */
public record SemiringOptions(
        DomainId domainId,
        long flags,
        long properties,
        OptionalLong closureBound) {
    /** Each callback stays on the runtime-attached thread that entered the consumer call. */
    public static final long THREAD_BOUND = 1;
    /** Concurrent calls are safe without a sequential gate. */ public static final long PARALLEL_REENTRANT = 2;
    /** Stable bytes may serve as hash keys. */ public static final long HASHABLE = 1;
    /** Addition is idempotent. */ public static final long IDEMPOTENT_PLUS = 2;
    /** Closure is bounded. */ public static final long K_CLOSED = 4;
    /** A sum is zero only when both operands are zero. */ public static final long ZERO_SUM_FREE = 8;
    /** Multiplication is commutative. */ public static final long COMMUTATIVE_TIMES = 16;
    /** The natural order is total. */ public static final long TOTALLY_ORDERED = 32;
    /** Values are nonnegative. */ public static final long NONNEGATIVE = 64;

    /** Construct an unflagged domain with no asserted laws or closure bound. */
    public SemiringOptions(DomainId domainId) {
        this(domainId, 0, 0, OptionalLong.empty());
    }

    /** Validate the domain, flags, law bits, and closure metadata. */
    public SemiringOptions {
        Objects.requireNonNull(domainId, "domainId");
        Objects.requireNonNull(closureBound, "closureBound");
        long knownFlags = THREAD_BOUND | PARALLEL_REENTRANT;
        long knownProperties = HASHABLE | IDEMPOTENT_PLUS | K_CLOSED | ZERO_SUM_FREE
                | COMMUTATIVE_TIMES | TOTALLY_ORDERED | NONNEGATIVE;
        if ((flags & ~knownFlags) != 0
                || (flags & knownFlags) == knownFlags
                || (properties & ~knownProperties) != 0
                || (closureBound.isPresent() && closureBound.getAsLong() < 0)) {
            throw new IllegalArgumentException("invalid semiring flags, properties, or closure bound");
        }
    }
}
