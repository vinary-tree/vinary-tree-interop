#!/usr/bin/env raku

use v6.d;

sub usage(--> Nil) {
    note 'usage: raku scripts/generate-bindings.raku [--check|--write]';
    exit 2;
}

my $mode = @*ARGS.elems == 1 ?? @*ARGS[0] !! '--check';
usage unless $mode eq '--check' || $mode eq '--write';

my $root = $?FILE.IO.absolute.IO.parent.parent;
my $header-path = $root.add('include/vinary_tree_interop.h');
my @header-lines = $header-path.lines;

my %macros;
for @header-lines -> $line {
    if $line ~~ /^ '#define ' (VT_\w+) \s+ (\S+) / {
        %macros{~$0} = ~$1;
    }
}

sub macro-value(Str:D $name --> Int:D) {
    my $raw = %macros{$name}
        // die "missing ABI macro $name in $header-path";
    $raw ~~ s/ 'UINT64_C(' (\d+) ')' /$0/;
    $raw ~~ s/ <[uUlL]>+ $//;
    $raw ~~ s/^ '(' (.*) ')' $/$0/;
    die "ABI macro $name is not an integer: $raw"
        unless $raw ~~ /^ '-'? \d+ $/;
    $raw.Int
}

my %enum-members;
my $active-enum;
for @header-lines -> $line {
    if $line ~~ /^ 'typedef enum ' (Vt\w+) \s* '{' / {
        $active-enum = ~$0;
        %enum-members{$active-enum} = [];
        next;
    }
    if $active-enum.defined {
        if $line ~~ /^ \s* (VT_\w+) \s* '=' \s* (\d+) ','? / {
            %enum-members{$active-enum}.push([~$0, +$1]);
        }
        $active-enum = Nil if $line ~~ /^ \s* '}' /;
    }
}

my @interfaces = (
    ['DICTIONARY', 'dictionary'],
    ['DICTIONARY_VISIT', 'dictionary-visit'],
    ['DICTIONARY_GRAPH', 'dictionary-graph'],
    ['DICTIONARY_ENTRIES', 'dictionary-entries'],
    ['SNAPSHOT_IDENTITY', 'snapshot-identity'],
    ['WFST', 'wfst'],
    ['LATTICE', 'lattice'],
    ['SEMIRING', 'semiring'],
    ['SEMIRING_DIVISION', 'semiring-division'],
    ['SEMIRING_STAR', 'semiring-star'],
    ['SEMIRING_NUMERIC', 'semiring-numeric'],
    ['SEMIRING_PROPERTIES', 'semiring-properties'],
);

my %interface-ids;
my $active-interface;
for @header-lines -> $line {
    if $line ~~ /^ 'static const VtInterfaceId VT_' (\w+) '_INTERFACE_ID' / {
        $active-interface = ~$0;
        %interface-ids{$active-interface} = '';
        next;
    }
    if $active-interface.defined {
        for $line.match(/ "'" (.) "'" /, :g) -> $match {
            %interface-ids{$active-interface} ~= ~$match[0];
        }
        $active-interface = Nil if $line ~~ / '};' /;
    }
}

