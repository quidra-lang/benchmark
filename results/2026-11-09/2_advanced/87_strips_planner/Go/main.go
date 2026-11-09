package main

import (
	"fmt"
	"os"
	"slices"
	"strconv"
	"strings"
)

type Settings struct {
	Budget, Weight, LevelLimit int
	Runs                       []SearchSettings
	Repair                     SearchSettings
}
type Step struct {
	Name      string
	Arguments []string
}

func (s Step) Text() string { return Atom{s.Name, s.Arguments}.Text() }

type CandidatePlan struct {
	Problem, Label string
	Steps          []Step
}

func readSettings() Settings {
	s := Settings{}
	for _, line := range lines("input/params.txt") {
		if line == "" || line[0] == '#' {
			continue
		}
		a := strings.Split(line, " ")
		switch a[0] {
		case "budget":
			s.Budget = integer(a[1])
		case "weight":
			s.Weight = integer(a[1])
		case "graphplan":
			s.LevelLimit = integer(a[1])
		case "run":
			s.Runs = append(s.Runs, SearchSettings{a[1], a[2]})
		case "repair":
			s.Repair = SearchSettings{a[1], a[2]}
		}
	}
	return s
}
func readCandidates() []CandidatePlan {
	out := []CandidatePlan{}
	for _, line := range lines("input/candidates.txt") {
		if line == "" || line[0] == '#' {
			continue
		}
		if strings.HasPrefix(line, "plan ") {
			a := strings.Split(line, " ")
			out = append(out, CandidatePlan{Problem: a[1], Label: a[2]})
		} else if line != "end" {
			a := strings.Split(line[1:len(line)-1], " ")
			i := len(out) - 1
			out[i].Steps = append(out[i].Steps, Step{a[0], a[1:]})
		}
	}
	return out
}
func argumentCheck(d *Domain, args, expected []string, types map[string]string, noun string) string {
	if len(args) != len(expected) {
		return fmt.Sprintf("expected %d arguments, got %d", len(expected), len(args))
	}
	for i, a := range args {
		actual, ok := types[a]
		if !ok {
			return "unknown " + noun + " " + a
		}
		if !d.Subtype(actual, expected[i]) {
			return fmt.Sprintf("argument %d (%s) is not of type %s", i+1, a, expected[i])
		}
	}
	return ""
}
func validateDomain(d *Domain) {
	kept := []*Schema{}
	for _, s := range d.Actions {
		reason := ""
		types := map[string]string{}
		for _, p := range s.Parameters {
			types[p.Name] = p.Type
			if !slices.Contains(d.Types, p.Type) && reason == "" {
				reason = "unknown type " + p.Type
			}
		}
		if reason == "" {
			literals := append(slices.Clone(s.Conditions), s.Effects...)
			for _, l := range literals {
				a := l.Atom
				expected := []string{}
				if a.Predicate == "=" {
					expected = []string{"object", "object"}
				} else if i, ok := d.PredicateIndex[a.Predicate]; ok {
					expected = d.Predicates[i].Types
				} else {
					reason = a.Text() + ": unknown predicate " + a.Predicate
					break
				}
				if error := argumentCheck(d, a.Terms, expected, types, "variable"); error != "" {
					reason = a.Text() + ": " + error
					break
				}
			}
		}
		if reason != "" {
			d.Diagnostics = append(d.Diagnostics, "error: action "+s.Name+": "+reason)
		} else {
			kept = append(kept, s)
		}
	}
	d.Actions = kept
	used := map[string]bool{}
	for _, s := range d.Actions {
		for _, l := range append(slices.Clone(s.Conditions), s.Effects...) {
			used[l.Atom.Predicate] = true
		}
	}
	for _, p := range d.Predicates {
		if !used[p.Name] {
			d.Diagnostics = append(d.Diagnostics, "warning: predicate "+p.Name+" is not used by any action")
		}
	}
	d.Classify()
}
func validateProblem(d *Domain, p *Problem) {
	types := objectTypes(p)
	check := func(atoms []Atom, side string) []Atom {
		kept := []Atom{}
		seen := map[string]bool{}
		for _, a := range atoms {
			reason := ""
			if i, ok := d.PredicateIndex[a.Predicate]; !ok {
				reason = "unknown predicate " + a.Predicate
			} else {
				reason = argumentCheck(d, a.Terms, d.Predicates[i].Types, types, "object")
			}
			if reason == "" && seen[a.Text()] {
				reason = "duplicate"
			}
			if reason != "" {
				p.Diagnostics = append(p.Diagnostics, "warning: "+side+" "+a.Text()+": "+reason)
			} else {
				seen[a.Text()] = true
				kept = append(kept, a)
			}
		}
		return kept
	}
	p.Initial = check(p.Initial, "init")
	p.Goals = check(p.Goals, "goal")
}
func heading(text string, items []string) string {
	if len(items) == 0 {
		return text + " -"
	}
	return text + " " + strings.Join(items, " ")
}
func numberList(s State) string {
	numbers := s.Numbers()
	if len(numbers) == 0 {
		return "-"
	}
	return intList(numbers, ",")
}
func intList(numbers []int, separator string) string {
	out := make([]string, len(numbers))
	for i, n := range numbers {
		out[i] = strconv.Itoa(n)
	}
	return strings.Join(out, separator)
}
func domainLines(d *Domain) []string {
	out := []string{"== domain " + d.Name + " =="}
	out = append(out, d.Diagnostics...)
	for _, t := range d.Types {
		chain := []string{t}
		for t != "object" {
			t = d.Parents[t]
			chain = append(chain, t)
		}
		out = append(out, "type "+strings.Join(chain, " < "))
	}
	for _, p := range d.Predicates {
		kind := "static"
		if d.Fluent[p.Name] {
			kind = "fluent"
		}
		out = append(out, fmt.Sprintf("predicate %s/%d %s", p.Name, len(p.Types), kind))
	}
	for _, s := range d.Actions {
		add, del := 0, 0
		for _, e := range s.Effects {
			if e.Negative {
				del++
			} else {
				add++
			}
		}
		out = append(out, fmt.Sprintf("action %s/%d cost=%d pre=%d add=%d del=%d", s.Name, len(s.Parameters), s.Cost, len(s.Conditions), add, del))
	}
	return out
}
func groundingLines(g *GroundProblem) []string {
	d, p := g.Domain, g.Problem
	out := []string{"== problem " + p.Name + " =="}
	out = append(out, p.Diagnostics...)
	out = append(out, fmt.Sprintf("objects: %d", len(p.Objects)))
	for _, t := range d.Types {
		out = append(out, heading("  "+t+":", objectsOfType(d, p, t)))
	}
	out = append(out, fmt.Sprintf("static facts: %d", g.StaticFacts))
	for _, s := range d.Actions {
		c := g.Counts[s.Name]
		out = append(out, fmt.Sprintf("schema %s: assignments=%d candidates=%d reachable=%d", s.Name, c.Assignments, c.Candidates, c.Reachable))
	}
	out = append(out, fmt.Sprintf("candidates: %d reachable: %d", g.CandidateCount, len(g.Actions)), fmt.Sprintf("facts: %d init: %d goals: %d", len(g.Facts), len(g.Initial.Numbers()), len(g.Goal.Numbers())))
	for _, a := range g.Unreachable {
		out = append(out, "unreachable goal: "+a.Text())
	}
	counts := map[string]int{}
	for _, a := range g.Facts {
		counts[a.Predicate]++
	}
	items := []string{}
	for _, p := range d.Predicates {
		if d.Fluent[p.Name] {
			items = append(items, fmt.Sprintf("%s=%d", p.Name, counts[p.Name]))
		}
	}
	out = append(out, heading("facts by predicate:", items), "facts:")
	for i, a := range g.Facts {
		out = append(out, fmt.Sprintf("  %d %s", i, a.Text()))
	}
	out = append(out, "actions:")
	for i, a := range g.Actions {
		out = append(out, fmt.Sprintf("  %d %s cost=%d pre=%s neg=%s add=%s del=%s", i, a.Text(), a.Cost, numberList(a.Pre), numberList(a.Neg), numberList(a.Add), numberList(a.Del)))
	}
	return out
}

