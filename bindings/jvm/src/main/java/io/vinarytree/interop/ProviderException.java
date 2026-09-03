package io.vinarytree.interop;

import java.util.Objects;

/** A portable failure that a host-defined provider intentionally returns through the ABI. */
public final class ProviderException extends RuntimeException {
    private static final long serialVersionUID = 1L;

    /** Statuses that provider implementations may intentionally report. */
    public enum Status {
        /** An input is outside the provider's semantic domain. */
        INVALID_ARGUMENT(2),
        /** The requested operation is not supported for this value. */
        UNSUPPORTED(4),
        /** A persistent backing store failed. */
        IO_ERROR(5),
        /** The provider was already closed. */
        CLOSED(6),
        /** A configured memory, size, or work bound was exceeded. */
        LIMIT_EXCEEDED(7),
        /** The provider failed without a more specific portable status. */
        PROVIDER_ERROR(8);

        private final int wireValue;

        Status(int wireValue) {
            this.wireValue = wireValue;
        }

        /** Raw {@code VtStatus} discriminant written at the native boundary. */
        public int wireValue() {
            return wireValue;
        }
    }

    private final Status status;

    /** Construct a deliberate provider failure. */
    public ProviderException(Status status, String message) {
        super(message);
        this.status = Objects.requireNonNull(status, "status");
    }

    /** Construct a deliberate provider failure with its host-language cause. */
    public ProviderException(Status status, String message, Throwable cause) {
        super(message, cause);
        this.status = Objects.requireNonNull(status, "status");
    }

    /** Portable status emitted by the callback boundary. */
    public Status status() {
        return status;
    }
}
