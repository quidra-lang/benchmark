package main

import (
	"fmt"
	"sort"
	"strconv"
	"strings"
)

const symbols = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
const csvHeader = "image,label,class,flags,area,x0,y0,x1,y1,cx,cy,mean,variance,min,max,contrast,border,perimeter,chain,straight,diagonal,turns,compactness,runs,holes,hole_area,euler,parent,depth,var_x,var_y,cov_xy,hu1,orientation,anisotropy,extent,mirror_lr,mirror_tb,hull_area,solidity,feret2,width2,elongation,bays,bay_area,skeleton,endpoints,branches,neighbor,distance2,codes"

var orientations = []string{"none", "horizontal", "vertical", "falling", "rising"}
var four = []Point{{1, 0}, {0, -1}, {-1, 0}, {0, 1}}
var eight = []Point{{1, 0}, {1, -1}, {0, -1}, {-1, -1}, {-1, 0}, {-1, 1}, {0, 1}, {1, 1}}

type Setting struct {
	Connectivity        int
	Threshold, Polarity string
	Operations          []string
}

func (setting Setting) Method() string {
	if setting.Threshold == "otsu" || setting.Threshold == "isodata" {
		return setting.Threshold
	}
	return "fixed"
}

type Parameters struct {
	OtsuTop, SweepStep, BayMin int
	Isotropy                   Rational
	Elements                   map[string][]Point
	Settings                   map[string]Setting
}

func parseRational(text string) Rational {
	first, second, fraction := strings.Cut(text, "/")
	denominator := 1
	if fraction {
		denominator = parseInt(second)
	}
	return ratio(int64(parseInt(first)), int64(denominator))
}

func readParameters(path string) Parameters {
	parameters := Parameters{Isotropy: integer(0), Elements: make(map[string][]Point), Settings: make(map[string]Setting)}
	for line := range strings.SplitSeq(readText(path), "\n") {
		if line == "" {
			continue
		}
		words := strings.Split(line, " ")
		switch words[0] {
		case "otsu_top":
			parameters.OtsuTop = parseInt(words[1])
		case "sweep":
			parameters.SweepStep = parseInt(words[1])
		case "isotropy":
			parameters.Isotropy = parseRational(words[1])
		case "bay_min":
			parameters.BayMin = parseInt(words[1])
		case "element":
			ox, oy := parseInt(words[4]), parseInt(words[5])
			var offsets []Point
			for y, row := range words[6:] {
				for x := range row {
					if row[x] == '#' {
						offsets = append(offsets, Point{x - ox, y - oy})
					}
				}
			}
			parameters.Elements[words[1]] = offsets
		case "image":
			parameters.Settings[words[1]] = Setting{parseInt(words[2]), words[3], words[4], words[5:]}
		}
	}
	return parameters
}

type Condition struct {
	Feature, Comparison, Text string
	Value                     Rational
}

func newCondition(words []string) Condition {
	value := integer(0)
	if words[0] != "orientation" {
		value = parseRational(words[2])
	}
	return Condition{words[0], words[1], words[2], value}
}

func (condition Condition) Holds(region *Region) bool {
	order := 0
	if condition.Feature == "orientation" {
		order = strings.Compare(region.Orientation, condition.Text)
	} else {
		order = region.Features[condition.Feature].Compare(condition.Value)
	}
	switch condition.Comparison {
	case "<":
		return order < 0
	case "<=":
		return order <= 0
	case ">":
		return order > 0
	case ">=":
		return order >= 0
	case "=":
		return order == 0
	case "!=":
		return order != 0
	}
	panic("invalid comparison")
}

func (condition Condition) Words() string {
	return condition.Feature + " " + condition.Comparison + " " + condition.Text
}

type Rule struct {
	Name       string
	Conditions []Condition
}

func (rule Rule) Matches(region *Region) bool {
	for _, condition := range rule.Conditions {
		if !condition.Holds(region) {
			return false
		}
	}
	return true
}

type Rules struct {
	Filters        []Condition
	Classes, Flags []Rule
}

func (rules Rules) ClassNames() []string {
	var names []string
	seen := make(map[string]bool)
	for _, rule := range rules.Classes {
		if !seen[rule.Name] {
			names = append(names, rule.Name)
			seen[rule.Name] = true
		}
	}
	return append(names, "other")
}

