#!/usr/bin/env python3
"""Validate immutable release refs and corrective-lane authority."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODEL_PATH = ROOT / "release/version.json"
REGISTRIES = frozenset(
    {
        "validate-only",
        "npm",
        "crates-io",
        "pypi",
        "maven-central",
        "nuget",
        "go-module",
        "opam",
    }
)
CORRECTIVE_REGISTRIES = frozenset(
    {"validate-only", "maven-central", "nuget", "opam"}
)


def validate(ref: str, ref_name: str, registry: str, canonical: str) -> None:
    if registry not in REGISTRIES:
        raise ValueError(f"unknown release registry: {registry}")
    if ref != f"refs/tags/{ref_name}":
        raise ValueError("manual releases must be dispatched against an immutable tag")

    canonical_tag = f"v{canonical}"
    if ref_name == canonical_tag:
        return
    corrective_pattern = rf"{re.escape(canonical_tag)}-release\.[1-9][0-9]*"
    if re.fullmatch(corrective_pattern, ref_name) is None:
        raise ValueError(
            f"expected {canonical_tag} or its numbered corrective release tag; "
            f"got {ref_name}"
        )
    if registry not in CORRECTIVE_REGISTRIES:
        raise ValueError(
            "corrective source tags are restricted to validation and the "
            f"explicitly authorized unpublished Maven/NuGet/opam lanes; got {registry}"
        )


def self_test(canonical: str) -> None:
    canonical_tag = f"v{canonical}"
    for registry in REGISTRIES:
        validate(f"refs/tags/{canonical_tag}", canonical_tag, registry, canonical)
    for registry in CORRECTIVE_REGISTRIES:
        ref_name = f"{canonical_tag}-release.1"
        validate(f"refs/tags/{ref_name}", ref_name, registry, canonical)

    rejected = (
        (f"refs/heads/{canonical_tag}", canonical_tag, "validate-only"),
        (
            f"refs/tags/{canonical_tag}-release.0",
            f"{canonical_tag}-release.0",
            "validate-only",
        ),
        (
            f"refs/tags/{canonical_tag}-release",
            f"{canonical_tag}-release",
            "validate-only",
        ),
        (f"refs/tags/{canonical_tag}-release.1", f"{canonical_tag}-release.1", "npm"),
        (
            f"refs/tags/{canonical_tag}-release.2",
            f"{canonical_tag}-release.2",
            "crates-io",
        ),
    )
    for ref, ref_name, registry in rejected:
        try:
            validate(ref, ref_name, registry, canonical)
        except ValueError:
            continue
        raise AssertionError(
            f"accepted forbidden release dispatch: {(ref, ref_name, registry)}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ref")
    parser.add_argument("--ref-name")
    parser.add_argument("--registry")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    model = json.loads(MODEL_PATH.read_text(encoding="utf-8"))
    canonical = model.get("canonical")
    if not isinstance(canonical, str):
        raise TypeError("release/version.json requires string canonical")
    if args.self_test:
        self_test(canonical)
        print("release-ref authority self-test passed")
        return 0
    if not all(
        isinstance(value, str) for value in (args.ref, args.ref_name, args.registry)
    ):
        parser.error("--ref, --ref-name, and --registry are required")
    try:
        validate(args.ref, args.ref_name, args.registry, canonical)
    except ValueError as error:
        parser.error(str(error))
    print(canonical)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
