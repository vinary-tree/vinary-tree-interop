# VinaryTreeInterop.jl

`VinaryTreeInterop` gives Julia safe, idiomatic access to Vinary Tree's stable
resource ABI: snapshot-consistent dictionaries, bounded entry streams, compact
graphs, scalar weighted finite-state transducers (WFSTs), and immutable lattice
values.

The package implements `AbstractDict`, deterministic `close`, retained snapshots,
bounded `do`-block batches, provider-side reducers, typed domains, and portable
errors without reimplementing the native automata.

The [published development guide and API reference](https://vinary-tree.github.io/vinary-tree-interop/julia/dev/)
documents the current source; its URL is not a claim that RC.6 is registered.

## Installation

From a repository checkout, add the package subdirectory:

```julia
using Pkg
Pkg.add(url="https://github.com/vinary-tree/vinary-tree-interop",
    subdir="bindings/julia/VinaryTreeInterop")
```

Until General registration is public, pin a reviewed full commit SHA with
`Pkg.PackageSpec(url=..., rev=..., subdir=...)` for repeatable installs. This
package does not ship a native automaton provider; a library-specific binding
must supply a compatible owned `Resource`. A fresh-installed consumer is
exercised in CI, independently of a developed checkout.

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
The cursor cannot be advanced, cancelled, reduced again, or closed from inside
its own callback: each reentrant operation raises `InteropError` with
`STATUS_BATCH_IN_USE` without consuming the cursor. An exception from the
callback is re-thrown after the provider settles its current batch lease; the
cursor remains open and can be closed in `finally`. Call `cancel!(cursor)`
outside a callback to stop before the next page, or return `STOP_REDUCTION`
from the callback to stop after its current page. The latter returns the exact
number of processed entries, including the stopping page's entries.

The page limits are hard upper bounds. If the next complete entry cannot fit,
`next_batch` raises `STATUS_LIMIT_EXCEEDED` without publishing a partial entry.
An `EntryBatch` becomes unusable after either `release!(batch)` or closure of
its parent cursor. `with_batch` handles normal and exceptional release paths.

## Domains and compact graphs

Dictionary keys may be arbitrary bytes (`Vector{UInt8}`), Unicode scalar
strings (`String`), or full-width application tokens (`Vector{UInt64}`). A
terminal dictionary value is either valueless or optional `UInt64`; `nothing`
is different from a present zero. `snapshot(dictionary)` retains an independent
resource, while `snapshot_identity(dictionary)` identifies its immutable
producer revision when the provider implements that optional capability.
The shared ABI now declares optional v2 byte-value copy and bounded byte-entry
capabilities, and this package generates their raw layouts and callable
signatures. Its high-level `Dictionary` facade remains v1-only for values:
indexing a `VALUE_BYTES` dictionary raises `STATUS_UNSUPPORTED` until a
separately qualified v2 facade is implemented.

For an immutable provider, `visit(dictionary, node)` obtains finality and an
edge page in one native call when the fused-visit capability exists. A compact
`graph(dictionary)` retains its provider snapshot; `graph_nodes` and
`graph_edges` return Julia-owned copies so they remain safe after `close(graph)`:

```julia
function inspect_graph(dictionary)
    compact = graph(dictionary)
    compact === nothing && return nothing
    try
        nodes = graph_nodes(compact)
        edges = graph_edges(compact)
        (nodes, edges)
    finally
        close(compact)
    end
end
```

The generated scalar WFST application binary interface (ABI) covers all three
unit domains and seven scalar weight domains. A `Wfst` retains its resource;
`arcs(wfst, state)` copies one bounded page at a time, including epsilon arcs
whose absent input or output labels appear as `nothing`. The generated dynamic
semiring ABI keeps value tokens scoped to a retained operation-context
resource: copying their two words does not clone ownership. Consumers must use
the provider's `clone_value` and `release_values` callbacks exactly once per
owned token.

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

Read the [Julia guide](docs/src/index.md), [dictionaries and bounded
streams](docs/src/dictionaries.md), [WFSTs and algebraic
values](docs/src/automata.md), [ownership and safety](docs/src/safety.md),
[measured boundary performance](docs/src/performance.md), and
[installation/release contract](docs/src/release.md). The generated
[API reference](docs/src/api.md) covers every exported symbol. The
[shared ABI design guide](../../../docs/language-bindings/julia-raku.md)
contains provider-side details.
