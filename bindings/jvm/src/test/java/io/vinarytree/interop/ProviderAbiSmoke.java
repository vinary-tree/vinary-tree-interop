package io.vinarytree.interop;

import static java.lang.foreign.ValueLayout.ADDRESS;
import static java.lang.foreign.ValueLayout.JAVA_BYTE;
import static java.lang.foreign.ValueLayout.JAVA_DOUBLE;
import static java.lang.foreign.ValueLayout.JAVA_INT;
import static java.lang.foreign.ValueLayout.JAVA_LONG;
import static java.lang.foreign.MemoryLayout.PathElement.groupElement;

import java.lang.foreign.Arena;
import java.lang.foreign.FunctionDescriptor;
import java.lang.foreign.Linker;
import java.lang.foreign.MemoryLayout;
import java.lang.foreign.MemorySegment;
import java.lang.invoke.MethodHandles;
import java.lang.invoke.MethodType;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Optional;
import java.util.OptionalLong;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.Future;
import java.util.concurrent.locks.LockSupport;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.Test;

/**
 * Dependency-free executable conformance test for JVM-defined ABI providers.
 *
 * <p>Every operation below enters the Java provider through a native downcall to the exported
 * upcall stub. This catches descriptor, layout, ownership, status, and exception-containment
 * regressions that a direct Java unit test cannot observe.
 */
public final class ProviderAbiSmoke {
    private static final Linker LINKER = Linker.nativeLinker();
    private static final int OK = 0;
    private static final int END = 1;
    private static final int INVALID_ARGUMENT = 2;
    private static final int UNSUPPORTED = 4;
    private static final int IO_ERROR = 5;
    private static final int LIMIT_EXCEEDED = 7;
    private static final int PROVIDER_ERROR = 8;

