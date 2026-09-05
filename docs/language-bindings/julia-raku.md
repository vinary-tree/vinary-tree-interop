# Julia and Raku resource-ABI bindings

The Julia package `VinaryTreeInterop` and the Raku distribution
`Vinary-Tree-Interop` provide language-native access to the same stable,
versioned C resource application binary interface (ABI). An ABI is the binary
contract that fixes data layouts, calling conventions, ownership rules, and
result codes between independently compiled components.

These packages are the shared foundation for the Julia and Raku bindings of
`llattice`, `libdictenstein`, `liblevenshtein`, `lling-llang`, and `duallity`.
They do not duplicate automata algorithms. Native producers implement the
algorithms once in Rust and expose dictionaries, scalar weighted finite-state
transducers (WFSTs), immutable lattice values, or dynamic semiring operation
contexts as retained resources.

![Resource ownership from native producer to bounded language-owned values](../diagrams/julia-raku-resource-ownership.svg)

## Design and ownership

`VtResource` is a two-word owned handle: a context pointer and a pointer to a
versioned function table. The function table supports three operations:

1. `retain` creates another independent reference.
2. `release` destroys exactly one reference.
3. `query_interface` discovers a typed optional interface without changing the
   resource ABI.

The language wrappers preserve that algebra. If `r` is the current native
reference count, ownership transitions obey:

```math
r_{t+1} = r_t + N_{\mathrm{retain}} - N_{\mathrm{release}}
```

Every successful retain is paired with exactly one release. Julia's
`borrow_resource` and Raku's `borrow-resource` first retain provider-owned
borrowed words; their `adopt` counterparts transfer an already-owned reference.
Julia's `close` and Raku's `.close` are deterministic. Finalizers are fallback
leak protection, not a substitute for explicit ownership.

### Snapshot consistency

A dictionary or WFST snapshot owns a retained native resource. Node and state
identifiers are scoped to that snapshot. A later mutation of the producer
cannot change the captured traversal. A compact graph view borrows immutable
native slices and retains its snapshot for the entire view lifetime.

### Bounded streaming

Entry cursors expose finite lexicographic streams. Each call supplies hard
limits for entry descriptors, units, and values. The cursor returns a batch
lease identified by a generation. A second batch cannot be acquired until the
first generation is released.

The high-level iterators copy each bounded page into language-owned values
before release. Performance-sensitive callers can use `with_batch` and inspect
the active raw view inside the callback, but no pointer may escape that dynamic
scope.

The streaming algorithm is:

```text
open a cursor over an immutable snapshot
loop:
    request a page subject to explicit hard limits
    if the provider reports end, close the cursor and stop
    copy or reduce every entry while the generation is active
    release that exact generation on success or failure
```

This uses constant native lease memory with respect to dictionary cardinality.
If $`B`$ is the maximum page footprint and $`n`$ is the number of entries,
native lease space is $`O(B)`$, while total traversal work remains $`O(n)`$
plus key data.

## Host-language idioms

Julia dictionaries implement `AbstractDict`; Unicode-scalar resources use
`String` keys, byte resources use `Vector{UInt8}`, and vocabulary resources use
`Vector{UInt64}`. `close`, `haskey`, indexing, `length`, iteration, `do` blocks,
and typed exception handling work as Julia users expect.

Raku dictionaries implement `Associative`, and entry cursors implement
`Iterable`. Missing optional unsigned values use the `UInt` type object, so
callers can distinguish presence with `:exists`. Batch and cursor objects have
deterministic `.release` and `.close` methods with garbage-collection fallback.

## Callback and concurrency safety

Reducers call back into Julia or Raku synchronously on the language-owned thread
that entered native code. Every language exception is contained inside the C
callback, translated to `VT_STATUS_PROVIDER_ERROR`, and re-thrown only after
native control returns. Exceptions never unwind through C or Rust frames.

Neither package advertises arbitrary native-thread language providers. A native
worker created outside Julia or Rakudo cannot safely enter those runtimes merely
because a function pointer exists. The lattice provider therefore carries an
explicit thread-affinity capability, while reducers remain synchronous on the
calling thread.

### Host-implemented lattice values

`vt.lattice.val.1` carries immutable values with `join`, `meet`, equality,
canonical bytes, diagnostics, and associative batch folds. Julia initializes
its `@cfunction` trampolines at module load so precompilation never serializes
process-local function addresses. A rooted provider registry keeps Julia
objects alive until the last native retain is released; its lock is used only
for retain/release bookkeeping, never on the algebra hot path.

