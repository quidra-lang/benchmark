package main

import (
	"slices"
	"sort"
)

type State [4]uint64

func (s State) Has(p int) bool { return s[p/64]&(uint64(1)<<uint(p%64)) != 0 }
func (s *State) Put(p int)     { s[p/64] |= uint64(1) << uint(p%64) }
func (s State) Union(t State) State {
	for i := range s {
		s[i] |= t[i]
	}
	return s
}
func (s State) Without(t State) State {
	for i := range s {
		s[i] &^= t[i]
	}
	return s
}
func (s State) Contains(t State) bool {
	for i := range s {
		if s[i]&t[i] != t[i] {
			return false
		}
	}
	return true
}
func (s State) Intersects(t State) bool {
	for i := range s {
		if s[i]&t[i] != 0 {
			return true
		}
	}
	return false
}
func (s State) Numbers() []int {
	out := []int{}
	for i := 0; i < 256; i++ {
		if s.Has(i) {
			out = append(out, i)
		}
	}
	return out
}
func state(numbers []int) State {
	out := State{}
	for _, p := range numbers {
		out.Put(p)
	}
	return out
}
func (d *Domain) Subtype(t, u string) bool {
	for {
		if t == u {
			return true
		}
		if t == "object" {
			return false
		}
		t = d.Parents[t]
	}
}
func (d *Domain) Classify() {
	d.Fluent = map[string]bool{}
	for _, s := range d.Actions {
		for _, e := range s.Effects {
			d.Fluent[e.Atom.Predicate] = true
		}
	}
}
func substitute(a Atom, assignment map[string]string) Atom {
	out := Atom{Predicate: a.Predicate, Terms: make([]string, len(a.Terms))}
	for i, t := range a.Terms {
		out.Terms[i] = assignment[t]
	}
	return out
}

type GroundAction struct {
	Schema             *Schema
	Arguments          []string
	Cost, Number       int
	Pre, Neg, Add, Del State
}

func (a *GroundAction) Text() string { return Atom{a.Schema.Name, a.Arguments}.Text() }

type Candidate struct {
	Schema             *Schema
	Arguments          []string
	Pre, Neg, Add, Del map[string]Atom
	Reachable          bool
}
type SchemaCount struct{ Assignments, Candidates, Reachable int }
type GroundProblem struct {
	Domain                      *Domain
	Problem                     *Problem
	Facts                       []Atom
	FactIndex                   map[string]int
	Actions                     []*GroundAction
	Initial, Goal               State
	Unreachable                 []Atom
	Counts                      map[string]*SchemaCount
	CandidateCount, StaticFacts int
	Cache                       map[State]*Heuristic
}

