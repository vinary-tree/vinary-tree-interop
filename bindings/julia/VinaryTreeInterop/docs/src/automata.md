# WFSTs and algebraic values

## Scalar weighted finite-state transducers

`wfstransducer(resource; take=true)` adopts a provider's scalar WFST
interface. `start`, `state_count`, `state_info`, and `arcs` are the principal
read operations. `arcs` requests bounded native pages and returns an owned
Julia vector. Absent input or output labels on epsilon arcs are `nothing`.
The generated ABI defines three unit domains and seven scalar weight domains;
the provider decides which it actually supports.

```julia
function outgoing(provider_resource::Resource)
    machine = wfstransducer(provider_resource; take=true)
    try
        origin = start(machine)
        return state_info(machine, origin), arcs(machine, origin; batch_size=256)
    finally
        close(machine)
    end
end
```

`snapshot(machine)` retains an independently closeable producer snapshot.
Unknown total state count is `nothing`, not zero. The facade does not turn a
scalar WFST into a mutable Julia graph or promise every provider is eager or
acyclic; inspect its flags.

## Lattice and semiring values

`LatticeValue` is an owned, immutable handle. `lattice_join`, `lattice_meet`,
`join_many`, and `meet_many` each return a new owned result. `equivalent`
tests values in the same 16-byte algebraic domain; `stable_bytes` returns the
provider's canonical representation when supported. Even an empty fold
returns a **retained** handle.

```julia
function merge_all(base::LatticeValue, updates)
    merged = join_many(base, updates)
    try
        return stable_bytes(merged)
    finally
        close(merged)
    end
end
```

Never combine values from different domain IDs. Dynamic semiring value
tokens are scoped to a retained operation context. Copying their two machine
words does **not** transfer ownership: use the provider's `clone_value` and
`release_values` operations and keep the context alive. Optional semiring
interfaces (division, star, numeric conversion, properties) must be
negotiated, not assumed. The [API reference](api.md) lists the generated
C-compatible tables; the [shared ABI guide](https://github.com/vinary-tree/vinary-tree-interop/blob/master/docs/language-bindings/julia-raku.md)
explains provider implementation.

```jldoctest
julia> using VinaryTreeInterop

julia> sizeof(VtSemiringValue)
16

julia> sizeof(VtInterfaceId)
16
```
