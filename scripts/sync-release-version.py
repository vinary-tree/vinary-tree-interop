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


def write_versions(expected: dict[str, str], dist_tag: str) -> None:
    package_path = ROOT / "bindings/javascript/package.json"
    package = json.loads(package_path.read_text(encoding="utf-8"))
    package["version"] = expected["npm"]
    package.setdefault("publishConfig", {})["tag"] = dist_tag
    package_path.write_text(json.dumps(package, indent=2) + "\n", encoding="utf-8")

    lock_path = ROOT / "bindings/javascript/package-lock.json"
    lock = json.loads(lock_path.read_text(encoding="utf-8"))
    lock["version"] = expected["npm"]
    lock["packages"][""]["version"] = expected["npm"]
    lock_path.write_text(json.dumps(lock, indent=2) + "\n", encoding="utf-8")

    replace("Cargo.toml", r'^version = "[^"]+"$', f'version = "{expected["cargo"]}"')
    replace(
        "bindings/python/pyproject.toml",
        r'^version = "[^"]+"$',
        f'version = "{expected["pypi"]}"',
    )
    replace(
        "bindings/jvm/build.gradle.kts",
        r'^version = "[^"]+"$',
        f'version = "{expected["maven"]}"',
    )
    replace(
        "bindings/jvm/jreleaser.yml",
        r"^  version: \S+$",
        f"  version: {expected['maven']}",
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
        ("bindings/**/*.md", "bindings/**/*.opam", "docs/**/*.md", "docs/**/*.puml"),
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
        "mavenJReleaser": capture("bindings/jvm/jreleaser.yml", r"^  version: (\S+)$"),
        "npm": str(package["version"]),
        "npmLock": str(lock["version"]),
        "npmLockRoot": str(lock["packages"][""]["version"]),
        "nuget": capture(
            "bindings/dotnet/src/VinaryTree.Interop/VinaryTree.Interop.csproj",
            r"^    <Version>([^<]+)</Version>$",
        ),
        "opam": capture("bindings/ocaml/dune-project", r"^\(version ([^)]+)\)$"),
        "pkgConfig": capture("pkgconfig/vinary-tree-interop.pc", r"^Version: (\S+)$"),
        "pypi": capture("bindings/python/pyproject.toml", r'^version = "([^"]+)"$'),
        "readme": capture("README.md", r"^\| Version \| ([^| ]+) \|$"),
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
    package = json.loads((ROOT / "bindings/javascript/package.json").read_text())
    publication = model.get("publication", {})
    if not isinstance(publication, dict) or publication.get("distTag") != "next":
        failures.append("npm release candidates must use the next dist-tag")
    if package.get("publishConfig", {}).get("tag") != "next":
        failures.append("npm package publishConfig must protect latest with tag=next")
    checks = {
        "cargo": expected["cargo"],
        "cmake": expected["cmake"],
        "fpm": expected["fpm"],
        "goMajor": expected["goTag"].split(".", 1)[0].removeprefix("v"),
        "hackage": expected["hackage"],
        "hackageCandidate": "rc." + expected["opam"].rsplit("rc", 1)[1],
        "maven": expected["maven"],
        "mavenJReleaser": expected["maven"],
        "npm": expected["npm"],
        "npmLock": expected["npm"],
        "npmLockRoot": expected["npm"],
        "nuget": expected["nuget"],
        "opam": expected["opam"],
        "pkgConfig": expected["pkgConfig"],
        "pypi": expected["pypi"],
        "readme": expected["cargo"],
        "releaseDocsCandidate": "rc." + expected["opam"].rsplit("rc", 1)[1],
    }
    for name, wanted in checks.items():
        if actual[name] != wanted:
            failures.append(f"{name}: expected {wanted}, got {actual[name]}")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--write", action="store_true", help="rewrite manifest versions"
    )
    args = parser.parse_args()
    model = json.loads(VERSION_FILE.read_text(encoding="utf-8"))
    expected = canonical_versions(model)
    publication = model.get("publication", {})
    if not isinstance(publication, dict) or not isinstance(
        publication.get("distTag"), str
    ):
        raise TypeError("release/version.json requires string publication.distTag")
    if args.write:
        write_versions(expected, publication["distTag"])
    failures = validate(expected, model)
    if failures:
        for failure in failures:
            print(f"release-version error: {failure}", file=sys.stderr)
        return 1
    print(f"release versions agree with {model['canonical']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
