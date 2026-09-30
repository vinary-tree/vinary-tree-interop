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
    $(joinpath(@__DIR__, "qualification-provider.c"))
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

function qualification_dictionary(unit_domain::VTI.UnitDomain,
    value_domain::VTI.ValueDomain; hostile_mode::Integer=0)
    output = Ref(VTI.VtResourceRaw(C_NULL, Ptr{VTI.VtResourceVTable}(C_NULL)))
    status = ccall((:vt_qualification_dictionary, NATIVE_FIXTURE), Cint,
        (UInt32, UInt32, UInt32, Ref{VTI.VtResourceRaw}),
        UInt32(unit_domain), UInt32(value_domain), UInt32(hostile_mode), output)
    @assert status == Cint(VTI.STATUS_OK)
    VTI.dictionary(output[])
end

function qualification_wfst(unit_domain::VTI.UnitDomain,
    weight_domain::VTI.WeightDomain; hostile_mode::Integer=0)
    output = Ref(VTI.VtResourceRaw(C_NULL, Ptr{VTI.VtResourceVTable}(C_NULL)))
    status = ccall((:vt_qualification_wfst, NATIVE_FIXTURE), Cint,
        (UInt32, UInt32, UInt32, Ref{VTI.VtResourceRaw}),
        UInt32(unit_domain), UInt32(weight_domain), UInt32(hostile_mode), output)
    @assert status == Cint(VTI.STATUS_OK)
    VTI.wfstransducer(output[])
end

function qualification_semiring()
    output = Ref(VTI.VtResourceRaw(C_NULL, Ptr{VTI.VtResourceVTable}(C_NULL)))
    status = ccall((:vt_qualification_semiring, NATIVE_FIXTURE), Cint,
        (Ref{VTI.VtResourceRaw},), output)
    @assert status == Cint(VTI.STATUS_OK)
    VTI.adopt_resource(output[])
end

qualification_live_dictionaries() = ccall(
    (:vt_qualification_live_dictionaries, NATIVE_FIXTURE), Csize_t, ())
qualification_live_cursors() = ccall(
    (:vt_qualification_live_cursors, NATIVE_FIXTURE), Csize_t, ())
qualification_visit_calls() = ccall(
    (:vt_qualification_visit_calls, NATIVE_FIXTURE), Csize_t, ())
qualification_live_semiring_tokens() = ccall(
    (:vt_qualification_live_semiring_tokens, NATIVE_FIXTURE), Csize_t, ())

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
    @test_throws VTI.InteropError VTI.next_batch(cursor, VTI.BatchLimits(1, 1, 1))
    second = VTI.next_batch(cursor, VTI.BatchLimits(1, 2, 1))
    VTI.release!(second)
    @test VTI.next_batch(cursor) === nothing
    close(cursor)
    @test native_references() == 1

    reduction_cursor = VTI.entries(dictionary)
    reduced = VTI.DictionaryEntry[]
    count = VTI.reduce_entries(reduction_cursor, VTI.BatchLimits(1, 2, 1)) do page
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

