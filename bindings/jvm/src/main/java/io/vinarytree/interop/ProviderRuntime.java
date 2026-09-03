package io.vinarytree.interop;

import static java.lang.foreign.ValueLayout.ADDRESS;
import static java.lang.foreign.ValueLayout.JAVA_BYTE;
import static java.lang.foreign.ValueLayout.JAVA_DOUBLE;
import static java.lang.foreign.ValueLayout.JAVA_INT;
import static java.lang.foreign.ValueLayout.JAVA_LONG;

import java.lang.foreign.Arena;
import java.lang.foreign.FunctionDescriptor;
import java.lang.foreign.Linker;
import java.lang.foreign.MemoryLayout;
import java.lang.foreign.MemorySegment;
import java.lang.invoke.MethodHandle;
import java.lang.invoke.MethodHandles;
import java.lang.invoke.MethodType;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.List;
import java.util.Objects;
import java.util.OptionalLong;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicLongArray;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.atomic.AtomicReferenceArray;
import java.util.concurrent.locks.ReentrantLock;

/** Internal, type-erased FFM callback runtime shared by every JVM provider facade. */
final class ProviderRuntime {
    static final int OK = 0;
    static final int END = 1;
    static final int INVALID_ARGUMENT = 2;
    static final int NULL_POINTER = 3;
    static final int UNSUPPORTED = 4;
    static final int IO_ERROR = 5;
    static final int CLOSED = 6;
    static final int LIMIT_EXCEEDED = 7;
    static final int PROVIDER_ERROR = 8;
    static final int INTERFACE_VERSION = 1;

    private static final byte[] WFST_ID = ascii("vt.scalar-wfst.1");
    private static final byte[] LATTICE_ID = ascii("vt.lattice.val.1");
    static final byte[] SEMIRING_ID = ascii("vt.semiring.val1");
    static final byte[] SEMIRING_DIVISION_ID = ascii("vt.semiring.div1");
    static final byte[] SEMIRING_STAR_ID = ascii("vt.semiring.str1");
    static final byte[] SEMIRING_NUMERIC_ID = ascii("vt.semiring.num1");
    static final byte[] SEMIRING_PROPERTIES_ID = ascii("vt.semiring.prp1");

