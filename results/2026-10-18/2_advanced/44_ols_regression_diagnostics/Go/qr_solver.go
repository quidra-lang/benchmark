package main

import "math"

type Fit struct {
	Matrix                                                                [][]float64
	Response, Weights                                                     []float64
	N, P, Rank                                                            int
	Accepted, Aliases                                                     []int
	Triangular, Inverse, G                                                [][]float64
	Effects, Beta, Variance, Leverage, Fitted, Residual, WeightedResidual []float64
	RSS                                                                   float64
}

func matrix(rows, cols int) [][]float64 {
	a := make([][]float64, rows)
	for i := range a {
		a[i] = make([]float64, cols)
	}
	return a
}
func fit(x [][]float64, y, w []float64, tolerance float64) *Fit {
	n, p := len(x), len(x[0])
	f := &Fit{Matrix: x, Response: y, Weights: w, N: n, P: p, Beta: make([]float64, p)}
	for j := range f.Beta {
		f.Beta[j] = math.NaN()
	}
	roots := make([]float64, n)
	weighted, work := matrix(n, p), matrix(n, p)
	b := make([]float64, n)
	lengths := make([]float64, p)
	for i := 0; i < n; i++ {
		roots[i] = math.Sqrt(w[i])
		for j := 0; j < p; j++ {
			weighted[i][j] = roots[i] * x[i][j]
			work[i][j] = weighted[i][j]
		}
		b[i] = roots[i] * y[i]
	}
	for j := 0; j < p; j++ {
		sum := 0.0
		for i := 0; i < n; i++ {
			sum += weighted[i][j] * weighted[i][j]
		}
		lengths[j] = math.Sqrt(sum)
	}
	triangular := matrix(p, p)
	for j := 0; j < p; j++ {
		k := len(f.Accepted)
		sum := 0.0
		for i := k; i < n; i++ {
			sum += work[i][j] * work[i][j]
		}
		eta := math.Sqrt(sum)
		if eta <= tolerance*lengths[j] {
			f.Aliases = append(f.Aliases, j)
			continue
		}
		f.Accepted = append(f.Accepted, j)
		alpha := eta
		if work[k][j] >= 0 {
			alpha = -eta
		}
		v := make([]float64, n-k)
		v[0] = work[k][j] - alpha
		for i := k + 1; i < n; i++ {
			v[i-k] = work[i][j]
		}
		squared := 0.0
		for _, z := range v {
			squared += z * z
		}
		for l := 0; l < k; l++ {
			triangular[l][k] = work[l][j]
		}
		triangular[k][k] = alpha
		for l := j + 1; l < p; l++ {
			dot := 0.0
			for i := k; i < n; i++ {
				dot += v[i-k] * work[i][l]
			}
			delta := 2 * dot / squared
			for i := k; i < n; i++ {
				work[i][l] = work[i][l] - delta*v[i-k]
			}
		}
		dot := 0.0
		for i := k; i < n; i++ {
			dot += v[i-k] * b[i]
		}
		delta := 2 * dot / squared
		for i := k; i < n; i++ {
			b[i] = b[i] - delta*v[i-k]
		}
	}
	r := len(f.Accepted)
	f.Rank = r
	f.Triangular = matrix(r, r)
	for i := 0; i < r; i++ {
		copy(f.Triangular[i], triangular[i][:r])
	}
	f.Effects = append([]float64{}, b[:r]...)
	for k := r - 1; k >= 0; k-- {
		tail := 0.0
		for l := k + 1; l < r; l++ {
			tail += f.Triangular[k][l] * f.Beta[f.Accepted[l]]
		}
		f.Beta[f.Accepted[k]] = (f.Effects[k] - tail) / f.Triangular[k][k]
	}
	f.Inverse = matrix(r, r)
	for m := 0; m < r; m++ {
		for l := r - 1; l >= 0; l-- {
			diagonal := 0.0
			if l == m {
				diagonal = 1
			}
			tail := 0.0
			for q := l + 1; q < r; q++ {
				tail += f.Triangular[l][q] * f.Inverse[q][m]
			}
			f.Inverse[l][m] = (diagonal - tail) / f.Triangular[l][l]
		}
	}
	f.Variance = make([]float64, r)
	for k, row := range f.Inverse {
		for _, v := range row {
			f.Variance[k] += v * v
		}
	}
	f.G = matrix(n, r)
	f.Leverage = make([]float64, n)
	f.Fitted = make([]float64, n)
	f.Residual = make([]float64, n)
	f.WeightedResidual = make([]float64, n)
	for i := 0; i < n; i++ {
		u := make([]float64, r)
		for k := 0; k < r; k++ {
			for m := 0; m < r; m++ {
				u[k] += weighted[i][f.Accepted[m]] * f.Inverse[m][k]
			}
			f.Leverage[i] += u[k] * u[k]
		}
		for k := 0; k < r; k++ {
			for m := 0; m < r; m++ {
				f.G[i][k] += f.Inverse[k][m] * u[m]
			}
		}
		for _, column := range f.Accepted {
			f.Fitted[i] += x[i][column] * f.Beta[column]
		}
		f.Residual[i] = y[i] - f.Fitted[i]
		f.WeightedResidual[i] = roots[i] * f.Residual[i]
	}
	for _, v := range f.WeightedResidual {
		f.RSS += v * v
	}
	return f
}
