package io.vinarytree.interop;

/** Natural-order relationship between two semiring values. */
public enum SemiringOrder {
    /** The left value is better. */
    BETTER(-1),
    /** The values are equivalent. */
    EQUAL(0),
    /** The left value is worse. */
    WORSE(1),
    /** Neither value precedes the other. */
    INCOMPARABLE(2);

    private final int wireValue;

    SemiringOrder(int wireValue) {
        this.wireValue = wireValue;
    }

    /** Stable C ABI discriminant. */
    public int wireValue() {
        return wireValue;
    }
}
