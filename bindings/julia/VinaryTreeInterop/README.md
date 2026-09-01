# VinaryTreeInterop.jl

`VinaryTreeInterop` gives Julia safe, idiomatic access to Vinary Tree's stable
resource ABI: snapshot-consistent dictionaries, bounded entry streams, compact
graphs, scalar weighted finite-state transducers (WFSTs), and immutable lattice
values.

The package implements `AbstractDict`, deterministic `close`, retained snapshots,
bounded `do`-block batches, provider-side reducers, typed domains, and portable
errors without reimplementing the native automata.

## Installation

From a repository checkout, add the package subdirectory:

```julia
using Pkg
Pkg.add(url="https://github.com/vinary-tree/vinary-tree-interop",
    subdir="bindings/julia/VinaryTreeInterop")
```

The library-specific Julia package supplies a native resource. Once a resource
is available, the shared collection surface is conventional Julia:

```julia
using VinaryTreeInterop

function inspect_dictionary(native_resource)
    dictionary = VinaryTreeInterop.dictionary(native_resource; take=true)
    try
        if haskey(dictionary, "café")
            println(dictionary["café"])
        end

        for (term, value) in dictionary
            println(term => value)
        end
    finally
        close(dictionary)
    end
end
```

## Bounded entry processing

Use provider-side reduction when the callback can process a page at a time:

```julia
function print_entries(dictionary)
    cursor = entries(dictionary)
    try
        total = reduce_entries(cursor, BatchLimits(256, 65_536, 256)) do page
            for entry in page
                println(entry.units => entry.value)
            end
        end
        @assert total == length(dictionary)
    finally
        close(cursor)
    end
end
```

Reducer callbacks are synchronous and must remain on a Julia-owned calling
thread. Exceptions are contained at the ABI boundary and re-thrown in Julia.

## Immutable lattice values

`LatticeValue` is an owned handle with `lattice_join`, `lattice_meet`,
`equivalent`, `stable_bytes`, `diagnostic`, `join_many`, and `meet_many`.
Every algebra operation returns an independent owned result. Empty batch folds
retain the receiver, while non-empty batches cross the ABI once:

```julia
function merge_page(base::LatticeValue, updates)
    merged = join_many(base, updates)
    try
        stable_bytes(merged)
    finally
        close(merged)
    end
end
```

The `LLattice.jl` package builds host-implemented Julia providers on this
consumer surface. A 16-byte domain identifier binds each provider's laws and
canonical encoding.

See the [complete design, security, and performance guide](../../../docs/language-bindings/julia-raku.md)
and the generated API reference in `docs/`.