func readRules(path string) Rules {
	var rules Rules
	for line := range strings.SplitSeq(readText(path), "\n") {
		if line == "" {
			continue
		}
		words := strings.Split(line, " ")
		if words[0] == "filter" {
			rules.Filters = append(rules.Filters, newCondition(words[1:]))
			continue
		}
		rule := Rule{Name: words[1]}
		for start := 2; start < len(words); start += 3 {
			rule.Conditions = append(rule.Conditions, newCondition(words[start:start+3]))
		}
		if words[0] == "class" {
			rules.Classes = append(rules.Classes, rule)
		} else {
			rules.Flags = append(rules.Flags, rule)
		}
	}
	return rules
}

type Hole struct {
	Number int
	Pixels []Point
	Owner  int
}
type Region struct {
	Number        int
	Pixels        []Point
	Features      map[string]Rational
	Orientation   string
	Codes         []int
	Skeleton      map[Point]bool
	HullDoubled   int64
	Parent, Depth int
	Children      []int
	Kept          bool
	DroppedBy     int
	ClassName     string
	Flags         []string
	Neighbor      int
	Distance      int64
}

func newRegion(number int, pixels []Point) *Region {
	return &Region{Number: number, Pixels: pixels, Features: make(map[string]Rational), Orientation: "none", DroppedBy: -1, ClassName: "other"}
}

func (region *Region) Int(name string) int64 {
	value := region.Features[name]
	return value.P / value.Q
}
func (region *Region) SetInt(name string, value int) { region.Features[name] = integer(int64(value)) }
func directions(connectivity int) []Point {
	if connectivity == 4 {
		return four
	}
	return eight
}

func countForeground(mask Mask) int {
	count := 0
	for _, row := range mask {
		for _, value := range row {
			if value {
				count++
			}
		}
	}
	return count
}

func groupPixels(labels [][]int, count int) [][]Point {
	groups := make([][]Point, count+1)
	for y, row := range labels {
		for x, label := range row {
			groups[label] = append(groups[label], Point{x, y})
		}
	}
	return groups
}

func enclosedComponents(mask Mask, connectivity int) [][]Point {
	background := newMask(len(mask[0]), len(mask))
	for y, row := range mask {
		for x, value := range row {
			background[y][x] = !value
		}
	}
	components := labelComponents(background, connectivity)
	var enclosed [][]Point
	for _, pixels := range groupPixels(components.Labels, components.Count)[1:] {
		onEdge := false
		for _, point := range pixels {
			if point.X == 0 || point.Y == 0 || point.X == len(mask[0])-1 || point.Y == len(mask)-1 {
				onEdge = true
				break
			}
		}
		if !onEdge {
			enclosed = append(enclosed, pixels)
		}
	}
	return enclosed
}

func fillHoles(mask Mask, connectivity int) Mask {
	result := make(Mask, len(mask))
	for y, row := range mask {
		result[y] = append([]bool(nil), row...)
	}
	for _, pixels := range enclosedComponents(mask, connectivity) {
		for _, point := range pixels {
			result[point.Y][point.X] = true
		}
	}
	return result
}

func cross(a, b, p Point) int64 { return int64(b.X-a.X)*int64(p.Y-a.Y) - int64(b.Y-a.Y)*int64(p.X-a.X) }
func squaredDistance(a, b Point) int64 {
	dx, dy := int64(a.X-b.X), int64(a.Y-b.Y)
	return dx*dx + dy*dy
}

func halfHull(points []Point) []Point {
	var chain []Point
	for _, point := range points {
		for len(chain) >= 2 && cross(chain[len(chain)-2], chain[len(chain)-1], point) <= 0 {
			chain = chain[:len(chain)-1]
		}
		chain = append(chain, point)
	}
	return chain
}

func convexHull(pixels []Point) []Point {
	seen := make(map[Point]bool)
	for _, point := range pixels {
		for dy := 0; dy <= 1; dy++ {
			for dx := 0; dx <= 1; dx++ {
				seen[Point{point.X + dx, point.Y + dy}] = true
			}
		}
	}
	ordered := make([]Point, 0, len(seen))
	for point := range seen {
		ordered = append(ordered, point)
	}
	sort.Slice(ordered, func(i, j int) bool {
		if ordered[i].X == ordered[j].X {
			return ordered[i].Y < ordered[j].Y
		}
		return ordered[i].X < ordered[j].X
	})
	lower := halfHull(ordered)
	reversed := make([]Point, len(ordered))
	for i, point := range ordered {
		reversed[len(ordered)-1-i] = point
	}
	upper := halfHull(reversed)
	return append(lower[:len(lower)-1], upper[:len(upper)-1]...)
}

func containsCenter(hull []Point, x, y int) bool {
	center := Point{2*x + 1, 2*y + 1}
	for i, a := range hull {
		b := hull[(i+1)%len(hull)]
		if cross(Point{2 * a.X, 2 * a.Y}, Point{2 * b.X, 2 * b.Y}, center) < 0 {
			return false
		}
	}
	return true
}