@testset "dictionary domains, fused visit, compact graph, and retained snapshots" begin
    cases = (
        (VTI.UNIT_BYTE, UInt8[0], UInt8[0xff], UInt64(0), UInt64(0xff)),
        (VTI.UNIT_UNICODE_SCALAR, "a", "λ", UInt64('a'), UInt64('λ')),
        (VTI.UNIT_U64, UInt64[0], UInt64[typemax(UInt64)],
            UInt64(0), typemax(UInt64)),
    )
    for (domain, low_key, high_key, low_label, high_label) in cases,
        value_domain in (VTI.VALUE_UNIT, VTI.VALUE_OPTIONAL_U64)
        dictionary = qualification_dictionary(domain, value_domain)
        try
            @test VTI.unit_domain(dictionary) == domain
            @test VTI.value_domain(dictionary) == value_domain
            @test VTI.flags(dictionary) & VTI.DICTIONARY_FLAG_IMMUTABLE != 0
            @test length(dictionary) == 2
            @test haskey(dictionary, low_key)
            @test haskey(dictionary, high_key)
            @test !haskey(dictionary, domain == VTI.UNIT_UNICODE_SCALAR ? "x" :
                domain == VTI.UNIT_BYTE ? UInt8[1] : UInt64[1])
            @test dictionary[low_key] === (value_domain == VTI.VALUE_UNIT ? nothing : UInt64(0))
            @test dictionary[high_key] === nothing
            @test VTI.edges(dictionary, 0; batch_size=1) ==
                [VTI.VtDictionaryEdge(low_label, 1),
                    VTI.VtDictionaryEdge(high_label, 2)]
            before = qualification_visit_calls()
            finality, visited = VTI.visit(dictionary, 0; batch_size=1)
            @test !finality
            @test visited == VTI.edges(dictionary, 0; batch_size=1)
            @test qualification_visit_calls() == before + 2
            @test VTI.visit(dictionary, 1) == (true, VTI.VtDictionaryEdge[])
            concurrent = [Threads.@spawn begin
                (VTI.transition(dictionary, 0, low_label),
                    VTI.visit(dictionary, 0; batch_size=2),
                    dictionary[low_key])
            end for _ in 1:8]
            @test all(fetch(task) == (UInt64(1),
                (false, [VTI.VtDictionaryEdge(low_label, 1),
                    VTI.VtDictionaryEdge(high_label, 2)]),
                value_domain == VTI.VALUE_UNIT ? nothing : UInt64(0))
                for task in concurrent)

            identity = VTI.snapshot_identity(dictionary)
            @test identity !== nothing
            snapshot = VTI.snapshot(dictionary)
            try
                @test VTI.snapshot_identity(snapshot) == identity
                @test snapshot[low_key] === dictionary[low_key]
            finally
                close(snapshot)
            end

            compact = VTI.graph(dictionary)
            @test compact !== nothing
            nodes = VTI.graph_nodes(compact)
            arcs = VTI.graph_edges(compact)
            @test length(nodes) == 3
            @test length(arcs) == 2
            @test arcs[1].label == low_label
            @test arcs[2].label == high_label
            @test arcs[2].target == 2
            if value_domain == VTI.VALUE_OPTIONAL_U64
                @test VTI.value(compact, nodes[2].value_cursor) == 0
                @test VTI.value(compact, nodes[3].value_cursor) === nothing
            end
            close(dictionary)
            @test VTI.graph_nodes(compact)[1].edge_len == 2
            close(compact)
            # Returned Julia arrays own their storage after the graph lease ends.
            @test nodes[1].edge_len == 2
            @test arcs[2].label == high_label
        finally
            close(dictionary)
        end
        @test qualification_live_dictionaries() == 0
    end
end

