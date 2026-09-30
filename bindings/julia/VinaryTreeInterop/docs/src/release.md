# Installation and release contract

This Julia package lives in `bindings/julia/VinaryTreeInterop` inside the
shared interop repository. Its `Project.toml` version follows the coordinated
Vinary Tree release train; the Julia package name is **VinaryTreeInterop**.
The package subdirectory contains its own OSI-compatible `LICENSE`, as
required by General for a subdirectory package.

## Reproducible pre-registry installation

Use a new Julia environment and a reviewed immutable source commit:

```julia
using Pkg
Pkg.activate("/path/to/empty/consumer")
Pkg.add(PackageSpec(
    url="https://github.com/vinary-tree/vinary-tree-interop",
    rev="<full reviewed commit SHA>",
    subdir="bindings/julia/VinaryTreeInterop"))
using VinaryTreeInterop
```

`Pkg.develop(path=...)` is useful while editing but is **not** proof that a
consumer can install the package from a Git revision. CI's
`test/installed_consumer.jl` checks a clean environment populated by `Pkg.add`
from a Git URL and verifies that `pathof(VinaryTreeInterop)` is outside the
checkout. Native provider binaries are supplied by library-specific packages
or an ABI fixture; this shared package does not ship one. Record the resolved
Git tree and Julia version in consumer manifests.

## General registration (not executed for RC.6)

1. Freeze and review the exact source commit, including Julia tests,
   documentation, package license, `[compat]`, and the release-version check.
   Confirm CI and a fresh Git-installed consumer on supported Julia versions.
2. Confirm the public repository and target commit are reachable; obtain
   explicit release authorization. Install the official Registrator GitHub app
   on `vinary-tree/vinary-tree-interop` if it is not already installed.
3. Comment on that **exact commit**:
   `@JuliaRegistrator register subdir=bindings/julia/VinaryTreeInterop`.
   Registrator submits a General pull request; inspect its `repo`, `subdir`,
   UUID, version, tree hash, license, and compatibility metadata before merge.
   A General version is immutable: never rebuild or overwrite a published
   version from a different tree.
4. Wait for the General pull request to merge. Only then verify in a new
   environment that `Pkg.add("VinaryTreeInterop")` resolves the intended
   UUID, version, and source tree, and that a native-provider smoke test passes.
   Dispatch the read-only `julia-general-readback.yml` workflow with the
   exact version and full reviewed source SHA; it compares General's package
   tree hash to the Git subdirectory tree and runs the installed consumer.
   Capture the public registry commit/PR and consumer manifest as readback.
5. TagBot is optional and **does not register the package**. For this
   subdirectory, set `subdir: bindings/julia/VinaryTreeInterop`. Its default
   tag is `VinaryTreeInterop-v<version>`, distinct from the coordinated source
   tag `v<version>`. Do not let TagBot create or move the coordinated tag.
   A tag created with `GITHUB_TOKEN` does not trigger downstream GitHub
   workflows; use a deliberately configured deploy key or a separately
   reviewed manual documentation deployment if tag-triggered docs are needed.

## Documentation publication (manual and post-readback)

CI builds strict Documenter pages and runs doctests on Julia 1.10 and 1.12;
it does not write to GitHub Pages. Configure the repository's Pages source as
the `gh-pages` branch at its root. After General readback passes and a
package-specific immutable tag exists, deliberately dispatch
`julia-docs-deploy.yml` **from that exact tag** with its version and reviewed
source SHA. For example, after explicit authorization for a future version:

```bash
gh workflow run julia-docs-deploy.yml \
  --repo vinary-tree/vinary-tree-interop \
  --ref VinaryTreeInterop-v<version> \
  -f version=<version> -f source_sha=<full-reviewed-commit-SHA>
```

The workflow rejects a branch or mismatched tag, runs the public General
readback first, rebuilds with fatal doctest and exported-API checks, and only
then lets Documenter write the isolated `julia/` subtree of `gh-pages`.
`VTI_DOCS_DEPLOY` is unset in ordinary CI, so a build never deploys by
accident. Confirm the public `julia/stable` page and API navigation after
the workflow succeeds. This manual dispatch avoids relying on TagBot's
`GITHUB_TOKEN`-created tags to trigger another workflow.

No RC.6 Julia registration, tag, or package publication is performed by this
documentation work. The existing [shared release contract](https://github.com/vinary-tree/vinary-tree-interop/blob/master/docs/releasing.md)
remains authoritative for coordinated source tags and registry lanes. General
registration is a separate, explicitly approved step, **not** an automatic
side effect of the shared release workflow.

Official references: [Pkg subdirectory installs](https://pkgdocs.julialang.org/v1/managing-packages/),
[General rules](https://github.com/JuliaRegistries/General#registering-a-package-in-general),
[Registrator's subdirectory trigger](https://github.com/JuliaRegistries/Registrator.jl#registering-a-package-in-a-subdirectory),
and [TagBot subpackage behavior](https://github.com/JuliaRegistries/TagBot#subpackage-configuration).
Documenter's [monorepo deployment guide](https://documenter.juliadocs.org/stable/man/hosting/#Deploying-from-a-monorepo)
defines the `dirname` and package tag-prefix behavior used here.
