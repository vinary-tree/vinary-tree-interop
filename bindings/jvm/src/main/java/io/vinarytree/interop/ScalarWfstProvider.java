package io.vinarytree.interop;

import java.util.List;
import java.util.OptionalLong;

/** An immutable scalar weighted finite-state transducer implemented on the JVM. */
public interface ScalarWfstProvider {
    /** Provider-scoped start-state identifier. */
    long startState();
    /** Exact state count, or empty when lazy expansion makes it unknown. */
    OptionalLong stateCount();
    /** Inspect an arbitrary identifier without throwing merely because it is unknown. */
    ScalarWfstStateInfo stateInfo(long state);
    /** Borrow immutable outgoing arcs for a valid state. */
    List<ScalarWfstArc> stateArcs(long state);

    /**
     * Borrow one bounded arc page and report the complete outgoing count.
     *
     * <p>Lazy or compact providers should override this method so native paging does not
     * materialize the complete outgoing list or repeat state inspection. The default preserves
     * the simpler full-list provider contract.
     */
    default ScalarWfstArcPage stateArcsPage(long state, long start, int capacity) {
        ScalarWfstStateInfo info = stateInfo(state);
        if (info == null || !info.valid()) {
            throw new ProviderException(
                    ProviderException.Status.INVALID_ARGUMENT, "unknown scalar-WFST state");
        }
        List<ScalarWfstArc> values = stateArcs(state);
        if (values == null) throw new NullPointerException("stateArcs");
        int first = start >= values.size() ? values.size() : Math.toIntExact(start);
        int count = Math.min(capacity, values.size() - first);
        return new ScalarWfstArcPage(values.subList(first, first + count), values.size());
    }
}
