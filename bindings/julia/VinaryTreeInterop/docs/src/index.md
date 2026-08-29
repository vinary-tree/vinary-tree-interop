# VinaryTreeInterop.jl

`VinaryTreeInterop` is the shared Julia ownership and traversal layer for Vinary
Tree resources. Native libraries supply the algorithms; this package supplies
Julia's collections, exceptions, snapshots, bounded streams, and scalar WFSTs.

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
is open. Raw entry-batch pointers remain valid only until the matching
generation is released. Prefer `with_batch` so exceptional control flow cannot
leak a lease.

Reducer callbacks are synchronous. Do not call the native reducer through
`@threadcall`, because Julia's manual forbids callbacks from that worker pool.
