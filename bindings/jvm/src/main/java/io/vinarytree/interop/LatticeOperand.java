package io.vinarytree.interop;

import static java.lang.foreign.ValueLayout.ADDRESS;
import static java.lang.foreign.ValueLayout.JAVA_INT;
import static java.lang.foreign.ValueLayout.JAVA_LONG;

import java.lang.foreign.Arena;
import java.lang.foreign.MemorySegment;
import java.util.Objects;
import java.util.Optional;

/** A validated foreign lattice operand borrowed for one provider callback. */
public final class LatticeOperand {
    private static final int MAX_BYTES = 16 * 1024 * 1024;
    private final MemorySegment context;
    private final MemorySegment table;
    private final LatticeProvider localProvider;
    private final ProviderRuntime.ForeignGateLease gate;
    private volatile boolean active = true;

    LatticeOperand(
            MemorySegment context,
            MemorySegment table,
            LatticeProvider localProvider,
            ProviderRuntime.ForeignGateLease gate) {
        this.context = context;
        this.table = table;
        this.localProvider = localProvider;
        this.gate = gate;
    }

    /** Whether the foreign value advertises canonical stable bytes. */
    public boolean hasStableBytes() {
        requireActive();
        return (table.get(JAVA_LONG, 16) & 4) != 0
                && !ProviderRuntime.isNull(table.get(ADDRESS, 64));
    }

    /**
     * Resolve a same-JVM value without crossing the native boundary.
     *
     * <p>The result is empty for a foreign provider or an incompatible Java type.
     */
    public <T extends LatticeProvider> Optional<T> localProvider(Class<T> type) {
        requireActive();
        Objects.requireNonNull(type, "type");
        return type.isInstance(localProvider) ? Optional.of(type.cast(localProvider)) : Optional.empty();
    }

    /** Read the canonical encoding with bounded allocation and an invariant two-call size. */
    public byte[] stableBytes() {
        requireActive();
        if (!hasStableBytes()) throw new UnsupportedOperationException("lattice stable bytes are unavailable");
        if (localProvider instanceof StableLatticeProvider stable) {
            byte[] bytes = Objects.requireNonNull(stable.stableBytes(), "stableBytes");
            if (bytes.length > MAX_BYTES) {
                throw new ProviderException(
                        ProviderException.Status.LIMIT_EXCEEDED,
                        "lattice stable bytes exceed the defensive limit");
            }
            return bytes.clone();
        }
        if (gate != null) gate.lock();
        try {
            return readForeignStableBytes();
        } finally {
            if (gate != null) gate.unlock();
        }
    }

    private byte[] readForeignStableBytes() {
        MemorySegment operation = table.get(ADDRESS, 64);
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment written = arena.allocate(JAVA_LONG);
            MemorySegment required = arena.allocate(JAVA_LONG);
            int status = ProviderRuntime.callBytes(
                    operation, context, MemorySegment.NULL, 0L, written, required);
            ProviderRuntime.check(ProviderRuntime.normalizeStatus(status), "query lattice stable-byte size");
            if (written.get(JAVA_LONG, 0) != 0) throw new IllegalStateException("lattice size query wrote bytes");
            long size = required.get(JAVA_LONG, 0);
            if (size < 0 || size > MAX_BYTES) {
                throw new ProviderException(
                        ProviderException.Status.LIMIT_EXCEEDED,
                        "lattice stable bytes exceed the defensive limit");
            }
            MemorySegment output = arena.allocate(Math.max(size, 1), 1);
            written.set(JAVA_LONG, 0, -1);
            required.set(JAVA_LONG, 0, -1);
            status = ProviderRuntime.callBytes(operation, context, output, size, written, required);
            ProviderRuntime.check(ProviderRuntime.normalizeStatus(status), "read lattice stable bytes");
            long actual = written.get(JAVA_LONG, 0);
            long confirmed = required.get(JAVA_LONG, 0);
            if (actual != size || confirmed != size) {
                throw new IllegalStateException("lattice stable-byte size changed or the final buffer was incomplete");
            }
            return output.asSlice(0, size).toArray(java.lang.foreign.ValueLayout.JAVA_BYTE);
        }
    }

    void invalidate() {
        active = false;
        if (gate != null) gate.close();
    }

    private void requireActive() {
        if (!active) throw new IllegalStateException("lattice operand escaped its provider callback");
    }
}
