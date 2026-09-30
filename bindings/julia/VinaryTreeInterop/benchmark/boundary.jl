using VinaryTreeInterop
using Libdl

const VTI = VinaryTreeInterop
const ROOT = normpath(joinpath(@__DIR__, "..", "..", "..", ".."))
const BUILD = joinpath(@__DIR__, "target")
const LIB = joinpath(BUILD, "libboundary_control.$(Libdl.dlext)")
const CASES = (
    (1, "resource_retain", 100_000),
    (2, "dictionary_query", 30_000),
    (3, "dictionary_snapshot", 20_000),
    (4, "dictionary_visit", 15_000),
    (5, "dictionary_graph", 10_000),
    (6, "entry_page", 5_000),
    (7, "entry_reduce_host_callback", 5_000),
    (8, "wfst_expand", 15_000),
    (9, "lattice_pair", 15_000),
    (10, "lattice_batch", 10_000),
    (11, "semiring_pair_with_context", 2_000),
    (12, "semiring_batch_with_context", 2_000),
)
const EXPECTED_PER_ITERATION = (1, 3, 1, 6, 3, 3, 4, 5, 5, 11, 2, 3)

function compile_control()
    mkpath(BUILD)
    run(`cc -O2 -std=c11 -Wall -Wextra -Werror -fPIC -shared
        -I$(joinpath(ROOT, "include"))
        $(joinpath(ROOT, "bindings", "raku", "t", "mock-resource.c"))
        $(joinpath(ROOT, "bindings", "julia", "VinaryTreeInterop", "test",
            "qualification-provider.c"))
        $(joinpath(@__DIR__, "native-control.c")) -o $LIB`)
end

function checked(status)
    status == Cint(VTI.STATUS_OK) ||
        error("native benchmark provider returned status $status")
end

function qualification_dictionary()
    output = Ref(VTI.VtResourceRaw(C_NULL, Ptr{VTI.VtResourceVTable}(C_NULL)))
    checked(ccall((:vt_qualification_dictionary, LIB), Cint,
        (UInt32, UInt32, UInt32, Ref{VTI.VtResourceRaw}),
        UInt32(VTI.UNIT_BYTE), UInt32(VTI.VALUE_OPTIONAL_U64), UInt32(0),
        output))
    VTI.dictionary(output[])
end

function qualification_wfst()
    output = Ref(VTI.VtResourceRaw(C_NULL, Ptr{VTI.VtResourceVTable}(C_NULL)))
    checked(ccall((:vt_qualification_wfst, LIB), Cint,
        (UInt32, UInt32, UInt32, Ref{VTI.VtResourceRaw}),
        UInt32(VTI.UNIT_BYTE), UInt32(VTI.WEIGHT_TROPICAL_F64), UInt32(0),
        output))
    VTI.wfstransducer(output[])
end

function qualification_semiring()
    output = Ref(VTI.VtResourceRaw(C_NULL, Ptr{VTI.VtResourceVTable}(C_NULL)))
    checked(ccall((:vt_qualification_semiring, LIB), Cint,
        (Ref{VTI.VtResourceRaw},), output))
    VTI.adopt_resource(output[])
end

function lattice_value(number::Integer)
    output = Ref(VTI.VtResourceRaw(C_NULL, Ptr{VTI.VtResourceVTable}(C_NULL)))
    ccall((:vt_test_lattice, LIB), Cvoid,
        (UInt64, Ref{VTI.VtResourceRaw}), UInt64(number), output)
    VTI.lattice_value(output[])
end

function native_sample(which::Integer, iterations::Integer)
    checksum = Ref{UInt64}(0)
    duration = Ref{UInt64}(0)
    checked(ccall((:vt_benchmark_native, LIB), Cint,
        (UInt32, Csize_t, Ref{UInt64}, Ref{UInt64}),
        UInt32(which), Csize_t(iterations), checksum, duration))
    actual = Int(checksum[])
    expected = EXPECTED_PER_ITERATION[which] * iterations
    actual == expected ||
        error("native case $which checksum $actual, expected $expected")
    (actual, Int(duration[]))
end

