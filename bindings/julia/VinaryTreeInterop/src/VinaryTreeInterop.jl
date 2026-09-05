module VinaryTreeInterop

export ABI_VERSION,
    DICTIONARY_INTERFACE_VERSION,
    DICTIONARY_VISIT_INTERFACE_VERSION,
    DICTIONARY_GRAPH_INTERFACE_VERSION,
    DICTIONARY_ENTRIES_INTERFACE_VERSION,
    SNAPSHOT_IDENTITY_INTERFACE_VERSION,
    WFST_INTERFACE_VERSION,
    LATTICE_INTERFACE_VERSION,
    SEMIRING_INTERFACE_VERSION,
    SEMIRING_DIVISION_INTERFACE_VERSION,
    SEMIRING_STAR_INTERFACE_VERSION,
    SEMIRING_NUMERIC_INTERFACE_VERSION,
    SEMIRING_PROPERTIES_INTERFACE_VERSION,
    Status,
    UnitDomain,
    ValueDomain,
    WeightDomain,
    EntryOrder,
    DICTIONARY_FLAG_PARALLEL_REENTRANT,
    DICTIONARY_FLAG_SUFFIX_BASED,
    DICTIONARY_FLAG_IMMUTABLE,
    ENTRIES_INFO_FLAG_EXACT_LEN,
    ENTRIES_INFO_FLAG_SNAPSHOT_IDENTITY,
    WFST_FLAG_PARALLEL_REENTRANT,
    WFST_FLAG_IMMUTABLE,
    WFST_FLAG_LAZY,
    WFST_FLAG_ACYCLIC,
    LATTICE_FLAG_THREAD_BOUND,
    LATTICE_FLAG_PARALLEL_REENTRANT,
    LATTICE_FLAG_STABLE_BYTES,
    LATTICE_FLAG_BATCH,
    SEMIRING_FLAG_THREAD_BOUND,
    SEMIRING_FLAG_PARALLEL_REENTRANT,
    SEMIRING_FLAG_STABLE_BYTES,
    SEMIRING_FLAG_BATCH,
    SEMIRING_PROPERTY_HASHABLE,
    SEMIRING_PROPERTY_IDEMPOTENT_PLUS,
    SEMIRING_PROPERTY_K_CLOSED,
    SEMIRING_PROPERTY_ZERO_SUM_FREE,
    SEMIRING_PROPERTY_COMMUTATIVE_TIMES,
    SEMIRING_PROPERTY_TOTALLY_ORDERED,
    SEMIRING_PROPERTY_NONNEGATIVE,
    SEMIRING_ORDER_BETTER,
    SEMIRING_ORDER_EQUAL,
    SEMIRING_ORDER_WORSE,
    SEMIRING_ORDER_INCOMPARABLE,
    DICTIONARY_INTERFACE_ID,
    DICTIONARY_VISIT_INTERFACE_ID,
    DICTIONARY_GRAPH_INTERFACE_ID,
    DICTIONARY_ENTRIES_INTERFACE_ID,
    SNAPSHOT_IDENTITY_INTERFACE_ID,
    WFST_INTERFACE_ID,
    LATTICE_INTERFACE_ID,
    SEMIRING_INTERFACE_ID,
    SEMIRING_DIVISION_INTERFACE_ID,
    SEMIRING_STAR_INTERFACE_ID,
    SEMIRING_NUMERIC_INTERFACE_ID,
    SEMIRING_PROPERTIES_INTERFACE_ID,
    VtInterfaceId,
    VtResourceVTable,
    VtResourceRaw,
    VtOptionalU64,
    VtDictionaryEdge,
    VtDictionaryVTable,
    VtDictionaryVisitVTable,
    VtDictionaryGraphNode,
    VtDictionaryGraphEdge,
    VtDictionaryGraphView,
    VtDictionaryGraphVTable,
    VtSnapshotIdentityVTable,
    VtDictionaryEntryRaw,
    VtDictionaryEntryBatchView,
    VtDictionaryEntriesInfo,
    VtDictionaryEntriesCursorRaw,
    VtDictionaryEntriesVTable,
    VtWfstArc,
    VtWfstVTable,
    VtLatticeVTable,
    VtSemiringValue,
    VtSemiringVTable,
    VtSemiringDivisionVTable,
    VtSemiringStarVTable,
    VtSemiringNumericVTable,
    VtSemiringPropertiesVTable,
    InteropError,
    Resource,
    Dictionary,
    DictionaryEntries,
    DictionaryEntry,
    DictionaryGraph,
    EntryBatch,
    Wfst,
    WfstStateInfo,
    WfstArc,
    LatticeValue,
    BatchLimits,
    SnapshotIdentity,
    adopt_resource,
    borrow_resource,
    retain,
    raw_resource,
    query_interface,
    with_resource,
    dictionary,
    wfstransducer,
    snapshot,
    known_length,
    unit_domain,
    value_domain,
    weight_domain,
    flags,
    root,
    isfinal,
    value,
    transition,
    edges,
    visit,
    graph,
    graph_nodes,
    graph_edges,
    snapshot_identity,
    entries,
    next_batch,
    copied_entries,
    release!,
    with_batch,
    reduce_entries,
    cancel!,
    start,
    state_count,
    state_info,
    arcs,
    lattice_value,
    domain_id,
    lattice_join,
    lattice_meet,
    equivalent,
    stable_bytes,
    diagnostic,
    join_many,
    meet_many,
    close!

# BEGIN GENERATED ABI CONSTANTS
const ABI_VERSION = UInt32(1)
const DICTIONARY_INTERFACE_VERSION = UInt32(1)
const DICTIONARY_VISIT_INTERFACE_VERSION = UInt32(1)
const DICTIONARY_GRAPH_INTERFACE_VERSION = UInt32(1)
const DICTIONARY_ENTRIES_INTERFACE_VERSION = UInt32(1)
const SNAPSHOT_IDENTITY_INTERFACE_VERSION = UInt32(1)
const WFST_INTERFACE_VERSION = UInt32(1)
const LATTICE_INTERFACE_VERSION = UInt32(1)
const SEMIRING_INTERFACE_VERSION = UInt32(1)
const SEMIRING_DIVISION_INTERFACE_VERSION = UInt32(1)
const SEMIRING_STAR_INTERFACE_VERSION = UInt32(1)
const SEMIRING_NUMERIC_INTERFACE_VERSION = UInt32(1)
const SEMIRING_PROPERTIES_INTERFACE_VERSION = UInt32(1)
const RECOMMENDED_EDGE_BATCH = 256
const RECOMMENDED_ARC_BATCH = 256
const RECOMMENDED_LATTICE_BATCH = 256
const RECOMMENDED_SEMIRING_BATCH = 256
const SEMIRING_ORDER_BETTER = Int32(-1)
const SEMIRING_ORDER_EQUAL = Int32(0)
const SEMIRING_ORDER_WORSE = Int32(1)
const SEMIRING_ORDER_INCOMPARABLE = Int32(2)

@enum Status::Cint begin
    STATUS_OK = 0
    STATUS_END = 1
    STATUS_INVALID_ARGUMENT = 2
    STATUS_NULL_POINTER = 3
    STATUS_UNSUPPORTED = 4
    STATUS_IO_ERROR = 5
    STATUS_CLOSED = 6
    STATUS_LIMIT_EXCEEDED = 7
    STATUS_PROVIDER_ERROR = 8
    STATUS_BATCH_IN_USE = 9
end

@enum UnitDomain::UInt32 begin
    UNIT_BYTE = 1
    UNIT_UNICODE_SCALAR = 2
    UNIT_U64 = 3
end

@enum ValueDomain::UInt32 begin
    VALUE_UNIT = 0
    VALUE_OPTIONAL_U64 = 1
    VALUE_BYTES = 2
end

@enum EntryOrder::UInt32 begin
    ENTRY_LEXICOGRAPHIC = 1
end

@enum WeightDomain::UInt32 begin
    WEIGHT_TROPICAL_F64 = 1
    WEIGHT_LOG_F64 = 2
    WEIGHT_PROBABILITY_F64 = 3
    WEIGHT_ARCTIC_F64 = 4
    WEIGHT_SIGNED_TROPICAL_F64 = 5
    WEIGHT_COUNT_F64 = 6
    WEIGHT_BOOLEAN_F64 = 7
end

const DICTIONARY_FLAG_PARALLEL_REENTRANT = UInt64(1)
const DICTIONARY_FLAG_SUFFIX_BASED = UInt64(2)
const DICTIONARY_FLAG_IMMUTABLE = UInt64(4)
const ENTRIES_INFO_FLAG_EXACT_LEN = UInt64(1)
const ENTRIES_INFO_FLAG_SNAPSHOT_IDENTITY = UInt64(2)
const WFST_FLAG_PARALLEL_REENTRANT = UInt64(1)
const WFST_FLAG_IMMUTABLE = UInt64(2)
const WFST_FLAG_LAZY = UInt64(4)
const WFST_FLAG_ACYCLIC = UInt64(8)
const LATTICE_FLAG_THREAD_BOUND = UInt64(1)
const LATTICE_FLAG_PARALLEL_REENTRANT = UInt64(2)
const LATTICE_FLAG_STABLE_BYTES = UInt64(4)
const LATTICE_FLAG_BATCH = UInt64(8)
const SEMIRING_FLAG_THREAD_BOUND = UInt64(1)
const SEMIRING_FLAG_PARALLEL_REENTRANT = UInt64(2)
const SEMIRING_FLAG_STABLE_BYTES = UInt64(4)
const SEMIRING_FLAG_BATCH = UInt64(8)
const SEMIRING_PROPERTY_HASHABLE = UInt64(1)
const SEMIRING_PROPERTY_IDEMPOTENT_PLUS = UInt64(2)
const SEMIRING_PROPERTY_K_CLOSED = UInt64(4)
const SEMIRING_PROPERTY_ZERO_SUM_FREE = UInt64(8)
const SEMIRING_PROPERTY_COMMUTATIVE_TIMES = UInt64(16)
const SEMIRING_PROPERTY_TOTALLY_ORDERED = UInt64(32)
const SEMIRING_PROPERTY_NONNEGATIVE = UInt64(64)
# END GENERATED ABI CONSTANTS

struct InteropError <: Exception
    status::Status
    operation::Symbol
end

function Base.showerror(io::IO, error::InteropError)
    print(io, "Vinary Tree interop operation ", error.operation,
        " failed with ", error.status)
end

# BEGIN GENERATED ABI INTERFACE ID LAYOUT
struct VtInterfaceId
    bytes::NTuple{16, UInt8}
end
# END GENERATED ABI INTERFACE ID LAYOUT

interface_id(value::AbstractString) = begin
    bytes = codeunits(value)
    length(bytes) == 16 || throw(ArgumentError("interface identifiers are 16 bytes"))
    VtInterfaceId(ntuple(i -> bytes[i], 16))
end

# BEGIN GENERATED ABI INTERFACE IDS
const DICTIONARY_INTERFACE_ID = interface_id("vt.dictionary.v1")
const DICTIONARY_VISIT_INTERFACE_ID = interface_id("vt.dict.visit.v1")
const DICTIONARY_GRAPH_INTERFACE_ID = interface_id("vt.dict.graph.v1")
const DICTIONARY_ENTRIES_INTERFACE_ID = interface_id("vt.dict.entry.v1")
const SNAPSHOT_IDENTITY_INTERFACE_ID = interface_id("vt.snapshot.id.1")
const WFST_INTERFACE_ID = interface_id("vt.scalar-wfst.1")
const LATTICE_INTERFACE_ID = interface_id("vt.lattice.val.1")
const SEMIRING_INTERFACE_ID = interface_id("vt.semiring.val1")
const SEMIRING_DIVISION_INTERFACE_ID = interface_id("vt.semiring.div1")
const SEMIRING_STAR_INTERFACE_ID = interface_id("vt.semiring.str1")
const SEMIRING_NUMERIC_INTERFACE_ID = interface_id("vt.semiring.num1")
const SEMIRING_PROPERTIES_INTERFACE_ID = interface_id("vt.semiring.prp1")
# END GENERATED ABI INTERFACE IDS

# BEGIN GENERATED ABI LAYOUTS AND CALLABLES
struct VtResourceVTable
    struct_size::Csize_t
    abi_version::UInt32
    reserved::UInt32
    retain::Ptr{Cvoid}
    release::Ptr{Cvoid}
    query_interface::Ptr{Cvoid}
end

struct VtOptionalU64
    value::UInt64
    has_value::UInt8
    reserved::NTuple{7, UInt8}
end

struct VtDictionaryEdge
    label::UInt64
    node::UInt64
end

struct VtDictionaryVTable
    struct_size::Csize_t
    interface_version::UInt32
    unit_domain::UInt32
    value_domain::UInt32
    flags::UInt64
    snapshot::Ptr{Cvoid}
    root::Ptr{Cvoid}
    len::Ptr{Cvoid}
    node_is_final::Ptr{Cvoid}
    node_value_u64::Ptr{Cvoid}
    node_transition::Ptr{Cvoid}
    node_edges::Ptr{Cvoid}
end

struct VtDictionaryVisitVTable
    struct_size::Csize_t
    interface_version::UInt32
    reserved::UInt32
    node_visit::Ptr{Cvoid}
end

struct VtDictionaryGraphNode
    edge_start::UInt64
    edge_len::UInt64
    value_cursor::UInt64
    is_final::UInt8
    reserved::NTuple{7, UInt8}
end

struct VtDictionaryGraphEdge
    label::UInt64
    target::UInt64
end

struct VtDictionaryGraphView
    nodes::Ptr{VtDictionaryGraphNode}
    node_count::Csize_t
    edges::Ptr{VtDictionaryGraphEdge}
    edge_count::Csize_t
    root::UInt64
    reserved::UInt64
end

struct VtDictionaryGraphVTable
    struct_size::Csize_t
    interface_version::UInt32
    reserved::UInt32
    graph::Ptr{Cvoid}
    node_value_u64::Ptr{Cvoid}
