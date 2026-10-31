package main

import (
	"math"
	"sort"
)

type DisjointSets struct {
	Parent, Size []int
	Count        int
}

func newDisjointSets(n int) *DisjointSets {
	out := &DisjointSets{make([]int, n+1), make([]int, n+1), n}
	for i := range out.Parent {
		out.Parent[i] = i
		out.Size[i] = 1
	}
	return out
}
func (s *DisjointSets) find(i int) int {
	for s.Parent[i] != i {
		s.Parent[i] = s.Parent[s.Parent[i]]
		i = s.Parent[i]
	}
	return i
}
func (s *DisjointSets) union(a, b int) bool {
	a, b = s.find(a), s.find(b)
	if a == b {
		return false
	}
	if s.Size[a] < s.Size[b] {
		a, b = b, a
	}
	s.Parent[b] = a
	s.Size[a] += s.Size[b]
	s.Count--
	return true
}
func nearestNeighbors(points []Point, neighbors [][]int) []int {
	nearest := make([]int, len(points))
	for s := 1; s < len(points); s++ {
		best := neighbors[s][0]
		for _, t := range neighbors[s][1:] {
			a, b := d2(points[s], points[t]), d2(points[s], points[best])
			if a < b || a == b && t < best {
				best = t
			}
		}
		nearest[s] = best
	}
	return nearest
}
func nearestComponents(nearest []int) [][]int {
	sets := newDisjointSets(len(nearest) - 1)
	for s := 1; s < len(nearest); s++ {
		sets.union(s, nearest[s])
	}
	groups := map[int][]int{}
	for s := 1; s < len(nearest); s++ {
		root := sets.find(s)
		groups[root] = append(groups[root], s)
	}
	out := [][]int{}
	for _, g := range groups {
		out = append(out, g)
	}
	sort.Slice(out, func(i, j int) bool { return out[i][0] < out[j][0] })
	return out
}
func kruskal(points []Point, edges []Edge) []Edge {
	ordered := append([]Edge{}, edges...)
	sort.Slice(ordered, func(i, j int) bool {
		a, b := d2(points[ordered[i][0]], points[ordered[i][1]]), d2(points[ordered[j][0]], points[ordered[j][1]])
		return a < b || a == b && edgeLess(ordered[i], ordered[j])
	})
	sets := newDisjointSets(len(points) - 1)
	adopted := []Edge{}
	for _, e := range ordered {
		if sets.union(e[0], e[1]) {
			adopted = append(adopted, e)
			if sets.Count == 1 {
				break
			}
		}
	}
	return adopted
}
func isGabriel(points []Point, e Edge, directed map[Edge]int) bool {
	for _, d := range []Edge{e, {e[1], e[0]}} {
		if q, ok := directed[d]; ok && dot(points[q], points[e[0]], points[e[1]]) <= 0 {
			return false
		}
	}
	return true
}
func isRelativeNeighbor(points []Point, e Edge) bool {
	length := d2(points[e[0]], points[e[1]])
	for _, p := range points[1:] {
		if d2(points[e[0]], p) < length && d2(points[e[1]], p) < length {
			return false
		}
	}
	return true
}
func greedyRoute(points []Point, neighbors [][]int, start, target int) ([]int, float64) {
	path := []int{start}
	length := 0.0
	for current := start; current != target; {
		best := neighbors[current][0]
		for _, t := range neighbors[current][1:] {
			a, b := d2(points[t], points[target]), d2(points[best], points[target])
			if a < b || a == b && t < best {
				best = t
			}
		}
		length += math.Sqrt(float64(d2(points[current], points[best])))
		path = append(path, best)
		current = best
	}
	return path, length
}

type ShortestPaths struct {
	Distances []float64
	Previous  []int
}

func dijkstra(points []Point, neighbors [][]int, start int) ShortestPaths {
	n := len(points)
	distances, previous, visited := make([]float64, n), make([]int, n), make([]bool, n)
	for i := range distances {
		distances[i] = math.Inf(1)
	}
	distances[start] = 0
	for step := 1; step < n; step++ {
		site := 0
		for i := 1; i < n; i++ {
			if !visited[i] && (site == 0 || distances[i] < distances[site]) {
				site = i
			}
		}
		if site == 0 {
			break
		}
		visited[site] = true
		for _, other := range neighbors[site] {
			candidate := distances[site] + math.Sqrt(float64(d2(points[site], points[other])))
			if candidate < distances[other] {
				distances[other] = candidate
				previous[other] = site
			}
		}
	}
	return ShortestPaths{distances, previous}
}
