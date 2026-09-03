package interop

/*
#include <stddef.h>
#include <stdint.h>

typedef struct VtResource {
    void* context;
    const void* vtable;
} VtResource;

typedef struct VtWfstArc {
    uint64_t input_label;
    uint64_t output_label;
    uint64_t target_state;
    double weight;
    uint8_t has_input;
    uint8_t has_output;
    uint8_t reserved[6];
} VtWfstArc;

typedef struct VtSemiringValue {
    uint64_t word0;
    uint64_t word1;
} VtSemiringValue;

VtResource vt_go_resource_from_words(uintptr_t context, uintptr_t vtable);
void vt_go_set_wfst_arc(VtWfstArc* arc, uint64_t input_label,
                        uint64_t output_label, uint64_t target_state,
                        double weight, uint8_t has_input,
                        uint8_t has_output);
*/
import "C"

import (
	"math"
	"unicode/utf8"
	"unsafe"
)

func callbackStatus(status Status) C.uint32_t { return C.uint32_t(status) }

func callbackContext(handle C.uintptr_t, capability uint64) (*hostedContext, Status) {
	context, ok := hostedFromHandle(uintptr(handle))
	if !ok || context.capabilities&capability == 0 {
		return nil, StatusClosed
	}
	return context, StatusOK
}

func callbackRawResource(resource C.VtResource) rawResource {
	return rawResource{context: uintptr(resource.context), vtable: uintptr(resource.vtable)}
}

func callbackCResource(resource rawResource) C.VtResource {
	return C.vt_go_resource_from_words(C.uintptr_t(resource.context), C.uintptr_t(resource.vtable))
}

func callbackSemiringValue(value C.VtSemiringValue) abiSemiringValue {
	return abiSemiringValue{word0: uint64(value.word0), word1: uint64(value.word1)}
}

func callbackCSemiringValue(value abiSemiringValue) C.VtSemiringValue {
	return C.VtSemiringValue{word0: C.uint64_t(value.word0), word1: C.uint64_t(value.word1)}
}

func callbackBytes(data []byte, output *C.uint8_t, capacity C.size_t, written, required *C.size_t) Status {
	if written == nil || required == nil {
		return StatusNullPointer
	}
	if len(data) > maximumProviderBytes {
		return StatusLimitExceeded
	}
	if capacity > 0 && output == nil {
		return StatusNullPointer
	}
	*written = 0
	*required = C.size_t(len(data))
	if uint64(capacity) < uint64(len(data)) || len(data) == 0 {
		return StatusOK
	}
	copy(unsafe.Slice((*byte)(unsafe.Pointer(output)), len(data)), data)
	*written = C.size_t(len(data))
	return StatusOK
}

func callbackResourceSlice(values *C.VtResource, count C.size_t, limit uint64) ([]rawResource, Status) {
	length := uint64(count)
	if length > limit || length > uint64(int(^uint(0)>>1)) {
		return nil, StatusLimitExceeded
	}
	if length == 0 {
		return []rawResource{}, StatusOK
	}
	if values == nil {
		return nil, StatusNullPointer
	}
	foreign := unsafe.Slice(values, int(length))
	resources := make([]rawResource, len(foreign))
	for index, resource := range foreign {
		resources[index] = callbackRawResource(resource)
	}
	return resources, StatusOK
}

func callbackSemiringSlice(values *C.VtSemiringValue, count C.size_t, limit uint64) ([]abiSemiringValue, Status) {
	length := uint64(count)
	if length > limit || length > uint64(int(^uint(0)>>1)) {
		return nil, StatusLimitExceeded
	}
	if length == 0 {
		return []abiSemiringValue{}, StatusOK
	}
	if values == nil {
		return nil, StatusNullPointer
	}
	foreign := unsafe.Slice(values, int(length))
	tokens := make([]abiSemiringValue, len(foreign))
	for index, value := range foreign {
		tokens[index] = callbackSemiringValue(value)
	}
	return tokens, StatusOK
}

