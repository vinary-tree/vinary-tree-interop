package interop

import (
	"fmt"
	"math"
	"runtime"
	"runtime/cgo"
	"sync"
	"sync/atomic"
	"unicode/utf8"
)

// SemiringFlags describe concurrency, stable encodings, and batch support.
type SemiringFlags uint64

const (
	SemiringThreadBound       SemiringFlags = 1
	SemiringParallelReentrant SemiringFlags = 2
	SemiringStableBytes       SemiringFlags = 4
	SemiringBatch             SemiringFlags = 8
)

const knownSemiringFlags = SemiringThreadBound | SemiringParallelReentrant | SemiringStableBytes | SemiringBatch

// SemiringProperties are law-bearing claims checked by consuming algorithms.
type SemiringProperties uint64

const (
	SemiringHashable         SemiringProperties = 1
	SemiringIdempotentPlus   SemiringProperties = 2
	SemiringKClosed          SemiringProperties = 4
	SemiringZeroSumFree      SemiringProperties = 8
	SemiringCommutativeTimes SemiringProperties = 16
	SemiringTotallyOrdered   SemiringProperties = 32
	SemiringNonnegative      SemiringProperties = 64
)

const knownSemiringProperties = SemiringHashable | SemiringIdempotentPlus | SemiringKClosed | SemiringZeroSumFree | SemiringCommutativeTimes | SemiringTotallyOrdered | SemiringNonnegative
const maximumSemiringFold = 256
const maximumSemiringRelease = 65_536

// NaturalOrder is the semiring-induced ordering of two weights.
type NaturalOrder int32

const (
	OrderBetter       NaturalOrder = -1
	OrderEqual        NaturalOrder = 0
	OrderWorse        NaturalOrder = 1
	OrderIncomparable NaturalOrder = 2
)

func (order NaturalOrder) valid() bool {
	return order >= OrderBetter && order <= OrderIncomparable
}

// SemiringOptions selects the concurrency promise published by a Go provider.
type SemiringOptions struct {
	ParallelReentrant bool
}

// SemiringProvider defines immutable Go values and the mandatory semiring
// operations over them. Values are opaque to the ABI and must not be mutated
// after being returned by the provider.
type SemiringProvider interface {
	DomainID() InterfaceID
	Zero() (any, error)
	One() (any, error)
	Plus(left, right any) (any, error)
	Times(left, right any) (any, error)
	Equal(left, right any) (bool, error)
	ApproxEqual(left, right any, epsilon float64) (bool, error)
	NaturalOrder(left, right any) (NaturalOrder, error)
	Diagnostic(value any) (string, error)
}

// StableSemiringProvider supplies a canonical encoding for each value.
type StableSemiringProvider interface {
	SemiringProvider
	StableBytes(value any) ([]byte, error)
}

// BatchSemiringProvider supplies optimized bounded associative folds.
type BatchSemiringProvider interface {
	SemiringProvider
	PlusMany(values []any) (any, error)
	TimesMany(values []any) (any, error)
}

// DivisibleSemiringProvider exposes division and weak left division. A false
// result flag maps to VT_STATUS_END and means the operation is undefined.
type DivisibleSemiringProvider interface {
	SemiringProvider
	Divide(dividend, divisor any) (value any, defined bool, err error)
	LeftDivide(value, divisor any) (result any, defined bool, err error)
}

// StarSemiringProvider exposes a potentially partial Kleene closure.
type StarSemiringProvider interface {
	SemiringProvider
	Star(value any) (result any, converged bool, err error)
}

// NumericSemiringProvider exposes numerical projections used by specialized
// shortest-path, quantization, and probabilistic algorithms.
type NumericSemiringProvider interface {
	SemiringProvider
	NumericalValue(value any) (float64, error)
	Quantize(value any, epsilon float64) (int64, error)
	ToProbability(value any) (float64, error)
}

// LawfulSemiringProvider declares algebraic refinements and an optional finite
// closure bound. Consumers validate claimed laws before selecting fast paths.
type LawfulSemiringProvider interface {
	SemiringProvider
	Properties() SemiringProperties
	ClosureBound() (bound uint64, known bool, err error)
}

type semiringContract struct {
	domain       InterfaceID
	flags        SemiringFlags
	capabilities uint64
	properties   SemiringProperties
}

