#define _POSIX_C_SOURCE 200809L
#include "vinary_tree_interop.h"

#include <stdint.h>
#include <string.h>
#include <time.h>

extern VtStatus vt_qualification_dictionary(uint32_t, uint32_t, uint32_t,
                                             VtResource *);
extern VtStatus vt_qualification_wfst(uint32_t, uint32_t, uint32_t,
                                      VtResource *);
extern VtStatus vt_qualification_semiring(VtResource *);
extern void vt_test_lattice(uint64_t, VtResource *);

enum {
    RESOURCE_RETAIN = 1, DICTIONARY_QUERY, DICTIONARY_SNAPSHOT,
    DICTIONARY_VISIT, DICTIONARY_GRAPH, ENTRY_PAGE, ENTRY_REDUCE,
    WFST_EXPAND, LATTICE_PAIR, LATTICE_BATCH, SEMIRING_PAIR,
    SEMIRING_BATCH,
};

static uint64_t now_ns(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return 0;
    return (uint64_t)now.tv_sec * UINT64_C(1000000000) + now.tv_nsec;
}

static VtStatus lookup(VtResource resource, const VtInterfaceId *id,
                        const void **out) {
    return resource.vtable->query_interface(resource.context, id, 1, out);
}

static VtStatus count_entries(void *context,
                               const VtDictionaryEntryBatchView *batch) {
    if (!context || !batch) return VT_STATUS_NULL_POINTER;
    *(uint64_t *)context += batch->entry_count;
    return VT_STATUS_OK;
}

