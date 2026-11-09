package main

import (
	"fmt"
	"slices"
)

type Mutex map[[2]int]bool

func mutexPair(a, b int) [2]int {
	if a > b {
		a, b = b, a
	}
	return [2]int{a, b}
}
func (m Mutex) Has(a, b int) bool { return a != b && m[mutexPair(a, b)] }
func (m Mutex) Compatible(facts State) bool {
	numbers := facts.Numbers()
	for i, a := range numbers {
		for _, b := range numbers[i+1:] {
			if m.Has(a, b) {
				return false
			}
		}
	}
	return true
}

type GraphElement struct {
	Action, Fact  int
	Pre, Add, Del State
}
type GraphMemo struct {
	Level int
	Goals State
}
type GraphPlanResult struct {
	Status                    string
	Plan                      []int
	Layers                    [][]int
	Searched, MemoHits, Tried int
	Logs                      []string
	ComplementCount           int
}
type PlanningGraph struct {
	Actions      []GraphElement
	Goal         State
	FactLevels   []State
	FactMutex    []Mutex
	ActionLevels [][]GraphElement
	ActionMutex  []Mutex
	Memo         map[GraphMemo]bool
	Result       *GraphPlanResult
}

func (g *PlanningGraph) Extract(level int, goals State) ([][]int, bool) {
	if level == 0 {
		return [][]int{}, true
	}
	key := GraphMemo{level, goals}
	if g.Memo[key] {
		g.Result.MemoHits++
		return nil, false
	}
	g.Result.Searched++
	numbers := goals.Numbers()
	elements := g.ActionLevels[level-1]
	mutex := g.ActionMutex[level-1]
	var assign func(int, []int) ([][]int, bool)
	assign = func(at int, chosen []int) ([][]int, bool) {
		covered := State{}
		for _, i := range chosen {
			covered = covered.Union(elements[i].Add)
		}
		for at < len(numbers) && covered.Has(numbers[at]) {
			at++
		}
		if at == len(numbers) {
			pre := State{}
			for _, i := range chosen {
				pre = pre.Union(elements[i].Pre)
			}
			layers, ok := g.Extract(level-1, pre)
			if !ok {
				return nil, false
			}
			actions := []int{}
			for _, i := range chosen {
				if elements[i].Action >= 0 {
					actions = append(actions, elements[i].Action)
				}
			}
			slices.Sort(actions)
			return append(layers, actions), true
		}
		fact := numbers[at]
		achievers := []int{}
		for i, e := range elements {
			if e.Action < 0 && e.Fact == fact {
				achievers = append(achievers, i)
			}
		}
		for i, e := range elements {
			if e.Action >= 0 && e.Add.Has(fact) {
				achievers = append(achievers, i)
			}
		}
		for _, i := range achievers {
			compatible := true
			for _, j := range chosen {
				if mutex.Has(i, j) {
					compatible = false
					break
				}
			}
			if !compatible {
				continue
			}
			g.Result.Tried++
			next := append(slices.Clone(chosen), i)
			if layers, ok := assign(at+1, next); ok {
				return layers, true
			}
		}
		return nil, false
	}
	layers, ok := assign(0, nil)
	if !ok {
		g.Memo[key] = true
	}
	return layers, ok
}
func (g *PlanningGraph) Expand() {
	facts := g.FactLevels[len(g.FactLevels)-1]
	previousMutex := g.FactMutex[len(g.FactMutex)-1]
	elements := []GraphElement{}
	realActions := 0
	for _, a := range g.Actions {
		if facts.Contains(a.Pre) && previousMutex.Compatible(a.Pre) {
			elements = append(elements, a)
			realActions++
		}
	}
	for _, p := range facts.Numbers() {
		set := state([]int{p})
		elements = append(elements, GraphElement{Action: -1, Fact: p, Pre: set, Add: set})
	}
	mutex := Mutex{}
	for i, a := range elements {
		for j := i + 1; j < len(elements); j++ {
			b := elements[j]
			exclusive := a.Del.Intersects(b.Pre.Union(b.Add)) || b.Del.Intersects(a.Pre.Union(a.Add))
			if !exclusive {
				for _, p := range a.Pre.Numbers() {
					for _, q := range b.Pre.Numbers() {
						if previousMutex.Has(p, q) {
							exclusive = true
							break
						}
					}
					if exclusive {
						break
					}
				}
			}
			if exclusive {
				mutex[mutexPair(i, j)] = true
			}
		}
	}
	level := len(g.ActionLevels)
	g.Result.Logs = append(g.Result.Logs, fmt.Sprintf("action level %d: actions=%d noops=%d mutexes=%d", level, realActions, len(facts.Numbers()), len(mutex)))
	next := State{}
	achievers := map[int][]int{}
	for i, e := range elements {
		next = next.Union(e.Add)
		for _, p := range e.Add.Numbers() {
			achievers[p] = append(achievers[p], i)
		}
	}
	factMutex := Mutex{}
	numbers := next.Numbers()
	for i, p := range numbers {
		for _, q := range numbers[i+1:] {
			exclusive := true
			for _, x := range achievers[p] {
				for _, y := range achievers[q] {
					if x == y || !mutex.Has(x, y) {
						exclusive = false
						break
					}
				}
				if !exclusive {
					break
				}
			}
			if exclusive {
				factMutex[mutexPair(p, q)] = true
			}
		}
	}
	g.ActionLevels = append(g.ActionLevels, elements)
	g.ActionMutex = append(g.ActionMutex, mutex)
	g.FactLevels = append(g.FactLevels, next)
	g.FactMutex = append(g.FactMutex, factMutex)
}
func graphPlan(actions []GraphElement, initial, goal State, complementCount, limit int) *GraphPlanResult {
	r := &GraphPlanResult{ComplementCount: complementCount}
	g := &PlanningGraph{Actions: actions, Goal: goal, FactLevels: []State{initial}, FactMutex: []Mutex{{}}, Memo: map[GraphMemo]bool{}, Result: r}
	for level := 0; ; level++ {
		facts, mutex := g.FactLevels[level], g.FactMutex[level]
		r.Logs = append(r.Logs, fmt.Sprintf("fact level %d: facts=%d mutexes=%d", level, len(facts.Numbers()), len(mutex)))
		attempted := facts.Contains(goal) && mutex.Compatible(goal)
		if attempted {
			searched, hits := r.Searched, r.MemoHits
			layers, ok := g.Extract(level, goal)
			status := "fail"
			if ok {
				status = "success"
			}
			r.Logs = append(r.Logs, fmt.Sprintf("extract level %d: %s searched=%d memo_hits=%d", level, status, r.Searched-searched, r.MemoHits-hits))
			if ok {
				r.Status = "solved"
				r.Layers = layers
				for _, layer := range layers {
					r.Plan = append(r.Plan, layer...)
				}
				return r
			}
		} else if level >= 1 && len(facts.Numbers()) == len(g.FactLevels[level-1].Numbers()) && len(mutex) == len(g.FactMutex[level-1]) {
			r.Status = "unreachable"
			return r
		}
		if level == limit {
			r.Status = "level limit"
			return r
		}
		g.Expand()
	}
}
