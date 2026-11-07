package main

import (
	"fmt"
	"slices"
	"sort"
	"strconv"
	"strings"
)

type Circle struct {
	Number    int
	Cell      CircleCell
	Offsets   []Point
	Gap, Arcs int
	Shape     *Shape
}
type Segment struct {
	Number, Theta  int
	Start, End     Point
	Length, Pixels int
}
type Line struct {
	Number   int
	Cell     LineCell
	Segments []*Segment
}
type Junction struct {
	A, B, EndA, EndB int
	Point            Point
}

func (j Junction) endFor(segment int) int {
	if segment == j.A {
		return j.EndA
	}
	return j.EndB
}

type Polygon struct {
	Number                                   int
	Segments                                 []int
	Vertices                                 []Point
	Angles, Lengths, Supports, VertexCorners []int
	Sigma                                    int
	Kind                                     string
	Explained                                map[Point]bool
	Shape                                    *Shape
}
type Shape struct {
	Name                   string
	Polygon                *Polygon
	Circle                 *Circle
	Representatives        []Point
	Pixels, Mean, Contrast int
	Enclosing              string
}

func pointSub(a, b Point) Point    { return Point{a.X - b.X, a.Y - b.Y} }
func dot(a, b Point) int           { return a.X*b.X + a.Y*b.Y }
func chebyshev(a, b Point) int     { return max(abs(a.X-b.X), abs(a.Y-b.Y)) }
func angleDifference(a, b int) int { d := abs(a - b); return min(d, 180-d) }
func roundRatio(n, d int) int {
	if d < 0 {
		n, d = -n, -d
	}
	return floorDiv(2*n+d, 2*d)
}
func bresenham(a, b Point) []Point {
	x, y := a.X, a.Y
	dx, dy := abs(b.X-x), -abs(b.Y-y)
	sx, sy := -1, -1
	if x < b.X {
		sx = 1
	}
	if y < b.Y {
		sy = 1
	}
	error := dx + dy
	out := []Point{}
	for {
		out = append(out, Point{x, y})
		if x == b.X && y == b.Y {
			return out
		}
		twice := 2 * error
		if twice >= dy {
			error += dy
			x += sx
		}
		if twice <= dx {
			error += dx
			y += sy
		}
	}
}
func edgeAt(edge Mask, p Point) bool { return inside(p, len(edge[0]), len(edge)) && edge[p.Y][p.X] }
func nearEdge(edge Mask, p Point) bool {
	for dy := -1; dy <= 1; dy++ {
		for dx := -1; dx <= 1; dx++ {
			if edgeAt(edge, Point{p.X + dx, p.Y + dy}) {
				return true
			}
		}
	}
	return false
}
func circumference(circle *Circle, p Point) bool {
	dx, dy := p.X-circle.Cell.X, p.Y-circle.Cell.Y
	d := dx*dx + dy*dy
	r := circle.Cell.Radius
	return (r-1)*(r-1) <= d && d <= (r+1)*(r+1)
}
func chooseCircles(voting CircleVoting, edge Mask, limit int) []*Circle {
	out := []*Circle{}
	for i, cell := range voting.Peaks[:min(limit, len(voting.Peaks))] {
		circle := &Circle{Number: i + 1, Cell: cell, Offsets: voting.Offsets[cell.Radius-voting.Minimum]}
		hits := make([]bool, len(circle.Offsets))
		count := 0
		for j, o := range circle.Offsets {
			hits[j] = edgeAt(edge, Point{cell.X + o.X, cell.Y + o.Y})
			if hits[j] {
				count++
			}
		}
		if count == len(hits) {
			circle.Arcs = 1
		} else if count == 0 {
			circle.Gap = len(hits)
		} else {
			for j, hit := range hits {
				if hit && !hits[(j+len(hits)-1)%len(hits)] {
					circle.Arcs++
				}
			}
			run := 0
			for j := 0; j < 2*len(hits); j++ {
				if hits[j%len(hits)] {
					run = 0
				} else {
					run++
					circle.Gap = max(circle.Gap, run)
				}
			}
		}
		out = append(out, circle)
	}
	return out
}
func extractSegments(points []Point, voting LineVoting, trig Trig, p Params, width, height int) ([]*Line, []*Segment, Mask) {
	used := newMask(width, height)
	lines, segments := []*Line{}, []*Segment{}
	for _, cell := range voting.Peaks {
		if len(lines) == p.integer("hough_max_lines") {
			break
		}
		collected := []Point{}
		for _, point := range points {
			if !used[point.Y][point.X] && abs(rho(point, cell.Theta, trig, p.integer("hough_rho_step"))-cell.Rho) <= p.integer("segment_tolerance") {
				collected = append(collected, point)
			}
		}
		u := func(point Point) int { return point.Y*trig[cell.Theta].X - point.X*trig[cell.Theta].Y }
		sort.Slice(collected, func(i, j int) bool {
			a, b := collected[i], collected[j]
			ua, ub := u(a), u(b)
			if ua != ub {
				return ua < ub
			}
			if a.X != b.X {
				return a.X < b.X
			}
			return a.Y < b.Y
		})
		line := &Line{Number: len(lines) + 1, Cell: cell}
		for start := 0; start < len(collected); {
			end := start + 1
			for end < len(collected) && u(collected[end])-u(collected[end-1]) <= p.integer("segment_max_gap")*16384 {
				end++
			}
			group := collected[start:end]
			length := chebyshev(group[0], group[len(group)-1]) + 1
			if length >= p.integer("segment_min_length") {
				segment := &Segment{len(segments) + 1, cell.Theta, group[0], group[len(group)-1], length, len(group)}
				line.Segments = append(line.Segments, segment)
				segments = append(segments, segment)
				for _, point := range group {
					used[point.Y][point.X] = true
				}
			}
			start = end
		}
		if len(line.Segments) > 0 {
			lines = append(lines, line)
		}
	}
	return lines, segments, used
}
func pairKey(a, b int) [2]int {
	if a > b {
		a, b = b, a
	}
	return [2]int{a, b}
}
func junctions(segments []*Segment, p Params) (map[[2]int]Junction, [][]int) {
	found := map[[2]int]Junction{}
	adjacent := make([][]int, len(segments))
	for i, a := range segments {
		for j := i + 1; j < len(segments); j++ {
			b := segments[j]
			if angleDifference(a.Theta, b.Theta) < p.integer("junction_min_angle") {
				continue
			}
			da, db := pointSub(a.End, a.Start), pointSub(b.End, b.Start)
			den := cross(da, db)
			if den == 0 {
				continue
			}
			lambda := cross(pointSub(b.Start, a.Start), db)
			x := Point{roundRatio(a.Start.X*den+lambda*da.X, den), roundRatio(a.Start.Y*den+lambda*da.Y, den)}
			endA, endB := 0, 0
			distanceA, distanceB := chebyshev(a.Start, x), chebyshev(b.Start, x)
			if d := chebyshev(a.End, x); d < distanceA {
				distanceA, endA = d, 1
			}
			if d := chebyshev(b.End, x); d < distanceB {
				distanceB, endB = d, 1
			}
			if distanceA <= p.integer("junction_distance") && distanceB <= p.integer("junction_distance") {
				found[pairKey(a.Number, b.Number)] = Junction{a.Number, b.Number, endA, endB, x}
				adjacent[i] = append(adjacent[i], b.Number)
				adjacent[j] = append(adjacent[j], a.Number)
			}
		}
	}
	for _, row := range adjacent {
		sort.Ints(row)
	}
	return found, adjacent
}
func findPolygons(segments []*Segment, joins map[[2]int]Junction, adjacent [][]int) []*Polygon {
	out := []*Polygon{}
	for _, size := range []int{3, 4} {
		for first := 1; first <= len(segments); first++ {
			var extend func([]int)
			extend = func(path []int) {
				last := path[len(path)-1]
				if len(path) == size {
					closing, ok := joins[pairKey(last, first)]
					if !ok || path[1] >= last {
						return
					}
					previous := joins[pairKey(path[len(path)-2], last)]
					opening := joins[pairKey(first, path[1])]
					if previous.endFor(last) == closing.endFor(last) || closing.endFor(first) == opening.endFor(first) {
						return
					}
					vertices := []Point{}
					for i, current := range path {
						before := path[(i+size-1)%size]
						vertices = append(vertices, joins[pairKey(before, current)].Point)
					}
					sign := 0
					for i, v := range vertices {
						a, b := vertices[(i+1)%size], vertices[(i+2)%size]
						z := cross(pointSub(a, v), pointSub(b, a))
						if z == 0 {
							return
						}
						currentSign := 1
						if z < 0 {
							currentSign = -1
						}
						if sign != 0 && currentSign != sign {
							return
						}
						sign = currentSign
					}
					out = append(out, &Polygon{Number: len(out) + 1, Segments: append([]int{}, path...), Vertices: vertices})
					return
				}
				for _, next := range adjacent[last-1] {
					if next <= first || slices.Contains(path, next) {
						continue
					}
					if len(path) > 1 {
						before := joins[pairKey(path[len(path)-2], last)]
						after := joins[pairKey(last, next)]
						if before.endFor(last) == after.endFor(last) {
							continue
						}
					}
					extend(append(append([]int{}, path...), next))
				}
			}
			extend([]int{first})
		}
	}
	return out
}
func polygonAttributes(polygon *Polygon, segments []*Segment, edge Mask, p Params) {
	size := len(polygon.Vertices)
	polygon.Explained = map[Point]bool{}
	for i, v := range polygon.Vertices {
		previous, next := polygon.Vertices[(i+size-1)%size], polygon.Vertices[(i+1)%size]
		thetaPrevious := segments[polygon.Segments[(i+size-1)%size]-1].Theta
		theta := segments[polygon.Segments[i]-1].Theta
		angle := angleDifference(thetaPrevious, theta)
		if dot(pointSub(previous, v), pointSub(next, v)) < 0 {
			angle = 180 - angle
		}
		polygon.Angles = append(polygon.Angles, angle)
		delta := pointSub(next, v)
		polygon.Lengths = append(polygon.Lengths, delta.X*delta.X+delta.Y*delta.Y)
		polygon.Sigma += cross(v, next)
		points := bresenham(v, next)
		hits := 0
		for _, point := range points {
			if nearEdge(edge, point) {
				hits++
			}
			for dy := -1; dy <= 1; dy++ {
				for dx := -1; dx <= 1; dx++ {
					q := Point{point.X + dx, point.Y + dy}
					if inside(q, len(edge[0]), len(edge)) {
						polygon.Explained[q] = true
					}
				}
			}
		}
		polygon.Supports = append(polygon.Supports, 100*hits/len(points))
	}
	tolerance := p.integer("angle_tolerance")
	right, equilateral := true, true
	someRight := false
	for _, a := range polygon.Angles {
		if abs(a-90) > tolerance {
			right = false
		} else {
			someRight = true
		}
		if abs(a-60) > tolerance {
			equilateral = false
		}
	}
	if size == 3 {
		polygon.Kind = "triangle"
		if equilateral {
			polygon.Kind = "equilateral_triangle"
		} else if someRight {
			polygon.Kind = "right_triangle"
		}
		return
	}
	theta := func(i int) int { return segments[polygon.Segments[i]-1].Theta }
	parallelA, parallelB := angleDifference(theta(0), theta(2)) <= tolerance, angleDifference(theta(1), theta(3)) <= tolerance
	switch {
	case !parallelA && !parallelB:
		polygon.Kind = "quadrilateral"
	case parallelA != parallelB:
		polygon.Kind = "trapezoid"
	case !right:
		polygon.Kind = "parallelogram"
	default:
		smallest, largest := polygon.Lengths[0], polygon.Lengths[0]
		for _, v := range polygon.Lengths[1:] {
			smallest = min(smallest, v)
			largest = max(largest, v)
		}
		polygon.Kind = "rectangle"
		if 100*(largest-smallest) <= p.integer("square_tolerance")*largest {
			polygon.Kind = "square"
		}
	}
}
func (shape *Shape) contains(point Point) bool {
	if shape.Circle != nil {
		c := shape.Circle.Cell
		dx, dy := point.X-c.X, point.Y-c.Y
		return dx*dx+dy*dy <= c.Radius*c.Radius
	}
	polygon := shape.Polygon
	for i, v := range polygon.Vertices {
		next := polygon.Vertices[(i+1)%len(polygon.Vertices)]
		value := cross(pointSub(next, v), pointSub(point, v))
		if polygon.Sigma > 0 && value < 0 || polygon.Sigma < 0 && value > 0 {
			return false
		}
	}
	return true
}
func measureShapes(polygons []*Polygon, circles []*Circle, image Image, margin int) []*Shape {
	shapes := []*Shape{}
	for _, polygon := range polygons {
		shape := &Shape{Name: fmt.Sprintf("polygon %d", polygon.Number), Polygon: polygon, Representatives: polygon.Vertices, Enclosing: "none"}
		polygon.Shape = shape
		shapes = append(shapes, shape)
	}
	for _, circle := range circles {
		c := circle.Cell
		shape := &Shape{Name: fmt.Sprintf("circle %d", circle.Number), Circle: circle, Representatives: []Point{{c.X + c.Radius,
			c.Y}, {c.X, c.Y + c.Radius}, {c.X - c.Radius, c.Y}, {c.X, c.Y - c.Radius}}, Enclosing: "none"}
		circle.Shape = shape
		shapes = append(shapes, shape)
	}
	for _, shape := range shapes {
		first := shape.Representatives[0]
		x0, x1, y0, y1 := first.X, first.X, first.Y, first.Y
		for _, q := range shape.Representatives[1:] {
			x0 = min(x0, q.X)
			x1 = max(x1, q.X)
			y0 = min(y0, q.Y)
			y1 = max(y1, q.Y)
		}
		x0, x1 = max(0, x0-margin), min(len(image[0])-1, x1+margin)
		y0, y1 = max(0, y0-margin), min(len(image)-1, y1+margin)
		innerSum, outerSum, outerCount := 0, 0, 0
		for y := y0; y <= y1; y++ {
			for x := x0; x <= x1; x++ {
				if shape.contains(Point{x, y}) {
					shape.Pixels++
					innerSum += image[y][x]
				} else {
					outerCount++
					outerSum += image[y][x]
				}
			}
		}
		if shape.Pixels > 0 {
			shape.Mean = floorDiv(innerSum, shape.Pixels)
		}
		outerMean := 0
		if outerCount > 0 {
			outerMean = floorDiv(outerSum, outerCount)
		}
		shape.Contrast = shape.Mean - outerMean
	}
	for _, shape := range shapes {
		var enclosing *Shape
		for _, other := range shapes {
			if other == shape || other.Pixels <= shape.Pixels {
				continue
			}
			if enclosing != nil && other.Pixels >= enclosing.Pixels {
				continue
			}
			all := true
			for _, q := range shape.Representatives {
				if !other.contains(q) {
					all = false
					break
				}
			}
			if all {
				enclosing = other
			}
		}
		if enclosing != nil {
			shape.Enclosing = enclosing.Name
		}
	}
	return shapes
}
func matchCorners(corners []*Corner, polygons []*Polygon, segments []*Segment, limit int) (int, int, int) {
	onVertices, onSegments, verticesWithCorner := 0, 0, 0
	for _, corner := range corners {
		best := limit + 1
		for _, polygon := range polygons {
			for i, vertex := range polygon.Vertices {
				d := chebyshev(corner.Point, vertex)
				if d < best {
					best = d
					corner.Match = fmt.Sprintf("polygon %d vertex %d", polygon.Number, i+1)
				}
			}
		}
		if best <= limit {
			onVertices++
			continue
		}
		for _, segment := range segments {
			for i, point := range []Point{segment.Start, segment.End} {
				d := chebyshev(corner.Point, point)
				if d < best {
					best = d
					end := "start"
					if i == 1 {
						end = "end"
					}
					corner.Match = fmt.Sprintf("segment %d %s", segment.Number, end)
				}
			}
		}
		if best <= limit {
			onSegments++
		}
	}
	for _, polygon := range polygons {
		for _, vertex := range polygon.Vertices {
			best, number := limit+1, 0
			for _, corner := range corners {
				d := chebyshev(vertex, corner.Point)
				if d < best {
					best, number = d, corner.Number
				}
			}
			polygon.VertexCorners = append(polygon.VertexCorners, number)
			if number > 0 {
				verticesWithCorner++
			}
		}
	}
	return onVertices, onSegments, verticesWithCorner
}
func componentLines(groups [][]Point, edge Mask, magnitude, direction Image, shapes []*Shape) []string {
	lines := []string{fmt.Sprintf("components %d", len(groups))}
	for i, group := range groups {
		x0, x1, y0, y1 := group[0].X, group[0].X, group[0].Y, group[0].Y
		ends, total := 0, 0
		counts := map[int]int{}
		for _, point := range group {
			x0 = min(x0, point.X)
			x1 = max(x1, point.X)
			y0 = min(y0, point.Y)
			y1 = max(y1, point.Y)
			degree := 0
			for _, q := range neighbors(point, len(edge[0]), len(edge)) {
				if edge[q.Y][q.X] {
					degree++
				}
			}
			if degree == 1 {
				ends++
			}
			total += magnitude[point.Y][point.X]
			counts[direction[point.Y][point.X]]++
		}
		mainDirection := 0
		for _, d := range []int{45, 90, 135} {
			if counts[d] > counts[mainDirection] {
				mainDirection = d
			}
		}
		match, explained := "none", 0
		for _, shape := range shapes {
			count := 0
			for _, point := range group {
				if shape.Circle != nil {
					if circumference(shape.Circle, point) {
						count++
					}
				} else if shape.Polygon.Explained[point] {
					count++
				}
			}
			if count > explained {
				explained, match = count, shape.Name
			}
		}
		lines = append(lines, fmt.Sprintf("component %d pixels %d box %d %d %d %d ends %d strength %d direction %d shape %s explained %d",
			i+1, len(group), x0, y0, x1, y1, ends, total/len(group), mainDirection, match, explained))
	}
	return lines
}
func lineLines(lines []*Line) []string {
	out := []string{fmt.Sprintf("lines %d", len(lines))}
	for _, line := range lines {
		cell := line.Cell
		out = append(out, fmt.Sprintf("line %d theta %d rho %d votes %d segments %d", line.Number, cell.Theta, cell.Rho, cell.Votes, len(line.Segments)))
		for _, s := range line.Segments {
			out = append(out, fmt.Sprintf("segment %d start %d %d end %d %d length %d pixels %d", s.Number, s.Start.X, s.Start.Y, s.End.X, s.End.Y, s.Length, s.Pixels))
		}
	}
	return out
}
func circleLines(circles []*Circle) []string {
	out := []string{fmt.Sprintf("circles %d", len(circles))}
	for _, c := range circles {
		cell, shape := c.Cell, c.Shape
		out = append(out, fmt.Sprintf("circle %d center %d %d radius %d votes %d points %d gap %d arcs %d pixels %d mean %d contrast %d inside %s",
			c.Number, cell.X, cell.Y, cell.Radius, cell.Votes, cell.Points, c.Gap, c.Arcs, shape.Pixels,
			shape.Mean, shape.Contrast, shape.Enclosing))
	}
	return out
}
func polygonLines(polygons []*Polygon) []string {
	out := []string{fmt.Sprintf("polygons %d", len(polygons))}
	for _, polygon := range polygons {
		segments := []string{}
		for _, id := range polygon.Segments {
			segments = append(segments, strconv.Itoa(id))
		}
		shape := polygon.Shape
		sigma := abs(polygon.Sigma)
		out = append(out, fmt.Sprintf("polygon %d %s segments %s area %d.%d pixels %d mean %d contrast %d inside %s",
			polygon.Number, polygon.Kind, strings.Join(segments, " "), sigma/2, 5*(sigma%2), shape.Pixels,
			shape.Mean, shape.Contrast, shape.Enclosing))
		for i, v := range polygon.Vertices {
			corner := "none"
			if polygon.VertexCorners[i] > 0 {
				corner = strconv.Itoa(polygon.VertexCorners[i])
			}
			out = append(out, fmt.Sprintf("vertex %d %d %d angle %d corner %s", i+1, v.X, v.Y, polygon.Angles[i], corner))
		}
		for i, id := range polygon.Segments {
			out = append(out, fmt.Sprintf("side %d segment %d length2 %d support %d", i+1, id, polygon.Lengths[i], polygon.Supports[i]))
		}
	}
	return out
}
func cornerLines(corners []*Corner) []string {
	out := []string{fmt.Sprintf("corners %d", len(corners))}
	for _, c := range corners {
		out = append(out, fmt.Sprintf("corner %d %d %d response %d match %s", c.Number, c.Point.X, c.Point.Y, c.Response, c.Match))
	}
	return out
}
func overlay(image Image, segments []*Segment, circles []*Circle, corners []*Corner, divisor int) Image {
	width, height := len(image[0]), len(image)
	out := newImage(width, height)
	for y, row := range image {
		for x, v := range row {
			out[y][x] = v / divisor
		}
	}
	mark := func(q Point) {
		if inside(q, width, height) {
			out[q.Y][q.X] = 255
		}
	}
	for _, s := range segments {
		for _, q := range bresenham(s.Start, s.End) {
			mark(q)
		}
	}
	for _, c := range circles {
		for _, o := range c.Offsets {
			mark(Point{c.Cell.X + o.X, c.Cell.Y + o.Y})
		}
	}
	for _, c := range corners {
		for e := -2; e <= 2; e++ {
			mark(Point{c.Point.X + e, c.Point.Y})
			mark(Point{c.Point.X, c.Point.Y + e})
		}
	}
	return out
}
func main() {
	image, trig, p := readInputs()
	width, height := len(image[0]), len(image)
	gx, gy, magnitude := gradient(smooth(image, p))
	direction := directions(gx, gy)
	nms := suppress(magnitude, direction)
	edge, strong, weak, weakKept := hysteresis(nms, p.integer("canny_low"), p.integer("canny_high"))
	groups := components(edge)
	circleVoting := circleVote(edge, p)
	circles := chooseCircles(circleVoting, edge, p.integer("circle_max_count"))
	linePoints := []Point{}
	edgePixels, circleEdgePixels := 0, 0
	edgeImage := newImage(width, height)
	counts := map[string]int{}
	for y, row := range magnitude {
		for x, value := range row {
			if value > 0 {
				counts["gradient_nonzero"]++
			}
			counts["gradient_max"] = max(counts["gradient_max"], value)
			if nms[y][x] > 0 {
				counts["nms_kept"]++
			}
			if !edge[y][x] {
				continue
			}
			edgePixels++
			edgeImage[y][x] = 255
			counts[fmt.Sprintf("direction_%d", direction[y][x])]++
			circleEdge := false
			for _, circle := range circles {
				if circumference(circle, Point{x, y}) {
					circleEdge = true
					break
				}
			}
			if circleEdge {
				circleEdgePixels++
			} else {
				linePoints = append(linePoints, Point{x, y})
			}
		}
	}
	lineVoting := lineVote(linePoints, width, height, trig, p.integer("hough_rho_step"), p.integer("hough_threshold"))
	lines, segments, used := extractSegments(linePoints, lineVoting, trig, p, width, height)
	joins, adjacent := junctions(segments, p)
	polygons := findPolygons(segments, joins, adjacent)
	for _, polygon := range polygons {
		polygonAttributes(polygon, segments, edge, p)
		counts[polygon.Kind]++
	}
	shapes := measureShapes(polygons, circles, image, p.integer("contrast_margin"))
	corners, cornerCandidates := harris(gx, gy, p)
	onVertices, onSegments, verticesWithCorner := matchCorners(corners, polygons, segments, p.integer("corner_match_distance"))
	claimed := 0
	for _, row := range used {
		for _, present := range row {
			if present {
				claimed++
			}
		}
	}
	voteImage := newImage(180, lineVoting.High-lineVoting.Low+1)
	if lineVoting.Maximum > 0 {
		for t, row := range lineVoting.Votes {
			for r, v := range row {
				voteImage[r-lineVoting.Low][t] = 255 * v / lineVoting.Maximum
			}
		}
	}
	writePGM("edges.pgm", edgeImage)
	writePGM("hough.pgm", voteImage)
	writePGM("overlay.pgm", overlay(image, segments, circles, corners, p.integer("overlay_divisor")))
	writeLines("lines.txt", lineLines(lines))
	writeLines("circles.txt", circleLines(circles))
	writeLines("polygons.txt", polygonLines(polygons))
	writeLines("corners.txt", cornerLines(corners))
	writeLines("components.txt", componentLines(groups, edge, magnitude, direction, shapes))
	values := map[string]int{"strong": strong, "weak": weak, "edges": edgePixels, "weak_kept": weakKept,
		"weak_dropped": weak - weakKept, "edge_components": len(groups), "circle_candidates": circleVoting.Candidates,
		"circle_peaks": len(circleVoting.Peaks), "circles": len(circles), "circle_edge_pixels": circleEdgePixels,
		"line_edge_pixels": len(linePoints), "hough_max_votes": lineVoting.Maximum, "hough_peaks": len(lineVoting.Peaks),
		"lines": len(lines), "segments": len(segments), "claimed_pixels": claimed, "junctions": len(joins),
		"polygons": len(polygons), "corner_candidates": cornerCandidates, "corners": len(corners),
		"corners_on_vertices": onVertices, "corners_on_segments": onSegments, "corners_unmatched": len(corners) - onVertices - onSegments,
		"vertices_with_corner": verticesWithCorner}
	for key, value := range values {
		counts[key] = value
	}
	report := []string{fmt.Sprintf("image %d %d", width, height)}
	for _, key := range []string{"gradient_nonzero", "gradient_max", "nms_kept", "strong", "weak", "edges",
		"weak_kept", "weak_dropped", "edge_components", "direction_0", "direction_45", "direction_90",
		"direction_135", "circle_candidates", "circle_peaks", "circles", "circle_edge_pixels", "line_edge_pixels",
		"hough_max_votes", "hough_peaks", "lines", "segments", "claimed_pixels", "junctions", "polygons",
		"equilateral_triangle", "right_triangle", "triangle", "square", "rectangle", "parallelogram",
		"trapezoid", "quadrilateral", "corner_candidates", "corners", "corners_on_vertices", "corners_on_segments",
		"corners_unmatched", "vertices_with_corner"} {
		report = append(report, fmt.Sprintf("%s %d", key, counts[key]))
	}
	writeLines("report.txt", report)
}
