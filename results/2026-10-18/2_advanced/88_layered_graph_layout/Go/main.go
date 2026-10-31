package main

import (
	"fmt"
	"os"
	"slices"
	"sort"
	"strconv"
	"strings"
)

type Edge struct {
	From, To, Upper, Lower         int
	Reversed, Transitive           bool
	Chain, Segments                []int
	Span, Crossings, Bends, Length int
	Route                          []Cell
}
type Vertex struct {
	Name                         string
	Layer, Width, Left, Right, X int
	Upper, Lower                 []int
}
type Segment struct{ Upper, Lower, Edge, Gap, Offset int }
type Sweep struct {
	Run, Number, Moved, Swaps, Crossings int
	Direction                            string
}
type Sift struct{ Round, Moves, Crossings int }
type Layout struct {
	Block                                                                         *Block
	N                                                                             int
	Vertices                                                                      []*Vertex
	Edges                                                                         []*Edge
	Segments                                                                      []Segment
	Gaps                                                                          [][]int
	Orders                                                                        [][]int
	Acyclic                                                                       []int
	Layering                                                                      *LayeringResult
	Coordinates                                                                   *Coordinates
	Sweeps                                                                        []Sweep
	Sifts                                                                         []Sift
	BestRun, BestSweep, InitialCrossings, AdoptedCrossings, FinalCrossings, Brute int
	Sources, Sinks, Isolated, Components                                          int
	SCC                                                                           [][]int
	Tracks, GapWidths, BandStarts, Thickness                                      []int
	M, Secondary                                                                  int
	Canvas                                                                        *Canvas
	Path                                                                          []int
}