my @macro-spec = (
    ['VT_ABI_VERSION', 'ABI_VERSION', 'ABI-VERSION', 'UInt32'],
    ['VT_DICTIONARY_INTERFACE_VERSION', 'DICTIONARY_INTERFACE_VERSION',
        'DICTIONARY-INTERFACE-VERSION', 'UInt32'],
    ['VT_DICTIONARY_VISIT_INTERFACE_VERSION',
        'DICTIONARY_VISIT_INTERFACE_VERSION',
        'DICTIONARY-VISIT-INTERFACE-VERSION', 'UInt32'],
    ['VT_DICTIONARY_GRAPH_INTERFACE_VERSION',
        'DICTIONARY_GRAPH_INTERFACE_VERSION',
        'DICTIONARY-GRAPH-INTERFACE-VERSION', 'UInt32'],
    ['VT_DICTIONARY_ENTRIES_INTERFACE_VERSION',
        'DICTIONARY_ENTRIES_INTERFACE_VERSION',
        'DICTIONARY-ENTRIES-INTERFACE-VERSION', 'UInt32'],
    ['VT_SNAPSHOT_IDENTITY_INTERFACE_VERSION',
        'SNAPSHOT_IDENTITY_INTERFACE_VERSION',
        'SNAPSHOT-IDENTITY-INTERFACE-VERSION', 'UInt32'],
    ['VT_WFST_INTERFACE_VERSION', 'WFST_INTERFACE_VERSION',
        'WFST-INTERFACE-VERSION', 'UInt32'],
    ['VT_LATTICE_INTERFACE_VERSION', 'LATTICE_INTERFACE_VERSION',
        'LATTICE-INTERFACE-VERSION', 'UInt32'],
    ['VT_SEMIRING_INTERFACE_VERSION', 'SEMIRING_INTERFACE_VERSION',
        'SEMIRING-INTERFACE-VERSION', 'UInt32'],
    ['VT_SEMIRING_DIVISION_INTERFACE_VERSION',
        'SEMIRING_DIVISION_INTERFACE_VERSION',
        'SEMIRING-DIVISION-INTERFACE-VERSION', 'UInt32'],
    ['VT_SEMIRING_STAR_INTERFACE_VERSION', 'SEMIRING_STAR_INTERFACE_VERSION',
        'SEMIRING-STAR-INTERFACE-VERSION', 'UInt32'],
    ['VT_SEMIRING_NUMERIC_INTERFACE_VERSION',
        'SEMIRING_NUMERIC_INTERFACE_VERSION',
        'SEMIRING-NUMERIC-INTERFACE-VERSION', 'UInt32'],
    ['VT_SEMIRING_PROPERTIES_INTERFACE_VERSION',
        'SEMIRING_PROPERTIES_INTERFACE_VERSION',
        'SEMIRING-PROPERTIES-INTERFACE-VERSION', 'UInt32'],
    ['VT_RECOMMENDED_EDGE_BATCH', 'RECOMMENDED_EDGE_BATCH',
        'RECOMMENDED-EDGE-BATCH', 'Int'],
    ['VT_RECOMMENDED_ARC_BATCH', 'RECOMMENDED_ARC_BATCH',
        'RECOMMENDED-ARC-BATCH', 'Int'],
    ['VT_RECOMMENDED_LATTICE_BATCH', 'RECOMMENDED_LATTICE_BATCH',
        'RECOMMENDED-LATTICE-BATCH', 'Int'],
    ['VT_RECOMMENDED_SEMIRING_BATCH', 'RECOMMENDED_SEMIRING_BATCH',
        'RECOMMENDED-SEMIRING-BATCH', 'Int'],
    ['VT_SEMIRING_ORDER_BETTER', 'SEMIRING_ORDER_BETTER',
        'SEMIRING-ORDER-BETTER', 'Int32'],
    ['VT_SEMIRING_ORDER_EQUAL', 'SEMIRING_ORDER_EQUAL',
        'SEMIRING-ORDER-EQUAL', 'Int32'],
    ['VT_SEMIRING_ORDER_WORSE', 'SEMIRING_ORDER_WORSE',
        'SEMIRING-ORDER-WORSE', 'Int32'],
    ['VT_SEMIRING_ORDER_INCOMPARABLE', 'SEMIRING_ORDER_INCOMPARABLE',
        'SEMIRING-ORDER-INCOMPARABLE', 'Int32'],
);

