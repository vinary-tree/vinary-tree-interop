# Performance and qualification

The [reproducible boundary benchmark](https://github.com/vinary-tree/vinary-tree-interop/blob/master/bindings/julia/VinaryTreeInterop/benchmark/README.md) compares
the same public ABI operations through direct C calls and this Julia facade.
Its [raw samples and analysis](https://github.com/vinary-tree/vinary-tree-interop/blob/master/bindings/julia/VinaryTreeInterop/benchmark/results/2026-09-30-analysis.md)
come from two eleven-block, alternating-order acquisitions on a Threadripper
PRO 5975WX with a pinned Julia thread, warmup, checksum checks, per-block
load controls, and separate allocation probes. They are **integration
boundary** measurements on a two-entry fixture, not automata-algorithm or
end-to-end production benchmarks.

In the committed run, a present query was 6.10 ns/op natively and 22.35
ns/op through Julia; a snapshot-and-release was 2.84 versus 851.30 ns/op;
one two-entry page was 24.88 versus 1,775.88 ns/op. The snapshot comparison
deliberately contrasts raw native retain/release with Julia's validated,
finalizer-equipped owned wrapper. It is not evidence that native snapshot
algorithms differ. The page path makes Julia-owned copies and had about
1.27 KiB allocated per operation on this fixture. Those absolute costs and
semantics matter more than a ratio over a tiny native denominator.

For real workloads, benchmark with the actual provider, key distribution,
page limits, result cardinality, callback work, thread count, and construction
strategy. Precompile and warm both paths; interleave controls; record CPU
contention, memory, and variance. Do not infer that a faster raw C operation
justifies skipping ownership or malformed-provider checks. A page-size sweep
and allocation profile are appropriate next experiments, not an established
optimization prescription.

The qualification suite exercises all three key domains, unit and
optional-`UInt64` values, snapshots, graph and entry lifecycles, callbacks,
scalar WFSTs, semiring contexts, and hostile-provider cases. The ABI v1
`VALUE_BYTES` dictionary gap is tracked separately and excluded from the
benchmark. CI runs the Julia suite, strict Documenter build, and a clean
installed-consumer smoke test on Julia 1.10 and 1.12.