@testset "entry batches, cancellation, reducer failures, and domain ownership" begin
    for domain in (VTI.UNIT_BYTE, VTI.UNIT_UNICODE_SCALAR, VTI.UNIT_U64),
        value_domain in (VTI.VALUE_UNIT, VTI.VALUE_OPTIONAL_U64)
        dictionary = qualification_dictionary(domain, value_domain)
        try
            cursor = VTI.entries(dictionary)
            @test VTI.known_length(cursor) == 2
            @test VTI.snapshot_identity(cursor) == VTI.snapshot_identity(dictionary)
            @test VTI.unit_domain(cursor) == domain
            @test VTI.value_domain(cursor) == value_domain
            first = VTI.next_batch(cursor, VTI.BatchLimits(1, 1, 1))
            @test first !== nothing
            @test_throws VTI.InteropError VTI.next_batch(cursor)
            copied = VTI.copied_entries(first)
            @test length(copied) == 1
            @test copied[1].units == (domain == VTI.UNIT_BYTE ? UInt8[0] :
                domain == VTI.UNIT_UNICODE_SCALAR ? UInt32[0x61] : UInt64[0])
            @test copied[1].value === (value_domain == VTI.VALUE_UNIT ? nothing : UInt64(0))
            VTI.release!(first)
            @test VTI.release!(first) === nothing
            second = VTI.next_batch(cursor, VTI.BatchLimits(1, 1, 1))
            @test VTI.copied_entries(second)[1].value === nothing
            close(second)
            @test VTI.next_batch(cursor) === nothing
            close(cursor)

            reduction = VTI.entries(dictionary)
            pages = Vector{VTI.DictionaryEntry}()
            @test VTI.reduce_entries(reduction, VTI.BatchLimits(1, 1, 1)) do page
                append!(pages, page)
                @test_throws VTI.InteropError VTI.next_batch(reduction)
                @test_throws VTI.InteropError VTI.cancel!(reduction)
                @test_throws VTI.InteropError close(reduction)
                @test isopen(reduction)
            end == 2
            @test length(pages) == 2
            close(reduction)

            stopped = VTI.entries(dictionary)
            @test VTI.reduce_entries(stopped, VTI.BatchLimits(1, 1, 1)) do _
                VTI.STOP_REDUCTION
            end == 1
            @test VTI.next_batch(stopped) === nothing
            close(stopped)

            reentrant = VTI.entries(dictionary)
            @test_throws VTI.InteropError VTI.reduce_entries(reentrant,
                VTI.BatchLimits(1, 1, 1)) do _
                close(reentrant)
            end
            @test isopen(reentrant)
            close(reentrant)

            failed = VTI.entries(dictionary)
            failure = ErrorException("qualification callback failure")
            caught = try
                VTI.reduce_entries(failed, VTI.BatchLimits(1, 1, 1)) do _
                    throw(failure)
                end
                nothing
            catch error
                error
            end
            @test caught === failure
            # The provider settles its callback lease even on failure.
            remaining = VTI.next_batch(failed, VTI.BatchLimits(1, 1, 1))
            @test remaining !== nothing
            close(remaining)
            VTI.cancel!(failed)
            @test VTI.next_batch(failed) === nothing
            close(failed)

            cancelled = VTI.entries(dictionary)
            VTI.cancel!(cancelled)
            @test VTI.next_batch(cancelled) === nothing
            close(cancelled)

            early = VTI.entries(dictionary)
            held = VTI.next_batch(early, VTI.BatchLimits(1, 1, 1))
            close(early) # Settles the lease before closing its native cursor.
            @test !isopen(early)
            @test qualification_live_cursors() == 0
            @test_throws VTI.InteropError VTI.copied_entries(held)
            close(dictionary)
            @test qualification_live_dictionaries() == 0
        finally
            close(dictionary)
        end
    end
end

@testset "hostile provider metadata and batch spans are contained" begin
    for mode in (1, 6)
        dictionary = qualification_dictionary(VTI.UNIT_BYTE, VTI.VALUE_OPTIONAL_U64;
            hostile_mode=mode)
        try
            @test_throws VTI.InteropError VTI.graph(dictionary)
        finally
            close(dictionary)
        end
    end
    for mode in (2, 3)
        dictionary = qualification_dictionary(VTI.UNIT_U64, VTI.VALUE_OPTIONAL_U64;
            hostile_mode=mode)
        try
            cursor = VTI.entries(dictionary)
            try
                @test_throws VTI.InteropError VTI.next_batch(cursor,
                    VTI.BatchLimits(1, 1, 1))
            finally
                close(cursor)
            end
        finally
            close(dictionary)
        end
    end
    dictionary = qualification_dictionary(VTI.UNIT_BYTE, VTI.VALUE_UNIT;
        hostile_mode=4)
    try
        @test_throws VTI.InteropError VTI.entries(dictionary)
    finally
        close(dictionary)
    end
    dictionary = qualification_dictionary(VTI.UNIT_BYTE, VTI.VALUE_UNIT;
        hostile_mode=5)
    try
        @test_throws VTI.InteropError VTI.visit(dictionary, 0; batch_size=1)
    finally
        close(dictionary)
    end
    @test qualification_live_cursors() == 0
    @test qualification_live_dictionaries() == 0
end

