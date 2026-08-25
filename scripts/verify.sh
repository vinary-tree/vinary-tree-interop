#!/usr/bin/env bash
set -euo pipefail

python3 scripts/sync-release-version.py
python3 scripts/check-release-ref.py --self-test
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
  dotnet build bindings/dotnet/src/VinaryTree.Interop/VinaryTree.Interop.csproj \
    --configuration Release -p:NuGetAudit=false -m:1
  bindings/jvm/gradlew --no-daemon -p bindings/jvm test javadoc
  swift build
  fpm test -C bindings/fortran
  dune build --root bindings/ocaml @install @runtest
  (cd bindings/haskell && cabal check)
fi
