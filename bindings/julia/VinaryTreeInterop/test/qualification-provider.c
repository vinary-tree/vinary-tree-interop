#include "vinary_tree_interop.h"

#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* A deliberately small, independently owned provider for Julia's ABI tests.
 * Every returned graph/page pointer is owned by a retained resource or cursor. */
typedef struct QualificationDictionary {
    atomic_size_t references;
    VtUnitDomain unit_domain;
    VtValueDomain value_domain;
    VtWeightDomain weight_domain;
    bool semiring_active;
    uint64_t next_token;
    bool live_tokens[256];
    uint32_t hostile_mode;
    uint64_t revision;
    VtDictionaryVTable dictionary;
    VtDictionaryVisitVTable visit;
    VtDictionaryGraphVTable graph;
    VtSnapshotIdentityVTable identity;
    VtDictionaryEntriesVTable entries;
    VtWfstVTable wfst;
    VtSemiringVTable semiring;
    VtSemiringDivisionVTable division;
    VtSemiringStarVTable star;
    VtSemiringNumericVTable numeric;
    VtSemiringPropertiesVTable properties;
    VtDictionaryGraphNode nodes[3];
    VtDictionaryGraphEdge graph_edges[2];
} QualificationDictionary;

typedef struct QualificationCursor {
    QualificationDictionary *dictionary;
    size_t next_index;
    bool leased;
    bool cancelled;
    uint64_t generation;
    VtDictionaryEntry descriptor;
    union {
        uint8_t bytes[1];
        uint32_t scalars[1];
        uint64_t tokens[1];
    } units;
    uint64_t values[1];
} QualificationCursor;

static atomic_size_t live_dictionaries = 0;
static atomic_size_t live_cursors = 0;
static atomic_size_t live_semiring_tokens = 0;
static atomic_size_t visit_calls = 0;
static atomic_uint_fast64_t next_revision = 1;

size_t vt_qualification_live_dictionaries(void) {
    return atomic_load(&live_dictionaries);
}

size_t vt_qualification_live_cursors(void) {
    return atomic_load(&live_cursors);
}

size_t vt_qualification_visit_calls(void) {
    return atomic_load(&visit_calls);
}

size_t vt_qualification_live_semiring_tokens(void) {
    return atomic_load(&live_semiring_tokens);
}

static uint64_t label_at(const QualificationDictionary *dictionary, size_t index) {
    switch (dictionary->unit_domain) {
    case VT_UNIT_DOMAIN_BYTE: return index == 0 ? 0 : UINT8_MAX;
    case VT_UNIT_DOMAIN_UNICODE_SCALAR: return index == 0 ? 'a' : 0x03bb;
    case VT_UNIT_DOMAIN_U64: return index == 0 ? 0 : UINT64_MAX;
    default: return 0;
    }
}

static void qualification_retain(void *context) {
    QualificationDictionary *dictionary = context;
    atomic_fetch_add(&dictionary->references, 1);
}

static void qualification_release(void *context) {
    QualificationDictionary *dictionary = context;
    if (atomic_fetch_sub(&dictionary->references, 1) == 1) {
        atomic_fetch_sub(&live_dictionaries, 1);
        free(dictionary);
    }
}

static VtStatus qualification_query(void *context, const VtInterfaceId *id,
                                    uint32_t minimum_version, const void **out) {
    QualificationDictionary *dictionary = context;
    if (!id || !out) return VT_STATUS_NULL_POINTER;
    *out = NULL;
    if (minimum_version > 1) return VT_STATUS_UNSUPPORTED;
    if (memcmp(id, &VT_DICTIONARY_INTERFACE_ID, sizeof(*id)) == 0)
        *out = &dictionary->dictionary;
    else if (memcmp(id, &VT_DICTIONARY_VISIT_INTERFACE_ID, sizeof(*id)) == 0)
        *out = &dictionary->visit;
    else if (memcmp(id, &VT_DICTIONARY_GRAPH_INTERFACE_ID, sizeof(*id)) == 0)
        *out = &dictionary->graph;
    else if (memcmp(id, &VT_SNAPSHOT_IDENTITY_INTERFACE_ID, sizeof(*id)) == 0)
        *out = &dictionary->identity;
    else if (memcmp(id, &VT_DICTIONARY_ENTRIES_INTERFACE_ID, sizeof(*id)) == 0)
        *out = &dictionary->entries;
    else if (dictionary->weight_domain != 0 &&
             memcmp(id, &VT_WFST_INTERFACE_ID, sizeof(*id)) == 0)
        *out = &dictionary->wfst;
    else if (dictionary->semiring_active &&
             memcmp(id, &VT_SEMIRING_INTERFACE_ID, sizeof(*id)) == 0)
        *out = &dictionary->semiring;
    else if (dictionary->semiring_active &&
             memcmp(id, &VT_SEMIRING_DIVISION_INTERFACE_ID, sizeof(*id)) == 0)
        *out = &dictionary->division;
    else if (dictionary->semiring_active &&
             memcmp(id, &VT_SEMIRING_STAR_INTERFACE_ID, sizeof(*id)) == 0)
        *out = &dictionary->star;
    else if (dictionary->semiring_active &&
             memcmp(id, &VT_SEMIRING_NUMERIC_INTERFACE_ID, sizeof(*id)) == 0)
        *out = &dictionary->numeric;
    else if (dictionary->semiring_active &&
             memcmp(id, &VT_SEMIRING_PROPERTIES_INTERFACE_ID, sizeof(*id)) == 0)
        *out = &dictionary->properties;
    return *out ? VT_STATUS_OK : VT_STATUS_UNSUPPORTED;
}