    private static final FunctionDescriptor BASE_QUERY =
            FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS, JAVA_INT, ADDRESS);
    private static final FunctionDescriptor VOID_CONTEXT = FunctionDescriptor.ofVoid(ADDRESS);
    private static final FunctionDescriptor CONTEXT_OUT =
            FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS);
    private static final FunctionDescriptor CONTEXT_TWO_OUT =
            FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS, ADDRESS);
    private static final FunctionDescriptor CONTEXT_TWO_VALUES_OUT =
            FunctionDescriptor.of(JAVA_INT, ADDRESS, JAVA_LONG, JAVA_LONG, ADDRESS, ADDRESS);
    private static final FunctionDescriptor CONTEXT_VALUE_OUT =
            FunctionDescriptor.of(JAVA_INT, ADDRESS, JAVA_LONG, ADDRESS);
    private static final FunctionDescriptor PAGE =
            FunctionDescriptor.of(
                    JAVA_INT, ADDRESS, JAVA_LONG, JAVA_LONG, ADDRESS, JAVA_LONG, ADDRESS, ADDRESS);
    private static final FunctionDescriptor FOUR_ADDRESSES =
            FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS, ADDRESS, ADDRESS);
    private static final FunctionDescriptor RELEASE_VALUES =
            FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS, JAVA_LONG);
    private static final FunctionDescriptor FOLD =
            FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS, JAVA_LONG, ADDRESS);
    private static final FunctionDescriptor APPROX =
            FunctionDescriptor.of(
                    JAVA_INT, ADDRESS, ADDRESS, ADDRESS, JAVA_DOUBLE, ADDRESS);
    private static final FunctionDescriptor VALUE_BYTES =
            FunctionDescriptor.of(
                    JAVA_INT, ADDRESS, ADDRESS, ADDRESS, JAVA_LONG, ADDRESS, ADDRESS);
    private static final FunctionDescriptor RESOURCE_BYTES =
            FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS, JAVA_LONG, ADDRESS, ADDRESS);
    private static final FunctionDescriptor QUANTIZE =
            FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS, JAVA_DOUBLE, ADDRESS);
    private static final FunctionDescriptor FOREIGN_QUERY =
            FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS, JAVA_INT, ADDRESS);
    private static final FunctionDescriptor FOREIGN_BYTES =
            FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS, JAVA_LONG, ADDRESS, ADDRESS);
    private static final MemoryLayout FOREIGN_STATE = MemoryLayout.structLayout(
            ADDRESS.withName("lattice"), JAVA_INT.withName("value"), JAVA_INT.withName("status"));
    private static final byte[] LATTICE_ID = "vt.lattice.val.1".getBytes(StandardCharsets.US_ASCII);
    private static final AtomicInteger FOREIGN_QUERY_ACTIVE = new AtomicInteger();
    private static final AtomicInteger FOREIGN_QUERY_PEAK = new AtomicInteger();

    ProviderAbiSmoke() {}

    /** Enforce the same complete ABI contract through the standard Gradle test lifecycle. */
    @Test
    void completeProviderContract() throws Exception {
        runContract();
    }

    /** Run the ABI suite; any failed invariant terminates the Gradle task. */
    public static void main(String[] arguments) throws Exception {
        runContract();
        System.out.println("JVM provider ABI smoke suite passed");
    }

    private static void runContract() throws Exception {
        testLayouts();
        testDictionary();
        testWfst();
        testLattice();
        testForeignLattice();
        testSemiring();
        testExceptionContainment();
        testHostedResourceLifetime();
        testParallelCallbacks();
    }

    private static void testLayouts() {
        equal(16, InteropLayouts.RESOURCE.byteSize(), "resource layout");
        equal(40, InteropLayouts.RESOURCE_VTABLE.byteSize(), "resource vtable");
        equal(88, InteropLayouts.DICTIONARY_VTABLE.byteSize(), "dictionary vtable");
        equal(40, InteropLayouts.WFST_ARC.byteSize(), "WFST arc");
        equal(72, InteropLayouts.WFST_VTABLE.byteSize(), "WFST vtable");
        equal(96, InteropLayouts.LATTICE_VTABLE.byteSize(), "lattice vtable");
        equal(16, InteropLayouts.SEMIRING_VALUE.byteSize(), "semiring value");
        equal(144, InteropLayouts.SEMIRING_VTABLE.byteSize(), "semiring vtable");
        equal(32, InteropLayouts.SEMIRING_DIVISION_VTABLE.byteSize(), "division vtable");
        equal(24, InteropLayouts.SEMIRING_STAR_VTABLE.byteSize(), "star vtable");
        equal(40, InteropLayouts.SEMIRING_NUMERIC_VTABLE.byteSize(), "numeric vtable");
        equal(32, InteropLayouts.SEMIRING_PROPERTIES_VTABLE.byteSize(), "properties vtable");
        equal(8, InteropLayouts.RESOURCE.byteAlignment(), "resource alignment");
        equal(8, InteropLayouts.RESOURCE.byteOffset(groupElement("vtable")), "resource vtable offset");
        equal(32, InteropLayouts.WFST_VTABLE.byteOffset(groupElement("snapshot")), "WFST snapshot offset");
        equal(64, InteropLayouts.WFST_VTABLE.byteOffset(groupElement("state_arcs")), "WFST arcs offset");
        equal(40, InteropLayouts.LATTICE_VTABLE.byteOffset(groupElement("join")), "lattice join offset");
        equal(136, InteropLayouts.SEMIRING_VTABLE.byteOffset(groupElement("times_many")), "times-many offset");
    }

    private static void testDictionary() {
        UnicodeDictionarySnapshot snapshot = new TinyDictionary();
        try (Arena arena = Arena.ofConfined();
                UnicodeDictionaryResource resource = new UnicodeDictionaryResource(() -> snapshot)) {
            MemorySegment descriptor = resource.resourceSegment();
            MemorySegment table = query(arena, descriptor, "vt.dictionary.v1", 1, OK);
            equal(1, table.get(JAVA_INT, 8), "dictionary interface version");
            equal(2, table.get(JAVA_INT, 12), "dictionary unit domain");

            MemorySegment root = arena.allocate(JAVA_LONG);
            equal(OK, call(table.get(ADDRESS, 40), CONTEXT_OUT, context(descriptor), root), "dictionary root status");
            equal(0, root.get(JAVA_LONG, 0), "dictionary root");

            MemorySegment count = arena.allocate(JAVA_LONG);
            MemorySegment known = arena.allocate(JAVA_BYTE);
            equal(OK, call(table.get(ADDRESS, 48), CONTEXT_TWO_OUT, context(descriptor), count, known), "dictionary len");
            equal(1, count.get(JAVA_LONG, 0), "dictionary len value");
            equal(1, known.get(JAVA_BYTE, 0), "dictionary len known");

            MemorySegment terminal = arena.allocate(JAVA_BYTE);
            equal(
                    OK,
                    call(table.get(ADDRESS, 56), CONTEXT_VALUE_OUT, context(descriptor), 1L, terminal),
                    "dictionary finality");
            equal(1, terminal.get(JAVA_BYTE, 0), "dictionary final value");
            MemorySegment optionalValue = arena.allocate(InteropLayouts.OPTIONAL_U64);
            equal(
                    OK,
                    call(table.get(ADDRESS, 64), CONTEXT_VALUE_OUT, context(descriptor), 1L, optionalValue),
                    "dictionary value");
            equal(9, optionalValue.get(JAVA_LONG, 0), "dictionary stored value");
            equal(1, optionalValue.get(JAVA_BYTE, 8), "dictionary value presence");
            terminal.set(JAVA_BYTE, 0, (byte) 0x5a);
            equal(
                    INVALID_ARGUMENT,
                    call(table.get(ADDRESS, 56), CONTEXT_VALUE_OUT, context(descriptor), 99L, terminal),
                    "dictionary unknown node");
            equal(0x5a, Byte.toUnsignedInt(terminal.get(JAVA_BYTE, 0)), "unknown node leaves output untouched");

            MemorySegment child = arena.allocate(JAVA_LONG);
            MemorySegment found = arena.allocate(JAVA_BYTE);
            equal(
                    OK,
                    call(
                            table.get(ADDRESS, 72),
                            CONTEXT_TWO_VALUES_OUT,
                            context(descriptor),
                            0L,
                            (long) 'a',
                            child,
                            found),
                    "dictionary transition");
            equal(1, child.get(JAVA_LONG, 0), "dictionary child");
            equal(1, found.get(JAVA_BYTE, 0), "dictionary found");
            equal(
                    INVALID_ARGUMENT,
                    call(
                            table.get(ADDRESS, 72),
                            CONTEXT_TWO_VALUES_OUT,
                            context(descriptor),
                            0L,
                            0xd800L,
                            child,
                            found),
                    "dictionary rejects surrogate labels");

            MemorySegment edges = arena.allocate(InteropLayouts.DICTIONARY_EDGE, 2);
            MemorySegment written = arena.allocate(JAVA_LONG);
            MemorySegment total = arena.allocate(JAVA_LONG);
            equal(
                    OK,
                    call(
                            table.get(ADDRESS, 80),
                            PAGE,
                            context(descriptor),
                            0L,
                            0L,
                            edges,
                            2L,
                            written,
                            total),
                    "dictionary edges");
            equal(1, written.get(JAVA_LONG, 0), "dictionary edges written");
            equal(1, total.get(JAVA_LONG, 0), "dictionary edges total");
            equal('a', edges.get(JAVA_LONG, 0), "dictionary edge label");
            equal(1, edges.get(JAVA_LONG, 8), "dictionary edge node");
            equal(
                    OK,
                    call(
                            table.get(ADDRESS, 80),
                            PAGE,
                            context(descriptor),
                            0L,
                            99L,
                            MemorySegment.NULL,
                            0L,
                            written,
                            total),
                    "past-end dictionary page");
            equal(0, written.get(JAVA_LONG, 0), "past-end dictionary page is empty");
            equal(
                    LIMIT_EXCEEDED,
                    call(
                            table.get(ADDRESS, 80),
                            PAGE,
                            context(descriptor),
                            0L,
                            Long.MIN_VALUE,
                            MemorySegment.NULL,
                            0L,
                            written,
                            total),
                    "unsigned dictionary start is bounded");

            MemorySegment captured = arena.allocate(InteropLayouts.RESOURCE);
            equal(OK, call(table.get(ADDRESS, 32), CONTEXT_OUT, context(descriptor), captured), "dictionary snapshot");
            resource.close();
            MemorySegment immutable = query(arena, captured, "vt.dictionary.v1", 1, OK);
            equal(4, immutable.get(JAVA_LONG, 24), "captured dictionary is immutable");
            release(captured);
            expectThrows(IllegalStateException.class, resource::resourceSegment, "closed dictionary facade");
        }
    }

    private static void testWfst() {
        ScalarWfstProvider provider = new PagedWfst();
        ScalarWfstOptions options = new ScalarWfstOptions(
                DictionaryUnitDomain.UNICODE_SCALAR,
                ScalarWeightDomain.TROPICAL_F64,
                ScalarWfstOptions.PARALLEL_REENTRANT | ScalarWfstOptions.ACYCLIC);
        try (Arena arena = Arena.ofConfined();
                HostedResource resource = HostProviders.scalarWfst(provider, options)) {
            MemorySegment descriptor = resource.resourceSegment();
            MemorySegment table = query(arena, descriptor, "vt.scalar-wfst.1", 1, OK);
            query(arena, descriptor, "vt.scalar-wfst.1", -1, UNSUPPORTED);
            MemorySegment start = arena.allocate(JAVA_LONG);
            equal(OK, call(table.get(ADDRESS, 40), CONTEXT_OUT, context(descriptor), start), "WFST start");
            equal(0, start.get(JAVA_LONG, 0), "WFST start state");

            MemorySegment count = arena.allocate(JAVA_LONG);
            MemorySegment known = arena.allocate(JAVA_BYTE);
            equal(OK, call(table.get(ADDRESS, 48), CONTEXT_TWO_OUT, context(descriptor), count, known), "WFST count");
            equal(2, count.get(JAVA_LONG, 0), "WFST state count");
            equal(1, known.get(JAVA_BYTE, 0), "WFST count known");

            MemorySegment valid = arena.allocate(JAVA_BYTE);
            MemorySegment terminal = arena.allocate(JAVA_BYTE);
            MemorySegment weight = arena.allocate(JAVA_DOUBLE);
            FunctionDescriptor stateInfo =
                    FunctionDescriptor.of(JAVA_INT, ADDRESS, JAVA_LONG, ADDRESS, ADDRESS, ADDRESS);
            equal(
                    OK,
                    call(table.get(ADDRESS, 56), stateInfo, context(descriptor), 1L, valid, terminal, weight),
                    "WFST state info");
            equal(1, valid.get(JAVA_BYTE, 0), "WFST valid state");
            equal(1, terminal.get(JAVA_BYTE, 0), "WFST final state");
            equal(
                    OK,
                    call(table.get(ADDRESS, 56), stateInfo, context(descriptor), 0L, valid, terminal, weight),
                    "WFST non-final NaN sentinel");
            check(Double.isNaN(weight.get(JAVA_DOUBLE, 0)), "non-final weight is ignored");

            MemorySegment arcs = arena.allocate(InteropLayouts.WFST_ARC, 2);
            MemorySegment written = arena.allocate(JAVA_LONG);
            MemorySegment total = arena.allocate(JAVA_LONG);
            equal(
                    OK,
                    call(table.get(ADDRESS, 64), PAGE, context(descriptor), 0L, 0L, arcs, 2L, written, total),
                    "WFST arcs");
            equal(2, written.get(JAVA_LONG, 0), "WFST arcs written");
            equal(2, total.get(JAVA_LONG, 0), "WFST arcs total");
            equal('a', arcs.get(JAVA_LONG, 0), "WFST input label");
            equal(0, arcs.get(JAVA_BYTE, 33), "WFST epsilon output");
            equal(
                    INVALID_ARGUMENT,
                    call(table.get(ADDRESS, 64), PAGE, context(descriptor), 99L, 0L, arcs, 2L, written, total),
                    "WFST unknown state");
            equal(
                    LIMIT_EXCEEDED,
                    call(
                            table.get(ADDRESS, 64),
                            PAGE,
                            context(descriptor),
                            0L,
                            0L,
                            MemorySegment.NULL,
                            Long.MIN_VALUE,
                            written,
                            total),
                    "unsigned WFST capacity is bounded");

            MemorySegment snapshot = arena.allocate(InteropLayouts.RESOURCE);
            equal(OK, call(table.get(ADDRESS, 32), CONTEXT_OUT, context(descriptor), snapshot), "WFST snapshot");
            resource.close();
            MemorySegment retainedTable = query(arena, snapshot, "vt.scalar-wfst.1", 1, OK);
            equal(OK, call(retainedTable.get(ADDRESS, 40), CONTEXT_OUT, context(snapshot), start), "retained WFST");
            release(snapshot);
        }
    }

    private static void testLattice() {
        DomainId domain = DomainId.fromAscii("test.integer.lat");
        try (Arena arena = Arena.ofConfined();
                HostedResource left = HostProviders.lattice(new IntegerLattice(7), new LatticeOptions(domain));
                HostedResource right = HostProviders.lattice(new IntegerLattice(11), new LatticeOptions(domain))) {
            MemorySegment leftTable = query(arena, left.resourceSegment(), "vt.lattice.val.1", 1, OK);
            MemorySegment result = arena.allocate(InteropLayouts.RESOURCE);
            equal(
                    OK,
                    call(
                            leftTable.get(ADDRESS, 40),
                            CONTEXT_TWO_OUT,
                            context(left.resourceSegment()),
                            right.resourceSegment(),
                            result),
                    "lattice join");
            byte[] stable = readResourceBytes(arena, result, 64, "lattice result");
            equal(11, ByteBuffer.wrap(stable).getInt(), "lattice join value");

            MemorySegment equal = arena.allocate(JAVA_BYTE);
            equal(
                    OK,
                    call(
                            leftTable.get(ADDRESS, 56),
                            CONTEXT_TWO_OUT,
                            context(left.resourceSegment()),
                            left.resourceSegment(),
                            equal),
                    "lattice equality");
            equal(1, equal.get(JAVA_BYTE, 0), "lattice equality result");
            release(result);

            MemorySegment meet = arena.allocate(InteropLayouts.RESOURCE);
            equal(
                    OK,
                    call(
                            leftTable.get(ADDRESS, 48),
                            CONTEXT_TWO_OUT,
                            context(left.resourceSegment()),
                            right.resourceSegment(),
                            meet),
                    "lattice meet");
            equal(7, ByteBuffer.wrap(readResourceBytes(arena, meet, 64, "lattice meet result")).getInt(),
                    "lattice meet value");
            release(meet);

            byte[] diagnostic = readResourceBytes(arena, left.resourceSegment(), 72, "lattice diagnostic");
            check(new String(diagnostic, java.nio.charset.StandardCharsets.UTF_8).equals("7"),
                    "lattice diagnostic value");

            MemorySegment operands = arena.allocate(InteropLayouts.RESOURCE, 2);
            MemorySegment.copy(right.resourceSegment(), 0, operands, 0, 16);
            MemorySegment.copy(left.resourceSegment(), 0, operands, 16, 16);
            MemorySegment folded = arena.allocate(InteropLayouts.RESOURCE);
            equal(
                    OK,
                    call(leftTable.get(ADDRESS, 80), FOLD, context(left.resourceSegment()), operands, 2L, folded),
                    "lattice join-many");
            equal(11, ByteBuffer.wrap(readResourceBytes(arena, folded, 64, "lattice fold result")).getInt(),
                    "lattice join-many value");
            release(folded);
            equal(
                    OK,
                    call(leftTable.get(ADDRESS, 88), FOLD, context(left.resourceSegment()), MemorySegment.NULL, 0L, folded),
                    "empty lattice meet-many retains receiver");
            release(folded);
            folded.fill((byte) 0x5a);
            equal(
                    LIMIT_EXCEEDED,
                    call(leftTable.get(ADDRESS, 80), FOLD, context(left.resourceSegment()), operands, 257L, folded),
                    "lattice batch bound");
            equal(0x5a, Byte.toUnsignedInt(folded.get(JAVA_BYTE, 0)), "bounded fold leaves output untouched");

            try (HostedResource limited = HostProviders.lattice(
                    new LimitLattice(), new LatticeOptions(domain))) {
                folded.fill((byte) 0x5a);
                equal(
                        LIMIT_EXCEEDED,
                        call(
                                leftTable.get(ADDRESS, 40),
                                CONTEXT_TWO_OUT,
                                context(left.resourceSegment()),
                                limited.resourceSegment(),
                                folded),
                        "lattice provider status is preserved");
                equal(0x5a, Byte.toUnsignedInt(folded.get(JAVA_BYTE, 0)), "failed lattice result is atomic");
            }

            try (HostedResource wrong = HostProviders.lattice(
                    new IntegerLattice(3), new LatticeOptions(DomainId.fromAscii("other.integer.lt")))) {
                MemorySegment output = arena.allocate(InteropLayouts.RESOURCE);
                output.fill((byte) 0x5a);
                equal(
                        INVALID_ARGUMENT,
                        call(
                                leftTable.get(ADDRESS, 40),
                                CONTEXT_TWO_OUT,
                                context(left.resourceSegment()),
                                wrong.resourceSegment(),
                                output),
                        "lattice domain mismatch");
                equal(0x5a, Byte.toUnsignedInt(output.get(JAVA_BYTE, 0)), "failed join leaves output untouched");
            }
        }
    }

    private static void testSemiring() {
        SemiringOptions options = new SemiringOptions(
                DomainId.fromAscii("test.probability"),
                SemiringOptions.PARALLEL_REENTRANT,
                SemiringOptions.COMMUTATIVE_TIMES
                        | SemiringOptions.TOTALLY_ORDERED
                        | SemiringOptions.NONNEGATIVE,
                OptionalLong.of(8));
        ProbabilitySemiring provider = new ProbabilitySemiring();
        try (Arena arena = Arena.ofConfined();
                HostedResource resource =
                        HostProviders.semiring(provider, options, SemiringValueCodec.doubles())) {
            MemorySegment descriptor = resource.resourceSegment();
            MemorySegment table = query(arena, descriptor, "vt.semiring.val1", 1, OK);
            MemorySegment zero = arena.allocate(InteropLayouts.SEMIRING_VALUE);
            MemorySegment one = arena.allocate(InteropLayouts.SEMIRING_VALUE);
            MemorySegment sum = arena.allocate(InteropLayouts.SEMIRING_VALUE);
            equal(OK, call(table.get(ADDRESS, 40), CONTEXT_OUT, context(descriptor), zero), "semiring zero");
            equal(OK, call(table.get(ADDRESS, 48), CONTEXT_OUT, context(descriptor), one), "semiring one");
            equal(
                    OK,
                    call(table.get(ADDRESS, 72), FOUR_ADDRESSES, context(descriptor), zero, one, sum),
                    "semiring plus");

            MemorySegment clone = arena.allocate(InteropLayouts.SEMIRING_VALUE);
            equal(
                    OK,
                    call(table.get(ADDRESS, 56), CONTEXT_TWO_OUT, context(descriptor), one, clone),
                    "semiring clone");
            MemorySegment product = arena.allocate(InteropLayouts.SEMIRING_VALUE);
            equal(
                    OK,
                    call(table.get(ADDRESS, 80), FOUR_ADDRESSES, context(descriptor), one, one, product),
                    "semiring times");
            MemorySegment exact = arena.allocate(JAVA_BYTE);
            equal(
                    OK,
                    call(table.get(ADDRESS, 88), FOUR_ADDRESSES, context(descriptor), clone, product, exact),
                    "semiring exact equality");
            equal(1, exact.get(JAVA_BYTE, 0), "semiring exact equality value");

            MemorySegment comparison = arena.allocate(JAVA_INT);
            equal(
                    OK,
                    call(table.get(ADDRESS, 104), FOUR_ADDRESSES, context(descriptor), zero, one, comparison),
                    "semiring natural order");
            equal(SemiringOrder.BETTER.wireValue(), comparison.get(JAVA_INT, 0), "semiring order value");

            MemorySegment approximatelyEqual = arena.allocate(JAVA_BYTE);
            equal(
                    OK,
                    call(
                            table.get(ADDRESS, 96),
                            APPROX,
                            context(descriptor),
                            one,
                            sum,
                            0.0,
                            approximatelyEqual),
                    "semiring approximate equality");
            equal(1, approximatelyEqual.get(JAVA_BYTE, 0), "semiring approximate equality value");

            byte[] stable = readValueBytes(arena, descriptor, table.get(ADDRESS, 112), sum, "semiring stable bytes");
            equal(Double.doubleToRawLongBits(1.0), ByteBuffer.wrap(stable).getLong(), "semiring stable encoding");
            byte[] semiringDiagnostic =
                    readValueBytes(arena, descriptor, table.get(ADDRESS, 120), sum, "semiring diagnostic");
            check(new String(semiringDiagnostic, java.nio.charset.StandardCharsets.UTF_8).equals("1.0"),
                    "semiring diagnostic value");

            MemorySegment division = query(arena, descriptor, "vt.semiring.div1", 1, OK);
            MemorySegment quotient = arena.allocate(InteropLayouts.SEMIRING_VALUE);
            equal(
                    OK,
                    call(division.get(ADDRESS, 16), FOUR_ADDRESSES, context(descriptor), one, one, quotient),
                    "semiring division");
            MemorySegment undefinedQuotient = arena.allocate(InteropLayouts.SEMIRING_VALUE);
            undefinedQuotient.fill((byte) 0x5a);
            equal(
                    END,
                    call(
                            division.get(ADDRESS, 16),
                            FOUR_ADDRESSES,
                            context(descriptor),
                            one,
                            zero,
                            undefinedQuotient),
                    "undefined semiring division");
            equal(0x5a, Byte.toUnsignedInt(undefinedQuotient.get(JAVA_BYTE, 0)),
                    "undefined division publishes no token");
            MemorySegment star = query(arena, descriptor, "vt.semiring.str1", 1, OK);
            MemorySegment closure = arena.allocate(InteropLayouts.SEMIRING_VALUE);
            equal(OK, call(star.get(ADDRESS, 16), CONTEXT_TWO_OUT, context(descriptor), zero, closure), "semiring star");
            MemorySegment divergent = arena.allocate(InteropLayouts.SEMIRING_VALUE);
            divergent.fill((byte) 0x5a);
            equal(END, call(star.get(ADDRESS, 16), CONTEXT_TWO_OUT, context(descriptor), one, divergent),
                    "divergent semiring star");
            equal(0x5a, Byte.toUnsignedInt(divergent.get(JAVA_BYTE, 0)), "divergent star publishes no token");

            MemorySegment numeric = query(arena, descriptor, "vt.semiring.num1", 1, OK);
            MemorySegment number = arena.allocate(JAVA_DOUBLE);
            equal(OK, call(numeric.get(ADDRESS, 16), CONTEXT_TWO_OUT, context(descriptor), one, number), "numeric value");
            equal(Double.doubleToRawLongBits(1.0), Double.doubleToRawLongBits(number.get(JAVA_DOUBLE, 0)), "numeric result");
            MemorySegment quantized = arena.allocate(JAVA_LONG);
            equal(
                    OK,
                    call(numeric.get(ADDRESS, 24), QUANTIZE, context(descriptor), one, 0.25, quantized),
                    "semiring quantize");
            equal(4, quantized.get(JAVA_LONG, 0), "semiring quantized value");

            MemorySegment properties = query(arena, descriptor, "vt.semiring.prp1", 1, OK);
            equal(options.properties(), properties.get(JAVA_LONG, 16), "semiring property bits");
            MemorySegment bound = arena.allocate(JAVA_LONG);
            MemorySegment known = arena.allocate(JAVA_BYTE);
            equal(
                    OK,
                    call(properties.get(ADDRESS, 24), CONTEXT_TWO_OUT, context(descriptor), bound, known),
                    "semiring closure bound");
            equal(8, bound.get(JAVA_LONG, 0), "semiring closure bound value");
            equal(1, known.get(JAVA_BYTE, 0), "semiring closure bound known");

            approximatelyEqual.set(JAVA_BYTE, 0, (byte) 0x5a);
            equal(
                    INVALID_ARGUMENT,
                    call(
                            table.get(ADDRESS, 96),
                            APPROX,
                            context(descriptor),
                            one,
                            sum,
                            Double.NaN,
                            approximatelyEqual),
                    "invalid approximate-equality epsilon");
            equal(0x5a, Byte.toUnsignedInt(approximatelyEqual.get(JAVA_BYTE, 0)),
                    "invalid epsilon leaves output untouched");

            MemorySegment values = arena.allocate(InteropLayouts.SEMIRING_VALUE, 3);
            copyValue(zero, values.asSlice(0, 16));
            copyValue(one, values.asSlice(16, 16));
            copyValue(one, values.asSlice(32, 16));
            MemorySegment folded = arena.allocate(InteropLayouts.SEMIRING_VALUE);
            equal(OK, call(table.get(ADDRESS, 128), FOLD, context(descriptor), values, 3L, folded), "semiring fold");
            byte[] foldedStable =
                    readValueBytes(arena, descriptor, table.get(ADDRESS, 112), folded, "folded stable bytes");
            equal(Double.doubleToRawLongBits(2.0), ByteBuffer.wrap(foldedStable).getLong(), "semiring fold result");
            MemorySegment multiplied = arena.allocate(InteropLayouts.SEMIRING_VALUE);
            equal(
                    OK,
                    call(table.get(ADDRESS, 136), FOLD, context(descriptor), values, 3L, multiplied),
                    "semiring times-many");
            equal(
                    LIMIT_EXCEEDED,
                    call(table.get(ADDRESS, 128), FOLD, context(descriptor), values, 257L, folded),
                    "semiring fold bound");

            MemorySegment duplicate = arena.allocate(InteropLayouts.SEMIRING_VALUE, 2);
            copyValue(one, duplicate.asSlice(0, 16));
            copyValue(one, duplicate.asSlice(16, 16));
            equal(
                    INVALID_ARGUMENT,
                    call(table.get(ADDRESS, 64), RELEASE_VALUES, context(descriptor), duplicate, 2L),
                    "duplicate primitive release is transactional");
            MemorySegment rollbackOutput = arena.allocate(InteropLayouts.SEMIRING_VALUE);
            equal(
                    OK,
                    call(table.get(ADDRESS, 72), FOUR_ADDRESSES, context(descriptor), one, one, rollbackOutput),
                    "failed primitive release rolls back every lease");

            MemorySegment releases = arena.allocate(InteropLayouts.SEMIRING_VALUE, 10);
            copyValue(zero, releases.asSlice(0, 16));
            copyValue(one, releases.asSlice(16, 16));
            copyValue(sum, releases.asSlice(32, 16));
            copyValue(quotient, releases.asSlice(48, 16));
            copyValue(closure, releases.asSlice(64, 16));
            copyValue(folded, releases.asSlice(80, 16));
            copyValue(clone, releases.asSlice(96, 16));
            copyValue(product, releases.asSlice(112, 16));
            copyValue(multiplied, releases.asSlice(128, 16));
            copyValue(rollbackOutput, releases.asSlice(144, 16));
            equal(OK, call(table.get(ADDRESS, 64), RELEASE_VALUES, context(descriptor), releases, 10L), "semiring release");
            equal(0, releases.get(JAVA_LONG, 8), "released semiring value is zeroed");
            equal(
                    INVALID_ARGUMENT,
                    call(table.get(ADDRESS, 72), FOUR_ADDRESSES, context(descriptor), one, one, sum),
                    "stale primitive token");

            try (HostedResource foreign = HostProviders.semiring(
                    new ProbabilitySemiring(),
                    new SemiringOptions(DomainId.fromAscii("other.integer.lt")),
                    SemiringValueCodec.doubles())) {
                MemorySegment foreignTable = query(arena, foreign.resourceSegment(), "vt.semiring.val1", 1, OK);
                MemorySegment foreignValue = arena.allocate(InteropLayouts.SEMIRING_VALUE);
                equal(OK, call(foreignTable.get(ADDRESS, 48), CONTEXT_OUT, context(foreign.resourceSegment()), foreignValue), "foreign semiring one");
                equal(
                        INVALID_ARGUMENT,
                        call(table.get(ADDRESS, 72), FOUR_ADDRESSES, context(descriptor), foreignValue, foreignValue, sum),
                        "cross-context semiring tokens");
                equal(
                        OK,
                        call(
                                foreignTable.get(ADDRESS, 64),
                                RELEASE_VALUES,
                                context(foreign.resourceSegment()),
                                foreignValue,
                                1L),
                        "foreign semiring release");
            }
        }

        testGenericSemiringTokens(options);
    }

    private static void testForeignLattice() throws Exception {
        DomainId domain = DomainId.fromAscii("test.integer.lat");
        try (Arena arena = Arena.ofShared();
                HostedResource left = HostProviders.lattice(
                        new IntegerLattice(7),
                        new LatticeOptions(domain, LatticeOptions.PARALLEL_REENTRANT))) {
            ForeignLattice foreign = foreignLattice(arena, domain, 11, OK, true);
            MemorySegment leftDescriptor = left.resourceSegment();
            MemorySegment leftTable = query(arena, leftDescriptor, "vt.lattice.val.1", 1, OK);
            MemorySegment result = arena.allocate(InteropLayouts.RESOURCE);
            equal(
                    OK,
                    call(
                            leftTable.get(ADDRESS, 40),
                            CONTEXT_TWO_OUT,
                            context(leftDescriptor),
                            foreign.resource(),
                            result),
                    "foreign lattice join");
            equal(11, ByteBuffer.wrap(readResourceBytes(arena, result, 64, "foreign lattice result")).getInt(),
                    "foreign lattice value");
            release(result);

            ForeignLattice unsupported = foreignLattice(arena, domain, 11, OK, false);
            result.fill((byte) 0x5a);
            equal(
                    UNSUPPORTED,
                    call(
                            leftTable.get(ADDRESS, 40),
                            CONTEXT_TWO_OUT,
                            context(leftDescriptor),
                            unsupported.resource(),
                            result),
                    "foreign lattice requires an interpretable representation");
            equal(0x5a, Byte.toUnsignedInt(result.get(JAVA_BYTE, 0)),
                    "unsupported foreign lattice leaves output untouched");

            ForeignLattice failing = foreignLattice(arena, domain, 11, IO_ERROR, true);
            result.fill((byte) 0x5a);
            equal(
                    IO_ERROR,
                    call(
                            leftTable.get(ADDRESS, 40),
                            CONTEXT_TWO_OUT,
                            context(leftDescriptor),
                            failing.resource(),
                            result),
                    "foreign lattice status forwarding");
            equal(0x5a, Byte.toUnsignedInt(result.get(JAVA_BYTE, 0)),
                    "foreign lattice failure leaves output untouched");

            FOREIGN_QUERY_ACTIVE.set(0);
            FOREIGN_QUERY_PEAK.set(0);
            int workers = 8;
            int iterations = 40;
            CountDownLatch start = new CountDownLatch(1);
            AtomicReference<Throwable> failure = new AtomicReference<>();
            try (ExecutorService executor = Executors.newFixedThreadPool(workers)) {
                for (int worker = 0; worker < workers; worker++) {
                    executor.execute(() -> {
                        try {
                            start.await();
                            for (int iteration = 0; iteration < iterations; iteration++) {
                                MemorySegment output = arena.allocate(InteropLayouts.RESOURCE);
                                equal(
                                        OK,
                                        call(
                                                leftTable.get(ADDRESS, 40),
                                                CONTEXT_TWO_OUT,
                                                context(leftDescriptor),
                                                foreign.resource(),
                                                output),
                                        "serialized foreign lattice join");
                                release(output);
                            }
                        } catch (Throwable problem) {
                            failure.compareAndSet(null, problem);
                        }
                    });
                }
                start.countDown();
                executor.shutdown();
                check(executor.awaitTermination(30, TimeUnit.SECONDS), "foreign lattice timeout");
            }
            if (failure.get() != null) throw new AssertionError("foreign lattice concurrency failure", failure.get());
            equal(1, FOREIGN_QUERY_PEAK.get(), "unflagged foreign query serialization");
        }
    }

    private static void testGenericSemiringTokens(SemiringOptions options) {
        SemiringProvider<String> strings = new StringSemiring();
        try (Arena arena = Arena.ofConfined();
                HostedResource resource = HostProviders.semiring(strings, options)) {
            MemorySegment descriptor = resource.resourceSegment();
            MemorySegment table = query(arena, descriptor, "vt.semiring.val1", 1, OK);
            MemorySegment value = arena.allocate(InteropLayouts.SEMIRING_VALUE);
            MemorySegment duplicate = arena.allocate(InteropLayouts.SEMIRING_VALUE, 2);
            equal(OK, call(table.get(ADDRESS, 48), CONTEXT_OUT, context(descriptor), value), "generic semiring one");
            copyValue(value, duplicate.asSlice(0, 16));
            copyValue(value, duplicate.asSlice(16, 16));
            equal(
                    INVALID_ARGUMENT,
                    call(table.get(ADDRESS, 64), RELEASE_VALUES, context(descriptor), duplicate, 2L),
                    "duplicate generic release is transactional");
            MemorySegment output = arena.allocate(InteropLayouts.SEMIRING_VALUE);
            equal(
                    OK,
                    call(table.get(ADDRESS, 72), FOUR_ADDRESSES, context(descriptor), value, value, output),
                    "failed release rolls back all generic leases");
            MemorySegment releases = arena.allocate(InteropLayouts.SEMIRING_VALUE, 2);
            copyValue(value, releases.asSlice(0, 16));
            copyValue(output, releases.asSlice(16, 16));
            equal(OK, call(table.get(ADDRESS, 64), RELEASE_VALUES, context(descriptor), releases, 2L), "generic release");
            equal(
                    INVALID_ARGUMENT,
                    call(table.get(ADDRESS, 72), FOUR_ADDRESSES, context(descriptor), value, value, output),
                    "stale generic token");
        }
    }

    private static void testExceptionContainment() {
        ScalarWfstProvider failing = new TinyWfst() {
            @Override
            public long startState() {
                throw new IllegalStateException("deliberate callback failure");
            }
        };
        try (Arena arena = Arena.ofConfined();
                HostedResource resource = HostProviders.scalarWfst(failing)) {
            MemorySegment descriptor = resource.resourceSegment();
            MemorySegment table = query(arena, descriptor, "vt.scalar-wfst.1", 1, OK);
            MemorySegment output = arena.allocate(JAVA_LONG);
            output.set(JAVA_LONG, 0, 0x5a5a5a5aL);
            equal(
                    PROVIDER_ERROR,
                    call(table.get(ADDRESS, 40), CONTEXT_OUT, context(descriptor), output),
                    "exception containment");
            equal(0x5a5a5a5aL, output.get(JAVA_LONG, 0), "failed callback leaves output untouched");
            check(resource.lastCallbackError() instanceof IllegalStateException, "provider fault is observable");
        }

        ScalarWfstProvider portableFailure = new TinyWfst() {
            @Override
            public long startState() {
                throw new ProviderException(ProviderException.Status.IO_ERROR, "backing store failed");
            }
        };
        try (Arena arena = Arena.ofConfined();
                HostedResource resource = HostProviders.scalarWfst(portableFailure)) {
            MemorySegment descriptor = resource.resourceSegment();
            MemorySegment table = query(arena, descriptor, "vt.scalar-wfst.1", 1, OK);
            MemorySegment output = arena.allocate(JAVA_LONG);
            output.set(JAVA_LONG, 0, 0x5a5a5a5aL);
            equal(IO_ERROR, call(table.get(ADDRESS, 40), CONTEXT_OUT, context(descriptor), output),
                    "intentional provider status");
            equal(0x5a5a5a5aL, output.get(JAVA_LONG, 0), "portable failure leaves output untouched");
        }
    }

    private static void testHostedResourceLifetime() throws Exception {
        HostedResource resource = HostProviders.scalarWfst(new TinyWfst());
        MemorySegment descriptor = resource.resourceSegment();
        MemorySegment staleContext = context(descriptor);
        MemorySegment base = descriptor.get(ADDRESS, 8).reinterpret(InteropLayouts.RESOURCE_VTABLE.byteSize());
        CountDownLatch borrowed = new CountDownLatch(1);
        CountDownLatch closed = new CountDownLatch(1);
        try (ExecutorService executor = Executors.newSingleThreadExecutor()) {
            Future<Long> result = executor.submit(() -> resource.withResourceSegment(live -> {
                borrowed.countDown();
                try {
                    check(closed.await(10, TimeUnit.SECONDS), "close race timeout");
                } catch (InterruptedException failure) {
                    Thread.currentThread().interrupt();
                    throw new AssertionError(failure);
                }
                try (Arena arena = Arena.ofConfined()) {
                    MemorySegment table = query(arena, live, "vt.scalar-wfst.1", 1, OK);
                    MemorySegment output = arena.allocate(JAVA_LONG);
                    equal(OK, call(table.get(ADDRESS, 40), CONTEXT_OUT, context(live), output),
                            "retained operation survives facade close");
                    return output.get(JAVA_LONG, 0);
                }
            }));
            check(borrowed.await(10, TimeUnit.SECONDS), "borrow acquisition timeout");
            resource.close();
            resource.close();
            closed.countDown();
            equal(0, result.get(10, TimeUnit.SECONDS), "close-race result");
        }
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment id = arena.allocateFrom(JAVA_BYTE, "vt.scalar-wfst.1".getBytes(
                    java.nio.charset.StandardCharsets.US_ASCII));
            MemorySegment output = arena.allocate(ADDRESS);
            output.set(ADDRESS, 0, MemorySegment.ofAddress(0x55));
            equal(
                    INVALID_ARGUMENT,
                    call(base.get(ADDRESS, 32), BASE_QUERY, staleContext, id, 1, output),
                    "stale provider handle");
            equal(0x55, output.get(ADDRESS, 0).address(), "stale query leaves output untouched");
        }
    }

    private static void testParallelCallbacks() throws Exception {
        try (HostedResource resource = HostProviders.scalarWfst(
                new TinyWfst(),
                new ScalarWfstOptions(
                        DictionaryUnitDomain.UNICODE_SCALAR,
                        ScalarWeightDomain.TROPICAL_F64,
                        ScalarWfstOptions.PARALLEL_REENTRANT))) {
            int workers = 8;
            int iterations = 1_000;
            CountDownLatch start = new CountDownLatch(1);
            AtomicReference<Throwable> failure = new AtomicReference<>();
            try (ExecutorService executor = Executors.newFixedThreadPool(workers)) {
                for (int worker = 0; worker < workers; worker++) {
                    executor.execute(() -> {
                        try {
                            start.await();
                            for (int iteration = 0; iteration < iterations; iteration++) {
                                resource.withResourceSegment(descriptor -> {
                                    try (Arena arena = Arena.ofConfined()) {
                                        MemorySegment table = query(arena, descriptor, "vt.scalar-wfst.1", 1, OK);
                                        MemorySegment output = arena.allocate(JAVA_LONG);
                                        equal(
                                                OK,
                                                call(table.get(ADDRESS, 40), CONTEXT_OUT, context(descriptor), output),
                                                "parallel WFST start");
                                        equal(0, output.get(JAVA_LONG, 0), "parallel WFST value");
                                    }
                                });
                            }
                        } catch (Throwable problem) {
                            failure.compareAndSet(null, problem);
                        }
                    });
                }
                start.countDown();
                executor.shutdown();
                check(executor.awaitTermination(30, TimeUnit.SECONDS), "parallel callback timeout");
            }
            if (failure.get() != null) throw new AssertionError("parallel callback failure", failure.get());
        }
    }

    private static MemorySegment query(
            Arena arena,
            MemorySegment resource,
            String identifier,
            int minimumVersion,
            int expectedStatus) {
        MemorySegment id = arena.allocate(16, 1);
        MemorySegment.copy(identifier.getBytes(java.nio.charset.StandardCharsets.US_ASCII), 0, id, JAVA_BYTE, 0, 16);
        MemorySegment output = arena.allocate(ADDRESS);
        output.set(ADDRESS, 0, MemorySegment.ofAddress(0x55));
        MemorySegment base = resource.get(ADDRESS, 8).reinterpret(InteropLayouts.RESOURCE_VTABLE.byteSize());
        int status = call(
                base.get(ADDRESS, 32),
                BASE_QUERY,
                context(resource),
                id,
                minimumVersion,
                output);
        equal(expectedStatus, status, "query " + identifier);
        if (status != OK) {
            equal(0x55, output.get(ADDRESS, 0).address(), "unsupported query output");
            return MemorySegment.NULL;
        }
        MemorySegment address = output.get(ADDRESS, 0);
        check(address.address() != 0, "query returned a null table");
        MemorySegment prefix = address.reinterpret(JAVA_LONG.byteSize());
        return address.reinterpret(prefix.get(JAVA_LONG, 0));
    }

    private static byte[] readResourceBytes(
            Arena arena, MemorySegment resource, long operationOffset, String label) {
        MemorySegment table = query(arena, resource, "vt.lattice.val.1", 1, OK);
        MemorySegment operation = table.get(ADDRESS, operationOffset);
        return readBytes(arena, operation, RESOURCE_BYTES, context(resource), null, label);
    }

    private static byte[] readValueBytes(
            Arena arena,
            MemorySegment resource,
            MemorySegment operation,
            MemorySegment value,
            String label) {
        return readBytes(arena, operation, VALUE_BYTES, context(resource), value, label);
    }

    private static byte[] readBytes(
            Arena arena,
            MemorySegment operation,
            FunctionDescriptor descriptor,
            MemorySegment context,
            MemorySegment value,
            String label) {
        MemorySegment written = arena.allocate(JAVA_LONG);
        MemorySegment required = arena.allocate(JAVA_LONG);
        int status = value == null
                ? call(operation, descriptor, context, MemorySegment.NULL, 0L, written, required)
                : call(operation, descriptor, context, value, MemorySegment.NULL, 0L, written, required);
        equal(OK, status, label + " size");
        equal(0, written.get(JAVA_LONG, 0), label + " size write");
        long size = required.get(JAVA_LONG, 0);
        check(size >= 0 && size <= 1_048_576, label + " bounded size");
        MemorySegment output = arena.allocate(Math.max(size, 1), 1);
        status = value == null
                ? call(operation, descriptor, context, output, size, written, required)
                : call(operation, descriptor, context, value, output, size, written, required);
        equal(OK, status, label + " contents");
        equal(size, written.get(JAVA_LONG, 0), label + " complete write");
        equal(size, required.get(JAVA_LONG, 0), label + " stable size");
        return output.asSlice(0, size).toArray(JAVA_BYTE);
    }

    private static MemorySegment context(MemorySegment resource) {
        return resource.get(ADDRESS, 0);
    }

    private static ForeignLattice foreignLattice(
            Arena arena, DomainId domain, int value, int stableStatus, boolean stable) {
        try {
            MemorySegment query = LINKER.upcallStub(
                    MethodHandles.lookup().findStatic(
                            ProviderAbiSmoke.class,
                            "foreignQuery",
                            MethodType.methodType(
                                    int.class,
                                    MemorySegment.class,
                                    MemorySegment.class,
                                    int.class,
                                    MemorySegment.class)),
                    FOREIGN_QUERY,
                    arena);
            MemorySegment retain = LINKER.upcallStub(
                    MethodHandles.lookup().findStatic(
                            ProviderAbiSmoke.class,
                            "foreignNoop",
                            MethodType.methodType(void.class, MemorySegment.class)),
                    VOID_CONTEXT,
                    arena);
            MemorySegment stableBytes = LINKER.upcallStub(
                    MethodHandles.lookup().findStatic(
                            ProviderAbiSmoke.class,
                            "foreignStableBytes",
                            MethodType.methodType(
                                    int.class,
                                    MemorySegment.class,
                                    MemorySegment.class,
                                    long.class,
                                    MemorySegment.class,
                                    MemorySegment.class)),
                    FOREIGN_BYTES,
                    arena);
            MemorySegment lattice = arena.allocate(InteropLayouts.LATTICE_VTABLE);
            lattice.fill((byte) 0);
            lattice.set(JAVA_LONG, 0, InteropLayouts.LATTICE_VTABLE.byteSize());
            lattice.set(JAVA_INT, 8, 1);
            lattice.set(JAVA_LONG, 16, stable ? 4 : 0);
            MemorySegment.copy(domain.bytes(), 0, lattice.asSlice(24, 16), JAVA_BYTE, 0, 16);
            lattice.set(ADDRESS, 40, retain);
            lattice.set(ADDRESS, 48, retain);
            lattice.set(ADDRESS, 56, retain);
            lattice.set(ADDRESS, 64, stable ? stableBytes : MemorySegment.NULL);
            MemorySegment base = arena.allocate(InteropLayouts.RESOURCE_VTABLE);
            base.fill((byte) 0);
            base.set(JAVA_LONG, 0, InteropLayouts.RESOURCE_VTABLE.byteSize());
            base.set(JAVA_INT, 8, 1);
            base.set(ADDRESS, 16, retain);
            base.set(ADDRESS, 24, retain);
            base.set(ADDRESS, 32, query);
            MemorySegment state = arena.allocate(FOREIGN_STATE);
            state.set(ADDRESS, 0, lattice);
            state.set(JAVA_INT, 8, value);
            state.set(JAVA_INT, 12, stableStatus);
            MemorySegment resource = arena.allocate(InteropLayouts.RESOURCE);
            resource.set(ADDRESS, 0, state);
            resource.set(ADDRESS, 8, base);
            return new ForeignLattice(resource);
        } catch (ReflectiveOperationException failure) {
            throw new AssertionError("foreign lattice fixture construction failed", failure);
        }
    }

    private static int foreignQuery(
            MemorySegment context, MemorySegment id, int minimumVersion, MemorySegment output) {
        int active = FOREIGN_QUERY_ACTIVE.incrementAndGet();
        FOREIGN_QUERY_PEAK.accumulateAndGet(active, Math::max);
        try {
            LockSupport.parkNanos(500_000L);
            if (Integer.compareUnsigned(minimumVersion, 1) > 0
                    || !ProviderRuntime.idEquals(id, LATTICE_ID)) return UNSUPPORTED;
            output.reinterpret(8).set(ADDRESS, 0, context.reinterpret(FOREIGN_STATE.byteSize()).get(ADDRESS, 0));
            return OK;
        } finally {
            FOREIGN_QUERY_ACTIVE.decrementAndGet();
        }
    }

    private static int foreignStableBytes(
            MemorySegment context,
            MemorySegment output,
            long capacity,
            MemorySegment written,
            MemorySegment required) {
        MemorySegment state = context.reinterpret(FOREIGN_STATE.byteSize());
        int status = state.get(JAVA_INT, 12);
        if (status != OK) return status;
        if (capacity < 0) return LIMIT_EXCEEDED;
        if (capacity != 0 && output.address() == 0) return 3;
        required.reinterpret(8).set(JAVA_LONG, 0, 4);
        long count = Math.min(capacity, 4);
        written.reinterpret(8).set(JAVA_LONG, 0, count);
        if (count == 4) {
            output.reinterpret(4).set(JAVA_INT.withOrder(ByteOrder.BIG_ENDIAN), 0, state.get(JAVA_INT, 8));
        }
        return OK;
    }

    private static void foreignNoop(MemorySegment context) {}

    private static void release(MemorySegment resource) {
        MemorySegment base = resource.get(ADDRESS, 8).reinterpret(InteropLayouts.RESOURCE_VTABLE.byteSize());
        invokeVoid(base.get(ADDRESS, 24), VOID_CONTEXT, context(resource));
    }

    private static int call(
            MemorySegment function, FunctionDescriptor descriptor, Object... arguments) {
        try {
            return (int) LINKER.downcallHandle(function, descriptor).invokeWithArguments(arguments);
        } catch (Throwable failure) {
            throw new AssertionError("native callback invocation failed", failure);
        }
    }

    private static void invokeVoid(
            MemorySegment function, FunctionDescriptor descriptor, Object... arguments) {
        try {
            LINKER.downcallHandle(function, descriptor).invokeWithArguments(arguments);
        } catch (Throwable failure) {
            throw new AssertionError("native callback invocation failed", failure);
        }
    }

    private static void copyValue(MemorySegment source, MemorySegment destination) {
        MemorySegment.copy(source, 0, destination, 0, InteropLayouts.SEMIRING_VALUE.byteSize());
    }

    private static void equal(long expected, long actual, String label) {
        if (expected != actual) {
            throw new AssertionError(label + ": expected " + expected + ", observed " + actual);
        }
    }

    private static void check(boolean condition, String label) {
        if (!condition) throw new AssertionError(label);
    }

    private static <T extends Throwable> void expectThrows(
            Class<T> type, Runnable operation, String label) {
        try {
            operation.run();
        } catch (Throwable failure) {
            if (type.isInstance(failure)) return;
            throw new AssertionError(label + ": unexpected exception", failure);
        }
        throw new AssertionError(label + ": expected " + type.getName());
    }

    private static final class TinyDictionary implements UnicodeDictionarySnapshot {
        @Override public long root() { return 0; }
        @Override public OptionalLong size() { return OptionalLong.of(1); }
        @Override public boolean isFinal(long node) {
            requireNode(node);
            return node == 1;
        }
        @Override public OptionalLong value(long node) {
            requireNode(node);
            return node == 1 ? OptionalLong.of(9) : OptionalLong.empty();
        }
        @Override public List<Edge> edges(long node) {
            requireNode(node);
            return node == 0 ? List.of(new Edge('a', 1)) : List.of();
        }
        private static void requireNode(long node) {
            if (node != 0 && node != 1) {
                throw new ProviderException(ProviderException.Status.INVALID_ARGUMENT, "unknown node");
            }
        }
    }

    private static class TinyWfst implements ScalarWfstProvider {
        @Override public long startState() { return 0; }
        @Override public OptionalLong stateCount() { return OptionalLong.of(2); }
        @Override public ScalarWfstStateInfo stateInfo(long state) {
            return switch ((int) state) {
                case 0 -> new ScalarWfstStateInfo(true, false, Double.NaN);
                case 1 -> new ScalarWfstStateInfo(true, true, 0.5);
                default -> new ScalarWfstStateInfo(false, false, 0.0);
            };
        }
        @Override public List<ScalarWfstArc> stateArcs(long state) {
            return state == 0
                    ? List.of(
                            new ScalarWfstArc(OptionalLong.of('a'), OptionalLong.empty(), 1, 0.25),
                            new ScalarWfstArc(OptionalLong.empty(), OptionalLong.of('b'), 1, 0.75))
                    : List.of();
        }
    }

    private static final class PagedWfst extends TinyWfst {
        @Override public List<ScalarWfstArc> stateArcs(long state) {
            throw new AssertionError("the paged provider path must not materialize all arcs");
        }
        @Override public ScalarWfstArcPage stateArcsPage(long state, long start, int capacity) {
            if (state != 0 && state != 1) {
                throw new ProviderException(ProviderException.Status.INVALID_ARGUMENT, "unknown state");
            }
            List<ScalarWfstArc> values = state == 0
                    ? List.of(
                            new ScalarWfstArc(OptionalLong.of('a'), OptionalLong.empty(), 1, 0.25),
                            new ScalarWfstArc(OptionalLong.empty(), OptionalLong.of('b'), 1, 0.75))
                    : List.of();
            int first = start >= values.size() ? values.size() : Math.toIntExact(start);
            int count = Math.min(capacity, values.size() - first);
            return new ScalarWfstArcPage(values.subList(first, first + count), values.size());
        }
    }

    private record IntegerLattice(int value) implements StableLatticeProvider {
        @Override public LatticeProvider join(LatticeOperand other) {
            return new IntegerLattice(Math.max(value, decode(other)));
        }
        @Override public LatticeProvider meet(LatticeOperand other) {
            return new IntegerLattice(Math.min(value, decode(other)));
        }
        @Override public boolean equalsValue(LatticeOperand other) {
            return value == decode(other);
        }
        @Override public String diagnostic() { return Integer.toString(value); }
        @Override public byte[] stableBytes() { return ByteBuffer.allocate(4).putInt(value).array(); }
        private static int decode(LatticeOperand operand) {
            return operand.localProvider(IntegerLattice.class)
                    .map(IntegerLattice::value)
                    .orElseGet(() -> ByteBuffer.wrap(operand.stableBytes()).getInt());
        }
    }

    private static final class LimitLattice implements StableLatticeProvider {
        @Override public LatticeProvider join(LatticeOperand other) { return this; }
        @Override public LatticeProvider meet(LatticeOperand other) { return this; }
        @Override public boolean equalsValue(LatticeOperand other) { return false; }
        @Override public String diagnostic() { return "bounded"; }
        @Override public byte[] stableBytes() {
            throw new ProviderException(
                    ProviderException.Status.LIMIT_EXCEEDED, "deliberate stable-byte limit");
        }
    }

    private record ForeignLattice(MemorySegment resource) {}

    private static final class ProbabilitySemiring
            implements DivisibleSemiringProvider<Double>,
                    StarSemiringProvider<Double>,
                    NumericSemiringProvider<Double> {
        @Override public Double zero() { return 0.0; }
        @Override public Double one() { return 1.0; }
        @Override public Double cloneValue(Double value) { return value; }
        @Override public Double plus(Double left, Double right) { return left + right; }
        @Override public Double times(Double left, Double right) { return left * right; }
        @Override public boolean equalsValue(Double left, Double right) {
            return Double.doubleToRawLongBits(left) == Double.doubleToRawLongBits(right);
        }
        @Override public boolean approximatelyEquals(Double left, Double right, double epsilon) {
            return Math.abs(left - right) <= epsilon;
        }
        @Override public SemiringOrder compareNatural(Double left, Double right) {
            int order = Double.compare(left, right);
            return order < 0 ? SemiringOrder.BETTER : order > 0 ? SemiringOrder.WORSE : SemiringOrder.EQUAL;
        }
        @Override public byte[] stableBytes(Double value) {
            return ByteBuffer.allocate(8).putLong(Double.doubleToRawLongBits(value)).array();
        }
        @Override public String diagnostic() { return "probability semiring"; }
        @Override public String diagnostic(Double value) { return Double.toString(value); }
        @Override public Optional<Double> divide(Double dividend, Double divisor) {
            return divisor == 0.0 ? Optional.empty() : Optional.of(dividend / divisor);
        }
        @Override public Optional<Double> leftDivide(Double value, Double divisor) {
            return divide(value, divisor);
        }
        @Override public Optional<Double> star(Double value) {
            return Math.abs(value) < 1.0 ? Optional.of(1.0 / (1.0 - value)) : Optional.empty();
        }
        @Override public double numericalValue(Double value) { return value; }
        @Override public long quantize(Double value, double epsilon) { return Math.round(value / epsilon); }
        @Override public double toProbability(Double value) { return value; }
    }

    private static final class StringSemiring implements SemiringProvider<String> {
        @Override public String zero() { return ""; }
        @Override public String one() { return "1"; }
        @Override public String cloneValue(String value) { return value; }
        @Override public String plus(String left, String right) { return left + right; }
        @Override public String times(String left, String right) { return left + "*" + right; }
        @Override public boolean equalsValue(String left, String right) { return left.equals(right); }
        @Override public boolean approximatelyEquals(String left, String right, double epsilon) {
            return left.equals(right);
        }
        @Override public SemiringOrder compareNatural(String left, String right) {
            int result = left.compareTo(right);
            return result < 0 ? SemiringOrder.BETTER : result > 0 ? SemiringOrder.WORSE : SemiringOrder.EQUAL;
        }
        @Override public byte[] stableBytes(String value) {
            return value.getBytes(java.nio.charset.StandardCharsets.UTF_8);
        }
        @Override public String diagnostic() { return "string semiring"; }
        @Override public String diagnostic(String value) { return value; }
    }
}