func boxBounds(pixels []Point) (int, int, int, int) {
	x0, y0, x1, y1 := pixels[0].X, pixels[0].Y, pixels[0].X, pixels[0].Y
	for _, point := range pixels {
		x0 = min(x0, point.X)
		y0 = min(y0, point.Y)
		x1 = max(x1, point.X)
		y1 = max(y1, point.Y)
	}
	return x0, y0, x1, y1
}

func boxDistance(first, second *Region) int64 {
	dx := first.Int("x0") + first.Int("x1") - second.Int("x0") - second.Int("x1")
	dy := first.Int("y0") + first.Int("y1") - second.Int("y0") - second.Int("y1")
	return dx*dx + dy*dy
}

func meanText(total int64, count int) string {
	if count == 0 {
		return "-"
	}
	return decimal(ratio(total, int64(count)), 2)
}

func orientationLine(regions []*Region) string {
	parts := []string{"orientations"}
	for _, name := range orientations {
		count := 0
		for _, region := range regions {
			if region.Orientation == name {
				count++
			}
		}
		parts = append(parts, name, strconv.Itoa(count))
	}
	return strings.Join(parts, " ")
}

type SweepResult struct{ Cutoff, Foreground, Regions int }
type ImageAnalysis struct {
	Image                                    Image
	Setting                                  Setting
	Histogram                                Histogram
	Otsu                                     OtsuResult
	IsodataCutoff, IsodataIterations, Cutoff int
	Initial, Final                           Mask
	MorphCounts                              []int
	Sweep                                    []SweepResult
	Labels                                   [][]int
	Provisional                              int
	Regions                                  []*Region
	FourComponents, EightComponents, BitQuad int
	Holes                                    []Hole
	HoleOf                                   [][]int
}

func newImageAnalysis(image Image, setting Setting, parameters Parameters) *ImageAnalysis {
	h := newHistogram(image)
	otsuResult := otsu(h)
	isoCutoff, isoIterations := isodata(h)
	cutoff := isoCutoff
	switch setting.Threshold {
	case "otsu":
		cutoff = otsuResult.Cutoff
	case "isodata":
	default:
		cutoff = parseInt(setting.Threshold)
	}
	analysis := &ImageAnalysis{Image: image, Setting: setting, Histogram: h, Otsu: otsuResult, IsodataCutoff: isoCutoff, IsodataIterations: isoIterations, Cutoff: cutoff}
	analysis.Initial = analysis.binarize(cutoff)
	analysis.Final = analysis.Initial
	for _, operation := range setting.Operations {
		if operation == "fill" {
			analysis.Final = fillHoles(analysis.Final, 12-setting.Connectivity)
		} else {
			kind, name, _ := strings.Cut(operation, ":")
			offsets := parameters.Elements[name]
			switch kind {
			case "erode":
				analysis.Final = erode(analysis.Final, offsets)
			case "dilate":
				analysis.Final = dilate(analysis.Final, offsets)
			case "open":
				analysis.Final = opening(analysis.Final, offsets)
			case "close":
				analysis.Final = closing(analysis.Final, offsets)
			}
		}
		analysis.MorphCounts = append(analysis.MorphCounts, countForeground(analysis.Final))
	}
	for t := parameters.SweepStep; t < image.Maxval; t += parameters.SweepStep {
		mask := analysis.binarize(t)
		analysis.Sweep = append(analysis.Sweep, SweepResult{t, countForeground(mask), labelComponents(mask, setting.Connectivity).Count})
	}
	result := labelComponents(analysis.Final, setting.Connectivity)
	analysis.Labels, analysis.Provisional = result.Labels, result.Provisional
	for i, pixels := range groupPixels(result.Labels, result.Count)[1:] {
		analysis.Regions = append(analysis.Regions, newRegion(i+1, pixels))
	}
	analysis.FourComponents = labelComponents(analysis.Final, 4).Count
	analysis.EightComponents = labelComponents(analysis.Final, 8).Count
	analysis.BitQuad = bitQuadEuler(analysis.Final, setting.Connectivity)
	analysis.HoleOf = make([][]int, image.Height)
	for y := range analysis.HoleOf {
		analysis.HoleOf[y] = make([]int, image.Width)
	}
	for _, pixels := range enclosedComponents(analysis.Final, 12-setting.Connectivity) {
		first := pixels[0]
		number := len(analysis.Holes) + 1
		owner := analysis.Labels[first.Y-1][first.X]
		for _, point := range pixels {
			analysis.HoleOf[point.Y][point.X] = number
		}
		analysis.Holes = append(analysis.Holes, Hole{number, pixels, owner})
	}
	for _, region := range analysis.Regions {
		first := region.Pixels[0]
		if first.Y >= 1 && analysis.HoleOf[first.Y-1][first.X] > 0 {
			owner := analysis.Holes[analysis.HoleOf[first.Y-1][first.X]-1].Owner
			region.Parent = owner
			region.Depth = analysis.Regions[owner-1].Depth + 1
			analysis.Regions[owner-1].Children = append(analysis.Regions[owner-1].Children, region.Number)
		}
		analysis.measure(region, parameters)
	}
	return analysis
}