static const VtResourceVTable qualification_resource_vtable = {
    .struct_size = sizeof(VtResourceVTable), .abi_version = VT_ABI_VERSION,
    .retain = qualification_retain, .release = qualification_release,
    .query_interface = qualification_query,
};

static VtResource qualification_resource(QualificationDictionary *dictionary) {
    VtResource resource = {dictionary, &qualification_resource_vtable};
    return resource;
}

static VtStatus qualification_snapshot(void *context, VtResource *out) {
    if (!out) return VT_STATUS_NULL_POINTER;
    qualification_retain(context);
    *out = qualification_resource(context);
    return VT_STATUS_OK;
}

static VtStatus qualification_root(void *context, uint64_t *out) {
    (void)context;
    if (!out) return VT_STATUS_NULL_POINTER;
    *out = 0;
    return VT_STATUS_OK;
}

static VtStatus qualification_len(void *context, size_t *out,
                                  uint8_t *known) {
    (void)context;
    if (!out || !known) return VT_STATUS_NULL_POINTER;
    *out = 2;
    *known = 1;
    return VT_STATUS_OK;
}

static VtStatus qualification_final(void *context, uint64_t node,
                                    uint8_t *out) {
    (void)context;
    if (!out) return VT_STATUS_NULL_POINTER;
    if (node > 2) return VT_STATUS_INVALID_ARGUMENT;
    *out = node != 0;
    return VT_STATUS_OK;
}

static VtStatus qualification_value(void *context, uint64_t node,
                                    VtOptionalU64 *out) {
    QualificationDictionary *dictionary = context;
    if (!out) return VT_STATUS_NULL_POINTER;
    if (node > 2) return VT_STATUS_INVALID_ARGUMENT;
    if (dictionary->value_domain != VT_VALUE_DOMAIN_OPTIONAL_U64)
        return VT_STATUS_UNSUPPORTED;
    *out = (VtOptionalU64){.value = 0, .has_value = node == 1};
    return VT_STATUS_OK;
}

static VtStatus qualification_transition(void *context, uint64_t node,
                                         uint64_t label, uint64_t *child,
                                         uint8_t *found) {
    QualificationDictionary *dictionary = context;
    if (!child || !found) return VT_STATUS_NULL_POINTER;
    if (node > 2) return VT_STATUS_INVALID_ARGUMENT;
    *found = 0;
    *child = 0;
    if (node == 0) {
        for (size_t index = 0; index < 2; ++index) {
            if (label == label_at(dictionary, index)) {
                *child = index + 1;
                *found = 1;
                break;
            }
        }
    }
    return VT_STATUS_OK;
}

static VtStatus qualification_edges(void *context, uint64_t node,
                                    size_t start, VtDictionaryEdge *out,
                                    size_t capacity, size_t *written,
                                    size_t *total) {
    QualificationDictionary *dictionary = context;
    if (!written || !total) return VT_STATUS_NULL_POINTER;
    if (node > 2) return VT_STATUS_INVALID_ARGUMENT;
    *total = node == 0 ? 2 : 0;
    *written = start >= *total ? 0 : (*total - start < capacity ? *total - start : capacity);
    if (*written && !out) return VT_STATUS_NULL_POINTER;
    for (size_t index = 0; index < *written; ++index)
        out[index] = (VtDictionaryEdge){label_at(dictionary, start + index), start + index + 1};
    if (dictionary->hostile_mode == 5 && capacity) *written = capacity + 1;
    return VT_STATUS_OK;
}

static VtStatus qualification_visit(void *context, uint64_t node,
                                    size_t start, uint8_t *final,
                                    VtDictionaryEdge *out, size_t capacity,
                                    size_t *written, size_t *total) {
    atomic_fetch_add(&visit_calls, 1);
    VtStatus status = qualification_final(context, node, final);
    if (status != VT_STATUS_OK) return status;
    return qualification_edges(context, node, start, out, capacity, written, total);
}

