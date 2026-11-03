package main

import "math"

type Merge struct {
	A, B   int
	Height float64
	Size   int
}
type Edge struct {
	Parent, Child int
	Weight        float64
}

func lanceWilliams(method string, sizeA, sizeB, sizeK int) (float64, float64, float64, float64) {
	switch method {
	case "single":
		return .5, .5, 0, -.5
	case "complete":
		return .5, .5, 0, .5
	case "average":
		return float64(sizeA) / float64(sizeA+sizeB), float64(sizeB) / float64(sizeA+sizeB), 0, 0
	case "weighted":
		return .5, .5, 0, 0
	case "centroid":
		merged := sizeA + sizeB
		return float64(sizeA) / float64(merged), float64(sizeB) / float64(merged), -float64(sizeA*sizeB) / float64(merged*merged), 0
	case "median":
		return .5, .5, -.25, 0
	}
	total := sizeA + sizeB + sizeK
	return float64(sizeA+sizeK) / float64(total), float64(sizeB+sizeK) / float64(total), -float64(sizeK) / float64(total), 0
}
func agglomerate(delta [][]float64, method string) []Merge {
	count := len(delta)
	squared := method == "centroid" || method == "median" || method == "ward"
	capacity := 2*count - 1
	values := floatMatrix(capacity, capacity)
	sizes := make([]int, capacity)
	active := make([]int, count)
	for u := 0; u < count; u++ {
		sizes[u] = 1
		active[u] = u
		for w := 0; w < count; w++ {
			value := delta[u][w]
			if squared {
				value *= value
			}
			values[u][w] = value
		}
	}
	merges := []Merge{}
	for step := 0; step < count-1; step++ {
		a, b := active[0], active[1]
		best := values[a][b]
		for position, u := range active {
			for _, w := range active[position+1:] {
				if values[u][w] < best {
					a, b, best = u, w, values[u][w]
				}
			}
		}
		node := count + step
		sizes[node] = sizes[a] + sizes[b]
		height := best
		if squared {
			height = math.Sqrt(height)
		}
		merges = append(merges, Merge{a, b, height, sizes[node]})
		for _, k := range active {
			if k == a || k == b {
				continue
			}
			aa, ab, beta, gamma := lanceWilliams(method, sizes[a], sizes[b], sizes[k])
			value := aa*values[a][k] + ab*values[b][k] + beta*values[a][b] + gamma*math.Abs(values[a][k]-values[b][k])
			values[node][k], values[k][node] = value, value
		}
		remaining := []int{}
		for _, id := range active {
			if id != a && id != b {
				remaining = append(remaining, id)
			}
		}
		active = append(remaining, node)
	}
	return merges
}
func minimumSpanningTree(delta [][]float64) []Edge {
	count := len(delta)
	inTree := make([]bool, count)
	inTree[0] = true
	key := append([]float64(nil), delta[0]...)
	parent := make([]int, count)
	edges := []Edge{}
	for step := 0; step < count-1; step++ {
		chosen := -1
		for u := 0; u < count; u++ {
			if !inTree[u] && (chosen < 0 || key[u] < key[chosen]) {
				chosen = u
			}
		}
		inTree[chosen] = true
		edges = append(edges, Edge{parent[chosen], chosen, key[chosen]})
		for u := 0; u < count; u++ {
			if !inTree[u] && delta[chosen][u] < key[u] {
				key[u] = delta[chosen][u]
				parent[u] = chosen
			}
		}
	}
	return edges
}
