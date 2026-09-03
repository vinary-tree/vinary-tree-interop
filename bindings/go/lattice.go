package interop

import (
	"fmt"
	"runtime"
	"sync/atomic"
	"unicode/utf8"
)

// LatticeFlags describe lifecycle, concurrency, and bulk capabilities.
type LatticeFlags uint64

const (
	LatticeThreadBound       LatticeFlags = 1
	LatticeParallelReentrant LatticeFlags = 2
	LatticeStableBytes       LatticeFlags = 4
	LatticeBatch             LatticeFlags = 8
)

const knownLatticeFlags = LatticeThreadBound | LatticeParallelReentrant | LatticeStableBytes | LatticeBatch
const maximumLatticeBatch = 256

// LatticeOptions selects the concurrency contract published by a Go provider.
// Serialized providers reject concurrent or reentrant callbacks instead of
// blocking an arbitrary native worker thread.
type LatticeOptions struct {
	ParallelReentrant bool
}

// LatticeProvider is one immutable host-defined value. Returned values must
// use the same domain and expose the same optional capabilities as the
// receiver.
type LatticeProvider interface {
	DomainID() InterfaceID
	Join(other *LatticeOperand) (LatticeProvider, error)
	Meet(other *LatticeOperand) (LatticeProvider, error)
	Equal(other *LatticeOperand) (bool, error)
	Diagnostic() (string, error)
}

// StableLatticeProvider exposes a canonical byte encoding suitable for
// hashing, persistence, and cross-runtime operand decoding.
type StableLatticeProvider interface {
	LatticeProvider
	StableBytes() ([]byte, error)
}

// BatchLatticeProvider amortizes cgo and host-runtime crossings for bounded
// associative folds. The bridge supplies a lawful sequential fallback when a
// provider does not implement this interface.
type BatchLatticeProvider interface {
	LatticeProvider
	JoinMany(others []*LatticeOperand) (LatticeProvider, error)
	MeetMany(others []*LatticeOperand) (LatticeProvider, error)
}

type latticeContract struct {
	domain InterfaceID
	flags  LatticeFlags
}

type latticeHost struct {
	provider LatticeProvider
	contract latticeContract
	gate     callbackGate
}

func latticeContractFor(provider LatticeProvider, options LatticeOptions) (contract latticeContract, err error) {
	if err := requireProvider("lattice", provider); err != nil {
		return latticeContract{}, err
	}
	defer func() {
		if recovered := recover(); recovered != nil {
			contract = latticeContract{}
			err = &Error{Operation: "inspect lattice provider", Status: StatusProviderError, Cause: fmt.Errorf("panic: %v", recovered)}
		}
	}()
	contract.domain = provider.DomainID()
	contract.flags = LatticeBatch
	if options.ParallelReentrant {
		contract.flags |= LatticeParallelReentrant
	}
	if _, stable := provider.(StableLatticeProvider); stable {
		contract.flags |= LatticeStableBytes
	}
	return contract, nil
}

func validateLatticeContract(provider LatticeProvider, expected latticeContract) error {
	actual, err := latticeContractFor(provider, LatticeOptions{
		ParallelReentrant: expected.flags&LatticeParallelReentrant != 0,
	})
	if err != nil {
		return err
	}
	if actual != expected {
		return &Error{
			Operation: "validate lattice result",
			Status:    StatusProviderError,
			Cause:     fmt.Errorf("result changed domain or capabilities"),
		}
	}
	return nil
}

func newLatticeRaw(provider LatticeProvider, contract latticeContract) (rawResource, error) {
	if err := validateLatticeContract(provider, contract); err != nil {
		return rawResource{}, err
	}
	host := &latticeHost{
		provider: provider,
		contract: contract,
		gate: callbackGate{
			parallel: contract.flags&LatticeParallelReentrant != 0,
		},
	}
	context := &hostedContext{capabilities: capabilityLattice, lattice: host}
	return newHostedContext(context, func(handle uintptr) rawResource {
		return abiMakeLatticeResource(handle, contract.flags, contract.domain)
	})
}

