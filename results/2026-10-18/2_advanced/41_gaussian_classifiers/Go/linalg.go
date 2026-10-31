package main

import "math"

func zeros(n int) [][]float64 {
	m := make([][]float64, n)
	for i := range m {
		m[i] = make([]float64, n)
	}
	return m
}
func dot(a, b []float64) float64 {
	s := 0.0
	for i, x := range a {
		s += x * b[i]
	}
	return s
}
func cholesky(a [][]float64) [][]float64 {
	l := zeros(len(a))
	for i := range a {
		for j := 0; j <= i; j++ {
			s := 0.0
			for k := 0; k < j; k++ {
				s += l[i][k] * l[j][k]
			}
			r := a[i][j] - s
			if i == j {
				l[i][j] = math.Sqrt(r)
			} else {
				l[i][j] = r / l[j][j]
			}
		}
	}
	return l
}
func forward(l [][]float64, r []float64) []float64 {
	z := make([]float64, len(l))
	for i := range l {
		s := 0.0
		for k := 0; k < i; k++ {
			s += l[i][k] * z[k]
		}
		z[i] = (r[i] - s) / l[i][i]
	}
	return z
}
func backward(l [][]float64, r []float64) []float64 {
	v := make([]float64, len(l))
	for i := len(l) - 1; i >= 0; i-- {
		s := 0.0
		for k := i + 1; k < len(l); k++ {
			s += l[k][i] * v[k]
		}
		v[i] = (r[i] - s) / l[i][i]
	}
	return v
}
func logDet(l [][]float64) float64 {
	s := 0.0
	for i := range l {
		s += math.Log(l[i][i])
	}
	return 2 * s
}
func quadratic(l [][]float64, r []float64) float64 { z := forward(l, r); return dot(z, z) }

type Eigen struct {
	Values  []float64
	Vectors [][]float64
	Sweeps  int
}

func jacobi(a [][]float64) Eigen {
	n := len(a)
	m := zeros(n)
	v := zeros(n)
	for i := range m {
		copy(m[i], a[i])
		v[i][i] = 1
	}
	sweeps := 0
	for {
		off := 0.0
		for a := 0; a < n-1; a++ {
			for b := a + 1; b < n; b++ {
				off += m[a][b] * m[a][b]
			}
		}
		if math.Sqrt(off) < 1e-12 || sweeps == 50 {
			break
		}
		for a := 0; a < n-1; a++ {
			for b := a + 1; b < n; b++ {
				if m[a][b] == 0 {
					continue
				}
				theta := (m[b][b] - m[a][a]) / (2 * m[a][b])
				sg := 1.0
				if theta < 0 {
					sg = -1
				}
				t := sg / (math.Abs(theta) + math.Sqrt(theta*theta+1))
				co := 1 / math.Sqrt(t*t+1)
				si := t * co
				for k := 0; k < n; k++ {
					if k == a || k == b {
						continue
					}
					x, y := m[k][a], m[k][b]
					m[k][a] = co*x - si*y
					m[a][k] = m[k][a]
					m[k][b] = si*x + co*y
					m[b][k] = m[k][b]
				}
				w := m[a][b]
				m[a][a] = m[a][a] - t*w
				m[b][b] = m[b][b] + t*w
				m[a][b] = 0
				m[b][a] = 0
				for k := 0; k < n; k++ {
					x, y := v[k][a], v[k][b]
					v[k][a] = co*x - si*y
					v[k][b] = si*x + co*y
				}
			}
		}
		sweeps++
	}
	values := make([]float64, n)
	for i := range values {
		values[i] = m[i][i]
	}
	return Eigen{values, v, sweeps}
}
