#include "bridge.h"

#include <stdlib.h>
#include <string.h>

extern void goVtRetain(uintptr_t context);
extern uint8_t goVtRelease(uintptr_t context);
extern uint32_t goVtLatticeJoin(uintptr_t context,
                                const VtResource* other,
                                VtResource* out_value);
extern uint32_t goVtLatticeMeet(uintptr_t context,
                                const VtResource* other,
                                VtResource* out_value);
extern uint32_t goVtLatticeEqual(uintptr_t context,
                                 const VtResource* other,
                                 uint8_t* out_equal);
extern uint32_t goVtLatticeStableBytes(uintptr_t context,
                                       uint8_t* out_bytes, size_t capacity,
                                       size_t* out_written,
                                       size_t* out_required);
extern uint32_t goVtLatticeDiagnostic(uintptr_t context,
                                      uint8_t* out_bytes, size_t capacity,
                                      size_t* out_written,
                                      size_t* out_required);
extern uint32_t goVtLatticeJoinMany(uintptr_t context,
                                    const VtResource* others, size_t count,
                                    VtResource* out_value);
extern uint32_t goVtLatticeMeetMany(uintptr_t context,
                                    const VtResource* others, size_t count,
                                    VtResource* out_value);
extern uint32_t goVtWfstStart(uintptr_t context, uint64_t* out_state);
extern uint32_t goVtWfstNumStates(uintptr_t context, size_t* out_count,
                                  uint8_t* out_known);
extern uint32_t goVtWfstStateInfo(uintptr_t context, uint64_t state,
                                  uint8_t* out_valid, uint8_t* out_final,
                                  double* out_weight);
extern uint32_t goVtWfstStateArcs(uintptr_t context, uint64_t state,
                                  size_t start, VtWfstArc* out_arcs,
                                  size_t capacity, size_t* out_written,
                                  size_t* out_total);
extern uint32_t goVtSemiringZero(uintptr_t context,
                                 VtSemiringValue* out_value);
extern uint32_t goVtSemiringOne(uintptr_t context,
                                VtSemiringValue* out_value);
extern uint32_t goVtSemiringClone(uintptr_t context,
                                  const VtSemiringValue* value,
                                  VtSemiringValue* out_value);
extern uint32_t goVtSemiringRelease(uintptr_t context,
                                    VtSemiringValue* values, size_t count);
extern uint32_t goVtSemiringPlus(uintptr_t context,
                                 const VtSemiringValue* left,
                                 const VtSemiringValue* right,
                                 VtSemiringValue* out_value);
extern uint32_t goVtSemiringTimes(uintptr_t context,
                                  const VtSemiringValue* left,
                                  const VtSemiringValue* right,
                                  VtSemiringValue* out_value);
extern uint32_t goVtSemiringEqual(uintptr_t context,
                                  const VtSemiringValue* left,
                                  const VtSemiringValue* right,
                                  uint8_t* out_equal);
extern uint32_t goVtSemiringApproxEqual(uintptr_t context,
                                        const VtSemiringValue* left,
                                        const VtSemiringValue* right,
                                        double epsilon,
                                        uint8_t* out_equal);
extern uint32_t goVtSemiringNaturalOrder(uintptr_t context,
                                         const VtSemiringValue* left,
                                         const VtSemiringValue* right,
                                         int32_t* out_order);
extern uint32_t goVtSemiringStableBytes(uintptr_t context,
                                        const VtSemiringValue* value,
                                        uint8_t* out_bytes, size_t capacity,
                                        size_t* out_written,
                                        size_t* out_required);
extern uint32_t goVtSemiringDiagnostic(uintptr_t context,
                                       const VtSemiringValue* value,
                                       uint8_t* out_bytes, size_t capacity,
                                       size_t* out_written,
                                       size_t* out_required);
extern uint32_t goVtSemiringPlusMany(uintptr_t context,
                                     const VtSemiringValue* values,
                                     size_t count,
                                     VtSemiringValue* out_value);
extern uint32_t goVtSemiringTimesMany(uintptr_t context,
                                      const VtSemiringValue* values,
                                      size_t count,
                                      VtSemiringValue* out_value);
extern uint32_t goVtSemiringDivide(uintptr_t context,
                                   const VtSemiringValue* dividend,
                                   const VtSemiringValue* divisor,
                                   VtSemiringValue* out_value);
extern uint32_t goVtSemiringLeftDivide(uintptr_t context,
                                       const VtSemiringValue* value,
                                       const VtSemiringValue* divisor,
                                       VtSemiringValue* out_value);
extern uint32_t goVtSemiringStar(uintptr_t context,
                                 const VtSemiringValue* value,
                                 VtSemiringValue* out_value);
extern uint32_t goVtSemiringNumericalValue(uintptr_t context,
                                           const VtSemiringValue* value,
                                           double* out_value);
extern uint32_t goVtSemiringQuantize(uintptr_t context,
                                     const VtSemiringValue* value,
                                     double epsilon,
                                     int64_t* out_value);
extern uint32_t goVtSemiringToProbability(uintptr_t context,
                                          const VtSemiringValue* value,
                                          double* out_value);
extern uint32_t goVtSemiringClosureBound(uintptr_t context,
                                         size_t* out_bound,
                                         uint8_t* out_known);

typedef struct VtGoTables {
    uint64_t capabilities;
    VtResourceVTable base;
    VtLatticeVTable lattice;
    VtWfstVTable wfst;
    VtSemiringVTable semiring;
    VtSemiringDivisionVTable semiring_division;
    VtSemiringStarVTable semiring_star;
    VtSemiringNumericVTable semiring_numeric;
    VtSemiringPropertiesVTable semiring_properties;
} VtGoTables;

typedef struct VtGoContext {
    uintptr_t handle;
    VtGoTables* tables;
} VtGoContext;

