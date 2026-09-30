# Julia/native boundary benchmark

This benchmark measures the cost of using the same small Vinary Tree provider
through two consumers: direct C vtable calls and the public
`VinaryTreeInterop.jl` wrappers. It is an **integration-boundary** benchmark,
not a throughput claim for the production automata. The native control does
the corresponding public ABI work, while Julia additionally performs its
normal validation, ownership, conversion, and collection materialization.
Consequently, a Julia/native ratio is not a Rust-versus-Julia algorithm ratio.

The [measurement topology](boundary-topology.svg) shows the common provider
and independent timing envelopes. Both paths assert an independently specified
checksum and that the qualification provider has no live dictionaries,
cursors, or semiring tokens after every case.

## Workloads

All dictionary cases use a two-entry immutable byte-key,
optional-`UInt64`-value provider. Query probes its present zero-valued key.
The entry page holds both one-unit entries. The scalar weighted finite-state
transducer (WFST) has two arcs, including one epsilon arc. The fixture lattice
joins a base value with one or three operands. The dynamic-semiring fixture
adds two or three owned one-valued tokens.

| Cases | Matched operation |
| --- | --- |
| `resource_retain` | Retain and release an owned resource |
| `dictionary_query` | Root, transition, finality, optional value |
| `dictionary_snapshot` | Capture and release an independent snapshot |
| `dictionary_visit` | Fused finality and one bounded edge page |
| `dictionary_graph` | Obtain an immutable graph and copy its node/edge slices |
| `entry_page` | Open, copy one bounded page, release the lease, close |
| `entry_reduce_host_callback` | Open, reduce two entries through a callback, close |
| `wfst_expand` | Inspect one state and expand one two-arc page |
| `lattice_pair`, `lattice_batch` | Join one or three values, release result |
| `semiring_pair_with_context`, `semiring_batch_with_context` | Create a scoped operation context, add owned tokens, release all tokens/context |

The semiring context is deliberately recreated per operation because the
qualification provider has a finite token table; this setup is timed on both
sides. The lattice and dictionary setup/teardown is timed once per sample on
both sides. The exact operations and output checksums are specified in
[`native-control.c`](native-control.c) and [`boundary.jl`](boundary.jl).
The C code enters through the public vtable, not private fixture functions.

This benchmark covers the `UNIT` and `OPTIONAL_U64` dictionary value
domains, **not** byte-valued dictionaries. ABI v1 has a
`VALUE_BYTES` discriminant but no corresponding dictionary-node or
entry-page byte-value accessors. That gap is tracked as
`vinary-tree-interop-byte-value-dictionary-abi-parity`.

## Reproduce

On Linux with Julia 1.10 or newer, a C11 compiler, `taskset`, and
`systemd-run`, choose an otherwise idle physical core whose simultaneous
multithreading sibling is also idle. Check load and per-core utilization before
every run. For example, core 8 and sibling 40 are one physical core on the
recorded workstation; verify that topology rather than copying the numbers
to another machine:

```sh
uptime
mpstat -P 8,40 1 2
mkdir -p bindings/julia/VinaryTreeInterop/benchmark/target
systemd-run --user --scope -p MemoryMax=3G -p MemorySwapMax=0 \
  -p CPUQuota=100% -p TasksMax=64 \
  taskset -c 8 env \
  TMPDIR="$PWD/bindings/julia/VinaryTreeInterop/benchmark/target" \
  JULIA_NUM_THREADS=1 \
  julia --project=bindings/julia/VinaryTreeInterop \
  bindings/julia/VinaryTreeInterop/benchmark/boundary.jl \
  bindings/julia/VinaryTreeInterop/benchmark/target/current.csv
```

The runner compiles the fixture and C control at `-O2` into the
disk-backed `benchmark/target/` directory. It writes one row per paired
sample to the requested CSV and a neighboring `.meta` file with source
revision and SHA-256 hashes of the driver/controls/fixtures, tool versions,
CPU identity, affinity, thread count, and noise
thresholds. It also records the selected core's governor, and each CSV row
records its clock frequency before and after the paired block. Never use
`/tmp` for the output or build directory on this
workstation: it is mounted as memory-backed storage.

Run a cheap correctness/compilation diagnostic with `--pilot`; such rows are
marked `pilot_diagnostic` and cannot serve as a baseline. Once a full CSV is
qualified and versioned, check a later run with
`--baseline path/to/qualified-baseline.csv`. The checker rejects pilot
baselines and requires at least nine clean paired samples in every case.
It also refuses to compare runs with different CPU models, affinity,
governors, Julia/compiler versions, native optimization level, or Julia
thread counts. The user must still inspect frequency drift and background
work before accepting the comparison.

## Controls and interpretation

Each case has three untimed warmup rounds, then eleven paired blocks with
alternating native-first and Julia-first order. The C loop's monotonic clock
starts and stops inside the native library; Julia uses `time_ns()` around its
public wrapper loop. A single Julia-to-C call starts the entire native
sample, so its entry cost does not contaminate individual native operations.
The reported paired ratio is:

$`R_i = T_{J,i} / T_{C,i}`$,

where $`T_{J,i}`$ and $`T_{C,i}`$ are the Julia and native durations of
paired block $`i`$. The runner reports the median of clean ratios and a
deterministic 2,000-resample percentile bootstrap interval, following the
resampling principle of [Efron (1979)](https://doi.org/10.1214/aos/1176344552).
This interval describes variation among these sequential blocks; it is not
a guarantee of 95% coverage if blocks are temporally correlated.

Each row also records Julia allocated bytes for a short, separately warmed
run, process resident-set size before and after the block, host load,
host-wide busy fraction, and the Julia process's scheduler-wait fraction.
Native transient allocations are **not** independently counted; process RSS
is not a substitute for a native allocation profiler. A block is excluded
from summaries if load exceeds one quarter of logical CPUs, host-wide busy
fraction exceeds 50%, or Julia scheduler wait exceeds 5% of block wall time.
Keep excluded rows in the raw CSV rather than silently deleting them. Core
affinity and the sibling-core observation in the manifest are necessary
context even when aggregate load is low.

The predeclared machine-local regression budgets compare a new full run to a
qualified full-run baseline on the **same host, affinity, compiler, and Julia
configuration**:

1. At least nine clean paired blocks per case, with matching checksums and no
   live qualification resources after every block.
2. Median Julia nanoseconds per operation at most $`1.5 \times`$ baseline.
3. Median paired Julia/native ratio at most $`2 \times`$ baseline.
4. Median Julia allocated bytes per operation at most the greater of
   $`1.25 \times`$ baseline or baseline plus $`32`$ bytes.

These thresholds are deliberately broad noise-tolerant regression guards,
not claims that a particular absolute latency is portable. A contaminated
or dissimilar-host run must be repeated rather than used to relax a budget.
The source-data CSV is the evidence; any human summary must retain its
revision, workload, exclusions, and uncertainty.

The [2026-09-30 controlled baseline and independent replication](results/2026-09-30-analysis.md)
include all raw paired blocks, machine/source manifests, absolute timings,
allocated bytes, uncertainty, and limitations. They characterize this ABI
fixture only; they are not product-level speed claims.