my @flag-spec = (
    ['VT_DICTIONARY_FLAG_PARALLEL_REENTRANT',
        'DICTIONARY_FLAG_PARALLEL_REENTRANT',
        'DICTIONARY-FLAG-PARALLEL-REENTRANT'],
    ['VT_DICTIONARY_FLAG_SUFFIX_BASED', 'DICTIONARY_FLAG_SUFFIX_BASED',
        'DICTIONARY-FLAG-SUFFIX-BASED'],
    ['VT_DICTIONARY_FLAG_IMMUTABLE', 'DICTIONARY_FLAG_IMMUTABLE',
        'DICTIONARY-FLAG-IMMUTABLE'],
    ['VT_DICTIONARY_ENTRIES_INFO_FLAG_EXACT_LEN',
        'ENTRIES_INFO_FLAG_EXACT_LEN', 'ENTRIES-INFO-FLAG-EXACT-LEN'],
    ['VT_DICTIONARY_ENTRIES_INFO_FLAG_SNAPSHOT_IDENTITY',
        'ENTRIES_INFO_FLAG_SNAPSHOT_IDENTITY',
        'ENTRIES-INFO-FLAG-SNAPSHOT-IDENTITY'],
    ['VT_WFST_FLAG_PARALLEL_REENTRANT', 'WFST_FLAG_PARALLEL_REENTRANT',
        'WFST-FLAG-PARALLEL-REENTRANT'],
    ['VT_WFST_FLAG_IMMUTABLE', 'WFST_FLAG_IMMUTABLE',
        'WFST-FLAG-IMMUTABLE'],
    ['VT_WFST_FLAG_LAZY', 'WFST_FLAG_LAZY', 'WFST-FLAG-LAZY'],
    ['VT_WFST_FLAG_ACYCLIC', 'WFST_FLAG_ACYCLIC', 'WFST-FLAG-ACYCLIC'],
    ['VT_LATTICE_FLAG_THREAD_BOUND', 'LATTICE_FLAG_THREAD_BOUND',
        'LATTICE-FLAG-THREAD-BOUND'],
    ['VT_LATTICE_FLAG_PARALLEL_REENTRANT',
        'LATTICE_FLAG_PARALLEL_REENTRANT',
        'LATTICE-FLAG-PARALLEL-REENTRANT'],
    ['VT_LATTICE_FLAG_STABLE_BYTES', 'LATTICE_FLAG_STABLE_BYTES',
        'LATTICE-FLAG-STABLE-BYTES'],
    ['VT_LATTICE_FLAG_BATCH', 'LATTICE_FLAG_BATCH',
        'LATTICE-FLAG-BATCH'],
    ['VT_SEMIRING_FLAG_THREAD_BOUND', 'SEMIRING_FLAG_THREAD_BOUND',
        'SEMIRING-FLAG-THREAD-BOUND'],
    ['VT_SEMIRING_FLAG_PARALLEL_REENTRANT',
        'SEMIRING_FLAG_PARALLEL_REENTRANT',
        'SEMIRING-FLAG-PARALLEL-REENTRANT'],
    ['VT_SEMIRING_FLAG_STABLE_BYTES', 'SEMIRING_FLAG_STABLE_BYTES',
        'SEMIRING-FLAG-STABLE-BYTES'],
    ['VT_SEMIRING_FLAG_BATCH', 'SEMIRING_FLAG_BATCH',
        'SEMIRING-FLAG-BATCH'],
    ['VT_SEMIRING_PROPERTY_HASHABLE', 'SEMIRING_PROPERTY_HASHABLE',
        'SEMIRING-PROPERTY-HASHABLE'],
    ['VT_SEMIRING_PROPERTY_IDEMPOTENT_PLUS',
        'SEMIRING_PROPERTY_IDEMPOTENT_PLUS',
        'SEMIRING-PROPERTY-IDEMPOTENT-PLUS'],
    ['VT_SEMIRING_PROPERTY_K_CLOSED', 'SEMIRING_PROPERTY_K_CLOSED',
        'SEMIRING-PROPERTY-K-CLOSED'],
    ['VT_SEMIRING_PROPERTY_ZERO_SUM_FREE',
        'SEMIRING_PROPERTY_ZERO_SUM_FREE',
        'SEMIRING-PROPERTY-ZERO-SUM-FREE'],
    ['VT_SEMIRING_PROPERTY_COMMUTATIVE_TIMES',
        'SEMIRING_PROPERTY_COMMUTATIVE_TIMES',
        'SEMIRING-PROPERTY-COMMUTATIVE-TIMES'],
    ['VT_SEMIRING_PROPERTY_TOTALLY_ORDERED',
        'SEMIRING_PROPERTY_TOTALLY_ORDERED',
        'SEMIRING-PROPERTY-TOTALLY-ORDERED'],
    ['VT_SEMIRING_PROPERTY_NONNEGATIVE',
        'SEMIRING_PROPERTY_NONNEGATIVE',
        'SEMIRING-PROPERTY-NONNEGATIVE'],
);

