package main

import "math"

type Family struct {
	Counts     [][]int
	Learned    [][]float64
	Parameters int
}

func parentCombination(parents, a []int, n Network) int {
	r := 0
	for _, p := range parents {
		r = r*len(n.Variables[p].States) + a[p]
	}
	return r
}
func learn(v int, parents []int, n Network) Family {
	rows, k := assignmentCount(parents, n), len(n.Variables[v].States)
	f := Family{Counts: make([][]int,
		rows), Learned: make([][]float64, rows), Parameters: (k - 1) * rows}
	for r := 0; r < rows; r++ {
		f.Counts[r] = make([]int,
			k)
		f.Learned[r] = make([]float64, k)
	}
	for _, a := range n.Samples {
		f.Counts[parentCombination(parents,
			a, n)][a[v]]++
	}
	for r := 0; r < rows; r++ {
		total := 0.0
		for s := 0; s < k; s++ {
			total += float64(f.Counts[r][s]) + n.Settings.Alpha
		}
		for s := 0; s < k; s++ {
			f.Learned[r][s] = (float64(f.Counts[r][s]) + n.Settings.Alpha) / total
		}
	}
	return f
}
func logLikelihood(counts [][]int, theta [][]float64) float64 {
	ll := 0.0
	for r, row := range counts {
		for s, count := range row {
			if count > 0 {
				ll += float64(count) * math.Log(theta[r][s])
			}
		}
	}
	return ll
}
func familyScore(v int, parents []int, n Network) float64 {
	f := learn(v, parents, n)
	return logLikelihood(f.Counts,
		f.Learned) - float64(f.Parameters)*math.Log(float64(len(n.Samples)))/2
}
