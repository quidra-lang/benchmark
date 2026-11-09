package main

import (
	"math"
	"slices"
)

func sumIntegers(values []int64) int64 {
	total := int64(0)
	for _, value := range values {
		total += value
	}
	return total
}
func sequentialSum(values []float64) float64 {
	total := 0.0
	for _, value := range values {
		total += value
	}
	return total
}
func orderedIntegers(values []int64) []int64 {
	ordered := append([]int64(nil), values...)
	slices.Sort(ordered)
	return ordered
}
func orderedReals(values []float64) []float64 {
	ordered := append([]float64(nil), values...)
	slices.Sort(ordered)
	return ordered
}
func mean(values []int64) float64 { return float64(sumIntegers(values)) / float64(100*len(values)) }
func doubledMedian(values []int64) int64 {
	ordered := orderedIntegers(values)
	count := len(values)
	return ordered[(count-1)/2] + ordered[count/2]
}
func median(values []int64) float64 { return float64(doubledMedian(values)) / 200 }
func trimmedMean(values []int64) float64 {
	ordered := orderedIntegers(values)
	count := len(values)
	trim := count / 10
	return float64(sumIntegers(ordered[trim:count-trim])) / float64(100*(count-2*trim))
}
func sd(values []int64) float64 {
	center := mean(values)
	squares := 0.0
	for _, value := range values {
		deviation := float64(value)/100 - center
		squares += deviation * deviation
	}
	return math.Sqrt(squares / float64(len(values)-1))
}
func centralMoments(values []int64) (float64, float64, float64) {
	center := mean(values)
	second, third, fourth := 0.0, 0.0, 0.0
	for _, value := range values {
		e := float64(value)/100 - center
		second += e * e
		third += e * e * e
		fourth += e * e * e * e
	}
	count := float64(len(values))
	return second / count, third / count, fourth / count
}
func absInteger(value int64) int64 {
	if value < 0 {
		return -value
	}
	return value
}
func mad(values []int64) float64 {
	center := doubledMedian(values)
	deviations := make([]int64, len(values))
	for i, value := range values {
		deviations[i] = absInteger(2*value - center)
	}
	return float64(doubledMedian(deviations)) / 400
}
func quantileNumerator(values []int64, percent int) int64 {
	ordered := orderedIntegers(values)
	position := (len(values) - 1) * percent
	index, fraction := position/100, int64(position%100)
	result := 100 * ordered[index]
	if fraction > 0 {
		result += fraction * (ordered[index+1] - ordered[index])
	}
	return result
}
func winsorized(values []int64) []int64 {
	ordered := orderedIntegers(values)
	trim := len(values) / 10
	low, high := ordered[trim], ordered[len(values)-trim-1]
	result := make([]int64, len(values))
	for i, value := range values {
		result[i] = min(max(value, low), high)
	}
	return result
}
func meanDifference(x, y []int64) float64 {
	return float64(int64(len(y))*sumIntegers(x)-int64(len(x))*sumIntegers(y)) / float64(100*len(x)*len(y))
}
func medianRatio(x, y []int64) float64 { return float64(doubledMedian(x)) / float64(doubledMedian(y)) }
func hodgesLehmann(x, y []int64) float64 {
	differences := make([]int64, 0, len(x)*len(y))
	for _, first := range x {
		for _, second := range y {
			differences = append(differences, first-second)
		}
	}
	return float64(doubledMedian(differences)) / 200
}
func pooledSD(x, y []int64) float64 {
	first, second := sd(x), sd(y)
	squares := float64(len(x)-1)*first*first + float64(len(y)-1)*second*second
	return math.Sqrt(squares / float64(len(x)+len(y)-2))
}
func cohenD(x, y []int64) float64 { return meanDifference(x, y) / pooledSD(x, y) }
func correlation(x, y []int64) float64 {
	firstCenter, secondCenter := mean(x), mean(y)
	products, firstSquares, secondSquares := 0.0, 0.0, 0.0
	for i, value := range x {
		e, f := float64(value)/100-firstCenter, float64(y[i])/100-secondCenter
		products += e * f
		firstSquares += e * e
		secondSquares += f * f
	}
	return products / math.Sqrt(firstSquares*secondSquares)
}
func resampleIndices(generator *Minstd, size int) []int {
	indices := make([]int, size)
	for i := range indices {
		indices[i] = generator.below(size)
	}
	return indices
}
func ordinaryIndices(generator *Minstd, size, count int) [][]int {
	indices := make([][]int, count)
	for i := range indices {
		indices[i] = resampleIndices(generator, size)
	}
	return indices
}
func balancedIndices(generator *Minstd, size, count int) [][]int {
	sequence := make([]int, size*count)
	for i := range sequence {
		sequence[i] = i % size
	}
	shuffle(generator, sequence)
	indices := make([][]int, count)
	for i := range indices {
		indices[i] = append([]int(nil), sequence[i*size:(i+1)*size]...)
	}
	return indices
}
func without(values []int64, index int) []int64 {
	result := append([]int64(nil), values[:index]...)
	return append(result, values[index+1:]...)
}
func meanAndSE(values []float64) (float64, float64) {
	average := sequentialSum(values) / float64(len(values))
	squares := 0.0
	for _, value := range values {
		d := value - average
		squares += d * d
	}
	return average, math.Sqrt(squares / float64(len(values)-1))
}
func phi(x float64) float64 {
	if x < 0 {
		return 1 - phi(-x)
	}
	eta := 1 / (1 + 0.2316419*x)
	psi := eta * (0.319381530 + eta*(-0.356563782+eta*(1.781477937+eta*(-1.821255978+eta*1.330274429))))
	return 1 - 0.3989422804014327*math.Exp(-(x*x)/2)*psi
}
func phiInverse(p float64) float64 {
	if p > 0.5 {
		return -phiInverse(1 - p)
	}
	eta := math.Sqrt(-2 * math.Log(p))
	numerator := 2.515517 + eta*(0.802853+eta*0.010328)
	denominator := 1 + eta*(1.432788+eta*(0.189269+eta*0.001308))
	return -(eta - numerator/denominator)
}
