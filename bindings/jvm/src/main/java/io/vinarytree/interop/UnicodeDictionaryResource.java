package io.vinarytree.interop;

import static java.lang.foreign.MemoryLayout.PathElement.groupElement;
import static java.lang.foreign.ValueLayout.ADDRESS;
import static java.lang.foreign.ValueLayout.JAVA_BYTE;
import static java.lang.foreign.ValueLayout.JAVA_INT;
import static java.lang.foreign.ValueLayout.JAVA_LONG;

import java.lang.foreign.Arena;
import java.lang.foreign.FunctionDescriptor;
import java.lang.foreign.Linker;
import java.lang.foreign.MemorySegment;
import java.lang.invoke.MethodHandle;
import java.lang.invoke.MethodHandles;
import java.lang.invoke.MethodType;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Objects;
import java.util.OptionalLong;
import java.util.function.Consumer;
import java.util.function.Function;
import java.util.function.Supplier;

/**
 * FFM upcall adapter for a Java-defined Unicode dictionary provider.
 *
 * <p>The capture callback must return an immutable revision in constant time. Consumer calls are
 * serialized unless {@code parallelReentrant} is explicitly enabled.
 */
public final class UnicodeDictionaryResource implements DictionaryResource {
    private static final int UNIT_UNICODE = 2;
    private static final int VALUE_OPTIONAL_U64 = 1;
    private static final long FLAG_PARALLEL_REENTRANT = 1;
    private static final long FLAG_IMMUTABLE = 4;
    private static final byte[] DICTIONARY_ID = "vt.dictionary.v1".getBytes(StandardCharsets.US_ASCII);

    private static final Linker LINKER = Linker.nativeLinker();
    private static final Arena GLOBAL = Arena.global();

    private static final long OPTIONAL_VALUE =
            InteropLayouts.OPTIONAL_U64.byteOffset(groupElement("value"));
    private static final long OPTIONAL_PRESENT =
            InteropLayouts.OPTIONAL_U64.byteOffset(groupElement("has_value"));
    private static final long EDGE_LABEL =
            InteropLayouts.DICTIONARY_EDGE.byteOffset(groupElement("label"));
    private static final long EDGE_NODE =
            InteropLayouts.DICTIONARY_EDGE.byteOffset(groupElement("node"));