end

struct SnapshotIdentity
    producer::UInt64
    revision::UInt64
end

struct VtSnapshotIdentityVTable
    struct_size::Csize_t
    interface_version::UInt32
    reserved::UInt32
    identity::Ptr{Cvoid}
end

struct VtDictionaryEntryRaw
    unit_offset::Csize_t
    unit_len::Csize_t
    value_offset::Csize_t
    value_len::Csize_t
    reserved::UInt64
end

struct BatchLimits
    max_entries::Csize_t
    max_units::Csize_t
    max_values::Csize_t
    reserved::UInt64

    function BatchLimits(max_entries::Integer=256, max_units::Integer=65_536,
        max_values::Integer=256)
        max_entries > 0 || throw(ArgumentError("max_entries must be positive"))
        max_units >= 0 || throw(ArgumentError("max_units cannot be negative"))
        max_values >= 0 || throw(ArgumentError("max_values cannot be negative"))
        new(max_entries, max_units, max_values, 0)
    end
end

struct VtDictionaryEntryBatchView
    entries::Ptr{VtDictionaryEntryRaw}
    entry_count::Csize_t
    units::Ptr{Cvoid}
    unit_count::Csize_t
    values::Ptr{UInt64}
    value_count::Csize_t
    generation::UInt64
    reserved::UInt64
end

struct VtDictionaryEntriesInfo
    unit_domain::UInt32
    value_domain::UInt32
    order::UInt32
    reserved0::UInt32
    flags::UInt64
    exact_len::Csize_t
    identity::SnapshotIdentity
    reserved::NTuple{2, UInt64}
end

struct VtDictionaryEntriesVTable
    struct_size::Csize_t
    interface_version::UInt32
    reserved::UInt32
    open::Ptr{Cvoid}
    next_batch::Ptr{Cvoid}
    release_batch::Ptr{Cvoid}
    reduce::Ptr{Cvoid}
    cancel::Ptr{Cvoid}
    close::Ptr{Cvoid}
end

struct VtWfstArc
    input_label::UInt64
    output_label::UInt64
    target_state::UInt64
    weight::Float64
    has_input::UInt8
    has_output::UInt8
    reserved::NTuple{6, UInt8}
end

struct VtWfstVTable
    struct_size::Csize_t
    interface_version::UInt32
    unit_domain::UInt32
    weight_domain::UInt32
    reserved::UInt32
    flags::UInt64
    snapshot::Ptr{Cvoid}
    start::Ptr{Cvoid}
    num_states::Ptr{Cvoid}
    state_info::Ptr{Cvoid}
    state_arcs::Ptr{Cvoid}
end

struct VtLatticeVTable
    struct_size::Csize_t
    interface_version::UInt32
    reserved::UInt32
    flags::UInt64
    domain_id::VtInterfaceId
    join::Ptr{Cvoid}
    meet::Ptr{Cvoid}
    equal::Ptr{Cvoid}
    stable_bytes::Ptr{Cvoid}
    diagnostic::Ptr{Cvoid}
    join_many::Ptr{Cvoid}
    meet_many::Ptr{Cvoid}
end

struct VtSemiringValue
    word0::UInt64
    word1::UInt64
end

struct VtSemiringVTable
    struct_size::Csize_t
    interface_version::UInt32
    reserved::UInt32
    flags::UInt64
    domain_id::VtInterfaceId
    zero::Ptr{Cvoid}
    one::Ptr{Cvoid}
    clone_value::Ptr{Cvoid}
    release_values::Ptr{Cvoid}
    plus::Ptr{Cvoid}
    times::Ptr{Cvoid}
    equal::Ptr{Cvoid}
    approx_equal::Ptr{Cvoid}
    natural_order::Ptr{Cvoid}
    stable_bytes::Ptr{Cvoid}
    diagnostic::Ptr{Cvoid}
    plus_many::Ptr{Cvoid}
    times_many::Ptr{Cvoid}
end

struct VtSemiringDivisionVTable
    struct_size::Csize_t
    interface_version::UInt32
    reserved::UInt32
    divide::Ptr{Cvoid}
    left_divide::Ptr{Cvoid}
end

struct VtSemiringStarVTable
    struct_size::Csize_t
    interface_version::UInt32
    reserved::UInt32
    star::Ptr{Cvoid}
end

struct VtSemiringNumericVTable
    struct_size::Csize_t
    interface_version::UInt32
    reserved::UInt32
    numerical_value::Ptr{Cvoid}
    quantize::Ptr{Cvoid}
    to_probability::Ptr{Cvoid}
end

struct VtSemiringPropertiesVTable
    struct_size::Csize_t
    interface_version::UInt32
    reserved::UInt32
    properties::UInt64
    closure_bound::Ptr{Cvoid}
end

struct VtResourceRaw
    context::Ptr{Cvoid}
    vtable::Ptr{VtResourceVTable}
end

struct VtDictionaryEntriesCursorRaw
    context::Ptr{Cvoid}
    vtable::Ptr{VtDictionaryEntriesVTable}
end

macro abi_cfunction_dictionary_entry_reducer(callback)
    esc(:(@cfunction($callback, Cint, (Ptr{Cvoid}, Ptr{VtDictionaryEntryBatchView}))))
end

@inline function abi_call_resource_retain(address::Ptr{Cvoid}, context)
    ccall(address, Cvoid, (Ptr{Cvoid},), context)
end

@inline function abi_call_resource_release(address::Ptr{Cvoid}, context)
    ccall(address, Cvoid, (Ptr{Cvoid},), context)
end

@inline function abi_call_resource_query_interface(address::Ptr{Cvoid}, context, interface_id, minimum_version, out_vtable)
    ccall(address, Cint, (Ptr{Cvoid}, Ref{VtInterfaceId}, UInt32, Ptr{Ptr{Cvoid}}), context, interface_id, minimum_version, out_vtable)
end

@inline function abi_call_dictionary_snapshot(address::Ptr{Cvoid}, context, out_snapshot)
    ccall(address, Cint, (Ptr{Cvoid}, Ref{VtResourceRaw}), context, out_snapshot)
end

@inline function abi_call_dictionary_root(address::Ptr{Cvoid}, context, out_node)
    ccall(address, Cint, (Ptr{Cvoid}, Ref{UInt64}), context, out_node)
end

@inline function abi_call_dictionary_len(address::Ptr{Cvoid}, context, out_len, out_known)
    ccall(address, Cint, (Ptr{Cvoid}, Ref{Csize_t}, Ref{UInt8}), context, out_len, out_known)
end

@inline function abi_call_dictionary_node_is_final(address::Ptr{Cvoid}, context, node, out_is_final)
    ccall(address, Cint, (Ptr{Cvoid}, UInt64, Ref{UInt8}), context, node, out_is_final)
end

@inline function abi_call_dictionary_node_value_u64(address::Ptr{Cvoid}, context, node, out_value)
    ccall(address, Cint, (Ptr{Cvoid}, UInt64, Ref{VtOptionalU64}), context, node, out_value)
end

@inline function abi_call_dictionary_node_transition(address::Ptr{Cvoid}, context, node, label, out_child, out_found)
    ccall(address, Cint, (Ptr{Cvoid}, UInt64, UInt64, Ref{UInt64}, Ref{UInt8}), context, node, label, out_child, out_found)
end

@inline function abi_call_dictionary_node_edges(address::Ptr{Cvoid}, context, node, start, out_edges, capacity, out_written, out_total)
    ccall(address, Cint, (Ptr{Cvoid}, UInt64, Csize_t, Ptr{VtDictionaryEdge}, Csize_t, Ref{Csize_t}, Ref{Csize_t}), context, node, start, out_edges, capacity, out_written, out_total)
end

@inline function abi_call_dictionary_visit_node_visit(address::Ptr{Cvoid}, context, node, start, out_is_final, out_edges, capacity, out_written, out_total)
    ccall(address, Cint, (Ptr{Cvoid}, UInt64, Csize_t, Ref{UInt8}, Ptr{VtDictionaryEdge}, Csize_t, Ref{Csize_t}, Ref{Csize_t}), context, node, start, out_is_final, out_edges, capacity, out_written, out_total)
end

@inline function abi_call_dictionary_graph_graph(address::Ptr{Cvoid}, context, out_graph)
    ccall(address, Cint, (Ptr{Cvoid}, Ref{VtDictionaryGraphView}), context, out_graph)
end

@inline function abi_call_dictionary_graph_node_value_u64(address::Ptr{Cvoid}, context, value_cursor, out_value)
    ccall(address, Cint, (Ptr{Cvoid}, UInt64, Ref{VtOptionalU64}), context, value_cursor, out_value)
end

@inline function abi_call_snapshot_identity_identity(address::Ptr{Cvoid}, context, out_identity)
    ccall(address, Cint, (Ptr{Cvoid}, Ref{SnapshotIdentity}), context, out_identity)
end

@inline function abi_call_dictionary_entries_open(address::Ptr{Cvoid}, resource_context, out_cursor, out_info)
    ccall(address, Cint, (Ptr{Cvoid}, Ref{VtDictionaryEntriesCursorRaw}, Ref{VtDictionaryEntriesInfo}), resource_context, out_cursor, out_info)
end

@inline function abi_call_dictionary_entries_next_batch(address::Ptr{Cvoid}, cursor, limits, out_batch)
    ccall(address, Cint, (Ref{VtDictionaryEntriesCursorRaw}, Ref{BatchLimits}, Ref{VtDictionaryEntryBatchView}), cursor, limits, out_batch)
end

@inline function abi_call_dictionary_entries_release_batch(address::Ptr{Cvoid}, cursor, generation)
    ccall(address, Cint, (Ref{VtDictionaryEntriesCursorRaw}, UInt64), cursor, generation)
end

@inline function abi_call_dictionary_entries_reduce(address::Ptr{Cvoid}, cursor, limits, reducer, reducer_context, out_count)
    ccall(address, Cint, (Ref{VtDictionaryEntriesCursorRaw}, Ref{BatchLimits}, Ptr{Cvoid}, Ptr{Cvoid}, Ref{Csize_t}), cursor, limits, reducer, reducer_context, out_count)
end

@inline function abi_call_dictionary_entries_cancel(address::Ptr{Cvoid}, cursor)
    ccall(address, Cint, (Ref{VtDictionaryEntriesCursorRaw},), cursor)
end

@inline function abi_call_dictionary_entries_close(address::Ptr{Cvoid}, cursor)
    ccall(address, Cint, (Ref{VtDictionaryEntriesCursorRaw},), cursor)
end

@inline function abi_call_wfst_snapshot(address::Ptr{Cvoid}, context, out_snapshot)
    ccall(address, Cint, (Ptr{Cvoid}, Ref{VtResourceRaw}), context, out_snapshot)
end

@inline function abi_call_wfst_start(address::Ptr{Cvoid}, context, out_state)
    ccall(address, Cint, (Ptr{Cvoid}, Ref{UInt64}), context, out_state)
end

@inline function abi_call_wfst_num_states(address::Ptr{Cvoid}, context, out_count, out_known)
    ccall(address, Cint, (Ptr{Cvoid}, Ref{Csize_t}, Ref{UInt8}), context, out_count, out_known)
end

@inline function abi_call_wfst_state_info(address::Ptr{Cvoid}, context, state, out_valid, out_is_final, out_final_weight)
    ccall(address, Cint, (Ptr{Cvoid}, UInt64, Ref{UInt8}, Ref{UInt8}, Ref{Float64}), context, state, out_valid, out_is_final, out_final_weight)
end

@inline function abi_call_wfst_state_arcs(address::Ptr{Cvoid}, context, state, start, out_arcs, capacity, out_written, out_total)
    ccall(address, Cint, (Ptr{Cvoid}, UInt64, Csize_t, Ptr{VtWfstArc}, Csize_t, Ref{Csize_t}, Ref{Csize_t}), context, state, start, out_arcs, capacity, out_written, out_total)
end

@inline function abi_call_lattice_join(address::Ptr{Cvoid}, context, other, out_value)
    ccall(address, Cint, (Ptr{Cvoid}, Ref{VtResourceRaw}, Ref{VtResourceRaw}), context, other, out_value)
end

@inline function abi_call_lattice_meet(address::Ptr{Cvoid}, context, other, out_value)
    ccall(address, Cint, (Ptr{Cvoid}, Ref{VtResourceRaw}, Ref{VtResourceRaw}), context, other, out_value)
end

@inline function abi_call_lattice_equal(address::Ptr{Cvoid}, context, other, out_equal)
    ccall(address, Cint, (Ptr{Cvoid}, Ref{VtResourceRaw}, Ref{UInt8}), context, other, out_equal)
end

@inline function abi_call_lattice_stable_bytes(address::Ptr{Cvoid}, context, out_bytes, capacity, out_written, out_required)
    ccall(address, Cint, (Ptr{Cvoid}, Ptr{UInt8}, Csize_t, Ref{Csize_t}, Ref{Csize_t}), context, out_bytes, capacity, out_written, out_required)
end

@inline function abi_call_lattice_diagnostic(address::Ptr{Cvoid}, context, out_bytes, capacity, out_written, out_required)
    ccall(address, Cint, (Ptr{Cvoid}, Ptr{UInt8}, Csize_t, Ref{Csize_t}, Ref{Csize_t}), context, out_bytes, capacity, out_written, out_required)
end

@inline function abi_call_lattice_join_many(address::Ptr{Cvoid}, context, others, count, out_value)
    ccall(address, Cint, (Ptr{Cvoid}, Ptr{VtResourceRaw}, Csize_t, Ref{VtResourceRaw}), context, others, count, out_value)
end

@inline function abi_call_lattice_meet_many(address::Ptr{Cvoid}, context, others, count, out_value)
    ccall(address, Cint, (Ptr{Cvoid}, Ptr{VtResourceRaw}, Csize_t, Ref{VtResourceRaw}), context, others, count, out_value)
end

