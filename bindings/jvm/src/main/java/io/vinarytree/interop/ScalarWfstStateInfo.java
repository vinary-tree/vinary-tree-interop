package io.vinarytree.interop;

/** Validity, finality, and final weight for one provider-scoped state. */
public record ScalarWfstStateInfo(boolean valid, boolean isFinal, double finalWeight) {}
