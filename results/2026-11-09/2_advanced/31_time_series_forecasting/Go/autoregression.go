package main

import "math"

var differenceKinds = []string{"none", "first", "seasonal", "both"}

func difference(values []float64, season int, kind string) ([]float64, int) {
	offset := 0
	switch kind {
	case "first":
		offset = 1
	case "seasonal":
		offset = season
	case "both":
		offset = season + 1
	}
	result := []float64{}
	for t := offset; t < len(values); t++ {
		value := values[t]
		switch kind {
		case "first":
			value -= values[t-1]
		case "seasonal":
			value -= values[t-season]
		case "both":
			value = (values[t] - values[t-1]) - (values[t-season] - values[t-season-1])
		}
		result = append(result, value)
	}
	return result, offset
}
func autocorrelation(values []float64, maxLag int) (float64, float64, []float64) {
	average := mean(values)
	centered := []float64{}
	squares := 0.0
	for _, v := range values {
		d := v - average
		centered = append(centered, d)
		squares += d * d
	}
	n := float64(len(values))
	variance := squares / n
	correlations := []float64{1}
	for lag := 1; lag <= maxLag; lag++ {
		numerator := 0.0
		for i := 0; i < len(values)-lag; i++ {
			numerator += centered[i] * centered[i+lag]
		}
		correlations = append(correlations, numerator/n/variance)
	}
	return average, variance, correlations
}
func durbinLevinson(r []float64) ([][]float64, []float64, []float64) {
	coefficients := [][]float64{{}}
	partial, variances := []float64{0}, []float64{1}
	for order := 1; order < len(r); order++ {
		previous := coefficients[order-1]
		correction := 0.0
		for j := 1; j < order; j++ {
			correction += previous[j-1] * r[order-j]
		}
		theta := (r[order] - correction) / variances[order-1]
		current := []float64{}
		for j := 1; j < order; j++ {
			current = append(current, previous[j-1]-theta*previous[order-j-1])
		}
		current = append(current, theta)
		coefficients = append(coefficients, current)
		partial = append(partial, theta)
		variances = append(variances, variances[order-1]*(1-theta*theta))
	}
	return coefficients, partial, variances
}
func arResiduals(values []float64, average float64, coefficients []float64) []float64 {
	errors := []float64{}
	p := len(coefficients)
	for i := p; i < len(values); i++ {
		correction := 0.0
		for j, c := range coefficients {
			correction += c * (values[i-j-1] - average)
		}
		errors = append(errors, values[i]-average-correction)
	}
	return errors
}
func arForecast(values, transformed []float64, offset int, kind string, average float64, coefficients []float64, origin, steps, season int) []float64 {
	transformed = append([]float64(nil), transformed[:origin-offset]...)
	extended := append([]float64(nil), values[:origin]...)
	result := []float64{}
	for k := 0; k < steps; k++ {
		correction := 0.0
		for j, c := range coefficients {
			correction += c * (transformed[len(transformed)-j-1] - average)
		}
		predicted := average + correction
		transformed = append(transformed, predicted)
		n := len(extended)
		switch kind {
		case "first":
			predicted += extended[n-1]
		case "seasonal":
			predicted += extended[n-season]
		case "both":
			predicted = predicted + extended[n-1] + extended[n-season] - extended[n-season-1]
		}
		extended = append(extended, predicted)
		result = append(result, predicted)
	}
	return result
}

type LjungBox struct {
	Lag  int
	Q, P float64
}

func ljungBox(errors []float64, lags []int) []LjungBox {
	maxLag := 0
	for _, lag := range lags {
		maxLag = max(maxLag, lag)
	}
	_, _, r := autocorrelation(errors, maxLag)
	n := float64(len(errors))
	result := []LjungBox{}
	for _, lag := range lags {
		sum := 0.0
		for k := 1; k <= lag; k++ {
			sum += r[k] * r[k] / (n - float64(k))
		}
		q := n * (n + 2) * sum
		x := q / 2
		term, terms := 1.0, 1.0
		for i := 1; i < lag/2; i++ {
			term = term * x / float64(i)
			terms += term
		}
		result = append(result, LjungBox{lag, q, math.Exp(-x) * terms})
	}
	return result
}
