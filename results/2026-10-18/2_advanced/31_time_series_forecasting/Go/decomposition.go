package main

func total(values []float64) float64 {
	result := 0.0
	for _, v := range values {
		result += v
	}
	return result
}
func mean(values []float64) float64 { return total(values) / float64(len(values)) }
func sampleVariance(values []float64) float64 {
	average := mean(values)
	squares := 0.0
	for _, v := range values {
		d := v - average
		squares += d * d
	}
	return squares / float64(len(values)-1)
}

type Decomposition struct {
	Trend, ResidualAdd, ResidualMult []*float64
	Additive, Multiplicative         []float64
	Defined                          []int
}

func pointer(value float64) *float64 { return &value }
func decompose(values []float64, season int) Decomposition {
	n, half := len(values), season/2
	d := Decomposition{Trend: make([]*float64, n), ResidualAdd: make([]*float64, n), ResidualMult: make([]*float64, n)}
	for t := half; t < n-half; t++ {
		d.Defined = append(d.Defined, t)
		v := 0.5 * values[t-half]
		for i := t - half + 1; i < t+half; i++ {
			v += values[i]
		}
		v += 0.5 * values[t+half]
		d.Trend[t] = pointer(v / float64(season))
	}
	for j := 0; j < season; j++ {
		add, mult := []float64{}, []float64{}
		for _, t := range d.Defined {
			if t%season == j {
				add = append(add, values[t]-*d.Trend[t])
				mult = append(mult, values[t] / *d.Trend[t])
			}
		}
		d.Additive = append(d.Additive, mean(add))
		d.Multiplicative = append(d.Multiplicative, mean(mult))
	}
	a, b := mean(d.Additive), mean(d.Multiplicative)
	for j := 0; j < season; j++ {
		d.Additive[j] -= a
		d.Multiplicative[j] /= b
	}
	for _, t := range d.Defined {
		d.ResidualAdd[t] = pointer(values[t] - *d.Trend[t] - d.Additive[t%season])
		d.ResidualMult[t] = pointer(values[t] / (*d.Trend[t] * d.Multiplicative[t%season]))
	}
	return d
}
func leastSquares(values []float64) (float64, float64) {
	center := float64(len(values)+1) / 2
	average := mean(values)
	numerator, denominator := 0.0, 0.0
	for t, v := range values {
		u := float64(t+1) - center
		numerator += u * (v - average)
		denominator += u * u
	}
	slope := numerator / denominator
	return average - slope*center, slope
}
