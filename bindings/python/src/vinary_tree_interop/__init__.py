"""Shared ctypes layouts for modular vinary-tree bindings."""

from __future__ import annotations

import ctypes
import itertools
import math
import threading
from collections.abc import Callable, Sequence
from contextlib import nullcontext
from dataclasses import dataclass
from enum import IntEnum, IntFlag
from typing import Protocol, TypeVar, cast, runtime_checkable

_Pointee_co = TypeVar("_Pointee_co", covariant=True)
_ScalarWfstT = TypeVar("_ScalarWfstT", bound="ScalarWfst")


class _Pointer(Protocol[_Pointee_co]):
    """Structural type of the ctypes pointers accepted by ABI callbacks."""

    @property
    def contents(self) -> _Pointee_co:
        """Dereference the pointer."""
        ...

    def __getitem__(self, index: int, /) -> _Pointee_co:
        """Read a pointee by offset."""
        ...

    def __setitem__(self, index: int, value: object, /) -> None:
        """Write a pointee by offset."""


class UnitDomain(IntEnum):
    """Dictionary edge-label domain."""

    BYTE = 1
    UNICODE_SCALAR = 2
    U64 = 3


class WeightDomain(IntEnum):
    """Portable scalar-weight representation used by scalar WFST resources."""

    TROPICAL_F64 = 1
    LOG_F64 = 2
    PROBABILITY_F64 = 3
    ARCTIC_F64 = 4
    SIGNED_TROPICAL_F64 = 5
    COUNT_F64 = 6
    BOOLEAN_F64 = 7


class ValueDomain(IntEnum):
    """Representation attached to final dictionary nodes."""

    UNIT = 0
    OPTIONAL_U64 = 1
    BYTES = 2


class DictionaryFlag(IntFlag):
    """Dictionary callback and representation capabilities."""

    NONE = 0
    PARALLEL_REENTRANT = 1
    SUFFIX_BASED = 2
    IMMUTABLE = 4


class WfstFlag(IntFlag):
    """Scalar-WFST callback and graph capabilities."""

    NONE = 0
    PARALLEL_REENTRANT = 1
    IMMUTABLE = 2
    LAZY = 4
    ACYCLIC = 8


class LatticeFlag(IntFlag):
    """Dynamic-lattice callback and encoding capabilities."""

    NONE = 0
    THREAD_BOUND = 1
    PARALLEL_REENTRANT = 2
    STABLE_BYTES = 4
    BATCH = 8


class SemiringFlag(IntFlag):
    """Dynamic-semiring callback and encoding capabilities."""

    NONE = 0
    THREAD_BOUND = 1
    PARALLEL_REENTRANT = 2
    STABLE_BYTES = 4
    BATCH = 8


class Status(IntEnum):
    """Stable status discriminants used by every shared ABI callback."""

    OK = 0
    END = 1
    INVALID_ARGUMENT = 2
    NULL_POINTER = 3
    UNSUPPORTED = 4
    IO_ERROR = 5
    CLOSED = 6
    LIMIT_EXCEEDED = 7
    PROVIDER_ERROR = 8
    BATCH_IN_USE = 9


class ProviderStatusError(Exception):
    """Request intentional translation to one portable provider status."""

    def __init__(self, status: Status, message: str) -> None:
        portable = Status(status)
        if portable not in {
            Status.INVALID_ARGUMENT,
            Status.UNSUPPORTED,
            Status.IO_ERROR,
            Status.CLOSED,
            Status.LIMIT_EXCEEDED,
            Status.PROVIDER_ERROR,
        }:
            raise ValueError(f"{portable.name} is not a provider-selectable failure")
        super().__init__(message)
        self.status = portable


class InteropError(RuntimeError):
    """Typed failure reported while consuming a Vinary Tree resource.

    Provider callback authors use :class:`ProviderStatusError` to select a
    portable callback status. Resource consumers receive ``InteropError`` so
    application code cannot accidentally reinterpret a consumer failure as a
    request to return one particular status through another callback.
    """

    def __init__(self, status: int | Status, operation: str, message: str) -> None:
        super().__init__(message)
        try:
            self.status: Status | int = Status(status)
        except ValueError:
            self.status = int(status)
        self.operation = operation


class VtResource(ctypes.Structure):
    """Two-word retained resource passed between native project libraries."""

    context: int | None
    vtable: int | None
    _fields_ = [("context", ctypes.c_void_p), ("vtable", ctypes.c_void_p)]


@runtime_checkable
class NativeResource(Protocol):
    """Borrowable live resource implemented by every Python facade owner."""

    @property
    def native_resource(self) -> VtResource:
        """Borrow the two-word resource for one synchronous native call."""
        ...

    def close(self) -> None:
        """Release this object's owned retain."""
        ...


class UnicodeDictionarySnapshot(Protocol):
    """Immutable node graph captured by a custom Python provider."""

    def root(self) -> int:
        """Return the root node identifier."""
        ...

    def __len__(self) -> int:
        """Return the number of final terms."""
        ...

    def is_final(self, node: int) -> bool:
        """Return whether a node terminates a term."""
        ...

    def value(self, node: int) -> int | None:
        """Return a final node's optional u64 value."""
        ...

    def edges(self, node: int) -> Sequence[tuple[str | int, int]]:
        """Return outgoing Unicode-scalar edges and child node IDs."""
        ...


@runtime_checkable
class DictionaryResource(NativeResource, Protocol):
    """A live resource implementing dictionary interface v1."""

    @property
    def native_resource(self) -> VtResource:
        """Borrow the two-word resource for one synchronous native call."""
        ...

    def close(self) -> None:
        """Release this facade's owned retain."""


ABI_VERSION = 1
DICTIONARY_INTERFACE_VERSION = 1
DICTIONARY_INTERFACE_ID = b"vt.dictionary.v1"


class _InterfaceId(ctypes.Structure):
    _fields_ = [("bytes", ctypes.c_uint8 * 16)]


class _OptionalU64(ctypes.Structure):
    _fields_ = [
        ("value", ctypes.c_uint64),
        ("has_value", ctypes.c_uint8),
        ("reserved", ctypes.c_uint8 * 7),
    ]


class _Edge(ctypes.Structure):
    _fields_ = [("label", ctypes.c_uint64), ("node", ctypes.c_uint64)]


_RETAIN = ctypes.CFUNCTYPE(None, ctypes.c_void_p)
_RELEASE = ctypes.CFUNCTYPE(None, ctypes.c_void_p)
_QUERY_INTERFACE = ctypes.CFUNCTYPE(
    ctypes.c_uint32,
    ctypes.c_void_p,
    ctypes.POINTER(_InterfaceId),
    ctypes.c_uint32,
    ctypes.POINTER(ctypes.c_void_p),
)
_SNAPSHOT = ctypes.CFUNCTYPE(
    ctypes.c_uint32, ctypes.c_void_p, ctypes.POINTER(VtResource)
)
_ROOT = ctypes.CFUNCTYPE(
    ctypes.c_uint32, ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint64)
)
_LEN = ctypes.CFUNCTYPE(
    ctypes.c_uint32,
    ctypes.c_void_p,
    ctypes.POINTER(ctypes.c_size_t),
    ctypes.POINTER(ctypes.c_uint8),
)
_IS_FINAL = ctypes.CFUNCTYPE(
    ctypes.c_uint32, ctypes.c_void_p, ctypes.c_uint64, ctypes.POINTER(ctypes.c_uint8)
)
_VALUE = ctypes.CFUNCTYPE(
    ctypes.c_uint32, ctypes.c_void_p, ctypes.c_uint64, ctypes.POINTER(_OptionalU64)
)
_TRANSITION = ctypes.CFUNCTYPE(
    ctypes.c_uint32,
    ctypes.c_void_p,
    ctypes.c_uint64,
    ctypes.c_uint64,
    ctypes.POINTER(ctypes.c_uint64),
    ctypes.POINTER(ctypes.c_uint8),
)
_EDGES = ctypes.CFUNCTYPE(
    ctypes.c_uint32,
    ctypes.c_void_p,
    ctypes.c_uint64,
    ctypes.c_size_t,
    ctypes.POINTER(_Edge),
    ctypes.c_size_t,
    ctypes.POINTER(ctypes.c_size_t),
    ctypes.POINTER(ctypes.c_size_t),
)


class _ResourceVTable(ctypes.Structure):
    _fields_ = [
        ("struct_size", ctypes.c_size_t),
        ("abi_version", ctypes.c_uint32),
        ("reserved", ctypes.c_uint32),
        ("retain", _RETAIN),
        ("release", _RELEASE),
        ("query_interface", _QUERY_INTERFACE),
    ]


class _DictionaryVTable(ctypes.Structure):
    _fields_ = [
        ("struct_size", ctypes.c_size_t),
        ("interface_version", ctypes.c_uint32),
        ("unit_domain", ctypes.c_uint32),
        ("value_domain", ctypes.c_uint32),
        ("flags", ctypes.c_uint64),
        ("snapshot", _SNAPSHOT),
        ("root", _ROOT),
        ("len", _LEN),
        ("node_is_final", _IS_FINAL),
        ("node_value_u64", _VALUE),
        ("node_transition", _TRANSITION),
        ("node_edges", _EDGES),
    ]


class _ProviderHolder:
    """Common retained-provider state.

    Registry mutation is a lifecycle operation.  Ordinary provider callbacks
    perform a lock-free dictionary lookup and never execute customer code while
    either the registry or retain-count lock is held.
    """

    __slots__ = ("_refs_lock", "context_key", "errors", "parallel", "refs")

    def __init__(
        self,
        *,
        parallel: bool,
        errors: list[BaseException | None] | None = None,
    ) -> None:
        self.parallel = parallel
        self.refs = 1
        self.errors: list[BaseException | None] = (
            errors if errors is not None else [None]
        )
        self._refs_lock = threading.Lock()
        self.context_key = 0

    def interface_vtable(
        self, interface_id: bytes, minimum_version: int
    ) -> ctypes.Structure | None:
        """Return one negotiated interface table, or ``None`` when absent."""
        raise NotImplementedError


class _Holder(_ProviderHolder):
    __slots__ = ("immutable", "source")

    def __init__(
        self,
        source: Callable[[], UnicodeDictionarySnapshot] | UnicodeDictionarySnapshot,
        *,
        immutable: bool,
        parallel: bool,
        errors: list[BaseException | None] | None = None,
    ) -> None:
        super().__init__(parallel=parallel, errors=errors)
        self.source = source
        self.immutable = immutable

    def snapshot(self) -> UnicodeDictionarySnapshot:
        if self.immutable:
            return cast(UnicodeDictionarySnapshot, self.source)
        capture = cast(Callable[[], UnicodeDictionarySnapshot], self.source)
        return capture()

    def interface_vtable(
        self, interface_id: bytes, minimum_version: int
    ) -> ctypes.Structure | None:
        if interface_id != DICTIONARY_INTERFACE_ID or minimum_version > 1:
            return None
        return _dictionary_vtable(self)


_registry: dict[int, _ProviderHolder] = {}
_registry_lock = threading.Lock()
_next_context = itertools.count(1)


def _register(holder: _ProviderHolder) -> int:
    with _registry_lock:
        key = next(_next_context)
        holder.context_key = key
        _registry[key] = holder
    return key


def _dictionary_holder(context: int) -> _Holder | None:
    """Resolve a live dictionary context without raising through a C callback."""
    holder = _registry.get(context)
    return holder if isinstance(holder, _Holder) else None


def _failure_status(holder: _ProviderHolder, error: BaseException) -> int:
    """Record one contained exception and select its portable status."""
    holder.errors[0] = error
    if isinstance(error, ProviderStatusError):
        return error.status
    if isinstance(error, MemoryError):
        return Status.LIMIT_EXCEEDED
    return Status.PROVIDER_ERROR


def _status(holder: _ProviderHolder, operation: Callable[[], None]) -> int:
    try:
        operation()
        return Status.OK
    except BaseException as error:  # noqa: BLE001 - no exception may cross the ABI
        return _failure_status(holder, error)


