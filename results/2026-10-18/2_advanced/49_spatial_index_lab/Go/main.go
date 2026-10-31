package main

import (
	"container/heap"
	"fmt"
	"slices"
	"sort"
	"strconv"
	"strings"
)

var pointStructures = []string{"kdtree", "quadtree", "rtree", "str", "grid"}
var rectangleStructures = []string{"rtree_rect", "str_rect"}
var rtreeStructures = []string{"rtree", "str", "rtree_rect", "str_rect"}
var searchCommands = []string{"RANGE", "RADIUS", "KNN", "WINDOWCOUNT", "CONTAINS", "NEAREST", "JOIN"}

func structuresFor(command string) []string {
	if command == "JOIN" {
		return []string{"rtree", "str"}
	}
	if command == "CONTAINS" || command == "NEAREST" {
		return rectangleStructures
	}
	return pointStructures
}

type NodeView struct {
	Region       Box
	Held         []Object
	Children     []*NodeView
	Count, Depth int
	Mark         string
	KD           *KDNode
	Quad         *QuadNode
	R            *RNode
}

func completeView(v *NodeView) *NodeView {
	v.Count = len(v.Held)
	for _, child := range v.Children {
		v.Count += child.Count
	}
	return v
}
func kdView(node *KDNode, region Box, mark string, depth int) *NodeView {
	v := &NodeView{Region: region, Held: []Object{node.Point}, Depth: depth, Mark: mark, KD: node}
	left, right := region, region
	if node.Axis == 0 {
		left[2] = node.Point.Box[0]
		right[0] = node.Point.Box[0]
	} else {
		left[3] = node.Point.Box[1]
		right[1] = node.Point.Box[1]
	}
	if node.Left != nil {
		v.Children = append(v.Children, kdView(node.Left, left, "L", depth+1))
	}
	if node.Right != nil {
		v.Children = append(v.Children, kdView(node.Right, right, "R", depth+1))
	}
	return completeView(v)
}
func quadView(node *QuadNode, mark string, depth int) *NodeView {
	v := &NodeView{Region: Box{node.X, node.Y, node.X + node.Size - 1, node.Y + node.Size - 1}, Held: node.Points, Depth: depth, Mark: mark, Quad: node}
	for i, child := range node.Children {
		v.Children = append(v.Children, quadView(child, childNames[i], depth+1))
	}
	return completeView(v)
}
func rtreeView(node *RNode, objects map[int]Object, depth int) *NodeView {
	v := &NodeView{Region: node.box(), Depth: depth, R: node}
	for _, e := range node.Entries {
		if node.Level == 0 {
			v.Held = append(v.Held, objects[e.ID])
		} else {
			v.Children = append(v.Children, rtreeView(e.Child, objects, depth+1))
		}
	}
	return completeView(v)
}
func gridView(grid *Grid) *NodeView {
	v := &NodeView{Region: Box{0, 0, grid.World - 1, grid.World - 1}}
	for _, cell := range grid.Cells {
		v.Children = append(v.Children, completeView(&NodeView{Region: cell.Box, Held: cell.Points, Depth: 1}))
	}
	return completeView(v)
}
func preorder(root *NodeView) []*NodeView {
	out := []*NodeView{}
	var walk func(*NodeView)
	walk = func(v *NodeView) {
		out = append(out, v)
		for _, child := range v.Children {
			walk(child)
		}
	}
	walk(root)
	return out
}
func minimumDistance(x, y int, b Box) int {
	dx, dy := 0, 0
	if x < b[0] {
		dx = b[0] - x
	} else if x > b[2] {
		dx = x - b[2]
	}
	if y < b[1] {
		dy = b[1] - y
	} else if y > b[3] {
		dy = y - b[3]
	}
	return dx*dx + dy*dy
}
func conditions(command string, values []int) (func(Box) bool, func(Object) bool) {
	if command == "RANGE" {
		box := Box{values[0], values[1], values[2], values[3]}
		return func(b Box) bool { return intersects(b, box) }, func(o Object) bool { return contains(box, o.Box) }
	}
	if command == "RADIUS" {
		x, y, r := values[0], values[1], values[2]
		return func(b Box) bool { return minimumDistance(x, y, b) <= r*r }, func(o Object) bool { return minimumDistance(x, y, o.Box) <= r*r }
	}
	q := Box{values[0], values[1], values[0], values[1]}
	return func(b Box) bool { return contains(b, q) }, func(o Object) bool { return contains(o.Box, q) }
}