static VtStatus dictionary_case(uint32_t which, size_t iterations,
                                 uint64_t *sum, uint64_t *duration) {
    const uint64_t started = now_ns();
    VtResource resource = {0};
    VtStatus status = vt_qualification_dictionary(VT_UNIT_DOMAIN_BYTE,
        VT_VALUE_DOMAIN_OPTIONAL_U64, 0, &resource);
    if (status != VT_STATUS_OK) return status;
    const void *pointer = NULL;
    status = lookup(resource, &VT_DICTIONARY_INTERFACE_ID, &pointer);
    if (status != VT_STATUS_OK) goto finish;
    const VtDictionaryVTable *dictionary = pointer;
    for (size_t i = 0; i < iterations; ++i) {
        if (which == RESOURCE_RETAIN) {
            resource.vtable->retain(resource.context);
            resource.vtable->release(resource.context);
            *sum += 1;
        } else if (which == DICTIONARY_QUERY) {
            uint64_t root = 0, child = 0;
            uint8_t found = 0, final = 0;
            VtOptionalU64 value = {0};
            status = dictionary->root(resource.context, &root);
            if (status == VT_STATUS_OK) status = dictionary->node_transition(
                resource.context, root, 0, &child, &found);
            if (status == VT_STATUS_OK && found) status = dictionary->node_is_final(
                resource.context, child, &final);
            if (status == VT_STATUS_OK && final) status = dictionary->node_value_u64(
                resource.context, child, &value);
            if (status != VT_STATUS_OK || !found || !final || !value.has_value)
                break;
            *sum += found + final + value.has_value;
        } else if (which == DICTIONARY_SNAPSHOT) {
            VtResource captured = {0};
            status = dictionary->snapshot(resource.context, &captured);
            if (status != VT_STATUS_OK) break;
            captured.vtable->release(captured.context);
            *sum += 1;
        } else if (which == DICTIONARY_VISIT) {
            status = lookup(resource, &VT_DICTIONARY_VISIT_INTERFACE_ID, &pointer);
            if (status != VT_STATUS_OK) break;
            const VtDictionaryVisitVTable *visit = pointer;
            VtDictionaryEdge page[2] = {{0}};
            size_t written = 0, total = 0;
            uint8_t final = 0;
            status = visit->node_visit(resource.context, 0, 0, &final, page,
                                       2, &written, &total);
            if (status != VT_STATUS_OK || written != 2 || total != 2) break;
            *sum += written + total + page[1].node;
        } else if (which == DICTIONARY_GRAPH) {
            status = lookup(resource, &VT_DICTIONARY_GRAPH_INTERFACE_ID, &pointer);
            if (status != VT_STATUS_OK) break;
            const VtDictionaryGraphVTable *graph = pointer;
            VtDictionaryGraphView view = {0};
            VtDictionaryGraphNode nodes[3];
            VtDictionaryGraphEdge edges[2];
            status = graph->graph(resource.context, &view);
            if (status != VT_STATUS_OK || view.node_count != 3 ||
                view.edge_count != 2) break;
            resource.vtable->retain(resource.context);
            memcpy(nodes, view.nodes, sizeof(nodes));
            memcpy(edges, view.edges, sizeof(edges));
            *sum += nodes[1].is_final + edges[1].target;
            resource.vtable->release(resource.context);
        } else if (which == ENTRY_PAGE || which == ENTRY_REDUCE) {
            status = lookup(resource, &VT_DICTIONARY_ENTRIES_INTERFACE_ID, &pointer);
            if (status != VT_STATUS_OK) break;
            const VtDictionaryEntriesVTable *entries = pointer;
            const VtDictionaryEntryBatchLimits limits = {2, 2, 2, 0};
            VtDictionaryEntriesCursor cursor = {0};
            VtDictionaryEntriesInfo info = {0};
            status = entries->open(resource.context, &cursor, &info);
            if (status != VT_STATUS_OK) break;
            if (which == ENTRY_PAGE) {
                VtDictionaryEntryBatchView page = {0};
                status = entries->next_batch(&cursor, &limits, &page);
                if (status == VT_STATUS_OK) {
                    if (page.entry_count != 2 || page.unit_count != 2)
                        status = VT_STATUS_PROVIDER_ERROR;
                    else *sum += page.entry_count +
                        ((const uint8_t *)page.units)[0] + page.entries[1].unit_len;
                    VtStatus released = entries->release_batch(&cursor,
                                                                 page.generation);
                    if (status == VT_STATUS_OK) status = released;
                }
            } else {
                uint64_t counted = 0;
                size_t processed = 0;
                status = entries->reduce(&cursor, &limits, count_entries,
                                         &counted, &processed);
                if (status == VT_STATUS_OK && counted == 2 && processed == 2)
                    *sum += counted + processed;
                else status = VT_STATUS_PROVIDER_ERROR;
            }
            VtStatus closed = entries->close(&cursor);
            if (status == VT_STATUS_OK) status = closed;
            if (status != VT_STATUS_OK) break;
        } else {
            status = VT_STATUS_INVALID_ARGUMENT;
            break;
        }
    }
finish:
    resource.vtable->release(resource.context);
    *duration = now_ns() - started;
    return status;
}

static VtStatus wfst_case(size_t iterations, uint64_t *sum,
                           uint64_t *duration) {
    const uint64_t started = now_ns();
    VtResource resource = {0};
    VtStatus status = vt_qualification_wfst(VT_UNIT_DOMAIN_BYTE,
        VT_WEIGHT_DOMAIN_TROPICAL_F64, 0, &resource);
    if (status != VT_STATUS_OK) return status;
    const void *pointer = NULL;
    status = lookup(resource, &VT_WFST_INTERFACE_ID, &pointer);
    if (status != VT_STATUS_OK) goto finish;
    const VtWfstVTable *wfst = pointer;
    for (size_t i = 0; i < iterations; ++i) {
        uint8_t valid = 0, final = 0;
        double weight = 0;
        size_t written = 0, total = 0;
        VtWfstArc arcs[2] = {{0}};
        status = wfst->state_info(resource.context, 0, &valid, &final, &weight);
        if (status == VT_STATUS_OK) status = wfst->state_arcs(
            resource.context, 0, 0, arcs, 2, &written, &total);
        if (status != VT_STATUS_OK || !valid || written != 2 || total != 2)
            break;
        *sum += written + total + arcs[0].target_state;
    }
finish:
    resource.vtable->release(resource.context);
    *duration = now_ns() - started;
    return status;
}

