package main

import "math"

func shiftedScores(w [][]float64, v []float64) []float64 {
	scores := make([]float64, len(w))
	top := math.Inf(-1)
	for k, row := range w {
		scores[k] = score(row, v)
		top = math.Max(top, scores[k])
	}
	for k := range scores {
		scores[k] -= top
	}
	return scores
}
func softmaxProbabilities(w [][]float64, v []float64) []float64 {
	values := shiftedScores(w, v)
	total := 0.0
	for _, u := range values {
		total += math.Exp(u)
	}
	for k := range values {
		values[k] = math.Exp(values[k]) / total
	}
	return values
}
func predictedClass(values []float64) int {
	best := 0
	for k, p := range values {
		if p > values[best] {
			best = k
		}
	}
	return best
}
func softmaxLoss(w [][]float64, v []float64, label int) float64 {
	values := shiftedScores(w, v)
	total := 0.0
	for _, u := range values {
		total += math.Exp(u)
	}
	return math.Log(total) - values[label]
}
func softmaxAverage(w, x [][]float64, y []int) float64 {
	total := 0.0
	for i, v := range x {
		total += softmaxLoss(w, v, y[i])
	}
	return total / float64(len(x))
}
func softmaxObjective(w, x [][]float64, y []int, lambda float64) float64 {
	total := 0.0
	for _, row := range w {
		for _, value := range row[1:] {
			total += value * value
		}
	}
	return softmaxAverage(w, x, y) + lambda*total/2
}
func softmaxGradient(w, x [][]float64, y []int, lambda float64) [][]float64 {
	g := matrix(len(w), len(w[0]))
	for i, v := range x {
		probs := softmaxProbabilities(w, v)
		for k, p := range probs {
			error := p
			if y[i] == k {
				error -= 1
			}
			for j := range g[k] {
				g[k][j] += error * v[j]
			}
		}
	}
	for k := range g {
		for j := range g[k] {
			g[k][j] /= float64(len(x))
			if j > 0 {
				g[k][j] += lambda * w[k][j]
			}
		}
	}
	return g
}

type SoftCheckpoint struct {
	Iteration int
	Weights   [][]float64
}

func softmaxTrain(x [][]float64, y []int, classes int, lambda, rate float64, iterations int) []SoftCheckpoint {
	w := matrix(classes, len(x[0]))
	checkpoints := []SoftCheckpoint{{0, w}}
	for t := 1; t <= iterations; t++ {
		g := softmaxGradient(w, x, y, lambda)
		next := [][]float64{}
		for k := range w {
			next = append(next, move(w[k], g[k], rate))
		}
		w = next
		if t%100 == 0 {
			checkpoints = append(checkpoints, SoftCheckpoint{t, w})
		}
	}
	return checkpoints
}
