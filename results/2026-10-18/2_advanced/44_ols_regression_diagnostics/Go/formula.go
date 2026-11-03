package main

import (
	"math/bits"
	"sort"
	"strings"
)

type Factor struct {
	Name, Column string
	Power        int
	Categorical  bool
}

func parseFactor(name string) Factor {
	f := Factor{Name: name, Column: name, Power: 1}
	if strings.HasPrefix(name, "C(") {
		f.Categorical = true
		f.Column = name[2 : len(name)-1]
	} else if strings.HasPrefix(name, "I(") {
		parts := strings.Split(name[2:len(name)-1], "^")
		f.Column = parts[0]
		f.Power = int(parts[1][0] - '0')
	}
	return f
}
func (f Factor) value(row Record, level string) float64 {
	v := row[f.Column]
	if f.Categorical {
		if v.Label == level {
			return 1
		}
		return 0
	}
	x := v.Number
	if f.Power == 2 {
		return x * x
	}
	if f.Power == 3 {
		return x * x * x
	}
	return x
}

type Term struct {
	Name    string
	Factors []Factor
	Names   map[string]bool
}

func newTerm(factors []Factor) Term {
	names := []string{}
	set := map[string]bool{}
	for _, f := range factors {
		names = append(names, f.Name)
		set[f.Name] = true
	}
	return Term{strings.Join(names, ":"), factors, set}
}
func (t Term) contained(other Term) bool {
	if len(t.Names) >= len(other.Names) {
		return false
	}
	for f := range t.Names {
		if !other.Names[f] {
			return false
		}
	}
	return true
}

type Model struct {
	Original, Response, Weight                string
	Terms                                     []Term
	FactorColumns, CategoryColumns, Variables []string
}

func parseModel(line string) Model {
	split := strings.SplitN(line, " weights=", 2)
	m := Model{Original: split[0]}
	if len(split) == 2 {
		m.Weight = split[1]
	}
	parts := strings.Split(m.Original, " ~ ")
	m.Response = parts[0]
	seen := map[string]bool{}
	add := func(f []Factor) {
		term := newTerm(f)
		names := []string{}
		for n := range term.Names {
			names = append(names, n)
		}
		sort.Strings(names)
		key := strings.Join(names, "\x00")
		if !seen[key] {
			m.Terms = append(m.Terms, term)
			seen[key] = true
		}
	}
	for _, expression := range strings.Split(parts[1], " + ") {
		if strings.Contains(expression, "*") {
			names := strings.Split(expression, "*")
			factors := []Factor{}
			for _, n := range names {
				factors = append(factors, parseFactor(n))
			}
			for size := 1; size <= len(factors); size++ {
				for mask := 1; mask < 1<<len(factors); mask++ {
					if bits.OnesCount(uint(mask)) != size {
						continue
					}
					seq := []Factor{}
					for j, f := range factors {
						if mask&(1<<j) != 0 {
							seq = append(seq, f)
						}
					}
					add(seq)
				}
			}
		} else {
			factors := []Factor{}
			for _, name := range strings.Split(expression, ":") {
				factors = append(factors, parseFactor(name))
			}
			add(factors)
		}
	}
	cols, cats := map[string]bool{}, map[string]bool{}
	for _, t := range m.Terms {
		for _, f := range t.Factors {
			if !cols[f.Column] {
				m.FactorColumns = append(m.FactorColumns, f.Column)
				cols[f.Column] = true
			}
			if f.Categorical && !cats[f.Column] {
				m.CategoryColumns = append(m.CategoryColumns, f.Column)
				cats[f.Column] = true
			}
		}
	}
	m.Variables = append(append([]string{}, m.FactorColumns...), m.Response)
	if m.Weight != "" {
		m.Variables = append(m.Variables, m.Weight)
	}
	return m
}
func (m Model) format(terms []int) string {
	names := []string{}
	for _, i := range terms {
		names = append(names, m.Terms[i].Name)
	}
	rhs := "1"
	if len(names) > 0 {
		rhs = strings.Join(names, " + ")
	}
	return m.Response + " ~ " + rhs
}
func (m Model) removable(terms []int) []int {
	out := []int{}
	for _, i := range terms {
		ok := true
		for _, j := range terms {
			if m.Terms[i].contained(m.Terms[j]) {
				ok = false
				break
			}
		}
		if ok {
			out = append(out, i)
		}
	}
	return out
}
func selectedTerms(terms []int) map[int]bool {
	set := map[int]bool{}
	for _, i := range terms {
		set[i] = true
	}
	return set
}
func (m Model) candidates(terms []int) []int {
	set := selectedTerms(terms)
	out := []int{}
	for i, t := range m.Terms {
		if set[i] {
			continue
		}
		ok := true
		for j, other := range m.Terms {
			if other.contained(t) && !set[j] {
				ok = false
				break
			}
		}
		if ok {
			out = append(out, i)
		}
	}
	return out
}
func (m Model) hierarchical(terms []int) bool {
	set := selectedTerms(terms)
	for _, i := range terms {
		for j, t := range m.Terms {
			if t.contained(m.Terms[i]) && !set[j] {
				return false
			}
		}
	}
	return true
}