static VtStatus qualification_graph(void *context,
                                    VtDictionaryGraphView *out) {
    QualificationDictionary *dictionary = context;
    if (!out) return VT_STATUS_NULL_POINTER;
    *out = (VtDictionaryGraphView){
        .nodes = dictionary->hostile_mode == 1 ? NULL : dictionary->nodes,
        .node_count = 3, .edges = dictionary->graph_edges,
        .edge_count = 2, .root = dictionary->hostile_mode == 6 ? 3 : 0,
    };
    return VT_STATUS_OK;
}

static VtStatus qualification_identity(void *context,
                                       VtSnapshotIdentity *out) {
    QualificationDictionary *dictionary = context;
    if (!out) return VT_STATUS_NULL_POINTER;
    *out = (VtSnapshotIdentity){0x5155414c494659ULL, dictionary->revision};
    return VT_STATUS_OK;
}

static VtStatus qualification_wfst_start(void *context, uint64_t *out) {
    (void)context;
    if (!out) return VT_STATUS_NULL_POINTER;
    *out = 0;
    return VT_STATUS_OK;
}

static VtStatus qualification_wfst_count(void *context, size_t *out,
                                          uint8_t *known) {
    (void)context;
    if (!out || !known) return VT_STATUS_NULL_POINTER;
    *out = 2;
    *known = 1;
    return VT_STATUS_OK;
}

static VtStatus qualification_wfst_info(void *context, uint64_t state,
                                         uint8_t *valid, uint8_t *final,
                                         double *weight) {
    (void)context;
    if (!valid || !final || !weight) return VT_STATUS_NULL_POINTER;
    *valid = state < 2;
    *final = state == 1;
    *weight = state == 1 ? 0.75 : 0.0;
    return VT_STATUS_OK;
}

static VtStatus qualification_wfst_arcs(void *context, uint64_t state,
                                         size_t start, VtWfstArc *out,
                                         size_t capacity, size_t *written,
                                         size_t *total) {
    QualificationDictionary *dictionary = context;
    if (!written || !total) return VT_STATUS_NULL_POINTER;
    if (state >= 2) return VT_STATUS_INVALID_ARGUMENT;
    *total = state == 0 ? 2 : 0;
    *written = start >= *total ? 0 : (*total - start < capacity ? *total - start : capacity);
    if (*written && !out) return VT_STATUS_NULL_POINTER;
    for (size_t index = 0; index < *written; ++index) {
        const size_t position = start + index;
        out[index] = position == 0 ? (VtWfstArc){
            .input_label = label_at(dictionary, 0),
            .output_label = label_at(dictionary, 1), .target_state = 1,
            .weight = 1.25, .has_input = 1, .has_output = 1,
        } : (VtWfstArc){.target_state = 1, .weight = 2.5};
    }
    if (dictionary->hostile_mode == 7 && capacity) *written = capacity + 1;
    return VT_STATUS_OK;
}

static VtStatus qualification_entries_next(VtDictionaryEntriesCursor *raw,
                                            const VtDictionaryEntryBatchLimits *limits,
                                            VtDictionaryEntryBatchView *out);
static VtStatus qualification_entries_release(VtDictionaryEntriesCursor *raw,
                                               uint64_t generation);
static VtStatus qualification_entries_reduce(VtDictionaryEntriesCursor *raw,
                                              const VtDictionaryEntryBatchLimits *limits,
                                              VtDictionaryEntryReducer reducer,
                                              void *reducer_context,
                                              size_t *out_count);
static VtStatus qualification_entries_cancel(VtDictionaryEntriesCursor *raw);
static VtStatus qualification_entries_close(VtDictionaryEntriesCursor *raw);

static VtStatus qualification_entries_open(void *context,
                                           VtDictionaryEntriesCursor *out,
                                           VtDictionaryEntriesInfo *info) {
    QualificationDictionary *dictionary = context;
    if (!out || !info) return VT_STATUS_NULL_POINTER;
    QualificationCursor *cursor = calloc(1, sizeof(*cursor));
    if (!cursor) return VT_STATUS_LIMIT_EXCEEDED;
    qualification_retain(dictionary);
    cursor->dictionary = dictionary;
    atomic_fetch_add(&live_cursors, 1);
    *out = (VtDictionaryEntriesCursor){cursor, &dictionary->entries};
    *info = (VtDictionaryEntriesInfo){
        .unit_domain = dictionary->hostile_mode == 4 ? 99 : dictionary->unit_domain,
        .value_domain = dictionary->value_domain,
        .order = VT_DICTIONARY_ENTRY_ORDER_LEXICOGRAPHIC,
        .flags = VT_DICTIONARY_ENTRIES_INFO_FLAG_EXACT_LEN |
                 VT_DICTIONARY_ENTRIES_INFO_FLAG_SNAPSHOT_IDENTITY,
        .exact_len = 2,
        .identity = {0x5155414c494659ULL, dictionary->revision},
    };
    return VT_STATUS_OK;
}

