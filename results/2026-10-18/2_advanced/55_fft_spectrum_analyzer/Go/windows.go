package main

import (
	"math"
	"math/cmplx"
)

var windowNames = []string{"rectangular", "hann", "hamming", "blackman", "flattop"}

func window(name string, q int) []float64 {
	coeff := map[string][]float64{"rectangular": {1}, "hann": {.5, .5}, "hamming": {.54, .46}, "blackman": {.42,
		.5, .08}, "flattop": {.21557895, .41663158, .277263158, .083578947, .006947368}}[name]
	w := make([]float64, q)
	for n := range w {
		for j, c := range coeff {
			sign := 1.0
			if j%2 == 1 {
				sign = -1
			}
			w[n] += sign * c * math.Cos(2*pi*float64(j*n)/float64(q))
		}
	}
	return w
}

type WindowFigures struct{ S1, S2, Gain, ENBW, Hz, Scalloping float64 }

func figures(w []float64, fs int) WindowFigures {
	f := WindowFigures{}
	z := complex(0, 0)
	for n, v := range w {
		f.S1 += v
		f.S2 += v * v
		z += complex(v, 0) * rot(pi*float64(n)/float64(len(w)))
	}
	f.Gain = f.S1 / float64(len(w))
	f.ENBW = float64(len(w)) * f.S2 / (f.S1 * f.S1)
	f.Hz = f.ENBW * float64(fs) / float64(len(w))
	f.Scalloping = -20 * math.Log10(cmplx.Abs(z)/f.S1)
	return f
}
