package main

import (
	"fmt"
	"math"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

type Params struct {
	Width, Height             int
	Layers, Sections, Queries []string
	Alpha                     []int64
}

func readLines(path string) []string {
	data, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
}
func integer(s string) int64 {
	n, e := strconv.ParseInt(s, 10, 64)
	if e != nil {
		panic(e)
	}
	return n
}
func readPoints() ([]Point, int, []string) {
	lines := readLines("input/points.txt")
	points := []Point{{}}
	accepted := map[Point]int{}
	rejected := []string{}
	word := regexp.MustCompile(`^-?[0-9]+$`)
	for i, line := range lines {
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		f := strings.Split(line, " ")
		if len(f) != 2 || !word.MatchString(f[0]) || !word.MatchString(f[1]) {
			rejected = append(rejected, fmt.Sprintf("reject %d format", i+1))
			continue
		}
		p := Point{integer(f[0]), integer(f[1])}
		if p.X < 0 || p.X > 1000 || p.Y < 0 || p.Y > 1000 {
			rejected = append(rejected, fmt.Sprintf("reject %d range", i+1))
			continue
		}
		if site, ok := accepted[p]; ok {
			rejected = append(rejected, fmt.Sprintf("reject %d duplicate %d", i+1, site))
			continue
		}
		accepted[p] = len(points)
		points = append(points, p)
	}
	return points, len(lines), rejected
}
func readParams() Params {
	p := Params{Width: 61, Height: 31, Layers: []string{"edges", "hull", "sites"}, Sections: []string{"summary"}}
	for _, line := range readLines("input/params.txt") {
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		f := strings.Split(line, " ")
		switch f[0] {
		case "plot":
			p.Width, p.Height = int(integer(f[1])), int(integer(f[2]))
		case "plot_layers":
			p.Layers = f[1:]
		case "sections":
			p.Sections = f[1:]
		case "alpha":
			for _, v := range f[1:] {
				p.Alpha = append(p.Alpha, integer(v))
			}
		case "query":
			p.Queries = append(p.Queries, strings.TrimPrefix(line, "query "))
		}
	}
	return p
}
func number(v float64) string {
	text := fmt.Sprintf("%.3f", v)
	if text == "-0.000" {
		return "0.000"
	}
	return text
}
func words(values []int) string {
	text := make([]string, len(values))
	for i, v := range values {
		text[i] = strconv.Itoa(v)
	}
	return strings.Join(text, " ")
}
func edgeWords(e Edge) string         { return fmt.Sprintf("%d %d", e[0], e[1]) }
func triangleWords(t Triangle) string { return fmt.Sprintf("%d %d %d", t[0], t[1], t[2]) }
func triangleNumber(n int) string {
	if n == 0 {
		return "-"
	}
	return strconv.Itoa(n)
}
func yes(v bool) string {
	if v {
		return "yes"
	}
	return "no"
}

type Cell struct {
	Vertices           []int
	Area, Clip         float64
	Incoming, Outgoing Point
}
type Report struct {
	Points                          []Point
	N, LineCount                    int
	Rejected                        []string
	Params                          Params
	Mesh                            *Triangulation
	Insertions                      []Insertion
	Triangles                       []Triangle
	Edges, HullEdges, MST           []Edge
	EdgeTriangles                   map[Edge]int
	Length2                         map[Edge]int64
	Hull                            []int
	HullNext, HullPrev              map[int]int
	Neighbors                       [][]int
	Centers                         []Center
	Radius2                         []float64
	Positions, Kinds                []string
	Areas                           []int64
	MinimumAngles, MaximumAngles    []float64
	Cells                           []Cell
	Gabriel, RNG, MSTSet            map[Edge]bool
	Nearest, ComponentNumber, Depth []int
	Components, Layers              [][]int
	GraphDegrees                    map[string][]int
	EmptyCandidates                 []int
	EmptyVertex                     int
	Paths                           map[int]ShortestPaths
	Sections                        map[string][]string
}

func newReport(points []Point, lineCount int, rejected []string, p Params) *Report {
	return &Report{Points: points, N: len(points) - 1, LineCount: lineCount, Rejected: rejected, Params: p,
		Paths: map[int]ShortestPaths{}, Sections: map[string][]string{}}
}
func (r *Report) buildTriangulation() {
	r.Mesh = newTriangulation(r.Points)
	for s := 4; s <= r.N; s++ {
		r.Insertions = append(r.Insertions, r.Mesh.insert(s))
	}
	r.Triangles = append([]Triangle{{}}, r.Mesh.triangles()...)
	r.EdgeTriangles = map[Edge]int{}
	r.Length2 = map[Edge]int64{}
	for k, t := range r.Triangles[1:] {
		for _, e := range triangleEdges(t) {
			r.EdgeTriangles[e] = k + 1
			pair := orderedEdge(e[0], e[1])
			r.Length2[pair] = d2(r.Points[pair[0]], r.Points[pair[1]])
		}
	}
	for e := range r.Length2 {
		r.Edges = append(r.Edges, e)
	}
	sort.Slice(r.Edges, func(i, j int) bool { return edgeLess(r.Edges[i], r.Edges[j]) })
	r.HullNext, r.HullPrev = map[int]int{}, map[int]int{}
	start := r.N + 1
	for _, e := range r.Mesh.hullEdges() {
		r.HullNext[e[0]] = e[1]
		r.HullPrev[e[1]] = e[0]
		start = min(start, e[0])
	}
	r.Hull = []int{start}
	for r.HullNext[r.Hull[len(r.Hull)-1]] != start {
		r.Hull = append(r.Hull, r.HullNext[r.Hull[len(r.Hull)-1]])
	}
	perimeter := 0.0
	area := int64(0)
	for i, u := range r.Hull {
		v := r.Hull[(i+1)%len(r.Hull)]
		r.HullEdges = append(r.HullEdges, Edge{u, v})
		a, b := r.Points[u], r.Points[v]
		perimeter += math.Sqrt(float64(d2(a, b)))
		area += a.X*b.Y - b.X*a.Y
	}
	r.Sections["hull"] = []string{fmt.Sprintf("hull_vertices %d", len(r.Hull)), "order " + words(r.Hull),
		"perimeter " + number(perimeter), fmt.Sprintf("area2 %d", area)}
	adjacent := make([][]int, r.N+1)
	for _, e := range r.Edges {
		adjacent[e[0]] = append(adjacent[e[0]], e[1])
		adjacent[e[1]] = append(adjacent[e[1]], e[0])
	}
	r.Neighbors = make([][]int, r.N+1)
	for s := 1; s <= r.N; s++ {
		r.Neighbors[s] = neighborOrder(s, adjacent[s], r.Mesh.Directed, r.HullNext)
	}
	lines := []string{"init " + triangleWords(r.Mesh.Initial)}
	for _, v := range r.Insertions {
		description := fmt.Sprintf("outside %d", v.Visible)
		if v.Kind == "inside" {
			description = "inside " + triangleWords(v.Containing)
		}
		lines = append(lines, fmt.Sprintf("insert %d %s flips %d triangles %d hull %d", v.Site, description, v.Flips, v.Triangles, v.Hull))
	}
	r.Sections["insertions"] = lines
}
func (r *Report) analyzeTriangles() {
	count := len(r.Triangles)
	r.Areas = make([]int64, count)
	r.Kinds = make([]string, count)
	r.MinimumAngles, r.MaximumAngles = make([]float64, count), make([]float64, count)
	bins := [6]int{}
	total := 0.0
	minimum, maximum := 1, 1
	for k, t := range r.Triangles[1:] {
		k++
		a, b, c := r.Points[t[0]], r.Points[t[1]], r.Points[t[2]]
		area := orient(a, b, c)
		products := [3]int64{dot(a, b, c), dot(b, c, a), dot(c, a, b)}
		lengths := [3]int64{d2(b, c), d2(c, a), d2(a, b)}
		kind := "acute"
		for _, v := range products {
			if v < 0 {
				kind = "obtuse"
			}
		}
		for _, v := range products {
			if v == 0 {
				kind = "right"
			}
		}
		shortest, longest := 0, 0
		for j := 1; j < 3; j++ {
			if lengths[j] < lengths[shortest] {
				shortest = j
			}
			if lengths[j] > lengths[longest] {
				longest = j
			}
		}
		r.Areas[k], r.Kinds[k] = area, kind
		r.MinimumAngles[k] = math.Atan2(float64(area), float64(products[shortest])) * 180 / math.Pi
		r.MaximumAngles[k] = math.Atan2(float64(area), float64(products[longest])) * 180 / math.Pi
		total += r.MinimumAngles[k]
		bins[int(r.MinimumAngles[k]/10)]++
		if r.MinimumAngles[k] < r.MinimumAngles[minimum] {
			minimum = k
		}
		if r.MaximumAngles[k] > r.MaximumAngles[maximum] {
			maximum = k
		}
		r.Sections["triangles"] = append(r.Sections["triangles"], fmt.Sprintf("tri %d %s area2 %d %s adj %s %s %s",
			k, triangleWords(t), area, kind, triangleNumber(r.EdgeTriangles[Edge{t[2], t[1]}]), triangleNumber(r.EdgeTriangles[Edge{t[0],
				t[2]}]), triangleNumber(r.EdgeTriangles[Edge{t[1], t[0]}])))
	}
	r.Sections["quality"] = []string{fmt.Sprintf("min_angle %s tri %d", number(r.MinimumAngles[minimum]),
		minimum), fmt.Sprintf("max_angle %s tri %d", number(r.MaximumAngles[maximum]), maximum),
		"mean_min_angle " + number(total/float64(count-1))}
	for j, n := range bins {
		r.Sections["quality"] = append(r.Sections["quality"], fmt.Sprintf("bin %d %d %d", 10*j, 10*(j+1), n))
	}
	for _, e := range r.Edges {
		left, right := r.EdgeTriangles[e], r.EdgeTriangles[Edge{e[1], e[0]}]
		kind := "hull"
		if left > 0 && right > 0 {
			kind = "inner"
		}
		r.Sections["edges"] = append(r.Sections["edges"], fmt.Sprintf("edge %s %s len2 %d left %s right %s",
			edgeWords(e), kind, r.Length2[e], triangleNumber(left), triangleNumber(right)))
	}
	flips, outside, best := 0, 0, -1
	for i, v := range r.Insertions {
		flips += v.Flips
		if v.Kind == "outside" {
			outside++
		}
		if best < 0 || v.Flips > r.Insertions[best].Flips {
			best = i
		}
	}
	maxFlips := "max_flips none"
	if best >= 0 {
		v := r.Insertions[best]
		maxFlips = fmt.Sprintf("max_flips %d %d", v.Site, v.Flips)
	}
	kinds := map[string]int{}
	for _, kind := range r.Kinds[1:] {
		kinds[kind]++
	}
	r.Sections["summary"] = []string{fmt.Sprintf("sites %d", r.N), fmt.Sprintf("triangles %d", count-1),
		fmt.Sprintf("edges %d", len(r.Edges)), fmt.Sprintf("hull_vertices %d", len(r.Hull)), fmt.Sprintf("interior_sites %d",
			r.N-len(r.Hull)), fmt.Sprintf("euler %d", r.N-len(r.Edges)+count-1), fmt.Sprintf("flips %d",
			flips), fmt.Sprintf("outside_insertions %d", outside), maxFlips, fmt.Sprintf("acute %d",
			kinds["acute"]), fmt.Sprintf("right %d", kinds["right"]), fmt.Sprintf("obtuse %d", kinds["obtuse"])}
}
func (r *Report) dual(e Edge) string {
	left, right := r.EdgeTriangles[e], r.EdgeTriangles[Edge{e[1], e[0]}]
	if left > 0 && right > 0 {
		return fmt.Sprintf("segment %d %d", left, right)
	}
	u, v, k := e[0], e[1], left
	if left == 0 {
		u, v, k = v, u, right
	}
	d := outward(r.Points, u, v)
	return fmt.Sprintf("ray %d %d %d", k, d.X, d.Y)
}
func (r *Report) analyzeVoronoi() {
	count := len(r.Triangles)
	r.Centers = make([]Center, count)
	r.Radius2 = make([]float64, count)
	r.Positions = make([]string, count)
	positions := map[string]int{}
	for k, t := range r.Triangles[1:] {
		k++
		a, b, c := r.Points[t[0]], r.Points[t[1]], r.Points[t[2]]
		r.Centers[k] = circumcenter(a, b, c)
		r.Radius2[k] = squaredRadius(a, b, c)
		r.Positions[k] = position(r.Centers[k], r.Points, r.Hull)
		positions[r.Positions[k]]++
	}
	for _, name := range []string{"inside", "on", "outside"} {
		r.Sections["vertices"] = append(r.Sections["vertices"], fmt.Sprintf("%s %d", name, positions[name]))
	}
	for k := 1; k < count; k++ {
		c := r.Centers[k]
		r.Sections["vertices"] = append(r.Sections["vertices"], fmt.Sprintf("v %d %s %s r %s %s", k, fraction(c.X,
			c.D), fraction(c.Y, c.D), number(math.Sqrt(r.Radius2[k])), r.Positions[k]))
	}
	r.Sections["voronoi_edges"] = []string{fmt.Sprintf("segments %d", len(r.Edges)-len(r.Hull)), fmt.Sprintf("rays %d", len(r.Hull))}
	for _, e := range r.Edges {
		r.Sections["voronoi_edges"] = append(r.Sections["voronoi_edges"], "ve "+edgeWords(e)+" "+r.dual(e))
	}
	r.Cells = make([]Cell, r.N+1)
	areaTotal, clipTotal := 0.0, 0.0
	largest := 0
	cellLines := []string{}
	for s := 1; s <= r.N; s++ {
		cell := Cell{Clip: clippedArea(r.Points, s, r.Neighbors[s])}
		centers := []Center{}
		for _, other := range r.Neighbors[s] {
			if k := r.EdgeTriangles[Edge{s, other}]; k > 0 {
				cell.Vertices = append(cell.Vertices, k)
				centers = append(centers, r.Centers[k])
			}
		}
		if next := r.HullNext[s]; next > 0 {
			cell.Incoming = outward(r.Points, s, next)
			cell.Outgoing = outward(r.Points, r.HullPrev[s], s)
			cellLines = append(cellLines, fmt.Sprintf("cell %d unbounded %d clip %s from %d %d vertices %s to %d %d",
				s, len(cell.Vertices), number(cell.Clip), cell.Incoming.X, cell.Incoming.Y, words(cell.Vertices),
				cell.Outgoing.X, cell.Outgoing.Y))
		} else {
			cell.Area = boundedArea(r.Points[s], centers)
			areaTotal += cell.Area
			if largest == 0 || cell.Area > r.Cells[largest].Area {
				largest = s
			}
			cellLines = append(cellLines, fmt.Sprintf("cell %d bounded %d area %s clip %s vertices %s", s,
				len(cell.Vertices), number(cell.Area), number(cell.Clip), words(cell.Vertices)))
		}
		r.Cells[s] = cell
		clipTotal += cell.Clip
	}
	r.Sections["cells"] = []string{fmt.Sprintf("bounded %d", r.N-len(r.Hull)), fmt.Sprintf("unbounded %d",
		len(r.Hull)), "total_area " + number(areaTotal), "clip_total " + number(clipTotal)}
	if largest == 0 {
		r.Sections["cells"] = append(r.Sections["cells"], "largest none")
	} else {
		r.Sections["cells"] = append(r.Sections["cells"], fmt.Sprintf("largest %d area %s", largest, number(r.Cells[largest].Area)))
	}
	r.Sections["cells"] = append(r.Sections["cells"], cellLines...)
}
func (r *Report) analyzeProximity() {
	r.Nearest = nearestNeighbors(r.Points, r.Neighbors)
	r.Components = nearestComponents(r.Nearest)
	r.ComponentNumber = make([]int, r.N+1)
	mutual := 0
	for s := 1; s <= r.N; s++ {
		if s < r.Nearest[s] && r.Nearest[r.Nearest[s]] == s {
			mutual++
		}
	}
	closest := r.Edges[0]
	for _, e := range r.Edges[1:] {
		if r.Length2[e] < r.Length2[closest] {
			closest = e
		}
	}
	r.Sections["nearest"] = []string{fmt.Sprintf("mutual_pairs %d", mutual), fmt.Sprintf("closest_pair %s d2 %d", edgeWords(closest), r.Length2[closest])}
	for s := 1; s <= r.N; s++ {
		other := r.Nearest[s]
		kind := "-"
		if r.Nearest[other] == s {
			kind = "mutual"
		}
		r.Sections["nearest"] = append(r.Sections["nearest"], fmt.Sprintf("nn %d %d d2 %d %s", s, other, d2(r.Points[s], r.Points[other]), kind))
	}
	r.Sections["components"] = []string{fmt.Sprintf("components %d", len(r.Components))}
	for k, sites := range r.Components {
		pair := Edge{}
		for _, s := range sites {
			r.ComponentNumber[s] = k + 1
			if s < r.Nearest[s] && r.Nearest[r.Nearest[s]] == s {
				pair = Edge{s, r.Nearest[s]}
			}
		}
		r.Sections["components"] = append(r.Sections["components"], fmt.Sprintf("component %d size %d pair %s sites %s",
			k+1, len(sites), edgeWords(pair), words(sites)))
	}
	r.MST = kruskal(r.Points, r.Edges)
	r.MSTSet, r.Gabriel, r.RNG = map[Edge]bool{}, map[Edge]bool{}, map[Edge]bool{}
	length := 0.0
	for _, e := range r.MST {
		r.MSTSet[e] = true
		length += math.Sqrt(float64(r.Length2[e]))
	}
	last := r.MST[len(r.MST)-1]
	r.Sections["mst"] = []string{fmt.Sprintf("edges %d", r.N-1), "total_length " + number(length), fmt.Sprintf("longest %s len2 %d",
		edgeWords(last), r.Length2[last])}
	for _, e := range r.MST {
		r.Sections["mst"] = append(r.Sections["mst"], fmt.Sprintf("mst %s len2 %d", edgeWords(e), r.Length2[e]))
	}
	for _, e := range r.Edges {
		if isGabriel(r.Points, e, r.Mesh.Directed) {
			r.Gabriel[e] = true
		}
		if isRelativeNeighbor(r.Points, e) {
			r.RNG[e] = true
		}
	}
	r.Sections["proximity"] = []string{fmt.Sprintf("delaunay %d", len(r.Edges)), fmt.Sprintf("gabriel %d",
		len(r.Gabriel)), fmt.Sprintf("rng %d", len(r.RNG)), fmt.Sprintf("mst %d", r.N-1), fmt.Sprintf("nn %d",
		r.N-mutual)}
	for _, e := range r.Edges {
		if r.RNG[e] && !r.MSTSet[e] {
			r.Sections["proximity"] = append(r.Sections["proximity"], fmt.Sprintf("rng_extra %s len2 %d", edgeWords(e), r.Length2[e]))
		}
	}
	r.GraphDegrees = map[string][]int{}
	for name, edges := range map[string]map[Edge]bool{"gg": r.Gabriel, "rng": r.RNG, "mst": r.MSTSet} {
		degrees := make([]int, r.N+1)
		for e := range edges {
			degrees[e[0]]++
			degrees[e[1]]++
		}
		r.GraphDegrees[name] = degrees
	}
	counts := map[int]int{}
	smallest, largest := r.N, 0
	for _, neighbors := range r.Neighbors[1:] {
		d := len(neighbors)
		counts[d]++
		smallest = min(smallest, d)
		largest = max(largest, d)
	}
	r.Sections["degrees"] = []string{fmt.Sprintf("min %d", smallest), fmt.Sprintf("max %d", largest)}
	for d := smallest; d <= largest; d++ {
		if counts[d] > 0 {
			r.Sections["degrees"] = append(r.Sections["degrees"], fmt.Sprintf("degree %d count %d", d, counts[d]))
		}
	}
}
func (r *Report) circleRelation(support []int, site int) int64 {
	if len(support) == 1 {
		if support[0] == site {
			return 0
		}
		return -1
	}
	if len(support) == 2 {
		return -dot(r.Points[site], r.Points[support[0]], r.Points[support[1]])
	}
	return incircle(r.Points[support[0]], r.Points[support[1]], r.Points[support[2]], r.Points[site])
}
func (r *Report) circleOrder(a, b, c int) []int {
	if orient(r.Points[a], r.Points[b], r.Points[c]) < 0 {
		b, c = c, b
	}
	return []int{a, b, c}
}
func (r *Report) enclosingCircle() (Center, float64, []int) {
	support := []int{}
	for i, first := range r.Hull {
		if len(support) > 0 && r.circleRelation(support, first) >= 0 {
			continue
		}
		support = []int{first}
		for j := 0; j < i; j++ {
			second := r.Hull[j]
			if r.circleRelation(support, second) >= 0 {
				continue
			}
			support = []int{first, second}
			for k := 0; k < j; k++ {
				third := r.Hull[k]
				if r.circleRelation(support, third) < 0 {
					support = r.circleOrder(first, second, third)
				}
			}
		}
	}
	boundary := []int{}
	for s := 1; s <= r.N; s++ {
		if r.circleRelation(support, s) == 0 {
			boundary = append(boundary, s)
		}
	}
	for i, a := range boundary {
		for _, b := range boundary[i+1:] {
			diameter := true
			for _, s := range boundary {
				if dot(r.Points[s], r.Points[a], r.Points[b]) != 0 {
					diameter = false
					break
				}
			}
			if diameter {
				p, q := r.Points[a], r.Points[b]
				return Center{p.X + q.X, p.Y + q.Y, 2}, float64(d2(p, q)) / 4, boundary
			}
		}
	}
	ordered := r.circleOrder(boundary[0], boundary[1], boundary[2])
	a, b, c := r.Points[ordered[0]], r.Points[ordered[1]], r.Points[ordered[2]]
	return circumcenter(a, b, c), squaredRadius(a, b, c), boundary
}
func (r *Report) analyzeExtent() {
	for k := 1; k < len(r.Triangles); k++ {
		if r.Positions[k] == "inside" {
			r.EmptyCandidates = append(r.EmptyCandidates, k)
			if r.EmptyVertex == 0 || r.Radius2[k] > r.Radius2[r.EmptyVertex] {
				r.EmptyVertex = k
			}
		}
	}
	r.Sections["empty_circle"] = []string{fmt.Sprintf("candidates %d", len(r.EmptyCandidates))}
	if r.EmptyVertex == 0 {
		r.Sections["empty_circle"] = append(r.Sections["empty_circle"], "none")
	} else {
		k := r.EmptyVertex
		c := r.Centers[k]
		r.Sections["empty_circle"] = append(r.Sections["empty_circle"], fmt.Sprintf("vertex %d", k), "center "+fraction(c.X,
			c.D)+" "+fraction(c.Y, c.D), "radius "+number(math.Sqrt(r.Radius2[k])), "sites "+triangleWords(r.Triangles[k]))
	}
	diameter := Edge{}
	diameter2 := int64(-1)
	for a := 1; a < r.N; a++ {
		for b := a + 1; b <= r.N; b++ {
			length := d2(r.Points[a], r.Points[b])
			if length > diameter2 {
				diameter, diameter2 = Edge{a, b}, length
			}
		}
	}
	width := math.Inf(1)
	widthEdge := Edge{}
	for _, e := range r.HullEdges {
		maximum := int64(0)
		for _, s := range r.Hull {
			maximum = max(maximum, orient(r.Points[e[0]], r.Points[e[1]], r.Points[s]))
		}
		value := float64(maximum) / math.Sqrt(float64(d2(r.Points[e[0]], r.Points[e[1]])))
		if value < width {
			width, widthEdge = value, e
		}
	}
	center, radius, sites := r.enclosingCircle()
	r.Sections["extent"] = []string{fmt.Sprintf("diameter %s d2 %d", edgeWords(diameter), diameter2),
		"width " + number(width) + " edge " + edgeWords(widthEdge), "enclosing_center " + fraction(center.X,
			center.D) + " " + fraction(center.Y, center.D), "enclosing_radius " + number(math.Sqrt(radius)),
		"enclosing_sites " + words(sites)}
}
func (r *Report) analyzeLayers() {
	remaining := make([]int, r.N)
	for i := range remaining {
		remaining[i] = i + 1
	}
	r.Depth = make([]int, r.N+1)
	for len(remaining) > 0 {
		layer := append([]int{}, remaining...)
		if len(remaining) > 2 {
			sort.Slice(layer, func(i, j int) bool {
				a, b := r.Points[layer[i]], r.Points[layer[j]]
				return a.X < b.X || a.X == b.X && a.Y < b.Y
			})
			lower, upper := []int{}, []int{}
			for _, s := range layer {
				for len(lower) >= 2 && orient(r.Points[lower[len(lower)-2]], r.Points[lower[len(lower)-1]], r.Points[s]) <= 0 {
					lower = lower[:len(lower)-1]
				}
				lower = append(lower, s)
			}
			for i := len(layer) - 1; i >= 0; i-- {
				s := layer[i]
				for len(upper) >= 2 && orient(r.Points[upper[len(upper)-2]], r.Points[upper[len(upper)-1]], r.Points[s]) <= 0 {
					upper = upper[:len(upper)-1]
				}
				upper = append(upper, s)
			}
			layer = append(lower[:len(lower)-1], upper[:len(upper)-1]...)
			start := 0
			for i, s := range layer {
				if s < layer[start] {
					start = i
				}
			}
			layer = append(append([]int{}, layer[start:]...), layer[:start]...)
		}
		r.Layers = append(r.Layers, layer)
		for _, s := range layer {
			r.Depth[s] = len(r.Layers)
		}
		next := []int{}
		for _, s := range remaining {
			if r.Depth[s] == 0 {
				next = append(next, s)
			}
		}
		remaining = next
	}
	r.Sections["convex_layers"] = []string{fmt.Sprintf("layers %d", len(r.Layers))}
	for i, layer := range r.Layers {
		r.Sections["convex_layers"] = append(r.Sections["convex_layers"], fmt.Sprintf("layer %d size %d sites %s", i+1, len(layer), words(layer)))
	}
}
func (r *Report) shortestFrom(s int) ShortestPaths {
	if v, ok := r.Paths[s]; ok {
		return v
	}
	v := dijkstra(r.Points, r.Neighbors, s)
	r.Paths[s] = v
	return v
}
func (r *Report) analyzeSpanner() {
	pairs := r.N * (r.N - 1) / 2
	total, maximum, length, distance := 0.0, -1.0, 0.0, 0.0
	pair := Edge{}
	for a := 1; a < r.N; a++ {
		paths := r.shortestFrom(a)
		for b := a + 1; b <= r.N; b++ {
			direct := math.Sqrt(float64(d2(r.Points[a], r.Points[b])))
			stretch := paths.Distances[b] / direct
			total += stretch
			if stretch > maximum {
				maximum, pair, length, distance = stretch, Edge{a, b}, paths.Distances[b], direct
			}
		}
	}
	r.Sections["spanner"] = []string{fmt.Sprintf("pairs %d", pairs), fmt.Sprintf("max_stretch %s pair %s length %s distance %s",
		number(maximum), edgeWords(pair), number(length), number(distance)), "mean_stretch " + number(total/float64(pairs))}
}
func (r *Report) analyzeAlpha() {
	for _, alpha := range r.Params.Alpha {
		incidence := map[Edge]int{}
		faces := 0
		area := int64(0)
		for k := 1; k < len(r.Triangles); k++ {
			if r.Radius2[k] <= float64(alpha) {
				faces++
				area += r.Areas[k]
				for _, e := range triangleEdges(r.Triangles[k]) {
					incidence[orderedEdge(e[0], e[1])]++
				}
			}
		}
		selected := map[Edge]bool{}
		for e := range incidence {
			selected[e] = true
		}
		for e := range r.Gabriel {
			if r.Length2[e] <= 4*alpha {
				selected[e] = true
			}
		}
		sets := newDisjointSets(r.N)
		incident := make([]bool, r.N+1)
		boundary, dangling, isolated := 0, 0, r.N
		for _, e := range r.Edges {
			if !selected[e] {
				continue
			}
			sets.union(e[0], e[1])
			for _, s := range e {
				if !incident[s] {
					incident[s] = true
					isolated--
				}
			}
			if incidence[e] == 1 {
				boundary++
			}
			if incidence[e] == 0 {
				dangling++
			}
		}
		r.Sections["alpha"] = append(r.Sections["alpha"], fmt.Sprintf("alpha %d triangles %d edges %d boundary %d dangling %d isolated %d components %d holes %d area2 %d",
			alpha, faces, len(selected), boundary, dangling, isolated, sets.Count, sets.Count-(r.N-len(selected)+faces),
			area))
	}
}
func (r *Report) locate(q Point) string {
	nearest := 1
	location := "outside"
	for s := 1; s <= r.N; s++ {
		if d2(r.Points[s], q) < d2(r.Points[nearest], q) {
			nearest = s
		}
		if r.Points[s] == q {
			location = fmt.Sprintf("vertex %d", s)
		}
	}
	if location == "outside" {
		for _, e := range r.Edges {
			if orient(r.Points[e[0]], r.Points[e[1]], q) == 0 && dot(q, r.Points[e[0]], r.Points[e[1]]) < 0 {
				location = "edge " + edgeWords(e)
				break
			}
		}
	}
	if location == "outside" {
		for _, t := range r.Triangles[1:] {
			inside := true
			for _, e := range triangleEdges(t) {
				if orient(r.Points[e[0]], r.Points[e[1]], q) <= 0 {
					inside = false
				}
			}
			if inside {
				location = "triangle " + triangleWords(t)
				break
			}
		}
	}
	return fmt.Sprintf("%s nearest %d d2 %d", location, nearest, d2(r.Points[nearest], q))
}
func (r *Report) queryAnswer(query string) string {
	fields := strings.Split(query, " ")
	name := fields[0]
	args := []int{}
	for _, v := range fields[1:] {
		args = append(args, int(integer(v)))
	}
	a := args[0]
	b := 0
	if len(args) > 1 {
		b = args[1]
	}
	if name == "route" || name == "path" || name == "neighbors" || name == "edge" {
		for _, s := range args {
			if s < 1 || s > r.N {
				return query + " error unknown_site"
			}
		}
		if name == "edge" && a == b {
			return query + " error same_site"
		}
	}
	answer := ""
	q := Point{int64(a), int64(b)}
	switch name {
	case "locate":
		answer = r.locate(q)
	case "walk":
		path, outside := r.Mesh.visibilityWalk(q, r.Triangles, r.EdgeTriangles)
		stopping := fmt.Sprintf("triangle %d", path[len(path)-1])
		if outside[0] > 0 {
			stopping = "outside " + edgeWords(outside)
		}
		answer = fmt.Sprintf("steps %d %s path %s", len(path)-1, stopping, words(path))
	case "natural":
		count := 0
		sites := map[int]bool{}
		for _, t := range r.Triangles[1:] {
			if incircle(r.Points[t[0]], r.Points[t[1]], r.Points[t[2]], q) > 0 {
				count++
				for _, s := range t {
					sites[s] = true
				}
			}
		}
		ordered := []int{}
		for s := 1; s <= r.N; s++ {
			if sites[s] {
				ordered = append(ordered, s)
			}
		}
		text := "-"
		if len(ordered) > 0 {
			text = words(ordered)
		}
		answer = fmt.Sprintf("triangles %d sites %s", count, text)
	case "route":
		path, length := greedyRoute(r.Points, r.Neighbors, a, b)
		answer = fmt.Sprintf("hops %d length %s path %s", len(path)-1, number(length), words(path))
	case "path":
		paths := r.shortestFrom(a)
		path := []int{b}
		for path[len(path)-1] != a {
			path = append(path, paths.Previous[path[len(path)-1]])
		}
		for i, j := 0, len(path)-1; i < j; i, j = i+1, j-1 {
			path[i], path[j] = path[j], path[i]
		}
		stretch := "-"
		if a != b {
			stretch = number(paths.Distances[b] / math.Sqrt(float64(d2(r.Points[a], r.Points[b]))))
		}
		answer = fmt.Sprintf("length %s stretch %s hops %d sites %s", number(paths.Distances[b]), stretch, len(path)-1, words(path))
	case "neighbors":
		answer = fmt.Sprintf("degree %d sites %s", len(r.Neighbors[a]), words(r.Neighbors[a]))
	case "edge":
		e := orderedEdge(a, b)
		if length, ok := r.Length2[e]; ok {
			answer = fmt.Sprintf("delaunay len2 %d gabriel %s rng %s mst %s dual %s", length, yes(r.Gabriel[e]), yes(r.RNG[e]), yes(r.MSTSet[e]), r.dual(e))
		} else {
			crossings := []string{}
			p, q := r.Points[a], r.Points[b]
			for _, e := range r.Edges {
				u, v := r.Points[e[0]], r.Points[e[1]]
				if orient(p, q, u)*orient(p, q, v) < 0 && orient(u, v, p)*orient(u, v, q) < 0 {
					crossings = append(crossings, fmt.Sprintf("%d-%d", e[0], e[1]))
				}
			}
			answer = fmt.Sprintf("missing crossings %d", len(crossings))
			if len(crossings) > 0 {
				answer += " " + strings.Join(crossings, " ")
			}
		}
	}
	return query + " " + answer
}
func (r *Report) finish() {
	for s := 1; s <= r.N; s++ {
		p := r.Points[s]
		kind := "inner"
		if r.HullNext[s] > 0 {
			kind = "hull"
		}
		r.Sections["sites"] = append(r.Sections["sites"], fmt.Sprintf("site %d %d %d %s dt %d gg %d rng %d mst %d nn %d comp %d depth %d",
			s, p.X, p.Y, kind, len(r.Neighbors[s]), r.GraphDegrees["gg"][s], r.GraphDegrees["rng"][s],
			r.GraphDegrees["mst"][s], r.Nearest[s], r.ComponentNumber[s], r.Depth[s]))
	}
	for _, query := range r.Params.Queries {
		r.Sections["queries"] = append(r.Sections["queries"], r.queryAnswer(query))
	}
	canvas := newCanvas(r.Params.Width, r.Params.Height)
	for _, layer := range r.Params.Layers {
		switch layer {
		case "sites":
			for _, p := range r.Points[1:] {
				canvas.mark(p.X, p.Y, 1, 'o')
			}
		case "circle":
			if r.EmptyVertex > 0 {
				c := r.Centers[r.EmptyVertex]
				canvas.mark(c.X, c.Y, c.D, '@')
			}
		default:
			edges, ch := r.Edges, byte('.')
			if layer == "mst" {
				edges, ch = r.MST, '*'
			}
			if layer == "hull" {
				edges, ch = r.HullEdges, '#'
			}
			for _, e := range edges {
				canvas.line(r.Points[e[0]], r.Points[e[1]], ch)
			}
		}
	}
	r.Sections["delaunay_plot"] = canvas.framed()
	canvas = newCanvas(r.Params.Width, r.Params.Height)
	canvas.drawVoronoi(r.Points)
	r.Sections["voronoi_plot"] = canvas.framed()
	r.Sections["input"] = append([]string{fmt.Sprintf("lines %d", r.LineCount), fmt.Sprintf("accepted %d",
		r.N), fmt.Sprintf("rejected %d", len(r.Rejected))}, r.Rejected...)
	owners := map[string][]string{"triangulation.txt": {"input", "summary", "insertions", "triangles",
		"edges", "hull", "convex_layers", "quality"}, "voronoi.txt": {"vertices", "voronoi_edges",
		"cells"}, "derived.txt": {"nearest", "components", "mst", "proximity", "degrees", "empty_circle",
		"extent", "spanner", "alpha", "sites", "queries"}, "plot.txt": {"delaunay_plot", "voronoi_plot"}}
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	for name, sections := range owners {
		owned := map[string]bool{}
		for _, s := range sections {
			owned[s] = true
		}
		lines := []string{}
		for _, s := range r.Params.Sections {
			if owned[s] {
				lines = append(lines, "["+s+"]")
				lines = append(lines, r.Sections[s]...)
			}
		}
		text := ""
		if len(lines) > 0 {
			text = strings.Join(lines, "\n") + "\n"
		}
		if e := os.WriteFile("output/"+name, []byte(text), 0644); e != nil {
			panic(e)
		}
	}
}
func main() {
	points, count, rejected := readPoints()
	report := newReport(points, count, rejected, readParams())
	report.buildTriangulation()
	report.analyzeTriangles()
	report.analyzeVoronoi()
	report.analyzeProximity()
	report.analyzeExtent()
	report.analyzeLayers()
	report.analyzeSpanner()
	report.analyzeAlpha()
	report.finish()
}