@inline function abi_call_semiring_zero(address::Ptr{Cvoid}, context, out_value)
    ccall(address, Cint, (Ptr{Cvoid}, Ref{VtSemiringValue}), context, out_value)
end

@inline function abi_call_semiring_one(address::Ptr{Cvoid}, context, out_value)
    ccall(address, Cint, (Ptr{Cvoid}, Ref{VtSemiringValue}), context, out_value)
end

@inline function abi_call_semiring_clone_value(address::Ptr{Cvoid}, context, value, out_value)
    ccall(address, Cint, (Ptr{Cvoid}, Ref{VtSemiringValue}, Ref{VtSemiringValue}), context, value, out_value)
end

@inline function abi_call_semiring_release_values(address::Ptr{Cvoid}, context, values, count)
    ccall(address, Cint, (Ptr{Cvoid}, Ptr{VtSemiringValue}, Csize_t), context, values, count)
end

@inline function abi_call_semiring_plus(address::Ptr{Cvoid}, context, left, right, out_value)
    ccall(address, Cint, (Ptr{Cvoid}, Ref{VtSemiringValue}, Ref{VtSemiringValue}, Ref{VtSemiringValue}), context, left, right, out_value)
end

@inline function abi_call_semiring_times(address::Ptr{Cvoid}, context, left, right, out_value)
    ccall(address, Cint, (Ptr{Cvoid}, Ref{VtSemiringValue}, Ref{VtSemiringValue}, Ref{VtSemiringValue}), context, left, right, out_value)
end

@inline function abi_call_semiring_equal(address::Ptr{Cvoid}, context, left, right, out_equal)
    ccall(address, Cint, (Ptr{Cvoid}, Ref{VtSemiringValue}, Ref{VtSemiringValue}, Ref{UInt8}), context, left, right, out_equal)
end

@inline function abi_call_semiring_approx_equal(address::Ptr{Cvoid}, context, left, right, epsilon, out_equal)
    ccall(address, Cint, (Ptr{Cvoid}, Ref{VtSemiringValue}, Ref{VtSemiringValue}, Float64, Ref{UInt8}), context, left, right, epsilon, out_equal)
end

@inline function abi_call_semiring_natural_order(address::Ptr{Cvoid}, context, left, right, out_order)
    ccall(address, Cint, (Ptr{Cvoid}, Ref{VtSemiringValue}, Ref{VtSemiringValue}, Ref{Int32}), context, left, right, out_order)
end

@inline function abi_call_semiring_stable_bytes(address::Ptr{Cvoid}, context, value, out_bytes, capacity, out_written, out_required)
    ccall(address, Cint, (Ptr{Cvoid}, Ref{VtSemiringValue}, Ptr{UInt8}, Csize_t, Ref{Csize_t}, Ref{Csize_t}), context, value, out_bytes, capacity, out_written, out_required)
end

@inline function abi_call_semiring_diagnostic(address::Ptr{Cvoid}, context, value, out_bytes, capacity, out_written, out_required)
    ccall(address, Cint, (Ptr{Cvoid}, Ref{VtSemiringValue}, Ptr{UInt8}, Csize_t, Ref{Csize_t}, Ref{Csize_t}), context, value, out_bytes, capacity, out_written, out_required)
end

@inline function abi_call_semiring_plus_many(address::Ptr{Cvoid}, context, values, count, out_value)
    ccall(address, Cint, (Ptr{Cvoid}, Ptr{VtSemiringValue}, Csize_t, Ref{VtSemiringValue}), context, values, count, out_value)
end

@inline function abi_call_semiring_times_many(address::Ptr{Cvoid}, context, values, count, out_value)
    ccall(address, Cint, (Ptr{Cvoid}, Ptr{VtSemiringValue}, Csize_t, Ref{VtSemiringValue}), context, values, count, out_value)
end

@inline function abi_call_semiring_division_divide(address::Ptr{Cvoid}, context, dividend, divisor, out_value)
    ccall(address, Cint, (Ptr{Cvoid}, Ref{VtSemiringValue}, Ref{VtSemiringValue}, Ref{VtSemiringValue}), context, dividend, divisor, out_value)
end

@inline function abi_call_semiring_division_left_divide(address::Ptr{Cvoid}, context, value, divisor, out_value)
    ccall(address, Cint, (Ptr{Cvoid}, Ref{VtSemiringValue}, Ref{VtSemiringValue}, Ref{VtSemiringValue}), context, value, divisor, out_value)
end

@inline function abi_call_semiring_star_star(address::Ptr{Cvoid}, context, value, out_value)
    ccall(address, Cint, (Ptr{Cvoid}, Ref{VtSemiringValue}, Ref{VtSemiringValue}), context, value, out_value)
end

@inline function abi_call_semiring_numeric_numerical_value(address::Ptr{Cvoid}, context, value, out_value)
    ccall(address, Cint, (Ptr{Cvoid}, Ref{VtSemiringValue}, Ref{Float64}), context, value, out_value)
end

@inline function abi_call_semiring_numeric_quantize(address::Ptr{Cvoid}, context, value, epsilon, out_value)
    ccall(address, Cint, (Ptr{Cvoid}, Ref{VtSemiringValue}, Float64, Ref{Int64}), context, value, epsilon, out_value)
end

@inline function abi_call_semiring_numeric_to_probability(address::Ptr{Cvoid}, context, value, out_value)
    ccall(address, Cint, (Ptr{Cvoid}, Ref{VtSemiringValue}, Ref{Float64}), context, value, out_value)
end

@inline function abi_call_semiring_properties_closure_bound(address::Ptr{Cvoid}, context, out_bound, out_known)
    ccall(address, Cint, (Ptr{Cvoid}, Ref{Csize_t}, Ref{UInt8}), context, out_bound, out_known)
end