type Validation struct {
	Status   string
	Messages []string
	Correct  int
}

func (v Validation) Verdict() string {
	if v.Status == "valid" {
		return "valid " + v.Messages[0]
	}
	return v.Status + ": " + v.Messages[0]
}
func validateSteps(d *Domain, p *Problem, steps []Step) Validation {
	world := map[string]Atom{}
	for _, a := range p.Initial {
		world[a.Text()] = a
	}
	schemas := map[string]*Schema{}
	for _, s := range d.Actions {
		schemas[s.Name] = s
	}
	types := objectTypes(p)
	cost := 0
	for k, step := range steps {
		prefix := fmt.Sprintf("step %d %s: ", k+1, step.Text())
		schema := schemas[step.Name]
		if schema == nil {
			return Validation{"invalid", []string{prefix + "unknown action " + step.Name}, k}
		}
		expected := make([]string, len(schema.Parameters))
		for i, param := range schema.Parameters {
			expected[i] = param.Type
		}
		if reason := argumentCheck(d, step.Arguments, expected, types, "object"); reason != "" {
			return Validation{"invalid", []string{prefix + reason}, k}
		}
		assignment := map[string]string{}
		for i, param := range schema.Parameters {
			assignment[param.Name] = step.Arguments[i]
		}
		for _, condition := range schema.Conditions {
			a := substitute(condition.Atom, assignment)
			truth := false
			if a.Predicate == "=" {
				truth = a.Terms[0] == a.Terms[1]
			} else {
				_, truth = world[a.Text()]
			}
			if truth == condition.Negative {
				literal := Literal{a, condition.Negative}
				return Validation{"invalid", []string{prefix + "precondition " + literal.Text() + " is false"}, k}
			}
		}
		for _, e := range schema.Effects {
			if e.Negative {
				delete(world, substitute(e.Atom, assignment).Text())
			}
		}
		for _, e := range schema.Effects {
			if !e.Negative {
				a := substitute(e.Atom, assignment)
				world[a.Text()] = a
			}
		}
		cost += schema.Cost
	}
	messages := []string{}
	for _, a := range p.Goals {
		if _, ok := world[a.Text()]; !ok {
			messages = append(messages, "unsatisfied goal "+a.Text())
		}
	}
	if len(messages) > 0 {
		return Validation{"goal not reached", messages, len(steps)}
	}
	return Validation{"valid", []string{fmt.Sprintf("length=%d cost=%d", len(steps), cost)}, len(steps)}
}
func planSteps(g *GroundProblem, plan []int) []Step {
	out := make([]Step, len(plan))
	for i, a := range plan {
		out[i] = Step{g.Actions[a].Schema.Name, g.Actions[a].Arguments}
	}
	return out
}
func mapSteps(g *GroundProblem, steps []Step) []int {
	indices := map[string]int{}
	for i, a := range g.Actions {
		indices[a.Text()] = i
	}
	out := make([]int, len(steps))
	for i, s := range steps {
		out[i] = indices[s.Text()]
	}
	return out
}
func planCost(g *GroundProblem, plan []int) int {
	cost := 0
	for _, i := range plan {
		cost += g.Actions[i].Cost
	}
	return cost
}
func improve(g *GroundProblem, plan []int) []int {
	out := slices.Clone(plan)
	for at := 0; at < len(out); {
		s := g.Initial
		for _, i := range out[:at] {
			s = apply(g.Actions[i], s)
		}
		kept := slices.Clone(out[:at])
		for _, i := range out[at+1:] {
			if applicable(g.Actions[i], s) {
				s = apply(g.Actions[i], s)
				kept = append(kept, i)
			}
		}
		if goal(g, s) {
			out = kept
		} else {
			at++
		}
	}
	return out
}
func interfere(a, b *GroundAction) bool {
	return a.Del.Intersects(b.Pre.Union(b.Add)) || b.Del.Intersects(a.Pre.Union(a.Add)) || a.Add.Intersects(b.Neg) || b.Add.Intersects(a.Neg)
}
func parallelize(g *GroundProblem, plan []int) [][]int {
	layers := make([]int, len(plan))
	count := 0
	for j, index := range plan {
		a := g.Actions[index]
		layers[j] = 1
		for i, previous := range plan[:j] {
			b := g.Actions[previous]
			if b.Add.Intersects(a.Pre) || b.Del.Intersects(a.Neg) || interfere(a, b) {
				layers[j] = max(layers[j], layers[i]+1)
			}
		}
		count = max(count, layers[j])
	}
	out := make([][]int, count)
	for i, a := range plan {
		out[layers[i]-1] = append(out[layers[i]-1], a)
	}
	return out
}
func parallelValidation(g *GroundProblem, layers [][]int) string {
	s := g.Initial
	for k, layer := range layers {
		for i, index := range layer {
			a := g.Actions[index]
			if !applicable(a, s) {
				return fmt.Sprintf("invalid at layer %d", k+1)
			}
			for _, other := range layer[i+1:] {
				if interfere(a, g.Actions[other]) {
					return fmt.Sprintf("invalid at layer %d", k+1)
				}
			}
		}
		adds, deletes := State{}, State{}
		for _, index := range layer {
			a := g.Actions[index]
			adds = adds.Union(a.Add)
			deletes = deletes.Union(a.Del)
		}
		s = s.Without(deletes).Union(adds)
	}
	if goal(g, s) {
		return "valid"
	}
	return "goal not reached"
}

