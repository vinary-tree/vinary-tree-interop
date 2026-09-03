package interop

import (
	"encoding/binary"
	"errors"
	"fmt"
	"math"
	"sort"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

var (
	setDomain      = mustTestID("go.set.lattice.1")
	semiringDomain = mustTestID("go.tropical.f641")
)

func mustTestID(value string) InterfaceID {
	identifier, err := InterfaceIDFromASCII(value)
	if err != nil {
		panic(err)
	}
	return identifier
}

func requireStatus(t *testing.T, err error, expected Status) {
	t.Helper()
	var failure *Error
	if !errors.As(err, &failure) || failure.Status != expected {
		t.Fatalf("expected status %d, found %v", expected, err)
	}
}

type setLattice struct {
	values     []uint32
	last       **LatticeOperand
	batchCalls *atomic.Int64
	block      <-chan struct{}
	entered    chan<- struct{}
	panicJoin  bool
}

func newSetLattice(values ...uint32) *setLattice {
	return (&setLattice{values: values}).normalized()
}

func (value *setLattice) normalized() *setLattice {
	result := *value
	result.values = append([]uint32(nil), value.values...)
	sort.Slice(result.values, func(left, right int) bool { return result.values[left] < result.values[right] })
	unique := result.values[:0]
	for _, item := range result.values {
		if len(unique) == 0 || unique[len(unique)-1] != item {
			unique = append(unique, item)
		}
	}
	result.values = unique
	return &result
}

func (value *setLattice) DomainID() InterfaceID { return setDomain }

func (value *setLattice) operand(other *LatticeOperand) (*setLattice, error) {
	if value.last != nil {
		*value.last = other
	}
	local, ok := other.LocalProvider()
	if !ok {
		return nil, fmt.Errorf("test expected a local Go operand")
	}
	result, ok := local.(*setLattice)
	if !ok {
		return nil, fmt.Errorf("test operand has type %T", local)
	}
	return result, nil
}

func (value *setLattice) Join(other *LatticeOperand) (LatticeProvider, error) {
	if value.panicJoin {
		panic("deliberate lattice provider panic")
	}
	right, err := value.operand(other)
	if err != nil {
		return nil, err
	}
	return newSetLattice(append(append([]uint32(nil), value.values...), right.values...)...), nil
}

func (value *setLattice) Meet(other *LatticeOperand) (LatticeProvider, error) {
	right, err := value.operand(other)
	if err != nil {
		return nil, err
	}
	rightValues := make(map[uint32]struct{}, len(right.values))
	for _, item := range right.values {
		rightValues[item] = struct{}{}
	}
	intersection := make([]uint32, 0, len(value.values))
	for _, item := range value.values {
		if _, present := rightValues[item]; present {
			intersection = append(intersection, item)
		}
	}
	return newSetLattice(intersection...), nil
}

func (value *setLattice) Equal(other *LatticeOperand) (bool, error) {
	right, err := value.operand(other)
	if err != nil || len(value.values) != len(right.values) {
		return false, err
	}
	for index := range value.values {
		if value.values[index] != right.values[index] {
			return false, nil
		}
	}
	return true, nil
}

func (value *setLattice) StableBytes() ([]byte, error) {
	result := make([]byte, 4*len(value.values))
	for index, item := range value.values {
		binary.LittleEndian.PutUint32(result[4*index:], item)
	}
	return result, nil
}

func (value *setLattice) Diagnostic() (string, error) {
	if value.entered != nil {
		select {
		case value.entered <- struct{}{}:
		default:
		}
	}
	if value.block != nil {
		<-value.block
	}
	parts := make([]string, len(value.values))
	for index, item := range value.values {
		parts[index] = fmt.Sprint(item)
	}
	return "{" + strings.Join(parts, ",") + "}", nil
}

func (value *setLattice) JoinMany(others []*LatticeOperand) (LatticeProvider, error) {
	if value.batchCalls != nil {
		value.batchCalls.Add(1)
	}
	var result LatticeProvider = value
	var err error
	for _, other := range others {
		result, err = result.Join(other)
		if err != nil {
			return nil, err
		}
	}
	return result, nil
}

func (value *setLattice) MeetMany(others []*LatticeOperand) (LatticeProvider, error) {
	if value.batchCalls != nil {
		value.batchCalls.Add(1)
	}
	var result LatticeProvider = value
	var err error
	for _, other := range others {
		result, err = result.Meet(other)
		if err != nil {
			return nil, err
		}
	}
	return result, nil
}

func TestGoLatticeProviderRoundTripLifecycleAndBatches(t *testing.T) {
	var escaped *LatticeOperand
	var batches atomic.Int64
	leftProvider := newSetLattice(1, 3)
	leftProvider.last = &escaped
	leftProvider.batchCalls = &batches
	left, err := NewLatticeValue(leftProvider, LatticeOptions{})
	if err != nil {
		t.Fatal(err)
	}
	defer left.Close()
	right, err := NewLatticeValue(newSetLattice(2, 3), LatticeOptions{})
	if err != nil {
		t.Fatal(err)
	}
	defer right.Close()

	joined, err := left.Join(right)
	if err != nil {
		t.Fatal(err)
	}
	defer joined.Close()
	diagnostic, err := joined.Diagnostic()
	if err != nil || diagnostic != "{1,2,3}" {
		t.Fatalf("unexpected join: %q, %v", diagnostic, err)
	}
	if escaped == nil {
		t.Fatal("provider did not observe its lexical operand")
	}
	if _, err := escaped.StableBytes(); err == nil {
		t.Fatal("escaped lattice operand remained usable")
	} else {
		requireStatus(t, err, StatusClosed)
	}

	met, err := left.Meet(right)
	if err != nil {
		t.Fatal(err)
	}
	defer met.Close()
	if diagnostic, err = met.Diagnostic(); err != nil || diagnostic != "{3}" {
		t.Fatalf("unexpected meet: %q, %v", diagnostic, err)
	}
	equal, err := left.Equal(left)
	if err != nil || !equal {
		t.Fatalf("self equality failed: %t, %v", equal, err)
	}
	encoded, err := joined.StableBytes()
	if err != nil || len(encoded) != 12 {
		t.Fatalf("stable encoding failed: %x, %v", encoded, err)
	}

	batched, err := left.JoinMany(right, met)
	if err != nil {
		t.Fatal(err)
	}
	defer batched.Close()
	if batches.Load() != 1 {
		t.Fatalf("expected one optimized batch callback, found %d", batches.Load())
	}
	if diagnostic, err = batched.Diagnostic(); err != nil || diagnostic != "{1,2,3}" {
		t.Fatalf("unexpected batch join: %q, %v", diagnostic, err)
	}

	copyView, err := OpenLatticeValue(left)
	if err != nil {
		t.Fatal(err)
	}
	left.Close()
	if diagnostic, err = copyView.Diagnostic(); err != nil || diagnostic != "{1,3}" {
		t.Fatalf("retained view did not survive source close: %q, %v", diagnostic, err)
	}
	copyView.Close()
	if _, err := copyView.Diagnostic(); err == nil {
		t.Fatal("closed lattice remained usable")
	} else {
		requireStatus(t, err, StatusClosed)
	}
}

func TestGoProviderPanicsAndConcurrentSerializedCallsDoNotCrossABI(t *testing.T) {
	panicking, err := NewLatticeValue((&setLattice{values: []uint32{1}, panicJoin: true}).normalized(), LatticeOptions{})
	if err != nil {
		t.Fatal(err)
	}
	defer panicking.Close()
	other, err := NewLatticeValue(newSetLattice(2), LatticeOptions{})
	if err != nil {
		t.Fatal(err)
	}
	defer other.Close()
	if _, err := panicking.Join(other); err == nil {
		t.Fatal("provider panic escaped as success")
	} else {
		requireStatus(t, err, StatusProviderError)
	}

	entered := make(chan struct{}, 1)
	unblock := make(chan struct{})
	serialized, err := NewLatticeValue((&setLattice{values: []uint32{1}, entered: entered, block: unblock}).normalized(), LatticeOptions{})
	if err != nil {
		t.Fatal(err)
	}
	defer serialized.Close()
	firstDone := make(chan error, 1)
	go func() {
		_, callErr := serialized.Diagnostic()
		firstDone <- callErr
	}()
	select {
	case <-entered:
	case <-time.After(2 * time.Second):
		t.Fatal("first serialized callback did not enter")
	}
	if _, err := serialized.Diagnostic(); err == nil {
		t.Fatal("concurrent serialized callback was not rejected")
	} else {
		requireStatus(t, err, StatusProviderError)
	}
	close(unblock)
	if err := <-firstDone; err != nil {
		t.Fatalf("first serialized callback failed: %v", err)
	}
}

type testWfst struct {
	invalid bool
}

func (testWfst) StartState() (uint64, error) { return 0, nil }

func (testWfst) StateCount() (uint64, bool, error) { return 2, true, nil }

func (testWfst) StateInfo(state uint64) (WfstStateInfo, error) {
	switch state {
	case 0:
		return WfstStateInfo{Valid: true}, nil
	case 1:
		return WfstStateInfo{Valid: true, Final: true, FinalWeight: 2.5}, nil
	default:
		return WfstStateInfo{}, nil
	}
}

func (provider testWfst) StateArcs(state uint64) ([]WfstArc, error) {
	if state != 0 {
		return []WfstArc{}, nil
	}
	label := uint64('a')
	if provider.invalid {
		label = 0xd800
	}
	return []WfstArc{
		{Input: label, Output: 'A', Target: 1, Weight: 1.25, HasInput: true, HasOutput: true},
		{Target: 1, Weight: 0.5},
	}, nil
}

type pagedProbeWfst struct {
	fullCalls atomic.Int64
	pageCalls atomic.Int64
}

func (*pagedProbeWfst) StartState() (uint64, error) { return 0, nil }

func (*pagedProbeWfst) StateCount() (uint64, bool, error) { return 1, true, nil }

func (*pagedProbeWfst) StateInfo(uint64) (WfstStateInfo, error) {
	return WfstStateInfo{Valid: true}, nil
}

func (provider *pagedProbeWfst) StateArcs(uint64) ([]WfstArc, error) {
	provider.fullCalls.Add(1)
	return nil, errors.New("full arc materialization was not expected")
}

func (provider *pagedProbeWfst) StateArcsPage(_ uint64, start uint64, capacity int) (WfstArcPage, error) {
	provider.pageCalls.Add(1)
	if start != 0 || capacity != 0 {
		return WfstArcPage{}, fmt.Errorf("unexpected probe page (%d, %d)", start, capacity)
	}
	return WfstArcPage{Arcs: []WfstArc{}, Total: 1_000_000}, nil
}

func TestWfstSizeProbeUsesPagedProviderWithoutMaterializingArcs(t *testing.T) {
	provider := &pagedProbeWfst{}
	host := &wfstHost{provider: provider, contract: wfstContract{unit: UnitUnicodeScalar}}
	page, err := host.stateArcsPage(0, 0, 0)
	if err != nil || len(page.Arcs) != 0 || page.Total != 1_000_000 {
		t.Fatalf("unexpected size probe: %+v, %v", page, err)
	}
	if calls := provider.fullCalls.Load(); calls != 0 {
		t.Fatalf("size probe materialized the complete arc list %d time(s)", calls)
	}
	if calls := provider.pageCalls.Load(); calls != 1 {
		t.Fatalf("size probe invoked paged provider %d time(s), want 1", calls)
	}
}

func TestGoScalarWfstProviderSnapshotPagingAndValidation(t *testing.T) {
	graph, err := NewScalarWfst(testWfst{}, ScalarWfstOptions{
		UnitDomain: UnitUnicodeScalar, WeightDomain: WeightTropicalF64, Acyclic: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	snapshot, err := graph.Snapshot()
	if err != nil {
		t.Fatal(err)
	}
	graph.Close()
	defer snapshot.Close()
	if start, err := snapshot.StartState(); err != nil || start != 0 {
		t.Fatalf("unexpected start state: %d, %v", start, err)
	}
	if count, known, err := snapshot.StateCount(); err != nil || !known || count != 2 {
		t.Fatalf("unexpected state count: %d, %t, %v", count, known, err)
	}
	if info, err := snapshot.StateInfo(1); err != nil || !info.Valid || !info.Final || info.FinalWeight != 2.5 {
		t.Fatalf("unexpected final state: %+v, %v", info, err)
	}
	first, err := snapshot.StateArcsPage(0, 0, 1)
	if err != nil || len(first.Arcs) != 1 || first.Total != 2 || first.Arcs[0].Input != 'a' {
		t.Fatalf("unexpected first page: %+v, %v", first, err)
	}
	arcs, err := snapshot.StateArcs(0, 1)
	if err != nil || len(arcs) != 2 || arcs[1].HasInput || arcs[1].HasOutput {
		t.Fatalf("unexpected complete arc list: %+v, %v", arcs, err)
	}

	invalid, err := NewScalarWfst(testWfst{invalid: true}, ScalarWfstOptions{
		UnitDomain: UnitUnicodeScalar, WeightDomain: WeightTropicalF64,
	})
	if err != nil {
		t.Fatal(err)
	}
	defer invalid.Close()
	if _, err := invalid.StateArcs(0, 16); err == nil {
		t.Fatal("surrogate arc label was accepted")
	} else {
		requireStatus(t, err, StatusProviderError)
	}
}

type tropicalSemiring struct {
	panicZero bool
	block     <-chan struct{}
	entered   chan<- struct{}
}

func (tropicalSemiring) DomainID() InterfaceID { return semiringDomain }
func (provider tropicalSemiring) Zero() (any, error) {
	if provider.panicZero {
		panic("deliberate semiring provider panic")
	}
	return math.Inf(1), nil
}
func (tropicalSemiring) One() (any, error) { return float64(0), nil }
func (tropicalSemiring) Plus(left, right any) (any, error) {
	return math.Min(left.(float64), right.(float64)), nil
}
func (tropicalSemiring) Times(left, right any) (any, error) {
	return left.(float64) + right.(float64), nil
}
func (tropicalSemiring) Equal(left, right any) (bool, error) { return left == right, nil }
func (tropicalSemiring) ApproxEqual(left, right any, epsilon float64) (bool, error) {
	return math.Abs(left.(float64)-right.(float64)) <= epsilon, nil
}
func (tropicalSemiring) NaturalOrder(left, right any) (NaturalOrder, error) {
	first, second := left.(float64), right.(float64)
	switch {
	case first < second:
		return OrderBetter, nil
	case first > second:
		return OrderWorse, nil
	default:
		return OrderEqual, nil
	}
}
func (tropicalSemiring) StableBytes(value any) ([]byte, error) {
	result := make([]byte, 8)
	binary.LittleEndian.PutUint64(result, math.Float64bits(value.(float64)))
	return result, nil
}
func (provider tropicalSemiring) Diagnostic(value any) (string, error) {
	if provider.entered != nil {
		select {
		case provider.entered <- struct{}{}:
		default:
		}
	}
	if provider.block != nil {
		<-provider.block
	}
	return fmt.Sprint(value), nil
}
func (provider tropicalSemiring) PlusMany(values []any) (any, error) {
	result, _ := provider.Zero()
	for _, value := range values {
		result, _ = provider.Plus(result, value)
	}
	return result, nil
}
func (provider tropicalSemiring) TimesMany(values []any) (any, error) {
	result, _ := provider.One()
	for _, value := range values {
		result, _ = provider.Times(result, value)
	}
	return result, nil
}
func (tropicalSemiring) Divide(dividend, divisor any) (any, bool, error) {
	if math.IsInf(divisor.(float64), 1) {
		return nil, false, nil
	}
	return dividend.(float64) - divisor.(float64), true, nil
}
func (provider tropicalSemiring) LeftDivide(value, divisor any) (any, bool, error) {
	return provider.Divide(value, divisor)
}
func (tropicalSemiring) Star(value any) (any, bool, error) {
	if value.(float64) < 0 {
		return nil, false, nil
	}
	return float64(0), true, nil
}
func (tropicalSemiring) NumericalValue(value any) (float64, error) { return value.(float64), nil }
func (tropicalSemiring) Quantize(value any, epsilon float64) (int64, error) {
	return int64(math.Round(value.(float64) / epsilon)), nil
}
func (tropicalSemiring) ToProbability(value any) (float64, error) {
	return math.Exp(-value.(float64)), nil
}
func (tropicalSemiring) Properties() SemiringProperties {
	return SemiringHashable | SemiringIdempotentPlus | SemiringZeroSumFree | SemiringCommutativeTimes | SemiringTotallyOrdered | SemiringNonnegative
}
func (tropicalSemiring) ClosureBound() (uint64, bool, error) { return 7, true, nil }

func TestGoDynamicSemiringProviderFullSurfaceAndLifetimes(t *testing.T) {
	context, err := NewSemiringContext(tropicalSemiring{}, SemiringOptions{})
	if err != nil {
		t.Fatal(err)
	}
	zero, err := context.Zero()
	if err != nil {
		t.Fatal(err)
	}
	defer zero.Close()
	one, err := context.One()
	if err != nil {
		t.Fatal(err)
	}
	defer one.Close()
	two, err := context.NewValue(float64(2))
	if err != nil {
		t.Fatal(err)
	}
	defer two.Close()

	sum, err := context.Plus(two, one)
	if err != nil {
		t.Fatal(err)
	}
	defer sum.Close()
	if equal, err := context.Equal(sum, one); err != nil || !equal {
		t.Fatalf("tropical plus failed: %t, %v", equal, err)
	}
	product, err := context.Times(two, two)
	if err != nil {
		t.Fatal(err)
	}
	defer product.Close()
	if numeric, err := product.NumericalValue(); err != nil || numeric != 4 {
		t.Fatalf("tropical times failed: %g, %v", numeric, err)
	}
	if quantized, err := product.Quantize(0.5); err != nil || quantized != 8 {
		t.Fatalf("quantization failed: %d, %v", quantized, err)
	}
	if probability, err := two.ToProbability(); err != nil || math.Abs(probability-math.Exp(-2)) > 1e-15 {
		t.Fatalf("probability projection failed: %g, %v", probability, err)
	}
	if order, err := context.NaturalOrder(one, two); err != nil || order != OrderBetter {
		t.Fatalf("natural order failed: %d, %v", order, err)
	}
	if encoded, err := two.StableBytes(); err != nil || len(encoded) != 8 {
		t.Fatalf("stable bytes failed: %x, %v", encoded, err)
	}
	if diagnostic, err := two.Diagnostic(); err != nil || diagnostic != "2" {
		t.Fatalf("diagnostic failed: %q, %v", diagnostic, err)
	}
	if clone, err := two.Clone(); err != nil {
		t.Fatal(err)
	} else {
		clone.Close()
	}
	if quotient, defined, err := context.Divide(product, two); err != nil || !defined {
		t.Fatalf("division failed: %t, %v", defined, err)
	} else {
		defer quotient.Close()
	}
	if _, defined, err := context.Divide(product, zero); err != nil || defined {
		t.Fatalf("undefined division contract failed: %t, %v", defined, err)
	}
	if closure, converged, err := two.Star(); err != nil || !converged {
		t.Fatalf("star failed: %t, %v", converged, err)
	} else {
		defer closure.Close()
	}
	if folded, err := context.TimesMany(one, two, two); err != nil {
		t.Fatal(err)
	} else {
		defer folded.Close()
		if numeric, numericErr := folded.NumericalValue(); numericErr != nil || numeric != 4 {
			t.Fatalf("batch times failed: %g, %v", numeric, numericErr)
		}
	}
	if properties, err := context.Properties(); err != nil || properties&SemiringIdempotentPlus == 0 {
		t.Fatalf("properties failed: %#x, %v", properties, err)
	}
	if bound, known, err := context.ClosureBound(); err != nil || !known || bound != 7 {
		t.Fatalf("closure bound failed: %d, %t, %v", bound, known, err)
	}

	foreign, err := NewSemiringContext(tropicalSemiring{}, SemiringOptions{})
	if err != nil {
		t.Fatal(err)
	}
	foreignOne, err := foreign.One()
	if err != nil {
		t.Fatal(err)
	}
	defer foreignOne.Close()
	defer foreign.Close()
	if _, err := context.Plus(one, foreignOne); err == nil {
		t.Fatal("foreign-context semiring value was accepted")
	} else {
		requireStatus(t, err, StatusInvalidArgument)
	}

	context.Close()
	if diagnostic, err := two.Diagnostic(); err != nil || diagnostic != "2" {
		t.Fatalf("value did not retain its closed context: %q, %v", diagnostic, err)
	}
	if _, err := context.One(); err == nil {
		t.Fatal("closed semiring context remained usable")
	} else {
		requireStatus(t, err, StatusClosed)
	}
}

func TestGoSemiringPanicAndNumericInputContainment(t *testing.T) {
	context, err := NewSemiringContext(tropicalSemiring{panicZero: true}, SemiringOptions{})
	if err != nil {
		t.Fatal(err)
	}
	defer context.Close()
	if _, err := context.NewValue(nil); err == nil {
		t.Fatal("nil semiring value was accepted")
	} else {
		requireStatus(t, err, StatusProviderError)
	}
	if _, err := context.Zero(); err == nil {
		t.Fatal("semiring provider panic escaped as success")
	} else {
		requireStatus(t, err, StatusProviderError)
	}
	one, err := context.One()
	if err != nil {
		t.Fatal(err)
	}
	defer one.Close()
	if _, err := one.Quantize(0); err == nil {
		t.Fatal("zero quantization epsilon was accepted")
	} else {
		requireStatus(t, err, StatusInvalidArgument)
	}
	if _, err := context.ApproxEqual(one, one, math.NaN()); err == nil {
		t.Fatal("NaN comparison epsilon was accepted")
	} else {
		requireStatus(t, err, StatusInvalidArgument)
	}
}

func TestNilConsumerReceiversFailClosed(t *testing.T) {
	var lattice *LatticeValue
	if _, err := lattice.JoinMany(); err == nil {
		t.Fatal("nil lattice receiver remained usable")
	} else {
		requireStatus(t, err, StatusClosed)
	}
	var graph *ScalarWfst
	if _, err := graph.StartState(); err == nil {
		t.Fatal("nil WFST receiver remained usable")
	} else {
		requireStatus(t, err, StatusClosed)
	}
	var semiring *SemiringContext
	if _, err := semiring.PlusMany(); err == nil {
		t.Fatal("nil semiring receiver remained usable")
	} else {
		requireStatus(t, err, StatusClosed)
	}
}

func TestSemiringConstructionCloseRacePreservesEveryOwnedToken(t *testing.T) {
	for iteration := 0; iteration < 256; iteration++ {
		context, err := NewSemiringContext(tropicalSemiring{}, SemiringOptions{ParallelReentrant: true})
		if err != nil {
			t.Fatal(err)
		}
		start := make(chan struct{})
		closed := make(chan struct{})
		go func() {
			<-start
			context.Close()
			close(closed)
		}()
		close(start)
		value, err := context.NewValue(float64(iteration))
		<-closed
		if err != nil {
			requireStatus(t, err, StatusClosed)
			continue
		}
		diagnostic, diagnosticErr := value.Diagnostic()
		if diagnosticErr != nil || diagnostic != fmt.Sprint(iteration) {
			t.Fatalf("owned token did not survive context close: %q, %v", diagnostic, diagnosticErr)
		}
		value.Close()
	}
}

func TestSemiringValueReleaseNeverWaitsForSerializedProviderCode(t *testing.T) {
	entered := make(chan struct{}, 1)
	unblock := make(chan struct{})
	context, err := NewSemiringContext(tropicalSemiring{entered: entered, block: unblock}, SemiringOptions{})
	if err != nil {
		t.Fatal(err)
	}
	defer context.Close()
	active, err := context.NewValue(float64(1))
	if err != nil {
		t.Fatal(err)
	}
	defer active.Close()
	releasable, err := context.NewValue(float64(2))
	if err != nil {
		t.Fatal(err)
	}
	callbackDone := make(chan error, 1)
	go func() {
		_, callErr := active.Diagnostic()
		callbackDone <- callErr
	}()
	select {
	case <-entered:
	case <-time.After(2 * time.Second):
		t.Fatal("serialized semiring callback did not enter")
	}
	releaseDone := make(chan struct{})
	go func() {
		releasable.Close()
		close(releaseDone)
	}()
	select {
	case <-releaseDone:
	case <-time.After(2 * time.Second):
		close(unblock)
		t.Fatal("semiring value release waited on customer provider code")
	}
	close(unblock)
	if err := <-callbackDone; err != nil {
		t.Fatalf("active semiring callback failed: %v", err)
	}
}
