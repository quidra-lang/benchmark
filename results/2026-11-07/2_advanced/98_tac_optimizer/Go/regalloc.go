package main

import (
	"math/big"
)

type PotentialSpill struct {
	Name   string
	Degree int
}
type Allocation struct {
	Nodes               []string
	Neighbors, Partners map[string]Set[string]
	Costs               map[string]*big.Int
	Simplify            []string
	Potential           []PotentialSpill
	Registers           map[string]int
	Spills              Set[string]
	Edges               int
}

func allocate(g *CFG, d *DataFlow, k int) *Allocation {
	nodes := Set[string]{}
	for _, name := range g.Function.Parameters {
		nodes[name] = true
	}
	for _, b := range g.Blocks[1:] {
		if !b.Reachable {
			continue
		}
		for n := b.First; n <= b.Last; n++ {
			s := g.Instructions[n]
			if x := s.definition(); x != "" {
				nodes[x] = true
			}
			for _, v := range s.used() {
				nodes[v] = true
			}
		}
	}
	a := &Allocation{Nodes: sortedStrings(nodes), Neighbors: map[string]Set[string]{}, Partners: map[string]Set[string]{}, Costs: map[string]*big.Int{}, Registers: map[string]int{}, Spills: Set[string]{}}
	for _, v := range a.Nodes {
		a.Neighbors[v] = Set[string]{}
		a.Partners[v] = Set[string]{}
		a.Costs[v] = new(big.Int)
	}
	edge := func(x, y string) {
		if x == y || !nodes[x] || !nodes[y] {
			return
		}
		a.Neighbors[x][y] = true
		a.Neighbors[y][x] = true
	}
	for _, b := range g.Blocks[1:] {
		if !b.Reachable {
			continue
		}
		live := cloneSet(d.LiveOut[b.Number])
		weight := new(big.Int).Exp(big.NewInt(10), big.NewInt(int64(b.Depth)), nil)
		for n := b.Last; n >= b.First; n-- {
			s := g.Instructions[n]
			if x := s.definition(); x != "" {
				for v := range live {
					if s.Kind == "copy" && !s.A.IsConstant && v == s.A.Variable {
						continue
					}
					edge(x, v)
				}
				a.Costs[x].Add(a.Costs[x], weight)
			}
			for _, v := range s.used() {
				a.Costs[v].Add(a.Costs[v], weight)
			}
			live = liveTransfer(s, live)
		}
	}
	entry := cloneSet(d.LiveIn[1])
	for _, p := range g.Function.Parameters {
		entry[p] = true
	}
	for _, p := range g.Function.Parameters {
		a.Costs[p].Add(a.Costs[p], big.NewInt(1))
		for v := range entry {
			edge(p, v)
		}
	}
	for _, line := range g.Function.Code {
		s := line.Instruction
		if s != nil && s.Kind == "copy" && !s.A.IsConstant && s.Destination != s.A.Variable && nodes[s.Destination] && nodes[s.A.Variable] {
			a.Partners[s.Destination][s.A.Variable] = true
			a.Partners[s.A.Variable][s.Destination] = true
		}
	}
	for _, v := range a.Nodes {
		a.Edges += len(a.Neighbors[v])
	}
	a.Edges /= 2
	remaining := cloneSet(nodes)
	for len(remaining) > 0 {
		degrees := map[string]int{}
		for v := range remaining {
			for neighbor := range a.Neighbors[v] {
				if remaining[neighbor] {
					degrees[v]++
				}
			}
		}
		chosen := ""
		low := false
		for _, v := range a.Nodes {
			if !remaining[v] || degrees[v] >= k {
				continue
			}
			if !low || degrees[v] < degrees[chosen] {
				chosen = v
				low = true
			}
		}
		if !low {
			for _, v := range a.Nodes {
				if !remaining[v] {
					continue
				}
				if chosen == "" {
					chosen = v
					continue
				}
				left := new(big.Int).Mul(a.Costs[v], big.NewInt(int64(degrees[chosen])))
				right := new(big.Int).Mul(a.Costs[chosen], big.NewInt(int64(degrees[v])))
				if left.Cmp(right) < 0 {
					chosen = v
				}
			}
			a.Potential = append(a.Potential, PotentialSpill{chosen, degrees[chosen]})
		}
		a.Simplify = append(a.Simplify, chosen)
		delete(remaining, chosen)
	}
	for i := len(a.Simplify) - 1; i >= 0; i-- {
		v := a.Simplify[i]
		forbidden := Set[int]{}
		for neighbor := range a.Neighbors[v] {
			if r, ok := a.Registers[neighbor]; ok {
				forbidden[r] = true
			}
		}
		chosen := -1
		for partner := range a.Partners[v] {
			if r, ok := a.Registers[partner]; ok && !forbidden[r] && (chosen < 0 || r < chosen) {
				chosen = r
			}
		}
		if chosen < 0 {
			for r := 0; r < k; r++ {
				if !forbidden[r] {
					chosen = r
					break
				}
			}
		}
		if chosen < 0 {
			a.Spills[v] = true
		} else {
			a.Registers[v] = chosen
		}
	}
	return a
}
