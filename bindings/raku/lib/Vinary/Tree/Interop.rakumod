unit module Vinary::Tree::Interop;

use NativeCall;

sub native-header-path(--> IO::Path:D) is export {
    %?RESOURCES<include/vinary_tree_interop.h>.IO.absolute.IO
}

sub materialize-native-header(IO() $directory --> IO::Path:D) is export {
    my $include-directory = $directory.IO.absolute.IO;
    $include-directory.mkdir(:parents);
    my $header = $include-directory.add('vinary_tree_interop.h');
    $header.spurt(native-header-path().slurp(:bin), :bin);
    $header
}

# BEGIN GENERATED ABI CONSTANTS
our constant ABI-VERSION is export = 1;
our constant DICTIONARY-INTERFACE-VERSION is export = 1;
our constant DICTIONARY-VISIT-INTERFACE-VERSION is export = 1;
our constant DICTIONARY-GRAPH-INTERFACE-VERSION is export = 1;
our constant DICTIONARY-ENTRIES-INTERFACE-VERSION is export = 1;
our constant SNAPSHOT-IDENTITY-INTERFACE-VERSION is export = 1;
our constant WFST-INTERFACE-VERSION is export = 1;
our constant LATTICE-INTERFACE-VERSION is export = 1;
our constant SEMIRING-INTERFACE-VERSION is export = 1;
our constant SEMIRING-DIVISION-INTERFACE-VERSION is export = 1;
our constant SEMIRING-STAR-INTERFACE-VERSION is export = 1;
our constant SEMIRING-NUMERIC-INTERFACE-VERSION is export = 1;
our constant SEMIRING-PROPERTIES-INTERFACE-VERSION is export = 1;
our constant RECOMMENDED-EDGE-BATCH is export = 256;
our constant RECOMMENDED-ARC-BATCH is export = 256;
our constant RECOMMENDED-LATTICE-BATCH is export = 256;
our constant RECOMMENDED-SEMIRING-BATCH is export = 256;
our constant SEMIRING-ORDER-BETTER is export = -1;
our constant SEMIRING-ORDER-EQUAL is export = 0;
our constant SEMIRING-ORDER-WORSE is export = 1;
our constant SEMIRING-ORDER-INCOMPARABLE is export = 2;

our enum Status is export (
    OK => 0,
    END => 1,
    INVALID-ARGUMENT => 2,
    NULL-POINTER => 3,
    UNSUPPORTED => 4,
    IO-ERROR => 5,
    CLOSED => 6,
    LIMIT-EXCEEDED => 7,
    PROVIDER-ERROR => 8,
    BATCH-IN-USE => 9,
);

our enum UnitDomain is export (
    BYTE => 1,
    UNICODE-SCALAR => 2,
    U64 => 3,
);

our enum ValueDomain is export (
    UNIT => 0,
    OPTIONAL-U64 => 1,
    BYTES => 2,
);

our enum EntryOrder is export (
    LEXICOGRAPHIC => 1,
);

our enum WeightDomain is export (
    TROPICAL-F64 => 1,
    LOG-F64 => 2,
    PROBABILITY-F64 => 3,
    ARCTIC-F64 => 4,
    SIGNED-TROPICAL-F64 => 5,
    COUNT-F64 => 6,
    BOOLEAN-F64 => 7,
);

our constant DICTIONARY-FLAG-PARALLEL-REENTRANT is export = 1;
our constant DICTIONARY-FLAG-SUFFIX-BASED is export = 2;
our constant DICTIONARY-FLAG-IMMUTABLE is export = 4;
our constant ENTRIES-INFO-FLAG-EXACT-LEN is export = 1;
our constant ENTRIES-INFO-FLAG-SNAPSHOT-IDENTITY is export = 2;
our constant WFST-FLAG-PARALLEL-REENTRANT is export = 1;
our constant WFST-FLAG-IMMUTABLE is export = 2;
our constant WFST-FLAG-LAZY is export = 4;
our constant WFST-FLAG-ACYCLIC is export = 8;
our constant LATTICE-FLAG-THREAD-BOUND is export = 1;
our constant LATTICE-FLAG-PARALLEL-REENTRANT is export = 2;
our constant LATTICE-FLAG-STABLE-BYTES is export = 4;
our constant LATTICE-FLAG-BATCH is export = 8;
our constant SEMIRING-FLAG-THREAD-BOUND is export = 1;
our constant SEMIRING-FLAG-PARALLEL-REENTRANT is export = 2;
our constant SEMIRING-FLAG-STABLE-BYTES is export = 4;
our constant SEMIRING-FLAG-BATCH is export = 8;
our constant SEMIRING-PROPERTY-HASHABLE is export = 1;
our constant SEMIRING-PROPERTY-IDEMPOTENT-PLUS is export = 2;
our constant SEMIRING-PROPERTY-K-CLOSED is export = 4;
our constant SEMIRING-PROPERTY-ZERO-SUM-FREE is export = 8;
our constant SEMIRING-PROPERTY-COMMUTATIVE-TIMES is export = 16;
our constant SEMIRING-PROPERTY-TOTALLY-ORDERED is export = 32;
our constant SEMIRING-PROPERTY-NONNEGATIVE is export = 64;
# END GENERATED ABI CONSTANTS

class X::Vinary::Tree::Interop is Exception is export {
    has Status:D $.status is required;
    has Str:D $.operation is required;

    method message(--> Str:D) {
        "Vinary Tree interop operation '$!operation' failed with $!status"
    }
}

# BEGIN GENERATED ABI LAYOUTS AND CALLABLES
class InterfaceId is repr('CStruct') is export {
    has uint8 $.b0;
    has uint8 $.b1;
    has uint8 $.b2;
    has uint8 $.b3;
    has uint8 $.b4;
    has uint8 $.b5;
    has uint8 $.b6;
    has uint8 $.b7;
    has uint8 $.b8;
    has uint8 $.b9;
    has uint8 $.b10;
    has uint8 $.b11;
    has uint8 $.b12;
    has uint8 $.b13;
    has uint8 $.b14;
    has uint8 $.b15;

    method bytes(--> List:D) {
        ($!b0, $!b1, $!b2, $!b3, $!b4, $!b5, $!b6, $!b7,
            $!b8, $!b9, $!b10, $!b11, $!b12, $!b13, $!b14, $!b15)
    }
}

class RawResource is repr('CStruct') is export {
    has Pointer $.context is rw;
    has Pointer $.vtable is rw;
}

class ResourceVTable is repr('CStruct') is export {
    has size_t $.struct-size;
    has uint32 $.abi-version;
    has uint32 $.reserved;
    has Pointer $.retain;
    has Pointer $.release;
    has Pointer $.query-interface;
}

class OptionalU64 is repr('CStruct') is export {
    has uint64 $.value;
    has uint8 $.has-value;
    has uint8 $.reserved0;
    has uint8 $.reserved1;
    has uint8 $.reserved2;
    has uint8 $.reserved3;
    has uint8 $.reserved4;
    has uint8 $.reserved5;
    has uint8 $.reserved6;
}

class DictionaryEdge is repr('CStruct') is export {
    has uint64 $.label;
    has uint64 $.node;
}

class DictionaryVTable is repr('CStruct') is export {
    has size_t $.struct-size;
    has uint32 $.interface-version;
    has uint32 $.unit-domain;
    has uint32 $.value-domain;
    has uint64 $.flags;
    has Pointer $.snapshot;
    has Pointer $.root;
    has Pointer $.len;
    has Pointer $.node-is-final;
    has Pointer $.node-value-u64;
    has Pointer $.node-transition;
    has Pointer $.node-edges;
}