function semiring_iteration(which::Integer)
    resource = qualification_semiring()
    try
        raw = VTI.raw_resource(resource)
        table = unsafe_load(Ptr{VTI.VtSemiringVTable}(
            VTI.query_interface(resource, VTI.SEMIRING_INTERFACE_ID)))
        operands = VTI.VtSemiringValue[]
        try
            for _ in 1:(which == 11 ? 2 : 3)
                output = Ref(VTI.VtSemiringValue(0, 0))
                checked(VTI.abi_call_semiring_one(table.one, raw.context, output))
                push!(operands, output[])
            end
            result = Ref(VTI.VtSemiringValue(0, 0))
            if which == 11
                checked(VTI.abi_call_semiring_plus(table.plus, raw.context,
                    Ref(operands[1]), Ref(operands[2]), result))
            else
                checked(GC.@preserve operands VTI.abi_call_semiring_plus_many(
                    table.plus_many, raw.context, pointer(operands),
                    length(operands), result))
            end
            push!(operands, result[])
            Int(result[].word0)
        finally
            if !isempty(operands)
                checked(GC.@preserve operands VTI.abi_call_semiring_release_values(
                    table.release_values, raw.context, pointer(operands),
                    length(operands)))
            end
        end
    finally
        close(resource)
    end
end

function julia_sample(which::Integer, iterations::Integer)
    checksum = 0
    if which <= 7
        dictionary = qualification_dictionary()
        try
            key = UInt8[0]
            resource = dictionary.resource
            for _ in 1:iterations
                if which == 1
                    held = VTI.retain(resource)
                    close(held)
                    checksum += 1
                elseif which == 2
                    dictionary[key] == 0 || error("dictionary mismatch")
                    checksum += 3
                elseif which == 3
                    captured = VTI.snapshot(dictionary)
                    close(captured)
                    checksum += 1
                elseif which == 4
                    final, edges = VTI.visit(dictionary, 0; batch_size=2)
                    !final && length(edges) == 2 || error("visit mismatch")
                    checksum += length(edges) + length(edges) + Int(edges[2].node)
                elseif which == 5
                    graph = VTI.graph(dictionary)
                    try
                        nodes = VTI.graph_nodes(graph)
                        edges = VTI.graph_edges(graph)
                        checksum += Int(nodes[2].is_final) + Int(edges[2].target)
                    finally
                        close(graph)
                    end
                else
                    cursor = VTI.entries(dictionary)
                    try
                        limits = VTI.BatchLimits(2, 2, 2)
                        if which == 6
                            batch = VTI.next_batch(cursor, limits)
                            try
                                copied = VTI.copied_entries(batch)
                                checksum += length(copied) + length(copied[2].units)
                            finally
                                VTI.release!(batch)
                            end
                        else
                            counted = Ref(0)
                            processed = VTI.reduce_entries(cursor, limits) do page
                                counted[] += length(page)
                            end
                            checksum += counted[] + processed
                        end
                    finally
                        close(cursor)
                    end
                end
            end
        finally
            close(dictionary)
        end
    elseif which == 8
        wfst = qualification_wfst()
        try
            for _ in 1:iterations
                info = VTI.state_info(wfst, 0)
                arcs = VTI.arcs(wfst, 0; batch_size=2)
                info !== nothing && length(arcs) == 2 || error("WFST mismatch")
                checksum += length(arcs) + length(arcs) + Int(arcs[1].target)
            end
        finally
            close(wfst)
        end
    elseif which == 9 || which == 10
        base = lattice_value(3)
        operands = [lattice_value(n) for n in (5, 7, 11)]
        try
            for _ in 1:iterations
                result = which == 9 ? VTI.lattice_join(base, operands[1]) :
                    VTI.join_many(base, operands)
                try
                    checksum += which == 9 ? 5 : 11
                finally
                    close(result)
                end
            end
        finally
            foreach(close, operands)
            close(base)
        end
    elseif which == 11 || which == 12
        for _ in 1:iterations
            checksum += semiring_iteration(which)
        end
    else
        error("unknown case: $which")
    end
    expected = EXPECTED_PER_ITERATION[which] * iterations
    checksum == expected ||
        error("Julia case $which checksum $checksum, expected $expected")
    checksum
