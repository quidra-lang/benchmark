package main

import "math"

func maximumIndex(values []float64) int {
	best := 0
	for i := 1; i < len(values); i++ {
		if values[i] > values[best] {
			best = i
		}
	}
	return best
}
func emissionFactors(model *Model, observation int, logarithm bool) []float64 {
	out := make([]float64, len(model.States))
	for i := range out {
		if observation < 0 {
			if !logarithm {
				out[i] = 1
			}
		} else {
			out[i] = model.Emission[i][observation]
			if logarithm {
				out[i] = math.Log(out[i])
			}
		}
	}
	return out
}

type Forward struct {
	Values, Emissions [][]float64
	Scales            []float64
	Loglik            float64
}

func scaledForward(model *Model, observations []int) Forward {
	k := len(model.States)
	out := Forward{}
	for t, observation := range observations {
		factors := emissionFactors(model, observation, false)
		out.Emissions = append(out.Emissions, factors)
		values := make([]float64, k)
		for state := 0; state < k; state++ {
			if t == 0 {
				values[state] = model.Initial[state] * factors[state]
			} else {
				total := 0.0
				for previous := 0; previous < k; previous++ {
					total += out.Values[t-1][previous] * model.Transition[previous][state]
				}
				values[state] = total * factors[state]
			}
		}
		scale := sum(values)
		out.Scales = append(out.Scales, scale)
		for i := range values {
			values[i] /= scale
		}
		out.Values = append(out.Values, values)
		out.Loglik += math.Log(scale)
	}
	return out
}

type ForwardBackward struct {
	Forward             Forward
	Backward, Posterior [][]float64
}

func forwardBackward(model *Model, observations []int) ForwardBackward {
	forward := scaledForward(model, observations)
	k, length := len(model.States), len(observations)
	backward := matrix(length, k)
	for i := 0; i < k; i++ {
		backward[length-1][i] = 1
	}
	for t := length - 2; t >= 0; t-- {
		for i := 0; i < k; i++ {
			total := 0.0
			for j := 0; j < k; j++ {
				total += model.Transition[i][j] * forward.Emissions[t+1][j] * backward[t+1][j]
			}
			backward[t][i] = total / forward.Scales[t+1]
		}
	}
	posterior := matrix(length, k)
	for t := range observations {
		for i := 0; i < k; i++ {
			posterior[t][i] = forward.Values[t][i] * backward[t][i]
		}
	}
	return ForwardBackward{forward, backward, posterior}
}
func posteriorTransition(model *Model, result ForwardBackward, t, i, j int) float64 {
	return result.Forward.Values[t][i] * model.Transition[i][j] * result.Forward.Emissions[t+1][j] * result.Backward[t+1][j] / result.Forward.Scales[t+1]
}
func viterbi(model *Model, observations []int) ([]int, float64) {
	k := len(model.States)
	transition := matrix(k, k)
	for i := 0; i < k; i++ {
		for j := 0; j < k; j++ {
			transition[i][j] = math.Log(model.Transition[i][j])
		}
	}
	factors := emissionFactors(model, observations[0], true)
	scores := make([]float64, k)
	for i := range scores {
		scores[i] = math.Log(model.Initial[i]) + factors[i]
	}
	predecessors := make([][]int, len(observations))
	predecessors[0] = make([]int, k)
	for t := 1; t < len(observations); t++ {
		factors = emissionFactors(model, observations[t], true)
		next := make([]float64, k)
		predecessors[t] = make([]int, k)
		for state := 0; state < k; state++ {
			candidates := make([]float64, k)
			for previous := 0; previous < k; previous++ {
				candidates[previous] = scores[previous] + transition[previous][state]
			}
			previous := maximumIndex(candidates)
			predecessors[t][state] = previous
			next[state] = candidates[previous] + factors[state]
		}
		scores = next
	}
	path := make([]int, len(observations))
	path[len(path)-1] = maximumIndex(scores)
	logprob := scores[path[len(path)-1]]
	for t := len(path) - 1; t > 0; t-- {
		path[t-1] = predecessors[t][path[t]]
	}
	return path, logprob
}

type Decoding struct {
	Viterbi, Posterior []int
	ViterbiLogprob     float64
	Confidence         []float64
	FB                 ForwardBackward
}

func decode(model *Model, observations []int) Decoding {
	fb := forwardBackward(model, observations)
	path, logprob := viterbi(model, observations)
	out := Decoding{Viterbi: path, ViterbiLogprob: logprob, FB: fb}
	for _, row := range fb.Posterior {
		state := maximumIndex(row)
		out.Posterior = append(out.Posterior, state)
		out.Confidence = append(out.Confidence, row[state])
	}
	return out
}
