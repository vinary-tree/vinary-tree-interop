package io.vinarytree.interop;

import java.lang.foreign.MemorySegment;
import java.lang.ref.Cleaner;
import java.lang.ref.Reference;
import java.util.Objects;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.Consumer;
import java.util.function.Function;

/** One owned retain of a JVM provider exported through the native resource ABI. */
public final class HostedResource implements InteropResource {
    private static final Cleaner CLEANER = Cleaner.create();
    private final State state;
    private final Cleaner.Cleanable cleanable;

    HostedResource(ProviderRuntime.ProviderContext context) {
        try {
            State nextState = new State(context);
            Cleaner.Cleanable nextCleanable = CLEANER.register(this, nextState);
            state = nextState;
            cleanable = nextCleanable;
        } catch (Throwable failure) {
            context.release();
            throw failure;
        }
    }

    /**
     * Borrow the live two-word descriptor.
     *
     * <p>The caller must keep this owner strongly reachable for the complete synchronous native call;
     * {@link #withResourceSegment(Function)} is safer for temporary or concurrent ownership.
     */
    @Override
    public MemorySegment resourceSegment() {
        return state.resource();
    }

    /** Last exception contained at this provider's native callback boundary, if any. */
    public Throwable lastCallbackError() {
        return state.fault.error.get();
    }

    /** Run one synchronous operation under an independent native retain. */
    public <T> T withResourceSegment(Function<? super MemorySegment, ? extends T> operation) {
        Objects.requireNonNull(operation, "operation");
        ProviderRuntime.ProviderContext context = state.acquire();
        try {
            return operation.apply(context.resource());
        } finally {
            context.release();
            Reference.reachabilityFence(this);
        }
    }

    /** Run one void synchronous operation under an independent native retain. */
    public void withResourceSegment(Consumer<? super MemorySegment> operation) {
        Objects.requireNonNull(operation, "operation");
        withResourceSegment(resource -> {
            operation.accept(resource);
            return null;
        });
    }

    /** Release this wrapper's owned retain; repeated calls are harmless. */
    @Override
    public void close() {
        cleanable.clean();
    }

    private static final class State implements Runnable {
        private final AtomicReference<ProviderRuntime.ProviderContext> context;
        private final ProviderRuntime.ProviderFault fault;

        State(ProviderRuntime.ProviderContext context) {
            this.context = new AtomicReference<>(context);
            fault = context.fault();
        }

        MemorySegment resource() {
            ProviderRuntime.ProviderContext current = context.get();
            if (current == null) throw new IllegalStateException("hosted resource is closed");
            return current.resource();
        }

        ProviderRuntime.ProviderContext acquire() {
            ProviderRuntime.ProviderContext current = context.get();
            if (current == null) throw new IllegalStateException("hosted resource is closed");
            current.retain();
            return current;
        }

        @Override
        public void run() {
            ProviderRuntime.ProviderContext current = context.getAndSet(null);
            if (current != null) current.release();
        }
    }
}
