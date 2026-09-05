using Test
using VinaryTreeInterop
using Libdl

const VTI = VinaryTreeInterop

mutable struct MockDictionaryState
    references::Int
    releases::Int
end

const MOCK_STATE = MockDictionaryState(1, 0)
const MOCK_DICTIONARY_TABLE = Ref{VTI.VtDictionaryVTable}()
const MOCK_RESOURCE_TABLE = Ref{VTI.VtResourceVTable}()

function mock_state(context::Ptr{Cvoid})
    unsafe_pointer_to_objref(context)::MockDictionaryState
end

function mock_retain(context::Ptr{Cvoid})::Cvoid
    mock_state(context).references += 1
    nothing
end

function mock_release(context::Ptr{Cvoid})::Cvoid
    state = mock_state(context)
    state.references -= 1
    state.releases += 1
    nothing
end

function mock_query(context::Ptr{Cvoid}, id_pointer::Ptr{VTI.VtInterfaceId},
    minimum_version::UInt32, output::Ptr{Ptr{Cvoid}})::Cint
    id = unsafe_load(id_pointer)
    if id == VTI.DICTIONARY_INTERFACE_ID &&
        minimum_version <= VTI.DICTIONARY_INTERFACE_VERSION
        unsafe_store!(output, Ptr{Cvoid}(Base.unsafe_convert(
            Ptr{VTI.VtDictionaryVTable}, MOCK_DICTIONARY_TABLE)))
        return Cint(VTI.STATUS_OK)
    end
    unsafe_store!(output, C_NULL)
    Cint(VTI.STATUS_UNSUPPORTED)
end

function mock_snapshot(context::Ptr{Cvoid}, output::Ptr{VTI.VtResourceRaw})::Cint
    mock_retain(context)
    unsafe_store!(output, VTI.VtResourceRaw(context,
        Base.unsafe_convert(Ptr{VTI.VtResourceVTable}, MOCK_RESOURCE_TABLE)))
    Cint(VTI.STATUS_OK)
end

function mock_root(::Ptr{Cvoid}, output::Ptr{UInt64})::Cint
    unsafe_store!(output, 0)
    Cint(VTI.STATUS_OK)
end

function mock_len(::Ptr{Cvoid}, output::Ptr{Csize_t}, known::Ptr{UInt8})::Cint
    unsafe_store!(output, 2)
    unsafe_store!(known, 1)
    Cint(VTI.STATUS_OK)
end

function mock_isfinal(::Ptr{Cvoid}, node::UInt64, output::Ptr{UInt8})::Cint
    unsafe_store!(output, node in (1, 2))
    Cint(VTI.STATUS_OK)
end

function mock_value(::Ptr{Cvoid}, node::UInt64,
    output::Ptr{VTI.VtOptionalU64})::Cint
    unsafe_store!(output, VTI.VtOptionalU64(node * 10, node in (1, 2),
        ntuple(_ -> UInt8(0), 7)))
    Cint(VTI.STATUS_OK)
end

function mock_transition(::Ptr{Cvoid}, node::UInt64, label::UInt64,
    child::Ptr{UInt64}, found::Ptr{UInt8})::Cint
    target = node == 0 && label == UInt64('a') ? 1 :
        node == 0 && label == UInt64('b') ? 2 : 0
    unsafe_store!(child, target)
    unsafe_store!(found, target != 0)
    Cint(VTI.STATUS_OK)
end

const MOCK_EDGES = [
    VTI.VtDictionaryEdge(UInt64('a'), 1),
    VTI.VtDictionaryEdge(UInt64('b'), 2),
]

function mock_edges(::Ptr{Cvoid}, node::UInt64, start::Csize_t,
    output::Ptr{VTI.VtDictionaryEdge}, capacity::Csize_t,
    written::Ptr{Csize_t}, total::Ptr{Csize_t})::Cint
    available = node == 0 ? MOCK_EDGES : VTI.VtDictionaryEdge[]
    first = min(Int(start) + 1, length(available) + 1)
    count = min(Int(capacity), length(available) - first + 1)
    for index in 1:count
        unsafe_store!(output, available[first + index - 1], index)
    end
    unsafe_store!(written, count)
    unsafe_store!(total, length(available))
    Cint(VTI.STATUS_OK)
end

const MOCK_RETAIN = @cfunction(mock_retain, Cvoid, (Ptr{Cvoid},))
const MOCK_RELEASE = @cfunction(mock_release, Cvoid, (Ptr{Cvoid},))
const MOCK_QUERY = @cfunction(mock_query, Cint,
    (Ptr{Cvoid}, Ptr{VTI.VtInterfaceId}, UInt32, Ptr{Ptr{Cvoid}}))
const MOCK_SNAPSHOT = @cfunction(mock_snapshot, Cint,
    (Ptr{Cvoid}, Ptr{VTI.VtResourceRaw}))