type semiringHost struct {
	provider SemiringProvider
	contract semiringContract
	gate     callbackGate
}

type hostedSemiringToken struct {
	context *hostedContext
	value   any
}

func semiringContractFor(provider SemiringProvider, options SemiringOptions) (contract semiringContract, err error) {
	if err := requireProvider("semiring", provider); err != nil {
		return semiringContract{}, err
	}
	defer func() {
		if recovered := recover(); recovered != nil {
			contract = semiringContract{}
			err = &Error{Operation: "inspect semiring provider", Status: StatusProviderError, Cause: fmt.Errorf("panic: %v", recovered)}
		}
	}()
	contract.domain = provider.DomainID()
	contract.flags = SemiringBatch
	contract.capabilities = capabilitySemiring
	if options.ParallelReentrant {
		contract.flags |= SemiringParallelReentrant
	}
	if _, ok := provider.(StableSemiringProvider); ok {
		contract.flags |= SemiringStableBytes
	}
	if _, ok := provider.(DivisibleSemiringProvider); ok {
		contract.capabilities |= capabilitySemiringDivision
	}
	if _, ok := provider.(StarSemiringProvider); ok {
		contract.capabilities |= capabilitySemiringStar
	}
	if _, ok := provider.(NumericSemiringProvider); ok {
		contract.capabilities |= capabilitySemiringNumeric
	}
	if lawful, ok := provider.(LawfulSemiringProvider); ok {
		contract.capabilities |= capabilitySemiringProperties
		contract.properties = lawful.Properties()
		if contract.properties&^knownSemiringProperties != 0 {
			return semiringContract{}, &Error{Operation: "inspect semiring provider", Status: StatusInvalidArgument, Cause: fmt.Errorf("unknown property bits %#x", contract.properties)}
		}
	}
	return contract, nil
}

func newSemiringRaw(provider SemiringProvider, contract semiringContract) (rawResource, error) {
	host := &semiringHost{
		provider: provider,
		contract: contract,
		gate:     callbackGate{parallel: contract.flags&SemiringParallelReentrant != 0},
	}
	context := &hostedContext{capabilities: contract.capabilities, semiring: host}
	return newHostedContext(context, func(handle uintptr) rawResource {
		return abiMakeSemiringResource(handle, contract.flags, contract.domain, contract.capabilities, uint64(contract.properties))
	})
}

func (host *semiringHost) newToken(context *hostedContext, value any) (abiSemiringValue, error) {
	if nilProvider(value) {
		return abiSemiringValue{}, &Error{Operation: "own semiring value", Status: StatusProviderError, Cause: fmt.Errorf("provider returned a nil value")}
	}
	handle := cgo.NewHandle(&hostedSemiringToken{context: context, value: value})
	return abiSemiringValue{word0: uint64(handle), word1: uint64(context.handle)}, nil
}

func (host *semiringHost) resolveToken(context *hostedContext, token abiSemiringValue) (any, error) {
	if token.word0 == 0 || token.word1 != uint64(context.handle) {
		return nil, &Error{Operation: "resolve semiring value", Status: StatusInvalidArgument, Cause: fmt.Errorf("token belongs to another operation context")}
	}
	value := cgo.Handle(token.word0).Value()
	boxed, ok := value.(*hostedSemiringToken)
	if !ok || boxed == nil || boxed.context != context {
		return nil, &Error{Operation: "resolve semiring value", Status: StatusInvalidArgument, Cause: fmt.Errorf("token is stale or forged")}
	}
	return boxed.value, nil
}

func (host *semiringHost) releaseTokens(context *hostedContext, tokens []abiSemiringValue) error {
	if len(tokens) > maximumSemiringRelease {
		return &Error{Operation: "release semiring values", Status: StatusLimitExceeded}
	}
	handles := make([]cgo.Handle, 0, len(tokens))
	seen := make(map[uint64]struct{}, len(tokens))
	for _, token := range tokens {
		if _, duplicate := seen[token.word0]; duplicate {
			return &Error{Operation: "release semiring values", Status: StatusInvalidArgument, Cause: fmt.Errorf("duplicate owned token")}
		}
		seen[token.word0] = struct{}{}
		if _, err := host.resolveToken(context, token); err != nil {
			return err
		}
		handles = append(handles, cgo.Handle(token.word0))
	}
	for _, handle := range handles {
		handle.Delete()
	}
	return nil
}

