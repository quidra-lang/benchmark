package main

import "sort"

type Set[T comparable] map[T]bool

func cloneSet[T comparable](source Set[T]) Set[T] {
	out := Set[T]{}
	for value := range source {
		out[value] = true
	}
	return out
}
func equalSet[T comparable](a, b Set[T]) bool {
	if len(a) != len(b) {
		return false
	}
	for value := range a {
		if !b[value] {
			return false
		}
	}
	return true
}
func unionInto[T comparable](a, b Set[T]) {
	for value := range b {
		a[value] = true
	}
}
func intersectInto[T comparable](a, b Set[T]) {
	for value := range a {
		if !b[value] {
			delete(a, value)
		}
	}
}
func sortedInts(set Set[int]) []int {
	out := []int{}
	for value := range set {
		out = append(out, value)
	}
	sort.Ints(out)
	return out
}
func sortedStrings(set Set[string]) []string {
	out := []string{}
	for value := range set {
		out = append(out, value)
	}
	sort.Strings(out)
	return out
}

type Block struct {
	Number, First, Last, Start, End, IDom, Depth int
	Labels                                       []string
	Predecessors, Successors                     []int
	Dom                                          Set[int]
	Reachable                                    bool
}
type Loop struct {
	Header                 int
	Latches                []int
	Blocks, Exits, Outside Set[int]
	Depth                  int
}
type CFG struct {
	Function                    *Function
	Blocks                      []*Block
	Instructions                []*Instruction
	BlockOf, Positions          map[int]int
	Postorder, ReversePostorder []int
	Reachable                   Set[int]
	Loops                       []*Loop
}

func newCFG(f *Function) *CFG {
	g := &CFG{Function: f, Blocks: []*Block{nil}, Instructions: []*Instruction{nil}, BlockOf: map[int]int{}, Positions: map[int]int{}, Reachable: Set[int]{}}
	pending := []string{}
	pendingStart := 0
	var current *Block
	var previous *Instruction
	for i, line := range f.Code {
		if line.Instruction == nil {
			if len(pending) == 0 {
				pendingStart = i
			}
			pending = append(pending, line.Label)
			continue
		}
		s := line.Instruction
		number := len(g.Instructions)
		s.Number = number
		g.Instructions = append(g.Instructions, s)
		g.Positions[number] = i
		if current == nil || len(pending) > 0 || previous.Kind == "goto" || previous.Kind == "if" || previous.Kind == "return" {
			start := i
			if len(pending) > 0 {
				start = pendingStart
			}
			if current != nil {
				current.End = start
			}
			current = &Block{Number: len(g.Blocks), First: number, Last: number, Start: start, Labels: append([]string{}, pending...)}
			g.Blocks = append(g.Blocks, current)
		} else {
			current.Last = number
		}
		pending = nil
		g.BlockOf[number] = current.Number
		previous = s
	}
	current.End = len(f.Code)
	labels := map[string]int{}
	for _, b := range g.Blocks[1:] {
		for _, label := range b.Labels {
			labels[label] = b.Number
		}
	}
	for _, b := range g.Blocks[1:] {
		s := g.Instructions[b.Last]
		switch s.Kind {
		case "goto":
			b.Successors = []int{labels[s.Name]}
		case "if":
			b.Successors = []int{b.Number + 1}
			if target := labels[s.Name]; target != b.Number+1 {
				b.Successors = append(b.Successors, target)
			}
		case "return":
		default:
			b.Successors = []int{b.Number + 1}
		}
		for _, next := range b.Successors {
			g.Blocks[next].Predecessors = append(g.Blocks[next].Predecessors, b.Number)
		}
	}
	var visit func(int)
	visit = func(n int) {
		g.Reachable[n] = true
		g.Blocks[n].Reachable = true
		for _, next := range g.Blocks[n].Successors {
			if !g.Reachable[next] {
				visit(next)
			}
		}
		g.Postorder = append(g.Postorder, n)
	}
	visit(1)
	for i := len(g.Postorder) - 1; i >= 0; i-- {
		g.ReversePostorder = append(g.ReversePostorder, g.Postorder[i])
	}
	for _, n := range g.ReversePostorder {
		g.Blocks[n].Dom = cloneSet(g.Reachable)
	}
	g.Blocks[1].Dom = Set[int]{1: true}
	for {
		changed := false
		for _, n := range g.ReversePostorder[1:] {
			var dom Set[int]
			for _, pred := range g.Blocks[n].Predecessors {
				if !g.Reachable[pred] {
					continue
				}
				if dom == nil {
					dom = cloneSet(g.Blocks[pred].Dom)
				} else {
					intersectInto(dom, g.Blocks[pred].Dom)
				}
			}
			dom[n] = true
			if !equalSet(dom, g.Blocks[n].Dom) {
				g.Blocks[n].Dom = dom
				changed = true
			}
		}
		if !changed {
			break
		}
	}
	for _, b := range g.Blocks[1:] {
		if !b.Reachable || b.Number == 1 {
			continue
		}
		best := 0
		for d := range b.Dom {
			if d != b.Number && (best == 0 || len(g.Blocks[d].Dom) > len(g.Blocks[best].Dom)) {
				best = d
			}
		}
		b.IDom = best
	}
	for _, h := range g.Blocks[1:] {
		if !h.Reachable {
			continue
		}
		loop := &Loop{Header: h.Number, Blocks: Set[int]{h.Number: true}, Exits: Set[int]{}, Outside: Set[int]{}}
		for _, t := range g.Blocks[1:] {
			if !t.Reachable || !t.Dom[h.Number] {
				continue
			}
			for _, next := range t.Successors {
				if next == h.Number {
					loop.Latches = append(loop.Latches, t.Number)
					loop.Blocks[t.Number] = true
					break
				}
			}
		}
		if len(loop.Latches) == 0 {
			continue
		}
		queue := append([]int{}, loop.Latches...)
		for head := 0; head < len(queue); head++ {
			n := queue[head]
			if n == h.Number {
				continue
			}
			for _, pred := range g.Blocks[n].Predecessors {
				if g.Reachable[pred] && !loop.Blocks[pred] {
					loop.Blocks[pred] = true
					queue = append(queue, pred)
				}
			}
		}
		for n := range loop.Blocks {
			b := g.Blocks[n]
			if g.Instructions[b.Last].Kind == "return" {
				loop.Exits[n] = true
			}
			for _, next := range b.Successors {
				if !loop.Blocks[next] {
					loop.Exits[n] = true
					loop.Outside[next] = true
				}
			}
		}
		g.Loops = append(g.Loops, loop)
	}
	for _, loop := range g.Loops {
		for _, other := range g.Loops {
			if other.Blocks[loop.Header] {
				loop.Depth++
			}
		}
		for b := range loop.Blocks {
			g.Blocks[b].Depth++
		}
	}
	return g
}
