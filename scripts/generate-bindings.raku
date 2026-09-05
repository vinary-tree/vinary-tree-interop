#!/usr/bin/env raku

use v6.d;

sub usage(--> Nil) {
    note 'usage: raku scripts/generate-bindings.raku [--check|--write|--self-test]';
    exit 2;
}

my $mode = @*ARGS.elems == 1 ?? @*ARGS[0] !! '--check';
usage unless $mode eq '--check' || $mode eq '--write' || $mode eq '--self-test';

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

sub require-exact-names(Str:D $kind, @actual, @expected --> Nil) {
    my @observed = @actual.sort;
    my @modeled = @expected.sort;
    die "$kind coverage is incomplete: observed={@observed.join(',')} " ~
        "modeled={@modeled.join(',')}"
        unless @observed eqv @modeled;
}

require-exact-names(
    'ABI macro',
    %macros.keys,
    (|@macro-spec.map({ $_[0] }), |@flag-spec.map({ $_[0] })),
);
require-exact-names(
    'ABI enum',
    %enum-members.keys,
    @enum-spec.map({ $_[0] }),
);
require-exact-names(
    'ABI interface ID',
    %interface-ids.keys,
    @interfaces.map({ $_[0] }),
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

sub normalize-space(Str:D $text --> Str:D) {
    $text.subst(/\s+/, ' ', :g).trim
}

sub parse-parameters(Str:D $raw --> Array:D) {
    my $normalized = normalize-space($raw);
    return [] if $normalized eq '' || $normalized eq 'void';
    $normalized.split(',').map(-> $part {
        my $parameter = normalize-space($part);
        my $name-match = $parameter.match(/(<[A..Za..z_]>\w*) $/)
            // die "cannot parse parameter name from '$parameter'";
        {
            name => ~$name-match[0],
            c_type => $parameter.substr(0, $name-match.from).trim,
            c_declaration => $parameter,
        }
    }).Array
}

sub parse-callable(Str:D $declaration, Str:D $owner --> Hash:D) {
    my $normalized = normalize-space($declaration);
    my $marker = $normalized.index('(*')
        // die "cannot find function-pointer marker in '$normalized'";
    my $name-end = $normalized.index(')', $marker + 2)
        // die "cannot find function-pointer name end in '$normalized'";
    my $parameters-start = $normalized.index('(', $name-end + 1)
        // die "cannot find parameter list in '$normalized'";
    die "function-pointer declaration does not end in ')' : '$normalized'"
        unless $normalized.ends-with(')');
    {
        owner => $owner,
        name => $normalized.substr($marker + 2, $name-end - $marker - 2),
        c_return => $normalized.substr(0, $marker).trim,
        parameters => parse-parameters(
            $normalized.substr(
                $parameters-start + 1,
                $normalized.chars - $parameters-start - 2,
            ),
        ),
        c_signature => $normalized,
    }
}

sub parse-struct-fields(Str:D $body, Str:D $owner --> Array:D) {
    my @fields;
    for $body.split(';') -> $part {
        my $declaration = normalize-space($part);
        next unless $declaration.chars;
        if $declaration.contains('(*') {
            @fields.push(parse-callable($declaration, $owner));
            next;
        }
        my $separator = $declaration.rindex(' ')
            // die "cannot split field declaration '$declaration'";
        my $c-type = $declaration.substr(0, $separator).trim;
        my $tail = $declaration.substr($separator + 1).trim;
        if $tail ~~ /^ (\w+) '[' (\d+) ']' $/ {
            @fields.push({
                owner => $owner,
                name => ~$0,
                c_type => $c-type,
                array_count => +$1,
                c_declaration => $declaration,
            });
            next;
        }
        die "cannot parse field name from '$declaration'"
            unless $tail ~~ /^ \w+ $/;
        @fields.push({
            owner => $owner,
            name => $tail,
            c_type => $c-type,
            c_declaration => $declaration,
        });
    }
    @fields.Array
}

my @structs;
my %struct-fields;
my @operations;
my $active-struct;
my $struct-body = '';
for @header-lines -> $raw-line {
    my $fragment;
    if $active-struct.defined {
        $fragment = $raw-line;
    } else {
        if $raw-line ~~ /^ \s* 'typedef struct ' (Vt\w+) \s* '{' (.*) $/ {
            $active-struct = ~$0;
            $struct-body = '';
            $fragment = ~$1;
        } else {
            next;
        }
    }

    my $closing = $fragment.index('}');
    if $closing.defined {
        $struct-body ~= ' ' ~ $fragment.substr(0, $closing);
        my @fields = parse-struct-fields($struct-body, $active-struct);
        @structs.push($active-struct);
        %struct-fields{$active-struct} = @fields.Array;
        @operations.append(@fields.grep({ $_<c_return>:exists }));
        $active-struct = Nil;
        $struct-body = '';
    } else {
        $struct-body ~= ' ' ~ $fragment;
    }
}
die "unterminated struct $active-struct" if $active-struct.defined;

my %callback-typedefs;
my $callback-declaration = '';
for @header-lines -> $raw-line {
    my $line = $raw-line.trim;
    if !$callback-declaration.chars &&
            $line.starts-with('typedef ') && $line.contains('(*') {
        $callback-declaration = $line;
    } elsif $callback-declaration.chars {
        $callback-declaration ~= ' ' ~ $line;
    }
    if $callback-declaration.chars && $callback-declaration.ends-with(');') {
        my $callable = parse-callable(
            $callback-declaration.substr(
                'typedef '.chars,
                $callback-declaration.chars - 'typedef '.chars - 1,
            ),
            'typedef',
        );
        %callback-typedefs{$callable<name>} = $callable;
        $callback-declaration = '';
    }
}
die 'unterminated callback typedef' if $callback-declaration.chars;

my %struct-raku-name = (
    VtResource => 'RawResource',
    VtDictionaryEntry => 'DictionaryEntryDescriptor',
    VtDictionaryEntryBatchLimits => 'BatchLimits',
    VtDictionaryEntriesCursor => 'RawDictionaryEntriesCursor',
);

my %struct-julia-name = (
    VtResource => 'VtResourceRaw',
    VtSnapshotIdentity => 'SnapshotIdentity',
    VtDictionaryEntry => 'VtDictionaryEntryRaw',
    VtDictionaryEntryBatchLimits => 'BatchLimits',
    VtDictionaryEntriesCursor => 'VtDictionaryEntriesCursorRaw',
);

sub raku-struct-name(Str:D $c-name --> Str:D) {
    %struct-raku-name{$c-name} // $c-name.substr(2)
}

sub julia-struct-name(Str:D $c-name --> Str:D) {
    %struct-julia-name{$c-name} // $c-name
}

sub raku-field-name(Str:D $c-name --> Str:D) {
    $c-name.subst('_', '-', :g)
}

my %primitive-raku-type = (
    size_t => 'size_t',
    uint64_t => 'uint64',
    uint32_t => 'uint32',
    int64_t => 'int64',
    int32_t => 'int32',
    uint8_t => 'uint8',
    double => 'num64',
);
my %enum-raku-type = @enum-spec.map({ $_[0] => 'uint32' });
%enum-raku-type<VtStatus> = 'int32';
my %mutable-field = (
    'VtResource.context' => True,
    'VtResource.vtable' => True,
    'VtDictionaryEntriesCursor.context' => True,
    'VtDictionaryEntriesCursor.vtable' => True,
    'VtSemiringValue.word0' => True,
    'VtSemiringValue.word1' => True,
);
my %typed-pointer-field = (
    'VtDictionaryGraphView.nodes' => 'Pointer[DictionaryGraphNode]',
    'VtDictionaryGraphView.edges' => 'Pointer[DictionaryGraphEdge]',
    'VtDictionaryEntryBatchView.entries' => 'Pointer[DictionaryEntryDescriptor]',
    'VtDictionaryEntryBatchView.values' => 'Pointer[uint64]',
);

sub clean-c-type(Str:D $type --> Str:D) {
    $type.subst(/^ 'const ' /, '').subst(/^ 'struct ' /, '').trim
}

sub scalar-raku-type(Str:D $c-type --> Str:D) {
    my $clean = clean-c-type($c-type);
    %primitive-raku-type{$clean} // %enum-raku-type{$clean} //
        (@structs.first(* eq $clean).defined ?? raku-struct-name($clean) !! '')
}

sub render-struct-field(Str:D $struct, %field, Hash:D $used --> Array:D) {
    my $c-name = %field<name>;
    my $key = "$struct.$c-name";
    if %field<c_return>:exists {
        my $name = raku-field-name($c-name);
        $used{$name} = True;
        return ["    has Pointer \$.{$name};"];
    }
    if %field<array_count>:exists {
        my $type = scalar-raku-type(%field<c_type>);
        die "unsupported array element type {%field<c_type>} in $key"
            unless $type.chars;
        my $base = $struct eq 'VtInterfaceId' && $c-name eq 'bytes'
            ?? 'b' !! raku-field-name($c-name);
        my $start = 0;
        $start++ while $used{"$base$start"}:exists;
        my @lines;
        for $start ..^ $start + %field<array_count> -> $index {
            my $name = "$base$index";
            $used{$name} = True;
            @lines.push("    has $type \$.{$name};");
        }
        return @lines;
    }
    if $key eq 'VtDictionaryEntriesInfo.identity' {
        $used<identity-producer> = True;
        $used<identity-revision> = True;
        return [
            '    has uint64 $.identity-producer;',
            '    has uint64 $.identity-revision;',
        ];
    }
    my $name = raku-field-name($c-name);
    $used{$name} = True;
    my $c-type = %field<c_type>;
    my $type;
    my $storage = 'has';
    if $c-type.contains('*') {
        $type = %typed-pointer-field{$key} // 'Pointer';
    } else {
        $type = scalar-raku-type($c-type);
        die "unsupported field type $c-type in $key" unless $type.chars;
        $storage = 'HAS' if @structs.first(* eq clean-c-type($c-type)).defined;
    }
    my $mutable = %mutable-field{$key}:exists ?? ' is rw' !! '';
    ["    $storage $type \$.{$name}$mutable;"]
}

sub struct-extra-lines(Str:D $struct --> Array:D) {
    given $struct {
        when 'VtInterfaceId' {
            return [
                '',
                '    method bytes(--> List:D) {',
                '        ($!b0, $!b1, $!b2, $!b3, $!b4, $!b5, $!b6, $!b7,',
                '            $!b8, $!b9, $!b10, $!b11, $!b12, $!b13, $!b14, $!b15)',
                '    }',
            ];
        }
        when 'VtDictionaryEntryBatchLimits' {
            return [
                '',
                '    method new(',
                '        Int:D :$max-entries = 256,',
                '        Int:D :$max-units = 65_536,',
                '        Int:D :$max-values = 256,',
                '    ) {',
                q[        die 'max-entries must be positive' unless $max-entries > 0;],
                q[        die 'max-units cannot be negative' unless $max-units >= 0;],
                q[        die 'max-values cannot be negative' unless $max-values >= 0;],
                '        self.bless(:$max-entries, :$max-units, :$max-values, :reserved(0))',
                '    }',
            ];
        }
    }
    []
}

sub render-struct(Str:D $struct --> Array:D) {
    my @lines = "class {raku-struct-name($struct)} is repr('CStruct') is export \{";
    my %used;
    for %struct-fields{$struct}.list -> %field {
        @lines.append(render-struct-field($struct, %field, %used));
    }
    @lines.append(struct-extra-lines($struct));
    @lines.push('}');
    @lines.Array
}

my %array-parameter = (
    'VtDictionaryVTable.node_edges.out_edges' => True,
    'VtDictionaryVisitVTable.node_visit.out_edges' => True,
    'VtDictionaryEntryReducer.batch' => True,
    'VtWfstVTable.state_arcs.out_arcs' => True,
    'VtLatticeVTable.stable_bytes.out_bytes' => True,
    'VtLatticeVTable.diagnostic.out_bytes' => True,
    'VtLatticeVTable.join_many.others' => True,
    'VtLatticeVTable.meet_many.others' => True,
    'VtSemiringVTable.release_values.values' => True,
    'VtSemiringVTable.stable_bytes.out_bytes' => True,
    'VtSemiringVTable.diagnostic.out_bytes' => True,
    'VtSemiringVTable.plus_many.values' => True,
    'VtSemiringVTable.times_many.values' => True,
);

sub raku-parameter-type(%callable, %parameter --> Str:D) {
    my $c-type = %parameter<c_type>;
    my $name = %parameter<name>;
    my $scope = %callable<owner> eq 'typedef'
        ?? %callable<name> !! "%callable<owner>.%callable<name>";
    my $key = "$scope.$name";
    if %callback-typedefs{$c-type}:exists {
        return "&callback ({raku-signature-body(%callback-typedefs{$c-type})})";
    }
    my $pointer-depth = $c-type.comb('*').elems;
    my $base = clean-c-type($c-type.subst('*', '', :g));
    if $pointer-depth {
        return 'Pointer is rw' if $pointer-depth > 1;
        return 'Pointer' if %array-parameter{$key}:exists || $base eq 'void';
        if %primitive-raku-type{$base}:exists {
            return "%primitive-raku-type{$base} is rw";
        }
        if @structs.first(* eq $base).defined {
            return raku-struct-name($base);
        }
        die "unsupported pointer parameter type $c-type in $key";
    }
    return %primitive-raku-type{$base} if %primitive-raku-type{$base}:exists;
    return %enum-raku-type{$base} if %enum-raku-type{$base}:exists;
    return raku-struct-name($base) if @structs.first(* eq $base).defined;
    die "unsupported value parameter type $c-type in $key";
}

sub raku-return-type(Str:D $c-type --> Str:D) {
    my $base = clean-c-type($c-type);
    return '' if $base eq 'void';
    return %primitive-raku-type{$base} if %primitive-raku-type{$base}:exists;
    return %enum-raku-type{$base} if %enum-raku-type{$base}:exists;
    die "unsupported callable return type $c-type";
}

sub raku-signature-body(%callable --> Str:D) {
    my @parameters = %callable<parameters>.list.map({
        raku-parameter-type(%callable, $_)
    });
    my $returned = raku-return-type(%callable<c_return>);
    @parameters.join(', ') ~ ($returned.chars ?? " --> $returned" !! '')
}

sub raku-signature(%callable --> Str:D) {
    ":({raku-signature-body(%callable)})"
}

my %primitive-julia-type = (
    size_t => 'Csize_t',
    uint64_t => 'UInt64',
    uint32_t => 'UInt32',
    int64_t => 'Int64',
    int32_t => 'Int32',
    uint8_t => 'UInt8',
    double => 'Float64',
    void => 'Cvoid',
);
my %enum-julia-type = @enum-spec.map({ $_[0] => 'UInt32' });
%enum-julia-type<VtStatus> = 'Cint';

sub julia-scalar-type(Str:D $c-type --> Str:D) {
    my $base = clean-c-type($c-type);
    return %primitive-julia-type{$base} if %primitive-julia-type{$base}:exists;
    return %enum-julia-type{$base} if %enum-julia-type{$base}:exists;
    return julia-struct-name($base) if @structs.first(* eq $base).defined;
    die "unsupported Julia scalar type $c-type";
}

sub julia-type(Str:D $c-type, Bool:D :$callback = False --> Str:D) {
    return 'Ptr{Cvoid}' if $callback || (%callback-typedefs{$c-type}:exists);
    my $pointer-depth = $c-type.comb('*').elems;
    my $base = clean-c-type($c-type.subst('*', '', :g));
    my $type = julia-scalar-type($base);
    for ^$pointer-depth {
        $type = "Ptr\{$type\}";
    }
    $type
}

sub julia-parameter-type(%callable, %parameter --> Str:D) {
    my $c-type = %parameter<c_type>;
    return 'Ptr{Cvoid}' if %callback-typedefs{$c-type}:exists;
    return julia-type($c-type) if %callable<owner> eq 'typedef';
    my $pointer-depth = $c-type.comb('*').elems;
    return julia-type($c-type) unless $pointer-depth;
    my $scope = "%callable<owner>.%callable<name>";
    my $key = "$scope.%parameter<name>";
    my $base = clean-c-type($c-type.subst('*', '', :g));
    return julia-type($c-type)
        if %array-parameter{$key}:exists || $base eq 'void';
    my $value-type = julia-scalar-type($base);
    for ^($pointer-depth - 1) {
        $value-type = "Ptr\{$value-type\}";
    }
    "Ref\{$value-type\}"
}

sub julia-signature(%callable --> Str:D) {
    my @parameters = %callable<parameters>.list.map({
        julia-parameter-type(%callable, $_)
    });
    my $arguments = @parameters.elems == 1
        ?? "Tuple\{{@parameters[0]},\}"
        !! "Tuple\{{@parameters.join(', ')}\}";
    "{julia-scalar-type(%callable<c_return>)} $arguments"
}

sub julia-call-name(%callable --> Str:D) {
    my $owner = %callable<owner>.subst(/^ 'Vt' /, '').subst(/ 'VTable' $/, '');
    my $prefix = $owner.comb(/ <[A..Z]> <[a..z0..9]>* /).join('_').lc;
    "abi_call_{$prefix}_{%callable<name>}"
}

sub julia-macro-name(%callable --> Str:D) {
    my $name = %callable<name>.subst(/^ 'Vt' /, '');
    'abi_cfunction_' ~ $name.comb(/ <[A..Z]> <[a..z0..9]>* /).join('_').lc
}

sub julia-struct-dependencies(Str:D $struct --> List:D) {
    %struct-fields{$struct}.list.map(-> %field {
        next if %field<c_return>:exists;
        my $base = clean-c-type(%field<c_type>.subst('*', '', :g));
        $base if $base ne $struct && @structs.first(* eq $base).defined;
    }).grep(*.defined).unique.List
}

sub julia-struct-order(--> Array:D) {
    my @remaining = @structs;
    my @ordered;
    my %emitted;
    while @remaining {
        my $before = @remaining.elems;
        for @remaining.List -> $struct {
            my @missing = julia-struct-dependencies($struct).grep({
                !(%emitted{$_}:exists)
            });
            next if @missing;
            @ordered.push($struct);
            %emitted{$struct} = True;
            @remaining = @remaining.grep(* ne $struct);
        }
        die "cyclic Julia struct dependencies: {@remaining.join(', ')}"
            if @remaining.elems == $before;
    }
    @ordered.Array
}

sub julia-field-type(Str:D $struct, %field --> Str:D) {
    return 'Ptr{Cvoid}' if %field<c_return>:exists;
    my $type = julia-type(%field<c_type>);
    %field<array_count>:exists
        ?? "NTuple\{{%field<array_count>}, $type\}"
        !! $type
}

sub julia-struct-extra-lines(Str:D $struct --> Array:D) {
    return [] unless $struct eq 'VtDictionaryEntryBatchLimits';
    [
        '',
        '    function BatchLimits(max_entries::Integer=256, max_units::Integer=65_536,',
        '        max_values::Integer=256)',
        '        max_entries > 0 || throw(ArgumentError("max_entries must be positive"))',
        '        max_units >= 0 || throw(ArgumentError("max_units cannot be negative"))',
        '        max_values >= 0 || throw(ArgumentError("max_values cannot be negative"))',
        '        new(max_entries, max_units, max_values, 0)',
        '    end',
    ]
}

sub render-julia-struct(Str:D $struct --> Array:D) {
    my @lines = "struct {julia-struct-name($struct)}";
    for %struct-fields{$struct}.list -> %field {
        @lines.push("    {%field<name>}::{julia-field-type($struct, %field)}");
    }
    @lines.append(julia-struct-extra-lines($struct));
    @lines.push('end');
    @lines.Array
}

sub render-julia-call(%callable --> Array:D) {
    my @types = %callable<parameters>.list.map({
        julia-parameter-type(%callable, $_)
    });
    my @names = %callable<parameters>.list.map(*.<name>);
    my $tuple = @types.elems == 1
        ?? "({@types[0]},)"
        !! "({@types.join(', ')})";
    my $arguments = @names.elems ?? ', ' ~ @names.join(', ') !! '';
    [
        "\@inline function {julia-call-name(%callable)}(address::Ptr\{Cvoid\}" ~
            (@names.elems ?? ', ' ~ @names.join(', ') !! '') ~ ')',
        "    ccall(address, {julia-scalar-type(%callable<c_return>)}, $tuple$arguments)",
        'end',
    ]
}

sub render-julia-cfunction-macro(%callable --> Array:D) {
    my @types = %callable<parameters>.list.map({ julia-type($_<c_type>) });
    my $tuple = @types.elems == 1
        ?? "({@types[0]},)"
        !! "({@types.join(', ')})";
    [
        "macro {julia-macro-name(%callable)}(callback)",
        '    esc(:(@cfunction($callback, ' ~
            julia-scalar-type(%callable<c_return>) ~ ", $tuple)))",
        'end',
    ]
}

my %vtable-prefix = (
    VtResourceVTable => 'resource',
    VtDictionaryVTable => 'dictionary',
    VtDictionaryVisitVTable => 'dictionary-visit',
    VtDictionaryGraphVTable => 'dictionary-graph',
    VtSnapshotIdentityVTable => 'snapshot-identity',
    VtDictionaryEntriesVTable => 'dictionary-entries',
    VtWfstVTable => 'wfst',
    VtLatticeVTable => 'lattice',
    VtSemiringVTable => 'semiring',
    VtSemiringDivisionVTable => 'semiring-division',
    VtSemiringStarVTable => 'semiring-star',
    VtSemiringNumericVTable => 'semiring-numeric',
    VtSemiringPropertiesVTable => 'semiring-properties',
);

sub cast-helper-name(%callable --> Str:D) {
    my $prefix = %vtable-prefix{%callable<owner>}
        // die "missing cast-helper prefix for %callable<owner>";
    "abi-cast-$prefix-{raku-field-name(%callable<name>)}"
}

my @raku-layouts;
for @structs.kv -> $index, $struct {
    @raku-layouts.append(render-struct($struct));
    @raku-layouts.push('') unless $index == @structs.end;
}
@raku-layouts.append(
    '',
    "our constant ABI-STRUCT-COUNT is export(:abi) = {@structs.elems};",
    "our constant ABI-CALLABLE-COUNT is export(:abi) = {@operations.elems};",
    '',
);
for @operations.kv -> $index, %callable {
    my $helper = cast-helper-name(%callable);
    my $signature = raku-signature(%callable);
    @raku-layouts.append(
        "sub $helper" ~ q[(Pointer:D $address) is export(:abi) {],
        "    nativecast($signature, " ~ q[$address)],
        '}',
    );
    @raku-layouts.push('') unless $index == @operations.end;
}

my $raku-file = $root.add('bindings/raku/lib/Vinary/Tree/Interop.rakumod');
my $raku-key = $raku-file.Str;
my $raku-current = %updated{$raku-key} // $raku-file.slurp;
%updated{$raku-key} = replace-region(
    $raku-current,
    'ABI LAYOUTS AND CALLABLES',
    @raku-layouts,
);

my %vtable-interface = (
    VtDictionaryVTable => 'DICTIONARY',
    VtDictionaryVisitVTable => 'DICTIONARY_VISIT',
    VtDictionaryGraphVTable => 'DICTIONARY_GRAPH',
    VtSnapshotIdentityVTable => 'SNAPSHOT_IDENTITY',
    VtDictionaryEntriesVTable => 'DICTIONARY_ENTRIES',
    VtWfstVTable => 'WFST',
    VtLatticeVTable => 'LATTICE',
    VtSemiringVTable => 'SEMIRING',
    VtSemiringDivisionVTable => 'SEMIRING_DIVISION',
    VtSemiringStarVTable => 'SEMIRING_STAR',
    VtSemiringNumericVTable => 'SEMIRING_NUMERIC',
    VtSemiringPropertiesVTable => 'SEMIRING_PROPERTIES',
);

sub parameter-contract(%callable --> Str:D) {
    %callable<parameters>.list.map(-> %parameter {
        my $name = %parameter<name>;
        my $direction = $name.starts-with('out_') ?? 'output'
            !! ($name eq 'cursor' ||
                (%callable<name> eq 'release_values' && $name eq 'values')
                ?? 'inout' !! 'input');
        my $owned-output-type = clean-c-type(
            %parameter<c_type>.subst('*', '', :g),
        );
        my $ownership = $name.starts-with('out_') &&
                ($name eq 'out_snapshot' || $name eq 'out_cursor' ||
                    ($name eq 'out_value' &&
                        $owned-output-type eq any(<VtResource VtSemiringValue>)))
            ?? 'owned'
            !! ((%callable<name> eq 'release_values' && $name eq 'values') ||
                    (%callable<owner> eq 'VtResourceVTable' &&
                        %callable<name> eq 'release' && $name eq 'context') ||
                    (%callable<owner> eq 'VtDictionaryEntriesVTable' &&
                        %callable<name> eq 'close' && $name eq 'cursor')
                ?? 'consumed' !! 'borrowed');
        "$name:$direction:$ownership"
    }).join(',')
}

my @julia-order = julia-struct-order();
die 'VtInterfaceId is missing from the generated Julia struct order'
    unless @julia-order.first(* eq 'VtInterfaceId').defined;

my @julia-layouts;
for @julia-order.grep(* ne 'VtInterfaceId') -> $struct {
    @julia-layouts.append(render-julia-struct($struct));
    @julia-layouts.push('');
}

for %callback-typedefs.values.sort(*.<name>) -> %callable {
    @julia-layouts.append(render-julia-cfunction-macro(%callable));
    @julia-layouts.push('');
}
for @operations -> %callable {
    @julia-layouts.append(render-julia-call(%callable));
    @julia-layouts.push('');
}

@julia-layouts.append(
    "const ABI_STRUCT_NAMES = ({@julia-order.map({ ':' ~ julia-struct-name($_) }).join(', ')})",
    "const ABI_STRUCT_COUNT = {@structs.elems}",
    "const ABI_OPERATION_COUNT = {@operations.elems}",
    "const ABI_CALLBACK_COUNT = {%callback-typedefs.elems}",
    "const ABI_CALLABLE_COUNT = {@operations.elems + %callback-typedefs.elems}",
    'const ABI_CALLABLES = (',
);
for %callback-typedefs.values.sort(*.<name>) -> %callable {
    @julia-layouts.push(
        '    (kind=:callback, owner=:typedef, name=:' ~ %callable<name> ~
        ', julia_name=Symbol("@' ~ julia-macro-name(%callable) ~ '")' ~
        ', signature="' ~ julia-signature(%callable) ~
        '", parameter_contract="' ~ parameter-contract(%callable) ~
        '", threading=:julia_owned_calling_thread_only, capability=:dictionary_entry_reducer),'
    );
}
for @operations -> %callable {
    my $interface = %vtable-interface{%callable<owner>};
    my $capability = $interface.defined
        ?? $interface.lc.subst('_', '-', :g)
        !! 'resource';
    @julia-layouts.push(
        '    (kind=:operation, owner=:' ~ %callable<owner> ~
        ', name=:' ~ %callable<name> ~
        ', julia_name=:' ~ julia-call-name(%callable) ~
        ', signature="' ~ julia-signature(%callable) ~
        '", parameter_contract="' ~ parameter-contract(%callable) ~
        '", threading=:caller_thread_synchronous, capability=Symbol("' ~
        $capability ~ '")),'
    );
}
@julia-layouts.push(')');

my $julia-file = $root.add('bindings/julia/VinaryTreeInterop/src/VinaryTreeInterop.jl');
my $julia-key = $julia-file.Str;
my $julia-current = %updated{$julia-key} // $julia-file.slurp;
$julia-current = replace-region(
    $julia-current,
    'ABI INTERFACE ID LAYOUT',
    render-julia-struct('VtInterfaceId'),
);
%updated{$julia-key} = replace-region(
    $julia-current,
    'ABI LAYOUTS AND CALLABLES',
    @julia-layouts,
);

my @inventory = [[
    <kind owner c_name raku_name julia_name version identity c_signature raku_signature julia_signature parameter_contract threading capability notes>
].flat.join("\t")];
for @interfaces -> @interface {
    my ($constant, $routine) = @interface;
    @inventory.push([
        'interface', '-', "VT_{$constant}_INTERFACE_ID",
        "{$routine}-interface-id", "{$constant}_INTERFACE_ID",
        macro-value("VT_{$constant}_INTERFACE_VERSION"),
        %interface-ids{$constant}, '-', '-', '-', '-', 'caller-thread-synchronous',
        $routine, 'versioned optional capability',
    ].join("\t"));
}
for @structs -> $struct {
    @inventory.push([
        'struct', '-', $struct, raku-struct-name($struct),
        julia-struct-name($struct), '-', '-', '-', '-', '-', '-',
        'not-applicable', 'layout', 'generated Julia and NativeCall layouts',
    ].join("\t"));
}
for %callback-typedefs.values.sort(*.<name>) -> %callable {
    @inventory.push([
        'callback', 'typedef', %callable<name>, %callable<name>,
        '@' ~ julia-macro-name(%callable), '-', '-',
        %callable<c_signature>, raku-signature(%callable), julia-signature(%callable),
        parameter-contract(%callable), 'host-runtime-attached-calling-thread-only',
        'dictionary-entry-reducer', 'generated Julia and NativeCall callback signature',
    ].join("\t"));
}
for @operations -> %callable {
    my $interface = %vtable-interface{%callable<owner>};
    my $version = $interface.defined
        ?? macro-value("VT_{$interface}_INTERFACE_VERSION")
        !! macro-value('VT_ABI_VERSION');
    my $identity = $interface.defined ?? %interface-ids{$interface} !! '-';
    @inventory.push([
        'operation', %callable<owner>, %callable<name>,
        cast-helper-name(%callable), julia-call-name(%callable), $version, $identity,
        %callable<c_signature>, raku-signature(%callable), julia-signature(%callable),
        parameter-contract(%callable), 'caller-thread-synchronous',
        $interface.defined ?? $interface.lc.subst('_', '-', :g) !! 'resource',
        'generated Julia ccall wrapper and typed NativeCall cast',
    ].join("\t"));
}
my $inventory = @inventory.join("\n") ~ "\n";
my $inventory-path = $root.add('bindings/generated/abi-capabilities.tsv');
my @header-targets =
    $root.add('bindings/go/vinary_tree_interop.h'),
    $root.add('bindings/haskell/include/vinary_tree_interop.h'),
    $root.add('bindings/ocaml/vinary_tree_interop.h'),
    $root.add('bindings/raku/resources/include/vinary_tree_interop.h');
my $header = $header-path.slurp;

sub outside-generated-region(Str:D $text, Str:D $label --> Str:D) {
    my $begin = "# BEGIN GENERATED $label";
    my $end = "# END GENERATED $label";
    my $start = $text.index($begin) // die "missing marker $begin";
    my $finish = $text.index($end, $start) // die "missing marker $end";
    $text.substr(0, $start) ~ $text.substr($finish + $end.chars)
}

my $facade-outside-abi = outside-generated-region(
    $raku-file.slurp,
    'ABI LAYOUTS AND CALLABLES',
);
die 'Raku ergonomic facade must not handwrite CStruct layouts outside the generated ABI region'
    if $facade-outside-abi.contains("repr('CStruct')");
die 'Raku ergonomic facade must use generated typed callback casts'
    if $facade-outside-abi ~~ / 'nativecast' \s* '(' \s* ':(' /;

sub julia-facade-has-handwritten-abi(Str:D $text --> Bool:D) {
    my $outside = $text;
    for 'ABI CONSTANTS', 'ABI INTERFACE ID LAYOUT', 'ABI INTERFACE IDS',
            'ABI LAYOUTS AND CALLABLES' -> $label {
        $outside = outside-generated-region($outside, $label);
    }
    $outside.contains('ccall(') || $outside.contains('@cfunction') ||
        $outside.contains('struct Vt')
}

die 'Julia ergonomic facade must use generated layouts and typed callable wrappers'
    if julia-facade-has-handwritten-abi(%updated{$julia-key});

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

if $mode ne '--write' && @differences {
    note "generated bindings are stale:\n  " ~ @differences.join("\n  ");
    note 'run: raku scripts/generate-bindings.raku --write';
    exit 1;
}

if $mode eq '--self-test' {
    my $needle =
        "our constant ABI-CALLABLE-COUNT is export(:abi) = {@operations.elems};";
    my $negative = %updated{$raku-key}.subst(
        $needle,
        "our constant ABI-CALLABLE-COUNT is export(:abi) = {@operations.elems + 1};",
    );
    die 'negative control could not perturb the generated Raku ABI'
        if $negative eq %updated{$raku-key};
    die 'negative control did not make the committed Raku ABI stale'
        if $negative eq $raku-file.slurp;
    my $julia-needle =
        "const ABI_CALLABLE_COUNT = {@operations.elems + %callback-typedefs.elems}";
    my $julia-negative = %updated{$julia-key}.subst(
        $julia-needle,
        "const ABI_CALLABLE_COUNT = {@operations.elems + %callback-typedefs.elems + 1}",
    );
    die 'negative control could not perturb the generated Julia ABI'
        if $julia-negative eq %updated{$julia-key};
    die 'negative control did not make the committed Julia ABI stale'
        if $julia-negative eq $julia-file.slurp;
    my $handwritten-julia-drift =
        %updated{$julia-key} ~ "\nccall(C_NULL, Cvoid, ())\n";
    die 'negative control did not detect a handwritten Julia ccall signature'
        unless julia-facade-has-handwritten-abi($handwritten-julia-drift);
    say 'negative controls passed: generated Raku and Julia drift plus handwritten Julia ccall duplication are rejected';
    exit 0;
}

say $mode eq '--write'
    ?? "updated {@differences.elems} generated binding file(s)"
    !! 'generated binding declarations and capability inventory are current';