def _checked_u64(value: object, subject: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or not 0 <= value < 2**64:
        raise ValueError(f"{subject} is outside u64")
    return value


def _checked_size(value: object, subject: str) -> int:
    if (
        isinstance(value, bool)
        or not isinstance(value, int)
        or not 0 <= value <= ctypes.c_size_t(-1).value
    ):
        raise ValueError(f"{subject} is outside size_t")
    return value


def _checked_bool(value: object, subject: str) -> bool:
    if not isinstance(value, bool):
        raise TypeError(f"{subject} must return bool")
    return value


@_RETAIN
def _retain(context: int) -> None:
    # Retain/release are lifecycle operations, not traversal callbacks. The
    # short registry section prevents a final release from racing a valid
    # retain; no customer code runs under this process-wide lock.
    with _registry_lock:
        holder = _registry.get(context)
        if holder is None:
            return
        with holder._refs_lock:
            holder.refs += 1


@_RELEASE
def _release(context: int) -> None:
    with _registry_lock:
        holder = _registry.get(context)
        if holder is None:
            return
        with holder._refs_lock:
            if holder.refs == 0:
                return
            holder.refs -= 1
            if holder.refs == 0:
                del _registry[context]


def _dictionary_vtable(holder: _Holder) -> _DictionaryVTable:
    return _DICTIONARY_VTABLES[(holder.immutable, holder.parallel)]


@_QUERY_INTERFACE
def _query_interface(
    context: int,
    interface_id: _Pointer[_InterfaceId],
    minimum_version: int,
    out_vtable: _Pointer[ctypes.c_void_p],
) -> int:
    if not interface_id or not out_vtable:
        return Status.NULL_POINTER
    holder = _registry.get(context)
    if holder is None:
        return Status.CLOSED
    table = holder.interface_vtable(bytes(interface_id.contents.bytes), minimum_version)
    if table is None:
        return Status.UNSUPPORTED
    out_vtable[0] = ctypes.cast(ctypes.pointer(table), ctypes.c_void_p)
    return Status.OK


@_SNAPSHOT
def _snapshot(context: int, output: _Pointer[VtResource]) -> int:
    if not output:
        return Status.NULL_POINTER
    holder = _dictionary_holder(context)
    if holder is None:
        return Status.CLOSED

    def run() -> None:
        snapshot = holder.snapshot()
        child = _Holder(
            snapshot,
            immutable=True,
            parallel=holder.parallel,
            errors=holder.errors,
        )
        key = _register(child)
        output[0] = VtResource(key, ctypes.addressof(_RESOURCE_VTABLE))

    return _status(holder, run)


@_ROOT
def _root(context: int, output: _Pointer[ctypes.c_uint64]) -> int:
    if not output:
        return Status.NULL_POINTER
    holder = _dictionary_holder(context)
    if holder is None:
        return Status.CLOSED
    return _status(
        holder,
        lambda: output.__setitem__(
            0, _checked_u64(holder.snapshot().root(), "dictionary root")
        ),
    )


@_LEN
def _len(
    context: int,
    output: _Pointer[ctypes.c_size_t],
    known: _Pointer[ctypes.c_uint8],
) -> int:
    if not output or not known:
        return Status.NULL_POINTER
    holder = _dictionary_holder(context)
    if holder is None:
        return Status.CLOSED

    def run() -> None:
        output[0] = _checked_size(len(holder.snapshot()), "dictionary length")
        known[0] = 1

    return _status(holder, run)


@_IS_FINAL
def _is_final(context: int, node: int, output: _Pointer[ctypes.c_uint8]) -> int:
    if not output:
        return Status.NULL_POINTER
    holder = _dictionary_holder(context)
    if holder is None:
        return Status.CLOSED
    return _status(
        holder,
        lambda: output.__setitem__(
            0,
            _checked_bool(holder.snapshot().is_final(node), "dictionary is_final"),
        ),
    )


@_VALUE
def _value(context: int, node: int, output: _Pointer[_OptionalU64]) -> int:
    if not output:
        return Status.NULL_POINTER
    holder = _dictionary_holder(context)
    if holder is None:
        return Status.CLOSED

    def run() -> None:
        value = holder.snapshot().value(node)
        checked = (
            0 if value is None else _checked_u64(value, "dictionary optional value")
        )
        output[0] = _OptionalU64(checked, value is not None, (ctypes.c_uint8 * 7)())

    return _status(holder, run)


def _label(value: str | int) -> int:
    if isinstance(value, str):
        if len(value) != 1:
            raise ValueError("Unicode edge labels must contain one scalar")
        value = ord(value)
    if isinstance(value, bool) or not isinstance(value, int):
        raise TypeError("Unicode edge labels must be one-character strings or integers")
    if not 0 <= value <= 0x10FFFF or 0xD800 <= value <= 0xDFFF:
        raise ValueError("edge label is not a Unicode scalar")
    return value


@_TRANSITION
def _transition(
    context: int,
    node: int,
    label: int,
    child: _Pointer[ctypes.c_uint64],
    found: _Pointer[ctypes.c_uint8],
) -> int:
    if not child or not found:
        return Status.NULL_POINTER
    holder = _dictionary_holder(context)
    if holder is None:
        return Status.CLOSED
    try:
        requested = _label(label)
    except (TypeError, ValueError):
        return Status.INVALID_ARGUMENT

    def run() -> None:
        for edge_label, edge_child in holder.snapshot().edges(node):
            if _label(edge_label) == requested:
                child[0], found[0] = (
                    _checked_u64(edge_child, "dictionary child node"),
                    1,
                )
                return
        child[0], found[0] = 0, 0

    return _status(holder, run)


@_EDGES
def _edges(
    context: int,
    node: int,
    start: int,
    output: _Pointer[_Edge],
    capacity: int,
    written: _Pointer[ctypes.c_size_t],
    total: _Pointer[ctypes.c_size_t],
) -> int:
    if not written or not total or (capacity and not output):
        return Status.NULL_POINTER
    holder = _dictionary_holder(context)
    if holder is None:
        return Status.CLOSED

    def run() -> None:
        values = holder.snapshot().edges(node)
        if not isinstance(values, Sequence):
            raise TypeError("dictionary edges must return a sequence")
        total_count = _checked_size(len(values), "dictionary edge count")
        page = values[start : start + capacity]
        encoded = [
            _Edge(_label(label), _checked_u64(child, "dictionary child node"))
            for label, child in page
        ]
        for index, edge in enumerate(encoded):
            output[index] = edge
        total[0] = total_count
        written[0] = len(encoded)

    return _status(holder, run)


_RESOURCE_VTABLE = _ResourceVTable(
    ctypes.sizeof(_ResourceVTable), ABI_VERSION, 0, _retain, _release, _query_interface
)


def _make_dictionary_vtable(immutable: bool, parallel: bool) -> _DictionaryVTable:
    flags = DictionaryFlag.NONE
    if parallel:
        flags |= DictionaryFlag.PARALLEL_REENTRANT
    if immutable:
        flags |= DictionaryFlag.IMMUTABLE
    return _DictionaryVTable(
        ctypes.sizeof(_DictionaryVTable),
        DICTIONARY_INTERFACE_VERSION,
        UnitDomain.UNICODE_SCALAR,
        ValueDomain.OPTIONAL_U64,
        int(flags),
        _snapshot,
        _root,
        _len,
        _is_final,
        _value,
        _transition,
        _edges,
    )


_DICTIONARY_VTABLES = {
    (immutable, parallel): _make_dictionary_vtable(immutable, parallel)
    for immutable in (False, True)
    for parallel in (False, True)
}


class _OwnedProviderResource:
    """Shared deterministic lifecycle for Python-hosted ABI resources."""

    _holder: _ProviderHolder
    _key: int
    _resource: VtResource

    def _open(self, holder: _ProviderHolder) -> None:
        self._holder = holder
        self._key = _register(holder)
        self._resource = VtResource(self._key, ctypes.addressof(_RESOURCE_VTABLE))

    @property
    def native_resource(self) -> VtResource:
        """Borrow this facade's two-word resource for one synchronous call."""
        if not self._key:
            raise RuntimeError("provider resource is closed")
        return self._resource

    @property
    def last_callback_error(self) -> BaseException | None:
        """Return the last exception translated to a provider status."""
        return self._holder.errors[0]

    def close(self) -> None:
        """Release this facade's retain exactly once."""
        key = getattr(self, "_key", 0)
        if key:
            _release(key)
            self._key = 0
            self._resource = VtResource()

    def __del__(self) -> None:
        """Contain leaked facades without replacing deterministic ``close``."""
        try:
            self.close()
        except BaseException:  # noqa: BLE001 - finalizers must never escape
            return


class UnicodeDictionaryResource(_OwnedProviderResource):
    """Adapt a host-defined Unicode snapshot provider to dictionary ABI v1.

    Callbacks are serialized by consumers unless ``parallel_reentrant`` is true.
    ``capture`` must return an immutable, O(1)-captured revision.
    """

    def __init__(
        self,
        capture: Callable[[], UnicodeDictionarySnapshot],
        *,
        parallel_reentrant: bool = False,
    ) -> None:
        if not callable(capture):
            raise TypeError("dictionary capture must be callable")
        if not isinstance(parallel_reentrant, bool):
            raise TypeError("parallel_reentrant must be bool")
        self._open(_Holder(capture, immutable=False, parallel=parallel_reentrant))

    def __enter__(self) -> UnicodeDictionaryResource:  # noqa: PYI034 - Python 3.10
        return self

    def __exit__(self, *_args: object) -> None:
        self.close()


WFST_INTERFACE_VERSION = 1
WFST_INTERFACE_ID = b"vt.scalar-wfst.1"


@dataclass(frozen=True, slots=True)
class ScalarWfstArc:
    """One immutable scalar-WFST arc.

    ``None`` denotes epsilon. String labels must contain exactly one Unicode
    scalar; integer labels are checked against the resource's unit domain.
    """

    input_label: str | int | None
    output_label: str | int | None
    target_state: int
    weight: float


@dataclass(frozen=True, slots=True)
class ScalarWfstState:
    """Complete immutable metadata and outgoing arcs for one state."""

    final_weight: float | None
    arcs: Sequence[ScalarWfstArc]


class ScalarWfstSnapshot(Protocol):
    """Immutable state graph captured by a custom Python WFST provider."""

    def start(self) -> int:
        """Return the initial state identifier."""
        ...

    def num_states(self) -> int | None:
        """Return the exact state count, or ``None`` when expanded lazily."""
        ...

    def state(self, state: int) -> ScalarWfstState | None:
        """Return a complete state, or ``None`` for an unknown identifier."""
        ...


class _WfstArc(ctypes.Structure):
    _fields_ = [
        ("input_label", ctypes.c_uint64),
        ("output_label", ctypes.c_uint64),
        ("target_state", ctypes.c_uint64),
        ("weight", ctypes.c_double),
        ("has_input", ctypes.c_uint8),
        ("has_output", ctypes.c_uint8),
        ("reserved", ctypes.c_uint8 * 6),
    ]


_WFST_START = ctypes.CFUNCTYPE(
    ctypes.c_uint32, ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint64)
)
_WFST_NUM_STATES = ctypes.CFUNCTYPE(
    ctypes.c_uint32,
    ctypes.c_void_p,
    ctypes.POINTER(ctypes.c_size_t),
    ctypes.POINTER(ctypes.c_uint8),
)
_WFST_STATE_INFO = ctypes.CFUNCTYPE(
    ctypes.c_uint32,
    ctypes.c_void_p,
    ctypes.c_uint64,
    ctypes.POINTER(ctypes.c_uint8),
    ctypes.POINTER(ctypes.c_uint8),
    ctypes.POINTER(ctypes.c_double),
)
_WFST_STATE_ARCS = ctypes.CFUNCTYPE(
    ctypes.c_uint32,
    ctypes.c_void_p,
    ctypes.c_uint64,
    ctypes.c_size_t,
    ctypes.POINTER(_WfstArc),
    ctypes.c_size_t,
    ctypes.POINTER(ctypes.c_size_t),
    ctypes.POINTER(ctypes.c_size_t),
)


class _WfstVTable(ctypes.Structure):
    _fields_ = [
        ("struct_size", ctypes.c_size_t),
        ("interface_version", ctypes.c_uint32),
        ("unit_domain", ctypes.c_uint32),
        ("weight_domain", ctypes.c_uint32),
        ("reserved", ctypes.c_uint32),
        ("flags", ctypes.c_uint64),
        ("snapshot", _SNAPSHOT),
        ("start", _WFST_START),
        ("num_states", _WFST_NUM_STATES),
        ("state_info", _WFST_STATE_INFO),
        ("state_arcs", _WFST_STATE_ARCS),
    ]


