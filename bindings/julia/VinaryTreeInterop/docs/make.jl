using Documenter
using VinaryTreeInterop

DocMeta.setdocmeta!(VinaryTreeInterop, :DocTestSetup,
    :(using VinaryTreeInterop); recursive=true)

makedocs(
    modules=[VinaryTreeInterop],
    sitename="VinaryTreeInterop.jl",
    authors="Vinary Tree",
    format=Documenter.HTML(
        canonical="https://vinary-tree.github.io/vinary-tree-interop/julia/",
        prettyurls=get(ENV, "CI", "false") == "true",
        edit_link="master",
        repolink="https://github.com/vinary-tree/vinary-tree-interop",
    ),
    pages=[
        "Guide" => "index.md",
        "Dictionaries and bounded streams" => "dictionaries.md",
        "WFSTs and algebraic values" => "automata.md",
        "Ownership, concurrency, and safety" => "safety.md",
        "Performance and qualification" => "performance.md",
        "Installation and release" => "release.md",
        "API reference" => "api.md",
    ],
    checkdocs=:exports,
    doctest=true,
    remotes=nothing,
    warnonly=false,
)

isfile(joinpath(@__DIR__, "build", "index.html")) ||
    error("Documenter did not generate docs/build/index.html")

# Deployment is opt-in, after the exact General readback and a manual workflow
# dispatch from the package-specific TagBot tag, or from the master-only
# development-docs workflow. Ordinary CI only builds docs.
if get(ENV, "VTI_DOCS_DEPLOY", "false") == "true"
    deploydocs(
        repo="github.com/vinary-tree/vinary-tree-interop.git",
        dirname="julia",
        tag_prefix="VinaryTreeInterop-",
        devbranch="master",
        push_preview=false,
    )
end
