# A separate process is essential: no active checkout project or world-age
# effects from Pkg.add may influence the installed consumer.
using VinaryTreeInterop
using Pkg
using Libdl
using UUIDs

const VTI = VinaryTreeInterop
length(ARGS) == 2 || error("expected repository path and immutable revision")
repository, revision = ARGS
package_path = realpath(pathof(VTI))
startswith(package_path, realpath(repository) * "/") &&
    error("consumer resolved the checkout instead of an installed package")
haskey(Pkg.project().dependencies, "VinaryTreeInterop") ||
    error("installed package is absent from the clean consumer project")
package_info = Pkg.dependencies()[UUID("8d6503e5-4d65-4bd8-a8ee-293a0149584e")]
expected_tree = readchomp(`git -C $repository rev-parse $(revision * ":bindings/julia/VinaryTreeInterop")`)
string(package_info.tree_hash) == expected_tree ||
    error("installed package tree does not match source commit subtree")

fixture = joinpath(dirname(Base.active_project()),
    "libvinary_tree_interop_test.$(Libdl.dlext)")
run(`cc -std=c11 -Wall -Wextra -Werror -fPIC -shared
    -I$(joinpath(repository, "include"))
    $(joinpath(repository, "bindings", "raku", "t", "mock-resource.c"))
    $(joinpath(repository, "bindings", "julia", "VinaryTreeInterop", "test",
        "qualification-provider.c")) -o $fixture`)

library = Libdl.dlopen(fixture)
output = Ref(VTI.VtResourceRaw(C_NULL, Ptr{VTI.VtResourceVTable}(C_NULL)))
ccall(Libdl.dlsym(library, :vt_test_resource), Cvoid,
    (Ref{VTI.VtResourceRaw},), output)
d = VTI.dictionary(output[])
try
    @assert d isa AbstractDict{String}
    @assert length(d) == 2
    @assert haskey(d, "a") && d["a"] == UInt64(10)
    @assert collect(d) == ["a" => UInt64(10), "bc" => UInt64(20)]
    captured = VTI.snapshot(d)
    try
        @assert captured["a"] == UInt64(10)
    finally
        close(captured)
    end
finally
    close(d)
end
Libdl.dlclose(library)
println("installed consumer passed: Julia ", VERSION,
    ", revision ", revision, ", package ", package_path)
