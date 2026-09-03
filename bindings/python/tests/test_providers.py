"""Executable ctypes conformance tests for Python-hosted ABI providers."""

from __future__ import annotations

import ctypes
import gc
import math
import struct
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from typing import Any, cast

import vinary_tree_interop as interop


def vtable_address(resource: interop.VtResource) -> int:
    """Return a non-null vtable address for low-level ABI assertions."""
    if resource.vtable is None:
        raise AssertionError("resource has a null vtable")
    return resource.vtable


def interface(resource: interop.VtResource, identity: bytes, table_type: type):
    """Negotiate and return one private ctypes table for ABI-level testing."""
    base = ctypes.cast(
        vtable_address(resource), ctypes.POINTER(interop._ResourceVTable)
    ).contents
    identifier = interop._InterfaceId((ctypes.c_uint8 * 16).from_buffer_copy(identity))
    output = ctypes.c_void_p()
    status = base.query_interface(
        resource.context, ctypes.byref(identifier), 1, ctypes.byref(output)
    )
    if status != 0:
        raise AssertionError(f"query_interface returned {status}")
    return base, ctypes.cast(output, ctypes.POINTER(table_type)).contents


class DictionarySnapshot:
    def root(self) -> int:
        return 0

    def __len__(self) -> int:
        return 1

    def is_final(self, node: int) -> bool:
        return node == 1

    def value(self, node: int) -> int | None:
        return 7 if node == 1 else None

    def edges(self, node: int):
        if node == 0:
            return (("x", 1),)
        if node == 1:
            return ()
        raise ValueError("unknown dictionary node")


class WfstSnapshot:
    def __init__(self) -> None:
        self.state_calls = 0
        self.seen_threads: set[int] = set()
        self.seen_lock = threading.Lock()

    def start(self) -> int:
        return 0

    def num_states(self) -> int | None:
        return 2

    def state(self, state: int) -> interop.ScalarWfstState | None:
        with self.seen_lock:
            self.state_calls += 1
            self.seen_threads.add(threading.get_ident())
        if state == 0:
            return interop.ScalarWfstState(
                None,
                (
                    interop.ScalarWfstArc("a", "b", 1, 0.5),
                    interop.ScalarWfstArc(None, "c", 1, math.inf),
                ),
            )
        if state == 1:
            return interop.ScalarWfstState(1.25, ())
        return None


class MaxMin:
    def __init__(self, value: int) -> None:
        self.value = value

    @staticmethod
    def _value(other: interop.LatticeOperand) -> int:
        local = other.python_value()
        if isinstance(local, MaxMin):
            return local.value
        return struct.unpack(">q", other.stable_bytes())[0]

    def join(self, other: interop.LatticeOperand) -> MaxMin:
        return MaxMin(max(self.value, self._value(other)))

    def meet(self, other: interop.LatticeOperand) -> MaxMin:
        return MaxMin(min(self.value, self._value(other)))

    def equal(self, other: interop.LatticeOperand) -> bool:
        return self.value == self._value(other)

    def stable_bytes(self) -> bytes:
        return struct.pack(">q", self.value)

    def diagnostic(self) -> str:
        return f"MaxMin({self.value})"


class CapturingMaxMin(MaxMin):
    """Lattice value that records a callback-scoped borrowed operand."""

    def __init__(self, value: int) -> None:
        super().__init__(value)
        self.borrowed_operand: interop.LatticeOperand | None = None
        self.borrowed_was_local: bool | None = None

    def join(self, other: interop.LatticeOperand) -> MaxMin:
        self.borrowed_operand = other
        self.borrowed_was_local = other.python_value() is not None
        return super().join(other)


class ProbabilitySemiring:
    """Full optional-capability provider used to exercise every ABI table."""

    def __init__(self) -> None:
        self.plus_many_calls = 0
        self.times_many_calls = 0

    @staticmethod
    def _scalar(value: object) -> float:
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise TypeError("probability-semiring values must be real scalars")
        return float(value)

    def zero(self) -> float:
        return 0.0

    def one(self) -> float:
        return 1.0

    def plus(self, left: object, right: object) -> float:
        return self._scalar(left) + self._scalar(right)

    def times(self, left: object, right: object) -> float:
        return self._scalar(left) * self._scalar(right)

    def equal(self, left: object, right: object) -> bool:
        return struct.pack(">d", self._scalar(left)) == struct.pack(
            ">d", self._scalar(right)
        )

    def approximately_equal(self, left: object, right: object, epsilon: float) -> bool:
        return abs(self._scalar(left) - self._scalar(right)) <= epsilon

    def natural_order(self, left: object, right: object) -> interop.SemiringOrder:
        difference = self._scalar(left) - self._scalar(right)
        if difference < 0:
            return interop.SemiringOrder.BETTER
        if difference > 0:
            return interop.SemiringOrder.WORSE
        return interop.SemiringOrder.EQUAL

    def stable_bytes(self, value: object) -> bytes:
        return struct.pack(">d", self._scalar(value))

    def diagnostic(self, value: object | None = None) -> str:
        return "probability semiring" if value is None else str(self._scalar(value))

    def plus_many(self, values: tuple[object, ...]) -> float:
        self.plus_many_calls += 1
        return sum(self._scalar(value) for value in values)

    def times_many(self, values: tuple[object, ...]) -> float:
        self.times_many_calls += 1
        return math.prod(self._scalar(value) for value in values)

    def divide(self, dividend: object, divisor: object) -> float | None:
        denominator = self._scalar(divisor)
        return None if denominator == 0.0 else self._scalar(dividend) / denominator

    def left_divide(self, value: object, divisor: object) -> float | None:
        return self.divide(value, divisor)

    def star(self, value: object) -> float | None:
        scalar = self._scalar(value)
        return 1.0 / (1.0 - scalar) if abs(scalar) < 1.0 else None

    def numerical_value(self, value: object) -> float:
        return self._scalar(value)

    def quantize(self, value: object, epsilon: float) -> int:
        return round(self._scalar(value) / epsilon)

    def to_probability(self, value: object) -> float:
        return self._scalar(value)


