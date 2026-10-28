package main

import (
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

func readLines(path string) []string {
	data, err := os.ReadFile(path)
	if err != nil {
		panic(err)
	}
	if len(data) == 0 {
		return nil
	}
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
}
func integer64(text string) int64 {
	v, err := strconv.ParseInt(text, 10, 64)
	if err != nil {
		panic(err)
	}
	return v
}
func yes(v bool) string {
	if v {
		return "yes"
	}
	return "no"
}
func listing(values []int) string {
	if len(values) == 0 {
		return "-"
	}
	parts := []string{}
	for _, v := range values {
		parts = append(parts, fmt.Sprint(v))
	}
	return strings.Join(parts, " ")
}
func stringList(values []string) string {
	if len(values) == 0 {
		return "-"
	}
	return strings.Join(values, " ")
}
func vecText(p Vec) string         { return fmt.Sprintf("%d %d %d", p[0], p[1], p[2]) }
func edgeText(e Edge) string       { return fmt.Sprintf("%d %d", e[0], e[1]) }
func triangleText(v [3]int) string { return fmt.Sprintf("%d %d %d", v[0], v[1], v[2]) }
func optional(v int) string {
	if v == 0 {
		return "-"
	}
	return fmt.Sprint(v)
}

type Query struct {
	Kind string
	Args []int64
}
type Settings struct {
	Snap                                                       int64
	Merge, Degenerate, Duplicates, Orient, Outward, KeepUnused bool
	FillHoles                                                  int
	Sections                                                   []string
	Queries                                                    []Query
}

func readParameters() *Settings {
	s := &Settings{Snap: 1, Merge: true, Degenerate: true, Duplicates: true, Orient: true, Outward: true,
		KeepUnused: true, Sections: []string{"summary", "components"}}
	for _, line := range readLines("input/params.txt") {
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		words := strings.Split(line, " ")
		key, args := words[0], words[1:]
		switch key {
		case "query":
			q := Query{Kind: args[0]}
			for _, a := range args[1:] {
				q.Args = append(q.Args, integer64(a))
			}
			s.Queries = append(s.Queries, q)
		case "sections":
			s.Sections = args
		case "snap":
			s.Snap = integer64(args[0])
		case "fill_holes":
			s.FillHoles = int(integer64(args[0]))
		case "merge":
			s.Merge = args[0] == "on"
		case "degenerate":
			s.Degenerate = args[0] == "on"
		case "duplicates":
			s.Duplicates = args[0] == "on"
		case "orient":
			s.Orient = args[0] == "on"
		case "outward":
			s.Outward = args[0] == "on"
		case "keep_unused":
			s.KeepUnused = args[0] == "on"
		}
	}
	return s
}
func polygonNonplanar(p *Polygon, snapped []Vec) bool {
	first := snapped[p.Vertices[0]]
	var total Vec
	for i := 1; i < len(p.Vertices)-1; i++ {
		n := cross(subtract(snapped[p.Vertices[i]], first), subtract(snapped[p.Vertices[i+1]], first))
		for axis := range 3 {
			total[axis] += n[axis]
		}
	}
	for _, v := range p.Vertices {
		if dot(subtract(snapped[v], first), total) != 0 {
			return true
		}
	}
	return false
}
func edgeShape(edge Edge, faces []*Face, points []Vec, adjacent []int) string {
	if len(adjacent) != 2 {
		return "-"
	}
	a, b := edge[0], edge[1]
	first, second := faces[adjacent[0]-1], faces[adjacent[1]-1]
	if hasDirected(first.Vertices, a, b) == hasDirected(second.Vertices, a, b) {
		return "inconsistent"
	}
	third := 0
	for _, v := range second.Vertices {
		if v != a && v != b {
			third = v
			break
		}
	}
	origin := points[first.Vertices[0]]
	s := dot(subtract(points[third], origin), normal(first, points))
	if s < 0 {
		return "convex"
	}
	if s > 0 {
		return "concave"
	}
	return "flat"
}
func componentConsistency(c *TopologyComponent, inconsistent []Edge) bool {
	set := map[Edge]bool{}
	for _, e := range inconsistent {
		set[e] = true
	}
	for _, e := range c.Edges {
		if set[e] {
			return false
		}
	}
	return true
}
func preliminarySolids(faces []*Face, m *Mesh) map[int]bool {
	bad := inconsistentEdges(faces, m.Edges, m.EdgeOrder)
	solids := map[int]bool{}
	for _, c := range m.Components {
		solids[c.Number] = len(c.Boundary) == 0 && len(c.Nonmanifold) == 0 && len(c.NonmanifoldVertices) == 0 && componentConsistency(c, bad)
	}
	return solids
}
func findNesting(m *Mesh, solids map[int]bool, faces []*Face, points []Vec) map[int][]int {
	inside := map[int][]int{}
	for _, c := range m.Components {
		if !solids[c.Number] {
			continue
		}
		for _, other := range m.Components {
			if other.Number == c.Number || !solids[other.Number] {
				continue
			}
			set := map[int]bool{}
			for _, v := range other.Vertices {
				set[v] = true
			}
			test := 0
			for _, v := range c.Vertices {
				if !set[v] {
					test = v
					break
				}
			}
			if test > 0 && windingNumber(other.Faces, faces, points, points[test]) != 0 {
				inside[c.Number] = append(inside[c.Number], other.Number)
			}
		}
	}
	return inside
}
func applyOutward(faces []*Face, points []Vec, m *Mesh, solids map[int]bool, inside map[int][]int, enabled bool) int {
	count := 0
	if !enabled {
		return count
	}
	for _, c := range m.Components {
		if !solids[c.Number] {
			continue
		}
		signed := volume6(c.Faces, faces, points)
		depth := len(inside[c.Number])
		if signed != 0 && (depth%2 == 0 && signed < 0 || depth%2 == 1 && signed > 0) {
			for _, id := range c.Faces {
				flip(faces[id-1])
			}
			count++
		}
	}
	return count
}

type Component struct {
	Topology                                        *TopologyComponent
	Closed, Manifold, Consistent, Orientable, Solid bool
	Loops, Euler, Genus, Crosscaps                  int
	HasGenus, HasCrosscaps                          bool
	Volume6                                         int64
	Area                                            float64
	Centroid                                        []string
	Normal                                          Vec
	Box                                             [6]int64
	Inside                                          []int
	Angles, Shapes                                  map[string]int
	EdgeMin, EdgeMax                                int64
	ValenceMin, ValenceMax                          int
}

func buildComponents(faces []*Face, points []Vec, m *Mesh, loopCounts map[int]int, orientable map[int]bool, inside map[int][]int) []*Component {
	result := []*Component{}
	bad := inconsistentEdges(faces, m.Edges, m.EdgeOrder)
	for _, c := range m.Components {
		d := &Component{Topology: c, Closed: len(c.Boundary) == 0, Manifold: len(c.Nonmanifold) == 0 && len(c.NonmanifoldVertices) == 0,
			Consistent: componentConsistency(c, bad), Orientable: orientable[c.Number], Loops: loopCounts[c.Number],
			Euler: len(c.Vertices) - len(c.Edges) + len(c.Faces), Angles: map[string]int{}, Shapes: map[string]int{},
			Box: bbox(c.Vertices, points)}
		d.Solid = d.Closed && d.Manifold && d.Consistent
		if d.Manifold && d.Orientable {
			d.HasGenus = true
			d.Genus = int(floorDiv(int64(2-d.Euler-d.Loops), 2))
		} else if d.Manifold {
			d.HasCrosscaps = true
			d.Crosscaps = 2 - d.Euler - d.Loops
		}
		d.Volume6 = volume6(c.Faces, faces, points)
		if d.Solid {
			d.Inside = inside[c.Number]
			if d.Volume6 != 0 {
				center := centroid(c.Faces, faces, points, d.Volume6)
				d.Centroid = center[:]
			}
		}
		chosen := []*Face{}
		for _, id := range c.Faces {
			f := faces[id-1]
			chosen = append(chosen, f)
			n := normal(f, points)
			for axis := range 3 {
				d.Normal[axis] += n[axis]
			}
			d.Angles[triangleAngle(f, points)]++
		}
		d.Area = area(chosen, points)
		degree := map[int]int{}
		for i, e := range c.Edges {
			degree[e[0]]++
			degree[e[1]]++
			length := edgeLengthSquared(e, points)
			if i == 0 {
				d.EdgeMin, d.EdgeMax = length, length
			} else {
				d.EdgeMin = min(d.EdgeMin, length)
				d.EdgeMax = max(d.EdgeMax, length)
			}
			d.Shapes[edgeShape(e, faces, points, m.Edges[e])]++
		}
		for i, v := range c.Vertices {
			if i == 0 {
				d.ValenceMin, d.ValenceMax = degree[v], degree[v]
			} else {
				d.ValenceMin = min(d.ValenceMin, degree[v])
				d.ValenceMax = max(d.ValenceMax, degree[v])
			}
		}
		result = append(result, d)
	}
	return result
}

type Analysis struct {
	Source                                 *Source
	Settings                               *Settings
	Snapped                                []Vec
	SnappedList                            []SnappedVertex
	Representative                         []int
	OriginalToReps                         map[int][]int
	Triangles, Faces, Added                []*Face
	Removed                                []RemovedFace
	Points                                 []Vec
	Renumber                               map[int]int
	InitialFaces                           int
	MeshBefore, Mesh                       *Mesh
	InitialInconsistent, InconsistentAfter []Edge
	LoopsBefore                            []*BoundaryLoop
	Components                             []*Component
	OutwardComponents, FlippedFaces        int
	Nonplanar                              map[int]bool
	GroupOrder                             []string
	GroupFaces                             map[string][]int
}

func analyzeSource(source *Source, s *Settings) *Analysis {
	a := &Analysis{Source: source, Settings: s, Nonplanar: map[int]bool{}, OriginalToReps: map[int][]int{}, GroupFaces: map[string][]int{}}
	a.Snapped, a.SnappedList = snappedVertices(source.Vertices, s.Snap)
	a.Representative = representatives(a.Snapped, s.Merge)
	a.Triangles = splitPolygons(source.Polygons)
	kept, removed := cleanedFaces(a.Triangles, a.Snapped, a.Representative, s.Degenerate, s.Duplicates)
	a.Removed = removed
	points, cleaned, renumber := remapVertices(a.Snapped, a.Representative, kept, s.KeepUnused)
	a.Points, a.Renumber = points, renumber
	a.InitialFaces = len(cleaned)
	initial := make([][3]int, len(cleaned))
	for i, f := range cleaned {
		initial[i] = f.Vertices
	}
	a.MeshBefore = analyzeMesh(cleaned)
	a.InitialInconsistent = inconsistentEdges(cleaned, a.MeshBefore.Edges, a.MeshBefore.EdgeOrder)
	if s.Orient {
		repairOrientation(cleaned, a.MeshBefore.Edges)
	}
	a.InconsistentAfter = inconsistentEdges(cleaned, a.MeshBefore.Edges, a.MeshBefore.EdgeOrder)
	a.LoopsBefore = boundaryLoops(cleaned, a.MeshBefore)
	permitted := map[int]bool{}
	for _, c := range a.MeshBefore.Components {
		if len(c.Nonmanifold) == 0 && componentConsistency(c, a.InconsistentAfter) {
			permitted[c.Number] = true
		}
	}
	a.Faces, a.Added = fillLoops(cleaned, a.LoopsBefore, s.FillHoles, permitted)
	a.Mesh = analyzeMesh(a.Faces)
	solids := preliminarySolids(a.Faces, a.Mesh)
	inside := findNesting(a.Mesh, solids, a.Faces, a.Points)
	a.OutwardComponents = applyOutward(a.Faces, a.Points, a.Mesh, solids, inside, s.Outward)
	for i, f := range a.Faces[:a.InitialFaces] {
		if f.Vertices != initial[i] {
			a.FlippedFaces++
		}
	}
	orientable := orientableComponents(a.Faces, a.Mesh)
	loopsFinal := boundaryLoops(a.Faces, a.Mesh)
	counts := map[int]int{}
	for _, loop := range loopsFinal {
		counts[loop.Component]++
	}
	a.Components = buildComponents(a.Faces, a.Points, a.Mesh, counts, orientable, inside)
	groupSeen := map[string]bool{}
	for _, p := range source.Polygons {
		if polygonNonplanar(p, a.Snapped) {
			a.Nonplanar[p.Number] = true
		}
		if !groupSeen[p.Group] {
			groupSeen[p.Group] = true
			a.GroupOrder = append(a.GroupOrder, p.Group)
		}
	}
	if len(a.Added) > 0 {
		a.GroupOrder = append(a.GroupOrder, "fill")
	}
	for number := 1; number < len(source.Vertices); number++ {
		rep := a.Representative[number]
		a.OriginalToReps[rep] = append(a.OriginalToReps[rep], number)
	}
	for i, f := range a.Faces {
		a.GroupFaces[f.Group] = append(a.GroupFaces[f.Group], i+1)
	}
	return a
}
func mergedCount(a *Analysis) int {
	count := 0
	for i := 1; i < len(a.Representative); i++ {
		if i != a.Representative[i] {
			count++
		}
	}
	return count
}
func sectionSummary(a *Analysis) []string {
	source := a.Source
	sizes := map[int]int{}
	for _, p := range source.Polygons {
		sizes[len(p.Vertices)]++
	}
	removals := map[string]int{}
	for _, r := range a.Removed {
		removals[r.Reason]++
	}
	var totalVolume int64
	solids := 0
	for _, c := range a.Components {
		if c.Solid {
			solids++
			totalVolume += c.Volume6
		}
	}
	filled := 0
	for _, loop := range a.LoopsBefore {
		if loop.Filled {
			filled++
		}
	}
	lines := []string{"[summary]", fmt.Sprintf("lines %d", source.Lines), fmt.Sprintf("vertices %d",
		len(source.Vertices)-1), fmt.Sprintf("polygons %d", len(source.Polygons)), fmt.Sprintf("errors %d",
		len(source.Errors)), fmt.Sprintf("ignored %d", source.Ignored), fmt.Sprintf("nonplanar_polygons %d",
		len(a.Nonplanar))}
	order := []int{}
	for size := range sizes {
		order = append(order, size)
	}
	sort.Ints(order)
	for _, size := range order {
		lines = append(lines, fmt.Sprintf("polygon_size %d %d", size, sizes[size]))
	}
	for _, item := range []struct {
		Name  string
		Value int
	}{{"triangles", len(a.Triangles)}, {"snapped", len(a.SnappedList)}, {"merged", mergedCount(a)}, {"removed_repeated",
		removals["repeated"]}, {"removed_zero_area", removals["zero_area"]}, {"removed_duplicate",
		removals["duplicate"]}, {"faces", a.InitialFaces}, {"inconsistent_before", len(a.InitialInconsistent)},
		{"flipped_faces", a.FlippedFaces}, {"outward_components", a.OutwardComponents}, {"boundary_loops",
			len(a.LoopsBefore)}, {"holes_filled", filled}, {"fill_faces", len(a.Added)}, {"final_vertices",
			len(a.Points) - 1}, {"final_faces", len(a.Faces)}, {"components", len(a.Components)}, {"solids",
			solids}} {
		lines = append(lines, fmt.Sprintf("%s %d", item.Name, item.Value))
	}
	return append(lines, "total_area "+real(area(a.Faces, a.Points)), "total_volume "+fraction(totalVolume, 6))
}
func sectionWarnings(a *Analysis) []string {
	lines := []string{"[warnings]"}
	for _, e := range a.Source.Errors {
		lines = append(lines, fmt.Sprintf("line %d %s", e.Line, e.Kind))
	}
	return lines
}
func sectionCleanup(a *Analysis) []string {
	lines := []string{"[cleanup]", fmt.Sprintf("snapped %d", len(a.SnappedList))}
	for _, v := range a.SnappedList {
		lines = append(lines, fmt.Sprintf("snap %d %s to %s", v.Number, vecText(v.Before), vecText(v.After)))
	}
	lines = append(lines, fmt.Sprintf("merged %d", mergedCount(a)))
	reps := []int{}
	for rep := range a.OriginalToReps {
		reps = append(reps, rep)
	}
	sort.Ints(reps)
	for _, rep := range reps {
		members := a.OriginalToReps[rep]
		if len(members) > 1 {
			lines = append(lines, "merge "+optional(a.Renumber[rep])+" "+listing(members))
		}
	}
	lines = append(lines, fmt.Sprintf("removed %d", len(a.Removed)))
	for _, r := range a.Removed {
		f := r.Face
		lines = append(lines, fmt.Sprintf("remove %d polygon %d line %d %s", f.Triangle, f.Polygon, f.Line, r.Reason))
	}
	return lines
}
func sectionComponents(a *Analysis) []string {
	lines := []string{}
	for _, d := range a.Components {
		c := d.Topology
		present := map[string]bool{}
		for _, id := range c.Faces {
			present[a.Faces[id-1].Group] = true
		}
		groups := []string{}
		for _, g := range a.GroupOrder {
			if present[g] {
				groups = append(groups, g)
			}
		}
		lines = append(lines, fmt.Sprintf("[component %d]", c.Number), "groups "+stringList(groups), fmt.Sprintf("faces %d",
			len(c.Faces)), fmt.Sprintf("vertices %d", len(c.Vertices)), fmt.Sprintf("edges %d", len(c.Edges)),
			fmt.Sprintf("boundary_edges %d", len(c.Boundary)), fmt.Sprintf("nonmanifold_edges %d",
				len(c.Nonmanifold)), fmt.Sprintf("nonmanifold_vertices %d", len(c.NonmanifoldVertices)),
			fmt.Sprintf("boundary_loops %d", d.Loops), "closed "+yes(d.Closed), "manifold "+yes(d.Manifold),
			"orientable "+yes(d.Orientable), "consistent "+yes(d.Consistent), "solid "+yes(d.Solid),
			fmt.Sprintf("euler %d", d.Euler))
		genus := "genus -"
		if d.HasGenus {
			genus = fmt.Sprintf("genus %d", d.Genus)
		} else if d.HasCrosscaps {
			genus = fmt.Sprintf("crosscaps %d", d.Crosscaps)
		}
		volume := "-"
		if d.Solid {
			volume = fraction(d.Volume6, 6)
		}
		box := d.Box
		lines = append(lines, genus, "volume "+volume, "area "+real(d.Area), "normal_sum "+vecText(d.Normal),
			fmt.Sprintf("bbox %d %d %d %d %d %d", box[0], box[1], box[2], box[3], box[4], box[5]),
			"inside "+listing(d.Inside), "centroid "+stringList(d.Centroid))
		for _, name := range []string{"convex", "concave", "flat"} {
			lines = append(lines, fmt.Sprintf("%s %d", name, d.Shapes[name]))
		}
		for _, name := range []string{"acute", "right", "obtuse"} {
			lines = append(lines, fmt.Sprintf("%s %d", name, d.Angles[name]))
		}
		lines = append(lines, fmt.Sprintf("edge_len2 %d %d", d.EdgeMin, d.EdgeMax), fmt.Sprintf("valence %d %d", d.ValenceMin, d.ValenceMax))
	}
	return lines
}
func sectionGroups(a *Analysis) []string {
	lines := []string{}
	for _, group := range a.GroupOrder {
		polygons, triangles, nonplanar := 0, 0, 0
		for _, p := range a.Source.Polygons {
			if p.Group == group {
				polygons++
				if a.Nonplanar[p.Number] {
					nonplanar++
				}
			}
		}
		for _, t := range a.Triangles {
			if t.Group == group {
				triangles++
			}
		}
		chosen := []*Face{}
		components := map[int]bool{}
		for _, id := range a.GroupFaces[group] {
			chosen = append(chosen, a.Faces[id-1])
			components[a.Mesh.FaceComponents[id]] = true
		}
		lines = append(lines, "[group "+group+"]", fmt.Sprintf("polygons %d", polygons), fmt.Sprintf("triangles %d",
			triangles), fmt.Sprintf("nonplanar %d", nonplanar), fmt.Sprintf("faces %d", len(chosen)),
			"area "+real(area(chosen, a.Points)), "components "+listing(sortedInts(components)))
	}
	return lines
}
func intersectingBoxes(a, b [6]int64) bool {
	for axis := range 3 {
		if a[axis] > b[axis+3] || b[axis] > a[axis+3] {
			return false
		}
	}
	return true
}
func sectionContacts(a *Analysis) []string {
	lines := []string{"[contacts]"}
	for i, first := range a.Components {
		for _, second := range a.Components[i+1:] {
			if !intersectingBoxes(first.Box, second.Box) {
				continue
			}
			set := map[int]bool{}
			for _, v := range first.Topology.Vertices {
				set[v] = true
			}
			shared := 0
			for _, v := range second.Topology.Vertices {
				if set[v] {
					shared++
				}
			}
			gap := int64(-1)
			for _, u := range first.Topology.Vertices {
				for _, v := range second.Topology.Vertices {
					if u == v {
						continue
					}
					d := subtract(a.Points[u], a.Points[v])
					square := dot(d, d)
					if gap < 0 || square < gap {
						gap = square
					}
				}
			}
			lines = append(lines, fmt.Sprintf("contact %d %d shared %d gap2 %d", first.Topology.Number, second.Topology.Number, shared, gap))
		}
	}
	return lines
}
func sectionEdges(a *Analysis) []string {
	counts, shapes := map[string]int{}, map[string]int{}
	maxFaces := 0
	shortest, longest := a.Mesh.EdgeOrder[0], a.Mesh.EdgeOrder[0]
	shortDistance, longDistance := edgeLengthSquared(shortest, a.Points), edgeLengthSquared(longest, a.Points)
	for _, e := range a.Mesh.EdgeOrder {
		adjacent := a.Mesh.Edges[e]
		kind := "nonmanifold"
		if len(adjacent) == 1 {
			kind = "boundary"
		} else if len(adjacent) == 2 {
			kind = "manifold"
		}
		counts[kind]++
		shapes[edgeShape(e, a.Faces, a.Points, adjacent)]++
		maxFaces = max(maxFaces, len(adjacent))
		distance := edgeLengthSquared(e, a.Points)
		if distance < shortDistance {
			shortest, shortDistance = e, distance
		}
		if distance > longDistance {
			longest, longDistance = e, distance
		}
	}
	lines := []string{"[edges]", fmt.Sprintf("edges %d", len(a.Mesh.EdgeOrder)), fmt.Sprintf("boundary %d",
		counts["boundary"]), fmt.Sprintf("manifold %d", counts["manifold"]), fmt.Sprintf("nonmanifold %d",
		counts["nonmanifold"]), fmt.Sprintf("max_faces %d", maxFaces)}
	for _, name := range []string{"convex", "concave", "flat", "inconsistent"} {
		lines = append(lines, fmt.Sprintf("%s %d", name, shapes[name]))
	}
	return append(lines, fmt.Sprintf("shortest %s len2 %d", edgeText(shortest), shortDistance), fmt.Sprintf("longest %s len2 %d", edgeText(longest), longDistance))
}
func sectionValence(a *Analysis) []string {
	degree := map[int]int{}
	for _, e := range a.Mesh.EdgeOrder {
		degree[e[0]]++
		degree[e[1]]++
	}
	histogram := map[int]int{}
	lo, hi, total := 0, 0, 0
	for _, d := range degree {
		if lo == 0 || d < lo {
			lo = d
		}
		hi = max(hi, d)
		total += d
		histogram[d]++
	}
	lines := []string{"[valence]", fmt.Sprintf("used %d", len(degree)), fmt.Sprintf("isolated %d", len(a.Points)-1-len(degree)),
		fmt.Sprintf("min %d", lo), fmt.Sprintf("max %d", hi), "mean " + fraction(int64(total), int64(len(degree)))}
	values := []int{}
	for d := range histogram {
		values = append(values, d)
	}
	sort.Ints(values)
	for _, d := range values {
		lines = append(lines, fmt.Sprintf("degree %d %d", d, histogram[d]))
	}
	return lines
}
func findVertexPath(start, end int, m *Mesh) []int {
	graph := map[int]map[int]bool{}
	for _, e := range m.EdgeOrder {
		if graph[e[0]] == nil {
			graph[e[0]] = map[int]bool{}
		}
		if graph[e[1]] == nil {
			graph[e[1]] = map[int]bool{}
		}
		graph[e[0]][e[1]] = true
		graph[e[1]][e[0]] = true
	}
	parent := map[int]int{start: 0}
	queue := []int{start}
	for head := 0; head < len(queue); head++ {
		current := queue[head]
		for _, neighbor := range sortedInts(graph[current]) {
			if _, seen := parent[neighbor]; !seen {
				parent[neighbor] = current
				queue = append(queue, neighbor)
			}
		}
	}
	if _, found := parent[end]; !found {
		return nil
	}
	path := []int{}
	for cursor := end; cursor != 0; cursor = parent[cursor] {
		path = append(path, cursor)
	}
	for i, j := 0, len(path)-1; i < j; i, j = i+1, j-1 {
		path[i], path[j] = path[j], path[i]
	}
	return path
}
func queryVertex(v int, a *Analysis) string {
	if v < 1 || v >= len(a.Points) {
		return fmt.Sprintf("vertex %d invalid", v)
	}
	faces, degree := 0, 0
	components := map[int]bool{}
	for i, f := range a.Faces {
		for _, corner := range f.Vertices {
			if corner == v {
				faces++
				components[a.Mesh.FaceComponents[i+1]] = true
				break
			}
		}
	}
	boundary := false
	for _, e := range a.Mesh.EdgeOrder {
		if e[0] == v || e[1] == v {
			degree++
			if len(a.Mesh.Edges[e]) == 1 {
				boundary = true
			}
		}
	}
	return fmt.Sprintf("vertex %d at %s faces %d valence %d fans %d boundary %s components %s", v, vecText(a.Points[v]),
		faces, degree, len(a.Mesh.Fans[v]), yes(boundary), listing(sortedInts(components)))
}
func queryFace(number int, a *Analysis) string {
	if number < 1 || number > len(a.Faces) {
		return fmt.Sprintf("face %d invalid", number)
	}
	f := a.Faces[number-1]
	neighbors := []string{}
	for _, e := range triangleEdges(f.Vertices) {
		participants := a.Mesh.Edges[keyEdge(e[0], e[1])]
		neighbor := "-"
		if len(participants) >= 3 {
			neighbor = "*"
		} else if len(participants) == 2 {
			other := participants[0]
			if other == number {
				other = participants[1]
			}
			neighbor = fmt.Sprint(other)
		}
		neighbors = append(neighbors, neighbor)
	}
	return fmt.Sprintf("face %d vertices %s group %s polygon %s line %s component %d normal %s area %s neighbors %s",
		number, triangleText(f.Vertices), f.Group, optional(f.Polygon), optional(f.Line), a.Mesh.FaceComponents[number],
		vecText(normal(f, a.Points)), real(area([]*Face{f}, a.Points)), stringList(neighbors))
}
func queryEdge(start, end int, a *Analysis) string {
	e := keyEdge(start, end)
	adjacent, ok := a.Mesh.Edges[e]
	if !ok {
		return "edge " + edgeText(e) + " none"
	}
	kind := "nonmanifold"
	if len(adjacent) == 1 {
		kind = "boundary"
	} else if len(adjacent) == 2 {
		kind = "manifold"
	}
	return fmt.Sprintf("edge %s faces %s kind %s shape %s len2 %d", edgeText(e), listing(adjacent), kind,
		edgeShape(e, a.Faces, a.Points, adjacent), edgeLengthSquared(e, a.Points))
}
func queryPoint(p Vec, a *Analysis) string {
	inside := []int{}
	total := 0
	for _, c := range a.Components {
		if c.Solid {
			w := windingNumber(c.Topology.Faces, a.Faces, a.Points, p)
			if w != 0 {
				inside = append(inside, c.Topology.Number)
				total += w
			}
		}
	}
	return fmt.Sprintf("point %s inside %s winding %d", vecText(p), listing(inside), total)
}
func queryPath(start, end int, a *Analysis) string {
	if start < 1 || start >= len(a.Points) || end < 1 || end >= len(a.Points) {
		return fmt.Sprintf("path %d %d invalid", start, end)
	}
	path := findVertexPath(start, end, a.Mesh)
	if path == nil {
		return fmt.Sprintf("path %d %d none", start, end)
	}
	return fmt.Sprintf("path %d %d hops %d vertices %s", start, end, len(path)-1, listing(path))
}
func queryView(direction Vec, a *Analysis) string {
	scores := make([]int64, len(a.Faces))
	front, back, side, silhouette := 0, 0, 0, 0
	for i, f := range a.Faces {
		scores[i] = dot(normal(f, a.Points), direction)
		if scores[i] > 0 {
			front++
		} else if scores[i] < 0 {
			back++
		} else {
			side++
		}
	}
	for _, adjacent := range a.Mesh.Edges {
		if len(adjacent) == 2 {
			x, y := scores[adjacent[0]-1], scores[adjacent[1]-1]
			if x > 0 && y < 0 || x < 0 && y > 0 {
				silhouette++
			}
		}
	}
	return fmt.Sprintf("view %s front %d back %d side %d silhouette %d", vecText(direction), front, back, side, silhouette)
}
func sectionQueries(a *Analysis) []string {
	lines := []string{"[queries]"}
	for _, q := range a.Settings.Queries {
		v := q.Args
		switch q.Kind {
		case "vertex":
			lines = append(lines, queryVertex(int(v[0]), a))
		case "face":
			lines = append(lines, queryFace(int(v[0]), a))
		case "edge":
			lines = append(lines, queryEdge(int(v[0]), int(v[1]), a))
		case "point":
			lines = append(lines, queryPoint(Vec{v[0], v[1], v[2]}, a))
		case "path":
			lines = append(lines, queryPath(int(v[0]), int(v[1]), a))
		case "view":
			lines = append(lines, queryView(Vec{v[0], v[1], v[2]}, a))
		}
	}
	return lines
}
func reportSections(a *Analysis) []string {
	actions := map[string]func(*Analysis) []string{"summary": sectionSummary, "warnings": sectionWarnings,
		"cleanup": sectionCleanup, "components": sectionComponents, "groups": sectionGroups, "contacts": sectionContacts,
		"edges": sectionEdges, "valence": sectionValence, "queries": sectionQueries}
	lines := []string{}
	for _, section := range a.Settings.Sections {
		lines = append(lines, actions[section](a)...)
	}
	return lines
}
func csvComponents(a *Analysis) []string {
	lines := []string{"component,faces,vertices,closed,euler,genus,volume6,area"}
	for _, c := range a.Components {
		genus, volume := "-", "-"
		if c.HasGenus {
			genus = fmt.Sprint(c.Genus)
		}
		if c.Solid {
			volume = fmt.Sprint(c.Volume6)
		}
		lines = append(lines, fmt.Sprintf("%d,%d,%d,%s,%d,%s,%s,%s", c.Topology.Number, len(c.Topology.Faces),
			len(c.Topology.Vertices), yes(c.Closed), c.Euler, genus, volume, real(c.Area)))
	}
	return lines
}
func boundariesReport(a *Analysis) []string {
	m := a.MeshBefore
	lines := []string{fmt.Sprintf("loops %d", len(a.LoopsBefore))}
	for _, loop := range a.LoopsBefore {
		state := "kept"
		if loop.Filled {
			state = "filled"
		}
		lines = append(lines, fmt.Sprintf("loop %d component %d length %d %s %s vertices %s", loop.Number,
			loop.Component, loop.Length, loop.Kind, state, listing(loop.Vertices)))
	}
	nonmanifold := []Edge{}
	for _, e := range m.EdgeOrder {
		if len(m.Edges[e]) >= 3 {
			nonmanifold = append(nonmanifold, e)
		}
	}
	lines = append(lines, fmt.Sprintf("nonmanifold_edges %d", len(nonmanifold)))
	for _, e := range nonmanifold {
		lines = append(lines, "edge "+edgeText(e)+" faces "+listing(m.Edges[e]))
	}
	lines = append(lines, fmt.Sprintf("nonmanifold_vertices %d", len(m.NonmanifoldVertices)))
	for _, v := range m.NonmanifoldVertices {
		components := map[int]bool{}
		for _, fan := range m.Fans[v] {
			for _, f := range fan {
				components[m.FaceComponents[f]] = true
			}
		}
		lines = append(lines, fmt.Sprintf("vertex %d fans %d components %s", v, len(m.Fans[v]), listing(sortedInts(components))))
	}
	lines = append(lines, fmt.Sprintf("inconsistent_edges %d", len(a.InconsistentAfter)))
	for _, e := range a.InconsistentAfter {
		lines = append(lines, "edge "+edgeText(e)+" faces "+listing(m.Edges[e]))
	}
	return lines
}
func writeLines(name string, lines []string) {
	if err := os.WriteFile("output/"+name, []byte(strings.Join(lines, "\n")+"\n"), 0644); err != nil {
		panic(err)
	}
}
func main() {
	a := analyzeSource(readOBJ(), readParameters())
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	writeLines("report.txt", reportSections(a))
	writeLines("components.csv", csvComponents(a))
	writeLines("boundaries.txt", boundariesReport(a))
	writeLines("repaired.obj", repairedOBJ(a.Points, a.Faces))
}
