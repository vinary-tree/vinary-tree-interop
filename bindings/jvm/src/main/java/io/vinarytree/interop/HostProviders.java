package io.vinarytree.interop;

import java.util.Objects;

/** Factories that export JVM providers through the stable resource ABI. */
public final class HostProviders {
    private HostProviders() {}

    /** Export a snapshot-consistent scalar weighted finite-state transducer. */
    public static HostedResource scalarWfst(ScalarWfstProvider provider) {
        return scalarWfst(provider, ScalarWfstOptions.DEFAULT);
    }

    /** Export a scalar weighted finite-state transducer with explicit domains and promises. */
    public static HostedResource scalarWfst(ScalarWfstProvider provider, ScalarWfstOptions options) {
        return new HostedResource(ProviderRuntime.wfst(
                Objects.requireNonNull(provider, "provider"),
                Objects.requireNonNull(options, "options")));
    }

    /** Export one immutable lattice value. */
    public static HostedResource lattice(LatticeProvider provider, LatticeOptions options) {
        return new HostedResource(ProviderRuntime.lattice(
                Objects.requireNonNull(provider, "provider"),
                Objects.requireNonNull(options, "options")));
    }

    /** Export a generic semiring using provider-scoped owned tokens. */
    public static <T> HostedResource semiring(SemiringProvider<T> provider, SemiringOptions options) {
        return semiring(provider, options, null);
    }

    /** Export a semiring with a primitive codec that avoids per-token value-object allocation. */
    public static <T> HostedResource semiring(
            SemiringProvider<T> provider,
            SemiringOptions options,
            SemiringValueCodec<T> codec) {
        return new HostedResource(SemiringRuntime.create(
                Objects.requireNonNull(provider, "provider"),
                Objects.requireNonNull(options, "options"),
                codec));
    }
}