func transformedGraph(g *GroundProblem) ([]GraphElement, State, int) {
	negative := State{}
	for _, a := range g.Actions {
		negative = negative.Union(a.Neg)
	}
	complement := map[int]int{}
	for i, p := range negative.Numbers() {
		complement[p] = len(g.Facts) + i
	}
	initial := g.Initial
	for p, c := range complement {
		if !initial.Has(p) {
			initial.Put(c)
		}
	}
	actions := []GraphElement{}
	for i, a := range g.Actions {
		pre, add, del := a.Pre, a.Add, a.Del
		for _, p := range a.Neg.Numbers() {
			pre.Put(complement[p])
		}
		for _, p := range a.Del.Numbers() {
			if c, ok := complement[p]; ok {
				add.Put(c)
			}
		}
		for _, p := range a.Add.Numbers() {
			if c, ok := complement[p]; ok {
				del.Put(c)
			}
		}
		actions = append(actions, GraphElement{Action: i, Fact: -1, Pre: pre, Add: add, Del: del})
	}
	return actions, initial, len(complement)
}
func heuristicText(value int) string {
	if value == infinity {
		return "inf"
	}
	return strconv.Itoa(value)
}

var heuristicNames = []string{"goalcount", "hmax", "hadd", "ff", "lmcount"}

