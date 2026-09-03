package io.vinarytree.interop;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HexFormat;
import java.util.Objects;

/** An exact 16-byte identity for one host-defined algebraic domain. */
public final class DomainId {
    private final byte[] bytes;

    /** Copy an exact 16-byte identity. */
    public DomainId(byte[] bytes) {
        Objects.requireNonNull(bytes, "bytes");
        if (bytes.length != 16) throw new IllegalArgumentException("a domain identity must contain exactly 16 bytes");
        this.bytes = bytes.clone();
    }

    /** Create an identity from exactly 16 single-byte ASCII characters. */
    public static DomainId fromAscii(String value) {
        Objects.requireNonNull(value, "value");
        byte[] bytes = value.getBytes(StandardCharsets.US_ASCII);
        if (value.length() != 16 || bytes.length != 16 || !value.equals(new String(bytes, StandardCharsets.US_ASCII))) {
            throw new IllegalArgumentException("a domain identity must contain exactly 16 ASCII characters");
        }
        return new DomainId(bytes);
    }

    /** Return a defensive copy of the identity bytes. */
    public byte[] bytes() {
        return bytes.clone();
    }

    @Override
    public boolean equals(Object other) {
        return other instanceof DomainId id && Arrays.equals(bytes, id.bytes);
    }

    @Override
    public int hashCode() {
        return Arrays.hashCode(bytes);
    }

    @Override
    public String toString() {
        return HexFormat.of().withUpperCase().formatHex(bytes);
    }
}