const MOCK_ROOT = @cfunction(mock_root, Cint, (Ptr{Cvoid}, Ptr{UInt64}))
const MOCK_LEN = @cfunction(mock_len, Cint,
    (Ptr{Cvoid}, Ptr{Csize_t}, Ptr{UInt8}))
const MOCK_ISFINAL = @cfunction(mock_isfinal, Cint,
    (Ptr{Cvoid}, UInt64, Ptr{UInt8}))
const MOCK_VALUE = @cfunction(mock_value, Cint,
    (Ptr{Cvoid}, UInt64, Ptr{VTI.VtOptionalU64}))
const MOCK_TRANSITION = @cfunction(mock_transition, Cint,
    (Ptr{Cvoid}, UInt64, UInt64, Ptr{UInt64}, Ptr{UInt8}))
const MOCK_EDGES_FUNCTION = @cfunction(mock_edges, Cint,
    (Ptr{Cvoid}, UInt64, Csize_t, Ptr{VTI.VtDictionaryEdge}, Csize_t,
        Ptr{Csize_t}, Ptr{Csize_t}))

MOCK_DICTIONARY_TABLE[] = VTI.VtDictionaryVTable(
    sizeof(VTI.VtDictionaryVTable), VTI.DICTIONARY_INTERFACE_VERSION,
    UInt32(VTI.UNIT_UNICODE_SCALAR), UInt32(VTI.VALUE_OPTIONAL_U64),
    VTI.DICTIONARY_FLAG_IMMUTABLE, MOCK_SNAPSHOT, MOCK_ROOT, MOCK_LEN,
    MOCK_ISFINAL, MOCK_VALUE, MOCK_TRANSITION, MOCK_EDGES_FUNCTION)

MOCK_RESOURCE_TABLE[] = VTI.VtResourceVTable(
    sizeof(VTI.VtResourceVTable), VTI.ABI_VERSION, 0,
    MOCK_RETAIN, MOCK_RELEASE, MOCK_QUERY)

function mock_resource()
    raw = VTI.VtResourceRaw(pointer_from_objref(MOCK_STATE),
        Base.unsafe_convert(Ptr{VTI.VtResourceVTable}, MOCK_RESOURCE_TABLE))
    VTI.adopt_resource(raw; anchors=[MOCK_STATE, MOCK_RESOURCE_TABLE,
        MOCK_DICTIONARY_TABLE])
end

@testset "ABI layouts" begin
    @test sizeof(VTI.VtResourceRaw) == 2sizeof(Ptr{Cvoid})
    @test sizeof(VTI.VtInterfaceId) == 16
    @test sizeof(VTI.VtOptionalU64) == 16
    @test sizeof(VTI.VtDictionaryEdge) == 16
    @test sizeof(VTI.VtDictionaryEntriesCursorRaw) == 2sizeof(Ptr{Cvoid})
    @test sizeof(VTI.VtSemiringValue) == 16
end

@testset "generated ABI inventory" begin
    @test length(VTI.ABI_STRUCT_NAMES) == VTI.ABI_STRUCT_COUNT
    @test length(unique(VTI.ABI_STRUCT_NAMES)) == VTI.ABI_STRUCT_COUNT
    @test all(name -> isdefined(VTI, name) && getfield(VTI, name) isa DataType,
        VTI.ABI_STRUCT_NAMES)
    @test length(VTI.ABI_CALLABLES) == VTI.ABI_CALLABLE_COUNT
    @test all(callable -> isdefined(VTI, callable.julia_name),
        VTI.ABI_CALLABLES)
    @test count(callable -> callable.kind == :operation,
        VTI.ABI_CALLABLES) == VTI.ABI_OPERATION_COUNT
    @test count(callable -> callable.kind == :callback,
        VTI.ABI_CALLABLES) == VTI.ABI_CALLBACK_COUNT
    @test all(callable -> !isempty(callable.signature), VTI.ABI_CALLABLES)
    @test all(callable -> !isempty(callable.parameter_contract),
        VTI.ABI_CALLABLES)
    @test any(callable -> callable.name == :query_interface &&
        callable.capability == :resource, VTI.ABI_CALLABLES)
    @test any(callable -> callable.name == :reduce &&
        callable.capability == Symbol("dictionary-entries"),
        VTI.ABI_CALLABLES)
    @test any(callable -> callable.name == :VtDictionaryEntryReducer &&
        callable.threading == :julia_owned_calling_thread_only,
        VTI.ABI_CALLABLES)
end

@testset "exported API documentation" begin
    exported = filter(name -> Base.isexported(VTI, name) && name != nameof(VTI),
        names(VTI; all=true))
    documented = Set(keys(Base.Docs.meta(VTI)))
    undocumented = filter(exported) do name
        !(Base.Docs.Binding(VTI, name) in documented)
    end
    @test isempty(undocumented)
