# JavaScript and TypeScript host providers

JavaScript and TypeScript applications can define immutable lattice values,
dynamic semirings, and scalar weighted finite-state transducers (WFSTs) in host
code. Scalar WFSTs can be passed to the same lling-llang algorithms that
consume Rust-owned WFSTs through Node-API, browser WebAssembly, and Node WASI
Preview 1. ClojureScript can use the same JavaScript runtime objects, but its
idiomatic protocol facade is tracked separately.

Use a host provider when transitions already live in JavaScript, when a graph
is computed lazily, or when an application-specific transducer should compose
with duallity without first rebuilding a `VectorWfst`.

The shared `@vinary-tree/vinary-tree-interop` package also exports
`LatticeProvider`, `SemiringProvider<Value>`, their option types, and matching
runtime guards. Those declarations establish one portable contract before
backend-specific resource construction. Native Node-API, browser WebAssembly,
and WASI now root `LatticeProvider` values through lling-llang's dynamic
lattice consumer. Dynamic-semiring trampolines remain follow-up work;
structural validation alone does not create a semiring resource.

| Provider | Shared contract | Native/WASM/WASI resource construction |
|---|---|---|
| Scalar WFST | Complete | Complete |
| Immutable lattice value | Complete structural contract | Complete |
| Dynamic semiring | Complete structural contract | Not yet exposed |

## Complete example

This provider rewrites `cat` to `CAT` one scalar at a time:

```js
import { llingLlang } from "@vinary-tree/javascript-runtime";

const labels = [["c", "C"], ["a", "A"], ["t", "T"]];
const provider = {
  startState() {
    return 0n;
  },
  stateCount() {
    return 4n;
  },
  stateInfo(state) {
    return {
      valid: state >= 0n && state <= 3n,
      final: state === 3n,
      finalWeight: 0,
    };
  },
  stateArcs(state) {
    const index = Number(state);
    if (index < 0 || index >= labels.length) return [];
    const [input, output] = labels[index];
    return [{ input, output, target: state + 1n, weight: 0 }];
  },
};

using uppercase = llingLlang.scalarWfst(provider, {
  unitDomain: "unicode",
  weightDomain: "tropical-f64",
  lazy: true,
  acyclic: true,
});

console.log(uppercase.state(uppercase.start()));
```

The provider object is rooted until the last retained snapshot is released.
Closing `uppercase` does not invalidate a composition that already captured
it. `close()` and `Symbol.dispose` are deterministic and idempotent.

## Provider contract

`assertScalarWfstProvider(provider)` validates the required method shape.
`normalizeScalarWfstProviderOptions(options)` validates domains and capability
claims, fills defaults, and returns a frozen object. The runtime calls both
before it publishes a resource.

| Method | Result | Contract |
|---|---|---|
| `startState()` | `bigint` | Unsigned 64-bit provider-scoped start state. |
| `stateCount()` | `bigint \| null` | Exact count when cheaply known; `null` otherwise. |
| `stateInfo(state)` | `{ valid, final, finalWeight }` | Booleans plus a non-NaN scalar weight. An invalid state cannot be final. |
| `stateArcs(state)` | `readonly WfstProviderArc[]` | Complete outgoing arcs when the bounded page method is absent. |
| `stateArcsPage(state, start, capacity)` | `{ arcs, total }` | Optional bounded page. `start` and `total` are `bigint`; `capacity` is a small positive number. |

An arc has `input`, `output`, `target`, and `weight`. A `null` label is epsilon.
The target is an unsigned 64-bit `bigint`, and the weight is a non-NaN
JavaScript number. Label types follow the declared unit domain:

| Unit domain | Present label |
|---|---|
| `"byte"` | Integer from 0 through 255. |
| `"unicode"` | String containing exactly one Unicode scalar value. |
| `"u64"` | Unsigned 64-bit `bigint`. |

`stateArcsPage` is the preferred interface for high-degree states. A page may
contain at most `capacity` arcs; `total` must remain stable throughout one
state expansion; and a nonterminal page must make progress. Results are
validated and copied transactionally before the runtime publishes them.

## Lattice provider contract

A lattice models two order-theoretic bounds over immutable values: `join`
returns the least upper bound and `meet` returns the greatest lower bound.
The provider receives an eagerly copied `LatticeOperand`, not an untyped raw
pointer. The operand exposes its 16-byte domain identity, an optional local
JavaScript value, and optional canonical bytes. No native pointer or borrowed
buffer can escape through this object.