func (host *semiringHost) binary(context *hostedContext, leftToken, rightToken abiSemiringValue, operation string) (abiSemiringValue, bool, error) {
	left, err := host.resolveToken(context, leftToken)
	if err != nil {
		return abiSemiringValue{}, false, err
	}
	right, err := host.resolveToken(context, rightToken)
	if err != nil {
		return abiSemiringValue{}, false, err
	}
	var result any
	defined := true
	switch operation {
	case "plus":
		result, err = host.provider.Plus(left, right)
	case "times":
		result, err = host.provider.Times(left, right)
	case "divide":
		provider, ok := host.provider.(DivisibleSemiringProvider)
		if !ok {
			return abiSemiringValue{}, false, &Error{Operation: "divide semiring values", Status: StatusUnsupported}
		}
		result, defined, err = provider.Divide(left, right)
	case "left-divide":
		provider, ok := host.provider.(DivisibleSemiringProvider)
		if !ok {
			return abiSemiringValue{}, false, &Error{Operation: "left-divide semiring values", Status: StatusUnsupported}
		}
		result, defined, err = provider.LeftDivide(left, right)
	default:
		return abiSemiringValue{}, false, &Error{Operation: "combine semiring values", Status: StatusInvalidArgument}
	}
	if err != nil || !defined {
		return abiSemiringValue{}, defined, err
	}
	token, err := host.newToken(context, result)
	return token, true, err
}

func (host *semiringHost) fold(context *hostedContext, tokens []abiSemiringValue, times bool) (abiSemiringValue, error) {
	if len(tokens) > maximumSemiringFold {
		return abiSemiringValue{}, &Error{Operation: "fold semiring values", Status: StatusLimitExceeded}
	}
	values := make([]any, len(tokens))
	for index, token := range tokens {
		value, err := host.resolveToken(context, token)
		if err != nil {
			return abiSemiringValue{}, err
		}
		values[index] = value
	}
	var result any
	var err error
	if batch, ok := host.provider.(BatchSemiringProvider); ok {
		if times {
			result, err = batch.TimesMany(values)
		} else {
			result, err = batch.PlusMany(values)
		}
	} else if len(values) == 0 {
		if times {
			result, err = host.provider.One()
		} else {
			result, err = host.provider.Zero()
		}
	} else {
		result = values[0]
		for _, value := range values[1:] {
			if times {
				result, err = host.provider.Times(result, value)
			} else {
				result, err = host.provider.Plus(result, value)
			}
			if err != nil {
				break
			}
		}
	}
	if err != nil {
		return abiSemiringValue{}, err
	}
	return host.newToken(context, result)
}

type sharedLease struct {
	state       atomic.Uint64
	releaseOnce sync.Once
	release     func()
}

func (lease *sharedLease) acquire() bool {
	for {
		state := lease.state.Load()
		if state&resourceClosedBit != 0 || state == resourceClosedBit-1 {
			return false
		}
		if lease.state.CompareAndSwap(state, state+1) {
			return true
		}
	}
}

func (lease *sharedLease) releaseBorrow() {
	if lease.state.Add(^uint64(0)) == resourceClosedBit {
		lease.finish()
	}
}

func (lease *sharedLease) close() {
	for {
		state := lease.state.Load()
		if state&resourceClosedBit != 0 {
			return
		}
		if lease.state.CompareAndSwap(state, state|resourceClosedBit) {
			if state == 0 {
				lease.finish()
			}
			return
		}
	}
}

func (lease *sharedLease) finish() {
	lease.releaseOnce.Do(lease.release)
}

type semiringCore struct {
	raw        rawResource
	flags      SemiringFlags
	domain     InterfaceID
	references atomic.Int64
	release    sync.Once
}

func (core *semiringCore) retain() bool {
	for {
		count := core.references.Load()
		if count <= 0 {
			return false
		}
		if count == math.MaxInt64 {
			return false
		}
		if core.references.CompareAndSwap(count, count+1) {
			return true
		}
	}
}

func (core *semiringCore) drop() {
	remaining := core.references.Add(-1)
	if remaining < 0 {
		panic("semiring core reference underflow")
	}
	if remaining == 0 {
		core.release.Do(func() { abiReleaseResource(core.raw) })
	}
}

