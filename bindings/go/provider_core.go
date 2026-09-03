package interop

import (
	"fmt"
	"math"
	"reflect"
	"runtime/cgo"
	"sync"
	"sync/atomic"
)

const (
	capabilityLattice            uint64 = 1
	capabilityWfst               uint64 = 2
	capabilitySemiring           uint64 = 4
	capabilitySemiringDivision   uint64 = 8
	capabilitySemiringStar       uint64 = 16
	capabilitySemiringNumeric    uint64 = 32
	capabilitySemiringProperties uint64 = 64
)

type callbackGate struct {
	parallel bool
	mutex    sync.Mutex
}

func (gate *callbackGate) invoke(callback func() Status) (status Status) {
	if !gate.parallel {
		if !gate.mutex.TryLock() {
			return StatusProviderError
		}
		defer gate.mutex.Unlock()
	}
	defer func() {
		if recover() != nil {
			status = StatusProviderError
		}
	}()
	return callback()
}

type hostedContext struct {
	handle       uintptr
	refs         atomic.Int64
	capabilities uint64
	lattice      *latticeHost
	wfst         *wfstHost
	semiring     *semiringHost
}

func newHostedContext(context *hostedContext, makeResource func(uintptr) rawResource) (rawResource, error) {
	context.refs.Store(1)
	handle := cgo.NewHandle(context)
	context.handle = uintptr(handle)
	resource := makeResource(uintptr(handle))
	if resource.isNull() {
		handle.Delete()
		return rawResource{}, &Error{Operation: "allocate hosted resource", Status: StatusLimitExceeded}
	}
	return resource, nil
}

func hostedFromHandle(handle uintptr) (context *hostedContext, ok bool) {
	if handle == 0 {
		return nil, false
	}
	defer func() {
		if recover() != nil {
			context = nil
			ok = false
		}
	}()
	value := cgo.Handle(handle).Value()
	context, ok = value.(*hostedContext)
	return context, ok && context != nil
}

func localHostedResource(resource rawResource) (*hostedContext, bool) {
	handle, ok := abiHostedHandle(resource)
	if !ok {
		return nil, false
	}
	return hostedFromHandle(handle)
}

func (context *hostedContext) retain() {
	if context == nil {
		panic("retain called on a nil hosted resource")
	}
	for {
		count := context.refs.Load()
		if count <= 0 {
			panic("retain called after hosted resource release")
		}
		if count == math.MaxInt64 {
			panic("hosted resource reference count overflow")
		}
		if context.refs.CompareAndSwap(count, count+1) {
			return
		}
	}
}

func (context *hostedContext) release() bool {
	if context == nil {
		return false
	}
	remaining := context.refs.Add(-1)
	if remaining < 0 {
		panic("hosted resource released more times than retained")
	}
	if remaining != 0 {
		return false
	}
	cgo.Handle(context.handle).Delete()
	return true
}

func nilProvider(value any) bool {
	if value == nil {
		return true
	}
	reflected := reflect.ValueOf(value)
	switch reflected.Kind() {
	case reflect.Chan, reflect.Func, reflect.Interface, reflect.Map, reflect.Pointer, reflect.Slice:
		return reflected.IsNil()
	default:
		return false
	}
}

func requireProvider(name string, value any) error {
	if nilProvider(value) {
		return &Error{Operation: "host " + name, Status: StatusInvalidArgument, Cause: fmt.Errorf("provider is nil")}
	}
	return nil
}