```ts
import { llingLlang } from "@vinary-tree/javascript-runtime";
import {
  assertLatticeProvider,
  normalizeLatticeProviderOptions,
  type LatticeOperand,
  type LatticeProvider,
} from "@vinary-tree/vinary-tree-interop";

class Maximum implements LatticeProvider {
  constructor(readonly value: number) {}

  join(other: LatticeOperand): Maximum {
    const right = other.localValue;
    if (!(right instanceof Maximum)) throw new TypeError("foreign maximum value");
    return new Maximum(Math.max(this.value, right.value));
  }

  meet(other: LatticeOperand): Maximum {
    const right = other.localValue;
    if (!(right instanceof Maximum)) throw new TypeError("foreign maximum value");
    return new Maximum(Math.min(this.value, right.value));
  }

  equal(other: LatticeOperand): boolean {
    const right = other.localValue;
    return right instanceof Maximum && right.value === this.value;
  }

  diagnostic(): string {
    return `maximum(${this.value})`;
  }
}

const value = new Maximum(3);
assertLatticeProvider(value);
const options = normalizeLatticeProviderOptions({
  domainId: "example.maximum1",
});

using rooted = llingLlang.lattice(value, options);
```

`stableBytes()` is optional and must return a fresh or immutable
`Uint8Array` containing a canonical encoding. `joinMany()` and `meetMany()`
are an optional pair: implementing only one would advertise an incoherent
bounded-batch capability, so both guards reject it.

Each backend resource implements `join`, `meet`, `equal`, `stableBytes`,
`diagnostic`, `joinMany`, `meetMany`, `close`, and `Symbol.dispose`. Result
providers may add or drop optional stable-byte and batch capabilities; every
intermediate is renegotiated, and a batch fold resumes pairwise when needed.
`llingLlang.validateLatticeLaws(values)` checks idempotence, commutativity,
associativity, and absorption over one to sixteen representative values.

## Dynamic semiring contract

A semiring combines alternative paths with `plus` and sequential path segments
with `times`. `zero` and `one` are their respective identities. Host values
remain ordinary immutable JavaScript values; a runtime adapter owns the
provider-scoped generational tokens required by `VtSemiringValue`.

```ts
import {
  assertSemiringProvider,
  normalizeSemiringProviderOptions,
  type SemiringProvider,
  type SemiringOrder,
} from "@vinary-tree/vinary-tree-interop";

class Tropical implements SemiringProvider<number> {
  zero(): number { return Infinity; }
  one(): number { return 0; }
  plus(left: number, right: number): number { return Math.min(left, right); }
  times(left: number, right: number): number { return left + right; }
  equal(left: number, right: number): boolean { return Object.is(left, right); }
  approximatelyEqual(left: number, right: number, epsilon: number): boolean {
    return Math.abs(left - right) <= epsilon;
  }
  naturalOrder(left: number, right: number): SemiringOrder {
    return left < right ? "better" : left > right ? "worse" : "equal";
  }
  diagnostic(value?: number): string { return String(value); }
  numericalValue(value: number): number { return value; }
  quantize(value: number, epsilon: number): bigint {
    return BigInt(Math.round(value / epsilon));
  }
  toProbability(value: number): number { return Math.exp(-value); }
}

const weights = new Tropical();
assertSemiringProvider(weights);
const options = normalizeSemiringProviderOptions({
  domainId: "demo.tropical.01",
  properties: ["idempotent-plus", "totally-ordered", "nonnegative"],
});
```

Optional capability groups are atomic. `plusMany` pairs with `timesMany`,
`divide` pairs with `leftDivide`, and `numericalValue`, `quantize`, and
`toProbability` form one numerical group. `star` and `stableBytes` are
independent. A non-null `closureBound` is legal only with the `k-closed` law.
Law names are semantic claims, not optimization hints: consuming algorithms
must validate representative values before selecting a specialized path.

## Options and capability claims

| Option | Default | Meaning |
|---|---|---|
| `unitDomain` | `"unicode"` | Representation of every present input and output label. |
| `weightDomain` | `"tropical-f64"` | One of the seven scalar semiring representations in `vt.scalar-wfst.1`. |
| `lazy` | `true` | States or arcs may be derived on demand. |
| `acyclic` | `false` | The reachable graph contains no directed cycle. |