class _WfstHolder(_ProviderHolder):
    __slots__ = (
        "_states",
        "acyclic",
        "immutable",
        "lazy",
        "source",
        "unit_domain",
        "weight_domain",
    )

    def __init__(
        self,
        source: Callable[[], ScalarWfstSnapshot] | ScalarWfstSnapshot,
        *,
        immutable: bool,
        unit_domain: UnitDomain,
        weight_domain: WeightDomain,
        lazy: bool,
        acyclic: bool,
        parallel: bool,
        errors: list[BaseException | None] | None = None,
    ) -> None:
        super().__init__(parallel=parallel, errors=errors)
        self.source = source
        self.immutable = immutable
        self.unit_domain = unit_domain
        self.weight_domain = weight_domain
        self.lazy = lazy
        self.acyclic = acyclic
        self._states: dict[int, ScalarWfstState | None] = {}

    def snapshot(self) -> ScalarWfstSnapshot:
        if self.immutable:
            return cast(ScalarWfstSnapshot, self.source)
        capture = cast(Callable[[], ScalarWfstSnapshot], self.source)
        return capture()

    def state(self, state: int) -> ScalarWfstState | None:
        if state not in self._states:
            # setdefault makes publication atomic on CPython. A free-threaded
            # parallel provider may compute the same immutable state twice,
            # which is safe and avoids serializing unrelated state expansion.
            self._states.setdefault(state, self.snapshot().state(state))
        return self._states[state]

    def interface_vtable(
        self, interface_id: bytes, minimum_version: int
    ) -> ctypes.Structure | None:
        if interface_id != WFST_INTERFACE_ID or minimum_version > 1:
            return None
        return _wfst_vtable(self)


def _wfst_holder(context: int) -> _WfstHolder | None:
    holder = _registry.get(context)
    return holder if isinstance(holder, _WfstHolder) else None


def _checked_state_id(value: int) -> int:
    return _checked_u64(value, "WFST state identifier")


def _checked_unit(value: str | int, domain: UnitDomain) -> int:
    if isinstance(value, str):
        if domain is not UnitDomain.UNICODE_SCALAR or len(value) != 1:
            raise ValueError("string WFST labels require one Unicode scalar")
        value = ord(value)
    if not isinstance(value, int):
        raise TypeError("WFST labels must be integers, strings, or None")
    if domain is UnitDomain.BYTE:
        valid = 0 <= value <= 0xFF
    elif domain is UnitDomain.UNICODE_SCALAR:
        valid = 0 <= value <= 0x10FFFF and not 0xD800 <= value <= 0xDFFF
    else:
        valid = 0 <= value < 2**64
    if not valid:
        raise ValueError(f"WFST label is outside the {domain.name} domain")
    return value


def _checked_weight(value: float) -> float:
    result = float(value)
    if math.isnan(result):
        raise ValueError("WFST weights cannot be NaN")
    return result


@_SNAPSHOT
def _wfst_snapshot(context: int, output: _Pointer[VtResource]) -> int:
    if not output:
        return Status.NULL_POINTER
    holder = _wfst_holder(context)
    if holder is None:
        return Status.CLOSED

    def run() -> None:
        child = _WfstHolder(
            holder.snapshot(),
            immutable=True,
            unit_domain=holder.unit_domain,
            weight_domain=holder.weight_domain,
            lazy=holder.lazy,
            acyclic=holder.acyclic,
            parallel=holder.parallel,
            errors=holder.errors,
        )
        key = _register(child)
        output[0] = VtResource(key, ctypes.addressof(_RESOURCE_VTABLE))

    return _status(holder, run)


@_WFST_START
def _wfst_start(context: int, output: _Pointer[ctypes.c_uint64]) -> int:
    if not output:
        return Status.NULL_POINTER
    holder = _wfst_holder(context)
    if holder is None:
        return Status.CLOSED
    return _status(
        holder,
        lambda: output.__setitem__(0, _checked_state_id(holder.snapshot().start())),
    )


@_WFST_NUM_STATES
def _wfst_num_states(
    context: int,
    output: _Pointer[ctypes.c_size_t],
    known: _Pointer[ctypes.c_uint8],
) -> int:
    if not output or not known:
        return Status.NULL_POINTER
    holder = _wfst_holder(context)
    if holder is None:
        return Status.CLOSED

    def run() -> None:
        count = holder.snapshot().num_states()
        if count is None:
            output[0], known[0] = 0, 0
        else:
            output[0], known[0] = _checked_size(count, "WFST state count"), 1

    return _status(holder, run)


@_WFST_STATE_INFO
def _wfst_state_info(
    context: int,
    state: int,
    valid: _Pointer[ctypes.c_uint8],
    final: _Pointer[ctypes.c_uint8],
    final_weight: _Pointer[ctypes.c_double],
) -> int:
    if not valid or not final or not final_weight:
        return Status.NULL_POINTER
    holder = _wfst_holder(context)
    if holder is None:
        return Status.CLOSED

    def run() -> None:
        description = holder.state(state)
        if description is None:
            valid[0], final[0], final_weight[0] = 0, 0, 0.0
            return
        declared_weight = description.final_weight
        is_final = declared_weight is not None
        weight = (
            _checked_weight(declared_weight) if declared_weight is not None else 0.0
        )
        valid[0] = 1
        final[0] = is_final
        final_weight[0] = weight

    return _status(holder, run)


@_WFST_STATE_ARCS
def _wfst_state_arcs(
    context: int,
    state: int,
    start: int,
    output: _Pointer[_WfstArc],
    capacity: int,
    written: _Pointer[ctypes.c_size_t],
    total: _Pointer[ctypes.c_size_t],
) -> int:
    if not written or not total or (capacity and not output):
        return Status.NULL_POINTER
    holder = _wfst_holder(context)
    if holder is None:
        return Status.CLOSED

    def run() -> None:
        description = holder.state(state)
        if description is None:
            raise ValueError("WFST state identifier is unknown")
        arcs = description.arcs
        if not isinstance(arcs, Sequence):
            raise TypeError("WFST state arcs must be a sequence")
        total_count = _checked_size(len(arcs), "WFST arc count")
        page = arcs[start : start + capacity]
        encoded: list[_WfstArc] = []
        for arc in page:
            input_label = (
                0
                if arc.input_label is None
                else _checked_unit(arc.input_label, holder.unit_domain)
            )
            output_label = (
                0
                if arc.output_label is None
                else _checked_unit(arc.output_label, holder.unit_domain)
            )
            encoded.append(
                _WfstArc(
                    input_label,
                    output_label,
                    _checked_state_id(arc.target_state),
                    _checked_weight(arc.weight),
                    arc.input_label is not None,
                    arc.output_label is not None,
                    (ctypes.c_uint8 * 6)(),
                )
            )
        for index, arc in enumerate(encoded):
            output[index] = arc
        total[0] = total_count
        written[0] = len(encoded)

    return _status(holder, run)


def _make_wfst_vtable(
    unit_domain: UnitDomain,
    weight_domain: WeightDomain,
    immutable: bool,
    lazy: bool,
    acyclic: bool,
    parallel: bool,
) -> _WfstVTable:
    flags = WfstFlag.NONE
    if parallel:
        flags |= WfstFlag.PARALLEL_REENTRANT
    if immutable:
        flags |= WfstFlag.IMMUTABLE
    if lazy:
        flags |= WfstFlag.LAZY
    if acyclic:
        flags |= WfstFlag.ACYCLIC
    return _WfstVTable(
        ctypes.sizeof(_WfstVTable),
        WFST_INTERFACE_VERSION,
        unit_domain,
        weight_domain,
        0,
        int(flags),
        _wfst_snapshot,
        _wfst_start,
        _wfst_num_states,
        _wfst_state_info,
        _wfst_state_arcs,
    )


_WFST_VTABLES = {
    (unit_domain, weight_domain, immutable, lazy, acyclic, parallel): _make_wfst_vtable(
        unit_domain, weight_domain, immutable, lazy, acyclic, parallel
    )
    for unit_domain in UnitDomain
    for weight_domain in WeightDomain
    for immutable in (False, True)
    for lazy in (False, True)
    for acyclic in (False, True)
    for parallel in (False, True)
}


def _wfst_vtable(holder: _WfstHolder) -> _WfstVTable:
    return _WFST_VTABLES[
        (
            holder.unit_domain,
            holder.weight_domain,
            holder.immutable,
            holder.lazy,
            holder.acyclic,
            holder.parallel,
        )
    ]


class ScalarWfstResource(_OwnedProviderResource):
    """Adapt a Python state provider to scalar-WFST resource ABI v1.

    The native consumer captures a revision before traversal. State objects are
    cached by identifier within that immutable revision so metadata and arc
    paging do not repeat provider work. The cache does not impose a resource-
    wide lock; a provider advertising ``parallel_reentrant`` must make its own
    state implementation safe for overlapping calls.
    """

    def __init__(
        self,
        capture: Callable[[], ScalarWfstSnapshot],
        *,
        unit_domain: UnitDomain = UnitDomain.UNICODE_SCALAR,
        weight_domain: WeightDomain = WeightDomain.TROPICAL_F64,
        lazy: bool = True,
        acyclic: bool = False,
        parallel_reentrant: bool = False,
    ) -> None:
        if not callable(capture):
            raise TypeError("WFST capture must be callable")
        flags = {
            "lazy": lazy,
            "acyclic": acyclic,
            "parallel_reentrant": parallel_reentrant,
        }
        invalid = [name for name, value in flags.items() if not isinstance(value, bool)]
        if invalid:
            raise TypeError(f"WFST flags must be bool: {', '.join(invalid)}")
        self._open(
            _WfstHolder(
                capture,
                immutable=False,
                unit_domain=UnitDomain(unit_domain),
                weight_domain=WeightDomain(weight_domain),
                lazy=lazy,
                acyclic=acyclic,
                parallel=parallel_reentrant,
            )
        )

    def __enter__(self) -> ScalarWfstResource:  # noqa: PYI034 - Python 3.10
        return self

    def __exit__(self, *_args: object) -> None:
        self.close()


@dataclass(frozen=True, slots=True)
class ScalarWfstStateInfo:
    """Finality metadata for one valid scalar-WFST state."""

    final: bool
    final_weight: float


def _resource_words(resource: NativeResource | VtResource) -> VtResource:
    raw = resource if isinstance(resource, VtResource) else resource.native_resource
    return VtResource(raw.context, raw.vtable)


def _consumer_status(raw: int, operation: str) -> None:
    if raw == Status.OK:
        return
    try:
        status: Status | int = Status(raw)
        label = status.name
    except ValueError:
        status = int(raw)
        label = f"unknown status {raw}"
    raise InteropError(status, operation, f"{operation} failed with {label}")