func (a *ImageAnalysis) binarize(cutoff int) Mask {
	mask := newMask(a.Image.Width, a.Image.Height)
	for y, row := range a.Image.Pixels {
		for x, value := range row {
			mask[y][x] = value > int64(cutoff)
			if a.Setting.Polarity == "dark" {
				mask[y][x] = value <= int64(cutoff)
			}
		}
	}
	return mask
}

func (a *ImageAnalysis) labelAt(x, y int) int {
	if x < 0 || x >= a.Image.Width || y < 0 || y >= a.Image.Height {
		return -1
	}
	return a.Labels[y][x]
}

func (a *ImageAnalysis) chainCode(region *Region) []int {
	steps := directions(a.Setting.Connectivity)
	visited := []Point{region.Pixels[0]}
	var codes []int
	heading := len(steps) - 1
	for {
		point := visited[len(visited)-1]
		start := (heading + 3) % 4
		if len(steps) == 8 {
			if heading%2 == 0 {
				start = (heading + 7) % 8
			} else {
				start = (heading + 6) % 8
			}
		}
		chosen := -1
		for offset := range len(steps) {
			direction := (start + offset) % len(steps)
			step := steps[direction]
			if a.labelAt(point.X+step.X, point.Y+step.Y) == region.Number {
				chosen = direction
				break
			}
		}
		if chosen < 0 {
			return nil
		}
		step := steps[chosen]
		visited = append(visited, Point{point.X + step.X, point.Y + step.Y})
		codes = append(codes, chosen)
		heading = chosen
		moves := len(codes)
		if moves >= 2 && visited[moves] == visited[1] && visited[moves-1] == visited[0] {
			return codes[:moves-1]
		}
	}
}

