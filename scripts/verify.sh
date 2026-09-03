#!/usr/bin/env bash
set -euo pipefail

export TMPDIR="${TMPDIR:-$PWD/target/tmp}"
export GOCACHE="${GOCACHE:-$PWD/target/go-cache}"
export GOTMPDIR="${GOTMPDIR:-$PWD/target/go-tmp}"
mkdir -p "$TMPDIR" "$GOCACHE" "$GOTMPDIR"

python3 scripts/sync-release-version.py
python3 scripts/check-release-ref.py --self-test
cmp LICENSE bindings/python/LICENSE
git ls-files --eol | awk '
  $1 == "i/crlf" || $1 == "i/mixed" {
    print "tracked text is not normalized in the Git object database: " $0 > "/dev/stderr"
    invalid = 1
  }
  END { exit invalid }
'
cargo fmt --all -- --check
cargo test --all-targets
cargo clippy --all-targets -- -D warnings

cc -std=c17 -Wall -Wextra -Werror -Iinclude -x c -fsyntax-only include/vinary_tree_interop.h
c++ -std=c++23 -Wall -Wextra -Werror -Iinclude -x c++ -fsyntax-only include/vinary_tree_interop.h
cpp_work=$(mktemp -d "$TMPDIR/vinary-tree-interop-cpp.XXXXXX")
trap 'rm -rf "$cpp_work"' EXIT
c++ -std=c++20 -Wall -Wextra -Wpedantic -Werror -Iinclude \
  tests/cpp/providers.cpp -o "$cpp_work/providers"
"$cpp_work/providers"
package_prefix=$(./scripts/stage-native-package.sh "$cpp_work/staged")
cmake -S tests/cpp/package -B "$cpp_work/build" \
  -DCMAKE_PREFIX_PATH="$package_prefix"
cmake --build "$cpp_work/build"
ctest --test-dir "$cpp_work/build" --output-on-failure
cmp include/vinary_tree_interop.h bindings/ocaml/vinary_tree_interop.h
cc -std=c17 -Wall -Wextra -Werror -Iinclude -Ibindings/lua \
  -x c -fsyntax-only bindings/lua/vinary_tree_lua.h

npm --prefix bindings/javascript test
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=bindings/python/src python3 -m unittest discover \
  -s bindings/python/tests -v
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=bindings/python/src \
  python3 bindings/python/examples/host_providers.py
GOWORK=off go -C bindings/go vet ./...
GOWORK=off go -C bindings/go test ./...

if [[ "${1:-}" == "--full" ]]; then
  raku scripts/generate-bindings.raku --check
  dotnet build bindings/dotnet/src/VinaryTree.Interop/VinaryTree.Interop.csproj \
    --configuration Release -p:NuGetAudit=false -m:1
  dotnet run \
    --project bindings/dotnet/tests/VinaryTree.Interop.ProviderTests/VinaryTree.Interop.ProviderTests.csproj \
    --configuration Release -p:NuGetAudit=false -m:1
  dotnet run \
    --project bindings/dotnet/tests/VinaryTree.Interop.FSharpProviders/VinaryTree.Interop.FSharpProviders.fsproj \
    --configuration Release -p:NuGetAudit=false -m:1
  bindings/jvm/gradlew --no-daemon -p bindings/jvm check javadoc
  swift build
  fpm test -C bindings/fortran
  dune build --root bindings/ocaml @install @runtest
  (cd bindings/haskell && cabal check)
fi
