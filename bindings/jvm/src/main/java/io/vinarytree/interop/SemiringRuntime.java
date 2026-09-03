package io.vinarytree.interop;

import static java.lang.foreign.ValueLayout.ADDRESS;
import static java.lang.foreign.ValueLayout.JAVA_BYTE;
import static java.lang.foreign.ValueLayout.JAVA_DOUBLE;
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
import java.util.Arrays;
import java.util.Objects;
import java.util.Optional;
import java.util.OptionalLong;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicIntegerArray;
import java.util.concurrent.atomic.AtomicLongArray;
import java.util.concurrent.atomic.AtomicReferenceArray;

/** Type-erased callback runtime for JVM-defined semirings. */
final class SemiringRuntime {
    private static final int MAX_RELEASE_BATCH = 65_536;
    private static final int MAX_FOLD_BATCH = 256;
    private static final long STABLE_BYTES = 4;
    private static final long BATCH = 8;
    private static final long KNOWN_FLAGS = SemiringOptions.THREAD_BOUND | SemiringOptions.PARALLEL_REENTRANT;
    private static final long KNOWN_PROPERTIES = SemiringOptions.HASHABLE
            | SemiringOptions.IDEMPOTENT_PLUS
            | SemiringOptions.K_CLOSED
            | SemiringOptions.ZERO_SUM_FREE
            | SemiringOptions.COMMUTATIVE_TIMES
            | SemiringOptions.TOTALLY_ORDERED
            | SemiringOptions.NONNEGATIVE;

    private static final Linker LINKER = Linker.nativeLinker();
    private static final Arena GLOBAL = Arena.global();

