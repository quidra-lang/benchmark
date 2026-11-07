package main

import "math"

func realMatrix(size int) [][]float64 {
	result := make([][]float64, size)
	for i := range result {
		result[i] = make([]float64, size)
	}
	return result
}
func choleskySolve(matrix [][]float64, vector []float64) []float64 {
	size := len(vector)
	lower := realMatrix(size)
	for i := 0; i < size; i++ {
		for j := 0; j <= i; j++ {
			total := 0.0
			for k := 0; k < j; k++ {
				total += lower[i][k] * lower[j][k]
			}
			if j < i {
				lower[i][j] = (matrix[i][j] - total) / lower[j][j]
			} else {
				lower[i][i] = math.Sqrt(matrix[i][i] - total)
			}
		}
	}
	forward := make([]float64, size)
	for i := 0; i < size; i++ {
		total := 0.0
		for k := 0; k < i; k++ {
			total += lower[i][k] * forward[k]
		}
		forward[i] = (vector[i] - total) / lower[i][i]
	}
	solution := make([]float64, size)
	for i := size - 1; i >= 0; i-- {
		total := 0.0
		for k := i + 1; k < size; k++ {
			total += lower[k][i] * solution[k]
		}
		solution[i] = (forward[i] - total) / lower[i][i]
	}
	return solution
}
func gaussianSolve(matrix [][]float64, vector []float64) []float64 {
	size := len(vector)
	for k := 0; k < size; k++ {
		pivot := k
		for row := k + 1; row < size; row++ {
			if math.Abs(matrix[row][k]) > math.Abs(matrix[pivot][k]) {
				pivot = row
			}
		}
		matrix[k], matrix[pivot] = matrix[pivot], matrix[k]
		vector[k], vector[pivot] = vector[pivot], vector[k]
		for i := k + 1; i < size; i++ {
			factor := matrix[i][k] / matrix[k][k]
			for j := k; j < size; j++ {
				matrix[i][j] -= factor * matrix[k][j]
			}
			vector[i] -= factor * vector[k]
		}
	}
	solution := make([]float64, size)
	for i := size - 1; i >= 0; i-- {
		total := 0.0
		for j := i + 1; j < size; j++ {
			total += matrix[i][j] * solution[j]
		}
		solution[i] = (vector[i] - total) / matrix[i][i]
	}
	return solution
}
func colleyRatings(count int, matches []Match) []float64 {
	matrix := realMatrix(count)
	balance := make([]int, count)
	for i := range matrix {
		matrix[i][i] = 2
	}
	for _, match := range matches {
		i, j := match.Home, match.Away
		matrix[i][i]++
		matrix[j][j]++
		matrix[i][j]--
		matrix[j][i]--
		if match.Margin > 0 {
			balance[i]++
			balance[j]--
		} else if match.Margin < 0 {
			balance[i]--
			balance[j]++
		}
	}
	vector := make([]float64, count)
	for i := range vector {
		vector[i] = 1 + float64(balance[i])/2
	}
	return choleskySolve(matrix, vector)
}
func masseyRatings(count int, matches []Match) ([]float64, float64) {
	size := count + 1
	last := count
	matrix := realMatrix(size)
	vector := make([]float64, size)
	for _, match := range matches {
		i, j := match.Home, match.Away
		margin := float64(match.Margin)
		matrix[i][i]++
		matrix[j][j]++
		matrix[i][j]--
		matrix[j][i]--
		matrix[i][last]++
		matrix[last][i]++
		matrix[j][last]--
		matrix[last][j]--
		matrix[last][last]++
		vector[i] += margin
		vector[j] -= margin
		vector[last] += margin
	}
	for k := 0; k < count; k++ {
		matrix[count-1][k] = 1
	}
	matrix[count-1][last] = 0
	vector[count-1] = 0
	solution := gaussianSolve(matrix, vector)
	return solution[:count], solution[last]
}