static uintptr_t vt_go_handle(void* context) {
    return ((VtGoContext*)context)->handle;
}

static void vt_go_retain(void* context) {
    goVtRetain(vt_go_handle(context));
}

static void vt_go_release(void* context) {
    VtGoContext* hosted = (VtGoContext*)context;
    if (goVtRelease(hosted->handle)) {
        free(hosted->tables);
        free(hosted);
    }
}

static VtStatus vt_go_query_interface(void* context,
                                      const VtInterfaceId* interface_id,
                                      uint32_t minimum_version,
                                      const void** out_vtable);

static VtStatus vt_go_lattice_join_cb(void* context,
                                      const VtResource* other,
                                      VtResource* out_value) {
    return (VtStatus)goVtLatticeJoin(vt_go_handle(context), other, out_value);
}

static VtStatus vt_go_lattice_meet_cb(void* context,
                                      const VtResource* other,
                                      VtResource* out_value) {
    return (VtStatus)goVtLatticeMeet(vt_go_handle(context), other, out_value);
}

static VtStatus vt_go_lattice_equal_cb(void* context,
                                       const VtResource* other,
                                       uint8_t* out_equal) {
    return (VtStatus)goVtLatticeEqual(vt_go_handle(context), other, out_equal);
}

static VtStatus vt_go_lattice_stable_bytes_cb(void* context,
                                               uint8_t* out_bytes,
                                               size_t capacity,
                                               size_t* out_written,
                                               size_t* out_required) {
    return (VtStatus)goVtLatticeStableBytes(vt_go_handle(context), out_bytes,
                                            capacity, out_written,
                                            out_required);
}

static VtStatus vt_go_lattice_diagnostic_cb(void* context,
                                             uint8_t* out_bytes,
                                             size_t capacity,
                                             size_t* out_written,
                                             size_t* out_required) {
    return (VtStatus)goVtLatticeDiagnostic(vt_go_handle(context), out_bytes,
                                           capacity, out_written,
                                           out_required);
}

static VtStatus vt_go_lattice_join_many_cb(void* context,
                                            const VtResource* others,
                                            size_t count,
                                            VtResource* out_value) {
    return (VtStatus)goVtLatticeJoinMany(vt_go_handle(context), others, count,
                                         out_value);
}

static VtStatus vt_go_lattice_meet_many_cb(void* context,
                                            const VtResource* others,
                                            size_t count,
                                            VtResource* out_value) {
    return (VtStatus)goVtLatticeMeetMany(vt_go_handle(context), others, count,
                                         out_value);
}

static VtStatus vt_go_wfst_snapshot_cb(void* context,
                                       VtResource* out_snapshot) {
    if (out_snapshot == NULL) return VT_STATUS_NULL_POINTER;
    VtGoContext* hosted = (VtGoContext*)context;
    vt_go_retain(context);
    out_snapshot->context = context;
    out_snapshot->vtable = &hosted->tables->base;
    return VT_STATUS_OK;
}

static VtStatus vt_go_wfst_start_cb(void* context, uint64_t* out_state) {
    return (VtStatus)goVtWfstStart(vt_go_handle(context), out_state);
}

static VtStatus vt_go_wfst_num_states_cb(void* context, size_t* out_count,
                                         uint8_t* out_known) {
    return (VtStatus)goVtWfstNumStates(vt_go_handle(context), out_count,
                                      out_known);
}

static VtStatus vt_go_wfst_state_info_cb(void* context, uint64_t state,
                                         uint8_t* out_valid,
                                         uint8_t* out_final,
                                         double* out_weight) {
    return (VtStatus)goVtWfstStateInfo(vt_go_handle(context), state, out_valid,
                                      out_final, out_weight);
}

static VtStatus vt_go_wfst_state_arcs_cb(void* context, uint64_t state,
                                         size_t start, VtWfstArc* out_arcs,
                                         size_t capacity,
                                         size_t* out_written,
                                         size_t* out_total) {
    return (VtStatus)goVtWfstStateArcs(vt_go_handle(context), state, start,
                                      out_arcs, capacity, out_written,
                                      out_total);
}

#define VT_GO_SEMIRING_BINARY_CALLBACK(name, go_name)                         \
    static VtStatus name(void* context, const VtSemiringValue* left,          \
                         const VtSemiringValue* right,                         \
                         VtSemiringValue* out_value) {                         \
        return (VtStatus)go_name(vt_go_handle(context), left, right,          \
                                 out_value);                                  \
    }

static VtStatus vt_go_semiring_zero_cb(void* context,
                                       VtSemiringValue* out_value) {
    return (VtStatus)goVtSemiringZero(vt_go_handle(context), out_value);
}

static VtStatus vt_go_semiring_one_cb(void* context,
                                      VtSemiringValue* out_value) {
    return (VtStatus)goVtSemiringOne(vt_go_handle(context), out_value);
}

static VtStatus vt_go_semiring_clone_cb(void* context,
                                        const VtSemiringValue* value,
                                        VtSemiringValue* out_value) {
    return (VtStatus)goVtSemiringClone(vt_go_handle(context), value, out_value);
}

static VtStatus vt_go_semiring_release_cb(void* context,
                                          VtSemiringValue* values,
                                          size_t count) {
    return (VtStatus)goVtSemiringRelease(vt_go_handle(context), values, count);
}

VT_GO_SEMIRING_BINARY_CALLBACK(vt_go_semiring_plus_cb, goVtSemiringPlus)
VT_GO_SEMIRING_BINARY_CALLBACK(vt_go_semiring_times_cb, goVtSemiringTimes)

static VtStatus vt_go_semiring_equal_cb(void* context,
                                        const VtSemiringValue* left,
                                        const VtSemiringValue* right,
                                        uint8_t* out_equal) {
    return (VtStatus)goVtSemiringEqual(vt_go_handle(context), left, right,
                                      out_equal);
}

