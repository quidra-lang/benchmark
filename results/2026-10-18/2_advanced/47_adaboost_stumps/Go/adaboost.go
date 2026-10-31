package main

import "math"

type Round struct {
	Stump          Stump
	Weights        []float64
	Error, Alpha   float64
	Polarity       int
	Z, Bound, Loss float64
}
type Model struct {
	Rounds []Round
	Stop   string
	Cuts   [][]float64
}

func labelsOf(rows []Row) []int {
	labels := make([]int, len(rows))
	for i, r := range rows {
		labels[i] = r.Label
	}
	return labels
}
func uniformWeights(n int) []float64 {
	weights := make([]float64, n)
	for i := range weights {
		weights[i] = 1 / float64(n)
	}
	return weights
}
func trainDiscrete(rows []Row, maxRounds int, initial []float64, shrinkage float64, space *SearchSpace) Model {
	if space == nil {
		space = newSearchSpace(rows)
	}
	labels := labelsOf(rows)
	weights := uniformWeights(len(rows))
	if initial != nil {
		weights = append([]float64{}, initial...)
	}
	model := Model{Stop: "completed"}
	bound := 1.0
	for t := 0; t < maxRounds; t++ {
		c := discreteSearch(space, labels, weights)
		e := c.Error
		if e >= 0.5 {
			model.Stop = "weak"
			break
		}
		alpha := 1.0
		if e > 1e-10 {
			alpha = shrinkage * (0.5 * math.Log((1-e)/e))
		}
		stump := Stump{c.Feature, []float64{c.Threshold}, []float64{-float64(c.Polarity) * alpha, float64(c.Polarity) * alpha}}
		before := append([]float64{}, weights...)
		updated := make([]float64, len(weights))
		for i, row := range rows {
			decision := -c.Polarity
			if row.Values[c.Feature] > c.Threshold {
				decision = c.Polarity
			}
			factor := math.Exp(alpha)
			if decision == row.Label {
				factor = math.Exp(-alpha)
			}
			if weights[i] != 0 {
				updated[i] = weights[i] * factor
			}
		}
		z := sum(updated)
		for i, w := range updated {
			weights[i] = w / z
		}
		bound *= z
		model.Rounds = append(model.Rounds, Round{Stump: stump, Weights: before, Error: e, Alpha: alpha, Polarity: c.Polarity, Z: z, Bound: bound})
		if e <= 1e-10 {
			model.Stop = "perfect"
			break
		}
	}
	return model
}
func trainSamme(rows []Row, maxRounds, classes int) Model {
	space := newSearchSpace(rows)
	labels := labelsOf(rows)
	weights := uniformWeights(len(rows))
	model := Model{Stop: "completed"}
	for t := 0; t < maxRounds; t++ {
		stump, e := multiclassSearch(space, labels, weights, classes)
		if e >= float64(classes-1)/float64(classes) {
			model.Stop = "weak"
			break
		}
		alpha := 1.0
		if e > 1e-10 {
			alpha = math.Log((1-e)/e) + math.Log(float64(classes-1))
		}
		updated := append([]float64{}, weights...)
		for i, row := range rows {
			if int(stump.output(row.Values)) != row.Label {
				updated[i] *= math.Exp(alpha)
			}
		}
		z := sum(updated)
		for i, w := range updated {
			weights[i] = w / z
		}
		model.Rounds = append(model.Rounds, Round{Stump: stump, Error: e, Alpha: alpha})
		if e <= 1e-10 {
			model.Stop = "perfect"
			break
		}
	}
	return model
}