The runtime always marks the captured facade immutable. It never advertises
parallel/reentrant callbacks for a JavaScript provider: one JavaScript object
belongs to one agent or event loop. A false `acyclic` value is conservative;
an incorrect true claim is a provider contract violation.

## Scalar-WFST backend ownership model

![A JavaScript provider is validated, rooted by its runtime-specific handle, retained by a scalar-WFST resource, called through bounded pages, and released after the last source or composition closes.](../diagrams/javascript-wfst-provider-sequence.svg)

| Backend | Root and dispatch representation | Raw-pointer rule |
|---|---|---|
| Node-API | Strong N-API reference, per-resource thread-safe cleanup function, and atomic retain count. | Native pointers remain inside the addon. |
| Browser WebAssembly | `JsValue` rooted in a WebAssembly-owned context with a nonblocking callback gate. | ABI pointers remain inside linear memory and never enter JavaScript. |
| WASI Preview 1 | Index-plus-generation JavaScript table; the guest owns one table retain and imports bounded callbacks. | JavaScript receives only integers, `bigint` state IDs, and linear-memory offsets. |

WASI generation checks prevent a stale handle from selecting a provider that
later reused the same slot. Guest code retains the WFST resource and drops the
global resource-table guard before invoking any host method. A callback may
therefore close its source without use-after-free or registry deadlock.

## Exceptions, reentrancy, and shutdown

Provider exceptions never unwind through C++, Rust, or WebAssembly. Each
backend translates them to `ProviderError`; provider-private exception text is
not treated as a portable error protocol. After failure, the callback gate is
cleared and later calls may succeed.

The lattice and semiring structural guards run before a backend resource is
created. They verify required methods and atomic optional groups, but operation
results still require boundary-time type, domain, range, lifetime, and law
validation. Lattice result providers are revalidated and renegotiate optional
capabilities after every bound operation; semiring execution remains pending.

Calling the same provider recursively is rejected immediately. It does not
block, acquire a process-wide provider lock, or poison the resource. Node
cleanup may execute off the JavaScript thread, so it is scheduled through a
per-resource N-API cleanup function. Browser and WASI callbacks remain
synchronous on their owning JavaScript agent.

## Performance

Resource construction and snapshot retention take $`\Theta(1)`$ time and
storage. A full state expansion takes $`\Theta(a)`$ work for $`a`$ outgoing
arcs and uses at most 256 temporary arc records per boundary crossing.
Composition stays lazy: creating a product does not enumerate either graph.

Prefer `stateArcsPage` when a state can have hundreds of arcs. Keep state IDs
compact, avoid allocating intermediate object graphs in hot callbacks, and do
not memoize without a strict capacity and an eviction policy. Built-in Rust
WFSTs retain their monomorphized path and do not pay JavaScript callback cost.

For lattice and semiring implementations, provide bounded batch methods when
the host calculation can avoid intermediate allocations. A runtime adapter
must still cap every batch, copy callback-lexical views before they escape, and
retain specialized Rust implementations whenever dynamic dispatch loses
materially.

## Testing a provider

For scalar WFSTs, test empty and final states, epsilon arcs, the domain boundaries
0/255 and 0/$`2^{64}-1`$, invalid state IDs, a page boundary above 256 arcs,
an exception followed by recovery, reentrant entry, source close during a
callback, composition after source close, and repeated close. The runtime's
conformance suite exercises all these cases plus stale-generation rejection
and steady-state memory behavior.

For lattices, test associativity, commutativity, idempotence, absorption,
domain mismatch, escaped operands, canonical-byte coherence, and both batch
folds. For semirings, test both identities, associativity, distributivity,
declared optional laws, undefined division or closure, stale tokens, bounded
batches, and malformed numerical projections. Structural contract tests run
with:

```sh
npm test --prefix bindings/javascript
```

Run the relevant gates from the JavaScript runtime repository:

```sh
npm run test:native
npm run test:leak
npm run build:wasm
npm run build:wasi
npm test
```

## Security boundaries

Treat every provider result as untrusted. The adapters reject wrong JavaScript
types, out-of-range integers, NaN weights, invalid Unicode scalars, final
metadata on invalid states, oversized or nonprogressing pages, changing totals,
and stale handles. Bounded pages are copied into caller-owned storage only
after complete validation. Capability claims improve scheduling and planning;
they never waive validation.
