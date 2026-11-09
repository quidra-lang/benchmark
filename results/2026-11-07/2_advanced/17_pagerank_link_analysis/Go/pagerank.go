package main

import "math"

type WeightedEdge struct{ source, weight int }
type PageRankResult struct {
	values, changes []float64
	convergedAt     int
}

func powerIteration(inEdges [][]WeightedEdge, teleport []int, damping float64, iterations int, tolerance float64) *PageRankResult {
	count := len(inEdges)
	outWeight := make([]int, count)
	for _, edges := range inEdges {
		for _, edge := range edges {
			outWeight[edge.source] += edge.weight
		}
	}
	inTeleport := make([]bool, count)
	for _, node := range teleport {
		inTeleport[node] = true
	}
	values := make([]float64, count)
	for node := range values {
		if inTeleport[node] {
			values[node] = 1 / float64(len(teleport))
		}
	}
	result := &PageRankResult{}
	for step := 1; step <= iterations; step++ {
		mass := 0.0
		for node, weight := range outWeight {
			if weight == 0 {
				mass += values[node]
			}
		}
		base := ((1 - damping) + damping*mass) / float64(len(teleport))
		updated := make([]float64, count)
		change := 0.0
		for node, edges := range inEdges {
			inflow := 0.0
			for _, edge := range edges {
				inflow += values[edge.source] * float64(edge.weight) / float64(outWeight[edge.source])
			}
			updated[node] = damping * inflow
			if inTeleport[node] {
				updated[node] += base
			}
			change += math.Abs(updated[node] - values[node])
		}
		result.changes = append(result.changes, change)
		if result.convergedAt == 0 && change < tolerance {
			result.convergedAt = step
		}
		values = updated
	}
	result.values = values
	return result
}
