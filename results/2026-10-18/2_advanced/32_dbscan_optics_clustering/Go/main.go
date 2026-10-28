package main

import (
	"fmt"
	"sort"
	"strings"
)

func line(parts ...any) string {
	fields := []string{}
	for _, part := range parts {
		fields = append(fields, fmt.Sprint(part))
	}
	return strings.Join(fields, " ")
}
func joined(values []int) string {
	fields := []string{}
	for _, value := range values {
		fields = append(fields, fmt.Sprint(value))
	}
	return strings.Join(fields, " ")
}
func valueText(v int64) string {
	if v == INF {
		return "-"
	}
	return fmt.Sprint(v)
}
func optionalRoot(v int64) string {
	if v == INF {
		return "-"
	}
	return rootText(v)
}
func optionalIndex(v int) string {
	if v < 0 {
		return "-"
	}
	return fmt.Sprint(v)
}
func labelChar(label int) string {
	if label < 0 {
		return "."
	}
	letters := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
	if label < len(letters) {
		return string(letters[label])
	}
	return "#"
}
func checkText(ok bool) string {
	if ok {
		return "ok"
	}
	return "mismatch"
}
func conditionText(ok bool) string {
	if ok {
		return "ok"
	}
	return "fail"
}
func abs(v int64) int64 {
	if v < 0 {
		return -v
	}
	return v
}
func integerRoot(n int64) int64 {
	if n == 0 {
		return 0
	}
	low, high := int64(0), n+1
	for low+1 < high {
		middle := (low + high) / 2
		if middle <= n/middle {
			low = middle
		} else {
			high = middle
		}
	}
	return low
}
func suggestedRadius(v int64) int {
	root := integerRoot(v)
	if root*root < v {
		root++
	}
	return max(1, int(root))
}
func pairs(n int) int64 { return int64(n) * int64(n-1) / 2 }
func joinParts(parts [][]string) []string {
	lines := []string{}
	for i, part := range parts {
		if i > 0 {
			lines = append(lines, "")
		}
		lines = append(lines, part...)
	}
	return lines
}

type Curve struct {
	Order     []int
	Values    []int64
	Knee, EPS int
	Cross     int64
}

func newCurve(points []Point, values []int64) Curve {
	c := Curve{Order: make([]int, len(points))}
	for i := range c.Order {
		c.Order[i] = i
	}
	sort.SliceStable(c.Order, func(i, j int) bool { return values[c.Order[i]] > values[c.Order[j]] })
	for _, i := range c.Order {
		c.Values = append(c.Values, values[i])
	}
	first, last := c.Values[0], c.Values[len(values)-1]
	for r, v := range c.Values {
		cross := abs(int64(len(values)-1)*(v-first) - (last-first)*int64(r))
		if cross > c.Cross {
			c.Cross, c.Knee = cross, r
		}
	}
	c.EPS = suggestedRadius(c.Values[c.Knee])
	return c
}

type GridSummary struct {
	EPS, Cells, Candidates, Pairs, BrutePairs int
	Busiest                                   Cell
	BusiestCount                              int
	Neighborhoods                             [][]int
	Consistent                                bool
	Occupancy                                 map[int]int
}

func newGridSummary(points []Point, eps int) GridSummary {
	grid := newGrid(points, eps)
	g := GridSummary{EPS: eps, Cells: len(grid.Cells), Consistent: true, Occupancy: map[int]int{}}
	total := 0
	for i := range points {
		n, c := grid.Neighborhood(i)
		g.Neighborhoods = append(g.Neighborhoods, n)
		g.Candidates += c
		total += len(n)
	}
	g.Pairs = (total - len(points)) / 2
	brute := bruteForceCounts(points, eps)
	count := 0
	for i, c := range brute {
		count += c
		if c != len(g.Neighborhoods[i]) {
			g.Consistent = false
		}
	}
	g.BrutePairs = (count - len(points)) / 2
	g.Busiest, g.BusiestCount = grid.Busiest()
	for _, row := range grid.Cells {
		g.Occupancy[len(row)]++
	}
	return g
}
func (g GridSummary) Lines() []string {
	sizes := []int{}
	for size := range g.Occupancy {
		sizes = append(sizes, size)
	}
	sort.Ints(sizes)
	occupancy := []string{}
	for _, size := range sizes {
		occupancy = append(occupancy, fmt.Sprintf("%d:%d", size, g.Occupancy[size]))
	}
	return []string{line("eps", g.EPS, "cells", g.Cells, "busiest", g.Busiest.X, g.Busiest.Y, g.BusiestCount,
		"candidates", g.Candidates, "pairs", g.Pairs, "brute_pairs", g.BrutePairs, checkText(g.Consistent)),
		"  occupancy " + strings.Join(occupancy, " ")}
}

