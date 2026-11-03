package main

import (
	"fmt"
	"slices"
	"sort"
	"strconv"
	"strings"
)

func dense(values [][]int) []int {
	order := make([]int, len(values))
	for i := range order {
		order[i] = i
	}
	sort.Slice(order, func(i, j int) bool { return slices.Compare(values[order[i]], values[order[j]]) < 0 })
	ranks := make([]int, len(values))
	rank := 0
	var previous []int
	for k, i := range order {
		if k == 0 || !slices.Equal(values[i], previous) {
			rank++
			previous = values[i]
		}
		ranks[i] = rank
	}
	return ranks
}
func rankCount(ranks []int) int {
	count := 0
	for _, r := range ranks {
		count = max(count, r)
	}
	return count
}
func refine(m *Molecule, ranks []int) []int {
	for {
		values := make([][]int, len(m.Atoms))
		for a := range m.Atoms {
			neighbors := [][2]int{}
			for _, e := range m.Adjacent[a] {
				b := m.Bonds[e]
				neighbors = append(neighbors, [2]int{ranks[b.Other(a)], b.Type})
			}
			sort.Slice(neighbors, func(i, j int) bool {
				a, b := neighbors[i], neighbors[j]
				if a[0] != b[0] {
					return a[0] < b[0]
				}
				return a[1] < b[1]
			})
			values[a] = []int{ranks[a]}
			for _, v := range neighbors {
				values[a] = append(values[a], v[0], v[1])
			}
		}
		next := dense(values)
		if rankCount(next) == rankCount(ranks) {
			return next
		}
		ranks = next
	}
}
func canonicalRanks(m *Molecule, elements map[string]Element) {
	values := make([][]int, len(m.Atoms))
	for i, a := range m.Atoms {
		aromatic := 0
		if a.Aromatic {
			aromatic = 1
		}
		values[i] = []int{len(m.Adjacent[i]), elements[a.Symbol].Number, a.Mass, a.Charge, a.Hydrogens, aromatic}
	}
	ranks := refine(m, dense(values))
	m.Classes = rankCount(ranks)
	for rankCount(ranks) < len(m.Atoms) {
		counts := map[int]int{}
		for _, r := range ranks {
			counts[r]++
		}
		smallest := len(m.Atoms) + 1
		for r, n := range counts {
			if n > 1 {
				smallest = min(smallest, r)
			}
		}
		chosen := -1
		for i, r := range ranks {
			if r == smallest {
				chosen = i
				break
			}
		}
		values := make([][]int, len(ranks))
		for i, r := range ranks {
			value := 2 * r
			if i == chosen {
				value--
			}
			values[i] = []int{value}
		}
		ranks = refine(m, dense(values))
	}
	m.Ranks = ranks
}
func atomNotation(m *Molecule, index int, elements map[string]Element) string {
	a := m.Atoms[index]
	symbol := a.Symbol
	if a.Aromatic {
		symbol = strings.ToLower(symbol)
	}
	organic := slices.Contains([]string{"B", "C", "N", "O", "P", "S", "F", "Cl", "Br", "I"}, a.Symbol) && (!a.Aromatic || slices.Contains([]string{"B", "C", "N", "O", "P", "S"}, a.Symbol))
	hydrogens, possible := organicHydrogens(m, index, elements)
	if organic && a.Mass == 0 && a.Charge == 0 && (!a.Aromatic || m.NeedsPi(index, elements, true) == m.NeedsPi(index, elements, false)) && possible && hydrogens == a.Hydrogens {
		return symbol
	}
	var out strings.Builder
	out.WriteByte('[')
	if a.Mass != 0 {
		out.WriteString(strconv.Itoa(a.Mass))
	}
	out.WriteString(symbol)
	if a.Hydrogens > 0 {
		out.WriteByte('H')
		if a.Hydrogens >= 2 {
			out.WriteString(strconv.Itoa(a.Hydrogens))
		}
	}
	if a.Charge != 0 {
		charge := a.Charge
		if charge > 0 {
			out.WriteByte('+')
		} else {
			out.WriteByte('-')
			charge = -charge
		}
		if charge >= 2 {
			out.WriteString(strconv.Itoa(charge))
		}
	}
	out.WriteByte(']')
	return out.String()
}
func canonicalBond(m *Molecule, b *Bond) string {
	inRing := m.Atoms[b.A].Aromatic && m.Atoms[b.B].Aromatic && b.Ring
	switch b.Type {
	case 1:
		if inRing {
			return "-"
		}
		return ""
	case 2:
		return "="
	case 3:
		return "#"
	case 4:
		if inRing {
			return ""
		}
		return ":"
	}
	panic("bad bond type")
}
func canonicalSMILES(m *Molecule, elements map[string]Element) string {
	start := 0
	for i, r := range m.Ranks {
		if r == 1 {
			start = i
			break
		}
	}
	visited := make([]bool, len(m.Atoms))
	visitOrder := make([]int, len(m.Atoms))
	classification := make([]int, len(m.Bonds))
	children := make([][][2]int, len(m.Atoms))
	serial := 0
	var visit func(int, int)
	visit = func(a, parentEdge int) {
		visited[a] = true
		serial++
		visitOrder[a] = serial
		neighbors := slices.Clone(m.Adjacent[a])
		sort.Slice(neighbors, func(i, j int) bool {
			return m.Ranks[m.Bonds[neighbors[i]].Other(a)] < m.Ranks[m.Bonds[neighbors[j]].Other(a)]
		})
		for _, e := range neighbors {
			if e == parentEdge || classification[e] == 2 {
				continue
			}
			b := m.Bonds[e].Other(a)
			if !visited[b] {
				classification[e] = 1
				children[a] = append(children[a], [2]int{b, e})
				visit(b, e)
			} else {
				classification[e] = 2
			}
		}
	}
	visit(start, -1)
	assignments := map[int]int{}
	used := map[int]bool{}
	numberText := func(n int) string {
		if n <= 9 {
			return strconv.Itoa(n)
		}
		return fmt.Sprintf("%%%02d", n)
	}
	var write func(int) string
	write = func(a int) string {
		var out strings.Builder
		out.WriteString(atomNotation(m, a, elements))
		closures := []int{}
		for _, e := range m.Adjacent[a] {
			if classification[e] == 2 {
				closures = append(closures, e)
			}
		}
		sort.Slice(closures, func(i, j int) bool {
			return visitOrder[m.Bonds[closures[i]].Other(a)] < visitOrder[m.Bonds[closures[j]].Other(a)]
		})
		for _, e := range closures {
			if number, ok := assignments[e]; ok {
				out.WriteString(numberText(number))
				delete(assignments, e)
				delete(used, number)
			} else {
				number := 1
				for used[number] {
					number++
				}
				assignments[e] = number
				used[number] = true
				out.WriteString(canonicalBond(m, m.Bonds[e]))
				out.WriteString(numberText(number))
			}
		}
		for i, child := range children[a] {
			text := canonicalBond(m, m.Bonds[child[1]]) + write(child[0])
			if i+1 < len(children[a]) {
				out.WriteString("(" + text + ")")
			} else {
				out.WriteString(text)
			}
		}
		return out.String()
	}
	return write(start)
}
