package main

import "math"

func updateWeights(rows []Row, weights []float64, stump Stump) []float64 {
	out := make([]float64, len(weights))
	for i, row := range rows {
		out[i] = weights[i] * math.Exp(-float64(row.Label)*stump.output(row.Values))
	}
	z := sum(out)
	for i := range out {
		out[i] /= z
	}
	return out
}
func trainReal(rows []Row, maxRounds, bins int, smoothing, convergence float64) Model {
	space := newSearchSpace(rows)
	cuts, assignments := realGeometry(space, bins)
	labels := labelsOf(rows)
	weights := uniformWeights(len(rows))
	model := Model{Stop: "completed", Cuts: cuts}
	bound := 1.0
	for t := 0; t < maxRounds; t++ {
		c := realSearch(assignments, labels, weights, bins)
		z := c.Error
		if z >= 1-convergence {
			model.Stop = "converged"
			break
		}
		values := make([]float64, bins)
		for b, p := range c.Positive {
			values[b] = 0.5 * math.Log((p+smoothing)/(c.Negative[b]+smoothing))
		}
		stump := Stump{c.Feature, cuts[c.Feature], values}
		bound *= z
		model.Rounds = append(model.Rounds, Round{Stump: stump, Weights: append([]float64{}, weights...), Z: z, Bound: bound})
		weights = updateWeights(rows, weights, stump)
	}
	return model
}
func trainGentle(rows []Row, maxRounds int) Model {
	space := newSearchSpace(rows)
	targets := make([]float64, len(rows))
	for i, row := range rows {
		targets[i] = float64(row.Label)
	}
	weights := uniformWeights(len(rows))
	model := Model{Stop: "completed"}
	for t := 0; t < maxRounds; t++ {
		stump, e := regressionSearch(space, targets, weights)
		model.Rounds = append(model.Rounds, Round{Stump: stump, Weights: append([]float64{}, weights...), Error: e})
		weights = updateWeights(rows, weights, stump)
	}
	return model
}
func trainLogit(rows []Row, maxRounds int, clip float64) Model {
	space := newSearchSpace(rows)
	scores := make([]float64, len(rows))
	probabilities := make([]float64, len(rows))
	for i := range probabilities {
		probabilities[i] = 0.5
	}
	model := Model{Stop: "completed"}
	for t := 0; t < maxRounds; t++ {
		q, responses := make([]float64, len(rows)), make([]float64, len(rows))
		for i, row := range rows {
			p := probabilities[i]
			target := 0.0
			if row.Label == 1 {
				target = 1
			}
			q[i] = p * (1 - p)
			response := (target - p) / q[i]
			if response > clip {
				response = clip
			} else if response < -clip {
				response = -clip
			}
			responses[i] = response
		}
		z := sum(q)
		weights := make([]float64, len(q))
		for i, w := range q {
			weights[i] = w / z
		}
		fitted, e := regressionSearch(space, responses, weights)
		stump := Stump{fitted.Feature, fitted.Thresholds, []float64{fitted.Values[0] / 2, fitted.Values[1] / 2}}
		loss := 0.0
		for i, row := range rows {
			scores[i] += stump.output(row.Values)
			probabilities[i] = 1 / (1 + math.Exp(-2*scores[i]))
			loss += math.Log(1 + math.Exp(-2*float64(row.Label)*scores[i]))
		}
		loss /= float64(len(rows))
		model.Rounds = append(model.Rounds, Round{Stump: stump, Weights: weights, Error: e, Loss: loss})
	}
	return model
}