// LatticeOperand is a validated same-domain resource borrowed for exactly one
// provider callback. Methods reject use after that callback returns.
type LatticeOperand struct {
	raw    rawResource
	active *atomic.Bool
	local  LatticeProvider
	flags  LatticeFlags
	domain InterfaceID
}

func newLatticeOperand(resource rawResource, expected InterfaceID) (*LatticeOperand, error) {
	flags, domain, err := abiLatticeMetadata(resource)
	if err != nil {
		return nil, err
	}
	if flags&^knownLatticeFlags != 0 || domain != expected {
		return nil, &Error{Operation: "validate lattice operand", Status: StatusInvalidArgument, Cause: fmt.Errorf("domain or flags are incompatible")}
	}
	active := &atomic.Bool{}
	active.Store(true)
	operand := &LatticeOperand{raw: resource, active: active, flags: flags, domain: domain}
	if context, local := localHostedResource(resource); local && context.lattice != nil {
		operand.local = context.lattice.provider
	}
	return operand, nil
}

func (operand *LatticeOperand) requireActive() error {
	if operand == nil || operand.active == nil || !operand.active.Load() {
		return &Error{Operation: "use lattice operand", Status: StatusClosed, Cause: fmt.Errorf("operand escaped its provider callback")}
	}
	return nil
}

func (operand *LatticeOperand) invalidate() {
	if operand != nil && operand.active != nil {
		operand.active.Store(false)
	}
}

// LocalProvider returns the underlying Go provider without crossing the ABI
// when both operands were created by this Go module instance.
func (operand *LatticeOperand) LocalProvider() (LatticeProvider, bool) {
	if operand.requireActive() != nil || operand.local == nil {
		return nil, false
	}
	return operand.local, true
}

// HasStableBytes reports whether the foreign operand advertises a canonical
// encoding callback.
func (operand *LatticeOperand) HasStableBytes() bool {
	return operand.requireActive() == nil && operand.flags&LatticeStableBytes != 0
}

// StableBytes copies the canonical encoding before the callback lease ends.
func (operand *LatticeOperand) StableBytes() ([]byte, error) {
	if err := operand.requireActive(); err != nil {
		return nil, err
	}
	if operand.flags&LatticeStableBytes == 0 {
		return nil, &Error{Operation: "read lattice operand stable bytes", Status: StatusUnsupported}
	}
	if local, ok := operand.local.(StableLatticeProvider); ok {
		bytes, err := local.StableBytes()
		if err != nil {
			return nil, err
		}
		if len(bytes) > maximumProviderBytes {
			return nil, &Error{Operation: "read lattice operand stable bytes", Status: StatusLimitExceeded}
		}
		return append([]byte(nil), bytes...), nil
	}
	return abiLatticeBytes(operand.raw, false)
}

func (host *latticeHost) binary(other rawResource, meet bool) (rawResource, error) {
	operand, err := newLatticeOperand(other, host.contract.domain)
	if err != nil {
		return rawResource{}, err
	}
	defer operand.invalidate()
	var result LatticeProvider
	if meet {
		result, err = host.provider.Meet(operand)
	} else {
		result, err = host.provider.Join(operand)
	}
	if err != nil {
		return rawResource{}, err
	}
	return newLatticeRaw(result, host.contract)
}

func (host *latticeHost) equal(other rawResource) (bool, error) {
	operand, err := newLatticeOperand(other, host.contract.domain)
	if err != nil {
		return false, err
	}
	defer operand.invalidate()
	return host.provider.Equal(operand)
}

func (host *latticeHost) many(resources []rawResource, meet bool) (rawResource, error) {
	operands := make([]*LatticeOperand, 0, len(resources))
	defer func() {
		for _, operand := range operands {
			operand.invalidate()
		}
	}()
	for _, resource := range resources {
		operand, err := newLatticeOperand(resource, host.contract.domain)
		if err != nil {
			return rawResource{}, err
		}
		operands = append(operands, operand)
	}
	var result LatticeProvider
	var err error
	if batch, ok := host.provider.(BatchLatticeProvider); ok {
		if meet {
			result, err = batch.MeetMany(operands)
		} else {
			result, err = batch.JoinMany(operands)
		}
	} else {
		result = host.provider
		for _, operand := range operands {
			if meet {
				result, err = result.Meet(operand)
			} else {
				result, err = result.Join(operand)
			}
			if err != nil {
				break
			}
		}
	}
	if err != nil {
		return rawResource{}, err
	}
	return newLatticeRaw(result, host.contract)
}

