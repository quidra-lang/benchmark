package main

import "math"

type RowDiagnostic struct {
	Standardized, Studentized, Cooks, DFFITS float64
	Flags                                    string
	DFBETAS                                  []float64
}
type Diagnostic struct {
	Rows                                     []RowDiagnostic
	DW, BP, BPP, JB, JBP, Skewness, Kurtosis float64
	BPDF                                     int
}

func calculateDiagnostics(f *Fit, p Params) Diagnostic {
	n, r := f.N, f.Rank
	df := n - r
	sigma := math.Sqrt(f.RSS / float64(df))
	leverageLimit := p.Leverage * float64(r) / float64(n)
	cookLimit := p.Cook / float64(n)
	dffitsLimit := p.DFFITS * math.Sqrt(float64(r)/float64(n))
	result := Diagnostic{}
	for i := 0; i < n; i++ {
		h, eps := f.Leverage[i], f.WeightedResidual[i]
		z := eps / (sigma * math.Sqrt(1-h))
		t := z * math.Sqrt(float64(df-1)/(float64(df)-z*z))
		cook := z * z * h / (float64(r) * (1 - h))
		dffits := t * math.Sqrt(h/(1-h))
		flags := ""
		if h > leverageLimit {
			flags += "H"
		}
		if math.Abs(t) > p.Studentized {
			flags += "O"
		}
		if cook > cookLimit {
			flags += "C"
		}
		if math.Abs(dffits) > dffitsLimit {
			flags += "F"
		}
		if flags == "" {
			flags = "-"
		}
		deleted := sigma * math.Sqrt((float64(df)-z*z)/float64(df-1))
		db := make([]float64, r)
		for k := range db {
			db[k] = f.G[i][k] * eps / (1 - h) / (deleted * math.Sqrt(f.Variance[k]))
		}
		result.Rows = append(result.Rows, RowDiagnostic{z, t, cook, dffits, flags, db})
	}
	numerator := 0.0
	for i := 1; i < n; i++ {
		d := f.WeightedResidual[i] - f.WeightedResidual[i-1]
		numerator += d * d
	}
	result.DW = numerator / f.RSS
	squared := make([]float64, n)
	ones := make([]float64, n)
	accepted := matrix(n, r)
	sum := 0.0
	for i, v := range f.WeightedResidual {
		squared[i] = v * v
		sum += squared[i]
		ones[i] = 1
		for k, j := range f.Accepted {
			accepted[i][k] = f.Matrix[i][j]
		}
	}
	aux := fit(accepted, squared, ones, p.Tolerance)
	mean := sum / float64(n)
	tss := 0.0
	for _, v := range squared {
		tss += (v - mean) * (v - mean)
	}
	result.BP = float64(n) * (1 - aux.RSS/tss)
	result.BPDF = aux.Rank - 1
	result.BPP = chiP(result.BP, result.BPDF)
	sum = 0
	for _, v := range f.WeightedResidual {
		sum += v
	}
	mean = sum / float64(n)
	m2, m3, m4 := 0.0, 0.0, 0.0
	for _, v := range f.WeightedResidual {
		d := v - mean
		m2 += d * d
		m3 += d * d * d
		m4 += d * d * d * d
	}
	m2 /= float64(n)
	m3 /= float64(n)
	m4 /= float64(n)
	result.Skewness = m3 / (m2 * math.Sqrt(m2))
	result.Kurtosis = m4 / (m2 * m2)
	s, k := result.Skewness, result.Kurtosis
	result.JB = float64(n) / 6 * (s*s + (k-3)*(k-3)/4)
	result.JBP = chiP(result.JB, 2)
	return result
}
