# Exercise the package as an installed Git dependency, not a developed checkout.
# Usage: julia --startup-file=no test/installed_consumer.jl <disk-backed scratch root>
using Pkg

length(ARGS) == 1 || error("pass a disk-backed scratch directory")
scratch_root = abspath(ARGS[1])
isdir(scratch_root) || error("scratch root does not exist: $scratch_root")
repository = normpath(joinpath(@__DIR__, "..", "..", "..", ".."))
revision = readchomp(`git -C $repository rev-parse HEAD`)
occursin(r"^[0-9a-f]{40}$", revision) || error("expected an immutable Git SHA")
subdir = "bindings/julia/VinaryTreeInterop"

mktempdir(scratch_root) do consumer
    Pkg.activate(consumer)
    Pkg.add(PackageSpec(url="file://$repository", rev=revision, subdir=subdir))
    Pkg.instantiate()
    check = joinpath(@__DIR__, "installed_consumer_check.jl")
    run(`$(Base.julia_cmd()) --startup-file=no --project=$consumer $check $repository $revision`)
end
