package main

type Definition struct {
	Variable string
	Number   int
}
type CopyPair struct{ Destination, Source string }
type Flow[T comparable] struct {
	In, Out, Before map[int]Set[T]
	Iterations      int
}
type DataFlow struct {
	Graph                                  *CFG
	Reaching                               Flow[Definition]
	Expressions                            Flow[Expression]
	Copies                                 Flow[CopyPair]
	LiveIn, LiveOut, LiveBefore, LiveAfter map[int]Set[string]
	LiveIterations                         int
}

func reachingTransfer(s *Instruction, number int, state Set[Definition]) Set[Definition] {
	out := cloneSet(state)
	if x := s.definition(); x != "" {
		for d := range out {
			if d.Variable == x {
				delete(out, d)
			}
		}
		out[Definition{x, number}] = true
	}
	return out
}
func liveTransfer(s *Instruction, state Set[string]) Set[string] {
	out := cloneSet(state)
	delete(out, s.definition())
	for _, v := range s.used() {
		out[v] = true
	}
	return out
}
func expressionTransfer(s *Instruction, number int, state Set[Expression]) Set[Expression] {
	out := cloneSet(state)
	if expression, ok := s.expression(); ok {
		out[expression] = true
	}
	for expression := range out {
		if s.Kind == "store" && expression.Kind == "load" && expression.Operator == s.Name || s.Kind == "call" && expression.Kind == "load" || s.definition() != "" && expression.uses(s.definition()) {
			delete(out, expression)
		}
	}
	return out
}
func copyTransfer(s *Instruction, number int, state Set[CopyPair]) Set[CopyPair] {
	out := cloneSet(state)
	if x := s.definition(); x != "" {
		for pair := range out {
			if pair.Destination == x || pair.Source == x {
				delete(out, pair)
			}
		}
	}
	if s.Kind == "copy" && !s.A.IsConstant && s.Destination != s.A.Variable {
		out[CopyPair{s.Destination, s.A.Variable}] = true
	}
	return out
}
func forward[T comparable](g *CFG, universe, entry Set[T], union bool, transfer func(*Instruction, int, Set[T]) Set[T]) Flow[T] {
	flow := Flow[T]{In: map[int]Set[T]{}, Out: map[int]Set[T]{}, Before: map[int]Set[T]{}}
	for n := range g.Reachable {
		flow.Out[n] = cloneSet(universe)
	}
	for {
		flow.Iterations++
		changed := false
		for _, n := range g.ReversePostorder {
			state := Set[T]{}
			first := true
			for _, pred := range g.Blocks[n].Predecessors {
				if !g.Reachable[pred] {
					continue
				}
				if union {
					unionInto(state, flow.Out[pred])
				} else if first {
					state = cloneSet(flow.Out[pred])
					first = false
				} else {
					intersectInto(state, flow.Out[pred])
				}
			}
			if n == 1 {
				if union {
					unionInto(state, entry)
				} else {
					state = Set[T]{}
				}
			}
			flow.In[n] = cloneSet(state)
			b := g.Blocks[n]
			for i := b.First; i <= b.Last; i++ {
				state = transfer(g.Instructions[i], i, state)
			}
			if !equalSet(state, flow.Out[n]) {
				flow.Out[n] = state
				changed = true
			}
		}
		if !changed {
			break
		}
	}
	for _, b := range g.Blocks[1:] {
		if !b.Reachable {
			continue
		}
		state := cloneSet(flow.In[b.Number])
		for n := b.First; n <= b.Last; n++ {
			flow.Before[n] = cloneSet(state)
			state = transfer(g.Instructions[n], n, state)
		}
	}
	return flow
}
func newDataFlow(g *CFG) *DataFlow {
	d := &DataFlow{Graph: g, LiveIn: map[int]Set[string]{}, LiveOut: map[int]Set[string]{}, LiveBefore: map[int]Set[string]{}, LiveAfter: map[int]Set[string]{}}
	expressions := Set[Expression]{}
	copies := Set[CopyPair]{}
	parameters := Set[Definition]{}
	for _, name := range g.Function.Parameters {
		parameters[Definition{name, 0}] = true
	}
	for n, s := range g.Instructions[1:] {
		if !g.Reachable[g.BlockOf[n+1]] {
			continue
		}
		if e, ok := s.expression(); ok {
			expressions[e] = true
		}
		if s.Kind == "copy" && !s.A.IsConstant && s.Destination != s.A.Variable {
			copies[CopyPair{s.Destination, s.A.Variable}] = true
		}
	}
	d.Reaching = forward(g, Set[Definition]{}, parameters, true, reachingTransfer)
	d.Expressions = forward(g, expressions, Set[Expression]{}, false, expressionTransfer)
	d.Copies = forward(g, copies, Set[CopyPair]{}, false, copyTransfer)
	for n := range g.Reachable {
		d.LiveIn[n] = Set[string]{}
	}
	for {
		d.LiveIterations++
		changed := false
		for _, n := range g.Postorder {
			state := Set[string]{}
			for _, next := range g.Blocks[n].Successors {
				unionInto(state, d.LiveIn[next])
			}
			d.LiveOut[n] = cloneSet(state)
			b := g.Blocks[n]
			for i := b.Last; i >= b.First; i-- {
				state = liveTransfer(g.Instructions[i], state)
			}
			if !equalSet(state, d.LiveIn[n]) {
				d.LiveIn[n] = state
				changed = true
			}
		}
		if !changed {
			break
		}
	}
	for _, b := range g.Blocks[1:] {
		if !b.Reachable {
			continue
		}
		state := cloneSet(d.LiveOut[b.Number])
		for n := b.Last; n >= b.First; n-- {
			d.LiveAfter[n] = cloneSet(state)
			state = liveTransfer(g.Instructions[n], state)
			d.LiveBefore[n] = cloneSet(state)
		}
	}
	return d
}
