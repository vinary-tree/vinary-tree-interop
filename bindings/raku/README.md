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
