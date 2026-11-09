package main

import (
	"container/heap"
	"fmt"
	"os"
	"slices"
	"sort"
	"strconv"
	"strings"
)

type RunDefinition struct{ Solver, CostFunction, Name string }
type Delay struct{ Agent, Start, Length int }
type Parameters struct {
	Horizon, HighBudget, LowBudget, Window, Step, Frames int
	Animate                                              string
	Orders                                               [][]int
	Definitions                                          []RunDefinition
	Delays                                               []Delay
}

func readParameters(n int) Parameters {
	p := Parameters{}
	order := make([]int, n)
	for i := range order {
		order[i] = i
	}
	p.Orders = append(p.Orders, order)
	for _, line := range lines("input/params.txt") {
		a := strings.Fields(line)
		switch a[0] {
		case "HORIZON":
			p.Horizon = integer(a[1])
		case "HL_BUDGET":
			p.HighBudget = integer(a[1])
		case "LL_BUDGET":
			p.LowBudget = integer(a[1])
		case "WINDOW":
			p.Window = integer(a[1])
			p.Step = integer(a[2])
		case "ORDER":
			order := []int{}
			for _, v := range a[1:] {
				order = append(order, integer(v))
			}
			p.Orders = append(p.Orders, order)
		case "RUN":
			p.Definitions = append(p.Definitions, RunDefinition{a[1], a[2], a[1] + "-" + a[2]})
		case "ANIMATE":
			p.Animate = a[1]
			p.Frames = integer(a[2])
		case "DELAY":
			p.Delays = append(p.Delays, Delay{integer(a[1]), integer(a[2]), integer(a[3])})
		}
	}
	return p
}

type Run struct {
	Definition                    RunDefinition
	Reason, End                   string
	Paths                         [][]int
	Counter                       Counters
	High, Generated, Pruned, Open int
	Classes                       [3]int
	Specific, Trace               []string
	Answer                        *Node
	Metrics                       *PlanMetrics
	Execution                     *Execution
}

var classNames = []string{"cardinal", "semi_cardinal", "non_cardinal"}

