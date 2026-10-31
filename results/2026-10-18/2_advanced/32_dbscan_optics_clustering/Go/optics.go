package main

import "sort"

const INF int64 = 1 << 62

func coreDistances(points []Point, neighborhoods [][]int, minPts int) []int64 {
	core := make([]int64, len(points))
	for i, neighbors := range neighborhoods {
		core[i] = INF
		if len(neighbors) >= minPts {
			d := []int64{}
			for _, j := range neighbors {
				d = append(d, squaredDistance(points[i], points[j]))
			}
			sort.Slice(d, func(i, j int) bool { return d[i] < d[j] })
			core[i] = d[minPts-1]
		}
	}
	return core
}
func opticsOrdering(points []Point, neighborhoods [][]int, core []int64) ([]int, []int64, []int) {
	n := len(points)
	reach, pred, processed := make([]int64, n), make([]int, n), make([]bool, n)
	for i := range reach {
		reach[i], pred[i] = INF, -1
	}
	order := []int{}
	for start := range points {
		if processed[start] {
			continue
		}
		seeds := map[int]bool{start: true}
		for len(seeds) > 0 {
			current := -1
			for p := range seeds {
				if current < 0 || reach[p] < reach[current] || reach[p] == reach[current] && points[p].ID < points[current].ID {
					current = p
				}
			}
			delete(seeds, current)
			processed[current] = true
			order = append(order, current)
			if core[current] == INF {
				continue
			}
			for _, q := range neighborhoods[current] {
				if processed[q] {
					continue
				}
				r := max(core[current], squaredDistance(points[current], points[q]))
				if r < reach[q] {
					reach[q], pred[q] = r, current
					seeds[q] = true
				}
			}
		}
	}
	return order, reach, pred
}