class ScalarWfst:
    """Owned, snapshot-capable view of a scalar-WFST resource.

    Normal construction borrows a live resource and obtains an independent
    retain. :meth:`adopt` consumes a raw ``VtResource`` that already owns one
    retain, which is the zero-copy handoff used by project libraries.
    """

    __slots__ = ("_base", "_resource", "_serial_lock", "_table")

    def __init__(
        self,
        resource: NativeResource | VtResource,
        *,
        _take_ownership: bool = False,
    ) -> None:
        if _take_ownership and not isinstance(resource, VtResource):
            raise TypeError("ownership transfer requires a raw VtResource")
        raw = _resource_words(resource)
        if not raw.context or not raw.vtable:
            raise InteropError(Status.CLOSED, "wfst_open", "resource is closed")
        base_pointer = ctypes.cast(raw.vtable, ctypes.POINTER(_ResourceVTable))
        base = base_pointer.contents
        if base.struct_size < ctypes.sizeof(_ResourceVTable):
            raise InteropError(
                Status.UNSUPPORTED,
                "wfst_open",
                "resource base vtable is truncated",
            )
        if base.abi_version != ABI_VERSION:
            raise InteropError(
                Status.UNSUPPORTED,
                "wfst_open",
                f"resource ABI {base.abi_version} is not supported",
            )
        if not all(
            bool(callback)
            for callback in (base.retain, base.release, base.query_interface)
        ):
            raise InteropError(
                Status.UNSUPPORTED,
                "wfst_open",
                "resource base vtable has a null mandatory callback",
            )
        if not _take_ownership:
            base.retain(raw.context)
        owned = VtResource(raw.context, raw.vtable)
        try:
            identifier = _InterfaceId(
                (ctypes.c_uint8 * 16).from_buffer_copy(WFST_INTERFACE_ID)
            )
            output = ctypes.c_void_p()
            _consumer_status(
                base.query_interface(
                    owned.context,
                    ctypes.byref(identifier),
                    WFST_INTERFACE_VERSION,
                    ctypes.byref(output),
                ),
                "wfst_query_interface",
            )
            if not output.value:
                raise InteropError(
                    Status.UNSUPPORTED,
                    "wfst_query_interface",
                    "resource did not return the scalar-WFST interface",
                )
            table_pointer = ctypes.cast(output, ctypes.POINTER(_WfstVTable))
            table = table_pointer.contents
            if table.struct_size < ctypes.sizeof(_WfstVTable):
                raise InteropError(
                    Status.UNSUPPORTED,
                    "wfst_open",
                    "scalar-WFST vtable is truncated",
                )
            if table.interface_version < WFST_INTERFACE_VERSION or table.reserved:
                raise InteropError(
                    Status.UNSUPPORTED,
                    "wfst_open",
                    "scalar-WFST interface version or reserved field is invalid",
                )
            try:
                UnitDomain(table.unit_domain)
                WeightDomain(table.weight_domain)
            except ValueError as error:
                raise InteropError(
                    Status.UNSUPPORTED,
                    "wfst_open",
                    "scalar-WFST domain discriminant is unknown",
                ) from error
            mandatory = (
                table.snapshot,
                table.start,
                table.num_states,
                table.state_info,
                table.state_arcs,
            )
            if not all(bool(callback) for callback in mandatory):
                raise InteropError(
                    Status.UNSUPPORTED,
                    "wfst_open",
                    "scalar-WFST vtable has a null mandatory callback",
                )
        except BaseException:
            base.release(owned.context)
            raise
        self._resource = owned
        self._base = base
        self._table = table_pointer
        self._serial_lock = (
            None if table.flags & WfstFlag.PARALLEL_REENTRANT else threading.RLock()
        )

    @classmethod
    def adopt(  # noqa: PYI019 - typing.Self requires Python 3.11
        cls: type[_ScalarWfstT], resource: VtResource
    ) -> _ScalarWfstT:
        """Consume one already-owned raw resource without another retain."""
        return cls(resource, _take_ownership=True)

    @property
    def native_resource(self) -> VtResource:
        """Borrow the retained resource for one synchronous native call."""
        self._ensure_open()
        return VtResource(self._resource.context, self._resource.vtable)

    def _ensure_open(self) -> None:
        if not self._resource.context:
            raise InteropError(Status.CLOSED, "wfst", "scalar WFST is closed")

    def _guard(self):
        lock = self._serial_lock
        return nullcontext() if lock is None else lock

    @property
    def unit_domain(self) -> UnitDomain:
        """Return the graph's exact edge-label domain."""
        self._ensure_open()
        return UnitDomain(self._table.contents.unit_domain)

    @property
    def weight_domain(self) -> WeightDomain:
        """Return the graph's exact scalar-weight representation."""
        self._ensure_open()
        return WeightDomain(self._table.contents.weight_domain)

    @property
    def flags(self) -> WfstFlag:
        """Return validated immutability, laziness, and threading flags."""
        self._ensure_open()
        return WfstFlag(self._table.contents.flags)

    def snapshot(  # noqa: PYI019 - typing.Self requires Python 3.11
        self: _ScalarWfstT,
    ) -> _ScalarWfstT:
        """Capture and own one immutable revision at the provider boundary."""
        self._ensure_open()
        output = VtResource()
        with self._guard():
            _consumer_status(
                self._table.contents.snapshot(
                    self._resource.context, ctypes.byref(output)
                ),
                "wfst_snapshot",
            )
        if not output.context or not output.vtable:
            raise InteropError(
                Status.PROVIDER_ERROR,
                "wfst_snapshot",
                "provider returned a null successful snapshot",
            )
        return type(self).adopt(output)

    @property
    def start(self) -> int:
        """Return the start-state identifier."""
        self._ensure_open()
        output = ctypes.c_uint64()
        with self._guard():
            _consumer_status(
                self._table.contents.start(
                    self._resource.context, ctypes.byref(output)
                ),
                "wfst_start",
            )
        return output.value

    def __len__(self) -> int:
        """Return the exact state count, raising for a lazy unknown-size graph."""
        count = self.state_count
        if count is None:
            raise TypeError("lazy scalar WFST does not report an exact state count")
        return count

    @property
    def state_count(self) -> int | None:
        """Return the exact state count, or ``None`` for a lazy graph."""
        self._ensure_open()
        output = ctypes.c_size_t()
        known = ctypes.c_uint8()
        with self._guard():
            _consumer_status(
                self._table.contents.num_states(
                    self._resource.context,
                    ctypes.byref(output),
                    ctypes.byref(known),
                ),
                "wfst_num_states",
            )
        if known.value not in (0, 1):
            raise InteropError(
                Status.PROVIDER_ERROR,
                "wfst_num_states",
                "provider returned a non-boolean known flag",
            )
        return output.value if known.value else None

    def state_info(self, state: int) -> ScalarWfstStateInfo | None:
        """Return finality metadata, or ``None`` for an unknown state ID."""
        state = _checked_state_id(state)
        self._ensure_open()
        valid = ctypes.c_uint8()
        final = ctypes.c_uint8()
        weight = ctypes.c_double()
        with self._guard():
            _consumer_status(
                self._table.contents.state_info(
                    self._resource.context,
                    state,
                    ctypes.byref(valid),
                    ctypes.byref(final),
                    ctypes.byref(weight),
                ),
                "wfst_state_info",
            )
        if valid.value not in (0, 1) or final.value not in (0, 1):
            raise InteropError(
                Status.PROVIDER_ERROR,
                "wfst_state_info",
                "provider returned a non-boolean state flag",
            )
        if not valid.value:
            return None
        if math.isnan(weight.value):
            raise InteropError(
                Status.PROVIDER_ERROR,
                "wfst_state_info",
                "provider returned a NaN final weight",
            )
        return ScalarWfstStateInfo(bool(final.value), weight.value)

    def arcs(self, state: int, *, batch_size: int = 256) -> tuple[ScalarWfstArc, ...]:
        """Copy all outgoing arcs using bounded, progress-checked pages."""
        state = _checked_state_id(state)
        batch_size = _checked_size(batch_size, "WFST arc batch size")
        if not batch_size:
            raise ValueError("WFST arc batch size must be positive")
        self._ensure_open()
        result: list[ScalarWfstArc] = []
        offset = 0
        expected_total: int | None = None
        while expected_total is None or offset < expected_total:
            page = (_WfstArc * batch_size)()
            written = ctypes.c_size_t()
            total = ctypes.c_size_t()
            with self._guard():
                _consumer_status(
                    self._table.contents.state_arcs(
                        self._resource.context,
                        state,
                        offset,
                        page,
                        batch_size,
                        ctypes.byref(written),
                        ctypes.byref(total),
                    ),
                    "wfst_state_arcs",
                )
            if written.value > batch_size or offset > total.value:
                raise InteropError(
                    Status.PROVIDER_ERROR,
                    "wfst_state_arcs",
                    "provider returned inconsistent page bounds",
                )
            if expected_total is not None and total.value != expected_total:
                raise InteropError(
                    Status.PROVIDER_ERROR,
                    "wfst_state_arcs",
                    "provider changed the arc count during one traversal",
                )
            expected_total = total.value
            if not written.value and offset < expected_total:
                raise InteropError(
                    Status.PROVIDER_ERROR,
                    "wfst_state_arcs",
                    "provider made no progress before the final page",
                )
            for raw in page[: written.value]:
                if raw.has_input not in (0, 1) or raw.has_output not in (0, 1):
                    raise InteropError(
                        Status.PROVIDER_ERROR,
                        "wfst_state_arcs",
                        "provider returned a non-boolean epsilon flag",
                    )
                if math.isnan(raw.weight):
                    raise InteropError(
                        Status.PROVIDER_ERROR,
                        "wfst_state_arcs",
                        "provider returned a NaN arc weight",
                    )
                result.append(
                    ScalarWfstArc(
                        raw.input_label if raw.has_input else None,
                        raw.output_label if raw.has_output else None,
                        raw.target_state,
                        raw.weight,
                    )
                )
            offset += written.value
        return tuple(result)

    def state(self, state: int, *, batch_size: int = 256) -> ScalarWfstState | None:
        """Materialize one complete immutable state description."""
        info = self.state_info(state)
        if info is None:
            return None
        return ScalarWfstState(
            info.final_weight if info.final else None,
            self.arcs(state, batch_size=batch_size),
        )

    def close(self) -> None:
        """Release this view's independent retain exactly once."""
        context = self._resource.context
        if context:
            self._base.release(context)
            self._resource = VtResource()

    def __enter__(  # noqa: PYI019 - typing.Self requires Python 3.11
        self: _ScalarWfstT,
    ) -> _ScalarWfstT:
        return self

    def __exit__(self, *_args: object) -> None:
        self.close()

    def __del__(self) -> None:
        try:
            self.close()
        except BaseException:  # noqa: BLE001 - finalizers must never escape
            return


LATTICE_INTERFACE_VERSION = 1
LATTICE_INTERFACE_ID = b"vt.lattice.val.1"
RECOMMENDED_LATTICE_BATCH = 256
_MAX_PROVIDER_BYTES = 16 * 1024 * 1024
_MAX_BUFFER_ATTEMPTS = 3


@dataclass(frozen=True, slots=True)
class DomainId:
    """Exact 16-byte semantic domain identifier."""

    bytes: bytes

    def __post_init__(self) -> None:
        value = bytes(self.bytes)
        if len(value) != 16:
            raise ValueError("domain identifiers must contain exactly 16 bytes")
        object.__setattr__(self, "bytes", value)

    @classmethod
    def ascii(cls, value: str) -> DomainId:
        """Create an identifier from exactly 16 ASCII characters."""
        return cls(value.encode("ascii"))


@dataclass(frozen=True, slots=True)
class LatticeOptions:
    """Semantic identity and concurrency promises for one lattice value."""

    domain_id: DomainId
    thread_bound: bool = False
    parallel_reentrant: bool = False

    def __post_init__(self) -> None:
        if not isinstance(self.domain_id, DomainId):
            raise TypeError("lattice domain_id must be a DomainId")
        if not isinstance(self.thread_bound, bool) or not isinstance(
            self.parallel_reentrant, bool
        ):
            raise TypeError("lattice threading options must be bool")
        if self.thread_bound and self.parallel_reentrant:
            raise ValueError("a lattice provider cannot be thread-bound and parallel")


class LatticeProvider(Protocol):
    """One immutable Python-defined lattice value."""

    def join(self, other: LatticeOperand) -> LatticeProvider:
        """Return this value joined with a compatible borrowed operand."""
        ...

    def meet(self, other: LatticeOperand) -> LatticeProvider:
        """Return this value met with a compatible borrowed operand."""
        ...

    def equal(self, other: LatticeOperand) -> bool:
        """Return semantic equality with a compatible borrowed operand."""
        ...

    def diagnostic(self) -> str:
        """Return a concise human-readable diagnostic representation."""
        ...


_LATTICE_BINARY = ctypes.CFUNCTYPE(
    ctypes.c_uint32,
    ctypes.c_void_p,
    ctypes.POINTER(VtResource),
    ctypes.POINTER(VtResource),
)
_LATTICE_EQUAL = ctypes.CFUNCTYPE(
    ctypes.c_uint32,
    ctypes.c_void_p,
    ctypes.POINTER(VtResource),
    ctypes.POINTER(ctypes.c_uint8),
)
_LATTICE_BYTES = ctypes.CFUNCTYPE(
    ctypes.c_uint32,
    ctypes.c_void_p,
    ctypes.POINTER(ctypes.c_uint8),
    ctypes.c_size_t,
    ctypes.POINTER(ctypes.c_size_t),
    ctypes.POINTER(ctypes.c_size_t),
)
_LATTICE_MANY = ctypes.CFUNCTYPE(
    ctypes.c_uint32,
    ctypes.c_void_p,
    ctypes.POINTER(VtResource),
    ctypes.c_size_t,
    ctypes.POINTER(VtResource),
)


