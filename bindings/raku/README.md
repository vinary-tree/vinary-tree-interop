# Vinary-Tree-Interop for Raku

`Vinary::Tree::Interop` gives Raku safe, idiomatic NativeCall access to Vinary
Tree's stable resource ABI: snapshot-consistent dictionaries, bounded entry
streams, compact graphs, and scalar weighted finite-state transducers (WFSTs).

The distribution implements `Associative` dictionaries, `Iterable` entry
cursors, deterministic `.close`, retained snapshots, bounded batch callbacks,
provider-side reducers, and typed portable exceptions.

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

See the [complete design, security, and performance guide](../../docs/language-bindings/julia-raku.md).