class DictionaryVisitVTable is repr('CStruct') is export {
    has size_t $.struct-size;
    has uint32 $.interface-version;
    has uint32 $.reserved;
    has Pointer $.node-visit;
}

class DictionaryGraphNode is repr('CStruct') is export {
    has uint64 $.edge-start;
    has uint64 $.edge-len;
    has uint64 $.value-cursor;
    has uint8 $.is-final;
    has uint8 $.reserved0;
    has uint8 $.reserved1;
    has uint8 $.reserved2;
    has uint8 $.reserved3;
    has uint8 $.reserved4;
    has uint8 $.reserved5;
    has uint8 $.reserved6;
}

class DictionaryGraphEdge is repr('CStruct') is export {
    has uint64 $.label;
    has uint64 $.target;
}

class DictionaryGraphView is repr('CStruct') is export {
    has Pointer[DictionaryGraphNode] $.nodes;
    has size_t $.node-count;
    has Pointer[DictionaryGraphEdge] $.edges;
    has size_t $.edge-count;
    has uint64 $.root;
    has uint64 $.reserved;
}

class DictionaryGraphVTable is repr('CStruct') is export {
    has size_t $.struct-size;
    has uint32 $.interface-version;
    has uint32 $.reserved;
    has Pointer $.graph;
    has Pointer $.node-value-u64;
}

class SnapshotIdentity is repr('CStruct') is export {
    has uint64 $.producer;
    has uint64 $.revision;
}

class SnapshotIdentityVTable is repr('CStruct') is export {
    has size_t $.struct-size;
    has uint32 $.interface-version;
    has uint32 $.reserved;
    has Pointer $.identity;
}

class DictionaryEntryDescriptor is repr('CStruct') is export {
    has size_t $.unit-offset;
    has size_t $.unit-len;
    has size_t $.value-offset;
    has size_t $.value-len;
    has uint64 $.reserved;
}

class BatchLimits is repr('CStruct') is export {
    has size_t $.max-entries;
    has size_t $.max-units;
    has size_t $.max-values;
    has uint64 $.reserved;

    method new(
        Int:D :$max-entries = 256,
        Int:D :$max-units = 65_536,
        Int:D :$max-values = 256,
    ) {
        die 'max-entries must be positive' unless $max-entries > 0;
        die 'max-units cannot be negative' unless $max-units >= 0;
        die 'max-values cannot be negative' unless $max-values >= 0;
        self.bless(:$max-entries, :$max-units, :$max-values, :reserved(0))
    }
}

class DictionaryEntryBatchView is repr('CStruct') is export {
    has Pointer[DictionaryEntryDescriptor] $.entries;
    has size_t $.entry-count;
    has Pointer $.units;
    has size_t $.unit-count;
    has Pointer[uint64] $.values;
    has size_t $.value-count;
    has uint64 $.generation;
    has uint64 $.reserved;
}

class DictionaryEntriesInfo is repr('CStruct') is export {
    has uint32 $.unit-domain;
    has uint32 $.value-domain;
    has uint32 $.order;
    has uint32 $.reserved0;
    has uint64 $.flags;
    has size_t $.exact-len;
    has uint64 $.identity-producer;
    has uint64 $.identity-revision;
    has uint64 $.reserved1;
    has uint64 $.reserved2;
}

class RawDictionaryEntriesCursor is repr('CStruct') is export {
    has Pointer $.context is rw;
    has Pointer $.vtable is rw;
}

class DictionaryEntriesVTable is repr('CStruct') is export {
    has size_t $.struct-size;
    has uint32 $.interface-version;
    has uint32 $.reserved;
    has Pointer $.open;
    has Pointer $.next-batch;
    has Pointer $.release-batch;
    has Pointer $.reduce;
    has Pointer $.cancel;
    has Pointer $.close;
}

class WfstArc is repr('CStruct') is export {
    has uint64 $.input-label;
    has uint64 $.output-label;
    has uint64 $.target-state;
    has num64 $.weight;
    has uint8 $.has-input;
    has uint8 $.has-output;
    has uint8 $.reserved0;
    has uint8 $.reserved1;
    has uint8 $.reserved2;
    has uint8 $.reserved3;
    has uint8 $.reserved4;
    has uint8 $.reserved5;
}

class WfstVTable is repr('CStruct') is export {
    has size_t $.struct-size;
    has uint32 $.interface-version;
    has uint32 $.unit-domain;
    has uint32 $.weight-domain;
    has uint32 $.reserved;
    has uint64 $.flags;
    has Pointer $.snapshot;
    has Pointer $.start;
    has Pointer $.num-states;
    has Pointer $.state-info;
    has Pointer $.state-arcs;
}

class LatticeVTable is repr('CStruct') is export {
    has size_t $.struct-size;
    has uint32 $.interface-version;
    has uint32 $.reserved;
    has uint64 $.flags;
    HAS InterfaceId $.domain-id;
    has Pointer $.join;
    has Pointer $.meet;
    has Pointer $.equal;
    has Pointer $.stable-bytes;
    has Pointer $.diagnostic;
    has Pointer $.join-many;
    has Pointer $.meet-many;
}

class SemiringValue is repr('CStruct') is export {
    has uint64 $.word0 is rw;
    has uint64 $.word1 is rw;
}

class SemiringVTable is repr('CStruct') is export {
    has size_t $.struct-size;
    has uint32 $.interface-version;
    has uint32 $.reserved;
    has uint64 $.flags;
    HAS InterfaceId $.domain-id;
    has Pointer $.zero;
    has Pointer $.one;
    has Pointer $.clone-value;
    has Pointer $.release-values;
    has Pointer $.plus;
    has Pointer $.times;
    has Pointer $.equal;
    has Pointer $.approx-equal;
    has Pointer $.natural-order;
    has Pointer $.stable-bytes;
    has Pointer $.diagnostic;
    has Pointer $.plus-many;
    has Pointer $.times-many;
}

class SemiringDivisionVTable is repr('CStruct') is export {
    has size_t $.struct-size;
    has uint32 $.interface-version;
    has uint32 $.reserved;
    has Pointer $.divide;
    has Pointer $.left-divide;
}

class SemiringStarVTable is repr('CStruct') is export {
    has size_t $.struct-size;
    has uint32 $.interface-version;
    has uint32 $.reserved;
    has Pointer $.star;
}

class SemiringNumericVTable is repr('CStruct') is export {
    has size_t $.struct-size;
    has uint32 $.interface-version;
    has uint32 $.reserved;
    has Pointer $.numerical-value;
    has Pointer $.quantize;
    has Pointer $.to-probability;
}

class SemiringPropertiesVTable is repr('CStruct') is export {
    has size_t $.struct-size;
    has uint32 $.interface-version;
    has uint32 $.reserved;
    has uint64 $.properties;
    has Pointer $.closure-bound;
}

our constant ABI-STRUCT-COUNT is export(:abi) = 28;
our constant ABI-CALLABLE-COUNT is export(:abi) = 52;

sub abi-cast-resource-retain(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer), $address)
}

sub abi-cast-resource-release(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer), $address)
}

sub abi-cast-resource-query-interface(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, InterfaceId, uint32, Pointer is rw --> int32), $address)
}

sub abi-cast-dictionary-snapshot(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, RawResource --> int32), $address)
}

sub abi-cast-dictionary-root(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, uint64 is rw --> int32), $address)
}

sub abi-cast-dictionary-len(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, size_t is rw, uint8 is rw --> int32), $address)
}

sub abi-cast-dictionary-node-is-final(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, uint64, uint8 is rw --> int32), $address)
}