func objectTypes(p *Problem) map[string]string {
	out := map[string]string{}
	for _, o := range p.Objects {
		out[o.Name] = o.Type
	}
	return out
}
func objectsOfType(d *Domain, p *Problem, t string) []string {
	out := []string{}
	for _, o := range p.Objects {
		if d.Subtype(o.Type, t) {
			out = append(out, o.Name)
		}
	}
	return out
}
func atomsContain(set map[string]Atom, required map[string]Atom) bool {
	for key := range required {
		if _, ok := set[key]; !ok {
			return false
		}
	}
	return true
}
func ground(d *Domain, p *Problem) *GroundProblem {
	g := &GroundProblem{Domain: d, Problem: p, FactIndex: map[string]int{}, Counts: map[string]*SchemaCount{}, Cache: map[State]*Heuristic{}}
	initial := map[string]Atom{}
	reachable := map[string]Atom{}
	for _, a := range p.Initial {
		initial[a.Text()] = a
		if d.Fluent[a.Predicate] {
			reachable[a.Text()] = a
		} else {
			g.StaticFacts++
		}
	}
	candidates := []*Candidate{}
	for _, s := range d.Actions {
		count := &SchemaCount{Assignments: 1}
		g.Counts[s.Name] = count
		choices := make([][]string, len(s.Parameters))
		for i, param := range s.Parameters {
			choices[i] = objectsOfType(d, p, param.Type)
			count.Assignments *= len(choices[i])
		}
		assignment := map[string]string{}
		arguments := make([]string, len(s.Parameters))
		var enumerate func(int)
		enumerate = func(at int) {
			if at < len(s.Parameters) {
				for _, object := range choices[at] {
					arguments[at] = object
					assignment[s.Parameters[at].Name] = object
					enumerate(at + 1)
				}
				return
			}
			c := &Candidate{Schema: s, Arguments: slices.Clone(arguments), Pre: map[string]Atom{}, Neg: map[string]Atom{}, Add: map[string]Atom{}, Del: map[string]Atom{}}
			for _, literal := range s.Conditions {
				a := substitute(literal.Atom, assignment)
				if a.Predicate == "=" || !d.Fluent[a.Predicate] {
					truth := false
					if a.Predicate == "=" {
						truth = a.Terms[0] == a.Terms[1]
					} else {
						_, truth = initial[a.Text()]
					}
					if truth == literal.Negative {
						return
					}
				} else if literal.Negative {
					c.Neg[a.Text()] = a
				} else {
					c.Pre[a.Text()] = a
				}
			}
			for _, literal := range s.Effects {
				a := substitute(literal.Atom, assignment)
				if literal.Negative {
					c.Del[a.Text()] = a
				} else {
					c.Add[a.Text()] = a
				}
			}
			for key := range c.Add {
				delete(c.Del, key)
			}
			candidates = append(candidates, c)
			count.Candidates++
		}
		enumerate(0)
	}
	g.CandidateCount = len(candidates)
	for {
		changed := false
		for _, c := range candidates {
			if !c.Reachable && atomsContain(reachable, c.Pre) {
				c.Reachable = true
				changed = true
				for key, a := range c.Add {
					reachable[key] = a
				}
			}
		}
		if !changed {
			break
		}
	}
	for _, a := range reachable {
		g.Facts = append(g.Facts, a)
	}
	objectNumbers := map[string]int{}
	for i, o := range p.Objects {
		objectNumbers[o.Name] = i
	}
	sort.Slice(g.Facts, func(i, j int) bool {
		a, b := g.Facts[i], g.Facts[j]
		if d.PredicateIndex[a.Predicate] != d.PredicateIndex[b.Predicate] {
			return d.PredicateIndex[a.Predicate] < d.PredicateIndex[b.Predicate]
		}
		aa, bb := make([]int, len(a.Terms)), make([]int, len(b.Terms))
		for k, t := range a.Terms {
			aa[k] = objectNumbers[t]
		}
		for k, t := range b.Terms {
			bb[k] = objectNumbers[t]
		}
		return slices.Compare(aa, bb) < 0
	})
	for i, a := range g.Facts {
		g.FactIndex[a.Text()] = i
	}
	toState := func(atoms map[string]Atom) State {
		out := State{}
		for key := range atoms {
			if number, ok := g.FactIndex[key]; ok {
				out.Put(number)
			}
		}
		return out
	}
	g.Initial = toState(initial)
	for _, c := range candidates {
		if !c.Reachable {
			continue
		}
		a := &GroundAction{Schema: c.Schema, Arguments: c.Arguments, Cost: c.Schema.Cost, Number: len(g.Actions), Pre: toState(c.Pre), Neg: toState(c.Neg), Add: toState(c.Add), Del: toState(c.Del)}
		g.Actions = append(g.Actions, a)
		g.Counts[c.Schema.Name].Reachable++
	}
	for _, a := range p.Goals {
		if number, ok := g.FactIndex[a.Text()]; ok {
			g.Goal.Put(number)
		} else if !d.Fluent[a.Predicate] {
			if _, trueStatic := initial[a.Text()]; !trueStatic {
				g.Unreachable = append(g.Unreachable, a)
			}
		} else {
			g.Unreachable = append(g.Unreachable, a)
		}
	}
	return g
}