end

function assert_no_qualification_leaks()
    dictionaries = ccall((:vt_qualification_live_dictionaries, LIB), Csize_t, ())
    cursors = ccall((:vt_qualification_live_cursors, LIB), Csize_t, ())
    tokens = ccall((:vt_qualification_live_semiring_tokens, LIB), Csize_t, ())
    (dictionaries, cursors, tokens) == (0, 0, 0) ||
        error("qualification leaks: dictionaries=$dictionaries, " *
            "cursors=$cursors, semiring tokens=$tokens")
end

function timed_julia(which::Integer, iterations::Integer)
    started = time_ns()
    checksum = julia_sample(which, iterations)
    (checksum, time_ns() - started)
end

function load_average()
    parse(Float64, first(split(read("/proc/loadavg", String))))
end

function rss_kib()
    for line in eachline("/proc/self/status")
        startswith(line, "VmRSS:") && return parse(Int, split(line)[2])
    end
    error("VmRSS not available")
end

function cpu_ticks()
    fields = split(first(eachline("/proc/stat")))[2:end]
    values = parse.(Int, fields)
    (sum(values) - values[4] - values[5], sum(values))
end

function scheduler_wait_ns()
    parse(Int, split(read("/proc/self/schedstat", String))[2])
end

function affinity_cpu()
    for line in eachline("/proc/self/status")
        if startswith(line, "Cpus_allowed_list:")
            return parse(Int, first(split(strip(split(line, ":"; limit=2)[2]),
                r"[,-]")))
        end
    end
    error("CPU affinity is unavailable")
end

function cpu_frequency_khz(cpu::Integer)
    path = "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_cur_freq"
    isfile(path) ? parse(Int, strip(read(path, String))) : 0
end

function median_value(values)
    ordered = sort(collect(values))
    middle = length(ordered) ÷ 2
    isodd(length(ordered)) ? ordered[middle + 1] :
        (ordered[middle] + ordered[middle + 1]) / 2
end

function bootstrap_interval(values; resamples=2_000)
    count = length(values)
    samples = Vector{Float64}(undef, resamples)
    state = UInt64(0x9e3779b97f4a7c15)
    for replicate in eachindex(samples)
        selected = Vector{Float64}(undef, count)
        for index in eachindex(selected)
            state = state * UInt64(6364136223846793005) + UInt64(1)
            selected[index] = values[Int(state % UInt64(count)) + 1]
        end
        samples[replicate] = median_value(selected)
    end
    sort!(samples)
    (samples[50], samples[1950])
end

function write_manifest(output, pilot)
    function field_from(path, prefix)
        for line in eachline(path)
            startswith(line, prefix) &&
                return strip(split(line, ":"; limit=2)[2])
        end
        "unknown"
    end
    cpu_model = field_from("/proc/cpuinfo", "model name")
    affinity = field_from("/proc/self/status", "Cpus_allowed_list:")
    cpu = affinity_cpu()
    governor_path = "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor"
    governor = isfile(governor_path) ? strip(read(governor_path, String)) :
        "unavailable"
    open(output * ".meta", "w") do io
        println(io, "mode=", pilot ? "pilot_diagnostic" : "full")
        println(io, "epoch_seconds=", time())
        println(io, "git_head=", readchomp(`git rev-parse HEAD`))
        for (name, path) in (
            ("julia_driver", @__FILE__),
            ("native_control", joinpath(@__DIR__, "native-control.c")),
            ("dictionary_fixture", joinpath(ROOT, "bindings", "julia",
                "VinaryTreeInterop", "test", "qualification-provider.c")),
            ("lattice_fixture", joinpath(ROOT, "bindings", "raku", "t",
                "mock-resource.c")),
        )
            println(io, "sha256_", name, "=",
                first(split(readchomp(`sha256sum $path`))))
        end
        println(io, "julia_version=", VERSION)
        println(io, "julia_project=", Base.active_project())
        println(io, "cc_version=", first(split(readchomp(`cc --version`), '\n')))
        println(io, "kernel=", Sys.KERNEL)
        println(io, "arch=", Sys.ARCH)
        println(io, "cpu_threads=", Sys.CPU_THREADS)
        println(io, "cpu_model=", strip(cpu_model))
        println(io, "affinity=", strip(affinity))
        println(io, "affinity_first_cpu=", cpu)
        println(io, "cpu_governor=", governor)
        println(io, "julia_threads=", Threads.nthreads())
        println(io, "native_optimization=-O2")
        println(io, "max_accepted_load=", max(4, Sys.CPU_THREADS ÷ 4))
        println(io, "max_accepted_host_busy_fraction=0.5")
        println(io, "max_accepted_scheduler_wait_fraction=0.05")
    end
