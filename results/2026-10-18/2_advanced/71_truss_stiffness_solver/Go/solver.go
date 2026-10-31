package main

import "math"

func cholesky(a [][]float64) ([][]float64, int) {
	n := len(a)
	g := matrix(n, n)
	for i := 0; i < n; i++ {
		for j := 0; j <= i; j++ {
			w := a[i][j]
			for h := 0; h < j; h++ {
				w -= g[i][h] * g[j][h]
			}
			if j < i {
				g[i][j] = w / g[j][j]
			} else {
				if w <= 0.000000001*a[i][i] {
					return nil,
						i
				}
				g[i][i] = math.Sqrt(w)
			}
		}
	}
	return g, -1
}
func solve(g [][]float64, b []float64) []float64 {
	n := len(b)
	y, x := make([]float64, n), make([]float64,
		n)
	for i := 0; i < n; i++ {
		w := b[i]
		for h := 0; h < i; h++ {
			w -= g[i][h] * y[h]
		}
		y[i] = w / g[i][i]
	}
	for i := n - 1; i >= 0; i-- {
		w := y[i]
		for h := i + 1; h < n; h++ {
			w -= g[h][i] * x[h]
		}
		x[i] = w / g[i][i]
	}
	return x
}