func mdd(g *Grid, agent, length int, b *Prohibitions) []map[int]bool {
	forward := make([]map[int]bool, length+1)
	forward[0] = map[int]bool{g.Agents[agent].Start: true}
	for t := 1; t <= length; t++ {
		forward[t] = map[int]bool{}
		for c := range forward[t-1] {
			for _, v := range g.Destinations(c) {
				if g.Dist[agent][v] >= 0 && t+g.Dist[agent][v] <= length && b.Allowed(c, v, t) {
					forward[t][v] = true
				}
			}
		}
	}
	valid := make([]map[int]bool, length+1)
	valid[length] = map[int]bool{g.Agents[agent].Goal: true}
	for t := length - 1; t >= 0; t-- {
		valid[t] = map[int]bool{}
		for c := range forward[t] {
			for _, v := range g.Destinations(c) {
				if valid[t+1][v] && b.Allowed(c, v, t+1) {
					valid[t][c] = true
					break
				}
			}
		}
	}
	return valid
}
func classify(g *Grid, c Conflict, paths [][]int, cs [][]Constraint, cache map[int][]map[int]bool) int {
	fixed := 0
	for _, agent := range []int{c.A, c.B} {
		length := len(paths[agent]) - 1
		if c.Time > length {
			fixed++
			continue
		}
		layers := cache[agent]
		if layers == nil {
			layers = mdd(g, agent, length, constraintsProhibitions(cs[agent]))
			cache[agent] = layers
		}
		if len(layers[c.Time]) == 1 && (!c.Edge || len(layers[c.Time-1]) == 1) {
			fixed++
		}
	}
	return 2 - fixed
}
func overview(g *Grid, p Parameters, independent [][]int) []string {
	free, components := 0, 0
	degrees := [4]int{}
	seen := map[int]bool{}
	for c := 0; c < g.W*g.H; c++ {
		if !g.Free(c) {
			continue
		}
		free++
		degree := len(g.Destinations(c)) - 1
		degrees[min(degree, 3)]++
		if seen[c] {
			continue
		}
		components++
		q := []int{c}
		seen[c] = true
		for h := 0; h < len(q); h++ {
			for _, v := range g.Destinations(q[h])[1:] {
				if !seen[v] {
					seen[v] = true
					q = append(q, v)
				}
			}
		}
	}
	out := []string{fmt.Sprintf("instance width %d height %d free %d agents %d", g.W, g.H, free, len(g.Agents)), fmt.Sprintf("map isolated %d dead_ends %d corridors %d junctions %d components %d", degrees[0], degrees[1], degrees[2], degrees[3], components)}
	lowerSOC, lowerMax := 0, 0
	for i, a := range g.Agents {
		d := g.Dist[i][a.Start]
		layers := mdd(g, i, d, newProhibitions())
		states, width := 0, 0
		for _, layer := range layers {
			states += len(layer)
			width = max(width, len(layer))
		}
		lowerSOC += d
		lowerMax = max(lowerMax, d)
		out = append(out, fmt.Sprintf("agent %s start %s goal %s distance %d mdd %d width %d", name(i), cell(g, a.Start), cell(g, a.Goal), d, states, width))
	}
	out = append(out, fmt.Sprintf("lower_bound soc %d makespan %d", lowerSOC, lowerMax))
	cs := conflicts(independent)
	counts := [3]int{}
	vertex, edge := 0, 0
	restrictions := make([][]Constraint, len(g.Agents))
	cache := map[int][]map[int]bool{}
	adj := make([][]int, len(g.Agents))
	for _, c := range cs {
		counts[classify(g, c, independent, restrictions, cache)]++
		if c.Edge {
			edge++
		} else {
			vertex++
		}
		adj[c.A] = append(adj[c.A], c.B)
		adj[c.B] = append(adj[c.B], c.A)
	}
	out = append(out, fmt.Sprintf("independent conflicts %d vertex %d edge %d cardinal %d semi_cardinal %d non_cardinal %d", len(cs), vertex, edge, counts[0], counts[1], counts[2]))
	groups := []string{}
	visited := make([]bool, len(g.Agents))
	for i := range g.Agents {
		if visited[i] || len(adj[i]) == 0 {
			continue
		}
		q := []int{i}
		visited[i] = true
		for h := 0; h < len(q); h++ {
			for _, j := range adj[q[h]] {
				if !visited[j] {
					visited[j] = true
					q = append(q, j)
				}
			}
		}
		slices.Sort(q)
		text := ""
		for _, j := range q {
			text += name(j)
		}
		groups = append(groups, text)
	}
	groupText := "-"
	if len(groups) > 0 {
		groupText = strings.Join(groups, " ")
	}
	return append(out, "groups "+groupText)
}
func solvePP(g *Grid, p Parameters, r *Run) {
	for k, order := range p.Orders {
		r.High++
		before := r.Counter.Expansions
		paths, planned, failed := prioritized(g, p, order, k+1, r)
		if r.Counter.Aborted {
			r.Reason = "ll_budget"
			break
		}
		names := ""
		for _, i := range order {
			names += name(i)
		}
		line := fmt.Sprintf("order %d %s planned %d expansions %d", k+1, names, planned, r.Counter.Expansions-before)
		if paths != nil {
			r.Paths = paths
			r.Specific = append(r.Specific, line+" ok")
			r.End = fmt.Sprintf("end OK order %d", k+1)
			return
		}
		r.Specific = append(r.Specific, line+" failed "+name(failed))
	}
	if r.Reason == "" {
		r.Reason = "orders"
	}
}
func nodeFor(paths [][]int, cs [][]Constraint, number, parent, depth int, costFunction string) *Node {
	soc, makespan := planCosts(paths)
	cost := soc
	if costFunction == "MAKESPAN" {
		cost = makespan
	}
	return &Node{number, parent, depth, cost, paths, cs, conflicts(paths)}
}
func solveCBS(g *Grid, p Parameters, r *Run) {
	n := len(g.Agents)
	paths := make([][]int, n)
	constraints := make([][]Constraint, n)
	open := &NodeHeap{}
	defer func() {
		r.Open = open.Len()
		r.Specific = append(r.Specific, fmt.Sprintf("search expanded %d generated %d pruned %d open %d", r.High, r.Generated, r.Pruned, r.Open))
		if r.Definition.Solver == "ICBS" {
			r.Specific = append(r.Specific, fmt.Sprintf("classes cardinal %d semi_cardinal %d non_cardinal %d", r.Classes[0], r.Classes[1], r.Classes[2]))
		}
		if r.Answer != nil {
			a := r.Answer
			r.Specific = append(r.Specific, fmt.Sprintf("solution node %d depth %d", a.Number, a.Depth))
			all := []Constraint{}
			for _, cs := range a.Constraints {
				all = append(all, cs...)
			}
			sort.Slice(all, func(i, j int) bool {
				a, b := all[i], all[j]
				av := []int{a.Agent, a.Time, 0, a.U % g.W, a.U / g.W, a.V % g.W, a.V / g.W}
				bv := []int{b.Agent, b.Time, 0, b.U % g.W, b.U / g.W, b.V % g.W, b.V / g.W}
				if a.Edge {
					av[2] = 1
				}
				if b.Edge {
					bv[2] = 1
				}
				return slices.Compare(av, bv) < 0
			})
			for _, c := range all {
				if c.Edge {
					r.Specific = append(r.Specific, fmt.Sprintf("constraint %s edge %s %s t %d", name(c.Agent), cell(g, c.U), cell(g, c.V), c.Time))
				} else {
					r.Specific = append(r.Specific, fmt.Sprintf("constraint %s vertex %s t %d", name(c.Agent), cell(g, c.V), c.Time))
				}
			}
		}
	}()
	for i, a := range g.Agents {
		paths[i] = lowLevel(g, i, a.Start, 0, p.Horizon, newProhibitions(), false, &r.Counter)
		if r.Counter.Aborted {
			r.Reason = "ll_budget"
			return
		}
	}
	heap.Push(open, nodeFor(paths, constraints, 0, -1, 0, r.Definition.CostFunction))
	r.Generated = 1
	for open.Len() > 0 {
		node := heap.Pop(open).(*Node)
		if len(node.Conflicts) == 0 {
			r.Paths = node.Paths
			r.Answer = node
			r.End = fmt.Sprintf("end OK node %d cost %d", node.Number, node.Cost)
			return
		}
		if r.High == p.HighBudget {
			r.Reason = "hl_budget"
			return
		}
		r.High++
		split := node.Conflicts[0]
		class := 2
		if r.Definition.Solver == "ICBS" {
			cache := map[int][]map[int]bool{}
			class = 3
			for _, c := range node.Conflicts {
				kind := classify(g, c, node.Paths, node.Constraints, cache)
				if kind < class {
					split = c
					class = kind
				}
			}
			r.Classes[class]++
		}
		children := []string{"-", "-"}
		for k, agent := range []int{split.A, split.B} {
			cs := slices.Clone(node.Constraints)
			cs[agent] = append(slices.Clone(cs[agent]), split.Constraint(agent))
			path := lowLevel(g, agent, g.Agents[agent].Start, 0, p.Horizon, constraintsProhibitions(cs[agent]), false, &r.Counter)
			if r.Counter.Aborted {
				r.Reason = "ll_budget"
				return
			}
			if path == nil {
				r.Pruned++
				continue
			}
			newPaths := slices.Clone(node.Paths)
			newPaths[agent] = path
			number := r.Generated
			r.Generated++
			heap.Push(open, nodeFor(newPaths, cs, number, node.Number, node.Depth+1, r.Definition.CostFunction))
			children[k] = strconv.Itoa(number)
		}
		parent := "-"
		if node.Parent >= 0 {
			parent = strconv.Itoa(node.Parent)
		}
		splitText := conflictText(g, split)
		if r.Definition.Solver == "ICBS" {
			splitText += " class " + classNames[class]
		}
		r.Trace = append(r.Trace, fmt.Sprintf("expand %d node %d parent %s depth %d cost %d conflicts %d split %s children %s %s", r.High, node.Number, parent, node.Depth, node.Cost, len(node.Conflicts), splitText, children[0], children[1]))
	}
	r.Reason = "exhausted"
}
func solveWHCA(g *Grid, p Parameters, r *Run) {
	defer func() {
		r.Specific = append(r.Specific, fmt.Sprintf("window %d step %d rounds %d", p.Window, p.Step, r.High))
	}()
	executed := make([][]int, len(g.Agents))
	current := make([]int, len(g.Agents))
	for i, a := range g.Agents {
		current[i] = a.Start
		executed[i] = []int{a.Start}
	}
	for time := 0; ; time += p.Step {
		done := true
		for i, a := range g.Agents {
			if current[i] != a.Goal {
				done = false
			}
		}
		if done {
			for i, a := range g.Agents {
				path := executed[i]
				for len(path) > 1 && path[len(path)-2] == a.Goal {
					path = path[:len(path)-1]
				}
				executed[i] = path
			}
			r.Paths = executed
			r.End = fmt.Sprintf("end OK rounds %d", r.High)
			return
		}
		if time >= p.Horizon {
			r.Reason = "timeout"
			return
		}
		r.High++
		order := []int{}
		for _, atGoal := range []bool{false, true} {
			for i, a := range g.Agents {
				if (current[i] == a.Goal) == atGoal {
					order = append(order, i)
				}
			}
		}
		b := newProhibitions()
		window := make([][]int, len(g.Agents))
		for _, agent := range order {
			before := r.Counter.Expansions
			path := lowLevel(g, agent, current[agent], time, time+p.Window, b, true, &r.Counter)
			if r.Counter.Aborted {
				r.Reason = "ll_budget"
				return
			}
			base := fmt.Sprintf("round %d time %d agent %s", r.High, time, name(agent))
			if path == nil {
				r.Trace = append(r.Trace, fmt.Sprintf("%s blocked expansions %d", base, r.Counter.Expansions-before))
				r.Reason = "blocked"
				return
			}
			for len(path) < p.Window+1 {
				path = append(path, path[len(path)-1])
			}
			r.Trace = append(r.Trace, fmt.Sprintf("%s moves %s expansions %d", base, actions(g, path), r.Counter.Expansions-before))
			window[agent] = path
			b.Reserve(path, time, false)
		}
		for i := range g.Agents {
			executed[i] = append(executed[i], window[i][1:p.Step+1]...)
			current[i] = window[i][p.Step]
		}
	}
}

