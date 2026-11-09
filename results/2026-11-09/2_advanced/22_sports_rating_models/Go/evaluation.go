package main

import "math"

func sigma(value float64) float64 { return 1 / (1 + math.Exp(-value)) }
func fitLink(features, results []float64, iterations int) [2]float64 {
	alpha, beta := 0.0, 0.0
	for iteration := 0; iteration < iterations; iteration++ {
		g0, g1, h00, h01, h11 := 0.0, 0.0, 0.0, 0.0, 0.0
		for k, z := range features {
			p := sigma(alpha + beta*z)
			w := p * (1 - p)
			g0 += results[k] - p
			g1 += (results[k] - p) * z
			h00 += w
			h01 += w * z
			h11 += w * z * z
		}
		det := h00*h11 - h01*h01
		alpha, beta = alpha+(h11*g0-h01*g1)/det, beta+(h00*g1-h01*g0)/det
	}
	return [2]float64{alpha, beta}
}
func logLoss(p float64, result2 int) float64 {
	if result2 == 2 {
		return -math.Log(p)
	}
	if result2 == 0 {
		return -math.Log(1 - p)
	}
	return -(math.Log(p)/2 + math.Log(1-p)/2)
}
func brierScore(p, y float64) float64 { return (p - y) * (p - y) }
func correctness2(p float64, result2 int) int {
	if result2 == 1 {
		return 1
	}
	if p > 0.5 && result2 == 2 || p < 0.5 && result2 == 0 {
		return 2
	}
	return 0
}
func averageRanks2(values []Fraction) []int64 {
	ranks := make([]int64, len(values))
	for i, value := range values {
		greater, equal := int64(0), int64(0)
		for _, other := range values {
			compared := other.Cmp(value)
			if compared > 0 {
				greater++
			} else if compared == 0 {
				equal++
			}
		}
		ranks[i] = 2*greater + equal + 1
	}
	return ranks
}
func kendallTau(first, second []Fraction) Fraction {
	count := int64(len(first))
	balance := int64(0)
	for t := 0; t < len(first); t++ {
		for u := t + 1; u < len(first); u++ {
			agreement := first[t].Cmp(first[u]) * second[t].Cmp(second[u])
			if agreement > 0 {
				balance++
			} else if agreement < 0 {
				balance--
			}
		}
	}
	return fraction(balance, count*(count-1)/2)
}
func spearmanRho(first, second []Fraction) Fraction {
	count := int64(len(first))
	a, b := averageRanks2(first), averageRanks2(second)
	squares := int64(0)
	for i := range a {
		difference := a[i] - b[i]
		squares += difference * difference
	}
	denominator := 4 * count * (count*count - 1)
	return fraction(denominator-6*squares, denominator)
}