type SearchResult struct {
	IDs                 []int
	Pairs               [][2]int
	Count, Nodes, Tests int
}

func conditionSearch(root *NodeView, regionCondition func(Box) bool, objectCondition func(Object) bool) SearchResult {
	out := SearchResult{}
	var visit func(*NodeView)
	visit = func(v *NodeView) {
		out.Nodes++
		out.Tests += len(v.Held)
		for _, o := range v.Held {
			if objectCondition(o) {
				out.IDs = append(out.IDs, o.ID)
			}
		}
		for _, child := range v.Children {
			if regionCondition(child.Region) {
				visit(child)
			}
		}
	}
	visit(root)
	sort.Ints(out.IDs)
	return out
}
func windowCount(root *NodeView, window Box) SearchResult {
	out := SearchResult{}
	var count func(*NodeView)
	count = func(v *NodeView) {
		out.Nodes++
		if contains(window, v.Region) {
			out.Count += v.Count
			return
		}
		out.Tests += len(v.Held)
		for _, o := range v.Held {
			if contains(window, o.Box) {
				out.Count++
			}
		}
		for _, child := range v.Children {
			if intersects(child.Region, window) {
				count(child)
			}
		}
	}
	count(root)
	return out
}

type QueueElement struct {
	Distance, Kind, Tie int
	Node                *NodeView
	Object              Object
}
type PriorityQueue []QueueElement

