#include "vinary_tree_interop.h"

#include <string.h>
#include <stdlib.h>

static size_t references = 0;

static void test_retain(void *context) {
    (void)context;
    references += 1;
}

static void test_release(void *context) {
    (void)context;
    references -= 1;
}

static VtStatus test_snapshot(void *context, VtResource *out_snapshot);

static VtStatus test_root(void *context, uint64_t *out_node) {
    (void)context;
    *out_node = 0;
    return VT_STATUS_OK;
}

static VtStatus test_len(void *context, size_t *out_len, uint8_t *out_known) {
    (void)context;
    *out_len = 2;
    *out_known = 1;
    return VT_STATUS_OK;
}

static VtStatus test_is_final(void *context, uint64_t node,
                              uint8_t *out_is_final) {
    (void)context;
    *out_is_final = node == 1 || node == 2;
    return VT_STATUS_OK;
}

static VtStatus test_value(void *context, uint64_t node,
                           VtOptionalU64 *out_value) {
    (void)context;
    memset(out_value, 0, sizeof(*out_value));
    if (node == 1 || node == 2) {
        out_value->has_value = 1;
        out_value->value = node * 10;
    }
    return VT_STATUS_OK;
}

static VtStatus test_transition(void *context, uint64_t node, uint64_t label,
                                uint64_t *out_child, uint8_t *out_found) {
    (void)context;
    *out_found = 0;
    *out_child = 0;
    if (node == 0 && label == 'a') {
        *out_found = 1;
        *out_child = 1;
    } else if (node == 0 && label == 'b') {
        *out_found = 1;
        *out_child = 2;
    }
    return VT_STATUS_OK;
}

static VtStatus test_edges(void *context, uint64_t node, size_t start,
                           VtDictionaryEdge *out_edges, size_t capacity,
                           size_t *out_written, size_t *out_total) {
    static const VtDictionaryEdge edges[] = {{'a', 1}, {'b', 2}};
    (void)context;
    const size_t total = node == 0 ? 2 : 0;
    *out_total = total;
    *out_written = 0;
    for (size_t index = start; index < total && *out_written < capacity; ++index) {
        out_edges[*out_written] = edges[index];
        *out_written += 1;
    }
    return VT_STATUS_OK;
}

static const VtDictionaryVTable dictionary_vtable = {
    sizeof(VtDictionaryVTable),
    VT_DICTIONARY_INTERFACE_VERSION,
    VT_UNIT_DOMAIN_UNICODE_SCALAR,
    VT_VALUE_DOMAIN_OPTIONAL_U64,
    VT_DICTIONARY_FLAG_IMMUTABLE | VT_DICTIONARY_FLAG_PARALLEL_REENTRANT,
    test_snapshot,
    test_root,
    test_len,
    test_is_final,
    test_value,
    test_transition,
    test_edges,
};

typedef struct TestEntriesCursor {
    size_t index;
    uint64_t generation;
    uint8_t batch_active;
    VtDictionaryEntry entry;
    uint32_t unit;
    uint64_t value;
} TestEntriesCursor;

static VtStatus test_entries_open(void *context,
                                  VtDictionaryEntriesCursor *out_cursor,
                                  VtDictionaryEntriesInfo *out_info);
static VtStatus test_entries_next(VtDictionaryEntriesCursor *cursor,
                                  const VtDictionaryEntryBatchLimits *limits,
                                  VtDictionaryEntryBatchView *out_batch);
static VtStatus test_entries_release(VtDictionaryEntriesCursor *cursor,
                                     uint64_t generation);
static VtStatus test_entries_reduce(VtDictionaryEntriesCursor *cursor,
                                    const VtDictionaryEntryBatchLimits *limits,
                                    VtDictionaryEntryReducer reducer,
                                    void *reducer_context,
                                    size_t *out_count);
static VtStatus test_entries_cancel(VtDictionaryEntriesCursor *cursor);
static VtStatus test_entries_close(VtDictionaryEntriesCursor *cursor);

static const VtDictionaryEntriesVTable entries_vtable = {
    sizeof(VtDictionaryEntriesVTable),
    VT_DICTIONARY_ENTRIES_INTERFACE_VERSION,
    0,
    test_entries_open,
    test_entries_next,
    test_entries_release,
    test_entries_reduce,
    test_entries_cancel,
    test_entries_close,
};

static VtStatus test_wfst_snapshot(void *context, VtResource *out_snapshot) {
    return test_snapshot(context, out_snapshot);
}

static VtStatus test_wfst_start(void *context, uint64_t *out_state) {
    (void)context;
    *out_state = 0;
    return VT_STATUS_OK;
}

static VtStatus test_wfst_num_states(void *context, size_t *out_count,
                                     uint8_t *out_known) {
    (void)context;
    *out_count = 2;
    *out_known = 1;
    return VT_STATUS_OK;
}

