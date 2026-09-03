"""Construct each Python-hosted Vinary Tree ABI resource."""

from __future__ import annotations

import json
from dataclasses import dataclass
from typing import ClassVar

from vinary_tree_interop import (
    DomainId,
    LatticeOperand,
    LatticeOptions,
    LatticeResource,
    ScalarWfst,
    ScalarWfstArc,
    ScalarWfstResource,
    ScalarWfstState,
    SemiringOptions,
    SemiringOrder,
    SemiringProperty,
    SemiringResource,
    UnicodeDictionaryResource,
)


class TinyDictionary:
    """One immutable dictionary snapshot containing ``cat``."""

    _edges: ClassVar[dict[int, tuple[tuple[str, int], ...]]] = {
        0: (("c", 1),),
        1: (("a", 2),),
        2: (("t", 3),),
        3: (),
    }

    def root(self) -> int:
        return 0

    def __len__(self) -> int:
        return 1

    def is_final(self, node: int) -> bool:
        return node == 3

    def value(self, node: int) -> int | None:
        return 7 if node == 3 else None

    def edges(self, node: int) -> tuple[tuple[str, int], ...]:
        return self._edges[node]


class TinyWfst:
    """Immutable two-state Unicode/tropical transducer snapshot."""

    def start(self) -> int:
        return 0

    def num_states(self) -> int:
        return 2

    def state(self, state: int) -> ScalarWfstState | None:
        if state == 0:
            return ScalarWfstState(
                None,
                (ScalarWfstArc("c", "k", 1, 0.25),),
            )
        if state == 1:
            return ScalarWfstState(0.0, ())
        return None


@dataclass(frozen=True, slots=True)
class StringSet:
    """Finite-set lattice with deterministic JSON interchange bytes."""

    values: frozenset[str]

    @staticmethod
    def _decode(other: LatticeOperand) -> frozenset[str]:
        local = other.python_value()
        if isinstance(local, StringSet):
            return local.values
        decoded = json.loads(other.stable_bytes().decode("utf-8"))
        if not isinstance(decoded, list) or not all(
            isinstance(value, str) for value in decoded
        ):
            raise ValueError("foreign set-lattice encoding is malformed")
        return frozenset(decoded)

    def join(self, other: LatticeOperand) -> StringSet:
        return StringSet(self.values | self._decode(other))

    def meet(self, other: LatticeOperand) -> StringSet:
        return StringSet(self.values & self._decode(other))

    def equal(self, other: LatticeOperand) -> bool:
        return self.values == self._decode(other)

    def stable_bytes(self) -> bytes:
        return json.dumps(
            sorted(self.values), ensure_ascii=False, separators=(",", ":")
        ).encode("utf-8")

    def diagnostic(self) -> str:
        return f"StringSet({sorted(self.values)!r})"


class BooleanSemiring:
    """Boolean path-existence semiring over immutable Python ``bool`` values."""

    def zero(self) -> bool:
        return False

    def one(self) -> bool:
        return True

    def plus(self, left: object, right: object) -> bool:
        return bool(left) or bool(right)

    def times(self, left: object, right: object) -> bool:
        return bool(left) and bool(right)

    def equal(self, left: object, right: object) -> bool:
        return left is right

    def approximately_equal(self, left: object, right: object, epsilon: float) -> bool:
        return self.equal(left, right)

    def natural_order(self, left: object, right: object) -> SemiringOrder:
        if left is right:
            return SemiringOrder.EQUAL
        return SemiringOrder.WORSE if bool(left) else SemiringOrder.BETTER

    def stable_bytes(self, value: object) -> bytes:
        return bytes((int(bool(value)),))

    def diagnostic(self, value: object | None = None) -> str:
        return "Boolean semiring" if value is None else repr(bool(value))


def main() -> None:
    """Create deterministic resources and release every facade with ``with``."""
    set_domain = DomainId.ascii("py.set.strs.v001")
    semiring_domain = DomainId.ascii("py.bool.sem.v001")
    properties = (
        SemiringProperty.HASHABLE
        | SemiringProperty.IDEMPOTENT_PLUS
        | SemiringProperty.ZERO_SUM_FREE
        | SemiringProperty.COMMUTATIVE_TIMES
        | SemiringProperty.TOTALLY_ORDERED
        | SemiringProperty.NONNEGATIVE
    )

    with (
        UnicodeDictionaryResource(lambda: TinyDictionary()) as dictionary,
        ScalarWfstResource(lambda: TinyWfst(), acyclic=True) as wfst,
        LatticeResource(
            StringSet(frozenset({"search", "speech"})),
            LatticeOptions(set_domain, parallel_reentrant=True),
        ) as lattice,
        SemiringResource(
            BooleanSemiring(),
            SemiringOptions(
                semiring_domain,
                properties=properties,
                parallel_reentrant=True,
            ),
        ) as semiring,
    ):
        resources = (dictionary, wfst, lattice, semiring)
        if not all(resource.native_resource.context for resource in resources):
            raise RuntimeError("provider resource registration failed")
        with ScalarWfst(wfst) as view, view.snapshot() as frozen:
            if frozen.start != 0 or frozen.state_count != 2:
                raise RuntimeError("scalar-WFST consumer observed invalid metadata")
            start = frozen.state(frozen.start, batch_size=1)
            if start is None or len(start.arcs) != 1:
                raise RuntimeError("scalar-WFST consumer observed invalid paging")
        # Pass ``resource.native_resource`` by pointer to a synchronous native
        # constructor. The consumer retains it if the resulting object outlives
        # that call; this facade keeps its independent retain until ``with`` exits.


if __name__ == "__main__":
    main()