    private static final Linker LINKER = Linker.nativeLinker();
    private static final Arena GLOBAL = Arena.global();
    private static final Registry REGISTRY = new Registry();
    private static final MethodHandle FOREIGN_QUERY = LINKER.downcallHandle(
            FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS, JAVA_INT, ADDRESS));
    private static final MethodHandle FOREIGN_BYTES = LINKER.downcallHandle(
            FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS, JAVA_LONG, ADDRESS, ADDRESS));

    static {
        if (ADDRESS.byteSize() != 8) {
            throw new ExceptionInInitializerError("vinary-tree interop requires a 64-bit JVM");
        }
    }

    private static final MemorySegment RETAIN = stub(
            "retain", MethodType.methodType(void.class, MemorySegment.class),
            FunctionDescriptor.ofVoid(ADDRESS));
    private static final MemorySegment RELEASE = stub(
            "release", MethodType.methodType(void.class, MemorySegment.class),
            FunctionDescriptor.ofVoid(ADDRESS));
    private static final MemorySegment QUERY = stub(
            "queryInterface",
            MethodType.methodType(int.class, MemorySegment.class, MemorySegment.class, int.class, MemorySegment.class),
            FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS, JAVA_INT, ADDRESS));
    private static final MemorySegment RESOURCE_VTABLE = resourceVtable();

    private static final MemorySegment WFST_SNAPSHOT = stub(
            "wfstSnapshot", addressAddress(), FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS));
    private static final MemorySegment WFST_START = stub(
            "wfstStart", addressAddress(), FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS));
    private static final MemorySegment WFST_NUM_STATES = stub(
            "wfstNumStates", addressAddressAddress(), FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS, ADDRESS));
    private static final MemorySegment WFST_STATE_INFO = stub(
            "wfstStateInfo",
            MethodType.methodType(int.class, MemorySegment.class, long.class, MemorySegment.class, MemorySegment.class, MemorySegment.class),
            FunctionDescriptor.of(JAVA_INT, ADDRESS, JAVA_LONG, ADDRESS, ADDRESS, ADDRESS));
    private static final MemorySegment WFST_STATE_ARCS = stub(
            "wfstStateArcs",
            MethodType.methodType(int.class, MemorySegment.class, long.class, long.class, MemorySegment.class, long.class, MemorySegment.class, MemorySegment.class),
            FunctionDescriptor.of(JAVA_INT, ADDRESS, JAVA_LONG, JAVA_LONG, ADDRESS, JAVA_LONG, ADDRESS, ADDRESS));

    private static final MemorySegment LATTICE_JOIN = stub(
            "latticeJoin", addressAddressAddress(), FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS, ADDRESS));
    private static final MemorySegment LATTICE_MEET = stub(
            "latticeMeet", addressAddressAddress(), FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS, ADDRESS));
    private static final MemorySegment LATTICE_EQUAL = stub(
            "latticeEqual", addressAddressAddress(), FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS, ADDRESS));
    private static final MemorySegment LATTICE_STABLE = stub(
            "latticeStableBytes", bytesMethodType(), bytesDescriptor());
    private static final MemorySegment LATTICE_DIAGNOSTIC = stub(
            "latticeDiagnostic", bytesMethodType(), bytesDescriptor());
    private static final MemorySegment LATTICE_JOIN_MANY = stub(
            "latticeJoinMany", foldMethodType(), foldDescriptor());
    private static final MemorySegment LATTICE_MEET_MANY = stub(
            "latticeMeetMany", foldMethodType(), foldDescriptor());

    private ProviderRuntime() {}

    static ProviderContext wfst(ScalarWfstProvider provider, ScalarWfstOptions options) {
        WfstContext context = new WfstContext(provider, options);
        context.activate();
        return context;
    }

    static ProviderContext lattice(LatticeProvider provider, LatticeOptions options) {
        LatticeContext context = new LatticeContext(provider, options);
        context.activate();
        return context;
    }

    static int callQuery(
            MemorySegment function,
            MemorySegment context,
            MemorySegment interfaceId,
            int minimumVersion,
            MemorySegment output) {
        try {
            if (isNull(function)) throw new ProviderStatusFailure(PROVIDER_ERROR, "native callback is null");
            return (int) FOREIGN_QUERY.invokeExact(function, context, interfaceId, minimumVersion, output);
        } catch (ProviderStatusFailure failure) {
            throw failure;
        } catch (Throwable failure) {
            throw new ProviderStatusFailure(PROVIDER_ERROR, "native callback failed", failure);
        }
    }

    static int callBytes(
            MemorySegment function,
            MemorySegment context,
            MemorySegment output,
            long capacity,
            MemorySegment written,
            MemorySegment required) {
        try {
            if (isNull(function)) throw new ProviderStatusFailure(PROVIDER_ERROR, "native callback is null");
            return (int) FOREIGN_BYTES.invokeExact(function, context, output, capacity, written, required);
        } catch (ProviderStatusFailure failure) {
            throw failure;
        } catch (Throwable failure) {
            throw new ProviderStatusFailure(PROVIDER_ERROR, "native callback failed", failure);
        }
    }

    static void check(int status, String operation) {
        if (status == OK) return;
        int portable = switch (status) {
            case INVALID_ARGUMENT, UNSUPPORTED, IO_ERROR, CLOSED, LIMIT_EXCEEDED, PROVIDER_ERROR -> status;
            default -> PROVIDER_ERROR;
        };
        throw new ProviderStatusFailure(portable, operation + " failed with status " + status);
    }

    static boolean idEquals(MemorySegment pointer, byte[] expected) {
        if (isNull(pointer)) return false;
        MemorySegment actual = pointer.reinterpret(16);
        for (int index = 0; index < 16; index++) {
            if (actual.get(JAVA_BYTE, index) != expected[index]) return false;
        }
        return true;
    }

    static int writeBytes(byte[] bytes, MemorySegment output, long capacity, MemorySegment written, MemorySegment required) {
        if (isNull(written) || isNull(required)) return NULL_POINTER;
        if (capacity < 0) return LIMIT_EXCEEDED;
        if (capacity != 0 && isNull(output)) return NULL_POINTER;
        long count = Math.min(capacity, bytes.length);
        if (count != 0) MemorySegment.copy(bytes, 0, output.reinterpret(count), JAVA_BYTE, 0, (int) count);
        required.reinterpret(8).set(JAVA_LONG, 0, bytes.length);
        written.reinterpret(8).set(JAVA_LONG, 0, count);
        return OK;
    }

    static int status(Throwable failure) {
        if (failure instanceof OutOfMemoryError) return LIMIT_EXCEEDED;
        if (failure instanceof ProviderStatusFailure status) return status.status;
        if (failure instanceof ProviderException status) return status.status().wireValue();
        return PROVIDER_ERROR;
    }

    static int status(ProviderContext context, Throwable failure) {
        context.record(failure);
        return status(failure);
    }

    static int status(MemorySegment raw, Throwable failure) {
        ProviderContext context = REGISTRY.get(raw);
        if (context != null) context.record(failure);
        return status(failure);
    }

    static int normalizeStatus(int status) {
        return status >= OK && status <= 9 ? status : PROVIDER_ERROR;
    }

    static MemorySegment view(MemorySegment pointer, long bytes) {
        return pointer.reinterpret(bytes);
    }

    static boolean isNull(MemorySegment segment) {
        return segment == null || segment.address() == 0;
    }

    private static void retain(MemorySegment raw) {
        ProviderContext context = REGISTRY.get(raw);
        if (context == null) return;
        try {
            context.retain();
        } catch (Throwable failure) {
            context.record(failure);
        }
    }

    private static void release(MemorySegment raw) {
        ProviderContext context = REGISTRY.get(raw);
        if (context == null) return;
        try {
            context.release();
        } catch (Throwable failure) {
            context.record(failure);
        }
    }

    private static int queryInterface(MemorySegment raw, MemorySegment id, int minimumVersion, MemorySegment output) {
        if (isNull(raw) || isNull(id) || isNull(output)) return NULL_POINTER;
        try {
            ProviderContext context = REGISTRY.get(raw);
            return context == null ? INVALID_ARGUMENT : context.query(id, minimumVersion, output);
        } catch (Throwable failure) {
            return status(raw, failure);
        }
    }

    private static int wfstSnapshot(MemorySegment raw, MemorySegment output) {
        if (isNull(raw) || isNull(output)) return NULL_POINTER;
        WfstContext context = context(raw, WfstContext.class);
        if (context == null) return INVALID_ARGUMENT;
        try {
            context.retain();
            try {
                writeResource(output, context);
            } catch (Throwable failure) {
                context.release();
                throw failure;
            }
            return OK;
        } catch (Throwable failure) {
            return status(raw, failure);
        }
    }

    private static int wfstStart(MemorySegment raw, MemorySegment output) {
        if (isNull(raw) || isNull(output)) return NULL_POINTER;
        try {
            WfstContext context = context(raw, WfstContext.class);
            if (context == null) return INVALID_ARGUMENT;
            long value = context.provider.startState();
            view(output, 8).set(JAVA_LONG, 0, value);
            return OK;
        } catch (Throwable failure) {
            return status(raw, failure);
        }
    }

    private static int wfstNumStates(MemorySegment raw, MemorySegment count, MemorySegment known) {
        if (isNull(raw) || isNull(count) || isNull(known)) return NULL_POINTER;
        try {
            WfstContext context = context(raw, WfstContext.class);
            if (context == null) return INVALID_ARGUMENT;
            OptionalLong value = Objects.requireNonNull(context.provider.stateCount(), "stateCount");
            if (value.isPresent() && value.getAsLong() < 0) return PROVIDER_ERROR;
            view(count, 8).set(JAVA_LONG, 0, value.orElse(0));
            view(known, 1).set(JAVA_BYTE, 0, value.isPresent() ? (byte) 1 : 0);
            return OK;
        } catch (Throwable failure) {
            return status(raw, failure);
        }
    }

    private static int wfstStateInfo(
            MemorySegment raw,
            long state,
            MemorySegment valid,
            MemorySegment isFinal,
            MemorySegment finalWeight) {
        if (isNull(raw) || isNull(valid) || isNull(isFinal) || isNull(finalWeight)) return NULL_POINTER;
        try {
            WfstContext context = context(raw, WfstContext.class);
            if (context == null) return INVALID_ARGUMENT;
            ScalarWfstStateInfo value = Objects.requireNonNull(context.provider.stateInfo(state), "stateInfo");
            if ((!value.valid() && value.isFinal())
                    || (value.isFinal()
                            && !context.options.weightDomain().isValid(value.finalWeight()))) {
                return PROVIDER_ERROR;
            }
            view(valid, 1).set(JAVA_BYTE, 0, value.valid() ? (byte) 1 : 0);
            view(isFinal, 1).set(JAVA_BYTE, 0, value.isFinal() ? (byte) 1 : 0);
            view(finalWeight, 8).set(JAVA_DOUBLE, 0, value.finalWeight());
            return OK;
        } catch (Throwable failure) {
            return status(raw, failure);
        }
    }

    private static int wfstStateArcs(
            MemorySegment raw,
            long state,
            long start,
            MemorySegment output,
            long capacity,
            MemorySegment written,
            MemorySegment total) {
        if (isNull(raw) || isNull(written) || isNull(total)) return NULL_POINTER;
        if (start < 0 || capacity < 0) return LIMIT_EXCEEDED;
        if (capacity != 0 && isNull(output)) return NULL_POINTER;
        try {
            WfstContext context = context(raw, WfstContext.class);
            if (context == null) return INVALID_ARGUMENT;
            int boundedCapacity = Math.toIntExact(Math.min(capacity, Integer.MAX_VALUE));
            ScalarWfstArcPage page = Objects.requireNonNull(
                    context.provider.stateArcsPage(state, start, boundedCapacity), "stateArcsPage");
            List<ScalarWfstArc> pageValues = Objects.requireNonNull(page.arcs(), "stateArcsPage.arcs");
            long expected = start >= page.total()
                    ? 0
                    : Math.min(capacity, Math.subtractExact(page.total(), start));
            if (pageValues.size() != expected) return PROVIDER_ERROR;
            for (ScalarWfstArc arc : pageValues) {
                if (arc == null || !validArc(context.options, arc)) return PROVIDER_ERROR;
            }
            long count = pageValues.size();
            MemorySegment target = count == 0
                    ? MemorySegment.NULL
                    : view(output, Math.multiplyExact(count, 40));
            int index = 0;
            for (ScalarWfstArc arc : pageValues) {
                MemorySegment destination = target.asSlice(index * 40L, 40);
                destination.fill((byte) 0);
                destination.set(JAVA_LONG, 0, arc.inputLabel().orElse(0));
                destination.set(JAVA_LONG, 8, arc.outputLabel().orElse(0));
                destination.set(JAVA_LONG, 16, arc.targetState());
                destination.set(JAVA_DOUBLE, 24, arc.weight());
                destination.set(JAVA_BYTE, 32, arc.inputLabel().isPresent() ? (byte) 1 : 0);
                destination.set(JAVA_BYTE, 33, arc.outputLabel().isPresent() ? (byte) 1 : 0);
                index++;
            }
            view(total, 8).set(JAVA_LONG, 0, page.total());
            view(written, 8).set(JAVA_LONG, 0, count);
            return OK;
        } catch (Throwable failure) {
            return status(raw, failure);
        }
    }

    private static int latticeJoin(MemorySegment raw, MemorySegment other, MemorySegment output) {
        return latticeBinary(raw, other, output, true);
    }

    private static int latticeMeet(MemorySegment raw, MemorySegment other, MemorySegment output) {
        return latticeBinary(raw, other, output, false);
    }

    private static int latticeBinary(MemorySegment raw, MemorySegment other, MemorySegment output, boolean join) {
        if (isNull(raw) || isNull(other) || isNull(output)) return NULL_POINTER;
        try {
            LatticeContext context = context(raw, LatticeContext.class);
            if (context == null) return INVALID_ARGUMENT;
            OperandResult resolved = operand(context, other);
            if (resolved.status != OK) return resolved.status;
            LatticeProvider result;
            try {
                result = join
                        ? context.provider.join(resolved.operand)
                        : context.provider.meet(resolved.operand);
            } finally {
                resolved.operand.invalidate();
            }
            if (result == null) return PROVIDER_ERROR;
            LatticeContext next = new LatticeContext(result, context.options);
            next.activate();
            try {
                writeResource(output, next);
            } catch (Throwable failure) {
                next.release();
                throw failure;
            }
            return OK;
        } catch (Throwable failure) {
            return status(raw, failure);
        }
    }

    private static int latticeEqual(MemorySegment raw, MemorySegment other, MemorySegment output) {
        if (isNull(raw) || isNull(other) || isNull(output)) return NULL_POINTER;
        try {
            LatticeContext context = context(raw, LatticeContext.class);
            if (context == null) return INVALID_ARGUMENT;
            OperandResult resolved = operand(context, other);
            if (resolved.status != OK) return resolved.status;
            boolean result;
            try {
                result = context.provider.equalsValue(resolved.operand);
            } finally {
                resolved.operand.invalidate();
            }
            view(output, 1).set(JAVA_BYTE, 0, result ? (byte) 1 : 0);
            return OK;
        } catch (Throwable failure) {
            return status(raw, failure);
        }
    }

    private static int latticeStableBytes(
            MemorySegment raw, MemorySegment output, long capacity, MemorySegment written, MemorySegment required) {
        if (isNull(raw) || isNull(written) || isNull(required)) return NULL_POINTER;
        if (capacity < 0) return LIMIT_EXCEEDED;
        if (capacity != 0 && isNull(output)) return NULL_POINTER;
        try {
            LatticeContext context = context(raw, LatticeContext.class);
            if (context == null) return INVALID_ARGUMENT;
            if (!(context.provider instanceof StableLatticeProvider stable)) return UNSUPPORTED;
            return writeBytes(Objects.requireNonNull(stable.stableBytes(), "stableBytes"), output, capacity, written, required);
        } catch (Throwable failure) {
            return status(raw, failure);
        }
    }

    private static int latticeDiagnostic(
            MemorySegment raw, MemorySegment output, long capacity, MemorySegment written, MemorySegment required) {
        if (isNull(raw) || isNull(written) || isNull(required)) return NULL_POINTER;
        if (capacity < 0) return LIMIT_EXCEEDED;
        if (capacity != 0 && isNull(output)) return NULL_POINTER;
        try {
            LatticeContext context = context(raw, LatticeContext.class);
            if (context == null) return INVALID_ARGUMENT;
            byte[] bytes = Objects.requireNonNull(context.provider.diagnostic(), "diagnostic")
                    .getBytes(StandardCharsets.UTF_8);
            return writeBytes(bytes, output, capacity, written, required);
        } catch (Throwable failure) {
            return status(raw, failure);
        }
    }

    private static int latticeJoinMany(
            MemorySegment raw, MemorySegment others, long count, MemorySegment output) {
        return latticeFold(raw, others, count, output, true);
    }

    private static int latticeMeetMany(
            MemorySegment raw, MemorySegment others, long count, MemorySegment output) {
        return latticeFold(raw, others, count, output, false);
    }

    private static int latticeFold(
            MemorySegment raw, MemorySegment others, long count, MemorySegment output, boolean join) {
        if (isNull(raw) || isNull(output)) return NULL_POINTER;
        if (count < 0 || count > 256) return LIMIT_EXCEEDED;
        if (count != 0 && isNull(others)) return NULL_POINTER;
        try {
            LatticeContext context = context(raw, LatticeContext.class);
            if (context == null) return INVALID_ARGUMENT;
            if (count == 0) {
                context.retain();
                try {
                    writeResource(output, context);
                } catch (Throwable failure) {
                    context.release();
                    throw failure;
                }
                return OK;
            }
            MemorySegment values = view(others, Math.multiplyExact(count, 16));
            OperandResult first = operand(context, values.asSlice(0, 16));
            if (first.status != OK) return first.status;
            LatticeProvider accumulator;
            try {
                accumulator = join
                        ? context.provider.join(first.operand)
                        : context.provider.meet(first.operand);
            } finally {
                first.operand.invalidate();
            }
            if (accumulator == null) return PROVIDER_ERROR;
            for (long index = 1; index < count; index++) {
                OperandResult next = operand(context, values.asSlice(index * 16, 16));
                if (next.status != OK) return next.status;
                try {
                    accumulator = join ? accumulator.join(next.operand) : accumulator.meet(next.operand);
                } finally {
                    next.operand.invalidate();
                }
                if (accumulator == null) return PROVIDER_ERROR;
            }
            LatticeContext result = new LatticeContext(accumulator, context.options);
            result.activate();
            try {
                writeResource(output, result);
            } catch (Throwable failure) {
                result.release();
                throw failure;
            }
            return OK;
        } catch (Throwable failure) {
            return status(raw, failure);
        }
    }

    private static OperandResult operand(LatticeContext context, MemorySegment raw) {
        if (isNull(raw)) return new OperandResult(NULL_POINTER, null);
        MemorySegment resource = view(raw, 16);
        MemorySegment resourceContext = resource.get(ADDRESS, 0);
        MemorySegment baseAddress = resource.get(ADDRESS, 8);
        if (isNull(resourceContext) || isNull(baseAddress)) return new OperandResult(NULL_POINTER, null);
        MemorySegment base = view(baseAddress, InteropLayouts.RESOURCE_VTABLE.byteSize());
        if (base.get(JAVA_LONG, 0) < InteropLayouts.RESOURCE_VTABLE.byteSize()
                || base.get(JAVA_INT, 8) != InteropLayouts.ABI_VERSION
                || base.get(JAVA_INT, 12) != 0
                || isNull(base.get(ADDRESS, 16))
                || isNull(base.get(ADDRESS, 24))
                || isNull(base.get(ADDRESS, 32))) return new OperandResult(INVALID_ARGUMENT, null);
        if (baseAddress.address() == RESOURCE_VTABLE.address()) {
            LatticeContext local = context(resourceContext, LatticeContext.class);
            if (local == null || !domainEquals(local.table.asSlice(24, 16), context.domainId)) {
                return new OperandResult(INVALID_ARGUMENT, null);
            }
            return new OperandResult(
                    OK, new LatticeOperand(resourceContext, local.table, local.provider, null));
        }
        ForeignGateLease negotiationGate = ForeignGates.acquire(resourceContext, baseAddress);
        boolean transferred = false;
        negotiationGate.lock();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment id = arena.allocateFrom(JAVA_BYTE, LATTICE_ID);
            MemorySegment output = arena.allocate(ADDRESS);
            output.set(ADDRESS, 0, MemorySegment.NULL);
            int status = normalizeStatus(callQuery(
                    base.get(ADDRESS, 32), resourceContext, id, INTERFACE_VERSION, output));
            if (status != OK) return new OperandResult(status == UNSUPPORTED ? INVALID_ARGUMENT : status, null);
            MemorySegment address = output.get(ADDRESS, 0);
            if (isNull(address)) return new OperandResult(PROVIDER_ERROR, null);
            MemorySegment table = view(address, InteropLayouts.LATTICE_VTABLE.byteSize());
            long flags = table.get(JAVA_LONG, 16);
            if (table.get(JAVA_LONG, 0) < InteropLayouts.LATTICE_VTABLE.byteSize()
                    || Integer.compareUnsigned(table.get(JAVA_INT, 8), INTERFACE_VERSION) < 0
                    || table.get(JAVA_INT, 12) != 0
                    || isNull(table.get(ADDRESS, 40))
                    || isNull(table.get(ADDRESS, 48))
                    || isNull(table.get(ADDRESS, 56))
                    || (flags & LatticeOptions.THREAD_BOUND) != 0
                            && (flags & LatticeOptions.PARALLEL_REENTRANT) != 0
                    || (flags & 4) != 0 && isNull(table.get(ADDRESS, 64))
                    || (flags & 8) != 0
                            && (isNull(table.get(ADDRESS, 80)) || isNull(table.get(ADDRESS, 88)))
                    || !domainEquals(table.asSlice(24, 16), context.domainId)) {
                return new OperandResult(INVALID_ARGUMENT, null);
            }
            if ((flags & 4) == 0 || isNull(table.get(ADDRESS, 64))) {
                return new OperandResult(UNSUPPORTED, null);
            }
            ForeignGateLease gate = (flags & LatticeOptions.PARALLEL_REENTRANT) == 0
                    ? negotiationGate
                    : null;
            transferred = gate != null;
            return new OperandResult(OK, new LatticeOperand(resourceContext, table, null, gate));
        } finally {
            negotiationGate.unlock();
            if (!transferred) negotiationGate.close();
        }
    }

    private static boolean domainEquals(MemorySegment actual, byte[] expected) {
        for (int index = 0; index < 16; index++) {
            if (actual.get(JAVA_BYTE, index) != expected[index]) return false;
        }
        return true;
    }

    private static boolean validArc(ScalarWfstOptions options, ScalarWfstArc arc) {
        return options.weightDomain().isValid(arc.weight())
                && (arc.inputLabel().isEmpty()
                        || validLabel(options.unitDomain(), arc.inputLabel().getAsLong()))
                && (arc.outputLabel().isEmpty()
                        || validLabel(options.unitDomain(), arc.outputLabel().getAsLong()));
    }

    private static boolean validLabel(DictionaryUnitDomain domain, long label) {
        return switch (domain) {
            case BYTE -> Long.compareUnsigned(label, 255) <= 0;
            case UNICODE_SCALAR -> Long.compareUnsigned(label, 0x10ffff) <= 0
                    && !(label >= 0xd800 && label <= 0xdfff);
            case U64 -> true;
        };
    }

    static void writeResource(MemorySegment output, ProviderContext context) {
        MemorySegment destination = view(output, 16);
        destination.set(ADDRESS, 0, context.address());
        destination.set(ADDRESS, 8, RESOURCE_VTABLE);
    }

    private static MemorySegment resourceVtable() {
        MemorySegment table = GLOBAL.allocate(InteropLayouts.RESOURCE_VTABLE);
        table.fill((byte) 0);
        table.set(JAVA_LONG, 0, InteropLayouts.RESOURCE_VTABLE.byteSize());
        table.set(JAVA_INT, 8, InteropLayouts.ABI_VERSION);
        table.set(ADDRESS, 16, RETAIN);
        table.set(ADDRESS, 24, RELEASE);
        table.set(ADDRESS, 32, QUERY);
        return table;
    }

    private static MemorySegment stub(String name, MethodType type, FunctionDescriptor descriptor) {
        try {
            MethodHandle target = MethodHandles.lookup().findStatic(ProviderRuntime.class, name, type);
            return LINKER.upcallStub(target, descriptor, GLOBAL);
        } catch (ReflectiveOperationException failure) {
            throw new ExceptionInInitializerError(failure);
        }
    }

    private static MethodType addressAddress() {
        return MethodType.methodType(int.class, MemorySegment.class, MemorySegment.class);
    }

    private static MethodType addressAddressAddress() {
        return MethodType.methodType(int.class, MemorySegment.class, MemorySegment.class, MemorySegment.class);
    }

    private static MethodType bytesMethodType() {
        return MethodType.methodType(
                int.class, MemorySegment.class, MemorySegment.class, long.class, MemorySegment.class, MemorySegment.class);
    }

    private static FunctionDescriptor bytesDescriptor() {
        return FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS, JAVA_LONG, ADDRESS, ADDRESS);
    }

    private static MethodType foldMethodType() {
        return MethodType.methodType(
                int.class, MemorySegment.class, MemorySegment.class, long.class, MemorySegment.class);
    }

    private static FunctionDescriptor foldDescriptor() {
        return FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS, JAVA_LONG, ADDRESS);
    }

    private static byte[] ascii(String value) {
        byte[] bytes = value.getBytes(StandardCharsets.US_ASCII);
        if (bytes.length != 16) throw new ExceptionInInitializerError("interface ID must contain 16 bytes");
        return bytes;
    }

    @SuppressWarnings("unchecked")
    static <T extends ProviderContext> T context(MemorySegment raw, Class<T> type) {
        ProviderContext context = REGISTRY.get(raw);
        return type.isInstance(context) ? (T) context : null;
    }

    abstract static class ProviderContext {
        final Arena arena = Arena.ofShared();
        private final AtomicLong retains = new AtomicLong(1);
        private final ProviderFault fault;
        private volatile long identifier;
        private volatile MemorySegment resource;

        ProviderContext() {
            this(null);
        }

        ProviderContext(ProviderFault sharedFault) {
            fault = sharedFault == null ? new ProviderFault() : sharedFault;
        }

        final MemorySegment address() {
            return MemorySegment.ofAddress(identifier);
        }

        final long identifier() {
            return identifier;
        }

        final MemorySegment resource() {
            MemorySegment current = resource;
            if (retains.get() == 0 || current == null) throw new IllegalStateException("hosted resource is closed");
            return current;
        }

        final synchronized void activate() {
            if (resource != null || identifier != 0) throw new IllegalStateException("provider is already active");
            Registry.Reservation reservation = null;
            boolean published = false;
            try {
                reservation = REGISTRY.reserve();
                MemorySegment nextResource = arena.allocate(InteropLayouts.RESOURCE);
                long nextIdentifier = reservation.handle();
                nextResource.set(ADDRESS, 0, MemorySegment.ofAddress(nextIdentifier));
                nextResource.set(ADDRESS, 8, RESOURCE_VTABLE);
                identifier = nextIdentifier;
                resource = nextResource;
                onActivated(nextIdentifier);
                REGISTRY.publish(reservation, this);
                published = true;
            } catch (Throwable failure) {
                if (reservation != null) {
                    if (published) REGISTRY.remove(reservation.handle(), this);
                    else REGISTRY.cancel(reservation);
                }
                resource = null;
                identifier = 0;
                closeArena();
                throw failure;
            }
        }

        final void retain() {
            long observed = retains.get();
            while (observed != 0) {
                if (observed == Long.MAX_VALUE) return;
                if (retains.compareAndSet(observed, observed + 1)) return;
                observed = retains.get();
            }
            throw new IllegalStateException("provider is closed");
        }

        final void release() {
            long observed = retains.get();
            while (observed != 0) {
                if (observed == Long.MAX_VALUE) return;
                if (retains.compareAndSet(observed, observed - 1)) {
                    if (observed == 1) {
                        try {
                            REGISTRY.remove(identifier, this);
                        } finally {
                            closeArena();
                        }
                    }
                    return;
                }
                observed = retains.get();
            }
        }

        final void abortConstruction() {
            if (resource == null && identifier == 0) closeArena();
        }

        void onActivated(long handle) {}

        final void record(Throwable failure) {
            fault.error.set(failure);
        }

        final ProviderFault fault() {
            return fault;
        }

        private void closeArena() {
            try {
                arena.close();
            } catch (Throwable failure) {
                record(failure);
            }
        }

        abstract int query(MemorySegment id, int minimumVersion, MemorySegment output);
    }

    private static final class WfstContext extends ProviderContext {
        final ScalarWfstProvider provider;
        final ScalarWfstOptions options;
        final MemorySegment table;

        WfstContext(ScalarWfstProvider provider, ScalarWfstOptions options) {
            this.provider = Objects.requireNonNull(provider, "provider");
            this.options = new ScalarWfstOptions(
                    options.unitDomain(), options.weightDomain(), options.flags() | ScalarWfstOptions.IMMUTABLE);
            MemorySegment allocated;
            try {
                allocated = arena.allocate(InteropLayouts.WFST_VTABLE);
                allocated.fill((byte) 0);
                allocated.set(JAVA_LONG, 0, InteropLayouts.WFST_VTABLE.byteSize());
                allocated.set(JAVA_INT, 8, INTERFACE_VERSION);
                allocated.set(JAVA_INT, 12, options.unitDomain().wireValue);
                allocated.set(JAVA_INT, 16, options.weightDomain().wireValue());
                allocated.set(JAVA_LONG, 24, this.options.flags());
                allocated.set(ADDRESS, 32, WFST_SNAPSHOT);
                allocated.set(ADDRESS, 40, WFST_START);
                allocated.set(ADDRESS, 48, WFST_NUM_STATES);
                allocated.set(ADDRESS, 56, WFST_STATE_INFO);
                allocated.set(ADDRESS, 64, WFST_STATE_ARCS);
            } catch (Throwable failure) {
                abortConstruction();
                throw failure;
            }
            table = allocated;
        }

        @Override
        int query(MemorySegment id, int minimumVersion, MemorySegment output) {
            if (Integer.compareUnsigned(minimumVersion, INTERFACE_VERSION) > 0 || !idEquals(id, WFST_ID)) {
                return UNSUPPORTED;
            }
            view(output, 8).set(ADDRESS, 0, table);
            return OK;
        }
    }

    private static final class LatticeContext extends ProviderContext {
        final LatticeProvider provider;
        final LatticeOptions options;
        final byte[] domainId;
        final MemorySegment table;

        LatticeContext(LatticeProvider provider, LatticeOptions options) {
            this.provider = Objects.requireNonNull(provider, "provider");
            this.options = new LatticeOptions(options.domainId(), options.flags());
            domainId = options.domainId().bytes();
            MemorySegment allocated;
            try {
                allocated = arena.allocate(InteropLayouts.LATTICE_VTABLE);
                allocated.fill((byte) 0);
                allocated.set(JAVA_LONG, 0, InteropLayouts.LATTICE_VTABLE.byteSize());
                allocated.set(JAVA_INT, 8, INTERFACE_VERSION);
                long flags = options.flags() | 8 | (provider instanceof StableLatticeProvider ? 4 : 0);
                allocated.set(JAVA_LONG, 16, flags);
                MemorySegment.copy(domainId, 0, allocated.asSlice(24, 16), JAVA_BYTE, 0, 16);
                allocated.set(ADDRESS, 40, LATTICE_JOIN);
                allocated.set(ADDRESS, 48, LATTICE_MEET);
                allocated.set(ADDRESS, 56, LATTICE_EQUAL);
                allocated.set(
                        ADDRESS,
                        64,
                        provider instanceof StableLatticeProvider ? LATTICE_STABLE : MemorySegment.NULL);
                allocated.set(ADDRESS, 72, LATTICE_DIAGNOSTIC);
                allocated.set(ADDRESS, 80, LATTICE_JOIN_MANY);
                allocated.set(ADDRESS, 88, LATTICE_MEET_MANY);
            } catch (Throwable failure) {
                abortConstruction();
                throw failure;
            }
            table = allocated;
        }

        @Override
        int query(MemorySegment id, int minimumVersion, MemorySegment output) {
            if (Integer.compareUnsigned(minimumVersion, INTERFACE_VERSION) > 0 || !idEquals(id, LATTICE_ID)) {
                return UNSUPPORTED;
            }
            view(output, 8).set(ADDRESS, 0, table);
            return OK;
        }
    }

    private record OperandResult(int status, LatticeOperand operand) {}

    /** An already-validated status transported only between internal callback adapters. */
    private static final class ProviderStatusFailure extends RuntimeException {
        private static final long serialVersionUID = 1L;
        final int status;

        ProviderStatusFailure(int status, String message) {
            super(message);
            this.status = status;
        }

        ProviderStatusFailure(int status, String message, Throwable cause) {
            super(message, cause);
            this.status = status;
        }
    }

    /** Lifecycle-bounded gates serialize exactly one foreign provider without unrelated collisions. */
    private static final class ForeignGates {
        private static final ConcurrentHashMap<ForeignGateKey, ForeignGate> GATES =
                new ConcurrentHashMap<>();

        static ForeignGateLease acquire(MemorySegment context, MemorySegment vtable) {
            ForeignGateKey key = new ForeignGateKey(context.address(), vtable.address());
            ForeignGate gate = GATES.compute(key, (ignored, current) -> {
                ForeignGate result = current == null ? new ForeignGate() : current;
                result.leases++;
                return result;
            });
            return new ForeignGateLease(key, gate);
        }

        static void release(ForeignGateKey key, ForeignGate gate) {
            GATES.computeIfPresent(key, (ignored, current) -> {
                if (current != gate) return current;
                current.leases--;
                if (current.leases < 0) throw new IllegalStateException("foreign gate lease underflow");
                return current.leases == 0 ? null : current;
            });
        }

        private ForeignGates() {}
    }

    private record ForeignGateKey(long context, long vtable) {}

    private static final class ForeignGate {
        final ReentrantLock lock = new ReentrantLock();
        int leases;
    }

    /** One scoped reference to a foreign provider's exact serial gate. */
    static final class ForeignGateLease implements AutoCloseable {
        private final ForeignGateKey key;
        private final ForeignGate gate;
        private final AtomicInteger open = new AtomicInteger(1);

        ForeignGateLease(ForeignGateKey key, ForeignGate gate) {
            this.key = key;
            this.gate = gate;
        }

        void lock() {
            if (open.get() == 0) throw new IllegalStateException("foreign gate lease is closed");
            gate.lock.lock();
        }

        void unlock() {
            gate.lock.unlock();
        }

        @Override
        public void close() {
            if (open.compareAndSet(1, 0)) ForeignGates.release(key, gate);
        }
    }

    static final class ProviderFault {
        final AtomicReference<Throwable> error = new AtomicReference<>();
    }

    /** Lock-free reads over recyclable generation-stamped opaque handles. */
    private static final class Registry {
        private static final int SHIFT = 10;
        private static final int SIZE = 1 << SHIFT;
        private static final int MASK = SIZE - 1;
        /* Keep fabricated void* handles below 2^47 for x86-64 canonical-address portability. */
        private static final long MAX_GENERATION = 0x7fffL;
        private final AtomicInteger nextIndex = new AtomicInteger();
        private final ConcurrentLinkedQueue<Integer> free = new ConcurrentLinkedQueue<>();
        private volatile AtomicReferenceArray<ProviderContext>[] contexts = contextChunks(1);
        private volatile AtomicLongArray[] generations = generationChunks(1);

        Reservation reserve() {
            while (true) {
                Integer reclaimed = free.poll();
                int index = reclaimed == null ? nextIndex.getAndIncrement() : reclaimed;
                if (index < 0 || index == Integer.MAX_VALUE) {
                    throw new IllegalStateException("provider registry exhausted");
                }
                int chunkIndex = index >>> SHIFT;
                ensure(chunkIndex);
                AtomicLongArray generationChunk = generations[chunkIndex];
                int slot = index & MASK;
                long generation = generationChunk.incrementAndGet(slot);
                if (generation > MAX_GENERATION) continue;
                long handle = (generation << 32) | Integer.toUnsignedLong(index + 1);
                return new Reservation(index, handle);
            }
        }

        void publish(Reservation reservation, ProviderContext context) {
            AtomicReferenceArray<ProviderContext> chunk = contexts[reservation.index() >>> SHIFT];
            if (!chunk.compareAndSet(reservation.index() & MASK, null, context)) {
                throw new IllegalStateException("provider registry slot is occupied");
            }
        }

        void cancel(Reservation reservation) {
            AtomicReferenceArray<ProviderContext> chunk = contexts[reservation.index() >>> SHIFT];
            if (chunk.get(reservation.index() & MASK) == null) {
                recycle(reservation.index(), reservation.handle());
            }
        }

        ProviderContext get(MemorySegment raw) {
            if (isNull(raw)) return null;
            long handle = raw.address();
            if (handle <= 0) return null;
            long encodedSlot = handle & 0xffff_ffffL;
            if (encodedSlot == 0 || encodedSlot > Integer.MAX_VALUE) return null;
            int index = (int) encodedSlot - 1;
            int chunkIndex = index >>> SHIFT;
            AtomicReferenceArray<ProviderContext>[] snapshot = contexts;
            if (chunkIndex >= snapshot.length) return null;
            ProviderContext context = snapshot[chunkIndex].get(index & MASK);
            return context != null && context.identifier() == handle ? context : null;
        }

        void remove(long handle, ProviderContext context) {
            if (handle <= 0) return;
            long encodedSlot = handle & 0xffff_ffffL;
            if (encodedSlot == 0 || encodedSlot > Integer.MAX_VALUE) return;
            int index = (int) encodedSlot - 1;
            int chunkIndex = index >>> SHIFT;
            AtomicReferenceArray<ProviderContext>[] snapshot = contexts;
            if (chunkIndex >= snapshot.length) return;
            if (snapshot[chunkIndex].compareAndSet(index & MASK, context, null)
                    && (handle >>> 32) < MAX_GENERATION) {
                recycle(index, handle);
            }
        }

        private void recycle(int index, long handle) {
            if ((handle >>> 32) < MAX_GENERATION) {
                try {
                    free.offer(index);
                } catch (Throwable ignored) {
                    /* Resource closure wins; allocation failure safely retires this slot. */
                }
            }
        }

        private record Reservation(int index, long handle) {}

        private synchronized void ensure(int chunkIndex) {
            AtomicReferenceArray<ProviderContext>[] currentContexts = contexts;
            if (chunkIndex < currentContexts.length) return;
            int length = currentContexts.length;
            while (length <= chunkIndex) length = Math.multiplyExact(length, 2);
            AtomicReferenceArray<ProviderContext>[] expandedContexts =
                    Arrays.copyOf(currentContexts, length);
            AtomicLongArray[] expandedGenerations = Arrays.copyOf(generations, length);
            for (int index = currentContexts.length; index < length; index++) {
                expandedContexts[index] = new AtomicReferenceArray<>(SIZE);
                expandedGenerations[index] = new AtomicLongArray(SIZE);
            }
            generations = expandedGenerations;
            contexts = expandedContexts;
        }

        @SuppressWarnings("unchecked")
        private static AtomicReferenceArray<ProviderContext>[] contextChunks(int length) {
            AtomicReferenceArray<ProviderContext>[] result =
                    (AtomicReferenceArray<ProviderContext>[]) new AtomicReferenceArray<?>[length];
            for (int index = 0; index < length; index++) {
                result[index] = new AtomicReferenceArray<>(SIZE);
            }
            return result;
        }

        private static AtomicLongArray[] generationChunks(int length) {
            AtomicLongArray[] result = new AtomicLongArray[length];
            for (int index = 0; index < length; index++) result[index] = new AtomicLongArray(SIZE);
            return result;
        }
    }
}
