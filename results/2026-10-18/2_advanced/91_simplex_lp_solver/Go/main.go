package main

import (
	"fmt"
	"os"
	"strings"
)

type Model struct {
	Name, Direction string
	Variables       []string
	Cost            []Fraction
	Constraints     []Constraint
	Lower, Upper    []*Fraction
	Integer         []bool
	Err             *ModelError
}

func makeModel(raw RawModel) *Model {
	m := &Model{Name: raw.Name, Direction: raw.Direction, Constraints: raw.Constraints, Err: raw.Err}
	if m.Err != nil {
		return m
	}
	index := map[string]int{}
	register := func(terms []Term) {
		for _, term := range terms {
			if _, exists := index[term.Name]; !exists {
				index[term.Name] = len(m.Variables)
				m.Variables = append(m.Variables, term.Name)
			}
		}
	}
	register(raw.Objective)
	for _, c := range m.Constraints {
		register(c.Terms)
	}
	n := len(m.Variables)
	m.Cost = make([]Fraction, n)
	m.Lower = make([]*Fraction, n)
	m.Upper = make([]*Fraction, n)
	m.Integer = make([]bool, n)
	for j := range m.Lower {
		m.Lower[j] = finite(integer(0))
	}
	for _, term := range raw.Objective {
		j := index[term.Name]
		m.Cost[j] = m.Cost[j].add(term.Coefficient)
	}
	for i := range m.Constraints {
		c := &m.Constraints[i]
		c.Coefficients = make([]Fraction, n)
		for _, term := range c.Terms {
			j := index[term.Name]
			c.Coefficients[j] = c.Coefficients[j].add(term.Coefficient)
		}
	}
	seen := map[string]bool{}
	for _, c := range m.Constraints {
		if seen[c.Name] {
			m.Err = &ModelError{c.Line, "duplicate constraint " + c.Name}
			return m
		}
		seen[c.Name] = true
	}
	inconsistent := func(j int) bool { return m.Lower[j] != nil && m.Upper[j] != nil && m.Lower[j].cmp(*m.Upper[j]) > 0 }
	for _, b := range raw.Bounds {
		j, ok := index[b.Name]
		if !ok {
			m.Err = &ModelError{b.Line, "unknown variable " + b.Name}
			return m
		}
		if b.Kind == "lower" || b.Kind == "both" {
			m.Lower[j] = b.Lower
		}
		if b.Kind == "upper" || b.Kind == "both" {
			m.Upper[j] = b.Upper
		}
		if inconsistent(j) {
			m.Err = &ModelError{b.Line, "inconsistent bounds " + b.Name}
			return m
		}
	}
	for _, d := range raw.Integers {
		for _, name := range d.Names {
			j, ok := index[name]
			if !ok {
				m.Err = &ModelError{d.Line, "unknown variable " + name}
				return m
			}
			m.Integer[j] = true
			if m.Lower[j] != nil {
				m.Lower[j] = finite(integer(m.Lower[j].ceil()))
			}
			if m.Upper[j] != nil {
				m.Upper[j] = finite(integer(m.Upper[j].floor()))
			}
			if inconsistent(j) {
				m.Err = &ModelError{d.Line, "inconsistent bounds " + name}
				return m
			}
		}
	}
	for _, d := range raw.Binaries {
		for _, name := range d.Names {
			j, ok := index[name]
			if !ok {
				m.Err = &ModelError{d.Line, "unknown variable " + name}
				return m
			}
			m.Integer[j] = true
			m.Lower[j] = finite(integer(0))
			m.Upper[j] = finite(integer(1))
		}
	}
	return m
}
func integerCount(m *Model) int {
	count := 0
	for _, required := range m.Integer {
		if required {
			count++
		}
	}
	return count
}

type VariableMap struct {
	Kind     string
	Offset   Fraction
	Columns  []int
	UpperRow int
}
type Standard struct {
	Columns, Rows, Comparisons                        []string
	ColumnVariable, Directions, Sigma, Initial, Slack []int
	Artificial                                        []bool
	Costs1, Costs2                                    []Fraction
	Maps                                              []VariableMap
	Constant                                          Fraction
	Sign                                              int
	Tableau                                           *Tableau
}

