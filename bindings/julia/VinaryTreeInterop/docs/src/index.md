# VinaryTreeInterop.jl

`VinaryTreeInterop` is the shared Julia facade for Vinary Tree's versioned
native resource ABI. It makes provider-owned dictionaries behave like
`AbstractDict`s and exposes snapshots, bounded entry streams, scalar weighted
finite-state transducers (WFSTs), and immutable lattice values. It does **not**
construct automata or select a native library; a library-specific binding must
create a compatible resource first.

## Start here

Install the package from its repository subdirectory until its General
registration is public:

```julia
using Pkg
Pkg.add(url="https://github.com/vinary-tree/vinary-tree-interop",
    subdir="bindings/julia/VinaryTreeInterop")
using VinaryTreeInterop
```

Pin a tested Git revision with `Pkg.PackageSpec(url=..., rev="<full commit>",
subdir=...)` for reproducible pre-registry consumers. A clean-environment
installation check is run by CI; see [Installation and release](release.md).

Given an *owned* `Resource` returned by a native provider, use:

```julia
function lookup(provider_resource::VinaryTreeInterop.Resource, term::String)
    dictionary = VinaryTreeInterop.dictionary(provider_resource; take=true)
    try
        return get(dictionary, term, nothing)
    finally
        close(dictionary)
    end
end
```

`take=true` transfers the caller's existing reference. Without it, the facade
retains a second reference and the caller must close the original separately.
The provider must keep its ABI code and vtables loaded until all related
resources and snapshots are closed.

The [dictionary guide](dictionaries.md) covers collection behavior and bounded
scans. [WFSTs and algebraic values](automata.md) covers the other public
capabilities. [Ownership and safety](safety.md) explains concurrency rules;
[performance](performance.md) reports measured boundary costs; the
[API reference](api.md) lists every exported symbol.

```jldoctest
julia> using VinaryTreeInterop

julia> Int(BatchLimits(2, 8, 2).max_entries)
2

julia> VinaryTreeInterop.UNIT_UNICODE_SCALAR isa UnitDomain
true
```
