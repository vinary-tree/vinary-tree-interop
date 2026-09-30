# Ownership, concurrency, and safety

`adopt_resource(raw)` transfers one existing native reference into Julia;
`borrow_resource(raw)` retains a new reference. `dictionary(resource)` and
`wfstransducer(resource)` retain by default; `take=true` transfers their
input resource. `snapshot` and `retain` return independently closeable
owners. `close` is idempotent on these wrappers; use `try`/`finally` rather
than relying on finalizers for timely native release. A finalizer is a leak
fallback, not a scheduling or thread-affinity guarantee.

```julia
function with_dictionary(f, provider_resource::Resource)
    d = dictionary(provider_resource; take=true)
    try
        return f(d)
    finally
        close(d)
    end
end
```

The provider's shared library and vtables must outlive every resource,
cursor, batch, snapshot, graph, and algebra token using them. Never call
`dlclose` merely because an outer facade was closed; retained children may
still reference its code. Copied graph nodes, graph edges, entry data, and
lattice byte strings are Julia-owned after their source closes; raw ABI
slices and batch views are not.

## Threads and callbacks

The `PARALLEL_REENTRANT` flags are **provider promises**, not Julia-side
locks. Concurrent reads on one immutable resource require the relevant flag
or an independent synchronization guarantee from that provider. Distinct
snapshots may share native internals; snapshotting alone is not proof of
parallel safety. Thread-bound lattice or semiring resources must stay on
their designated thread. Never close a resource concurrently with a call
that uses it.

Reducer callbacks run synchronously on the Julia-owned caller thread. Do
not dispatch their ABI call through Julia's `@threadcall` worker pool, which
cannot call back into Julia. Never retain page pointers or re-enter the same
cursor from a reducer callback. The facade catches Julia exceptions at the
C callback boundary and rethrows after the native lease is settled.

## Untrusted providers

Query only negotiated interface IDs and versions. The facade checks status
codes, null pointers, lengths, offsets, page bounds, and domain compatibility
before exposing copies. These checks do not make an arbitrary malicious
native library safe to load: native code runs in-process and can violate C
memory safety independently of this facade. Use trusted, version-matched
providers; keep the ABI header and Julia layouts in sync. `STATUS_UNSUPPORTED`
means an optional capability or value path is unavailable, not an empty result.