end

@testset "owned resource and dictionary traversal" begin
    MOCK_STATE.references = 1
    MOCK_STATE.releases = 0
    resource = mock_resource()
    borrowed = VTI.borrow_resource(VTI.raw_resource(resource))
    @test MOCK_STATE.references == 2
    close(borrowed)
    @test MOCK_STATE.references == 1
    retained = VTI.retain(resource)
    @test MOCK_STATE.references == 2
    close(retained)
    @test MOCK_STATE.references == 1

    dictionary = VTI.dictionary(resource; take=true)
    @test VTI.unit_domain(dictionary) == VTI.UNIT_UNICODE_SCALAR
    @test VTI.value_domain(dictionary) == VTI.VALUE_OPTIONAL_U64
    @test length(dictionary) == 2
    @test VTI.root(dictionary) == 0
    @test !VTI.isfinal(dictionary, 0)
    @test VTI.isfinal(dictionary, 1)
    @test VTI.value(dictionary, 1) == 10
    @test VTI.value(dictionary, 0) === nothing
    @test VTI.transition(dictionary, 0, UInt64('a')) == 1
    @test VTI.transition(dictionary, 0, UInt64('x')) === nothing
    @test VTI.edges(dictionary, 0; batch_size=1) == MOCK_EDGES

    captured = VTI.snapshot(dictionary)
    @test MOCK_STATE.references == 2
    close(captured)
    close(dictionary)
    @test MOCK_STATE.references == 0
    @test MOCK_STATE.releases == 4
    @test_throws VTI.InteropError VTI.root(dictionary)
end

const REPOSITORY_ROOT = normpath(joinpath(@__DIR__, "..", "..", "..", ".."))
const NATIVE_BUILD_DIRECTORY = joinpath(@__DIR__, "target")
mkpath(NATIVE_BUILD_DIRECTORY)
const NATIVE_FIXTURE = joinpath(NATIVE_BUILD_DIRECTORY,
    "libvinary_tree_interop_test.$(Libdl.dlext)")
run(`cc -std=c11 -Wall -Wextra -Werror -fPIC -shared
    -I$(joinpath(REPOSITORY_ROOT, "include"))
    $(joinpath(REPOSITORY_ROOT, "bindings", "raku", "t", "mock-resource.c"))
    -o $NATIVE_FIXTURE`)

function native_resource()
    output = Ref(VTI.VtResourceRaw(C_NULL, Ptr{VTI.VtResourceVTable}(C_NULL)))
    ccall((:vt_test_resource, NATIVE_FIXTURE), Cvoid,
        (Ref{VTI.VtResourceRaw},), output)
    VTI.adopt_resource(output[])
end

native_references() = ccall((:vt_test_references, NATIVE_FIXTURE), Csize_t, ())
native_sizeof(kind) = ccall((:vt_test_sizeof, NATIVE_FIXTURE), Csize_t,
    (UInt32,), kind)

@testset "complete native ABI size correspondence" begin
    types = [
        VTI.VtInterfaceId,
        VTI.VtResourceRaw,
        VTI.VtResourceVTable,
        VTI.VtOptionalU64,
        VTI.VtDictionaryEdge,
        VTI.VtDictionaryVTable,
        VTI.VtDictionaryVisitVTable,
        VTI.VtDictionaryGraphNode,
        VTI.VtDictionaryGraphEdge,
        VTI.VtDictionaryGraphView,
        VTI.VtDictionaryGraphVTable,
        VTI.SnapshotIdentity,
        VTI.VtSnapshotIdentityVTable,
        VTI.VtDictionaryEntryRaw,
        VTI.BatchLimits,
        VTI.VtDictionaryEntryBatchView,
        VTI.VtDictionaryEntriesInfo,
        VTI.VtDictionaryEntriesCursorRaw,
        VTI.VtDictionaryEntriesVTable,
        VTI.VtWfstArc,
        VTI.VtWfstVTable,
        VTI.VtLatticeVTable,
        VTI.VtSemiringValue,
        VTI.VtSemiringVTable,
        VTI.VtSemiringDivisionVTable,
        VTI.VtSemiringStarVTable,
        VTI.VtSemiringNumericVTable,
        VTI.VtSemiringPropertiesVTable,
    ]
    for (index, type) in enumerate(types)
        @test sizeof(type) == native_sizeof(index)
    end
end

function native_lattice(value::Integer)
    output = Ref(VTI.VtResourceRaw(C_NULL, Ptr{VTI.VtResourceVTable}(C_NULL)))
    ccall((:vt_test_lattice, NATIVE_FIXTURE), Cvoid,
        (UInt64, Ref{VTI.VtResourceRaw}), UInt64(value), output)
    VTI.lattice_value(output[])
end

