package main

import (
	"math"
	"math/cmplx"
	"sort"
)

func median(v []float64) float64 {
	a := append([]float64(nil), v...)
	sort.Float64s(a)
	n := len(a)
	if n%2 == 1 {
		return a[n/2]
	}
	return (a[n/2-1] + a[n/2]) / 2
}
func local(v []float64, k int) bool { return k > 0 && k+1 < len(v) && v[k] > v[k-1] && v[k] > v[k+1] }
func interpolate(v []float64, k int, logarithmic bool) (float64, float64) {
	if !local(v, k) {
		return float64(k), v[k]
	}
	a, b, c := v[k-1], v[k], v[k+1]
	if logarithmic {
		a, b, c = math.Log(a), math.Log(b), math.Log(c)
	}
	d := (a - c) / (2 * (a - 2*b + c))
	value := b - (a-c)*d/4
	if logarithmic {
		value = math.Exp(value)
	}
	return float64(k) + d, value
}
func amplitude(x, w []float64) ([]float64, []complex128, []float64) {
	u := make([]float64, len(w))
	s := 0.0
	for n, v := range w {
		u[n] = x[n] * v
		s += v
	}
	z := transform(realComplex(u, len(u)), false)
	a := make([]float64, len(w)/2+1)
	for k := range a {
		c := 2.0
		if k == 0 || 2*k == len(w) {
			c = 1
		}
		a[k] = c * cmplx.Abs(z[k]) / s
	}
	return u, z, a
}
func frameTransforms(x, w []float64, hop int) ([][]complex128, float64) {
	out := [][]complex128{}
	error := 0.0
	for start := 0; start+len(w) <= len(x); start += hop {
		u := make([]float64, len(w))
		for n, v := range w {
			u[n] = x[start+n] * v
		}
		z := packed(u)
		full := radix(realComplex(u, len(u)), false)
		for k, v := range z {
			error = math.Max(error, cmplx.Abs(v-full[k]))
		}
		out = append(out, z)
	}
	return out, error
}

type WelchResult struct {
	PSD, Coherence []float64
	Transfer       []complex128
	Segments       int
	Error          float64
}

func welch(x, y []float64, fs, l int, name string) WelchResult {
	w := window(name, l)
	a, ea := frameTransforms(x, w, l/2)
	b, eb := frameTransforms(y, w, l/2)
	ns := len(a)
	out := WelchResult{PSD: make([]float64, l/2+1), Coherence: make([]float64, l/2+1), Transfer: make([]complex128, l/2+1), Segments: ns, Error: math.Max(ea, eb)}
	uw := 0.0
	for _, v := range w {
		uw += v * v
	}
	for k := range out.PSD {
		xx, yy := 0.0, 0.0
		xy := complex(0, 0)
		for j := 0; j < ns; j++ {
			v, t := cmplx.Abs(a[j][k]), cmplx.Abs(b[j][k])
			xx += v * v
			yy += t * t
			xy += cmplx.Conj(a[j][k]) * b[j][k]
		}
		c := 2.0
		if k == 0 || k == l/2 {
			c = 1
		}
		out.PSD[k] = c * xx / (float64(ns*fs) * uw)
		v := cmplx.Abs(xy)
		out.Coherence[k] = v * v / (xx * yy)
		out.Transfer[k] = xy / complex(xx, 0)
	}
	return out
}
func rankedPeaks(v []float64, count int, accept func(int) bool) []int {
	out := []int{}
	for k := 1; k+1 < len(v); k++ {
		if local(v, k) && (accept == nil || accept(k)) {
			out = append(out, k)
		}
	}
	sort.Slice(out, func(i, j int) bool {
		if v[out[i]] != v[out[j]] {
			return v[out[i]] > v[out[j]]
		}
		return out[i] < out[j]
	})
	if len(out) > count {
		out = out[:count]
	}
	return out
}