@testset "scalar WFST domains, epsilon arcs, and retained pages" begin
    for unit_domain in (VTI.UNIT_BYTE, VTI.UNIT_UNICODE_SCALAR, VTI.UNIT_U64),
        weight_domain in instances(VTI.WeightDomain)
        wfst = qualification_wfst(unit_domain, weight_domain)
        try
            @test VTI.unit_domain(wfst) == unit_domain
            @test VTI.weight_domain(wfst) == weight_domain
            @test VTI.flags(wfst) & VTI.WFST_FLAG_IMMUTABLE != 0
            @test VTI.start(wfst) == 0
            @test VTI.state_count(wfst) == 2
            @test VTI.state_info(wfst, 1) == VTI.WfstStateInfo(true, 0.75)
            @test VTI.state_info(wfst, 9) === nothing
            page = VTI.arcs(wfst, 0; batch_size=1)
            @test length(page) == 2
            @test page[1].input == 0 || page[1].input == UInt64('a')
            @test page[1].output == (unit_domain == VTI.UNIT_BYTE ? 0xff :
                unit_domain == VTI.UNIT_UNICODE_SCALAR ? UInt64('λ') :
                typemax(UInt64))
            @test page[1].target == 1
            @test page[1].weight == 1.25
            @test page[2] == VTI.WfstArc(nothing, nothing, 1, 2.5)
            @test isempty(VTI.arcs(wfst, 1))
            retained = VTI.snapshot(wfst)
            close(wfst)
            try
                @test VTI.arcs(retained, 0; batch_size=1) == page
                @test VTI.state_info(retained, 1).final
            finally
                close(retained)
            end
        finally
            close(wfst)
        end
        @test qualification_live_dictionaries() == 0
    end
    hostile = qualification_wfst(VTI.UNIT_BYTE, VTI.WEIGHT_TROPICAL_F64;
        hostile_mode=7)
    try
        @test_throws VTI.InteropError VTI.arcs(hostile, 0; batch_size=1)
    finally
        close(hostile)
    end
    @test qualification_live_dictionaries() == 0
end