func standardForm(m *Model, lower, upper []*Fraction) *Standard {
	s := &Standard{Sign: 1}
	if m.Direction == "maximize" {
		s.Sign = -1
	}
	addVariableColumn := func(name string, j, direction int) int {
		index := len(s.Columns)
		s.Columns = append(s.Columns, name)
		s.ColumnVariable = append(s.ColumnVariable, j)
		s.Directions = append(s.Directions, direction)
		return index
	}
	for j, name := range m.Variables {
		mapping := VariableMap{UpperRow: -1}
		if lower[j] != nil {
			mapping.Kind = "shift"
			mapping.Offset = *lower[j]
			mapping.Columns = []int{addVariableColumn(name, j, 1)}
		} else if upper[j] != nil {
			mapping.Kind = "reflect"
			mapping.Offset = *upper[j]
			mapping.Columns = []int{addVariableColumn(name+"'", j, -1)}
		} else {
			mapping.Kind = "split"
			mapping.Columns = []int{addVariableColumn(name+"+", j, 1), addVariableColumn(name+"-", j, -1)}
		}
		s.Constant = s.Constant.add(m.Cost[j].mul(mapping.Offset))
		s.Maps = append(s.Maps, mapping)
	}
	decisionColumns := len(s.Columns)
	tableau := &Tableau{}
	for _, c := range m.Constraints {
		row := make([]Fraction, decisionColumns)
		rhs := c.RHS
		for j, mapping := range s.Maps {
			rhs = rhs.sub(c.Coefficients[j].mul(mapping.Offset))
			for _, k := range mapping.Columns {
				row[k] = c.Coefficients[j].mul(integer(int64(s.Directions[k])))
			}
		}
		tableau.T = append(tableau.T, row)
		tableau.Beta = append(tableau.Beta, rhs)
		s.Rows = append(s.Rows, c.Name)
		s.Comparisons = append(s.Comparisons, c.Comparison)
	}
	for j, mapping := range s.Maps {
		if mapping.Kind == "shift" && upper[j] != nil {
			row := make([]Fraction, decisionColumns)
			row[mapping.Columns[0]] = integer(1)
			s.Maps[j].UpperRow = len(s.Rows)
			s.Rows = append(s.Rows, m.Variables[j]+".ub")
			s.Comparisons = append(s.Comparisons, "<=")
			tableau.T = append(tableau.T, row)
			tableau.Beta = append(tableau.Beta, upper[j].sub(*lower[j]))
		}
	}
	for i := range s.Rows {
		sigma := 1
		if tableau.Beta[i].N < 0 {
			sigma = -1
			tableau.Beta[i] = tableau.Beta[i].neg()
			for k := range tableau.T[i] {
				tableau.T[i][k] = tableau.T[i][k].neg()
			}
			if s.Comparisons[i] == "<=" {
				s.Comparisons[i] = ">="
			} else if s.Comparisons[i] == ">=" {
				s.Comparisons[i] = "<="
			}
		}
		s.Sigma = append(s.Sigma, sigma)
		s.Slack = append(s.Slack, -1)
		s.Initial = append(s.Initial, -1)
	}
	addExtra := func(name string, row int, value Fraction, artificial bool) int {
		k := len(s.Columns)
		s.Columns = append(s.Columns, name)
		s.ColumnVariable = append(s.ColumnVariable, -1)
		s.Directions = append(s.Directions, 0)
		for i := range tableau.T {
			tableau.T[i] = append(tableau.T[i], integer(0))
		}
		tableau.T[row][k] = value
		s.Artificial = append(s.Artificial, artificial)
		return k
	}
	s.Artificial = make([]bool, decisionColumns)
	for i, comparison := range s.Comparisons {
		if comparison != "=" {
			value := integer(1)
			if comparison == ">=" {
				value = integer(-1)
			}
			s.Slack[i] = addExtra("s:"+s.Rows[i], i, value, false)
			if comparison == "<=" {
				s.Initial[i] = s.Slack[i]
			}
		}
	}
	for i, comparison := range s.Comparisons {
		if comparison != "<=" {
			s.Initial[i] = addExtra("a:"+s.Rows[i], i, integer(1), true)
		}
	}
	s.Costs1 = make([]Fraction, len(s.Columns))
	s.Costs2 = make([]Fraction, len(s.Columns))
	for k, j := range s.ColumnVariable {
		if j >= 0 {
			s.Costs2[k] = m.Cost[j].mul(integer(int64(s.Sign * s.Directions[k])))
		}
		if s.Artificial[k] {
			s.Costs1[k] = integer(1)
		}
	}
	tableau.Basis = append([]int{}, s.Initial...)
	s.Tableau = tableau
	return s
}