// LatticeValue is an owned consumer view over any version-1 lattice resource.
type LatticeValue struct {
	resource *Resource
	flags    LatticeFlags
	domain   InterfaceID
}

func wrapLattice(raw rawResource, adopted bool) (*LatticeValue, error) {
	flags, domain, err := abiLatticeMetadata(raw)
	if err != nil {
		if adopted {
			abiReleaseResource(raw)
		}
		return nil, err
	}
	if flags&^knownLatticeFlags != 0 {
		if adopted {
			abiReleaseResource(raw)
		}
		return nil, &Error{Operation: "open lattice value", Status: StatusUnsupported, Cause: fmt.Errorf("unknown lattice flags %#x", flags)}
	}
	var resource *Resource
	if adopted {
		resource, err = adoptResource(raw)
	} else {
		owned, retainErr := abiRetainResource(raw)
		if retainErr != nil {
			return nil, retainErr
		}
		resource, err = adoptResource(owned)
	}
	if err != nil {
		return nil, err
	}
	value := &LatticeValue{resource: resource, flags: flags, domain: domain}
	runtime.SetFinalizer(value, (*LatticeValue).Close)
	return value, nil
}

// NewLatticeValue exposes a Go provider through the stable native ABI and
// returns an owned consumer view of the same value.
func NewLatticeValue(provider LatticeProvider, options LatticeOptions) (*LatticeValue, error) {
	contract, err := latticeContractFor(provider, options)
	if err != nil {
		return nil, err
	}
	raw, err := newLatticeRaw(provider, contract)
	if err != nil {
		return nil, err
	}
	return wrapLattice(raw, true)
}

// OpenLatticeValue retains and validates a lattice resource produced by any
// Vinary Tree language binding.
func OpenLatticeValue(source NativeResource) (*LatticeValue, error) {
	raw, err := retainRawResource(source)
	if err != nil {
		return nil, err
	}
	return wrapLattice(raw, true)
}

// WithResource lends this lattice value to another project facade.
func (value *LatticeValue) WithResource(callback func(context, vtable uintptr) error) error {
	if value == nil || value.resource == nil {
		return &Error{Operation: "borrow lattice value", Status: StatusClosed}
	}
	return value.resource.WithResource(callback)
}

// Close releases the owned lattice resource exactly once.
func (value *LatticeValue) Close() {
	if value == nil {
		return
	}
	runtime.SetFinalizer(value, nil)
	if value.resource != nil {
		value.resource.Close()
	}
}

// DomainID identifies the algebra implemented by this value.
func (value *LatticeValue) DomainID() InterfaceID {
	if value == nil {
		return InterfaceID{}
	}
	return value.domain
}

// Flags returns the validated provider capability flags.
func (value *LatticeValue) Flags() LatticeFlags {
	if value == nil {
		return 0
	}
	return value.flags
}

func (value *LatticeValue) binary(other NativeResource, meet bool) (*LatticeValue, error) {
	if value == nil || value.resource == nil || other == nil {
		return nil, &Error{Operation: "combine lattice values", Status: StatusInvalidArgument}
	}
	var output rawResource
	err := value.resource.withRaw("combine lattice values", func(left rawResource) error {
		return other.WithResource(func(context, vtable uintptr) error {
			var operation string
			if meet {
				operation = "meet lattice values"
			} else {
				operation = "join lattice values"
			}
			var callErr error
			output, callErr = abiLatticeBinary(operation, left, rawResource{context: context, vtable: vtable}, meet)
			return callErr
		})
	})
	if err != nil {
		return nil, err
	}
	return wrapLattice(output, true)
}

