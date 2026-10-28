package main

import "sort"

type Tree struct {
	Adj            map[int]map[int]float64
	Next, Negative int
}
type Rooted struct {
	Root     int
	Parent   map[int]int
	Children map[int][]int
	Masks    map[int]int
	All      int
}

func newTree(n int) Tree { return Tree{Adj: map[int]map[int]float64{}, Next: n} }
func (t *Tree) connect(a, b int, length float64) {
	if t.Adj[a] == nil {
		t.Adj[a] = map[int]float64{}
	}
	if t.Adj[b] == nil {
		t.Adj[b] = map[int]float64{}
	}
	t.Adj[a][b],
		t.Adj[b][a] = length, length
}
func (t *Tree) disconnect(a, b int) { delete(t.Adj[a], b); delete(t.Adj[b], a) }
func (t Tree) copy() Tree {
	v := newTree(t.Next)
	v.Negative = t.Negative
	for a, neighbors := range t.Adj {
		v.Adj[a] = map[int]float64{}
		for b, length := range neighbors {
			v.Adj[a][b] = length
		}
	}
	return v
}
func (t Tree) leaves(n int) []int {
	var a []int
	for i := 0; i < n; i++ {
		if len(t.Adj[i]) > 0 {
			a = append(a, i)
		}
	}
	return a
}
func minimumName(mask int, taxa []Record) string {
	s := ""
	for i, t := range taxa {
		if mask>>i&1 != 0 && (s == "" || t.Name < s) {
			s = t.Name
		}
	}
	return s
}
func rootTree(t Tree, taxa []Record, outgroup int) Rooted {
	root := -1
	for v := range t.Adj[outgroup] {
		root = v
	}
	r := Rooted{Root: root,
		Parent: map[int]int{}, Children: map[int][]int{}, Masks: map[int]int{}}
	var visit func(int, int) int
	visit = func(v,
		parent int) int {
		r.Parent[v] = parent
		if v < len(taxa) {
			r.Masks[v] = 1 << v
			return 1 << v
		}
		mask := 0
		var children []int
		for c := range t.Adj[v] {
			if c != parent {
				children = append(children,
					c)
			}
		}
		sort.Ints(children)
		for _, c := range children {
			mask |= visit(c, v)
		}
		sort.Slice(children, func(i,
			j int) bool {
			return minimumName(r.Masks[children[i]], taxa) < minimumName(r.Masks[children[j]], taxa)
		})
		r.Children[v] = children
		r.Masks[v] = mask
		return mask
	}
	all := visit(root,
		-1)
	r.All = all &^ (1 << outgroup)
	r.Masks[root] = r.All
	return r
}
func splitSet(t Tree, taxa []Record, outgroup int) map[int]bool {
	r := rootTree(t, taxa, outgroup)
	s := map[int]bool{}
	for v, mask := range r.Masks {
		if v >= len(taxa) && v != r.Root {
			s[mask] = true
		}
	}
	return s
}
func neighborJoining(matrix [][]float64, list []int, n int) Tree {
	t := newTree(n)
	d := make([][]float64,
		3*n)
	for i := range d {
		d[i] = make([]float64, 3*n)
		if i < n {
			copy(d[i], matrix[i])
		}
	}
	active := append([]int(nil),
		list...)
	for len(active) >= 4 {
		r := len(active)
		totals := map[int]float64{}
		for _, x := range active {
			s := 0.0
			for _, y := range active {
				if y != x {
					s += d[x][y]
				}
			}
			totals[x] = s
		}
		bi, bj := 0, 1
		best := float64(r-2)*d[active[0]][active[1]] - totals[active[0]] - totals[active[1]]
		for i := 0; i < r; i++ {
			for j := i + 1; j < r; j++ {
				q := float64(r-2)*d[active[i]][active[j]] - totals[active[i]] - totals[active[j]]
				if q < best {
					bi,
						bj, best = i, j, q
				}
			}
		}
		i, j := active[bi], active[bj]
		u := t.Next
		t.Next++
		li := d[i][j]/2 + (totals[i]-totals[j])/(2*float64(r-2))
		t.connect(i,
			u, li)
		t.connect(j, u, d[i][j]-li)
		var next []int
		for _, k := range active {
			if k != i && k != j {
				d[u][k] = (d[i][k] + d[j][k] - d[i][j]) / 2
				d[k][u] = d[u][k]
				next = append(next,
					k)
			}
		}
		active = append(next, u)
	}
	a, b, c := active[0], active[1], active[2]
	z := t.Next
	t.Next++
	t.connect(a,
		z, (d[a][b]+d[a][c]-d[b][c])/2)
	t.connect(b, z, (d[a][b]+d[b][c]-d[a][c])/2)
	t.connect(c, z, (d[a][c]+d[b][c]-d[a][b])/2)
	for a, neighbors := range t.Adj {
		for b, length := range neighbors {
			if a < b && length < 0 {
				t.Negative++
				t.Adj[a][b],
					t.Adj[b][a] = 0, 0
			}
		}
	}
	return t
}
func path(t Tree, a, b int) (float64, int) {
	var find func(int, int, float64, int) (float64, int, bool)
	find = func(v,
		parent int, length float64, edges int) (float64, int, bool) {
		if v == b {
			return length, edges, true
		}
		neighbors := make([]int,
			0, len(t.Adj[v]))
		for u := range t.Adj[v] {
			neighbors = append(neighbors, u)
		}
		sort.Ints(neighbors)
		for _, u := range neighbors {
			if u != parent {
				if l, n, ok := find(u, v, length+t.Adj[v][u], edges+1); ok {
					return l,
						n, true
				}
			}
		}
		return 0, 0, false
	}
	l, n, _ := find(a, -1, 0, 0)
	return l, n
}
func patristic(t Tree, n int) [][]float64 {
	d := make([][]float64, n)
	for i := range d {
		d[i] = make([]float64, n)
		for j := 0; j < n; j++ {
			d[i][j], _ = path(t, i, j)
		}
	}
	return d
}