func (p PriorityQueue) Len() int { return len(p) }
func (p PriorityQueue) Less(i, j int) bool {
	a, b := p[i], p[j]
	if a.Distance != b.Distance {
		return a.Distance < b.Distance
	}
	if a.Kind != b.Kind {
		return a.Kind < b.Kind
	}
	return a.Tie < b.Tie
}
func (p PriorityQueue) Swap(i, j int) { p[i], p[j] = p[j], p[i] }
func (p *PriorityQueue) Push(v any)   { *p = append(*p, v.(QueueElement)) }
func (p *PriorityQueue) Pop() any     { old := *p; v := old[len(old)-1]; *p = old[:len(old)-1]; return v }
func bestFirst(root *NodeView, x, y, k int) SearchResult {
	pending := &PriorityQueue{}
	heap.Push(pending, QueueElement{Distance: minimumDistance(x, y, root.Region), Node: root})
	serial := 1
	out := SearchResult{}
	for pending.Len() > 0 {
		e := heap.Pop(pending).(QueueElement)
		if e.Kind == 1 {
			out.Pairs = append(out.Pairs, [2]int{e.Object.ID, e.Distance})
			if len(out.Pairs) == k {
				break
			}
			continue
		}
		v := e.Node
		out.Nodes++
		out.Tests += len(v.Held)
		for _, o := range v.Held {
			heap.Push(pending, QueueElement{Distance: minimumDistance(x, y, o.Box), Kind: 1, Tie: o.ID, Object: o})
		}
		for _, child := range v.Children {
			heap.Push(pending, QueueElement{Distance: minimumDistance(x, y, child.Region), Tie: serial, Node: child})
			serial++
		}
	}
	return out
}
func sortPairs(pairs [][2]int) {
	sort.Slice(pairs, func(i, j int) bool {
		return pairs[i][0] < pairs[j][0] || pairs[i][0] == pairs[j][0] && pairs[i][1] < pairs[j][1]
	})
}
func spatialJoin(pointRoot, rectRoot *NodeView) SearchResult {
	out := SearchResult{}
	var join func(*NodeView, *NodeView)
	join = func(a, b *NodeView) {
		out.Nodes++
		if len(a.Children) == 0 && len(b.Children) == 0 {
			out.Tests += len(a.Held) * len(b.Held)
			for _, point := range a.Held {
				for _, rect := range b.Held {
					if contains(rect.Box, point.Box) {
						out.Pairs = append(out.Pairs, [2]int{rect.ID, point.ID})
					}
				}
			}
			return
		}
		if len(a.Children) == 0 {
			for _, child := range b.Children {
				if intersects(a.Region, child.Region) {
					join(a, child)
				}
			}
		} else if len(b.Children) == 0 {
			for _, child := range a.Children {
				if intersects(child.Region, b.Region) {
					join(child, b)
				}
			}
		} else {
			for _, ac := range a.Children {
				for _, bc := range b.Children {
					if intersects(ac.Region, bc.Region) {
						join(ac, bc)
					}
				}
			}
		}
	}
	join(pointRoot, rectRoot)
	sortPairs(out.Pairs)
	return out
}
func bruteForce(command string, v []int, points, rects map[int]Object) SearchResult {
	out := SearchResult{}
	objects := points
	if command == "CONTAINS" || command == "NEAREST" {
		objects = rects
	}
	switch command {
	case "RANGE", "RADIUS", "CONTAINS":
		_, condition := conditions(command, v)
		for _, o := range objects {
			if condition(o) {
				out.IDs = append(out.IDs, o.ID)
			}
		}
		sort.Ints(out.IDs)
	case "WINDOWCOUNT":
		box := Box{v[0], v[1], v[2], v[3]}
		for _, o := range points {
			if contains(box, o.Box) {
				out.Count++
			}
		}
	case "KNN", "NEAREST":
		for _, o := range objects {
			out.Pairs = append(out.Pairs, [2]int{o.ID, minimumDistance(v[0], v[1], o.Box)})
		}
		sort.Slice(out.Pairs, func(i, j int) bool {
			a, b := out.Pairs[i], out.Pairs[j]
			return a[1] < b[1] || a[1] == b[1] && a[0] < b[0]
		})
		out.Pairs = out.Pairs[:v[2]]
	case "JOIN":
		for _, rect := range rects {
			for _, point := range points {
				if contains(rect.Box, point.Box) {
					out.Pairs = append(out.Pairs, [2]int{rect.ID, point.ID})
				}
			}
		}
		sortPairs(out.Pairs)
	}
	return out
}
func sameAnswer(a, b SearchResult) bool {
	return a.Count == b.Count && slices.Equal(a.IDs, b.IDs) && slices.Equal(a.Pairs, b.Pairs)
}
func locateKD(root *KDNode, point Object) string {
	path := ""
	for root.Point.ID != point.ID {
		if keyLess(point, root.Point, root.Axis) {
			path += "L"
			root = root.Left
		} else {
			path += "R"
			root = root.Right
		}
	}
	if path == "" {
		return "-"
	}
	return path
}
func locateQuad(root *QuadNode, point Object) string {
	path := []string{}
	for len(root.Children) > 0 {
		index := destination(root, point)
		path = append(path, childNames[index])
		root = root.Children[index]
	}
	if len(path) == 0 {
		return "-"
	}
	return strings.Join(path, "/")
}
func locateRTree(root *RNode, point Object) string {
	var find func(*RNode, []string) string
	find = func(node *RNode, path []string) string {
		for i, e := range node.Entries {
			next := append(append([]string{}, path...), strconv.Itoa(i+1))
			if node.Level == 0 {
				if e.ID == point.ID {
					return strings.Join(next, "/")
				}
			} else if contains(e.Box, point.Box) {
				if answer := find(e.Child, next); answer != "" {
					return answer
				}
			}
		}
		return ""
	}
	return find(root, nil)
}
func dumpTree(root *NodeView, name string) []string {
	lines := []string{}
	for _, v := range preorder(root) {
		prefix := strings.Repeat("  ", v.Depth+1)
		line := ""
		switch name {
		case "kdtree":
			o := v.Held[0]
			line = fmt.Sprintf("%s %c %d %d %d box %s", v.Mark, "xy"[v.KD.Axis], o.ID, o.Box[0], o.Box[1], boxWords(v.Region))
		case "quadtree":
			node := v.Quad
			line = fmt.Sprintf("%s %d %d %d", v.Mark, node.X, node.Y, node.Size)
			if len(v.Children) > 0 {
				line += fmt.Sprintf(" node count %d", v.Count)
			} else {
				values := []int{}
				for _, o := range v.Held {
					values = append(values, o.ID)
				}
				line += " leaf " + ids(values)
			}
		default:
			if v.R.Level == 0 {
				values := []int{}
				for _, o := range v.Held {
					values = append(values, o.ID)
				}
				line = "leaf " + boxWords(v.Region) + " ids " + ids(values)
			} else {
				line = fmt.Sprintf("node %d %s entries %d", v.R.Level, boxWords(v.Region), len(v.R.Entries))
			}
		}
		lines = append(lines, prefix+line)
	}
	return lines
}
func kdStatistics(root *NodeView) []string {
	depths := map[int][3]int{}
	height, nodes, leaves, one, depthSum := 0, 0, 0, 0, 0
	for _, v := range preorder(root) {
		row := depths[v.Depth]
		row[0]++
		nodes++
		if len(v.Children) == 0 {
			row[1]++
			leaves++
		} else if len(v.Children) == 1 {
			row[2]++
			one++
		}
		depths[v.Depth] = row
		depthSum += v.Depth
		height = max(height, v.Depth+1)
	}
	ideal, capacity := 0, 0
	for capacity < nodes {
		capacity = 2*capacity + 1
		ideal++
	}
	lines := []string{fmt.Sprintf("kdtree height %d ideal %d nodes %d leaves %d one_child %d depth_sum %d avg_depth %s",
		height, ideal, nodes, leaves, one, depthSum, fraction(depthSum, nodes))}
	for depth := 0; depth < height; depth++ {
		row := depths[depth]
		lines = append(lines, fmt.Sprintf("  depth %d nodes %d leaves %d one_child %d", depth, row[0], row[1], row[2]))
	}
	return lines
}
func quadStatistics(root *NodeView, capacity int) []string {
	depths := map[int][3]int{}
	height, internal, leaves, empty, maximum := 0, 0, 0, 0, 0
	for _, v := range preorder(root) {
		row := depths[v.Depth]
		if len(v.Children) > 0 {
			row[0]++
			internal++
		} else {
			count := len(v.Held)
			row[1]++
			row[2] += count
			leaves++
			if count == 0 {
				empty++
			}
			maximum = max(maximum, count)
		}
		depths[v.Depth] = row
		height = max(height, v.Depth+1)
	}
	lines := []string{fmt.Sprintf("quadtree height %d internal %d leaves %d empty %d max_leaf %d fill %s",
		height, internal, leaves, empty, maximum, fraction(root.Count, leaves*capacity))}
	for depth := 0; depth < height; depth++ {
		row := depths[depth]
		lines = append(lines, fmt.Sprintf("  depth %d internal %d leaves %d points %d", depth, row[0], row[1], row[2]))
	}
	return lines
}
func rtreeStatistics(name string, root *NodeView, maximum, minimum int) []string {
	levels := map[int][]*NodeView{}
	nodes, entries := 0, 0
	for _, v := range preorder(root) {
		level := v.R.Level
		levels[level] = append(levels[level], v)
		nodes++
		entries += len(v.R.Entries)
	}
	height := root.R.Level + 1
	lines := []string{fmt.Sprintf("%s height %d nodes %d leaves %d entries %d fill %s", name, height,
		nodes, len(levels[0]), entries, fraction(entries, nodes*maximum))}
	for level := height - 1; level >= 0; level-- {
		group := levels[level]
		count, smallest, largest, under, areaSum, overlapSum := 0, maximum+1, 0, 0, 0, 0
		for i, v := range group {
			size := len(v.R.Entries)
			count += size
			smallest = min(smallest, size)
			largest = max(largest, size)
			if size < minimum {
				under++
			}
			areaSum += area(v.Region)
			for _, other := range group[i+1:] {
				overlapSum += overlap(v.Region, other.Region)
			}
		}
		lines = append(lines, fmt.Sprintf("  level %d nodes %d entries %d min %d max %d under %d area %d overlap %d",
			level, len(group), count, smallest, largest, under, areaSum, overlapSum))
	}
	return lines
}
func gridStatistics(root *NodeView) []string {
	occupancy := map[int]int{}
	maximum := 0
	for _, cell := range root.Children {
		size := len(cell.Held)
		occupancy[size]++
		maximum = max(maximum, size)
	}
	fields := []string{}
	for size := 0; size <= maximum; size++ {
		if occupancy[size] > 0 {
			fields = append(fields, fmt.Sprintf("%d:%d", size, occupancy[size]))
		}
	}
	return []string{fmt.Sprintf("grid cells %d used %d max %d", len(root.Children), len(root.Children)-occupancy[0],
		maximum), "  occupancy " + strings.Join(fields, " ")}
}

