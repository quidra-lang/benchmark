package main

import (
	"fmt"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

var commands = []string{"SOLVE", "ENUM", "CORE", "QUEENS", "PIGEON", "COLOR", "CHROMATIC"}
var argumentTypes = map[string][]string{"SOLVE": {"file"}, "ENUM": {"file", "limit"}, "CORE": {"file"},
	"QUEENS": {"small", "limit"}, "PIGEON": {"small", "small", "limit"}, "COLOR": {"graph", "color",
		"limit"}, "CHROMATIC": {"graph", "color"}}
var namePattern = regexp.MustCompile(`^[a-z0-9_]{1,20}$`)

func abs(v int) int {
	if v < 0 {
		return -v
	}
	return v
}
func integer(text string) int {
	n, err := strconv.Atoi(text)
	if err != nil {
		panic(err)
	}
	return n
}
func readLines(path string) []string {
	data, err := os.ReadFile(path)
	if err != nil {
		panic(err)
	}
	if len(data) == 0 {
		return nil
	}
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
}
func contains(values []int, value int) bool {
	for _, v := range values {
		if v == value {
			return true
		}
	}
	return false
}

type Graph struct {
	Name     string
	Vertices int
	Edges    [][2]int
	Invalid  string
}

func loadGraphs() map[string]*Graph {
	graphs := map[string]*Graph{}
	var current *Graph
	for index, line := range readLines("input/graphs.txt") {
		if current == nil {
			if line == "" || strings.HasPrefix(line, "#") {
				continue
			}
			tokens := strings.Split(line, " ")
			current = &Graph{Name: tokens[1], Vertices: integer(tokens[2])}
			continue
		}
		if line == "END" {
			sort.Slice(current.Edges, func(i, j int) bool {
				a, b := current.Edges[i], current.Edges[j]
				if a[0] != b[0] {
					return a[0] < b[0]
				}
				return a[1] < b[1]
			})
			graphs[current.Name] = current
			current = nil
			continue
		}
		if current.Invalid != "" {
			continue
		}
		tokens := strings.Split(line, " ")
		reason := ""
		if len(tokens) != 2 || !validNumber(tokens[0]) || !validNumber(tokens[1]) {
			reason = "bad edge line"
		} else {
			a, b := integer(tokens[0]), integer(tokens[1])
			if a < 1 || a > current.Vertices || b < 1 || b > current.Vertices {
				reason = "vertex out of range"
			} else if a == b {
				reason = "self loop"
			} else {
				edge := [2]int{min(a, b), max(a, b)}
				duplicate := false
				for _, e := range current.Edges {
					if e == edge {
						duplicate = true
						break
					}
				}
				if duplicate {
					reason = "duplicate edge"
				} else {
					current.Edges = append(current.Edges, edge)
				}
			}
		}
		if reason != "" {
			current.Invalid = fmt.Sprintf("%s at line %d", reason, index+1)
		}
	}
	return graphs
}

type Solution struct {
	Formula                 Formula
	Models                  [][]bool
	Status, Stop            string
	Rounds, Removed, Colors int
	Trace                   []string
	Stats                   SearchStats
	Preparation             *Preparation
}
type ModelAnalysis struct {
	FailureModel, FailureClause                 int
	TrueDistribution, Safe, Diversity, Backbone []int
}
type Core struct {
	Clauses              []int
	Decisions, Conflicts int
}
type Job struct {
	Number                            int
	Text, Command, Error              string
	Args                              []string
	Graph                             *Graph
	Colors, Chromatic                 int
	Solution                          *Solution
	Attempts                          []*Solution
	Aggregate                         SearchStats
	AggregateRounds, AggregateRemoved int
	Analysis                          *ModelAnalysis
	Core                              *Core
}

func loadJobs() []*Job {
	jobs := []*Job{}
	for _, line := range readLines("input/jobs.txt") {
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		tokens := strings.Split(line, " ")
		jobs = append(jobs, &Job{Number: len(jobs) + 1, Text: line, Command: tokens[0], Args: tokens[1:]})
	}
	return jobs
}
func validateJob(j *Job, graphs map[string]*Graph) string {
	types, ok := argumentTypes[j.Command]
	if !ok {
		return "unknown command " + j.Command
	}
	if len(j.Args) != len(types) {
		return "wrong argument count"
	}
	for i, kind := range types {
		argument := j.Args[i]
		switch kind {
		case "file":
			if !strings.HasSuffix(argument, ".cnf") || !namePattern.MatchString(strings.TrimSuffix(argument, ".cnf")) {
				return "bad file name " + argument
			}
		case "graph":
			g := graphs[argument]
			if g == nil {
				return "unknown graph " + argument
			}
			if g.Invalid != "" {
				return "invalid graph " + argument + ": " + g.Invalid
			}
		default:
			if !validNumber(argument) {
				return "bad number " + argument
			}
			n := integer(argument)
			maximum := map[string]int{"small": 8, "color": 6, "limit": 200}[kind]
			if n < 1 || n > maximum {
				return "out of range " + argument
			}
		}
	}
	return ""
}
func greedyColoring(g *Graph) []int {
	degree := make([]int, g.Vertices+1)
	neighbors := make([][]int, g.Vertices+1)
	for _, e := range g.Edges {
		a, b := e[0], e[1]
		degree[a]++
		degree[b]++
		neighbors[a] = append(neighbors[a], b)
		neighbors[b] = append(neighbors[b], a)
	}
	order := make([]int, g.Vertices)
	for i := range order {
		order[i] = i + 1
	}
	sort.Slice(order, func(i, j int) bool {
		a, b := order[i], order[j]
		if degree[a] != degree[b] {
			return degree[a] > degree[b]
		}
		return a < b
	})
	colors := make([]int, g.Vertices+1)
	for _, v := range order {
		used := map[int]bool{}
		for _, n := range neighbors[v] {
			if colors[n] > 0 {
				used[colors[n]] = true
			}
		}
		c := 1
		for used[c] {
			c++
		}
		colors[v] = c
	}
	return colors[1:]
}
func solveFormula(f Formula, limit int) *Solution {
	prep := preprocess(f, limit == 1)
	s := &Solution{Formula: f, Preparation: prep, Removed: prep.Counts["removed"], Stop: "limit"}
	blocking := [][]int{}
	if prep.EmptyClause > 0 {
		s.Stop = "preprocess"
	} else {
		for len(s.Models) < limit {
			s.Rounds++
			search := append(append([][]int(nil), prep.Clauses...), blocking...)
			model, events, stats := runRound(f.Variables, search)
			if s.Rounds == 1 {
				s.Trace = events
			}
			s.Stats.Add(stats)
			if model == nil {
				s.Stop = "all"
				break
			}
			for v, value := range prep.Fixed {
				model[v] = value
			}
			s.Models = append(s.Models, model)
			clause := []int{}
			for _, v := range prep.Active {
				literal := v
				if model[v] {
					literal = -v
				}
				clause = append(clause, literal)
			}
			blocking = append(blocking, clause)
		}
	}
	s.Status = "UNSAT"
	if len(s.Models) > 0 {
		s.Status = "SAT"
	}
	return s
}
func trueLiteral(model []bool, literal int) bool {
	if literal > 0 {
		return model[literal]
	}
	return !model[-literal]
}
func satisfies(model []bool, clauses [][]int) bool {
	for _, c := range clauses {
		satisfied := false
		for _, lit := range c {
			if trueLiteral(model, lit) {
				satisfied = true
				break
			}
		}
		if !satisfied {
			return false
		}
	}
	return true
}
func analyzeModels(s *Solution) *ModelAnalysis {
	if len(s.Models) == 0 {
		return nil
	}
	a := &ModelAnalysis{}
	for mi, m := range s.Models {
		for ci, c := range s.Formula.Clauses {
			satisfied := false
			for _, lit := range c {
				if trueLiteral(m, lit) {
					satisfied = true
					break
				}
			}
			if !satisfied {
				a.FailureModel, a.FailureClause = mi+1, ci+1
				break
			}
		}
		if a.FailureModel > 0 {
			break
		}
	}
	first := s.Models[0]
	for _, c := range s.Formula.Clauses {
		count := 0
		for _, lit := range c {
			if trueLiteral(first, lit) {
				count++
			}
		}
		a.TrueDistribution = append(a.TrueDistribution, count)
	}
	for v := 1; v <= s.Formula.Variables; v++ {
		inverted := append([]bool(nil), first...)
		inverted[v] = !inverted[v]
		if satisfies(inverted, s.Formula.Clauses) {
			a.Safe = append(a.Safe, v)
		}
	}
	for i, m := range s.Models {
		for _, other := range s.Models[i+1:] {
			distance := 0
			for v := 1; v <= s.Formula.Variables; v++ {
				if m[v] != other[v] {
					distance++
				}
			}
			a.Diversity = append(a.Diversity, distance)
		}
	}
	for v := 1; v <= s.Formula.Variables; v++ {
		same := true
		for _, m := range s.Models {
			if m[v] != first[v] {
				same = false
				break
			}
		}
		if same {
			literal := v
			if !first[v] {
				literal = -v
			}
			a.Backbone = append(a.Backbone, literal)
		}
	}
	return a
}
func unsatCore(f Formula) *Core {
	remaining := make([]bool, len(f.Clauses))
	for i := range remaining {
		remaining[i] = true
	}
	core := &Core{}
	for remove := range f.Clauses {
		clauses := [][]int{}
		for i, c := range f.Clauses {
			if remaining[i] && i != remove {
				clauses = append(clauses, c)
			}
		}
		test := solveFormula(Formula{f.Variables, clauses}, 1)
		core.Decisions += test.Stats.Decisions
		core.Conflicts += test.Stats.Conflicts
		if test.Status == "UNSAT" {
			remaining[remove] = false
		}
	}
	for i, keep := range remaining {
		if keep {
			core.Clauses = append(core.Clauses, i+1)
		}
	}
	return core
}
func executeJobs(jobs []*Job, graphs map[string]*Graph) {
	for _, j := range jobs {
		j.Error = validateJob(j, graphs)
		if j.Error != "" {
			continue
		}
		args := j.Args
		if j.Command == "CHROMATIC" {
			j.Graph = graphs[args[0]]
			for colors := 1; colors <= integer(args[1]); colors++ {
				s := solveFormula(coloring(j.Graph, colors), 1)
				s.Colors = colors
				j.Attempts = append(j.Attempts, s)
				j.Aggregate.Add(s.Stats)
				j.AggregateRounds += s.Rounds
				j.AggregateRemoved += s.Removed
				j.Solution = s
				j.Colors = colors
				if s.Status == "SAT" {
					j.Chromatic = colors
					break
				}
			}
		} else {
			var f Formula
			limit := 1
			switch j.Command {
			case "SOLVE", "ENUM", "CORE":
				f, j.Error = readDimacs(args[0])
				if j.Command == "ENUM" {
					limit = integer(args[1])
				}
			case "QUEENS":
				f = queens(integer(args[0]))
				limit = integer(args[1])
			case "PIGEON":
				f = pigeon(integer(args[0]), integer(args[1]))
				limit = integer(args[2])
			case "COLOR":
				j.Graph = graphs[args[0]]
				j.Colors = integer(args[1])
				f = coloring(j.Graph, j.Colors)
				limit = integer(args[2])
			}
			if j.Error != "" {
				continue
			}
			s := solveFormula(f, limit)
			j.Solution = s
			j.Aggregate = s.Stats
			j.AggregateRounds = s.Rounds
			j.AggregateRemoved = s.Removed
			if j.Command == "CORE" && s.Status == "UNSAT" {
				j.Core = unsatCore(f)
			}
		}
		j.Analysis = analyzeModels(j.Solution)
	}
}
func sum(values []int) int {
	total := 0
	for _, v := range values {
		total += v
	}
	return total
}
func formulaSummary(f Formula) string {
	lengths := []int{}
	for _, c := range f.Clauses {
		lengths = append(lengths, len(c))
	}
	return fmt.Sprintf("variables=%d clauses=%d literals=%d lengths=%s", f.Variables, len(f.Clauses), sum(lengths), frequency(lengths))
}
func graphSummary(g *Graph) string {
	degrees := make([]int, g.Vertices+1)
	for _, e := range g.Edges {
		degrees[e[0]]++
		degrees[e[1]]++
	}
	maxDegree := 0
	for _, d := range degrees {
		maxDegree = max(maxDegree, d)
	}
	greedy := greedyColoring(g)
	used := 0
	for _, c := range greedy {
		used = max(used, c)
	}
	return fmt.Sprintf("vertices=%d edges=%d max_degree=%d greedy=%d", g.Vertices, len(g.Edges), maxDegree, used)
}
func preprocessingReport(p *Preparation) []string {
	c, r := p.Counts, p.Records
	pure := "off"
	if p.Pure {
		pure = "on"
	}
	lines := []string{fmt.Sprintf("preprocess pure=%s tautologies=%d duplicate_literals=%d unit_fixed=%d unit_removed=%d subsumed=%d pure_fixed=%d pure_removed=%d removed=%d",
		pure, c["tautologies"], c["duplicate_literals"], c["unit_fixed"], c["unit_removed"], c["subsumed"],
		c["pure_fixed"], c["pure_removed"], c["removed"]), fmt.Sprintf("removed_clauses tautology=%s unit=%s subsumed=%s pure=%s",
		numberList(r["tautology"]), numberList(r["unit"]), numberList(r["subsumed"]), numberList(r["pure"]))}
	if p.EmptyClause > 0 {
		return append(lines, fmt.Sprintf("simplified empty_clause=%d", p.EmptyClause))
	}
	lengths := []int{}
	for _, c := range p.Clauses {
		lengths = append(lengths, len(c))
	}
	lines = append(lines, fmt.Sprintf("simplified clauses=%d literals=%d lengths=%s fixed=%d active=%d",
		len(p.Clauses), sum(lengths), frequency(lengths), len(p.Fixed), len(p.Active)))
	variables := []int{}
	for v := range p.Fixed {
		variables = append(variables, v)
	}
	sort.Ints(variables)
	for i, v := range variables {
		if !p.Fixed[v] {
			variables[i] = -v
		}
	}
	return append(lines, "fixed literals="+numberList(variables))
}
func searchReport(s SearchStats) string {
	return "search " + named(NamedValue{"decisions", s.Decisions}, NamedValue{"propagations", s.Propagations},
		NamedValue{"conflicts", s.Conflicts}, NamedValue{"max_depth", s.MaxDepth})
}
func verificationReport(s *Solution, a *ModelAnalysis) []string {
	if a == nil {
		return nil
	}
	if a.FailureModel > 0 {
		return []string{fmt.Sprintf("verify failed model=%d clause=%d", a.FailureModel, a.FailureClause)}
	}
	return []string{fmt.Sprintf("verify ok models=%d clauses=%d true_literals=%s", len(s.Models), len(s.Formula.Clauses), frequency(a.TrueDistribution))}
}
func safeFlipReport(a *ModelAnalysis) string {
	return fmt.Sprintf("flips safe=%d variables=%s", len(a.Safe), numberList(a.Safe))
}
func analysisReport(s *Solution, a *ModelAnalysis) []string {
	if a == nil {
		return nil
	}
	lines := []string{safeFlipReport(a)}
	if len(a.Diversity) > 0 {
		lo, hi := a.Diversity[0], a.Diversity[0]
		for _, v := range a.Diversity {
			lo = min(lo, v)
			hi = max(hi, v)
		}
		lines = append(lines, fmt.Sprintf("diversity pairs=%d min_distance=%d max_distance=%d", len(a.Diversity), lo, hi))
	}
	if s.Stop == "all" {
		lines = append(lines, fmt.Sprintf("backbone size=%d literals=%s", len(a.Backbone), numberList(a.Backbone)))
	}
	return lines
}
func traceReport(events []string) string {
	if len(events) == 0 {
		return "trace -"
	}
	count := min(12, len(events))
	text := "trace " + strings.Join(events[:count], " ")
	if len(events) > count {
		text += fmt.Sprintf(" +%d", len(events)-count)
	}
	return text
}
func standardResult(j *Job) []string {
	s := j.Solution
	lines := []string{heading(j)}
	if j.Command == "COLOR" {
		lines = append(lines, "graph "+graphSummary(j.Graph))
	}
	lines = append(lines, "formula "+formulaSummary(s.Formula))
	lines = append(lines, preprocessingReport(s.Preparation)...)
	lines = append(lines, fmt.Sprintf("result %s models=%d rounds=%d stop=%s", s.Status, len(s.Models), s.Rounds, s.Stop), searchReport(s.Stats))
	if s.Rounds > 0 {
		lines = append(lines, traceReport(s.Trace))
	}
	lines = append(lines, verificationReport(s, j.Analysis)...)
	lines = append(lines, analysisReport(s, j.Analysis)...)
	if c := j.Core; c != nil {
		lines = append(lines, fmt.Sprintf("core size=%d decisions=%d conflicts=%d clauses=%s", len(c.Clauses), c.Decisions, c.Conflicts, numberList(c.Clauses)))
	}
	return lines
}
func chromaticResult(j *Job) []string {
	lines := []string{heading(j), "graph " + graphSummary(j.Graph)}
	for _, s := range j.Attempts {
		c := s.Stats
		lines = append(lines, fmt.Sprintf("attempt k=%d clauses=%d removed=%d result=%s stop=%s decisions=%d propagations=%d conflicts=%d max_depth=%d",
			s.Colors, len(s.Formula.Clauses), s.Removed, s.Status, s.Stop, c.Decisions, c.Propagations,
			c.Conflicts, c.MaxDepth))
	}
	chromatic := "-"
	if j.Chromatic > 0 {
		chromatic = fmt.Sprint(j.Chromatic)
	}
	lines = append(lines, fmt.Sprintf("result %s chromatic=%s attempts=%d", j.Solution.Status, chromatic, len(j.Attempts)), searchReport(j.Aggregate))
	if j.Solution.Status == "SAT" {
		lines = append(lines, verificationReport(j.Solution, j.Analysis)...)
		lines = append(lines, safeFlipReport(j.Analysis))
	}
	return lines
}
func validJobs(jobs []*Job) []*Job {
	valid := []*Job{}
	for _, j := range jobs {
		if j.Error == "" {
			valid = append(valid, j)
		}
	}
	return valid
}
func resultsSummary(jobs []*Job) []string {
	valid := validJobs(jobs)
	sat, models, rounds, removed := 0, 0, 0, 0
	totals := SearchStats{}
	for _, j := range valid {
		if j.Solution.Status == "SAT" {
			sat++
		}
		models += len(j.Solution.Models)
		rounds += j.AggregateRounds
		removed += j.AggregateRemoved
		totals.Add(j.Aggregate)
	}
	lines := []string{fmt.Sprintf("SUMMARY jobs=%d sat=%d unsat=%d error=%d", len(jobs), sat, len(valid)-sat,
		len(jobs)-len(valid)), fmt.Sprintf("totals models=%d rounds=%d decisions=%d propagations=%d conflicts=%d removed_clauses=%d",
		models, rounds, totals.Decisions, totals.Propagations, totals.Conflicts, removed)}
	for _, command := range commands {
		count, sat := 0, 0
		counters := SearchStats{}
		for _, j := range valid {
			if j.Command == command {
				count++
				if j.Solution.Status == "SAT" {
					sat++
				}
				counters.Add(j.Aggregate)
			}
		}
		if count > 0 {
			lines = append(lines, fmt.Sprintf("command %s jobs=%d sat=%d unsat=%d decisions=%d propagations=%d conflicts=%d",
				command, count, sat, count-sat, counters.Decisions, counters.Propagations, counters.Conflicts))
		}
	}
	if len(valid) > 0 {
		for _, kind := range []string{"hardest", "deepest", "busiest"} {
			key := "conflicts"
			value := func(j *Job) int { return j.Aggregate.Conflicts }
			if kind == "deepest" {
				key = "max_depth"
				value = func(j *Job) int { return j.Aggregate.MaxDepth }
			} else if kind == "busiest" {
				key = "propagations"
				value = func(j *Job) int { return j.Aggregate.Propagations }
			}
			best := valid[0]
			for _, j := range valid[1:] {
				if value(j) > value(best) {
					best = j
				}
			}
			lines = append(lines, fmt.Sprintf("%s job=%d %s=%d", kind, best.Number, key, value(best)))
		}
	}
	return lines
}
func resultParagraphs(jobs []*Job) [][]string {
	paragraphs := [][]string{}
	for _, j := range jobs {
		if j.Error != "" {
			paragraphs = append(paragraphs, []string{heading(j), "error " + j.Error})
		} else if j.Command == "CHROMATIC" {
			paragraphs = append(paragraphs, chromaticResult(j))
		} else {
			paragraphs = append(paragraphs, standardResult(j))
		}
	}
	return append(paragraphs, resultsSummary(jobs))
}
func modelParagraphs(jobs []*Job) [][]string {
	paragraphs := [][]string{}
	for _, j := range validJobs(jobs) {
		if len(j.Solution.Models) == 0 {
			continue
		}
		lines := []string{heading(j)}
		for i, model := range j.Solution.Models {
			lines = append(lines, fmt.Sprintf("model %d", i+1))
			lines = append(lines, modelLines(model)...)
		}
		paragraphs = append(paragraphs, lines)
	}
	return paragraphs
}
func sequenceLess(a, b []int) bool {
	for i, v := range a {
		if v != b[i] {
			return v < b[i]
		}
	}
	return false
}
func queensCanonical(columns []int) ([]int, int) {
	n := len(columns)
	variants := make([][]int, 8)
	for i := range variants {
		variants[i] = make([]int, n)
	}
	for row, col := range columns {
		r, c := row+1, col
		transforms := [][2]int{{r, c}, {c, n + 1 - r}, {n + 1 - r, n + 1 - c}, {n + 1 - c, r}, {r, n + 1 - c}, {n + 1 - r, c}, {c, r}, {n + 1 - c, n + 1 - r}}
		for i, p := range transforms {
			variants[i][p[0]-1] = p[1]
		}
	}
	best := variants[0]
	distinct := map[string]bool{}
	for _, v := range variants {
		distinct[numberList(v)] = true
		if sequenceLess(v, best) {
			best = v
		}
	}
	return best, len(distinct)
}
func canonicalColoring(colors []int) []int {
	numbers := map[int]int{}
	result := []int{}
	for _, c := range colors {
		if numbers[c] == 0 {
			numbers[c] = len(numbers) + 1
		}
		result = append(result, numbers[c])
	}
	return result
}

type ModelClass struct {
	Number, First, Found, Orbit int
	Canonical                   []int
}
type ClassifiedModel struct {
	Value []int
	Group *ModelClass
	First bool
}

func classesForModels(columns [][]int, queen bool) ([]ClassifiedModel, []*ModelClass) {
	table := map[string]*ModelClass{}
	classes := []*ModelClass{}
	assignments := []ClassifiedModel{}
	for i, value := range columns {
		canonical, orbit := canonicalColoring(value), 0
		if queen {
			canonical, orbit = queensCanonical(value)
		}
		key := numberList(canonical)
		group := table[key]
		if group == nil {
			group = &ModelClass{Number: len(classes) + 1, First: i + 1, Canonical: canonical, Orbit: orbit}
			table[key] = group
			classes = append(classes, group)
		}
		group.Found++
		assignments = append(assignments, ClassifiedModel{value, group, i+1 == group.First})
	}
	return assignments, classes
}
func queensBoards(j *Job) []string {
	n := integer(j.Args[0])
	columns := [][]int{}
	for _, model := range j.Solution.Models {
		columns = append(columns, positions(model, n, n))
	}
	assignments, classes := classesForModels(columns, true)
	lines := []string{fmt.Sprintf("QUEENS job=%d n=%d", j.Number, n)}
	for i, a := range assignments {
		lines = append(lines, fmt.Sprintf("solution %d columns=%s class=%d", i+1, numberList(a.Value), a.Group.Number))
		if a.First {
			lines = append(lines, queensBoard(a.Value)...)
		}
	}
	for _, g := range classes {
		lines = append(lines, fmt.Sprintf("class %d orbit=%d found=%d first=%d canonical=%s", g.Number, g.Orbit, g.Found, g.First, numberList(g.Canonical)))
	}
	return append(lines, fmt.Sprintf("summary solutions=%d stop=%s classes=%d", len(j.Solution.Models), j.Solution.Stop, len(classes)))
}
func pigeonBoards(j *Job) []string {
	p, h := integer(j.Args[0]), integer(j.Args[1])
	lines := []string{fmt.Sprintf("PIGEON job=%d pigeons=%d holes=%d", j.Number, p, h)}
	for i, model := range j.Solution.Models {
		places := positions(model, p, h)
		empty := []int{}
		for hole := 1; hole <= h; hole++ {
			if !contains(places, hole) {
				empty = append(empty, hole)
			}
		}
		lines = append(lines, fmt.Sprintf("assignment %d holes=%s empty=%s", i+1, numberList(places), numberList(empty)))
	}
	expected := 1
	if p > h {
		expected = 0
	} else {
		for v := h; v > h-p; v-- {
			expected *= v
		}
	}
	return append(lines, fmt.Sprintf("summary assignments=%d stop=%s expected=%d", len(j.Solution.Models), j.Solution.Stop, expected))
}
func coloringBoards(j *Job) []string {
	g, k := j.Graph, j.Colors
	decoded := [][]int{}
	for _, model := range j.Solution.Models {
		decoded = append(decoded, positions(model, g.Vertices, k))
	}
	assignments, classes := classesForModels(decoded, false)
	lines := []string{fmt.Sprintf("%s job=%d graph=%s vertices=%d edges=%d colors=%d", j.Command, j.Number, g.Name, g.Vertices, len(g.Edges), k)}
	greedy := greedyColoring(g)
	used := 0
	for _, c := range greedy {
		used = max(used, c)
	}
	lines = append(lines, fmt.Sprintf("greedy used=%d colors=%s", used, numberList(greedy)))
	for i, a := range assignments {
		sizes := make([]int, k)
		distinct := map[int]bool{}
		for _, c := range a.Value {
			sizes[c-1]++
			distinct[c] = true
		}
		lines = append(lines, fmt.Sprintf("coloring %d colors=%s used=%d sizes=%s class=%d", i+1, numberList(a.Value),
			len(distinct), numberList(sizes), a.Group.Number))
	}
	for _, g := range classes {
		lines = append(lines, fmt.Sprintf("class %d found=%d first=%d canonical=%s", g.Number, g.Found, g.First, numberList(g.Canonical)))
	}
	return append(lines, fmt.Sprintf("summary colorings=%d stop=%s classes=%d", len(j.Solution.Models), j.Solution.Stop, len(classes)))
}
func boardsParagraphs(jobs []*Job) [][]string {
	paragraphs := [][]string{}
	for _, j := range validJobs(jobs) {
		switch j.Command {
		case "QUEENS":
			paragraphs = append(paragraphs, queensBoards(j))
		case "PIGEON":
			paragraphs = append(paragraphs, pigeonBoards(j))
		case "COLOR", "CHROMATIC":
			paragraphs = append(paragraphs, coloringBoards(j))
		}
	}
	return paragraphs
}
func statsLines(jobs []*Job) []string {
	lines := []string{"job,command,status,variables,clauses,removed_clauses,decisions,propagations,conflicts,max_depth,models,rounds"}
	for _, j := range validJobs(jobs) {
		s, c := j.Solution, j.Aggregate
		lines = append(lines, fmt.Sprintf("%d,%s,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d", j.Number, j.Command, s.Status,
			s.Formula.Variables, len(s.Formula.Clauses), j.AggregateRemoved, c.Decisions, c.Propagations,
			c.Conflicts, c.MaxDepth, len(s.Models), j.AggregateRounds))
	}
	return lines
}
func main() {
	graphs, jobs := loadGraphs(), loadJobs()
	executeJobs(jobs, graphs)
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	saveParagraphs("results.txt", resultParagraphs(jobs))
	saveParagraphs("models.txt", modelParagraphs(jobs))
	saveParagraphs("boards.txt", boardsParagraphs(jobs))
	saveLines("stats.csv", statsLines(jobs))
}
