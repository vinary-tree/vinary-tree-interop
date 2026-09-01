#!/usr/bin/env python3
"""Validate or write every registry spelling of the canonical release version."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION_FILE = ROOT / "release/version.json"
GENERATED_TREE_PARTS = frozenset(
    {".git", ".venv", "_build", "build", "dist", "node_modules", "target", "venv"}
)
COORDINATE_MIGRATION_RECORD = Path("docs/npm-coordinate-migration.md")


def canonical_versions(model: dict[str, object]) -> dict[str, str]:
    canonical = str(model["canonical"])
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)-rc\.(\d+)", canonical)
    if match is None:
        raise ValueError(
            f"canonical version is not a numbered release candidate: {canonical}"
        )
    major, minor, patch, candidate = match.groups()
    base = f"{major}.{minor}.{patch}"
    return {
        "cargo": canonical,
        "cmake": canonical,
        "fpm": base,
        "goTag": f"v{canonical}",
        "hackage": base,
        "maven": canonical,
        "npm": canonical,
        "nuget": canonical,
        "opam": f"{base}~rc{candidate}",
        "pkgConfig": canonical,
        "pypi": f"{base}rc{candidate}",
        "swiftTag": canonical,
    }


def replace(path: str, pattern: str, replacement: str, expected: int = 1) -> None:
    target = ROOT / path
    original = target.read_text(encoding="utf-8")
    updated, count = re.subn(pattern, replacement, original, flags=re.MULTILINE)
    if count != expected:
        raise ValueError(f"{path}: expected {expected} version fields, found {count}")
    target.write_text(updated, encoding="utf-8")


def rewrite_candidate_tokens(patterns: tuple[str, ...], canonical: str) -> None:
    base, candidate = canonical.split("-rc.", 1)
    escaped = re.escape(base)
    replacements = (
        (rf"{escaped}\.rc\.\d+", f"{base}.rc.{candidate}"),
        (rf"{escaped}~rc\d+", f"{base}~rc{candidate}"),
        (rf"{escaped}rc\d+-\d+", f"{base}rc{candidate}-1"),
        (rf"{escaped}rc\d+", f"{base}rc{candidate}"),
        (rf"{escaped}-rc\.\d+", canonical),
        (r"x-release-candidate: rc\.\d+", f"x-release-candidate: rc.{candidate}"),
    )
    for pattern in patterns:
        for target in ROOT.glob(pattern):
            relative = target.relative_to(ROOT)
            if not target.is_file() or GENERATED_TREE_PARTS.intersection(relative.parts):
                continue
            source = target.read_text(encoding="utf-8")
            for version_pattern, replacement in replacements:
                source = re.sub(version_pattern, replacement, source)
            target.write_text(source, encoding="utf-8")


def release_coordinates(model: dict[str, object]) -> tuple[str, str, str, str]:
    coordinates = model.get("coordinates")
    if not isinstance(coordinates, dict):
        raise TypeError("release/version.json requires coordinates")
    group = coordinates.get("mavenGroup")
    artifact = coordinates.get("mavenArtifact")
    java_package = coordinates.get("javaPackage")
    npm_package = coordinates.get("npmPackage")
    if not all(
        isinstance(value, str)
        for value in (group, artifact, java_package, npm_package)
    ):
        raise TypeError(
            "release/version.json requires string coordinates.mavenGroup and "
            "coordinates.mavenArtifact and coordinates.javaPackage and "
            "coordinates.npmPackage"
        )
    return group, artifact, java_package, npm_package


def forbidden_npm_coordinates() -> tuple[tuple[str, str], ...]:
    legacy_interop = "/".join(("@vinary-tree", "interop"))
    legacy_runtime = "/".join(("@vinary-tree", "vinary-tree"))
    malformed_composition = "/".join(
        ("@vinary-tree", "javascript-runtime-interop")
    )
    return (
        ("legacy interop coordinate", legacy_interop),
        ("legacy runtime coordinate", legacy_runtime),
        ("malformed runtime/interop composition", malformed_composition),
    )


def npm_coordinate_violation(source: str) -> str | None:
    for label, coordinate in forbidden_npm_coordinates():
        pattern = re.compile(re.escape(coordinate) + r"(?![A-Za-z0-9._-])")
        if pattern.search(source) is not None:
            return label
    return None


def validate_npm_coordinates() -> list[str]:
    """Reject legacy or accidentally composed public npm identities."""

    failures: list[str] = []
    canonical_examples = (
        "@vinary-tree/vinary-tree-interop",
        "@vinary-tree/javascript-runtime",
        "@vinary-tree/javascript-runtime/wasm",
    )
    for coordinate in canonical_examples:
        if npm_coordinate_violation(coordinate) is not None:
            failures.append(f"coordinate gate rejects canonical example: {coordinate}")
    for label, coordinate in forbidden_npm_coordinates():
        if npm_coordinate_violation(f'"{coordinate}@4.0.0-rc.4"') != label:
            failures.append(f"coordinate gate fails to reject {label}")
    for target in ROOT.rglob("*"):
        if not target.is_file():
            continue
        relative = target.relative_to(ROOT)
        if relative == COORDINATE_MIGRATION_RECORD:
            continue
        if GENERATED_TREE_PARTS.intersection(relative.parts):
            continue
        try:
            source = target.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for label, coordinate in forbidden_npm_coordinates():
            pattern = re.compile(re.escape(coordinate) + r"(?![A-Za-z0-9._-])")
            match = pattern.search(source)
            if match is None:
                continue
            line = source.count("\n", 0, match.start()) + 1
            failures.append(f"{relative}:{line}: {label} is forbidden")
    return failures


def write_versions(
    expected: dict[str, str],
    dist_tag: str,
    maven_group: str,
    maven_artifact: str,
    npm_package: str,
) -> None:
    package_path = ROOT / "bindings/javascript/package.json"
    package = json.loads(package_path.read_text(encoding="utf-8"))
    package["name"] = npm_package
    package["version"] = expected["npm"]
    package.setdefault("publishConfig", {})["tag"] = dist_tag
    package_path.write_text(json.dumps(package, indent=2) + "\n", encoding="utf-8")

    lock_path = ROOT / "bindings/javascript/package-lock.json"
    lock = json.loads(lock_path.read_text(encoding="utf-8"))
    lock["name"] = npm_package
    lock["version"] = expected["npm"]
    lock["packages"][""]["name"] = npm_package
    lock["packages"][""]["version"] = expected["npm"]
    lock_path.write_text(json.dumps(lock, indent=2) + "\n", encoding="utf-8")

    replace("Cargo.toml", r'^version = "[^"]+"$', f'version = "{expected["cargo"]}"')
    replace(
        "Cargo.lock",
        r'(\[\[package\]\]\nname = "vinary-tree-interop"\nversion = ")[^"]+',
        rf'\g<1>{expected["cargo"]}',
    )
    replace(
        "bindings/python/pyproject.toml",
        r'^version = "[^"]+"$',
        f'version = "{expected["pypi"]}"',
    )
    replace(
        "bindings/julia/VinaryTreeInterop/Project.toml",
        r'^version = "[^"]+"$',
        f'version = "{expected["cargo"]}"',
    )
    raku_path = ROOT / "bindings/raku/META6.json"
    raku = json.loads(raku_path.read_text(encoding="utf-8"))
    raku["version"] = expected["cargo"]
    raku_path.write_text(json.dumps(raku, indent=2) + "\n", encoding="utf-8")
    replace(
        "bindings/jvm/build.gradle.kts",
        r'^version = "[^"]+"$',
        f'version = "{expected["maven"]}"',
    )
    replace(
        "bindings/jvm/build.gradle.kts",
        r'^group = "[^"]+"$',
        f'group = "{maven_group}"',
    )
    replace(
        "bindings/jvm/jreleaser.yml",
        r"^  version: \S+$",
        f"  version: {expected['maven']}",
    )
    replace(
        "bindings/jvm/jreleaser.yml",
        r"^      groupId: \S+$",
        f"      groupId: {maven_group}",
    )
    replace(
        "bindings/jvm/jreleaser.yml",
        r"^      artifactId: \S+$",
        f"      artifactId: {maven_artifact}",
    )
    replace(
        "bindings/jvm/jreleaser.yml",
        r"^        namespace: \S+$",
        f"        namespace: {maven_group}",
    )
    replace(
        "bindings/dotnet/src/VinaryTree.Interop/VinaryTree.Interop.csproj",
        r"^    <Version>[^<]+</Version>$",
        f"    <Version>{expected['nuget']}</Version>",
    )
    replace(
        "bindings/haskell/vinary-tree-interop.cabal",
        r"^version: \S+$",
        f"version: {expected['hackage']}",
    )
    candidate = expected["opam"].split("~", 1)[1].replace("rc", "rc.")
    replace(
        "bindings/haskell/vinary-tree-interop.cabal",
        r"^x-release-candidate: \S+$",
        f"x-release-candidate: {candidate}",
    )
    replace(
        "bindings/fortran/fpm.toml",
        r'^version = "[^"]+"$',
        f'version = "{expected["fpm"]}"',
    )
    replace(
        "bindings/ocaml/dune-project",
        r"^\(version [^)]+\)$",
        f"(version {expected['opam']})",
    )
    major = expected["goTag"].split(".", 1)[0].removeprefix("v")
    replace(
        "bindings/go/go.mod",
        r"^module \S+$",
        f"module github.com/vinary-tree/vinary-tree-interop/bindings/go/v{major}",
    )
    replace(
        "cmake/vinary-tree-interopConfigVersion.cmake",
        r'^set\(PACKAGE_VERSION "[^"]+"\)$',
        f'set(PACKAGE_VERSION "{expected["cmake"]}")',
    )
    replace(
        "pkgconfig/vinary-tree-interop.pc",
        r"^Version: \S+$",
        f"Version: {expected['pkgConfig']}",
    )
    replace(
        "README.md", r"^\| Version \| [^|]+\|$", f"| Version | {expected['cargo']} |"
    )
    rewrite_candidate_tokens(
        (
            "bindings/**/*.md",
            "bindings/**/*.opam",
            "docs/abi-evolution.md",
            "docs/diagrams/abi-evolution-timeline.puml",
        ),
        expected["cargo"],
    )


def actual_versions() -> dict[str, str]:
    package = json.loads((ROOT / "bindings/javascript/package.json").read_text())
    lock = json.loads((ROOT / "bindings/javascript/package-lock.json").read_text())

    def capture(path: str, pattern: str) -> str:
        text = (ROOT / path).read_text(encoding="utf-8")
        match = re.search(pattern, text, flags=re.MULTILINE)
        if match is None:
            raise ValueError(f"{path}: version field is missing")
        return match.group(1)

    go_module = capture("bindings/go/go.mod", r"^module (\S+)$")
    return {
        "cargo": capture("Cargo.toml", r'^version = "([^"]+)"$'),
        "cargoLock": capture(
            "Cargo.lock",
            r'\[\[package\]\]\nname = "vinary-tree-interop"\nversion = "([^"]+)"',
        ),
        "cmake": capture(
            "cmake/vinary-tree-interopConfigVersion.cmake",
            r'^set\(PACKAGE_VERSION "([^"]+)"\)$',
        ),
        "fpm": capture("bindings/fortran/fpm.toml", r'^version = "([^"]+)"$'),
        "goMajor": go_module.rsplit("/v", 1)[-1],
        "hackage": capture(
            "bindings/haskell/vinary-tree-interop.cabal", r"^version: (\S+)$"
        ),
        "hackageCandidate": capture(
            "bindings/haskell/vinary-tree-interop.cabal",
            r"^x-release-candidate: (\S+)$",
        ),
        "maven": capture("bindings/jvm/build.gradle.kts", r'^version = "([^"]+)"$'),
        "julia": capture(
            "bindings/julia/VinaryTreeInterop/Project.toml",
            r'^version = "([^"]+)"$',
        ),
        "mavenGroup": capture(
            "bindings/jvm/build.gradle.kts", r'^group = "([^"]+)"$'
        ),
        "mavenJReleaser": capture("bindings/jvm/jreleaser.yml", r"^  version: (\S+)$"),
        "mavenJReleaserGroup": capture(
            "bindings/jvm/jreleaser.yml", r"^      groupId: (\S+)$"
        ),
        "mavenJReleaserArtifact": capture(
            "bindings/jvm/jreleaser.yml", r"^      artifactId: (\S+)$"
        ),
        "mavenNamespace": capture(
            "bindings/jvm/jreleaser.yml", r"^        namespace: (\S+)$"
        ),
        "npmPackage": str(package["name"]),
        "npm": str(package["version"]),
        "npmLockPackage": str(lock["name"]),
        "npmLock": str(lock["version"]),
        "npmLockRootPackage": str(lock["packages"][""]["name"]),
        "npmLockRoot": str(lock["packages"][""]["version"]),
        "nuget": capture(
            "bindings/dotnet/src/VinaryTree.Interop/VinaryTree.Interop.csproj",
            r"^    <Version>([^<]+)</Version>$",
        ),
        "opam": capture("bindings/ocaml/dune-project", r"^\(version ([^)]+)\)$"),
        "pkgConfig": capture("pkgconfig/vinary-tree-interop.pc", r"^Version: (\S+)$"),
        "pypi": capture("bindings/python/pyproject.toml", r'^version = "([^"]+)"$'),
        "readme": capture("README.md", r"^\| Version \| ([^| ]+) \|$"),
        "raku": str(
            json.loads((ROOT / "bindings/raku/META6.json").read_text())["version"]
        ),
        "releaseDocsCandidate": capture(
            "docs/releasing.md", r"Haskell manifest records `x-release-candidate: (rc\.\d+)`"
        ),
    }


def validate(expected: dict[str, str], model: dict[str, object]) -> list[str]:
    failures: list[str] = []
    declared = model.get("registries")
    if declared != expected:
        failures.append(
            f"release/version.json registries differ: expected {expected}, got {declared}"
        )
    if model.get("publication", {}).get("hackage") is not False:  # type: ignore[union-attr]
        failures.append(
            "Hackage publication must remain disabled for a release candidate"
        )
    if model.get("publication", {}).get("fpm") is not False:  # type: ignore[union-attr]
        failures.append("fpm publication must remain disabled for a release candidate")

    actual = actual_versions()
    maven_group, maven_artifact, java_package, npm_package = release_coordinates(model)
    if maven_group != "io.vinarytree":
        failures.append("the canonical Maven group must be io.vinarytree")
    if java_package != "io.vinarytree.interop":
        failures.append("the canonical Java package must be io.vinarytree.interop")
    if npm_package != "@vinary-tree/vinary-tree-interop":
        failures.append(
            "the canonical npm package must be @vinary-tree/vinary-tree-interop"
        )
    java_root = ROOT / "bindings/jvm/src/main/java" / Path(*java_package.split("."))
    if not java_root.is_dir():
        failures.append(f"canonical Java package directory is missing: {java_root}")
    release_workflow = (ROOT / ".github/workflows/release.yml").read_text(
        encoding="utf-8"
    )
    for marker in (
        "deploy --git-root-search --deployer-name sonatype",
        "scripts/check-release-ref.py",
        '--registry "$REGISTRY"',
        './scripts/stage-ocaml-package.sh dist "$GITHUB_REF_NAME"',
        "environment: opam",
        "environment: github-release-interop",
        'fork="vinary-tree/opam-repository"',
        "gh auth setup-git",
        '["registries"]["opam"]',
        '--head "vinary-tree:$branch"',
        "secrets.OPAM_GITHUB_TOKEN",
    ):
        if marker not in release_workflow:
            failures.append(f"release workflow is missing {marker}")
    for forbidden in (
        "account=$(gh api user",
        "gh repo fork ocaml/opam-repository",
        "environment: opam-interop",
    ):
        if forbidden in release_workflow:
            failures.append(f"release workflow retains forbidden opam logic: {forbidden}")
    package = json.loads((ROOT / "bindings/javascript/package.json").read_text())
    publication = model.get("publication", {})
    if not isinstance(publication, dict) or publication.get("distTag") != "next":
        failures.append("npm release candidates must use the next dist-tag")
    if package.get("publishConfig", {}).get("tag") != "next":
        failures.append("npm package publishConfig must protect latest with tag=next")
    checks = {
        "cargo": expected["cargo"],
        "cargoLock": expected["cargo"],
        "cmake": expected["cmake"],
        "fpm": expected["fpm"],
        "goMajor": expected["goTag"].split(".", 1)[0].removeprefix("v"),
        "hackage": expected["hackage"],
        "hackageCandidate": "rc." + expected["opam"].rsplit("rc", 1)[1],
        "maven": expected["maven"],
        "julia": expected["cargo"],
        "mavenGroup": maven_group,
        "mavenJReleaser": expected["maven"],
        "mavenJReleaserGroup": maven_group,
        "mavenJReleaserArtifact": maven_artifact,
        "mavenNamespace": maven_group,
        "npmPackage": npm_package,
        "npm": expected["npm"],
        "npmLockPackage": npm_package,
        "npmLock": expected["npm"],
        "npmLockRootPackage": npm_package,
        "npmLockRoot": expected["npm"],
        "nuget": expected["nuget"],
        "opam": expected["opam"],
        "pkgConfig": expected["pkgConfig"],
        "pypi": expected["pypi"],
        "readme": expected["cargo"],
        "raku": expected["cargo"],
        "releaseDocsCandidate": "rc." + expected["opam"].rsplit("rc", 1)[1],
    }
    for name, wanted in checks.items():
        if actual[name] != wanted:
            failures.append(f"{name}: expected {wanted}, got {actual[name]}")
    failures.extend(validate_npm_coordinates())
    return failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--write", action="store_true", help="rewrite manifest versions"
    )
    args = parser.parse_args()
    model = json.loads(VERSION_FILE.read_text(encoding="utf-8"))
    expected = canonical_versions(model)
    maven_group, maven_artifact, _java_package, npm_package = release_coordinates(model)
    publication = model.get("publication", {})
    if not isinstance(publication, dict) or not isinstance(
        publication.get("distTag"), str
    ):
        raise TypeError("release/version.json requires string publication.distTag")
    if args.write:
        write_versions(
            expected,
            publication["distTag"],
            maven_group,
            maven_artifact,
            npm_package,
        )
    failures = validate(expected, model)
    if failures:
        for failure in failures:
            print(f"release-version error: {failure}", file=sys.stderr)
        return 1
    print(f"release versions agree with {model['canonical']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
