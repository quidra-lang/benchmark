package main

import (
	"fmt"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

type Polygon struct{ Input, Rings []Ring }
type Result struct {
	Polygons []*Polygon
	A, B     *Polygon
}
type SourceLine struct {
	Number int
	Text   string
}
type Laboratory struct {
	Used                                                             map[string]bool
	Polygons                                                         map[string]*Polygon
	Results                                                          map[int]*Result
	Output, Areas, Render, PolygonErrors, OperationErrors            []string
	Blocks, Valid, Defined, OperationCount, Succeeded, CrossingCount int
	Kinds, Accepted                                                  map[string]int
}

var unsignedWord = regexp.MustCompile(`^[0-9]{1,9}$`)
var integerWord = regexp.MustCompile(`^-?[0-9]{1,9}$`)
var nameWord = regexp.MustCompile(`^[a-z0-9_]{1,16}$`)
var kinds = []string{"UNION", "INTERSECTION", "DIFFERENCE", "XOR", "CLIP", "AREA", "MOVE", "ROTATE", "MIRROR", "SNAP", "LOCATE", "RENDER"}

func integer(s string) int64 {
	v, e := strconv.ParseInt(s, 10, 64)
	if e != nil {
		panic(e)
	}
	return v
}
func lines(path string) []string {
	b, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	if len(b) == 0 {
		return nil
	}
	return strings.Split(strings.TrimSuffix(string(b), "\n"), "\n")
}
func ignored(line string) bool { return line == "" || strings.HasPrefix(line, "#") }
func parseBlock(content []SourceLine, end int) ([]Ring, int) {
	rings := []Ring{}
	at := 0
	for at < len(content) {
		line := content[at]
		a := strings.Split(line.Text, " ")
		if len(a) != 2 || (a[0] != "OUTER" && a[0] != "HOLE") || !unsignedWord.MatchString(a[1]) || integer(a[1]) < 1 || (a[0] == "OUTER" && len(rings) > 0) || (a[0] == "HOLE" && len(rings) == 0) {
			return nil, line.Number
		}
		n := integer(a[1])
		at++
		ring := Ring{}
		for k := int64(0); k < n; k++ {
			if at == len(content) {
				return nil, end
			}
			line = content[at]
			v := strings.Split(line.Text, " ")
			if len(v) != 2 || !integerWord.MatchString(v[0]) || !integerWord.MatchString(v[1]) {
				return nil, line.Number
			}
			ring = append(ring, point(integer(v[0]), integer(v[1])))
			at++
		}
		rings = append(rings, ring)
	}
	if len(rings) == 0 {
		return nil, end
	}
	return rings, 0
}
func inRange(p Point) bool {
	return p.X.Cmp(rational(0)) >= 0 && p.X.Cmp(rational(1000)) <= 0 && p.Y.Cmp(rational(0)) >= 0 && p.Y.Cmp(rational(1000)) <= 0
}
func checkPolygon(rings []Ring) string {
	for k, ring := range rings {
		n := len(ring)
		if n < 3 {
			return fmt.Sprintf("too_few_vertices ring %d", k+1)
		}
		for _, p := range ring {
			if !inRange(p) {
				return fmt.Sprintf("out_of_range ring %d %s", k+1, p)
			}
		}
		seen := map[string]bool{}
		for _, p := range ring {
			key := p.String()
			if seen[key] {
				return fmt.Sprintf("duplicate_vertex ring %d %s", k+1, p)
			}
			seen[key] = true
		}
		for i, p := range ring {
			if cross(ring[(i+n-1)%n], p, ring[(i+1)%n]).Sign() == 0 {
				return fmt.Sprintf("collinear ring %d %s", k+1, p)
			}
		}
		for i, a := range ring {
			b := ring[(i+1)%n]
			for j := i + 1; j < n; j++ {
				if j == i+1 || (i == 0 && j == n-1) {
					continue
				}
				c, d := ring[j], ring[(j+1)%n]
				if touching(a, b, c, d) {
					return fmt.Sprintf("self_intersection ring %d %s %s", k+1, segmentText(a, b), segmentText(c, d))
				}
			}
		}
	}
	for i, first := range rings {
		for j := i + 1; j < len(rings); j++ {
			second := rings[j]
			for e, a := range first {
				b := first[(e+1)%len(first)]
				for f, c := range second {
					d := second[(f+1)%len(second)]
					if touching(a, b, c, d) {
						return fmt.Sprintf("rings_touch rings %d %d %s %s", i+1, j+1, segmentText(a, b), segmentText(c, d))
					}
				}
			}
		}
	}
	for k := 1; k < len(rings); k++ {
		if !insideRing(rings[k][0], rings[0]) {
			return fmt.Sprintf("hole_outside ring %d %s", k+1, rings[k][0])
		}
	}
	for i := 1; i < len(rings); i++ {
		for j := i + 1; j < len(rings); j++ {
			if insideRing(rings[j][0], rings[i]) {
				return fmt.Sprintf("hole_in_hole rings %d %d %s", i+1, j+1, rings[j][0])
			}
			if insideRing(rings[i][0], rings[j]) {
				return fmt.Sprintf("hole_in_hole rings %d %d %s", i+1, j+1, rings[i][0])
			}
		}
	}
	return ""
}
func (l *Laboratory) ReadPolygons() {
	source := lines("input/polygons.txt")
	for i := 0; i < len(source); i++ {
		if ignored(source[i]) {
			continue
		}
		start := i + 1
		name := strings.Split(source[i], " ")[1]
		content := []SourceLine{}
		i++
		for source[i] != "END" {
			if !ignored(source[i]) {
				content = append(content, SourceLine{i + 1, source[i]})
			}
			i++
		}
		end := i + 1
		l.Blocks++
		reason := ""
		if l.Used[name] {
			reason = fmt.Sprintf("duplicate_name line %d", start)
		} else {
			l.Used[name] = true
			rings, errorLine := parseBlock(content, end)
			if errorLine > 0 {
				reason = fmt.Sprintf("format line %d", errorLine)
			} else {
				reason = checkPolygon(rings)
				if reason == "" {
					l.Polygons[name] = canonical(rings)
					l.Valid++
				}
			}
		}
		if reason != "" {
			l.PolygonErrors = append(l.PolygonErrors, "polygon "+name+" "+reason)
		}
	}
}
func generalPosition(a, b *Polygon, aName, bName string) string {
	vertices := map[string]bool{}
	for _, ring := range b.Rings {
		for _, p := range ring {
			vertices[p.String()] = true
		}
	}
	for _, ring := range a.Rings {
		for _, p := range ring {
			if vertices[p.String()] {
				return "shared_vertex " + p.String()
			}
		}
	}
	for _, first := range a.Rings {
		for e, p := range first {
			q := first[(e+1)%len(first)]
			for _, second := range b.Rings {
				for f, r := range second {
					s := second[(f+1)%len(second)]
					if overlapping(p, q, r, s) {
						return "overlapping_edges " + segmentText(p, q) + " " + segmentText(r, s)
					}
				}
			}
		}
	}
	for side, polygons := range [][2]*Polygon{{a, b}, {b, a}} {
		firstName, secondName := aName, bName
		if side == 1 {
			firstName, secondName = bName, aName
		}
		for _, ring := range polygons[0].Rings {
			for _, p := range ring {
				for _, other := range polygons[1].Rings {
					for e, q := range other {
						r := other[(e+1)%len(other)]
						if onSegment(p, q, r) {
							return fmt.Sprintf("vertex_on_edge %s %s %s %s", firstName, p, secondName, segmentText(q, r))
						}
					}
				}
			}
		}
	}
	return ""
}
func (l *Laboratory) Polygon(name string) (*Polygon, string) {
	if !l.Used[name] {
		return nil, "unknown_polygon " + name
	}
	if p := l.Polygons[name]; p != nil {
		return p, ""
	}
	return nil, "invalid_polygon " + name
}
func (l *Laboratory) Target(text string) (*Result, string) {
	if strings.HasPrefix(text, "@") {
		number := strings.TrimPrefix(text, "@")
		if unsignedWord.MatchString(number) {
			if r := l.Results[int(integer(number))]; r != nil {
				return r, ""
			}
		}
		return nil, "bad_target " + text
	}
	p, reason := l.Polygon(text)
	if reason != "" {
		return nil, reason
	}
	return &Result{Polygons: []*Polygon{p}}, ""
}
func numeric(s string, low, high int64) bool {
	return integerWord.MatchString(s) && integer(s) >= low && integer(s) <= high
}
func validArguments(a []string) bool {
	required := map[string]int{"UNION": 3, "INTERSECTION": 3, "DIFFERENCE": 3, "XOR": 3, "CLIP": 3, "SNAP": 3, "AREA": 2, "LOCATE": 4, "MOVE": 5, "MIRROR": 5, "ROTATE": 6, "RENDER": 8}
	if len(a) != required[a[0]] {
		return false
	}
	switch a[0] {
	case "LOCATE":
		return numeric(a[2], 0, 1000) && numeric(a[3], 0, 1000)
	case "MOVE":
		return numeric(a[2], -1000, 1000) && numeric(a[3], -1000, 1000) && nameWord.MatchString(a[4])
	case "ROTATE":
		return numeric(a[2], 0, 1000) && numeric(a[3], 0, 1000) && numeric(a[4], 1, 3) && nameWord.MatchString(a[5])
	case "MIRROR":
		return (a[2] == "x" || a[2] == "y") && numeric(a[3], 0, 1000) && nameWord.MatchString(a[4])
	case "SNAP":
		return nameWord.MatchString(a[2])
	case "RENDER":
		for i := 2; i < 8; i++ {
			low, high := int64(0), int64(1000)
			if i == 4 || i == 5 || i == 6 {
				low, high = 1, 100
			}
			if i == 7 {
				low, high = 1, 60
			}
			if !numeric(a[i], low, high) {
				return false
			}
		}
		return integer(a[2])+integer(a[4])*integer(a[6]) <= 1000 && integer(a[3])+integer(a[5])*integer(a[7]) <= 1000
	}
	return true
}
func transformed(p *Polygon, a []string) []Ring {
	out := make([]Ring, len(p.Input))
	for i, ring := range p.Input {
		for _, v := range ring {
			x, y := v.X.value.Num().Int64(), v.Y.value.Num().Int64()
			switch a[0] {
			case "MOVE":
				x += integer(a[2])
				y += integer(a[3])
			case "ROTATE":
				cx, cy := integer(a[2]), integer(a[3])
				for q := int64(0); q < integer(a[4]); q++ {
					x, y = cx-(y-cy), cy+(x-cx)
				}
			case "MIRROR":
				if a[2] == "x" {
					x = 2*integer(a[3]) - x
				} else {
					y = 2*integer(a[3]) - y
				}
			}
			out[i] = append(out[i], point(x, y))
		}
	}
	return out
}
func convex(p *Polygon) bool {
	if len(p.Rings) != 1 {
		return false
	}
	r := p.Rings[0]
	for i, v := range r {
		if cross(r[(i+len(r)-1)%len(r)], v, r[(i+1)%len(r)]).Sign() <= 0 {
			return false
		}
	}
	return true
}
func cyclicEqual(a, b Ring) bool {
	if len(a) != len(b) {
		return false
	}
	for offset, p := range b {
		if !a[0].Equal(p) {
			continue
		}
		same := true
		for i, v := range a {
			if !v.Equal(b[(offset+i)%len(b)]) {
				same = false
				break
			}
		}
		if same {
			return true
		}
	}
	return false
}
func sutherland(subject, window *Polygon, result []*Polygon) (string, int, int) {
	clipped := []Ring{}
	for _, ring := range subject.Rings {
		list := ring
		for j, c1 := range window.Rings[0] {
			c2 := window.Rings[0][(j+1)%len(window.Rings[0])]
			next := Ring{}
			for i, cur := range list {
				prev := list[(i+len(list)-1)%len(list)]
				insidePrev, insideCur := cross(c1, c2, prev).Sign() > 0, cross(c1, c2, cur).Sign() > 0
				if insidePrev != insideCur {
					next = append(next, lineIntersection(prev, cur, c1, c2))
				}
				if insideCur {
					next = append(next, cur)
				}
			}
			list = next
		}
		deduplicated := Ring{}
		for i, p := range list {
			if !p.Equal(list[(i+len(list)-1)%len(list)]) {
				deduplicated = append(deduplicated, p)
			}
		}
		if len(deduplicated) >= 3 {
			clipped = append(clipped, deduplicated)
		}
	}
	vertices := 0
	for _, ring := range clipped {
		vertices += len(ring)
	}
	rings := flatten(result)
	match := len(rings) == len(clipped)
	if match {
		for _, r := range rings {
			found := false
			for _, other := range clipped {
				if cyclicEqual(r, other) {
					found = true
					break
				}
			}
			if !found {
				match = false
				break
			}
		}
	}
	judgment := "mismatch"
	if match {
		judgment = "match"
	}
	return judgment, len(clipped), vertices
}

func location(result *Result, p Point) string {
	for k, polygon := range result.Polygons {
		for j, ring := range polygon.Rings {
			if boundary(p, ring) {
				if j == 0 {
					return fmt.Sprintf("boundary outer %d", k+1)
				}
				return fmt.Sprintf("boundary hole %d %d", k+1, j)
			}
		}
	}
	for k, polygon := range result.Polygons {
		if !insideRing(p, polygon.Rings[0]) {
			continue
		}
		hole := false
		for _, ring := range polygon.Rings[1:] {
			if insideRing(p, ring) {
				hole = true
				break
			}
		}
		if !hole {
			return fmt.Sprintf("inside polygon %d", k+1)
		}
	}
	return "outside"
}
func operandLocation(p Point, polygon *Polygon) string {
	for _, ring := range polygon.Rings {
		if boundary(p, ring) {
			return "boundary"
		}
	}
	if interior(p, polygon.Rings) {
		return "inside"
	}
	return "outside"
}
func exactArea(ring Ring) Rational {
	sum := rational(0)
	for i, p := range ring {
		q := ring[(i+1)%len(ring)]
		sum = sum.Add(p.X.Mul(q.Y).Sub(q.X.Mul(p.Y)))
	}
	return sum.Div(rational(2))
}
func hull(ring Ring) Ring {
	sorted := append(Ring{}, ring...)
	sort.Slice(sorted, func(i, j int) bool {
		c := sorted[i].X.Cmp(sorted[j].X)
		if c != 0 {
			return c < 0
		}
		return sorted[i].Y.Cmp(sorted[j].Y) < 0
	})
	lower, upper := Ring{}, Ring{}
	for _, p := range sorted {
		for len(lower) >= 2 && cross(lower[len(lower)-2], lower[len(lower)-1], p).Sign() <= 0 {
			lower = lower[:len(lower)-1]
		}
		lower = append(lower, p)
	}
	for i := len(sorted) - 1; i >= 0; i-- {
		p := sorted[i]
		for len(upper) >= 2 && cross(upper[len(upper)-2], upper[len(upper)-1], p).Sign() <= 0 {
			upper = upper[:len(upper)-1]
		}
		upper = append(upper, p)
	}
	return append(lower[:len(lower)-1], upper[:len(upper)-1]...)
}
func (l *Laboratory) ReportRegion(number int, words []string, line string, result *Result, originA, originB, property *Polygon, g *GHGraph) {
	l.Output = append(l.Output, fmt.Sprintf("op %d %s", number, line))
	if g != nil {
		relation := "overlap"
		if len(g.Crossings) == 0 {
			switch {
			case g.NA == len(g.Rings[0]) && g.NB == 0:
				relation = "within"
			case g.NB == len(g.Rings[1]) && g.NA == 0:
				relation = "contains"
			case g.NA == 0 && g.NB == 0:
				relation = "disjoint"
			}
		}
		intersection := assemble(g.Traverse(false, false))
		union := assemble(g.Traverse(true, true))
		iou := totalArea(intersection) / totalArea(union)
		l.Output = append(l.Output, fmt.Sprintf("relation %s iou %.6f", relation, iou), fmt.Sprintf("crossings %d", len(g.Crossings)))
		for _, c := range g.Crossings {
			kind := "out"
			if c.First.Entering {
				kind = "in"
			}
			l.Output = append(l.Output, fmt.Sprintf("crossing %s %s", c.Point, kind))
		}
		l.CrossingCount += len(g.Crossings)
	}
	rings := flatten(result.Polygons)
	ringCount, holeCount, vertices := len(rings), len(rings)-len(result.Polygons), 0
	for _, r := range rings {
		vertices += len(r)
	}
	area := totalArea(result.Polygons)
	l.Output = append(l.Output, fmt.Sprintf("polygons %d rings %d holes %d vertices %d area %.3f", len(result.Polygons), ringCount, holeCount, vertices, area))
	for k, p := range result.Polygons {
		for j, r := range p.Rings {
			prefix := fmt.Sprintf("outer %d", k+1)
			if j > 0 {
				prefix = fmt.Sprintf("hole %d %d", k+1, j)
			}
			text := fmt.Sprintf("%s %d %.3f", prefix, len(r), ringArea(r))
			for _, v := range r {
				text += " " + v.String()
			}
			l.Output = append(l.Output, text)
		}
	}
	perimeter, sx, sy := 0.0, 0.0, 0.0
	var low, high Point
	hasPoint := false
	for _, r := range rings {
		perimeter += ringPerimeter(r)
		for i, p := range r {
			q := r[(i+1)%len(r)]
			if !hasPoint {
				low, high = p, p
				hasPoint = true
			}
			if p.X.Cmp(low.X) < 0 {
				low.X = p.X
			}
			if p.Y.Cmp(low.Y) < 0 {
				low.Y = p.Y
			}
			if p.X.Cmp(high.X) > 0 {
				high.X = p.X
			}
			if p.Y.Cmp(high.Y) > 0 {
				high.Y = p.Y
			}
			x1, y1, x2, y2 := p.X.Real(), p.Y.Real(), q.X.Real(), q.Y.Real()
			c := x1*y2 - x2*y1
			sx += (x1 + x2) * c
			sy += (y1 + y2) * c
		}
	}
	if hasPoint {
		l.Output = append(l.Output, fmt.Sprintf("bbox %s %s", low, high), fmt.Sprintf("centroid (%.3f,%.3f)", sx/(6*area), sy/(6*area)))
	} else {
		l.Output = append(l.Output, "bbox none", "centroid none")
	}
	l.Output = append(l.Output, fmt.Sprintf("perimeter %.3f", perimeter))
	aVertices, bVertices := map[string]bool{}, map[string]bool{}
	if originA != nil {
		for _, r := range originA.Rings {
			for _, p := range r {
				aVertices[p.String()] = true
			}
		}
	}
	if originB != nil {
		for _, r := range originB.Rings {
			for _, p := range r {
				bVertices[p.String()] = true
			}
		}
	}
	aCount, bCount, cCount := 0, 0, 0
	for _, r := range rings {
		for _, p := range r {
			key := p.String()
			if aVertices[key] {
				aCount++
			} else if bVertices[key] {
				bCount++
			} else {
				cCount++
			}
		}
	}
	l.Output = append(l.Output, fmt.Sprintf("origins a %d b %d crossing %d", aCount, bCount, cCount))
	if property != nil {
		orientations := []string{}
		for _, r := range property.Input {
			orientation := "cw"
			if exactArea(r).Sign() > 0 {
				orientation = "ccw"
			}
			orientations = append(orientations, orientation)
		}
		reflex := 0
		for _, r := range property.Rings {
			for i, p := range r {
				if cross(r[(i+len(r)-1)%len(r)], p, r[(i+1)%len(r)]).Sign() < 0 {
					reflex++
				}
			}
		}
		h := hull(property.Rings[0])
		hullArea := exactArea(h).Real()
		l.Output = append(l.Output, "input "+strings.Join(orientations, " "), fmt.Sprintf("reflex %d", reflex), fmt.Sprintf("hull %d %.3f solidity %.6f", len(h), hullArea, area/hullArea))
	}
	if words[0] == "CLIP" {
		judgment, k, v := sutherland(result.A, result.B, result.Polygons)
		l.Output = append(l.Output, fmt.Sprintf("crosscheck %s rings %d vertices %d", judgment, k, v))
	}
	l.Areas = append(l.Areas, fmt.Sprintf("%d:%s,%d,%d,%d,%.3f", number, strings.Join(words, ":"), ringCount, holeCount, vertices, area))
}
func (l *Laboratory) Operation(number int, line string) string {
	a := strings.Split(line, " ")
	kind := a[0]
	known := false
	for _, k := range kinds {
		if k == kind {
			known = true
			break
		}
	}
	if !known {
		return "unknown_operation " + kind
	}
	if !validArguments(a) {
		return "bad_arguments"
	}
	binary := kind == "UNION" || kind == "INTERSECTION" || kind == "DIFFERENCE" || kind == "XOR" || kind == "CLIP"
	definition := kind == "MOVE" || kind == "ROTATE" || kind == "MIRROR" || kind == "SNAP"
	var first, second, property *Polygon
	var target *Result
	reason := ""
	if binary || kind == "AREA" || kind == "MOVE" || kind == "ROTATE" || kind == "MIRROR" {
		first, reason = l.Polygon(a[1])
		if reason != "" {
			return reason
		}
		if binary {
			second, reason = l.Polygon(a[2])
			if reason != "" {
				return reason
			}
		}
	} else {
		target, reason = l.Target(a[1])
		if reason != "" {
			return reason
		}
	}
	newName := ""
	if definition {
		newName = a[len(a)-1]
		if l.Used[newName] {
			return "duplicate_name " + newName
		}
	}
	if kind == "SNAP" && len(target.Polygons) != 1 {
		return "not_single " + a[1]
	}
	if kind == "CLIP" && !convex(second) {
		return "not_convex " + a[2]
	}
	if binary {
		if reason = generalPosition(first, second, a[1], a[2]); reason != "" {
			return reason
		}
	}
	if definition {
		var input []Ring
		if kind == "SNAP" {
			for _, r := range target.Polygons[0].Rings {
				ring := Ring{}
				for _, p := range r {
					ring = append(ring, point(p.X.Round(), p.Y.Round()))
				}
				input = append(input, ring)
			}
			if reason = checkPolygon(input); reason != "" {
				return "invalid_result " + reason
			}
		} else {
			input = transformed(first, a)
			for _, r := range input {
				for _, p := range r {
					if !inRange(p) {
						return "out_of_range " + newName
					}
				}
			}
		}
		property = canonical(input)
		l.Used[newName] = true
		l.Polygons[newName] = property
		l.Defined++
	}
	l.Succeeded++
	l.Accepted[kind]++
	if kind == "LOCATE" {
		p := point(integer(a[2]), integer(a[3]))
		l.Output = append(l.Output, fmt.Sprintf("op %d %s", number, line), "location "+location(target, p))
		if target.A != nil && target.B != nil {
			l.Output = append(l.Output, "operands a "+operandLocation(p, target.A)+" b "+operandLocation(p, target.B))
		}
		return ""
	}
	if kind == "RENDER" {
		picture := render(target, integer(a[2]), integer(a[3]), integer(a[4]), integer(a[5]), integer(a[6]), integer(a[7]))
		l.Render = append(l.Render, fmt.Sprintf("render %d %s cols %d rows %d result %d a %d b %d both %d", number, a[1], integer(a[6]), integer(a[7]), picture.Result, picture.A, picture.B, picture.Both))
		l.Render = append(l.Render, picture.Rows...)
		return ""
	}
	var result *Result
	var g *GHGraph
	originA, originB := first, second
	if binary {
		g = graph(first.Rings, second.Rings)
		var polygons []*Polygon
		switch kind {
		case "UNION":
			polygons = assemble(g.Traverse(true, true))
		case "DIFFERENCE":
			polygons = assemble(g.Traverse(true, false))
		case "XOR":
			polygons = assemble(g.Traverse(true, false))
			other := graph(second.Rings, first.Rings)
			polygons = append(polygons, assemble(other.Traverse(true, false))...)
			sort.Slice(polygons, func(i, j int) bool { return pointLess(polygons[i].Rings[0][0], polygons[j].Rings[0][0]) })
		default:
			polygons = assemble(g.Traverse(false, false))
		}
		result = &Result{polygons, first, second}
	} else {
		if !definition {
			property = first
		}
		originA, originB = property, nil
		result = &Result{Polygons: []*Polygon{property}}
	}
	l.Results[number] = result
	l.ReportRegion(number, a, line, result, originA, originB, property, g)
	return ""
}
func main() {
	l := &Laboratory{Used: map[string]bool{}, Polygons: map[string]*Polygon{}, Results: map[int]*Result{}, Kinds: map[string]int{}, Accepted: map[string]int{}, Areas: []string{"operation,rings,holes,vertices,area"}}
	l.ReadPolygons()
	for _, line := range lines("input/operations.txt") {
		if ignored(line) {
			continue
		}
		l.OperationCount++
		kind := strings.Split(line, " ")[0]
		l.Kinds[kind]++
		reason := l.Operation(l.OperationCount, line)
		if reason != "" {
			l.OperationErrors = append(l.OperationErrors, fmt.Sprintf("op %d %s", l.OperationCount, reason))
		}
	}
	l.Output = append(l.Output, fmt.Sprintf("summary polygons %d valid %d invalid %d defined %d", l.Blocks, l.Valid, l.Blocks-l.Valid, l.Defined), fmt.Sprintf("summary operations %d succeeded %d rejected %d", l.OperationCount, l.Succeeded, len(l.OperationErrors)), fmt.Sprintf("summary crossings %d", l.CrossingCount))
	for _, kind := range kinds {
		l.Output = append(l.Output, fmt.Sprintf("kind %s %d %d", kind, l.Kinds[kind], l.Accepted[kind]))
	}
	rejections := []string{fmt.Sprintf("rejections %d", len(l.PolygonErrors)+len(l.OperationErrors))}
	rejections = append(rejections, l.PolygonErrors...)
	rejections = append(rejections, l.OperationErrors...)
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	writeLines("results.txt", l.Output)
	writeLines("areas.csv", l.Areas)
	writeLines("render.txt", l.Render)
	writeLines("rejections.txt", rejections)
}
func writeLines(name string, a []string) {
	s := ""
	if len(a) > 0 {
		s = strings.Join(a, "\n") + "\n"
	}
	if e := os.WriteFile("output/"+name, []byte(s), 0644); e != nil {
		panic(e)
	}
}