// SemiringContext owns a dynamic operation context imported from any binding.
type SemiringContext struct {
	core  *semiringCore
	lease *sharedLease
}

func wrapSemiring(raw rawResource, adopted bool) (*SemiringContext, error) {
	flags, domain, err := abiSemiringMetadata(raw)
	if err != nil {
		if adopted {
			abiReleaseResource(raw)
		}
		return nil, err
	}
	if flags&^knownSemiringFlags != 0 {
		if adopted {
			abiReleaseResource(raw)
		}
		return nil, &Error{Operation: "open semiring context", Status: StatusUnsupported, Cause: fmt.Errorf("unknown flags %#x", flags)}
	}
	if !adopted {
		raw, err = abiRetainResource(raw)
		if err != nil {
			return nil, err
		}
	}
	core := &semiringCore{raw: raw, flags: flags, domain: domain}
	core.references.Store(1)
	context := &SemiringContext{core: core}
	context.lease = &sharedLease{release: core.drop}
	runtime.SetFinalizer(context, (*SemiringContext).Close)
	return context, nil
}

// NewSemiringContext exposes a Go provider through the stable dynamic ABI.
func NewSemiringContext(provider SemiringProvider, options SemiringOptions) (*SemiringContext, error) {
	contract, err := semiringContractFor(provider, options)
	if err != nil {
		return nil, err
	}
	raw, err := newSemiringRaw(provider, contract)
	if err != nil {
		return nil, err
	}
	return wrapSemiring(raw, true)
}

// OpenSemiringContext retains a dynamic semiring from another binding.
func OpenSemiringContext(source NativeResource) (*SemiringContext, error) {
	raw, err := retainRawResource(source)
	if err != nil {
		return nil, err
	}
	return wrapSemiring(raw, true)
}

func (context *SemiringContext) withRaw(operation string, callback func(rawResource) error) error {
	if context == nil || context.core == nil || context.lease == nil || !context.lease.acquire() {
		return &Error{Operation: operation, Status: StatusClosed}
	}
	defer context.lease.releaseBorrow()
	return callback(context.core.raw)
}

// WithResource lends the operation-context resource to another project.
func (context *SemiringContext) WithResource(callback func(context, vtable uintptr) error) error {
	if callback == nil {
		return &Error{Operation: "borrow semiring context", Status: StatusInvalidArgument}
	}
	return context.withRaw("borrow semiring context", func(raw rawResource) error {
		return callback(raw.context, raw.vtable)
	})
}

// Close closes this context view. Existing values retain the native operation
// context until their own deterministic Close calls complete.
func (context *SemiringContext) Close() {
	if context == nil || context.lease == nil {
		return
	}
	runtime.SetFinalizer(context, nil)
	context.lease.close()
}

// DomainID identifies the algebra implemented by this context.
func (context *SemiringContext) DomainID() InterfaceID {
	if context == nil || context.core == nil {
		return InterfaceID{}
	}
	return context.core.domain
}

// Flags returns the validated dynamic-semiring flags.
func (context *SemiringContext) Flags() SemiringFlags {
	if context == nil || context.core == nil {
		return 0
	}
	return context.core.flags
}

func (context *SemiringContext) value(token abiSemiringValue) (*SemiringValue, error) {
	if context == nil || context.core == nil {
		return nil, &Error{Operation: "own semiring result", Status: StatusClosed}
	}
	if !context.core.retain() {
		_ = abiSemiringRelease(context.core.raw, []abiSemiringValue{token})
		return nil, &Error{Operation: "own semiring result", Status: StatusClosed}
	}
	value := &SemiringValue{core: context.core, token: token}
	value.lease = &sharedLease{release: func() {
		_ = abiSemiringRelease(value.core.raw, []abiSemiringValue{value.token})
		value.core.drop()
	}}
	runtime.SetFinalizer(value, (*SemiringValue).Close)
	return value, nil
}

func (context *SemiringContext) nullary(one bool) (*SemiringValue, error) {
	var result *SemiringValue
	err := context.withRaw("construct semiring identity", func(raw rawResource) error {
		var callErr error
		operation := "construct semiring zero"
		if one {
			operation = "construct semiring one"
		}
		token, callErr := abiSemiringNullary(operation, raw, one)
		if callErr != nil {
			return callErr
		}
		result, callErr = context.value(token)
		return callErr
	})
	if err != nil {
		return nil, err
	}
	return result, nil
}

