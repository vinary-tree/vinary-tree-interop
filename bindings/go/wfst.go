package interop

import (
	"fmt"
	"math"
	"runtime"
)

// UnitDomain is the exact edge-label representation of a scalar WFST.
type UnitDomain uint32

const (
	UnitByte          UnitDomain = 1
	UnitUnicodeScalar UnitDomain = 2
	UnitU64           UnitDomain = 3
)

func (domain UnitDomain) valid() bool {
	return domain >= UnitByte && domain <= UnitU64
}

// WeightDomain identifies the portable scalar-semiring interpretation.
type WeightDomain uint32

const (
	WeightTropicalF64       WeightDomain = 1
	WeightLogF64            WeightDomain = 2
	WeightProbabilityF64    WeightDomain = 3
	WeightArcticF64         WeightDomain = 4
	WeightSignedTropicalF64 WeightDomain = 5
	WeightCountF64          WeightDomain = 6
	WeightBooleanF64        WeightDomain = 7
)

func (domain WeightDomain) valid() bool {
	return domain >= WeightTropicalF64 && domain <= WeightBooleanF64
}

// WfstFlags describe immutable graph, concurrency, and topology properties.
type WfstFlags uint64

const (
	WfstParallelReentrant WfstFlags = 1
	WfstImmutable         WfstFlags = 2
	WfstLazy              WfstFlags = 4
	WfstAcyclic           WfstFlags = 8
)

const knownWfstFlags = WfstParallelReentrant | WfstImmutable | WfstLazy | WfstAcyclic
const maximumWfstPage = 1 << 20

// ScalarWfstOptions declares the exact domains and capability promises of an
// immutable Go graph.
type ScalarWfstOptions struct {
	UnitDomain        UnitDomain
	WeightDomain      WeightDomain
	ParallelReentrant bool
	Lazy              bool
	Acyclic           bool
}

func (options ScalarWfstOptions) contract() (wfstContract, error) {
	if !options.UnitDomain.valid() || !options.WeightDomain.valid() {
		return wfstContract{}, &Error{Operation: "host scalar WFST", Status: StatusInvalidArgument, Cause: fmt.Errorf("unknown unit or weight domain")}
	}
	flags := WfstImmutable
	if options.ParallelReentrant {
		flags |= WfstParallelReentrant
	}
	if options.Lazy {
		flags |= WfstLazy
	}
	if options.Acyclic {
		flags |= WfstAcyclic
	}
	return wfstContract{unit: options.UnitDomain, weight: options.WeightDomain, flags: flags}, nil
}

// WfstStateInfo is finality metadata for one provider-scoped state ID.
type WfstStateInfo struct {
	Valid       bool
	Final       bool
	FinalWeight float64
}

// WfstArc is one scalar weighted transition. HasInput or HasOutput false
// denotes epsilon on that tape; zero remains a valid non-epsilon label.
type WfstArc struct {
	Input     uint64
	Output    uint64
	Target    uint64
	Weight    float64
	HasInput  bool
	HasOutput bool
}

// WfstArcPage is one bounded page plus the complete outgoing arc count.
type WfstArcPage struct {
	Arcs  []WfstArc
	Total uint64
}

// ScalarWfstProvider is an immutable graph implemented in Go.
type ScalarWfstProvider interface {
	StartState() (uint64, error)
	StateCount() (count uint64, known bool, err error)
	StateInfo(state uint64) (WfstStateInfo, error)
	StateArcs(state uint64) ([]WfstArc, error)
}

// PagedScalarWfstProvider avoids full outgoing-list materialization for lazy
// or very high-degree states.
type PagedScalarWfstProvider interface {
	ScalarWfstProvider
	StateArcsPage(state, start uint64, capacity int) (WfstArcPage, error)
}

type wfstContract struct {
	unit   UnitDomain
	weight WeightDomain
	flags  WfstFlags
}

type wfstHost struct {
	provider ScalarWfstProvider
	contract wfstContract
	gate     callbackGate
}

func validUnicodeScalar(value uint64) bool {
	return value <= 0x10ffff && !(value >= 0xd800 && value <= 0xdfff)
}

func validateWfstArc(arc WfstArc, domain UnitDomain) error {
	if math.IsNaN(arc.Weight) {
		return fmt.Errorf("arc weight is NaN")
	}
	if arc.HasInput {
		switch domain {
		case UnitByte:
			if arc.Input > 0xff {
				return fmt.Errorf("input label exceeds the byte domain")
			}
		case UnitUnicodeScalar:
			if !validUnicodeScalar(arc.Input) {
				return fmt.Errorf("input label is not a Unicode scalar")
			}
		}
	}
	if arc.HasOutput {
		switch domain {
		case UnitByte:
			if arc.Output > 0xff {
				return fmt.Errorf("output label exceeds the byte domain")
			}
		case UnitUnicodeScalar:
			if !validUnicodeScalar(arc.Output) {
				return fmt.Errorf("output label is not a Unicode scalar")
			}
		}
	}
	return nil
}