static VtStatus qualification_entries_next(VtDictionaryEntriesCursor *raw,
                                            const VtDictionaryEntryBatchLimits *limits,
                                            VtDictionaryEntryBatchView *out) {
    if (!raw || !raw->context || !limits || !out) return VT_STATUS_NULL_POINTER;
    QualificationCursor *cursor = raw->context;
    if (cursor->leased) return VT_STATUS_BATCH_IN_USE;
    if (limits->max_entries == 0) return VT_STATUS_INVALID_ARGUMENT;
    if (cursor->cancelled || cursor->next_index == 2) return VT_STATUS_END;
    if (limits->max_units < 1 ||
        (cursor->dictionary->value_domain == VT_VALUE_DOMAIN_OPTIONAL_U64 &&
         cursor->next_index == 0 && limits->max_values < 1))
        return VT_STATUS_LIMIT_EXCEEDED;
    const size_t index = cursor->next_index++;
    const uint64_t label = label_at(cursor->dictionary, index);
    const void *units;
    if (cursor->dictionary->unit_domain == VT_UNIT_DOMAIN_BYTE) {
        cursor->units.bytes[0] = (uint8_t)label;
        units = cursor->units.bytes;
    } else if (cursor->dictionary->unit_domain == VT_UNIT_DOMAIN_UNICODE_SCALAR) {
        cursor->units.scalars[0] = (uint32_t)label;
        units = cursor->units.scalars;
    } else {
        cursor->units.tokens[0] = label;
        units = cursor->units.tokens;
    }
    cursor->values[0] = 0;
    cursor->descriptor = (VtDictionaryEntry){
        .unit_offset = 0,
        .unit_len = cursor->dictionary->hostile_mode == 2 ? 2 : 1,
        .value_offset = 0,
        .value_len = cursor->dictionary->hostile_mode == 3 ? 2 :
            (cursor->dictionary->value_domain == VT_VALUE_DOMAIN_OPTIONAL_U64 && index == 0),
    };
    cursor->leased = true;
    ++cursor->generation;
    *out = (VtDictionaryEntryBatchView){
        .entries = &cursor->descriptor, .entry_count = 1,
        .units = units, .unit_count = 1,
        .values = cursor->values, .value_count = cursor->descriptor.value_len ? 1 : 0,
        .generation = cursor->generation,
    };
    return VT_STATUS_OK;
}

static VtStatus qualification_entries_release(VtDictionaryEntriesCursor *raw,
                                               uint64_t generation) {
    if (!raw || !raw->context) return VT_STATUS_NULL_POINTER;
    QualificationCursor *cursor = raw->context;
    if (!cursor->leased || generation != cursor->generation)
        return VT_STATUS_INVALID_ARGUMENT;
    cursor->leased = false;
    return VT_STATUS_OK;
}

static VtStatus qualification_entries_reduce(VtDictionaryEntriesCursor *raw,
                                              const VtDictionaryEntryBatchLimits *limits,
                                              VtDictionaryEntryReducer reducer,
                                              void *reducer_context,
                                              size_t *out_count) {
    if (!raw || !raw->context || !limits || !reducer || !out_count)
        return VT_STATUS_NULL_POINTER;
    QualificationCursor *cursor = raw->context;
    if (cursor->leased) return VT_STATUS_BATCH_IN_USE;
    *out_count = 0;
    for (;;) {
        VtDictionaryEntryBatchView batch;
        VtStatus status = qualification_entries_next(raw, limits, &batch);
        if (status == VT_STATUS_END) return VT_STATUS_OK;
        if (status != VT_STATUS_OK) return status;
        status = reducer(reducer_context, &batch);
        VtStatus release_status = qualification_entries_release(raw, batch.generation);
        if (release_status != VT_STATUS_OK) return release_status;
        ++*out_count;
        if (status == VT_STATUS_END) {
            cursor->cancelled = true;
            return VT_STATUS_OK;
        }
        if (status != VT_STATUS_OK) return status;
    }
}

static VtStatus qualification_entries_cancel(VtDictionaryEntriesCursor *raw) {
    if (!raw || !raw->context) return VT_STATUS_NULL_POINTER;
    QualificationCursor *cursor = raw->context;
    if (cursor->leased) return VT_STATUS_BATCH_IN_USE;
    cursor->cancelled = true;
    return VT_STATUS_OK;
}