static VtStatus vt_go_semiring_approx_equal_cb(
        void* context, const VtSemiringValue* left,
        const VtSemiringValue* right, double epsilon, uint8_t* out_equal) {
    return (VtStatus)goVtSemiringApproxEqual(vt_go_handle(context), left, right,
                                            epsilon, out_equal);
}

static VtStatus vt_go_semiring_natural_order_cb(
        void* context, const VtSemiringValue* left,
        const VtSemiringValue* right, int32_t* out_order) {
    return (VtStatus)goVtSemiringNaturalOrder(vt_go_handle(context), left, right,
                                             out_order);
}

static VtStatus vt_go_semiring_stable_bytes_cb(
        void* context, const VtSemiringValue* value, uint8_t* out_bytes,
        size_t capacity, size_t* out_written, size_t* out_required) {
    return (VtStatus)goVtSemiringStableBytes(
        vt_go_handle(context), value, out_bytes, capacity, out_written,
        out_required);
}

static VtStatus vt_go_semiring_diagnostic_cb(
        void* context, const VtSemiringValue* value, uint8_t* out_bytes,
        size_t capacity, size_t* out_written, size_t* out_required) {
    return (VtStatus)goVtSemiringDiagnostic(
        vt_go_handle(context), value, out_bytes, capacity, out_written,
        out_required);
}

static VtStatus vt_go_semiring_plus_many_cb(
        void* context, const VtSemiringValue* values, size_t count,
        VtSemiringValue* out_value) {
    return (VtStatus)goVtSemiringPlusMany(vt_go_handle(context), values, count,
                                         out_value);
}

static VtStatus vt_go_semiring_times_many_cb(
        void* context, const VtSemiringValue* values, size_t count,
        VtSemiringValue* out_value) {
    return (VtStatus)goVtSemiringTimesMany(vt_go_handle(context), values, count,
                                          out_value);
}

VT_GO_SEMIRING_BINARY_CALLBACK(vt_go_semiring_divide_cb, goVtSemiringDivide)
VT_GO_SEMIRING_BINARY_CALLBACK(vt_go_semiring_left_divide_cb,
                               goVtSemiringLeftDivide)

static VtStatus vt_go_semiring_star_cb(void* context,
                                       const VtSemiringValue* value,
                                       VtSemiringValue* out_value) {
    return (VtStatus)goVtSemiringStar(vt_go_handle(context), value, out_value);
}

static VtStatus vt_go_semiring_numerical_value_cb(
        void* context, const VtSemiringValue* value, double* out_value) {
    return (VtStatus)goVtSemiringNumericalValue(vt_go_handle(context), value,
                                               out_value);
}

static VtStatus vt_go_semiring_quantize_cb(void* context,
                                            const VtSemiringValue* value,
                                            double epsilon,
                                            int64_t* out_value) {
    return (VtStatus)goVtSemiringQuantize(vt_go_handle(context), value, epsilon,
                                         out_value);
}

static VtStatus vt_go_semiring_to_probability_cb(
        void* context, const VtSemiringValue* value, double* out_value) {
    return (VtStatus)goVtSemiringToProbability(vt_go_handle(context), value,
                                              out_value);
}

static VtStatus vt_go_semiring_closure_bound_cb(void* context,
                                                 size_t* out_bound,
                                                 uint8_t* out_known) {
    return (VtStatus)goVtSemiringClosureBound(vt_go_handle(context), out_bound,
                                             out_known);
}

static const VtResourceVTable VT_GO_RESOURCE_TEMPLATE = {
    sizeof(VtResourceVTable), VT_ABI_VERSION, 0, vt_go_retain, vt_go_release,
    vt_go_query_interface
};

static const VtLatticeVTable VT_GO_LATTICE_TEMPLATE = {
    sizeof(VtLatticeVTable), VT_LATTICE_INTERFACE_VERSION, 0, 0,
    {{0}}, vt_go_lattice_join_cb, vt_go_lattice_meet_cb,
    vt_go_lattice_equal_cb, vt_go_lattice_stable_bytes_cb,
    vt_go_lattice_diagnostic_cb, vt_go_lattice_join_many_cb,
    vt_go_lattice_meet_many_cb
};

static const VtWfstVTable VT_GO_WFST_TEMPLATE = {
    sizeof(VtWfstVTable), VT_WFST_INTERFACE_VERSION,
    VT_UNIT_DOMAIN_UNICODE_SCALAR, VT_WEIGHT_DOMAIN_TROPICAL_F64, 0, 0,
    vt_go_wfst_snapshot_cb, vt_go_wfst_start_cb, vt_go_wfst_num_states_cb,
    vt_go_wfst_state_info_cb, vt_go_wfst_state_arcs_cb
};

static const VtSemiringVTable VT_GO_SEMIRING_TEMPLATE = {
    sizeof(VtSemiringVTable), VT_SEMIRING_INTERFACE_VERSION, 0, 0, {{0}},
    vt_go_semiring_zero_cb, vt_go_semiring_one_cb, vt_go_semiring_clone_cb,
    vt_go_semiring_release_cb, vt_go_semiring_plus_cb,
    vt_go_semiring_times_cb, vt_go_semiring_equal_cb,
    vt_go_semiring_approx_equal_cb, vt_go_semiring_natural_order_cb,
    vt_go_semiring_stable_bytes_cb, vt_go_semiring_diagnostic_cb,
    vt_go_semiring_plus_many_cb, vt_go_semiring_times_many_cb
};

static const VtSemiringDivisionVTable VT_GO_SEMIRING_DIVISION_TEMPLATE = {
    sizeof(VtSemiringDivisionVTable), VT_SEMIRING_DIVISION_INTERFACE_VERSION,
    0, vt_go_semiring_divide_cb, vt_go_semiring_left_divide_cb
};