const ABI_STRUCT_NAMES = (:VtInterfaceId, :VtResourceVTable, :VtOptionalU64, :VtDictionaryEdge, :VtDictionaryVTable, :VtDictionaryVisitVTable, :VtDictionaryGraphNode, :VtDictionaryGraphEdge, :VtDictionaryGraphView, :VtDictionaryGraphVTable, :SnapshotIdentity, :VtSnapshotIdentityVTable, :VtDictionaryEntryRaw, :BatchLimits, :VtDictionaryEntryBatchView, :VtDictionaryEntriesInfo, :VtDictionaryEntriesVTable, :VtWfstArc, :VtWfstVTable, :VtLatticeVTable, :VtSemiringValue, :VtSemiringVTable, :VtSemiringDivisionVTable, :VtSemiringStarVTable, :VtSemiringNumericVTable, :VtSemiringPropertiesVTable, :VtResourceRaw, :VtDictionaryEntriesCursorRaw)
const ABI_STRUCT_COUNT = 28
const ABI_OPERATION_COUNT = 52
const ABI_CALLBACK_COUNT = 1
const ABI_CALLABLE_COUNT = 53
const ABI_CALLABLES = (
    (kind=:callback, owner=:typedef, name=:VtDictionaryEntryReducer, julia_name=Symbol("@abi_cfunction_dictionary_entry_reducer"), signature="Cint Tuple{Ptr{Cvoid}, Ptr{VtDictionaryEntryBatchView}}", parameter_contract="reducer_context:input:borrowed,batch:input:borrowed", threading=:julia_owned_calling_thread_only, capability=:dictionary_entry_reducer),
    (kind=:operation, owner=:VtResourceVTable, name=:retain, julia_name=:abi_call_resource_retain, signature="Cvoid Tuple{Ptr{Cvoid},}", parameter_contract="context:input:borrowed", threading=:caller_thread_synchronous, capability=Symbol("resource")),
    (kind=:operation, owner=:VtResourceVTable, name=:release, julia_name=:abi_call_resource_release, signature="Cvoid Tuple{Ptr{Cvoid},}", parameter_contract="context:input:consumed", threading=:caller_thread_synchronous, capability=Symbol("resource")),
    (kind=:operation, owner=:VtResourceVTable, name=:query_interface, julia_name=:abi_call_resource_query_interface, signature="Cint Tuple{Ptr{Cvoid}, Ref{VtInterfaceId}, UInt32, Ptr{Ptr{Cvoid}}}", parameter_contract="context:input:borrowed,interface_id:input:borrowed,minimum_version:input:borrowed,out_vtable:output:borrowed", threading=:caller_thread_synchronous, capability=Symbol("resource")),
    (kind=:operation, owner=:VtDictionaryVTable, name=:snapshot, julia_name=:abi_call_dictionary_snapshot, signature="Cint Tuple{Ptr{Cvoid}, Ref{VtResourceRaw}}", parameter_contract="context:input:borrowed,out_snapshot:output:owned", threading=:caller_thread_synchronous, capability=Symbol("dictionary")),
    (kind=:operation, owner=:VtDictionaryVTable, name=:root, julia_name=:abi_call_dictionary_root, signature="Cint Tuple{Ptr{Cvoid}, Ref{UInt64}}", parameter_contract="context:input:borrowed,out_node:output:borrowed", threading=:caller_thread_synchronous, capability=Symbol("dictionary")),
    (kind=:operation, owner=:VtDictionaryVTable, name=:len, julia_name=:abi_call_dictionary_len, signature="Cint Tuple{Ptr{Cvoid}, Ref{Csize_t}, Ref{UInt8}}", parameter_contract="context:input:borrowed,out_len:output:borrowed,out_known:output:borrowed", threading=:caller_thread_synchronous, capability=Symbol("dictionary")),
    (kind=:operation, owner=:VtDictionaryVTable, name=:node_is_final, julia_name=:abi_call_dictionary_node_is_final, signature="Cint Tuple{Ptr{Cvoid}, UInt64, Ref{UInt8}}", parameter_contract="context:input:borrowed,node:input:borrowed,out_is_final:output:borrowed", threading=:caller_thread_synchronous, capability=Symbol("dictionary")),
    (kind=:operation, owner=:VtDictionaryVTable, name=:node_value_u64, julia_name=:abi_call_dictionary_node_value_u64, signature="Cint Tuple{Ptr{Cvoid}, UInt64, Ref{VtOptionalU64}}", parameter_contract="context:input:borrowed,node:input:borrowed,out_value:output:borrowed", threading=:caller_thread_synchronous, capability=Symbol("dictionary")),
    (kind=:operation, owner=:VtDictionaryVTable, name=:node_transition, julia_name=:abi_call_dictionary_node_transition, signature="Cint Tuple{Ptr{Cvoid}, UInt64, UInt64, Ref{UInt64}, Ref{UInt8}}", parameter_contract="context:input:borrowed,node:input:borrowed,label:input:borrowed,out_child:output:borrowed,out_found:output:borrowed", threading=:caller_thread_synchronous, capability=Symbol("dictionary")),
    (kind=:operation, owner=:VtDictionaryVTable, name=:node_edges, julia_name=:abi_call_dictionary_node_edges, signature="Cint Tuple{Ptr{Cvoid}, UInt64, Csize_t, Ptr{VtDictionaryEdge}, Csize_t, Ref{Csize_t}, Ref{Csize_t}}", parameter_contract="context:input:borrowed,node:input:borrowed,start:input:borrowed,out_edges:output:borrowed,capacity:input:borrowed,out_written:output:borrowed,out_total:output:borrowed", threading=:caller_thread_synchronous, capability=Symbol("dictionary")),
    (kind=:operation, owner=:VtDictionaryVisitVTable, name=:node_visit, julia_name=:abi_call_dictionary_visit_node_visit, signature="Cint Tuple{Ptr{Cvoid}, UInt64, Csize_t, Ref{UInt8}, Ptr{VtDictionaryEdge}, Csize_t, Ref{Csize_t}, Ref{Csize_t}}", parameter_contract="context:input:borrowed,node:input:borrowed,start:input:borrowed,out_is_final:output:borrowed,out_edges:output:borrowed,capacity:input:borrowed,out_written:output:borrowed,out_total:output:borrowed", threading=:caller_thread_synchronous, capability=Symbol("dictionary-visit")),
    (kind=:operation, owner=:VtDictionaryGraphVTable, name=:graph, julia_name=:abi_call_dictionary_graph_graph, signature="Cint Tuple{Ptr{Cvoid}, Ref{VtDictionaryGraphView}}", parameter_contract="context:input:borrowed,out_graph:output:borrowed", threading=:caller_thread_synchronous, capability=Symbol("dictionary-graph")),
    (kind=:operation, owner=:VtDictionaryGraphVTable, name=:node_value_u64, julia_name=:abi_call_dictionary_graph_node_value_u64, signature="Cint Tuple{Ptr{Cvoid}, UInt64, Ref{VtOptionalU64}}", parameter_contract="context:input:borrowed,value_cursor:input:borrowed,out_value:output:borrowed", threading=:caller_thread_synchronous, capability=Symbol("dictionary-graph")),
    (kind=:operation, owner=:VtSnapshotIdentityVTable, name=:identity, julia_name=:abi_call_snapshot_identity_identity, signature="Cint Tuple{Ptr{Cvoid}, Ref{SnapshotIdentity}}", parameter_contract="context:input:borrowed,out_identity:output:borrowed", threading=:caller_thread_synchronous, capability=Symbol("snapshot-identity")),
    (kind=:operation, owner=:VtDictionaryEntriesVTable, name=:open, julia_name=:abi_call_dictionary_entries_open, signature="Cint Tuple{Ptr{Cvoid}, Ref{VtDictionaryEntriesCursorRaw}, Ref{VtDictionaryEntriesInfo}}", parameter_contract="resource_context:input:borrowed,out_cursor:output:owned,out_info:output:borrowed", threading=:caller_thread_synchronous, capability=Symbol("dictionary-entries")),
    (kind=:operation, owner=:VtDictionaryEntriesVTable, name=:next_batch, julia_name=:abi_call_dictionary_entries_next_batch, signature="Cint Tuple{Ref{VtDictionaryEntriesCursorRaw}, Ref{BatchLimits}, Ref{VtDictionaryEntryBatchView}}", parameter_contract="cursor:inout:borrowed,limits:input:borrowed,out_batch:output:borrowed", threading=:caller_thread_synchronous, capability=Symbol("dictionary-entries")),
    (kind=:operation, owner=:VtDictionaryEntriesVTable, name=:release_batch, julia_name=:abi_call_dictionary_entries_release_batch, signature="Cint Tuple{Ref{VtDictionaryEntriesCursorRaw}, UInt64}", parameter_contract="cursor:inout:borrowed,generation:input:borrowed", threading=:caller_thread_synchronous, capability=Symbol("dictionary-entries")),
    (kind=:operation, owner=:VtDictionaryEntriesVTable, name=:reduce, julia_name=:abi_call_dictionary_entries_reduce, signature="Cint Tuple{Ref{VtDictionaryEntriesCursorRaw}, Ref{BatchLimits}, Ptr{Cvoid}, Ptr{Cvoid}, Ref{Csize_t}}", parameter_contract="cursor:inout:borrowed,limits:input:borrowed,reducer:input:borrowed,reducer_context:input:borrowed,out_count:output:borrowed", threading=:caller_thread_synchronous, capability=Symbol("dictionary-entries")),
    (kind=:operation, owner=:VtDictionaryEntriesVTable, name=:cancel, julia_name=:abi_call_dictionary_entries_cancel, signature="Cint Tuple{Ref{VtDictionaryEntriesCursorRaw},}", parameter_contract="cursor:inout:borrowed", threading=:caller_thread_synchronous, capability=Symbol("dictionary-entries")),
    (kind=:operation, owner=:VtDictionaryEntriesVTable, name=:close, julia_name=:abi_call_dictionary_entries_close, signature="Cint Tuple{Ref{VtDictionaryEntriesCursorRaw},}", parameter_contract="cursor:inout:consumed", threading=:caller_thread_synchronous, capability=Symbol("dictionary-entries")),
    (kind=:operation, owner=:VtWfstVTable, name=:snapshot, julia_name=:abi_call_wfst_snapshot, signature="Cint Tuple{Ptr{Cvoid}, Ref{VtResourceRaw}}", parameter_contract="context:input:borrowed,out_snapshot:output:owned", threading=:caller_thread_synchronous, capability=Symbol("wfst")),
    (kind=:operation, owner=:VtWfstVTable, name=:start, julia_name=:abi_call_wfst_start, signature="Cint Tuple{Ptr{Cvoid}, Ref{UInt64}}", parameter_contract="context:input:borrowed,out_state:output:borrowed", threading=:caller_thread_synchronous, capability=Symbol("wfst")),
    (kind=:operation, owner=:VtWfstVTable, name=:num_states, julia_name=:abi_call_wfst_num_states, signature="Cint Tuple{Ptr{Cvoid}, Ref{Csize_t}, Ref{UInt8}}", parameter_contract="context:input:borrowed,out_count:output:borrowed,out_known:output:borrowed", threading=:caller_thread_synchronous, capability=Symbol("wfst")),
    (kind=:operation, owner=:VtWfstVTable, name=:state_info, julia_name=:abi_call_wfst_state_info, signature="Cint Tuple{Ptr{Cvoid}, UInt64, Ref{UInt8}, Ref{UInt8}, Ref{Float64}}", parameter_contract="context:input:borrowed,state:input:borrowed,out_valid:output:borrowed,out_is_final:output:borrowed,out_final_weight:output:borrowed", threading=:caller_thread_synchronous, capability=Symbol("wfst")),
    (kind=:operation, owner=:VtWfstVTable, name=:state_arcs, julia_name=:abi_call_wfst_state_arcs, signature="Cint Tuple{Ptr{Cvoid}, UInt64, Csize_t, Ptr{VtWfstArc}, Csize_t, Ref{Csize_t}, Ref{Csize_t}}", parameter_contract="context:input:borrowed,state:input:borrowed,start:input:borrowed,out_arcs:output:borrowed,capacity:input:borrowed,out_written:output:borrowed,out_total:output:borrowed", threading=:caller_thread_synchronous, capability=Symbol("wfst")),
    (kind=:operation, owner=:VtLatticeVTable, name=:join, julia_name=:abi_call_lattice_join, signature="Cint Tuple{Ptr{Cvoid}, Ref{VtResourceRaw}, Ref{VtResourceRaw}}", parameter_contract="context:input:borrowed,other:input:borrowed,out_value:output:owned", threading=:caller_thread_synchronous, capability=Symbol("lattice")),
    (kind=:operation, owner=:VtLatticeVTable, name=:meet, julia_name=:abi_call_lattice_meet, signature="Cint Tuple{Ptr{Cvoid}, Ref{VtResourceRaw}, Ref{VtResourceRaw}}", parameter_contract="context:input:borrowed,other:input:borrowed,out_value:output:owned", threading=:caller_thread_synchronous, capability=Symbol("lattice")),
    (kind=:operation, owner=:VtLatticeVTable, name=:equal, julia_name=:abi_call_lattice_equal, signature="Cint Tuple{Ptr{Cvoid}, Ref{VtResourceRaw}, Ref{UInt8}}", parameter_contract="context:input:borrowed,other:input:borrowed,out_equal:output:borrowed", threading=:caller_thread_synchronous, capability=Symbol("lattice")),
    (kind=:operation, owner=:VtLatticeVTable, name=:stable_bytes, julia_name=:abi_call_lattice_stable_bytes, signature="Cint Tuple{Ptr{Cvoid}, Ptr{UInt8}, Csize_t, Ref{Csize_t}, Ref{Csize_t}}", parameter_contract="context:input:borrowed,out_bytes:output:borrowed,capacity:input:borrowed,out_written:output:borrowed,out_required:output:borrowed", threading=:caller_thread_synchronous, capability=Symbol("lattice")),
    (kind=:operation, owner=:VtLatticeVTable, name=:diagnostic, julia_name=:abi_call_lattice_diagnostic, signature="Cint Tuple{Ptr{Cvoid}, Ptr{UInt8}, Csize_t, Ref{Csize_t}, Ref{Csize_t}}", parameter_contract="context:input:borrowed,out_bytes:output:borrowed,capacity:input:borrowed,out_written:output:borrowed,out_required:output:borrowed", threading=:caller_thread_synchronous, capability=Symbol("lattice")),
    (kind=:operation, owner=:VtLatticeVTable, name=:join_many, julia_name=:abi_call_lattice_join_many, signature="Cint Tuple{Ptr{Cvoid}, Ptr{VtResourceRaw}, Csize_t, Ref{VtResourceRaw}}", parameter_contract="context:input:borrowed,others:input:borrowed,count:input:borrowed,out_value:output:owned", threading=:caller_thread_synchronous, capability=Symbol("lattice")),
    (kind=:operation, owner=:VtLatticeVTable, name=:meet_many, julia_name=:abi_call_lattice_meet_many, signature="Cint Tuple{Ptr{Cvoid}, Ptr{VtResourceRaw}, Csize_t, Ref{VtResourceRaw}}", parameter_contract="context:input:borrowed,others:input:borrowed,count:input:borrowed,out_value:output:owned", threading=:caller_thread_synchronous, capability=Symbol("lattice")),
    (kind=:operation, owner=:VtSemiringVTable, name=:zero, julia_name=:abi_call_semiring_zero, signature="Cint Tuple{Ptr{Cvoid}, Ref{VtSemiringValue}}", parameter_contract="context:input:borrowed,out_value:output:owned", threading=:caller_thread_synchronous, capability=Symbol("semiring")),
    (kind=:operation, owner=:VtSemiringVTable, name=:one, julia_name=:abi_call_semiring_one, signature="Cint Tuple{Ptr{Cvoid}, Ref{VtSemiringValue}}", parameter_contract="context:input:borrowed,out_value:output:owned", threading=:caller_thread_synchronous, capability=Symbol("semiring")),
    (kind=:operation, owner=:VtSemiringVTable, name=:clone_value, julia_name=:abi_call_semiring_clone_value, signature="Cint Tuple{Ptr{Cvoid}, Ref{VtSemiringValue}, Ref{VtSemiringValue}}", parameter_contract="context:input:borrowed,value:input:borrowed,out_value:output:owned", threading=:caller_thread_synchronous, capability=Symbol("semiring")),
    (kind=:operation, owner=:VtSemiringVTable, name=:release_values, julia_name=:abi_call_semiring_release_values, signature="Cint Tuple{Ptr{Cvoid}, Ptr{VtSemiringValue}, Csize_t}", parameter_contract="context:input:borrowed,values:inout:consumed,count:input:borrowed", threading=:caller_thread_synchronous, capability=Symbol("semiring")),
    (kind=:operation, owner=:VtSemiringVTable, name=:plus, julia_name=:abi_call_semiring_plus, signature="Cint Tuple{Ptr{Cvoid}, Ref{VtSemiringValue}, Ref{VtSemiringValue}, Ref{VtSemiringValue}}", parameter_contract="context:input:borrowed,left:input:borrowed,right:input:borrowed,out_value:output:owned", threading=:caller_thread_synchronous, capability=Symbol("semiring")),
    (kind=:operation, owner=:VtSemiringVTable, name=:times, julia_name=:abi_call_semiring_times, signature="Cint Tuple{Ptr{Cvoid}, Ref{VtSemiringValue}, Ref{VtSemiringValue}, Ref{VtSemiringValue}}", parameter_contract="context:input:borrowed,left:input:borrowed,right:input:borrowed,out_value:output:owned", threading=:caller_thread_synchronous, capability=Symbol("semiring")),
    (kind=:operation, owner=:VtSemiringVTable, name=:equal, julia_name=:abi_call_semiring_equal, signature="Cint Tuple{Ptr{Cvoid}, Ref{VtSemiringValue}, Ref{VtSemiringValue}, Ref{UInt8}}", parameter_contract="context:input:borrowed,left:input:borrowed,right:input:borrowed,out_equal:output:borrowed", threading=:caller_thread_synchronous, capability=Symbol("semiring")),
    (kind=:operation, owner=:VtSemiringVTable, name=:approx_equal, julia_name=:abi_call_semiring_approx_equal, signature="Cint Tuple{Ptr{Cvoid}, Ref{VtSemiringValue}, Ref{VtSemiringValue}, Float64, Ref{UInt8}}", parameter_contract="context:input:borrowed,left:input:borrowed,right:input:borrowed,epsilon:input:borrowed,out_equal:output:borrowed", threading=:caller_thread_synchronous, capability=Symbol("semiring")),
    (kind=:operation, owner=:VtSemiringVTable, name=:natural_order, julia_name=:abi_call_semiring_natural_order, signature="Cint Tuple{Ptr{Cvoid}, Ref{VtSemiringValue}, Ref{VtSemiringValue}, Ref{Int32}}", parameter_contract="context:input:borrowed,left:input:borrowed,right:input:borrowed,out_order:output:borrowed", threading=:caller_thread_synchronous, capability=Symbol("semiring")),
    (kind=:operation, owner=:VtSemiringVTable, name=:stable_bytes, julia_name=:abi_call_semiring_stable_bytes, signature="Cint Tuple{Ptr{Cvoid}, Ref{VtSemiringValue}, Ptr{UInt8}, Csize_t, Ref{Csize_t}, Ref{Csize_t}}", parameter_contract="context:input:borrowed,value:input:borrowed,out_bytes:output:borrowed,capacity:input:borrowed,out_written:output:borrowed,out_required:output:borrowed", threading=:caller_thread_synchronous, capability=Symbol("semiring")),
    (kind=:operation, owner=:VtSemiringVTable, name=:diagnostic, julia_name=:abi_call_semiring_diagnostic, signature="Cint Tuple{Ptr{Cvoid}, Ref{VtSemiringValue}, Ptr{UInt8}, Csize_t, Ref{Csize_t}, Ref{Csize_t}}", parameter_contract="context:input:borrowed,value:input:borrowed,out_bytes:output:borrowed,capacity:input:borrowed,out_written:output:borrowed,out_required:output:borrowed", threading=:caller_thread_synchronous, capability=Symbol("semiring")),
    (kind=:operation, owner=:VtSemiringVTable, name=:plus_many, julia_name=:abi_call_semiring_plus_many, signature="Cint Tuple{Ptr{Cvoid}, Ptr{VtSemiringValue}, Csize_t, Ref{VtSemiringValue}}", parameter_contract="context:input:borrowed,values:input:borrowed,count:input:borrowed,out_value:output:owned", threading=:caller_thread_synchronous, capability=Symbol("semiring")),
    (kind=:operation, owner=:VtSemiringVTable, name=:times_many, julia_name=:abi_call_semiring_times_many, signature="Cint Tuple{Ptr{Cvoid}, Ptr{VtSemiringValue}, Csize_t, Ref{VtSemiringValue}}", parameter_contract="context:input:borrowed,values:input:borrowed,count:input:borrowed,out_value:output:owned", threading=:caller_thread_synchronous, capability=Symbol("semiring")),
    (kind=:operation, owner=:VtSemiringDivisionVTable, name=:divide, julia_name=:abi_call_semiring_division_divide, signature="Cint Tuple{Ptr{Cvoid}, Ref{VtSemiringValue}, Ref{VtSemiringValue}, Ref{VtSemiringValue}}", parameter_contract="context:input:borrowed,dividend:input:borrowed,divisor:input:borrowed,out_value:output:owned", threading=:caller_thread_synchronous, capability=Symbol("semiring-division")),
    (kind=:operation, owner=:VtSemiringDivisionVTable, name=:left_divide, julia_name=:abi_call_semiring_division_left_divide, signature="Cint Tuple{Ptr{Cvoid}, Ref{VtSemiringValue}, Ref{VtSemiringValue}, Ref{VtSemiringValue}}", parameter_contract="context:input:borrowed,value:input:borrowed,divisor:input:borrowed,out_value:output:owned", threading=:caller_thread_synchronous, capability=Symbol("semiring-division")),
    (kind=:operation, owner=:VtSemiringStarVTable, name=:star, julia_name=:abi_call_semiring_star_star, signature="Cint Tuple{Ptr{Cvoid}, Ref{VtSemiringValue}, Ref{VtSemiringValue}}", parameter_contract="context:input:borrowed,value:input:borrowed,out_value:output:owned", threading=:caller_thread_synchronous, capability=Symbol("semiring-star")),
    (kind=:operation, owner=:VtSemiringNumericVTable, name=:numerical_value, julia_name=:abi_call_semiring_numeric_numerical_value, signature="Cint Tuple{Ptr{Cvoid}, Ref{VtSemiringValue}, Ref{Float64}}", parameter_contract="context:input:borrowed,value:input:borrowed,out_value:output:borrowed", threading=:caller_thread_synchronous, capability=Symbol("semiring-numeric")),
    (kind=:operation, owner=:VtSemiringNumericVTable, name=:quantize, julia_name=:abi_call_semiring_numeric_quantize, signature="Cint Tuple{Ptr{Cvoid}, Ref{VtSemiringValue}, Float64, Ref{Int64}}", parameter_contract="context:input:borrowed,value:input:borrowed,epsilon:input:borrowed,out_value:output:borrowed", threading=:caller_thread_synchronous, capability=Symbol("semiring-numeric")),
    (kind=:operation, owner=:VtSemiringNumericVTable, name=:to_probability, julia_name=:abi_call_semiring_numeric_to_probability, signature="Cint Tuple{Ptr{Cvoid}, Ref{VtSemiringValue}, Ref{Float64}}", parameter_contract="context:input:borrowed,value:input:borrowed,out_value:output:borrowed", threading=:caller_thread_synchronous, capability=Symbol("semiring-numeric")),
    (kind=:operation, owner=:VtSemiringPropertiesVTable, name=:closure_bound, julia_name=:abi_call_semiring_properties_closure_bound, signature="Cint Tuple{Ptr{Cvoid}, Ref{Csize_t}, Ref{UInt8}}", parameter_contract="context:input:borrowed,out_bound:output:borrowed,out_known:output:borrowed", threading=:caller_thread_synchronous, capability=Symbol("semiring-properties")),
)
# END GENERATED ABI LAYOUTS AND CALLABLES

