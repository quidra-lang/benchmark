package main

import "sort"

type Branch struct{ U, V, Mask int }

func merge(a, b int) (int, int) {
	if a&b != 0 {
		return a & b, 0
	}
	return a | b, 1
}
func provisional(t Tree, taxa []Record, outgroup, column int) (map[int]int, int, int) {
	r := rootTree(t, taxa,
		outgroup)
	sets := map[int]int{}
	changes := 0
	var visit func(int) int
	visit = func(v int) int {
		if v < len(taxa) {
			sets[v] = baseSets[taxa[v].Sequence[column]]
			return sets[v]
		}
		var parts []int
		for _, c := range r.Children[v] {
			if v == r.Root && c == outgroup {
				continue
			}
			parts = append(parts, visit(c))
		}
		s,
			delta := merge(parts[0], parts[1])
		changes += delta
		sets[v] = s
		return s
	}
	rootSet := visit(r.Root)
	sets[outgroup] = baseSets[taxa[outgroup].Sequence[column]]
	combined,
		delta := merge(rootSet, sets[outgroup])
	changes += delta
	return sets, changes, combined
}
func parsimonyScore(t Tree, taxa []Record, outgroup, length int) int {
	score := 0
	for col := 0; col < length; col++ {
		_,
			n, _ := provisional(t, taxa, outgroup, col)
		score += n
	}
	return score
}
func firstBase(mask int) int {
	for b := 1; b <= 8; b <<= 1 {
		if mask&b != 0 {
			return b
		}
	}
	return 1
}
func reconstruct(t Tree, taxa []Record, outgroup, length int) (Tree, map[int]string, map[int]int, []int) {
	r := rootTree(t,
		taxa, outgroup)
	seq := map[int]string{}
	changes := map[int]int{}
	columns := make([]int, length)
	for col := 0; col < length; col++ {
		sets,
			n, combined := provisional(t, taxa, outgroup, col)
		columns[col] = n
		state := map[int]int{}
		x0 := firstBase(combined)
		state[r.Root] = x0
		if sets[r.Root]&x0 == 0 {
			state[r.Root] = firstBase(sets[r.Root])
		}
		state[outgroup] = x0
		if sets[outgroup]&x0 == 0 {
			state[outgroup] = firstBase(sets[outgroup])
		}
		var assign func(int)
		assign = func(v int) {
			for _, c := range r.Children[v] {
				if c == outgroup {
					continue
				}
				state[c] = state[v]
				if sets[c]&state[v] == 0 {
					state[c] = firstBase(sets[c])
				}
				assign(c)
			}
		}
		assign(r.Root)
		for v, mask := range r.Masks {
			if v >= len(taxa) {
				b := byte('A')
				switch state[v] {
				case 2:
					b = 'C'
				case 4:
					b = 'G'
				case 8:
					b = 'T'
				}
				seq[mask] += string(b)
			}
			if v != r.Root {
				branchMask := mask
				if v == outgroup {
					branchMask = r.All
				}
				if state[v] != state[r.Parent[v]] {
					changes[branchMask]++
				}
			}
		}
	}
	result := t.copy()
	for _, b := range branches(t, taxa, outgroup) {
		result.Adj[b.U][b.V] = float64(changes[b.Mask]) / float64(length)
		result.Adj[b.V][b.U] = result.Adj[b.U][b.V]
	}
	return result,
		seq, changes, columns
}
func branches(t Tree, taxa []Record, outgroup int) []Branch {
	r := rootTree(t, taxa, outgroup)
	var a []Branch
	for v, p := range r.Parent {
		if v == r.Root {
			continue
		}
		mask := r.Masks[v]
		if v == outgroup {
			mask = r.All
		}
		a = append(a,
			Branch{p, v, mask})
	}
	sort.Slice(a, func(i, j int) bool { return a[i].Mask < a[j].Mask })
	return a
}
func insertion(t Tree, b Branch, x int) Tree {
	v := t.copy()
	w := v.Next
	v.Next++
	v.disconnect(b.U, b.V)
	v.connect(b.U,
		w, 0)
	v.connect(b.V, w, 0)
	v.connect(w, x, 0)
	return v
}
func nni(t Tree, b Branch, swap int, taxa []Record, outgroup int) Tree {
	r := rootTree(t, taxa, outgroup)
	u,
		v := b.U, b.V
	s := -1
	for _, child := range r.Children[u] {
		if child != v && child != outgroup {
			s = child
		}
	}
	children := append([]int(nil),
		r.Children[v]...)
	sort.Slice(children, func(i, j int) bool { return r.Masks[children[i]] < r.Masks[children[j]] })
	c := children[swap-1]
	result := t.copy()
	result.disconnect(u,
		s)
	result.disconnect(v, c)
	result.connect(u, c, 0)
	result.connect(v, s, 0)
	return result
}
