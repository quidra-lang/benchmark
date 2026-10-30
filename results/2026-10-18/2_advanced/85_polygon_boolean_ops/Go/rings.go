package main

import (
	"math"
	"slices"
	"sort"
)

type Ring []Point

func insideRing(p Point, ring Ring) bool {
	inside := false
	for i, u := range ring {
		w := ring[(i+1)%len(ring)]
		if (u.Y.Cmp(p.Y) > 0) == (w.Y.Cmp(p.Y) > 0) {
			continue
		}
		lo, hi := u, w
		if lo.Y.Cmp(hi.Y) > 0 {
			lo, hi = hi, lo
		}
		if cross(lo, hi, p).Sign() > 0 {
			inside = !inside
		}
	}
	return inside
}
func interior(p Point, rings []Ring) bool {
	inside := false
	for _, ring := range rings {
		if insideRing(p, ring) {
			inside = !inside
		}
	}
	return inside
}
func boundary(p Point, ring Ring) bool {
	for i, a := range ring {
		if onSegment(p, a, ring[(i+1)%len(ring)]) {
			return true
		}
	}
	return false
}
func rotate(ring Ring) Ring {
	first := 0
	for i, p := range ring {
		if pointLess(p, ring[first]) {
			first = i
		}
	}
	out := append(slices.Clone(ring[first:]), ring[:first]...)
	return out
}
func ccw(ring Ring) bool { return cross(ring[len(ring)-1], ring[0], ring[1]).Sign() > 0 }
func reverse(ring Ring) Ring {
	out := make(Ring, len(ring))
	out[0] = ring[0]
	for i := 1; i < len(ring); i++ {
		out[i] = ring[len(ring)-i]
	}
	return out
}
func normalize(ring Ring, outer bool) Ring {
	out := rotate(ring)
	if ccw(out) != outer {
		out = reverse(out)
	}
	return out
}
func canonical(input []Ring) *Polygon {
	p := &Polygon{Input: make([]Ring, len(input)), Rings: make([]Ring, len(input))}
	for i, ring := range input {
		p.Input[i] = slices.Clone(ring)
		p.Rings[i] = normalize(ring, i == 0)
	}
	sort.Slice(p.Rings[1:], func(i, j int) bool { return pointLess(p.Rings[i+1][0], p.Rings[j+1][0]) })
	return p
}
func assemble(input []Ring) []*Polygon {
	rings := make([]Ring, len(input))
	depth := make([]int, len(input))
	for i, r := range input {
		rings[i] = rotate(r)
	}
	for i, r := range rings {
		for j, other := range rings {
			if i != j && insideRing(r[0], other) {
				depth[i]++
			}
		}
		if ccw(r) != (depth[i]%2 == 0) {
			rings[i] = reverse(r)
		}
	}
	outer := []int{}
	for i := range rings {
		if depth[i]%2 == 0 {
			outer = append(outer, i)
		}
	}
	sort.Slice(outer, func(i, j int) bool { return pointLess(rings[outer[i]][0], rings[outer[j]][0]) })
	out := []*Polygon{}
	for _, i := range outer {
		holes := []Ring{}
		for j, r := range rings {
			if depth[j] == depth[i]+1 && insideRing(r[0], rings[i]) {
				holes = append(holes, r)
			}
		}
		sort.Slice(holes, func(i, j int) bool { return pointLess(holes[i][0], holes[j][0]) })
		out = append(out, &Polygon{Rings: append([]Ring{rings[i]}, holes...)})
	}
	return out
}
func ringArea(ring Ring) float64 {
	sum := 0.0
	for i, p := range ring {
		q := ring[(i+1)%len(ring)]
		sum += p.X.Real()*q.Y.Real() - q.X.Real()*p.Y.Real()
	}
	return sum / 2
}
func ringPerimeter(ring Ring) float64 {
	sum := 0.0
	for i, p := range ring {
		q := ring[(i+1)%len(ring)]
		dx, dy := q.X.Real()-p.X.Real(), q.Y.Real()-p.Y.Real()
		sum += math.Sqrt(dx*dx + dy*dy)
	}
	return sum
}
func flatten(polygons []*Polygon) []Ring {
	out := []Ring{}
	for _, p := range polygons {
		out = append(out, p.Rings...)
	}
	return out
}
func totalArea(polygons []*Polygon) float64 {
	sum := 0.0
	for _, ring := range flatten(polygons) {
		sum += ringArea(ring)
	}
	return sum
}
