#!/usr/bin/env bash
set -euo pipefail

export TMPDIR="${TMPDIR:-$PWD/target/tmp}"
export GOCACHE="${GOCACHE:-$PWD/target/go-cache}"
export GOTMPDIR="${GOTMPDIR:-$PWD/target/go-tmp}"
mkdir -p "$TMPDIR" "$GOCACHE" "$GOTMPDIR"

python3 scripts/sync-release-version.py
python3 scripts/check-release-ref.py --self-test
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
cmp include/vinary_tree_interop.h bindings/ocaml/vinary_tree_interop.h
cc -std=c17 -Wall -Wextra -Werror -Iinclude -Ibindings/lua \
  -x c -fsyntax-only bindings/lua/vinary_tree_lua.h

npm --prefix bindings/javascript test
PYTHONPATH=bindings/python/src python3 -c \
  'from vinary_tree_interop import UnitDomain; assert UnitDomain.UNICODE_SCALAR.value == 2'
GOWORK=off go -C bindings/go test ./...

if [[ "${1:-}" == "--full" ]]; then
  raku scripts/generate-bindings.raku --check
  dotnet build bindings/dotnet/src/VinaryTree.Interop/VinaryTree.Interop.csproj \
    --configuration Release -p:NuGetAudit=false -m:1
  bindings/jvm/gradlew --no-daemon -p bindings/jvm test javadoc
  swift build
  fpm test -C bindings/fortran
  dune build --root bindings/ocaml @install @runtest
  (cd bindings/haskell && cabal check)
fi