static const VtSemiringStarVTable VT_GO_SEMIRING_STAR_TEMPLATE = {
    sizeof(VtSemiringStarVTable), VT_SEMIRING_STAR_INTERFACE_VERSION, 0,
    vt_go_semiring_star_cb
};

static const VtSemiringNumericVTable VT_GO_SEMIRING_NUMERIC_TEMPLATE = {
    sizeof(VtSemiringNumericVTable), VT_SEMIRING_NUMERIC_INTERFACE_VERSION, 0,
    vt_go_semiring_numerical_value_cb, vt_go_semiring_quantize_cb,
    vt_go_semiring_to_probability_cb
};

static const VtSemiringPropertiesVTable VT_GO_SEMIRING_PROPERTIES_TEMPLATE = {
    sizeof(VtSemiringPropertiesVTable),
    VT_SEMIRING_PROPERTIES_INTERFACE_VERSION, 0, 0,
    vt_go_semiring_closure_bound_cb
};

static int vt_go_id_equal(const VtInterfaceId* left,
                          const VtInterfaceId* right) {
    return left != NULL && right != NULL &&
           memcmp(left->bytes, right->bytes, sizeof(left->bytes)) == 0;
}

static VtStatus vt_go_query_interface(void* context,
                                      const VtInterfaceId* interface_id,
                                      uint32_t minimum_version,
                                      const void** out_vtable) {
    if (interface_id == NULL || out_vtable == NULL) {
        return VT_STATUS_NULL_POINTER;
    }
    *out_vtable = NULL;
    const VtGoTables* tables = ((const VtGoContext*)context)->tables;
    const uint64_t capabilities = tables->capabilities;
    if (vt_go_id_equal(interface_id, &VT_LATTICE_INTERFACE_ID)) {
        if (minimum_version > VT_LATTICE_INTERFACE_VERSION ||
            !(capabilities & VT_GO_CAP_LATTICE)) return VT_STATUS_UNSUPPORTED;
        *out_vtable = &tables->lattice;
    } else if (vt_go_id_equal(interface_id, &VT_WFST_INTERFACE_ID)) {
        if (minimum_version > VT_WFST_INTERFACE_VERSION ||
            !(capabilities & VT_GO_CAP_WFST)) return VT_STATUS_UNSUPPORTED;
        *out_vtable = &tables->wfst;
    } else if (vt_go_id_equal(interface_id, &VT_SEMIRING_INTERFACE_ID)) {
        if (minimum_version > VT_SEMIRING_INTERFACE_VERSION ||
            !(capabilities & VT_GO_CAP_SEMIRING)) return VT_STATUS_UNSUPPORTED;
        *out_vtable = &tables->semiring;
    } else if (vt_go_id_equal(interface_id,
                              &VT_SEMIRING_DIVISION_INTERFACE_ID)) {
        if (minimum_version > VT_SEMIRING_DIVISION_INTERFACE_VERSION ||
            !(capabilities & VT_GO_CAP_SEMIRING_DIVISION))
            return VT_STATUS_UNSUPPORTED;
        *out_vtable = &tables->semiring_division;
    } else if (vt_go_id_equal(interface_id,
                              &VT_SEMIRING_STAR_INTERFACE_ID)) {
        if (minimum_version > VT_SEMIRING_STAR_INTERFACE_VERSION ||
            !(capabilities & VT_GO_CAP_SEMIRING_STAR))
            return VT_STATUS_UNSUPPORTED;
        *out_vtable = &tables->semiring_star;
    } else if (vt_go_id_equal(interface_id,
                              &VT_SEMIRING_NUMERIC_INTERFACE_ID)) {
        if (minimum_version > VT_SEMIRING_NUMERIC_INTERFACE_VERSION ||
            !(capabilities & VT_GO_CAP_SEMIRING_NUMERIC))
            return VT_STATUS_UNSUPPORTED;
        *out_vtable = &tables->semiring_numeric;
    } else if (vt_go_id_equal(interface_id,
                              &VT_SEMIRING_PROPERTIES_INTERFACE_ID)) {
        if (minimum_version > VT_SEMIRING_PROPERTIES_INTERFACE_VERSION ||
            !(capabilities & VT_GO_CAP_SEMIRING_PROPERTIES))
            return VT_STATUS_UNSUPPORTED;
        *out_vtable = &tables->semiring_properties;
    } else {
        return VT_STATUS_UNSUPPORTED;
    }
    return VT_STATUS_OK;
}

static VtResource vt_go_make_hosted_resource(uintptr_t handle,
                                              uint64_t capabilities) {
    VtResource resource = {NULL, NULL};
    VtGoTables* tables = (VtGoTables*)calloc(1, sizeof(VtGoTables));
    VtGoContext* context = (VtGoContext*)malloc(sizeof(VtGoContext));
    if (tables == NULL || context == NULL) {
        free(tables);
        free(context);
        return resource;
    }
    tables->capabilities = capabilities;
    tables->base = VT_GO_RESOURCE_TEMPLATE;
    tables->lattice = VT_GO_LATTICE_TEMPLATE;
    tables->wfst = VT_GO_WFST_TEMPLATE;
    tables->semiring = VT_GO_SEMIRING_TEMPLATE;
    tables->semiring_division = VT_GO_SEMIRING_DIVISION_TEMPLATE;
    tables->semiring_star = VT_GO_SEMIRING_STAR_TEMPLATE;
    tables->semiring_numeric = VT_GO_SEMIRING_NUMERIC_TEMPLATE;
    tables->semiring_properties = VT_GO_SEMIRING_PROPERTIES_TEMPLATE;
    context->handle = handle;
    context->tables = tables;
    resource.context = context;
    resource.vtable = &tables->base;
    return resource;
}