@testset "generated dynamic-semiring ABI values, batches, extensions, and ownership" begin
    resource = qualification_semiring()
    retained = VTI.retain(resource)
    close(resource)
    raw = VTI.raw_resource(retained)
    base = unsafe_load(Ptr{VTI.VtSemiringVTable}(VTI.query_interface(retained,
        VTI.SEMIRING_INTERFACE_ID)))
    division = unsafe_load(Ptr{VTI.VtSemiringDivisionVTable}(VTI.query_interface(retained,
        VTI.SEMIRING_DIVISION_INTERFACE_ID)))
    star = unsafe_load(Ptr{VTI.VtSemiringStarVTable}(VTI.query_interface(retained,
        VTI.SEMIRING_STAR_INTERFACE_ID)))
    numeric = unsafe_load(Ptr{VTI.VtSemiringNumericVTable}(VTI.query_interface(retained,
        VTI.SEMIRING_NUMERIC_INTERFACE_ID)))
    properties = unsafe_load(Ptr{VTI.VtSemiringPropertiesVTable}(VTI.query_interface(retained,
        VTI.SEMIRING_PROPERTIES_INTERFACE_ID)))
    @test VTI.query_interface(retained, VTI.LATTICE_INTERFACE_ID) === nothing
    @test base.flags & VTI.SEMIRING_FLAG_BATCH != 0
    @test properties.properties & VTI.SEMIRING_PROPERTY_HASHABLE != 0
    owned = VTI.VtSemiringValue[]
    function result(call)
        output = Ref(VTI.VtSemiringValue(0, 0))
        @test call(output) == Cint(VTI.STATUS_OK)
        push!(owned, output[])
        output[]
    end
    try
        zero = result(out -> VTI.abi_call_semiring_zero(base.zero, raw.context, out))
        one = result(out -> VTI.abi_call_semiring_one(base.one, raw.context, out))
        two = result(out -> VTI.abi_call_semiring_plus(base.plus, raw.context,
            Ref(one), Ref(one), out))
        four = result(out -> VTI.abi_call_semiring_times(base.times, raw.context,
            Ref(two), Ref(two), out))
        cloned = result(out -> VTI.abi_call_semiring_clone_value(base.clone_value,
            raw.context, Ref(four), out))
        @test cloned.word0 == four.word0 == 4
        @test cloned.word1 != four.word1
        equal = Ref{UInt8}(0)
        @test VTI.abi_call_semiring_equal(base.equal, raw.context,
            Ref(four), Ref(cloned), equal) == Cint(VTI.STATUS_OK)
        @test equal[] == 1
        @test VTI.abi_call_semiring_approx_equal(base.approx_equal, raw.context,
            Ref(two), Ref(four), 2.0, equal) == Cint(VTI.STATUS_OK)
        @test equal[] == 1
        order = Ref{Int32}(0)
        @test VTI.abi_call_semiring_natural_order(base.natural_order, raw.context,
            Ref(two), Ref(four), order) == Cint(VTI.STATUS_OK)
        @test order[] == VTI.SEMIRING_ORDER_BETTER

        bytes = Vector{UInt8}(undef, 32)
        written = Ref{Csize_t}(0)
        required = Ref{Csize_t}(0)
        @test GC.@preserve bytes VTI.abi_call_semiring_stable_bytes(
            base.stable_bytes, raw.context, Ref(four), pointer(bytes),
            length(bytes), written, required) == Cint(VTI.STATUS_OK)
        @test bytes[1:Int(written[])] == UInt8[0, 0, 0, 0, 0, 0, 0, 4]
        @test required[] == 8
        @test GC.@preserve bytes VTI.abi_call_semiring_diagnostic(
            base.diagnostic, raw.context, Ref(four), pointer(bytes),
            length(bytes), written, required) == Cint(VTI.STATUS_OK)
        @test String(bytes[1:Int(written[])]) == "qualification count"

        inputs = VTI.VtSemiringValue[one, two, four]
        sum = result(out -> GC.@preserve inputs VTI.abi_call_semiring_plus_many(
            base.plus_many, raw.context, pointer(inputs), length(inputs), out))
        product = result(out -> GC.@preserve inputs VTI.abi_call_semiring_times_many(
            base.times_many, raw.context, pointer(inputs), length(inputs), out))
        @test (sum.word0, product.word0) == (7, 8)
        additive_identity = result(out -> VTI.abi_call_semiring_plus_many(
            base.plus_many, raw.context, Ptr{VTI.VtSemiringValue}(C_NULL), 0, out))
        multiplicative_identity = result(out -> VTI.abi_call_semiring_times_many(
            base.times_many, raw.context, Ptr{VTI.VtSemiringValue}(C_NULL), 0, out))
        @test (additive_identity.word0, multiplicative_identity.word0) == (0, 1)

        quotient = result(out -> VTI.abi_call_semiring_division_divide(
            division.divide, raw.context, Ref(product), Ref(two), out))
        left_quotient = result(out -> VTI.abi_call_semiring_division_left_divide(
            division.left_divide, raw.context, Ref(product), Ref(two), out))
        @test quotient.word0 == left_quotient.word0 == 4
        absent = Ref(VTI.VtSemiringValue(0, 0))
        @test VTI.abi_call_semiring_division_divide(division.divide, raw.context,
            Ref(one), Ref(two), absent) == Cint(VTI.STATUS_END)
        @test absent[] == VTI.VtSemiringValue(0, 0)
        star_zero = result(out -> VTI.abi_call_semiring_star_star(star.star,
            raw.context, Ref(zero), out))
        @test star_zero.word0 == 1
        @test VTI.abi_call_semiring_star_star(star.star, raw.context,
            Ref(one), absent) == Cint(VTI.STATUS_END)

        number = Ref{Float64}(0)
        quantized = Ref{Int64}(0)
        @test VTI.abi_call_semiring_numeric_numerical_value(
            numeric.numerical_value, raw.context, Ref(four), number) == Cint(VTI.STATUS_OK)
        @test number[] == 4.0
        @test VTI.abi_call_semiring_numeric_quantize(numeric.quantize,
            raw.context, Ref(four), 2.0, quantized) == Cint(VTI.STATUS_OK)
        @test quantized[] == 2
        @test VTI.abi_call_semiring_numeric_to_probability(numeric.to_probability,
            raw.context, Ref(four), number) == Cint(VTI.STATUS_OK)
        @test number[] == 4.0
        bound = Ref{Csize_t}(0)
        known = Ref{UInt8}(1)
        @test VTI.abi_call_semiring_properties_closure_bound(
            properties.closure_bound, raw.context, bound, known) == Cint(VTI.STATUS_OK)
        @test known[] == 0
        @test qualification_live_semiring_tokens() == length(owned)
    finally
        @test GC.@preserve owned VTI.abi_call_semiring_release_values(
            base.release_values, raw.context, pointer(owned), length(owned)) ==
            Cint(VTI.STATUS_OK)
        @test all(value -> value.word1 == 0, owned)
        @test qualification_live_semiring_tokens() == 0
        close(retained)
    end
    @test qualification_live_dictionaries() == 0
end