func cloneOrders(orders [][]int) [][]int {
	out := make([][]int, len(orders))
	for i, row := range orders {
		out[i] = slices.Clone(row)
	}
	return out
}
func equalOrders(a, b [][]int) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if !slices.Equal(a[i], b[i]) {
			return false
		}
	}
	return true
}
func graphAnalysis(g *Layout) {
	in, out := make([]int, g.N), make([]int, g.N)
	weak := make([][]int, g.N)
	reach := make([][]bool, g.N)
	for i := range reach {
		reach[i] = make([]bool, g.N)
		reach[i][i] = true
	}
	for _, e := range g.Edges {
		out[e.From]++
		in[e.To]++
		weak[e.From] = append(weak[e.From], e.To)
		weak[e.To] = append(weak[e.To], e.From)
		reach[e.From][e.To] = true
	}
	for v := 0; v < g.N; v++ {
		if in[v] == 0 && out[v] > 0 {
			g.Sources++
		}
		if out[v] == 0 && in[v] > 0 {
			g.Sinks++
		}
		if in[v] == 0 && out[v] == 0 {
			g.Isolated++
		}
	}
	seen := make([]bool, g.N)
	for v := 0; v < g.N; v++ {
		if seen[v] {
			continue
		}
		g.Components++
		queue := []int{v}
		seen[v] = true
		for h := 0; h < len(queue); h++ {
			for _, w := range weak[queue[h]] {
				if !seen[w] {
					seen[w] = true
					queue = append(queue, w)
				}
			}
		}
	}
	for k := 0; k < g.N; k++ {
		for i := 0; i < g.N; i++ {
			for j := 0; j < g.N; j++ {
				reach[i][j] = reach[i][j] || (reach[i][k] && reach[k][j])
			}
		}
	}
	seen = make([]bool, g.N)
	for v := 0; v < g.N; v++ {
		if seen[v] {
			continue
		}
		component := []int{}
		for w := v; w < g.N; w++ {
			if reach[v][w] && reach[w][v] {
				seen[w] = true
				component = append(component, w)
			}
		}
		if len(component) > 1 {
			g.SCC = append(g.SCC, component)
		}
	}
}
func initialize(block *Block) *Layout {
	g := &Layout{Block: block, N: len(block.Nodes)}
	index := map[int]int{}
	horizontal := block.Settings.Direction == "TB" || block.Settings.Direction == "BT"
	for i, node := range block.Nodes {
		index[node.ID] = i
		v := &Vertex{Name: strconv.Itoa(node.ID), Width: len(node.Label) + 2}
		if horizontal {
			v.Left = (v.Width - 1) / 2
			v.Right = v.Width - 1 - v.Left
		}
		g.Vertices = append(g.Vertices, v)
	}
	for _, e := range block.Edges {
		g.Edges = append(g.Edges, &Edge{From: index[e.From], To: index[e.To]})
	}
	graphAnalysis(g)
	g.Acyclic = acyclic(g.N, g.Edges)
	rank := make([]int, g.N)
	for i, v := range g.Acyclic {
		rank[v] = i
	}
	allSuccessors := make([][]int, g.N)
	reach := make([][]bool, g.N)
	for i := range reach {
		reach[i] = make([]bool, g.N)
		reach[i][i] = true
	}
	for _, e := range g.Edges {
		e.Upper, e.Lower = e.From, e.To
		if rank[e.From] > rank[e.To] {
			e.Reversed = true
			e.Upper, e.Lower = e.To, e.From
		}
		allSuccessors[e.Upper] = append(allSuccessors[e.Upper], e.Lower)
		reach[e.Upper][e.Lower] = true
	}
	for k := 0; k < g.N; k++ {
		for i := 0; i < g.N; i++ {
			for j := 0; j < g.N; j++ {
				reach[i][j] = reach[i][j] || (reach[i][k] && reach[k][j])
			}
		}
	}
	if block.Settings.Reduce == "on" {
		for _, e := range g.Edges {
			if e.Reversed {
				continue
			}
			for _, w := range allSuccessors[e.Upper] {
				if w != e.Lower && reach[w][e.Lower] {
					e.Transitive = true
					break
				}
			}
		}
	}
	pre, succ := make([][]int, g.N), make([][]int, g.N)
	for _, e := range g.Edges {
		if !e.Transitive {
			pre[e.Lower] = append(pre[e.Lower], e.Upper)
			succ[e.Upper] = append(succ[e.Upper], e.Lower)
		}
	}
	for i := 0; i < g.N; i++ {
		slices.Sort(pre[i])
		slices.Sort(succ[i])
	}
	g.Layering = assignLayers(g.N, pre, succ, block.Settings)
	maxHeight := 0
	for _, h := range g.Layering.Height {
		maxHeight = max(maxHeight, h)
	}
	used := map[int]bool{}
	for _, h := range g.Layering.Height {
		used[maxHeight-h] = true
	}
	for _, e := range g.Edges {
		if e.Transitive {
			continue
		}
		a, b := maxHeight-g.Layering.Height[e.Upper], maxHeight-g.Layering.Height[e.Lower]
		for k := a + 1; k < b; k++ {
			used[k] = true
		}
	}
	levels := []int{}
	for k := range used {
		levels = append(levels, k)
	}
	slices.Sort(levels)
	renumber := map[int]int{}
	for i, k := range levels {
		renumber[k] = i
	}
	g.Orders = make([][]int, len(levels))
	g.Gaps = make([][]int, max(0, len(levels)-1))
	for i := 0; i < g.N; i++ {
		g.Vertices[i].Layer = renumber[maxHeight-g.Layering.Height[i]]
	}
	for edgeIndex, e := range g.Edges {
		if e.Transitive {
			continue
		}
		a, b := g.Vertices[e.Upper].Layer, g.Vertices[e.Lower].Layer
		e.Span = b - a
		e.Chain = []int{e.Upper}
		for layer := a + 1; layer < b; layer++ {
			v := len(g.Vertices)
			g.Vertices = append(g.Vertices, &Vertex{Name: fmt.Sprintf("d%d", v-g.N+1), Layer: layer, Width: 1})
			e.Chain = append(e.Chain, v)
		}
		e.Chain = append(e.Chain, e.Lower)
		for i := 0; i+1 < len(e.Chain); i++ {
			u, v := e.Chain[i], e.Chain[i+1]
			gap := g.Vertices[u].Layer
			number := len(g.Segments)
			g.Segments = append(g.Segments, Segment{Upper: u, Lower: v, Edge: edgeIndex, Gap: gap})
			e.Segments = append(e.Segments, number)
			g.Gaps[gap] = append(g.Gaps[gap], number)
			g.Vertices[u].Lower = append(g.Vertices[u].Lower, v)
			g.Vertices[v].Upper = append(g.Vertices[v].Upper, u)
		}
	}
	visited := make([]bool, len(g.Vertices))
	var visit func(int)
	visit = func(v int) {
		if visited[v] {
			return
		}
		visited[v] = true
		g.Orders[g.Vertices[v].Layer] = append(g.Orders[g.Vertices[v].Layer], v)
		for _, w := range g.Vertices[v].Lower {
			visit(w)
		}
	}
	for v := 0; v < g.N; v++ {
		visit(v)
	}
	return g
}
func reorderLayer(g *Layout, orders [][]int, layer int, down bool) {
	pos := positions(orders, len(g.Vertices))
	slots, vertices := []int{}, []int{}
	type Key struct{ N, D int }
	keys := map[int]Key{}
	for j, v := range orders[layer] {
		reference := g.Vertices[v].Upper
		if !down {
			reference = g.Vertices[v].Lower
		}
		if len(reference) == 0 {
			continue
		}
		slots = append(slots, j)
		vertices = append(vertices, v)
		values := make([]int, len(reference))
		sum := 0
		for i, u := range reference {
			values[i] = pos[u]
			sum += pos[u]
		}
		key := Key{sum, len(reference)}
		if g.Block.Settings.Heuristic == "median" {
			slices.Sort(values)
			key = Key{values[(len(values)-1)/2] + values[len(values)/2], 1}
		}
		keys[v] = key
	}
	sort.SliceStable(vertices, func(i, j int) bool {
		a, b := keys[vertices[i]], keys[vertices[j]]
		return a.N*b.D < b.N*a.D
	})
	for i, slot := range slots {
		orders[layer][slot] = vertices[i]
	}
}
func adjacentExchanges(g *Layout, orders [][]int) int {
	swaps := 0
	pos := positions(orders, len(g.Vertices))
	for {
		changed := false
		for _, row := range orders {
			for j := 0; j+1 < len(row); j++ {
				v, w := row[j], row[j+1]
				if adjacentCost(g, v, w, pos) > adjacentCost(g, w, v, pos) {
					row[j], row[j+1] = w, v
					pos[v], pos[w] = j+1, j
					swaps++
					changed = true
				}
			}
		}
		if !changed {
			return swaps
		}
	}
}
func reduceCrossings(g *Layout) {
	initial := cloneOrders(g.Orders)
	random := g.Block.Settings.Seed
	bestCrossings := -1
	var adopted [][]int
	for run := 0; run <= g.Block.Settings.Restarts; run++ {
		orders := cloneOrders(initial)
		if run > 0 {
			for _, row := range orders {
				for j := len(row) - 1; j >= 1; j-- {
					random = 48271 * random % 2147483647
					k := int(random % int64(j+1))
					row[j], row[k] = row[k], row[j]
				}
			}
		}
		crossings := totalCrossings(g, orders)
		g.Sweeps = append(g.Sweeps, Sweep{Run: run, Crossings: crossings, Direction: "initial"})
		if run == 0 {
			g.InitialCrossings = crossings
		}
		history := [][][]int{cloneOrders(orders)}
		runBest, runSweep, runOrder := crossings, 0, cloneOrders(orders)
		for sweep := 1; ; sweep++ {
			last := len(history) - 1
			if crossings == 0 || sweep-1 == g.Block.Settings.Sweeps || (last >= 2 && equalOrders(history[last], history[last-2])) {
				break
			}
			oldPos := positions(orders, len(g.Vertices))
			down := sweep%2 == 1
			direction := "up"
			if down {
				direction = "down"
				for layer := 1; layer < len(orders); layer++ {
					reorderLayer(g, orders, layer, true)
				}
			} else {
				for layer := len(orders) - 2; layer >= 0; layer-- {
					reorderLayer(g, orders, layer, false)
				}
			}
			newPos := positions(orders, len(g.Vertices))
			moved := 0
			for v := range oldPos {
				if oldPos[v] != newPos[v] {
					moved++
				}
			}
			swaps := adjacentExchanges(g, orders)
			crossings = totalCrossings(g, orders)
			g.Sweeps = append(g.Sweeps, Sweep{run, sweep, moved, swaps, crossings, direction})
			history = append(history, cloneOrders(orders))
			if crossings < runBest {
				runBest = crossings
				runSweep = sweep
				runOrder = cloneOrders(orders)
			}
		}
		if bestCrossings < 0 || runBest < bestCrossings {
			bestCrossings = runBest
			g.BestRun = run
			g.BestSweep = runSweep
			adopted = runOrder
		}
	}
	g.AdoptedCrossings = bestCrossings
	g.Orders = adopted
	if g.Block.Settings.Sifting == "on" {
		for round := 1; ; round++ {
			moves := 0
			for v, vertex := range g.Vertices {
				layer := vertex.Layer
				row := g.Orders[layer]
				original := slices.Index(row, v)
				without := append(slices.Clone(row[:original]), row[original+1:]...)
				minimum, best, originalCost := int(^uint(0)>>1), 0, 0
				for p := 0; p <= len(without); p++ {
					inserted := append(slices.Clone(without[:p]), v)
					inserted = append(inserted, without[p:]...)
					trial := slices.Clone(g.Orders)
					trial[layer] = inserted
					pos := positions(trial, len(g.Vertices))
					cost := 0
					if layer > 0 {
						cost += gapCrossings(g.Segments, g.Gaps[layer-1], pos, len(trial[layer]))
					}
					if layer+1 < len(trial) {
						cost += gapCrossings(g.Segments, g.Gaps[layer], pos, len(trial[layer+1]))
					}
					if p == original {
						originalCost = cost
					}
					if cost < minimum {
						minimum = cost
						best = p
					}
				}
				if originalCost == minimum {
					best = original
				}
				inserted := append(slices.Clone(without[:best]), v)
				g.Orders[layer] = append(inserted, without[best:]...)
				if best != original {
					moves++
				}
			}
			crossings := totalCrossings(g, g.Orders)
			g.Sifts = append(g.Sifts, Sift{round, moves, crossings})
			if moves == 0 {
				break
			}
		}
	}
	g.FinalCrossings = totalCrossings(g, g.Orders)
	g.Brute = bruteCrossings(g, g.Orders, true)
}