static VtStatus lattice_case(uint32_t which, size_t iterations,
                              uint64_t *sum, uint64_t *duration) {
    const uint64_t started = now_ns();
    VtResource base = {0}, operands[3] = {{0}};
    vt_test_lattice(3, &base);
    vt_test_lattice(5, &operands[0]);
    vt_test_lattice(7, &operands[1]);
    vt_test_lattice(11, &operands[2]);
    const void *pointer = NULL;
    VtStatus status = base.vtable && operands[0].vtable &&
        operands[1].vtable && operands[2].vtable ? VT_STATUS_OK :
        VT_STATUS_IO_ERROR;
    if (status != VT_STATUS_OK) goto finish;
    status = lookup(base, &VT_LATTICE_INTERFACE_ID, &pointer);
    if (status != VT_STATUS_OK) goto finish;
    const VtLatticeVTable *lattice = pointer;
    for (size_t i = 0; i < iterations; ++i) {
        VtResource result = {0};
        status = which == LATTICE_PAIR ?
            lattice->join(base.context, &operands[0], &result) :
            lattice->join_many(base.context, operands, 3, &result);
        if (status != VT_STATUS_OK) break;
        *sum += which == LATTICE_PAIR ? 5 : 11;
        result.vtable->release(result.context);
    }
finish:
    for (size_t i = 0; i < 3; ++i)
        if (operands[i].vtable) operands[i].vtable->release(operands[i].context);
    if (base.vtable) base.vtable->release(base.context);
    *duration = now_ns() - started;
    return status;
}

static VtStatus semiring_case(uint32_t which, size_t iterations,
                               uint64_t *sum, uint64_t *duration) {
    /* The qualification fixture has a finite token table, so each iteration
     * uses a fresh context. Both native and Julia timings include that setup. */
    const uint64_t started = now_ns();
    VtStatus status = VT_STATUS_OK;
    for (size_t i = 0; i < iterations; ++i) {
        VtResource resource = {0};
        status = vt_qualification_semiring(&resource);
        if (status != VT_STATUS_OK) break;
        const void *pointer = NULL;
        status = lookup(resource, &VT_SEMIRING_INTERFACE_ID, &pointer);
        if (status == VT_STATUS_OK) {
            const VtSemiringVTable *semiring = pointer;
            VtSemiringValue values[4] = {{0}};
            const size_t count = which == SEMIRING_PAIR ? 3 : 4;
            status = semiring->one(resource.context, &values[0]);
            if (status == VT_STATUS_OK)
                status = semiring->one(resource.context, &values[1]);
            if (status == VT_STATUS_OK && count == 4)
                status = semiring->one(resource.context, &values[2]);
            if (status == VT_STATUS_OK) status = count == 3 ?
                semiring->plus(resource.context, &values[0], &values[1],
                               &values[2]) :
                semiring->plus_many(resource.context, values, 3, &values[3]);
            if (status == VT_STATUS_OK) {
                *sum += count == 3 ? 2 : 3;
                status = semiring->release_values(resource.context, values,
                                                  count);
            }
        }
        resource.vtable->release(resource.context);
        if (status != VT_STATUS_OK) break;
    }
    *duration = now_ns() - started;
    return status;
}

VtStatus vt_benchmark_native(uint32_t which, size_t iterations,
                              uint64_t *checksum, uint64_t *elapsed_ns) {
    if (!checksum || !elapsed_ns || iterations == 0)
        return VT_STATUS_INVALID_ARGUMENT;
    *checksum = 0;
    *elapsed_ns = 0;
    if (which >= RESOURCE_RETAIN && which <= ENTRY_REDUCE)
        return dictionary_case(which, iterations, checksum, elapsed_ns);
    if (which == WFST_EXPAND)
        return wfst_case(iterations, checksum, elapsed_ns);
    if (which == LATTICE_PAIR || which == LATTICE_BATCH)
        return lattice_case(which, iterations, checksum, elapsed_ns);
    if (which == SEMIRING_PAIR || which == SEMIRING_BATCH)
        return semiring_case(which, iterations, checksum, elapsed_ns);
    return VT_STATUS_INVALID_ARGUMENT;
}
