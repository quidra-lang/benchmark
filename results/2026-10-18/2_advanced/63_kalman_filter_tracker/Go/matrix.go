package main

type Matrix [][]float64

func zeros(rows, cols int) Matrix {
	a := make(Matrix, rows)
	for i := range a {
		a[i] = make([]float64, cols)
	}
	return a
}
func identity(n int) Matrix {
	a := zeros(n, n)
	for i := range a {
		a[i][i] = 1
	}
	return a
}
func diagonal(v []float64) Matrix {
	a := zeros(len(v), len(v))
	for i, x := range v {
		a[i][i] = x
	}
	return a
}
func transpose(a Matrix) Matrix {
	out := zeros(len(a[0]), len(a))
	for i, row := range a {
		for j, x := range row {
			out[j][i] = x
		}
	}
	return out
}
func product(a, b Matrix) Matrix {
	out := zeros(len(a), len(b[0]))
	for i := range out {
		for j := range out[i] {
			s := 0.0
			for k := range b {
				s += a[i][k] * b[k][j]
			}
			out[i][j] = s
		}
	}
	return out
}
func matrixVector(a Matrix, v []float64) []float64 {
	out := make([]float64, len(a))
	for i, row := range a {
		for j, x := range row {
			out[i] += x * v[j]
		}
	}
	return out
}
func matrixAdd(a, b Matrix, sign float64) Matrix {
	out := zeros(len(a), len(a[0]))
	for i, row := range a {
		for j, x := range row {
			out[i][j] = x + sign*b[i][j]
		}
	}
	return out
}
func vectorAdd(a, b []float64, sign float64) []float64 {
	out := make([]float64, len(a))
	for i, x := range a {
		out[i] = x + sign*b[i]
	}
	return out
}
func inverse(a Matrix) Matrix {
	n := len(a)
	x := zeros(n, 2*n)
	for i, row := range a {
		copy(x[i], row)
		x[i][n+i] = 1
	}
	for c := 0; c < n; c++ {
		p := x[c][c]
		for j := 0; j < 2*n; j++ {
			x[c][j] /= p
		}
		for i := 0; i < n; i++ {
			if i == c {
				continue
			}
			f := x[i][c]
			for j := 0; j < 2*n; j++ {
				x[i][j] = x[i][j] - f*x[c][j]
			}
		}
	}
	out := zeros(n, n)
	for i := range out {
		copy(out[i], x[i][n:])
	}
	return out
}
func determinant(a Matrix) float64 { return a[0][0]*a[1][1] - a[0][1]*a[1][0] }
func quadratic(v []float64, a Matrix) float64 {
	return v[0]*(a[0][0]*v[0]+a[0][1]*v[1]) + v[1]*(a[1][0]*v[0]+a[1][1]*v[1])
}
func positionCovariance(a Matrix) Matrix { return Matrix{{a[0][0], a[0][1]}, {a[1][0], a[1][1]}} }