// Zero returns an independently owned additive identity.
func (context *SemiringContext) Zero() (*SemiringValue, error) { return context.nullary(false) }

// One returns an independently owned multiplicative identity.
func (context *SemiringContext) One() (*SemiringValue, error) { return context.nullary(true) }

// NewValue publishes one immutable value in a Go-hosted operation context.
// Foreign contexts reject the operation because only their originating
// runtime knows how to encode a host-language value into an owned token.
func (context *SemiringContext) NewValue(value any) (*SemiringValue, error) {
	var result *SemiringValue
	err := context.withRaw("publish semiring value", func(raw rawResource) error {
		hosted, ok := localHostedResource(raw)
		if !ok || hosted.semiring == nil {
			return &Error{Operation: "publish semiring value", Status: StatusUnsupported, Cause: fmt.Errorf("context is hosted by another runtime")}
		}
		token, tokenErr := hosted.semiring.newToken(hosted, value)
		if tokenErr != nil {
			return tokenErr
		}
		result, tokenErr = context.value(token)
		return tokenErr
	})
	if err != nil {
		return nil, err
	}
	return result, nil
}

func borrowSemiringValues(core *semiringCore, values []*SemiringValue) ([]abiSemiringValue, func(), error) {
	tokens := make([]abiSemiringValue, 0, len(values))
	acquired := make([]*sharedLease, 0, len(values))
	release := func() {
		for index := len(acquired) - 1; index >= 0; index-- {
			acquired[index].releaseBorrow()
		}
	}
	for _, value := range values {
		if value == nil || value.core != core || value.lease == nil || !value.lease.acquire() {
			release()
			return nil, nil, &Error{Operation: "borrow semiring values", Status: StatusInvalidArgument, Cause: fmt.Errorf("closed value or context mismatch")}
		}
		acquired = append(acquired, value.lease)
		tokens = append(tokens, value.token)
	}
	return tokens, release, nil
}

func (context *SemiringContext) binary(left, right *SemiringValue, kind string) (*SemiringValue, bool, error) {
	if context == nil || context.core == nil || context.lease == nil {
		return nil, false, &Error{Operation: "combine semiring values", Status: StatusClosed}
	}
	tokens, release, err := borrowSemiringValues(context.core, []*SemiringValue{left, right})
	if err != nil {
		return nil, false, err
	}
	defer release()
	var value *SemiringValue
	defined := false
	err = context.withRaw("combine semiring values", func(raw rawResource) error {
		operation := kind + " semiring values"
		var callErr error
		var token abiSemiringValue
		token, defined, callErr = abiSemiringBinary(operation, raw, tokens[0], tokens[1], kind)
		if callErr != nil || !defined {
			return callErr
		}
		value, callErr = context.value(token)
		return callErr
	})
	if err != nil || !defined {
		return nil, defined, err
	}
	return value, true, nil
}

// Plus adds two values in this exact operation context.
func (context *SemiringContext) Plus(left, right *SemiringValue) (*SemiringValue, error) {
	value, _, err := context.binary(left, right, "plus")
	return value, err
}

// Times multiplies two values in this exact operation context.
func (context *SemiringContext) Times(left, right *SemiringValue) (*SemiringValue, error) {
	value, _, err := context.binary(left, right, "times")
	return value, err
}

// Divide returns false when division is undefined for this operand pair.
func (context *SemiringContext) Divide(dividend, divisor *SemiringValue) (*SemiringValue, bool, error) {
	return context.binary(dividend, divisor, "divide")
}

// LeftDivide returns false when weak left division is undefined.
func (context *SemiringContext) LeftDivide(value, divisor *SemiringValue) (*SemiringValue, bool, error) {
	return context.binary(value, divisor, "left-divide")
}

