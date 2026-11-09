package main

import (
	"container/heap"
	"slices"
)

func applicable(a *GroundAction, s State) bool { return s.Contains(a.Pre) && !s.Intersects(a.Neg) }
func apply(a *GroundAction, s State) State     { return s.Without(a.Del).Union(a.Add) }
func goal(g *GroundProblem, s State) bool      { return s.Contains(g.Goal) }

type SearchSettings struct{ Algorithm, Heuristic string }

func (s SearchSettings) Tag() string { return s.Algorithm + " " + s.Heuristic }

type SearchResult struct {
	Status              string
	Plan                []int
	Expanded, Generated int
}
type SearchNode struct {
	State              State
	G, D, H, F, Serial int
	Parent             *SearchNode
	Action             int
}
type SearchHeap []*SearchNode

func (h SearchHeap) Len() int { return len(h) }
func (h SearchHeap) Less(i, j int) bool {
	a, b := h[i], h[j]
	if a.F != b.F {
		return a.F < b.F
	}
	if a.H != b.H {
		return a.H < b.H
	}
	return a.Serial < b.Serial
}
func (h SearchHeap) Swap(i, j int) { h[i], h[j] = h[j], h[i] }
func (h *SearchHeap) Push(v any)   { *h = append(*h, v.(*SearchNode)) }
func (h *SearchHeap) Pop() any {
	a := *h
	v := a[len(a)-1]
	*h = a[:len(a)-1]
	return v
}
func bestFirst(g *GroundProblem, start State, settings SearchSettings, budget, weight int) *SearchResult {
	r := &SearchResult{}
	initialH := g.Heuristics(start).Value(settings.Heuristic)
	if initialH == infinity {
		r.Status = "dead end"
		return r
	}
	fValue := func(cost, depth, h int) int {
		switch settings.Algorithm {
		case "bfs":
			return depth
		case "ucs":
			return cost
		case "gbfs":
			return h
		case "astar":
			return cost + h
		case "wastar":
			return cost + weight*h
		}
		panic("unknown algorithm")
	}
	open := &SearchHeap{}
	serial := 0
	heap.Push(open, &SearchNode{State: start, H: initialH, F: fValue(0, 0, initialH), Action: -1})
	table := map[State]int{start: 0}
	costBased := settings.Algorithm == "ucs" || settings.Algorithm == "astar" || settings.Algorithm == "wastar"
	for open.Len() > 0 {
		node := heap.Pop(open).(*SearchNode)
		if costBased && node.G > table[node.State] {
			continue
		}
		if goal(g, node.State) {
			r.Status = "solved"
			for n := node; n.Parent != nil; n = n.Parent {
				r.Plan = append(r.Plan, n.Action)
			}
			slices.Reverse(r.Plan)
			return r
		}
		if r.Expanded == budget {
			r.Status = "budget"
			return r
		}
		r.Expanded++
		for i, a := range g.Actions {
			if !applicable(a, node.State) {
				continue
			}
			r.Generated++
			next := apply(a, node.State)
			cost := node.G + a.Cost
			previous, seen := table[next]
			if seen && (!costBased || previous <= cost) {
				continue
			}
			table[next] = cost
			h := g.Heuristics(next).Value(settings.Heuristic)
			if h == infinity {
				continue
			}
			serial++
			heap.Push(open, &SearchNode{State: next, G: cost, D: node.D + 1, H: h, F: fValue(cost, node.D+1, h), Serial: serial, Parent: node, Action: i})
		}
	}
	r.Status = "exhausted"
	return r
}

type LocalNode struct {
	State State
	Plan  []int
}

func enforcedHillClimbing(g *GroundProblem, start State, settings SearchSettings, budget int) *SearchResult {
	r := &SearchResult{}
	current := start
	hc := g.Heuristics(current).Value(settings.Heuristic)
	if hc == infinity {
		r.Status = "dead end"
		return r
	}
	for {
		if goal(g, current) {
			r.Status = "solved"
			return r
		}
		queue := []LocalNode{{State: current}}
		visited := map[State]bool{current: true}
		improved := false
		for head := 0; head < len(queue) && !improved; head++ {
			node := queue[head]
			if r.Expanded == budget {
				r.Status = "budget"
				return r
			}
			r.Expanded++
			for _, i := range g.Heuristics(node.State).Helpful {
				r.Generated++
				next := apply(g.Actions[i], node.State)
				if visited[next] {
					continue
				}
				visited[next] = true
				h := g.Heuristics(next).Value(settings.Heuristic)
				if h == infinity {
					continue
				}
				path := append(slices.Clone(node.Plan), i)
				if h < hc {
					r.Plan = append(r.Plan, path...)
					current = next
					hc = h
					improved = true
					break
				}
				queue = append(queue, LocalNode{next, path})
			}
		}
		if !improved {
			r.Status = "stuck"
			return r
		}
	}
}
func search(g *GroundProblem, start State, settings SearchSettings, budget, weight int) *SearchResult {
	if settings.Algorithm == "ehc" {
		return enforcedHillClimbing(g, start, settings, budget)
	}
	return bestFirst(g, start, settings, budget, weight)
}