class _LatticeVTable(ctypes.Structure):
    _fields_ = [
        ("struct_size", ctypes.c_size_t),
        ("interface_version", ctypes.c_uint32),
        ("reserved", ctypes.c_uint32),
        ("flags", ctypes.c_uint64),
        ("domain_id", _InterfaceId),
        ("join", _LATTICE_BINARY),
        ("meet", _LATTICE_BINARY),
        ("equal", _LATTICE_EQUAL),
        ("stable_bytes", _LATTICE_BYTES),
        ("diagnostic", _LATTICE_BYTES),
        ("join_many", _LATTICE_MANY),
        ("meet_many", _LATTICE_MANY),
    ]


def _native_id(identity: bytes) -> _InterfaceId:
    return _InterfaceId((ctypes.c_uint8 * 16).from_buffer_copy(identity))


def _portable_status(raw: int, operation: str) -> None:
    if raw == Status.OK:
        return
    try:
        status = Status(raw)
    except ValueError as error:
        raise RuntimeError(f"{operation} returned unknown status {raw}") from error
    if status in {
        Status.INVALID_ARGUMENT,
        Status.UNSUPPORTED,
        Status.IO_ERROR,
        Status.CLOSED,
        Status.LIMIT_EXCEEDED,
        Status.PROVIDER_ERROR,
    }:
        raise ProviderStatusError(status, f"{operation} failed with {status.name}")
    raise RuntimeError(f"{operation} returned invalid status {status.name}")


def _write_bytes(
    data: bytes,
    output: _Pointer[ctypes.c_uint8],
    capacity: int,
    written: _Pointer[ctypes.c_size_t],
    required: _Pointer[ctypes.c_size_t],
) -> int:
    if not written or not required or (capacity and not output):
        return Status.NULL_POINTER
    count = min(capacity, len(data))
    if count:
        ctypes.memmove(ctypes.addressof(output.contents), data, count)
    written[0] = count
    required[0] = len(data)
    return Status.OK


def _provider_bytes(value: object, operation: str) -> bytes:
    """Materialize and bound one provider-owned byte result."""
    if not isinstance(value, (bytes, bytearray, memoryview)):
        raise TypeError(f"{operation} must return a bytes-like object")
    size = len(value) if not isinstance(value, memoryview) else value.nbytes
    if size > _MAX_PROVIDER_BYTES:
        raise ProviderStatusError(
            Status.LIMIT_EXCEEDED, f"{operation} exceeds the provider byte limit"
        )
    return bytes(value)


def _provider_text(value: object, operation: str) -> bytes:
    """Validate, encode, and bound one provider-owned UTF-8 diagnostic."""
    if not isinstance(value, str):
        raise TypeError(f"{operation} must return str")
    if len(value) > _MAX_PROVIDER_BYTES:
        raise ProviderStatusError(
            Status.LIMIT_EXCEEDED, f"{operation} exceeds the provider byte limit"
        )
    return _provider_bytes(value.encode("utf-8"), operation)


class LatticeOperand:
    """Borrowed compatible lattice value passed to one provider callback.

    The operand is invalidated as soon as that callback returns. A provider may
    read canonical bytes from a foreign implementation or recover the original
    Python object when both values were created by this runtime.
    """

    __slots__ = ("_active", "_resource", "_table")

    def __init__(self, resource: VtResource, table: _LatticeVTable) -> None:
        self._resource = resource
        self._table = table
        self._active = True

    def _check(self) -> None:
        if not self._active:
            raise RuntimeError("lattice operand is no longer borrowed")

    def _invalidate(self) -> None:
        self._active = False

    @property
    def has_stable_bytes(self) -> bool:
        """Whether the operand advertises canonical stable bytes."""
        self._check()
        return bool(
            self._table.flags & LatticeFlag.STABLE_BYTES and self._table.stable_bytes
        )

    def python_value(self) -> LatticeProvider | None:
        """Return the local Python value, or ``None`` for a foreign provider."""
        self._check()
        if int(self._resource.vtable or 0) != ctypes.addressof(_RESOURCE_VTABLE):
            return None
        holder = _registry.get(int(self._resource.context or 0))
        return holder.provider if isinstance(holder, _LatticeHolder) else None

    def stable_bytes(self) -> bytes:
        """Read the bounded canonical encoding from the operand's provider."""
        self._check()
        if not self.has_stable_bytes:
            raise ProviderStatusError(Status.UNSUPPORTED, "stable bytes unavailable")
        required = ctypes.c_size_t()
        written = ctypes.c_size_t()
        _portable_status(
            self._table.stable_bytes(
                self._resource.context,
                None,
                0,
                ctypes.byref(written),
                ctypes.byref(required),
            ),
            "lattice stable-byte size query",
        )
        if written.value:
            raise RuntimeError("lattice size query wrote a nonzero byte count")
        for _attempt in range(_MAX_BUFFER_ATTEMPTS):
            if required.value > _MAX_PROVIDER_BYTES:
                raise ProviderStatusError(
                    Status.LIMIT_EXCEEDED, "lattice stable bytes exceed limit"
                )
            storage = (ctypes.c_uint8 * max(required.value, 1))()
            next_written = ctypes.c_size_t()
            next_required = ctypes.c_size_t()
            _portable_status(
                self._table.stable_bytes(
                    self._resource.context,
                    storage,
                    required.value,
                    ctypes.byref(next_written),
                    ctypes.byref(next_required),
                ),
                "lattice stable-byte read",
            )
            if (
                next_written.value > required.value
                or next_written.value > next_required.value
            ):
                raise RuntimeError("lattice provider returned impossible byte counts")
            if next_required.value <= required.value:
                if next_written.value != next_required.value:
                    raise RuntimeError(
                        "lattice provider returned incomplete final bytes"
                    )
                return bytes(storage[: next_written.value])
            required = next_required
        raise RuntimeError("lattice stable-byte size did not stabilize")


class _LatticeHolder(_ProviderHolder):
    __slots__ = ("_table", "options", "provider")

    def __init__(
        self,
        provider: object,
        options: LatticeOptions,
        *,
        errors: list[BaseException | None] | None = None,
    ) -> None:
        required = ("join", "meet", "equal", "diagnostic")
        absent = [
            name for name in required if not callable(getattr(provider, name, None))
        ]
        if absent:
            raise TypeError(f"lattice provider is missing methods: {', '.join(absent)}")
        super().__init__(parallel=options.parallel_reentrant, errors=errors)
        self.provider = cast(LatticeProvider, provider)
        self.options = options
        flags = LatticeFlag.BATCH
        if options.thread_bound:
            flags |= LatticeFlag.THREAD_BOUND
        if options.parallel_reentrant:
            flags |= LatticeFlag.PARALLEL_REENTRANT
        stable = callable(getattr(provider, "stable_bytes", None))
        if stable:
            flags |= LatticeFlag.STABLE_BYTES
        self._table = _LatticeVTable(
            ctypes.sizeof(_LatticeVTable),
            LATTICE_INTERFACE_VERSION,
            0,
            int(flags),
            _native_id(options.domain_id.bytes),
            _lattice_join,
            _lattice_meet,
            _lattice_equal,
            _lattice_stable_bytes if stable else _LATTICE_BYTES(),
            _lattice_diagnostic,
            _lattice_join_many,
            _lattice_meet_many,
        )

    def interface_vtable(
        self, interface_id: bytes, minimum_version: int
    ) -> ctypes.Structure | None:
        if interface_id != LATTICE_INTERFACE_ID or minimum_version > 1:
            return None
        return self._table


def _lattice_holder(context: int) -> _LatticeHolder | None:
    holder = _registry.get(context)
    return holder if isinstance(holder, _LatticeHolder) else None


def _lattice_operand(
    owner: _LatticeHolder, pointer: _Pointer[VtResource]
) -> LatticeOperand:
    if not pointer or not pointer.contents.context or not pointer.contents.vtable:
        raise ProviderStatusError(Status.INVALID_ARGUMENT, "null lattice operand")
    resource = pointer.contents
    vtable = resource.vtable
    if vtable is None:
        raise ProviderStatusError(Status.INVALID_ARGUMENT, "null lattice vtable")
    base = ctypes.cast(vtable, ctypes.POINTER(_ResourceVTable)).contents
    if (
        base.struct_size < ctypes.sizeof(_ResourceVTable)
        or base.abi_version != ABI_VERSION
    ):
        raise ProviderStatusError(Status.INVALID_ARGUMENT, "invalid resource vtable")
    output = ctypes.c_void_p()
    identifier = _native_id(LATTICE_INTERFACE_ID)
    _portable_status(
        base.query_interface(
            resource.context,
            ctypes.byref(identifier),
            LATTICE_INTERFACE_VERSION,
            ctypes.byref(output),
        ),
        "lattice interface query",
    )
    if not output.value:
        raise RuntimeError("lattice query returned a null vtable")
    table = ctypes.cast(output, ctypes.POINTER(_LatticeVTable)).contents
    if (
        table.struct_size < ctypes.sizeof(_LatticeVTable)
        or table.interface_version < LATTICE_INTERFACE_VERSION
        or table.reserved != 0
        or table.flags
        & ~int(
            LatticeFlag.THREAD_BOUND
            | LatticeFlag.PARALLEL_REENTRANT
            | LatticeFlag.STABLE_BYTES
            | LatticeFlag.BATCH
        )
        or bool(table.flags & LatticeFlag.THREAD_BOUND)
        and bool(table.flags & LatticeFlag.PARALLEL_REENTRANT)
    ):
        raise ProviderStatusError(Status.INVALID_ARGUMENT, "invalid lattice vtable")
    if bytes(table.domain_id.bytes) != owner.options.domain_id.bytes:
        raise ProviderStatusError(Status.INVALID_ARGUMENT, "lattice domain mismatch")
    return LatticeOperand(resource, table)


def _export_lattice_result(
    owner: _LatticeHolder,
    provider: object,
    output: _Pointer[VtResource],
) -> None:
    if provider is None:
        raise RuntimeError("lattice operation returned None")
    child = _LatticeHolder(provider, owner.options, errors=owner.errors)
    key = _register(child)
    output[0] = VtResource(key, ctypes.addressof(_RESOURCE_VTABLE))


def _lattice_binary(
    context: int,
    other: _Pointer[VtResource],
    output: _Pointer[VtResource],
    operation: str,
) -> int:
    if not other or not output:
        return Status.NULL_POINTER
    holder = _lattice_holder(context)
    if holder is None:
        return Status.CLOSED

    def run() -> None:
        operand = _lattice_operand(holder, other)
        try:
            result = getattr(holder.provider, operation)(operand)
        finally:
            operand._invalidate()
        _export_lattice_result(holder, result, output)

    return _status(holder, run)


@_LATTICE_BINARY
def _lattice_join(
    context: int,
    other: _Pointer[VtResource],
    output: _Pointer[VtResource],
) -> int:
    return _lattice_binary(context, other, output, "join")


@_LATTICE_BINARY
def _lattice_meet(
    context: int,
    other: _Pointer[VtResource],
    output: _Pointer[VtResource],
) -> int:
    return _lattice_binary(context, other, output, "meet")


@_LATTICE_EQUAL
def _lattice_equal(
    context: int,
    other: _Pointer[VtResource],
    output: _Pointer[ctypes.c_uint8],
) -> int:
    if not other or not output:
        return Status.NULL_POINTER
    holder = _lattice_holder(context)
    if holder is None:
        return Status.CLOSED

    def run() -> None:
        operand = _lattice_operand(holder, other)
        try:
            result = holder.provider.equal(operand)
            if not isinstance(result, bool):
                raise TypeError("lattice equal must return bool")
            output[0] = result
        finally:
            operand._invalidate()

    return _status(holder, run)


@_LATTICE_BYTES
def _lattice_stable_bytes(
    context: int,
    output: _Pointer[ctypes.c_uint8],
    capacity: int,
    written: _Pointer[ctypes.c_size_t],
    required: _Pointer[ctypes.c_size_t],
) -> int:
    holder = _lattice_holder(context)
    if holder is None:
        return Status.CLOSED
    try:
        stable_bytes = getattr(holder.provider, "stable_bytes", None)
        if not callable(stable_bytes):
            raise ProviderStatusError(
                Status.UNSUPPORTED, "lattice stable bytes unavailable"
            )
        data = _provider_bytes(stable_bytes(), "lattice stable bytes")
        return _write_bytes(data, output, capacity, written, required)
    except BaseException as error:  # noqa: BLE001 - no exception may cross the ABI
        return _failure_status(holder, error)


