package io.vinarytree.interop;

/** Optional canonical serialization for a host-defined lattice value. */
public interface StableLatticeProvider extends LatticeProvider {
    /** Return canonical bytes for cross-provider decoding and hashing. */
    byte[] stableBytes();
}
