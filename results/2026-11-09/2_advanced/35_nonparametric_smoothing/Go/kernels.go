package main

import "math"

var kernelConstants = map[string]float64{"epanechnikov": 0.75, "biweight": 0.9375, "triweight": 1.09375}

type KernelEvaluation struct {
	Estimate float64
	Weights  []float64
}
type KernelFit struct {
	BaseFit
	Positions   []int
	X, Y        []float64
	Bandwidth   int
	Kernel      string
	LocalLinear bool
	Cache       map[int]KernelEvaluation
}

func newKernelFit(positions []int, values []float64, bandwidth int, kernel string, localLinear, diagnostics bool) *KernelFit {
	f := &KernelFit{BaseFit: BaseFit{EDF: math.NaN()}, Positions: positions, Y: values, Bandwidth: bandwidth,
		Kernel: kernel, LocalLinear: localLinear, Cache: map[int]KernelEvaluation{}}
	for _, x := range positions {
		f.X = append(f.X, float64(x)/100)
	}
	if diagnostics {
		f.Fitted = make([]float64, len(values))
		f.Leverage = make([]float64, len(values))
		for i, p := range positions {
			result := f.Evaluate(p)
			if math.IsNaN(result.Estimate) {
				f.Fitted = nil
				f.Leverage = nil
				return f
			}
			f.Fitted[i] = result.Estimate
			f.Leverage[i] = result.Weights[i]
		}
		f.EDF = orderedSum(f.Leverage)
	}
	return f
}
func (f *KernelFit) Evaluate(position int) KernelEvaluation {
	if v, ok := f.Cache[position]; ok {
		return v
	}
	used := []int{}
	for i, x := range f.Positions {
		if absInt(x-position) < f.Bandwidth {
			used = append(used, i)
		}
	}
	minimum := 1
	if f.LocalLinear {
		minimum = 2
	}
	if len(used) < minimum {
		v := KernelEvaluation{Estimate: math.NaN()}
		f.Cache[position] = v
		return v
	}
	x0, h := float64(position)/100, float64(f.Bandwidth)/100
	kernels, differences := []float64{}, []float64{}
	var s0, t0, s1, s2, t1 float64
	for _, i := range used {
		d := f.X[i] - x0
		u := d / h
		t := 1 - u*u
		k := kernelConstants[f.Kernel] * t
		if f.Kernel != "epanechnikov" {
			k *= t
		}
		if f.Kernel == "triweight" {
			k *= t
		}
		kernels = append(kernels, k)
		differences = append(differences, d)
		s0 += k
		t0 += k * f.Y[i]
		s1 += k * d
		s2 += k * d * d
		t1 += k * d * f.Y[i]
	}
	weights := make([]float64, len(f.Positions))
	estimate := t0 / s0
	if f.LocalLinear {
		q := s0*s2 - s1*s1
		estimate = (s2*t0 - s1*t1) / q
		for j, i := range used {
			weights[i] = kernels[j] * (s2 - s1*differences[j]) / q
		}
	} else {
		for j, i := range used {
			weights[i] = kernels[j] / s0
		}
	}
	result := KernelEvaluation{estimate, weights}
	f.Cache[position] = result
	return result
}
func (f *KernelFit) Estimate(position int) float64  { return f.Evaluate(position).Estimate }
func (f *KernelFit) Weights(position int) []float64 { return f.Evaluate(position).Weights }
