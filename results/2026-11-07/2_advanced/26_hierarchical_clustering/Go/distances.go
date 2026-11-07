package main

import "math"

var distanceTypes = []string{"euclidean", "manhattan", "correlation"}

func sequentialSum(values []float64) float64 {
	total := 0.0
	for _, value := range values {
		total += value
	}
	return total
}
func squaredDistance(u, w []float64) float64 {
	total := 0.0
	for i, value := range u {
		difference := value - w[i]
		total += difference * difference
	}
	return total
}
func floatMatrix(rows, columns int) [][]float64 {
	matrix := make([][]float64, rows)
	for i := range matrix {
		matrix[i] = make([]float64, columns)
	}
	return matrix
}
func featureStatistics(rows [][]float64) ([]float64, []float64) {
	count := len(rows)
	means, deviations := make([]float64, len(rows[0])), make([]float64, len(rows[0]))
	for f := range means {
		total := 0.0
		for _, row := range rows {
			total += row[f]
		}
		mean := total / float64(count)
		squares := 0.0
		for _, row := range rows {
			difference := row[f] - mean
			squares += difference * difference
		}
		means[f] = mean
		deviations[f] = math.Sqrt(squares / float64(count-1))
	}
	return means, deviations
}
func standardize(rows [][]float64, means, deviations []float64) [][]float64 {
	result := floatMatrix(len(rows), len(means))
	for i, row := range rows {
		for f, value := range row {
			result[i][f] = (value - means[f]) / deviations[f]
		}
	}
	return result
}
func distance(u, w []float64, kind string) float64 {
	if kind == "euclidean" {
		return math.Sqrt(squaredDistance(u, w))
	}
	if kind == "manhattan" {
		total := 0.0
		for f, value := range u {
			total += math.Abs(value - w[f])
		}
		return total
	}
	mu, mw := sequentialSum(u)/float64(len(u)), sequentialSum(w)/float64(len(w))
	cross, first, second := 0.0, 0.0, 0.0
	for f, value := range u {
		du, dw := value-mu, w[f]-mw
		cross += du * dw
		first += du * du
		second += dw * dw
	}
	return 1 - cross/math.Sqrt(first*second)
}
func distanceMatrix(vectors [][]float64, kind string) [][]float64 {
	count := len(vectors)
	matrix := floatMatrix(count, count)
	for i := 0; i < count; i++ {
		for j := i + 1; j < count; j++ {
			value := distance(vectors[i], vectors[j], kind)
			matrix[i][j], matrix[j][i] = value, value
		}
	}
	return matrix
}
