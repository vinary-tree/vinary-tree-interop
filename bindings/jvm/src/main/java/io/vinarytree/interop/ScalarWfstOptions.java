package io.vinarytree.interop;

import java.util.Objects;

/** Domains and capability promises for one immutable scalar WFST. */
public record ScalarWfstOptions(
        DictionaryUnitDomain unitDomain,
        ScalarWeightDomain weightDomain,
        long flags) {
    /** Concurrent calls are safe without an external sequential gate. */
    public static final long PARALLEL_REENTRANT = 1;
    /** The exported revision never changes; this flag is always added by the facade. */
    public static final long IMMUTABLE = 2;
    /** States or arcs may be expanded on demand. */
    public static final long LAZY = 4;
    /** The state graph is acyclic. */
    public static final long ACYCLIC = 8;
    /** Unicode-scalar labels and tropical weights on an immutable graph. */
    public static final ScalarWfstOptions DEFAULT =
            new ScalarWfstOptions(DictionaryUnitDomain.UNICODE_SCALAR, ScalarWeightDomain.TROPICAL_F64, IMMUTABLE);

    /** Validate domains and reject unknown capability bits. */
    public ScalarWfstOptions {
        Objects.requireNonNull(unitDomain, "unitDomain");
        Objects.requireNonNull(weightDomain, "weightDomain");
        long known = PARALLEL_REENTRANT | IMMUTABLE | LAZY | ACYCLIC;
        if ((flags & ~known) != 0) throw new IllegalArgumentException("unknown scalar-WFST flag");
    }
}
