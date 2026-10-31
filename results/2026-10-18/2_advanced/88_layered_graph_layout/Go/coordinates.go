package main

import (
	"slices"
	"sort"
)

type BKVariant struct {
	Name                     string
	Root, Aligned            []int
	Blocks, Width, Low, High int
}
type Coordinates struct {
	Marked   map[[2]int]bool
	Variants []BKVariant
	Smallest int
}

func segmentKey(a, b int) [2]int {
	if a > b {
		a, b = b, a
	}
	return [2]int{a, b}
}
func separation(g *Layout, a, b int) int {
	gap := g.Block.Settings.DummySep
	if a < g.N && b < g.N {
		gap = g.Block.Settings.NodeSep
	}
	return g.Vertices[a].Right + g.Vertices[b].Left + 1 + gap
}
func floorDiv(a, b int) int {
	q := a / b
	if a < 0 && a%b != 0 {
		q--
	}
	return q
}
func coordinates(g *Layout) *Coordinates {
	result := &Coordinates{Marked: map[[2]int]bool{}}
	count := len(g.Vertices)
	pos := positions(g.Orders, count)
	for i := 0; i+1 < len(g.Orders); i++ {
		upper, lower := g.Orders[i], g.Orders[i+1]
		k0, start := 0, 0
		for end, v := range lower {
			inner := v >= g.N && g.Vertices[v].Upper[0] >= g.N
			if !inner && end != len(lower)-1 {
				continue
			}
			k1 := len(upper) - 1
			if inner {
				k1 = pos[g.Vertices[v].Upper[0]]
			}
			for _, w := range lower[start : end+1] {
				for _, u := range g.Vertices[w].Upper {
					if pos[u] < k0 || pos[u] > k1 {
						result.Marked[segmentKey(u, w)] = true
					}
				}
			}
			start = end + 1
			k0 = k1
		}
	}
	for _, name := range []string{"ul", "ur", "dl", "dr"} {
		right, down := name[1] == 'r', name[0] == 'd'
		root, align := make([]int, count), make([]int, count)
		for v := 0; v < count; v++ {
			root[v], align[v] = v, v
		}
		rank := func(v int) int {
			if right {
				return len(g.Orders[g.Vertices[v].Layer]) - 1 - pos[v]
			}
			return pos[v]
		}
		layerOrder := make([]int, len(g.Orders))
		for i := range layerOrder {
			layerOrder[i] = i
		}
		if down {
			slices.Reverse(layerOrder)
		}
		for _, i := range layerOrder[1:] {
			rho := -1
			scan := slices.Clone(g.Orders[i])
			if right {
				slices.Reverse(scan)
			}
			for _, v := range scan {
				reference := g.Vertices[v].Upper
				if down {
					reference = g.Vertices[v].Lower
				}
				if len(reference) == 0 {
					continue
				}
				reference = slices.Clone(reference)
				sort.Slice(reference, func(i, j int) bool { return rank(reference[i]) < rank(reference[j]) })
				for _, median := range []int{(len(reference) - 1) / 2, len(reference) / 2} {
					u := reference[median]
					if align[v] == v && !result.Marked[segmentKey(u, v)] && rho < rank(u) {
						align[u] = v
						root[v] = root[u]
						align[v] = root[v]
						rho = rank(u)
					}
				}
			}
		}
		constraints := map[[2]int]int{}
		for _, row := range g.Orders {
			scan := slices.Clone(row)
			if right {
				slices.Reverse(scan)
			}
			for i := 0; i+1 < len(scan); i++ {
				a, b := scan[i], scan[i+1]
				delta := separation(g, a, b)
				if right {
					delta = separation(g, b, a)
				}
				key := [2]int{root[a], root[b]}
				constraints[key] = max(constraints[key], delta)
			}
		}
		type Weighted struct{ Other, Weight int }
		incoming, outgoing := map[int][]Weighted{}, map[int][]Weighted{}
		roots := map[int]bool{}
		for _, r := range root {
			roots[r] = true
		}
		keys := make([][2]int, 0, len(constraints))
		for key := range constraints {
			keys = append(keys, key)
		}
		sort.Slice(keys, func(i, j int) bool {
			a, b := keys[i], keys[j]
			if a[0] != b[0] {
				return a[0] < b[0]
			}
			return a[1] < b[1]
		})
		for _, key := range keys {
			weight := constraints[key]
			outgoing[key[0]] = append(outgoing[key[0]], Weighted{key[1], weight})
			incoming[key[1]] = append(incoming[key[1]], Weighted{key[0], weight})
		}
		y1, y2 := map[int]int{}, map[int]int{}
		var leftmost, rightmost func(int) int
		leftmost = func(r int) int {
			if value, known := y1[r]; known {
				return value
			}
			value := 0
			for _, edge := range incoming[r] {
				value = max(value, leftmost(edge.Other)+edge.Weight)
			}
			y1[r] = value
			return value
		}
		rightmost = func(r int) int {
			if value, known := y2[r]; known {
				return value
			}
			value := leftmost(r)
			if len(outgoing[r]) > 0 {
				minimum := int(^uint(0) >> 1)
				for _, edge := range outgoing[r] {
					minimum = min(minimum, rightmost(edge.Other)-edge.Weight)
				}
				value = max(value, minimum)
			}
			y2[r] = value
			return value
		}
		variant := BKVariant{Name: name, Root: root, Blocks: len(roots), Aligned: make([]int, count)}
		for v, r := range root {
			x := rightmost(r)
			if right {
				x = -x
			}
			variant.Aligned[v] = x
			low, high := x-g.Vertices[v].Left, x+g.Vertices[v].Right
			if v == 0 || low < variant.Low {
				variant.Low = low
			}
			if v == 0 || high > variant.High {
				variant.High = high
			}
		}
		variant.Width = variant.High - variant.Low + 1
		result.Variants = append(result.Variants, variant)
	}
	for k := 1; k < 4; k++ {
		if result.Variants[k].Width < result.Variants[result.Smallest].Width {
			result.Smallest = k
		}
	}
	best := result.Variants[result.Smallest]
	for k := range result.Variants {
		variant := &result.Variants[k]
		shift := best.Low - variant.Low
		if variant.Name[1] == 'r' {
			shift = best.High - variant.High
		}
		for v := range variant.Aligned {
			variant.Aligned[v] += shift
		}
	}
	for v := 0; v < count; v++ {
		values := []int{}
		for _, variant := range result.Variants {
			values = append(values, variant.Aligned[v])
		}
		slices.Sort(values)
		g.Vertices[v].X = floorDiv(values[1]+values[2], 2)
	}
	minimum := g.Vertices[0].X - g.Vertices[0].Left
	for _, v := range g.Vertices {
		minimum = min(minimum, v.X-v.Left)
	}
	for _, v := range g.Vertices {
		v.X -= minimum
	}
	return result
}
