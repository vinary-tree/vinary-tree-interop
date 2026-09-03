package interop

/*
#cgo CFLAGS: -std=c11 -Wall -Wextra -Werror
#include <stdlib.h>
#include "bridge.h"
*/
import "C"

import (
	"fmt"
	"unsafe"
)

const maximumProviderBytes = 16 * 1024 * 1024

func cResource(resource rawResource) C.VtResource {
	return C.vt_go_resource_from_words(C.uintptr_t(resource.context), C.uintptr_t(resource.vtable))
}

func goResource(resource C.VtResource) rawResource {
	return rawResource{
		context: uintptr(C.vt_go_resource_context(resource)),
		vtable:  uintptr(C.vt_go_resource_vtable(resource)),
	}
}

func cInterfaceID(identifier InterfaceID) C.VtInterfaceId {
	var result C.VtInterfaceId
	copy(unsafe.Slice((*byte)(unsafe.Pointer(&result)), len(identifier)), identifier[:])
	return result
}

func goInterfaceID(identifier C.VtInterfaceId) InterfaceID {
	var result InterfaceID
	copy(result[:], unsafe.Slice((*byte)(unsafe.Pointer(&identifier)), len(result)))
	return result
}

func abiRetainResource(resource rawResource) (rawResource, error) {
	var owned C.VtResource
	status := Status(C.vt_go_retain_resource(cResource(resource), &owned))
	if err := statusError("retain resource", status); err != nil {
		return rawResource{}, err
	}
	return goResource(owned), nil
}

func abiReleaseResource(resource rawResource) {
	if !resource.isNull() {
		C.vt_go_release_resource(cResource(resource))
	}
}

func abiHostedHandle(resource rawResource) (uintptr, bool) {
	var handle C.uintptr_t
	status := Status(C.vt_go_hosted_handle(cResource(resource), &handle))
	return uintptr(handle), status == StatusOK
}

func abiMakeLatticeResource(handle uintptr, flags LatticeFlags, domain InterfaceID) rawResource {
	return goResource(C.vt_go_make_lattice_resource(C.uintptr_t(handle), C.uint64_t(flags), cInterfaceID(domain)))
}

func abiMakeWfstResource(handle uintptr, unit UnitDomain, weight WeightDomain, flags WfstFlags) rawResource {
	return goResource(C.vt_go_make_wfst_resource(C.uintptr_t(handle), C.VtUnitDomain(unit), C.VtWeightDomain(weight), C.uint64_t(flags)))
}

func abiMakeSemiringResource(handle uintptr, flags SemiringFlags, domain InterfaceID, capabilities, properties uint64) rawResource {
	return goResource(C.vt_go_make_semiring_resource(C.uintptr_t(handle), C.uint64_t(flags), cInterfaceID(domain), C.uint64_t(capabilities), C.uint64_t(properties)))
}

func abiLatticeMetadata(resource rawResource) (LatticeFlags, InterfaceID, error) {
	var flags C.uint64_t
	var domain C.VtInterfaceId
	status := Status(C.vt_go_lattice_metadata(cResource(resource), &flags, &domain))
	if err := statusError("discover lattice", status); err != nil {
		return 0, InterfaceID{}, err
	}
	return LatticeFlags(flags), goInterfaceID(domain), nil
}

func abiLatticeBinary(operation string, left, right rawResource, meet bool) (rawResource, error) {
	var output C.VtResource
	var status Status
	if meet {
		status = Status(C.vt_go_lattice_meet(cResource(left), cResource(right), &output))
	} else {
		status = Status(C.vt_go_lattice_join(cResource(left), cResource(right), &output))
	}
	if err := statusError(operation, status); err != nil {
		return rawResource{}, err
	}
	result := goResource(output)
	if result.isNull() {
		return rawResource{}, &Error{Operation: operation, Status: StatusProviderError, Cause: fmt.Errorf("provider returned a null successful result")}
	}
	return result, nil
}

