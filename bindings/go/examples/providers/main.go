package main

import (
	"encoding/binary"
	"fmt"
	"log"
	"math"
	"sort"
	"strings"

	interop "github.com/vinary-tree/vinary-tree-interop/bindings/go/v4"
)

var (
	setDomain      = mustID("example.set.v001")
	semiringDomain = mustID("example.minplus1")
)

func mustID(text string) interop.InterfaceID {
	identifier, err := interop.InterfaceIDFromASCII(text)
	if err != nil {
		panic(err)
	}
	return identifier
}

type integerSet []uint32

func newSet(values ...uint32) integerSet {
	result := append(integerSet(nil), values...)
	sort.Slice(result, func(left, right int) bool { return result[left] < result[right] })
	unique := result[:0]
	for _, value := range result {
		if len(unique) == 0 || unique[len(unique)-1] != value {
			unique = append(unique, value)
		}
	}
	return unique
}

func (integerSet) DomainID() interop.InterfaceID { return setDomain }

func (set integerSet) other(operand *interop.LatticeOperand) (integerSet, error) {
	provider, local := operand.LocalProvider()
	if !local {
		return nil, fmt.Errorf("this example accepts local Go operands")
	}
	other, ok := provider.(integerSet)
	if !ok {
		return nil, fmt.Errorf("incompatible provider %T", provider)
	}
	return other, nil
}

func (set integerSet) Join(operand *interop.LatticeOperand) (interop.LatticeProvider, error) {
	other, err := set.other(operand)
	if err != nil {
		return nil, err
	}
	return newSet(append(append(integerSet(nil), set...), other...)...), nil
}

func (set integerSet) Meet(operand *interop.LatticeOperand) (interop.LatticeProvider, error) {
	other, err := set.other(operand)
	if err != nil {
		return nil, err
	}
	present := make(map[uint32]struct{}, len(other))
	for _, value := range other {
		present[value] = struct{}{}
	}
	intersection := make(integerSet, 0, len(set))
	for _, value := range set {
		if _, found := present[value]; found {
			intersection = append(intersection, value)
		}
	}
	return intersection, nil
}

func (set integerSet) Equal(operand *interop.LatticeOperand) (bool, error) {
	other, err := set.other(operand)
	if err != nil || len(set) != len(other) {
		return false, err
	}
	for index := range set {
		if set[index] != other[index] {
			return false, nil
		}
	}
	return true, nil
}

func (set integerSet) StableBytes() ([]byte, error) {
	result := make([]byte, 4*len(set))
	for index, value := range set {
		binary.LittleEndian.PutUint32(result[index*4:], value)
	}
	return result, nil
}

func (set integerSet) Diagnostic() (string, error) {
	values := make([]string, len(set))
	for index, value := range set {
		values[index] = fmt.Sprint(value)
	}
	return "{" + strings.Join(values, ",") + "}", nil
}

type tinyGraph struct{}

func (tinyGraph) StartState() (uint64, error)       { return 0, nil }
func (tinyGraph) StateCount() (uint64, bool, error) { return 2, true, nil }
func (tinyGraph) StateInfo(state uint64) (interop.WfstStateInfo, error) {
	return interop.WfstStateInfo{
		Valid:       state < 2,
		Final:       state == 1,
		FinalWeight: 0,
	}, nil
}
func (tinyGraph) StateArcs(state uint64) ([]interop.WfstArc, error) {
	if state != 0 {
		return []interop.WfstArc{}, nil
	}
	return []interop.WfstArc{{
		Input: 'a', Output: 'A', Target: 1, Weight: 0.25,
		HasInput: true, HasOutput: true,
	}}, nil
}

type minPlus struct{}

func (minPlus) DomainID() interop.InterfaceID { return semiringDomain }
func (minPlus) Zero() (any, error)            { return math.Inf(1), nil }
func (minPlus) One() (any, error)             { return float64(0), nil }
func (minPlus) Plus(left, right any) (any, error) {
	return math.Min(left.(float64), right.(float64)), nil
}
func (minPlus) Times(left, right any) (any, error) {
	return left.(float64) + right.(float64), nil
}
func (minPlus) Equal(left, right any) (bool, error) { return left == right, nil }
func (minPlus) ApproxEqual(left, right any, epsilon float64) (bool, error) {
	return math.Abs(left.(float64)-right.(float64)) <= epsilon, nil
}
func (minPlus) NaturalOrder(left, right any) (interop.NaturalOrder, error) {
	switch first, second := left.(float64), right.(float64); {
	case first < second:
		return interop.OrderBetter, nil
	case first > second:
		return interop.OrderWorse, nil
	default:
		return interop.OrderEqual, nil
	}
}
func (minPlus) Diagnostic(value any) (string, error) { return fmt.Sprint(value), nil }

func main() {
	left, err := interop.NewLatticeValue(newSet(1, 3), interop.LatticeOptions{})
	if err != nil {
		log.Fatal(err)
	}
	defer left.Close()
	right, err := interop.NewLatticeValue(newSet(2, 3), interop.LatticeOptions{})
	if err != nil {
		log.Fatal(err)
	}
	defer right.Close()
	joined, err := left.Join(right)
	if err != nil {
		log.Fatal(err)
	}
	defer joined.Close()
	setText, err := joined.Diagnostic()
	if err != nil {
		log.Fatal(err)
	}

	graph, err := interop.NewScalarWfst(tinyGraph{}, interop.ScalarWfstOptions{
		UnitDomain: interop.UnitUnicodeScalar, WeightDomain: interop.WeightTropicalF64,
		Acyclic: true,
	})
	if err != nil {
		log.Fatal(err)
	}
	defer graph.Close()
	arcs, err := graph.StateArcs(0, 256)
	if err != nil {
		log.Fatal(err)
	}

	semiring, err := interop.NewSemiringContext(minPlus{}, interop.SemiringOptions{})
	if err != nil {
		log.Fatal(err)
	}
	defer semiring.Close()
	two, err := semiring.NewValue(float64(2))
	if err != nil {
		log.Fatal(err)
	}
	defer two.Close()
	three, err := semiring.NewValue(float64(3))
	if err != nil {
		log.Fatal(err)
	}
	defer three.Close()
	pathWeight, err := semiring.Times(two, three)
	if err != nil {
		log.Fatal(err)
	}
	defer pathWeight.Close()
	weightText, err := pathWeight.Diagnostic()
	if err != nil {
		log.Fatal(err)
	}

	fmt.Printf("join=%s arcs=%d path-weight=%s\n", setText, len(arcs), weightText)
}
