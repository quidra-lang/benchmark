package main

import "math"

func zeros(rows, cols int) [][]float64 {
	m := make([][]float64, rows)
	for i := range m {
		m[i] = make([]float64, cols)
	}
	return m
}
func identity(n int) [][]float64 {
	m := zeros(n, n)
	for i := range m {
		m[i][i] = 1
	}
	return m
}
func copyMatrix(a [][]float64) [][]float64 {
	out := make([][]float64, len(a))
	for i, row := range a {
		out[i] = append([]float64{}, row...)
	}
	return out
}
func column(a [][]float64, j int) []float64 {
	v := make([]float64, len(a))
	for i := range v {
		v[i] = a[i][j]
	}
	return v
}
func sum(values []float64) float64 {
	s := 0.0
	for _, v := range values {
		s += v
	}
	return s
}
func dot(a, b []float64) float64 {
	s := 0.0
	for i, v := range a {
		s += v * b[i]
	}
	return s
}
func multiply(a [][]float64, v []float64) []float64 {
	out := make([]float64, len(a))
	for i, row := range a {
		out[i] = dot(row, v)
	}
	return out
}
func normalize(v []float64) []float64 {
	length := math.Sqrt(dot(v, v))
	out := make([]float64, len(v))
	for i, x := range v {
		out[i] = x / length
	}
	return out
}
func orient(v []float64) []float64 {
	best := 0
	for j := 1; j < len(v); j++ {
		if math.Abs(v[j]) > math.Abs(v[best]) {
			best = j
		}
	}
	if v[best] < 0 {
		for j := range v {
			v[j] = -v[j]
		}
	}
	return v
}
func maxDifference(a, b []float64) float64 {
	v := 0.0
	for j, x := range a {
		v = math.Max(v, math.Abs(x-b[j]))
	}
	return v
}
func deflate(a [][]float64, value float64, v []float64) {
	for i := range a {
		for j := range a[i] {
			a[i][j] = a[i][j] - value*v[i]*v[j]
		}
	}
}
func gaussJordan(a [][]float64) ([][]float64, float64) {
	n := len(a)
	unit := identity(n)
	work := zeros(n, 2*n)
	for i := range a {
		copy(work[i], a[i])
		copy(work[i][n:], unit[i])
	}
	det := 1.0
	for k := 0; k < n; k++ {
		pivot := work[k][k]
		det *= pivot
		for h := 0; h < 2*n; h++ {
			work[k][h] /= pivot
		}
		for i := 0; i < n; i++ {
			if i == k {
				continue
			}
			gamma := work[i][k]
			for h := 0; h < 2*n; h++ {
				work[i][h] = work[i][h] - gamma*work[k][h]
			}
		}
	}
	out := zeros(n, n)
	for i := range out {
		copy(out[i], work[i][n:])
	}
	return out, det
}
