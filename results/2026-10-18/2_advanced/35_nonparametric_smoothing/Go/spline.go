package main

import "sort"

type SplineValues struct{ Fitted, Gamma []float64 }
type SplineFit struct {
	BaseFit
	Positions       []int
	X, H, D, L1, L2 []float64
	Penalty         float64
	Fit             SplineValues
	Basis           []SplineValues
}

func newSplineFit(positions []int, values []float64, penalty float64, diagnostics bool) *SplineFit {
	f := &SplineFit{Positions: positions, Penalty: penalty}
	for _, p := range positions {
		f.X = append(f.X, float64(p)/100)
	}
	for i := 0; i < len(positions)-1; i++ {
		f.H = append(f.H, f.X[i+1]-f.X[i])
	}
	f.Decompose()
	f.Fit = f.FitValues(values)
	f.Fitted = f.Fit.Fitted
	if diagnostics {
		f.PrepareBasis()
	}
	return f
}
func (f *SplineFit) Decompose() {
	size := len(f.Positions) - 2
	a, b, c := make([]float64, size), make([]float64, size), make([]float64, size)
	for i := range size {
		a[i] = 1 / f.H[i]
		c[i] = 1 / f.H[i+1]
		b[i] = -(a[i] + c[i])
	}
	diagonal := make([]float64, size)
	first := make([]float64, max(0, size-1))
	second := make([]float64, max(0, size-2))
	for i := range size {
		diagonal[i] = (f.H[i]+f.H[i+1])/3 + f.Penalty*(a[i]*a[i]+b[i]*b[i]+c[i]*c[i])
		if i < size-1 {
			first[i] = f.H[i+1]/6 + f.Penalty*c[i]*(b[i]+b[i+1])
		}
		if i < size-2 {
			second[i] = f.Penalty * c[i] * c[i+1]
		}
	}
	f.D = make([]float64, size)
	f.L1 = make([]float64, size)
	f.L2 = make([]float64, size)
	for i := range size {
		if i >= 2 {
			f.L2[i] = second[i-2] / f.D[i-2]
		}
		if i >= 1 {
			correction := 0.0
			if i >= 2 {
				correction = f.L2[i] * f.D[i-2] * f.L1[i-1]
			}
			f.L1[i] = (first[i-1] - correction) / f.D[i-1]
		}
		v := diagonal[i]
		if i >= 1 {
			v -= f.L1[i] * f.L1[i] * f.D[i-1]
		}
		if i >= 2 {
			v -= f.L2[i] * f.L2[i] * f.D[i-2]
		}
		f.D[i] = v
	}
}
func (f *SplineFit) FitValues(values []float64) SplineValues {
	n := len(values)
	size := n - 2
	z := make([]float64, size)
	for i := range size {
		v := (values[i+2]-values[i+1])/f.H[i+1] - (values[i+1]-values[i])/f.H[i]
		if i >= 1 {
			v -= f.L1[i] * z[i-1]
		}
		if i >= 2 {
			v -= f.L2[i] * z[i-2]
		}
		z[i] = v
	}
	gamma := make([]float64, n)
	for i := size - 1; i >= 0; i-- {
		v := z[i] / f.D[i]
		if i+1 < size {
			v -= f.L1[i+1] * gamma[i+2]
		}
		if i+2 < size {
			v -= f.L2[i+2] * gamma[i+3]
		}
		gamma[i+1] = v
	}
	omega := make([]float64, n)
	omega[0] = (gamma[1] - gamma[0]) / f.H[0]
	for i := 1; i < n-1; i++ {
		omega[i] = (gamma[i+1]-gamma[i])/f.H[i] - (gamma[i]-gamma[i-1])/f.H[i-1]
	}
	omega[n-1] = 0 - (gamma[n-1]-gamma[n-2])/f.H[n-2]
	fitted := make([]float64, n)
	for i, v := range values {
		fitted[i] = v - f.Penalty*omega[i]
	}
	return SplineValues{fitted, gamma}
}
func (f *SplineFit) EvaluateFit(fit SplineValues, position int) float64 {
	g, gamma := fit.Fitted, fit.Gamma
	n := len(g)
	x0 := float64(position) / 100
	index := sort.SearchInts(f.Positions, position)
	if index < n && f.Positions[index] == position {
		return g[index]
	}
	if index == 0 {
		tau := (g[1]-g[0])/f.H[0] - f.H[0]*gamma[1]/6
		return g[0] - (f.X[0]-x0)*tau
	}
	if index == n {
		tau := (g[n-1]-g[n-2])/f.H[n-2] + f.H[n-2]*gamma[n-2]/6
		return g[n-1] + (x0-f.X[n-1])*tau
	}
	i := index - 1
	pl, pr := x0-f.X[i], f.X[i+1]-x0
	return (pl*g[i+1]+pr*g[i])/f.H[i] - pl*pr*((1+pl/f.H[i])*gamma[i+1]+(1+pr/f.H[i])*gamma[i])/6
}
func (f *SplineFit) PrepareBasis() {
	if f.Basis != nil {
		return
	}
	n := len(f.Positions)
	f.Basis = make([]SplineValues, n)
	f.Leverage = make([]float64, n)
	for i := range n {
		unit := make([]float64, n)
		unit[i] = 1
		f.Basis[i] = f.FitValues(unit)
		f.Leverage[i] = f.Basis[i].Fitted[i]
	}
	f.EDF = orderedSum(f.Leverage)
}
func (f *SplineFit) Estimate(position int) float64 { return f.EvaluateFit(f.Fit, position) }
func (f *SplineFit) Weights(position int) []float64 {
	f.PrepareBasis()
	weights := make([]float64, len(f.Basis))
	for i, fit := range f.Basis {
		weights[i] = f.EvaluateFit(fit, position)
	}
	return weights
}
