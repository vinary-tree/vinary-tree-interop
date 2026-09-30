# Read-only summary of the raw paired-block CSV. Never drops or rewrites rows.
length(ARGS) == 1 || error("usage: julia summarize.jl RESULTS.csv")

function median_value(values)
    ordered = sort(collect(values))
    middle = length(ordered) ÷ 2
    isodd(length(ordered)) ? ordered[middle + 1] :
        (ordered[middle] + ordered[middle + 1]) / 2
end

function interval(values; resamples=2_000)
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

lines = readlines(ARGS[1])
header = split(first(lines), ",")
column = Dict(name => index for (index, name) in enumerate(header))
rows = Dict{String,Vector{NamedTuple}}()
order = String[]
for line in lines[2:end]
    fields = split(line, ",")
    fields[column["mode"]] == "full" ||
        error("pilot data cannot be summarized as a full baseline")
    name = fields[column["case"]]
    if !haskey(rows, name)
        rows[name] = NamedTuple[]
        push!(order, name)
    end
    push!(rows[name], (
        iterations=parse(Int, fields[column["iterations"]]),
        native_ns=parse(Float64, fields[column["native_ns"]]),
        julia_ns=parse(Float64, fields[column["julia_ns"]]),
        alloc_bytes=parse(Float64, fields[column["julia_alloc_bytes"]]),
        rss_delta=parse(Int, fields[column["rss_after_kib"]]) -
            parse(Int, fields[column["rss_before_kib"]]),
        contaminated=fields[column["contaminated"]] == "true",
    ))
end

println("| Case | Clean/total | Native ns/op | Julia ns/op | Julia alloc B/op | " *
    "Julia/native median (95% bootstrap interval) | Median RSS delta KiB |")
println("| --- | ---: | ---: | ---: | ---: | ---: | ---: |")
for name in order
    all_rows = rows[name]
    clean = filter(row -> !row.contaminated, all_rows)
    isempty(clean) && error("$name has no clean observations")
    native = median_value(row.native_ns / row.iterations for row in clean)
    julia = median_value(row.julia_ns / row.iterations for row in clean)
    allocation = median_value(row.alloc_bytes / min(100, row.iterations)
        for row in clean)
    ratios = [row.julia_ns / row.native_ns for row in clean]
    low, high = interval(ratios)
    rss = median_value(row.rss_delta for row in clean)
    println("| $name | $(length(clean))/$(length(all_rows)) | " *
        "$(round(native; digits=2)) | $(round(julia; digits=2)) | " *
        "$(round(allocation; digits=2)) | " *
        "$(round(median_value(ratios); digits=2))× " *
        "[$(round(low; digits=2)), $(round(high; digits=2))] | " *
        "$(round(rss; digits=1)) |")
end
