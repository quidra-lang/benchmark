package main

import "sort"

func positions(orders [][]int, count int) []int {
	out := make([]int, count)
	for _, row := range orders {
		for i, v := range row {
			out[v] = i
		}
	}
	return out
}
func gapCrossings(segments []Segment, indices []int, pos []int, width int) int {
	pairs := make([][2]int, len(indices))
	for i, index := range indices {
		s := segments[index]
		pairs[i] = [2]int{pos[s.Upper], pos[s.Lower]}
	}
	sort.Slice(pairs, func(i, j int) bool {
		a, b := pairs[i], pairs[j]
		if a[0] != b[0] {
			return a[0] < b[0]
		}
		return a[1] < b[1]
	})
	capacity := 1
	for capacity < width {
		capacity *= 2
	}
	tree := make([]int, 2*capacity-1)
	crossings := 0
	for _, pair := range pairs {
		k := pair[1] + capacity - 1
		tree[k]++
		for k > 0 {
			if k%2 == 1 {
				crossings += tree[k+1]
			}
			k = (k - 1) / 2
			tree[k]++
		}
	}
	return crossings
}
func totalCrossings(g *Layout, orders [][]int) int {
	pos := positions(orders, len(g.Vertices))
	sum := 0
	for i, indices := range g.Gaps {
		sum += gapCrossings(g.Segments, indices, pos, len(orders[i+1]))
	}
	return sum
}
func bruteCrossings(g *Layout, orders [][]int, countEdges bool) int {
	pos := positions(orders, len(g.Vertices))
	sum := 0
	for _, indices := range g.Gaps {
		for i, index := range indices {
			a := g.Segments[index]
			for _, other := range indices[i+1:] {
				b := g.Segments[other]
				if (pos[a.Upper]-pos[b.Upper])*(pos[a.Lower]-pos[b.Lower]) < 0 {
					sum++
					if countEdges {
						g.Edges[a.Edge].Crossings++
						g.Edges[b.Edge].Crossings++
					}
				}
			}
		}
	}
	return sum
}
func adjacentCost(g *Layout, v, w int, pos []int) int {
	count := 0
	for side := 0; side < 2; side++ {
		a, b := g.Vertices[v].Upper, g.Vertices[w].Upper
		if side == 1 {
			a, b = g.Vertices[v].Lower, g.Vertices[w].Lower
		}
		for _, u := range a {
			for _, q := range b {
				if pos[u] > pos[q] {
					count++
				}
			}
		}
	}
	return count
}