func (a *ImageAnalysis) measure(region *Region, parameters Parameters) {
	f := region.Features
	area := int64(len(region.Pixels))
	x0, y0, x1, y1 := boxBounds(region.Pixels)
	for name, value := range map[string]int{"area": int(area), "x0": x0, "y0": y0, "x1": x1, "y1": y1, "width": x1 - x0 + 1, "height": y1 - y0 + 1} {
		region.SetInt(name, value)
	}
	border := 0
	if x0 == 0 || y0 == 0 || x1 == a.Image.Width-1 || y1 == a.Image.Height-1 {
		border = 1
	}
	region.SetInt("border", border)
	var sumValues, sumSquares, sumX, sumY, sumXX, sumYY, sumXY int64
	minimum, maximum := int64(a.Image.Maxval), int64(0)
	surrounding := make(map[Point]bool)
	perimeter, runs, mirroredLR, mirroredTB := 0, 0, 0, 0
	for _, point := range region.Pixels {
		x, y := int64(point.X), int64(point.Y)
		value := a.Image.Pixels[point.Y][point.X]
		sumValues += value
		sumSquares += value * value
		sumX += x
		sumY += y
		sumXX += x * x
		sumYY += y * y
		sumXY += x * y
		minimum = min(minimum, value)
		maximum = max(maximum, value)
		for _, offset := range eight {
			neighbor := Point{point.X + offset.X, point.Y + offset.Y}
			if a.labelAt(neighbor.X, neighbor.Y) == 0 {
				surrounding[neighbor] = true
			}
		}
		for _, offset := range directions(12 - a.Setting.Connectivity) {
			if a.labelAt(point.X+offset.X, point.Y+offset.Y) != region.Number {
				perimeter++
				break
			}
		}
		if a.labelAt(point.X-1, point.Y) != region.Number {
			runs++
		}
		if a.labelAt(x0+x1-point.X, point.Y) == region.Number {
			mirroredLR++
		}
		if a.labelAt(point.X, y0+y1-point.Y) == region.Number {
			mirroredTB++
		}
	}
	f["mean"] = ratio(sumValues, area)
	f["variance"] = ratio(area*sumSquares-sumValues*sumValues, area*area)
	f["min"], f["max"] = integer(minimum), integer(maximum)
	count := int64(len(surrounding))
	sumSurrounding := int64(0)
	for point := range surrounding {
		sumSurrounding += a.Image.Pixels[point.Y][point.X]
	}
	f["contrast"] = integer(0)
	if count > 0 {
		f["contrast"] = ratio(sumValues*count-sumSurrounding*area, area*count)
	}
	region.SetInt("perimeter", perimeter)
	region.SetInt("runs", runs)
	region.Codes = a.chainCode(region)
	straight := 0
	for _, code := range region.Codes {
		if a.Setting.Connectivity == 4 || code%2 == 0 {
			straight++
		}
	}
	diagonal := len(region.Codes) - straight
	turns := 0
	for i, code := range region.Codes {
		if code != region.Codes[(i+len(region.Codes)-1)%len(region.Codes)] {
			turns++
		}
	}
	region.SetInt("chain", len(region.Codes))
	region.SetInt("straight", straight)
	region.SetInt("diagonal", diagonal)
	region.SetInt("turns", turns)
	length := int64(5*straight + 7*diagonal)
	f["compactness"] = ratio(length*length, 25*area)
	owned, holeArea := 0, 0
	for _, hole := range a.Holes {
		if hole.Owner == region.Number {
			owned++
			holeArea += len(hole.Pixels)
		}
	}
	region.SetInt("holes", owned)
	region.SetInt("hole_area", holeArea)
	region.SetInt("euler", 1-owned)
	region.SetInt("depth", region.Depth)
	m20, m02, m11 := area*sumXX-sumX*sumX, area*sumYY-sumY*sumY, area*sumXY-sumX*sumY
	f["cx"], f["cy"] = ratio(sumX, area), ratio(sumY, area)
	f["var_x"], f["var_y"], f["cov_xy"] = ratio(m20, area*area), ratio(m02, area*area), ratio(m11, area*area)
	f["hu1"] = ratio(m20+m02, area*area*area)
	anisotropy := integer(0)
	if m20+m02 > 0 {
		anisotropy = ratio(abs64(m20-m02)+2*abs64(m11), m20+m02)
	}
	f["anisotropy"] = anisotropy
	u, v := m20-m02, 2*m11
	if anisotropy.Compare(parameters.Isotropy) <= 0 {
		region.Orientation = "none"
	} else if abs64(v) >= abs64(u) {
		if v > 0 {
			region.Orientation = "falling"
		} else {
			region.Orientation = "rising"
		}
	} else if u > 0 {
		region.Orientation = "horizontal"
	} else {
		region.Orientation = "vertical"
	}
	f["extent"] = ratio(area, int64((x1-x0+1)*(y1-y0+1)))
	f["mirror_lr"], f["mirror_tb"] = ratio(int64(mirroredLR), area), ratio(int64(mirroredTB), area)
	hull := convexHull(region.Pixels)
	var doubled, feret int64
	width := integer(0)
	for i, p := range hull {
		q := hull[(i+1)%len(hull)]
		doubled += int64(p.X)*int64(q.Y) - int64(q.X)*int64(p.Y)
		reach := int64(0)
		for _, vertex := range hull {
			reach = max(reach, abs64(cross(p, q, vertex)))
			feret = max(feret, squaredDistance(p, vertex))
		}
		candidate := ratio(reach*reach, squaredDistance(p, q))
		if i == 0 || candidate.Compare(width) < 0 {
			width = candidate
		}
	}
	region.HullDoubled = abs64(doubled)
	f["solidity"] = ratio(2*area, region.HullDoubled)
	f["feret2"] = integer(feret)
	f["width2"] = width
	f["elongation"] = ratio(feret*width.Q, width.P)
	bayMask := newMask(x1-x0+1, y1-y0+1)
	for y := y0; y <= y1; y++ {
		for x := x0; x <= x1; x++ {
			bayMask[y-y0][x-x0] = a.Labels[y][x] == 0 && a.HoleOf[y][x] == 0 && containsCenter(hull, x, y)
		}
	}
	bays := labelComponents(bayMask, 12-a.Setting.Connectivity)
	qualified, bayArea := 0, 0
	for _, pixels := range groupPixels(bays.Labels, bays.Count)[1:] {
		bayArea += len(pixels)
		if len(pixels) >= parameters.BayMin {
			qualified++
		}
	}
	region.SetInt("bays", qualified)
	region.SetInt("bay_area", bayArea)
	region.Skeleton = thin(region.Pixels)
	endpoints, branches := 0, 0
	for point := range region.Skeleton {
		crossing := crossingNumber(region.Skeleton, point)
		if crossing == 1 {
			endpoints++
		}
		if crossing >= 3 {
			branches++
		}
	}
	region.SetInt("skeleton", len(region.Skeleton))
	region.SetInt("endpoints", endpoints)
	region.SetInt("branches", branches)
}

