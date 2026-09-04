# npm coordinate migration for the interop contract

## Terms and intent

An npm *coordinate* is the scoped package name that identifies an immutable
sequence of published versions. The canonical coordinate for this repository
is `@vinary-tree/vinary-tree-interop`: its leaf is the repository and component
name, so registry identity, source ownership, and documentation agree.

RC4 was published under `@vinary-tree/interop`. That shorter coordinate is a
legacy publication mistake, not a second implementation and not an alias that
new dependency manifests should select. npm versions are immutable, so RC4 is
preserved as historical evidence and RC5 begins the canonical version line.

| Role | Coordinate | Policy from RC5 onward |
|---|---|---|
| Canonical interop package | `@vinary-tree/vinary-tree-interop` | Publish, document, test, and reference directly. |
| Legacy RC4 package | `@vinary-tree/interop` | Retain immutable bytes; deprecate with a pointer to the canonical package after RC5 passes public-install smoke tests. |
| Shared runtime | `@vinary-tree/javascript-runtime` | Consume the canonical interop package at the exact family RC. |

## Machine-enforced identity

[`release/version.json`](../release/version.json) owns both the canonical
version and `coordinates.npmPackage`. The release synchronizer writes the npm
manifest and lockfile names from that field and rejects any disagreement. A
repository-wide coordinate gate also rejects legacy or accidentally composed
names outside this migration record. This makes a package rename an explicit
release-model change rather than an incidental edit to `package.json`.

## Publication and verification sequence

The order is fail-closed: no legacy coordinate is deprecated until the
canonical artifact is independently usable.

```text
publish canonical RC5 with provenance and the `next` dist-tag
verify public metadata names this repository and exact RC5 source
install the canonical package into an empty project
run the retained-resource ABI smoke tests
move canonical `latest` only after the complete release-train smoke gate
deprecate every legacy version with the canonical replacement coordinate
verify both registry pages and dist-tags by unauthenticated read-back
```

Distribution tags are mutable pointers; package versions are not. Rollback
therefore restores a prior tag target and never deletes, overwrites, or reuses
a version. The unscoped legacy `liblevenshtein` package has a separate
compatibility policy and is not affected by this coordinate migration.

## Consumer migration

Replace the dependency key and import specifier together:

```json
{
  "dependencies": {
    "@vinary-tree/vinary-tree-interop": "4.0.0-rc.6"
  }
}
```

```js
import { INTEROP_ABI_VERSION } from "@vinary-tree/vinary-tree-interop";
```

No resource conversion is involved. The two packages describe the same ABI;
the change aligns package identity with its owning component and prevents a
second runtime or interop implementation from entering the process.

## Security and provenance

Publication uses the repository's npm trusted publisher and protected `npm`
environment. Registry read-back must confirm the provenance-bearing tarball,
repository URL, version, and package name before any dist-tag or deprecation
mutation. Tokens, passkeys, and one-time codes never belong in commands saved
to the repository, build logs, release notes, or support transcripts.