@_LATTICE_BYTES
def _lattice_diagnostic(
    context: int,
    output: _Pointer[ctypes.c_uint8],
    capacity: int,
    written: _Pointer[ctypes.c_size_t],
    required: _Pointer[ctypes.c_size_t],
) -> int:
    holder = _lattice_holder(context)
    if holder is None:
        return Status.CLOSED
    try:
        data = _provider_text(holder.provider.diagnostic(), "lattice diagnostic")
        return _write_bytes(data, output, capacity, written, required)
    except BaseException as error:  # noqa: BLE001 - no exception may cross the ABI
        return _failure_status(holder, error)


def _lattice_fold(
    context: int,
    others: _Pointer[VtResource],
    count: int,
    output: _Pointer[VtResource],
    operation: str,
) -> int:
    if not output or count and not others:
        return Status.NULL_POINTER
    if count > RECOMMENDED_LATTICE_BATCH:
        return Status.LIMIT_EXCEEDED
    holder = _lattice_holder(context)
    if holder is None:
        return Status.CLOSED

    def run() -> None:
        if count == 0:
            _retain(context)
            output[0] = VtResource(context, ctypes.addressof(_RESOURCE_VTABLE))
            return
        operands: list[LatticeOperand] = []
        try:
            operands = [
                _lattice_operand(holder, ctypes.pointer(others[index]))
                for index in range(count)
            ]
            bulk = getattr(holder.provider, f"{operation}_many", None)
            if callable(bulk):
                result = bulk(tuple(operands))
            else:
                result: object = holder.provider
                for operand in operands:
                    result = getattr(result, operation)(operand)
            _export_lattice_result(holder, result, output)
        finally:
            for operand in operands:
                operand._invalidate()

    return _status(holder, run)


@_LATTICE_MANY
def _lattice_join_many(
    context: int,
    others: _Pointer[VtResource],
    count: int,
    output: _Pointer[VtResource],
) -> int:
    return _lattice_fold(context, others, count, output, "join")


@_LATTICE_MANY
def _lattice_meet_many(
    context: int,
    others: _Pointer[VtResource],
    count: int,
    output: _Pointer[VtResource],
) -> int:
    return _lattice_fold(context, others, count, output, "meet")


class LatticeResource(_OwnedProviderResource):
    """Export one immutable Python lattice value through ABI v1."""

    def __init__(self, provider: LatticeProvider, options: LatticeOptions) -> None:
        self._open(_LatticeHolder(provider, options))

    def __enter__(self) -> LatticeResource:  # noqa: PYI034 - Python 3.10
        return self

    def __exit__(self, *_args: object) -> None:
        self.close()


SEMIRING_INTERFACE_VERSION = 1
SEMIRING_DIVISION_INTERFACE_VERSION = 1
SEMIRING_STAR_INTERFACE_VERSION = 1
SEMIRING_NUMERIC_INTERFACE_VERSION = 1
SEMIRING_PROPERTIES_INTERFACE_VERSION = 1
SEMIRING_INTERFACE_ID = b"vt.semiring.val1"
SEMIRING_DIVISION_INTERFACE_ID = b"vt.semiring.div1"
SEMIRING_STAR_INTERFACE_ID = b"vt.semiring.str1"
SEMIRING_NUMERIC_INTERFACE_ID = b"vt.semiring.num1"
SEMIRING_PROPERTIES_INTERFACE_ID = b"vt.semiring.prp1"
RECOMMENDED_SEMIRING_BATCH = 256


class SemiringProperty(IntFlag):
    """Algebraic laws declared by a dynamic semiring provider."""

    NONE = 0
    HASHABLE = 1
    IDEMPOTENT_PLUS = 2
    K_CLOSED = 4
    ZERO_SUM_FREE = 8
    COMMUTATIVE_TIMES = 16
    TOTALLY_ORDERED = 32
    NONNEGATIVE = 64


class SemiringOrder(IntEnum):
    """Natural-order result returned by a dynamic semiring provider."""

    BETTER = -1
    EQUAL = 0
    WORSE = 1
    INCOMPARABLE = 2


@dataclass(frozen=True, slots=True)
class SemiringOptions:
    """Semantic identity, concurrency promises, and declared algebraic laws."""

    domain_id: DomainId
    properties: SemiringProperty = SemiringProperty.NONE
    closure_bound: int | None = None
    thread_bound: bool = False
    parallel_reentrant: bool = False

    def __post_init__(self) -> None:
        if not isinstance(self.domain_id, DomainId):
            raise TypeError("semiring domain_id must be a DomainId")
        if not isinstance(self.thread_bound, bool) or not isinstance(
            self.parallel_reentrant, bool
        ):
            raise TypeError("semiring threading options must be bool")
        if self.thread_bound and self.parallel_reentrant:
            raise ValueError("a semiring provider cannot be thread-bound and parallel")
        raw_properties = int(self.properties)
        if raw_properties & ~127:
            raise ValueError("semiring options contain unknown property bits")
        object.__setattr__(self, "properties", SemiringProperty(raw_properties))
        if self.closure_bound is not None and (
            isinstance(self.closure_bound, bool)
            or not isinstance(self.closure_bound, int)
            or not 0 <= self.closure_bound <= ctypes.c_size_t(-1).value
        ):
            raise ValueError("semiring closure bound must fit size_t")
        if self.closure_bound is not None and not (
            self.properties & SemiringProperty.K_CLOSED
        ):
            raise ValueError("a closure bound requires the K_CLOSED property")


class SemiringProvider(Protocol):
    """Host-defined semiring over immutable Python values."""

    def zero(self) -> object:
        """Return the additive identity."""
        ...

    def one(self) -> object:
        """Return the multiplicative identity."""
        ...

    def plus(self, left: object, right: object) -> object:
        """Combine alternative-path values."""
        ...

    def times(self, left: object, right: object) -> object:
        """Combine sequential-path values."""
        ...

    def equal(self, left: object, right: object) -> bool:
        """Return exact semantic equality."""
        ...

    def approximately_equal(self, left: object, right: object, epsilon: float) -> bool:
        """Return equality within a nonnegative finite tolerance."""
        ...

    def natural_order(self, left: object, right: object) -> SemiringOrder:
        """Compare two values in the semiring's natural order."""
        ...

    def stable_bytes(self, value: object) -> bytes:
        """Return a canonical deterministic encoding."""
        ...

    def diagnostic(self, value: object | None = None) -> str:
        """Describe the context or one value when supplied."""
        ...


class DivisibleSemiringProvider(Protocol):
    """Optional dynamic-semiring quotient operations."""

    def divide(self, dividend: object, divisor: object) -> object | None:
        """Return the quotient, or ``None`` when undefined."""
        ...

    def left_divide(self, value: object, divisor: object) -> object | None:
        """Return the left quotient, or ``None`` when undefined."""
        ...


class StarSemiringProvider(Protocol):
    """Optional dynamic-semiring Kleene closure."""

    def star(self, value: object) -> object | None:
        """Return closure, or ``None`` when the series diverges."""
        ...


class NumericSemiringProvider(Protocol):
    """Optional numerical projections for specialized algorithms."""

    def numerical_value(self, value: object) -> float:
        """Return a scalar projection other than NaN; infinity is permitted."""
        ...

    def quantize(self, value: object, epsilon: float) -> int:
        """Return a signed 64-bit quantization bucket."""
        ...

    def to_probability(self, value: object) -> float:
        """Return a finite nonnegative sampling weight."""
        ...


class VtSemiringValue(ctypes.Structure):
    """Two-word provider-scoped owned semiring token."""

    _fields_ = [("word0", ctypes.c_uint64), ("word1", ctypes.c_uint64)]


_SEMIRING_CONSTRUCTOR = ctypes.CFUNCTYPE(
    ctypes.c_uint32, ctypes.c_void_p, ctypes.POINTER(VtSemiringValue)
)
_SEMIRING_CLONE = ctypes.CFUNCTYPE(
    ctypes.c_uint32,
    ctypes.c_void_p,
    ctypes.POINTER(VtSemiringValue),
    ctypes.POINTER(VtSemiringValue),
)
_SEMIRING_RELEASE = ctypes.CFUNCTYPE(
    ctypes.c_uint32,
    ctypes.c_void_p,
    ctypes.POINTER(VtSemiringValue),
    ctypes.c_size_t,
)
_SEMIRING_BINARY = ctypes.CFUNCTYPE(
    ctypes.c_uint32,
    ctypes.c_void_p,
    ctypes.POINTER(VtSemiringValue),
    ctypes.POINTER(VtSemiringValue),
    ctypes.POINTER(VtSemiringValue),
)
_SEMIRING_EQUAL = ctypes.CFUNCTYPE(
    ctypes.c_uint32,
    ctypes.c_void_p,
    ctypes.POINTER(VtSemiringValue),
    ctypes.POINTER(VtSemiringValue),
    ctypes.POINTER(ctypes.c_uint8),
)
_SEMIRING_APPROX = ctypes.CFUNCTYPE(
    ctypes.c_uint32,
    ctypes.c_void_p,
    ctypes.POINTER(VtSemiringValue),
    ctypes.POINTER(VtSemiringValue),
    ctypes.c_double,
    ctypes.POINTER(ctypes.c_uint8),
)
_SEMIRING_ORDER = ctypes.CFUNCTYPE(
    ctypes.c_uint32,
    ctypes.c_void_p,
    ctypes.POINTER(VtSemiringValue),
    ctypes.POINTER(VtSemiringValue),
    ctypes.POINTER(ctypes.c_int32),
)
_SEMIRING_BYTES = ctypes.CFUNCTYPE(
    ctypes.c_uint32,
    ctypes.c_void_p,
    ctypes.POINTER(VtSemiringValue),
    ctypes.POINTER(ctypes.c_uint8),
    ctypes.c_size_t,
    ctypes.POINTER(ctypes.c_size_t),
    ctypes.POINTER(ctypes.c_size_t),
)
_SEMIRING_DIAGNOSTIC = _SEMIRING_BYTES
_SEMIRING_MANY = ctypes.CFUNCTYPE(
    ctypes.c_uint32,
    ctypes.c_void_p,
    ctypes.POINTER(VtSemiringValue),
    ctypes.c_size_t,
    ctypes.POINTER(VtSemiringValue),
)
_SEMIRING_OPTIONAL_BINARY = _SEMIRING_BINARY
_SEMIRING_OPTIONAL_UNARY = ctypes.CFUNCTYPE(
    ctypes.c_uint32,
    ctypes.c_void_p,
    ctypes.POINTER(VtSemiringValue),
    ctypes.POINTER(VtSemiringValue),
)
_SEMIRING_NUMERICAL = ctypes.CFUNCTYPE(
    ctypes.c_uint32,
    ctypes.c_void_p,
    ctypes.POINTER(VtSemiringValue),
    ctypes.POINTER(ctypes.c_double),
)
_SEMIRING_QUANTIZE = ctypes.CFUNCTYPE(
    ctypes.c_uint32,
    ctypes.c_void_p,
    ctypes.POINTER(VtSemiringValue),
    ctypes.c_double,
    ctypes.POINTER(ctypes.c_int64),
)
_SEMIRING_CLOSURE_BOUND = ctypes.CFUNCTYPE(
    ctypes.c_uint32,
    ctypes.c_void_p,
    ctypes.POINTER(ctypes.c_size_t),
    ctypes.POINTER(ctypes.c_uint8),
)


class _SemiringVTable(ctypes.Structure):
    _fields_ = [
        ("struct_size", ctypes.c_size_t),
        ("interface_version", ctypes.c_uint32),
        ("reserved", ctypes.c_uint32),
        ("flags", ctypes.c_uint64),
        ("domain_id", _InterfaceId),
        ("zero", _SEMIRING_CONSTRUCTOR),
        ("one", _SEMIRING_CONSTRUCTOR),
        ("clone_value", _SEMIRING_CLONE),
        ("release_values", _SEMIRING_RELEASE),
        ("plus", _SEMIRING_BINARY),
        ("times", _SEMIRING_BINARY),
        ("equal", _SEMIRING_EQUAL),
        ("approx_equal", _SEMIRING_APPROX),
        ("natural_order", _SEMIRING_ORDER),
        ("stable_bytes", _SEMIRING_BYTES),
        ("diagnostic", _SEMIRING_DIAGNOSTIC),
        ("plus_many", _SEMIRING_MANY),
        ("times_many", _SEMIRING_MANY),
    ]