function checked_status(code::Integer, operation::Symbol; allow_end::Bool=false,
    allow_unsupported::Bool=false)
    status = Status(code)
    status == STATUS_OK && return status
    allow_end && status == STATUS_END && return status
    allow_unsupported && status == STATUS_UNSUPPORTED && return status
    throw(InteropError(status, operation))
end

function require_pointer(pointer::Ptr, operation::Symbol)
    pointer == C_NULL && throw(InteropError(STATUS_UNSUPPORTED, operation))
    pointer
end

function finalize_close(value)
    try
        close!(value)
    catch
        # Finalizers are a leak-safety fallback; deterministic close reports errors.
    end
    nothing
end

function finalize_release(value)
    try
        release!(value)
    catch
        # Finalizers cannot safely propagate an exception during garbage collection.
    end
    nothing
end

function resource_vtable(raw::VtResourceRaw)
    raw.context == C_NULL && throw(InteropError(STATUS_CLOSED, :resource))
    raw.vtable == C_NULL && throw(InteropError(STATUS_NULL_POINTER, :resource_vtable))
    table = unsafe_load(raw.vtable)
    table.abi_version == ABI_VERSION ||
        throw(InteropError(STATUS_UNSUPPORTED, :abi_version))
    table
end

mutable struct Resource
    raw::VtResourceRaw
    closed::Bool
    anchors::Vector{Any}
end

function adopt_resource(raw::VtResourceRaw; anchors=Any[])
    resource_vtable(raw)
    resource = Resource(raw, false, Any[anchors...])
    finalizer(finalize_close, resource)
    resource
end

function borrow_resource(raw::VtResourceRaw; anchors=Any[])
    table = resource_vtable(raw)
    require_pointer(table.retain, :retain)
    require_pointer(table.release, :release)
    abi_call_resource_retain(table.retain, raw.context)
    try
        adopt_resource(raw; anchors)
    catch
        abi_call_resource_release(table.release, raw.context)
        rethrow()
    end
end

function retain_raw(raw::VtResourceRaw)
    table = resource_vtable(raw)
    require_pointer(table.retain, :retain)
    abi_call_resource_retain(table.retain, raw.context)
    raw
end

function retain(resource::Resource)
    raw = raw_resource(resource)
    retain_raw(raw)
    adopt_resource(raw; anchors=resource.anchors)
end

function raw_resource(resource::Resource)
    resource.closed && throw(InteropError(STATUS_CLOSED, :resource))
    resource.raw
end

function close!(resource::Resource)
    resource.closed && return nothing
    raw = resource.raw
    resource.closed = true
    resource.raw = VtResourceRaw(C_NULL, Ptr{VtResourceVTable}(C_NULL))
    anchors = resource.anchors
    table = resource_vtable(raw)
    if table.release != C_NULL
        GC.@preserve anchors abi_call_resource_release(table.release, raw.context)
    end
    empty!(anchors)
    nothing
end

Base.close(resource::Resource) = close!(resource)
Base.isopen(resource::Resource) = !resource.closed

function with_resource(f::F, resource::Resource) where {F}
    owned = retain(resource)
    try
        f(owned)
    finally
        close!(owned)
    end
end

function query_interface(resource::Resource, id::VtInterfaceId,
    minimum_version::Integer=1)
    raw = raw_resource(resource)
    table = resource_vtable(raw)
    require_pointer(table.query_interface, :query_interface)
    output = Ref{Ptr{Cvoid}}(C_NULL)
    status = abi_call_resource_query_interface(table.query_interface,
        raw.context, Ref(id), UInt32(minimum_version), output)
    checked_status(status, :query_interface; allow_unsupported=true)
    Status(status) == STATUS_UNSUPPORTED && return nothing
    output[] == C_NULL && throw(InteropError(STATUS_NULL_POINTER, :query_interface))
    output[]
end

mutable struct Dictionary{K,V} <: AbstractDict{K,V}
    resource::Resource
    table::Ptr{VtDictionaryVTable}
    closed::Bool
end

function dictionary(resource::Resource; take::Bool=false)
    owned = take ? resource : retain(resource)
    try
        pointer = query_interface(owned, DICTIONARY_INTERFACE_ID,
            DICTIONARY_INTERFACE_VERSION)
        pointer === nothing && throw(InteropError(STATUS_UNSUPPORTED, :dictionary))
        table = Ptr{VtDictionaryVTable}(pointer)
        value = unsafe_load(table)
        value.interface_version >= DICTIONARY_INTERFACE_VERSION ||
            throw(InteropError(STATUS_UNSUPPORTED, :dictionary_version))
        key_type = if value.unit_domain == UInt32(UNIT_BYTE)
            Vector{UInt8}
        elseif value.unit_domain == UInt32(UNIT_UNICODE_SCALAR)
            String
        else
            Vector{UInt64}
        end
        mapped_type = if value.value_domain == UInt32(VALUE_UNIT)
            Nothing
        elseif value.value_domain == UInt32(VALUE_OPTIONAL_U64)
            Union{Nothing, UInt64}
        elseif value.value_domain == UInt32(VALUE_BYTES)
            Vector{UInt8}
        else
            Any
        end
        result = Dictionary{key_type,mapped_type}(owned, table, false)
        finalizer(finalize_close, result)
        result
    catch
        close!(owned)
        rethrow()
    end
end

function dictionary(raw::VtResourceRaw)
    dictionary(adopt_resource(raw); take=true)
end

function dictionary_table(dictionary::Dictionary)
    dictionary.closed && throw(InteropError(STATUS_CLOSED, :dictionary))
    unsafe_load(dictionary.table)
end

function close!(dictionary::Dictionary)
    dictionary.closed && return nothing
    dictionary.closed = true
    close!(dictionary.resource)
end

Base.close(dictionary::Dictionary) = close!(dictionary)
Base.isopen(dictionary::Dictionary) = !dictionary.closed

unit_domain(dictionary::Dictionary) = UnitDomain(dictionary_table(dictionary).unit_domain)
value_domain(dictionary::Dictionary) = ValueDomain(dictionary_table(dictionary).value_domain)
flags(dictionary::Dictionary) = dictionary_table(dictionary).flags

function snapshot(source::Dictionary)
    raw = raw_resource(source.resource)
    table = dictionary_table(source)
    function_pointer = require_pointer(table.snapshot, :dictionary_snapshot)
    output = Ref(VtResourceRaw(C_NULL, Ptr{VtResourceVTable}(C_NULL)))
    status = abi_call_dictionary_snapshot(function_pointer, raw.context, output)
    checked_status(status, :dictionary_snapshot)
    dictionary(output[])
end

function root(dictionary::Dictionary)
    raw = raw_resource(dictionary.resource)
    table = dictionary_table(dictionary)
    output = Ref{UInt64}(0)
    status = abi_call_dictionary_root(
        require_pointer(table.root, :dictionary_root), raw.context, output)
    checked_status(status, :dictionary_root)
    output[]
end

function known_length(dictionary::Dictionary)
    raw = raw_resource(dictionary.resource)
    table = dictionary_table(dictionary)
    output = Ref{Csize_t}(0)
    known = Ref{UInt8}(0)
    status = abi_call_dictionary_len(
        require_pointer(table.len, :dictionary_len), raw.context, output, known)
    checked_status(status, :dictionary_len)
    known[] == 0 ? nothing : Int(output[])
end

function Base.length(dictionary::Dictionary)
    result = known_length(dictionary)
    result === nothing && throw(ArgumentError("dictionary length is not known"))
    result
end

function key_units(dictionary::Dictionary, key)
    domain = unit_domain(dictionary)
    if domain == UNIT_BYTE
        key isa AbstractVector{UInt8} && return key
        key isa AbstractString && return codeunits(key)
    elseif domain == UNIT_UNICODE_SCALAR
        key isa AbstractString && return UInt32[UInt32(character) for character in key]
        key isa AbstractVector{UInt32} && return key
    elseif domain == UNIT_U64
        key isa AbstractVector{UInt64} && return key
    end
    throw(ArgumentError("key is incompatible with dictionary unit domain $domain"))
end

function terminal(dictionary::Dictionary, key)
    node = root(dictionary)
    for label in key_units(dictionary, key)
        child = transition(dictionary, node, label)
        child === nothing && return nothing
        node = child
    end
    isfinal(dictionary, node) ? node : nothing
end

Base.haskey(dictionary::Dictionary, key) = terminal(dictionary, key) !== nothing

function Base.getindex(dictionary::Dictionary, key)
    node = terminal(dictionary, key)
    node === nothing && throw(KeyError(key))
    domain = value_domain(dictionary)
    domain == VALUE_UNIT && return nothing
    domain == VALUE_OPTIONAL_U64 && return value(dictionary, node)
    throw(InteropError(STATUS_UNSUPPORTED, :dictionary_getindex))
end

function isfinal(dictionary::Dictionary, node::Integer)
    raw = raw_resource(dictionary.resource)
    table = dictionary_table(dictionary)
    output = Ref{UInt8}(0)
    status = abi_call_dictionary_node_is_final(
        require_pointer(table.node_is_final, :dictionary_isfinal), raw.context,
        UInt64(node), output)
    checked_status(status, :dictionary_isfinal)
    output[] != 0
end

function value(dictionary::Dictionary, node::Integer)
    value_domain(dictionary) == VALUE_OPTIONAL_U64 ||
        throw(InteropError(STATUS_UNSUPPORTED, :dictionary_value))
    raw = raw_resource(dictionary.resource)
    table = dictionary_table(dictionary)
    output = Ref(VtOptionalU64(0, 0, ntuple(_ -> UInt8(0), 7)))
    status = abi_call_dictionary_node_value_u64(
        require_pointer(table.node_value_u64, :dictionary_value), raw.context,
        UInt64(node), output)
    checked_status(status, :dictionary_value)
    output[].has_value == 0 ? nothing : output[].value
end

function transition(dictionary::Dictionary, node::Integer, label::Integer)
    raw = raw_resource(dictionary.resource)
    table = dictionary_table(dictionary)
    child = Ref{UInt64}(0)
    found = Ref{UInt8}(0)
    status = abi_call_dictionary_node_transition(
        require_pointer(table.node_transition, :dictionary_transition), raw.context,
        UInt64(node), UInt64(label), child, found)
    checked_status(status, :dictionary_transition)
    found[] == 0 ? nothing : child[]
end

function edges(dictionary::Dictionary, node::Integer;
    batch_size::Integer=RECOMMENDED_EDGE_BATCH)
    batch_size > 0 || throw(ArgumentError("batch_size must be positive"))
    raw = raw_resource(dictionary.resource)
    table = dictionary_table(dictionary)
    function_pointer = require_pointer(table.node_edges, :dictionary_edges)
    output = VtDictionaryEdge[]
    start_offset = 0
    total = typemax(Int)
    page = Vector{VtDictionaryEdge}(undef, batch_size)
    while start_offset < total
        written = Ref{Csize_t}(0)
        reported_total = Ref{Csize_t}(0)
        status = GC.@preserve page abi_call_dictionary_node_edges(
            function_pointer, raw.context, UInt64(node), start_offset,
            pointer(page), length(page), written, reported_total)
        checked_status(status, :dictionary_edges)
        total = Int(reported_total[])
        count = Int(written[])
        count <= length(page) || throw(InteropError(STATUS_PROVIDER_ERROR, :dictionary_edges))
        append!(output, @view page[1:count])
        count == 0 && start_offset < total &&
            throw(InteropError(STATUS_PROVIDER_ERROR, :dictionary_edges))
        start_offset += count
    end
    output
end