static VtStatus test_wfst_state_info(void *context, uint64_t state,
                                     uint8_t *out_valid,
                                     uint8_t *out_is_final,
                                     double *out_final_weight) {
    (void)context;
    *out_valid = state < 2;
    *out_is_final = state == 1;
    *out_final_weight = state == 1 ? 2.0 : 0.0;
    return VT_STATUS_OK;
}

static VtStatus test_wfst_arcs(void *context, uint64_t state, size_t start,
                               VtWfstArc *out_arcs, size_t capacity,
                               size_t *out_written, size_t *out_total) {
    (void)context;
    static const VtWfstArc arc = {
        'a',
        'A',
        1,
        1.5,
        1,
        1,
        {0, 0, 0, 0, 0, 0},
    };
    *out_total = state == 0 ? 1 : 0;
    *out_written = 0;
    if (state == 0 && start == 0 && capacity > 0) {
        out_arcs[0] = arc;
        *out_written = 1;
    }
    return VT_STATUS_OK;
}

static const VtWfstVTable wfst_vtable = {
    sizeof(VtWfstVTable),
    VT_WFST_INTERFACE_VERSION,
    VT_UNIT_DOMAIN_UNICODE_SCALAR,
    VT_WEIGHT_DOMAIN_TROPICAL_F64,
    0,
    VT_WFST_FLAG_IMMUTABLE | VT_WFST_FLAG_ACYCLIC,
    test_wfst_snapshot,
    test_wfst_start,
    test_wfst_num_states,
    test_wfst_state_info,
    test_wfst_arcs,
};

static VtStatus test_entries_open(void *context,
                                  VtDictionaryEntriesCursor *out_cursor,
                                  VtDictionaryEntriesInfo *out_info) {
    (void)context;
    TestEntriesCursor *cursor = calloc(1, sizeof(*cursor));
    if (cursor == NULL) {
        return VT_STATUS_IO_ERROR;
    }
    out_cursor->context = cursor;
    out_cursor->vtable = &entries_vtable;
    memset(out_info, 0, sizeof(*out_info));
    out_info->unit_domain = VT_UNIT_DOMAIN_UNICODE_SCALAR;
    out_info->value_domain = VT_VALUE_DOMAIN_OPTIONAL_U64;
    out_info->order = VT_DICTIONARY_ENTRY_ORDER_LEXICOGRAPHIC;
    out_info->flags = VT_DICTIONARY_ENTRIES_INFO_FLAG_EXACT_LEN |
                      VT_DICTIONARY_ENTRIES_INFO_FLAG_SNAPSHOT_IDENTITY;
    out_info->exact_len = 2;
    out_info->identity.producer = 42;
    out_info->identity.revision = 7;
    return VT_STATUS_OK;
}

static VtStatus test_entries_next(VtDictionaryEntriesCursor *raw_cursor,
                                  const VtDictionaryEntryBatchLimits *limits,
                                  VtDictionaryEntryBatchView *out_batch) {
    TestEntriesCursor *cursor = raw_cursor->context;
    if (cursor == NULL) {
        return VT_STATUS_CLOSED;
    }
    if (limits == NULL || limits->max_entries == 0) {
        return VT_STATUS_INVALID_ARGUMENT;
    }
    if (cursor->batch_active) {
        return VT_STATUS_BATCH_IN_USE;
    }
    if (cursor->index >= 2) {
        return VT_STATUS_END;
    }
    memset(out_batch, 0, sizeof(*out_batch));
    memset(&cursor->entry, 0, sizeof(cursor->entry));
    cursor->unit = cursor->index == 0 ? 'a' : 'b';
    cursor->value = (cursor->index + 1) * 10;
    cursor->entry.unit_len = 1;
    cursor->entry.value_len = 1;
    cursor->generation += 1;
    cursor->batch_active = 1;
    out_batch->entries = &cursor->entry;
    out_batch->entry_count = 1;
    out_batch->units = &cursor->unit;
    out_batch->unit_count = 1;
    out_batch->values = &cursor->value;
    out_batch->value_count = 1;
    out_batch->generation = cursor->generation;
    cursor->index += 1;
    return VT_STATUS_OK;
}

static VtStatus test_entries_release(VtDictionaryEntriesCursor *raw_cursor,
                                     uint64_t generation) {
    TestEntriesCursor *cursor = raw_cursor->context;
    if (cursor == NULL) {
        return VT_STATUS_CLOSED;
    }
    if (!cursor->batch_active || generation != cursor->generation) {
        return VT_STATUS_INVALID_ARGUMENT;
    }
    cursor->batch_active = 0;
    return VT_STATUS_OK;
}