end

function raw_rows(path)
    lines = readlines(path)
    header = split(first(lines), ",")
    positions = Dict(name => index for (index, name) in enumerate(header))
    all(split(line, ",")[positions["mode"]] == "full" for line in lines[2:end]) ||
        error("only full, non-pilot CSV files may be used as regression baselines")
    rows = Dict{String,Vector{NamedTuple}}()
    for line in lines[2:end]
        fields = split(line, ",")
        fields[positions["contaminated"]] == "false" || continue
        case = fields[positions["case"]]
        sample = (
            julia_ns=parse(Float64, fields[positions["julia_ns"]]),
            native_ns=parse(Float64, fields[positions["native_ns"]]),
            iterations=parse(Int, fields[positions["iterations"]]),
            allocation=parse(Float64, fields[positions["julia_alloc_bytes"]]),
        )
        push!(get!(rows, case, NamedTuple[]), sample)
    end
    rows
end

function run_metadata(path)
    meta = Dict{String,String}()
    for line in eachline(path * ".meta")
        key, value = split(line, "="; limit=2)
        meta[key] = value
    end
    meta
end

function check_budgets(current, baseline)
    current_meta = run_metadata(current)
    baseline_meta = run_metadata(baseline)
    for key in ("cpu_model", "affinity", "cpu_governor", "julia_version",
        "cc_version", "native_optimization", "julia_threads")
        get(current_meta, key, nothing) == get(baseline_meta, key, nothing) ||
            error("incomparable benchmark metadata at $key: " *
                "current=$(get(current_meta, key, missing)), " *
                "baseline=$(get(baseline_meta, key, missing))")
    end
    new = raw_rows(current)
    old = raw_rows(baseline)
    violations = String[]
    for (_, name, _) in CASES
        measured = get(new, name, NamedTuple[])
        reference = get(old, name, NamedTuple[])
        if length(measured) < 9 || length(reference) < 9
            push!(violations, "$name has fewer than 9 clean current/baseline samples")
            continue
        end
        function metrics(samples)
            (
                median_value(row.julia_ns / row.iterations for row in samples),
                median_value(row.julia_ns / max(1, row.native_ns)
                    for row in samples),
                median_value(row.allocation / min(row.iterations, 100)
                    for row in samples),
            )
        end
        julia_ns, ratio, bytes = metrics(measured)
        base_ns, base_ratio, base_bytes = metrics(reference)
        julia_ns <= 1.5base_ns ||
            push!(violations, "$name Julia latency $(round(julia_ns; digits=1))" *
                " ns/op exceeds 1.5× baseline $(round(base_ns; digits=1))")
        ratio <= 2base_ratio ||
            push!(violations, "$name Julia/native ratio $(round(ratio; digits=1))" *
                " exceeds 2× baseline $(round(base_ratio; digits=1))")
        bytes <= max(1.25base_bytes, base_bytes + 32) ||
            push!(violations, "$name Julia allocation $(round(bytes; digits=1))" *
                " B/op exceeds baseline $(round(base_bytes; digits=1))" *
                " plus 25% or 32 B")
    end
    isempty(violations) || error("boundary regression budget failures:\n" *
        join(violations, "\n"))
    println("All machine-local regression budgets passed against $baseline")
end

