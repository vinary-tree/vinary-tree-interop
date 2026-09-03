#!/usr/bin/env bash
set -euo pipefail

repository_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
build_python=${1:-python3}
dist_dir=${2:-"$repository_root/target/python-dist"}
test_python=${3:-"$build_python"}
expected_version=$(
  "$build_python" -c '
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    canonical = json.load(source)["canonical"]
print(canonical.replace("-rc.", "rc"))
' "$repository_root/release/version.json"
)

case "$dist_dir" in
  /*) ;;
  *) dist_dir="$repository_root/$dist_dir" ;;
esac

mkdir -p "$repository_root/target" "$dist_dir"
work_dir=$(mktemp -d "$repository_root/target/python-package-roundtrip.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT

cmp "$repository_root/LICENSE" "$repository_root/bindings/python/LICENSE"
mkdir "$work_dir/project"
rsync -a \
  --exclude build/ \
  --exclude '*.egg-info/' \
  --exclude __pycache__/ \
  "$repository_root/bindings/python/" "$work_dir/project/"
"$build_python" -m build --wheel --sdist \
  --outdir "$dist_dir" "$work_dir/project"

mapfile -t wheels < <(
  find "$dist_dir" -maxdepth 1 -type f -name '*.whl' -print
)
mapfile -t sdists < <(
  find "$dist_dir" -maxdepth 1 -type f -name '*.tar.gz' -print
)
if [[ ${#wheels[@]} -ne 1 || ${#sdists[@]} -ne 1 ]]; then
  echo "expected exactly one wheel and one source archive" >&2
  exit 1
fi

mkdir "$work_dir/source"
tar -xzf "${sdists[0]}" -C "$work_dir/source"
mapfile -t source_roots < <(
  find "$work_dir/source" -mindepth 1 -maxdepth 1 -type d -print
)
if [[ ${#source_roots[@]} -ne 1 ]]; then
  echo "expected exactly one source root in the source archive" >&2
  exit 1
fi
source_root=${source_roots[0]}
cmp "$repository_root/LICENSE" "$source_root/LICENSE"
test -f "$source_root/examples/host_providers.py"
test -f "$source_root/tests/test_providers.py"

verify_installed() {
  local environment=$1
  EXPECTED_VERSION="$expected_version" "$environment/bin/python" -I -B -c '
import importlib.metadata as metadata
import os
import vinary_tree_interop

distribution = metadata.distribution("vinary-tree-interop")
assert distribution.version == os.environ["EXPECTED_VERSION"]
assert distribution.metadata["License-Expression"] == "Apache-2.0"
assert distribution.metadata.get_all("License-File") == ["LICENSE"]
assert any(
    str(path).endswith(".dist-info/licenses/LICENSE")
    for path in distribution.files or ()
)
assert any(
    str(path).endswith("vinary_tree_interop/py.typed")
    for path in distribution.files or ()
)
assert vinary_tree_interop.ABI_VERSION == 1
'
  "$environment/bin/python" -I -B -m unittest discover -s "$repository_root/bindings/python/tests" -v
  "$environment/bin/python" -I -B "$repository_root/bindings/python/examples/host_providers.py"
}

"$test_python" -m venv "$work_dir/direct-env"
"$work_dir/direct-env/bin/python" -m pip install --disable-pip-version-check --no-deps --no-index "${wheels[0]}"
verify_installed "$work_dir/direct-env"

mkdir "$work_dir/rebuilt-dist"
"$build_python" -m build --wheel --outdir "$work_dir/rebuilt-dist" "$source_root"
mapfile -t rebuilt_wheels < <(
  find "$work_dir/rebuilt-dist" -maxdepth 1 -type f -name '*.whl' -print
)
if [[ ${#rebuilt_wheels[@]} -ne 1 ]]; then
  echo "expected exactly one wheel rebuilt from the source archive" >&2
  exit 1
fi

"$test_python" -m venv "$work_dir/rebuilt-env"
"$work_dir/rebuilt-env/bin/python" -m pip install --disable-pip-version-check --no-deps --no-index "${rebuilt_wheels[0]}"
verify_installed "$work_dir/rebuilt-env"
