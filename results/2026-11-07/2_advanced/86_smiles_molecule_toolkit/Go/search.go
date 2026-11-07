package main

import (
	"math/big"
	"slices"
	"strings"
)

func patternAtom(source string, at int) (*Atom, int, string) {
	c := source[at]
	if c == '*' || c == 'A' || c == 'a' {
		return &Atom{Wildcard: c}, at + 1, ""
	}
	if c == '[' {
		end := strings.IndexByte(source[at+1:], ']')
		if end < 0 {
			return nil, at, "unclosed bracket"
		}
		end += at + 1
		parts := strings.Split(source[at+1:end], ",")
		atom := &Atom{}
		for _, part := range parts {
			if part == "" {
				return nil, at, "bad bracket atom"
			}
			a, next, ok := organic(part, 0)
			if !ok || next != len(part) {
				return nil, at, "bad bracket atom"
			}
			atom.Choices = append(atom.Choices, Choice{a.Symbol, a.Aromatic})
		}
		return atom, end + 1, ""
	}
	a, next, ok := organic(source, at)
	if !ok {
		return nil, at, "unexpected character"
	}
	a.Choices = []Choice{{a.Symbol, a.Aromatic}}
	return a, next, ""
}
func atomMatches(pattern, molecule *Atom) bool {
	switch pattern.Wildcard {
	case '*':
		return true
	case 'A':
		return !molecule.Aromatic
	case 'a':
		return molecule.Aromatic
	}
	for _, c := range pattern.Choices {
		if c.Symbol == molecule.Symbol && c.Aromatic == molecule.Aromatic {
			return true
		}
	}
	return false
}
func bondMatches(pattern, molecule *Bond) bool { return pattern.Match&(1<<molecule.Type) != 0 }
func moleculePattern(m *Molecule) *Molecule {
	p := &Molecule{}
	for _, a := range m.Atoms {
		p.Atoms = append(p.Atoms, &Atom{Choices: []Choice{{a.Symbol, a.Aromatic}}})
	}
	for _, b := range m.Bonds {
		p.Bonds = append(p.Bonds, &Bond{A: b.A, B: b.B, Match: 1 << b.Type})
	}
	p.Build()
	return p
}

type Embeddings struct {
	Count, Unique int
	First         []int
}

func embeddings(pattern, molecule *Molecule) Embeddings {
	out := Embeddings{}
	if len(pattern.Atoms) > len(molecule.Atoms) {
		return out
	}
	mapping := make([]int, len(pattern.Atoms))
	for i := range mapping {
		mapping[i] = -1
	}
	used := make([]bool, len(molecule.Atoms))
	sets := map[string]bool{}
	var search func(int)
	search = func(index int) {
		if index == len(pattern.Atoms) {
			out.Count++
			if out.First == nil {
				out.First = make([]int, len(mapping))
				for i, a := range mapping {
					out.First[i] = a + 1
				}
			}
			mask := new(big.Int)
			for _, a := range mapping {
				mask.SetBit(mask, a, 1)
			}
			sets[mask.Text(16)] = true
			return
		}
		for candidate, a := range molecule.Atoms {
			if used[candidate] || !atomMatches(pattern.Atoms[index], a) {
				continue
			}
			valid := true
			for _, e := range pattern.Adjacent[index] {
				b := pattern.Bonds[e]
				other := b.Other(index)
				if other >= index {
					continue
				}
				actual := molecule.Bond(candidate, mapping[other])
				if actual == nil || !bondMatches(b, actual) {
					valid = false
					break
				}
			}
			if valid {
				mapping[index] = candidate
				used[candidate] = true
				search(index + 1)
				used[candidate] = false
				mapping[index] = -1
			}
		}
	}
	search(0)
	out.Unique = len(sets)
	return out
}
func fingerprint(m *Molecule, elements map[string]Element) {
	codes := make([]int, len(m.Atoms))
	for i, a := range m.Atoms {
		aromatic := 0
		if a.Aromatic {
			aromatic = 8
		}
		codes[i] = 16*elements[a.Symbol].Number + aromatic + len(m.Adjacent[i])
	}
	visited := make([]bool, len(m.Atoms))
	var visit func(int, int, int)
	visit = func(a, depth, hash int) {
		m.Paths++
		m.Bits[hash%1024] = true
		if depth == 5 {
			return
		}
		for _, e := range m.Adjacent[a] {
			b := m.Bonds[e]
			next := b.Other(a)
			if visited[next] {
				continue
			}
			value := (hash*31 + b.Type) % 1000003
			value = (value*31 + codes[next]) % 1000003
			visited[next] = true
			visit(next, depth+1, value)
			visited[next] = false
		}
	}
	for i := range m.Atoms {
		visited[i] = true
		visit(i, 0, codes[i])
		visited[i] = false
	}
	for _, bit := range m.Bits {
		if bit {
			m.BitCount++
		}
	}
}

type Fraction struct{ N, D int }

func gcd(a, b int) int {
	for b != 0 {
		a, b = b, a%b
	}
	return a
}
func fraction(n, d int) Fraction {
	g := gcd(n, d)
	return Fraction{n / g, d / g}
}
func (a Fraction) Cmp(b Fraction) int {
	left, right := a.N*b.D, b.N*a.D
	if left < right {
		return -1
	}
	if left > right {
		return 1
	}
	return 0
}
func similarity(a, b *Molecule) (Fraction, int, int) {
	common, union := 0, 0
	for i := range a.Bits {
		if a.Bits[i] && b.Bits[i] {
			common++
		}
		if a.Bits[i] || b.Bits[i] {
			union++
		}
	}
	return fraction(common, union), common, union
}
func distinctStrings(a []string) int {
	copy := slices.Clone(a)
	slices.Sort(copy)
	return len(slices.Compact(copy))
}
