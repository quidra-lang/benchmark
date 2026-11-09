package main

import "math"

func columnMeans(rows [][]float64) []float64 {
	out := make([]float64, len(rows[0]))
	for j := range out {
		s := 0.0
		for _, row := range rows {
			s += row[j]
		}
		out[j] = s / float64(len(rows))
	}
	return out
}
func covarianceMatrix(rows [][]float64, means []float64) [][]float64 {
	p := len(means)
	dev := zeros(len(rows), p)
	for i, row := range rows {
		for j, v := range row {
			dev[i][j] = v - means[j]
		}
	}
	cov := zeros(p, p)
	for j := 0; j < p; j++ {
		for k := j; k < p; k++ {
			s := 0.0
			for _, row := range dev {
				s += row[j] * row[k]
			}
			cov[j][k] = s / float64(len(rows)-1)
			cov[k][j] = cov[j][k]
		}
	}
	return cov
}
func standardDeviations(cov [][]float64) []float64 {
	out := make([]float64, len(cov))
	for j := range out {
		out[j] = math.Sqrt(cov[j][j])
	}
	return out
}
func correlationMatrix(cov [][]float64, sd []float64) [][]float64 {
	out := zeros(len(cov), len(cov))
	for j := range out {
		for k := range out[j] {
			if j == k {
				out[j][k] = 1
			} else {
				out[j][k] = cov[j][k] / (sd[j] * sd[k])
			}
		}
	}
	return out
}
func standardize(values, means, scales []float64) []float64 {
	out := make([]float64, len(values))
	for j, x := range values {
		if !math.IsNaN(x) {
			out[j] = (x - means[j]) / scales[j]
		}
	}
	return out
}
func componentScores(z []float64, vectors [][]float64) []float64 {
	scores := make([]float64, len(vectors))
	for k, v := range vectors {
		scores[k] = dot(z, v)
	}
	return scores
}
func residuals(z, scores []float64, vectors [][]float64, count int) []float64 {
	out := make([]float64, len(z))
	for j, v := range z {
		s := 0.0
		for k := 0; k < count; k++ {
			s += scores[k] * vectors[k][j]
		}
		out[j] = v - s
	}
	return out
}
func hotelling(scores, eigenvalues []float64, count int) float64 {
	s := 0.0
	for k := 0; k < count; k++ {
		s += scores[k] * scores[k] / eigenvalues[k]
	}
	return s
}