static VtStatus qualification_entries_close(VtDictionaryEntriesCursor *raw) {
    if (!raw || !raw->context) return VT_STATUS_NULL_POINTER;
    QualificationCursor *cursor = raw->context;
    if (cursor->leased) return VT_STATUS_BATCH_IN_USE;
    QualificationDictionary *dictionary = cursor->dictionary;
    raw->context = NULL;
    raw->vtable = NULL;
    atomic_fetch_sub(&live_cursors, 1);
    free(cursor);
    qualification_release(dictionary);
    return VT_STATUS_OK;
}

static VtStatus semiring_token(QualificationDictionary *dictionary,
                               uint64_t number, VtSemiringValue *out) {
    if (!out) return VT_STATUS_NULL_POINTER;
    if (dictionary->next_token + 1 >= 256) return VT_STATUS_LIMIT_EXCEEDED;
    const uint64_t token = ++dictionary->next_token;
    dictionary->live_tokens[token] = true;
    atomic_fetch_add(&live_semiring_tokens, 1);
    *out = (VtSemiringValue){number, token};
    return VT_STATUS_OK;
}

static VtStatus semiring_number(QualificationDictionary *dictionary,
                                const VtSemiringValue *value, uint64_t *out) {
    if (!value || !out) return VT_STATUS_NULL_POINTER;
    if (value->word1 == 0 || value->word1 >= 256 ||
        !dictionary->live_tokens[value->word1])
        return VT_STATUS_INVALID_ARGUMENT;
    *out = value->word0;
    return VT_STATUS_OK;
}

static VtStatus semiring_zero(void *context, VtSemiringValue *out) {
    return semiring_token(context, 0, out);
}

static VtStatus semiring_one(void *context, VtSemiringValue *out) {
    return semiring_token(context, 1, out);
}

static VtStatus semiring_clone(void *context, const VtSemiringValue *value,
                               VtSemiringValue *out) {
    uint64_t number;
    VtStatus status = semiring_number(context, value, &number);
    return status == VT_STATUS_OK ? semiring_token(context, number, out) : status;
}

static VtStatus semiring_release_values(void *context, VtSemiringValue *values,
                                        size_t count) {
    QualificationDictionary *dictionary = context;
    if (count && !values) return VT_STATUS_NULL_POINTER;
    for (size_t index = 0; index < count; ++index) {
        uint64_t number;
        VtStatus status = semiring_number(dictionary, &values[index], &number);
        if (status != VT_STATUS_OK) return status;
        for (size_t prior = 0; prior < index; ++prior)
            if (values[prior].word1 == values[index].word1)
                return VT_STATUS_INVALID_ARGUMENT;
    }
    for (size_t index = 0; index < count; ++index) {
        dictionary->live_tokens[values[index].word1] = false;
        values[index] = (VtSemiringValue){0};
        atomic_fetch_sub(&live_semiring_tokens, 1);
    }
    return VT_STATUS_OK;
}

static VtStatus semiring_binary(void *context, const VtSemiringValue *left,
                                const VtSemiringValue *right,
                                VtSemiringValue *out, bool multiply) {
    uint64_t a, b;
    VtStatus status = semiring_number(context, left, &a);
    if (status != VT_STATUS_OK) return status;
    status = semiring_number(context, right, &b);
    if (status != VT_STATUS_OK) return status;
    if (multiply) {
        if (b && a > UINT64_MAX / b) return VT_STATUS_LIMIT_EXCEEDED;
        return semiring_token(context, a * b, out);
    }
    if (a > UINT64_MAX - b) return VT_STATUS_LIMIT_EXCEEDED;
    return semiring_token(context, a + b, out);
}

static VtStatus semiring_plus(void *context, const VtSemiringValue *left,
                              const VtSemiringValue *right,
                              VtSemiringValue *out) {
    return semiring_binary(context, left, right, out, false);
}

static VtStatus semiring_times(void *context, const VtSemiringValue *left,
                               const VtSemiringValue *right,
                               VtSemiringValue *out) {
    return semiring_binary(context, left, right, out, true);
}

static VtStatus semiring_equal(void *context, const VtSemiringValue *left,
                               const VtSemiringValue *right, uint8_t *out) {
    uint64_t a, b;
    if (!out) return VT_STATUS_NULL_POINTER;
    VtStatus status = semiring_number(context, left, &a);
    if (status != VT_STATUS_OK) return status;
    status = semiring_number(context, right, &b);
    if (status != VT_STATUS_OK) return status;
    *out = a == b;
    return VT_STATUS_OK;
}

