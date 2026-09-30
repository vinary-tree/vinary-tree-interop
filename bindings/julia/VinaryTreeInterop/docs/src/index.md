# VinaryTreeInterop.jl

`VinaryTreeInterop` is the shared Julia ownership and traversal layer for Vinary
Tree resources. Native libraries supply the algorithms; this package supplies
Julia's collections, exceptions, snapshots, bounded streams, scalar WFSTs, and
immutable lattice values.

## Ownership

Adopting a raw resource transfers one existing reference. Constructing a facade
without `take=true` retains an independent reference. Always close the outermost
facade deterministically:

```julia
function dictionary_size(native_resource)
    dictionary = VinaryTreeInterop.dictionary(native_resource; take=true)
    try
        length(dictionary)
    finally
        close(dictionary)
    end
end
```

## Collections

`Dictionary` implements `AbstractDict`. Its key type follows the token domain:

| Domain | Julia key |
|---|---|
| byte | `Vector{UInt8}` |
| Unicode scalar | `String` |
| unsigned 64-bit token | `Vector{UInt64}` |

The entry iterator acquires bounded native pages, copies their contents, and
releases each generation before yielding Julia-owned pairs.

## Safety

Raw compact-graph slices remain valid only while their `DictionaryGraph` owner
is open; public `graph_nodes` and `graph_edges` return Julia-owned copies that
remain valid after closing it. Raw entry-batch pointers remain valid only until
the matching generation is released. Prefer `with_batch` so exceptional control
flow cannot leak a lease. A reducer callback may return `STOP_REDUCTION` to
stop after its current page; use `cancel!` outside callbacks to cancel a cursor.

Reducer callbacks are synchronous. Do not call the native reducer through
`@threadcall`, because Julia's manual forbids callbacks from that worker pool.

## Lattice values

`LatticeValue` owns an immutable value implementing the negotiated
`vt.lattice.val.1` capability. `lattice_join` and `lattice_meet` return new
owned values; `join_many` and `meet_many` use one bounded callback when the
producer advertises batching. `stable_bytes` returns the canonical value
encoding, and `diagnostic` reports a contained provider failure.

Close all providers and results in `finally` blocks. Domain identifiers must
match before an operation; equality and encoding do not make values from
different algebraic domains interchangeable.
