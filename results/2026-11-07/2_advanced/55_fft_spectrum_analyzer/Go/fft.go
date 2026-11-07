package main

import (
	"math"
	"math/cmplx"
)

const pi = 3.141592653589793

func pow2(n int) int {
	q := 1
	for q < n {
		q *= 2
	}
	return q
}
func rot(t float64) complex128 { return complex(math.Cos(t), -math.Sin(t)) }
func radix(a []complex128, inverse bool) []complex128 {
	a = append([]complex128(nil), a...)
	q := len(a)
	for n := 1; n < q; n++ {
		r, v := 0, n
		for bit := q / 2; bit > 0; bit /= 2 {
			r = r*2 + v%2
			v /= 2
		}
		if n < r {
			a[n], a[r] = a[r], a[n]
		}
	}
	w := make([]complex128, q/2)
	for k := range w {
		w[k] = rot(2 * pi * float64(k) / float64(q))
		if inverse {
			w[k] = cmplx.Conj(w[k])
		}
	}
	for s := 2; s <= q; s *= 2 {
		for b := 0; b < q; b += s {
			for j := 0; j < s/2; j++ {
				t, u := w[j*(q/s)]*a[b+j+s/2], a[b+j]
				a[b+j], a[b+j+s/2] = u+t, u-t
			}
		}
	}
	if inverse {
		for k := range a {
			a[k] /= complex(float64(q), 0)
		}
	}
	return a
}
func transform(v []complex128, inverse bool) []complex128 {
	m := len(v)
	if pow2(m) == m {
		return radix(v, inverse)
	}
	if inverse {
		a := make([]complex128, m)
		for i, z := range v {
			a[i] = cmplx.Conj(z)
		}
		a = transform(a, false)
		for i := range a {
			a[i] = cmplx.Conj(a[i]) / complex(float64(m), 0)
		}
		return a
	}
	q := pow2(2*m - 1)
	w, a, b := make([]complex128, m), make([]complex128, q), make([]complex128, q)
	for n := 0; n < m; n++ {
		w[n] = rot(pi * float64(n*n%(2*m)) / float64(m))
		a[n] = v[n] * w[n]
		b[n] = cmplx.Conj(w[n])
		if n > 0 {
			b[q-n] = b[n]
		}
	}
	a, b = radix(a, false), radix(b, false)
	for i := range a {
		a[i] *= b[i]
	}
	g := radix(a, true)
	for k := 0; k < m; k++ {
		g[k] *= w[k]
	}
	return g[:m]
}
func realComplex(v []float64, q int) []complex128 {
	a := make([]complex128, q)
	for i, x := range v {
		a[i] = complex(x, 0)
	}
	return a
}
func realParts(v []complex128) []float64 {
	a := make([]float64, len(v))
	for i, z := range v {
		a[i] = real(z)
	}
	return a
}
func packed(v []float64) []complex128 {
	q := len(v)
	h := q / 2
	z := make([]complex128, h)
	for j := range z {
		z[j] = complex(v[2*j], v[2*j+1])
	}
	z = radix(z, false)
	out := make([]complex128, h+1)
	for k := range out {
		a, b := z[k%h], cmplx.Conj(z[(h-k+h)%h])
		e, o := (a+b)/2, (a-b)/complex(0, 2)
		out[k] = e + rot(2*pi*float64(k)/float64(q))*o
	}
	return out
}
func convolution(a, b []float64) []float64 {
	n := len(a) + len(b) - 1
	q := pow2(n)
	x, y := radix(realComplex(a, q), false), radix(realComplex(b, q), false)
	for k := range x {
		x[k] *= y[k]
	}
	return realParts(radix(x, true))[:n]
}
func chirpZ(u []float64, fs, z1, z2, j int) []complex128 {
	m := len(u)
	q := pow2(m + j - 1)
	dz := float64(z2-z1) / float64(j-1)
	a, b := make([]complex128, q), make([]complex128, q)
	for n, v := range u {
		a[n] = complex(v, 0) * rot(2*pi*float64(z1*n)/float64(fs)) * rot(pi*dz*float64(n*n)/float64(fs))
	}
	for k := -(m - 1); k < j; k++ {
		index := k
		if index < 0 {
			index += q
		}
		b[index] = cmplx.Conj(rot(pi * dz * float64(k*k) / float64(fs)))
	}
	a, b = radix(a, false), radix(b, false)
	for k := range a {
		a[k] *= b[k]
	}
	g := radix(a, true)
	for k := 0; k < j; k++ {
		g[k] *= rot(pi * dz * float64(k*k) / float64(fs))
	}
	return g[:j]
}
