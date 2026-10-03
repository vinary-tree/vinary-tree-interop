import CVinaryTreeInterop

/// A retained `vt.dictionary.v1` producer. Implementations borrow their
/// two-word handle for the duration of `body`; consumers retain it in O(1).
public protocol DictionaryResource: AnyObject, Sendable {
    /// The exact unit domain of the retained dictionary; never infer it from a host string.
    var unitDomain: UnitDomain { get }
    /// Borrow the two-word native descriptor only for this synchronous closure.
    /// A native consumer may retain it by calling the ABI's retain callback.
    func withVtResource<Result>(
        _ body: (UnsafePointer<VtResource>) throws -> Result
    ) rethrows -> Result
}

/// The three disjoint dictionary token domains in the stable resource ABI.
public enum UnitDomain: Sendable {
    case byte
    case unicodeScalar
    case u64

    /// The matching C ABI discriminant for interface negotiation.
    public var cValue: VtUnitDomain {
        switch self {
        case .byte: VT_UNIT_DOMAIN_BYTE
        case .unicodeScalar: VT_UNIT_DOMAIN_UNICODE_SCALAR
        case .u64: VT_UNIT_DOMAIN_U64
        }
    }
}
