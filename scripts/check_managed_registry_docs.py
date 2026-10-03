"""Read back exact-version JVM, .NET, and Swift documentation after publication.

This is a read-only post-publication gate. It is intentionally not run by the
RC.6 source/validation workflows while those registries remain unpublished.
"""

from __future__ import annotations

import argparse
import importlib.util
import io
import json
import re
import urllib.request
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = json.loads((ROOT / "release/version.json").read_text(encoding="utf-8"))[
    "canonical"
]
SPEC = importlib.util.spec_from_file_location(
    "managed_api_docs", ROOT / "scripts/check-managed-api-docs.py"
)
assert SPEC is not None and SPEC.loader is not None
API = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(API)


def fetch(url: str, *, ceiling: int) -> tuple[bytes, str]:
    request = urllib.request.Request(
        url, headers={"User-Agent": "vinary-tree-doc-readback/1"}
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        body = response.read(ceiling + 1)
        final_url = response.geturl()
    if len(body) > ceiling:
        raise ValueError(f"registry document exceeds {ceiling} bytes: {url}")
    return body, final_url


def check_maven_archive(payload: bytes) -> None:
    names = API.source_types(API.JVM_SOURCE, API.JAVA_TYPE, "java")
    with zipfile.ZipFile(io.BytesIO(payload)) as archive:
        files = set(archive.namelist())
        required = {"index.html"} | {
            f"io/vinarytree/interop/{name}.html" for name in names
        }
        missing = sorted(required - files)
        if missing:
            raise ValueError(f"published Maven Javadoc omits public types: {missing}")
        for name in required:
            if "<html" not in archive.read(name).decode("utf-8").lower():
                raise ValueError(f"published Maven Javadoc is not browsable: {name}")


def check_nuget_archive(payload: bytes) -> None:
    names = API.source_types(API.DOTNET_SOURCE, API.CSHARP_TYPE, "cs")
    required_types = {f"T:VinaryTree.Interop.{name}" for name in names}
    with zipfile.ZipFile(io.BytesIO(payload)) as archive:
        files = set(archive.namelist())
        if "README.md" not in files:
            raise ValueError("published NuGet package lacks its README")
        readme = archive.read("README.md").decode("utf-8")
        if "F#" not in readme or VERSION not in readme or "HostProviders" not in readme:
            raise ValueError(
                "published NuGet README lacks managed usage and release links"
            )
        for framework in ("net8.0", "net10.0"):
            path = f"lib/{framework}/VinaryTree.Interop.xml"
            if path not in files:
                raise ValueError(f"published NuGet package lacks {path}")
            root = ET.fromstring(archive.read(path))
            documented = {node.get("name") for node in root.findall(".//member")}
            missing = sorted(
                name
                for name in required_types
                if name not in documented
                and not any(
                    re.fullmatch(re.escape(name) + r"`[1-9][0-9]*", member or "")
                    for member in documented
                )
            )
            if missing:
                raise ValueError(
                    f"published NuGet {framework} XML omits types: {missing}"
                )


def check_spi_page(html: bytes, final_url: str) -> None:
    expected = (
        f"/vinary-tree/vinary-tree-interop/{VERSION}/documentation/vinarytreeinterop"
    )
    if expected not in final_url.lower():
        raise ValueError(
            f"Swift Package Index redirected away from {VERSION}: {final_url}"
        )
    body = html.decode("utf-8").lower()
    if "vinarytreeinterop" not in body or VERSION not in body:
        raise ValueError("Swift Package Index lacks the exact versioned DocC page")


def check_registries() -> None:
    maven = (
        "https://repo.maven.apache.org/maven2/io/vinarytree/vinary-tree-interop/"
        f"{VERSION}/vinary-tree-interop-{VERSION}-javadoc.jar"
    )
    nuget = (
        "https://api.nuget.org/v3-flatcontainer/vinarytree.interop/"
        f"{VERSION}/vinarytree.interop.{VERSION}.nupkg"
    )
    spi = (
        "https://swiftpackageindex.com/vinary-tree/vinary-tree-interop/"
        f"{VERSION}/documentation/vinarytreeinterop"
    )
    check_maven_archive(fetch(maven, ceiling=32 * 1024 * 1024)[0])
    check_nuget_archive(fetch(nuget, ceiling=256 * 1024 * 1024)[0])
    body, final_url = fetch(spi, ceiling=16 * 1024 * 1024)
    check_spi_page(body, final_url)
    print(
        f"managed registry docs: exact {VERSION} Maven, NuGet, and SPI readbacks passed"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--version", required=True, help="expected exact canonical released version"
    )
    parser.add_argument(
        "--local-nuget",
        type=Path,
        help="inspect a staged NuGet package without network access",
    )
    args = parser.parse_args()
    if args.version != VERSION or not re.fullmatch(r"\d+\.\d+\.\d+-rc\.\d+", VERSION):
        parser.error(f"version must equal source candidate {VERSION}")
    if args.local_nuget is not None:
        check_nuget_archive(args.local_nuget.read_bytes())
        print(f"managed registry docs: local NuGet {VERSION} README/XML passed")
    else:
        check_registries()


if __name__ == "__main__":
    main()