func abiLatticeEqual(left, right rawResource) (bool, error) {
	var equal C.uint8_t
	status := Status(C.vt_go_lattice_equal(cResource(left), cResource(right), &equal))
	if err := statusError("compare lattice values", status); err != nil {
		return false, err
	}
	if equal > 1 {
		return false, &Error{Operation: "compare lattice values", Status: StatusProviderError, Cause: fmt.Errorf("provider returned non-boolean equality %d", equal)}
	}
	return equal == 1, nil
}

func abiLatticeBytes(resource rawResource, diagnostic bool) ([]byte, error) {
	operation := "read lattice stable bytes"
	if diagnostic {
		operation = "read lattice diagnostic"
	}
	return abiReadBytes(operation, func(output *C.uint8_t, capacity C.size_t, written, required *C.size_t) Status {
		if diagnostic {
			return Status(C.vt_go_lattice_diagnostic(cResource(resource), output, capacity, written, required))
		}
		return Status(C.vt_go_lattice_stable_bytes(cResource(resource), output, capacity, written, required))
	})
}

func cResourceArray(resources []rawResource) (*C.VtResource, func(), error) {
	if len(resources) == 0 {
		return nil, func() {}, nil
	}
	size := uintptr(len(resources)) * unsafe.Sizeof(C.VtResource{})
	if size/unsafe.Sizeof(C.VtResource{}) != uintptr(len(resources)) {
		return nil, nil, &Error{Operation: "allocate resource batch", Status: StatusLimitExceeded}
	}
	memory := C.malloc(C.size_t(size))
	if memory == nil {
		return nil, nil, &Error{Operation: "allocate resource batch", Status: StatusLimitExceeded}
	}
	array := unsafe.Slice((*C.VtResource)(memory), len(resources))
	for index, resource := range resources {
		array[index] = cResource(resource)
	}
	return (*C.VtResource)(memory), func() { C.free(memory) }, nil
}

func abiLatticeMany(operation string, receiver rawResource, others []rawResource, meet bool) (rawResource, error) {
	array, release, err := cResourceArray(others)
	if err != nil {
		return rawResource{}, err
	}
	defer release()
	var output C.VtResource
	var status Status
	if meet {
		status = Status(C.vt_go_lattice_meet_many(cResource(receiver), array, C.size_t(len(others)), &output))
	} else {
		status = Status(C.vt_go_lattice_join_many(cResource(receiver), array, C.size_t(len(others)), &output))
	}
	if err := statusError(operation, status); err != nil {
		return rawResource{}, err
	}
	result := goResource(output)
	if result.isNull() {
		return rawResource{}, &Error{Operation: operation, Status: StatusProviderError, Cause: fmt.Errorf("provider returned a null successful result")}
	}
	return result, nil
}

func abiWfstMetadata(resource rawResource) (UnitDomain, WeightDomain, WfstFlags, error) {
	var unit C.VtUnitDomain
	var weight C.VtWeightDomain
	var flags C.uint64_t
	status := Status(C.vt_go_wfst_metadata(cResource(resource), &unit, &weight, &flags))
	if err := statusError("discover scalar WFST", status); err != nil {
		return 0, 0, 0, err
	}
	return UnitDomain(unit), WeightDomain(weight), WfstFlags(flags), nil
}

func abiWfstSnapshot(resource rawResource) (rawResource, error) {
	var output C.VtResource
	status := Status(C.vt_go_wfst_snapshot(cResource(resource), &output))
	if err := statusError("capture scalar WFST snapshot", status); err != nil {
		return rawResource{}, err
	}
	result := goResource(output)
	if result.isNull() {
		return rawResource{}, &Error{Operation: "capture scalar WFST snapshot", Status: StatusProviderError, Cause: fmt.Errorf("provider returned a null successful snapshot")}
	}
	return result, nil
}

func abiWfstStart(resource rawResource) (uint64, error) {
	var state C.uint64_t
	status := Status(C.vt_go_wfst_start(cResource(resource), &state))
	return uint64(state), statusError("read scalar WFST start state", status)
}

func abiWfstStateCount(resource rawResource) (uint64, bool, error) {
	var count C.size_t
	var known C.uint8_t
	status := Status(C.vt_go_wfst_num_states(cResource(resource), &count, &known))
	if err := statusError("read scalar WFST state count", status); err != nil {
		return 0, false, err
	}
	if known > 1 {
		return 0, false, &Error{Operation: "read scalar WFST state count", Status: StatusProviderError, Cause: fmt.Errorf("provider returned non-boolean known flag %d", known)}
	}
	return uint64(count), known == 1, nil
}

