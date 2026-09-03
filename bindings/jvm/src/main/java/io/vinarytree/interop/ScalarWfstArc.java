package io.vinarytree.interop;

import java.util.OptionalLong;

/** One weighted transition; an empty label denotes epsilon. */
public record ScalarWfstArc(
        OptionalLong inputLabel,
        OptionalLong outputLabel,
        long targetState,
        double weight) {
    /** Create an arc while rejecting null option containers. */
    public ScalarWfstArc {
        if (inputLabel == null || outputLabel == null) throw new NullPointerException("arc labels");
    }
}