//export goVtRetain
func goVtRetain(handle C.uintptr_t) {
	defer func() { _ = recover() }()
	if context, ok := hostedFromHandle(uintptr(handle)); ok {
		context.retain()
	}
}

//export goVtRelease
func goVtRelease(handle C.uintptr_t) (released C.uint8_t) {
	defer func() {
		if recover() != nil {
			released = 0
		}
	}()
	context, ok := hostedFromHandle(uintptr(handle))
	if ok && context.release() {
		return 1
	}
	return 0
}

func latticeCallback(handle C.uintptr_t, operation func(*latticeHost) Status) Status {
	context, status := callbackContext(handle, capabilityLattice)
	if status != StatusOK || context.lattice == nil {
		return StatusClosed
	}
	return context.lattice.gate.invoke(func() Status { return operation(context.lattice) })
}

func latticeBinaryCallback(handle C.uintptr_t, other *C.VtResource, output *C.VtResource, meet bool) C.uint32_t {
	if other == nil || output == nil {
		return callbackStatus(StatusNullPointer)
	}
	status := latticeCallback(handle, func(host *latticeHost) Status {
		result, err := host.binary(callbackRawResource(*other), meet)
		if err != nil {
			return statusFromError(err)
		}
		*output = callbackCResource(result)
		return StatusOK
	})
	return callbackStatus(status)
}

//export goVtLatticeJoin
func goVtLatticeJoin(handle C.uintptr_t, other *C.VtResource, output *C.VtResource) C.uint32_t {
	return latticeBinaryCallback(handle, other, output, false)
}

//export goVtLatticeMeet
func goVtLatticeMeet(handle C.uintptr_t, other *C.VtResource, output *C.VtResource) C.uint32_t {
	return latticeBinaryCallback(handle, other, output, true)
}

//export goVtLatticeEqual
func goVtLatticeEqual(handle C.uintptr_t, other *C.VtResource, output *C.uint8_t) C.uint32_t {
	if other == nil || output == nil {
		return callbackStatus(StatusNullPointer)
	}
	status := latticeCallback(handle, func(host *latticeHost) Status {
		equal, err := host.equal(callbackRawResource(*other))
		if err != nil {
			return statusFromError(err)
		}
		if equal {
			*output = 1
		} else {
			*output = 0
		}
		return StatusOK
	})
	return callbackStatus(status)
}

func latticeBytesCallback(handle C.uintptr_t, output *C.uint8_t, capacity C.size_t, written, required *C.size_t, diagnostic bool) C.uint32_t {
	status := latticeCallback(handle, func(host *latticeHost) Status {
		var data []byte
		var err error
		if diagnostic {
			var text string
			text, err = host.provider.Diagnostic()
			if err == nil && !utf8.ValidString(text) {
				err = &Error{Operation: "encode lattice diagnostic", Status: StatusProviderError}
			}
			data = []byte(text)
		} else {
			provider, ok := host.provider.(StableLatticeProvider)
			if !ok {
				return StatusUnsupported
			}
			data, err = provider.StableBytes()
		}
		if err != nil {
			return statusFromError(err)
		}
		return callbackBytes(data, output, capacity, written, required)
	})
	return callbackStatus(status)
}

//export goVtLatticeStableBytes
func goVtLatticeStableBytes(handle C.uintptr_t, output *C.uint8_t, capacity C.size_t, written, required *C.size_t) C.uint32_t {
	return latticeBytesCallback(handle, output, capacity, written, required, false)
}

//export goVtLatticeDiagnostic
func goVtLatticeDiagnostic(handle C.uintptr_t, output *C.uint8_t, capacity C.size_t, written, required *C.size_t) C.uint32_t {
	return latticeBytesCallback(handle, output, capacity, written, required, true)
}

