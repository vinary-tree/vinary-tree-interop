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
        "API reference" => "api.md",
    ],
    checkdocs=:exports,
    doctest=true,
    remotes=nothing,
    warnonly=false,
)