func abiWfstStateInfo(resource rawResource, state uint64) (bool, bool, float64, error) {
	var valid, final C.uint8_t
	var weight C.double
	status := Status(C.vt_go_wfst_state_info(cResource(resource), C.uint64_t(state), &valid, &final, &weight))
	if err := statusError("read scalar WFST state metadata", status); err != nil {
		return false, false, 0, err
	}
	if valid > 1 || final > 1 {
		return false, false, 0, &Error{Operation: "read scalar WFST state metadata", Status: StatusProviderError, Cause: fmt.Errorf("provider returned non-boolean state flags")}
	}
	return valid == 1, final == 1, float64(weight), nil
}

func abiWfstArcPage(resource rawResource, state, start uint64, capacity int) ([]WfstArc, uint64, error) {
	if capacity <= 0 {
		return nil, 0, &Error{Operation: "read scalar WFST arc page", Status: StatusInvalidArgument}
	}
	page := make([]C.VtWfstArc, capacity)
	var written, total C.size_t
	status := Status(C.vt_go_wfst_state_arcs(
		cResource(resource), C.uint64_t(state), C.size_t(start), &page[0],
		C.size_t(capacity), &written, &total,
	))
	if err := statusError("read scalar WFST arc page", status); err != nil {
		return nil, 0, err
	}
	if uint64(written) > uint64(capacity) || uint64(start) > uint64(total) || uint64(start)+uint64(written) > uint64(total) {
		return nil, 0, &Error{Operation: "read scalar WFST arc page", Status: StatusProviderError, Cause: fmt.Errorf("provider returned inconsistent page bounds")}
	}
	result := make([]WfstArc, int(written))
	for index := range result {
		raw := page[index]
		if raw.has_input > 1 || raw.has_output > 1 {
			return nil, 0, &Error{Operation: "read scalar WFST arc page", Status: StatusProviderError, Cause: fmt.Errorf("provider returned non-boolean epsilon flags")}
		}
		result[index] = WfstArc{
			Input:     uint64(raw.input_label),
			Output:    uint64(raw.output_label),
			Target:    uint64(raw.target_state),
			Weight:    float64(raw.weight),
			HasInput:  raw.has_input == 1,
			HasOutput: raw.has_output == 1,
		}
	}
	return result, uint64(total), nil
}

func abiReadBytes(operation string, callback func(*C.uint8_t, C.size_t, *C.size_t, *C.size_t) Status) ([]byte, error) {
	var written, required C.size_t
	if err := statusError(operation, callback(nil, 0, &written, &required)); err != nil {
		return nil, err
	}
	if written != 0 || uint64(required) > maximumProviderBytes {
		return nil, &Error{Operation: operation, Status: StatusLimitExceeded, Cause: fmt.Errorf("provider requested %d bytes and wrote %d during sizing", required, written)}
	}
	if required == 0 {
		return []byte{}, nil
	}
	result := make([]byte, int(required))
	written = 0
	confirmed := C.size_t(^uintptr(0))
	if err := statusError(operation, callback((*C.uint8_t)(unsafe.Pointer(&result[0])), C.size_t(len(result)), &written, &confirmed)); err != nil {
		return nil, err
	}
	if written != required || confirmed != required {
		return nil, &Error{Operation: operation, Status: StatusProviderError, Cause: fmt.Errorf("provider byte size changed from %d to written=%d required=%d", required, written, confirmed)}
	}
	return result, nil
}

type abiSemiringValue struct {
	word0 uint64
	word1 uint64
}

func cSemiringValue(value abiSemiringValue) C.VtSemiringValue {
	var result C.VtSemiringValue
	C.vt_go_set_semiring_value(&result, C.uint64_t(value.word0), C.uint64_t(value.word1))
	return result
}

