package main

func hasDirected(triangle [3]int, start, end int) bool {
	for _, e := range triangleEdges(triangle) {
		if e[0] == start && e[1] == end {
			return true
		}
	}
	return false
}
func flip(f *Face) { f.Vertices[1], f.Vertices[2] = f.Vertices[2], f.Vertices[1] }
func inconsistentEdges(faces []*Face, edges map[Edge][]int, order []Edge) []Edge {
	result := []Edge{}
	for _, e := range order {
		adjacent := edges[e]
		if len(adjacent) == 2 {
			a, b := hasDirected(faces[adjacent[0]-1].Vertices, e[0], e[1]), hasDirected(faces[adjacent[1]-1].Vertices, e[0], e[1])
			if a == b {
				result = append(result, e)
			}
		}
	}
	return result
}
func repairOrientation(faces []*Face, edges map[Edge][]int) {
	visited := make([]bool, len(faces)+1)
	for seed := 1; seed <= len(faces); seed++ {
		if visited[seed] {
			continue
		}
		visited[seed] = true
		queue := []int{seed}
		for head := 0; head < len(queue); head++ {
			current := queue[head]
			for _, directed := range triangleEdges(faces[current-1].Vertices) {
				adjacent := edges[keyEdge(directed[0], directed[1])]
				if len(adjacent) != 2 {
					continue
				}
				other := adjacent[0]
				if other == current {
					other = adjacent[1]
				}
				if visited[other] {
					continue
				}
				if hasDirected(faces[other-1].Vertices, directed[0], directed[1]) {
					flip(faces[other-1])
				}
				visited[other] = true
				queue = append(queue, other)
			}
		}
	}
}
func orientableComponents(faces []*Face, mesh *Mesh) map[int]bool {
	copied := []*Face{}
	for _, f := range faces {
		copy := *f
		copied = append(copied, &copy)
	}
	repairOrientation(copied, mesh.Edges)
	violations := inconsistentEdges(copied, mesh.Edges, mesh.EdgeOrder)
	result := map[int]bool{}
	for _, c := range mesh.Components {
		result[c.Number] = true
		set := map[Edge]bool{}
		for _, e := range c.Edges {
			set[e] = true
		}
		for _, e := range violations {
			if set[e] {
				result[c.Number] = false
				break
			}
		}
	}
	return result
}