my @enum-spec = (
    ['VtStatus', 'Status', 'Cint', 'VT_STATUS_', 'STATUS_', 'Status', ''],
    ['VtUnitDomain', 'UnitDomain', 'UInt32', 'VT_UNIT_DOMAIN_', 'UNIT_',
        'UnitDomain', ''],
    ['VtValueDomain', 'ValueDomain', 'UInt32', 'VT_VALUE_DOMAIN_', 'VALUE_',
        'ValueDomain', ''],
    ['VtDictionaryEntryOrder', 'EntryOrder', 'UInt32',
        'VT_DICTIONARY_ENTRY_ORDER_', 'ENTRY_', 'EntryOrder', ''],
    ['VtWeightDomain', 'WeightDomain', 'UInt32', 'VT_WEIGHT_DOMAIN_',
        'WEIGHT_', 'WeightDomain', ''],
);

my @julia;
for @macro-spec -> @spec {
    my $value = macro-value(@spec[0]);
    if @spec[3] eq 'UInt32' {
        @julia.push("const {@spec[1]} = UInt32($value)");
    } elsif @spec[3] eq 'Int32' {
        @julia.push("const {@spec[1]} = Int32($value)");
    } else {
        @julia.push("const {@spec[1]} = $value");
    }
}
@julia.push('');
for @enum-spec.kv -> $index, @spec {
    @julia.push("\@enum {@spec[1]}::{@spec[2]} begin");
    for %enum-members{@spec[0]}.list -> @member {
        my $name = @member[0].substr(@spec[3].chars);
        @julia.push("    {@spec[4]}$name = {@member[1]}");
    }
    @julia.push('end');
    @julia.push('') unless $index == @enum-spec.end;
}
@julia.push('');
for @flag-spec -> @spec {
    @julia.push("const {@spec[1]} = UInt64({macro-value(@spec[0])})");
}

my @raku;
for @macro-spec -> @spec {
    @raku.push("our constant {@spec[2]} is export = {macro-value(@spec[0])};");
}
@raku.push('');
for @enum-spec.kv -> $index, @spec {
    @raku.push("our enum {@spec[5]} is export (");
    for %enum-members{@spec[0]}.list -> @member {
        my $name = @member[0].substr(@spec[3].chars).subst('_', '-', :g);
        @raku.push("    $name => {@member[1]},");
    }
    @raku.push(');');
    @raku.push('') unless $index == @enum-spec.end;
}
@raku.push('');
for @flag-spec -> @spec {
    @raku.push("our constant {@spec[2]} is export = {macro-value(@spec[0])};");
}

my @julia-ids;
my @raku-ids;
for @interfaces -> @interface {
    my ($constant, $routine) = @interface;
    my $id = %interface-ids{$constant}
        // die "missing interface ID VT_{$constant}_INTERFACE_ID";
    die "interface ID VT_{$constant}_INTERFACE_ID is not 16 bytes"
        unless $id.encode('ascii').bytes == 16;
    @julia-ids.push("const {$constant}_INTERFACE_ID = interface_id(\"$id\")");
    @raku-ids.append(
        "sub {$routine}-interface-id(--> InterfaceId:D) is export \{",
        "    interface-id('$id')",
        '}',
        '',
    );
}
@raku-ids.pop;

