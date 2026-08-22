# Releasing the shared interop contract

The shared interop repository publishes one contract through several package
registries. A release is a promotion of tested immutable artifacts, not a
collection of unrelated builds.

## Version authorities

`release/version.json` contains the canonical family release candidate and its
registry spellings. `scripts/sync-release-version.py --write` derives manifest
versions; the same command without `--write` rejects drift. Package version 4
does not change `VT_ABI_VERSION`, which remains governed by
[ABI evolution](abi-evolution.md).

The `4.0.0-rc.1` train uses `4.0.0rc1` on PyPI, `4.0.0~rc1` in opam, and a
`/v4` Go module path. Cabal and fpm accept numeric package versions only, so CI
builds their `4.0.0` source candidates but the release workflow cannot upload
either candidate to Hackage or the fpm registry until the final `4.0.0`
release. The Haskell manifest records `x-release-candidate: rc.1`; the Fortran
candidate identity remains in `release/version.json` and the release tag.

## Pipeline

1. Validate generated versions, Rust layouts, C/C++ syntax, and every available
   language mirror.
2. Construct registry artifacts once and upload them as workflow artifacts.
3. Inspect package contents, hashes, and provenance before entering protected
   publication environments.
4. Publish each registry lane independently from its staged artifact, except
   the explicitly embargoed Hackage and fpm candidates.
5. Install from the public coordinate and rerun its smoke test.

The release tag is `v4.0.0-rc.1`. Go uses the additional immutable submodule
tag `bindings/go/v4.0.0-rc.1`. npm publishes the release candidate with the
`next` distribution tag. No release-candidate workflow changes `latest`.

## Failure and rollback

Published versions and Git tags are never moved or overwritten. If a registry
accepts an artifact and a later lane fails, repair the lane and issue the next
release candidate. npm rollback changes only a distribution tag; it never
deletes `4.0.0-rc.1`. ABI incompatibility requires a new interface identifier
or coordinated ABI version according to the evolution policy, not a package
republish.