type VisitTotal struct{ Queries, Nodes, Tests, Maximum int }

func visitsSummary(totals map[string]map[string]VisitTotal) []string {
	lines := []string{"visits"}
	for _, command := range searchCommands {
		rows, ok := totals[command]
		if !ok {
			continue
		}
		structures := structuresFor(command)
		for _, name := range structures {
			v := rows[name]
			lines = append(lines, fmt.Sprintf("%s %s queries %d nodes %d tests %d max_nodes %d mean_nodes %s",
				command, name, v.Queries, v.Nodes, v.Tests, v.Maximum, fraction(v.Nodes, v.Queries)))
		}
		ranking := append([]string{}, structures...)
		sort.SliceStable(ranking, func(i, j int) bool {
			a, b := rows[ranking[i]], rows[ranking[j]]
			return a.Nodes < b.Nodes || a.Nodes == b.Nodes && a.Tests < b.Tests
		})
		lines = append(lines, "rank "+command+" "+strings.Join(ranking, " "))
	}
	return lines
}

type Laboratory struct {
	Points, Rectangles                                map[int]Object
	Params                                            Params
	KD                                                *KDNode
	Quad                                              *QuadNode
	Grid                                              *Grid
	RTrees                                            map[string]*RTree
	Views                                             map[string]*NodeView
	Answers, Visits, JoinRows, Structures, Statistics []string
	Totals                                            map[string]map[string]VisitTotal
	Snapshot                                          int
}