class ProviderTests(unittest.TestCase):
    def test_ctypes_semiring_layouts_match_the_lp64_abi(self) -> None:
        self.assertEqual(ctypes.sizeof(interop.VtSemiringValue), 16)
        self.assertEqual(ctypes.sizeof(interop._SemiringVTable), 144)
        self.assertEqual(ctypes.sizeof(interop._SemiringDivisionVTable), 32)
        self.assertEqual(ctypes.sizeof(interop._SemiringStarVTable), 24)
        self.assertEqual(ctypes.sizeof(interop._SemiringNumericVTable), 40)
        self.assertEqual(ctypes.sizeof(interop._SemiringPropertiesVTable), 32)
        self.assertEqual(interop._SemiringVTable.times_many.offset, 136)
        identities = (
            interop.SEMIRING_INTERFACE_ID,
            interop.SEMIRING_DIVISION_INTERFACE_ID,
            interop.SEMIRING_STAR_INTERFACE_ID,
            interop.SEMIRING_NUMERIC_INTERFACE_ID,
            interop.SEMIRING_PROPERTIES_INTERFACE_ID,
        )
        self.assertTrue(all(len(identity) == 16 for identity in identities))
        self.assertEqual(interop.ValueDomain.OPTIONAL_U64, 1)
        self.assertEqual(interop.DictionaryFlag.IMMUTABLE, 4)
        self.assertEqual(interop.WfstFlag.ACYCLIC, 8)
        self.assertEqual(interop.LatticeFlag.BATCH, 8)
        self.assertEqual(interop.SemiringFlag.BATCH, 8)

    def test_dictionary_snapshot_retain_and_stale_handle(self) -> None:
        provider = interop.UnicodeDictionaryResource(lambda: DictionarySnapshot())
        live = provider.native_resource
        base, table = interface(
            live, interop.DICTIONARY_INTERFACE_ID, interop._DictionaryVTable
        )

        snapshot = interop.VtResource()
        self.assertEqual(table.snapshot(live.context, ctypes.byref(snapshot)), 0)
        snapshot_base, snapshot_table = interface(
            snapshot, interop.DICTIONARY_INTERFACE_ID, interop._DictionaryVTable
        )
        root = ctypes.c_uint64()
        self.assertEqual(snapshot_table.root(snapshot.context, ctypes.byref(root)), 0)
        self.assertEqual(root.value, 0)
        child = ctypes.c_uint64()
        found = ctypes.c_uint8()
        self.assertEqual(
            snapshot_table.node_transition(
                snapshot.context,
                root.value,
                ord("x"),
                ctypes.byref(child),
                ctypes.byref(found),
            ),
            0,
        )
        self.assertEqual((found.value, child.value), (1, 1))

        base.retain(live.context)
        provider.close()
        interface(live, interop.DICTIONARY_INTERFACE_ID, interop._DictionaryVTable)
        base.release(live.context)
        identifier = interop._InterfaceId(
            (ctypes.c_uint8 * 16).from_buffer_copy(interop.DICTIONARY_INTERFACE_ID)
        )
        output = ctypes.c_void_p()
        self.assertEqual(
            base.query_interface(
                live.context, ctypes.byref(identifier), 1, ctypes.byref(output)
            ),
            6,
        )
        snapshot_base.release(snapshot.context)

    def test_scalar_wfst_consumer_retains_snapshots_and_pages(self) -> None:
        source = WfstSnapshot()
        provider = interop.ScalarWfstResource(
            lambda: source,
            lazy=False,
            acyclic=True,
        )
        graph = interop.ScalarWfst(provider)
        provider.close()

        self.assertEqual(graph.unit_domain, interop.UnitDomain.UNICODE_SCALAR)
        self.assertEqual(graph.weight_domain, interop.WeightDomain.TROPICAL_F64)
        self.assertTrue(graph.flags & interop.WfstFlag.ACYCLIC)
        self.assertEqual(graph.start, 0)
        self.assertEqual(graph.state_count, 2)
        self.assertEqual(len(graph), 2)
        self.assertEqual(graph.state_info(1), interop.ScalarWfstStateInfo(True, 1.25))
        self.assertIsNone(graph.state_info(99))
        self.assertEqual(
            graph.arcs(0, batch_size=1),
            (
                interop.ScalarWfstArc(ord("a"), ord("b"), 1, 0.5),
                interop.ScalarWfstArc(None, ord("c"), 1, math.inf),
            ),
        )
        self.assertEqual(graph.state(1), interop.ScalarWfstState(1.25, ()))

        snapshot = graph.snapshot()
        graph.close()
        self.assertEqual(snapshot.start, 0)
        self.assertEqual(snapshot.state_count, 2)
        snapshot.close()
        snapshot.close()
        with self.assertRaises(interop.InteropError) as closed:
            _ = snapshot.start
        self.assertEqual(closed.exception.status, interop.Status.CLOSED)

    def test_scalar_wfst_consumer_preserves_unknown_lazy_count(self) -> None:
        class LazySnapshot(WfstSnapshot):
            def num_states(self) -> int | None:
                return None

        with (
            interop.ScalarWfstResource(lambda: LazySnapshot()) as provider,
            interop.ScalarWfst(provider) as graph,
        ):
            self.assertIsNone(graph.state_count)
            with self.assertRaises(TypeError):
                len(graph)
            with self.assertRaises(ValueError):
                graph.arcs(0, batch_size=0)

    def test_dictionary_rejects_malformed_results_transactionally(self) -> None:
        class MalformedDictionary(DictionarySnapshot):
            def root(self) -> int:
                return -1

            def is_final(self, node: int) -> bool:
                return cast(Any, 1)

            def value(self, node: int) -> int | None:
                return True

            def edges(self, node: int) -> tuple[tuple[str, int], ...]:
                return (("a", 1), ("\ud800", 2))

        with interop.UnicodeDictionaryResource(
            lambda: MalformedDictionary()
        ) as provider:
            live = provider.native_resource
            _, table = interface(
                live, interop.DICTIONARY_INTERFACE_ID, interop._DictionaryVTable
            )
            snapshot = interop.VtResource()
            self.assertEqual(table.snapshot(live.context, ctypes.byref(snapshot)), 0)
            snapshot_base, table = interface(
                snapshot, interop.DICTIONARY_INTERFACE_ID, interop._DictionaryVTable
            )

            root = ctypes.c_uint64(0x5A)
            self.assertEqual(
                table.root(snapshot.context, ctypes.byref(root)),
                interop.Status.PROVIDER_ERROR,
            )
            self.assertEqual(root.value, 0x5A)

            final = ctypes.c_uint8(0x5A)
            self.assertEqual(
                table.node_is_final(snapshot.context, 0, ctypes.byref(final)),
                interop.Status.PROVIDER_ERROR,
            )
            self.assertEqual(final.value, 0x5A)

            value = interop._OptionalU64(0x5A, 0x5A, (ctypes.c_uint8 * 7)())
            self.assertEqual(
                table.node_value_u64(snapshot.context, 0, ctypes.byref(value)),
                interop.Status.PROVIDER_ERROR,
            )
            self.assertEqual((value.value, value.has_value), (0x5A, 0x5A))

            edges = (interop._Edge * 2)(
                interop._Edge(0x5A, 0x5A), interop._Edge(0x5A, 0x5A)
            )
            written = ctypes.c_size_t(0x5A)
            total = ctypes.c_size_t(0x5A)
            self.assertEqual(
                table.node_edges(
                    snapshot.context,
                    0,
                    0,
                    edges,
                    2,
                    ctypes.byref(written),
                    ctypes.byref(total),
                ),
                interop.Status.PROVIDER_ERROR,
            )
            self.assertEqual((written.value, total.value), (0x5A, 0x5A))
            self.assertEqual(
                [(edge.label, edge.node) for edge in edges],
                [(0x5A, 0x5A), (0x5A, 0x5A)],
            )

            child = ctypes.c_uint64(0x5A)
            found = ctypes.c_uint8(0x5A)
            self.assertEqual(
                table.node_transition(
                    snapshot.context,
                    0,
                    0x110000,
                    ctypes.byref(child),
                    ctypes.byref(found),
                ),
                interop.Status.INVALID_ARGUMENT,
            )
            self.assertEqual((child.value, found.value), (0x5A, 0x5A))
            snapshot_base.release(snapshot.context)

    def test_wfst_snapshot_paging_cache_and_concurrency(self) -> None:
        graph = WfstSnapshot()
        with interop.ScalarWfstResource(
            lambda: graph,
            parallel_reentrant=True,
            lazy=True,
            acyclic=True,
        ) as provider:
            live = provider.native_resource
            _, table = interface(live, interop.WFST_INTERFACE_ID, interop._WfstVTable)
            snapshot = interop.VtResource()
            self.assertEqual(table.snapshot(live.context, ctypes.byref(snapshot)), 0)
            snapshot_base, table = interface(
                snapshot, interop.WFST_INTERFACE_ID, interop._WfstVTable
            )

            start = ctypes.c_uint64()
            self.assertEqual(table.start(snapshot.context, ctypes.byref(start)), 0)
            self.assertEqual(start.value, 0)
            count = ctypes.c_size_t()
            known = ctypes.c_uint8()
            self.assertEqual(
                table.num_states(
                    snapshot.context, ctypes.byref(count), ctypes.byref(known)
                ),
                0,
            )
            self.assertEqual((known.value, count.value), (1, 2))

            valid = ctypes.c_uint8()
            final = ctypes.c_uint8()
            weight = ctypes.c_double()
            self.assertEqual(
                table.state_info(
                    snapshot.context,
                    0,
                    ctypes.byref(valid),
                    ctypes.byref(final),
                    ctypes.byref(weight),
                ),
                0,
            )
            self.assertEqual((valid.value, final.value), (1, 0))

            page = (interop._WfstArc * 1)()
            written = ctypes.c_size_t()
            total = ctypes.c_size_t()
            self.assertEqual(
                table.state_arcs(
                    snapshot.context,
                    0,
                    0,
                    page,
                    1,
                    ctypes.byref(written),
                    ctypes.byref(total),
                ),
                0,
            )
            self.assertEqual((written.value, total.value), (1, 2))
            self.assertEqual(
                (page[0].input_label, page[0].output_label, page[0].target_state),
                (ord("a"), ord("b"), 1),
            )
            self.assertEqual(graph.state_calls, 1)

            def inspect_final(_index: int) -> int:
                local_valid = ctypes.c_uint8()
                local_final = ctypes.c_uint8()
                local_weight = ctypes.c_double()
                status = table.state_info(
                    snapshot.context,
                    1,
                    ctypes.byref(local_valid),
                    ctypes.byref(local_final),
                    ctypes.byref(local_weight),
                )
                self.assertEqual(status, 0)
                self.assertEqual((local_valid.value, local_final.value), (1, 1))
                self.assertEqual(local_weight.value, 1.25)
                return status

            with ThreadPoolExecutor(max_workers=8) as executor:
                self.assertEqual(
                    list(executor.map(inspect_final, range(128))), [0] * 128
                )
            self.assertGreaterEqual(len(graph.seen_threads), 1)
            snapshot_base.release(snapshot.context)

    def test_wfst_exception_is_contained_as_provider_error(self) -> None:
        class InvalidWeight(WfstSnapshot):
            def state(self, state: int) -> interop.ScalarWfstState | None:
                return interop.ScalarWfstState(float("nan"), ())

        with interop.ScalarWfstResource(lambda: InvalidWeight()) as provider:
            live = provider.native_resource
            _, table = interface(live, interop.WFST_INTERFACE_ID, interop._WfstVTable)
            snapshot = interop.VtResource()
            self.assertEqual(table.snapshot(live.context, ctypes.byref(snapshot)), 0)
            snapshot_base, table = interface(
                snapshot, interop.WFST_INTERFACE_ID, interop._WfstVTable
            )
            valid = ctypes.c_uint8(0x5A)
            final = ctypes.c_uint8(0x5A)
            weight = ctypes.c_double(91.0)
            self.assertEqual(
                table.state_info(
                    snapshot.context,
                    0,
                    ctypes.byref(valid),
                    ctypes.byref(final),
                    ctypes.byref(weight),
                ),
                8,
            )
            self.assertIsInstance(provider.last_callback_error, ValueError)
            self.assertEqual(
                (valid.value, final.value, weight.value), (0x5A, 0x5A, 91.0)
            )
            snapshot_base.release(snapshot.context)

    def test_wfst_rejects_malformed_pages_without_partial_writes(self) -> None:
        class MalformedWfst(WfstSnapshot):
            def num_states(self) -> int | None:
                return True

            def state(self, state: int) -> interop.ScalarWfstState | None:
                return interop.ScalarWfstState(
                    None,
                    (
                        interop.ScalarWfstArc("a", "b", 1, 0.0),
                        interop.ScalarWfstArc("c", "d", -1, 0.0),
                    ),
                )

        with interop.ScalarWfstResource(lambda: MalformedWfst()) as provider:
            live = provider.native_resource
            _, table = interface(live, interop.WFST_INTERFACE_ID, interop._WfstVTable)
            snapshot = interop.VtResource()
            self.assertEqual(table.snapshot(live.context, ctypes.byref(snapshot)), 0)
            snapshot_base, table = interface(
                snapshot, interop.WFST_INTERFACE_ID, interop._WfstVTable
            )

            count = ctypes.c_size_t(0x5A)
            known = ctypes.c_uint8(0x5A)
            self.assertEqual(
                table.num_states(
                    snapshot.context, ctypes.byref(count), ctypes.byref(known)
                ),
                interop.Status.PROVIDER_ERROR,
            )
            self.assertEqual((count.value, known.value), (0x5A, 0x5A))

            arcs = (interop._WfstArc * 2)()
            for arc in arcs:
                arc.input_label = 0x5A
                arc.output_label = 0x5A
                arc.target_state = 0x5A
                arc.weight = 91.0
                arc.has_input = 0x5A
                arc.has_output = 0x5A
            written = ctypes.c_size_t(0x5A)
            total = ctypes.c_size_t(0x5A)
            self.assertEqual(
                table.state_arcs(
                    snapshot.context,
                    0,
                    0,
                    arcs,
                    2,
                    ctypes.byref(written),
                    ctypes.byref(total),
                ),
                interop.Status.PROVIDER_ERROR,
            )
            self.assertEqual((written.value, total.value), (0x5A, 0x5A))
            self.assertTrue(
                all(
                    (
                        arc.input_label,
                        arc.output_label,
                        arc.target_state,
                        arc.weight,
                        arc.has_input,
                        arc.has_output,
                    )
                    == (0x5A, 0x5A, 0x5A, 91.0, 0x5A, 0x5A)
                    for arc in arcs
                )
            )
            snapshot_base.release(snapshot.context)

    def test_lattice_operations_batches_domains_and_borrow_lifetime(self) -> None:
        options = interop.LatticeOptions(interop.DomainId.ascii("py.maxmin.i64.v1"))
        two_provider = CapturingMaxMin(2)
        with (
            interop.LatticeResource(two_provider, options) as two,
            interop.LatticeResource(MaxMin(7), options) as seven,
            interop.LatticeResource(MaxMin(5), options) as five,
        ):
            two_resource = two.native_resource
            _, table = interface(
                two_resource, interop.LATTICE_INTERFACE_ID, interop._LatticeVTable
            )

            joined = interop.VtResource()
            seven_resource = seven.native_resource
            self.assertEqual(
                table.join(
                    two_resource.context,
                    ctypes.byref(seven_resource),
                    ctypes.byref(joined),
                ),
                0,
            )
            joined_base, joined_table = interface(
                joined, interop.LATTICE_INTERFACE_ID, interop._LatticeVTable
            )
            required = ctypes.c_size_t()
            written = ctypes.c_size_t()
            self.assertEqual(
                joined_table.stable_bytes(
                    joined.context,
                    None,
                    0,
                    ctypes.byref(written),
                    ctypes.byref(required),
                ),
                0,
            )
            self.assertEqual((written.value, required.value), (0, 8))
            encoded = (ctypes.c_uint8 * 8)()
            self.assertEqual(
                joined_table.stable_bytes(
                    joined.context,
                    encoded,
                    8,
                    ctypes.byref(written),
                    ctypes.byref(required),
                ),
                0,
            )
            self.assertEqual(struct.unpack(">q", bytes(encoded))[0], 7)
            joined_base.release(joined.context)
            self.assertTrue(two_provider.borrowed_was_local)

            borrowed = cast(interop.LatticeOperand, two_provider.borrowed_operand)
            with self.assertRaisesRegex(RuntimeError, "no longer borrowed"):
                borrowed.python_value()
            with self.assertRaisesRegex(RuntimeError, "no longer borrowed"):
                borrowed.stable_bytes()

            local_base = ctypes.cast(
                vtable_address(seven_resource),
                ctypes.POINTER(interop._ResourceVTable),
            ).contents
            proxy_base = interop._ResourceVTable.from_buffer_copy(
                ctypes.string_at(
                    ctypes.addressof(local_base),
                    ctypes.sizeof(interop._ResourceVTable),
                )
            )
            foreign_proxy = interop.VtResource(
                seven_resource.context,
                ctypes.addressof(proxy_base),
            )
            proxy_joined = interop.VtResource()
            self.assertEqual(
                table.join(
                    two_resource.context,
                    ctypes.byref(foreign_proxy),
                    ctypes.byref(proxy_joined),
                ),
                interop.Status.OK,
            )
            self.assertFalse(two_provider.borrowed_was_local)
            proxy_base_table = ctypes.cast(
                vtable_address(proxy_joined),
                ctypes.POINTER(interop._ResourceVTable),
            ).contents
            proxy_base_table.release(proxy_joined.context)

            operands = (interop.VtResource * 2)(
                seven.native_resource, five.native_resource
            )
            folded = interop.VtResource()
            self.assertEqual(
                table.meet_many(
                    two_resource.context, operands, 2, ctypes.byref(folded)
                ),
                0,
            )
            folded_base, folded_table = interface(
                folded, interop.LATTICE_INTERFACE_ID, interop._LatticeVTable
            )
            five_resource = five.native_resource
            equal = ctypes.c_uint8()
            self.assertEqual(
                folded_table.equal(
                    folded.context, ctypes.byref(five_resource), ctypes.byref(equal)
                ),
                0,
            )
            self.assertEqual(equal.value, 0)
            folded_base.release(folded.context)

            retained_identity = interop.VtResource()
            self.assertEqual(
                table.join_many(
                    two_resource.context, None, 0, ctypes.byref(retained_identity)
                ),
                0,
            )
            self.assertEqual(retained_identity.context, two_resource.context)
            base = ctypes.cast(
                vtable_address(retained_identity),
                ctypes.POINTER(interop._ResourceVTable),
            ).contents
            base.release(retained_identity.context)

            foreign_options = interop.LatticeOptions(
                interop.DomainId.ascii("py.other.i64.v01")
            )
            with interop.LatticeResource(MaxMin(3), foreign_options) as foreign:
                foreign_resource = foreign.native_resource
                rejected = interop.VtResource()
                self.assertEqual(
                    table.join(
                        two_resource.context,
                        ctypes.byref(foreign_resource),
                        ctypes.byref(rejected),
                    ),
                    2,
                )
                self.assertIsInstance(
                    two.last_callback_error, interop.ProviderStatusError
                )

    def test_semiring_all_capabilities_tokens_batches_and_concurrency(self) -> None:
        provider = ProbabilitySemiring()
        properties = (
            interop.SemiringProperty.K_CLOSED
            | interop.SemiringProperty.COMMUTATIVE_TIMES
            | interop.SemiringProperty.TOTALLY_ORDERED
            | interop.SemiringProperty.NONNEGATIVE
        )
        options = interop.SemiringOptions(
            interop.DomainId.ascii("py.prob.f64.v001"),
            properties=properties,
            closure_bound=8,
            parallel_reentrant=True,
        )
        with interop.SemiringResource(provider, options) as resource:
            native = resource.native_resource
            base, table = interface(
                native, interop.SEMIRING_INTERFACE_ID, interop._SemiringVTable
            )
            self.assertEqual(ctypes.sizeof(table), 144)
            self.assertEqual(table.flags, 4 | 8 | 2)

            zero = interop.VtSemiringValue()
            one = interop.VtSemiringValue()
            summed = interop.VtSemiringValue()
            product = interop.VtSemiringValue()
            self.assertEqual(table.zero(native.context, ctypes.byref(zero)), 0)
            self.assertEqual(table.one(native.context, ctypes.byref(one)), 0)
            self.assertEqual(
                table.plus(
                    native.context,
                    ctypes.byref(zero),
                    ctypes.byref(one),
                    ctypes.byref(summed),
                ),
                0,
            )
            self.assertEqual(
                table.times(
                    native.context,
                    ctypes.byref(one),
                    ctypes.byref(one),
                    ctypes.byref(product),
                ),
                0,
            )

            def stable(value: interop.VtSemiringValue) -> float:
                written = ctypes.c_size_t()
                required = ctypes.c_size_t()
                self.assertEqual(
                    table.stable_bytes(
                        native.context,
                        ctypes.byref(value),
                        None,
                        0,
                        ctypes.byref(written),
                        ctypes.byref(required),
                    ),
                    0,
                )
                self.assertEqual((written.value, required.value), (0, 8))
                output = (ctypes.c_uint8 * required.value)()
                self.assertEqual(
                    table.stable_bytes(
                        native.context,
                        ctypes.byref(value),
                        output,
                        len(output),
                        ctypes.byref(written),
                        ctypes.byref(required),
                    ),
                    0,
                )
                return struct.unpack(">d", bytes(output))[0]

            self.assertEqual(stable(summed), 1.0)
            exact = ctypes.c_uint8()
            approximate = ctypes.c_uint8()
            order = ctypes.c_int32()
            self.assertEqual(
                table.equal(
                    native.context,
                    ctypes.byref(summed),
                    ctypes.byref(product),
                    ctypes.byref(exact),
                ),
                0,
            )
            self.assertEqual(exact.value, 1)
            self.assertEqual(
                table.approx_equal(
                    native.context,
                    ctypes.byref(summed),
                    ctypes.byref(product),
                    0.0,
                    ctypes.byref(approximate),
                ),
                0,
            )
            self.assertEqual(approximate.value, 1)
            self.assertEqual(
                table.natural_order(
                    native.context,
                    ctypes.byref(zero),
                    ctypes.byref(one),
                    ctypes.byref(order),
                ),
                0,
            )
            self.assertEqual(order.value, interop.SemiringOrder.BETTER)

            invalid = ctypes.c_uint8(0x5A)
            self.assertEqual(
                table.approx_equal(
                    native.context,
                    ctypes.byref(zero),
                    ctypes.byref(one),
                    math.nan,
                    ctypes.byref(invalid),
                ),
                interop.Status.INVALID_ARGUMENT,
            )
            self.assertEqual(invalid.value, 0x5A)

            values = (interop.VtSemiringValue * 3)(zero, one, one)
            folded = interop.VtSemiringValue()
            multiplied = interop.VtSemiringValue()
            self.assertEqual(
                table.plus_many(native.context, values, 3, ctypes.byref(folded)), 0
            )
            self.assertEqual(
                table.times_many(native.context, values, 3, ctypes.byref(multiplied)),
                0,
            )
            self.assertEqual((stable(folded), stable(multiplied)), (2.0, 0.0))
            self.assertEqual(
                (provider.plus_many_calls, provider.times_many_calls), (1, 1)
            )

            _, division = interface(
                native,
                interop.SEMIRING_DIVISION_INTERFACE_ID,
                interop._SemiringDivisionVTable,
            )
            quotient = interop.VtSemiringValue()
            self.assertEqual(
                division.divide(
                    native.context,
                    ctypes.byref(one),
                    ctypes.byref(one),
                    ctypes.byref(quotient),
                ),
                0,
            )
            undefined = interop.VtSemiringValue(0x5A, 0x5A)
            self.assertEqual(
                division.divide(
                    native.context,
                    ctypes.byref(one),
                    ctypes.byref(zero),
                    ctypes.byref(undefined),
                ),
                interop.Status.END,
            )
            self.assertEqual((undefined.word0, undefined.word1), (0x5A, 0x5A))

            _, star = interface(
                native,
                interop.SEMIRING_STAR_INTERFACE_ID,
                interop._SemiringStarVTable,
            )
            closure = interop.VtSemiringValue()
            self.assertEqual(
                star.star(native.context, ctypes.byref(zero), ctypes.byref(closure)),
                0,
            )
            self.assertEqual(stable(closure), 1.0)
            divergent = interop.VtSemiringValue(0x5A, 0x5A)
            self.assertEqual(
                star.star(native.context, ctypes.byref(one), ctypes.byref(divergent)),
                interop.Status.END,
            )
            self.assertEqual((divergent.word0, divergent.word1), (0x5A, 0x5A))

            _, numeric = interface(
                native,
                interop.SEMIRING_NUMERIC_INTERFACE_ID,
                interop._SemiringNumericVTable,
            )
            number = ctypes.c_double()
            probability = ctypes.c_double()
            quantized = ctypes.c_int64()
            self.assertEqual(
                numeric.numerical_value(
                    native.context, ctypes.byref(one), ctypes.byref(number)
                ),
                0,
            )
            self.assertEqual(
                numeric.to_probability(
                    native.context, ctypes.byref(one), ctypes.byref(probability)
                ),
                0,
            )
            self.assertEqual(
                numeric.quantize(
                    native.context,
                    ctypes.byref(one),
                    0.25,
                    ctypes.byref(quantized),
                ),
                0,
            )
            self.assertEqual(
                (number.value, probability.value, quantized.value), (1.0, 1.0, 4)
            )

            _, declared = interface(
                native,
                interop.SEMIRING_PROPERTIES_INTERFACE_ID,
                interop._SemiringPropertiesVTable,
            )
            bound = ctypes.c_size_t()
            known = ctypes.c_uint8()
            self.assertEqual(
                declared.closure_bound(
                    native.context, ctypes.byref(bound), ctypes.byref(known)
                ),
                0,
            )
            self.assertEqual(declared.properties, int(properties))
            self.assertEqual((bound.value, known.value), (8, 1))

            cloned = interop.VtSemiringValue()
            self.assertEqual(
                table.clone_value(
                    native.context, ctypes.byref(one), ctypes.byref(cloned)
                ),
                0,
            )
            duplicates = (interop.VtSemiringValue * 2)(cloned, cloned)
            self.assertEqual(
                table.release_values(native.context, duplicates, 2),
                interop.Status.INVALID_ARGUMENT,
            )
            self.assertEqual(stable(cloned), 1.0)

            with interop.SemiringResource(ProbabilitySemiring(), options) as foreign:
                foreign_one = interop.VtSemiringValue()
                _, foreign_table = interface(
                    foreign.native_resource,
                    interop.SEMIRING_INTERFACE_ID,
                    interop._SemiringVTable,
                )
                self.assertEqual(
                    foreign_table.one(
                        foreign.native_resource.context, ctypes.byref(foreign_one)
                    ),
                    0,
                )
                rejected = interop.VtSemiringValue(0x5A, 0x5A)
                self.assertEqual(
                    table.plus(
                        native.context,
                        ctypes.byref(one),
                        ctypes.byref(foreign_one),
                        ctypes.byref(rejected),
                    ),
                    interop.Status.INVALID_ARGUMENT,
                )
                self.assertEqual((rejected.word0, rejected.word1), (0x5A, 0x5A))
                self.assertEqual(
                    foreign_table.release_values(
                        foreign.native_resource.context,
                        ctypes.byref(foreign_one),
                        1,
                    ),
                    0,
                )

            def parallel_add(_index: int) -> int:
                output = interop.VtSemiringValue()
                status = table.plus(
                    native.context,
                    ctypes.byref(zero),
                    ctypes.byref(one),
                    ctypes.byref(output),
                )
                if status == 0:
                    self.assertEqual(stable(output), 1.0)
                    self.assertEqual(
                        table.release_values(native.context, ctypes.byref(output), 1),
                        0,
                    )
                return status

            with ThreadPoolExecutor(max_workers=8) as executor:
                self.assertEqual(
                    list(executor.map(parallel_add, range(128))), [0] * 128
                )

            owned = (
                zero,
                one,
                summed,
                product,
                folded,
                multiplied,
                quotient,
                closure,
                cloned,
            )
            for value in owned:
                self.assertEqual(
                    table.release_values(native.context, ctypes.byref(value), 1), 0
                )

            base.retain(native.context)
            resource.close()
            interface(native, interop.SEMIRING_INTERFACE_ID, interop._SemiringVTable)
            base.release(native.context)
            identifier = interop._InterfaceId(
                (ctypes.c_uint8 * 16).from_buffer_copy(interop.SEMIRING_INTERFACE_ID)
            )
            output = ctypes.c_void_p()
            self.assertEqual(
                base.query_interface(
                    native.context, ctypes.byref(identifier), 1, ctypes.byref(output)
                ),
                interop.Status.CLOSED,
            )

    def test_semiring_validation_optional_groups_and_error_containment(self) -> None:
        domain = interop.DomainId.ascii("py.prob.f64.v001")
        with self.assertRaises(ValueError):
            interop.SemiringOptions(
                domain,
                properties=interop.SemiringProperty(128),
            )
        with self.assertRaises(ValueError):
            interop.SemiringOptions(domain, closure_bound=1)

        partial_division = ProbabilitySemiring()
        cast(Any, partial_division).left_divide = None
        with self.assertRaises(TypeError):
            interop.SemiringResource(partial_division, interop.SemiringOptions(domain))

        class Failing(ProbabilitySemiring):
            def plus(self, left: object, right: object) -> float:
                raise interop.ProviderStatusError(
                    interop.Status.LIMIT_EXCEEDED, "deliberate limit"
                )

        with interop.SemiringResource(
            Failing(), interop.SemiringOptions(domain)
        ) as resource:
            native = resource.native_resource
            _, table = interface(
                native, interop.SEMIRING_INTERFACE_ID, interop._SemiringVTable
            )
            zero = interop.VtSemiringValue()
            one = interop.VtSemiringValue()
            self.assertEqual(table.zero(native.context, ctypes.byref(zero)), 0)
            self.assertEqual(table.one(native.context, ctypes.byref(one)), 0)
            output = interop.VtSemiringValue(0x5A, 0x5A)
            self.assertEqual(
                table.plus(
                    native.context,
                    ctypes.byref(zero),
                    ctypes.byref(one),
                    ctypes.byref(output),
                ),
                interop.Status.LIMIT_EXCEEDED,
            )
            self.assertEqual((output.word0, output.word1), (0x5A, 0x5A))
            self.assertIsInstance(
                resource.last_callback_error, interop.ProviderStatusError
            )
            values = (interop.VtSemiringValue * 2)(zero, one)
            self.assertEqual(table.release_values(native.context, values, 2), 0)

    def test_semiring_base_only_batches_validation_and_gc_fallback(self) -> None:
        options = interop.SemiringOptions(interop.DomainId.ascii("py.prob.f64.v001"))
        base_only = ProbabilitySemiring()
        for method in (
            "divide",
            "left_divide",
            "star",
            "numerical_value",
            "quantize",
            "to_probability",
        ):
            setattr(base_only, method, None)
        resource = interop.SemiringResource(base_only, options)
        native = resource.native_resource
        base, table = interface(
            native, interop.SEMIRING_INTERFACE_ID, interop._SemiringVTable
        )

        for identity in (
            interop.SEMIRING_DIVISION_INTERFACE_ID,
            interop.SEMIRING_STAR_INTERFACE_ID,
            interop.SEMIRING_NUMERIC_INTERFACE_ID,
        ):
            identifier = interop._InterfaceId(
                (ctypes.c_uint8 * 16).from_buffer_copy(identity)
            )
            output = ctypes.c_void_p(0x5A)
            self.assertEqual(
                base.query_interface(
                    native.context, ctypes.byref(identifier), 1, ctypes.byref(output)
                ),
                interop.Status.UNSUPPORTED,
            )
            self.assertEqual(output.value, 0x5A)

        _, declared = interface(
            native,
            interop.SEMIRING_PROPERTIES_INTERFACE_ID,
            interop._SemiringPropertiesVTable,
        )
        bound = ctypes.c_size_t(0x5A)
        known = ctypes.c_uint8(0x5A)
        self.assertEqual(
            declared.closure_bound(
                native.context, ctypes.byref(bound), ctypes.byref(known)
            ),
            0,
        )
        self.assertEqual((bound.value, known.value), (0, 0))

        additive_identity = interop.VtSemiringValue()
        multiplicative_identity = interop.VtSemiringValue()
        self.assertEqual(
            table.plus_many(native.context, None, 0, ctypes.byref(additive_identity)),
            0,
        )
        self.assertEqual(
            table.times_many(
                native.context, None, 0, ctypes.byref(multiplicative_identity)
            ),
            0,
        )
        too_large = interop.VtSemiringValue(0x5A, 0x5A)
        self.assertEqual(
            table.plus_many(
                native.context,
                ctypes.byref(additive_identity),
                interop.RECOMMENDED_SEMIRING_BATCH + 1,
                ctypes.byref(too_large),
            ),
            interop.Status.LIMIT_EXCEEDED,
        )
        self.assertEqual((too_large.word0, too_large.word1), (0x5A, 0x5A))
        values = (interop.VtSemiringValue * 2)(
            additive_identity, multiplicative_identity
        )
        self.assertEqual(table.release_values(native.context, values, 2), 0)

        del resource
        gc.collect()
        identifier = interop._InterfaceId(
            (ctypes.c_uint8 * 16).from_buffer_copy(interop.SEMIRING_INTERFACE_ID)
        )
        output = ctypes.c_void_p()
        self.assertEqual(
            base.query_interface(
                native.context, ctypes.byref(identifier), 1, ctypes.byref(output)
            ),
            interop.Status.CLOSED,
        )

    def test_semiring_rejects_malformed_host_results_without_partial_output(
        self,
    ) -> None:
        domain = interop.DomainId.ascii("py.prob.f64.v001")

        class Malformed(ProbabilitySemiring):
            def equal(self, left: object, right: object) -> bool:
                return cast(Any, 1)

            def stable_bytes(self, value: object) -> bytes:
                return cast(Any, 8)

        with interop.SemiringResource(
            Malformed(), interop.SemiringOptions(domain)
        ) as resource:
            native = resource.native_resource
            _, table = interface(
                native, interop.SEMIRING_INTERFACE_ID, interop._SemiringVTable
            )
            zero = interop.VtSemiringValue()
            self.assertEqual(table.zero(native.context, ctypes.byref(zero)), 0)

            equal = ctypes.c_uint8(0x5A)
            self.assertEqual(
                table.equal(
                    native.context,
                    ctypes.byref(zero),
                    ctypes.byref(zero),
                    ctypes.byref(equal),
                ),
                interop.Status.PROVIDER_ERROR,
            )
            self.assertEqual(equal.value, 0x5A)

            written = ctypes.c_size_t(0x5A)
            required = ctypes.c_size_t(0x5A)
            self.assertEqual(
                table.stable_bytes(
                    native.context,
                    ctypes.byref(zero),
                    None,
                    0,
                    ctypes.byref(written),
                    ctypes.byref(required),
                ),
                interop.Status.PROVIDER_ERROR,
            )
            self.assertEqual((written.value, required.value), (0x5A, 0x5A))
            self.assertEqual(
                table.release_values(native.context, ctypes.byref(zero), 1), 0
            )


if __name__ == "__main__":
    unittest.main()