type AgentMetrics struct {
	Cost, Extra, Waits, Turns, Arrival, Leave int
	Actions                                   string
}
type PlanMetrics struct {
	SOC, Makespan, SumExtra, MaxExtra, Waits, Turns int
	Agents                                          []AgentMetrics
	Traffic, CellWaits                              []int
	Arrivals                                        []int
	Hotspots                                        []int
}

func metrics(g *Grid, paths [][]int) *PlanMetrics {
	soc, makespan := planCosts(paths)
	m := &PlanMetrics{SOC: soc, Makespan: makespan, Traffic: make([]int, g.W*g.H), CellWaits: make([]int, g.W*g.H), Arrivals: make([]int, makespan+1)}
	for i, p := range paths {
		a := AgentMetrics{Cost: len(p) - 1, Extra: len(p) - 1 - g.Dist[i][g.Agents[i].Start], Arrival: -1, Actions: actions(g, p)}
		seen := map[int]bool{}
		last := byte(0)
		for t, c := range p {
			seen[c] = true
			if c == g.Agents[i].Goal && a.Arrival < 0 {
				a.Arrival = t
			}
			if t == 0 {
				continue
			}
			if c == p[t-1] {
				a.Waits++
				m.CellWaits[c]++
			} else {
				d := action(g, p[t-1], c)
				if last != 0 && last != d {
					a.Turns++
				}
				last = d
			}
			if p[t-1] == g.Agents[i].Goal && c != g.Agents[i].Goal {
				a.Leave++
			}
		}
		for c := range seen {
			m.Traffic[c]++
		}
		for t := a.Cost; t <= makespan; t++ {
			m.Arrivals[t]++
		}
		m.SumExtra += a.Extra
		m.MaxExtra = max(m.MaxExtra, a.Extra)
		m.Waits += a.Waits
		m.Turns += a.Turns
		m.Agents = append(m.Agents, a)
	}
	for c, n := range m.Traffic {
		if n > 0 {
			m.Hotspots = append(m.Hotspots, c)
		}
	}
	sort.Slice(m.Hotspots, func(i, j int) bool {
		a, b := m.Hotspots[i], m.Hotspots[j]
		if m.Traffic[a] != m.Traffic[b] {
			return m.Traffic[a] > m.Traffic[b]
		}
		return a < b
	})
	m.Hotspots = m.Hotspots[:min(5, len(m.Hotspots))]
	return m
}
func validation(g *Grid, name string, paths [][]int, independent bool) []string {
	start, goal, moves, follows, vertex, edge := 0, 0, 0, 0, 0, 0
	for i, p := range paths {
		if p[0] != g.Agents[i].Start {
			start++
		}
		if p[len(p)-1] != g.Agents[i].Goal {
			goal++
		}
		for t := 1; t < len(p); t++ {
			if !slices.Contains(g.Destinations(p[t-1]), p[t]) {
				moves++
			}
		}
	}
	cs := conflicts(paths)
	for _, c := range cs {
		if c.Edge {
			edge++
		} else {
			vertex++
		}
	}
	_, last := planCosts(paths)
	for t := 1; t <= last; t++ {
		for a := range paths {
			for b := range paths {
				if a != b && position(paths[a], t) != position(paths[a], t-1) && position(paths[a], t) == position(paths[b], t-1) && position(paths[b], t) != position(paths[a], t-1) {
					follows++
				}
			}
		}
	}
	verdict := "VALID"
	if start+goal+moves+vertex+edge > 0 {
		verdict = "INVALID"
	}
	out := []string{fmt.Sprintf("plan %s verdict %s start %d goal %d moves %d vertex %d edge %d follows %d", name, verdict, start, goal, moves, vertex, edge, follows)}
	cache := map[int][]map[int]bool{}
	constraints := make([][]Constraint, len(paths))
	for _, c := range cs {
		text := "  " + conflictText(g, c)
		if independent {
			text += " " + classNames[classify(g, c, paths, constraints, cache)]
		}
		out = append(out, text)
	}
	return out
}