sub abi-cast-dictionary-node-value-u64(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, uint64, OptionalU64 --> int32), $address)
}

sub abi-cast-dictionary-node-transition(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, uint64, uint64, uint64 is rw, uint8 is rw --> int32), $address)
}

sub abi-cast-dictionary-node-edges(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, uint64, size_t, Pointer, size_t, size_t is rw, size_t is rw --> int32), $address)
}

sub abi-cast-dictionary-visit-node-visit(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, uint64, size_t, uint8 is rw, Pointer, size_t, size_t is rw, size_t is rw --> int32), $address)
}

sub abi-cast-dictionary-graph-graph(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, DictionaryGraphView --> int32), $address)
}

sub abi-cast-dictionary-graph-node-value-u64(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, uint64, OptionalU64 --> int32), $address)
}

sub abi-cast-snapshot-identity-identity(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, SnapshotIdentity --> int32), $address)
}

sub abi-cast-dictionary-entries-open(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, RawDictionaryEntriesCursor, DictionaryEntriesInfo --> int32), $address)
}

sub abi-cast-dictionary-entries-next-batch(Pointer:D $address) is export(:abi) {
    nativecast(:(RawDictionaryEntriesCursor, BatchLimits, DictionaryEntryBatchView --> int32), $address)
}

sub abi-cast-dictionary-entries-release-batch(Pointer:D $address) is export(:abi) {
    nativecast(:(RawDictionaryEntriesCursor, uint64 --> int32), $address)
}

sub abi-cast-dictionary-entries-reduce(Pointer:D $address) is export(:abi) {
    nativecast(:(RawDictionaryEntriesCursor, BatchLimits, &callback (Pointer, Pointer --> int32), Pointer, size_t is rw --> int32), $address)
}

sub abi-cast-dictionary-entries-cancel(Pointer:D $address) is export(:abi) {
    nativecast(:(RawDictionaryEntriesCursor --> int32), $address)
}

sub abi-cast-dictionary-entries-close(Pointer:D $address) is export(:abi) {
    nativecast(:(RawDictionaryEntriesCursor --> int32), $address)
}

sub abi-cast-wfst-snapshot(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, RawResource --> int32), $address)
}

sub abi-cast-wfst-start(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, uint64 is rw --> int32), $address)
}

sub abi-cast-wfst-num-states(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, size_t is rw, uint8 is rw --> int32), $address)
}

sub abi-cast-wfst-state-info(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, uint64, uint8 is rw, uint8 is rw, num64 is rw --> int32), $address)
}

sub abi-cast-wfst-state-arcs(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, uint64, size_t, Pointer, size_t, size_t is rw, size_t is rw --> int32), $address)
}

sub abi-cast-lattice-join(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, RawResource, RawResource --> int32), $address)
}

sub abi-cast-lattice-meet(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, RawResource, RawResource --> int32), $address)
}

sub abi-cast-lattice-equal(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, RawResource, uint8 is rw --> int32), $address)
}

sub abi-cast-lattice-stable-bytes(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, Pointer, size_t, size_t is rw, size_t is rw --> int32), $address)
}

sub abi-cast-lattice-diagnostic(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, Pointer, size_t, size_t is rw, size_t is rw --> int32), $address)
}

sub abi-cast-lattice-join-many(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, Pointer, size_t, RawResource --> int32), $address)
}

sub abi-cast-lattice-meet-many(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, Pointer, size_t, RawResource --> int32), $address)
}

sub abi-cast-semiring-zero(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, SemiringValue --> int32), $address)
}

sub abi-cast-semiring-one(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, SemiringValue --> int32), $address)
}

sub abi-cast-semiring-clone-value(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, SemiringValue, SemiringValue --> int32), $address)
}

sub abi-cast-semiring-release-values(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, Pointer, size_t --> int32), $address)
}

sub abi-cast-semiring-plus(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, SemiringValue, SemiringValue, SemiringValue --> int32), $address)
}

sub abi-cast-semiring-times(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, SemiringValue, SemiringValue, SemiringValue --> int32), $address)
}

sub abi-cast-semiring-equal(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, SemiringValue, SemiringValue, uint8 is rw --> int32), $address)
}

sub abi-cast-semiring-approx-equal(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, SemiringValue, SemiringValue, num64, uint8 is rw --> int32), $address)
}

sub abi-cast-semiring-natural-order(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, SemiringValue, SemiringValue, int32 is rw --> int32), $address)
}

sub abi-cast-semiring-stable-bytes(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, SemiringValue, Pointer, size_t, size_t is rw, size_t is rw --> int32), $address)
}

sub abi-cast-semiring-diagnostic(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, SemiringValue, Pointer, size_t, size_t is rw, size_t is rw --> int32), $address)
}

sub abi-cast-semiring-plus-many(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, Pointer, size_t, SemiringValue --> int32), $address)
}

sub abi-cast-semiring-times-many(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, Pointer, size_t, SemiringValue --> int32), $address)
}

sub abi-cast-semiring-division-divide(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, SemiringValue, SemiringValue, SemiringValue --> int32), $address)
}

sub abi-cast-semiring-division-left-divide(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, SemiringValue, SemiringValue, SemiringValue --> int32), $address)
}

sub abi-cast-semiring-star-star(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, SemiringValue, SemiringValue --> int32), $address)
}

sub abi-cast-semiring-numeric-numerical-value(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, SemiringValue, num64 is rw --> int32), $address)
}

sub abi-cast-semiring-numeric-quantize(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, SemiringValue, num64, int64 is rw --> int32), $address)
}

sub abi-cast-semiring-numeric-to-probability(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, SemiringValue, num64 is rw --> int32), $address)
}

sub abi-cast-semiring-properties-closure-bound(Pointer:D $address) is export(:abi) {
    nativecast(:(Pointer, size_t is rw, uint8 is rw --> int32), $address)
}
# END GENERATED ABI LAYOUTS AND CALLABLES

sub interface-id(Str:D $text --> InterfaceId:D) is export {
    my @bytes = $text.encode('ascii').list;
    die "interface identifiers are exactly 16 bytes" unless @bytes.elems == 16;
    InterfaceId.new(
        b0 => @bytes[0], b1 => @bytes[1], b2 => @bytes[2], b3 => @bytes[3],
        b4 => @bytes[4], b5 => @bytes[5], b6 => @bytes[6], b7 => @bytes[7],
        b8 => @bytes[8], b9 => @bytes[9], b10 => @bytes[10],
        b11 => @bytes[11], b12 => @bytes[12], b13 => @bytes[13],
        b14 => @bytes[14], b15 => @bytes[15],
    )
}

# BEGIN GENERATED ABI INTERFACE IDS
sub dictionary-interface-id(--> InterfaceId:D) is export {
    interface-id('vt.dictionary.v1')
}

sub dictionary-visit-interface-id(--> InterfaceId:D) is export {
    interface-id('vt.dict.visit.v1')
}

sub dictionary-graph-interface-id(--> InterfaceId:D) is export {
    interface-id('vt.dict.graph.v1')
}

sub dictionary-entries-interface-id(--> InterfaceId:D) is export {
    interface-id('vt.dict.entry.v1')
}

sub snapshot-identity-interface-id(--> InterfaceId:D) is export {
    interface-id('vt.snapshot.id.1')
}

sub wfst-interface-id(--> InterfaceId:D) is export {
    interface-id('vt.scalar-wfst.1')
}

sub lattice-interface-id(--> InterfaceId:D) is export {
    interface-id('vt.lattice.val.1')
}

sub semiring-interface-id(--> InterfaceId:D) is export {
    interface-id('vt.semiring.val1')
}