func latticeManyCallback(handle C.uintptr_t, others *C.VtResource, count C.size_t, output *C.VtResource, meet bool) C.uint32_t {
	if output == nil {
		return callbackStatus(StatusNullPointer)
	}
	resources, status := callbackResourceSlice(others, count, maximumLatticeBatch)
	if status != StatusOK {
		return callbackStatus(status)
	}
	status = latticeCallback(handle, func(host *latticeHost) Status {
		result, err := host.many(resources, meet)
		if err != nil {
			return statusFromError(err)
		}
		*output = callbackCResource(result)
		return StatusOK
	})
	return callbackStatus(status)
}

//export goVtLatticeJoinMany
func goVtLatticeJoinMany(handle C.uintptr_t, others *C.VtResource, count C.size_t, output *C.VtResource) C.uint32_t {
	return latticeManyCallback(handle, others, count, output, false)
}

//export goVtLatticeMeetMany
func goVtLatticeMeetMany(handle C.uintptr_t, others *C.VtResource, count C.size_t, output *C.VtResource) C.uint32_t {
	return latticeManyCallback(handle, others, count, output, true)
}

func wfstCallback(handle C.uintptr_t, operation func(*wfstHost) Status) Status {
	context, status := callbackContext(handle, capabilityWfst)
	if status != StatusOK || context.wfst == nil {
		return StatusClosed
	}
	return context.wfst.gate.invoke(func() Status { return operation(context.wfst) })
}

//export goVtWfstStart
func goVtWfstStart(handle C.uintptr_t, output *C.uint64_t) C.uint32_t {
	if output == nil {
		return callbackStatus(StatusNullPointer)
	}
	status := wfstCallback(handle, func(host *wfstHost) Status {
		state, err := host.provider.StartState()
		if err != nil {
			return statusFromError(err)
		}
		*output = C.uint64_t(state)
		return StatusOK
	})
	return callbackStatus(status)
}

//export goVtWfstNumStates
func goVtWfstNumStates(handle C.uintptr_t, output *C.size_t, known *C.uint8_t) C.uint32_t {
	if output == nil || known == nil {
		return callbackStatus(StatusNullPointer)
	}
	status := wfstCallback(handle, func(host *wfstHost) Status {
		count, isKnown, err := host.provider.StateCount()
		if err != nil {
			return statusFromError(err)
		}
		converted := C.size_t(count)
		if uint64(converted) != count {
			return StatusLimitExceeded
		}
		*output = converted
		if isKnown {
			*known = 1
		} else {
			*known = 0
		}
		return StatusOK
	})
	return callbackStatus(status)
}

//export goVtWfstStateInfo
func goVtWfstStateInfo(handle C.uintptr_t, state C.uint64_t, valid, final *C.uint8_t, finalWeight *C.double) C.uint32_t {
	if valid == nil || final == nil || finalWeight == nil {
		return callbackStatus(StatusNullPointer)
	}
	status := wfstCallback(handle, func(host *wfstHost) Status {
		info, err := host.provider.StateInfo(uint64(state))
		if err != nil {
			return statusFromError(err)
		}
		if info.Final && math.IsNaN(info.FinalWeight) {
			return StatusProviderError
		}
		if info.Valid {
			*valid = 1
		} else {
			*valid = 0
		}
		if info.Final {
			*final = 1
		} else {
			*final = 0
		}
		*finalWeight = C.double(info.FinalWeight)
		return StatusOK
	})
	return callbackStatus(status)
}

