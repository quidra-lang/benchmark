package main

import "container/heap"

type State struct{ Cell, Time int }
type Move struct{ From, To, Time int }
type Prohibitions struct {
	States    map[State]bool
	Moves     map[Move]bool
	Permanent map[int]int
}

func newProhibitions() *Prohibitions {
	return &Prohibitions{map[State]bool{}, map[Move]bool{}, map[int]int{}}
}
func (b *Prohibitions) Allowed(u, v, t int) bool {
	if b.States[State{v, t}] {
		return false
	}
	if at, ok := b.Permanent[v]; ok && at <= t {
		return false
	}
	return u == v || !b.Moves[Move{u, v, t}]
}
func (b *Prohibitions) Arrival(goal int) int {
	r := 0
	for s := range b.States {
		if s.Cell == goal {
			r = max(r, s.Time+1)
		}
	}
	return r
}
func (b *Prohibitions) Reserve(path []int, start int, permanent bool) {
	for k, c := range path {
		b.States[State{c, start + k}] = true
		if k > 0 && c != path[k-1] {
			b.Moves[Move{c, path[k-1], start + k}] = true
		}
	}
	if permanent {
		goal := path[len(path)-1]
		at := start + len(path) - 1
		if old, ok := b.Permanent[goal]; !ok || at < old {
			b.Permanent[goal] = at
		}
	}
}
func constraintsProhibitions(cs []Constraint) *Prohibitions {
	b := newProhibitions()
	for _, c := range cs {
		if c.Edge {
			b.Moves[Move{c.U, c.V, c.Time}] = true
		} else {
			b.States[State{c.V, c.Time}] = true
		}
	}
	return b
}

type Counters struct {
	Searches, Expansions, Limit int
	Aborted                     bool
}
type SearchState struct{ Cell, Time, F, G, Serial, Parent int }
type SearchHeap struct {
	Values []int
	States *[]SearchState
}

func (h SearchHeap) Len() int { return len(h.Values) }
func (h SearchHeap) Less(i, j int) bool {
	a, b := (*h.States)[h.Values[i]], (*h.States)[h.Values[j]]
	if a.F != b.F {
		return a.F < b.F
	}
	if a.G != b.G {
		return a.G > b.G
	}
	return a.Serial < b.Serial
}
func (h SearchHeap) Swap(i, j int) { h.Values[i], h.Values[j] = h.Values[j], h.Values[i] }
func (h *SearchHeap) Push(v any)   { h.Values = append(h.Values, v.(int)) }
func (h *SearchHeap) Pop() any {
	v := h.Values[len(h.Values)-1]
	h.Values = h.Values[:len(h.Values)-1]
	return v
}
func lowLevel(g *Grid, agent, start, t0, tmax int, b *Prohibitions, window bool, counter *Counters) []int {
	counter.Searches++
	r := b.Arrival(g.Agents[agent].Goal)
	states := []SearchState{{start, t0, g.Dist[agent][start], 0, 0, -1}}
	open := &SearchHeap{[]int{0}, &states}
	generated := map[State]bool{{start, t0}: true}
	for open.Len() > 0 {
		index := heap.Pop(open).(int)
		s := states[index]
		counter.Expansions++
		if counter.Expansions > counter.Limit {
			counter.Aborted = true
			return nil
		}
		if (s.Cell == g.Agents[agent].Goal && s.Time >= r) || (window && s.Time == tmax) {
			out := []int{}
			for index >= 0 {
				out = append(out, states[index].Cell)
				index = states[index].Parent
			}
			for i, j := 0, len(out)-1; i < j; i, j = i+1, j-1 {
				out[i], out[j] = out[j], out[i]
			}
			return out
		}
		if s.Time == tmax {
			continue
		}
		for _, v := range g.Destinations(s.Cell) {
			key := State{v, s.Time + 1}
			if g.Dist[agent][v] < 0 || generated[key] || !b.Allowed(s.Cell, v, s.Time+1) {
				continue
			}
			generated[key] = true
			serial := len(states)
			distance := s.Time + 1 - t0
			states = append(states, SearchState{v, s.Time + 1, distance + g.Dist[agent][v], distance, serial, index})
			heap.Push(open, serial)
		}
	}
	return nil
}