func newWfstRaw(provider ScalarWfstProvider, contract wfstContract) (rawResource, error) {
	if err := requireProvider("scalar WFST", provider); err != nil {
		return rawResource{}, err
	}
	host := &wfstHost{
		provider: provider,
		contract: contract,
		gate:     callbackGate{parallel: contract.flags&WfstParallelReentrant != 0},
	}
	context := &hostedContext{capabilities: capabilityWfst, wfst: host}
	return newHostedContext(context, func(handle uintptr) rawResource {
		return abiMakeWfstResource(handle, contract.unit, contract.weight, contract.flags)
	})
}

func (host *wfstHost) stateArcs(state uint64) ([]WfstArc, error) {
	arcs, err := host.provider.StateArcs(state)
	if err == nil {
		arcs = append([]WfstArc(nil), arcs...)
		for _, arc := range arcs {
			if invalid := validateWfstArc(arc, host.contract.unit); invalid != nil {
				err = &Error{Operation: "validate scalar WFST arc", Status: StatusProviderError, Cause: invalid}
				arcs = nil
				break
			}
		}
	}
	return arcs, err
}

func (host *wfstHost) stateArcsPage(state, start uint64, capacity int) (WfstArcPage, error) {
	if capacity < 0 || capacity > maximumWfstPage {
		return WfstArcPage{}, &Error{Operation: "page scalar WFST arcs", Status: StatusLimitExceeded}
	}
	if paged, ok := host.provider.(PagedScalarWfstProvider); ok {
		page, err := paged.StateArcsPage(state, start, capacity)
		if err != nil {
			return WfstArcPage{}, err
		}
		if len(page.Arcs) > capacity || start > page.Total || start+uint64(len(page.Arcs)) > page.Total || (capacity > 0 && len(page.Arcs) == 0 && start < page.Total) {
			return WfstArcPage{}, &Error{Operation: "page scalar WFST arcs", Status: StatusProviderError, Cause: fmt.Errorf("provider returned inconsistent page bounds")}
		}
		result := WfstArcPage{Arcs: append([]WfstArc(nil), page.Arcs...), Total: page.Total}
		for _, arc := range result.Arcs {
			if err := validateWfstArc(arc, host.contract.unit); err != nil {
				return WfstArcPage{}, &Error{Operation: "validate scalar WFST arc", Status: StatusProviderError, Cause: err}
			}
		}
		return result, nil
	}
	arcs, err := host.stateArcs(state)
	if err != nil {
		return WfstArcPage{}, err
	}
	total := uint64(len(arcs))
	if start >= total {
		return WfstArcPage{Arcs: []WfstArc{}, Total: total}, nil
	}
	end := start + uint64(capacity)
	if end > total {
		end = total
	}
	return WfstArcPage{Arcs: append([]WfstArc(nil), arcs[start:end]...), Total: total}, nil
}

// ScalarWfst is an owned consumer view over any version-1 scalar-WFST resource.
type ScalarWfst struct {
	resource *Resource
	contract wfstContract
}