VtResource vt_go_make_lattice_resource(uintptr_t handle, uint64_t flags,
                                       VtInterfaceId domain) {
    VtResource resource =
        vt_go_make_hosted_resource(handle, VT_GO_CAP_LATTICE);
    if (resource.context != NULL) {
        VtGoTables* tables = ((VtGoContext*)resource.context)->tables;
        tables->lattice.flags = flags;
        tables->lattice.domain_id = domain;
    }
    return resource;
}

VtResource vt_go_make_wfst_resource(uintptr_t handle, VtUnitDomain unit,
                                    VtWeightDomain weight, uint64_t flags) {
    VtResource resource = vt_go_make_hosted_resource(handle, VT_GO_CAP_WFST);
    if (resource.context != NULL) {
        VtGoTables* tables = ((VtGoContext*)resource.context)->tables;
        tables->wfst.unit_domain = unit;
        tables->wfst.weight_domain = weight;
        tables->wfst.flags = flags;
    }
    return resource;
}

VtResource vt_go_make_semiring_resource(uintptr_t handle, uint64_t flags,
                                        VtInterfaceId domain,
                                        uint64_t capabilities,
                                        uint64_t properties) {
    VtResource resource = vt_go_make_hosted_resource(
        handle, capabilities | VT_GO_CAP_SEMIRING);
    if (resource.context != NULL) {
        VtGoTables* tables = ((VtGoContext*)resource.context)->tables;
        tables->semiring.flags = flags;
        tables->semiring.domain_id = domain;
        tables->semiring_properties.properties = properties;
    }
    return resource;
}

VtResource vt_go_resource_from_words(uintptr_t context, uintptr_t vtable) {
    VtResource resource = {(void*)context, (const VtResourceVTable*)vtable};
    return resource;
}

uintptr_t vt_go_resource_context(VtResource resource) {
    return (uintptr_t)resource.context;
}

uintptr_t vt_go_resource_vtable(VtResource resource) {
    return (uintptr_t)resource.vtable;
}

int vt_go_is_hosted_resource(VtResource resource) {
    return resource.context != NULL && resource.vtable != NULL &&
           resource.vtable->retain == vt_go_retain &&
           resource.vtable->release == vt_go_release &&
           resource.vtable->query_interface == vt_go_query_interface;
}

VtStatus vt_go_hosted_handle(VtResource resource, uintptr_t* out_handle) {
    if (out_handle == NULL) return VT_STATUS_NULL_POINTER;
    if (!vt_go_is_hosted_resource(resource)) return VT_STATUS_UNSUPPORTED;
    *out_handle = ((VtGoContext*)resource.context)->handle;
    return VT_STATUS_OK;
}

static VtStatus vt_go_validate_base(VtResource resource) {
    if (resource.context == NULL || resource.vtable == NULL) {
        return VT_STATUS_CLOSED;
    }
    if (resource.vtable->struct_size < sizeof(VtResourceVTable) ||
        resource.vtable->abi_version != VT_ABI_VERSION ||
        resource.vtable->reserved != 0 || resource.vtable->retain == NULL ||
        resource.vtable->release == NULL ||
        resource.vtable->query_interface == NULL) {
        return VT_STATUS_UNSUPPORTED;
    }
    return VT_STATUS_OK;
}

VtStatus vt_go_retain_resource(VtResource borrowed, VtResource* out_owned) {
    if (out_owned == NULL) return VT_STATUS_NULL_POINTER;
    const VtStatus status = vt_go_validate_base(borrowed);
    if (status != VT_STATUS_OK) return status;
    borrowed.vtable->retain(borrowed.context);
    *out_owned = borrowed;
    return VT_STATUS_OK;
}

void vt_go_release_resource(VtResource owned) {
    if (vt_go_validate_base(owned) == VT_STATUS_OK) {
        owned.vtable->release(owned.context);
    }
}

static VtStatus vt_go_discover(VtResource resource,
                               const VtInterfaceId* interface_id,
                               uint32_t version, size_t minimum_size,
                               const void** out_table) {
    if (out_table == NULL) return VT_STATUS_NULL_POINTER;
    *out_table = NULL;
    VtStatus status = vt_go_validate_base(resource);
    if (status != VT_STATUS_OK) return status;
    status = resource.vtable->query_interface(resource.context, interface_id,
                                              version, out_table);
    if (status != VT_STATUS_OK) return status;
    if (*out_table == NULL || *(const size_t*)*out_table < minimum_size) {
        *out_table = NULL;
        return VT_STATUS_UNSUPPORTED;
    }
    return VT_STATUS_OK;
}

static VtStatus vt_go_discover_lattice(VtResource resource,
                                       const VtLatticeVTable** out_table) {
    VtStatus status = vt_go_discover(resource, &VT_LATTICE_INTERFACE_ID,
                                     VT_LATTICE_INTERFACE_VERSION,
                                     sizeof(VtLatticeVTable),
                                     (const void**)out_table);
    if (status != VT_STATUS_OK) return status;
    const VtLatticeVTable* table = *out_table;
    if (table->interface_version < VT_LATTICE_INTERFACE_VERSION ||
        table->reserved != 0 || table->join == NULL || table->meet == NULL ||
        table->equal == NULL || table->diagnostic == NULL ||
        ((table->flags & VT_LATTICE_FLAG_STABLE_BYTES) &&
         table->stable_bytes == NULL) ||
        ((table->flags & VT_LATTICE_FLAG_BATCH) &&
         (table->join_many == NULL || table->meet_many == NULL))) {
        *out_table = NULL;
        return VT_STATUS_UNSUPPORTED;
    }
    return VT_STATUS_OK;
}

