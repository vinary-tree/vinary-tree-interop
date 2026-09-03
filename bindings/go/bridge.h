#ifndef VINARY_TREE_GO_BRIDGE_H
#define VINARY_TREE_GO_BRIDGE_H

#include "vinary_tree_interop.h"

#ifdef __cplusplus
extern "C" {
#endif

enum VtGoCapability {
    VT_GO_CAP_LATTICE = UINT64_C(1),
    VT_GO_CAP_WFST = UINT64_C(2),
    VT_GO_CAP_SEMIRING = UINT64_C(4),
    VT_GO_CAP_SEMIRING_DIVISION = UINT64_C(8),
    VT_GO_CAP_SEMIRING_STAR = UINT64_C(16),
    VT_GO_CAP_SEMIRING_NUMERIC = UINT64_C(32),
    VT_GO_CAP_SEMIRING_PROPERTIES = UINT64_C(64)
};

VtResource vt_go_make_lattice_resource(uintptr_t handle, uint64_t flags,
                                       VtInterfaceId domain);
VtResource vt_go_make_wfst_resource(uintptr_t handle, VtUnitDomain unit,
                                    VtWeightDomain weight, uint64_t flags);
VtResource vt_go_make_semiring_resource(uintptr_t handle, uint64_t flags,
                                        VtInterfaceId domain,
                                        uint64_t capabilities,
                                        uint64_t properties);
VtResource vt_go_resource_from_words(uintptr_t context, uintptr_t vtable);
uintptr_t vt_go_resource_context(VtResource resource);
uintptr_t vt_go_resource_vtable(VtResource resource);
int vt_go_is_hosted_resource(VtResource resource);
VtStatus vt_go_hosted_handle(VtResource resource, uintptr_t* out_handle);
VtStatus vt_go_retain_resource(VtResource borrowed, VtResource* out_owned);
void vt_go_release_resource(VtResource owned);

VtStatus vt_go_lattice_metadata(VtResource resource, uint64_t* out_flags,
                                VtInterfaceId* out_domain);
VtStatus vt_go_lattice_join(VtResource left, VtResource right,
                            VtResource* out_value);
VtStatus vt_go_lattice_meet(VtResource left, VtResource right,
                            VtResource* out_value);
VtStatus vt_go_lattice_equal(VtResource left, VtResource right,
                             uint8_t* out_equal);
VtStatus vt_go_lattice_stable_bytes(VtResource value, uint8_t* out_bytes,
                                    size_t capacity, size_t* out_written,
                                    size_t* out_required);
VtStatus vt_go_lattice_diagnostic(VtResource value, uint8_t* out_bytes,
                                  size_t capacity, size_t* out_written,
                                  size_t* out_required);
VtStatus vt_go_lattice_join_many(VtResource value,
                                 const VtResource* others, size_t count,
                                 VtResource* out_value);
VtStatus vt_go_lattice_meet_many(VtResource value,
                                 const VtResource* others, size_t count,
                                 VtResource* out_value);

VtStatus vt_go_wfst_metadata(VtResource resource, VtUnitDomain* out_unit,
                             VtWeightDomain* out_weight,
                             uint64_t* out_flags);
VtStatus vt_go_wfst_snapshot(VtResource resource, VtResource* out_snapshot);
VtStatus vt_go_wfst_start(VtResource resource, uint64_t* out_state);
VtStatus vt_go_wfst_num_states(VtResource resource, size_t* out_count,
                               uint8_t* out_known);
VtStatus vt_go_wfst_state_info(VtResource resource, uint64_t state,
                               uint8_t* out_valid, uint8_t* out_final,
                               double* out_weight);
VtStatus vt_go_wfst_state_arcs(VtResource resource, uint64_t state,
                               size_t start, VtWfstArc* out_arcs,
                               size_t capacity, size_t* out_written,
                               size_t* out_total);

VtStatus vt_go_semiring_metadata(VtResource resource, uint64_t* out_flags,
                                 VtInterfaceId* out_domain);
VtStatus vt_go_semiring_zero(VtResource resource, VtSemiringValue* out_value);
VtStatus vt_go_semiring_one(VtResource resource, VtSemiringValue* out_value);
VtStatus vt_go_semiring_clone(VtResource resource,
                              const VtSemiringValue* value,
                              VtSemiringValue* out_value);
VtStatus vt_go_semiring_release(VtResource resource, VtSemiringValue* values,
                                size_t count);
VtStatus vt_go_semiring_plus(VtResource resource,
                             const VtSemiringValue* left,
                             const VtSemiringValue* right,
                             VtSemiringValue* out_value);
VtStatus vt_go_semiring_times(VtResource resource,
                              const VtSemiringValue* left,
                              const VtSemiringValue* right,
                              VtSemiringValue* out_value);
VtStatus vt_go_semiring_equal(VtResource resource,
                              const VtSemiringValue* left,
                              const VtSemiringValue* right,
                              uint8_t* out_equal);
VtStatus vt_go_semiring_approx_equal(VtResource resource,
                                     const VtSemiringValue* left,
                                     const VtSemiringValue* right,
                                     double epsilon, uint8_t* out_equal);
VtStatus vt_go_semiring_natural_order(VtResource resource,
                                      const VtSemiringValue* left,
                                      const VtSemiringValue* right,
                                      int32_t* out_order);
VtStatus vt_go_semiring_stable_bytes(VtResource resource,
                                     const VtSemiringValue* value,
                                     uint8_t* out_bytes, size_t capacity,
                                     size_t* out_written,
                                     size_t* out_required);
VtStatus vt_go_semiring_diagnostic(VtResource resource,
                                   const VtSemiringValue* value,
                                   uint8_t* out_bytes, size_t capacity,
                                   size_t* out_written,
                                   size_t* out_required);
VtStatus vt_go_semiring_plus_many(VtResource resource,
                                  const VtSemiringValue* values,
                                  size_t count,
                                  VtSemiringValue* out_value);
VtStatus vt_go_semiring_times_many(VtResource resource,
                                   const VtSemiringValue* values,
                                   size_t count,
                                   VtSemiringValue* out_value);
VtStatus vt_go_semiring_divide(VtResource resource,
                               const VtSemiringValue* dividend,
                               const VtSemiringValue* divisor,
                               VtSemiringValue* out_value);
VtStatus vt_go_semiring_left_divide(VtResource resource,
                                    const VtSemiringValue* value,
                                    const VtSemiringValue* divisor,
                                    VtSemiringValue* out_value);
VtStatus vt_go_semiring_star(VtResource resource,
                             const VtSemiringValue* value,
                             VtSemiringValue* out_value);
VtStatus vt_go_semiring_numerical_value(VtResource resource,
                                        const VtSemiringValue* value,
                                        double* out_value);
VtStatus vt_go_semiring_quantize(VtResource resource,
                                 const VtSemiringValue* value,
                                 double epsilon, int64_t* out_value);
VtStatus vt_go_semiring_to_probability(VtResource resource,
                                       const VtSemiringValue* value,
                                       double* out_value);
VtStatus vt_go_semiring_properties(VtResource resource,
                                   uint64_t* out_properties);
VtStatus vt_go_semiring_closure_bound(VtResource resource,
                                      size_t* out_bound,
                                      uint8_t* out_known);

uint64_t vt_go_semiring_value_word0(const VtSemiringValue* value);
uint64_t vt_go_semiring_value_word1(const VtSemiringValue* value);
void vt_go_set_semiring_value(VtSemiringValue* value, uint64_t word0,
                              uint64_t word1);
void vt_go_set_wfst_arc(VtWfstArc* arc, uint64_t input_label,
                        uint64_t output_label, uint64_t target_state,
                        double weight, uint8_t has_input,
                        uint8_t has_output);

#ifdef __cplusplus
}
#endif

#endif
