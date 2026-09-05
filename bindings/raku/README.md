# Vinary-Tree-Interop for Raku

`Vinary::Tree::Interop` gives Raku safe, idiomatic NativeCall access to Vinary
Tree's stable resource ABI: snapshot-consistent dictionaries, bounded entry
streams, compact graphs, and scalar weighted finite-state transducers (WFSTs).

The distribution implements `Associative` dictionaries, `Iterable` entry
cursors, deterministic `.close`, retained snapshots, bounded batch callbacks,
provider-side reducers, lattice-value algebra, and typed portable exceptions.
It also publishes the exact C header used to generate the NativeCall layout.
Dependent distributions can read its package-resource path with
`native-header-path()` or copy it under its canonical C include name with
`materialize-native-header($include-directory)` when they compile a small
native adapter during installation. Materialization is required because an
installed Raku distribution may store resources under content-addressed names.

## Authoritative ABI generation

[`include/vinary_tree_interop.h`](../../include/vinary_tree_interop.h) is the
single source for Raku's raw binary interface. The Raku generator derives all
28 representable `CStruct` layouts, all 52 typed vtable callback casts, enum
values, constants, interface identifiers, and the packaged header from it. The
generated [`abi-capabilities.tsv`](../generated/abi-capabilities.tsv) inventory
records each interface and callback together with its C and NativeCall
signatures, version, identity, parameter direction and ownership, threading
contract, and capability family.

The default export tag remains the idiomatic collection and resource API.
Provider authors who need the generated low-level casts can opt into the
advanced ABI tag without copying a signature:

```raku
use Vinary::Tree::Interop :DEFAULT, :abi;

say ABI-STRUCT-COUNT;       # 28
say ABI-CALLABLE-COUNT;     # 52
```

The generator preserves the few necessary Rakudo adaptations explicitly:
fixed-size C arrays become consecutive native scalar fields, nested identity
storage is flattened without changing its bytes, and the bounded-entry
constructor retains its validated defaults. The high-level classes and
ownership rules remain hand-authored because they express Raku semantics, not
C layout.

```console
raku scripts/generate-bindings.raku --write
raku scripts/generate-bindings.raku --check
raku scripts/generate-bindings.raku --self-test
```

The self-test is a negative control. It perturbs the generated callback count
in memory and must prove that the committed module would be stale. CI and the
release workflow run both the positive freshness check and this negative
control.

## Installation

Install a checkout with `zef`:

```console
zef install ./bindings/raku
```

A library-specific Raku distribution supplies the native resource. The shared
dictionary then follows ordinary Raku collection conventions:

```raku
use Vinary::Tree::Interop;

sub inspect-dictionary(Resource:D $native-resource) {
    my $dictionary = dictionary($native-resource, :take);
    LEAVE $dictionary.close;

    say $dictionary{'café'} if $dictionary{'café'}:exists;
    for entries($dictionary) -> $entry {
        say $entry.units, ' => ', $entry.value;
    }
}
```

## Bounded entry processing

```raku
sub print-entries(Dictionary:D $dictionary) {
    my $cursor = entries($dictionary);
    LEAVE $cursor.close;

    $cursor.reduce(
        -> @page {
            say .units, ' => ', .value for @page;
        },
        BatchLimits.new(
            max-entries => 256,
            max-units => 65_536,
            max-values => 256,
        ),
    )
}
```

Reducer callbacks are synchronous and must remain on a Rakudo-owned calling
thread. Exceptions are caught before they can cross C or Rust frames and are
re-thrown after native control returns.

## Lattice values

`LatticeValue` is an owned, closeable handle to an immutable lattice element.
It exposes `join`, `meet`, equality, canonical bytes, diagnostics, and bounded
batch folds. Empty batch folds return an independent retain of the receiver;
non-empty folds are associative left folds. Provider packages such as
`LLattice` use this consumer surface to keep callback implementation and ABI
ownership separate.

```raku
sub merge(LatticeValue:D $base, @updates --> Blob:D) {
    my $merged = $base.join-many(@updates);
    LEAVE $merged.close;
    $merged.stable-bytes
}
```

See the [complete design, security, and performance guide](../../docs/language-bindings/julia-raku.md).