func wrapScalarWfst(raw rawResource, adopted bool) (*ScalarWfst, error) {
	unit, weight, flags, err := abiWfstMetadata(raw)
	if err != nil {
		if adopted {
			abiReleaseResource(raw)
		}
		return nil, err
	}
	if !unit.valid() || !weight.valid() || flags&^knownWfstFlags != 0 {
		if adopted {
			abiReleaseResource(raw)
		}
		return nil, &Error{Operation: "open scalar WFST", Status: StatusUnsupported, Cause: fmt.Errorf("unknown domain or flags")}
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
	wfst := &ScalarWfst{resource: resource, contract: wfstContract{unit: unit, weight: weight, flags: flags}}
	runtime.SetFinalizer(wfst, (*ScalarWfst).Close)
	return wfst, nil
}

// NewScalarWfst exposes an immutable Go provider through the native ABI.
func NewScalarWfst(provider ScalarWfstProvider, options ScalarWfstOptions) (*ScalarWfst, error) {
	contract, err := options.contract()
	if err != nil {
		return nil, err
	}
	raw, err := newWfstRaw(provider, contract)
	if err != nil {
		return nil, err
	}
	return wrapScalarWfst(raw, true)
}

// OpenScalarWfst retains a scalar-WFST resource from another project binding.
func OpenScalarWfst(source NativeResource) (*ScalarWfst, error) {
	raw, err := retainRawResource(source)
	if err != nil {
		return nil, err
	}
	return wrapScalarWfst(raw, true)
}

// WithResource lends this graph to another project facade.
func (wfst *ScalarWfst) WithResource(callback func(context, vtable uintptr) error) error {
	if wfst == nil || wfst.resource == nil {
		return &Error{Operation: "borrow scalar WFST", Status: StatusClosed}
	}
	return wfst.resource.WithResource(callback)
}

// Close releases the graph exactly once.
func (wfst *ScalarWfst) Close() {
	if wfst == nil {
		return
	}
	runtime.SetFinalizer(wfst, nil)
	if wfst.resource != nil {
		wfst.resource.Close()
	}
}

func (wfst *ScalarWfst) withRaw(operation string, callback func(rawResource) error) error {
	if wfst == nil || wfst.resource == nil {
		return &Error{Operation: operation, Status: StatusClosed}
	}
	return wfst.resource.withRaw(operation, callback)
}

// UnitDomain returns the exact edge-label domain.
func (wfst *ScalarWfst) UnitDomain() UnitDomain {
	if wfst == nil {
		return 0
	}
	return wfst.contract.unit
}

// WeightDomain returns the scalar-semiring representation.
func (wfst *ScalarWfst) WeightDomain() WeightDomain {
	if wfst == nil {
		return 0
	}
	return wfst.contract.weight
}

// Flags returns the validated graph capabilities.
func (wfst *ScalarWfst) Flags() WfstFlags {
	if wfst == nil {
		return 0
	}
	return wfst.contract.flags
}

// Snapshot captures an independent owned retain of the same immutable revision.
func (wfst *ScalarWfst) Snapshot() (*ScalarWfst, error) {
	var output rawResource
	err := wfst.withRaw("capture scalar WFST snapshot", func(raw rawResource) error {
		var callErr error
		output, callErr = abiWfstSnapshot(raw)
		return callErr
	})
	if err != nil {
		return nil, err
	}
	return wrapScalarWfst(output, true)
}

// StartState returns the provider-scoped start identifier.
func (wfst *ScalarWfst) StartState() (uint64, error) {
	var state uint64
	err := wfst.withRaw("read scalar WFST start state", func(raw rawResource) error {
		var callErr error
		state, callErr = abiWfstStart(raw)
		return callErr
	})
	return state, err
}

// StateCount returns the exact size when known without forcing lazy expansion.
func (wfst *ScalarWfst) StateCount() (uint64, bool, error) {
	var count uint64
	var known bool
	err := wfst.withRaw("read scalar WFST state count", func(raw rawResource) error {
		var callErr error
		count, known, callErr = abiWfstStateCount(raw)
		return callErr
	})
	return count, known, err
}

// StateInfo returns metadata for an arbitrary provider-scoped state ID.
func (wfst *ScalarWfst) StateInfo(state uint64) (WfstStateInfo, error) {
	var info WfstStateInfo
	err := wfst.withRaw("read scalar WFST state metadata", func(raw rawResource) error {
		var callErr error
		info.Valid, info.Final, info.FinalWeight, callErr = abiWfstStateInfo(raw, state)
		if callErr == nil && math.IsNaN(info.FinalWeight) {
			callErr = &Error{Operation: "read scalar WFST state metadata", Status: StatusProviderError, Cause: fmt.Errorf("provider returned a NaN final weight")}
		}
		return callErr
	})
	return info, err
}

// StateArcsPage copies one bounded outgoing-arc page.
func (wfst *ScalarWfst) StateArcsPage(state, start uint64, capacity int) (WfstArcPage, error) {
	if capacity <= 0 || capacity > maximumWfstPage {
		return WfstArcPage{}, &Error{Operation: "read scalar WFST arc page", Status: StatusInvalidArgument}
	}
	var page WfstArcPage
	err := wfst.withRaw("read scalar WFST arc page", func(raw rawResource) error {
		var callErr error
		page.Arcs, page.Total, callErr = abiWfstArcPage(raw, state, start, capacity)
		return callErr
	})
	return page, err
}

// StateArcs copies all outgoing arcs through progress-checked bounded pages.
func (wfst *ScalarWfst) StateArcs(state uint64, batchSize int) ([]WfstArc, error) {
	if batchSize <= 0 || batchSize > maximumWfstPage {
		return nil, &Error{Operation: "read scalar WFST arcs", Status: StatusInvalidArgument}
	}
	result := make([]WfstArc, 0, batchSize)
	var start uint64
	var expected *uint64
	for expected == nil || start < *expected {
		page, err := wfst.StateArcsPage(state, start, batchSize)
		if err != nil {
			return nil, err
		}
		if expected != nil && page.Total != *expected {
			return nil, &Error{Operation: "read scalar WFST arcs", Status: StatusProviderError, Cause: fmt.Errorf("provider changed total arc count during traversal")}
		}
		if len(page.Arcs) == 0 && start < page.Total {
			return nil, &Error{Operation: "read scalar WFST arcs", Status: StatusProviderError, Cause: fmt.Errorf("provider made no paging progress")}
		}
		total := page.Total
		expected = &total
		result = append(result, page.Arcs...)
		start += uint64(len(page.Arcs))
	}
	return result, nil
}