func goSemiringValue(value C.VtSemiringValue) abiSemiringValue {
	return abiSemiringValue{
		word0: uint64(C.vt_go_semiring_value_word0(&value)),
		word1: uint64(C.vt_go_semiring_value_word1(&value)),
	}
}

func abiSemiringMetadata(resource rawResource) (SemiringFlags, InterfaceID, error) {
	var flags C.uint64_t
	var domain C.VtInterfaceId
	status := Status(C.vt_go_semiring_metadata(cResource(resource), &flags, &domain))
	if err := statusError("discover semiring", status); err != nil {
		return 0, InterfaceID{}, err
	}
	return SemiringFlags(flags), goInterfaceID(domain), nil
}

func abiSemiringNullary(operation string, resource rawResource, one bool) (abiSemiringValue, error) {
	var output C.VtSemiringValue
	var status Status
	if one {
		status = Status(C.vt_go_semiring_one(cResource(resource), &output))
	} else {
		status = Status(C.vt_go_semiring_zero(cResource(resource), &output))
	}
	if err := statusError(operation, status); err != nil {
		return abiSemiringValue{}, err
	}
	return goSemiringValue(output), nil
}

func abiSemiringClone(resource rawResource, value abiSemiringValue) (abiSemiringValue, error) {
	input := cSemiringValue(value)
	var output C.VtSemiringValue
	status := Status(C.vt_go_semiring_clone(cResource(resource), &input, &output))
	if err := statusError("clone semiring value", status); err != nil {
		return abiSemiringValue{}, err
	}
	return goSemiringValue(output), nil
}

func abiSemiringRelease(resource rawResource, values []abiSemiringValue) error {
	if len(values) == 0 {
		return nil
	}
	array := make([]C.VtSemiringValue, len(values))
	for index, value := range values {
		array[index] = cSemiringValue(value)
	}
	status := Status(C.vt_go_semiring_release(cResource(resource), &array[0], C.size_t(len(array))))
	return statusError("release semiring values", status)
}

func abiSemiringBinary(operation string, resource rawResource, left, right abiSemiringValue, kind string) (abiSemiringValue, bool, error) {
	leftRaw, rightRaw := cSemiringValue(left), cSemiringValue(right)
	var output C.VtSemiringValue
	var status Status
	switch kind {
	case "plus":
		status = Status(C.vt_go_semiring_plus(cResource(resource), &leftRaw, &rightRaw, &output))
	case "times":
		status = Status(C.vt_go_semiring_times(cResource(resource), &leftRaw, &rightRaw, &output))
	case "divide":
		status = Status(C.vt_go_semiring_divide(cResource(resource), &leftRaw, &rightRaw, &output))
	case "left-divide":
		status = Status(C.vt_go_semiring_left_divide(cResource(resource), &leftRaw, &rightRaw, &output))
	default:
		return abiSemiringValue{}, false, &Error{Operation: operation, Status: StatusInvalidArgument}
	}
	if status == StatusEnd {
		return abiSemiringValue{}, false, nil
	}
	if err := statusError(operation, status); err != nil {
		return abiSemiringValue{}, false, err
	}
	return goSemiringValue(output), true, nil
}

func abiSemiringBool(operation string, resource rawResource, left, right abiSemiringValue, epsilon *float64) (bool, error) {
	leftRaw, rightRaw := cSemiringValue(left), cSemiringValue(right)
	var output C.uint8_t
	var status Status
	if epsilon == nil {
		status = Status(C.vt_go_semiring_equal(cResource(resource), &leftRaw, &rightRaw, &output))
	} else {
		status = Status(C.vt_go_semiring_approx_equal(cResource(resource), &leftRaw, &rightRaw, C.double(*epsilon), &output))
	}
	if err := statusError(operation, status); err != nil {
		return false, err
	}
	if output > 1 {
		return false, &Error{Operation: operation, Status: StatusProviderError, Cause: fmt.Errorf("provider returned non-boolean result %d", output)}
	}
	return output == 1, nil
}