class _SemiringDivisionVTable(ctypes.Structure):
    _fields_ = [
        ("struct_size", ctypes.c_size_t),
        ("interface_version", ctypes.c_uint32),
        ("reserved", ctypes.c_uint32),
        ("divide", _SEMIRING_OPTIONAL_BINARY),
        ("left_divide", _SEMIRING_OPTIONAL_BINARY),
    ]


class _SemiringStarVTable(ctypes.Structure):
    _fields_ = [
        ("struct_size", ctypes.c_size_t),
        ("interface_version", ctypes.c_uint32),
        ("reserved", ctypes.c_uint32),
        ("star", _SEMIRING_OPTIONAL_UNARY),
    ]


class _SemiringNumericVTable(ctypes.Structure):
    _fields_ = [
        ("struct_size", ctypes.c_size_t),
        ("interface_version", ctypes.c_uint32),
        ("reserved", ctypes.c_uint32),
        ("numerical_value", _SEMIRING_NUMERICAL),
        ("quantize", _SEMIRING_QUANTIZE),
        ("to_probability", _SEMIRING_NUMERICAL),
    ]


class _SemiringPropertiesVTable(ctypes.Structure):
    _fields_ = [
        ("struct_size", ctypes.c_size_t),
        ("interface_version", ctypes.c_uint32),
        ("reserved", ctypes.c_uint32),
        ("properties", ctypes.c_uint64),
        ("closure_bound", _SEMIRING_CLOSURE_BOUND),
    ]


class _SemiringHolder(_ProviderHolder):
    __slots__ = (
        "_base_table",
        "_division_table",
        "_next_token",
        "_numeric_table",
        "_properties_table",
        "_star_table",
        "_token_lock",
        "_tokens",
        "options",
        "provider",
    )

    def __init__(self, provider: SemiringProvider, options: SemiringOptions) -> None:
        required = (
            "zero",
            "one",
            "plus",
            "times",
            "equal",
            "approximately_equal",
            "natural_order",
            "stable_bytes",
            "diagnostic",
        )
        absent = [
            name for name in required if not callable(getattr(provider, name, None))
        ]
        if absent:
            raise TypeError(
                f"semiring provider is missing methods: {', '.join(absent)}"
            )
        super().__init__(parallel=options.parallel_reentrant)
        self.provider = provider
        self.options = options
        self._tokens: dict[int, object] = {}
        self._next_token = itertools.count(1)
        self._token_lock = threading.Lock()
        flags = SemiringFlag.STABLE_BYTES | SemiringFlag.BATCH
        if options.thread_bound:
            flags |= SemiringFlag.THREAD_BOUND
        if options.parallel_reentrant:
            flags |= SemiringFlag.PARALLEL_REENTRANT
        self._base_table = _SemiringVTable(
            ctypes.sizeof(_SemiringVTable),
            SEMIRING_INTERFACE_VERSION,
            0,
            int(flags),
            _native_id(options.domain_id.bytes),
            _semiring_zero,
            _semiring_one,
            _semiring_clone,
            _semiring_release,
            _semiring_plus,
            _semiring_times,
            _semiring_equal,
            _semiring_approx,
            _semiring_order,
            _semiring_stable_bytes,
            _semiring_diagnostic,
            _semiring_plus_many,
            _semiring_times_many,
        )
        division_methods = tuple(
            callable(getattr(provider, name, None))
            for name in ("divide", "left_divide")
        )
        if any(division_methods) and not all(division_methods):
            raise TypeError("semiring division requires divide and left_divide")
        divisible = all(division_methods)
        self._division_table = (
            _SemiringDivisionVTable(
                ctypes.sizeof(_SemiringDivisionVTable),
                SEMIRING_DIVISION_INTERFACE_VERSION,
                0,
                _semiring_divide,
                _semiring_left_divide,
            )
            if divisible
            else None
        )
        self._star_table = (
            _SemiringStarVTable(
                ctypes.sizeof(_SemiringStarVTable),
                SEMIRING_STAR_INTERFACE_VERSION,
                0,
                _semiring_star,
            )
            if callable(getattr(provider, "star", None))
            else None
        )
        numeric_methods = tuple(
            callable(getattr(provider, name, None))
            for name in ("numerical_value", "quantize", "to_probability")
        )
        if any(numeric_methods) and not all(numeric_methods):
            raise TypeError(
                "semiring numeric projection requires numerical_value, quantize, "
                "and to_probability"
            )
        numeric = all(numeric_methods)
        self._numeric_table = (
            _SemiringNumericVTable(
                ctypes.sizeof(_SemiringNumericVTable),
                SEMIRING_NUMERIC_INTERFACE_VERSION,
                0,
                _semiring_numerical_value,
                _semiring_quantize,
                _semiring_to_probability,
            )
            if numeric
            else None
        )
        self._properties_table = _SemiringPropertiesVTable(
            ctypes.sizeof(_SemiringPropertiesVTable),
            SEMIRING_PROPERTIES_INTERFACE_VERSION,
            0,
            int(options.properties),
            _semiring_closure_bound,
        )

    def interface_vtable(
        self, interface_id: bytes, minimum_version: int
    ) -> ctypes.Structure | None:
        candidates: dict[bytes, tuple[int, ctypes.Structure | None]] = {
            SEMIRING_INTERFACE_ID: (SEMIRING_INTERFACE_VERSION, self._base_table),
            SEMIRING_DIVISION_INTERFACE_ID: (
                SEMIRING_DIVISION_INTERFACE_VERSION,
                self._division_table,
            ),
            SEMIRING_STAR_INTERFACE_ID: (
                SEMIRING_STAR_INTERFACE_VERSION,
                self._star_table,
            ),
            SEMIRING_NUMERIC_INTERFACE_ID: (
                SEMIRING_NUMERIC_INTERFACE_VERSION,
                self._numeric_table,
            ),
            SEMIRING_PROPERTIES_INTERFACE_ID: (
                SEMIRING_PROPERTIES_INTERFACE_VERSION,
                self._properties_table,
            ),
        }
        version, table = candidates.get(interface_id, (0, None))
        return table if table is not None and minimum_version <= version else None

    def own(self, value: object) -> VtSemiringValue:
        if value is None:
            raise ValueError("None is reserved for an undefined semiring operation")
        with self._token_lock:
            token = next(self._next_token)
            if token >= 2**64:
                raise OverflowError("semiring token space is exhausted")
            self._tokens[token] = value
        return VtSemiringValue(token, self.context_key)

    def value(self, pointer: _Pointer[VtSemiringValue]) -> object:
        if not pointer:
            raise ProviderStatusError(Status.INVALID_ARGUMENT, "null semiring token")
        token = pointer.contents
        if token.word1 != self.context_key or token.word0 == 0:
            raise ProviderStatusError(Status.INVALID_ARGUMENT, "foreign semiring token")
        with self._token_lock:
            try:
                return self._tokens[token.word0]
            except KeyError as error:
                raise ProviderStatusError(
                    Status.INVALID_ARGUMENT, "stale semiring token"
                ) from error

    def values(self, pointer: _Pointer[VtSemiringValue], count: int) -> list[object]:
        if count and not pointer:
            raise ProviderStatusError(
                Status.INVALID_ARGUMENT, "null semiring token array"
            )
        if count > RECOMMENDED_SEMIRING_BATCH:
            raise ProviderStatusError(
                Status.LIMIT_EXCEEDED, "semiring batch exceeds limit"
            )
        with self._token_lock:
            result: list[object] = []
            for index in range(count):
                token = pointer[index]
                if token.word1 != self.context_key or token.word0 not in self._tokens:
                    raise ProviderStatusError(
                        Status.INVALID_ARGUMENT, "foreign or stale semiring token"
                    )
                result.append(self._tokens[token.word0])
            return result

    def release(self, pointer: _Pointer[VtSemiringValue], count: int) -> None:
        if count and not pointer:
            raise ProviderStatusError(
                Status.INVALID_ARGUMENT, "null semiring token array"
            )
        if count > RECOMMENDED_SEMIRING_BATCH:
            raise ProviderStatusError(
                Status.LIMIT_EXCEEDED, "semiring batch exceeds limit"
            )
        with self._token_lock:
            identifiers: list[int] = []
            distinct: set[int] = set()
            for index in range(count):
                token = pointer[index]
                if (
                    token.word1 != self.context_key
                    or token.word0 not in self._tokens
                    or token.word0 in distinct
                ):
                    raise ProviderStatusError(
                        Status.INVALID_ARGUMENT,
                        "semiring release contains a stale, foreign, or duplicate token",
                    )
                identifiers.append(token.word0)
                distinct.add(token.word0)
            for index, identifier in enumerate(identifiers):
                del self._tokens[identifier]
                pointer[index] = VtSemiringValue()


def _semiring_holder(context: int) -> _SemiringHolder | None:
    holder = _registry.get(context)
    return holder if isinstance(holder, _SemiringHolder) else None


def _semiring_construct(
    context: int, output: _Pointer[VtSemiringValue], operation: str
) -> int:
    if not output:
        return Status.NULL_POINTER
    holder = _semiring_holder(context)
    if holder is None:
        return Status.CLOSED

    def run() -> None:
        output[0] = holder.own(getattr(holder.provider, operation)())

    return _status(holder, run)


@_SEMIRING_CONSTRUCTOR
def _semiring_zero(context: int, output: _Pointer[VtSemiringValue]) -> int:
    return _semiring_construct(context, output, "zero")


@_SEMIRING_CONSTRUCTOR
def _semiring_one(context: int, output: _Pointer[VtSemiringValue]) -> int:
    return _semiring_construct(context, output, "one")


@_SEMIRING_CLONE
def _semiring_clone(
    context: int,
    value: _Pointer[VtSemiringValue],
    output: _Pointer[VtSemiringValue],
) -> int:
    if not value or not output:
        return Status.NULL_POINTER
    holder = _semiring_holder(context)
    if holder is None:
        return Status.CLOSED
    return _status(
        holder, lambda: output.__setitem__(0, holder.own(holder.value(value)))
    )


@_SEMIRING_RELEASE
def _semiring_release(
    context: int, values: _Pointer[VtSemiringValue], count: int
) -> int:
    holder = _semiring_holder(context)
    if holder is None:
        return Status.CLOSED
    return _status(holder, lambda: holder.release(values, count))


def _semiring_binary(
    context: int,
    left: _Pointer[VtSemiringValue],
    right: _Pointer[VtSemiringValue],
    output: _Pointer[VtSemiringValue],
    operation: str,
) -> int:
    if not left or not right or not output:
        return Status.NULL_POINTER
    holder = _semiring_holder(context)
    if holder is None:
        return Status.CLOSED

    def run() -> None:
        result = getattr(holder.provider, operation)(
            holder.value(left), holder.value(right)
        )
        output[0] = holder.own(result)

    return _status(holder, run)


@_SEMIRING_BINARY
def _semiring_plus(
    context: int,
    left: _Pointer[VtSemiringValue],
    right: _Pointer[VtSemiringValue],
    output: _Pointer[VtSemiringValue],
) -> int:
    return _semiring_binary(context, left, right, output, "plus")


@_SEMIRING_BINARY
def _semiring_times(
    context: int,
    left: _Pointer[VtSemiringValue],
    right: _Pointer[VtSemiringValue],
    output: _Pointer[VtSemiringValue],
) -> int:
    return _semiring_binary(context, left, right, output, "times")


def _semiring_compare(
    context: int,
    left: _Pointer[VtSemiringValue],
    right: _Pointer[VtSemiringValue],
    output: _Pointer[ctypes.c_uint8],
    operation: str,
    *arguments: float,
) -> int:
    if not left or not right or not output:
        return Status.NULL_POINTER
    holder = _semiring_holder(context)
    if holder is None:
        return Status.CLOSED

    def run() -> None:
        result = getattr(holder.provider, operation)(
            holder.value(left), holder.value(right), *arguments
        )
        if not isinstance(result, bool):
            raise TypeError(f"semiring {operation} must return bool")
        output[0] = result

    return _status(holder, run)