sub semiring-division-interface-id(--> InterfaceId:D) is export {
    interface-id('vt.semiring.div1')
}

sub semiring-star-interface-id(--> InterfaceId:D) is export {
    interface-id('vt.semiring.str1')
}

sub semiring-numeric-interface-id(--> InterfaceId:D) is export {
    interface-id('vt.semiring.num1')
}

sub semiring-properties-interface-id(--> InterfaceId:D) is export {
    interface-id('vt.semiring.prp1')
}
# END GENERATED ABI INTERFACE IDS

class Edge is export {
    has UInt:D $.label is required;
    has UInt:D $.node is required;
}

sub memcpy(Pointer, Pointer, size_t --> Pointer) is native { * }

sub copy-cstruct(::T, Pointer:D $source --> T:D) {
    my $copy = T.new;
    memcpy(nativecast(Pointer, $copy), $source, nativesizeof($copy));
    $copy
}

sub check-status(Int:D $code, Str:D $operation, Bool :$allow-end = False,
    Bool :$allow-unsupported = False --> Status:D) is export {
    my $status = Status($code);
    return $status if $status == OK;
    return $status if $allow-end && $status == END;
    return $status if $allow-unsupported && $status == UNSUPPORTED;
    X::Vinary::Tree::Interop.new(:$status, :$operation).throw;
}

sub require-pointer(Pointer $pointer, Str:D $operation --> Pointer:D) {
    X::Vinary::Tree::Interop.new(
        status => UNSUPPORTED,
        :$operation,
    ).throw unless $pointer;
    $pointer
}

class Resource is export {
    has RawResource:D $!raw is required;
    has ResourceVTable $!table;
    has Bool $!closed = False;
    has @!anchors;

    submethod BUILD(RawResource:D :$raw!, :@anchors = ()) {
        my $table = copy-cstruct(ResourceVTable, $raw.vtable);
        X::Vinary::Tree::Interop.new(
            status => UNSUPPORTED,
            operation => 'abi-version',
        ).throw unless $table.abi-version == ABI-VERSION;
        $!raw := $raw;
        $!table := $table;
        @!anchors = @anchors;
    }

    method raw(--> RawResource:D) {
        X::Vinary::Tree::Interop.new(
            status => CLOSED,
            operation => 'resource',
        ).throw if $!closed;
        $!raw
    }

    method retain(--> Resource:D) {
        my $raw = self.raw;
        my $table = $!table;
        my &retain = abi-cast-resource-retain(
            require-pointer($table.retain, 'retain'));
        retain($raw.context);
        Resource.new(:$raw, anchors => @!anchors)
    }

    method query-interface(InterfaceId:D $id, UInt:D $minimum-version = 1
        --> Pointer) {
        my $raw = self.raw;
        my $table = $!table;
        my &query = abi-cast-resource-query-interface(
            require-pointer($table.query-interface, 'query-interface'),
        );
        my Pointer $output .= new;
        my $status = query($raw.context, $id, $minimum-version, $output);
        check-status($status, 'query-interface', :allow-unsupported);
        return Pointer unless Status($status) == OK;
        X::Vinary::Tree::Interop.new(
            status => NULL-POINTER,
            operation => 'query-interface',
        ).throw unless $output;
        $output
    }

    method close(--> Nil) {
        return if $!closed;
        my $raw = $!raw;
        $!closed = True;
        my $table = $!table;
        if $table.release {
            my &release = abi-cast-resource-release($table.release);
            release($raw.context);
        }
        @!anchors = ();
    }

    method opened(--> Bool:D) { !$!closed }

    submethod DESTROY { self.close }
}

sub adopt-resource(RawResource:D $raw, :@anchors = () --> Resource:D) is export {
    Resource.new(:$raw, :@anchors)
}

sub borrow-resource(RawResource:D $raw, :@anchors = () --> Resource:D) is export {
    my $table = copy-cstruct(ResourceVTable, $raw.vtable);
    X::Vinary::Tree::Interop.new(
        status => UNSUPPORTED,
        operation => 'abi-version',
    ).throw unless $table.abi-version == ABI-VERSION;
    my &retain = abi-cast-resource-retain(
        require-pointer($table.retain, 'retain'));
    my &release = abi-cast-resource-release(
        require-pointer($table.release, 'release'));
    retain($raw.context);
    my $owned;
    try {
        $owned = Resource.new(:$raw, :@anchors);
        CATCH {
            default {
                release($raw.context);
                .rethrow;
            }
        }
    }
    $owned
}

sub with-resource(Resource:D $resource, &operation --> Mu) is export {
    my $owned = $resource.retain;
    LEAVE $owned.close;
    operation($owned)
}

class Dictionary does Associative is export {
    has Resource:D $.resource is required;
    has Pointer $!table-pointer;
    has DictionaryVTable $!table-copy;
    has Bool $!closed = False;

    submethod BUILD(Resource:D :$resource!, Bool :$take = False) {
        $!resource = $take ?? $resource !! $resource.retain;
        CATCH {
            default {
                $!resource.close if $!resource.defined;
                .rethrow;
            }
        }
        $!table-pointer = $!resource.query-interface(
            dictionary-interface-id(),
            DICTIONARY-INTERFACE-VERSION,
        );
        X::Vinary::Tree::Interop.new(
            status => UNSUPPORTED,
            operation => 'dictionary',
        ).throw unless $!table-pointer;
        $!table-copy := copy-cstruct(DictionaryVTable, $!table-pointer);
    }

    method !table(--> DictionaryVTable:D) {
        X::Vinary::Tree::Interop.new(
            status => CLOSED,
            operation => 'dictionary',
        ).throw if $!closed;
        $!table-copy
    }

    method unit-domain(--> UnitDomain:D) { UnitDomain(self!table.unit-domain) }
    method value-domain(--> ValueDomain:D) { ValueDomain(self!table.value-domain) }
    method flags(--> UInt:D) { self!table.flags }

    method snapshot(--> Dictionary:D) {
        my $table = self!table;
        my &call = abi-cast-dictionary-snapshot(
            require-pointer($table.snapshot, 'dictionary-snapshot'));
        my $raw = RawResource.new;
        check-status(call($!resource.raw.context, $raw),
            'dictionary-snapshot');
        Dictionary.new(resource => adopt-resource($raw), take => True)
    }

    method root(--> UInt:D) {
        my $table = self!table;
        my &call = abi-cast-dictionary-root(
            require-pointer($table.root, 'dictionary-root'));
        my uint64 $output = 0;
        check-status(call($!resource.raw.context, $output), 'dictionary-root');
        $output
    }

    method known-length(--> Int) {
        my $table = self!table;
        my &call = abi-cast-dictionary-len(
            require-pointer($table.len, 'dictionary-len'));
        my size_t $output = 0;
        my uint8 $known = 0;
        check-status(call($!resource.raw.context, $output, $known), 'dictionary-len');
        $known ?? $output.Int !! Int
    }

    method is-final(UInt:D $node --> Bool:D) {
        my $table = self!table;
        my &call = abi-cast-dictionary-node-is-final(
            require-pointer($table.node-is-final, 'dictionary-is-final'));
        my uint8 $output = 0;
        check-status(call($!resource.raw.context, $node, $output),
            'dictionary-is-final');
        so $output
    }

    method value(UInt:D $node --> UInt) {
        X::Vinary::Tree::Interop.new(
            status => UNSUPPORTED,
            operation => 'dictionary-value',
        ).throw unless self.value-domain == OPTIONAL-U64;
        my $table = self!table;
        my &call = abi-cast-dictionary-node-value-u64(
            require-pointer($table.node-value-u64, 'dictionary-value'));
        my $output = OptionalU64.new;
        check-status(call($!resource.raw.context, $node, $output),
            'dictionary-value');
        $output.has-value ?? $output.value !! UInt
    }

