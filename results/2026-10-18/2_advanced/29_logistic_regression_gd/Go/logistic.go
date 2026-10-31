package main

import "math"

func score(weights, vector []float64) float64 {
	total := 0.0
	for j, w := range weights {
		total += w * vector[j]
	}
	return total
}
func probability(u float64) float64 {
	if u >= 0 {
		return 1 / (1 + math.Exp(-u))
	}
	e := math.Exp(u)
	return e / (1 + e)
}
func loss(u float64, target int) float64 {
	return math.Max(u, 0) - float64(target)*u + math.Log(1+math.Exp(-math.Abs(u)))
}
func averageLoss(w []float64, x [][]float64, y []int) float64 {
	total := 0.0
	for i, v := range x {
		total += loss(score(w, v), y[i])
	}
	return total / float64(len(x))
}
func objective(w []float64, x [][]float64, y []int, lambda float64) float64 {
	penalty := 0.0
	for _, v := range w[1:] {
		penalty += v * v
	}
	return averageLoss(w, x, y) + lambda*penalty/2
}
func gradient(w []float64, x [][]float64, y []int, lambda float64) []float64 {
	g := make([]float64, len(w))
	for i, v := range x {
		e := probability(score(w, v)) - float64(y[i])
		for j := range g {
			g[j] += e * v[j]
		}
	}
	for j := range g {
		g[j] /= float64(len(x))
		if j > 0 {
			g[j] += lambda * w[j]
		}
	}
	return g
}
func matrix(rows, columns int) [][]float64 {
	result := make([][]float64, rows)
	for i := range result {
		result[i] = make([]float64, columns)
	}
	return result
}
func hessian(w []float64, x [][]float64, lambda float64) [][]float64 {
	n := len(w)
	h := matrix(n, n)
	for _, v := range x {
		p := probability(score(w, v))
		variance := p * (1 - p)
		for j := 0; j < n; j++ {
			for k := 0; k <= j; k++ {
				h[j][k] += variance * v[j] * v[k]
			}
		}
	}
	for j := 0; j < n; j++ {
		for k := 0; k <= j; k++ {
			value := h[j][k] / float64(len(x))
			if j == k && j > 0 {
				value += lambda
			}
			h[j][k], h[k][j] = value, value
		}
	}
	return h
}