type BusKey struct {
	Upper  bool
	Vertex int
}
type Bus struct {
	Key              BusKey
	Low, High, Track int
	Segments         []int
}

func abs(a int) int {
	if a < 0 {
		return -a
	}
	return a
}
func geometry(g *Layout) {
	layers := len(g.Orders)
	g.Tracks = make([]int, len(g.Gaps))
	g.GapWidths = make([]int, len(g.Gaps))
	for gap, indices := range g.Gaps {
		counts := map[int]int{}
		for _, index := range indices {
			s := g.Segments[index]
			if g.Vertices[s.Upper].X != g.Vertices[s.Lower].X {
				counts[s.Upper]++
			}
		}
		byKey := map[BusKey]*Bus{}
		buses := []*Bus{}
		for _, index := range indices {
			s := g.Segments[index]
			upper, lower := g.Vertices[s.Upper].X, g.Vertices[s.Lower].X
			if upper == lower {
				continue
			}
			key := BusKey{counts[s.Upper] >= 2, s.Lower}
			if key.Upper {
				key.Vertex = s.Upper
			}
			bus := byKey[key]
			if bus == nil {
				bus = &Bus{Key: key, Low: min(upper, lower), High: max(upper, lower)}
				byKey[key] = bus
				buses = append(buses, bus)
			}
			bus.Low = min(bus.Low, min(upper, lower))
			bus.High = max(bus.High, max(upper, lower))
			bus.Segments = append(bus.Segments, index)
		}
		sort.Slice(buses, func(i, j int) bool {
			a, b := buses[i], buses[j]
			if a.Low != b.Low {
				return a.Low < b.Low
			}
			if a.High != b.High {
				return a.High < b.High
			}
			if a.Key.Upper != b.Key.Upper {
				return a.Key.Upper
			}
			return g.Vertices[a.Key.Vertex].X < g.Vertices[b.Key.Vertex].X
		})
		ends := []int{}
		for _, bus := range buses {
			track := -1
			for t, end := range ends {
				if end+1 < bus.Low {
					track = t
					break
				}
			}
			if track < 0 {
				track = len(ends)
				ends = append(ends, bus.High)
			} else {
				ends[track] = bus.High
			}
			bus.Track = track + 1
		}
		g.Tracks[gap] = len(ends)
		g.GapWidths[gap] = max(g.Block.Settings.LayerGap, len(ends)+2)
		for _, bus := range buses {
			offset := bus.Track + (g.GapWidths[gap]-2-len(ends))/2
			for _, index := range bus.Segments {
				g.Segments[index].Offset = offset
			}
		}
	}
	g.Thickness = make([]int, layers)
	g.BandStarts = make([]int, layers)
	vertical := g.Block.Settings.Direction == "TB" || g.Block.Settings.Direction == "BT"
	for i, row := range g.Orders {
		g.Thickness[i] = 1
		if !vertical {
			for _, v := range row {
				g.Thickness[i] = max(g.Thickness[i], g.Vertices[v].Width)
			}
		}
		if i > 0 {
			g.BandStarts[i] = g.BandStarts[i-1] + g.Thickness[i-1] + g.GapWidths[i-1]
		}
	}
	g.M = g.BandStarts[layers-1] + g.Thickness[layers-1]
	for _, v := range g.Vertices {
		g.Secondary = max(g.Secondary, v.X+v.Right+1)
	}
	g.Canvas = newCanvas(g.M, g.Secondary, g.Block.Settings.Direction)
	vertexSize := func(v int) int {
		if vertical {
			return 1
		}
		return g.Vertices[v].Width
	}
	for _, e := range g.Edges {
		if e.Transitive {
			continue
		}
		upper := g.Canvas.Map(g.BandStarts[g.Vertices[e.Upper].Layer]+vertexSize(e.Upper), g.Vertices[e.Upper].X)
		lower := g.Canvas.Map(g.BandStarts[g.Vertices[e.Lower].Layer]-1, g.Vertices[e.Lower].X)
		e.Route = []Cell{upper}
		for _, index := range e.Segments {
			s := g.Segments[index]
			x, y := g.Vertices[s.Upper].X, g.Vertices[s.Lower].X
			if x != y {
				main := g.BandStarts[s.Gap] + g.Thickness[s.Gap] + s.Offset
				e.Route = append(e.Route, g.Canvas.Map(main, x), g.Canvas.Map(main, y))
				e.Bends += 2
			}
		}
		e.Route = append(e.Route, lower)
		if e.Reversed {
			slices.Reverse(e.Route)
		}
		e.Length = 1
		for i := 0; i+1 < len(e.Route); i++ {
			a, b := e.Route[i], e.Route[i+1]
			e.Length += abs(a.Row-b.Row) + abs(a.Column-b.Column)
		}
	}
	if g.Block.HasPath {
		indices := map[int]int{}
		for i, n := range g.Block.Nodes {
			indices[n.ID] = i
		}
		from, to := indices[g.Block.PathFrom], indices[g.Block.PathTo]
		adjacent := make([][]int, g.N)
		for _, e := range g.Edges {
			if !e.Transitive {
				adjacent[e.From] = append(adjacent[e.From], e.To)
			}
		}
		for i := range adjacent {
			slices.Sort(adjacent[i])
		}
		parent := make([]int, g.N)
		for i := range parent {
			parent[i] = -2
		}
		parent[from] = -1
		queue := []int{from}
		for h := 0; h < len(queue); h++ {
			for _, v := range adjacent[queue[h]] {
				if parent[v] == -2 {
					parent[v] = queue[h]
					queue = append(queue, v)
				}
			}
		}
		if parent[to] != -2 {
			for v := to; v >= 0; v = parent[v] {
				g.Path = append(g.Path, v)
			}
			slices.Reverse(g.Path)
		}
	}
}
func draw(g *Layout) {
	c := g.Canvas
	for i, v := range g.Vertices {
		if i >= g.N {
			for j := 0; j < g.Thickness[v.Layer]; j++ {
				c.MainLine(g.BandStarts[v.Layer]+j, v.X)
			}
		} else if (c.Direction == "LR" || c.Direction == "RL") && len(v.Lower) > 0 {
			for j := v.Width; j < g.Thickness[v.Layer]; j++ {
				c.MainLine(g.BandStarts[v.Layer]+j, v.X)
			}
		}
	}
	for _, s := range g.Segments {
		c.Segment(g.BandStarts[s.Gap]+g.Thickness[s.Gap], g.GapWidths[s.Gap], g.Vertices[s.Upper].X, g.Vertices[s.Lower].X, s.Offset)
	}
	arrows := map[string][2]byte{"TB": {'v', '^'}, "BT": {'^', 'v'}, "LR": {'>', '<'}, "RL": {'<', '>'}}
	for _, e := range g.Edges {
		if e.Transitive {
			continue
		}
		position := e.Route[len(e.Route)-1]
		arrow := arrows[c.Direction][0]
		if e.Reversed {
			arrow = arrows[c.Direction][1]
		}
		c.Arrows[position.Row][position.Column] = arrow
	}
	pathNodes := map[int]bool{}
	pathEdges := map[[2]int]bool{}
	for i, v := range g.Path {
		pathNodes[v] = true
		if i > 0 {
			pathEdges[[2]int{g.Path[i-1], v}] = true
		}
	}
	for _, e := range g.Edges {
		if e.Transitive || !pathEdges[[2]int{e.From, e.To}] {
			continue
		}
		for i := 0; i+1 < len(e.Route); i++ {
			c.Highlight(e.Route[i], e.Route[i+1])
		}
	}
	for i, node := range g.Block.Nodes {
		v := g.Vertices[i]
		text := "[" + node.Label + "]"
		if pathNodes[i] {
			text = "{" + node.Label + "}"
		}
		var start Cell
		switch c.Direction {
		case "TB", "BT":
			start = c.Map(g.BandStarts[v.Layer], v.X-v.Left)
		case "LR":
			start = Cell{v.X, g.BandStarts[v.Layer]}
		case "RL":
			start = Cell{v.X, g.M - g.BandStarts[v.Layer] - v.Width}
		}
		for j := range text {
			c.Boxes[start.Row][start.Column+j] = text[j]
		}
	}
}
func displayNames(g *Layout, vertices []int) []string {
	out := make([]string, len(vertices))
	for i, v := range vertices {
		out[i] = g.Vertices[v].Name
	}
	return out
}
func edgeName(g *Layout, e *Edge) string {
	return g.Vertices[e.From].Name + "->" + g.Vertices[e.To].Name
}
func layoutLines(g *Layout) []string {
	block := g.Block
	settings := []string{}
	for i, value := range block.Settings.Values() {
		settings = append(settings, settingNames[i]+"="+value)
	}
	out := []string{"graph " + block.Name, "settings " + strings.Join(settings, " "), "acyclic " + strings.Join(displayNames(g, g.Acyclic), " ")}
	if block.Settings.Layering == "coffman" {
		labels := []string{}
		for v, label := range g.Layering.Labels {
			labels = append(labels, fmt.Sprintf("%s:%d", g.Vertices[v].Name, label))
		}
		out = append(out, "labels "+strings.Join(labels, " "))
	}
	for _, p := range g.Layering.Promotions {
		out = append(out, fmt.Sprintf("promote %d %s %d", p.Round, g.Vertices[p.Node].Name, p.Diff))
	}
	for _, s := range g.Sweeps {
		if s.Number == 0 {
			out = append(out, fmt.Sprintf("sweep %d 0 initial crossings %d", s.Run, s.Crossings))
		} else {
			out = append(out, fmt.Sprintf("sweep %d %d %s moved %d swaps %d crossings %d", s.Run, s.Number, s.Direction, s.Moved, s.Swaps, s.Crossings))
		}
	}
	out = append(out, fmt.Sprintf("best run %d sweep %d crossings %d", g.BestRun, g.BestSweep, g.AdoptedCrossings))
	for _, s := range g.Sifts {
		out = append(out, fmt.Sprintf("sift %d moves %d crossings %d", s.Round, s.Moves, s.Crossings))
	}
	for i, row := range g.Orders {
		bandStart, bandEnd := g.BandStarts[i], g.BandStarts[i]+g.Thickness[i]-1
		if block.Settings.Direction == "BT" || block.Settings.Direction == "RL" {
			bandStart, bandEnd = g.M-1-bandEnd, g.M-1-bandStart
		}
		low, high := 0, 0
		vertices := []string{}
		for j, index := range row {
			v := g.Vertices[index]
			if j == 0 || v.X-v.Left < low {
				low = v.X - v.Left
			}
			if j == 0 || v.X+v.Right > high {
				high = v.X + v.Right
			}
			vertices = append(vertices, fmt.Sprintf("%s@%d", v.Name, v.X))
		}
		out = append(out, fmt.Sprintf("layer %d band %d %d extent %d %d : %s", i, bandStart, bandEnd, low, high, strings.Join(vertices, " ")))
	}
	pos := positions(g.Orders, len(g.Vertices))
	for i, indices := range g.Gaps {
		crossings := gapCrossings(g.Segments, indices, pos, len(g.Orders[i+1]))
		out = append(out, fmt.Sprintf("between %d %d segments %d crossings %d tracks %d gap %d", i, i+1, len(indices), crossings, g.Tracks[i], g.GapWidths[i]))
	}
	parts := []string{}
	for _, variant := range g.Coordinates.Variants {
		parts = append(parts, fmt.Sprintf("%s=%d/%d", variant.Name, variant.Blocks, variant.Width))
	}
	out = append(out, fmt.Sprintf("bk conflicts %d %s smallest %s", len(g.Coordinates.Marked), strings.Join(parts, " "), g.Coordinates.Variants[g.Coordinates.Smallest].Name))
	for layer, row := range g.Orders {
		for p, v := range row {
			x := g.Vertices[v].X
			variants := g.Coordinates.Variants
			out = append(out, fmt.Sprintf("vertex %s layer %d pos %d ul %d ur %d dl %d dr %d x %d", g.Vertices[v].Name, layer, p, variants[0].Aligned[v], variants[1].Aligned[v], variants[2].Aligned[v], variants[3].Aligned[v], x))
		}
	}
	for _, e := range g.Edges {
		prefix := fmt.Sprintf("edge %s %s", g.Vertices[e.From].Name, g.Vertices[e.To].Name)
		if e.Transitive {
			out = append(out, prefix+" transitive")
			continue
		}
		if e.Reversed {
			prefix += " reversed"
		}
		chain := slices.Clone(e.Chain)
		if e.Reversed {
			slices.Reverse(chain)
		}
		values := []string{}
		for _, v := range chain {
			values = append(values, strconv.Itoa(g.Vertices[v].X))
		}
		route := []string{}
		for _, p := range e.Route {
			route = append(route, fmt.Sprintf("%d,%d", p.Row, p.Column))
		}
		out = append(out, fmt.Sprintf("%s span %d crossings %d bends %d path %s route %s", prefix, e.Span, e.Crossings, e.Bends, strings.Join(values, " "), strings.Join(route, " ")))
	}
	return append(out, "end")
}
func statsLines(g *Layout) []string {
	block := g.Block
	out := []string{"graph " + block.Name, fmt.Sprintf("nodes %d edges %d self_loops %d duplicates %d", g.N, len(g.Edges), block.SelfLoops, block.Duplicates), fmt.Sprintf("sources %d sinks %d isolated %d components %d", g.Sources, g.Sinks, g.Isolated, g.Components)}
	for _, component := range g.SCC {
		out = append(out, "scc "+strings.Join(displayNames(g, component), " "))
	}
	reversed, transitive := []string{}, []string{}
	spanCounts := map[int]int{}
	spanTotal, spanMax, longEdges, vertical, routeLength, bends, longest := 0, 0, 0, 0, 0, 0, -1
	for i, e := range g.Edges {
		if e.Reversed {
			reversed = append(reversed, edgeName(g, e))
		}
		if e.Transitive {
			transitive = append(transitive, edgeName(g, e))
			continue
		}
		spanCounts[e.Span]++
		spanTotal += e.Span
		spanMax = max(spanMax, e.Span)
		if e.Span >= 2 {
			longEdges++
			same := true
			dummies := e.Chain[1 : len(e.Chain)-1]
			x := g.Vertices[dummies[0]].X
			for _, v := range dummies {
				if g.Vertices[v].X != x {
					same = false
				}
			}
			if same {
				vertical++
			}
		}
		routeLength += e.Length
		bends += e.Bends
		if longest < 0 || e.Length > g.Edges[longest].Length {
			longest = i
		}
	}
	rLine := fmt.Sprintf("reversed %d", len(reversed))
	if len(reversed) > 0 {
		rLine += " " + strings.Join(reversed, " ")
	}
	tLine := fmt.Sprintf("transitive %d", len(transitive))
	if len(transitive) > 0 {
		tLine += " " + strings.Join(transitive, " ")
	}
	maxNodes, maxVertices := 0, 0
	for _, row := range g.Orders {
		nodes := 0
		for _, v := range row {
			if v < g.N {
				nodes++
			}
		}
		maxNodes = max(maxNodes, nodes)
		maxVertices = max(maxVertices, len(row))
	}
	out = append(out, rLine, tLine, fmt.Sprintf("layers %d max_nodes %d max_vertices %d", len(g.Orders), maxNodes, maxVertices))
	if block.Settings.Promotion == "on" {
		out = append(out, fmt.Sprintf("promotion rounds %d accepted %d dummies_before %d", g.Layering.Rounds, len(g.Layering.Promotions), g.Layering.DummiesBefore))
	} else {
		out = append(out, "promotion off")
	}
	out = append(out, fmt.Sprintf("dummies %d span_total %d span_max %d", len(g.Vertices)-g.N, spanTotal, spanMax))
	spans := []int{}
	for span := range spanCounts {
		spans = append(spans, span)
	}
	slices.Sort(spans)
	line := "spans none"
	if len(spans) > 0 {
		values := []string{}
		for _, span := range spans {
			values = append(values, fmt.Sprintf("%d:%d", span, spanCounts[span]))
		}
		line = "spans " + strings.Join(values, " ")
	}
	out = append(out, line, fmt.Sprintf("long_edges %d vertical %d", longEdges, vertical), fmt.Sprintf("crossings initial %d swept %d best_run %d best_sweep %d final %d brute %d", g.InitialCrossings, g.AdoptedCrossings, g.BestRun, g.BestSweep, g.FinalCrossings, g.Brute))
	straight, offset := 0, 0
	for _, s := range g.Segments {
		a, b := g.Vertices[s.Upper].X, g.Vertices[s.Lower].X
		if a == b {
			straight++
		}
		offset += abs(a - b)
	}
	out = append(out, fmt.Sprintf("segments %d straight %d bent %d offset %d", len(g.Segments), straight, len(g.Segments)-straight, offset))
	line = fmt.Sprintf("routes length %d bends %d", routeLength, bends)
	if longest >= 0 {
		line += fmt.Sprintf(" longest %s %d", edgeName(g, g.Edges[longest]), g.Edges[longest].Length)
	}
	out = append(out, line, fmt.Sprintf("canvas width %d height %d crossing_cells %d", g.Canvas.Columns, g.Canvas.Rows, g.Canvas.CrossingCells()))
	if block.HasPath {
		if len(g.Path) == 0 {
			out = append(out, fmt.Sprintf("path %d %d none", block.PathFrom, block.PathTo))
		} else {
			out = append(out, fmt.Sprintf("path %d %d hops %d : %s", block.PathFrom, block.PathTo, len(g.Path)-1, strings.Join(displayNames(g, g.Path), " ")))
		}
	}
	return append(out, "end")
}
func writeLines(name string, lines []string) {
	text := ""
	if len(lines) > 0 {
		text = strings.Join(lines, "\n") + "\n"
	}
	if e := os.WriteFile("output/"+name, []byte(text), 0644); e != nil {
		panic(e)
	}
}
func main() {
	blocks := readBlocks()
	layout, stats, drawings := []string{}, []string{}, []string{}
	crossings := []string{"graph,run,sweep,crossings"}
	laidOut, errors, nodes, edges, dummies, initial, final := 0, 0, 0, 0, 0, 0, 0
	for i, block := range blocks {
		if i > 0 {
			drawings = append(drawings, "")
		}
		if block.Error != "" {
			errors++
			errorLines := []string{"graph " + block.Name, fmt.Sprintf("error %s line %d", block.Error, block.ErrorLine), "end"}
			layout = append(layout, errorLines...)
			stats = append(stats, errorLines...)
			drawings = append(drawings, "graph "+block.Name+" error "+block.Error)
			continue
		}
		g := initialize(block)
		reduceCrossings(g)
		g.Coordinates = coordinates(g)
		geometry(g)
		draw(g)
		layout = append(layout, layoutLines(g)...)
		stats = append(stats, statsLines(g)...)
		drawings = append(drawings, g.Canvas.Drawing(block.Name)...)
		for _, s := range g.Sweeps {
			crossings = append(crossings, fmt.Sprintf("%s,%d,%d,%d", block.Name, s.Run, s.Number, s.Crossings))
		}
		laidOut++
		nodes += g.N
		edges += len(g.Edges)
		dummies += len(g.Vertices) - g.N
		initial += g.InitialCrossings
		final += g.FinalCrossings
	}
	stats = append(stats, fmt.Sprintf("summary graphs %d laid_out %d errors %d nodes %d edges %d dummies %d crossings_initial %d crossings_final %d", len(blocks), laidOut, errors, nodes, edges, dummies, initial, final))
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	writeLines("layout.txt", layout)
	writeLines("stats.txt", stats)
	writeLines("crossings.csv", crossings)
	writeLines("drawings.txt", drawings)
}