    method transition(UInt:D $node, UInt:D $label --> UInt) {
        my $table = self!table;
        my &call = abi-cast-dictionary-node-transition(
            require-pointer($table.node-transition, 'dictionary-transition'),
        );
        my uint64 $child = 0;
        my uint8 $found = 0;
        check-status(call($!resource.raw.context, $node, $label, $child, $found),
            'dictionary-transition');
        $found ?? $child !! UInt
    }

    method !key-units(Mu:D $key --> List:D) {
        given self.unit-domain {
            when BYTE {
                return $key.list if $key ~~ Blob;
                return $key.encode('utf8').list if $key ~~ Str;
            }
            when UNICODE-SCALAR {
                return $key.ords.List if $key ~~ Str;
                return $key.list if $key ~~ Positional;
            }
            when U64 {
                return $key.list if $key ~~ Positional;
            }
        }
        die "key is incompatible with {self.unit-domain}";
    }

    method !terminal(Mu:D $key --> UInt) {
        my UInt $node = self.root;
        for self!key-units($key) -> $unit {
            my $child = self.transition($node, $unit.UInt);
            return UInt unless $child.defined;
            $node = $child;
        }
        self.is-final($node) ?? $node !! UInt
    }

    method EXISTS-KEY(Mu:D $key --> Bool:D) {
        self!terminal($key).defined
    }

    method AT-KEY(Mu:D $key --> Mu) {
        my $node = self!terminal($key);
        return Nil unless $node.defined;
        given self.value-domain {
            when UNIT { True }
            when OPTIONAL-U64 { self.value($node) }
            default {
                X::Vinary::Tree::Interop.new(
                    status => UNSUPPORTED,
                    operation => 'dictionary-at-key',
                ).throw;
            }
        }
    }

    method elems(--> Int:D) {
        my $length = self.known-length;
        die 'dictionary length is not known' unless $length.defined;
        $length
    }

    method edges(UInt:D $node, UInt:D :$batch-size = RECOMMENDED-EDGE-BATCH
        --> Array:D) {
        die 'batch-size must be positive' unless $batch-size > 0;
        my $table = self!table;
        my &call = abi-cast-dictionary-node-edges(
            require-pointer($table.node-edges, 'dictionary-edges'),
        );
        my $storage = buf8.allocate($batch-size * nativesizeof(DictionaryEdge));
        my $page = nativecast(Pointer, $storage);
        my @result;
        my size_t $start = 0;
        my size_t $total = $batch-size;
        while $start < $total {
            my size_t $written = 0;
            my size_t $reported-total = 0;
            check-status(
                call($!resource.raw.context, $node, $start, $page, $batch-size,
                    $written, $reported-total),
                'dictionary-edges',
            );
            X::Vinary::Tree::Interop.new(
                status => PROVIDER-ERROR,
                operation => 'dictionary-edges',
            ).throw if $written > $batch-size ||
                ($written == 0 && $start < $reported-total);
            for ^$written -> $index {
                my $raw-edge = DictionaryEdge.new;
                my $slice = $storage.subbuf(
                    $index * nativesizeof(DictionaryEdge),
                    nativesizeof(DictionaryEdge),
                );
                memcpy(nativecast(Pointer, $raw-edge),
                    nativecast(Pointer, $slice),
                    nativesizeof(DictionaryEdge));
                @result.push(Edge.new(
                    label => $raw-edge.label,
                    node => $raw-edge.node,
                ));
            }
            $start += $written;
            $total = $reported-total;
        }
        @result
    }

    method close(--> Nil) {
        return if $!closed;
        $!closed = True;
        $!resource.close;
    }

    method opened(--> Bool:D) { !$!closed }
    submethod DESTROY { self.close }
}

sub dictionary(Resource:D $resource, Bool :$take = False --> Dictionary:D)
    is export {
    Dictionary.new(:$resource, :$take)
}

class Entry is export {
    has Array:D $.units is required;
    has UInt $.value;
}

class DictionaryEntriesIterator does Iterator {
    has Mu:D $.cursor is required;
    has @!buffer;
    has Bool $!finished = False;

    method pull-one() {
        while !@!buffer {
            return IterationEnd if $!finished;
            my $batch = $!cursor.next-batch;
            unless $batch.defined {
                $!finished = True;
                $!cursor.close;
                return IterationEnd;
            }
            @!buffer = $batch.entries;
            $batch.release;
        }
        @!buffer.shift
    }

    submethod DESTROY { try $!cursor.close unless $!finished }
}

class EntryBatch is export {
    has Mu:D $.cursor is required;
    has DictionaryEntryBatchView:D $.view is required;
    has Bool $.borrowed = False;
    has Bool $!released = False;

    method raw-view(--> DictionaryEntryBatchView:D) {
        X::Vinary::Tree::Interop.new(
            status => CLOSED,
            operation => 'dictionary-entry-batch',
        ).throw if $!released;
        $!view
    }

    method entries(--> Array:D) {
        my $view = self.raw-view;
        my @result;
        for ^$view.entry-count -> $index {
            my $descriptor = DictionaryEntryDescriptor.new;
            memcpy(
                nativecast(Pointer, $descriptor),
                Pointer.new($view.entries +
                    $index * nativesizeof(DictionaryEntryDescriptor)),
                nativesizeof(DictionaryEntryDescriptor),
            );
            my $unit-width = $.cursor.unit-domain == BYTE ?? 1 !!
                $.cursor.unit-domain == UNICODE-SCALAR ?? 4 !! 8;
            my $unit-storage = buf8.allocate($descriptor.unit-len * $unit-width);
            if $descriptor.unit-len {
                memcpy(nativecast(Pointer, $unit-storage),
                    Pointer.new($view.units + $descriptor.unit-offset * $unit-width),
                    $descriptor.unit-len * $unit-width);
            }
            my @units;
            if $.cursor.unit-domain == BYTE {
                @units = $unit-storage.list;
            } else {
                my $native-type = $.cursor.unit-domain == UNICODE-SCALAR
                    ?? uint32
                    !! uint64;
                my $array = $native-type === uint32
                    ?? CArray[uint32].allocate($descriptor.unit-len)
                    !! CArray[uint64].allocate($descriptor.unit-len);
                memcpy(nativecast(Pointer, $array), nativecast(Pointer, $unit-storage),
                    $descriptor.unit-len * $unit-width) if $descriptor.unit-len;
                @units = (^$descriptor.unit-len).map({ $array[$_] }).Array;
            }
            my UInt $value;
            if $descriptor.value-len == 1 {
                my $storage = CArray[uint64].allocate(1);
                memcpy(nativecast(Pointer, $storage),
                    Pointer.new($view.values +
                        $descriptor.value-offset * nativesizeof(uint64)),
                    nativesizeof(uint64));
                $value = $storage[0];
            } elsif $descriptor.value-len != 0 {
                X::Vinary::Tree::Interop.new(
                    status => PROVIDER-ERROR,
                    operation => 'dictionary-entry-value',
                ).throw;
            }
            @result.push(Entry.new(units => @units.Array, :$value));
        }
        @result
    }

    method release(--> Nil) {
        return if $!released || $!borrowed;
        $!released = True;
        $!cursor.release-batch($!view.generation);
    }

    method opened(--> Bool:D) { !$!released }
    submethod DESTROY { try self.release }
}

