package main

import (
	"math"
	"sort"
)

func median(values []float64) float64 {
	v := append([]float64(nil), values...)
	sort.Float64s(v)
	mid := len(v) / 2
	if len(v)%2 == 1 {
		return v[mid]
	}
	return (v[mid-1] + v[mid]) / 2
}
func cholesky(matrix [][]float64) [][]float64 {
	n := len(matrix)
	lower := make([][]float64, n)
	for i := range lower {
		lower[i] = make([]float64, n)
	}
	for k := range n {
		for l := 0; l <= k; l++ {
			sigma := matrix[k][l]
			for j := 0; j < l; j++ {
				sigma -= lower[k][j] * lower[l][j]
			}
			if l == k {
				lower[k][l] = math.Sqrt(sigma)
			} else {
				lower[k][l] = sigma / lower[l][l]
			}
		}
	}
	return lower
}
func solve(lower [][]float64, right []float64) []float64 {
	n := len(right)
	eta := make([]float64, n)
	for k := range n {
		v := right[k]
		for j := 0; j < k; j++ {
			v -= lower[k][j] * eta[j]
		}
		eta[k] = v / lower[k][k]
	}
	solution := make([]float64, n)
	for k := n - 1; k >= 0; k-- {
		v := eta[k]
		for j := k + 1; j < n; j++ {
			v -= lower[j][k] * solution[j]
		}
		solution[k] = v / lower[k][k]
	}
	return solution
}

type LocalFit struct {
	Estimate, Zeta float64
	Weights        []float64
}
type RobustRecord struct {
	Iteration, ZeroCount int
	Scale, Change        float64
}
type LoessFit struct {
	BaseFit
	Positions    []int
	X, Y, Rho    []float64
	Span, Degree int
	Records      []RobustRecord
	Cache        map[int]LocalFit
}

func newLoessFit(positions []int, values []float64, span, degree, iterations int, diagnostics bool) *LoessFit {
	f := &LoessFit{BaseFit: BaseFit{EDF: math.NaN()}, Positions: positions, Y: values, Span: span, Degree: degree,
		Rho: make([]float64, len(values)), Cache: map[int]LocalFit{}}
	for i, p := range positions {
		f.X = append(f.X, float64(p)/100)
		f.Rho[i] = 1
	}
	if !diagnostics {
		return f
	}
	fits := make([]LocalFit, len(values))
	for i, p := range positions {
		fits[i] = f.Local(p)
	}
	for iteration := 1; iteration <= iterations; iteration++ {
		residuals, absolute := make([]float64, len(values)), make([]float64, len(values))
		for i, y := range values {
			residuals[i] = y - fits[i].Estimate
			absolute[i] = math.Abs(residuals[i])
		}
		scale := median(absolute)
		zeros := 0
		for i, e := range residuals {
			u := e / (6 * scale)
			v := 1 - u*u
			f.Rho[i] = 0
			if math.Abs(u) < 1 {
				f.Rho[i] = v * v
			} else {
				zeros++
			}
		}
		updated := make([]LocalFit, len(values))
		change := 0.0
		for i, p := range positions {
			updated[i] = f.Local(p)
			change = max(change, math.Abs(updated[i].Estimate-fits[i].Estimate))
		}
		f.Records = append(f.Records, RobustRecord{iteration, zeros, scale, change})
		fits = updated
	}
	f.Fitted = make([]float64, len(values))
	f.Leverage = make([]float64, len(values))
	for i, fit := range fits {
		f.Cache[positions[i]] = fit
		f.Fitted[i] = fit.Estimate
		f.Leverage[i] = f.Rho[i] * fit.Zeta
	}
	f.EDF = orderedSum(f.Leverage)
	return f
}
func (f *LoessFit) Local(position int) LocalFit {
	n := len(f.Positions)
	order := make([]int, n)
	for i := range order {
		order[i] = i
	}
	sort.Slice(order, func(i, j int) bool {
		a, b := order[i], order[j]
		da, db := absInt(f.Positions[a]-position), absInt(f.Positions[b]-position)
		if da != db {
			return da < db
		}
		return a < b
	})
	neighbors := order[:f.Span*n/100]
	distance := 0
	for _, i := range neighbors {
		distance = max(distance, absInt(f.Positions[i]-position))
	}
	sort.Ints(neighbors)
	size := f.Degree + 1
	matrix := make([][]float64, size)
	for i := range matrix {
		matrix[i] = make([]float64, size)
	}
	right := make([]float64, size)
	type Row struct {
		Index  int
		Weight float64
		Basis  []float64
	}
	rows := []Row{}
	for _, i := range neighbors {
		a := float64(absInt(f.Positions[i]-position)) / float64(distance)
		s := 1 - a*a*a
		v := s * s * s * f.Rho[i]
		d := f.X[i] - float64(position)/100
		basis := []float64{1, d}
		if f.Degree == 2 {
			basis = append(basis, d*d)
		}
		rows = append(rows, Row{i, v, basis})
		for k := range size {
			right[k] += v * basis[k] * f.Y[i]
			for l := range size {
				matrix[k][l] += v * basis[k] * basis[l]
			}
		}
	}
	lower := cholesky(matrix)
	beta := solve(lower, right)
	unit := make([]float64, size)
	unit[0] = 1
	zeta := solve(lower, unit)
	weights := make([]float64, n)
	for _, row := range rows {
		total := 0.0
		for k := range size {
			total += zeta[k] * row.Basis[k]
		}
		weights[row.Index] = row.Weight * total
	}
	return LocalFit{beta[0], zeta[0], weights}
}
func (f *LoessFit) Evaluate(position int) LocalFit {
	if v, ok := f.Cache[position]; ok {
		return v
	}
	v := f.Local(position)
	f.Cache[position] = v
	return v
}
func (f *LoessFit) Estimate(position int) float64  { return f.Evaluate(position).Estimate }
func (f *LoessFit) Weights(position int) []float64 { return f.Evaluate(position).Weights }
