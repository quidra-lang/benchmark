package main

import (
	"os"
	"strconv"
	"strings"
)

type Expression struct {
	Word string
	List []Expression
}

func expressions(path string) []Expression {
	tokens := []string{}
	for _, line := range lines(path) {
		line = strings.SplitN(line, ";", 2)[0]
		line = strings.ReplaceAll(strings.ReplaceAll(line, "(", " ( "), ")", " ) ")
		tokens = append(tokens, strings.Fields(line)...)
	}
	at := 0
	var read func() Expression
	read = func() Expression {
		token := tokens[at]
		at++
		if token != "(" {
			return Expression{Word: token}
		}
		list := []Expression{}
		for tokens[at] != ")" {
			list = append(list, read())
		}
		at++
		return Expression{List: list}
	}
	out := []Expression{}
	for at < len(tokens) {
		out = append(out, read())
	}
	return out
}
func words(a []Expression) []string {
	out := make([]string, len(a))
	for i, e := range a {
		out[i] = e.Word
	}
	return out
}

type Typed struct{ Name, Type string }

func typedList(tokens []string) []Typed {
	out := []Typed{}
	pending := []string{}
	for i := 0; i < len(tokens); i++ {
		if tokens[i] == "-" {
			i++
			for _, name := range pending {
				out = append(out, Typed{name, tokens[i]})
			}
			pending = nil
		} else {
			pending = append(pending, tokens[i])
		}
	}
	for _, name := range pending {
		out = append(out, Typed{name, "object"})
	}
	return out
}

type Atom struct {
	Predicate string
	Terms     []string
}

func (a Atom) Text() string {
	if len(a.Terms) == 0 {
		return "(" + a.Predicate + ")"
	}
	return "(" + a.Predicate + " " + strings.Join(a.Terms, " ") + ")"
}
func parseAtom(e Expression) Atom { return Atom{e.List[0].Word, words(e.List[1:])} }

type Literal struct {
	Atom     Atom
	Negative bool
}

func (l Literal) Text() string {
	if l.Negative {
		return "(not " + l.Atom.Text() + ")"
	}
	return l.Atom.Text()
}
func literal(e Expression) Literal {
	if e.List[0].Word == "not" {
		return Literal{parseAtom(e.List[1]), true}
	}
	return Literal{Atom: parseAtom(e)}
}
func conjunction(e Expression) []Expression {
	if len(e.List) > 0 && e.List[0].Word == "and" {
		return e.List[1:]
	}
	return []Expression{e}
}

type Predicate struct {
	Name  string
	Types []string
}
type Schema struct {
	Name                string
	Parameters          []Typed
	Conditions, Effects []Literal
	Cost                int
}
type Domain struct {
	Name           string
	Types          []string
	Parents        map[string]string
	Predicates     []Predicate
	PredicateIndex map[string]int
	Actions        []*Schema
	Fluent         map[string]bool
	Diagnostics    []string
}
type Problem struct {
	Name           string
	Objects        []Typed
	Initial, Goals []Atom
	Diagnostics    []string
}

func readDomain() *Domain {
	e := expressions("input/domain.txt")[0]
	d := &Domain{Name: e.List[1].List[1].Word, Types: []string{"object"}, Parents: map[string]string{}, PredicateIndex: map[string]int{}, Fluent: map[string]bool{}}
	for _, section := range e.List[2:] {
		a := section.List
		switch a[0].Word {
		case ":types":
			tokens := words(a[1:])
			seen := map[string]bool{"object": true}
			for _, t := range tokens {
				if t != "-" && !seen[t] {
					seen[t] = true
					d.Types = append(d.Types, t)
					d.Parents[t] = "object"
				}
			}
			for _, t := range typedList(tokens) {
				d.Parents[t.Name] = t.Type
			}
		case ":predicates":
			for _, decl := range a[1:] {
				p := Predicate{Name: decl.List[0].Word}
				for _, t := range typedList(words(decl.List[1:])) {
					p.Types = append(p.Types, t.Type)
				}
				d.PredicateIndex[p.Name] = len(d.Predicates)
				d.Predicates = append(d.Predicates, p)
			}
		case ":action":
			s := &Schema{Name: a[1].Word, Cost: 1}
			for i := 2; i < len(a); i += 2 {
				switch a[i].Word {
				case ":parameters":
					s.Parameters = typedList(words(a[i+1].List))
				case ":precondition":
					for _, e := range conjunction(a[i+1]) {
						s.Conditions = append(s.Conditions, literal(e))
					}
				case ":effect":
					for _, e := range conjunction(a[i+1]) {
						if e.List[0].Word == "increase" {
							s.Cost = integer(e.List[2].Word)
						} else {
							s.Effects = append(s.Effects, literal(e))
						}
					}
				}
			}
			d.Actions = append(d.Actions, s)
		}
	}
	return d
}
func readProblems() []*Problem {
	out := []*Problem{}
	for _, e := range expressions("input/problems.txt") {
		p := &Problem{Name: e.List[1].List[1].Word}
		for _, section := range e.List[2:] {
			a := section.List
			switch a[0].Word {
			case ":objects":
				p.Objects = typedList(words(a[1:]))
			case ":init":
				for _, e := range a[1:] {
					p.Initial = append(p.Initial, parseAtom(e))
				}
			case ":goal":
				for _, e := range conjunction(a[1]) {
					p.Goals = append(p.Goals, parseAtom(e))
				}
			}
		}
		out = append(out, p)
	}
	return out
}
func integer(s string) int {
	v, e := strconv.Atoi(s)
	if e != nil {
		panic(e)
	}
	return v
}
func lines(path string) []string {
	b, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	if len(b) == 0 {
		return nil
	}
	return strings.Split(strings.TrimSuffix(string(b), "\n"), "\n")
}