class DictionaryEntries does Iterable is export {
    has Resource:D $!resource is required;
    has RawDictionaryEntriesCursor:D $!raw is required;
    has DictionaryEntriesVTable $!table;
    has DictionaryEntriesInfo:D $.info is required;
    has Bool $!batch-active = False;
    has UInt $!active-generation = 0;
    has Bool $!closed = False;

    submethod BUILD(Dictionary:D :$dictionary!) {
        my $table-pointer = $dictionary.resource.query-interface(
            dictionary-entries-interface-id(),
            DICTIONARY-ENTRIES-INTERFACE-VERSION,
        );
        X::Vinary::Tree::Interop.new(
            status => UNSUPPORTED,
            operation => 'dictionary-entries',
        ).throw unless $table-pointer;
        $!table := copy-cstruct(DictionaryEntriesVTable, $table-pointer);
        my &open = abi-cast-dictionary-entries-open(
            require-pointer($!table.open, 'dictionary-entries-open'),
        );
        my $raw = RawDictionaryEntriesCursor.new;
        my $info = DictionaryEntriesInfo.new;
        check-status(open($dictionary.resource.raw.context, $raw, $info),
            'dictionary-entries-open');
        X::Vinary::Tree::Interop.new(
            status => NULL-POINTER,
            operation => 'dictionary-entries-open',
        ).throw unless $raw.context;
        $!resource = $dictionary.resource.retain;
        $!raw := $raw;
        $!info := $info;
    }

    method unit-domain(--> UnitDomain:D) { UnitDomain($!info.unit-domain) }
    method value-domain(--> ValueDomain:D) { ValueDomain($!info.value-domain) }
    method order(--> EntryOrder:D) { EntryOrder($!info.order) }
    method known-length(--> Int) {
        $!info.flags +& ENTRIES-INFO-FLAG-EXACT-LEN
            ?? $!info.exact-len.Int
            !! Int
    }
    method snapshot-identity(--> SnapshotIdentity) {
        $!info.flags +& ENTRIES-INFO-FLAG-SNAPSHOT-IDENTITY
            ?? SnapshotIdentity.new(
                producer => $!info.identity-producer,
                revision => $!info.identity-revision,
            )
            !! SnapshotIdentity
    }

    method next-batch(BatchLimits:D $limits = BatchLimits.new --> Mu) {
        X::Vinary::Tree::Interop.new(
            status => CLOSED,
            operation => 'dictionary-entries-next-batch',
        ).throw if $!closed;
        X::Vinary::Tree::Interop.new(
            status => BATCH-IN-USE,
            operation => 'dictionary-entries-next-batch',
        ).throw if $!batch-active;
        my &next = abi-cast-dictionary-entries-next-batch(
            require-pointer($!table.next-batch, 'dictionary-entries-next-batch'),
        );
        my $view = DictionaryEntryBatchView.new;
        my $status = next($!raw, $limits, $view);
        check-status($status, 'dictionary-entries-next-batch', :allow-end);
        return Nil if Status($status) == END;
        $!batch-active = True;
        $!active-generation = $view.generation;
        EntryBatch.new(cursor => self, :$view)
    }

    method release-batch(UInt:D $generation --> Nil) {
        X::Vinary::Tree::Interop.new(
            status => CLOSED,
            operation => 'dictionary-entries-release-batch',
        ).throw if $!closed;
        die 'no dictionary-entry batch is active' unless $!batch-active;
        my &release = abi-cast-dictionary-entries-release-batch(
            require-pointer($!table.release-batch,
                'dictionary-entries-release-batch'),
        );
        check-status(release($!raw, $generation),
            'dictionary-entries-release-batch');
        $!batch-active = False;
        $!active-generation = 0;
    }

    method cancel(--> Nil) {
        my &cancel = abi-cast-dictionary-entries-cancel(
            require-pointer($!table.cancel, 'dictionary-entries-cancel'));
        check-status(cancel($!raw), 'dictionary-entries-cancel');
    }

    method reduce(&operation, BatchLimits:D $limits = BatchLimits.new
        --> Int:D) {
        X::Vinary::Tree::Interop.new(
            status => CLOSED,
            operation => 'dictionary-entries-reduce',
        ).throw if $!closed;
        X::Vinary::Tree::Interop.new(
            status => BATCH-IN-USE,
            operation => 'dictionary-entries-reduce',
        ).throw if $!batch-active;
        my $failure;
        my &callback = -> Pointer $context, Pointer $view-pointer --> int32 {
            my int32 $status = PROVIDER-ERROR;
            try {
                my $view = copy-cstruct(DictionaryEntryBatchView, $view-pointer);
                operation(EntryBatch.new(
                    cursor => self,
                    :$view,
                    borrowed => True,
                ).entries);
                $status = OK;
                CATCH {
                    default {
                        $failure = $_;
                        $status = PROVIDER-ERROR;
                    }
                }
            }
            $status
        };
        my &reduce = abi-cast-dictionary-entries-reduce(
            require-pointer($!table.reduce, 'dictionary-entries-reduce'),
        );
        my size_t $count = 0;
        my $status = reduce($!raw, $limits, &callback, Pointer, $count);
        $failure.throw if $failure.defined;
        check-status($status, 'dictionary-entries-reduce');
        $count.Int
    }

    method close(--> Nil) {
        return if $!closed;
        if $!batch-active {
            try self.release-batch($!active-generation);
        }
        my &close = abi-cast-dictionary-entries-close(
            require-pointer($!table.close, 'dictionary-entries-close'));
        my $status = close($!raw);
        $!closed = True;
        $!resource.close;
        check-status($status, 'dictionary-entries-close');
    }

    method opened(--> Bool:D) { !$!closed }
    method iterator(--> Iterator:D) {
        DictionaryEntriesIterator.new(cursor => self)
    }
    method Seq(--> Seq:D) { Seq.new(self.iterator) }
    method list(--> List:D) { self.Seq.list }
    submethod DESTROY { try self.close }
}

sub entries(Dictionary:D $dictionary --> DictionaryEntries:D) is export {
    DictionaryEntries.new(:$dictionary)
}

sub with-batch(DictionaryEntries:D $cursor, &operation,
    BatchLimits:D $limits = BatchLimits.new --> Mu) is export {
    my $batch = $cursor.next-batch($limits);
    return Nil unless $batch.defined;
    LEAVE $batch.release;
    operation($batch)
}

class StateInfo is export {
    has Bool:D $.final is required;
    has Num:D $.final-weight is required;
}

class Arc is export {
    has UInt $.input;
    has UInt $.output;
    has UInt:D $.target is required;
    has Num:D $.weight is required;
}

class Wfst is export {
    has Resource:D $.resource is required;
    has WfstVTable $!table;
    has Bool $!closed = False;

    submethod BUILD(Resource:D :$resource!, Bool :$take = False) {
        $!resource = $take ?? $resource !! $resource.retain;
        CATCH {
            default {
                $!resource.close if $!resource.defined;
                .rethrow;
            }
        }
        my $pointer = $!resource.query-interface(
            wfst-interface-id(), WFST-INTERFACE-VERSION);
        X::Vinary::Tree::Interop.new(
            status => UNSUPPORTED,
            operation => 'wfst',
        ).throw unless $pointer;
        $!table := copy-cstruct(WfstVTable, $pointer);
    }

    method !open(--> Nil) {
        X::Vinary::Tree::Interop.new(
            status => CLOSED,
            operation => 'wfst',
        ).throw if $!closed;
    }

    method unit-domain(--> UnitDomain:D) {
        self!open;
        UnitDomain($!table.unit-domain)
    }
    method weight-domain(--> WeightDomain:D) {
        self!open;
        WeightDomain($!table.weight-domain)
    }
    method flags(--> UInt:D) {
        self!open;
        $!table.flags
    }

