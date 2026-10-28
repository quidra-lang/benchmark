package main

type TrainingPair struct{ Observations, Path []int }

func smoothedModel(template *Model, name string, initial []float64, transition, emission [][]float64, alpha float64) *Model {
	for i := range initial {
		initial[i] += alpha
	}
	for _, row := range transition {
		for i := range row {
			row[i] += alpha
		}
	}
	for _, row := range emission {
		for i := range row {
			row[i] += alpha
		}
	}
	return newModel(name, template, initial, transition, emission)
}
func baumWelchStep(model *Model, sequences [][]int, pseudocount float64) *Model {
	k := len(model.States)
	initial := make([]float64, k)
	transition, emission := matrix(k, k), matrix(k, len(model.Symbols))
	for _, observations := range sequences {
		result := forwardBackward(model, observations)
		for i := 0; i < k; i++ {
			initial[i] += result.Posterior[0][i]
		}
		for t, observation := range observations {
			for i := 0; i < k; i++ {
				if observation >= 0 {
					emission[i][observation] += result.Posterior[t][i]
				}
				if t+1 < len(observations) {
					for j := 0; j < k; j++ {
						transition[i][j] += posteriorTransition(model, result, t, i, j)
					}
				}
			}
		}
	}
	return smoothedModel(model, "BAUM_WELCH", initial, transition, emission, pseudocount)
}
func estimateByCounting(template *Model, pairs []TrainingPair, alpha float64, name string) *Model {
	k, m := len(template.States), len(template.Symbols)
	initialCounts := make([]int, k)
	transitionCounts, emissionCounts := intMatrix(k, k), intMatrix(k, m)
	for _, pair := range pairs {
		initialCounts[pair.Path[0]]++
		for t, state := range pair.Path {
			if pair.Observations[t] >= 0 {
				emissionCounts[state][pair.Observations[t]]++
			}
			if t+1 < len(pair.Path) {
				transitionCounts[state][pair.Path[t+1]]++
			}
		}
	}
	initial := make([]float64, k)
	transition, emission := matrix(k, k), matrix(k, m)
	for i := 0; i < k; i++ {
		initial[i] = float64(initialCounts[i])
		for j := 0; j < k; j++ {
			transition[i][j] = float64(transitionCounts[i][j])
		}
		for c := 0; c < m; c++ {
			emission[i][c] = float64(emissionCounts[i][c])
		}
	}
	return smoothedModel(template, name, initial, transition, emission, alpha)
}
func totalLoglik(model *Model, sequences [][]int) float64 {
	total := 0.0
	for _, observations := range sequences {
		total += scaledForward(model, observations).Loglik
	}
	return total
}