function visit(dictionary::Dictionary, node::Integer;
    batch_size::Integer=RECOMMENDED_EDGE_BATCH)
    batch_size > 0 || throw(ArgumentError("batch_size must be positive"))
    pointer = query_interface(dictionary.resource, DICTIONARY_VISIT_INTERFACE_ID,
        DICTIONARY_VISIT_INTERFACE_VERSION)
    pointer === nothing && return (isfinal(dictionary, node), edges(dictionary, node;
        batch_size))
    table = unsafe_load(Ptr{VtDictionaryVisitVTable}(pointer))
    raw = raw_resource(dictionary.resource)
    output = VtDictionaryEdge[]
    finality = Ref{UInt8}(0)
    start_offset = 0
    total = typemax(Int)
    page = Vector{VtDictionaryEdge}(undef, batch_size)
    while start_offset < total
        written = Ref{Csize_t}(0)
        reported_total = Ref{Csize_t}(0)
        status = GC.@preserve page abi_call_dictionary_visit_node_visit(
            require_pointer(table.node_visit, :dictionary_visit), raw.context,
            UInt64(node), start_offset, finality, pointer(page), length(page),
            written, reported_total)
        checked_status(status, :dictionary_visit)
        total = Int(reported_total[])
        count = Int(written[])
        count <= length(page) || throw(InteropError(STATUS_PROVIDER_ERROR, :dictionary_visit))
        append!(output, @view page[1:count])
        count == 0 && start_offset < total &&
            throw(InteropError(STATUS_PROVIDER_ERROR, :dictionary_visit))
        start_offset += count
    end
    (finality[] != 0, output)
end

mutable struct DictionaryGraph
    resource::Resource
    view::VtDictionaryGraphView
    value_function::Ptr{Cvoid}
    closed::Bool
end

function graph(dictionary::Dictionary)
    pointer = query_interface(dictionary.resource, DICTIONARY_GRAPH_INTERFACE_ID,
        DICTIONARY_GRAPH_INTERFACE_VERSION)
    pointer === nothing && return nothing
    table = unsafe_load(Ptr{VtDictionaryGraphVTable}(pointer))
    raw = raw_resource(dictionary.resource)
    output = Ref(VtDictionaryGraphView(
        Ptr{VtDictionaryGraphNode}(C_NULL), 0,
        Ptr{VtDictionaryGraphEdge}(C_NULL), 0, 0, 0))
    status = abi_call_dictionary_graph_graph(
        require_pointer(table.graph, :dictionary_graph), raw.context, output)
    checked_status(status, :dictionary_graph)
    result = DictionaryGraph(retain(dictionary.resource), output[],
        table.node_value_u64, false)
    finalizer(finalize_close, result)
    result
end

function close!(graph::DictionaryGraph)
    graph.closed && return nothing
    graph.closed = true
    close!(graph.resource)
end

Base.close(graph::DictionaryGraph) = close!(graph)
Base.isopen(graph::DictionaryGraph) = !graph.closed

function graph_nodes(graph::DictionaryGraph)
    graph.closed && throw(InteropError(STATUS_CLOSED, :dictionary_graph))
    unsafe_wrap(Vector{VtDictionaryGraphNode}, graph.view.nodes,
        Int(graph.view.node_count); own=false)
end

function graph_edges(graph::DictionaryGraph)
    graph.closed && throw(InteropError(STATUS_CLOSED, :dictionary_graph))
    unsafe_wrap(Vector{VtDictionaryGraphEdge}, graph.view.edges,
        Int(graph.view.edge_count); own=false)
end

function value(graph::DictionaryGraph, cursor::Integer)
    graph.closed && throw(InteropError(STATUS_CLOSED, :dictionary_graph))
    output = Ref(VtOptionalU64(0, 0, ntuple(_ -> UInt8(0), 7)))
    raw = raw_resource(graph.resource)
    status = abi_call_dictionary_graph_node_value_u64(
        require_pointer(graph.value_function, :dictionary_graph_value), raw.context,
        UInt64(cursor), output)
    checked_status(status, :dictionary_graph_value)
    output[].has_value == 0 ? nothing : output[].value
end

function snapshot_identity(resource::Resource)
    pointer = query_interface(resource, SNAPSHOT_IDENTITY_INTERFACE_ID,
        SNAPSHOT_IDENTITY_INTERFACE_VERSION)
    pointer === nothing && return nothing
    table = unsafe_load(Ptr{VtSnapshotIdentityVTable}(pointer))
    output = Ref(SnapshotIdentity(0, 0))
    raw = raw_resource(resource)
    status = abi_call_snapshot_identity_identity(
        require_pointer(table.identity, :snapshot_identity), raw.context, output)
    checked_status(status, :snapshot_identity)
    output[]
end

snapshot_identity(dictionary::Dictionary) = snapshot_identity(dictionary.resource)

struct DictionaryEntry{U}
    units::Vector{U}
    value::Union{Nothing, UInt64}
end

mutable struct DictionaryEntries
    resource::Resource
    raw::VtDictionaryEntriesCursorRaw
    table::Ptr{VtDictionaryEntriesVTable}
    info::VtDictionaryEntriesInfo
    batch_active::Bool
    active_generation::UInt64
    closed::Bool
end

function entries(dictionary::Dictionary)
    pointer = query_interface(dictionary.resource, DICTIONARY_ENTRIES_INTERFACE_ID,
        DICTIONARY_ENTRIES_INTERFACE_VERSION)
    pointer === nothing && throw(InteropError(STATUS_UNSUPPORTED, :dictionary_entries))
    table_pointer = Ptr{VtDictionaryEntriesVTable}(pointer)
    table = unsafe_load(table_pointer)
    cursor = Ref(VtDictionaryEntriesCursorRaw(C_NULL, C_NULL))
    info = Ref(VtDictionaryEntriesInfo(0, 0, 0, 0, 0, 0,
        SnapshotIdentity(0, 0), (0, 0)))
    raw = raw_resource(dictionary.resource)
    status = abi_call_dictionary_entries_open(
        require_pointer(table.open, :dictionary_entries_open), raw.context,
        cursor, info)
    checked_status(status, :dictionary_entries_open)
    cursor[].context == C_NULL &&
        throw(InteropError(STATUS_NULL_POINTER, :dictionary_entries_open))
    result = DictionaryEntries(retain(dictionary.resource), cursor[], table_pointer,
        info[], false, 0, false)
    finalizer(finalize_close, result)
    result
end

unit_domain(cursor::DictionaryEntries) = UnitDomain(cursor.info.unit_domain)
value_domain(cursor::DictionaryEntries) = ValueDomain(cursor.info.value_domain)
entry_order(cursor::DictionaryEntries) = EntryOrder(cursor.info.order)
known_length(cursor::DictionaryEntries) =
    cursor.info.flags & ENTRIES_INFO_FLAG_EXACT_LEN == 0 ? nothing : Int(cursor.info.exact_len)
snapshot_identity(cursor::DictionaryEntries) =
    cursor.info.flags & ENTRIES_INFO_FLAG_SNAPSHOT_IDENTITY == 0 ? nothing : cursor.info.identity

function entries_table(cursor::DictionaryEntries)
    cursor.closed && throw(InteropError(STATUS_CLOSED, :dictionary_entries))
    unsafe_load(cursor.table)
end

function release!(cursor::DictionaryEntries, generation::Integer)
    cursor.closed && throw(InteropError(STATUS_CLOSED, :dictionary_entries_release))
    cursor.batch_active || throw(ArgumentError("no dictionary-entry batch is active"))
    table = entries_table(cursor)
    status = abi_call_dictionary_entries_release_batch(
        require_pointer(table.release_batch, :dictionary_entries_release),
        cursor.raw, UInt64(generation))
    checked_status(status, :dictionary_entries_release)
    cursor.batch_active = false
    cursor.active_generation = 0
    nothing
end

mutable struct EntryBatch
    cursor::DictionaryEntries
    view::VtDictionaryEntryBatchView
    released::Bool
end

function next_batch(cursor::DictionaryEntries, limits::BatchLimits=BatchLimits())
    cursor.batch_active && throw(InteropError(STATUS_BATCH_IN_USE,
        :dictionary_entries_next_batch))
    table = entries_table(cursor)
    output = Ref(VtDictionaryEntryBatchView(
        Ptr{VtDictionaryEntryRaw}(C_NULL), 0, C_NULL, 0,
        Ptr{UInt64}(C_NULL), 0, 0, 0))
    status = abi_call_dictionary_entries_next_batch(
        require_pointer(table.next_batch, :dictionary_entries_next_batch),
        cursor.raw, Ref(limits), output)
    checked_status(status, :dictionary_entries_next_batch; allow_end=true)
    Status(status) == STATUS_END && return nothing
    cursor.batch_active = true
    cursor.active_generation = output[].generation
    batch = EntryBatch(cursor, output[], false)
    finalizer(finalize_release, batch)
    batch
end

function release!(batch::EntryBatch)
    batch.released && return nothing
    batch.released = true
    release!(batch.cursor, batch.view.generation)
end

Base.close(batch::EntryBatch) = release!(batch)
Base.isopen(batch::EntryBatch) = !batch.released

function copied_entries(batch::EntryBatch)
    batch.released && throw(InteropError(STATUS_CLOSED, :dictionary_entry_batch))
    view = batch.view
    descriptors = unsafe_wrap(Vector{VtDictionaryEntryRaw}, view.entries,
        Int(view.entry_count); own=false)
    unit_type = if unit_domain(batch.cursor) == UNIT_BYTE
        UInt8
    elseif unit_domain(batch.cursor) == UNIT_UNICODE_SCALAR
        UInt32
    else
        UInt64
    end
    units = unsafe_wrap(Vector{unit_type}, Ptr{unit_type}(view.units),
        Int(view.unit_count); own=false)
    values = unsafe_wrap(Vector{UInt64}, view.values, Int(view.value_count); own=false)
    result = DictionaryEntry{unit_type}[]
    sizehint!(result, length(descriptors))
    for descriptor in descriptors
        unit_start = Int(descriptor.unit_offset) + 1
        unit_stop = unit_start + Int(descriptor.unit_len) - 1
        key = descriptor.unit_len == 0 ? unit_type[] : copy(@view units[unit_start:unit_stop])
        entry_value = if descriptor.value_len == 0
            nothing
        elseif descriptor.value_len == 1
            values[Int(descriptor.value_offset) + 1]
        else
            throw(InteropError(STATUS_PROVIDER_ERROR, :dictionary_entry_value))
        end
        push!(result, DictionaryEntry(key, entry_value))
    end
    result
end

function with_batch(f::F, cursor::DictionaryEntries,
    limits::BatchLimits=BatchLimits()) where {F}
    batch = next_batch(cursor, limits)
    batch === nothing && return nothing
    try
        f(batch)
    finally
        release!(batch)
    end
end

mutable struct ReducerContext
    callback::Any
    unit_domain::UnitDomain
    value_domain::ValueDomain
    failure::Any
end

function reducer_bridge(context_pointer::Ptr{Cvoid},
    view_pointer::Ptr{VtDictionaryEntryBatchView})::Cint
    context_pointer == C_NULL && return Cint(STATUS_NULL_POINTER)
    view_pointer == C_NULL && return Cint(STATUS_NULL_POINTER)
    context = unsafe_pointer_to_objref(context_pointer)::ReducerContext
    view = unsafe_load(view_pointer)
    fake_cursor = DictionaryEntries(Resource(VtResourceRaw(C_NULL,
        Ptr{VtResourceVTable}(C_NULL)), true, Any[]),
        VtDictionaryEntriesCursorRaw(C_NULL, C_NULL),
        Ptr{VtDictionaryEntriesVTable}(C_NULL),
        VtDictionaryEntriesInfo(UInt32(context.unit_domain),
            UInt32(context.value_domain), UInt32(ENTRY_LEXICOGRAPHIC), 0, 0, 0,
            SnapshotIdentity(0, 0), (0, 0)), true, 0, true)
    batch = EntryBatch(fake_cursor, view, false)
    try
        context.callback(copied_entries(batch))
        Cint(STATUS_OK)
    catch error
        context.failure = (error, catch_backtrace())
        Cint(STATUS_PROVIDER_ERROR)
    end
end

function reduce_entries(callback, cursor::DictionaryEntries,
    limits::BatchLimits=BatchLimits())
    cursor.batch_active && throw(InteropError(STATUS_BATCH_IN_USE,
        :dictionary_entries_reduce))
    table = entries_table(cursor)
    context = ReducerContext(callback, unit_domain(cursor), value_domain(cursor), nothing)
    count = Ref{Csize_t}(0)
    context_pointer = pointer_from_objref(context)
    reducer_pointer = @abi_cfunction_dictionary_entry_reducer(reducer_bridge)
    status = GC.@preserve context abi_call_dictionary_entries_reduce(
        require_pointer(table.reduce, :dictionary_entries_reduce), cursor.raw,
        Ref(limits), reducer_pointer, context_pointer, count)
    if context.failure !== nothing
        error, backtrace = context.failure
        throw(error)
    end
    checked_status(status, :dictionary_entries_reduce)
    Int(count[])
end

function cancel!(cursor::DictionaryEntries)
    table = entries_table(cursor)
    status = abi_call_dictionary_entries_cancel(
        require_pointer(table.cancel, :dictionary_entries_cancel), cursor.raw)
    checked_status(status, :dictionary_entries_cancel)
    nothing
end

function close!(cursor::DictionaryEntries)
    cursor.closed && return nothing
    if cursor.batch_active
        try
            release!(cursor, cursor.active_generation)
        catch
            # The close operation below is authoritative and must still run.
        end
    end
    table = unsafe_load(cursor.table)
    cursor.closed = true
    status = abi_call_dictionary_entries_close(
        require_pointer(table.close, :dictionary_entries_close), cursor.raw)
    cursor.raw = VtDictionaryEntriesCursorRaw(C_NULL, C_NULL)
    close!(cursor.resource)
    checked_status(status, :dictionary_entries_close)
    nothing
end

Base.close(cursor::DictionaryEntries) = close!(cursor)
Base.isopen(cursor::DictionaryEntries) = !cursor.closed