//export goVtWfstStateArcs
func goVtWfstStateArcs(handle C.uintptr_t, state C.uint64_t, start C.size_t, output *C.VtWfstArc, capacity C.size_t, written, total *C.size_t) C.uint32_t {
	if written == nil || total == nil || (capacity > 0 && output == nil) {
		return callbackStatus(StatusNullPointer)
	}
	if uint64(capacity) > maximumWfstPage || uint64(capacity) > uint64(int(^uint(0)>>1)) {
		return callbackStatus(StatusLimitExceeded)
	}
	status := wfstCallback(handle, func(host *wfstHost) Status {
		page, err := host.stateArcsPage(uint64(state), uint64(start), int(capacity))
		if err != nil {
			return statusFromError(err)
		}
		converted := C.size_t(page.Total)
		if uint64(converted) != page.Total {
			return StatusLimitExceeded
		}
		if len(page.Arcs) > int(capacity) {
			return StatusProviderError
		}
		if len(page.Arcs) != 0 {
			arcs := unsafe.Slice(output, len(page.Arcs))
			for index, arc := range page.Arcs {
				C.vt_go_set_wfst_arc(&arcs[index], C.uint64_t(arc.Input), C.uint64_t(arc.Output), C.uint64_t(arc.Target), C.double(arc.Weight), C.uint8_t(boolByte(arc.HasInput)), C.uint8_t(boolByte(arc.HasOutput)))
			}
		}
		*written = C.size_t(len(page.Arcs))
		*total = converted
		return StatusOK
	})
	return callbackStatus(status)
}

func boolByte(value bool) uint8 {
	if value {
		return 1
	}
	return 0
}

func semiringCallback(handle C.uintptr_t, operation func(*hostedContext, *semiringHost) Status) Status {
	context, status := callbackContext(handle, capabilitySemiring)
	if status != StatusOK || context.semiring == nil {
		return StatusClosed
	}
	return context.semiring.gate.invoke(func() Status { return operation(context, context.semiring) })
}

func semiringNullaryCallback(handle C.uintptr_t, output *C.VtSemiringValue, one bool) C.uint32_t {
	if output == nil {
		return callbackStatus(StatusNullPointer)
	}
	status := semiringCallback(handle, func(context *hostedContext, host *semiringHost) Status {
		var value any
		var err error
		if one {
			value, err = host.provider.One()
		} else {
			value, err = host.provider.Zero()
		}
		if err != nil {
			return statusFromError(err)
		}
		token, tokenErr := host.newToken(context, value)
		if tokenErr != nil {
			return statusFromError(tokenErr)
		}
		*output = callbackCSemiringValue(token)
		return StatusOK
	})
	return callbackStatus(status)
}

//export goVtSemiringZero
func goVtSemiringZero(handle C.uintptr_t, output *C.VtSemiringValue) C.uint32_t {
	return semiringNullaryCallback(handle, output, false)
}

//export goVtSemiringOne
func goVtSemiringOne(handle C.uintptr_t, output *C.VtSemiringValue) C.uint32_t {
	return semiringNullaryCallback(handle, output, true)
}

//export goVtSemiringClone
func goVtSemiringClone(handle C.uintptr_t, value, output *C.VtSemiringValue) C.uint32_t {
	if value == nil || output == nil {
		return callbackStatus(StatusNullPointer)
	}
	status := semiringCallback(handle, func(context *hostedContext, host *semiringHost) Status {
		decoded, err := host.resolveToken(context, callbackSemiringValue(*value))
		if err != nil {
			return statusFromError(err)
		}
		token, tokenErr := host.newToken(context, decoded)
		if tokenErr != nil {
			return statusFromError(tokenErr)
		}
		*output = callbackCSemiringValue(token)
		return StatusOK
	})
	return callbackStatus(status)
}

//export goVtSemiringRelease
func goVtSemiringRelease(handle C.uintptr_t, values *C.VtSemiringValue, count C.size_t) (result C.uint32_t) {
	defer func() {
		if recover() != nil {
			result = callbackStatus(StatusProviderError)
		}
	}()
	tokens, status := callbackSemiringSlice(values, count, maximumSemiringRelease)
	if status != StatusOK {
		return callbackStatus(status)
	}
	context, status := callbackContext(handle, capabilitySemiring)
	if status != StatusOK || context.semiring == nil {
		return callbackStatus(StatusClosed)
	}
	// Token release never invokes customer code. It bypasses the provider
	// callback gate so deterministic Close cannot fail merely because another
	// independent provider operation is in flight.
	if err := context.semiring.releaseTokens(context, tokens); err != nil {
		return callbackStatus(statusFromError(err))
	}
	if len(tokens) != 0 {
		array := unsafe.Slice(values, len(tokens))
		for index := range array {
			array[index] = C.VtSemiringValue{}
		}
	}
	return callbackStatus(StatusOK)
}