type Step struct{ Time, Cell int }
type Prerequisite struct{ Agent, Step int }
type Execution struct {
	Deadlock                     bool
	Time, SOC, Makespan, Blocked int
	Finish                       []int
}

func delayed(paths [][]int, delays []Delay) *Execution {
	n := len(paths)
	steps := make([][]Step, n)
	for i, p := range paths {
		steps[i] = []Step{{0, p[0]}}
		for t := 1; t < len(p); t++ {
			if p[t] != p[t-1] {
				steps[i] = append(steps[i], Step{t, p[t]})
			}
		}
	}
	needs := make([][][]Prerequisite, n)
	for i, a := range steps {
		needs[i] = make([][]Prerequisite, len(a))
		for k, s := range a {
			if k == 0 {
				continue
			}
			for j, b := range steps {
				if i == j {
					continue
				}
				for l, t := range b {
					if t.Cell == s.Cell && t.Time < s.Time {
						needs[i][k] = append(needs[i][k], Prerequisite{j, l})
					}
				}
			}
		}
	}
	out := &Execution{Finish: make([]int, n)}
	progress := make([]int, n)
	for time := 0; ; time++ {
		done := true
		for i := range steps {
			if progress[i] < len(steps[i])-1 {
				done = false
			}
		}
		if done {
			for _, f := range out.Finish {
				out.SOC += f
				out.Makespan = max(out.Makespan, f)
			}
			return out
		}
		advance := []int{}
		stopped := false
		for i := range steps {
			if progress[i] == len(steps[i])-1 {
				continue
			}
			stop := false
			for _, d := range delays {
				if d.Agent == i && d.Start <= time && time < d.Start+d.Length {
					stop = true
					break
				}
			}
			if stop {
				stopped = true
				continue
			}
			held := false
			for _, p := range needs[i][progress[i]+1] {
				if progress[p.Agent] <= p.Step {
					held = true
					break
				}
			}
			if held {
				out.Blocked++
			} else {
				advance = append(advance, i)
			}
		}
		if len(advance) == 0 && !stopped {
			out.Deadlock = true
			out.Time = time
			return out
		}
		for _, i := range advance {
			progress[i]++
			out.Finish[i] = time + 1
		}
	}
}
func countPicture(g *Grid, counts []int) []string {
	out := []string{}
	for y := 0; y < g.H; y++ {
		row := []byte(g.Rows[y])
		for x := 0; x < g.W; x++ {
			c := y*g.W + x
			if !g.Free(c) {
				continue
			}
			v := counts[c]
			if v == 0 {
				row[x] = '.'
			} else if v <= 9 {
				row[x] = byte('0' + v)
			} else {
				row[x] = '+'
			}
		}
		out = append(out, string(row))
	}
	return out
}
func frames(g *Grid, p Parameters, r *Run) []string {
	if r.Paths == nil {
		return []string{"run " + p.Animate + " FAIL"}
	}
	out := []string{fmt.Sprintf("run %s frames %d", p.Animate, p.Frames)}
	for t := 0; t < p.Frames; t++ {
		picture := make([][]byte, g.H)
		for y := range picture {
			picture[y] = []byte(g.Rows[y])
		}
		for i, a := range g.Agents {
			picture[a.Goal/g.W][a.Goal%g.W] = byte('a' + i)
		}
		done, moving, waiting := 0, 0, 0
		for i, path := range r.Paths {
			c := position(path, t)
			picture[c/g.W][c%g.W] = byte('A' + i)
			if t >= len(path)-1 {
				done++
			} else if t >= 1 && position(path, t) != position(path, t-1) {
				moving++
			} else {
				waiting++
			}
		}
		out = append(out, "", fmt.Sprintf("frame %d done %d moving %d waiting %d", t, done, moving, waiting))
		for _, row := range picture {
			out = append(out, string(row))
		}
	}
	out = append(out, "", "traffic")
	out = append(out, countPicture(g, r.Metrics.Traffic)...)
	out = append(out, "", "waits")
	out = append(out, countPicture(g, r.Metrics.CellWaits)...)
	return out
}
func runBlock(g *Grid, r *Run) []string {
	d := r.Definition
	base := fmt.Sprintf("run %s solver %s cost_function %s result", d.Name, d.Solver, d.CostFunction)
	if r.Paths == nil {
		return append([]string{base + " FAIL reason " + r.Reason}, r.Specific...)
	}
	m := r.Metrics
	cost, lower := m.SOC, 0
	for i, a := range g.Agents {
		lower += g.Dist[i][a.Start]
	}
	if d.CostFunction == "MAKESPAN" {
		cost = m.Makespan
		lower = 0
		for i, a := range g.Agents {
			lower = max(lower, g.Dist[i][a.Start])
		}
	}
	out := append([]string{fmt.Sprintf("%s OK cost %d soc %d makespan %d ratio %s", base, cost, m.SOC, m.Makespan, fraction(cost, lower))}, r.Specific...)
	for i, a := range m.Agents {
		out = append(out, fmt.Sprintf("agent %s cost %d extra %d waits %d turns %d arrive %d leave %d moves %s", name(i), a.Cost, a.Extra, a.Waits, a.Turns, a.Arrival, a.Leave, a.Actions))
	}
	out = append(out, "arrivals "+strings.Join(intTexts(m.Arrivals), " "))
	hotspots := []string{}
	for _, c := range m.Hotspots {
		hotspots = append(hotspots, fmt.Sprintf("%s:%d", cell(g, c), m.Traffic[c]))
	}
	out = append(out, "hotspots "+strings.Join(hotspots, " "))
	e := r.Execution
	if e.Deadlock {
		out = append(out, fmt.Sprintf("execution deadlock time %d", e.Time))
	} else {
		out = append(out, fmt.Sprintf("execution soc %d makespan %d blocked %d finish %s", e.SOC, e.Makespan, e.Blocked, strings.Join(intTexts(e.Finish), " ")))
	}
	return out
}
func statsLine(r *Run) string {
	d := r.Definition
	out := []string{d.Name, d.Solver, d.CostFunction}
	if r.Paths == nil {
		out = append(out, "FAIL", r.Reason)
		for i := 0; i < 9; i++ {
			out = append(out, "-")
		}
	} else {
		m := r.Metrics
		cost := m.SOC
		if d.CostFunction == "MAKESPAN" {
			cost = m.Makespan
		}
		out = append(out, "OK", "-")
		out = append(out, intTexts([]int{cost, m.SOC, m.Makespan, m.SumExtra, m.MaxExtra, m.Waits, m.Turns})...)
		if r.Execution.Deadlock {
			out = append(out, "-", "-")
		} else {
			out = append(out, strconv.Itoa(r.Execution.SOC), strconv.Itoa(r.Execution.Makespan))
		}
	}
	generated := "-"
	if d.Solver == "CBS" || d.Solver == "ICBS" {
		generated = strconv.Itoa(r.Generated)
	}
	out = append(out, strconv.Itoa(r.High), generated, strconv.Itoa(r.Counter.Searches), strconv.Itoa(r.Counter.Expansions))
	return strings.Join(out, ",")
}
func main() {
	g := readGrid()
	p := readParameters(len(g.Agents))
	independent := make([][]int, len(g.Agents))
	counter := Counters{Limit: int(^uint(0) >> 1)}
	for i, a := range g.Agents {
		independent[i] = lowLevel(g, i, a.Start, 0, p.Horizon, newProhibitions(), false, &counter)
	}
	solutions := overview(g, p, independent)
	validations := validation(g, "INDEPENDENT", independent, true)
	stats := []string{"run,solver,cost_function,result,reason,cost,soc,makespan,sum_extra,max_extra,waits,turns,exec_soc,exec_makespan,high_level,generated,searches,expansions"}
	trace := []string{}
	runs := []*Run{}
	successful := []int{}
	var animated *Run
	for _, d := range p.Definitions {
		r := &Run{Definition: d, Counter: Counters{Limit: p.LowBudget}}
		switch d.Solver {
		case "PP":
			solvePP(g, p, r)
		case "CBS", "ICBS":
			solveCBS(g, p, r)
		case "WHCA":
			solveWHCA(g, p, r)
		}
		if r.Paths != nil {
			r.Metrics = metrics(g, r.Paths)
			r.Execution = delayed(r.Paths, p.Delays)
			successful = append(successful, len(runs))
			validations = append(validations, validation(g, d.Name, r.Paths, false)...)
		} else {
			validations = append(validations, "plan "+d.Name+" verdict NONE")
			r.End = "end FAIL " + r.Reason
		}
		solutions = append(solutions, "")
		solutions = append(solutions, runBlock(g, r)...)
		stats = append(stats, statsLine(r))
		if len(trace) > 0 {
			trace = append(trace, "")
		}
		trace = append(trace, "run "+d.Name)
		trace = append(trace, r.Trace...)
		trace = append(trace, r.End)
		runs = append(runs, r)
		if d.Name == p.Animate {
			animated = r
		}
	}
	solutions = append(solutions, "", fmt.Sprintf("summary ok %d failed %d", len(successful), len(runs)-len(successful)))
	if len(successful) > 0 {
		bestSOC, bestMax := runs[successful[0]].Metrics.SOC, runs[successful[0]].Metrics.Makespan
		for _, i := range successful {
			bestSOC = min(bestSOC, runs[i].Metrics.SOC)
			bestMax = min(bestMax, runs[i].Metrics.Makespan)
		}
		socNames, maxNames := []string{}, []string{}
		for _, i := range successful {
			if runs[i].Metrics.SOC == bestSOC {
				socNames = append(socNames, runs[i].Definition.Name)
			}
			if runs[i].Metrics.Makespan == bestMax {
				maxNames = append(maxNames, runs[i].Definition.Name)
			}
		}
		solutions = append(solutions, fmt.Sprintf("best_soc %d %s", bestSOC, strings.Join(socNames, " ")), fmt.Sprintf("best_makespan %d %s", bestMax, strings.Join(maxNames, " ")))
		sort.Slice(successful, func(i, j int) bool {
			a, b := runs[successful[i]].Metrics, runs[successful[j]].Metrics
			if a.SOC != b.SOC {
				return a.SOC < b.SOC
			}
			if a.Makespan != b.Makespan {
				return a.Makespan < b.Makespan
			}
			return successful[i] < successful[j]
		})
		ranking := []string{}
		for _, i := range successful {
			ranking = append(ranking, runs[i].Definition.Name)
		}
		solutions = append(solutions, "ranking "+strings.Join(ranking, " "))
	}
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	writeLines("solutions.txt", solutions)
	writeLines("stats.csv", stats)
	writeLines("validation.txt", validations)
	writeLines("trace.txt", trace)
	writeLines("frames.txt", frames(g, p, animated))
}
