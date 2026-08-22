# Extraction provenance

This repository was extracted from the `vinary-tree-interop/` component and
the small set of interop-owned packaging files in
[`vinary-tree/liblevenshtein-rust`](https://github.com/vinary-tree/liblevenshtein-rust).
The extraction restores the ownership boundary intended by the modular ABI
design: no automaton implementation owns or publishes the family contract.

## Frozen source

| Field | Value |
|---|---|
| Source repository | `vinary-tree/liblevenshtein-rust` |
| Source commit | `7e6adac39aa82f2cb6337d2da18a8f66dd223f19` |
| Filtered commit | `3ba43295c407f72fad6339341f2dba36fd804772` |
| Source date | 2026-08-20 |
| Extraction date | 2026-08-22 |

The filter retained component source, language mirrors, .NET interop sources,
CMake and `pkg-config` metadata, native/opam staging scripts, four normative
diagrams, and the historical interop release workflow. Root-level repository
metadata and the Apache-2.0 license were then added as an explicit
initialization change, avoiding unrelated source-repository commits whose only
surviving file would otherwise have been the shared license.

The complete machine-readable old-to-new commit map remains in the local
filtered repository metadata at `.git/filter-repo/commit-map`. It is not a
runtime or release artifact.