type Component struct {
	Factor      Factor
	Name, Level string
}
type DesignColumn struct {
	Term       int
	Name       string
	Components []Component
}

func (c DesignColumn) value(row Record) float64 {
	if len(c.Components) == 0 {
		return 1
	}
	v := c.Components[0].Factor.value(row, c.Components[0].Level)
	for _, s := range c.Components[1:] {
		v *= s.Factor.value(row, s.Level)
	}
	return v
}

type Design struct {
	Model             Model
	RowNumbers        []int
	Rows              []Record
	Levels            map[string][]string
	Columns           []DesignColumn
	Matrix            [][]float64
	Response, Weights []float64
}

func buildDesign(model Model, data DataFrame) *Design {
	d := &Design{Model: model, Levels: map[string][]string{}, Columns: []DesignColumn{{Term: -1, Name: "(Intercept)"}}}
	for i, row := range data.Rows {
		ok := true
		for _, c := range model.Variables {
			if !row[c].Present {
				ok = false
				break
			}
		}
		if ok {
			d.RowNumbers = append(d.RowNumbers, i+1)
			d.Rows = append(d.Rows, row)
		}
	}
	for _, c := range model.CategoryColumns {
		set := map[string]bool{}
		for _, r := range d.Rows {
			set[r[c].Label] = true
		}
		levels := []string{}
		for v := range set {
			levels = append(levels, v)
		}
		sort.Strings(levels)
		d.Levels[c] = levels
	}
	for i, t := range model.Terms {
		components := make([][]Component, len(t.Factors))
		for j, f := range t.Factors {
			if f.Categorical {
				for _, level := range d.Levels[f.Column][1:] {
					components[j] = append(components[j], Component{f, f.Name + level, level})
				}
			} else {
				components[j] = []Component{{Factor: f, Name: f.Name}}
			}
		}
		choices := make([]Component, len(components))
		var product func(int)
		product = func(j int) {
			if j < 0 {
				names := []string{}
				for _, c := range choices {
					names = append(names, c.Name)
				}
				d.Columns = append(d.Columns, DesignColumn{i, strings.Join(names, ":"), append([]Component{}, choices...)})
				return
			}
			for _, c := range components[j] {
				choices[j] = c
				product(j - 1)
			}
		}
		product(len(components) - 1)
	}
	for _, row := range d.Rows {
		d.Matrix = append(d.Matrix, d.values(row))
		d.Response = append(d.Response, row[model.Response].Number)
		w := 1.0
		if model.Weight != "" {
			w = row[model.Weight].Number
		}
		d.Weights = append(d.Weights, w)
	}
	return d
}
func (d *Design) values(row Record) []float64 {
	values := make([]float64, len(d.Columns))
	for j, c := range d.Columns {
		values[j] = c.value(row)
	}
	return values
}
func (d *Design) subsetMatrix(terms []int) [][]float64 {
	set := selectedTerms(terms)
	indices := []int{}
	for j, c := range d.Columns {
		if c.Term < 0 || set[c.Term] {
			indices = append(indices, j)
		}
	}
	out := make([][]float64, len(d.Rows))
	for i, row := range d.Matrix {
		for _, j := range indices {
			out[i] = append(out[i], row[j])
		}
	}
	return out
}
func (d *Design) predictable(row Record) bool {
	for _, c := range d.Model.FactorColumns {
		v := row[c]
		if !v.Present {
			return false
		}
		if levels, ok := d.Levels[c]; ok {
			found := false
			for _, s := range levels {
				if s == v.Label {
					found = true
					break
				}
			}
			if !found {
				return false
			}
		}
	}
	return true
}