static VtStatus semiring_approx(void *context, const VtSemiringValue *left,
                                const VtSemiringValue *right, double epsilon,
                                uint8_t *out) {
    uint64_t a, b;
    if (!out || epsilon < 0) return VT_STATUS_INVALID_ARGUMENT;
    VtStatus status = semiring_number(context, left, &a);
    if (status != VT_STATUS_OK) return status;
    status = semiring_number(context, right, &b);
    if (status != VT_STATUS_OK) return status;
    const double gap = a >= b ? (double)(a - b) : (double)(b - a);
    *out = gap <= epsilon;
    return VT_STATUS_OK;
}

static VtStatus semiring_order(void *context, const VtSemiringValue *left,
                               const VtSemiringValue *right, int32_t *out) {
    uint64_t a, b;
    if (!out) return VT_STATUS_NULL_POINTER;
    VtStatus status = semiring_number(context, left, &a);
    if (status != VT_STATUS_OK) return status;
    status = semiring_number(context, right, &b);
    if (status != VT_STATUS_OK) return status;
    *out = a < b ? VT_SEMIRING_ORDER_BETTER :
        a > b ? VT_SEMIRING_ORDER_WORSE : VT_SEMIRING_ORDER_EQUAL;
    return VT_STATUS_OK;
}

static VtStatus semiring_bytes(const uint8_t *bytes, size_t length,
                               uint8_t *out, size_t capacity,
                               size_t *written, size_t *required) {
    if (!written || !required) return VT_STATUS_NULL_POINTER;
    *required = length;
    *written = 0;
    if (capacity < length) return VT_STATUS_LIMIT_EXCEEDED;
    if (length && !out) return VT_STATUS_NULL_POINTER;
    memcpy(out, bytes, length);
    *written = length;
    return VT_STATUS_OK;
}

static VtStatus semiring_stable_bytes(void *context,
                                      const VtSemiringValue *value,
                                      uint8_t *out, size_t capacity,
                                      size_t *written, size_t *required) {
    uint64_t number;
    VtStatus status = semiring_number(context, value, &number);
    if (status != VT_STATUS_OK) return status;
    uint8_t bytes[8];
    for (size_t index = 0; index < 8; ++index)
        bytes[index] = (uint8_t)(number >> ((7 - index) * 8));
    return semiring_bytes(bytes, sizeof(bytes), out, capacity, written, required);
}

static VtStatus semiring_diagnostic(void *context,
                                    const VtSemiringValue *value,
                                    uint8_t *out, size_t capacity,
                                    size_t *written, size_t *required) {
    uint64_t number;
    VtStatus status = semiring_number(context, value, &number);
    if (status != VT_STATUS_OK) return status;
    (void)number;
    static const uint8_t description[] = "qualification count";
    return semiring_bytes(description, sizeof(description) - 1, out, capacity,
                          written, required);
}

static VtStatus semiring_many(void *context, const VtSemiringValue *values,
                              size_t count, VtSemiringValue *out,
                              bool multiply) {
    if (count && !values) return VT_STATUS_NULL_POINTER;
    uint64_t result = multiply ? 1 : 0;
    for (size_t index = 0; index < count; ++index) {
        uint64_t number;
        VtStatus status = semiring_number(context, &values[index], &number);
        if (status != VT_STATUS_OK) return status;
        if (multiply) {
            if (number && result > UINT64_MAX / number)
                return VT_STATUS_LIMIT_EXCEEDED;
            result *= number;
        } else {
            if (result > UINT64_MAX - number) return VT_STATUS_LIMIT_EXCEEDED;
            result += number;
        }
    }
    return semiring_token(context, result, out);
}

static VtStatus semiring_plus_many(void *context, const VtSemiringValue *values,
                                   size_t count, VtSemiringValue *out) {
    return semiring_many(context, values, count, out, false);
}

static VtStatus semiring_times_many(void *context, const VtSemiringValue *values,
                                    size_t count, VtSemiringValue *out) {
    return semiring_many(context, values, count, out, true);
}

static VtStatus semiring_divide(void *context, const VtSemiringValue *left,
                                const VtSemiringValue *right,
                                VtSemiringValue *out) {
    uint64_t a, b;
    VtStatus status = semiring_number(context, left, &a);
    if (status != VT_STATUS_OK) return status;
    status = semiring_number(context, right, &b);
    if (status != VT_STATUS_OK) return status;
    if (!b || a % b) return VT_STATUS_END;
    return semiring_token(context, a / b, out);
}

static VtStatus semiring_star(void *context, const VtSemiringValue *value,
                              VtSemiringValue *out) {
    uint64_t number;
    VtStatus status = semiring_number(context, value, &number);
    if (status != VT_STATUS_OK) return status;
    if (number != 0) return VT_STATUS_END;
    return semiring_token(context, 1, out);
}

