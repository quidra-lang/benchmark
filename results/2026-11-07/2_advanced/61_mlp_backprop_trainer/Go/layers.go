package main

import "math"

func activation(kind string, z float64) float64 {
	switch kind {
	case "TANH":
		return math.Tanh(z)
	case "SIGMOID":
		return 1 / (1 + math.Exp(-z))
	default:
		if z > 0 {
			return z
		}
		return 0
	}
}
func derivative(kind string, z, a float64) float64 {
	switch kind {
	case "TANH":
		return 1 - a*a
	case "SIGMOID":
		return a * (1 - a)
	default:
		if z > 0 {
			return 1
		}
		return 0
	}
}
func preactivations(layer Layer, theta, input []float64) []float64 {
	z := make([]float64, layer.Units)
	for j := range z {
		s := 0.0
		for i, v := range input {
			s += theta[layer.Weights+j*layer.Inputs+i] * v
		}
		z[j] = s + theta[layer.Biases+j]
	}
	return z
}
func output(kind string, z []float64, label int) ([]float64, float64, []float64) {
	k := len(z)
	scores, delta := make([]float64, k), make([]float64, k)
	loss := 0.0
	if kind == "SOFTMAX" {
		maximum := z[prediction(z)]
		sum := 0.0
		for j, v := range z {
			scores[j] = math.Exp(v - maximum)
			sum += scores[j]
		}
		for j := range scores {
			scores[j] /= sum
			delta[j] = scores[j]
			if j == label {
				delta[j]--
			}
		}
		loss = math.Log(sum) - (z[label] - maximum)
	} else {
		for j, v := range z {
			scores[j] = 1 / (1 + math.Exp(-v))
			target := 0.0
			if j == label {
				target = 1
			}
			difference := scores[j] - target
			loss += difference * difference
			delta[j] = 2 * difference * scores[j] * (1 - scores[j]) / float64(k)
		}
		loss /= float64(k)
	}
	return scores, loss, delta
}
func propagate(next Layer, theta, nextDelta []float64, unit int) float64 {
	s := 0.0
	for k, v := range nextDelta {
		s += theta[next.Weights+k*next.Inputs+unit] * v
	}
	return s
}
