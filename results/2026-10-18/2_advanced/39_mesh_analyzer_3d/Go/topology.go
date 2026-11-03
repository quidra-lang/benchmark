package main

import "sort"

type Edge [2]int

func triangleEdges(v [3]int) [3]Edge { return [3]Edge{{v[0], v[1]}, {v[1], v[2]}, {v[2], v[0]}} }
func keyEdge(a, b int) Edge          { return Edge{min(a, b), max(a, b)} }
func sortedInts(set map[int]bool) []int {
	values := []int{}
	for v := range set {
		values = append(values, v)
	}
	sort.Ints(values)
	return values
}
func edgeLess(a, b Edge) bool {
	if a[0] != b[0] {
		return a[0] < b[0]
	}
	return a[1] < b[1]
}
func edgeTable(faces []*Face) (map[Edge][]int, []Edge) {
	edges := map[Edge][]int{}
	for i, f := range faces {
		for _, e := range triangleEdges(f.Vertices) {
			key := keyEdge(e[0], e[1])
			edges[key] = append(edges[key], i+1)
		}
	}
	order := []Edge{}
	for e := range edges {
		order = append(order, e)
	}
	sort.Slice(order, func(i, j int) bool { return edgeLess(order[i], order[j]) })
	return edges, order
}
func connectedComponents(ids []int, neighbors map[int]map[int]bool) [][]int {
	unseen := map[int]bool{}
	for _, id := range ids {
		unseen[id] = true
	}
	components := [][]int{}
	for _, seed := range ids {
		if !unseen[seed] {
			continue
		}
		delete(unseen, seed)
		queue := []int{seed}
		for head := 0; head < len(queue); head++ {
			for _, other := range sortedInts(neighbors[queue[head]]) {
				if unseen[other] {
					delete(unseen, other)
					queue = append(queue, other)
				}
			}
		}
		sort.Ints(queue)
		components = append(components, queue)
	}
	return components
}
func vertexFans(vertex int, faces []*Face, edges map[Edge][]int, order []Edge) [][]int {
	ids := []int{}
	for i, f := range faces {
		for _, v := range f.Vertices {
			if v == vertex {
				ids = append(ids, i+1)
				break
			}
		}
	}
	neighbors := map[int]map[int]bool{}
	for _, e := range order {
		if e[0] != vertex && e[1] != vertex {
			continue
		}
		for _, first := range edges[e] {
			if neighbors[first] == nil {
				neighbors[first] = map[int]bool{}
			}
			for _, second := range edges[e] {
				if second != first {
					neighbors[first][second] = true
				}
			}
		}
	}
	return connectedComponents(ids, neighbors)
}

type TopologyComponent struct {
	Number                               int
	Faces, Vertices, NonmanifoldVertices []int
	Edges, Boundary, Nonmanifold         []Edge
}
type Mesh struct {
	Edges               map[Edge][]int
	EdgeOrder           []Edge
	Components          []*TopologyComponent
	FaceComponents      map[int]int
	Fans                map[int][][]int
	NonmanifoldVertices []int
}

func analyzeMesh(faces []*Face) *Mesh {
	edges, order := edgeTable(faces)
	m := &Mesh{Edges: edges, EdgeOrder: order, FaceComponents: map[int]int{}, Fans: map[int][][]int{}}
	neighbors := map[int]map[int]bool{}
	ids := []int{}
	for i := range faces {
		ids = append(ids, i+1)
		neighbors[i+1] = map[int]bool{}
	}
	for _, adjacent := range edges {
		for _, a := range adjacent {
			for _, b := range adjacent {
				if a != b {
					neighbors[a][b] = true
				}
			}
		}
	}
	for number, group := range connectedComponents(ids, neighbors) {
		c := &TopologyComponent{Number: number + 1, Faces: group}
		vertices := map[int]bool{}
		for _, id := range group {
			m.FaceComponents[id] = number + 1
			for _, v := range faces[id-1].Vertices {
				vertices[v] = true
			}
		}
		c.Vertices = sortedInts(vertices)
		for _, e := range order {
			if m.FaceComponents[edges[e][0]] == number+1 {
				c.Edges = append(c.Edges, e)
				if len(edges[e]) == 1 {
					c.Boundary = append(c.Boundary, e)
				} else if len(edges[e]) >= 3 {
					c.Nonmanifold = append(c.Nonmanifold, e)
				}
			}
		}
		m.Components = append(m.Components, c)
	}
	used := map[int]bool{}
	for _, f := range faces {
		for _, v := range f.Vertices {
			used[v] = true
		}
	}
	for _, v := range sortedInts(used) {
		m.Fans[v] = vertexFans(v, faces, edges, order)
		if len(m.Fans[v]) >= 2 {
			m.NonmanifoldVertices = append(m.NonmanifoldVertices, v)
		}
	}
	for _, c := range m.Components {
		for _, v := range c.Vertices {
			count := 0
			for _, fan := range m.Fans[v] {
				if len(fan) > 0 && m.FaceComponents[fan[0]] == c.Number {
					count++
				}
			}
			if count >= 2 {
				c.NonmanifoldVertices = append(c.NonmanifoldVertices, v)
			}
		}
	}
	return m
}

type BoundaryLoop struct {
	Number, Component, Length int
	Vertices                  []int
	Kind                      string
	Filled                    bool
}

func boundaryLoops(faces []*Face, m *Mesh) []*BoundaryLoop {
	loops := []*BoundaryLoop{}
	for _, c := range m.Components {
		unused := map[Edge]bool{}
		for _, e := range c.Boundary {
			unused[e] = true
		}
		for _, first := range c.Boundary {
			if !unused[first] {
				continue
			}
			delete(unused, first)
			a, b := first[0], first[1]
			sequence := []int{a, b}
			current := b
			for current != a {
				other := -1
				var chosen Edge
				for e := range unused {
					if e[0] != current && e[1] != current {
						continue
					}
					v := e[0]
					if v == current {
						v = e[1]
					}
					if other < 0 || v < other {
						other = v
						chosen = e
					}
				}
				if other < 0 {
					break
				}
				delete(unused, chosen)
				sequence = append(sequence, other)
				current = other
			}
			kind := "open"
			length := len(sequence) - 1
			if sequence[len(sequence)-1] == a {
				sequence = sequence[:len(sequence)-1]
				length = len(sequence)
				count := 0
				for i, u := range sequence {
					v := sequence[(i+1)%length]
					e := keyEdge(u, v)
					if hasDirected(faces[m.Edges[e][0]-1].Vertices, u, v) {
						count++
					}
				}
				kind = "mixed"
				if count == length {
					kind = "coherent"
				} else if count == 0 {
					kind = "coherent"
					for i, j := 1, len(sequence)-1; i < j; i, j = i+1, j-1 {
						sequence[i], sequence[j] = sequence[j], sequence[i]
					}
				}
			}
			loops = append(loops, &BoundaryLoop{Number: len(loops) + 1, Component: c.Number, Length: length, Vertices: sequence, Kind: kind})
		}
	}
	return loops
}