type LPResult struct {
	Status                            string
	Objective, W                      Fraction
	Standard                          *Standard
	Solution, Farkas, Ray             []Fraction
	Rate                              Fraction
	Phase1, Phase2, Drives, Redundant int
	Log                               []string
}

func (r *LPResult) pivots() int { return r.Phase1 + r.Phase2 + r.Drives }
func (s *Standard) originalValues(columns []Fraction, direction bool) []Fraction {
	values := make([]Fraction, len(s.Maps))
	for j, mapping := range s.Maps {
		if !direction {
			values[j] = mapping.Offset
		}
		for _, k := range mapping.Columns {
			values[j] = values[j].add(columns[k].mul(integer(int64(s.Directions[k]))))
		}
	}
	return values
}
func (s *Standard) solution() []Fraction {
	columns := make([]Fraction, len(s.Columns))
	for i, k := range s.Tableau.Basis {
		columns[k] = s.Tableau.Beta[i]
	}
	return s.originalValues(columns, false)
}
func solveLP(m *Model, lower, upper []*Fraction, number, level int) *LPResult {
	s := standardForm(m, lower, upper)
	r := &LPResult{Standard: s}
	artificials := 0
	for _, art := range s.Artificial {
		if art {
			artificials++
		}
	}
	emit := func(required int, line string) {
		if required <= level {
			r.Log = append(r.Log, line)
		}
	}
	display := func(heading string, cost []Fraction, phase1 bool) {
		if level < 2 {
			return
		}
		constant, sign := s.Constant, s.Sign
		if phase1 {
			constant = integer(0)
			sign = 1
		}
		r.Log = append(r.Log, s.Tableau.display(heading, s.Columns, s.Rows, cost, constant, sign)...)
	}
	emit(0, fmt.Sprintf("SOLVE node %d rows %d columns %d artificials %d", number, len(s.Rows), len(s.Columns), artificials))
	for j, mapping := range s.Maps {
		line := "MAP " + m.Variables[j] + " " + mapping.Kind
		if mapping.Kind != "split" {
			line += " " + mapping.Offset.String()
		}
		if mapping.Kind == "shift" && upper[j] != nil {
			line += " upper " + upper[j].String()
		}
		emit(1, line)
	}
	for i, sigma := range s.Sigma {
		if sigma < 0 {
			emit(1, "FLIP "+s.Rows[i])
		}
	}
	all := make([]bool, len(s.Columns))
	real := make([]bool, len(s.Columns))
	for k := range all {
		all[k] = true
		real[k] = !s.Artificial[k]
	}
	finish := func() *LPResult {
		objective := "-"
		if r.Status == "OPTIMAL" {
			objective = r.Objective.String()
		}
		emit(0, fmt.Sprintf("RESULT %s objective %s phase1 %d phase2 %d drives %d redundant %d", r.Status, objective, r.Phase1, r.Phase2, r.Drives, r.Redundant))
		return r
	}
	if artificials > 0 {
		emit(1, "PHASE 1")
		display("phase 1 start", s.Costs1, true)
		p := phase(s.Tableau, s.Costs1, all, s.Columns, s.Rows, func(v Fraction) Fraction { return v })
		r.Phase1 = p.Iterations
		for _, line := range p.Lines {
			emit(1, line)
		}
		reduced, w := s.Tableau.reduced(s.Costs1)
		r.W = w
		emit(1, fmt.Sprintf("PHASE 1 END objective %s iterations %d", w, r.Phase1))
		if w.N > 0 {
			r.Status = "INFEASIBLE"
			for i, k := range s.Initial {
				r.Farkas = append(r.Farkas, s.Costs1[k].sub(reduced[k]).mul(integer(int64(s.Sigma[i]))))
			}
			display("final", s.Costs1, true)
			return finish()
		}
		for i, k := range s.Tableau.Basis {
			if !s.Artificial[k] {
				continue
			}
			q := -1
			for column, value := range s.Tableau.T[i] {
				if !s.Artificial[column] && value.N != 0 {
					q = column
					break
				}
			}
			if q < 0 {
				r.Redundant++
				emit(1, "REDUNDANT row "+s.Rows[i])
			} else {
				emit(1, fmt.Sprintf("DRIVE row %s enter %s leave %s", s.Rows[i], s.Columns[q], s.Columns[k]))
				s.Tableau.pivot(i, q)
				r.Drives++
			}
		}
	}
	emit(1, "PHASE 2")
	display("phase 2 start", s.Costs2, false)
	objective := func(v Fraction) Fraction { return s.Constant.add(v.mul(integer(int64(s.Sign)))) }
	p := phase(s.Tableau, s.Costs2, real, s.Columns, s.Rows, objective)
	r.Phase2 = p.Iterations
	for _, line := range p.Lines {
		emit(1, line)
	}
	_, z := s.Tableau.reduced(s.Costs2)
	r.Objective = objective(z)
	r.Solution = s.solution()
	r.Status = "OPTIMAL"
	if p.Entering >= 0 {
		r.Status = "UNBOUNDED"
		emit(1, "UNBOUNDED enter "+s.Columns[p.Entering])
		delta := make([]Fraction, len(s.Columns))
		delta[p.Entering] = integer(1)
		for i, k := range s.Tableau.Basis {
			delta[k] = s.Tableau.T[i][p.Entering].neg()
		}
		r.Ray = s.originalValues(delta, true)
		for j, v := range r.Ray {
			r.Rate = r.Rate.add(m.Cost[j].mul(v))
		}
	}
	emit(1, fmt.Sprintf("PHASE 2 END objective %s iterations %d", r.Objective, r.Phase2))
	display("final", s.Costs2, false)
	return finish()
}
func rangeText(base Fraction, limit *Fraction, lower bool) string {
	if limit == nil {
		return boundText(nil, lower)
	}
	return base.add(*limit).String()
}
func sensitivity(m *Model, root *LPResult) []string {
	s := root.Standard
	t := s.Tableau
	reduced, _ := t.reduced(s.Costs2)
	basic := make([]bool, len(s.Columns))
	basis := []string{}
	primal, dual := 0, 0
	for i, k := range t.Basis {
		basic[k] = true
		basis = append(basis, s.Columns[k])
		if !s.Artificial[k] && t.Beta[i].N == 0 {
			primal++
		}
	}
	for k, v := range reduced {
		if !basic[k] && !s.Artificial[k] && v.N == 0 {
			dual++
		}
	}
	prices := make([]Fraction, len(m.Constraints))
	variableReduced := append([]Fraction{}, m.Cost...)
	dualObjective := integer(0)
	for i, c := range m.Constraints {
		prices[i] = reduced[s.Initial[i]].mul(integer(int64(-s.Sign * s.Sigma[i])))
		dualObjective = dualObjective.add(prices[i].mul(c.RHS))
		for j, a := range c.Coefficients {
			variableReduced[j] = variableReduced[j].sub(prices[i].mul(a))
		}
	}
	for j, value := range root.Solution {
		dualObjective = dualObjective.add(variableReduced[j].mul(value))
	}
	mode := "lp"
	if integerCount(m) > 0 {
		mode = "relaxation"
	}
	out := []string{fmt.Sprintf("MODEL %s %s objective %s", m.Name, mode, root.Objective), "BASIS " + strings.Join(basis, " "), fmt.Sprintf("DEGENERACY primal %d dual %d", primal, dual), "DUAL objective " + dualObjective.String()}
	for i, c := range m.Constraints {
		var lower, upper *Fraction
		fixed := false
		for row, k := range t.Basis {
			rho := t.T[row][s.Initial[i]].mul(integer(int64(s.Sigma[i])))
			if rho.N == 0 {
				continue
			}
			if s.Artificial[k] {
				fixed = true
				break
			}
			limit := t.Beta[row].neg().div(rho)
			if rho.N > 0 {
				if lower == nil || limit.cmp(*lower) > 0 {
					lower = finite(limit)
				}
			} else if upper == nil || limit.cmp(*upper) < 0 {
				upper = finite(limit)
			}
		}
		low, high := rangeText(c.RHS, lower, true), rangeText(c.RHS, upper, false)
		if fixed {
			low = c.RHS.String()
			high = low
		}
		out = append(out, fmt.Sprintf("CONSTRAINT %s price %s rhs %s range %s %s", c.Name, prices[i], c.RHS, low, high))
	}
	for j, name := range m.Variables {
		mapping := s.Maps[j]
		status := "basic"
		switch mapping.Kind {
		case "split":
			if !basic[mapping.Columns[0]] && !basic[mapping.Columns[1]] {
				status = "zero"
			}
		case "reflect":
			if !basic[mapping.Columns[0]] {
				status = "upper"
			}
		case "shift":
			if !basic[mapping.Columns[0]] {
				status = "lower"
			} else if mapping.UpperRow >= 0 && !basic[s.Slack[mapping.UpperRow]] {
				status = "upper"
			}
		}
		h := make([]Fraction, len(s.Columns))
		for _, k := range mapping.Columns {
			h[k] = integer(int64(s.Sign * s.Directions[k]))
		}
		var lower, upper *Fraction
		for k := range s.Columns {
			if basic[k] || s.Artificial[k] {
				continue
			}
			eta := h[k]
			for row, b := range t.Basis {
				eta = eta.sub(h[b].mul(t.T[row][k]))
			}
			if eta.N == 0 {
				continue
			}
			limit := reduced[k].neg().div(eta)
			if eta.N > 0 {
				if lower == nil || limit.cmp(*lower) > 0 {
					lower = finite(limit)
				}
			} else if upper == nil || limit.cmp(*upper) < 0 {
				upper = finite(limit)
			}
		}
		out = append(out, fmt.Sprintf("VARIABLE %s %s value %s reduced %s cost %s range %s %s", name, status, root.Solution[j], variableReduced[j], m.Cost[j], rangeText(m.Cost[j], lower, true), rangeText(m.Cost[j], upper, false)))
	}
	return out
}
func coefficientStats(m *Model) string {
	sets := make([][]Fraction, 4)
	nonzeros := 0
	for _, c := range m.Constraints {
		for _, v := range c.Coefficients {
			if v.N != 0 {
				sets[0] = append(sets[0], v.abs())
				nonzeros++
			}
		}
		if c.RHS.N != 0 {
			sets[2] = append(sets[2], c.RHS.abs())
		}
	}
	for _, v := range m.Cost {
		if v.N != 0 {
			sets[1] = append(sets[1], v.abs())
		}
	}
	for j := range m.Variables {
		for _, v := range []*Fraction{m.Lower[j], m.Upper[j]} {
			if v != nil && v.N != 0 {
				sets[3] = append(sets[3], v.abs())
			}
		}
	}
	line := fmt.Sprintf("STATS nonzeros %d", nonzeros)
	for i, name := range []string{"matrix", "objective", "rhs", "bounds"} {
		low, high := "-", "-"
		if len(sets[i]) > 0 {
			minimum, maximum := sets[i][0], sets[i][0]
			for _, v := range sets[i][1:] {
				if v.cmp(minimum) < 0 {
					minimum = v
				}
				if v.cmp(maximum) > 0 {
					maximum = v
				}
			}
			low = minimum.String()
			high = maximum.String()
		}
		line += " " + name + " " + low + " " + high
	}
	return line
}
func constraintValues(m *Model, solution []Fraction) []string {
	out := []string{}
	for _, c := range m.Constraints {
		value := integer(0)
		for j, a := range c.Coefficients {
			value = value.add(a.mul(solution[j]))
		}
		margin := value.sub(c.RHS)
		if c.Comparison == "<=" {
			margin = c.RHS.sub(value)
		}
		out = append(out, fmt.Sprintf("ROW %s %s %s", c.Name, value, margin))
	}
	return out
}
func writeLines(path string, lines []string) {
	value := ""
	if len(lines) > 0 {
		value = strings.Join(lines, "\n") + "\n"
	}
	if err := os.WriteFile("output/"+path, []byte(value), 0644); err != nil {
		panic(err)
	}
}
func main() {
	settings := readSettings()
	iterations, solutions, sensitivities, tree := []string{}, []string{}, []string{}, []string{}
	summary := []string{"model,status,objective,approx,relaxation,nodes,pivots"}
	statuses := map[string]int{}
	solves, p1, p2, drives, analyzed, integerModels, integerNodes, integerLimits := 0, 0, 0, 0, 0, 0, 0, 0
	models := readModels()
	for _, raw := range models {
		m := makeModel(raw)
		if m.Err != nil {
			statuses["ERROR"]++
			iterations = append(iterations, "MODEL "+m.Name+" error")
			solutions = append(solutions, "MODEL "+m.Name, fmt.Sprintf("STATUS ERROR line %d %s", m.Err.Line, m.Err.Message))
			sensitivities = append(sensitivities, "MODEL "+m.Name+" skipped ERROR")
			summary = append(summary, m.Name+",ERROR,-,-,-,0,0")
			continue
		}
		level, limit := settings.Level, settings.Limit
		if value, ok := settings.Logs[m.Name]; ok {
			level = value
		}
		if value, ok := settings.Limits[m.Name]; ok {
			limit = value
		}
		iterations = append(iterations, fmt.Sprintf("MODEL %s level %d", m.Name, level))
		solve := func(lower, upper []*Fraction, number int) *LPResult { return solveLP(m, lower, upper, number, level) }
		var result ModelResult
		integerVariables := integerCount(m)
		if integerVariables > 0 {
			result = branchBound(m, limit, solve)
			integerModels++
			integerNodes += len(result.Solves)
			if result.Status == "NODE_LIMIT" {
				integerLimits++
			}
			tree = append(tree, fmt.Sprintf("MODEL %s %s integers %d node_limit %d", m.Name, m.Direction, integerVariables, limit))
			tree = append(tree, result.Tree...)
		} else {
			root := solve(m.Lower, m.Upper, 1)
			result = ModelResult{Status: root.Status, Root: root, Solves: []*LPResult{root}}
			if root.Status == "OPTIMAL" {
				result.HasSolution = true
				result.Objective = root.Objective
				result.Solution = append([]Fraction{}, root.Solution...)
			}
		}
		pivots := 0
		for _, lp := range result.Solves {
			iterations = append(iterations, lp.Log...)
			solves++
			p1 += lp.Phase1
			p2 += lp.Phase2
			drives += lp.Drives
			pivots += lp.pivots()
		}
		statuses[result.Status]++
		solutions = append(solutions, fmt.Sprintf("MODEL %s %s variables %d constraints %d integers %d", m.Name, m.Direction, len(m.Variables), len(m.Constraints), integerVariables), coefficientStats(m), "STATUS "+result.Status)
		objective, approx, relaxation := "-", "-", "-"
		if result.HasSolution {
			objective = result.Objective.String()
			approx = result.Objective.approx()
			solutions = append(solutions, "OBJECTIVE "+objective+" approx "+approx)
		}
		root := result.Root
		if root.Status == "OPTIMAL" {
			relaxation = root.Objective.String()
			if integerVariables > 0 {
				solutions = append(solutions, "RELAXATION "+relaxation+" approx "+root.Objective.approx())
			}
			sensitivities = append(sensitivities, sensitivity(m, root)...)
			analyzed++
		} else {
			sensitivities = append(sensitivities, "MODEL "+m.Name+" skipped "+root.Status)
		}
		if root.Status == "INFEASIBLE" {
			solutions = append(solutions, "INFEASIBILITY "+root.W.String())
			for i, value := range root.Farkas {
				solutions = append(solutions, "FARKAS "+root.Standard.Rows[i]+" "+value.String())
			}
		}
		if result.HasSolution || result.Status == "UNBOUNDED" {
			values := result.Solution
			if !result.HasSolution {
				values = root.Solution
			}
			for j, value := range values {
				solutions = append(solutions, "VALUE "+m.Variables[j]+" "+value.String())
			}
		}
		if result.Status == "UNBOUNDED" {
			for j, value := range root.Ray {
				solutions = append(solutions, "RAY "+m.Variables[j]+" "+value.String())
			}
			solutions = append(solutions, "RATE "+root.Rate.String())
		}
		if result.HasSolution {
			solutions = append(solutions, constraintValues(m, result.Solution)...)
		}
		if integerVariables > 0 {
			solutions = append(solutions, fmt.Sprintf("NODES %d", len(result.Solves)))
		}
		solutions = append(solutions, fmt.Sprintf("PIVOTS %d", pivots))
		summary = append(summary, fmt.Sprintf("%s,%s,%s,%s,%s,%d,%d", m.Name, result.Status, objective, approx, relaxation, len(result.Solves), pivots))
	}
	iterations = append(iterations, fmt.Sprintf("TOTAL solves %d phase1 %d phase2 %d drives %d pivots %d", solves, p1, p2, drives, p1+p2+drives))
	solutions = append(solutions, fmt.Sprintf("SUMMARY models %d optimal %d infeasible %d unbounded %d node_limit %d error %d", len(models), statuses["OPTIMAL"], statuses["INFEASIBLE"], statuses["UNBOUNDED"], statuses["NODE_LIMIT"], statuses["ERROR"]))
	sensitivities = append(sensitivities, fmt.Sprintf("SUMMARY analyzed %d skipped %d", analyzed, len(models)-analyzed))
	tree = append(tree, fmt.Sprintf("SUMMARY models %d nodes %d node_limit %d", integerModels, integerNodes, integerLimits))
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	writeLines("iterations.txt", iterations)
	writeLines("solutions.txt", solutions)
	writeLines("sensitivity.txt", sensitivities)
	writeLines("bnb_tree.txt", tree)
	writeLines("summary.csv", summary)
}
