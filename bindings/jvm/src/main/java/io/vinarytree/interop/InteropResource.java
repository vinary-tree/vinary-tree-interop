package io.vinarytree.interop;

import java.lang.foreign.MemorySegment;

/** A retained two-word Vinary Tree resource with deterministic JVM lifetime. */
public interface InteropResource extends AutoCloseable {
    /** Borrow the native resource struct for one synchronous Foreign Function and Memory API call. */
    MemorySegment resourceSegment();

    /** Release this facade's owned retain. */
    @Override
    void close();
}
