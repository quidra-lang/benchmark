package main

import "math"

type Fraction struct{ A, B int }

func gcd(a, b int) int {
	if a < 0 {
		a = -a
	}
	for b != 0 {
		a, b = b, a%b
	}
	return a
}
func fraction(a, b int) Fraction {
	if b == 0 {
		return Fraction{0, 0}
	}
	g := gcd(a, b)
	return Fraction{a / g, b / g}
}
func addFractions(a, b Fraction) Fraction { return fraction(a.A*b.B+b.A*a.B, a.B*b.B) }

type Metrics struct {
	Matrix                    [][]int
	Support                   []int
	Correct                   int
	Accuracy, Balanced, Kappa Fraction
	Recall, Precision, F1     []Fraction
	MacroF1                   float64
}

func measures(actual, predicted []int, c int) Metrics {
	m := Metrics{Matrix: make([][]int, c), Support: make([]int, c), Recall: make([]Fraction, c), Precision: make([]Fraction, c), F1: make([]Fraction, c)}
	for k := range m.Matrix {
		m.Matrix[k] = make([]int, c)
	}
	for i, a := range actual {
		m.Matrix[a][predicted[i]]++
	}
	counts := make([]int, c)
	for a, row := range m.Matrix {
		for b, v := range row {
			m.Support[a] += v
			counts[b] += v
		}
	}
	recall := Fraction{0, 1}
	expected := 0
	for k := 0; k < c; k++ {
		v := m.Matrix[k][k]
		m.Correct += v
		m.Recall[k] = fraction(v, m.Support[k])
		m.Precision[k] = fraction(v, counts[k])
		m.F1[k] = fraction(2*v, m.Support[k]+counts[k])
		recall = addFractions(recall, m.Recall[k])
		expected += m.Support[k] * counts[k]
		m.MacroF1 += float64(2*v) / float64(m.Support[k]+counts[k])
	}
	m.MacroF1 /= float64(c)
	n := len(actual)
	m.Accuracy = fraction(m.Correct, n)
	m.Balanced = fraction(recall.A, recall.B*c)
	m.Kappa = fraction(n*m.Correct-expected, n*n-expected)
	return m
}
func mcnemar(actual, a, b []int) (int, int, float64) {
	b01, b10 := 0, 0
	for i, x := range actual {
		ca, cb := a[i] == x, b[i] == x
		if ca && !cb {
			b01++
		} else if cb && !ca {
			b10++
		}
	}
	chi := 0.0
	if b01 != b10 {
		d := int(math.Abs(float64(b01-b10))) - 1
		chi = float64(d*d) / float64(b01+b10)
	}
	return b01, b10, chi
}

type RandomGenerator struct{ State int64 }

func (r *RandomGenerator) draw() int64 { r.State = 48271 * r.State % 2147483647; return r.State }
