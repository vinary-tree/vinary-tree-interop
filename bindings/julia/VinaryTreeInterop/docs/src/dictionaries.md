# Dictionaries and bounded streams

`Dictionary{K,V}` implements `AbstractDict{K,V}`. Use `haskey`, indexing,
`get`, `length` (when the provider advertises an exact length), and iteration
as with other Julia dictionaries. Iteration traverses copied, finite entry
pages; it is not a live view of producer mutations. `snapshot(d)` retains an
independently closeable resource with the provider's snapshot semantics.

| ABI unit domain | Julia key | Query input |
| --- | --- | --- |
| `UNIT_BYTE` | `Vector{UInt8}` | byte vector or UTF-8 `String` code units |
| `UNIT_UNICODE_SCALAR` | `String` | `String` or `Vector{UInt32}` scalars |
| `UNIT_U64` | `Vector{UInt64}` | `Vector{UInt64}` |

`VALUE_UNIT` maps every final key to `nothing`; `VALUE_OPTIONAL_U64` maps it
to `nothing` or `UInt64`. An absent key raises `KeyError` on indexing, so use
`haskey` when absence differs from a present key whose value is `nothing`.
`VALUE_BYTES` exists as an ABI discriminant but v1 dictionary callbacks cannot
retrieve byte-valued nodes or entry pages: a `Dictionary{K,Vector{UInt8}}`
may be constructed, but indexing raises `STATUS_UNSUPPORTED`. Do not use or
advertise that domain until a versioned ABI extension is shipped.

## Query and snapshot

```julia
function read_both(d::Dictionary{String})
    captured = snapshot(d)
    try
        present = haskey(captured, "café")
        return present, present ? captured["café"] : nothing
    finally
        close(captured)
    end
end
```

`root`, `transition`, `isfinal`, `value`, `edges`, and `visit` expose graph
traversal. `visit` is optional and combines finality with an edge page when
the provider advertises the fused capability. `graph(d)` is also optional
and only applies to an immutable provider; `graph_nodes` and `graph_edges`
copy provider slices into Julia-owned arrays. `snapshot_identity` is a
process-local producer revision, **not** a content hash or cross-process ID.

## Bounded entry pages

Use `entries(d)` for a finite, snapshot-consistent cursor. `BatchLimits` bounds
complete entries, key units, and values per page. If the next complete entry
does not fit, the provider returns `STATUS_LIMIT_EXCEEDED`; no partial entry
is published. `with_batch` releases the native lease even if your callback
throws. `copied_entries` makes Julia-owned data valid after the lease ends.

```julia
function first_page(d::Dictionary)
    cursor = entries(d)
    try
        return with_batch(cursor, BatchLimits(128, 16_384, 128)) do batch
            copied_entries(batch)
        end
    finally
        close(cursor)
    end
end
```

An `EntryBatch` cannot be used after `release!` or cursor closure. A cursor
cannot advance while one batch is live. Its raw pointers are borrowed for
that generation only; never retain them in a Julia object or callback closure.

`reduce_entries` calls a Julia callback once per page when the provider
supports reduction:

```julia
function count_entries(d::Dictionary)
    cursor = entries(d)
    try
        return reduce_entries(cursor, BatchLimits(256, 65_536, 256)) do page
            @assert !isempty(page) # Julia-owned DictionaryEntry values
        end
    finally
        close(cursor)
    end
end
```

The return is the **number of entries**, not pages. `STOP_REDUCTION` stops
after the current page and includes it in the count. Call `cancel!` outside
callbacks to stop before another page. Reentrant advance, reduction, cancel,
or close from a callback raises `STATUS_BATCH_IN_USE`; callback exceptions
are re-thrown after the provider settles its lease.

```jldoctest
julia> using VinaryTreeInterop

julia> limits = BatchLimits(4, 32, 4);

julia> Int.((limits.max_entries, limits.max_units, limits.max_values))
(4, 32, 4)
```
