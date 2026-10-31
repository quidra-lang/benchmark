package main

import "math"

const z95 = 1.959963984540054

func zeros(n int) [][]float64 {
	a := make([][]float64, n)
	for i := range a {
		a[i] = make([]float64, n)
	}
	return a
}
func solve(matrix [][]float64, vector []float64) []float64 {
	n := len(vector)
	a := zeros(n)
	for i := range a {
		copy(a[i], matrix[i])
	}
	b := append([]float64{}, vector...)
	for k := 0; k < n; k++ {
		for i := k + 1; i < n; i++ {
			f := a[i][k] / a[k][k]
			for j := k; j < n; j++ {
				a[i][j] -= f * a[k][j]
			}
			b[i] -= f * b[k]
		}
	}
	x := make([]float64, n)
	for i := n - 1; i >= 0; i-- {
		v := b[i]
		for j := i + 1; j < n; j++ {
			v -= a[i][j] * x[j]
		}
		x[i] = v / a[i][i]
	}
	return x
}
func inverse(matrix [][]float64) [][]float64 {
	n := len(matrix)
	out := zeros(n)
	for c := 0; c < n; c++ {
		unit := make([]float64, n)
		unit[c] = 1
		x := solve(matrix, unit)
		for r := 0; r < n; r++ {
			out[r][c] = x[r]
		}
	}
	return out
}
func logGamma(a float64) float64 {
	coeff := []float64{76.18009172947146, -86.50532032941677, 24.01409824083091, -1.231739572450155, 0.001208650973866179, -0.000005395239384953}
	xi := a + 5.5
	xi = xi - (a+0.5)*math.Log(xi)
	sigma, y := 1.000000000190015, a
	for _, g := range coeff {
		y += 1
		sigma += g / y
	}
	return -xi + math.Log(2.5066282746310005*sigma/a)
}
func gammaQ(a, x float64) float64 {
	if x == 0 {
		return 1
	}
	pref := math.Exp(-x + a*math.Log(x) - logGamma(a))
	if x < a+1 {
		alpha, xi := a, 1/a
		sigma := xi
		for i := 0; i < 1000; i++ {
			alpha++
			xi *= x / alpha
			sigma += xi
			if math.Abs(xi) < math.Abs(sigma)*1e-15 {
				break
			}
		}
		return 1 - sigma*pref
	}
	eps := 1e-300
	b := x + 1 - a
	c, d := 1/eps, 1/b
	h := d
	for i := 1; i <= 1000; i++ {
		an := -float64(i) * (float64(i) - a)
		b += 2
		d = an*d + b
		if math.Abs(d) < eps {
			d = eps
		}
		c = b + an/c
		if math.Abs(c) < eps {
			c = eps
		}
		d = 1 / d
		delta := d * c
		h *= delta
		if math.Abs(delta-1) < 1e-15 {
			break
		}
	}
	return pref * h
}
func chiP(statistic float64, degrees int) float64 { return gammaQ(float64(degrees)/2, statistic/2) }