type Setting struct {
	Name, Kind                    string
	Radius                        int
	Labels                        []int
	Core                          []bool
	Members                       [][]int
	Noise, CoreCount, BorderCount int
}

func newSetting(name, kind string, radius int, labels []int, core []bool) *Setting {
	s := &Setting{Name: name, Kind: kind, Radius: radius, Labels: labels, Core: core}
	count := 0
	for _, label := range labels {
		count = max(count, label+1)
	}
	s.Members = make([][]int, count)
	for i, label := range labels {
		if label < 0 {
			s.Noise++
		} else {
			s.Members[label] = append(s.Members[label], i)
			if core[i] {
				s.CoreCount++
			} else {
				s.BorderCount++
			}
		}
	}
	return s
}
func extract(order []int, reach, core []int64, radius int) ([]int, []bool) {
	labels, isCore := make([]int, len(order)), make([]bool, len(order))
	for i := range labels {
		labels[i] = -1
	}
	cluster := -1
	limit := int64(radius) * int64(radius)
	for _, p := range order {
		if reach[p] > limit {
			if core[p] <= limit {
				cluster++
				labels[p] = cluster
			}
		} else {
			labels[p] = cluster
		}
		isCore[p] = core[p] <= limit
	}
	return labels, isCore
}

type DownArea struct {
	Start, End int
	High       int64
}
type SteepArea struct {
	Kind       string
	Start, End int
}
type Xi struct {
	Reach                                  []int64
	Alpha, Beta                            int64
	MinPts, MinSize                        int
	SteepUp, SteepDown, Up, Down           []bool
	Areas                                  []SteepArea
	Clusters                               [][2]int
	PositionLabels, ClusterLabels, Parents []int
}