static VtStatus test_entries_reduce(VtDictionaryEntriesCursor *cursor,
                                    const VtDictionaryEntryBatchLimits *limits,
                                    VtDictionaryEntryReducer reducer,
                                    void *reducer_context,
                                    size_t *out_count) {
    *out_count = 0;
    for (;;) {
        VtDictionaryEntryBatchView batch;
        VtStatus status = test_entries_next(cursor, limits, &batch);
        if (status == VT_STATUS_END) {
            return VT_STATUS_OK;
        }
        if (status != VT_STATUS_OK) {
            return status;
        }
        status = reducer(reducer_context, &batch);
        if (status != VT_STATUS_OK) {
            return status;
        }
        status = test_entries_release(cursor, batch.generation);
        if (status != VT_STATUS_OK) {
            return status;
        }
        *out_count += batch.entry_count;
    }
}

static VtStatus test_entries_cancel(VtDictionaryEntriesCursor *raw_cursor) {
    TestEntriesCursor *cursor = raw_cursor->context;
    if (cursor == NULL) {
        return VT_STATUS_CLOSED;
    }
    cursor->index = 2;
    return VT_STATUS_OK;
}

static VtStatus test_entries_close(VtDictionaryEntriesCursor *raw_cursor) {
    TestEntriesCursor *cursor = raw_cursor->context;
    if (cursor == NULL) {
        return VT_STATUS_CLOSED;
    }
    free(cursor);
    raw_cursor->context = NULL;
    raw_cursor->vtable = NULL;
    return VT_STATUS_OK;
}

static VtStatus test_query_interface(void *context,
                                     const VtInterfaceId *interface_id,
                                     uint32_t minimum_version,
                                     const void **out_vtable) {
    (void)context;
    *out_vtable = NULL;
    if (minimum_version <= VT_DICTIONARY_INTERFACE_VERSION &&
        memcmp(interface_id, &VT_DICTIONARY_INTERFACE_ID,
               sizeof(*interface_id)) == 0) {
        *out_vtable = &dictionary_vtable;
        return VT_STATUS_OK;
    }
    if (minimum_version <= VT_DICTIONARY_ENTRIES_INTERFACE_VERSION &&
        memcmp(interface_id, &VT_DICTIONARY_ENTRIES_INTERFACE_ID,
               sizeof(*interface_id)) == 0) {
        *out_vtable = &entries_vtable;
        return VT_STATUS_OK;
    }
    if (minimum_version <= VT_WFST_INTERFACE_VERSION &&
        memcmp(interface_id, &VT_WFST_INTERFACE_ID,
               sizeof(*interface_id)) == 0) {
        *out_vtable = &wfst_vtable;
        return VT_STATUS_OK;
    }
    return VT_STATUS_UNSUPPORTED;
}

static const VtResourceVTable resource_vtable = {
    sizeof(VtResourceVTable),
    VT_ABI_VERSION,
    0,
    test_retain,
    test_release,
    test_query_interface,
};

static VtStatus test_snapshot(void *context, VtResource *out_snapshot) {
    test_retain(context);
    out_snapshot->context = context;
    out_snapshot->vtable = &resource_vtable;
    return VT_STATUS_OK;
}

void vt_test_resource(VtResource *out_resource) {
    references += 1;
    out_resource->context = &references;
    out_resource->vtable = &resource_vtable;
}

size_t vt_test_references(void) { return references; }

size_t vt_test_sizeof(uint32_t kind) {
    switch (kind) {
    case 1: return sizeof(VtInterfaceId);
    case 2: return sizeof(VtResource);
    case 3: return sizeof(VtResourceVTable);
    case 4: return sizeof(VtOptionalU64);
    case 5: return sizeof(VtDictionaryEdge);
    case 6: return sizeof(VtDictionaryVTable);
    case 7: return sizeof(VtDictionaryVisitVTable);
    case 8: return sizeof(VtDictionaryGraphNode);
    case 9: return sizeof(VtDictionaryGraphEdge);
    case 10: return sizeof(VtDictionaryGraphView);
    case 11: return sizeof(VtDictionaryGraphVTable);
    case 12: return sizeof(VtSnapshotIdentity);
    case 13: return sizeof(VtSnapshotIdentityVTable);
    case 14: return sizeof(VtDictionaryEntry);
    case 15: return sizeof(VtDictionaryEntryBatchLimits);
    case 16: return sizeof(VtDictionaryEntryBatchView);
    case 17: return sizeof(VtDictionaryEntriesInfo);
    case 18: return sizeof(VtDictionaryEntriesCursor);
    case 19: return sizeof(VtDictionaryEntriesVTable);
    case 20: return sizeof(VtWfstArc);
    case 21: return sizeof(VtWfstVTable);
    default: return 0;
    }
}
