# ``VinaryTreeInterop``

A Swift-facing bridge to Vinary Tree's versioned, two-word resource ABI.

## Overview

`DictionaryResource` is a protocol implemented by a producer, not a concrete
dictionary constructor. A consumer borrows the producer's `VtResource` only
inside `withVtResource`; it must retain the resource through the C ABI to use it
after the closure returns. `UnitDomain` distinguishes byte, Unicode-scalar,
and unsigned-64 tokens, so crossing domains never silently converts a key.

```swift
import VinaryTreeInterop

func inspect<R: DictionaryResource>(_ dictionary: R) {
    dictionary.withVtResource { pointer in
        precondition(pointer.pointee.context != nil)
        // Negotiate a supported interface before invoking its vtable.
    }
}
```

`VinaryTreeInterop` deliberately has no algorithm-specific constructor. Add a
separate dictionary package when you need an actual data structure. For ABI
layout, ownership, and error rules, see the [resource ABI reference](https://github.com/vinary-tree/vinary-tree-interop/blob/v4.0.0-rc.6/docs/abi-reference.md).

## Topics

### Resource contract

- ``DictionaryResource``
- ``UnitDomain``