@_SEMIRING_EQUAL
def _semiring_equal(
    context: int,
    left: _Pointer[VtSemiringValue],
    right: _Pointer[VtSemiringValue],
    output: _Pointer[ctypes.c_uint8],
) -> int:
    return _semiring_compare(context, left, right, output, "equal")


@_SEMIRING_APPROX
def _semiring_approx(
    context: int,
    left: _Pointer[VtSemiringValue],
    right: _Pointer[VtSemiringValue],
    epsilon: float,
    output: _Pointer[ctypes.c_uint8],
) -> int:
    if not math.isfinite(epsilon) or epsilon < 0:
        return Status.INVALID_ARGUMENT
    return _semiring_compare(
        context, left, right, output, "approximately_equal", epsilon
    )


@_SEMIRING_ORDER
def _semiring_order(
    context: int,
    left: _Pointer[VtSemiringValue],
    right: _Pointer[VtSemiringValue],
    output: _Pointer[ctypes.c_int32],
) -> int:
    if not left or not right or not output:
        return Status.NULL_POINTER
    holder = _semiring_holder(context)
    if holder is None:
        return Status.CLOSED

    def run() -> None:
        output[0] = SemiringOrder(
            holder.provider.natural_order(holder.value(left), holder.value(right))
        )

    return _status(holder, run)


def _semiring_bytes(
    context: int,
    value: _Pointer[VtSemiringValue],
    output: _Pointer[ctypes.c_uint8],
    capacity: int,
    written: _Pointer[ctypes.c_size_t],
    required: _Pointer[ctypes.c_size_t],
    diagnostic: bool,
) -> int:
    if not value:
        return Status.NULL_POINTER
    holder = _semiring_holder(context)
    if holder is None:
        return Status.CLOSED
    try:
        decoded = holder.value(value)
        if diagnostic:
            data = _provider_text(
                holder.provider.diagnostic(decoded), "semiring diagnostic"
            )
        else:
            data = _provider_bytes(
                holder.provider.stable_bytes(decoded), "semiring stable bytes"
            )
        return _write_bytes(data, output, capacity, written, required)
    except BaseException as error:  # noqa: BLE001 - no exception may cross the ABI
        return _failure_status(holder, error)


@_SEMIRING_BYTES
def _semiring_stable_bytes(
    context: int,
    value: _Pointer[VtSemiringValue],
    output: _Pointer[ctypes.c_uint8],
    capacity: int,
    written: _Pointer[ctypes.c_size_t],
    required: _Pointer[ctypes.c_size_t],
) -> int:
    return _semiring_bytes(context, value, output, capacity, written, required, False)


@_SEMIRING_DIAGNOSTIC
def _semiring_diagnostic(
    context: int,
    value: _Pointer[VtSemiringValue],
    output: _Pointer[ctypes.c_uint8],
    capacity: int,
    written: _Pointer[ctypes.c_size_t],
    required: _Pointer[ctypes.c_size_t],
) -> int:
    holder = _semiring_holder(context)
    if holder is None:
        return Status.CLOSED
    if not value:
        try:
            return _write_bytes(
                _provider_text(holder.provider.diagnostic(), "semiring diagnostic"),
                output,
                capacity,
                written,
                required,
            )
        except BaseException as error:  # noqa: BLE001 - no exception may cross the ABI
            return _failure_status(holder, error)
    return _semiring_bytes(context, value, output, capacity, written, required, True)


def _semiring_fold(
    context: int,
    values: _Pointer[VtSemiringValue],
    count: int,
    output: _Pointer[VtSemiringValue],
    operation: str,
) -> int:
    if not output or count and not values:
        return Status.NULL_POINTER
    if count > RECOMMENDED_SEMIRING_BATCH:
        return Status.LIMIT_EXCEEDED
    holder = _semiring_holder(context)
    if holder is None:
        return Status.CLOSED

    def run() -> None:
        decoded = holder.values(values, count)
        bulk = getattr(holder.provider, f"{operation}_many", None)
        if callable(bulk):
            result = bulk(tuple(decoded))
        else:
            result = getattr(
                holder.provider, "zero" if operation == "plus" else "one"
            )()
            for value in decoded:
                result = getattr(holder.provider, operation)(result, value)
        output[0] = holder.own(result)

    return _status(holder, run)


@_SEMIRING_MANY
def _semiring_plus_many(
    context: int,
    values: _Pointer[VtSemiringValue],
    count: int,
    output: _Pointer[VtSemiringValue],
) -> int:
    return _semiring_fold(context, values, count, output, "plus")


@_SEMIRING_MANY
def _semiring_times_many(
    context: int,
    values: _Pointer[VtSemiringValue],
    count: int,
    output: _Pointer[VtSemiringValue],
) -> int:
    return _semiring_fold(context, values, count, output, "times")


def _semiring_optional_binary(
    context: int,
    left: _Pointer[VtSemiringValue],
    right: _Pointer[VtSemiringValue],
    output: _Pointer[VtSemiringValue],
    operation: str,
) -> int:
    if not left or not right or not output:
        return Status.NULL_POINTER
    holder = _semiring_holder(context)
    if holder is None:
        return Status.CLOSED
    try:
        callback = getattr(holder.provider, operation, None)
        if not callable(callback):
            return Status.UNSUPPORTED
        result = callback(holder.value(left), holder.value(right))
        if result is None:
            return Status.END
        output[0] = holder.own(result)
        return Status.OK
    except BaseException as error:  # noqa: BLE001 - no exception may cross the ABI
        return _failure_status(holder, error)


@_SEMIRING_OPTIONAL_BINARY
def _semiring_divide(
    context: int,
    dividend: _Pointer[VtSemiringValue],
    divisor: _Pointer[VtSemiringValue],
    output: _Pointer[VtSemiringValue],
) -> int:
    return _semiring_optional_binary(context, dividend, divisor, output, "divide")


@_SEMIRING_OPTIONAL_BINARY
def _semiring_left_divide(
    context: int,
    value: _Pointer[VtSemiringValue],
    divisor: _Pointer[VtSemiringValue],
    output: _Pointer[VtSemiringValue],
) -> int:
    return _semiring_optional_binary(context, value, divisor, output, "left_divide")


@_SEMIRING_OPTIONAL_UNARY
def _semiring_star(
    context: int,
    value: _Pointer[VtSemiringValue],
    output: _Pointer[VtSemiringValue],
) -> int:
    if not value or not output:
        return Status.NULL_POINTER
    holder = _semiring_holder(context)
    if holder is None:
        return Status.CLOSED
    try:
        star = getattr(holder.provider, "star", None)
        if not callable(star):
            return Status.UNSUPPORTED
        result = star(holder.value(value))
        if result is None:
            return Status.END
        output[0] = holder.own(result)
        return Status.OK
    except BaseException as error:  # noqa: BLE001 - no exception may cross the ABI
        return _failure_status(holder, error)


def _semiring_numeric_value(
    context: int,
    value: _Pointer[VtSemiringValue],
    output: _Pointer[ctypes.c_double],
    operation: str,
    *,
    probability: bool = False,
) -> int:
    if not value or not output:
        return Status.NULL_POINTER
    holder = _semiring_holder(context)
    if holder is None:
        return Status.CLOSED

    def run() -> None:
        callback = getattr(holder.provider, operation, None)
        if not callable(callback):
            raise ProviderStatusError(
                Status.UNSUPPORTED,
                f"semiring provider does not implement {operation}",
            )
        numeric = cast(Callable[[object], float], callback)
        result = float(numeric(holder.value(value)))
        if math.isnan(result):
            raise ValueError(f"{operation} must not return NaN")
        if probability and (not math.isfinite(result) or result < 0.0):
            raise ValueError("to_probability must return a finite nonnegative value")
        output[0] = result

    return _status(holder, run)


@_SEMIRING_NUMERICAL
def _semiring_numerical_value(
    context: int,
    value: _Pointer[VtSemiringValue],
    output: _Pointer[ctypes.c_double],
) -> int:
    return _semiring_numeric_value(context, value, output, "numerical_value")


@_SEMIRING_QUANTIZE
def _semiring_quantize(
    context: int,
    value: _Pointer[VtSemiringValue],
    epsilon: float,
    output: _Pointer[ctypes.c_int64],
) -> int:
    if not value or not output:
        return Status.NULL_POINTER
    if not math.isfinite(epsilon) or epsilon <= 0:
        return Status.INVALID_ARGUMENT
    holder = _semiring_holder(context)
    if holder is None:
        return Status.CLOSED

    def run() -> None:
        quantize = getattr(holder.provider, "quantize", None)
        if not callable(quantize):
            raise ProviderStatusError(
                Status.UNSUPPORTED,
                "semiring provider does not implement quantize",
            )
        result = quantize(holder.value(value), epsilon)
        if isinstance(result, bool) or not isinstance(result, int):
            raise TypeError("quantize must return an integer")
        if not -(2**63) <= result < 2**63:
            raise OverflowError("quantize result is outside i64")
        output[0] = result

    return _status(holder, run)


@_SEMIRING_NUMERICAL
def _semiring_to_probability(
    context: int,
    value: _Pointer[VtSemiringValue],
    output: _Pointer[ctypes.c_double],
) -> int:
    return _semiring_numeric_value(
        context, value, output, "to_probability", probability=True
    )


@_SEMIRING_CLOSURE_BOUND
def _semiring_closure_bound(
    context: int,
    output: _Pointer[ctypes.c_size_t],
    known: _Pointer[ctypes.c_uint8],
) -> int:
    if not output or not known:
        return Status.NULL_POINTER
    holder = _semiring_holder(context)
    if holder is None:
        return Status.CLOSED
    bound = holder.options.closure_bound
    if bound is None:
        output[0] = 0
        known[0] = 0
    else:
        output[0] = bound
        known[0] = 1
    return Status.OK


class SemiringResource(_OwnedProviderResource):
    """Export a Python-defined semiring operation context through ABI v1.

    Values returned by callbacks are immutable provider-scoped leases. Native
    consumers clone and release those leases through the negotiated base
    interface. Optional division, star, and numeric interfaces are advertised
    only when their complete method groups are implemented.
    """

    def __init__(self, provider: SemiringProvider, options: SemiringOptions) -> None:
        self._open(_SemiringHolder(provider, options))

    def __enter__(self) -> SemiringResource:  # noqa: PYI034 - Python 3.10
        return self

    def __exit__(self, *_args: object) -> None:
        self.close()


__all__ = [
    "ABI_VERSION",
    "DICTIONARY_INTERFACE_ID",
    "DICTIONARY_INTERFACE_VERSION",
    "LATTICE_INTERFACE_ID",
    "LATTICE_INTERFACE_VERSION",
    "RECOMMENDED_LATTICE_BATCH",
    "RECOMMENDED_SEMIRING_BATCH",
    "SEMIRING_DIVISION_INTERFACE_ID",
    "SEMIRING_DIVISION_INTERFACE_VERSION",
    "SEMIRING_INTERFACE_ID",
    "SEMIRING_INTERFACE_VERSION",
    "SEMIRING_NUMERIC_INTERFACE_ID",
    "SEMIRING_NUMERIC_INTERFACE_VERSION",
    "SEMIRING_PROPERTIES_INTERFACE_ID",
    "SEMIRING_PROPERTIES_INTERFACE_VERSION",
    "SEMIRING_STAR_INTERFACE_ID",
    "SEMIRING_STAR_INTERFACE_VERSION",
    "WFST_INTERFACE_ID",
    "WFST_INTERFACE_VERSION",
    "DictionaryFlag",
    "DictionaryResource",
    "DivisibleSemiringProvider",
    "DomainId",
    "InteropError",
    "LatticeFlag",
    "LatticeOperand",
    "LatticeOptions",
    "LatticeProvider",
    "LatticeResource",
    "NativeResource",
    "NumericSemiringProvider",
    "ProviderStatusError",
    "ScalarWfst",
    "ScalarWfstArc",
    "ScalarWfstResource",
    "ScalarWfstSnapshot",
    "ScalarWfstState",
    "ScalarWfstStateInfo",
    "SemiringFlag",
    "SemiringOptions",
    "SemiringOrder",
    "SemiringProperty",
    "SemiringProvider",
    "SemiringResource",
    "StarSemiringProvider",
    "Status",
    "UnicodeDictionaryResource",
    "UnicodeDictionarySnapshot",
    "UnitDomain",
    "ValueDomain",
    "VtResource",
    "VtSemiringValue",
    "WeightDomain",
    "WfstFlag",
]