func (context *SemiringContext) compare(left, right *SemiringValue, epsilon *float64) (bool, error) {
	if context == nil || context.core == nil || context.lease == nil {
		return false, &Error{Operation: "compare semiring values", Status: StatusClosed}
	}
	tokens, release, err := borrowSemiringValues(context.core, []*SemiringValue{left, right})
	if err != nil {
		return false, err
	}
	defer release()
	var result bool
	err = context.withRaw("compare semiring values", func(raw rawResource) error {
		var callErr error
		operation := "compare semiring values"
		if epsilon != nil {
			if math.IsNaN(*epsilon) || math.IsInf(*epsilon, 0) || *epsilon < 0 {
				return &Error{Operation: operation, Status: StatusInvalidArgument, Cause: fmt.Errorf("epsilon must be finite and nonnegative")}
			}
			operation = "approximately compare semiring values"
		}
		result, callErr = abiSemiringBool(operation, raw, tokens[0], tokens[1], epsilon)
		return callErr
	})
	return result, err
}

// Equal performs exact provider-defined equality.
func (context *SemiringContext) Equal(left, right *SemiringValue) (bool, error) {
	return context.compare(left, right, nil)
}

// ApproxEqual performs provider-defined numerical equality.
func (context *SemiringContext) ApproxEqual(left, right *SemiringValue, epsilon float64) (bool, error) {
	return context.compare(left, right, &epsilon)
}

// NaturalOrder compares two values under the semiring-induced order.
func (context *SemiringContext) NaturalOrder(left, right *SemiringValue) (NaturalOrder, error) {
	if context == nil || context.core == nil || context.lease == nil {
		return 0, &Error{Operation: "compare semiring natural order", Status: StatusClosed}
	}
	tokens, release, err := borrowSemiringValues(context.core, []*SemiringValue{left, right})
	if err != nil {
		return 0, err
	}
	defer release()
	var result NaturalOrder
	err = context.withRaw("compare semiring natural order", func(raw rawResource) error {
		var callErr error
		result, callErr = abiSemiringNaturalOrder(raw, tokens[0], tokens[1])
		return callErr
	})
	return result, err
}

func (context *SemiringContext) many(values []*SemiringValue, times bool) (*SemiringValue, error) {
	if context == nil || context.core == nil || context.lease == nil {
		return nil, &Error{Operation: "fold semiring values", Status: StatusClosed}
	}
	if len(values) > maximumSemiringFold {
		return nil, &Error{Operation: "fold semiring values", Status: StatusLimitExceeded}
	}
	tokens, release, err := borrowSemiringValues(context.core, values)
	if err != nil {
		return nil, err
	}
	defer release()
	var result *SemiringValue
	err = context.withRaw("fold semiring values", func(raw rawResource) error {
		operation := "add semiring values"
		if times {
			operation = "multiply semiring values"
		}
		var callErr error
		token, callErr := abiSemiringMany(operation, raw, tokens, times)
		if callErr != nil {
			return callErr
		}
		result, callErr = context.value(token)
		return callErr
	})
	if err != nil {
		return nil, err
	}
	return result, nil
}

// PlusMany performs one bounded additive fold.
func (context *SemiringContext) PlusMany(values ...*SemiringValue) (*SemiringValue, error) {
	return context.many(values, false)
}

// TimesMany performs one bounded multiplicative fold.
func (context *SemiringContext) TimesMany(values ...*SemiringValue) (*SemiringValue, error) {
	return context.many(values, true)
}

// Properties returns validated law-bearing capability bits.
func (context *SemiringContext) Properties() (SemiringProperties, error) {
	var properties SemiringProperties
	err := context.withRaw("read semiring properties", func(raw rawResource) error {
		var callErr error
		properties, callErr = abiSemiringProperties(raw)
		if callErr == nil && properties&^knownSemiringProperties != 0 {
			callErr = &Error{Operation: "read semiring properties", Status: StatusProviderError, Cause: fmt.Errorf("unknown property bits %#x", properties)}
		}
		return callErr
	})
	return properties, err
}

// ClosureBound returns an optional finite bound for a K-closed semiring.
func (context *SemiringContext) ClosureBound() (uint64, bool, error) {
	var bound uint64
	var known bool
	err := context.withRaw("read semiring closure bound", func(raw rawResource) error {
		var callErr error
		bound, known, callErr = abiSemiringClosureBound(raw)
		return callErr
	})
	return bound, known, err
}

// SemiringValue owns exactly one provider token and keeps its operation
// context alive independently of the public SemiringContext view.
type SemiringValue struct {
	core  *semiringCore
	token abiSemiringValue
	lease *sharedLease
}

