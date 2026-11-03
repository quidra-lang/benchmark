package main

const infinity = 1 << 60

type Heuristic struct {
	Goalcount, Hmax, Hadd, FF, LMCount int
	Relaxed, Helpful                   []int
	Landmarks                          State
}

func (h *Heuristic) Value(name string) int {
	switch name {
	case "none":
		return 0
	case "goalcount":
		return h.Goalcount
	case "hmax":
		return h.Hmax
	case "hadd":
		return h.Hadd
	case "ff":
		return h.FF
	case "lmcount":
		return h.LMCount
	}
	panic("unknown heuristic")
}
func aggregate(costs []int, required State, sum bool) int {
	value := 0
	for _, p := range required.Numbers() {
		if costs[p] == infinity {
			return infinity
		}
		if sum {
			value += costs[p]
		} else {
			value = max(value, costs[p])
		}
	}
	return value
}
func relaxedCosts(g *GroundProblem, s State, sum bool) []int {
	costs := make([]int, len(g.Facts))
	for p := range costs {
		costs[p] = infinity
		if s.Has(p) {
			costs[p] = 0
		}
	}
	for {
		changed := false
		for _, a := range g.Actions {
			pre := aggregate(costs, a.Pre, sum)
			if pre == infinity {
				continue
			}
			value := a.Cost + pre
			for _, p := range a.Add.Numbers() {
				if value < costs[p] {
					costs[p] = value
					changed = true
				}
			}
		}
		if !changed {
			return costs
		}
	}
}
func reachableWithout(g *GroundProblem, s State, forbidden int) State {
	reachable := s
	for {
		previous := reachable
		for _, a := range g.Actions {
			if !a.Add.Has(forbidden) && reachable.Contains(a.Pre) {
				reachable = reachable.Union(a.Add)
			}
		}
		if reachable == previous {
			return reachable
		}
	}
}
func planningLevels(g *GroundProblem, s State) ([]int, []int) {
	facts, actions := make([]int, len(g.Facts)), make([]int, len(g.Actions))
	for p := range facts {
		facts[p] = infinity
		if s.Has(p) {
			facts[p] = 0
		}
	}
	for a := range actions {
		actions[a] = infinity
	}
	for level := 0; ; level++ {
		changed := false
		for i, a := range g.Actions {
			if actions[i] != infinity {
				continue
			}
			ready := true
			for _, p := range a.Pre.Numbers() {
				if facts[p] > level {
					ready = false
					break
				}
			}
			if !ready {
				continue
			}
			actions[i] = level
			for _, p := range a.Add.Numbers() {
				if facts[p] == infinity {
					facts[p] = level + 1
					changed = true
				}
			}
		}
		if !changed {
			return facts, actions
		}
	}
}
func (g *GroundProblem) Heuristics(s State) *Heuristic {
	if cached := g.Cache[s]; cached != nil {
		return cached
	}
	h := &Heuristic{}
	for _, p := range g.Goal.Numbers() {
		if !s.Has(p) {
			h.Goalcount++
		}
	}
	cmax, cadd := relaxedCosts(g, s, false), relaxedCosts(g, s, true)
	h.Hmax = aggregate(cmax, g.Goal, false)
	h.Hadd = aggregate(cadd, g.Goal, true)
	achievers := make([][]int, len(g.Facts))
	for i, a := range g.Actions {
		for _, p := range a.Add.Numbers() {
			achievers[p] = append(achievers[p], i)
		}
	}
	if h.Hadd == infinity {
		h.FF = infinity
	} else {
		best := make([]int, len(g.Facts))
		for p := range best {
			best[p] = -1
			if s.Has(p) || cadd[p] == infinity {
				continue
			}
			minimum := infinity
			for _, i := range achievers[p] {
				a := g.Actions[i]
				pre := aggregate(cadd, a.Pre, true)
				if pre != infinity && a.Cost+pre < minimum {
					minimum = a.Cost + pre
					best[p] = i
				}
			}
		}
		selected := make([]bool, len(g.Actions))
		var require func(int)
		require = func(p int) {
			if s.Has(p) {
				return
			}
			a := best[p]
			if selected[a] {
				return
			}
			selected[a] = true
			for _, q := range g.Actions[a].Pre.Numbers() {
				require(q)
			}
		}
		for _, p := range g.Goal.Numbers() {
			require(p)
		}
		for i, chosen := range selected {
			if chosen {
				h.Relaxed = append(h.Relaxed, i)
				h.FF += g.Actions[i].Cost
				if applicable(g.Actions[i], s) {
					h.Helpful = append(h.Helpful, i)
				}
			}
		}
	}
	factLevels, actionLevels := planningLevels(g, s)
	unreachable := false
	for _, p := range g.Goal.Numbers() {
		if factLevels[p] == infinity {
			unreachable = true
			break
		}
	}
	if unreachable {
		h.LMCount = infinity
	} else {
		h.Landmarks = g.Goal.Without(s)
		verified := map[int]bool{}
		verificationKnown := map[int]bool{}
		for {
			previous := h.Landmarks
			for _, p := range h.Landmarks.Numbers() {
				first := true
				common := State{}
				for _, i := range achievers[p] {
					if actionLevels[i] == factLevels[p]-1 {
						if first {
							common = g.Actions[i].Pre
							first = false
						} else {
							for k := range common {
								common[k] &= g.Actions[i].Pre[k]
							}
						}
					}
				}
				common = common.Without(s)
				for _, q := range common.Numbers() {
					if h.Landmarks.Has(q) {
						continue
					}
					if !verificationKnown[q] {
						verified[q] = !reachableWithout(g, s, q).Contains(g.Goal)
						verificationKnown[q] = true
					}
					if verified[q] {
						h.Landmarks.Put(q)
					}
				}
			}
			if h.Landmarks == previous {
				break
			}
		}
		h.LMCount = len(h.Landmarks.Numbers())
	}
	g.Cache[s] = h
	return h
}
