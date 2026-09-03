package io.vinarytree.interop;

/** Portable scalar weight encodings supported by the version-1 WFST ABI. */
public enum ScalarWeightDomain {
    /** Tropical costs. */
    TROPICAL_F64(1),
    /** Log-domain probabilities. */
    LOG_F64(2),
    /** Ordinary probabilities. */
    PROBABILITY_F64(3),
    /** Arctic scores. */
    ARCTIC_F64(4),
    /** Signed tropical costs. */
    SIGNED_TROPICAL_F64(5),
    /** Counting weights represented as doubles. */
    COUNT_F64(6),
    /** Boolean weights represented as zero or one. */
    BOOLEAN_F64(7);

    private final int wireValue;

    ScalarWeightDomain(int wireValue) {
        this.wireValue = wireValue;
    }

    /** Stable C ABI discriminant. */
    public int wireValue() {
        return wireValue;
    }

    /** Whether {@code value} is a valid ABI representation in this domain. */
    public boolean isValid(double value) {
        if (Double.isNaN(value)) return false;
        return switch (this) {
            case TROPICAL_F64, LOG_F64, SIGNED_TROPICAL_F64 -> value != Double.NEGATIVE_INFINITY;
            case ARCTIC_F64 -> value != Double.POSITIVE_INFINITY;
            case PROBABILITY_F64 -> Double.isFinite(value) && value >= 0.0;
            case COUNT_F64 -> Double.isFinite(value)
                    && value >= 0.0
                    && value <= 0x1.0p53
                    && value == Math.rint(value);
            case BOOLEAN_F64 -> value == 0.0 || value == 1.0;
        };
    }
}