// Close consumes the owned provider token exactly once.
func (value *SemiringValue) Close() {
	if value == nil || value.lease == nil {
		return
	}
	runtime.SetFinalizer(value, nil)
	value.lease.close()
}

// Clone returns an independently owned provider token.
func (value *SemiringValue) Clone() (*SemiringValue, error) {
	if value == nil || value.lease == nil || !value.lease.acquire() {
		return nil, &Error{Operation: "clone semiring value", Status: StatusClosed}
	}
	defer value.lease.releaseBorrow()
	token, err := abiSemiringClone(value.core.raw, value.token)
	if err != nil {
		return nil, err
	}
	context := &SemiringContext{core: value.core}
	return context.value(token)
}

func (value *SemiringValue) bytes(diagnostic bool) ([]byte, error) {
	if value == nil || value.lease == nil || !value.lease.acquire() {
		return nil, &Error{Operation: "read semiring value", Status: StatusClosed}
	}
	defer value.lease.releaseBorrow()
	return abiSemiringBytes(value.core.raw, value.token, diagnostic)
}

// StableBytes returns the canonical encoding when advertised.
func (value *SemiringValue) StableBytes() ([]byte, error) {
	if value == nil || value.core.flags&SemiringStableBytes == 0 {
		return nil, &Error{Operation: "read semiring stable bytes", Status: StatusUnsupported}
	}
	return value.bytes(false)
}

// Diagnostic returns the provider's human-readable representation.
func (value *SemiringValue) Diagnostic() (string, error) {
	bytes, err := value.bytes(true)
	if err == nil && !utf8.Valid(bytes) {
		err = &Error{Operation: "read semiring diagnostic", Status: StatusProviderError, Cause: fmt.Errorf("provider returned invalid UTF-8")}
	}
	return string(bytes), err
}

// LocalValue resolves a Go-hosted token without crossing the native boundary.
func (value *SemiringValue) LocalValue() (any, bool) {
	if value == nil || value.lease == nil || !value.lease.acquire() {
		return nil, false
	}
	defer value.lease.releaseBorrow()
	context, ok := localHostedResource(value.core.raw)
	if !ok || context.semiring == nil {
		return nil, false
	}
	resolved, err := context.semiring.resolveToken(context, value.token)
	return resolved, err == nil
}

// Star computes Kleene closure and returns false when it does not converge.
func (value *SemiringValue) Star() (*SemiringValue, bool, error) {
	if value == nil || value.lease == nil || !value.lease.acquire() {
		return nil, false, &Error{Operation: "close semiring value", Status: StatusClosed}
	}
	defer value.lease.releaseBorrow()
	token, converged, err := abiSemiringStar(value.core.raw, value.token)
	if err != nil || !converged {
		return nil, converged, err
	}
	context := &SemiringContext{core: value.core}
	result, err := context.value(token)
	return result, true, err
}

func (value *SemiringValue) numeric(operation, kind string, epsilon float64) (float64, int64, error) {
	if value == nil || value.lease == nil || !value.lease.acquire() {
		return 0, 0, &Error{Operation: operation, Status: StatusClosed}
	}
	defer value.lease.releaseBorrow()
	return abiSemiringNumeric(operation, value.core.raw, value.token, kind, epsilon)
}

// NumericalValue projects this value into a scalar measure.
func (value *SemiringValue) NumericalValue() (float64, error) {
	result, _, err := value.numeric("project semiring numerical value", "value", 0)
	return result, err
}

// Quantize maps this value to a stable epsilon-dependent integer bucket.
func (value *SemiringValue) Quantize(epsilon float64) (int64, error) {
	if math.IsNaN(epsilon) || math.IsInf(epsilon, 0) || epsilon <= 0 {
		return 0, &Error{Operation: "quantize semiring value", Status: StatusInvalidArgument, Cause: fmt.Errorf("epsilon must be finite and positive")}
	}
	_, result, err := value.numeric("quantize semiring value", "quantize", epsilon)
	return result, err
}

// ToProbability projects this value into its probability interpretation.
func (value *SemiringValue) ToProbability() (float64, error) {
	result, _, err := value.numeric("project semiring probability", "probability", 0)
	return result, err
}
