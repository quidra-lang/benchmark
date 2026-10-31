package main

import (
	"slices"
	"sort"
)

func acyclic(n int, edges []*Edge) []int {
	remaining := make([]bool, n)
	for i := range remaining {
		remaining[i] = true
	}
	head, tail := []int{}, []int{}
	for count := 0; count < n; count++ {
		in, out := make([]int, n), make([]int, n)
		for _, e := range edges {
			if remaining[e.From] && remaining[e.To] {
				out[e.From]++
				in[e.To]++
			}
		}
		chosen := -1
		toTail := false
		for v := 0; v < n; v++ {
			if remaining[v] && out[v] == 0 {
				chosen = v
				toTail = true
				break
			}
		}
		if chosen < 0 {
			for v := 0; v < n; v++ {
				if remaining[v] && in[v] == 0 {
					chosen = v
					break
				}
			}
		}
		if chosen < 0 {
			for v := 0; v < n; v++ {
				if remaining[v] && (chosen < 0 || out[v]-in[v] > out[chosen]-in[chosen]) {
					chosen = v
				}
			}
		}
		remaining[chosen] = false
		if toTail {
			tail = append([]int{chosen}, tail...)
		} else {
			head = append(head, chosen)
		}
	}
	return append(head, tail...)
}

type Promotion struct{ Round, Node, Diff int }
type LayeringResult struct {
	Height, Labels        []int
	DummiesBefore, Rounds int
	Promotions            []Promotion
}

func assignLayers(n int, predecessors, successors [][]int, settings Settings) *LayeringResult {
	r := &LayeringResult{Height: make([]int, n), Labels: make([]int, n)}
	if settings.Layering == "longest" {
		known := make([]bool, n)
		var height func(int) int
		height = func(v int) int {
			if known[v] {
				return r.Height[v]
			}
			for _, w := range successors[v] {
				r.Height[v] = max(r.Height[v], height(w)+1)
			}
			known[v] = true
			return r.Height[v]
		}
		for v := 0; v < n; v++ {
			height(v)
		}
	} else {
		for label := 1; label <= n; label++ {
			chosen := -1
			var best []int
			for v := 0; v < n; v++ {
				if r.Labels[v] != 0 {
					continue
				}
				ready := true
				key := []int{}
				for _, p := range predecessors[v] {
					if r.Labels[p] == 0 {
						ready = false
						break
					}
					key = append(key, r.Labels[p])
				}
				if !ready {
					continue
				}
				sort.Sort(sort.Reverse(sort.IntSlice(key)))
				if chosen < 0 || slices.Compare(key, best) < 0 {
					chosen = v
					best = key
				}
			}
			r.Labels[chosen] = label
		}
		for i := range r.Height {
			r.Height[i] = -1
		}
		current, count := 0, 0
		for k := 0; k < n; k++ {
			chosen := -1
			for v := 0; v < n; v++ {
				if r.Height[v] >= 0 {
					continue
				}
				ready := true
				for _, s := range successors[v] {
					if r.Height[s] < 0 {
						ready = false
						break
					}
				}
				if ready && (chosen < 0 || r.Labels[v] > r.Labels[chosen]) {
					chosen = v
				}
			}
			next := count == settings.Width
			for _, s := range successors[chosen] {
				if r.Height[s] == current {
					next = true
				}
			}
			if next {
				current++
				count = 0
			}
			r.Height[chosen] = current
			count++
		}
	}
	for v := 0; v < n; v++ {
		for _, w := range successors[v] {
			r.DummiesBefore += r.Height[v] - r.Height[w] - 1
		}
	}
	if settings.Promotion == "on" {
		var promote func(int) int
		promote = func(v int) int {
			diff := 0
			for _, u := range predecessors[v] {
				if r.Height[u] == r.Height[v]+1 {
					diff += promote(u)
				}
			}
			r.Height[v]++
			return diff + len(successors[v]) - len(predecessors[v])
		}
		for {
			r.Rounds++
			accepted := 0
			for v := 0; v < n; v++ {
				if len(predecessors[v]) == 0 {
					continue
				}
				saved := slices.Clone(r.Height)
				diff := promote(v)
				if diff < 0 {
					accepted++
					r.Promotions = append(r.Promotions, Promotion{r.Rounds, v, diff})
				} else {
					r.Height = saved
				}
			}
			if accepted == 0 {
				break
			}
		}
	}
	return r
}