func (a *ImageAnalysis) applyRules(rules Rules) {
	for _, region := range a.Regions {
		for i, condition := range rules.Filters {
			if !condition.Holds(region) {
				region.DroppedBy = i
				break
			}
		}
		if region.DroppedBy >= 0 {
			continue
		}
		region.Kept = true
		for _, rule := range rules.Classes {
			if rule.Matches(region) {
				region.ClassName = rule.Name
				break
			}
		}
		for _, rule := range rules.Flags {
			if rule.Matches(region) {
				region.Flags = append(region.Flags, rule.Name)
			}
		}
	}
	kept := a.keptRegions()
	for _, region := range kept {
		for _, other := range kept {
			if other.Number == region.Number {
				continue
			}
			distance := boxDistance(region, other)
			if region.Neighbor == 0 || distance < region.Distance {
				region.Neighbor = other.Number
				region.Distance = distance
			}
		}
	}
}

func (a *ImageAnalysis) keptRegions() []*Region {
	var kept []*Region
	for _, region := range a.Regions {
		if region.Kept {
			kept = append(kept, region)
		}
	}
	return kept
}

func (a *ImageAnalysis) treeText(number int) string {
	region := a.Regions[number-1]
	if len(region.Children) == 0 {
		return strconv.Itoa(number)
	}
	children := make([]string, len(region.Children))
	for i, child := range region.Children {
		children[i] = a.treeText(child)
	}
	return fmt.Sprintf("%d(%s)", number, strings.Join(children, " "))
}

func (a *ImageAnalysis) thresholdLines(top int) []string {
	image, h := a.Image, a.Histogram
	lines := []string{fmt.Sprintf("image %s size %d %d maxval %d", image.Name, image.Width, image.Height, image.Maxval),
		fmt.Sprintf("histogram pixels %d min %d max %d mean %s median %d mode %d levels %d", h.Pixels, h.Minimum, h.Maximum, meanText(h.Total, int(h.Pixels)), h.Median, h.Mode, h.Levels)}
	bins := []string{strconv.Itoa(h.BinWidth)}
	for _, frequency := range h.Bins {
		bins = append(bins, strconv.FormatInt(frequency, 10))
	}
	lines = append(lines, "bins "+strings.Join(bins, " "), fmt.Sprintf("otsu threshold %d upper %d candidates %d", a.Otsu.Cutoff, a.Otsu.Upper, len(a.Otsu.Candidates)))
	for i, candidate := range a.Otsu.Candidates[:min(top, len(a.Otsu.Candidates))] {
		gap := ratio(candidate.SumAbove*candidate.Below-candidate.SumBelow*candidate.Above, candidate.Below*candidate.Above)
		lines = append(lines, fmt.Sprintf("rank %d t %d below %d above %d mean_below %s mean_above %s gap %s", i+1, candidate.Cutoff, candidate.Below, candidate.Above, meanText(candidate.SumBelow, int(candidate.Below)), meanText(candidate.SumAbove, int(candidate.Above)), decimal(gap, 2)))
	}
	lines = append(lines, fmt.Sprintf("isodata threshold %d iterations %d", a.IsodataCutoff, a.IsodataIterations), fmt.Sprintf("threshold %d %s %s foreground %d", a.Cutoff, a.Setting.Method(), a.Setting.Polarity, countForeground(a.Initial)))
	for i, operation := range a.Setting.Operations {
		lines = append(lines, fmt.Sprintf("morph %s foreground %d", operation, a.MorphCounts[i]))
	}
	for _, result := range a.Sweep {
		lines = append(lines, fmt.Sprintf("sweep %d foreground %d regions %d", result.Cutoff, result.Foreground, result.Regions))
	}
	return lines
}

func (a *ImageAnalysis) regionSymbol(x, y int, skeletonOnly bool) byte {
	label := a.Labels[y][x]
	if label == 0 {
		if a.HoleOf[y][x] > 0 {
			return ':'
		}
		return '.'
	}
	region := a.Regions[label-1]
	if skeletonOnly && !region.Skeleton[Point{x, y}] {
		return '+'
	}
	if region.Kept {
		return symbols[label%len(symbols)]
	}
	return '#'
}