func newLaboratory(points, rects []Object, p Params) *Laboratory {
	lab := &Laboratory{Points: map[int]Object{}, Rectangles: map[int]Object{}, Params: p, KD: buildKD(points,
		0), Quad: buildQuad(points, p.World, p.Bucket), Grid: newGrid(p.World, p.CellSize, points),
		RTrees: map[string]*RTree{}, Views: map[string]*NodeView{}, Visits: []string{"query,command,structure,nodes,tests"},
		JoinRows: []string{"query,rect,point"}, Totals: map[string]map[string]VisitTotal{}}
	for _, o := range points {
		lab.Points[o.ID] = o
	}
	for _, o := range rects {
		lab.Rectangles[o.ID] = o
	}
	for _, name := range rtreeStructures {
		objects := points
		if name == "rtree_rect" || name == "str_rect" {
			objects = rects
		}
		lab.RTrees[name] = buildRTree(objects, p.Maximum, p.Minimum, name == "str" || name == "str_rect")
	}
	lab.refresh()
	for _, name := range rectangleStructures {
		lab.Views[name] = rtreeView(lab.RTrees[name].Root, lab.Rectangles, 0)
	}
	lab.recordSnapshot(0)
	return lab
}
func (l *Laboratory) refresh() {
	l.Views["kdtree"] = kdView(l.KD, Box{0, 0, l.Params.World - 1, l.Params.World - 1}, "root", 0)
	l.Views["quadtree"] = quadView(l.Quad, "root", 0)
	for _, name := range []string{"rtree", "str"} {
		l.Views[name] = rtreeView(l.RTrees[name].Root, l.Points, 0)
	}
	l.Views["grid"] = gridView(l.Grid)
}
func (l *Laboratory) recordSnapshot(query int) {
	header := fmt.Sprintf("snapshot %d query %d points %d rects %d", l.Snapshot, query, len(l.Points), len(l.Rectangles))
	if len(l.Structures) > 0 {
		l.Structures = append(l.Structures, "")
		l.Statistics = append(l.Statistics, "")
	}
	l.Structures = append(l.Structures, header, "kdtree")
	l.Structures = append(l.Structures, dumpTree(l.Views["kdtree"], "kdtree")...)
	l.Structures = append(l.Structures, "quadtree")
	l.Structures = append(l.Structures, dumpTree(l.Views["quadtree"], "quadtree")...)
	l.Statistics = append(l.Statistics, header)
	l.Statistics = append(l.Statistics, kdStatistics(l.Views["kdtree"])...)
	l.Statistics = append(l.Statistics, quadStatistics(l.Views["quadtree"], l.Params.Bucket)...)
	for _, name := range rtreeStructures {
		l.Structures = append(l.Structures, name)
		l.Structures = append(l.Structures, dumpTree(l.Views[name], name)...)
		l.Statistics = append(l.Statistics, rtreeStatistics(name, l.Views[name], l.Params.Maximum, l.Params.Minimum)...)
	}
	l.Statistics = append(l.Statistics, gridStatistics(l.Views["grid"])...)
}
func (l *Laboratory) searchStructure(name, command string, v []int) SearchResult {
	root := l.Views[name]
	switch command {
	case "RANGE", "RADIUS", "CONTAINS":
		region, object := conditions(command, v)
		return conditionSearch(root, region, object)
	case "WINDOWCOUNT":
		return windowCount(root, Box{v[0], v[1], v[2], v[3]})
	case "JOIN":
		return spatialJoin(root, l.Views[name+"_rect"])
	default:
		return bestFirst(root, v[0], v[1], v[2])
	}
}
func (l *Laboratory) recordVisit(query int, command, name string, result SearchResult) {
	l.Visits = append(l.Visits, fmt.Sprintf("%d,%s,%s,%d,%d", query, command, name, result.Nodes, result.Tests))
	if l.Totals[command] == nil {
		l.Totals[command] = map[string]VisitTotal{}
	}
	v := l.Totals[command][name]
	v.Queries++
	v.Nodes += result.Nodes
	v.Tests += result.Tests
	v.Maximum = max(v.Maximum, result.Nodes)
	l.Totals[command][name] = v
}
func (l *Laboratory) processSearch(query int, command string, values []int) {
	expected := bruteForce(command, values, l.Points, l.Rectangles)
	mismatches := []string{}
	for _, name := range structuresFor(command) {
		actual := l.searchStructure(name, command, values)
		l.recordVisit(query, command, name, actual)
		if !sameAnswer(actual, expected) {
			mismatches = append(mismatches, name)
		}
	}
	check := "ok"
	if len(mismatches) > 0 {
		check = "mismatch " + strings.Join(mismatches, " ")
	}
	line := ""
	if command == "WINDOWCOUNT" {
		line = fmt.Sprintf("%d %s count %d check %s", query, command, expected.Count, check)
	} else if command == "JOIN" {
		line = fmt.Sprintf("%d JOIN count %d check %s", query, len(expected.Pairs), check)
		for _, pair := range expected.Pairs {
			l.JoinRows = append(l.JoinRows, fmt.Sprintf("%d,%d,%d", query, pair[0], pair[1]))
		}
	} else {
		sequence, count := ids(expected.IDs), len(expected.IDs)
		if command == "KNN" || command == "NEAREST" {
			sequence, count = distances(expected.Pairs), len(expected.Pairs)
		}
		line = fmt.Sprintf("%d %s count %d ids %s check %s", query, command, count, sequence, check)
	}
	l.Answers = append(l.Answers, line)
}
func (l *Laboratory) processLocate(query, id int) {
	point, ok := l.Points[id]
	if !ok {
		l.Answers = append(l.Answers, fmt.Sprintf("%d LOCATE %d missing", query, id))
		return
	}
	column, row := l.Grid.position(point)
	l.Answers = append(l.Answers, fmt.Sprintf("%d LOCATE %d kdtree %s quadtree %s rtree %s str %s grid %d %d",
		query, id, locateKD(l.KD, point), locateQuad(l.Quad, point), locateRTree(l.RTrees["rtree"].Root,
			point), locateRTree(l.RTrees["str"].Root, point), column, row))
}
func (l *Laboratory) processInsert(query int, point Object) {
	l.Points[point.ID] = point
	l.KD = insertKD(l.KD, point)
	insertQuad(l.Quad, point, l.Params.Bucket)
	for _, name := range []string{"rtree", "str"} {
		l.RTrees[name].insert(&Entry{Box: point.Box, ID: point.ID}, 0)
	}
	l.Grid.insert(point)
	l.refresh()
	l.Answers = append(l.Answers, fmt.Sprintf("%d INSERT %d inserted points %d", query, point.ID, len(l.Points)))
}
func (l *Laboratory) processDelete(query, id int) {
	status := "missing"
	if point, ok := l.Points[id]; ok {
		l.KD = deleteKD(l.KD, point)
		deleteQuad(l.Quad, point, l.Params.Bucket)
		for _, name := range []string{"rtree", "str"} {
			l.RTrees[name].delete(point)
		}
		l.Grid.delete(point)
		delete(l.Points, id)
		l.refresh()
		status = "deleted"
	}
	l.Answers = append(l.Answers, fmt.Sprintf("%d DELETE %d %s points %d", query, id, status, len(l.Points)))
}
func (l *Laboratory) process(commands []Command) {
	for i, c := range commands {
		q := i + 1
		switch c.Name {
		case "LOCATE":
			l.processLocate(q, c.Values[0])
		case "INSERT":
			v := c.Values
			l.processInsert(q, Object{v[0], Box{v[1], v[2], v[1], v[2]}})
		case "DELETE":
			l.processDelete(q, c.Values[0])
		case "DUMP":
			l.Snapshot++
			l.recordSnapshot(q)
			l.Answers = append(l.Answers, fmt.Sprintf("%d DUMP snapshot %d", q, l.Snapshot))
		default:
			l.processSearch(q, c.Name, c.Values)
		}
	}
}
func (l *Laboratory) write() {
	statistics := append(append([]string{}, l.Statistics...), "")
	statistics = append(statistics, visitsSummary(l.Totals)...)
	for name, lines := range map[string][]string{"answers.txt": l.Answers, "visits.csv": l.Visits, "join.csv": l.JoinRows,
		"structures.txt": l.Structures, "stats.txt": statistics} {
		writeLines(name, lines)
	}
}
func main() {
	points, rects, params, commands := readDataset()
	lab := newLaboratory(points, rects, params)
	lab.process(commands)
	lab.write()
}