function native_lattice_value(value::VTI.LatticeValue)
    raw = Ref(VTI.raw_resource(value.resource))
    ccall((:vt_test_lattice_value, NATIVE_FIXTURE), UInt64,
        (Ref{VTI.VtResourceRaw},), raw)
end

@testset "immutable lattice value interface" begin
    small = native_lattice(3)
    large = native_lattice(8)
    @test VTI.flags(small) & VTI.LATTICE_FLAG_BATCH != 0
    @test VTI.domain_id(small) == VTI.domain_id(large)

    joined = VTI.lattice_join(small, large)
    met = VTI.lattice_meet(small, large)
    @test native_lattice_value(joined) == 8
    @test native_lattice_value(met) == 3
    @test VTI.equivalent(joined, large)
    @test !VTI.equivalent(met, large)
    @test VTI.stable_bytes(joined) == UInt8[0, 0, 0, 0, 0, 0, 0, 8]
    @test VTI.diagnostic(joined) == "fixture lattice"

    middle = native_lattice(5)
    batched_join = VTI.join_many(small, (middle, large))
    batched_meet = VTI.meet_many(large, (middle, small))
    empty_join = VTI.join_many(middle, ())
    @test native_lattice_value(batched_join) == 8
    @test native_lattice_value(batched_meet) == 3
    @test native_lattice_value(empty_join) == 5

    foreach(close, (empty_join, batched_meet, batched_join, middle, met,
        joined, large, small))
end

@testset "native collections, entry batches, and WFSTs" begin
    dictionary = VTI.dictionary(native_resource(); take=true)
    @test native_references() == 1
    @test dictionary isa AbstractDict
    @test @inferred(VTI.unit_domain(dictionary)) == VTI.UNIT_UNICODE_SCALAR
    @test @inferred(VTI.value_domain(dictionary)) == VTI.VALUE_OPTIONAL_U64
    @test @inferred(VTI.root(dictionary)) == UInt64(0)
    VTI.root(dictionary) # warm the allocation measurement
    @test (@allocated VTI.root(dictionary)) <= 256
    @test haskey(dictionary, "a")
    @test !haskey(dictionary, "x")
    @test dictionary["a"] == 10
    @test length(dictionary) == 2
    @test collect(dictionary) == ["a" => 10, "bc" => 20]

    tasks = [Threads.@spawn begin
        (VTI.root(dictionary), VTI.transition(
            dictionary, UInt64(0), UInt64('a')))
    end for _ in 1:32]
    @test all(fetch(task) == (UInt64(0), UInt64(1)) for task in tasks)

    cursor = VTI.entries(dictionary)
    @test VTI.known_length(cursor) == 2
    @test VTI.snapshot_identity(cursor) == VTI.SnapshotIdentity(42, 7)
    batch = VTI.next_batch(cursor, VTI.BatchLimits(1, 1, 1))
    copied = VTI.copied_entries(batch)
    @test length(copied) == 1
    @test copied[1].units == UInt32[UInt32('a')]
    @test copied[1].value == 10
    VTI.release!(batch)
    @test VTI.release!(batch) === nothing
    second = VTI.next_batch(cursor, VTI.BatchLimits(1, 1, 1))
    VTI.release!(second)
    @test VTI.next_batch(cursor) === nothing
    close(cursor)
    @test native_references() == 1

    reduction_cursor = VTI.entries(dictionary)
    reduced = VTI.DictionaryEntry[]
    count = VTI.reduce_entries(reduction_cursor, VTI.BatchLimits(1, 1, 1)) do page
        append!(reduced, page)
    end
    @test count == 2
    @test [entry.units for entry in reduced] ==
        [UInt32[UInt32('a')], UInt32[UInt32('b'), UInt32('c')]]
    close(reduction_cursor)
    failing_cursor = VTI.entries(dictionary)
    @test_throws ErrorException VTI.reduce_entries(failing_cursor) do _
        error("intentional reducer failure")
    end
    close(failing_cursor)
    @test native_references() == 1
    close(dictionary)
    @test native_references() == 0

    wfst = VTI.wfstransducer(native_resource(); take=true)
    @test VTI.unit_domain(wfst) == VTI.UNIT_UNICODE_SCALAR
    @test VTI.weight_domain(wfst) == VTI.WEIGHT_TROPICAL_F64
    @test VTI.start(wfst) == 0
    @test VTI.state_count(wfst) == 2
    @test VTI.state_info(wfst, 1) == VTI.WfstStateInfo(true, 2.0)
    @test VTI.state_info(wfst, 9) === nothing
    @test VTI.arcs(wfst, 0; batch_size=1) ==
        [VTI.WfstArc(UInt64('a'), UInt64('A'), 1, 1.5)]
    snapshot = VTI.snapshot(wfst)
    @test native_references() == 2
    close(snapshot)
    close(wfst)
    @test native_references() == 0
end