function Base.iterate(cursor::DictionaryEntries, state=(DictionaryEntry[], 1, false))
    buffer, index, finished = state
    while index > length(buffer)
        finished && return nothing
        batch = next_batch(cursor)
        batch === nothing && return nothing
        try
            buffer = copied_entries(batch)
        finally
            release!(batch)
        end
        index = 1
        finished = isempty(buffer)
    end
    (buffer[index], (buffer, index + 1, finished))
end

function dictionary_entry_key(dictionary::Dictionary, entry::DictionaryEntry)
    domain = unit_domain(dictionary)
    domain == UNIT_BYTE && return Vector{UInt8}(entry.units)
    domain == UNIT_UNICODE_SCALAR && return String(Char.(entry.units))
    domain == UNIT_U64 && return Vector{UInt64}(entry.units)
    throw(InteropError(STATUS_UNSUPPORTED, :dictionary_entry_key))
end

function dictionary_entry_value(dictionary::Dictionary, entry::DictionaryEntry)
    domain = value_domain(dictionary)
    domain == VALUE_UNIT && return nothing
    domain == VALUE_OPTIONAL_U64 && return entry.value
    throw(InteropError(STATUS_UNSUPPORTED, :dictionary_entry_value))
end

function Base.iterate(dictionary::Dictionary, state=nothing)
    cursor, cursor_state = if state === nothing
        (entries(dictionary), nothing)
    else
        state
    end
    result = cursor_state === nothing ? iterate(cursor) : iterate(cursor, cursor_state)
    if result === nothing
        close!(cursor)
        return nothing
    end
    entry, next_state = result
    pair = dictionary_entry_key(dictionary, entry) =>
        dictionary_entry_value(dictionary, entry)
    (pair, (cursor, next_state))
end

struct WfstStateInfo
    final::Bool
    final_weight::Float64
end

struct WfstArc
    input::Union{Nothing, UInt64}
    output::Union{Nothing, UInt64}
    target::UInt64
    weight::Float64
end

mutable struct Wfst
    resource::Resource
    table::Ptr{VtWfstVTable}
    closed::Bool
end

function wfstransducer(resource::Resource; take::Bool=false)
    owned = take ? resource : retain(resource)
    try
        pointer = query_interface(owned, WFST_INTERFACE_ID, WFST_INTERFACE_VERSION)
        pointer === nothing && throw(InteropError(STATUS_UNSUPPORTED, :wfst))
        table = Ptr{VtWfstVTable}(pointer)
        unsafe_load(table).interface_version >= WFST_INTERFACE_VERSION ||
            throw(InteropError(STATUS_UNSUPPORTED, :wfst_version))
        result = Wfst(owned, table, false)
        finalizer(finalize_close, result)
        result
    catch
        close!(owned)
        rethrow()
    end
end

wfstransducer(raw::VtResourceRaw) = wfstransducer(adopt_resource(raw); take=true)

function wfst_table(wfst::Wfst)
    wfst.closed && throw(InteropError(STATUS_CLOSED, :wfst))
    unsafe_load(wfst.table)
end

unit_domain(wfst::Wfst) = UnitDomain(wfst_table(wfst).unit_domain)
weight_domain(wfst::Wfst) = WeightDomain(wfst_table(wfst).weight_domain)
flags(wfst::Wfst) = wfst_table(wfst).flags

function close!(wfst::Wfst)
    wfst.closed && return nothing
    wfst.closed = true
    close!(wfst.resource)
end

Base.close(wfst::Wfst) = close!(wfst)
Base.isopen(wfst::Wfst) = !wfst.closed

function snapshot(wfst::Wfst)
    raw = raw_resource(wfst.resource)
    table = wfst_table(wfst)
    output = Ref(VtResourceRaw(C_NULL, Ptr{VtResourceVTable}(C_NULL)))
    status = abi_call_wfst_snapshot(
        require_pointer(table.snapshot, :wfst_snapshot), raw.context, output)
    checked_status(status, :wfst_snapshot)
    wfstransducer(output[])
end

function start(wfst::Wfst)
    raw = raw_resource(wfst.resource)
    table = wfst_table(wfst)
    output = Ref{UInt64}(0)
    status = abi_call_wfst_start(
        require_pointer(table.start, :wfst_start), raw.context, output)
    checked_status(status, :wfst_start)
    output[]
end

function state_count(wfst::Wfst)
    raw = raw_resource(wfst.resource)
    table = wfst_table(wfst)
    output = Ref{Csize_t}(0)
    known = Ref{UInt8}(0)
    status = abi_call_wfst_num_states(
        require_pointer(table.num_states, :wfst_num_states), raw.context,
        output, known)
    checked_status(status, :wfst_num_states)
    known[] == 0 ? nothing : Int(output[])
end

function state_info(wfst::Wfst, state::Integer)
    raw = raw_resource(wfst.resource)
    table = wfst_table(wfst)
    valid = Ref{UInt8}(0)
    finality = Ref{UInt8}(0)
    weight = Ref{Float64}(0)
    status = abi_call_wfst_state_info(
        require_pointer(table.state_info, :wfst_state_info), raw.context,
        UInt64(state), valid, finality, weight)
    checked_status(status, :wfst_state_info)
    valid[] == 0 ? nothing : WfstStateInfo(finality[] != 0, weight[])
end

function arcs(wfst::Wfst, state::Integer;
    batch_size::Integer=RECOMMENDED_ARC_BATCH)
    batch_size > 0 || throw(ArgumentError("batch_size must be positive"))
    raw = raw_resource(wfst.resource)
    table = wfst_table(wfst)
    function_pointer = require_pointer(table.state_arcs, :wfst_arcs)
    output = WfstArc[]
    start_offset = 0
    total = typemax(Int)
    page = Vector{VtWfstArc}(undef, batch_size)
    while start_offset < total
        written = Ref{Csize_t}(0)
        reported_total = Ref{Csize_t}(0)
        status = GC.@preserve page abi_call_wfst_state_arcs(
            function_pointer, raw.context, UInt64(state), start_offset,
            pointer(page), length(page), written, reported_total)
        checked_status(status, :wfst_arcs)
        total = Int(reported_total[])
        count = Int(written[])
        count <= length(page) || throw(InteropError(STATUS_PROVIDER_ERROR, :wfst_arcs))
        for arc in @view page[1:count]
            push!(output, WfstArc(arc.has_input == 0 ? nothing : arc.input_label,
                arc.has_output == 0 ? nothing : arc.output_label,
                arc.target_state, arc.weight))
        end
        count == 0 && start_offset < total &&
            throw(InteropError(STATUS_PROVIDER_ERROR, :wfst_arcs))
        start_offset += count
    end
    output
end

mutable struct LatticeValue
    resource::Resource
    table::Ptr{VtLatticeVTable}
    closed::Bool
end

function lattice_value(resource::Resource; take::Bool=false)
    owned = take ? resource : retain(resource)
    try
        pointer = query_interface(owned, LATTICE_INTERFACE_ID,
            LATTICE_INTERFACE_VERSION)
        pointer === nothing && throw(InteropError(STATUS_UNSUPPORTED,
            :lattice_value))
        table = Ptr{VtLatticeVTable}(pointer)
        value = unsafe_load(table)
        value.interface_version >= LATTICE_INTERFACE_VERSION ||
            throw(InteropError(STATUS_UNSUPPORTED, :lattice_version))
        value.reserved == 0 ||
            throw(InteropError(STATUS_PROVIDER_ERROR, :lattice_reserved))
        result = LatticeValue(owned, table, false)
        finalizer(finalize_close, result)
        result
    catch
        close!(owned)
        rethrow()
    end
end

lattice_value(raw::VtResourceRaw) = lattice_value(adopt_resource(raw); take=true)

function lattice_table(value::LatticeValue)
    value.closed && throw(InteropError(STATUS_CLOSED, :lattice_value))
    unsafe_load(value.table)
end

domain_id(value::LatticeValue) = lattice_table(value).domain_id
flags(value::LatticeValue) = lattice_table(value).flags

function close!(value::LatticeValue)
    value.closed && return nothing
    value.closed = true
    close!(value.resource)
end

Base.close(value::LatticeValue) = close!(value)
Base.isopen(value::LatticeValue) = !value.closed

function retain(value::LatticeValue)
    lattice_value(retain(value.resource); take=true)
end

function require_same_domain(left::LatticeValue, right::LatticeValue,
    operation::Symbol)
    domain_id(left) == domain_id(right) ||
        throw(InteropError(STATUS_INVALID_ARGUMENT, operation))
    nothing
end

function lattice_binary(left::LatticeValue, right::LatticeValue,
    operation::Symbol)
    require_same_domain(left, right, operation)
    left_raw = raw_resource(left.resource)
    right_raw = Ref(raw_resource(right.resource))
    output = Ref(VtResourceRaw(C_NULL, Ptr{VtResourceVTable}(C_NULL)))
    table = lattice_table(left)
    function_pointer = operation == :lattice_join ? table.join : table.meet
    address = require_pointer(function_pointer, operation)
    status = operation == :lattice_join ?
        abi_call_lattice_join(address, left_raw.context, right_raw, output) :
        abi_call_lattice_meet(address, left_raw.context, right_raw, output)
    checked_status(status, operation)
    lattice_value(output[])
end

lattice_join(left::LatticeValue, right::LatticeValue) =
    lattice_binary(left, right, :lattice_join)
lattice_meet(left::LatticeValue, right::LatticeValue) =
    lattice_binary(left, right, :lattice_meet)

function equivalent(left::LatticeValue, right::LatticeValue)
    require_same_domain(left, right, :lattice_equal)
    left_raw = raw_resource(left.resource)
    right_raw = Ref(raw_resource(right.resource))
    output = Ref{UInt8}(0)
    status = abi_call_lattice_equal(
        require_pointer(lattice_table(left).equal, :lattice_equal),
        left_raw.context, right_raw, output)
    checked_status(status, :lattice_equal)
    output[] <= 1 || throw(InteropError(STATUS_PROVIDER_ERROR,
        :lattice_equal))
    output[] == 1
end

function read_lattice_bytes(value::LatticeValue, field::Symbol,
    operation::Symbol)
    raw = raw_resource(value.resource)
    table = lattice_table(value)
    function_pointer = getfield(table, field)
    function_pointer == C_NULL && return nothing
    written = Ref{Csize_t}(0)
    required = Ref{Csize_t}(0)
    call = field == :stable_bytes ? abi_call_lattice_stable_bytes :
        abi_call_lattice_diagnostic
    status = call(function_pointer, raw.context, Ptr{UInt8}(C_NULL), 0,
        written, required)
    checked_status(status, operation)
    written[] == 0 || throw(InteropError(STATUS_PROVIDER_ERROR, operation))
    output = Vector{UInt8}(undef, Int(required[]))
    written[] = 0
    second_required = Ref{Csize_t}(0)
    status = GC.@preserve output call(function_pointer, raw.context,
        isempty(output) ? Ptr{UInt8}(C_NULL) : pointer(output), length(output),
        written, second_required)
    checked_status(status, operation)
    second_required[] == required[] ||
        throw(InteropError(STATUS_PROVIDER_ERROR, operation))
    written[] == required[] ||
        throw(InteropError(STATUS_PROVIDER_ERROR, operation))
    output
end

function stable_bytes(value::LatticeValue)
    lattice_table(value).flags & LATTICE_FLAG_STABLE_BYTES != 0 ||
        throw(InteropError(STATUS_UNSUPPORTED, :lattice_stable_bytes))
    result = read_lattice_bytes(value, :stable_bytes, :lattice_stable_bytes)
    result === nothing && throw(InteropError(STATUS_UNSUPPORTED,
        :lattice_stable_bytes))
    result
end

function diagnostic(value::LatticeValue)
    bytes = read_lattice_bytes(value, :diagnostic, :lattice_diagnostic)
    bytes === nothing ? nothing : String(bytes)
end

function lattice_many(value::LatticeValue, others,
    operation::Symbol)
    operands = collect(others)
    all(item -> item isa LatticeValue, operands) ||
        throw(ArgumentError("all lattice operands must be LatticeValue objects"))
    for item in operands
        require_same_domain(value, item, operation)
    end
    isempty(operands) && return retain(value)
    table = lattice_table(value)
    function_pointer = operation == :lattice_join_many ? table.join_many :
        table.meet_many
    supports_batch = table.flags & LATTICE_FLAG_BATCH != 0 &&
        function_pointer != C_NULL
    if !supports_batch
        result = retain(value)
        try
            for item in operands
                next = operation == :lattice_join_many ? lattice_join(result, item) :
                    lattice_meet(result, item)
                close!(result)
                result = next
            end
            return result
        catch
            close!(result)
            rethrow()
        end
    end
    raw = raw_resource(value.resource)
    raw_operands = VtResourceRaw[raw_resource(item.resource) for item in operands]
    output = Ref(VtResourceRaw(C_NULL, Ptr{VtResourceVTable}(C_NULL)))
    address = require_pointer(function_pointer, operation)
    status = GC.@preserve operands raw_operands begin
        operation == :lattice_join_many ?
            abi_call_lattice_join_many(address, raw.context,
                pointer(raw_operands), length(raw_operands), output) :
            abi_call_lattice_meet_many(address, raw.context,
                pointer(raw_operands), length(raw_operands), output)
    end
    checked_status(status, operation)
    lattice_value(output[])
end

join_many(value::LatticeValue, others) =
    lattice_many(value, others, :lattice_join_many)
meet_many(value::LatticeValue, others) =
    lattice_many(value, others, :lattice_meet_many)

