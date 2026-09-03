package io.vinarytree.interop;

import static java.lang.foreign.ValueLayout.ADDRESS;
import static java.lang.foreign.ValueLayout.JAVA_BYTE;
import static java.lang.foreign.ValueLayout.JAVA_INT;
import static java.lang.foreign.ValueLayout.JAVA_LONG;

import java.lang.foreign.Arena;
import java.lang.foreign.FunctionDescriptor;
import java.lang.foreign.Linker;
import java.lang.foreign.MemorySegment;
import java.lang.invoke.MethodHandle;
import java.nio.charset.StandardCharsets;

/** Exact-signature FFM probes shared by the Kotlin, Scala, and Clojure executable fixtures. */
public final class ProviderLanguageProbe {
    private static final Linker LINKER = Linker.nativeLinker();
    private static final FunctionDescriptor QUERY =
            FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS, JAVA_INT, ADDRESS);
    private static final FunctionDescriptor CONTEXT_OUT =
            FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS);
    private static final FunctionDescriptor CONTEXT_TWO_OUT =
            FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS, ADDRESS);
    private static final FunctionDescriptor RELEASE_VALUES =
            FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS, JAVA_LONG);

    private ProviderLanguageProbe() {}

    /** Invoke a target-language WFST's start callback through the native ABI. */
    public static void assertWfst(HostedResource resource, long expectedStart) {
        resource.withResourceSegment(descriptor -> {
            try (Arena arena = Arena.ofConfined()) {
                MemorySegment table = query(arena, descriptor, "vt.scalar-wfst.1");
                MemorySegment output = arena.allocate(JAVA_LONG);
                MethodHandle start = LINKER.downcallHandle(table.get(ADDRESS, 40), CONTEXT_OUT);
                int status = (int) start.invokeExact(context(descriptor), output);
                require(status == 0 && output.get(JAVA_LONG, 0) == expectedStart, "WFST start");
                return null;
            } catch (Throwable failure) {
                throw rethrow("WFST probe", failure);
            }
        });
    }

    /** Invoke a target-language lattice's equality callback through the native ABI. */
    public static void assertLatticeReflexive(HostedResource resource) {
        resource.withResourceSegment(descriptor -> {
            try (Arena arena = Arena.ofConfined()) {
                MemorySegment table = query(arena, descriptor, "vt.lattice.val.1");
                MemorySegment output = arena.allocate(JAVA_BYTE);
                MethodHandle equal = LINKER.downcallHandle(table.get(ADDRESS, 56), CONTEXT_TWO_OUT);
                int status = (int) equal.invokeExact(context(descriptor), descriptor, output);
                require(status == 0 && output.get(JAVA_BYTE, 0) == 1, "lattice equality");
                return null;
            } catch (Throwable failure) {
                throw rethrow("lattice probe", failure);
            }
        });
    }

    /** Invoke and release a target-language semiring's multiplicative identity through the ABI. */
    public static void assertSemiringOne(HostedResource resource) {
        resource.withResourceSegment(descriptor -> {
            try (Arena arena = Arena.ofConfined()) {
                MemorySegment table = query(arena, descriptor, "vt.semiring.val1");
                MemorySegment value = arena.allocate(InteropLayouts.SEMIRING_VALUE);
                MethodHandle one = LINKER.downcallHandle(table.get(ADDRESS, 48), CONTEXT_OUT);
                int status = (int) one.invokeExact(context(descriptor), value);
                require(status == 0, "semiring one");
                MethodHandle release =
                        LINKER.downcallHandle(table.get(ADDRESS, 64), RELEASE_VALUES);
                status = (int) release.invokeExact(context(descriptor), value, 1L);
                require(status == 0 && value.get(JAVA_LONG, 0) == 0 && value.get(JAVA_LONG, 8) == 0,
                        "semiring release");
                return null;
            } catch (Throwable failure) {
                throw rethrow("semiring probe", failure);
            }
        });
    }

    private static MemorySegment query(Arena arena, MemorySegment descriptor, String identifier)
            throws Throwable {
        MemorySegment id = arena.allocateFrom(
                JAVA_BYTE, identifier.getBytes(StandardCharsets.US_ASCII));
        MemorySegment output = arena.allocate(ADDRESS);
        MemorySegment base = descriptor.get(ADDRESS, 8)
                .reinterpret(InteropLayouts.RESOURCE_VTABLE.byteSize());
        MethodHandle query = LINKER.downcallHandle(base.get(ADDRESS, 32), QUERY);
        int status = (int) query.invokeExact(context(descriptor), id, 1, output);
        require(status == 0 && output.get(ADDRESS, 0).address() != 0, "interface query");
        MemorySegment address = output.get(ADDRESS, 0);
        return address.reinterpret(address.reinterpret(8).get(JAVA_LONG, 0));
    }

    private static MemorySegment context(MemorySegment descriptor) {
        return descriptor.get(ADDRESS, 0);
    }

    private static void require(boolean condition, String operation) {
        if (!condition) throw new AssertionError(operation + " failed");
    }

    private static AssertionError rethrow(String operation, Throwable failure) {
        return failure instanceof AssertionError error
                ? error
                : new AssertionError(operation + " native invocation failed", failure);
    }
}