    method snapshot(--> Wfst:D) {
        self!open;
        my &call = abi-cast-wfst-snapshot(
            require-pointer($!table.snapshot, 'wfst-snapshot'));
        my $raw = RawResource.new;
        check-status(call($!resource.raw.context, $raw), 'wfst-snapshot');
        Wfst.new(resource => adopt-resource($raw), take => True)
    }

    method start(--> UInt:D) {
        self!open;
        my &call = abi-cast-wfst-start(
            require-pointer($!table.start, 'wfst-start'));
        my uint64 $state = 0;
        check-status(call($!resource.raw.context, $state), 'wfst-start');
        $state
    }

    method state-count(--> Int) {
        self!open;
        my &call = abi-cast-wfst-num-states(
            require-pointer($!table.num-states, 'wfst-num-states'));
        my size_t $count = 0;
        my uint8 $known = 0;
        check-status(call($!resource.raw.context, $count, $known),
            'wfst-num-states');
        $known ?? $count.Int !! Int
    }

    method state-info(UInt:D $state --> StateInfo) {
        self!open;
        my &call = abi-cast-wfst-state-info(
            require-pointer($!table.state-info, 'wfst-state-info'),
        );
        my uint8 $valid = 0;
        my uint8 $final = 0;
        my num64 $weight = 0e0;
        check-status(call($!resource.raw.context, $state, $valid, $final, $weight),
            'wfst-state-info');
        $valid ?? StateInfo.new(final => so($final), final-weight => $weight)
            !! StateInfo
    }

    method arcs(UInt:D $state, UInt:D :$batch-size = RECOMMENDED-ARC-BATCH
        --> Array:D) {
        self!open;
        die 'batch-size must be positive' unless $batch-size > 0;
        my &call = abi-cast-wfst-state-arcs(
            require-pointer($!table.state-arcs, 'wfst-arcs'),
        );
        my $storage = buf8.allocate($batch-size * nativesizeof(WfstArc));
        my $page = nativecast(Pointer, $storage);
        my @result;
        my size_t $start = 0;
        my size_t $total = $batch-size;
        while $start < $total {
            my size_t $written = 0;
            my size_t $reported-total = 0;
            check-status(call($!resource.raw.context, $state, $start, $page,
                $batch-size, $written, $reported-total), 'wfst-arcs');
            X::Vinary::Tree::Interop.new(
                status => PROVIDER-ERROR,
                operation => 'wfst-arcs',
            ).throw if $written > $batch-size ||
                ($written == 0 && $start < $reported-total);
            for ^$written -> $index {
                my $raw = WfstArc.new;
                my $slice = $storage.subbuf($index * nativesizeof(WfstArc),
                    nativesizeof(WfstArc));
                memcpy(nativecast(Pointer, $raw), nativecast(Pointer, $slice),
                    nativesizeof(WfstArc));
                @result.push(Arc.new(
                    input => $raw.has-input ?? $raw.input-label !! UInt,
                    output => $raw.has-output ?? $raw.output-label !! UInt,
                    target => $raw.target-state,
                    weight => $raw.weight,
                ));
            }
            $start += $written;
            $total = $reported-total;
        }
        @result
    }

    method close(--> Nil) {
        return if $!closed;
        $!closed = True;
        $!resource.close;
    }

    method opened(--> Bool:D) { !$!closed }
    submethod DESTROY { try self.close }
}

sub wfst(Resource:D $resource, Bool :$take = False --> Wfst:D) is export {
    Wfst.new(:$resource, :$take)
}

class LatticeValue is export {
    has Resource:D $.resource is required;
    has LatticeVTable $!table;
    has Bool $!closed = False;

    submethod BUILD(Resource:D :$resource!, Bool :$take = False) {
        $!resource = $take ?? $resource !! $resource.retain;
        CATCH {
            default {
                $!resource.close if $!resource.defined;
                .rethrow;
            }
        }
        my $pointer = $!resource.query-interface(
            lattice-interface-id(), LATTICE-INTERFACE-VERSION);
        X::Vinary::Tree::Interop.new(
            status => UNSUPPORTED,
            operation => 'lattice-value',
        ).throw unless $pointer;
        $!table := copy-cstruct(LatticeVTable, $pointer);
        X::Vinary::Tree::Interop.new(
            status => UNSUPPORTED,
            operation => 'lattice-version',
        ).throw unless $!table.interface-version >= LATTICE-INTERFACE-VERSION;
        X::Vinary::Tree::Interop.new(
            status => PROVIDER-ERROR,
            operation => 'lattice-reserved',
        ).throw unless $!table.reserved == 0;
    }

    method !open(--> Nil) {
        X::Vinary::Tree::Interop.new(
            status => CLOSED,
            operation => 'lattice-value',
        ).throw if $!closed;
    }

    method domain-id(--> InterfaceId:D) {
        self!open;
        $!table.domain-id
    }

    method flags(--> UInt:D) {
        self!open;
        $!table.flags
    }

    method !same-domain(LatticeValue:D $other, Str:D $operation --> Nil) {
        X::Vinary::Tree::Interop.new(
            status => INVALID-ARGUMENT,
            :$operation,
        ).throw unless self.domain-id.bytes eqv $other.domain-id.bytes;
    }

    method !binary(LatticeValue:D $other, Str:D $operation --> LatticeValue:D) {
        self!same-domain($other, $operation);
        my $function = $operation eq 'lattice-join'
            ?? $!table.join
            !! $!table.meet;
        my $required = require-pointer($function, $operation);
        my &call = $operation eq 'lattice-join'
            ?? abi-cast-lattice-join($required)
            !! abi-cast-lattice-meet($required);
        my $output = RawResource.new;
        check-status(call($!resource.raw.context, $other.resource.raw, $output),
            $operation);
        lattice-value(adopt-resource($output), :take)
    }

    method join(LatticeValue:D $other --> LatticeValue:D) {
        self!binary($other, 'lattice-join')
    }

    method meet(LatticeValue:D $other --> LatticeValue:D) {
        self!binary($other, 'lattice-meet')
    }

    method equivalent(LatticeValue:D $other --> Bool:D) {
        self!same-domain($other, 'lattice-equal');
        my &call = abi-cast-lattice-equal(
            require-pointer($!table.equal, 'lattice-equal'),
        );
        my uint8 $output = 0;
        check-status(call($!resource.raw.context, $other.resource.raw, $output),
            'lattice-equal');
        X::Vinary::Tree::Interop.new(
            status => PROVIDER-ERROR,
            operation => 'lattice-equal',
        ).throw unless $output <= 1;
        so $output
    }

    method !bytes(Pointer $function, Str:D $operation --> Blob) {
        return Blob unless $function;
        my &call = $operation eq 'lattice-stable-bytes'
            ?? abi-cast-lattice-stable-bytes($function)
            !! abi-cast-lattice-diagnostic($function);
        my size_t $written = 0;
        my size_t $required = 0;
        check-status(call($!resource.raw.context, Pointer, 0,
            $written, $required), $operation);
        X::Vinary::Tree::Interop.new(
            status => PROVIDER-ERROR,
            :$operation,
        ).throw unless $written == 0;
        my $storage = buf8.allocate($required);
        my size_t $second-written = 0;
        my size_t $second-required = 0;
        my $pointer = $required ?? nativecast(Pointer, $storage) !! Pointer;
        check-status(call($!resource.raw.context, $pointer, $required,
            $second-written, $second-required), $operation);
        X::Vinary::Tree::Interop.new(
            status => PROVIDER-ERROR,
            :$operation,
        ).throw unless $second-required == $required &&
            $second-written == $required;
        Blob.new($storage.list)
    }