func abiSemiringNaturalOrder(resource rawResource, left, right abiSemiringValue) (NaturalOrder, error) {
	leftRaw, rightRaw := cSemiringValue(left), cSemiringValue(right)
	var output C.int32_t
	status := Status(C.vt_go_semiring_natural_order(cResource(resource), &leftRaw, &rightRaw, &output))
	if err := statusError("compare semiring natural order", status); err != nil {
		return 0, err
	}
	result := NaturalOrder(output)
	if !result.valid() {
		return 0, &Error{Operation: "compare semiring natural order", Status: StatusProviderError, Cause: fmt.Errorf("provider returned unknown natural order %d", output)}
	}
	return result, nil
}

func abiSemiringBytes(resource rawResource, value abiSemiringValue, diagnostic bool) ([]byte, error) {
	raw := cSemiringValue(value)
	operation := "read semiring stable bytes"
	if diagnostic {
		operation = "read semiring diagnostic"
	}
	return abiReadBytes(operation, func(output *C.uint8_t, capacity C.size_t, written, required *C.size_t) Status {
		if diagnostic {
			return Status(C.vt_go_semiring_diagnostic(cResource(resource), &raw, output, capacity, written, required))
		}
		return Status(C.vt_go_semiring_stable_bytes(cResource(resource), &raw, output, capacity, written, required))
	})
}

func abiSemiringMany(operation string, resource rawResource, values []abiSemiringValue, times bool) (abiSemiringValue, error) {
	array := make([]C.VtSemiringValue, len(values))
	for index, value := range values {
		array[index] = cSemiringValue(value)
	}
	var pointer *C.VtSemiringValue
	if len(array) != 0 {
		pointer = &array[0]
	}
	var output C.VtSemiringValue
	var status Status
	if times {
		status = Status(C.vt_go_semiring_times_many(cResource(resource), pointer, C.size_t(len(array)), &output))
	} else {
		status = Status(C.vt_go_semiring_plus_many(cResource(resource), pointer, C.size_t(len(array)), &output))
	}
	if err := statusError(operation, status); err != nil {
		return abiSemiringValue{}, err
	}
	return goSemiringValue(output), nil
}

func abiSemiringStar(resource rawResource, value abiSemiringValue) (abiSemiringValue, bool, error) {
	raw := cSemiringValue(value)
	var output C.VtSemiringValue
	status := Status(C.vt_go_semiring_star(cResource(resource), &raw, &output))
	if status == StatusEnd {
		return abiSemiringValue{}, false, nil
	}
	if err := statusError("close semiring value", status); err != nil {
		return abiSemiringValue{}, false, err
	}
	return goSemiringValue(output), true, nil
}

func abiSemiringNumeric(operation string, resource rawResource, value abiSemiringValue, kind string, epsilon float64) (float64, int64, error) {
	raw := cSemiringValue(value)
	switch kind {
	case "value":
		var output C.double
		status := Status(C.vt_go_semiring_numerical_value(cResource(resource), &raw, &output))
		return float64(output), 0, statusError(operation, status)
	case "probability":
		var output C.double
		status := Status(C.vt_go_semiring_to_probability(cResource(resource), &raw, &output))
		return float64(output), 0, statusError(operation, status)
	case "quantize":
		var output C.int64_t
		status := Status(C.vt_go_semiring_quantize(cResource(resource), &raw, C.double(epsilon), &output))
		return 0, int64(output), statusError(operation, status)
	default:
		return 0, 0, &Error{Operation: operation, Status: StatusInvalidArgument}
	}
}

func abiSemiringProperties(resource rawResource) (SemiringProperties, error) {
	var properties C.uint64_t
	status := Status(C.vt_go_semiring_properties(cResource(resource), &properties))
	return SemiringProperties(properties), statusError("read semiring properties", status)
}

func abiSemiringClosureBound(resource rawResource) (uint64, bool, error) {
	var bound C.size_t
	var known C.uint8_t
	status := Status(C.vt_go_semiring_closure_bound(cResource(resource), &bound, &known))
	if err := statusError("read semiring closure bound", status); err != nil {
		return 0, false, err
	}
	if known > 1 {
		return 0, false, &Error{Operation: "read semiring closure bound", Status: StatusProviderError, Cause: fmt.Errorf("provider returned non-boolean known flag %d", known)}
	}
	return uint64(bound), known == 1, nil
}
