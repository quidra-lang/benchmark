package main

type Conflict struct {
	Time, A, B, U, V int
	Edge             bool
}
type Constraint struct {
	Agent, Time, U, V int
	Edge              bool
}

func position(path []int, t int) int { return path[min(t, len(path)-1)] }
func planCosts(paths [][]int) (int, int) {
	soc, makespan := 0, 0
	for _, p := range paths {
		soc += len(p) - 1
		makespan = max(makespan, len(p)-1)
	}
	return soc, makespan
}
func conflicts(paths [][]int) []Conflict {
	_, last := planCosts(paths)
	out := []Conflict{}
	for t := 1; t <= last; t++ {
		for a := 0; a < len(paths); a++ {
			for b := a + 1; b < len(paths); b++ {
				u, v := position(paths[a], t-1), position(paths[a], t)
				bu, bv := position(paths[b], t-1), position(paths[b], t)
				if v == bv {
					out = append(out, Conflict{t, a, b, v, v, false})
				} else if v == bu && bv == u {
					out = append(out, Conflict{t, a, b, u, v, true})
				}
			}
		}
	}
	return out
}
func (c Conflict) Constraint(agent int) Constraint {
	u, v := c.U, c.V
	if c.Edge && agent == c.B {
		u, v = v, u
	}
	return Constraint{agent, c.Time, u, v, c.Edge}
}

type Node struct {
	Number, Parent, Depth, Cost int
	Paths                       [][]int
	Constraints                 [][]Constraint
	Conflicts                   []Conflict
}

func nodeLess(a, b *Node) bool {
	if a.Cost != b.Cost {
		return a.Cost < b.Cost
	}
	if len(a.Conflicts) != len(b.Conflicts) {
		return len(a.Conflicts) < len(b.Conflicts)
	}
	return a.Number < b.Number
}

type NodeHeap []*Node

func (h NodeHeap) Len() int           { return len(h) }
func (h NodeHeap) Less(i, j int) bool { return nodeLess(h[i], h[j]) }
func (h NodeHeap) Swap(i, j int)      { h[i], h[j] = h[j], h[i] }
func (h *NodeHeap) Push(v any)        { *h = append(*h, v.(*Node)) }
func (h *NodeHeap) Pop() any {
	a := *h
	v := a[len(a)-1]
	*h = a[:len(a)-1]
	return v
}