VtStatus vt_go_lattice_metadata(VtResource resource, uint64_t* out_flags,
                                VtInterfaceId* out_domain) {
    if (out_flags == NULL || out_domain == NULL) return VT_STATUS_NULL_POINTER;
    const VtLatticeVTable* table = NULL;
    VtStatus status = vt_go_discover_lattice(resource, &table);
    if (status != VT_STATUS_OK) return status;
    *out_flags = table->flags;
    *out_domain = table->domain_id;
    return VT_STATUS_OK;
}

#define VT_GO_LATTICE_BINARY(name, field)                                     \
    VtStatus name(VtResource left, VtResource right,                          \
                  VtResource* out_value) {                                    \
        if (out_value == NULL) return VT_STATUS_NULL_POINTER;                 \
        const VtLatticeVTable* table = NULL;                                  \
        VtStatus status = vt_go_discover_lattice(left, &table);               \
        if (status != VT_STATUS_OK) return status;                            \
        return table->field(left.context, &right, out_value);                 \
    }

VT_GO_LATTICE_BINARY(vt_go_lattice_join, join)
VT_GO_LATTICE_BINARY(vt_go_lattice_meet, meet)

VtStatus vt_go_lattice_equal(VtResource left, VtResource right,
                             uint8_t* out_equal) {
    if (out_equal == NULL) return VT_STATUS_NULL_POINTER;
    const VtLatticeVTable* table = NULL;
    VtStatus status = vt_go_discover_lattice(left, &table);
    if (status != VT_STATUS_OK) return status;
    return table->equal(left.context, &right, out_equal);
}

#define VT_GO_LATTICE_BYTES(name, field)                                      \
    VtStatus name(VtResource value, uint8_t* out_bytes, size_t capacity,      \
                  size_t* out_written, size_t* out_required) {                \
        const VtLatticeVTable* table = NULL;                                  \
        VtStatus status = vt_go_discover_lattice(value, &table);              \
        if (status != VT_STATUS_OK) return status;                            \
        if (table->field == NULL) return VT_STATUS_UNSUPPORTED;               \
        return table->field(value.context, out_bytes, capacity, out_written,  \
                            out_required);                                    \
    }

VT_GO_LATTICE_BYTES(vt_go_lattice_stable_bytes, stable_bytes)
VT_GO_LATTICE_BYTES(vt_go_lattice_diagnostic, diagnostic)

#define VT_GO_LATTICE_MANY(name, field)                                       \
    VtStatus name(VtResource value, const VtResource* others, size_t count,   \
                  VtResource* out_value) {                                    \
        const VtLatticeVTable* table = NULL;                                  \
        VtStatus status = vt_go_discover_lattice(value, &table);              \
        if (status != VT_STATUS_OK) return status;                            \
        if (table->field == NULL) return VT_STATUS_UNSUPPORTED;               \
        return table->field(value.context, others, count, out_value);         \
    }

VT_GO_LATTICE_MANY(vt_go_lattice_join_many, join_many)
VT_GO_LATTICE_MANY(vt_go_lattice_meet_many, meet_many)

static VtStatus vt_go_discover_wfst(VtResource resource,
                                    const VtWfstVTable** out_table) {
    VtStatus status = vt_go_discover(resource, &VT_WFST_INTERFACE_ID,
                                     VT_WFST_INTERFACE_VERSION,
                                     sizeof(VtWfstVTable),
                                     (const void**)out_table);
    if (status != VT_STATUS_OK) return status;
    const VtWfstVTable* table = *out_table;
    if (table->interface_version < VT_WFST_INTERFACE_VERSION ||
        table->reserved != 0 || table->snapshot == NULL ||
        table->start == NULL || table->num_states == NULL ||
        table->state_info == NULL || table->state_arcs == NULL) {
        *out_table = NULL;
        return VT_STATUS_UNSUPPORTED;
    }
    return VT_STATUS_OK;
}

VtStatus vt_go_wfst_metadata(VtResource resource, VtUnitDomain* out_unit,
                             VtWeightDomain* out_weight,
                             uint64_t* out_flags) {
    if (out_unit == NULL || out_weight == NULL || out_flags == NULL) {
        return VT_STATUS_NULL_POINTER;
    }
    const VtWfstVTable* table = NULL;
    VtStatus status = vt_go_discover_wfst(resource, &table);
    if (status != VT_STATUS_OK) return status;
    *out_unit = table->unit_domain;
    *out_weight = table->weight_domain;
    *out_flags = table->flags;
    return VT_STATUS_OK;
}

#define VT_GO_WFST_CALL(name, field, params, args)                             \
    VtStatus name params {                                                    \
        const VtWfstVTable* table = NULL;                                     \
        VtStatus status = vt_go_discover_wfst(resource, &table);              \
        if (status != VT_STATUS_OK) return status;                            \
        return table->field args;                                             \
    }

VT_GO_WFST_CALL(vt_go_wfst_snapshot, snapshot,
                 (VtResource resource, VtResource* out_snapshot),
                 (resource.context, out_snapshot))
VT_GO_WFST_CALL(vt_go_wfst_start, start,
                 (VtResource resource, uint64_t* out_state),
                 (resource.context, out_state))
VT_GO_WFST_CALL(vt_go_wfst_num_states, num_states,
                 (VtResource resource, size_t* out_count, uint8_t* out_known),
                 (resource.context, out_count, out_known))
VT_GO_WFST_CALL(vt_go_wfst_state_info, state_info,
                 (VtResource resource, uint64_t state, uint8_t* out_valid,
                  uint8_t* out_final, double* out_weight),
                 (resource.context, state, out_valid, out_final, out_weight))
VT_GO_WFST_CALL(vt_go_wfst_state_arcs, state_arcs,
                 (VtResource resource, uint64_t state, size_t start,
                  VtWfstArc* out_arcs, size_t capacity, size_t* out_written,
                  size_t* out_total),
                 (resource.context, state, start, out_arcs, capacity,
                  out_written, out_total))

