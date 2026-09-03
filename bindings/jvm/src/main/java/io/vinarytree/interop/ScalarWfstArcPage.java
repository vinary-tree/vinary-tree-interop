package io.vinarytree.interop;

import java.util.List;
import java.util.Objects;

/** One borrowed, bounded page of scalar-WFST arcs and the complete outgoing count. */
public record ScalarWfstArcPage(List<ScalarWfstArc> arcs, long total) {
    /** Validate only representation-independent page invariants. */
    public ScalarWfstArcPage {
        Objects.requireNonNull(arcs, "arcs");
        if (total < 0 || arcs.size() > total) {
            throw new IllegalArgumentException("invalid scalar-WFST arc page");
        }
    }
}