// Join returns the least upper bound of two compatible values.
func (value *LatticeValue) Join(other NativeResource) (*LatticeValue, error) {
	return value.binary(other, false)
}

// Meet returns the greatest lower bound of two compatible values.
func (value *LatticeValue) Meet(other NativeResource) (*LatticeValue, error) {
	return value.binary(other, true)
}

// Equal compares two compatible values through the provider contract.
func (value *LatticeValue) Equal(other NativeResource) (bool, error) {
	if value == nil || value.resource == nil || other == nil {
		return false, &Error{Operation: "compare lattice values", Status: StatusInvalidArgument}
	}
	var equal bool
	err := value.resource.withRaw("compare lattice values", func(left rawResource) error {
		return other.WithResource(func(context, vtable uintptr) error {
			var callErr error
			equal, callErr = abiLatticeEqual(left, rawResource{context: context, vtable: vtable})
			return callErr
		})
	})
	return equal, err
}

// StableBytes returns the canonical encoding when advertised by the provider.
func (value *LatticeValue) StableBytes() ([]byte, error) {
	if value == nil || value.flags&LatticeStableBytes == 0 {
		return nil, &Error{Operation: "read lattice stable bytes", Status: StatusUnsupported}
	}
	var result []byte
	err := value.resource.withRaw("read lattice stable bytes", func(raw rawResource) error {
		var callErr error
		result, callErr = abiLatticeBytes(raw, false)
		return callErr
	})
	return result, err
}

// Diagnostic returns the provider's human-readable representation.
func (value *LatticeValue) Diagnostic() (string, error) {
	if value == nil || value.resource == nil {
		return "", &Error{Operation: "read lattice diagnostic", Status: StatusClosed}
	}
	var result []byte
	err := value.resource.withRaw("read lattice diagnostic", func(raw rawResource) error {
		var callErr error
		result, callErr = abiLatticeBytes(raw, true)
		return callErr
	})
	if err == nil && !utf8.Valid(result) {
		err = &Error{Operation: "read lattice diagnostic", Status: StatusProviderError, Cause: fmt.Errorf("provider returned invalid UTF-8")}
	}
	return string(result), err
}

func retainRawResources(sources []NativeResource) ([]rawResource, func(), error) {
	if len(sources) > maximumLatticeBatch {
		return nil, nil, &Error{Operation: "retain resource batch", Status: StatusLimitExceeded}
	}
	resources := make([]rawResource, 0, len(sources))
	release := func() {
		for _, resource := range resources {
			abiReleaseResource(resource)
		}
	}
	for _, source := range sources {
		if source == nil {
			release()
			return nil, nil, &Error{Operation: "retain resource batch", Status: StatusInvalidArgument}
		}
		var owned rawResource
		err := source.WithResource(func(context, vtable uintptr) error {
			var retainErr error
			owned, retainErr = abiRetainResource(rawResource{context: context, vtable: vtable})
			return retainErr
		})
		if err != nil {
			release()
			return nil, nil, err
		}
		resources = append(resources, owned)
	}
	return resources, release, nil
}

func (value *LatticeValue) many(others []NativeResource, meet bool) (*LatticeValue, error) {
	if value == nil || value.resource == nil {
		return nil, &Error{Operation: "fold lattice values", Status: StatusClosed}
	}
	resources, release, err := retainRawResources(others)
	if err != nil {
		return nil, err
	}
	defer release()
	var output rawResource
	err = value.resource.withRaw("fold lattice values", func(receiver rawResource) error {
		operation := "join lattice values"
		if meet {
			operation = "meet lattice values"
		}
		var callErr error
		output, callErr = abiLatticeMany(operation, receiver, resources, meet)
		return callErr
	})
	if err != nil {
		return nil, err
	}
	return wrapLattice(output, true)
}

// JoinMany performs one bounded associative join batch.
func (value *LatticeValue) JoinMany(others ...NativeResource) (*LatticeValue, error) {
	return value.many(others, false)
}

// MeetMany performs one bounded associative meet batch.
func (value *LatticeValue) MeetMany(others ...NativeResource) (*LatticeValue, error) {
	return value.many(others, true)
}