static VtStatus vt_go_discover_semiring(VtResource resource,
                                        const VtSemiringVTable** out_table) {
    VtStatus status = vt_go_discover(resource, &VT_SEMIRING_INTERFACE_ID,
                                     VT_SEMIRING_INTERFACE_VERSION,
                                     sizeof(VtSemiringVTable),
                                     (const void**)out_table);
    if (status != VT_STATUS_OK) return status;
    const VtSemiringVTable* table = *out_table;
    if (table->interface_version < VT_SEMIRING_INTERFACE_VERSION ||
        table->reserved != 0 || table->zero == NULL || table->one == NULL ||
        table->clone_value == NULL || table->release_values == NULL ||
        table->plus == NULL || table->times == NULL || table->equal == NULL ||
        table->approx_equal == NULL || table->natural_order == NULL ||
        table->diagnostic == NULL || table->plus_many == NULL ||
        table->times_many == NULL ||
        ((table->flags & VT_SEMIRING_FLAG_STABLE_BYTES) &&
         table->stable_bytes == NULL)) {
        *out_table = NULL;
        return VT_STATUS_UNSUPPORTED;
    }
    return VT_STATUS_OK;
}

VtStatus vt_go_semiring_metadata(VtResource resource, uint64_t* out_flags,
                                 VtInterfaceId* out_domain) {
    if (out_flags == NULL || out_domain == NULL) return VT_STATUS_NULL_POINTER;
    const VtSemiringVTable* table = NULL;
    VtStatus status = vt_go_discover_semiring(resource, &table);
    if (status != VT_STATUS_OK) return status;
    *out_flags = table->flags;
    *out_domain = table->domain_id;
    return VT_STATUS_OK;
}

#define VT_GO_SEMIRING_CALL(name, field, params, args)                         \
    VtStatus name params {                                                    \
        const VtSemiringVTable* table = NULL;                                 \
        VtStatus status = vt_go_discover_semiring(resource, &table);          \
        if (status != VT_STATUS_OK) return status;                            \
        return table->field args;                                             \
    }

VT_GO_SEMIRING_CALL(vt_go_semiring_zero, zero,
                     (VtResource resource, VtSemiringValue* out_value),
                     (resource.context, out_value))
VT_GO_SEMIRING_CALL(vt_go_semiring_one, one,
                     (VtResource resource, VtSemiringValue* out_value),
                     (resource.context, out_value))
VT_GO_SEMIRING_CALL(vt_go_semiring_clone, clone_value,
                     (VtResource resource, const VtSemiringValue* value,
                      VtSemiringValue* out_value),
                     (resource.context, value, out_value))
VT_GO_SEMIRING_CALL(vt_go_semiring_release, release_values,
                     (VtResource resource, VtSemiringValue* values,
                      size_t count),
                     (resource.context, values, count))
VT_GO_SEMIRING_CALL(vt_go_semiring_plus, plus,
                     (VtResource resource, const VtSemiringValue* left,
                      const VtSemiringValue* right,
                      VtSemiringValue* out_value),
                     (resource.context, left, right, out_value))
VT_GO_SEMIRING_CALL(vt_go_semiring_times, times,
                     (VtResource resource, const VtSemiringValue* left,
                      const VtSemiringValue* right,
                      VtSemiringValue* out_value),
                     (resource.context, left, right, out_value))
VT_GO_SEMIRING_CALL(vt_go_semiring_equal, equal,
                     (VtResource resource, const VtSemiringValue* left,
                      const VtSemiringValue* right, uint8_t* out_equal),
                     (resource.context, left, right, out_equal))
VT_GO_SEMIRING_CALL(vt_go_semiring_approx_equal, approx_equal,
                     (VtResource resource, const VtSemiringValue* left,
                      const VtSemiringValue* right, double epsilon,
                      uint8_t* out_equal),
                     (resource.context, left, right, epsilon, out_equal))
VT_GO_SEMIRING_CALL(vt_go_semiring_natural_order, natural_order,
                     (VtResource resource, const VtSemiringValue* left,
                      const VtSemiringValue* right, int32_t* out_order),
                     (resource.context, left, right, out_order))
VT_GO_SEMIRING_CALL(vt_go_semiring_stable_bytes, stable_bytes,
                     (VtResource resource, const VtSemiringValue* value,
                      uint8_t* out_bytes, size_t capacity,
                      size_t* out_written, size_t* out_required),
                     (resource.context, value, out_bytes, capacity,
                      out_written, out_required))
VT_GO_SEMIRING_CALL(vt_go_semiring_diagnostic, diagnostic,
                     (VtResource resource, const VtSemiringValue* value,
                      uint8_t* out_bytes, size_t capacity,
                      size_t* out_written, size_t* out_required),
                     (resource.context, value, out_bytes, capacity,
                      out_written, out_required))
VT_GO_SEMIRING_CALL(vt_go_semiring_plus_many, plus_many,
                     (VtResource resource, const VtSemiringValue* values,
                      size_t count, VtSemiringValue* out_value),
                     (resource.context, values, count, out_value))
VT_GO_SEMIRING_CALL(vt_go_semiring_times_many, times_many,
                     (VtResource resource, const VtSemiringValue* values,
                      size_t count, VtSemiringValue* out_value),
                     (resource.context, values, count, out_value))

static VtStatus vt_go_discover_optional(VtResource resource,
                                        const VtInterfaceId* interface_id,
                                        uint32_t version, size_t size,
                                        const void** out_table) {
    return vt_go_discover(resource, interface_id, version, size, out_table);
}