func newXi(reach []int64, p Params) *Xi {
	n := len(reach) - 1
	x := &Xi{Reach: reach, Alpha: int64((p.XiV - p.XiU) * (p.XiV - p.XiU)), Beta: int64(p.XiV * p.XiV),
		MinPts: p.MinPts, MinSize: p.XiMinSize, SteepUp: make([]bool, n), SteepDown: make([]bool,
			n), Up: make([]bool, n), Down: make([]bool, n)}
	for i := 0; i < n; i++ {
		a, b := reach[i], reach[i+1]
		defined := a != INF || b != INF
		x.SteepUp[i] = defined && x.Xle(a, b)
		x.SteepDown[i] = defined && x.Xle(b, a)
		x.Up[i] = a < b
		x.Down[i] = a > b
	}
	x.Scan()
	x.PositionLabels = make([]int, n)
	for i := range x.PositionLabels {
		x.PositionLabels[i] = -1
	}
	next := 0
	for _, cluster := range x.Clusters {
		start, end := cluster[0], cluster[1]
		free := true
		for i := start; i <= end; i++ {
			if x.PositionLabels[i] >= 0 {
				free = false
			}
		}
		label := -1
		if free {
			label = next
			next++
			for i := start; i <= end; i++ {
				x.PositionLabels[i] = label
			}
		}
		x.ClusterLabels = append(x.ClusterLabels, label)
	}
	for j, c := range x.Clusters {
		best, bestSize := -1, 0
		size := c[1] - c[0] + 1
		for i, other := range x.Clusters {
			os := other[1] - other[0] + 1
			if i == j || other[0] > c[0] || c[1] > other[1] || os < size || os == size && i < j {
				continue
			}
			if best < 0 || os < bestSize {
				best, bestSize = i, os
			}
		}
		x.Parents = append(x.Parents, best)
	}
	return x
}
func (x *Xi) Xle(a, b int64) bool {
	if b == INF {
		return true
	}
	if a == INF {
		return false
	}
	return x.Beta*a <= x.Alpha*b
}
func (x *Xi) RegionEnd(start int, steep, reverse []bool) int {
	end, flat := start, 0
	for i := start; i < len(steep); i++ {
		if steep[i] {
			end, flat = i, 0
		} else if reverse[i] {
			break
		} else {
			flat++
			if flat > x.MinPts {
				break
			}
		}
	}
	return end
}
func (x *Xi) Scan() {
	downAreas := []DownArea{}
	index := 0
	mib := int64(0)
	for start := 0; start < len(x.SteepUp); start++ {
		if start < index || !(x.SteepUp[start] || x.SteepDown[start]) {
			continue
		}
		for i := index; i <= start; i++ {
			mib = max(mib, x.Reach[i])
		}
		if mib == INF {
			downAreas = nil
		} else {
			kept := []DownArea{}
			for _, area := range downAreas {
				if x.Xle(mib, x.Reach[area.Start]) {
					area.High = max(area.High, mib)
					kept = append(kept, area)
				}
			}
			downAreas = kept
		}
		if x.SteepDown[start] {
			end := x.RegionEnd(start, x.SteepDown, x.Up)
			x.Areas = append(x.Areas, SteepArea{"down", start, end})
			downAreas = append(downAreas, DownArea{Start: start, End: end})
			index = end + 1
			mib = x.Reach[index]
		} else {
			end := x.RegionEnd(start, x.SteepUp, x.Down)
			x.Areas = append(x.Areas, SteepArea{"up", start, end})
			index = end + 1
			mib = x.Reach[index]
			candidates := [][2]int{}
			for _, area := range downAreas {
				cs, ce := area.Start, end
				if !x.Xle(area.High, x.Reach[ce+1]) {
					continue
				}
				top := x.Reach[area.Start]
				if x.Xle(x.Reach[ce+1], top) {
					for cs < area.End && x.Reach[cs+1] > x.Reach[ce+1] {
						cs++
					}
				} else if x.Xle(top, x.Reach[ce+1]) {
					for ce > start && x.Reach[ce-1] > top {
						ce--
					}
				}
				if ce-cs+1 >= x.MinSize && cs <= area.End && ce >= start {
					candidates = append(candidates, [2]int{cs, ce})
				}
			}
			for i := len(candidates) - 1; i >= 0; i-- {
				x.Clusters = append(x.Clusters, candidates[i])
			}
		}
	}
}
func turn(o, a, b Point) int64 { return (a.X-o.X)*(b.Y-o.Y) - (a.Y-o.Y)*(b.X-o.X) }
func halfHull(points []Point) []Point {
	hull := []Point{}
	for _, p := range points {
		for len(hull) >= 2 && turn(hull[len(hull)-2], hull[len(hull)-1], p) <= 0 {
			hull = hull[:len(hull)-1]
		}
		hull = append(hull, p)
	}
	return hull
}
func convexHull(points []Point) []Point {
	ordered := append([]Point(nil), points...)
	sort.Slice(ordered, func(i, j int) bool {
		if ordered[i].X != ordered[j].X {
			return ordered[i].X < ordered[j].X
		}
		return ordered[i].Y < ordered[j].Y
	})
	if len(ordered) <= 2 {
		return ordered
	}
	lower := halfHull(ordered)
	for i, j := 0, len(ordered)-1; i < j; i, j = i+1, j-1 {
		ordered[i], ordered[j] = ordered[j], ordered[i]
	}
	upper := halfHull(ordered)
	return append(lower[:len(lower)-1], upper[:len(upper)-1]...)
}
func clusterLines(points []Point, s *Setting, label int) []string {
	members := s.Members[label]
	n := int64(len(members))
	sx, sy := int64(0), int64(0)
	core := 0
	loX, loY, hiX, hiY := points[members[0]].X, points[members[0]].Y, points[members[0]].X, points[members[0]].Y
	all := []Point{}
	for _, i := range members {
		p := points[i]
		all = append(all, p)
		sx += p.X
		sy += p.Y
		if s.Core[i] {
			core++
		}
		loX, loY, hiX, hiY = min(loX, p.X), min(loY, p.Y), max(hiX, p.X), max(hiY, p.Y)
	}
	medoid := members[0]
	best := int64(1 << 62)
	for _, i := range members {
		p := points[i]
		dx, dy := n*p.X-sx, n*p.Y-sy
		d := dx*dx + dy*dy
		if d < best {
			best, medoid = d, i
		}
	}
	area := (hiX - loX + 1) * (hiY - loY + 1)
	hull := convexHull(all)
	doubled, diameter := int64(0), int64(0)
	for i, p := range hull {
		q := hull[(i+1)%len(hull)]
		doubled += p.X*q.Y - q.X*p.Y
		for _, q := range hull {
			diameter = max(diameter, squaredDistance(p, q))
		}
	}
	doubled = abs(doubled)
	return []string{line("cluster", label, labelChar(label), "size", n, "core", core, "border", len(members)-core,
		"centroid", fractionText(sx, n), fractionText(sy, n), "medoid", points[medoid].ID), "  " + line("bbox",
		loX, loY, hiX, hiY, "area", area, "density", fractionText(n, area)), "  " + line("hull",
		len(hull), "hull_area", fmt.Sprintf("%d.%d", doubled/2, (doubled%2)*5), "diameter_sq", diameter,
		"diameter", rootText(diameter))}
}
func adjustedRand(a, b []int) (int64, int64) {
	joint := map[[2]int]int{}
	first, second := map[int]int{}, map[int]int{}
	for i, v := range a {
		joint[[2]int{v, b[i]}]++
		first[v]++
		second[b[i]]++
	}
	s, x, y := int64(0), int64(0), int64(0)
	for _, n := range joint {
		s += pairs(n)
	}
	for _, n := range first {
		x += pairs(n)
	}
	for _, n := range second {
		y += pairs(n)
	}
	z := pairs(len(a))
	numerator, denominator := 2*(z*s-x*y), z*(x+y)-2*x*y
	if denominator == 0 {
		return 1, 1
	}
	return numerator, denominator
}