func (a *ImageAnalysis) mapLines() []string {
	size := fmt.Sprintf("%s %d %d", a.Image.Name, a.Image.Width, a.Image.Height)
	lines := []string{"morphology " + size}
	for y, row := range a.Initial {
		text := make([]byte, len(row))
		for x, before := range row {
			after := a.Final[y][x]
			switch {
			case before && after:
				text[x] = '#'
			case after:
				text[x] = '+'
			case before:
				text[x] = '-'
			default:
				text[x] = '.'
			}
		}
		lines = append(lines, string(text))
	}
	for _, heading := range []string{"labels", "skeleton"} {
		lines = append(lines, heading+" "+size)
		for y := range a.Image.Height {
			text := make([]byte, a.Image.Width)
			for x := range text {
				text[x] = a.regionSymbol(x, y, heading == "skeleton")
			}
			lines = append(lines, string(text))
		}
	}
	return lines
}

func (a *ImageAnalysis) csvRow(region *Region) string {
	flags := strings.Join(region.Flags, "+")
	if flags == "" {
		flags = "-"
	}
	fields := []string{a.Image.Name, strconv.Itoa(region.Number), region.ClassName, flags}
	appendInt := func(name string) { fields = append(fields, strconv.FormatInt(region.Int(name), 10)) }
	appendDecimal := func(name string, digits int) { fields = append(fields, decimal(region.Features[name], digits)) }
	for _, name := range []string{"area", "x0", "y0", "x1", "y1"} {
		appendInt(name)
	}
	for _, name := range []string{"cx", "cy"} {
		appendDecimal(name, 3)
	}
	for _, name := range []string{"mean", "variance"} {
		appendDecimal(name, 2)
	}
	appendInt("min")
	appendInt("max")
	appendDecimal("contrast", 2)
	for _, name := range []string{"border", "perimeter", "chain", "straight", "diagonal", "turns"} {
		appendInt(name)
	}
	appendDecimal("compactness", 3)
	for _, name := range []string{"runs", "holes", "hole_area", "euler"} {
		appendInt(name)
	}
	parent := "-"
	if region.Parent > 0 {
		parent = strconv.Itoa(region.Parent)
	}
	fields = append(fields, parent, strconv.Itoa(region.Depth))
	for _, name := range []string{"var_x", "var_y", "cov_xy"} {
		appendDecimal(name, 3)
	}
	appendDecimal("hu1", 4)
	fields = append(fields, region.Orientation)
	for _, name := range []string{"anisotropy", "extent", "mirror_lr", "mirror_tb"} {
		appendDecimal(name, 3)
	}
	fields = append(fields, hullAreaText(region.HullDoubled))
	appendDecimal("solidity", 3)
	appendInt("feret2")
	appendDecimal("width2", 3)
	appendDecimal("elongation", 3)
	for _, name := range []string{"bays", "bay_area", "skeleton", "endpoints", "branches"} {
		appendInt(name)
	}
	neighbor, distance := "-", "-"
	if region.Neighbor > 0 {
		neighbor = strconv.Itoa(region.Neighbor)
		distance = decimal(ratio(region.Distance, 4), 2)
	}
	var codes strings.Builder
	for _, code := range region.Codes {
		codes.WriteByte(byte('0' + code))
	}
	codeText := codes.String()
	if codeText == "" {
		codeText = "-"
	}
	return strings.Join(append(fields, neighbor, distance, codeText), ",")
}

func (a *ImageAnalysis) intensityText(foreground bool) string {
	var sum int64
	count := 0
	for y, row := range a.Image.Pixels {
		for x, value := range row {
			if a.Final[y][x] == foreground {
				sum += value
				count++
			}
		}
	}
	return meanText(sum, count)
}

func (a *ImageAnalysis) areaLine() string {
	kept := a.keptRegions()
	if len(kept) == 0 {
		return "area total 0 mean - largest - smallest -"
	}
	largest, smallest := kept[0], kept[0]
	var total int64
	for _, region := range kept {
		area := region.Int("area")
		total += area
		if area > largest.Int("area") {
			largest = region
		}
		if area < smallest.Int("area") {
			smallest = region
		}
	}
	return fmt.Sprintf("area total %d mean %s largest %d %d smallest %d %d", total, meanText(total, len(kept)), largest.Number, largest.Int("area"), smallest.Number, smallest.Int("area"))
}

