// Package interop implements the stable Vinary Tree resource ABI for Go.
//
// It provides ownership-safe consumers and real cgo-backed host providers for
// lattice values, scalar WFSTs, and dynamic semirings. Project-specific Go
// packages exchange these resources without sharing Rust layouts or linking
// their implementation crates together.
package interop

import (
	"errors"
	"fmt"
	"runtime"
	"sync"
	"sync/atomic"
)

// Status is the portable error currency carried by every Vinary Tree ABI call.
type Status uint32

const (
	StatusOK              Status = 0
	StatusEnd             Status = 1
	StatusInvalidArgument Status = 2
	StatusNullPointer     Status = 3
	StatusUnsupported     Status = 4
	StatusIOError         Status = 5
	StatusClosed          Status = 6
	StatusLimitExceeded   Status = 7
	StatusProviderError   Status = 8
	StatusBatchInUse      Status = 9
)

func (status Status) valid() bool { return status <= StatusBatchInUse }

// Error preserves the operation and portable status for a failed ABI call.
type Error struct {
	Operation string
	Status    Status
	Cause     error
}

func (failure *Error) Error() string {
	if failure.Cause != nil {
		return fmt.Sprintf("%s failed with Vinary Tree status %d: %v", failure.Operation, failure.Status, failure.Cause)
	}
	return fmt.Sprintf("%s failed with Vinary Tree status %d", failure.Operation, failure.Status)
}

func (failure *Error) Unwrap() error { return failure.Cause }

func statusError(operation string, status Status) error {
	if status == StatusOK {
		return nil
	}
	if !status.valid() {
		return &Error{Operation: operation, Status: StatusProviderError, Cause: fmt.Errorf("provider returned unknown status %d", status)}
	}
	return &Error{Operation: operation, Status: status}
}

func statusFromError(err error) Status {
	if err == nil {
		return StatusOK
	}
	var failure *Error
	if errors.As(err, &failure) && failure.Status.valid() && failure.Status != StatusOK {
		return failure.Status
	}
	return StatusProviderError
}

// InterfaceID is a stable 16-byte capability or algebra-domain identifier.
type InterfaceID [16]byte

// InterfaceIDFromASCII creates an identifier and rejects strings whose byte
// length is not exactly 16. Interface identifiers are ASCII by convention.
func InterfaceIDFromASCII(value string) (InterfaceID, error) {
	var identifier InterfaceID
	if len(value) != len(identifier) {
		return identifier, fmt.Errorf("interface ID must be exactly 16 bytes, found %d", len(value))
	}
	for index := range value {
		if value[index] > 0x7f {
			return InterfaceID{}, fmt.Errorf("interface ID byte %d is not ASCII", index)
		}
	}
	copy(identifier[:], value)
	return identifier, nil
}

// NativeResource lends the two native words of a live VtResource to one
// synchronous callback. A native consumer may retain those words before the
// callback returns. Implementations must keep the owner alive for the complete
// callback and reject use after close.
type NativeResource interface {
	WithResource(func(context, vtable uintptr) error) error
}

// DictionaryResource is retained as the source-compatible name used by the
// project-specific dictionary packages.
type DictionaryResource = NativeResource

type rawResource struct {
	context uintptr
	vtable  uintptr
}

func (resource rawResource) isNull() bool {
	return resource.context == 0 || resource.vtable == 0
}

const resourceClosedBit uint64 = 1 << 63

// resourceOwner combines a close bit with an active-borrow count. This makes
// WithResource race-safe without a mutex: Close marks the owner closed, and
// the last in-flight lexical borrow performs the one native release.
type resourceOwner struct {
	raw         rawResource
	state       atomic.Uint64
	releaseOnce sync.Once
}

func (owner *resourceOwner) acquire() bool {
	for {
		state := owner.state.Load()
		if state&resourceClosedBit != 0 {
			return false
		}
		if state == resourceClosedBit-1 {
			return false
		}
		if owner.state.CompareAndSwap(state, state+1) {
			return true
		}
	}
}

func (owner *resourceOwner) releaseBorrow() {
	state := owner.state.Add(^uint64(0))
	if state == resourceClosedBit {
		owner.releaseNative()
	}
}

func (owner *resourceOwner) close() {
	for {
		state := owner.state.Load()
		if state&resourceClosedBit != 0 {
			return
		}
		if owner.state.CompareAndSwap(state, state|resourceClosedBit) {
			if state == 0 {
				owner.releaseNative()
			}
			return
		}
	}
}

func (owner *resourceOwner) releaseNative() {
	owner.releaseOnce.Do(func() { abiReleaseResource(owner.raw) })
}

// Resource owns one retain of a capability-negotiated VtResource.
//
// Resource values must be closed promptly with defer. The finalizer is a
// leak-safety backstop only; it does not provide deterministic release.
type Resource struct {
	owner *resourceOwner
}

func adoptResource(raw rawResource) (*Resource, error) {
	if raw.isNull() {
		return nil, &Error{Operation: "adopt resource", Status: StatusNullPointer}
	}
	resource := &Resource{owner: &resourceOwner{raw: raw}}
	runtime.SetFinalizer(resource, (*Resource).Close)
	return resource, nil
}

func retainRawResource(source NativeResource) (rawResource, error) {
	if source == nil {
		return rawResource{}, &Error{Operation: "retain resource", Status: StatusNullPointer}
	}
	var owned rawResource
	err := source.WithResource(func(context, vtable uintptr) error {
		var retainErr error
		owned, retainErr = abiRetainResource(rawResource{context: context, vtable: vtable})
		return retainErr
	})
	if err != nil {
		return rawResource{}, err
	}
	return owned, nil
}

// WithResource implements NativeResource with a lock-free lexical borrow.
func (resource *Resource) WithResource(callback func(context, vtable uintptr) error) error {
	if resource == nil || resource.owner == nil || callback == nil {
		return &Error{Operation: "borrow resource", Status: StatusInvalidArgument}
	}
	if !resource.owner.acquire() {
		return &Error{Operation: "borrow resource", Status: StatusClosed}
	}
	defer resource.owner.releaseBorrow()
	err := callback(resource.owner.raw.context, resource.owner.raw.vtable)
	runtime.KeepAlive(resource)
	return err
}

// Close releases this resource exactly once after any active lexical borrows
// complete. Concurrent calls are safe and idempotent.
func (resource *Resource) Close() {
	if resource == nil || resource.owner == nil {
		return
	}
	runtime.SetFinalizer(resource, nil)
	resource.owner.close()
}

func (resource *Resource) withRaw(operation string, callback func(rawResource) error) error {
	if callback == nil {
		return &Error{Operation: operation, Status: StatusInvalidArgument}
	}
	return resource.WithResource(func(context, vtable uintptr) error {
		return callback(rawResource{context: context, vtable: vtable})
	})
}
