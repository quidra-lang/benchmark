package main

import (
	"fmt"
	"math"
)

func logGamma(x float64) float64 {
	coefficients := []float64{76.18009172947146, -86.50532032941677, 24.01409824083091, -1.231739572450155, 0.001208650973866179, -0.000005395239384953}
	t := x + 5.5
	adjustment := t - (x+0.5)*math.Log(t)
	series := 1.000000000190015
	for j, c := range coefficients {
		series += c / (x + float64(j+1))
	}
	return -adjustment + math.Log(2.5066282746310005*series/x)
}
func replaceSmall(v float64) float64 {
	if math.Abs(v) < 1e-300 {
		return 1e-300
	}
	return v
}
func betaFraction(a, b, x float64) float64 {
	c := 1.0
	d := 1 / replaceSmall(1-(a+b)*x/(a+1))
	h := d
	for m := 1; m <= 1000; m++ {
		v := float64(m)
		q := v * (b - v) * x / ((a - 1 + 2*v) * (a + 2*v))
		d = 1 / replaceSmall(1+q*d)
		c = replaceSmall(1 + q/c)
		h *= d * c
		q = -(a + v) * (a + b + v) * x / ((a + 2*v) * (a + 1 + 2*v))
		d = 1 / replaceSmall(1+q*d)
		c = replaceSmall(1 + q/c)
		delta := d * c
		h *= delta
		if math.Abs(delta-1) < 1e-15 {
			break
		}
	}
	return h
}
func incompleteBeta(x, a, b float64) float64 {
	if x <= 0 {
		return 0
	}
	if x >= 1 {
		return 1
	}
	factor := math.Exp(logGamma(a+b) - logGamma(a) - logGamma(b) + a*math.Log(x) + b*math.Log(1-x))
	if x < (a+1)/(a+b+2) {
		return factor * betaFraction(a, b, x) / a
	}
	return 1 - factor*betaFraction(b, a, 1-x)/b
}
func upperGamma(a, x float64) float64 {
	if x <= 0 {
		return 1
	}
	factor := math.Exp(-x + a*math.Log(x) - logGamma(a))
	if x < a+1 {
		term, e := 1/a, a
		series := term
		for i := 0; i < 1000; i++ {
			e++
			term *= x / e
			series += term
			if math.Abs(term) < math.Abs(series)*1e-15 {
				break
			}
		}
		return 1 - series*factor
	}
	b := x + 1 - a
	c, d := 1/1e-300, 1/b
	h := d
	for i := 1; i <= 1000; i++ {
		q := -float64(i) * (float64(i) - a)
		b += 2
		d = 1 / replaceSmall(q*d+b)
		c = replaceSmall(b + q/c)
		delta := d * c
		h *= delta
		if math.Abs(delta-1) < 1e-15 {
			break
		}
	}
	return factor * h
}
func tP(t float64, df int) float64 { nu := float64(df); return incompleteBeta(nu/(nu+t*t), nu/2, 0.5) }
func fP(f float64, d1, d2 int) float64 {
	a, b := float64(d1), float64(d2)
	return incompleteBeta(b/(b+a*f), b/2, a/2)
}
func chiP(stat float64, df int) float64 { return upperGamma(float64(df)/2, stat/2) }
func tQuantile(confidence float64, df int) float64 {
	lo, hi := 0.0, 1000.0
	for i := 0; i < 100; i++ {
		mid := (lo + hi) / 2
		if tP(mid, df) > 1-confidence {
			lo = mid
		} else {
			hi = mid
		}
	}
	return (lo + hi) / 2
}
func significance(p float64) string {
	if math.IsNaN(p) {
		return ""
	}
	if p < 0.001 {
		return "***"
	}
	if p < 0.01 {
		return "**"
	}
	if p < 0.05 {
		return "*"
	}
	if p < 0.1 {
		return "."
	}
	return ""
}
func four(v float64) string {
	if math.IsNaN(v) {
		return "NA"
	}
	text := fmt.Sprintf("%.4f", v)
	if text == "-0.0000" {
		return "0.0000"
	}
	return text
}
func probability(v float64) string {
	if math.IsNaN(v) {
		return "NA"
	}
	if v < 0.0001 {
		return "<0.0001"
	}
	return four(v)
}