@doc "The stable resource ABI version understood by this package." ABI_VERSION
@doc "The minimum dictionary interface version used by `dictionary`." DICTIONARY_INTERFACE_VERSION
@doc "The minimum fused dictionary-visit interface version." DICTIONARY_VISIT_INTERFACE_VERSION
@doc "The minimum immutable dictionary-graph interface version." DICTIONARY_GRAPH_INTERFACE_VERSION
@doc "The minimum bounded dictionary-entry stream interface version." DICTIONARY_ENTRIES_INTERFACE_VERSION
@doc "The minimum snapshot-identity interface version." SNAPSHOT_IDENTITY_INTERFACE_VERSION
@doc "The minimum scalar weighted finite-state transducer interface version." WFST_INTERFACE_VERSION
@doc "The minimum immutable lattice-value interface version." LATTICE_INTERFACE_VERSION
@doc "The minimum dynamic-semiring base interface version." SEMIRING_INTERFACE_VERSION
@doc "The minimum optional dynamic-semiring division interface version." SEMIRING_DIVISION_INTERFACE_VERSION
@doc "The minimum optional dynamic-semiring Kleene-star interface version." SEMIRING_STAR_INTERFACE_VERSION
@doc "The minimum optional dynamic-semiring numerical interface version." SEMIRING_NUMERIC_INTERFACE_VERSION
@doc "The minimum optional dynamic-semiring property interface version." SEMIRING_PROPERTIES_INTERFACE_VERSION

@doc """
    Status

Portable result codes returned by every fallible C ABI operation. Public wrappers
translate every non-success code into `InteropError`; `STATUS_END` is handled by
bounded cursors and explicitly partial semiring operations, and
`STATUS_UNSUPPORTED` only by optional interface queries.
""" Status

@doc "The token representation used by a dictionary or scalar WFST." UnitDomain
@doc "The value representation attached to final dictionary nodes." ValueDomain
@doc "The portable scalar weight algebra used by a WFST." WeightDomain
@doc "The ordering guaranteed by a finite dictionary-entry cursor." EntryOrder
@doc "Provider promises safe parallel reentrant dictionary calls." DICTIONARY_FLAG_PARALLEL_REENTRANT
@doc "Dictionary node identifiers encode suffix-oriented structure." DICTIONARY_FLAG_SUFFIX_BASED
@doc "Dictionary resource and all exposed graph slices are immutable." DICTIONARY_FLAG_IMMUTABLE
@doc "Entry metadata contains an exact finite cardinality." ENTRIES_INFO_FLAG_EXACT_LEN
@doc "Entry metadata contains a process-local snapshot identity." ENTRIES_INFO_FLAG_SNAPSHOT_IDENTITY
@doc "Provider promises safe parallel reentrant WFST calls." WFST_FLAG_PARALLEL_REENTRANT
@doc "WFST resource is immutable for its retained lifetime." WFST_FLAG_IMMUTABLE
@doc "WFST states or arcs may be expanded lazily." WFST_FLAG_LAZY
@doc "WFST graph is acyclic." WFST_FLAG_ACYCLIC
@doc "Lattice callbacks must remain on the caller's runtime-attached thread." LATTICE_FLAG_THREAD_BOUND
@doc "Lattice callbacks are safe for concurrent and reentrant invocation." LATTICE_FLAG_PARALLEL_REENTRANT
@doc "Lattice values provide a canonical stable byte encoding." LATTICE_FLAG_STABLE_BYTES
@doc "Lattice values provide bounded batch join and meet callbacks." LATTICE_FLAG_BATCH
@doc "Semiring callbacks must remain on the caller's runtime-attached thread." SEMIRING_FLAG_THREAD_BOUND
@doc "Semiring callbacks are safe for concurrent and reentrant invocation." SEMIRING_FLAG_PARALLEL_REENTRANT
@doc "Semiring values provide a canonical stable byte encoding." SEMIRING_FLAG_STABLE_BYTES
@doc "Semiring values provide bounded addition and multiplication folds." SEMIRING_FLAG_BATCH
@doc "Semiring tokens support exact equality and canonical hash bytes." SEMIRING_PROPERTY_HASHABLE
@doc "Semiring addition is idempotent: `a ⊕ a = a`." SEMIRING_PROPERTY_IDEMPOTENT_PLUS
@doc "Semiring closure converges within a uniform bound when one is reported." SEMIRING_PROPERTY_K_CLOSED
@doc "A semiring sum is zero only when each operand is zero." SEMIRING_PROPERTY_ZERO_SUM_FREE
@doc "Semiring multiplication is commutative." SEMIRING_PROPERTY_COMMUTATIVE_TIMES
@doc "The semiring natural order is total." SEMIRING_PROPERTY_TOTALLY_ORDERED
@doc "Every semiring weight is nonnegative in the provider's interpretation." SEMIRING_PROPERTY_NONNEGATIVE
@doc "The left operand is better than the right operand in natural order." SEMIRING_ORDER_BETTER
@doc "The operands are equal in natural order." SEMIRING_ORDER_EQUAL
@doc "The left operand is worse than the right operand in natural order." SEMIRING_ORDER_WORSE
@doc "The natural order does not compare this operand pair." SEMIRING_ORDER_INCOMPARABLE
@doc "Stable identifier for the dictionary interface." DICTIONARY_INTERFACE_ID
@doc "Stable identifier for the fused dictionary-visit interface." DICTIONARY_VISIT_INTERFACE_ID
@doc "Stable identifier for the compact immutable dictionary-graph interface." DICTIONARY_GRAPH_INTERFACE_ID
@doc "Stable identifier for the bounded dictionary-entry stream interface." DICTIONARY_ENTRIES_INTERFACE_ID
@doc "Stable identifier for process-local snapshot identity." SNAPSHOT_IDENTITY_INTERFACE_ID
@doc "Stable identifier for the scalar WFST interface." WFST_INTERFACE_ID
@doc "Stable identifier for the immutable lattice-value interface." LATTICE_INTERFACE_ID
@doc "Stable identifier for the dynamic-semiring base interface." SEMIRING_INTERFACE_ID
@doc "Stable identifier for optional semiring division." SEMIRING_DIVISION_INTERFACE_ID
@doc "Stable identifier for optional semiring Kleene closure." SEMIRING_STAR_INTERFACE_ID
@doc "Stable identifier for optional semiring numerical projections." SEMIRING_NUMERIC_INTERFACE_ID
@doc "Stable identifier for declared semiring laws." SEMIRING_PROPERTIES_INTERFACE_ID
@doc "Sixteen-byte interface identifier passed to resource interface discovery." VtInterfaceId
@doc "Raw resource ownership and interface-discovery function table." VtResourceVTable
@doc "Raw two-word owned resource handle." VtResourceRaw
@doc "ABI representation of an optional unsigned 64-bit integer." VtOptionalU64
@doc "One labeled dictionary edge and its snapshot-local target node." VtDictionaryEdge
@doc "Raw dictionary graph traversal function table." VtDictionaryVTable
@doc "Raw fused finality-and-edge visit function table." VtDictionaryVisitVTable
@doc "One immutable compact-graph node descriptor." VtDictionaryGraphNode
@doc "One immutable compact-graph edge descriptor." VtDictionaryGraphEdge
@doc "Borrowed immutable compact-graph slices retained by a snapshot." VtDictionaryGraphView
@doc "Raw immutable compact-graph function table." VtDictionaryGraphVTable
@doc "Raw snapshot producer/revision identity function table." VtSnapshotIdentityVTable
@doc "One descriptor into a dictionary-entry batch's unit and value arenas." VtDictionaryEntryRaw
@doc "Raw cursor-owned bounded entry-batch lease." VtDictionaryEntryBatchView
@doc "Raw immutable metadata captured when an entry cursor opens." VtDictionaryEntriesInfo
@doc "Raw two-word move-only entry cursor handle." VtDictionaryEntriesCursorRaw
@doc "Raw bounded dictionary-entry cursor function table." VtDictionaryEntriesVTable
@doc "Raw scalar WFST arc representation." VtWfstArc
@doc "Raw scalar WFST traversal function table." VtWfstVTable
@doc "Raw immutable lattice-value operation function table." VtLatticeVTable
@doc "Compact provider-scoped dynamic-semiring value token." VtSemiringValue
@doc "Raw dynamic-semiring base operation function table." VtSemiringVTable
@doc "Raw optional semiring division function table." VtSemiringDivisionVTable
@doc "Raw optional semiring Kleene-star function table." VtSemiringStarVTable
@doc "Raw optional semiring numerical-projection function table." VtSemiringNumericVTable
@doc "Raw optional semiring law and closure-bound function table." VtSemiringPropertiesVTable

@doc """
    InteropError(status, operation)

Exception raised when an ABI operation fails. `status` preserves the portable
provider result and `operation` names the Julia operation that observed it.
""" InteropError

@doc """
    Resource

Owned, retained handle to a versioned native resource. Call `close` deterministically;
a finalizer is only a leak-safety fallback. Use `retain` before handing ownership to
an independently lived wrapper.
""" Resource

@doc """
    adopt_resource(raw; anchors=[])

Adopt exactly one existing native reference without retaining it. `anchors` keeps
Julia callback or storage objects alive for the complete native ownership interval.
""" adopt_resource

@doc "Return an independently owned reference to `resource`." retain
@doc "Retain a borrowed raw provider handle and return one independently owned resource." borrow_resource
@doc "Return the open raw two-word resource handle, or throw after closure." raw_resource
@doc """
    query_interface(resource, id, minimum_version=1)

Return the requested interface vtable pointer, or `nothing` when the provider does
not implement the requested version. The pointer remains valid only while the
resource is retained.
""" query_interface

@doc "Run a callback with a temporary retained resource and close it on every exit." with_resource
@doc "Deterministically release an owned resource, cursor, batch, graph, dictionary, or WFST." close!

@doc """
    Dictionary{K,V} <: AbstractDict{K,V}

Snapshot-capable dictionary graph backed by a retained resource. It implements
`AbstractDict`: Unicode-scalar dictionaries use `String` keys, byte dictionaries
use `Vector{UInt8}`, and vocabulary dictionaries use `Vector{UInt64}`.
""" Dictionary

@doc "Open the dictionary interface of a resource; `take=true` transfers ownership." dictionary
@doc "Capture an independently retained immutable dictionary or WFST snapshot." snapshot
@doc "Return an exact length/state count when the provider knows it, otherwise `nothing`." known_length
@doc "Return the unit domain declared by a dictionary, entry stream, or WFST." unit_domain
@doc "Return the value domain declared by a dictionary or entry stream." value_domain
@doc "Return the scalar weight domain declared by a WFST." weight_domain
@doc "Return the immutable capability flags declared by a dictionary or WFST." flags
@doc "Return the snapshot-local root dictionary node." root
@doc "Test whether a snapshot-local dictionary node is final." isfinal
@doc "Read the optional unsigned value attached to a final node or graph cursor." value
@doc "Follow one dictionary transition, returning `nothing` when it is absent." transition
@doc "Copy every outgoing edge through bounded provider pages." edges
@doc "Read finality and outgoing edges through the fused visit interface when available." visit

@doc """
    DictionaryGraph

Retained zero-copy view of an immutable compact dictionary graph. Node and edge
slices are borrowed from the snapshot and remain valid until this graph is closed.
""" DictionaryGraph

@doc "Open the optional immutable compact graph, or return `nothing`." graph
@doc "Return the zero-copy compact-graph node slice retained by a `DictionaryGraph`." graph_nodes
@doc "Return the zero-copy compact-graph edge slice retained by a `DictionaryGraph`." graph_edges
@doc "Return the optional process-local producer/revision identity." snapshot_identity

@doc "Hard upper bounds for one dictionary-entry batch." BatchLimits
@doc "Immutable process-local producer/revision pair." SnapshotIdentity
@doc "One copied dictionary entry with domain-typed units and an optional u64 value." DictionaryEntry
@doc "Active cursor-owned entry batch lease; use `release!` or `with_batch`." EntryBatch

@doc """
    DictionaryEntries

Move-only, bounded, lexicographic entry stream that owns a retained dictionary
snapshot. It is iterable; each yielded entry is copied before its native batch
lease is released.
""" DictionaryEntries

@doc "Open the optional finite dictionary-entry stream." entries
@doc "Acquire one bounded batch lease, or return `nothing` at end of stream." next_batch
@doc "Copy the entries in an active batch into Julia-owned domain-typed values." copied_entries
@doc "Release an entry batch lease. Releasing an already released batch is idempotent." release!
@doc "Run a callback with one acquired batch and release it on every exit." with_batch
@doc "Cancel the remaining work of an open entry cursor." cancel!
@doc """
    reduce_entries(callback, cursor, limits=BatchLimits())

Run the provider's fused reducer and return its exact processed count. Julia
exceptions are caught inside the C callback, converted to provider failure, and
re-thrown after native control returns; the callback must run on a Julia-owned
calling thread.
""" reduce_entries

@doc """
    Wfst

Retained scalar weighted finite-state transducer (WFST) resource with bounded arc
paging and snapshot-local state identifiers.
""" Wfst
@doc "Finality and final weight returned for one valid WFST state." WfstStateInfo
@doc "One copied WFST arc with optional input/output labels." WfstArc

@doc "Open the scalar WFST interface; `take=true` transfers resource ownership." wfstransducer
@doc "Return the snapshot-local start state." start
@doc "Return the known number of WFST states, or `nothing` for a lazy graph." state_count
@doc "Return finality and final weight, or `nothing` for an invalid state." state_info
@doc "Copy every outgoing WFST arc through bounded provider pages." arcs

@doc """
    LatticeValue

Owned immutable lattice element backed by a versioned resource. Binary and
batched operations return independently owned values. Call `close`
deterministically; the finalizer is a leak-safety fallback.
""" LatticeValue
@doc "Open the immutable lattice-value interface; `take=true` transfers ownership." lattice_value
@doc "Return the stable 16-byte lattice domain identifier." domain_id
@doc "Return the least upper bound of two same-domain lattice values." lattice_join
@doc "Return the greatest lower bound of two same-domain lattice values." lattice_meet
@doc "Compare two same-domain lattice values using the provider's equality relation." equivalent
@doc "Copy a lattice value's canonical stable encoding." stable_bytes
@doc "Return the provider's most recent advisory UTF-8 diagnostic, when supported." diagnostic
@doc "Join a value with a collection using one batch callback when available." join_many
@doc "Meet a value with a collection using one batch callback when available." meet_many

end # module VinaryTreeInterop