func semiringBinaryCallback(handle C.uintptr_t, left, right, output *C.VtSemiringValue, operation string) C.uint32_t {
	if left == nil || right == nil || output == nil {
		return callbackStatus(StatusNullPointer)
	}
	status := semiringCallback(handle, func(context *hostedContext, host *semiringHost) Status {
		result, defined, err := host.binary(context, callbackSemiringValue(*left), callbackSemiringValue(*right), operation)
		if err != nil {
			return statusFromError(err)
		}
		if !defined {
			return StatusEnd
		}
		*output = callbackCSemiringValue(result)
		return StatusOK
	})
	return callbackStatus(status)
}

//export goVtSemiringPlus
func goVtSemiringPlus(handle C.uintptr_t, left, right, output *C.VtSemiringValue) C.uint32_t {
	return semiringBinaryCallback(handle, left, right, output, "plus")
}

//export goVtSemiringTimes
func goVtSemiringTimes(handle C.uintptr_t, left, right, output *C.VtSemiringValue) C.uint32_t {
	return semiringBinaryCallback(handle, left, right, output, "times")
}

//export goVtSemiringDivide
func goVtSemiringDivide(handle C.uintptr_t, left, right, output *C.VtSemiringValue) C.uint32_t {
	return semiringBinaryCallback(handle, left, right, output, "divide")
}

//export goVtSemiringLeftDivide
func goVtSemiringLeftDivide(handle C.uintptr_t, left, right, output *C.VtSemiringValue) C.uint32_t {
	return semiringBinaryCallback(handle, left, right, output, "left-divide")
}

func semiringCompareCallback(handle C.uintptr_t, left, right *C.VtSemiringValue, output *C.uint8_t, epsilon *float64) C.uint32_t {
	if left == nil || right == nil || output == nil {
		return callbackStatus(StatusNullPointer)
	}
	if epsilon != nil && (math.IsNaN(*epsilon) || math.IsInf(*epsilon, 0) || *epsilon < 0) {
		return callbackStatus(StatusInvalidArgument)
	}
	status := semiringCallback(handle, func(context *hostedContext, host *semiringHost) Status {
		leftValue, err := host.resolveToken(context, callbackSemiringValue(*left))
		if err != nil {
			return statusFromError(err)
		}
		rightValue, err := host.resolveToken(context, callbackSemiringValue(*right))
		if err != nil {
			return statusFromError(err)
		}
		var equal bool
		if epsilon == nil {
			equal, err = host.provider.Equal(leftValue, rightValue)
		} else {
			equal, err = host.provider.ApproxEqual(leftValue, rightValue, *epsilon)
		}
		if err != nil {
			return statusFromError(err)
		}
		*output = C.uint8_t(boolByte(equal))
		return StatusOK
	})
	return callbackStatus(status)
}

//export goVtSemiringEqual
func goVtSemiringEqual(handle C.uintptr_t, left, right *C.VtSemiringValue, output *C.uint8_t) C.uint32_t {
	return semiringCompareCallback(handle, left, right, output, nil)
}

//export goVtSemiringApproxEqual
func goVtSemiringApproxEqual(handle C.uintptr_t, left, right *C.VtSemiringValue, epsilon C.double, output *C.uint8_t) C.uint32_t {
	converted := float64(epsilon)
	return semiringCompareCallback(handle, left, right, output, &converted)
}