sub replace-region(Str:D $text, Str:D $label, @generated --> Str:D) {
    my $begin = "# BEGIN GENERATED $label";
    my $end = "# END GENERATED $label";
    my $start = $text.index($begin) // die "missing marker $begin";
    my $finish = $text.index($end, $start) // die "missing marker $end";
    my $after = $finish + $end.chars;
    $text.substr(0, $start) ~ $begin ~ "\n" ~ @generated.join("\n") ~
        "\n" ~ $end ~ $text.substr($after)
}

my @targets = (
    [$root.add('bindings/julia/VinaryTreeInterop/src/VinaryTreeInterop.jl'),
        'ABI CONSTANTS', @julia.item],
    [$root.add('bindings/julia/VinaryTreeInterop/src/VinaryTreeInterop.jl'),
        'ABI INTERFACE IDS', @julia-ids.item],
    [$root.add('bindings/raku/lib/Vinary/Tree/Interop.rakumod'),
        'ABI CONSTANTS', @raku.item],
    [$root.add('bindings/raku/lib/Vinary/Tree/Interop.rakumod'),
        'ABI INTERFACE IDS', @raku-ids.item],
);

my %updated;
for @targets -> @target {
    my ($file, $label, $generated) = @target;
    my $key = $file.Str;
    my $current = %updated{$key} // $file.slurp;
    %updated{$key} = replace-region($current, $label, $generated.list);
}

my @structs;
my %operations;
my $active-struct;
for @header-lines -> $line {
    if $line ~~ /^ 'typedef struct ' (Vt\w+) \s* '{' / {
        $active-struct = ~$0;
        @structs.push($active-struct);
        %operations{$active-struct} = [];
        next;
    }
    if $active-struct.defined {
        if $line ~~ / '(' '*' (\w+) ')' / {
            %operations{$active-struct}.push(~$0);
        }
        $active-struct = Nil if $line ~~ /^ \s* '}' /;
    }
}

my @inventory = [<kind c_name version identity operation>.join("\t")];
for @interfaces -> @interface {
    my ($constant) = @interface;
    @inventory.push([
        'interface',
        "VT_{$constant}_INTERFACE_ID",
        macro-value("VT_{$constant}_INTERFACE_VERSION"),
        %interface-ids{$constant},
        '-',
    ].join("\t"));
}
for @structs.sort -> $struct {
    @inventory.push(['struct', $struct, '-', '-', '-'].join("\t"));
    for %operations{$struct}.list.sort -> $operation {
        @inventory.push(['operation', $struct, '-', '-', $operation].join("\t"));
    }
}
my $inventory = @inventory.join("\n") ~ "\n";
my $inventory-path = $root.add('bindings/generated/abi-capabilities.tsv');
my @header-targets =
    $root.add('bindings/go/vinary_tree_interop.h'),
    $root.add('bindings/haskell/include/vinary_tree_interop.h'),
    $root.add('bindings/ocaml/vinary_tree_interop.h'),
    $root.add('bindings/raku/resources/include/vinary_tree_interop.h');
my $header = $header-path.slurp;

my @differences;
for %updated.kv -> $name, $expected {
    my $actual = $name.IO.slurp;
    @differences.push($name) unless $actual eq $expected;
    $name.IO.spurt($expected) if $mode eq '--write' && $actual ne $expected;
}
my $actual-inventory = $inventory-path.e ?? $inventory-path.slurp !! '';
if $actual-inventory ne $inventory {
    @differences.push($inventory-path.Str);
    if $mode eq '--write' {
        $inventory-path.parent.mkdir;
        $inventory-path.spurt($inventory);
    }
}
for @header-targets -> $target {
    my $actual-header = $target.e ?? $target.slurp !! '';
    if $actual-header ne $header {
        @differences.push($target.Str);
        if $mode eq '--write' {
            $target.parent.mkdir;
            $target.spurt($header);
        }
    }
}

if $mode eq '--check' && @differences {
    note "generated bindings are stale:\n  " ~ @differences.join("\n  ");
    note 'run: raku scripts/generate-bindings.raku --write';
    exit 1;
}

say $mode eq '--write'
    ?? "updated {@differences.elems} generated binding file(s)"
    !! 'generated binding declarations and capability inventory are current';
