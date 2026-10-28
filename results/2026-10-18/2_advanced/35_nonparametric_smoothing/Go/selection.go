package main

import "math"

func orderedSum(values []float64) float64 {
	var total float64
	for _, v := range values {
		total += v
	}
	return total
}
func crossValidationScore(observed, predicted []float64) float64 {
	var total float64
	for i, y := range observed {
		if math.IsNaN(predicted[i]) {
			return math.NaN()
		}
		d := y - predicted[i]
		total += d * d
	}
	return total / float64(len(observed))
}
func residualSquare(observed, fitted []float64) float64 {
	var total float64
	for i, y := range observed {
		d := y - fitted[i]
		total += d * d
	}
	return total
}
func generalizedScore(observed, fitted []float64, edf float64) float64 {
	tau := 1 - edf/float64(len(observed))
	return residualSquare(observed, fitted) / float64(len(observed)) / (tau * tau)
}
func chooseCandidate(candidates []Candidate) int {
	best := -1
	for i, c := range candidates {
		if !math.IsNaN(c.Score) && (best < 0 || c.Score < candidates[best].Score) {
			best = i
		}
	}
	return best
}