static VtStatus semiring_numerical(void *context,
                                   const VtSemiringValue *value,
                                   double *out) {
    uint64_t number;
    if (!out) return VT_STATUS_NULL_POINTER;
    VtStatus status = semiring_number(context, value, &number);
    if (status == VT_STATUS_OK) *out = (double)number;
    return status;
}

static VtStatus semiring_quantize(void *context,
                                  const VtSemiringValue *value,
                                  double epsilon, int64_t *out) {
    double number;
    if (!out || epsilon <= 0) return VT_STATUS_INVALID_ARGUMENT;
    VtStatus status = semiring_numerical(context, value, &number);
    if (status != VT_STATUS_OK) return status;
    if (number / epsilon > (double)INT64_MAX) return VT_STATUS_LIMIT_EXCEEDED;
    *out = (int64_t)(number / epsilon);
    return VT_STATUS_OK;
}

static VtStatus semiring_probability(void *context,
                                     const VtSemiringValue *value,
                                     double *out) {
    return semiring_numerical(context, value, out);
}

static VtStatus semiring_closure_bound(void *context, size_t *out,
                                       uint8_t *known) {
    (void)context;
    if (!out || !known) return VT_STATUS_NULL_POINTER;
    *out = 0;
    *known = 0;
    return VT_STATUS_OK;
}

VtStatus vt_qualification_dictionary(uint32_t unit_domain,
                                      uint32_t value_domain,
                                      uint32_t hostile_mode,
                                      VtResource *out) {
    if (!out) return VT_STATUS_NULL_POINTER;
    *out = (VtResource){0};
    if (unit_domain < VT_UNIT_DOMAIN_BYTE || unit_domain > VT_UNIT_DOMAIN_U64 ||
        (value_domain != VT_VALUE_DOMAIN_UNIT &&
         value_domain != VT_VALUE_DOMAIN_OPTIONAL_U64))
        return VT_STATUS_INVALID_ARGUMENT;
    QualificationDictionary *dictionary = calloc(1, sizeof(*dictionary));
    if (!dictionary) return VT_STATUS_LIMIT_EXCEEDED;
    atomic_init(&dictionary->references, 1);
    dictionary->unit_domain = (VtUnitDomain)unit_domain;
    dictionary->value_domain = (VtValueDomain)value_domain;
    dictionary->hostile_mode = hostile_mode;
    dictionary->revision = atomic_fetch_add(&next_revision, 1);
    dictionary->dictionary = (VtDictionaryVTable){
        .struct_size = sizeof(VtDictionaryVTable),
        .interface_version = VT_DICTIONARY_INTERFACE_VERSION,
        .unit_domain = dictionary->unit_domain,
        .value_domain = dictionary->value_domain,
        .flags = VT_DICTIONARY_FLAG_IMMUTABLE | VT_DICTIONARY_FLAG_PARALLEL_REENTRANT,
        .snapshot = qualification_snapshot, .root = qualification_root,
        .len = qualification_len, .node_is_final = qualification_final,
        .node_value_u64 = qualification_value,
        .node_transition = qualification_transition,
        .node_edges = qualification_edges,
    };
    dictionary->visit = (VtDictionaryVisitVTable){
        .struct_size = sizeof(VtDictionaryVisitVTable),
        .interface_version = VT_DICTIONARY_VISIT_INTERFACE_VERSION,
        .node_visit = qualification_visit,
    };
    dictionary->graph = (VtDictionaryGraphVTable){
        .struct_size = sizeof(VtDictionaryGraphVTable),
        .interface_version = VT_DICTIONARY_GRAPH_INTERFACE_VERSION,
        .graph = qualification_graph, .node_value_u64 = qualification_value,
    };
    dictionary->identity = (VtSnapshotIdentityVTable){
        .struct_size = sizeof(VtSnapshotIdentityVTable),
        .interface_version = VT_SNAPSHOT_IDENTITY_INTERFACE_VERSION,
        .identity = qualification_identity,
    };
    dictionary->entries = (VtDictionaryEntriesVTable){
        .struct_size = sizeof(VtDictionaryEntriesVTable),
        .interface_version = VT_DICTIONARY_ENTRIES_INTERFACE_VERSION,
        .open = qualification_entries_open, .next_batch = qualification_entries_next,
        .release_batch = qualification_entries_release,
        .reduce = qualification_entries_reduce,
        .cancel = qualification_entries_cancel,
        .close = qualification_entries_close,
    };
    dictionary->nodes[0] = (VtDictionaryGraphNode){.edge_start = 0, .edge_len = 2};
    dictionary->nodes[1] = (VtDictionaryGraphNode){.edge_start = 2, .is_final = 1,
        .value_cursor = 1};
    dictionary->nodes[2] = (VtDictionaryGraphNode){.edge_start = 2, .is_final = 1,
        .value_cursor = 2};
    for (size_t index = 0; index < 2; ++index)
        dictionary->graph_edges[index] = (VtDictionaryGraphEdge){
            .label = label_at(dictionary, index), .target = index + 1,
        };
    atomic_fetch_add(&live_dictionaries, 1);
    *out = qualification_resource(dictionary);
    return VT_STATUS_OK;
}

