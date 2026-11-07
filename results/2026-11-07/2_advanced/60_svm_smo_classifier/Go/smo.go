package main

import "math"

type Pass struct {
	Full              bool
	Examined, Changed int
	Alpha             []float64
}
type Model struct {
	Data                            []Example
	Kernel                          Kernel
	Q                               [][]float64
	C, B                            float64
	Alpha, Errors                   []float64
	Full, Nonbound, Examined, Steps int
	Choice, Clipping                [3]int
	Converged                       bool
	Passes                          []Pass
	Tolerance, Epsilon              float64
}

func (m *Model) nonbound(i int) bool { return m.Alpha[i] > 0 && m.Alpha[i] < m.C }
func (m *Model) snap(a float64) float64 {
	if a < .00000001 {
		return 0
	}
	if a > m.C-.00000001 {
		return m.C
	}
	return a
}
func (m *Model) take(i1, i2 int) bool {
	if i1 == i2 {
		return false
	}
	alpha1, alpha2 := m.Alpha[i1], m.Alpha[i2]
	y1, y2 := float64(m.Data[i1].Label), float64(m.Data[i2].Label)
	e1, e2 := m.Errors[i1], m.Errors[i2]
	lo, hi := math.Max(0, alpha2+alpha1-m.C), math.Min(m.C, alpha2+alpha1)
	if y1 != y2 {
		lo, hi = math.Max(0, alpha2-alpha1), math.Min(m.C, m.C+alpha2-alpha1)
	}
	if lo == hi {
		return false
	}
	k11, k12, k22 := m.Q[i1][i1], m.Q[i1][i2], m.Q[i2][i2]
	eta := k11 + k22 - 2*k12
	if eta <= 0 {
		return false
	}
	a2 := alpha2 + y2*(e1-e2)/eta
	clip := 0
	if a2 < lo {
		a2, clip = lo, 1
	} else if a2 > hi {
		a2, clip = hi, 2
	}
	a2 = m.snap(a2)
	if math.Abs(a2-alpha2) < m.Epsilon*(a2+alpha2+m.Epsilon) {
		return false
	}
	a1 := m.snap(alpha1 + y1*y2*(alpha2-a2))
	t1, t2 := y1*(a1-alpha1), y2*(a2-alpha2)
	b1, b2 := e1+t1*k11+t2*k12+m.B, e2+t1*k12+t2*k22+m.B
	next := (b1 + b2) / 2
	if a1 > 0 && a1 < m.C {
		next = b1
	} else if a2 > 0 && a2 < m.C {
		next = b2
	}
	delta := next - m.B
	for i := range m.Errors {
		m.Errors[i] = m.Errors[i] + (t1*m.Q[i1][i] + t2*m.Q[i2][i] - delta)
	}
	if a1 > 0 && a1 < m.C {
		m.Errors[i1] = 0
	}
	if a2 > 0 && a2 < m.C {
		m.Errors[i2] = 0
	}
	m.Alpha[i1], m.Alpha[i2], m.B = a1, a2, next
	m.Steps++
	m.Clipping[clip]++
	return true
}
func (m *Model) examine(i2 int) int {
	m.Examined++
	r2 := m.Errors[i2] * float64(m.Data[i2].Label)
	if !((r2 < -m.Tolerance && m.Alpha[i2] < m.C) || (r2 > m.Tolerance && m.Alpha[i2] > 0)) {
		return 0
	}
	partner := -1
	largest := -1.0
	for i := range m.Alpha {
		if i != i2 && m.nonbound(i) {
			v := math.Abs(m.Errors[i] - m.Errors[i2])
			if v > largest {
				partner, largest = i, v
			}
		}
	}
	if partner >= 0 && m.take(partner, i2) {
		m.Choice[0]++
		return 1
	}
	for i := range m.Alpha {
		if m.nonbound(i) && m.take(i, i2) {
			m.Choice[1]++
			return 1
		}
	}
	for i := range m.Alpha {
		if m.take(i, i2) {
			m.Choice[2]++
			return 1
		}
	}
	return 0
}
func train(data []Example, q [][]float64, k Kernel, c float64, params Params) *Model {
	m := &Model{Data: data, Q: q, Kernel: k, C: c, Alpha: make([]float64, len(data)), Errors: make([]float64,
		len(data)), Tolerance: params.Tolerance, Epsilon: params.Epsilon}
	for i, e := range data {
		m.Errors[i] = -float64(e.Label)
	}
	all := true
	for {
		examined, changed := m.Examined, 0
		for i := range data {
			if all || m.nonbound(i) {
				changed += m.examine(i)
			}
		}
		pass := Pass{Full: all, Examined: m.Examined - examined, Changed: changed}
		if all {
			m.Full++
			pass.Alpha = append([]float64(nil), m.Alpha...)
		} else {
			m.Nonbound++
		}
		m.Passes = append(m.Passes, pass)
		if all && changed == 0 {
			m.Converged = true
			break
		}
		if len(m.Passes) == params.MaxPasses {
			break
		}
		if all {
			all = false
		} else if changed == 0 {
			all = true
		}
	}
	return m
}
func (m *Model) decision(z Point) float64 {
	s := 0.0
	for j, a := range m.Alpha {
		if a > 0 {
			s += a * float64(m.Data[j].Label) * m.Kernel.value(m.Data[j].Point, z)
		}
	}
	return s - m.B
}
func (m *Model) trainingValues() []float64 {
	out := make([]float64, len(m.Data))
	for i := range out {
		s := 0.0
		for j, a := range m.Alpha {
			if a > 0 {
				s += a * float64(m.Data[j].Label) * m.Q[i][j]
			}
		}
		out[i] = s - m.B
	}
	return out
}
func objective(alpha []float64, data []Example, q [][]float64) (float64, float64) {
	quadratic, total := 0.0, 0.0
	for i, a := range alpha {
		s := 0.0
		for j, b := range alpha {
			if b > 0 {
				s += b * float64(data[j].Label) * q[i][j]
			}
		}
		quadratic += a * float64(data[i].Label) * s
		total += a
	}
	return quadratic, total - quadratic/2
}
func (m *Model) counts() (int, int, int) {
	total, bound := 0, 0
	for _, a := range m.Alpha {
		if a > 0 {
			total++
			if a == m.C {
				bound++
			}
		}
	}
	return total, bound, total - bound
}
