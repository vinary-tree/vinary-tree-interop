# Read-only post-registration verification. Never run this as a publisher.
# Usage: julia --startup-file=no test/registry_readback.jl <version> <source-sha> <scratch-root>
using Pkg
using UUIDs

length(ARGS) == 3 || error("expected version, full source SHA, and scratch root")
expected_version, revision, scratch_root = ARGS
occursin(r"^[0-9a-f]{40}$", revision) || error("source SHA must be a full Git SHA")
VersionNumber(expected_version) # fail before any network access on malformed input
repository = normpath(joinpath(@__DIR__, "..", "..", "..", ".."))
readchomp(`git -C $repository rev-parse HEAD`) == revision ||
    error("checkout is not the reviewed source SHA")
expected_tree = readchomp(`git -C $repository rev-parse $(revision * ":bindings/julia/VinaryTreeInterop")`)
isdir(scratch_root) || error("scratch root does not exist")

mktempdir(abspath(scratch_root)) do consumer
    Pkg.activate(consumer)
    Pkg.Registry.add("General")
    Pkg.add(PackageSpec(name="VinaryTreeInterop", version=expected_version))
    info = Pkg.dependencies()[UUID("8d6503e5-4d65-4bd8-a8ee-293a0149584e")]
    info.version == VersionNumber(expected_version) ||
        error("General resolved version $(info.version), not $expected_version")
    string(info.tree_hash) == expected_tree ||
        error("General tree $(info.tree_hash) differs from reviewed $expected_tree")
    check = joinpath(@__DIR__, "installed_consumer_check.jl")
    run(`$(Base.julia_cmd()) --startup-file=no --project=$consumer $check $repository $revision`)
    println("General public readback passed: ", expected_version,
        ", source ", revision, ", tree ", expected_tree)
end