//export goVtSemiringNaturalOrder
func goVtSemiringNaturalOrder(handle C.uintptr_t, left, right *C.VtSemiringValue, output *C.int32_t) C.uint32_t {
	if left == nil || right == nil || output == nil {
		return callbackStatus(StatusNullPointer)
	}
	status := semiringCallback(handle, func(context *hostedContext, host *semiringHost) Status {
		leftValue, err := host.resolveToken(context, callbackSemiringValue(*left))
		if err != nil {
			return statusFromError(err)
		}
		rightValue, err := host.resolveToken(context, callbackSemiringValue(*right))
		if err != nil {
			return statusFromError(err)
		}
		order, err := host.provider.NaturalOrder(leftValue, rightValue)
		if err != nil {
			return statusFromError(err)
		}
		if !order.valid() {
			return StatusProviderError
		}
		*output = C.int32_t(order)
		return StatusOK
	})
	return callbackStatus(status)
}

func semiringBytesCallback(handle C.uintptr_t, value *C.VtSemiringValue, output *C.uint8_t, capacity C.size_t, written, required *C.size_t, diagnostic bool) C.uint32_t {
	if value == nil {
		return callbackStatus(StatusNullPointer)
	}
	status := semiringCallback(handle, func(context *hostedContext, host *semiringHost) Status {
		decoded, err := host.resolveToken(context, callbackSemiringValue(*value))
		if err != nil {
			return statusFromError(err)
		}
		var data []byte
		if diagnostic {
			var text string
			text, err = host.provider.Diagnostic(decoded)
			if err == nil && !utf8.ValidString(text) {
				err = &Error{Operation: "encode semiring diagnostic", Status: StatusProviderError}
			}
			data = []byte(text)
		} else {
			provider, ok := host.provider.(StableSemiringProvider)
			if !ok {
				return StatusUnsupported
			}
			data, err = provider.StableBytes(decoded)
		}
		if err != nil {
			return statusFromError(err)
		}
		return callbackBytes(data, output, capacity, written, required)
	})
	return callbackStatus(status)
}

//export goVtSemiringStableBytes
func goVtSemiringStableBytes(handle C.uintptr_t, value *C.VtSemiringValue, output *C.uint8_t, capacity C.size_t, written, required *C.size_t) C.uint32_t {
	return semiringBytesCallback(handle, value, output, capacity, written, required, false)
}

//export goVtSemiringDiagnostic
func goVtSemiringDiagnostic(handle C.uintptr_t, value *C.VtSemiringValue, output *C.uint8_t, capacity C.size_t, written, required *C.size_t) C.uint32_t {
	return semiringBytesCallback(handle, value, output, capacity, written, required, true)
}

func semiringManyCallback(handle C.uintptr_t, values *C.VtSemiringValue, count C.size_t, output *C.VtSemiringValue, times bool) C.uint32_t {
	if output == nil {
		return callbackStatus(StatusNullPointer)
	}
	tokens, status := callbackSemiringSlice(values, count, maximumSemiringFold)
	if status != StatusOK {
		return callbackStatus(status)
	}
	status = semiringCallback(handle, func(context *hostedContext, host *semiringHost) Status {
		result, err := host.fold(context, tokens, times)
		if err != nil {
			return statusFromError(err)
		}
		*output = callbackCSemiringValue(result)
		return StatusOK
	})
	return callbackStatus(status)
}

//export goVtSemiringPlusMany
func goVtSemiringPlusMany(handle C.uintptr_t, values *C.VtSemiringValue, count C.size_t, output *C.VtSemiringValue) C.uint32_t {
	return semiringManyCallback(handle, values, count, output, false)
}

//export goVtSemiringTimesMany
func goVtSemiringTimesMany(handle C.uintptr_t, values *C.VtSemiringValue, count C.size_t, output *C.VtSemiringValue) C.uint32_t {
	return semiringManyCallback(handle, values, count, output, true)
}