function run_benchmark(output; pilot=false, baseline=nothing)
    compile_control()
    samples = pilot ? 3 : 11
    multiplier = pilot ? 0.02 : 1.0
    mkpath(dirname(output))
    write_manifest(output, pilot)
    open(output, "w") do io
        println(io, "mode,case_id,case,replicate,order,iterations,native_ns,julia_ns," *
            "native_checksum,julia_checksum,julia_alloc_bytes,rss_before_kib," *
            "rss_after_kib,load_before,load_after,cpu_freq_before_khz," *
            "cpu_freq_after_khz,cpu_busy_fraction," *
            "scheduler_wait_fraction,contaminated")
        for (which, name, default_iterations) in CASES
            iterations = max(20, round(Int, default_iterations * multiplier))
            for _ in 1:3
                native_sample(which, max(10, iterations ÷ 10))
                julia_sample(which, max(10, iterations ÷ 10))
            end
            assert_no_qualification_leaks()
            ratios = Float64[]
            for replicate in 1:samples
                GC.gc()
                load_before = load_average()
                rss_before = rss_kib()
                freq_before = cpu_frequency_khz(affinity_cpu())
                busy_before, ticks_before = cpu_ticks()
                waited_before = scheduler_wait_ns()
                block_started = time_ns()
                order = isodd(replicate) ? "native_first" : "julia_first"
                if isodd(replicate)
                    native_checksum, native_ns = native_sample(which, iterations)
                    julia_checksum, julia_ns = timed_julia(which, iterations)
                else
                    julia_checksum, julia_ns = timed_julia(which, iterations)
                    native_checksum, native_ns = native_sample(which, iterations)
                end
                native_checksum == julia_checksum ||
                    error("$name checksum differs: native=$native_checksum Julia=$julia_checksum")
                julia_alloc_bytes = @allocated julia_sample(which,
                    max(1, min(iterations, 100)))
                assert_no_qualification_leaks()
                busy_after, ticks_after = cpu_ticks()
                block_elapsed = max(1, time_ns() - block_started)
                wait_fraction = (scheduler_wait_ns() - waited_before) /
                    block_elapsed
                rss_after = rss_kib()
                load_after = load_average()
                freq_after = cpu_frequency_khz(affinity_cpu())
                busy_fraction = (busy_after - busy_before) /
                    max(1, ticks_after - ticks_before)
                contaminated = max(load_before, load_after) >
                    max(4, Sys.CPU_THREADS ÷ 4) || busy_fraction > 0.5 ||
                    wait_fraction > 0.05
                println(io, join((pilot ? "pilot_diagnostic" : "full", which,
                    name, replicate, order, iterations,
                    native_ns, julia_ns, native_checksum, julia_checksum,
                    julia_alloc_bytes, rss_before, rss_after,
                    load_before, load_after, freq_before, freq_after,
                    busy_fraction,
                    wait_fraction, contaminated), ","))
                flush(io)
                !contaminated && push!(ratios, julia_ns / max(1, native_ns))
            end
            if length(ratios) >= (pilot ? 2 : 9)
                low, high = bootstrap_interval(ratios)
                println("$name: Julia/native median $(round(median_value(ratios); digits=2))" *
                    "× (bootstrap 95% CI $(round(low; digits=2))–$(round(high; digits=2))×)")
            else
                println("$name: insufficient uncontaminated samples " *
                    "($(length(ratios)) of $samples)")
            end
        end
    end
    println("Raw samples: $output")
    baseline !== nothing && !pilot && check_budgets(output, baseline)
end

1 <= length(ARGS) <= 4 ||
    error("usage: julia --project=bindings/julia/VinaryTreeInterop " *
        "benchmark/boundary.jl OUTPUT.csv [--pilot] [--baseline BASE.csv]")
options = ARGS[2:end]
pilot = "--pilot" in options
baseline_index = findfirst(==("--baseline"), options)
baseline_index !== nothing && baseline_index == length(options) &&
    error("--baseline requires a CSV path")
pilot && baseline_index !== nothing &&
    error("a diagnostic pilot cannot be checked against a baseline")
recognized = String[]
pilot && push!(recognized, "--pilot")
if baseline_index !== nothing
    append!(recognized, ("--baseline", options[baseline_index + 1]))
end
sort(options) == sort(recognized) ||
    error("unrecognized or duplicate benchmark option")
baseline = baseline_index === nothing ? nothing :
    abspath(options[baseline_index + 1])
run_benchmark(abspath(ARGS[1]); pilot, baseline)