VtStatus vt_qualification_wfst(uint32_t unit_domain, uint32_t weight_domain,
                                uint32_t hostile_mode, VtResource *out) {
    if (weight_domain < VT_WEIGHT_DOMAIN_TROPICAL_F64 ||
        weight_domain > VT_WEIGHT_DOMAIN_BOOLEAN_F64)
        return VT_STATUS_INVALID_ARGUMENT;
    VtStatus status = vt_qualification_dictionary(unit_domain, VT_VALUE_DOMAIN_UNIT,
                                                   hostile_mode, out);
    if (status != VT_STATUS_OK) return status;
    QualificationDictionary *dictionary = out->context;
    dictionary->weight_domain = (VtWeightDomain)weight_domain;
    dictionary->wfst = (VtWfstVTable){
        .struct_size = sizeof(VtWfstVTable),
        .interface_version = VT_WFST_INTERFACE_VERSION,
        .unit_domain = dictionary->unit_domain,
        .weight_domain = dictionary->weight_domain,
        .flags = VT_WFST_FLAG_IMMUTABLE | VT_WFST_FLAG_PARALLEL_REENTRANT,
        .snapshot = qualification_snapshot,
        .start = qualification_wfst_start,
        .num_states = qualification_wfst_count,
        .state_info = qualification_wfst_info,
        .state_arcs = qualification_wfst_arcs,
    };
    return VT_STATUS_OK;
}

VtStatus vt_qualification_semiring(VtResource *out) {
    VtStatus status = vt_qualification_dictionary(VT_UNIT_DOMAIN_BYTE,
                                                   VT_VALUE_DOMAIN_UNIT, 0, out);
    if (status != VT_STATUS_OK) return status;
    QualificationDictionary *dictionary = out->context;
    dictionary->semiring_active = true;
    const VtInterfaceId domain = {{'q','u','a','l','i','f','i','c','a','t','i','o','n','-','n','1'}};
    dictionary->semiring = (VtSemiringVTable){
        .struct_size = sizeof(VtSemiringVTable),
        .interface_version = VT_SEMIRING_INTERFACE_VERSION,
        .flags = VT_SEMIRING_FLAG_THREAD_BOUND |
                 VT_SEMIRING_FLAG_STABLE_BYTES | VT_SEMIRING_FLAG_BATCH,
        .domain_id = domain,
        .zero = semiring_zero, .one = semiring_one,
        .clone_value = semiring_clone,
        .release_values = semiring_release_values,
        .plus = semiring_plus, .times = semiring_times,
        .equal = semiring_equal, .approx_equal = semiring_approx,
        .natural_order = semiring_order,
        .stable_bytes = semiring_stable_bytes,
        .diagnostic = semiring_diagnostic,
        .plus_many = semiring_plus_many,
        .times_many = semiring_times_many,
    };
    dictionary->division = (VtSemiringDivisionVTable){
        .struct_size = sizeof(VtSemiringDivisionVTable),
        .interface_version = VT_SEMIRING_DIVISION_INTERFACE_VERSION,
        .divide = semiring_divide, .left_divide = semiring_divide,
    };
    dictionary->star = (VtSemiringStarVTable){
        .struct_size = sizeof(VtSemiringStarVTable),
        .interface_version = VT_SEMIRING_STAR_INTERFACE_VERSION,
        .star = semiring_star,
    };
    dictionary->numeric = (VtSemiringNumericVTable){
        .struct_size = sizeof(VtSemiringNumericVTable),
        .interface_version = VT_SEMIRING_NUMERIC_INTERFACE_VERSION,
        .numerical_value = semiring_numerical,
        .quantize = semiring_quantize,
        .to_probability = semiring_probability,
    };
    dictionary->properties = (VtSemiringPropertiesVTable){
        .struct_size = sizeof(VtSemiringPropertiesVTable),
        .interface_version = VT_SEMIRING_PROPERTIES_INTERFACE_VERSION,
        .properties = VT_SEMIRING_PROPERTY_HASHABLE |
                      VT_SEMIRING_PROPERTY_COMMUTATIVE_TIMES |
                      VT_SEMIRING_PROPERTY_ZERO_SUM_FREE |
                      VT_SEMIRING_PROPERTY_NONNEGATIVE,
        .closure_bound = semiring_closure_bound,
    };
    return VT_STATUS_OK;
}
