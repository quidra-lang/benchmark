package main

import (
	"math/big"
	"slices"
	"sort"
)

type RingCandidate struct {
	Atoms []int
	Bonds *big.Int
}

func canonicalRing(ring []int) []int {
	first := 0
	for i, a := range ring {
		if a < ring[first] {
			first = i
		}
	}
	direction := 1
	if ring[(first+1)%len(ring)] > ring[(first+len(ring)-1)%len(ring)] {
		direction = -1
	}
	out := make([]int, len(ring))
	for i := range out {
		out[i] = ring[(first+direction*i+len(ring))%len(ring)]
	}
	return out
}
func detectRings(m *Molecule) {
	n := len(m.Atoms)
	candidates := []RingCandidate{}
	seen := map[string]bool{}
	bondIndex := map[[2]int]int{}
	for e, b := range m.Bonds {
		bondIndex[[2]int{b.A, b.B}] = e
	}
	for root := 0; root < n; root++ {
		parent := make([]int, n)
		for i := range parent {
			parent[i] = -2
		}
		parent[root] = -1
		queue := []int{root}
		for h := 0; h < len(queue); h++ {
			a := queue[h]
			for _, e := range m.Adjacent[a] {
				b := m.Bonds[e].Other(a)
				if parent[b] == -2 {
					parent[b] = a
					queue = append(queue, b)
				}
			}
		}
		path := func(a int) []int {
			out := []int{}
			for a >= 0 {
				out = append(out, a)
				a = parent[a]
			}
			return out
		}
		for _, b := range m.Bonds {
			if parent[b.A] == b.B || parent[b.B] == b.A {
				continue
			}
			px, py := path(b.A), path(b.B)
			set := map[int]bool{}
			for _, a := range px[:len(px)-1] {
				set[a] = true
			}
			overlap := false
			for _, a := range py[:len(py)-1] {
				if set[a] {
					overlap = true
					break
				}
			}
			if overlap {
				continue
			}
			atoms := slices.Clone(px)
			slices.Reverse(atoms)
			atoms = append(atoms, py[:len(py)-1]...)
			vector := new(big.Int)
			for i, a := range atoms {
				b := atoms[(i+1)%len(atoms)]
				if a > b {
					a, b = b, a
				}
				vector.SetBit(vector, bondIndex[[2]int{a, b}], 1)
			}
			key := vector.Text(16)
			if !seen[key] {
				seen[key] = true
				candidates = append(candidates, RingCandidate{atoms, vector})
			}
		}
	}
	sort.SliceStable(candidates, func(i, j int) bool { return len(candidates[i].Atoms) < len(candidates[j].Atoms) })
	basis := map[int]*big.Int{}
	m.RingAtoms = make([]bool, n)
	for _, candidate := range candidates {
		reduced := new(big.Int).Set(candidate.Bonds)
		for reduced.Sign() != 0 {
			pivot := reduced.BitLen() - 1
			if old := basis[pivot]; old != nil {
				reduced.Xor(reduced, old)
			} else {
				basis[pivot] = new(big.Int).Set(reduced)
				m.Rings = append(m.Rings, canonicalRing(candidate.Atoms))
				for _, a := range candidate.Atoms {
					m.RingAtoms[a] = true
				}
				for e, b := range m.Bonds {
					if candidate.Bonds.Bit(e) != 0 {
						b.Ring = true
					}
				}
				break
			}
		}
	}
	sort.Slice(m.Rings, func(i, j int) bool {
		a, b := m.Rings[i], m.Rings[j]
		if len(a) != len(b) {
			return len(a) < len(b)
		}
		return slices.Compare(a, b) < 0
	})
}
func kekulize(m *Molecule, elements map[string]Element) *ParseError {
	need := make([]bool, len(m.Atoms))
	for i := range m.Atoms {
		need[i] = m.NeedsPi(i, elements, true)
	}
	seen := make([]bool, len(m.Atoms))
	paired := make([]int, len(m.Atoms))
	for i := range paired {
		paired[i] = -1
	}
	for first := range m.Atoms {
		if !need[first] || seen[first] {
			continue
		}
		system := []int{first}
		seen[first] = true
		for h := 0; h < len(system); h++ {
			u := system[h]
			for _, e := range m.Adjacent[u] {
				b := m.Bonds[e]
				v := b.Other(u)
				if b.Type == 4 && need[v] && !seen[v] {
					seen[v] = true
					system = append(system, v)
				}
			}
		}
		slices.Sort(system)
		member := make([]bool, len(m.Atoms))
		for _, a := range system {
			member[a] = true
		}
		var match func() bool
		match = func() bool {
			u := -1
			for _, a := range system {
				if paired[a] < 0 {
					u = a
					break
				}
			}
			if u < 0 {
				return true
			}
			for _, e := range m.Adjacent[u] {
				bond := m.Bonds[e]
				v := bond.Other(u)
				if bond.Type != 4 || !member[v] || paired[v] >= 0 {
					continue
				}
				paired[u], paired[v] = v, u
				if match() {
					return true
				}
				paired[u], paired[v] = -1, -1
			}
			return false
		}
		if !match() {
			return &ParseError{"kekulization failed", m.Atoms[first].Column}
		}
	}
	for _, b := range m.Bonds {
		b.Multiplicity = b.Type
		if b.Type == 4 {
			b.Multiplicity = 1
			if paired[b.A] == b.B {
				b.Multiplicity = 2
			}
		}
	}
	return nil
}