func heuristicValues(h *Heuristic) string {
	items := []string{}
	for _, name := range heuristicNames {
		items = append(items, name+"="+heuristicText(h.Value(name)))
	}
	return strings.Join(items, " ")
}
func actionTexts(g *GroundProblem, indices []int) []string {
	out := make([]string, len(indices))
	for i, a := range indices {
		out[i] = g.Actions[a].Text()
	}
	return out
}

type RunRecord struct {
	Settings SearchSettings
	Tag      string
	Result   *SearchResult
}
type ProblemResult struct {
	Ground  *GroundProblem
	Runs    []*RunRecord
	Graph   *GraphPlanResult
	Proof   *RunRecord
	Best    int
	Optimal string
	Solved  int
}
type Output struct {
	Plans, Graph, Validation, Comparison []string
	Validated, ValidPlans                int
}

func planBlock(g *GroundProblem, tag string, plan []int, seen map[string]string, output *Output) ([]string, []string) {
	line := fmt.Sprintf("plan: length=%d cost=%d", len(plan), planCost(g, plan))
	key := intList(plan, ",")
	if earlier, ok := seen[key]; ok {
		line += " (same as " + earlier + ")"
	} else {
		seen[key] = tag
	}
	out := []string{line}
	counts := map[string]int{}
	for k, index := range plan {
		a := g.Actions[index]
		counts[a.Schema.Name]++
		out = append(out, fmt.Sprintf("  %d %s", k+1, a.Text()))
	}
	items := []string{}
	for _, s := range g.Domain.Actions {
		if counts[s.Name] > 0 {
			items = append(items, fmt.Sprintf("%s=%d", s.Name, counts[s.Name]))
		}
	}
	out = append(out, heading("schemas:", items))
	layers := parallelize(g, plan)
	out = append(out, fmt.Sprintf("parallel: layers=%d", len(layers)))
	for k, layer := range layers {
		out = append(out, heading(fmt.Sprintf("  %d:", k+1), actionTexts(g, layer)))
	}
	improved := improve(g, plan)
	removed := len(plan) - len(improved)
	out = append(out, fmt.Sprintf("improved: length=%d cost=%d removed=%d", len(improved), planCost(g, improved), removed))
	if removed > 0 {
		for k, index := range improved {
			out = append(out, fmt.Sprintf("  %d %s", k+1, g.Actions[index].Text()))
		}
	}
	landmarks := g.Heuristics(g.Initial).Landmarks
	reached := State{}
	s := g.Initial
	for _, index := range plan {
		s = apply(g.Actions[index], s)
		for k := range reached {
			reached[k] |= s[k] & landmarks[k]
		}
	}
	out = append(out, fmt.Sprintf("landmarks reached: %d/%d", len(reached.Numbers()), len(landmarks.Numbers())))
	for _, p := range landmarks.Without(reached).Numbers() {
		out = append(out, "  missed "+g.Facts[p].Text())
	}
	originalValidation := validateSteps(g.Domain, g.Problem, planSteps(g, plan))
	improvedValidation := validateSteps(g.Domain, g.Problem, planSteps(g, improved))
	output.Validated++
	if originalValidation.Status == "valid" {
		output.ValidPlans++
	}
	validation := []string{tag + ": " + originalValidation.Verdict(), "  parallel: " + parallelValidation(g, layers), "  improved: " + improvedValidation.Verdict()}
	return out, validation
}
func profile(g *GroundProblem, proof *RunRecord) []string {
	plan := proof.Result.Plan
	out := []string{"-- profile (" + proof.Tag + ") --"}
	remaining := planCost(g, plan)
	s := g.Initial
	overestimates := make([]int, len(heuristicNames))
	for k := 0; k <= len(plan); k++ {
		h := g.Heuristics(s)
		out = append(out, fmt.Sprintf("  %d: h*=%d %s", k, remaining, heuristicValues(h)))
		for i, name := range heuristicNames {
			if h.Value(name) > remaining {
				overestimates[i]++
			}
		}
		if k < len(plan) {
			a := g.Actions[plan[k]]
			remaining -= a.Cost
			s = apply(a, s)
		}
	}
	counts := []string{}
	for i, name := range heuristicNames {
		counts = append(counts, fmt.Sprintf("%s=%d", name, overestimates[i]))
	}
	out = append(out, "overestimates: "+strings.Join(counts, " "), "-- causal links ("+proof.Tag+") --")
	supplier := make([]int, len(g.Facts))
	for k, index := range plan {
		a := g.Actions[index]
		items := []string{}
		for _, p := range a.Pre.Numbers() {
			items = append(items, fmt.Sprintf("%s<-%d", g.Facts[p].Text(), supplier[p]))
		}
		out = append(out, heading(fmt.Sprintf("  %d %s:", k+1, a.Text()), items))
		for _, p := range a.Add.Numbers() {
			supplier[p] = k + 1
		}
	}
	items := []string{}
	for _, p := range g.Goal.Numbers() {
		items = append(items, fmt.Sprintf("%s<-%d", g.Facts[p].Text(), supplier[p]))
	}
	return append(out, heading("  goal:", items))
}
func resultLine(r *SearchResult) string {
	if r.Status == "unreachable goal" {
		return "result: FAIL (unreachable goal)"
	}
	if r.Status == "solved" {
		return fmt.Sprintf("result: solved expanded=%d generated=%d", r.Expanded, r.Generated)
	}
	return fmt.Sprintf("result: FAIL (%s) expanded=%d generated=%d", r.Status, r.Expanded, r.Generated)
}
func processProblem(g *GroundProblem, settings Settings, out *Output) *ProblemResult {
	p := &ProblemResult{Ground: g, Best: -1, Optimal: "unknown"}
	out.Plans = append(out.Plans, "== problem "+g.Problem.Name+" ==")
	out.Graph = append(out.Graph, "== problem "+g.Problem.Name+" ==")
	out.Validation = append(out.Validation, "== problem "+g.Problem.Name+" ==")
	unreachable := len(g.Unreachable) > 0
	if unreachable {
		out.Plans = append(out.Plans, "initial h: unreachable goal")
	} else {
		h := g.Heuristics(g.Initial)
		out.Plans = append(out.Plans, "initial h: "+heuristicValues(h), fmt.Sprintf("landmarks: %d", len(h.Landmarks.Numbers())))
		for _, f := range h.Landmarks.Numbers() {
			out.Plans = append(out.Plans, "  "+g.Facts[f].Text())
		}
		out.Plans = append(out.Plans, fmt.Sprintf("relaxed plan: length=%d cost=%s", len(h.Relaxed), heuristicText(h.FF)))
		for _, a := range h.Relaxed {
			out.Plans = append(out.Plans, "  "+g.Actions[a].Text())
		}
		out.Plans = append(out.Plans, heading("helpful:", actionTexts(g, h.Helpful)))
	}
	for _, run := range settings.Runs {
		result := &SearchResult{Status: "unreachable goal"}
		if !unreachable {
			result = search(g, g.Initial, run, settings.Budget, settings.Weight)
		}
		record := &RunRecord{run, run.Tag(), result}
		p.Runs = append(p.Runs, record)
		if p.Proof == nil && result.Status == "solved" && (record.Tag == "ucs none" || record.Tag == "astar hmax") {
			p.Proof = record
		}
	}
	if unreachable {
		p.Graph = &GraphPlanResult{Status: "unreachable goal"}
		out.Graph = append(out.Graph, "result: FAIL (unreachable goal)")
	} else {
		actions, initial, count := transformedGraph(g)
		p.Graph = graphPlan(actions, initial, g.Goal, count, settings.LevelLimit)
		r := p.Graph
		out.Graph = append(out.Graph, fmt.Sprintf("complementary facts: %d", count))
		out.Graph = append(out.Graph, r.Logs...)
		if r.Status == "solved" {
			out.Graph = append(out.Graph, fmt.Sprintf("result: solved levels=%d length=%d cost=%d searched=%d memo_hits=%d tried=%d", len(r.Layers), len(r.Plan), planCost(g, r.Plan), r.Searched, r.MemoHits, r.Tried))
			for k, layer := range r.Layers {
				out.Graph = append(out.Graph, heading(fmt.Sprintf("layer %d:", k+1), actionTexts(g, layer)))
			}
		} else {
			out.Graph = append(out.Graph, fmt.Sprintf("result: FAIL (%s) searched=%d memo_hits=%d tried=%d", r.Status, r.Searched, r.MemoHits, r.Tried))
		}
	}
	gp := p.Graph
	p.Runs = append(p.Runs, &RunRecord{Settings: SearchSettings{"graphplan", "none"}, Tag: "graphplan", Result: &SearchResult{Status: gp.Status, Plan: gp.Plan, Expanded: gp.Searched, Generated: gp.Tried}})
	seen := map[string]string{}
	for _, record := range p.Runs {
		r := record.Result
		out.Plans = append(out.Plans, "-- "+record.Tag+" --", resultLine(r))
		length, cost := "-", "-"
		if r.Status == "solved" {
			p.Solved++
			value := planCost(g, r.Plan)
			if p.Best < 0 || value < p.Best {
				p.Best = value
			}
			length, cost = strconv.Itoa(len(r.Plan)), strconv.Itoa(value)
			block, validation := planBlock(g, record.Tag, r.Plan, seen, out)
			out.Plans = append(out.Plans, block...)
			out.Validation = append(out.Validation, validation...)
		}
		out.Comparison = append(out.Comparison, fmt.Sprintf("%s,%s,%s,%s,%s,%d,%d", g.Problem.Name, record.Settings.Algorithm, record.Settings.Heuristic, length, cost, r.Expanded, r.Generated))
	}
	if p.Proof != nil {
		p.Optimal = strconv.Itoa(planCost(g, p.Proof.Result.Plan))
		out.Plans = append(out.Plans, profile(g, p.Proof)...)
	} else {
		for _, record := range p.Runs {
			if slices.Contains([]string{"unreachable goal", "dead end", "exhausted", "unreachable"}, record.Result.Status) {
				p.Optimal = "none"
				break
			}
		}
	}
	out.Plans = append(out.Plans, "")
	out.Graph = append(out.Graph, "")
	out.Validation = append(out.Validation, "")
	return p
}
func bestText(value int) string {
	if value < 0 {
		return "-"
	}
	return strconv.Itoa(value)
}
func candidateLines(d *Domain, candidates []CandidatePlan, problems map[string]*ProblemResult, settings Settings) ([]string, int) {
	out := []string{"== candidates =="}
	validCount := 0
	for i, c := range candidates {
		p := problems[c.Problem]
		g := p.Ground
		v := validateSteps(d, g.Problem, c.Steps)
		base := fmt.Sprintf("candidate %d %s %s: ", i+1, c.Problem, c.Label)
		if v.Status == "valid" {
			validCount++
			plan := mapSteps(g, c.Steps)
			improved := improve(g, plan)
			out = append(out, base+v.Verdict(), fmt.Sprintf("  improved: length=%d cost=%d removed=%d best known=%s", len(improved), planCost(g, improved), len(c.Steps)-len(improved), bestText(p.Best)))
			continue
		}
		out = append(out, base+v.Status)
		for _, message := range v.Messages {
			out = append(out, "  "+message)
		}
		if len(g.Unreachable) > 0 {
			out = append(out, "  repair: FAIL (unreachable goal)")
			continue
		}
		prefix := mapSteps(g, c.Steps[:v.Correct])
		s := g.Initial
		for _, index := range prefix {
			s = apply(g.Actions[index], s)
		}
		repair := search(g, s, settings.Repair, settings.Budget, settings.Weight)
		if repair.Status != "solved" {
			out = append(out, "  repair: FAIL ("+repair.Status+")")
			continue
		}
		plan := append(slices.Clone(prefix), repair.Plan...)
		validation := validateSteps(d, g.Problem, planSteps(g, plan))
		out = append(out, fmt.Sprintf("  repair: kept=%d added=%d %s", len(prefix), len(repair.Plan), validation.Verdict()))
		for k, index := range plan {
			out = append(out, fmt.Sprintf("    %d %s", k+1, g.Actions[index].Text()))
		}
	}
	return out, validCount
}
func writeLines(name string, lines []string) {
	text := ""
	if len(lines) > 0 {
		text = strings.Join(lines, "\n") + "\n"
	}
	if e := os.WriteFile("output/"+name, []byte(text), 0644); e != nil {
		panic(e)
	}
}
func main() {
	d := readDomain()
	validateDomain(d)
	rawProblems := readProblems()
	settings := readSettings()
	candidates := readCandidates()
	grounding := domainLines(d)
	out := &Output{Comparison: []string{"problem,algorithm,heuristic,length,cost,expanded,generated"}}
	problems := []*ProblemResult{}
	byName := map[string]*ProblemResult{}
	for _, p := range rawProblems {
		validateProblem(d, p)
		g := ground(d, p)
		grounding = append(grounding, "")
		grounding = append(grounding, groundingLines(g)...)
		result := processProblem(g, settings, out)
		problems = append(problems, result)
		byName[p.Name] = result
	}
	out.Plans = append(out.Plans, "== summary ==")
	for _, p := range problems {
		out.Plans = append(out.Plans, fmt.Sprintf("%s: solved=%d/%d best=%s optimal=%s", p.Ground.Problem.Name, p.Solved, len(p.Runs), bestText(p.Best), p.Optimal))
	}
	for i, record := range problems[0].Runs {
		solved, best, expanded, generated := 0, 0, 0, 0
		for _, p := range problems {
			r := p.Runs[i].Result
			expanded += r.Expanded
			generated += r.Generated
			if r.Status == "solved" {
				solved++
				if planCost(p.Ground, r.Plan) == p.Best {
					best++
				}
			}
		}
		out.Plans = append(out.Plans, fmt.Sprintf("%s: solved=%d best=%d expanded=%d generated=%d", record.Tag, solved, best, expanded, generated))
	}
	candidateOutput, validCandidates := candidateLines(d, candidates, byName, settings)
	out.Validation = append(out.Validation, candidateOutput...)
	out.Validation = append(out.Validation, "", "== summary ==", fmt.Sprintf("plans: %d valid: %d", out.Validated, out.ValidPlans), fmt.Sprintf("candidates: %d valid: %d", len(candidates), validCandidates))
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	writeLines("grounding.txt", grounding)
	writeLines("plans.txt", out.Plans)
	writeLines("graphplan.txt", out.Graph)
	writeLines("validation.txt", out.Validation)
	writeLines("comparison.csv", out.Comparison)
}
