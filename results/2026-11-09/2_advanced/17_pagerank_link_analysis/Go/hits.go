package main

import (
	"math"
	"sort"
)

func norm(values []float64, nodes []int) float64 {
	squares := 0.0
	for _, node := range nodes {
		squares += values[node] * values[node]
	}
	return math.Sqrt(squares)
}
func hits(count int, nodes []int, links []Link, iterations int) ([]float64, []float64) {
	sources, targets := make([][]int, count), make([][]int, count)
	ordered := append([]Link(nil), links...)
	sort.Slice(ordered, func(i, j int) bool {
		if ordered[i].source != ordered[j].source {
			return ordered[i].source < ordered[j].source
		}
		return ordered[i].target < ordered[j].target
	})
	for _, link := range ordered {
		sources[link.target] = append(sources[link.target], link.source)
		targets[link.source] = append(targets[link.source], link.target)
	}
	authority, hub := make([]float64, count), make([]float64, count)
	for _, node := range nodes {
		authority[node] = 1
		hub[node] = 1
	}
	for step := 0; step < iterations; step++ {
		incoming, outgoing := make([]float64, count), make([]float64, count)
		for _, node := range nodes {
			for _, source := range sources[node] {
				incoming[node] += hub[source]
			}
		}
		for _, node := range nodes {
			for _, target := range targets[node] {
				outgoing[node] += incoming[target]
			}
		}
		aNorm, hNorm := norm(incoming, nodes), norm(outgoing, nodes)
		for _, node := range nodes {
			authority[node] = incoming[node] / aNorm
			hub[node] = outgoing[node] / hNorm
		}
	}
	return authority, hub
}
