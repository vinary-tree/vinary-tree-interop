package io.vinarytree.interop;

import java.util.Objects;

/** Domain identity and concurrency promises for one lattice value. */
public record LatticeOptions(DomainId domainId, long flags) {
    /** Each callback stays on the runtime-attached thread that entered the consumer call. */
    public static final long THREAD_BOUND = 1;
    /** Concurrent calls are safe without an external sequential gate. */
    public static final long PARALLEL_REENTRANT = 2;

    /** Construct an unflagged lattice domain. */
    public LatticeOptions(DomainId domainId) {
        this(domainId, 0);
    }

    /** Validate the domain and mutually exclusive threading promises. */
    public LatticeOptions {
        Objects.requireNonNull(domainId, "domainId");
        long known = THREAD_BOUND | PARALLEL_REENTRANT;
        if ((flags & ~known) != 0 || (flags & known) == known) {
            throw new IllegalArgumentException("invalid lattice threading flags");
        }
    }
}