    private static final MemorySegment ZERO = stub("zero", constructType(), constructDescriptor());
    private static final MemorySegment ONE = stub("one", constructType(), constructDescriptor());
    private static final MemorySegment CLONE_VALUE = stub("cloneValue", ternaryAddressType(), ternaryAddressDescriptor());
    private static final MemorySegment RELEASE_VALUES = stub(
            "releaseValues",
            MethodType.methodType(int.class, MemorySegment.class, MemorySegment.class, long.class),
            FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS, JAVA_LONG));
    private static final MemorySegment PLUS = stub("plus", quaternaryAddressType(), quaternaryAddressDescriptor());
    private static final MemorySegment TIMES = stub("times", quaternaryAddressType(), quaternaryAddressDescriptor());
    private static final MemorySegment EQUAL = stub("equal", quaternaryAddressType(), quaternaryAddressDescriptor());
    private static final MemorySegment APPROX_EQUAL = stub(
            "approxEqual",
            MethodType.methodType(
                    int.class,
                    MemorySegment.class,
                    MemorySegment.class,
                    MemorySegment.class,
                    double.class,
                    MemorySegment.class),
            FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS, ADDRESS, JAVA_DOUBLE, ADDRESS));
    private static final MemorySegment NATURAL_ORDER = stub(
            "naturalOrder", quaternaryAddressType(), quaternaryAddressDescriptor());
    private static final MemorySegment STABLE = stub("stableBytes", bytesType(), bytesDescriptor());
    private static final MemorySegment DIAGNOSTIC = stub("diagnostic", bytesType(), bytesDescriptor());
    private static final MemorySegment PLUS_MANY = stub("plusMany", foldType(), foldDescriptor());
    private static final MemorySegment TIMES_MANY = stub("timesMany", foldType(), foldDescriptor());
    private static final MemorySegment DIVIDE = stub("divide", quaternaryAddressType(), quaternaryAddressDescriptor());
    private static final MemorySegment LEFT_DIVIDE = stub(
            "leftDivide", quaternaryAddressType(), quaternaryAddressDescriptor());
    private static final MemorySegment STAR = stub("star", ternaryAddressType(), ternaryAddressDescriptor());
    private static final MemorySegment NUMERICAL_VALUE = stub(
            "numericalValue", ternaryAddressType(), ternaryAddressDescriptor());
    private static final MemorySegment QUANTIZE = stub(
            "quantize",
            MethodType.methodType(
                    int.class, MemorySegment.class, MemorySegment.class, double.class, MemorySegment.class),
            FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS, JAVA_DOUBLE, ADDRESS));
    private static final MemorySegment TO_PROBABILITY = stub(
            "toProbability", ternaryAddressType(), ternaryAddressDescriptor());
    private static final MemorySegment CLOSURE_BOUND = stub(
            "closureBound", ternaryAddressType(), ternaryAddressDescriptor());

    private SemiringRuntime() {}

    static <T> ProviderRuntime.ProviderContext create(
            SemiringProvider<T> provider,
            SemiringOptions options,
            SemiringValueCodec<T> codec) {
        SemiringContext<T> context = new SemiringContext<>(provider, options, codec);
        context.activate();
        return context;
    }

    private static int zero(MemorySegment raw, MemorySegment output) {
        SemiringContext<?> context = context(raw);
        if (ProviderRuntime.isNull(raw) || ProviderRuntime.isNull(output)) return ProviderRuntime.NULL_POINTER;
        if (context == null) return ProviderRuntime.INVALID_ARGUMENT;
        try {
            return context.zero(output);
        } catch (Throwable failure) {
            return ProviderRuntime.status(raw, failure);
        }
    }

    private static int one(MemorySegment raw, MemorySegment output) {
        SemiringContext<?> context = context(raw);
        if (ProviderRuntime.isNull(raw) || ProviderRuntime.isNull(output)) return ProviderRuntime.NULL_POINTER;
        if (context == null) return ProviderRuntime.INVALID_ARGUMENT;
        try {
            return context.one(output);
        } catch (Throwable failure) {
            return ProviderRuntime.status(raw, failure);
        }
    }

    private static int cloneValue(MemorySegment raw, MemorySegment value, MemorySegment output) {
        return unary(raw, value, output, UnaryOperation.CLONE);
    }

    private static int releaseValues(MemorySegment raw, MemorySegment values, long count) {
        if (ProviderRuntime.isNull(raw)) return ProviderRuntime.NULL_POINTER;
        if (count < 0) return ProviderRuntime.LIMIT_EXCEEDED;
        if (count != 0 && ProviderRuntime.isNull(values)) return ProviderRuntime.NULL_POINTER;
        SemiringContext<?> context = context(raw);
        if (context == null) return ProviderRuntime.INVALID_ARGUMENT;
        try {
            return context.releaseValues(values, count);
        } catch (Throwable failure) {
            return ProviderRuntime.status(raw, failure);
        }
    }

    private static int plus(
            MemorySegment raw, MemorySegment left, MemorySegment right, MemorySegment output) {
        return binary(raw, left, right, output, BinaryOperation.PLUS);
    }

    private static int times(
            MemorySegment raw, MemorySegment left, MemorySegment right, MemorySegment output) {
        return binary(raw, left, right, output, BinaryOperation.TIMES);
    }

    private static int equal(
            MemorySegment raw, MemorySegment left, MemorySegment right, MemorySegment output) {
        return binary(raw, left, right, output, BinaryOperation.EQUAL);
    }

    private static int approxEqual(
            MemorySegment raw,
            MemorySegment left,
            MemorySegment right,
            double epsilon,
            MemorySegment output) {
        if (ProviderRuntime.isNull(raw)
                || ProviderRuntime.isNull(left)
                || ProviderRuntime.isNull(right)
                || ProviderRuntime.isNull(output)) return ProviderRuntime.NULL_POINTER;
        if (!Double.isFinite(epsilon) || epsilon < 0) return ProviderRuntime.INVALID_ARGUMENT;
        SemiringContext<?> context = context(raw);
        if (context == null) return ProviderRuntime.INVALID_ARGUMENT;
        try {
            return context.approxEqual(left, right, epsilon, output);
        } catch (Throwable failure) {
            return ProviderRuntime.status(raw, failure);
        }
    }

    private static int naturalOrder(
            MemorySegment raw, MemorySegment left, MemorySegment right, MemorySegment output) {
        return binary(raw, left, right, output, BinaryOperation.NATURAL_ORDER);
    }

    private static int stableBytes(
            MemorySegment raw,
            MemorySegment value,
            MemorySegment output,
            long capacity,
            MemorySegment written,
            MemorySegment required) {
        return bytes(raw, value, output, capacity, written, required, false);
    }

    private static int diagnostic(
            MemorySegment raw,
            MemorySegment value,
            MemorySegment output,
            long capacity,
            MemorySegment written,
            MemorySegment required) {
        return bytes(raw, value, output, capacity, written, required, true);
    }

    private static int plusMany(
            MemorySegment raw, MemorySegment values, long count, MemorySegment output) {
        return fold(raw, values, count, output, true);
    }

    private static int timesMany(
            MemorySegment raw, MemorySegment values, long count, MemorySegment output) {
        return fold(raw, values, count, output, false);
    }

    private static int divide(
            MemorySegment raw, MemorySegment left, MemorySegment right, MemorySegment output) {
        return binary(raw, left, right, output, BinaryOperation.DIVIDE);
    }

    private static int leftDivide(
            MemorySegment raw, MemorySegment left, MemorySegment right, MemorySegment output) {
        return binary(raw, left, right, output, BinaryOperation.LEFT_DIVIDE);
    }

    private static int star(MemorySegment raw, MemorySegment value, MemorySegment output) {
        return unary(raw, value, output, UnaryOperation.STAR);
    }

    private static int numericalValue(MemorySegment raw, MemorySegment value, MemorySegment output) {
        return unary(raw, value, output, UnaryOperation.NUMERICAL_VALUE);
    }

    private static int quantize(
            MemorySegment raw, MemorySegment value, double epsilon, MemorySegment output) {
        if (ProviderRuntime.isNull(raw) || ProviderRuntime.isNull(value) || ProviderRuntime.isNull(output)) {
            return ProviderRuntime.NULL_POINTER;
        }
        if (!Double.isFinite(epsilon) || epsilon <= 0) return ProviderRuntime.INVALID_ARGUMENT;
        SemiringContext<?> context = context(raw);
        if (context == null) return ProviderRuntime.INVALID_ARGUMENT;
        try {
            return context.quantize(value, epsilon, output);
        } catch (Throwable failure) {
            return ProviderRuntime.status(raw, failure);
        }
    }

    private static int toProbability(MemorySegment raw, MemorySegment value, MemorySegment output) {
        return unary(raw, value, output, UnaryOperation.TO_PROBABILITY);
    }

    private static int closureBound(MemorySegment raw, MemorySegment output, MemorySegment known) {
        if (ProviderRuntime.isNull(raw) || ProviderRuntime.isNull(output) || ProviderRuntime.isNull(known)) {
            return ProviderRuntime.NULL_POINTER;
        }
        SemiringContext<?> context = context(raw);
        if (context == null) return ProviderRuntime.INVALID_ARGUMENT;
        try {
            OptionalLong bound = context.options.closureBound();
            ProviderRuntime.view(output, 8).set(JAVA_LONG, 0, bound.orElse(0));
            ProviderRuntime.view(known, 1).set(JAVA_BYTE, 0, bound.isPresent() ? (byte) 1 : 0);
            return ProviderRuntime.OK;
        } catch (Throwable failure) {
            return ProviderRuntime.status(raw, failure);
        }
    }

    private static int unary(
            MemorySegment raw, MemorySegment value, MemorySegment output, UnaryOperation operation) {
        if (ProviderRuntime.isNull(raw) || ProviderRuntime.isNull(value) || ProviderRuntime.isNull(output)) {
            return ProviderRuntime.NULL_POINTER;
        }
        SemiringContext<?> context = context(raw);
        if (context == null) return ProviderRuntime.INVALID_ARGUMENT;
        try {
            return context.unary(value, output, operation);
        } catch (Throwable failure) {
            return ProviderRuntime.status(raw, failure);
        }
    }

    private static int binary(
            MemorySegment raw,
            MemorySegment left,
            MemorySegment right,
            MemorySegment output,
            BinaryOperation operation) {
        if (ProviderRuntime.isNull(raw)
                || ProviderRuntime.isNull(left)
                || ProviderRuntime.isNull(right)
                || ProviderRuntime.isNull(output)) return ProviderRuntime.NULL_POINTER;
        SemiringContext<?> context = context(raw);
        if (context == null) return ProviderRuntime.INVALID_ARGUMENT;
        try {
            return context.binary(left, right, output, operation);
        } catch (Throwable failure) {
            return ProviderRuntime.status(raw, failure);
        }
    }

    private static int bytes(
            MemorySegment raw,
            MemorySegment value,
            MemorySegment output,
            long capacity,
            MemorySegment written,
            MemorySegment required,
            boolean diagnostic) {
        if (ProviderRuntime.isNull(raw)
                || (!diagnostic && ProviderRuntime.isNull(value))
                || ProviderRuntime.isNull(written)
                || ProviderRuntime.isNull(required)) return ProviderRuntime.NULL_POINTER;
        if (capacity < 0) return ProviderRuntime.LIMIT_EXCEEDED;
        if (capacity != 0 && ProviderRuntime.isNull(output)) return ProviderRuntime.NULL_POINTER;
        SemiringContext<?> context = context(raw);
        if (context == null) return ProviderRuntime.INVALID_ARGUMENT;
        try {
            return context.bytes(value, output, capacity, written, required, diagnostic);
        } catch (Throwable failure) {
            return ProviderRuntime.status(raw, failure);
        }
    }

    private static int fold(
            MemorySegment raw,
            MemorySegment values,
            long count,
            MemorySegment output,
            boolean plus) {
        if (ProviderRuntime.isNull(raw) || ProviderRuntime.isNull(output)) return ProviderRuntime.NULL_POINTER;
        if (count < 0) return ProviderRuntime.LIMIT_EXCEEDED;
        if (count != 0 && ProviderRuntime.isNull(values)) return ProviderRuntime.NULL_POINTER;
        SemiringContext<?> context = context(raw);
        if (context == null) return ProviderRuntime.INVALID_ARGUMENT;
        try {
            return context.fold(values, count, output, plus);
        } catch (Throwable failure) {
            return ProviderRuntime.status(raw, failure);
        }
    }

    private static SemiringContext<?> context(MemorySegment raw) {
        return ProviderRuntime.context(raw, SemiringContext.class);
    }

    private static MemorySegment stub(String name, MethodType type, FunctionDescriptor descriptor) {
        try {
            MethodHandle target = MethodHandles.lookup().findStatic(SemiringRuntime.class, name, type);
            return LINKER.upcallStub(target, descriptor, GLOBAL);
        } catch (ReflectiveOperationException failure) {
            throw new ExceptionInInitializerError(failure);
        }
    }

    private static MethodType constructType() {
        return MethodType.methodType(int.class, MemorySegment.class, MemorySegment.class);
    }

    private static FunctionDescriptor constructDescriptor() {
        return FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS);
    }

    private static MethodType ternaryAddressType() {
        return MethodType.methodType(
                int.class, MemorySegment.class, MemorySegment.class, MemorySegment.class);
    }

    private static FunctionDescriptor ternaryAddressDescriptor() {
        return FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS, ADDRESS);
    }

    private static MethodType quaternaryAddressType() {
        return MethodType.methodType(
                int.class,
                MemorySegment.class,
                MemorySegment.class,
                MemorySegment.class,
                MemorySegment.class);
    }

    private static FunctionDescriptor quaternaryAddressDescriptor() {
        return FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS, ADDRESS, ADDRESS);
    }

    private static MethodType bytesType() {
        return MethodType.methodType(
                int.class,
                MemorySegment.class,
                MemorySegment.class,
                MemorySegment.class,
                long.class,
                MemorySegment.class,
                MemorySegment.class);
    }

    private static FunctionDescriptor bytesDescriptor() {
        return FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS, ADDRESS, JAVA_LONG, ADDRESS, ADDRESS);
    }

    private static MethodType foldType() {
        return MethodType.methodType(
                int.class, MemorySegment.class, MemorySegment.class, long.class, MemorySegment.class);
    }

    private static FunctionDescriptor foldDescriptor() {
        return FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS, JAVA_LONG, ADDRESS);
    }

    private enum UnaryOperation {
        CLONE,
        STAR,
        NUMERICAL_VALUE,
        TO_PROBABILITY
    }

    private enum BinaryOperation {
        PLUS,
        TIMES,
        EQUAL,
        NATURAL_ORDER,
        DIVIDE,
        LEFT_DIVIDE
    }

    /** One provider context with per-domain tables and allocation-free hot lookups. */
    private static final class SemiringContext<T> extends ProviderRuntime.ProviderContext {
        private final SemiringProvider<T> provider;
        private final SemiringOptions options;
        private final SemiringValueCodec<T> codec;
        private final TokenStore<T> tokens;
        private final PrimitiveTokenStore primitiveTokens;
        private volatile long cookie;
        private final MemorySegment base;
        private final MemorySegment division;
        private final MemorySegment star;
        private final MemorySegment numeric;
        private final MemorySegment properties;

        SemiringContext(
                SemiringProvider<T> provider,
                SemiringOptions options,
                SemiringValueCodec<T> codec) {
            this.provider = Objects.requireNonNull(provider, "provider");
            this.options = validate(options);
            this.codec = codec;
            try {
                tokens = codec == null ? new TokenStore<>() : null;
                primitiveTokens = codec == null ? null : new PrimitiveTokenStore();
                base = baseTable();
                division = divisionTable();
                star = starTable();
                numeric = numericTable();
                properties = propertiesTable();
            } catch (Throwable failure) {
                abortConstruction();
                throw failure;
            }
        }

        @Override
        void onActivated(long handle) {
            cookie = handle;
        }

        @Override
        int query(MemorySegment id, int minimumVersion, MemorySegment output) {
            if (Integer.compareUnsigned(minimumVersion, ProviderRuntime.INTERFACE_VERSION) > 0) {
                return ProviderRuntime.UNSUPPORTED;
            }
            MemorySegment result;
            if (ProviderRuntime.idEquals(id, ProviderRuntime.SEMIRING_ID)) result = base;
            else if (provider instanceof DivisibleSemiringProvider<?>
                    && ProviderRuntime.idEquals(id, ProviderRuntime.SEMIRING_DIVISION_ID)) result = division;
            else if (provider instanceof StarSemiringProvider<?>
                    && ProviderRuntime.idEquals(id, ProviderRuntime.SEMIRING_STAR_ID)) result = star;
            else if (provider instanceof NumericSemiringProvider<?>
                    && ProviderRuntime.idEquals(id, ProviderRuntime.SEMIRING_NUMERIC_ID)) result = numeric;
            else if (ProviderRuntime.idEquals(id, ProviderRuntime.SEMIRING_PROPERTIES_ID)) result = properties;
            else return ProviderRuntime.UNSUPPORTED;
            ProviderRuntime.view(output, 8).set(ADDRESS, 0, result);
            return ProviderRuntime.OK;
        }

        int zero(MemorySegment output) {
            return encode(provider.zero(), output);
        }

        int one(MemorySegment output) {
            return encode(provider.one(), output);
        }

        int unary(MemorySegment value, MemorySegment output, UnaryOperation operation) {
            T decoded = decode(value);
            if (decoded == null) return ProviderRuntime.INVALID_ARGUMENT;
            return switch (operation) {
                case CLONE -> encode(provider.cloneValue(decoded), output);
                case STAR -> star(decoded, output);
                case NUMERICAL_VALUE -> numericalValue(decoded, output);
                case TO_PROBABILITY -> toProbability(decoded, output);
            };
        }

        int binary(
                MemorySegment left,
                MemorySegment right,
                MemorySegment output,
                BinaryOperation operation) {
            T lhs = decode(left);
            T rhs = decode(right);
            if (lhs == null || rhs == null) return ProviderRuntime.INVALID_ARGUMENT;
            return switch (operation) {
                case PLUS -> encode(provider.plus(lhs, rhs), output);
                case TIMES -> encode(provider.times(lhs, rhs), output);
                case EQUAL -> {
                    ProviderRuntime.view(output, 1).set(
                            JAVA_BYTE, 0, provider.equalsValue(lhs, rhs) ? (byte) 1 : 0);
                    yield ProviderRuntime.OK;
                }
                case NATURAL_ORDER -> {
                    SemiringOrder order = Objects.requireNonNull(
                            provider.compareNatural(lhs, rhs), "compareNatural");
                    if (order == SemiringOrder.INCOMPARABLE
                            && (options.properties() & SemiringOptions.TOTALLY_ORDERED) != 0) {
                        yield ProviderRuntime.PROVIDER_ERROR;
                    }
                    ProviderRuntime.view(output, 4).set(JAVA_INT, 0, order.wireValue());
                    yield ProviderRuntime.OK;
                }
                case DIVIDE -> divide(lhs, rhs, output, false);
                case LEFT_DIVIDE -> divide(lhs, rhs, output, true);
            };
        }

        int approxEqual(
                MemorySegment left,
                MemorySegment right,
                double epsilon,
                MemorySegment output) {
            T lhs = decode(left);
            T rhs = decode(right);
            if (lhs == null || rhs == null) return ProviderRuntime.INVALID_ARGUMENT;
            ProviderRuntime.view(output, 1).set(
                    JAVA_BYTE, 0, provider.approximatelyEquals(lhs, rhs, epsilon) ? (byte) 1 : 0);
            return ProviderRuntime.OK;
        }

        int bytes(
                MemorySegment value,
                MemorySegment output,
                long capacity,
                MemorySegment written,
                MemorySegment required,
                boolean diagnostic) {
            T decoded = ProviderRuntime.isNull(value) ? null : decode(value);
            if (!ProviderRuntime.isNull(value) && decoded == null) return ProviderRuntime.INVALID_ARGUMENT;
            byte[] bytes;
            if (diagnostic) {
                String text = decoded == null ? provider.diagnostic() : provider.diagnostic(decoded);
                bytes = Objects.requireNonNull(text, "diagnostic").getBytes(StandardCharsets.UTF_8);
            } else {
                bytes = Objects.requireNonNull(provider.stableBytes(decoded), "stableBytes");
            }
            return ProviderRuntime.writeBytes(bytes, output, capacity, written, required);
        }

        int fold(MemorySegment values, long count, MemorySegment output, boolean plus) {
            if (count > MAX_FOLD_BATCH) return ProviderRuntime.LIMIT_EXCEEDED;
            MemorySegment input = count == 0
                    ? MemorySegment.NULL
                    : ProviderRuntime.view(values, Math.multiplyExact(count, 16));
            for (long index = 0; index < count; index++) {
                if (!isValid(input.asSlice(index * 16, 16))) return ProviderRuntime.INVALID_ARGUMENT;
            }
            T accumulator;
            if (count == 0) accumulator = plus ? provider.zero() : provider.one();
            else {
                accumulator = decode(input.asSlice(0, 16));
                for (long index = 1; index < count; index++) {
                    T next = decode(input.asSlice(index * 16, 16));
                    accumulator = plus ? provider.plus(accumulator, next) : provider.times(accumulator, next);
                    if (accumulator == null) return ProviderRuntime.PROVIDER_ERROR;
                }
            }
            return encode(accumulator, output);
        }

        int releaseValues(MemorySegment values, long count) {
            if (count > MAX_RELEASE_BATCH) return ProviderRuntime.LIMIT_EXCEEDED;
            MemorySegment input = count == 0
                    ? MemorySegment.NULL
                    : ProviderRuntime.view(values, Math.multiplyExact(count, 16));
            for (long index = 0; index < count; index++) {
                MemorySegment value = input.asSlice(index * 16, 16);
                long handle = tokenHandle(value);
                if (!isValid(value)) {
                    for (long prior = 0; prior < index; prior++) {
                        long priorHandle = tokenHandle(input.asSlice(prior * 16, 16));
                        if (codec == null) tokens.rollback(priorHandle);
                        else primitiveTokens.rollback(priorHandle);
                    }
                    return ProviderRuntime.INVALID_ARGUMENT;
                }
                boolean claimed = codec == null ? tokens.claim(handle) : primitiveTokens.claim(handle);
                if (!claimed) {
                    for (long prior = 0; prior < index; prior++) {
                        long priorHandle = tokenHandle(input.asSlice(prior * 16, 16));
                        if (codec == null) tokens.rollback(priorHandle);
                        else primitiveTokens.rollback(priorHandle);
                    }
                    return ProviderRuntime.INVALID_ARGUMENT;
                }
            }
            for (long index = 0; index < count; index++) {
                MemorySegment value = input.asSlice(index * 16, 16);
                long handle = tokenHandle(value);
                if (codec == null) tokens.finish(handle);
                else primitiveTokens.finish(handle);
                value.fill((byte) 0);
            }
            return ProviderRuntime.OK;
        }

        int quantize(MemorySegment value, double epsilon, MemorySegment output) {
            T decoded = decode(value);
            if (decoded == null) return ProviderRuntime.INVALID_ARGUMENT;
            if (!(provider instanceof NumericSemiringProvider<?>)) return ProviderRuntime.UNSUPPORTED;
            @SuppressWarnings("unchecked")
            NumericSemiringProvider<T> numericProvider = (NumericSemiringProvider<T>) provider;
            long quantized = numericProvider.quantize(decoded, epsilon);
            ProviderRuntime.view(output, 8).set(JAVA_LONG, 0, quantized);
            return ProviderRuntime.OK;
        }

        private int divide(T left, T right, MemorySegment output, boolean leftDivide) {
            if (!(provider instanceof DivisibleSemiringProvider<?>)) return ProviderRuntime.UNSUPPORTED;
            @SuppressWarnings("unchecked")
            DivisibleSemiringProvider<T> divisible = (DivisibleSemiringProvider<T>) provider;
            Optional<T> result = Objects.requireNonNull(
                    leftDivide ? divisible.leftDivide(left, right) : divisible.divide(left, right),
                    leftDivide ? "leftDivide" : "divide");
            return result.isPresent() ? encode(result.get(), output) : ProviderRuntime.END;
        }

        private int star(T value, MemorySegment output) {
            if (!(provider instanceof StarSemiringProvider<?>)) return ProviderRuntime.UNSUPPORTED;
            @SuppressWarnings("unchecked")
            StarSemiringProvider<T> starProvider = (StarSemiringProvider<T>) provider;
            Optional<T> result = Objects.requireNonNull(starProvider.star(value), "star");
            return result.isPresent() ? encode(result.get(), output) : ProviderRuntime.END;
        }

        private int numericalValue(T value, MemorySegment output) {
            if (!(provider instanceof NumericSemiringProvider<?>)) return ProviderRuntime.UNSUPPORTED;
            @SuppressWarnings("unchecked")
            NumericSemiringProvider<T> numericProvider = (NumericSemiringProvider<T>) provider;
            double result = numericProvider.numericalValue(value);
            if (Double.isNaN(result)) return ProviderRuntime.PROVIDER_ERROR;
            ProviderRuntime.view(output, 8).set(JAVA_DOUBLE, 0, result);
            return ProviderRuntime.OK;
        }

        private int toProbability(T value, MemorySegment output) {
            if (!(provider instanceof NumericSemiringProvider<?>)) return ProviderRuntime.UNSUPPORTED;
            @SuppressWarnings("unchecked")
            NumericSemiringProvider<T> numericProvider = (NumericSemiringProvider<T>) provider;
            double result = numericProvider.toProbability(value);
            if (!Double.isFinite(result) || result < 0) return ProviderRuntime.PROVIDER_ERROR;
            ProviderRuntime.view(output, 8).set(JAVA_DOUBLE, 0, result);
            return ProviderRuntime.OK;
        }

        private int encode(T value, MemorySegment output) {
            if (value == null) return ProviderRuntime.PROVIDER_ERROR;
            if (codec != null) {
                long bits = codec.encode(value);
                long handle = primitiveTokens.put(bits);
                try {
                    writeToken(output, handle);
                    return ProviderRuntime.OK;
                } catch (Throwable failure) {
                    primitiveTokens.discard(handle);
                    throw failure;
                }
            }
            long handle = tokens.put(value);
            try {
                writeToken(output, handle);
                return ProviderRuntime.OK;
            } catch (Throwable failure) {
                tokens.discard(handle);
                throw failure;
            }
        }

        private boolean isValid(MemorySegment value) {
            if (ProviderRuntime.isNull(value)) return false;
            MemorySegment token = ProviderRuntime.view(value, 16);
            return token.get(JAVA_LONG, 8) == cookie
                    && (codec == null
                            ? tokens.get(token.get(JAVA_LONG, 0)) != null
                            : primitiveTokens.isLive(token.get(JAVA_LONG, 0)));
        }

        private T decode(MemorySegment value) {
            if (!isValid(value)) return null;
            MemorySegment token = ProviderRuntime.view(value, 16);
            long word0 = token.get(JAVA_LONG, 0);
            T decoded = codec != null ? codec.decode(primitiveTokens.get(word0)) : tokens.get(word0);
            return Objects.requireNonNull(decoded, "decoded semiring value");
        }

        private void writeToken(MemorySegment output, long handle) {
            MemorySegment destination = ProviderRuntime.view(output, 16);
            destination.set(JAVA_LONG, 0, handle);
            destination.set(JAVA_LONG, 8, cookie);
        }

        private long tokenHandle(MemorySegment value) {
            if (ProviderRuntime.isNull(value)) return 0;
            MemorySegment token = ProviderRuntime.view(value, 16);
            return token.get(JAVA_LONG, 8) == cookie ? token.get(JAVA_LONG, 0) : 0;
        }

        private MemorySegment baseTable() {
            MemorySegment table = arena.allocate(InteropLayouts.SEMIRING_VTABLE);
            table.fill((byte) 0);
            table.set(JAVA_LONG, 0, InteropLayouts.SEMIRING_VTABLE.byteSize());
            table.set(JAVA_INT, 8, ProviderRuntime.INTERFACE_VERSION);
            table.set(JAVA_LONG, 16, options.flags() | STABLE_BYTES | BATCH);
            MemorySegment.copy(options.domainId().bytes(), 0, table.asSlice(24, 16), JAVA_BYTE, 0, 16);
            table.set(ADDRESS, 40, ZERO);
            table.set(ADDRESS, 48, ONE);
            table.set(ADDRESS, 56, CLONE_VALUE);
            table.set(ADDRESS, 64, RELEASE_VALUES);
            table.set(ADDRESS, 72, PLUS);
            table.set(ADDRESS, 80, TIMES);
            table.set(ADDRESS, 88, EQUAL);
            table.set(ADDRESS, 96, APPROX_EQUAL);
            table.set(ADDRESS, 104, NATURAL_ORDER);
            table.set(ADDRESS, 112, STABLE);
            table.set(ADDRESS, 120, DIAGNOSTIC);
            table.set(ADDRESS, 128, PLUS_MANY);
            table.set(ADDRESS, 136, TIMES_MANY);
            return table;
        }

        private MemorySegment divisionTable() {
            MemorySegment table = arena.allocate(InteropLayouts.SEMIRING_DIVISION_VTABLE);
            table.fill((byte) 0);
            table.set(JAVA_LONG, 0, InteropLayouts.SEMIRING_DIVISION_VTABLE.byteSize());
            table.set(JAVA_INT, 8, ProviderRuntime.INTERFACE_VERSION);
            table.set(ADDRESS, 16, DIVIDE);
            table.set(ADDRESS, 24, LEFT_DIVIDE);
            return table;
        }

        private MemorySegment starTable() {
            MemorySegment table = arena.allocate(InteropLayouts.SEMIRING_STAR_VTABLE);
            table.fill((byte) 0);
            table.set(JAVA_LONG, 0, InteropLayouts.SEMIRING_STAR_VTABLE.byteSize());
            table.set(JAVA_INT, 8, ProviderRuntime.INTERFACE_VERSION);
            table.set(ADDRESS, 16, STAR);
            return table;
        }

        private MemorySegment numericTable() {
            MemorySegment table = arena.allocate(InteropLayouts.SEMIRING_NUMERIC_VTABLE);
            table.fill((byte) 0);
            table.set(JAVA_LONG, 0, InteropLayouts.SEMIRING_NUMERIC_VTABLE.byteSize());
            table.set(JAVA_INT, 8, ProviderRuntime.INTERFACE_VERSION);
            table.set(ADDRESS, 16, NUMERICAL_VALUE);
            table.set(ADDRESS, 24, QUANTIZE);
            table.set(ADDRESS, 32, TO_PROBABILITY);
            return table;
        }

        private MemorySegment propertiesTable() {
            MemorySegment table = arena.allocate(InteropLayouts.SEMIRING_PROPERTIES_VTABLE);
            table.fill((byte) 0);
            table.set(JAVA_LONG, 0, InteropLayouts.SEMIRING_PROPERTIES_VTABLE.byteSize());
            table.set(JAVA_INT, 8, ProviderRuntime.INTERFACE_VERSION);
            table.set(JAVA_LONG, 16, options.properties());
            table.set(ADDRESS, 24, CLOSURE_BOUND);
            return table;
        }

        private static SemiringOptions validate(SemiringOptions options) {
            Objects.requireNonNull(options, "options");
            Objects.requireNonNull(options.domainId(), "domainId");
            Objects.requireNonNull(options.closureBound(), "closureBound");
            if ((options.flags() & ~KNOWN_FLAGS) != 0
                    || (options.flags() & KNOWN_FLAGS) == KNOWN_FLAGS
                    || (options.properties() & ~KNOWN_PROPERTIES) != 0
                    || (options.closureBound().isPresent() && options.closureBound().getAsLong() < 0)) {
                throw new IllegalArgumentException("semiring options contain invalid flags, properties, or bounds");
            }
            return new SemiringOptions(
                    options.domainId(), options.flags(), options.properties(), options.closureBound());
        }
    }

    /** Generation-stamped leases over primitive payloads without per-value object allocation. */
    private static final class PrimitiveTokenStore {
        private static final int SHIFT = 10;
        private static final int SIZE = 1 << SHIFT;
        private static final int MASK = SIZE - 1;
        private static final int FREE = 0;
        private static final int LIVE = 1;
        private static final int RELEASING = 2;
        private static final int RETIRED = 3;
        private static final long MAX_GENERATION = 0xffff_ffffL;
        private final AtomicInteger cursor = new AtomicInteger();
        private volatile Segment[] segments = {new Segment()};

        long put(long value) {
            while (true) {
                Segment[] snapshot = segments;
                int capacity = Math.multiplyExact(snapshot.length, SIZE);
                int start = Math.floorMod(cursor.getAndIncrement(), capacity);
                for (int scanned = 0; scanned < capacity; scanned++) {
                    int index = start + scanned;
                    if (index >= capacity) index -= capacity;
                    Segment segment = snapshot[index >>> SHIFT];
                    int slot = index & MASK;
                    if (!segment.states.compareAndSet(slot, FREE, LIVE)) continue;
                    long generation = segment.generations.incrementAndGet(slot);
                    if (generation > MAX_GENERATION) {
                        segment.states.set(slot, RETIRED);
                        continue;
                    }
                    segment.values.set(slot, value);
                    return (generation << 32) | Integer.toUnsignedLong(index + 1);
                }
                grow(snapshot.length);
            }
        }

        boolean isLive(long handle) {
            int index = resolveIndex(handle);
            if (index < 0) return false;
            Segment[] snapshot = segments;
            int segmentIndex = index >>> SHIFT;
            if (segmentIndex >= snapshot.length) return false;
            Segment segment = snapshot[segmentIndex];
            int offset = index & MASK;
            return segment.states.get(offset) == LIVE
                    && segment.generations.get(offset) == generation(handle);
        }

        long get(long handle) {
            int index = resolveIndex(handle);
            if (index < 0) throw new IllegalStateException("invalid primitive semiring lease");
            Segment[] snapshot = segments;
            int segmentIndex = index >>> SHIFT;
            if (segmentIndex >= snapshot.length) {
                throw new IllegalStateException("invalid primitive semiring lease");
            }
            Segment segment = snapshot[segmentIndex];
            int offset = index & MASK;
            if (segment.states.get(offset) != LIVE
                    || segment.generations.get(offset) != generation(handle)) {
                throw new IllegalStateException("invalid primitive semiring lease");
            }
            return segment.values.get(offset);
        }

        boolean claim(long handle) {
            int index = resolveIndex(handle);
            if (index < 0) return false;
            Segment[] snapshot = segments;
            int segmentIndex = index >>> SHIFT;
            if (segmentIndex >= snapshot.length) return false;
            Segment segment = snapshot[segmentIndex];
            int offset = index & MASK;
            return segment.generations.get(offset) == generation(handle)
                    && segment.states.compareAndSet(offset, LIVE, RELEASING);
        }

        void rollback(long handle) {
            int index = resolveIndex(handle);
            if (index < 0) return;
            Segment[] snapshot = segments;
            int segmentIndex = index >>> SHIFT;
            if (segmentIndex >= snapshot.length) return;
            Segment segment = snapshot[segmentIndex];
            int offset = index & MASK;
            if (segment.generations.get(offset) == generation(handle)) {
                segment.states.compareAndSet(offset, RELEASING, LIVE);
            }
        }

        void finish(long handle) {
            int index = resolveIndex(handle);
            if (index < 0) throw new IllegalStateException("invalid primitive semiring lease");
            Segment[] snapshot = segments;
            int segmentIndex = index >>> SHIFT;
            if (segmentIndex >= snapshot.length) {
                throw new IllegalStateException("invalid primitive semiring lease");
            }
            Segment segment = snapshot[segmentIndex];
            int offset = index & MASK;
            if (segment.generations.get(offset) != generation(handle)
                    || segment.states.get(offset) != RELEASING) {
                throw new IllegalStateException("invalid primitive semiring lease");
            }
            segment.values.set(offset, 0);
            if (!segment.states.compareAndSet(offset, RELEASING, FREE)) {
                throw new IllegalStateException("primitive semiring lease release lost ownership");
            }
        }

        void discard(long handle) {
            if (claim(handle)) finish(handle);
        }

        private int resolveIndex(long handle) {
            long encodedSlot = handle & 0xffff_ffffL;
            return encodedSlot == 0 || encodedSlot > Integer.MAX_VALUE
                    ? -1
                    : (int) encodedSlot - 1;
        }

        private long generation(long handle) {
            return Integer.toUnsignedLong((int) (handle >>> 32));
        }

        private synchronized void grow(int observedLength) {
            Segment[] current = segments;
            if (current.length != observedLength) return;
            int length = Math.multiplyExact(current.length, 2);
            Segment[] expanded = Arrays.copyOf(current, length);
            for (int index = current.length; index < length; index++) expanded[index] = new Segment();
            segments = expanded;
        }

        private static final class Segment {
            final AtomicLongArray values = new AtomicLongArray(SIZE);
            final AtomicLongArray generations = new AtomicLongArray(SIZE);
            final AtomicIntegerArray states = new AtomicIntegerArray(SIZE);
        }
    }

    /** Provider-local recyclable leases with lock-free steady-state access. */
    private static final class TokenStore<T> {
        private static final int SHIFT = 10;
        private static final int SIZE = 1 << SHIFT;
        private static final int MASK = SIZE - 1;
        private static final int FREE = 0;
        private static final int LIVE = 1;
        private static final int RELEASING = 2;
        private static final int RETIRED = 3;
        private static final long MAX_GENERATION = 0xffff_ffffL;
        private final AtomicInteger cursor = new AtomicInteger();
        private volatile Segment[] segments = {new Segment()};

        long put(T value) {
            Objects.requireNonNull(value, "value");
            while (true) {
                Segment[] snapshot = segments;
                int capacity = Math.multiplyExact(snapshot.length, SIZE);
                int start = Math.floorMod(cursor.getAndIncrement(), capacity);
                for (int scanned = 0; scanned < capacity; scanned++) {
                    int index = start + scanned;
                    if (index >= capacity) index -= capacity;
                    Segment segment = snapshot[index >>> SHIFT];
                    int slot = index & MASK;
                    if (!segment.states.compareAndSet(slot, FREE, LIVE)) continue;
                    long generation = segment.generations.incrementAndGet(slot);
                    if (generation > MAX_GENERATION) {
                        segment.states.set(slot, RETIRED);
                        continue;
                    }
                    segment.values.set(slot, value);
                    return (generation << 32) | Integer.toUnsignedLong(index + 1);
                }
                grow(snapshot.length);
            }
        }

        @SuppressWarnings("unchecked")
        T get(long handle) {
            int index = resolveIndex(handle);
            if (index < 0) return null;
            Segment[] snapshot = segments;
            int segmentIndex = index >>> SHIFT;
            if (segmentIndex >= snapshot.length) return null;
            Segment segment = snapshot[segmentIndex];
            int offset = index & MASK;
            if (segment.states.get(offset) != LIVE) return null;
            Object value = segment.values.get(offset);
            if (value == null
                    || segment.generations.get(offset) != generation(handle)) {
                return null;
            }
            return (T) value;
        }

        boolean claim(long handle) {
            int index = resolveIndex(handle);
            if (index < 0) return false;
            Segment[] snapshot = segments;
            int segmentIndex = index >>> SHIFT;
            if (segmentIndex >= snapshot.length) return false;
            Segment segment = snapshot[segmentIndex];
            int offset = index & MASK;
            return segment.generations.get(offset) == generation(handle)
                    && segment.values.get(offset) != null
                    && segment.states.compareAndSet(offset, LIVE, RELEASING);
        }

        void rollback(long handle) {
            int index = resolveIndex(handle);
            if (index < 0) return;
            Segment[] snapshot = segments;
            int segmentIndex = index >>> SHIFT;
            if (segmentIndex >= snapshot.length) return;
            Segment segment = snapshot[segmentIndex];
            int offset = index & MASK;
            if (segment.generations.get(offset) == generation(handle)) {
                segment.states.compareAndSet(offset, RELEASING, LIVE);
            }
        }

        void finish(long handle) {
            int index = resolveIndex(handle);
            if (index < 0) throw new IllegalStateException("invalid semiring lease");
            Segment[] snapshot = segments;
            int segmentIndex = index >>> SHIFT;
            if (segmentIndex >= snapshot.length) throw new IllegalStateException("invalid semiring lease");
            Segment segment = snapshot[segmentIndex];
            int offset = index & MASK;
            if (segment.generations.get(offset) != generation(handle)
                    || segment.states.get(offset) != RELEASING) {
                throw new IllegalStateException("semiring lease changed during release");
            }
            segment.values.set(offset, null);
            if (!segment.states.compareAndSet(offset, RELEASING, FREE)) {
                throw new IllegalStateException("semiring lease release lost ownership");
            }
        }

        void discard(long handle) {
            if (claim(handle)) finish(handle);
        }

        private int resolveIndex(long handle) {
            long encodedSlot = handle & 0xffff_ffffL;
            return encodedSlot == 0 || encodedSlot > Integer.MAX_VALUE ? -1 : (int) encodedSlot - 1;
        }

        private long generation(long handle) {
            return Integer.toUnsignedLong((int) (handle >>> 32));
        }

        private synchronized void grow(int observedLength) {
            Segment[] current = segments;
            if (current.length != observedLength) return;
            int length = Math.multiplyExact(current.length, 2);
            Segment[] expanded = Arrays.copyOf(current, length);
            for (int index = current.length; index < length; index++) expanded[index] = new Segment();
            segments = expanded;
        }

        private static final class Segment {
            final AtomicReferenceArray<Object> values = new AtomicReferenceArray<>(SIZE);
            final AtomicLongArray generations = new AtomicLongArray(SIZE);
            final AtomicIntegerArray states = new AtomicIntegerArray(SIZE);
        }
    }
}