#define VT_GO_OPTIONAL_BINARY(name, id, version, table_type, field)            \
    VtStatus name(VtResource resource, const VtSemiringValue* left,           \
                  const VtSemiringValue* right,                               \
                  VtSemiringValue* out_value) {                               \
        const table_type* table = NULL;                                       \
        VtStatus status = vt_go_discover_optional(                            \
            resource, &id, version, sizeof(table_type),                       \
            (const void**)&table);                                            \
        if (status != VT_STATUS_OK) return status;                            \
        if (table->reserved != 0 || table->field == NULL)                     \
            return VT_STATUS_UNSUPPORTED;                                     \
        return table->field(resource.context, left, right, out_value);        \
    }

VT_GO_OPTIONAL_BINARY(vt_go_semiring_divide,
                      VT_SEMIRING_DIVISION_INTERFACE_ID,
                      VT_SEMIRING_DIVISION_INTERFACE_VERSION,
                      VtSemiringDivisionVTable, divide)
VT_GO_OPTIONAL_BINARY(vt_go_semiring_left_divide,
                      VT_SEMIRING_DIVISION_INTERFACE_ID,
                      VT_SEMIRING_DIVISION_INTERFACE_VERSION,
                      VtSemiringDivisionVTable, left_divide)

VtStatus vt_go_semiring_star(VtResource resource,
                             const VtSemiringValue* value,
                             VtSemiringValue* out_value) {
    const VtSemiringStarVTable* table = NULL;
    VtStatus status = vt_go_discover_optional(
        resource, &VT_SEMIRING_STAR_INTERFACE_ID,
        VT_SEMIRING_STAR_INTERFACE_VERSION, sizeof(VtSemiringStarVTable),
        (const void**)&table);
    if (status != VT_STATUS_OK) return status;
    if (table->reserved != 0 || table->star == NULL)
        return VT_STATUS_UNSUPPORTED;
    return table->star(resource.context, value, out_value);
}

#define VT_GO_NUMERIC(name, field, output_type)                               \
    VtStatus name(VtResource resource, const VtSemiringValue* value,          \
                  output_type* out_value) {                                   \
        const VtSemiringNumericVTable* table = NULL;                          \
        VtStatus status = vt_go_discover_optional(                            \
            resource, &VT_SEMIRING_NUMERIC_INTERFACE_ID,                     \
            VT_SEMIRING_NUMERIC_INTERFACE_VERSION,                           \
            sizeof(VtSemiringNumericVTable), (const void**)&table);           \
        if (status != VT_STATUS_OK) return status;                            \
        if (table->reserved != 0 || table->field == NULL)                     \
            return VT_STATUS_UNSUPPORTED;                                     \
        return table->field(resource.context, value, out_value);              \
    }

VT_GO_NUMERIC(vt_go_semiring_numerical_value, numerical_value, double)
VT_GO_NUMERIC(vt_go_semiring_to_probability, to_probability, double)

VtStatus vt_go_semiring_quantize(VtResource resource,
                                 const VtSemiringValue* value,
                                 double epsilon, int64_t* out_value) {
    const VtSemiringNumericVTable* table = NULL;
    VtStatus status = vt_go_discover_optional(
        resource, &VT_SEMIRING_NUMERIC_INTERFACE_ID,
        VT_SEMIRING_NUMERIC_INTERFACE_VERSION,
        sizeof(VtSemiringNumericVTable), (const void**)&table);
    if (status != VT_STATUS_OK) return status;
    if (table->reserved != 0 || table->quantize == NULL)
        return VT_STATUS_UNSUPPORTED;
    return table->quantize(resource.context, value, epsilon, out_value);
}

VtStatus vt_go_semiring_properties(VtResource resource,
                                   uint64_t* out_properties) {
    if (out_properties == NULL) return VT_STATUS_NULL_POINTER;
    const VtSemiringPropertiesVTable* table = NULL;
    VtStatus status = vt_go_discover_optional(
        resource, &VT_SEMIRING_PROPERTIES_INTERFACE_ID,
        VT_SEMIRING_PROPERTIES_INTERFACE_VERSION,
        sizeof(VtSemiringPropertiesVTable), (const void**)&table);
    if (status != VT_STATUS_OK) return status;
    if (table->reserved != 0) return VT_STATUS_UNSUPPORTED;
    *out_properties = table->properties;
    return VT_STATUS_OK;
}

VtStatus vt_go_semiring_closure_bound(VtResource resource,
                                      size_t* out_bound,
                                      uint8_t* out_known) {
    const VtSemiringPropertiesVTable* table = NULL;
    VtStatus status = vt_go_discover_optional(
        resource, &VT_SEMIRING_PROPERTIES_INTERFACE_ID,
        VT_SEMIRING_PROPERTIES_INTERFACE_VERSION,
        sizeof(VtSemiringPropertiesVTable), (const void**)&table);
    if (status != VT_STATUS_OK) return status;
    if (table->reserved != 0 || table->closure_bound == NULL)
        return VT_STATUS_UNSUPPORTED;
    return table->closure_bound(resource.context, out_bound, out_known);
}

uint64_t vt_go_semiring_value_word0(const VtSemiringValue* value) {
    return value == NULL ? 0 : value->word0;
}

uint64_t vt_go_semiring_value_word1(const VtSemiringValue* value) {
    return value == NULL ? 0 : value->word1;
}

void vt_go_set_semiring_value(VtSemiringValue* value, uint64_t word0,
                              uint64_t word1) {
    if (value != NULL) {
        value->word0 = word0;
        value->word1 = word1;
    }
}

void vt_go_set_wfst_arc(VtWfstArc* arc, uint64_t input_label,
                        uint64_t output_label, uint64_t target_state,
                        double weight, uint8_t has_input,
                        uint8_t has_output) {
    if (arc == NULL) return;
    arc->input_label = input_label;
    arc->output_label = output_label;
    arc->target_state = target_state;
    arc->weight = weight;
    arc->has_input = has_input;
    arc->has_output = has_output;
    memset(arc->reserved, 0, sizeof(arc->reserved));
}