    private static final MemorySegment SNAPSHOT = upcall(
            "snapshot",
            MethodType.methodType(int.class, MemorySegment.class, MemorySegment.class),
            FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS));
    private static final MemorySegment ROOT = upcall(
            "root",
            MethodType.methodType(int.class, MemorySegment.class, MemorySegment.class),
            FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS));
    private static final MemorySegment LEN = upcall(
            "len",
            MethodType.methodType(
                    int.class, MemorySegment.class, MemorySegment.class, MemorySegment.class),
            FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS, ADDRESS));
    private static final MemorySegment IS_FINAL = upcall(
            "isFinal",
            MethodType.methodType(int.class, MemorySegment.class, long.class, MemorySegment.class),
            FunctionDescriptor.of(JAVA_INT, ADDRESS, JAVA_LONG, ADDRESS));
    private static final MemorySegment VALUE = upcall(
            "value",
            MethodType.methodType(int.class, MemorySegment.class, long.class, MemorySegment.class),
            FunctionDescriptor.of(JAVA_INT, ADDRESS, JAVA_LONG, ADDRESS));
    private static final MemorySegment TRANSITION = upcall(
            "transition",
            MethodType.methodType(
                    int.class,
                    MemorySegment.class,
                    long.class,
                    long.class,
                    MemorySegment.class,
                    MemorySegment.class),
            FunctionDescriptor.of(JAVA_INT, ADDRESS, JAVA_LONG, JAVA_LONG, ADDRESS, ADDRESS));
    private static final MemorySegment EDGES = upcall(
            "edges",
            MethodType.methodType(
                    int.class,
                    MemorySegment.class,
                    long.class,
                    long.class,
                    MemorySegment.class,
                    long.class,
                    MemorySegment.class,
                    MemorySegment.class),
            FunctionDescriptor.of(
                    JAVA_INT, ADDRESS, JAVA_LONG, JAVA_LONG, ADDRESS, JAVA_LONG, ADDRESS, ADDRESS));

    private static final MemorySegment MUTABLE_SERIAL = makeDictionaryVtable(false, false);
    private static final MemorySegment MUTABLE_PARALLEL = makeDictionaryVtable(false, true);
    private static final MemorySegment IMMUTABLE_SERIAL = makeDictionaryVtable(true, false);
    private static final MemorySegment IMMUTABLE_PARALLEL = makeDictionaryVtable(true, true);

    private final HostedResource hosted;

    /** Create a serialized provider over an O(1) immutable-revision capture. */
    public UnicodeDictionaryResource(Supplier<? extends UnicodeDictionarySnapshot> capture) {
        this(capture, false);
    }

    /** Create a provider, optionally allowing concurrent and reentrant calls. */
    public UnicodeDictionaryResource(
            Supplier<? extends UnicodeDictionarySnapshot> capture,
            boolean parallelReentrant) {
        Objects.requireNonNull(capture, "capture");
        DictionaryContext context = new DictionaryContext(
                () -> Objects.requireNonNull(capture.get(), "captured snapshot"),
                false,
                parallelReentrant,
                null);
        context.activate();
        hosted = new HostedResource(context);
    }

    /** Last exception converted to {@code VT_STATUS_PROVIDER_ERROR}, if any. */
    public Throwable lastCallbackError() {
        return hosted.lastCallbackError();
    }

    /** Borrow the two-word resource while keeping this owner strongly reachable. */
    @Override
    public MemorySegment resourceSegment() {
        return hosted.resourceSegment();
    }

    /** Run one synchronous operation under an independent native retain. */
    public <T> T withResourceSegment(Function<? super MemorySegment, ? extends T> operation) {
        return hosted.withResourceSegment(operation);
    }

    /** Run one void synchronous operation under an independent native retain. */
    public void withResourceSegment(Consumer<? super MemorySegment> operation) {
        hosted.withResourceSegment(operation);
    }

    /** Release this facade's retain; native consumers keep their own retains. */
    @Override
    public void close() {
        hosted.close();
    }

    private static int snapshot(MemorySegment raw, MemorySegment output) {
        if (ProviderRuntime.isNull(raw) || ProviderRuntime.isNull(output)) {
            return ProviderRuntime.NULL_POINTER;
        }
        DictionaryContext parent = context(raw);
        if (parent == null) return ProviderRuntime.CLOSED;
        try {
            UnicodeDictionarySnapshot captured = parent.snapshot();
            DictionaryContext child = new DictionaryContext(
                    () -> captured, true, parent.parallel, parent.fault());
            child.activate();
            try {
                ProviderRuntime.writeResource(output, child);
            } catch (Throwable failure) {
                child.release();
                throw failure;
            }
            return ProviderRuntime.OK;
        } catch (Throwable failure) {
            return ProviderRuntime.status(parent, failure);
        }
    }

    private static int root(MemorySegment raw, MemorySegment output) {
        if (ProviderRuntime.isNull(raw) || ProviderRuntime.isNull(output)) {
            return ProviderRuntime.NULL_POINTER;
        }
        DictionaryContext context = context(raw);
        if (context == null) return ProviderRuntime.CLOSED;
        try {
            long value = context.snapshot().root();
            ProviderRuntime.view(output, 8).set(JAVA_LONG, 0, value);
            return ProviderRuntime.OK;
        } catch (Throwable failure) {
            return ProviderRuntime.status(context, failure);
        }
    }

    private static int len(MemorySegment raw, MemorySegment output, MemorySegment known) {
        if (ProviderRuntime.isNull(raw)
                || ProviderRuntime.isNull(output)
                || ProviderRuntime.isNull(known)) return ProviderRuntime.NULL_POINTER;
        DictionaryContext context = context(raw);
        if (context == null) return ProviderRuntime.CLOSED;
        try {
            OptionalLong size = Objects.requireNonNull(context.snapshot().size(), "size");
            if (size.isPresent() && size.getAsLong() < 0) return ProviderRuntime.PROVIDER_ERROR;
            ProviderRuntime.view(output, 8).set(JAVA_LONG, 0, size.orElse(0));
            ProviderRuntime.view(known, 1).set(
                    JAVA_BYTE, 0, size.isPresent() ? (byte) 1 : 0);
            return ProviderRuntime.OK;
        } catch (Throwable failure) {
            return ProviderRuntime.status(context, failure);
        }
    }

    private static int isFinal(MemorySegment raw, long node, MemorySegment output) {
        if (ProviderRuntime.isNull(raw) || ProviderRuntime.isNull(output)) {
            return ProviderRuntime.NULL_POINTER;
        }
        DictionaryContext context = context(raw);
        if (context == null) return ProviderRuntime.CLOSED;
        try {
            boolean value = context.snapshot().isFinal(node);
            ProviderRuntime.view(output, 1).set(JAVA_BYTE, 0, value ? (byte) 1 : 0);
            return ProviderRuntime.OK;
        } catch (Throwable failure) {
            return ProviderRuntime.status(context, failure);
        }
    }

    private static int value(MemorySegment raw, long node, MemorySegment output) {
        if (ProviderRuntime.isNull(raw) || ProviderRuntime.isNull(output)) {
            return ProviderRuntime.NULL_POINTER;
        }
        DictionaryContext context = context(raw);
        if (context == null) return ProviderRuntime.CLOSED;
        try {
            OptionalLong value = Objects.requireNonNull(context.snapshot().value(node), "value");
            MemorySegment target = ProviderRuntime.view(output, InteropLayouts.OPTIONAL_U64.byteSize());
            target.fill((byte) 0);
            target.set(JAVA_LONG, OPTIONAL_VALUE, value.orElse(0));
            target.set(JAVA_BYTE, OPTIONAL_PRESENT, value.isPresent() ? (byte) 1 : 0);
            return ProviderRuntime.OK;
        } catch (Throwable failure) {
            return ProviderRuntime.status(context, failure);
        }
    }

    private static int transition(
            MemorySegment raw,
            long node,
            long label,
            MemorySegment child,
            MemorySegment found) {
        if (ProviderRuntime.isNull(raw)
                || ProviderRuntime.isNull(child)
                || ProviderRuntime.isNull(found)) return ProviderRuntime.NULL_POINTER;
        if (!isUnicodeScalar(label)) return ProviderRuntime.INVALID_ARGUMENT;
        DictionaryContext context = context(raw);
        if (context == null) return ProviderRuntime.CLOSED;
        try {
            OptionalLong result = Objects.requireNonNull(
                    context.snapshot().transition(node, Math.toIntExact(label)), "transition");
            ProviderRuntime.view(child, 8).set(JAVA_LONG, 0, result.orElse(0));
            ProviderRuntime.view(found, 1).set(
                    JAVA_BYTE, 0, result.isPresent() ? (byte) 1 : 0);
            return ProviderRuntime.OK;
        } catch (Throwable failure) {
            return ProviderRuntime.status(context, failure);
        }
    }

    private static int edges(
            MemorySegment raw,
            long node,
            long start,
            MemorySegment output,
            long capacity,
            MemorySegment written,
            MemorySegment total) {
        if (ProviderRuntime.isNull(raw)
                || ProviderRuntime.isNull(written)
                || ProviderRuntime.isNull(total)) return ProviderRuntime.NULL_POINTER;
        if (start < 0 || capacity < 0) return ProviderRuntime.LIMIT_EXCEEDED;
        if (capacity != 0 && ProviderRuntime.isNull(output)) return ProviderRuntime.NULL_POINTER;
        DictionaryContext context = context(raw);
        if (context == null) return ProviderRuntime.CLOSED;
        try {
            List<UnicodeDictionarySnapshot.Edge> values =
                    Objects.requireNonNull(context.snapshot().edges(node), "edges");
            long count = start >= values.size() ? 0 : Math.min(capacity, values.size() - start);
            int pageSize = Math.toIntExact(count);
            int first = count == 0 ? values.size() : Math.toIntExact(start);
            List<UnicodeDictionarySnapshot.Edge> page =
                    values.subList(first, Math.addExact(first, pageSize));
            for (UnicodeDictionarySnapshot.Edge edge : page) {
                if (edge == null || !isUnicodeScalar(Integer.toUnsignedLong(edge.scalar()))) {
                    return ProviderRuntime.PROVIDER_ERROR;
                }
            }
            MemorySegment target = count == 0
                    ? MemorySegment.NULL
                    : ProviderRuntime.view(
                            output, Math.multiplyExact(count, InteropLayouts.DICTIONARY_EDGE.byteSize()));
            int index = 0;
            for (UnicodeDictionarySnapshot.Edge edge : page) {
                MemorySegment slot = target.asSlice(
                        index * InteropLayouts.DICTIONARY_EDGE.byteSize(),
                        InteropLayouts.DICTIONARY_EDGE.byteSize());
                slot.set(JAVA_LONG, EDGE_LABEL, Integer.toUnsignedLong(edge.scalar()));
                slot.set(JAVA_LONG, EDGE_NODE, edge.node());
                index++;
            }
            ProviderRuntime.view(written, 8).set(JAVA_LONG, 0, count);
            ProviderRuntime.view(total, 8).set(JAVA_LONG, 0, values.size());
            return ProviderRuntime.OK;
        } catch (Throwable failure) {
            return ProviderRuntime.status(context, failure);
        }
    }

    private static boolean isUnicodeScalar(long value) {
        return Long.compareUnsigned(value, 0x10ffff) <= 0
                && !(value >= 0xd800 && value <= 0xdfff);
    }

    private static DictionaryContext context(MemorySegment raw) {
        return ProviderRuntime.context(raw, DictionaryContext.class);
    }

    private static MemorySegment upcall(
            String name, MethodType type, FunctionDescriptor descriptor) {
        try {
            MethodHandle handle = MethodHandles.lookup().findStatic(
                    UnicodeDictionaryResource.class, name, type);
            return LINKER.upcallStub(handle, descriptor, GLOBAL);
        } catch (ReflectiveOperationException failure) {
            throw new ExceptionInInitializerError(failure);
        }
    }

    private static MemorySegment makeDictionaryVtable(boolean immutable, boolean parallel) {
        MemorySegment table = GLOBAL.allocate(InteropLayouts.DICTIONARY_VTABLE);
        table.fill((byte) 0);
        table.set(JAVA_LONG, 0, InteropLayouts.DICTIONARY_VTABLE.byteSize());
        table.set(JAVA_INT, 8, InteropLayouts.DICTIONARY_INTERFACE_VERSION);
        table.set(JAVA_INT, 12, UNIT_UNICODE);
        table.set(JAVA_INT, 16, VALUE_OPTIONAL_U64);
        table.set(JAVA_LONG, 24,
                (immutable ? FLAG_IMMUTABLE : 0) | (parallel ? FLAG_PARALLEL_REENTRANT : 0));
        table.set(ADDRESS, 32, SNAPSHOT);
        table.set(ADDRESS, 40, ROOT);
        table.set(ADDRESS, 48, LEN);
        table.set(ADDRESS, 56, IS_FINAL);
        table.set(ADDRESS, 64, VALUE);
        table.set(ADDRESS, 72, TRANSITION);
        table.set(ADDRESS, 80, EDGES);
        return table;
    }

    private static MemorySegment dictionaryVtable(boolean immutable, boolean parallel) {
        if (immutable) return parallel ? IMMUTABLE_PARALLEL : IMMUTABLE_SERIAL;
        return parallel ? MUTABLE_PARALLEL : MUTABLE_SERIAL;
    }

    private static final class DictionaryContext extends ProviderRuntime.ProviderContext {
        private final Supplier<UnicodeDictionarySnapshot> capture;
        private final boolean immutable;
        private final boolean parallel;

        DictionaryContext(
                Supplier<UnicodeDictionarySnapshot> capture,
                boolean immutable,
                boolean parallel,
                ProviderRuntime.ProviderFault fault) {
            super(fault);
            this.capture = Objects.requireNonNull(capture, "capture");
            this.immutable = immutable;
            this.parallel = parallel;
        }

        UnicodeDictionarySnapshot snapshot() {
            return Objects.requireNonNull(capture.get(), "captured snapshot");
        }

        @Override
        int query(MemorySegment id, int minimumVersion, MemorySegment output) {
            if (Integer.compareUnsigned(minimumVersion, InteropLayouts.DICTIONARY_INTERFACE_VERSION) > 0
                    || !ProviderRuntime.idEquals(id, DICTIONARY_ID)) return ProviderRuntime.UNSUPPORTED;
            ProviderRuntime.view(output, 8).set(
                    ADDRESS, 0, dictionaryVtable(immutable, parallel));
            return ProviderRuntime.OK;
        }
    }
}
