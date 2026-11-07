package main

import (
	"os"
	"sort"
	"strconv"
	"strings"
)

type Element struct {
	Symbol         string
	Number, Weight int
	Valences       []int
}
type Choice struct {
	Symbol   string
	Aromatic bool
}
type Atom struct {
	Symbol                          string
	Aromatic                        bool
	Mass, Charge, Hydrogens, Column int
	Bracket                         bool
	Choices                         []Choice
	Wildcard                        byte
}
type Bond struct {
	A, B                      int
	Symbol                    byte
	Type, Multiplicity, Match int
	Ring                      bool
}

func (b *Bond) Other(a int) int {
	if a == b.A {
		return b.B
	}
	return b.A
}

type Molecule struct {
	Name                                                string
	Atoms                                               []*Atom
	Bonds                                               []*Bond
	Adjacent                                            [][]int
	Rings                                               [][]int
	RingAtoms                                           []bool
	Ranks                                               []int
	Classes                                             int
	Canonical, Scaffold, Formula, Lipinski              string
	Weight, Heavy, Rotatable, Donors, Acceptors, Charge int
	Bits                                                [1024]bool
	BitCount, Paths                                     int
}

func (m *Molecule) Build() {
	sort.Slice(m.Bonds, func(i, j int) bool {
		a, b := m.Bonds[i], m.Bonds[j]
		if a.A != b.A {
			return a.A < b.A
		}
		return a.B < b.B
	})
	m.Adjacent = make([][]int, len(m.Atoms))
	for i, b := range m.Bonds {
		m.Adjacent[b.A] = append(m.Adjacent[b.A], i)
		m.Adjacent[b.B] = append(m.Adjacent[b.B], i)
	}
	for a := range m.Atoms {
		sort.Slice(m.Adjacent[a], func(i, j int) bool { return m.Bonds[m.Adjacent[a][i]].Other(a) < m.Bonds[m.Adjacent[a][j]].Other(a) })
	}
}
func (m *Molecule) Bond(a, b int) *Bond {
	for _, e := range m.Adjacent[a] {
		bond := m.Bonds[e]
		if bond.Other(a) == b {
			return bond
		}
	}
	return nil
}
func (m *Molecule) Base(a int) int {
	sum := 0
	for _, e := range m.Adjacent[a] {
		kind := m.Bonds[e].Type
		if kind == 4 {
			kind = 1
		}
		sum += kind
	}
	return sum
}
func (m *Molecule) Multiplicity(a int) int {
	sum := 0
	for _, e := range m.Adjacent[a] {
		sum += m.Bonds[e].Multiplicity
	}
	return sum
}
func (m *Molecule) NeedsPi(a int, elements map[string]Element, hydrogens bool) bool {
	atom := m.Atoms[a]
	if !atom.Aromatic {
		return false
	}
	sum := m.Base(a)
	if hydrogens {
		sum += atom.Hydrogens
	}
	return elements[atom.Symbol].Valences[0]+atom.Charge >= sum+1
}
func organicHydrogens(m *Molecule, a int, elements map[string]Element) (int, bool) {
	b := m.Multiplicity(a)
	for _, v := range elements[m.Atoms[a].Symbol].Valences {
		if v >= b {
			return v - b, true
		}
	}
	return 0, false
}

type ParseError struct {
	Reason string
	Column int
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
func ignored(s string) bool { return s == "" || s[0] == '#' }
func readElements() map[string]Element {
	out := map[string]Element{}
	for _, line := range lines("input/elements.txt") {
		if ignored(line) {
			continue
		}
		a := strings.Split(line, " ")
		valences := []int{}
		for _, s := range strings.Split(a[3], ",") {
			valences = append(valences, integer(s))
		}
		out[a[0]] = Element{a[0], integer(a[1]), integer(a[2]), valences}
	}
	return out
}