Rakudo cannot place a managed callback pointer directly into a `CStruct` field.
The Raku `LLattice` distribution therefore uses a small C17 trampoline. An
atomic native retain count owns the callback bundle and calls one contained Raku
drop callback at final release. The shim does not interpret values or serialize
operations; join, meet, equality, encoding, and batch folds execute in Raku.

Both managed providers advertise `LATTICE_FLAG_THREAD_BOUND`. Consumers must
keep callbacks synchronous on the runtime-attached calling thread and reject an
algorithm that requires unattached worker-thread callbacks. The optional
`PARALLEL_REENTRANT` flag permits concurrency among attached runtime threads; it
does not weaken the thread-bound requirement.

Same-provider operands use a direct object path. A host may additionally supply
a stable-byte decoder for cross-provider operations: the facade verifies the
16-byte domain identifier, retains the foreign value, copies its canonical
encoding, decodes, performs the operation, and releases on every exit.

### Host-implemented semirings

The semiring capability is deliberately an operation context rather than one
retained resource per weight. `VtSemiringValue` is a fixed two-word token. A
host may store a scalar inline or encode a slot and generation from a bounded,
recycling arena. The retained context owns that representation and implements
explicit token clone/release operations, so Rust's native `Semiring: Copy`
contract is never falsified by a reference-counted foreign object.

The base interface contains the universally meaningful operations: zero, one,
addition, multiplication, exact and approximate equality, natural order,
canonical bytes, diagnostics, and bounded folds. Division, Kleene closure,
numerical projections, and declared laws are separate negotiated interfaces.
This separation prevents an oversized vtable and lets algorithms ask for the
smallest lawful capability they require.

Julia `@cfunction` and Raku NativeCall providers must contain every host
exception and return a portable status. Their tokens remain scoped to one exact
operation context even when two providers publish the same 16-byte domain
identifier. An algorithm may use a declared law such as idempotence or total
order only after its conformance suite validates representative values; a flag
is a claim to test, not permission to assume arbitrary host code is lawful.

## ABI verification

The C header is the single source for Raku's raw ABI. The generator derives all
representable `CStruct` declarations and typed vtable casts, then emits a
tab-separated capability inventory containing C and NativeCall signatures,
interface versions and identities, parameter direction and ownership, and
threading constraints. A negative control perturbs the generated callback count
and proves that byte-for-byte freshness detects the change. Hand-authored Raku
code is limited to collection, ownership, validation, and provider ergonomics;
the generator rejects a raw layout or typed callback cast outside its owned
region.

The test fixture is compiled from the authoritative C header. Julia checks
`sizeof` for every ABI type against C, while Raku checks `nativesizeof` against
the same fixture. Both suites execute calls through actual function pointers,
exercise retain/release accounting, page dictionary edges and WFST arcs, reduce
entry streams, contain hostile reducer exceptions, and prove collection idioms.

Raku fixed-size padding fields are represented as individual native scalars.
This is layout-equivalent to a C array and avoids assigning or garbage-collecting
a borrowed `CArray`. The native-size correspondence test guards every field
group against drift.

## Performance model

Calls through the resource ABI are designed around coarse operations:

- fused finality and edge inspection when the optional visit interface exists;
- bounded edge, arc, and entry pages to amortize foreign-call overhead;
- compact immutable graph slices for zero-copy traversal;
- provider-side reducers when per-entry callbacks would dominate runtime.

The wrappers do not add global locks. A resource advertises parallel reentrancy
only when the native provider guarantees it. Julia and Raku collections retain
specialized native traversal and copy only at explicit ownership boundaries.

## Security boundaries

All foreign pointers are treated as untrusted provider output. Wrappers reject
null required pointers, unsupported interface versions, over-capacity page
counts, stalled pagination, invalid entry value widths, use after close, and a
second active batch. Raw views are exposed only with a retained owner and an
explicit lease lifetime.

The packages never load a native library by an untrusted search result. A
library-specific binding resolves its signed/reproducible release artifact and
then transfers the resulting resource into this shared layer.

## References

- Julia, [Calling C and Fortran Code](https://docs.julialang.org/en/v1/manual/calling-c-and-fortran-code/).
- Raku, [Native calling interface](https://docs.raku.org/language/nativecall).
- Julia Pkg, [Artifacts](https://pkgdocs.julialang.org/v1/artifacts/).
- Raku, [Uploading distributions](https://docs.raku.org/language/distributions/uploading).