    method stable-bytes(--> Blob:D) {
        X::Vinary::Tree::Interop.new(
            status => UNSUPPORTED,
            operation => 'lattice-stable-bytes',
        ).throw unless $!table.flags +& LATTICE-FLAG-STABLE-BYTES;
        my $bytes = self!bytes($!table.stable-bytes,
            'lattice-stable-bytes');
        X::Vinary::Tree::Interop.new(
            status => UNSUPPORTED,
            operation => 'lattice-stable-bytes',
        ).throw unless $bytes.defined;
        $bytes
    }

    method diagnostic(--> Str) {
        my $bytes = self!bytes($!table.diagnostic, 'lattice-diagnostic');
        $bytes.defined ?? $bytes.decode('utf8') !! Str
    }

    method !many(@others, Str:D $operation --> LatticeValue:D) {
        self!same-domain($_, $operation) for @others;
        return lattice-value($!resource.retain, :take) unless @others;
        my $function = $operation eq 'lattice-join-many'
            ?? $!table.join-many
            !! $!table.meet-many;
        unless $!table.flags +& LATTICE-FLAG-BATCH && $function {
            my $result = lattice-value($!resource.retain, :take);
            for @others -> $other {
                my $next = $operation eq 'lattice-join-many'
                    ?? $result.join($other)
                    !! $result.meet($other);
                $result.close;
                $result = $next;
            }
            return $result;
        }
        my $storage = buf8.allocate(@others.elems * nativesizeof(RawResource));
        for @others.kv -> $index, $other {
            my $raw = $other.resource.raw;
            memcpy(
                Pointer.new(nativecast(Pointer, $storage) +
                    $index * nativesizeof(RawResource)),
                nativecast(Pointer, $raw),
                nativesizeof(RawResource),
            );
        }
        my &call = $operation eq 'lattice-join-many'
            ?? abi-cast-lattice-join-many($function)
            !! abi-cast-lattice-meet-many($function);
        my $output = RawResource.new;
        check-status(call($!resource.raw.context, nativecast(Pointer, $storage),
            @others.elems, $output), $operation);
        lattice-value(adopt-resource($output), :take)
    }

    method join-many(*@others --> LatticeValue:D) {
        self!many(@others, 'lattice-join-many')
    }

    method meet-many(*@others --> LatticeValue:D) {
        self!many(@others, 'lattice-meet-many')
    }

    method close(--> Nil) {
        return if $!closed;
        $!closed = True;
        $!resource.close;
    }

    method opened(--> Bool:D) { !$!closed }
    submethod DESTROY { try self.close }
}

sub lattice-value(Resource:D $resource, Bool :$take = False --> LatticeValue:D)
    is export {
    LatticeValue.new(:$resource, :$take)
}

=begin pod

=NAME Vinary::Tree::Interop

=SUBTITLE Safe NativeCall collections, snapshots, streams, and WFSTs over the Vinary Tree resource ABI

=head1 SYNOPSIS

=begin code :lang<raku>
use Vinary::Tree::Interop;

sub print-dictionary(Resource:D $native-resource) {
    my $dictionary = dictionary($native-resource, :take);
    LEAVE $dictionary.close;

    say $dictionary{'café'} if $dictionary{'café'}:exists;

    my $cursor = entries($dictionary);
    LEAVE $cursor.close;
    for $cursor -> $entry {
        say $entry.units, ' => ', $entry.value;
    }
}
=end code

=head1 DESCRIPTION

C<Vinary::Tree::Interop> consumes the stable versioned C resource application
binary interface (ABI) shared by the Vinary Tree libraries. Native Rust code
implements the algorithms; this distribution supplies Raku ownership,
collections, bounded streams, exceptions, and scalar weighted finite-state
transducers (WFSTs).

=head1 OWNERSHIP

=head2 C<Resource>, C<adopt-resource>, C<borrow-resource>, C<with-resource>

C<adopt-resource> transfers one existing native reference into Raku without
retaining it. C<borrow-resource> retains provider-owned borrowed words before
wrapping them. C<Resource.retain> creates an independent reference.
C<Resource.close> releases exactly one reference and is idempotent. C<DESTROY>
is fallback leak protection; deterministic close is the supported normal path.

C<query-interface> returns a version-compatible vtable pointer or the C<Pointer>
type object when an optional interface is absent. The pointer is valid only while
the resource remains retained.

=head1 DICTIONARIES

=head2 C<Dictionary>, C<dictionary>

C<Dictionary> implements C<Associative>. Byte dictionaries accept C<Blob> or
UTF-8 C<Str> keys, Unicode-scalar dictionaries accept C<Str> or positional
scalar values, and vocabulary dictionaries accept positional unsigned 64-bit
tokens. C<:exists> distinguishes a missing key from a present optional value.

C<snapshot>, C<root>, C<is-final>, C<value>, C<transition>, and C<edges> expose
the versioned graph directly. Edge paging uses a caller-selected positive hard
limit and rejects stalled or over-capacity providers.

=head1 BOUNDED ENTRY STREAMS

=head2 C<DictionaryEntries>, C<EntryBatch>, C<BatchLimits>

C<entries> opens a finite lexicographic stream over a retained immutable
snapshot. C<DictionaryEntries> implements C<Iterable>. Its iterator copies each
bounded native page and releases the matching generation before yielding
language-owned C<Entry> values.

C<next-batch> exposes one explicit lease. C<with-batch> is preferred because it
releases the lease on normal return or exception. No pointer in C<raw-view> may
escape the callback.

=head2 C<DictionaryEntries.reduce>

The native provider drives bounded pages through one synchronous Raku callback.
The method returns the exact processed count. Raku exceptions are caught inside
the callback, translated to C<PROVIDER-ERROR>, and re-thrown only after native
control returns. The native call must originate on a Rakudo-owned thread.

=head1 WEIGHTED FINITE-STATE TRANSDUCERS

=head2 C<Wfst>, C<wfst>, C<StateInfo>, C<Arc>

C<Wfst> exposes the scalar WFST resource interface. C<start> returns the
snapshot-local start state, C<state-count> returns an exact count when known,
C<state-info> returns finality and final weight, and C<arcs> copies outgoing arcs
through bounded pages. Epsilon labels are represented by the C<UInt> type object.

=head1 RAW ABI TYPES

C<InterfaceId>, C<RawResource>, every C<*VTable>, graph node/edge/view types,
entry descriptor/view/info types, C<WfstArc>, and the compact
C<SemiringValue> token mirror the authoritative C header. The five semiring
vtable types keep base algebra, division, Kleene closure, numerical projections,
and declared laws independently negotiable. These raw layouts and all typed
vtable callback casts are generated from the packaged C header. Provider authors
may import the C<:abi> tag to use those casts without duplicating NativeCall
signatures. Fixed padding arrays are represented as individual native scalars to
preserve layout without giving Rakudo a separately owned CArray. Native tests
compare C<nativesizeof> for every raw type with C<sizeof> compiled from the C
header and execute the generated casts against an independent C fixture.

=head1 ERRORS AND SECURITY

C<X::Vinary::Tree::Interop> preserves the portable C<Status> and the operation
that observed it. Wrappers reject null required pointers, unsupported versions,
use after close, a second active batch, invalid value widths, stalled pagination,
and provider counts beyond the caller's capacity.

Arbitrary callbacks from native-created threads are not advertised. NativeCall
can create a function pointer, but that alone does not make an unknown native
thread a safe Rakudo execution thread. Synchronous reducers are supported because
the callback returns on the same Rakudo-owned thread that entered native code.

=head1 LICENSE

Apache License 2.0.

=end pod
