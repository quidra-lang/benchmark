package main

import (
	"math"
	"sort"
)

type EventSums struct {
	S0     float64
	S1     []float64
	Events int
}
type CoxEvaluation struct {
	Loglik      float64
	Score       []float64
	Information [][]float64
	Predictors  []float64
	Sums        map[int]EventSums
}
type CoxIteration struct {
	Number int
	Loglik float64
	Beta   []float64
}
type CoxModel struct {
	Beta        []float64
	Null, Final CoxEvaluation
	Iterations  []CoxIteration
}

func evaluateCox(subjects []Subject, vectors [][]int, beta []float64) CoxEvaluation {
	p := len(beta)
	r := CoxEvaluation{Score: make([]float64, p), Information: zeros(p), Predictors: make([]float64, len(subjects)), Sums: map[int]EventSums{}}
	risks := make([]float64, len(subjects))
	order := make([]int, len(subjects))
	for j := range subjects {
		for c, b := range beta {
			r.Predictors[j] += b * float64(vectors[j][c])
		}
		risks[j] = math.Exp(r.Predictors[j])
		order[j] = j
	}
	sort.SliceStable(order, func(i, j int) bool { return subjects[order[i]].Time > subjects[order[j]].Time })
	s0 := 0.0
	s1 := make([]float64, p)
	s2 := zeros(p)
	for start := 0; start < len(order); {
		end := start + 1
		time := subjects[order[start]].Time
		for end < len(order) && subjects[order[end]].Time == time {
			end++
		}
		events := []int{}
		for _, j := range order[start:end] {
			risk := risks[j]
			s0 += risk
			for c := 0; c < p; c++ {
				s1[c] += risk * float64(vectors[j][c])
				for d := 0; d < p; d++ {
					s2[c][d] += risk * float64(vectors[j][c]) * float64(vectors[j][d])
				}
			}
			if subjects[j].Event == 1 {
				events = append(events, j)
			}
		}
		if len(events) > 0 {
			e := float64(len(events))
			sumTheta := 0.0
			for _, j := range events {
				sumTheta += r.Predictors[j]
			}
			r.Loglik += sumTheta - e*math.Log(s0)
			for c := 0; c < p; c++ {
				sumX := 0
				for _, j := range events {
					sumX += vectors[j][c]
				}
				r.Score[c] += float64(sumX) - e*s1[c]/s0
				for d := 0; d < p; d++ {
					r.Information[c][d] += e * (s2[c][d]/s0 - (s1[c]/s0)*(s1[d]/s0))
				}
			}
			r.Sums[time] = EventSums{s0, append([]float64{}, s1...), len(events)}
		}
		start = end
	}
	return r
}
func fitCox(subjects []Subject, vectors [][]int) CoxModel {
	beta := make([]float64, len(vectors[0]))
	null := evaluateCox(subjects, vectors, beta)
	current := null
	iterations := []CoxIteration{}
	for s := 1; s <= 25; s++ {
		delta := solve(current.Information, current.Score)
		for c := range beta {
			beta[c] += delta[c]
		}
		iterations = append(iterations, CoxIteration{s, current.Loglik, append([]float64{}, beta...)})
		current = evaluateCox(subjects, vectors, beta)
	}
	return CoxModel{beta, null, current, iterations}
}