type Analysis struct {
	Points                 []Point
	Params                 Params
	Curves                 []Curve
	Curve                  Curve
	Kdist                  []int64
	Grids                  []GridSummary
	Neighborhoods          map[int][][]int
	Settings               []*Setting
	Knee, XiSetting        *Setting
	Core, Reach, Positions []int64
	Order, Predecessor     []int
	Xi                     *Xi
	MapCells               [][2]int
}

func newAnalysis(points []Point, p Params) *Analysis {
	a := &Analysis{Points: points, Params: p, Neighborhoods: map[int][][]int{}}
	rows := make([][]int64, len(points))
	for i, point := range points {
		for j, other := range points {
			if i != j {
				rows[i] = append(rows[i], squaredDistance(point, other))
			}
		}
		sort.Slice(rows[i], func(x, y int) bool { return rows[i][x] < rows[i][y] })
	}
	for j := 0; j < 2*p.MinPts; j++ {
		values := []int64{}
		for _, row := range rows {
			values = append(values, row[j])
		}
		a.Curves = append(a.Curves, newCurve(points, values))
		if j == p.MinPts-2 {
			a.Kdist = values
		}
	}
	a.Curve = a.Curves[p.MinPts-2]
	radii := map[int]bool{a.Curve.EPS: true, p.MaxEPS: true}
	for _, eps := range p.EPS {
		radii[eps] = true
	}
	sorted := []int{}
	for eps := range radii {
		sorted = append(sorted, eps)
	}
	sort.Ints(sorted)
	for _, eps := range sorted {
		g := newGridSummary(points, eps)
		a.Grids = append(a.Grids, g)
		a.Neighborhoods[eps] = g.Neighborhoods
	}
	for _, eps := range p.EPS {
		a.addDB(fmt.Sprintf("db%d", eps), eps)
	}
	a.Knee = a.addDB(fmt.Sprintf("knee%d", a.Curve.EPS), a.Curve.EPS)
	a.Core = coreDistances(points, a.Neighborhoods[p.MaxEPS], p.MinPts)
	a.Order, a.Reach, a.Predecessor = opticsOrdering(points, a.Neighborhoods[p.MaxEPS], a.Core)
	for _, eps := range p.Extract {
		labels, core := extract(a.Order, a.Reach, a.Core, eps)
		a.Settings = append(a.Settings, newSetting(fmt.Sprintf("op%d", eps), "extract", eps, labels, core))
	}
	for _, i := range a.Order {
		a.Positions = append(a.Positions, a.Reach[i])
	}
	a.Positions = append(a.Positions, INF)
	a.Xi = newXi(a.Positions, p)
	labels, core := make([]int, len(points)), make([]bool, len(points))
	for pos, i := range a.Order {
		labels[i] = a.Xi.PositionLabels[pos]
		core[i] = a.Core[i] != INF
	}
	a.XiSetting = newSetting("xi", "xi", p.MaxEPS, labels, core)
	a.Settings = append(a.Settings, a.XiSetting)
	loX, hiX, loY, hiY := points[0].X, points[0].X, points[0].Y, points[0].Y
	for _, point := range points {
		loX, hiX, loY, hiY = min(loX, point.X), max(hiX, point.X), min(loY, point.Y), max(hiY, point.Y)
	}
	for _, point := range points {
		a.MapCells = append(a.MapCells, [2]int{int((point.X - loX) * int64(p.MapWidth) / (hiX - loX + 1)),
			int((hiY - point.Y) * int64(p.MapHeight) / (hiY - loY + 1))})
	}
	return a
}
func (a *Analysis) addDB(name string, eps int) *Setting {
	labels, core := dbscan(a.Neighborhoods[eps], a.Params.MinPts)
	s := newSetting(name, "dbscan", eps, labels, core)
	a.Settings = append(a.Settings, s)
	return s
}
func (a *Analysis) dbSettings() []*Setting {
	settings := []*Setting{}
	for _, s := range a.Settings {
		if s.Kind == "dbscan" {
			settings = append(settings, s)
		}
	}
	return settings
}
func (a *Analysis) labelsLines() []string {
	names := []string{"id"}
	for _, s := range a.Settings {
		names = append(names, s.Name)
	}
	lines := []string{strings.Join(names, ",")}
	for i, p := range a.Points {
		fields := []string{fmt.Sprint(p.ID)}
		for _, s := range a.Settings {
			fields = append(fields, fmt.Sprint(s.Labels[i]))
		}
		lines = append(lines, strings.Join(fields, ","))
	}
	return lines
}
func (a *Analysis) opticsLines() []string {
	lines := []string{"order,id,core_sq,reach_sq,reach,predecessor"}
	for pos, i := range a.Order {
		predecessor := "-"
		if a.Predecessor[i] >= 0 {
			predecessor = fmt.Sprint(a.Points[a.Predecessor[i]].ID)
		}
		lines = append(lines, fmt.Sprintf("%d,%d,%s,%s,%s,%s", pos+1, a.Points[i].ID, valueText(a.Core[i]),
			valueText(a.Reach[i]), optionalRoot(a.Reach[i]), predecessor))
	}
	return lines
}
func (a *Analysis) kdistLines() []string {
	c := a.Curve
	lines := []string{line("k_distance", "k", a.Params.MinPts-1, "points", len(a.Points)), "rank id kdist_sq kdist"}
	for rank, i := range c.Order {
		v := c.Values[rank]
		lines = append(lines, line(rank+1, a.Points[i].ID, v, rootText(v)))
	}
	v := c.Values[c.Knee]
	lines = append(lines, "", line("knee", "rank", c.Knee+1, "id", a.Points[c.Order[c.Knee]].ID, "kdist_sq",
		v, "kdist", rootText(v), "cross", c.Cross), line("suggested_eps", c.EPS), "", "knee_table")
	for j, row := range a.Curves {
		lines = append(lines, line("k", j+1, "rank", row.Knee+1, "id", a.Points[row.Order[row.Knee]].ID, "kdist_sq", row.Values[row.Knee], "eps", row.EPS))
	}
	lines = append(lines, "", "core_check")
	for _, s := range a.dbSettings() {
		count, grid := 0, 0
		limit := int64(s.Radius * s.Radius)
		for i, v := range a.Kdist {
			if v <= limit {
				count++
			}
			if s.Core[i] {
				grid++
			}
		}
		lines = append(lines, line("eps", s.Radius, "core", count, "non_core", len(a.Points)-count, "grid_core", grid, checkText(count == grid)))
	}
	count := 0
	consistent := true
	for i, v := range a.Core {
		if v != INF {
			count++
			if v != a.Kdist[i] {
				consistent = false
			}
		}
	}
	return append(lines, line("optics", "max_eps", a.Params.MaxEPS, "core", count, checkText(consistent)))
}
func (a *Analysis) settingLines(s *Setting) []string {
	lines := []string{line("setting", s.Name, "eps", s.Radius, "clusters", len(s.Members), "noise", s.Noise, "core", s.CoreCount, "border", s.BorderCount)}
	for label := range s.Members {
		lines = append(lines, clusterLines(a.Points, s, label)...)
	}
	if s.Kind != "dbscan" {
		return lines
	}
	linked, supported, separated := true, true, true
	isolated := 0
	ambiguous := []string{}
	for i, neighbors := range a.Neighborhoods[s.Radius] {
		coreLabels := map[int]bool{}
		for _, j := range neighbors {
			if s.Core[j] {
				coreLabels[s.Labels[j]] = true
			}
		}
		label := s.Labels[i]
		if s.Core[i] {
			for other := range coreLabels {
				if other != label {
					linked = false
				}
			}
		} else if label >= 0 {
			if !coreLabels[label] {
				supported = false
			}
			others := []int{}
			for other := range coreLabels {
				if other != label {
					others = append(others, other)
				}
			}
			sort.Ints(others)
			if len(others) > 0 {
				ambiguous = append(ambiguous, "  "+line(a.Points[i].ID, "cluster", label, "also", joined(others)))
			}
		} else {
			if len(coreLabels) > 0 {
				separated = false
			}
			if len(neighbors) == 1 {
				isolated++
			}
		}
	}
	lines = append(lines, line("check", conditionText(linked), conditionText(supported), conditionText(separated)),
		line("isolated", isolated), line("ambiguous", len(ambiguous)))
	return append(lines, ambiguous...)
}
func (a *Analysis) hierarchyLines() []string {
	ordered := a.dbSettings()
	sort.SliceStable(ordered, func(i, j int) bool { return ordered[i].Radius < ordered[j].Radius })
	lines := []string{"hierarchy"}
	for i := 1; i < len(ordered); i++ {
		small, large := ordered[i-1], ordered[i]
		lines = append(lines, line(small.Name, "->", large.Name))
		sources := make([][]int, len(large.Members))
		for cluster, members := range small.Members {
			for _, p := range members {
				if small.Core[p] {
					destination := large.Labels[p]
					sources[destination] = append(sources[destination], cluster)
					break
				}
			}
		}
		for label, clusters := range sources {
			text := "-"
			if len(clusters) > 0 {
				text = joined(clusters)
			}
			lines = append(lines, "  "+line(label, "<-", text))
		}
	}
	return lines
}
func (a *Analysis) comparisonLines() []string {
	lines := []string{"optics_vs_dbscan"}
	for _, s := range a.Settings {
		if s.Kind != "extract" {
			continue
		}
		var reference *Setting
		for _, r := range a.dbSettings() {
			if r.Radius == s.Radius {
				reference = r
				break
			}
		}
		if reference == nil {
			continue
		}
		pairSet := map[[2]int]bool{}
		first, second := map[int]bool{}, map[int]bool{}
		mapping := map[int]int{}
		border := 0
		for i, label := range s.Labels {
			if s.Core[i] {
				other := reference.Labels[i]
				pairSet[[2]int{label, other}] = true
				first[label] = true
				second[other] = true
				mapping[label] = other
			}
			if label < 0 && reference.Labels[i] >= 0 {
				border++
			}
		}
		same := len(pairSet) == len(first) && len(pairSet) == len(second)
		state, moved := "different", "-"
		if same {
			state = "same"
			count := 0
			for i, label := range s.Labels {
				if label >= 0 && mapping[label] != reference.Labels[i] {
					count++
				}
			}
			moved = fmt.Sprint(count)
		}
		lines = append(lines, line(s.Name, reference.Name, "core_partition", state, "border_as_noise", border, "moved", moved))
	}
	return lines
}
func (a *Analysis) opticsSummary() []string {
	components := []int{}
	core := 0
	for _, i := range a.Order {
		if a.Reach[i] == INF {
			components = append(components, 0)
		}
		components[len(components)-1]++
		if a.Core[i] != INF {
			core++
		}
	}
	singletons, largest := 0, 0
	for _, n := range components {
		if n == 1 {
			singletons++
		}
		largest = max(largest, n)
	}
	return []string{line("optics", "max_eps", a.Params.MaxEPS, "core", core, "components", len(components), "singletons", singletons, "largest", largest)}
}
func (a *Analysis) sweepLines() []string {
	lines := []string{line("sweep", "max_eps", a.Params.MaxEPS), "eps clusters noise largest"}
	counts := []int{}
	for eps := 1; eps <= a.Params.MaxEPS; eps++ {
		labels, _ := extract(a.Order, a.Reach, a.Core, eps)
		sizes := map[int]int{}
		noise, count, largest := 0, 0, 0
		for _, label := range labels {
			if label < 0 {
				noise++
			} else {
				sizes[label]++
				count = max(count, label+1)
				largest = max(largest, sizes[label])
			}
		}
		counts = append(counts, count)
		lines = append(lines, line(eps, count, noise, largest))
	}
	bestStart, bestEnd, bestLength := -1, 0, 0
	for start := 0; start < len(counts); {
		end := start
		for end+1 < len(counts) && counts[end+1] == counts[start] {
			end++
		}
		length := end - start + 1
		if counts[start] >= 2 && length > bestLength {
			bestStart, bestEnd, bestLength = start, end, length
		}
		start = end + 1
	}
	if bestStart < 0 {
		return append(lines, "stable -")
	}
	return append(lines, line("stable", "clusters", counts[bestStart], "eps", bestStart+1, bestEnd+1, "length", bestLength))
}
func (a *Analysis) xiLines() []string {
	x := a.Xi
	lines := []string{line("xi", a.Params.XiText, "min_size", a.Params.XiMinSize, "steep_areas", len(x.Areas))}
	for _, area := range x.Areas {
		lines = append(lines, line(area.Kind, area.Start+1, area.End+1))
	}
	lines = append(lines, line("xi_clusters", len(x.Clusters)))
	for j, c := range x.Clusters {
		start, end := c[0], c[1]
		valley := INF
		for _, v := range x.Reach[start+1 : end+1] {
			valley = min(valley, v)
		}
		lines = append(lines, line(j, "start", start+1, "end", end+1, "size", end-start+1, "label", optionalIndex(x.ClusterLabels[j]),
			"parent", optionalIndex(x.Parents[j]), "walls", optionalRoot(x.Reach[start]), optionalRoot(x.Reach[end+1]),
			"valley", optionalRoot(valley)))
	}
	return lines
}
func (a *Analysis) outlierLines() []string {
	type Row struct {
		Distance       int64
		Point, Nearest int
	}
	rows := []Row{}
	s := a.Knee
	for i, label := range s.Labels {
		if label >= 0 {
			continue
		}
		nearest := -1
		best := INF
		for j, isCore := range s.Core {
			if isCore {
				d := squaredDistance(a.Points[i], a.Points[j])
				if d < best {
					best, nearest = d, j
				}
			}
		}
		rows = append(rows, Row{best, i, nearest})
	}
	sort.SliceStable(rows, func(i, j int) bool { return rows[i].Distance > rows[j].Distance })
	lines := []string{line("outliers", s.Name, "count", len(rows))}
	for _, r := range rows {
		lines = append(lines, line(a.Points[r.Point].ID, "nearest_core", a.Points[r.Nearest].ID, "cluster",
			s.Labels[r.Nearest], "dist_sq", r.Distance, "dist", rootText(r.Distance)))
	}
	return lines
}
func (a *Analysis) gapLines() []string {
	s := a.Knee
	lines := []string{line("gaps", s.Name)}
	for first := 0; first < len(s.Members); first++ {
		for second := first + 1; second < len(s.Members); second++ {
			best := INF
			p, q := -1, -1
			for _, i := range s.Members[first] {
				for _, j := range s.Members[second] {
					d := squaredDistance(a.Points[i], a.Points[j])
					if d < best {
						best, p, q = d, i, j
					}
				}
			}
			lines = append(lines, line(first, second, "dist_sq", best, "dist", rootText(best), "between", a.Points[p].ID, a.Points[q].ID))
		}
	}
	return lines
}
func (a *Analysis) contingencyLines() []string {
	knee, xi := a.Knee, a.XiSetting
	table := make([][]int, len(knee.Members)+1)
	for i := range table {
		table[i] = make([]int, len(xi.Members)+1)
	}
	for i, r := range knee.Labels {
		table[r+1][xi.Labels[i]+1]++
	}
	columns := []int{}
	for c := -1; c < len(xi.Members); c++ {
		columns = append(columns, c)
	}
	lines := []string{line("contingency", knee.Name, "xi"), "columns " + joined(columns)}
	for r, row := range table {
		lines = append(lines, line(r-1, joined(row)))
	}
	for c := range xi.Members {
		best, shared := 0, -1
		for r := range knee.Members {
			if table[r+1][c+1] > shared {
				best, shared = r, table[r+1][c+1]
			}
		}
		union := len(knee.Members[best]) + len(xi.Members[c]) - shared
		lines = append(lines, line("match", c, best, "shared", shared, "jaccard", fractionText(int64(shared), int64(union))))
	}
	return lines
}
func (a *Analysis) clustersLines() []string {
	names := []string{}
	for _, s := range a.Settings {
		names = append(names, s.Name)
	}
	parts := [][]string{{line("points", len(a.Points), "min_pts", a.Params.MinPts), "settings " + strings.Join(names, " ")}}
	grid := []string{"grid"}
	for _, g := range a.Grids {
		grid = append(grid, g.Lines()...)
	}
	parts = append(parts, grid)
	for _, s := range a.Settings {
		parts = append(parts, a.settingLines(s))
	}
	parts = append(parts, a.hierarchyLines(), a.comparisonLines(), a.opticsSummary(), a.sweepLines(),
		a.xiLines(), a.outlierLines(), a.gapLines(), a.contingencyLines())
	ari := []string{"ari"}
	for i, first := range a.Settings {
		for _, second := range a.Settings[i+1:] {
			numerator, denominator := adjustedRand(first.Labels, second.Labels)
			ari = append(ari, line(first.Name, second.Name, ariText(numerator, denominator)))
		}
	}
	return joinParts(append(parts, ari))
}
func (a *Analysis) clusterMap(s *Setting, kinds bool) []string {
	p := a.Params
	cells := make([][][]int, p.MapHeight)
	for r := range cells {
		cells[r] = make([][]int, p.MapWidth)
	}
	for i, cell := range a.MapCells {
		cells[cell[1]][cell[0]] = append(cells[cell[1]][cell[0]], i)
	}
	rows := []string{}
	for _, row := range cells {
		text := ""
		for _, indices := range row {
			mark := " "
			if len(indices) > 0 {
				if kinds {
					mark = "."
					for _, i := range indices {
						if s.Core[i] {
							mark = "#"
							break
						}
						if s.Labels[i] >= 0 {
							mark = "+"
						}
					}
				} else {
					mark = "."
					labels := map[int]bool{}
					for _, i := range indices {
						if s.Labels[i] >= 0 {
							labels[s.Labels[i]] = true
						}
					}
					if len(labels) == 1 {
						for label := range labels {
							mark = labelChar(label)
						}
					} else if len(labels) > 1 {
						mark = "*"
					}
				}
			}
			text += mark
		}
		rows = append(rows, text)
	}
	return rows
}
func (a *Analysis) mapsLines() []string {
	p := a.Params
	lines := []string{}
	for _, s := range a.Settings {
		lines = append(lines, line("map", s.Name, "clusters", len(s.Members), "noise", s.Noise))
		lines = append(lines, framed(a.clusterMap(s, false), p.MapWidth)...)
		legend := []string{}
		for label, members := range s.Members {
			legend = append(legend, fmt.Sprintf("%s=%d", labelChar(label), len(members)))
		}
		text := "-"
		if len(legend) > 0 {
			text = strings.Join(legend, " ")
		}
		lines = append(lines, "legend "+text, "")
	}
	lines = append(lines, line("kinds", a.Knee.Name))
	lines = append(lines, framed(a.clusterMap(a.Knee, true), p.MapWidth)...)
	lines = append(lines, "")
	heights := []int{}
	kneeColumn := 0
	n := len(a.Points)
	for c := 0; c < p.KdistWidth; c++ {
		first, last := c*n/p.KdistWidth, (c+1)*n/p.KdistWidth
		heights = append(heights, int(integerRoot(int64(p.KdistHeight*p.KdistHeight)*a.Curve.Values[first]/a.Curve.Values[0])))
		if first <= a.Curve.Knee && a.Curve.Knee < last {
			kneeColumn = c
		}
	}
	rows := []string{}
	for r := 0; r < p.KdistHeight; r++ {
		text := ""
		for c, height := range heights {
			if p.KdistHeight-r <= height {
				text += "#"
			} else if c == kneeColumn {
				text += ":"
			} else {
				text += " "
			}
		}
		rows = append(rows, text)
	}
	lines = append(lines, line("kdist_plot", "k", p.MinPts-1, "max", rootText(a.Curve.Values[0]), "knee_column", kneeColumn+1))
	lines = append(lines, framed(rows, p.KdistWidth)...)
	lines = append(lines, "")
	top := int64(0)
	for _, v := range a.Positions {
		if v != INF {
			top = max(top, v)
		}
	}
	settings := []*Setting{}
	names := []string{}
	for _, s := range a.Settings {
		if s.Kind == "extract" || s.Kind == "xi" {
			settings = append(settings, s)
			names = append(names, s.Name)
		}
	}
	lines = append(lines, line("reachability", "width", p.PlotWidth, "max_reach", rootText(top), "columns", strings.Join(names, " ")))
	for pos, i := range a.Order {
		reach := a.Reach[i]
		bar := strings.Repeat("-", p.PlotWidth)
		if reach != INF {
			bar = strings.Repeat("#", int(integerRoot(int64(p.PlotWidth*p.PlotWidth)*reach/top)))
		}
		labels := ""
		for _, s := range settings {
			labels += labelChar(s.Labels[i])
		}
		lines = append(lines, fmt.Sprintf("%4d %5d %7s %s |%s", pos+1, a.Points[i].ID, optionalRoot(reach), labels, bar))
	}
	return lines
}
func main() {
	a := newAnalysis(readPoints(), readParams())
	writeLines("labels.csv", a.labelsLines())
	writeLines("optics_order.csv", a.opticsLines())
	writeLines("kdist.txt", a.kdistLines())
	writeLines("clusters.txt", a.clustersLines())
	writeLines("maps.txt", a.mapsLines())
}