//export goVtSemiringStar
func goVtSemiringStar(handle C.uintptr_t, value, output *C.VtSemiringValue) C.uint32_t {
	if value == nil || output == nil {
		return callbackStatus(StatusNullPointer)
	}
	status := semiringCallback(handle, func(context *hostedContext, host *semiringHost) Status {
		provider, ok := host.provider.(StarSemiringProvider)
		if !ok {
			return StatusUnsupported
		}
		decoded, err := host.resolveToken(context, callbackSemiringValue(*value))
		if err != nil {
			return statusFromError(err)
		}
		result, converged, err := provider.Star(decoded)
		if err != nil {
			return statusFromError(err)
		}
		if !converged {
			return StatusEnd
		}
		token, tokenErr := host.newToken(context, result)
		if tokenErr != nil {
			return statusFromError(tokenErr)
		}
		*output = callbackCSemiringValue(token)
		return StatusOK
	})
	return callbackStatus(status)
}

func semiringNumericCallback(handle C.uintptr_t, value *C.VtSemiringValue, output *C.double, probability bool) C.uint32_t {
	if value == nil || output == nil {
		return callbackStatus(StatusNullPointer)
	}
	status := semiringCallback(handle, func(context *hostedContext, host *semiringHost) Status {
		provider, ok := host.provider.(NumericSemiringProvider)
		if !ok {
			return StatusUnsupported
		}
		decoded, err := host.resolveToken(context, callbackSemiringValue(*value))
		if err != nil {
			return statusFromError(err)
		}
		var result float64
		if probability {
			result, err = provider.ToProbability(decoded)
		} else {
			result, err = provider.NumericalValue(decoded)
		}
		if err != nil {
			return statusFromError(err)
		}
		if math.IsNaN(result) || (probability && (math.IsInf(result, 0) || result < 0)) {
			return StatusProviderError
		}
		*output = C.double(result)
		return StatusOK
	})
	return callbackStatus(status)
}

//export goVtSemiringNumericalValue
func goVtSemiringNumericalValue(handle C.uintptr_t, value *C.VtSemiringValue, output *C.double) C.uint32_t {
	return semiringNumericCallback(handle, value, output, false)
}

//export goVtSemiringQuantize
func goVtSemiringQuantize(handle C.uintptr_t, value *C.VtSemiringValue, epsilon C.double, output *C.int64_t) C.uint32_t {
	if value == nil || output == nil {
		return callbackStatus(StatusNullPointer)
	}
	converted := float64(epsilon)
	if math.IsNaN(converted) || math.IsInf(converted, 0) || converted <= 0 {
		return callbackStatus(StatusInvalidArgument)
	}
	status := semiringCallback(handle, func(context *hostedContext, host *semiringHost) Status {
		provider, ok := host.provider.(NumericSemiringProvider)
		if !ok {
			return StatusUnsupported
		}
		decoded, err := host.resolveToken(context, callbackSemiringValue(*value))
		if err != nil {
			return statusFromError(err)
		}
		result, err := provider.Quantize(decoded, converted)
		if err != nil {
			return statusFromError(err)
		}
		*output = C.int64_t(result)
		return StatusOK
	})
	return callbackStatus(status)
}

//export goVtSemiringToProbability
func goVtSemiringToProbability(handle C.uintptr_t, value *C.VtSemiringValue, output *C.double) C.uint32_t {
	return semiringNumericCallback(handle, value, output, true)
}

//export goVtSemiringClosureBound
func goVtSemiringClosureBound(handle C.uintptr_t, output *C.size_t, known *C.uint8_t) C.uint32_t {
	if output == nil || known == nil {
		return callbackStatus(StatusNullPointer)
	}
	status := semiringCallback(handle, func(_ *hostedContext, host *semiringHost) Status {
		provider, ok := host.provider.(LawfulSemiringProvider)
		if !ok {
			return StatusUnsupported
		}
		bound, isKnown, err := provider.ClosureBound()
		if err != nil {
			return statusFromError(err)
		}
		converted := C.size_t(bound)
		if uint64(converted) != bound {
			return StatusLimitExceeded
		}
		*output = converted
		*known = C.uint8_t(boolByte(isKnown))
		return StatusOK
	})
	return callbackStatus(status)
}
