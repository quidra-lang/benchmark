package main

import "sort"

type Face struct {
	Triangle, Polygon, Line int
	Group                   string
	Vertices                [3]int
}
type RemovedFace struct {
	Face   *Face
	Reason string
}
type SnappedVertex struct {
	Number        int
	Before, After Vec
}

func splitPolygons(polygons []*Polygon) []*Face {
	triangles := []*Face{}
	for _, p := range polygons {
		for i := 1; i < len(p.Vertices)-1; i++ {
			triangles = append(triangles, &Face{len(triangles) + 1, p.Number, p.Line, p.Group, [3]int{p.Vertices[0], p.Vertices[i], p.Vertices[i+1]}})
		}
	}
	return triangles
}
func floorDiv(a, b int64) int64 {
	q := a / b
	if a%b < 0 {
		q--
	}
	return q
}
func snappedVertices(vertices []Vec, spacing int64) ([]Vec, []SnappedVertex) {
	points := []Vec{{}}
	changed := []SnappedVertex{}
	for i, p := range vertices[1:] {
		var rounded Vec
		for axis, v := range p {
			rounded[axis] = spacing * floorDiv(2*v+spacing, 2*spacing)
		}
		points = append(points, rounded)
		if rounded != p {
			changed = append(changed, SnappedVertex{i + 1, p, rounded})
		}
	}
	return points, changed
}
func representatives(points []Vec, merge bool) []int {
	owner := map[Vec]int{}
	result := make([]int, len(points))
	for i, p := range points {
		if i == 0 {
			continue
		}
		result[i] = i
		if merge {
			if owner[p] == 0 {
				owner[p] = i
			}
			result[i] = owner[p]
		}
	}
	return result
}
func cleanedFaces(triangles []*Face, points []Vec, representative []int, removeZero, removeDuplicate bool) ([]*Face, []RemovedFace) {
	faces := []*Face{}
	removed := []RemovedFace{}
	seen := map[[3]int]bool{}
	for _, triangle := range triangles {
		vertices := [3]int{}
		for i, v := range triangle.Vertices {
			vertices[i] = representative[v]
		}
		a, b, c := vertices[0], vertices[1], vertices[2]
		reason := ""
		if a == b || a == c || b == c {
			reason = "repeated"
		} else if removeZero && cross(subtract(points[b], points[a]), subtract(points[c], points[a])) == (Vec{}) {
			reason = "zero_area"
		}
		if reason == "" {
			key := vertices
			sort.Ints(key[:])
			if removeDuplicate && seen[key] {
				reason = "duplicate"
			} else {
				seen[key] = true
			}
		}
		if reason != "" {
			removed = append(removed, RemovedFace{triangle, reason})
		} else {
			copy := *triangle
			copy.Vertices = vertices
			faces = append(faces, &copy)
		}
	}
	return faces, removed
}
func remapVertices(snapped []Vec, representative []int, faces []*Face, keepUnused bool) ([]Vec, []*Face, map[int]int) {
	present := map[int]bool{}
	if keepUnused {
		for i := 1; i < len(representative); i++ {
			if representative[i] == i {
				present[i] = true
			}
		}
	} else {
		for _, f := range faces {
			for _, v := range f.Vertices {
				present[v] = true
			}
		}
	}
	old := []int{}
	for v := range present {
		old = append(old, v)
	}
	sort.Ints(old)
	points := []Vec{{}}
	renumber := map[int]int{}
	for _, v := range old {
		renumber[v] = len(points)
		points = append(points, snapped[v])
	}
	mapped := []*Face{}
	for _, f := range faces {
		copy := *f
		for i, v := range f.Vertices {
			copy.Vertices[i] = renumber[v]
		}
		mapped = append(mapped, &copy)
	}
	return points, mapped, renumber
}
func fillLoops(faces []*Face, loops []*BoundaryLoop, maxLength int, permitted map[int]bool) ([]*Face, []*Face) {
	added := []*Face{}
	for _, loop := range loops {
		vertices, length := loop.Vertices, loop.Length
		unique := map[int]bool{}
		for _, v := range vertices {
			unique[v] = true
		}
		if loop.Kind != "coherent" || length < 3 || length > maxLength || len(unique) != length || !permitted[loop.Component] {
			continue
		}
		for i := 2; i < length; i++ {
			added = append(added, &Face{Group: "fill", Vertices: [3]int{vertices[0], vertices[i], vertices[i-1]}})
		}
		loop.Filled = true
	}
	return append(append([]*Face(nil), faces...), added...), added
}
