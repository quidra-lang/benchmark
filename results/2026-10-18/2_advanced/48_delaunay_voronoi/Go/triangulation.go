package main

import "sort"

type Triangulation struct {
	Points   []Point
	Directed map[Edge]int
	Initial  Triangle
}
type Insertion struct {
	Site                            int
	Kind                            string
	Containing                      Triangle
	Visible, Flips, Triangles, Hull int
}

func canonical(a, b, c int) Triangle {
	if b < a && b < c {
		return Triangle{b, c, a}
	}
	if c < a && c < b {
		return Triangle{c, a, b}
	}
	return Triangle{a, b, c}
}
func newTriangulation(points []Point) *Triangulation {
	initial := Triangle{1, 2, 3}
	if orient(points[1], points[2], points[3]) < 0 {
		initial = Triangle{1, 3, 2}
	}
	mesh := &Triangulation{points, map[Edge]int{}, initial}
	mesh.add(initial)
	return mesh
}
func (m *Triangulation) add(t Triangle) {
	for i, e := range triangleEdges(t) {
		m.Directed[e] = t[(i+2)%3]
	}
}
func (m *Triangulation) remove(t Triangle) {
	for _, e := range triangleEdges(t) {
		delete(m.Directed, e)
	}
}
func (m *Triangulation) triangles() []Triangle {
	out := []Triangle{}
	for e, c := range m.Directed {
		if e[0] < e[1] && e[0] < c {
			out = append(out, Triangle{e[0], e[1], c})
		}
	}
	sort.Slice(out, func(i, j int) bool {
		for k := 0; k < 3; k++ {
			if out[i][k] != out[j][k] {
				return out[i][k] < out[j][k]
			}
		}
		return false
	})
	return out
}
func (m *Triangulation) hullEdges() []Edge {
	out := []Edge{}
	for e := range m.Directed {
		if _, ok := m.Directed[Edge{e[1], e[0]}]; !ok {
			out = append(out, e)
		}
	}
	sort.Slice(out, func(i, j int) bool { return edgeLess(out[i], out[j]) })
	return out
}
func (m *Triangulation) insert(s int) Insertion {
	result := Insertion{Site: s, Kind: "outside"}
	pending := map[Edge]bool{}
	for _, t := range m.triangles() {
		inside := true
		for _, e := range triangleEdges(t) {
			if orient(m.Points[e[0]], m.Points[e[1]], m.Points[s]) <= 0 {
				inside = false
			}
		}
		if inside {
			result.Kind = "inside"
			result.Containing = t
			m.remove(t)
			for _, e := range triangleEdges(t) {
				pending[e] = true
			}
			break
		}
	}
	if result.Kind == "outside" {
		for _, e := range m.hullEdges() {
			if orient(m.Points[e[0]], m.Points[e[1]], m.Points[s]) < 0 {
				pending[Edge{e[1], e[0]}] = true
			}
		}
		result.Visible = len(pending)
	}
	for e := range pending {
		m.add(Triangle{e[0], e[1], s})
	}
	for len(pending) > 0 {
		first := true
		var e Edge
		for candidate := range pending {
			if first || edgeLess(candidate, e) {
				e = candidate
				first = false
			}
		}
		delete(pending, e)
		a, b := e[0], e[1]
		q, ok := m.Directed[Edge{b, a}]
		if ok && m.Directed[e] == s && incircle(m.Points[a], m.Points[b], m.Points[s], m.Points[q]) > 0 {
			m.remove(Triangle{a, b, s})
			m.remove(Triangle{b, a, q})
			m.add(Triangle{a, q, s})
			m.add(Triangle{q, b, s})
			pending[Edge{a, q}] = true
			pending[Edge{q, b}] = true
			result.Flips++
		}
	}
	result.Triangles = len(m.Directed) / 3
	result.Hull = len(m.hullEdges())
	return result
}
func (m *Triangulation) visibilityWalk(query Point, triangles []Triangle, edgeTriangles map[Edge]int) ([]int, Edge) {
	path := []int{1}
	for {
		current := path[len(path)-1]
		following := 0
		for _, e := range triangleEdges(triangles[current]) {
			if orient(m.Points[e[0]], m.Points[e[1]], query) < 0 {
				following = edgeTriangles[Edge{e[1], e[0]}]
				if following == 0 {
					return path, orderedEdge(e[0], e[1])
				}
				break
			}
		}
		if following == 0 {
			return path, Edge{}
		}
		path = append(path, following)
	}
}
