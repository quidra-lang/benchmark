package main

import "sort"

type Crossing struct {
	Point         Point
	First, Second *GHNode
}
type GHNode struct {
	Point                 Point
	Side                  int
	Crossing              *Crossing
	Entering              bool
	Next, Previous, Other *GHNode
}
type Inserted struct {
	Position Rational
	Node     *GHNode
}
type GHGraph struct {
	Rings         [2][]Ring
	Nodes         [2][][]*GHNode
	InitialInside [2][]bool
	Crossings     []*Crossing
	NA, NB        int
}

func graph(first, second []Ring) *GHGraph {
	g := &GHGraph{Rings: [2][]Ring{first, second}}
	var slots [2][][][]Inserted
	for side, sequence := range g.Rings {
		slots[side] = make([][][]Inserted, len(sequence))
		for i, ring := range sequence {
			slots[side][i] = make([][]Inserted, len(ring))
		}
	}
	for i, ring := range first {
		for e, a := range ring {
			b := ring[(e+1)%len(ring)]
			for j, other := range second {
				for f, c := range other {
					d := other[(f+1)%len(other)]
					t, u, p, ok := crossing(a, b, c, d)
					if !ok {
						continue
					}
					record := &Crossing{Point: p}
					record.First = &GHNode{Point: p, Side: 0, Crossing: record}
					record.Second = &GHNode{Point: p, Side: 1, Crossing: record}
					record.First.Other = record.Second
					record.Second.Other = record.First
					slots[0][i][e] = append(slots[0][i][e], Inserted{t, record.First})
					slots[1][j][f] = append(slots[1][j][f], Inserted{u, record.Second})
				}
			}
		}
	}
	for side, sequence := range g.Rings {
		for i, ring := range sequence {
			nodes := []*GHNode{}
			for e, p := range ring {
				nodes = append(nodes, &GHNode{Point: p, Side: side})
				inserted := slots[side][i][e]
				sort.Slice(inserted, func(a, b int) bool { return inserted[a].Position.Cmp(inserted[b].Position) < 0 })
				for _, x := range inserted {
					nodes = append(nodes, x.Node)
				}
			}
			for k, node := range nodes {
				node.Previous = nodes[(k+len(nodes)-1)%len(nodes)]
				node.Next = nodes[(k+1)%len(nodes)]
			}
			state := interior(ring[0], g.Rings[1-side])
			g.InitialInside[side] = append(g.InitialInside[side], state)
			for _, node := range nodes {
				if node.Crossing != nil {
					node.Entering = !state
					state = !state
					if side == 0 {
						g.Crossings = append(g.Crossings, node.Crossing)
					}
				}
			}
			g.Nodes[side] = append(g.Nodes[side], nodes)
		}
	}
	for _, v := range g.InitialInside[0] {
		if v {
			g.NA++
		}
	}
	for _, v := range g.InitialInside[1] {
		if v {
			g.NB++
		}
	}
	return g
}
func (g *GHGraph) Traverse(invertFirst, invertSecond bool) []Ring {
	inverted := [2]bool{invertFirst, invertSecond}
	visited := map[*Crossing]bool{}
	out := []Ring{}
	for _, start := range g.Crossings {
		if visited[start] {
			continue
		}
		points := Ring{}
		current := start.First
		for {
			visited[current.Crossing] = true
			points = append(points, current.Point)
			forward := current.Entering != inverted[current.Side]
			stopped := current.Previous
			if forward {
				stopped = current.Next
			}
			for stopped.Crossing == nil {
				points = append(points, stopped.Point)
				if forward {
					stopped = stopped.Next
				} else {
					stopped = stopped.Previous
				}
			}
			if stopped.Crossing == start {
				break
			}
			current = stopped.Other
		}
		out = append(out, points)
	}
	for side, sequence := range g.Rings {
		for i, ring := range sequence {
			hasCrossing := false
			for _, node := range g.Nodes[side][i] {
				if node.Crossing != nil {
					hasCrossing = true
					break
				}
			}
			if !hasCrossing && g.InitialInside[side][i] != inverted[side] {
				out = append(out, ring)
			}
		}
	}
	return out
}
