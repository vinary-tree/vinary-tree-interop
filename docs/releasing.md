# Releasing the shared interop contract

The shared interop repository publishes one contract through several package
registries. A release is a promotion of tested immutable artifacts, not a
collection of unrelated builds.

## Version authorities

`release/version.json` contains the canonical family release candidate and its
registry spellings plus the canonical Maven coordinate
`io.vinarytree:vinary-tree-interop`.
`scripts/sync-release-version.py --write` derives manifest versions and Maven
identity; the same command without `--write` rejects drift. The Java package
remains `io.vinarytree.interop`: Java namespaces and Maven repository
coordinates are deliberately independent. Package version 4 does not change
`VT_ABI_VERSION`, which remains governed by
[ABI evolution](abi-evolution.md).

The synchronizer also owns the `vinary-tree-interop` entry in `Cargo.lock`.
Both `cargo package --locked` and a byte-for-byte post-build lock check are
required; a release job never repairs a stale lock after checkout.

The `4.0.0-rc.4` train uses `4.0.0rc4` on PyPI, `4.0.0~rc4` in opam, and a
`/v4` Go module path. Cabal and fpm accept numeric package versions only, so CI
builds their `4.0.0` source candidates but the release workflow cannot upload
either candidate to Hackage or the fpm registry until the final `4.0.0`
release. The Haskell manifest records `x-release-candidate: rc.4`; the Fortran
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

Pushing `v4.0.0-rc.4` creates only the immutable source ref. The release
workflow is deliberately manual: `validate-only` stages every candidate and
creates the checksummed GitHub prerelease, while a later registry dispatch at
the same tag enables exactly one protected uploader.

```bash
gh workflow run release.yml \
  --repo vinary-tree/vinary-tree-interop \
  --ref v4.0.0-rc.4 \
  -f registry=validate-only

gh workflow run release.yml \
  --repo vinary-tree/vinary-tree-interop \
  --ref v4.0.0-rc.4 \
  -f registry=npm
```

A branch dispatch fails the contract job. `validate-only` cannot enter any
registry environment; `npm`, `crates-io`, `pypi`, `maven-central`, `nuget`,
`go-module`, and `opam` each authorize only their namesake job. This separation
permits the RC's npm lane to ship without accidentally publishing the
still-unconfigured ecosystem lanes.

The canonical RC.4 source already published its crate and npm package, but its
nested JReleaser invocation omitted Git-root discovery and therefore cannot
publish the still-unpublished Maven coordinate. The append-only corrective
source tag `v4.0.0-rc.4-release.1` contains release automation, release
identity validation, and documentation changes only. Its workflow guard
permits exactly `validate-only` and `maven-central`; it rejects crate, npm,
PyPI, NuGet, Go, and opam publication so no public RC.4 coordinate can be
rebuilt or overwritten. The package version remains `4.0.0-rc.4`, and the
canonical tag remains immutable.

NuGet subsequently introduced keyless trusted publishing. Corrective source
`v4.0.0-rc.4-release.2` replaces the long-lived NuGet API key with
`NuGet/login@v1`, grants `id-token: write` only to the upload job, and consumes
the one-use temporary key returned by nuget.org. It additionally authorizes the
still-unpublished `nuget` lane while continuing to reject crate and npm
republication. PyPI, Go, and opam remain available from the already-validated
canonical source; Maven remains available from the already-validated first
corrective source.

The same corrective source prepares future crates.io publication for keyless
authentication. Register the `vinary-tree-interop` crate's trusted publisher
as repository `vinary-tree/vinary-tree-interop`, workflow `release.yml`, and
environment `crates-io-interop`. The publish job uses
`rust-lang/crates-io-auth-action@v1` and its short-lived token rather than a
stored `CARGO_REGISTRY_TOKEN`. The corrective guard continues to reject the
crate lane for RC.4 because that immutable crate version is already public;
the OIDC path first becomes eligible for a later, unused crate version.

Before dispatching `maven-central`, the Central Portal must show
`io.vinarytree` as a verified namespace available to the publishing token.
The lane fails closed by asserting the staged
`io/vinarytree/vinary-tree-interop` repository path, and JReleaser declares
`io.vinarytree` explicitly as its deployment namespace. It selects the sole
named deployer and enables Git-root discovery because its release configuration
lives below the repository root. Do not substitute one of liblevenshtein's
historical `com.github.*` groups: this shared contract has no legacy Maven
coordinate to relocate.

After the corrective validation run succeeds, publish only the Maven artifact:

```bash
gh workflow run release.yml \
  --repo vinary-tree/vinary-tree-interop \
  --ref v4.0.0-rc.4-release.1 \
  -f registry=validate-only

gh workflow run release.yml \
  --repo vinary-tree/vinary-tree-interop \
  --ref v4.0.0-rc.4-release.1 \
  -f registry=maven-central
```

Validate the second corrective source before its NuGet-only dispatch:

```bash
gh workflow run release.yml \
  --repo vinary-tree/vinary-tree-interop \
  --ref v4.0.0-rc.4-release.2 \
  -f registry=validate-only

gh workflow run release.yml \
  --repo vinary-tree/vinary-tree-interop \
  --ref v4.0.0-rc.4-release.2 \
  -f registry=nuget
```

The release tag is `v4.0.0-rc.4`. Go uses the additional immutable submodule
tag `bindings/go/v4.0.0-rc.4`. npm publishes the release candidate with the
`next` distribution tag. npm assigned `latest` to the inert `0.0.0`
coordinate-reservation artifact despite its explicit `bootstrap` tag. After
the OIDC-published RC passes installed-artifact smoke tests, retarget
`@vinary-tree/interop@latest` to `4.0.0-rc.4`, remove the `bootstrap`
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
