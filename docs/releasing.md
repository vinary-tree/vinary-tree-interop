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

The `4.0.0-rc.3` train uses `4.0.0rc3` on PyPI, `4.0.0~rc3` in opam, and a
`/v4` Go module path. Cabal and fpm accept numeric package versions only, so CI
builds their `4.0.0` source candidates but the release workflow cannot upload
either candidate to Hackage or the fpm registry until the final `4.0.0`
release. The Haskell manifest records `x-release-candidate: rc.3`; the Fortran
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

### Exact-tag dispatch protocol

Pushing `v4.0.0-rc.3` creates only the immutable source ref. The release
workflow is deliberately manual: `validate-only` stages every candidate and
creates the checksummed GitHub prerelease, while a later registry dispatch at
the same tag enables exactly one protected uploader.

```bash
gh workflow run release.yml \
  --repo vinary-tree/vinary-tree-interop \
  --ref v4.0.0-rc.3 \
  -f registry=validate-only

gh workflow run release.yml \
  --repo vinary-tree/vinary-tree-interop \
  --ref v4.0.0-rc.3 \
  -f registry=npm
```

A branch dispatch fails the contract job. `validate-only` cannot enter any
registry environment; `npm`, `crates-io`, `pypi`, `maven-central`, `nuget`,
`go-module`, and `opam` each authorize only their namesake job. This
separation permits the RC's npm lane to ship without accidentally publishing
the still-unconfigured ecosystem lanes.

The release tag is `v4.0.0-rc.3`. Go uses the additional immutable submodule
tag `bindings/go/v4.0.0-rc.3`. npm publishes the release candidate with the
`next` distribution tag. npm assigned `latest` to the inert `0.0.0`
coordinate-reservation artifact despite its explicit `bootstrap` tag. After
the OIDC-published RC passes installed-artifact smoke tests, retarget
`@vinary-tree/interop@latest` to `4.0.0-rc.3`, remove the `bootstrap`
dist-tag, and deprecate `0.0.0` as a reservation-only artifact. This scoped
repair is distinct from promoting the legacy unscoped `liblevenshtein`
package, whose `latest` pointer remains `2.0.4` during the RC.

## Failure and rollback

Published versions and Git tags are never moved or overwritten. If a registry
accepts an artifact and a later lane fails, repair the lane and issue the next
unused release candidate. npm rollback changes only a distribution tag; it
never deletes the rejected coordinate. ABI incompatibility requires a new
interface identifier or coordinated ABI version according to the evolution
policy, not a package republish.