func (a *ImageAnalysis) summaryLines(rules Rules) []string {
	kept := a.keptRegions()
	holePixels, depthMax := 0, 0
	for _, hole := range a.Holes {
		holePixels += len(hole.Pixels)
	}
	lines := []string{fmt.Sprintf("image %s", a.Image.Name), fmt.Sprintf("threshold %d %s %s conn %d", a.Cutoff, a.Setting.Method(), a.Setting.Polarity, a.Setting.Connectivity),
		fmt.Sprintf("foreground %d %d", countForeground(a.Initial), countForeground(a.Final)), fmt.Sprintf("regions %d provisional %d kept %d dropped %d", len(a.Regions), a.Provisional, len(kept), len(a.Regions)-len(kept)),
		fmt.Sprintf("connectivity four %d eight %d", a.FourComponents, a.EightComponents), fmt.Sprintf("holes %d hole_pixels %d euler %d bitquad %d", len(a.Holes), holePixels, len(a.Regions)-len(a.Holes), a.BitQuad)}
	for _, hole := range a.Holes {
		x0, y0, x1, y1 := boxBounds(hole.Pixels)
		lines = append(lines, fmt.Sprintf("hole %d owner %d area %d box %d %d %d %d", hole.Number, hole.Owner, len(hole.Pixels), x0, y0, x1, y1))
	}
	trees := []string{"tree"}
	for _, region := range a.Regions {
		depthMax = max(depthMax, region.Depth)
		if region.Parent == 0 {
			trees = append(trees, a.treeText(region.Number))
		}
	}
	lines = append(lines, fmt.Sprintf("depth_max %d", depthMax), strings.Join(trees, " "), fmt.Sprintf("intensity foreground %s background %s", a.intensityText(true), a.intensityText(false)), a.areaLine())
	classes := []string{"classes"}
	for _, name := range rules.ClassNames() {
		count := 0
		for _, region := range kept {
			if region.ClassName == name {
				count++
			}
		}
		classes = append(classes, name, strconv.Itoa(count))
	}
	flags := []string{"flags"}
	for _, rule := range rules.Flags {
		count := 0
		for _, region := range kept {
			for _, flag := range region.Flags {
				if flag == rule.Name {
					count++
					break
				}
			}
		}
		flags = append(flags, rule.Name, strconv.Itoa(count))
	}
	return append(lines, strings.Join(classes, " "), orientationLine(kept), strings.Join(flags, " "))
}

func overallLines(analyses []*ImageAnalysis, rules Rules) []string {
	var regions, kept []*Region
	holes := 0
	var largest *Region
	largestName := ""
	for _, analysis := range analyses {
		regions = append(regions, analysis.Regions...)
		kept = append(kept, analysis.keptRegions()...)
		holes += len(analysis.Holes)
		for _, region := range analysis.keptRegions() {
			if largest == nil || region.Int("area") > largest.Int("area") {
				largest, largestName = region, analysis.Image.Name
			}
		}
	}
	lines := []string{"overall", fmt.Sprintf("images %d", len(analyses)), fmt.Sprintf("regions %d kept %d dropped %d", len(regions), len(kept), len(regions)-len(kept)), fmt.Sprintf("holes %d euler %d", holes, len(regions)-holes)}
	for i, condition := range rules.Filters {
		count := 0
		for _, region := range regions {
			if region.DroppedBy == i {
				count++
			}
		}
		lines = append(lines, fmt.Sprintf("filter %d %s dropped %d", i+1, condition.Words(), count))
	}
	for _, name := range rules.ClassNames() {
		count := 0
		var area int64
		for _, region := range kept {
			if region.ClassName == name {
				count++
				area += region.Int("area")
			}
		}
		lines = append(lines, fmt.Sprintf("class %s count %d area %d mean %s", name, count, area, meanText(area, count)))
	}
	for _, rule := range rules.Flags {
		count := 0
		for _, region := range kept {
			for _, flag := range region.Flags {
				if flag == rule.Name {
					count++
					break
				}
			}
		}
		lines = append(lines, fmt.Sprintf("flag %s count %d", rule.Name, count))
	}
	lines = append(lines, orientationLine(kept))
	if largest == nil {
		return append(lines, "largest -")
	}
	return append(lines, fmt.Sprintf("largest %s %d %d", largestName, largest.Number, largest.Int("area")))
}

func main() {
	parameters := readParameters("input/params.txt")
	rules := readRules("input/rules.txt")
	var analyses []*ImageAnalysis
	for _, image := range readImages("input/images.txt") {
		analysis := newImageAnalysis(image, parameters.Settings[image.Name], parameters)
		analysis.applyRules(rules)
		analyses = append(analyses, analysis)
	}
	var thresholds, maps, summary []string
	rows := []string{csvHeader}
	for _, analysis := range analyses {
		thresholds = append(thresholds, analysis.thresholdLines(parameters.OtsuTop)...)
		maps = append(maps, analysis.mapLines()...)
		for _, region := range analysis.keptRegions() {
			rows = append(rows, analysis.csvRow(region))
		}
		summary = append(summary, analysis.summaryLines(rules)...)
	}
	summary = append(summary, overallLines(analyses, rules)...)
	writeFiles("output", map[string][]string{"thresholds.txt": thresholds, "labels.txt": maps, "regions.csv": rows, "summary.txt": summary})
}
