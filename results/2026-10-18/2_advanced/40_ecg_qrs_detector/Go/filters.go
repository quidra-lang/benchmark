package main

type Signals struct{ Lowpass, Bandpass, Derivative, Squared, Integrated []int64 }

func at(values []int64, index int) int64 {
	if index < 0 {
		return 0
	}
	return values[index]
}
func filterECG(samples []int64) *Signals {
	n := len(samples)
	c, s := make([]int64, n), make([]int64, n)
	f := &Signals{make([]int64, n), make([]int64, n), make([]int64, n), make([]int64, n), make([]int64, n)}
	var window int64
	for i := range n {
		c[i] = 2*at(c, i-1) - at(c, i-2) + samples[i] - 2*at(samples, i-6) + at(samples, i-12)
		f.Lowpass[i] = floorDiv(c[i], 32)
		s[i] = at(s, i-1) + f.Lowpass[i] - at(f.Lowpass, i-32)
		f.Bandpass[i] = at(f.Lowpass, i-16) - floorDiv(s[i], 32)
		f.Derivative[i] = floorDiv(2*f.Bandpass[i]+at(f.Bandpass, i-1)-at(f.Bandpass, i-3)-2*at(f.Bandpass, i-4), 8)
		f.Squared[i] = f.Derivative[i] * f.Derivative[i]
		window += f.Squared[i]
		if i >= 30 {
			window -= f.Squared[i-30]
		}
		f.Integrated[i] = window / 30
	}
	return f
}
