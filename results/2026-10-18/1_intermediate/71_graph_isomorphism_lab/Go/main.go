package main

import (
	"bufio"
	"fmt"
	"io"
	"math/bits"
	"os"
	"sort"
	"strconv"
	"strings"
)

type graph struct {
	n         int
	adjacent  []uint32
	canonical *canonResult
}

type canonResult struct {
	nodes, leaves int
	text          string
	labels        []int
	best          [][]int
}

type invariants struct {
	degrees, sizes               []int
	edges, triangles, components int
	girth, diameter, radius      string
	bipartite                    bool
}

type pair struct {
	a, b int
}

func newGraph(n int) *graph {
	return &graph{n: n, adjacent: make([]uint32, n)}
}

func (g *graph) has(a, b int) bool {
	return g.adjacent[a]&(uint32(1)<<b) != 0
}

func (g *graph) join(a, b int) {
	g.adjacent[a] |= uint32(1) << b
	g.adjacent[b] |= uint32(1) << a
}

func (g *graph) edges() []pair {
	result := []pair{}
	for a := 0; a < g.n; a++ {
		for b := a + 1; b < g.n; b++ {
			if g.has(a, b) {
				result = append(result, pair{a, b})
			}
		}
	}
	return result
}

func integers(values []int) string {
	words := make([]string, len(values))
	for i, value := range values {
		words[i] = strconv.Itoa(value)
	}
	return strings.Join(words, " ")
}

func copyInts(values []int) []int {
	return append([]int{}, values...)
}

func compare(a, b []int) int {
	for i := 0; i < len(a) && i < len(b); i++ {
		if a[i] < b[i] {
			return -1
		}
		if a[i] > b[i] {
			return 1
		}
	}
	if len(a) < len(b) {
		return -1
	}
	if len(a) > len(b) {
		return 1
	}
	return 0
}

func colorsCount(colors []int) int {
	count := 0
	for _, color := range colors {
		if color+1 > count {
			count = color + 1
		}
	}
	return count
}

func degreeColors(g *graph) []int {
	degrees, unique := make([]int, g.n), []int{}
	seen := map[int]bool{}
	for i, adjacent := range g.adjacent {
		degrees[i] = bits.OnesCount32(adjacent)
		seen[degrees[i]] = true
	}
	for degree := range seen {
		unique = append(unique, degree)
	}
	sort.Ints(unique)
	for i, degree := range degrees {
		degrees[i] = sort.SearchInts(unique, degree)
	}
	return degrees
}

func refine(g *graph, initial []int) ([]int, int) {
	current, rounds := copyInts(initial), 0
	for {
		signatures := make([][]int, g.n)
		vertices := make([]int, g.n)
		for v := 0; v < g.n; v++ {
			neighbors := []int{}
			for w := 0; w < g.n; w++ {
				if g.has(v, w) {
					neighbors = append(neighbors, current[w])
				}
			}
			sort.Ints(neighbors)
			signatures[v] = append([]int{current[v]}, neighbors...)
			vertices[v] = v
		}
		sort.Slice(vertices, func(i, j int) bool {
			return compare(signatures[vertices[i]], signatures[vertices[j]]) < 0
		})
		next, color := make([]int, g.n), 0
		for i, v := range vertices {
			if i > 0 && compare(signatures[v], signatures[vertices[i-1]]) != 0 {
				color++
			}
			next[v] = color
		}
		if color+1 == colorsCount(current) {
			return current, rounds
		}
		current = next
		rounds++
	}
}

func individualize(colors []int, vertex int) []int {
	result, selected := copyInts(colors), colors[vertex]
	for v, color := range colors {
		if v != vertex && color >= selected {
			result[v]++
		}
	}
	return result
}

func cellSizes(colors []int) []int {
	sizes := make([]int, colorsCount(colors))
	for _, color := range colors {
		sizes[color]++
	}
	return sizes
}

func (g *graph) leafText(labels []int) string {
	inverse := make([]int, g.n)
	for v, label := range labels {
		inverse[label] = v
	}
	var text strings.Builder
	for a := 0; a < g.n; a++ {
		for b := a + 1; b < g.n; b++ {
			if g.has(inverse[a], inverse[b]) {
				text.WriteByte('1')
			} else {
				text.WriteByte('0')
			}
		}
	}
	return text.String()
}

func (g *graph) canon() *canonResult {
	if g.canonical != nil {
		return g.canonical
	}
	result := &canonResult{}
	var visit func([]int)
	visit = func(colors []int) {
		result.nodes++
		sizes := cellSizes(colors)
		if len(sizes) == g.n {
			result.leaves++
			text := g.leafText(colors)
			if result.labels == nil || text > result.text {
				result.text, result.labels, result.best = text, copyInts(colors), nil
			}
			if text == result.text {
				result.best = append(result.best, copyInts(colors))
			}
			return
		}
		selected, size := -1, g.n+1
		for color, count := range sizes {
			if count > 1 && count < size {
				selected, size = color, count
			}
		}
		for v, color := range colors {
			if color == selected {
				next, _ := refine(g, individualize(colors, v))
				visit(next)
			}
		}
	}
	initial, _ := refine(g, degreeColors(g))
	visit(initial)
	g.canonical = result
	return result
}

func relabel(g *graph, permutation []int) *graph {
	result := newGraph(g.n)
	for _, edge := range g.edges() {
		result.join(permutation[edge.a], permutation[edge.b])
	}
	return result
}

func (g *graph) invariants() invariants {
	result := invariants{edges: len(g.edges()), girth: "none", diameter: "INF", radius: "INF", bipartite: true}
	for _, mask := range g.adjacent {
		result.degrees = append(result.degrees, bits.OnesCount32(mask))
	}
	sort.Sort(sort.Reverse(sort.IntSlice(result.degrees)))
	for a := 0; a < g.n; a++ {
		for b := a + 1; b < g.n; b++ {
			for c := b + 1; c < g.n; c++ {
				if g.has(a, b) && g.has(a, c) && g.has(b, c) {
					result.triangles++
				}
			}
		}
	}
	reached, coloring := make([]bool, g.n), make([]int, g.n)
	shortest, diameter, radius := 0, 0, g.n
	for start := 0; start < g.n; start++ {
		distance, parent := make([]int, g.n), make([]int, g.n)
		for i := range distance {
			distance[i], parent[i] = -1, -1
		}
		distance[start] = 0
		queue := []int{start}
		eccentricity := 0
		for at := 0; at < len(queue); at++ {
			v := queue[at]
			if distance[v] > eccentricity {
				eccentricity = distance[v]
			}
			for w := 0; w < g.n; w++ {
				if !g.has(v, w) {
					continue
				}
				if distance[w] < 0 {
					distance[w], parent[w] = distance[v]+1, v
					queue = append(queue, w)
				} else if parent[v] != w {
					length := distance[v] + distance[w] + 1
					if shortest == 0 || length < shortest {
						shortest = length
					}
				}
			}
		}
		if !reached[start] {
			result.components++
			result.sizes = append(result.sizes, len(queue))
			for _, v := range queue {
				reached[v] = true
			}
			coloring[start] = 1
			pending := []int{start}
			for at := 0; at < len(pending); at++ {
				v := pending[at]
				for w := 0; w < g.n; w++ {
					if g.has(v, w) {
						if coloring[w] == 0 {
							coloring[w] = -coloring[v]
							pending = append(pending, w)
						} else if coloring[w] == coloring[v] {
							result.bipartite = false
						}
					}
				}
			}
		}
		if eccentricity > diameter {
			diameter = eccentricity
		}
		if eccentricity < radius {
			radius = eccentricity
		}
	}
	sort.Sort(sort.Reverse(sort.IntSlice(result.sizes)))
	if shortest > 0 {
		result.girth = strconv.Itoa(shortest)
	}
	if result.components == 1 {
		result.diameter, result.radius = strconv.Itoa(diameter), strconv.Itoa(radius)
	}
	return result
}

func (g *graph) clique() []int {
	best := []int{}
	for mask := uint32(1); mask < uint32(1)<<g.n; mask++ {
		if bits.OnesCount32(mask) < len(best) {
			continue
		}
		vertices, valid := []int{}, true
		for v := 0; v < g.n; v++ {
			if mask&(uint32(1)<<v) != 0 {
				vertices = append(vertices, v)
				if mask & ^(g.adjacent[v]|uint32(1)<<v) != 0 {
					valid = false
					break
				}
			}
		}
		if valid && (len(vertices) > len(best) || compare(vertices, best) < 0) {
			best = vertices
		}
	}
	return best
}

func (g *graph) chromatic() (int, []int) {
	colors := make([]int, g.n)
	var search func(int, int) bool
	search = func(v, limit int) bool {
		if v == g.n {
			return true
		}
		for color := 0; color < limit; color++ {
			valid := true
			for w := 0; w < v; w++ {
				if g.has(v, w) && colors[w] == color {
					valid = false
					break
				}
			}
			if valid {
				colors[v] = color
				if search(v+1, limit) {
					return true
				}
			}
		}
		return false
	}
	for limit := 1; limit <= g.n; limit++ {
		if search(0, limit) {
			return limit, colors
		}
	}
	return 0, nil
}

func yes(value bool) string {
	if value {
		return "yes"
	}
	return "no"
}

func numberWord(s string) bool {
	if len(s) == 0 || len(s) > 3 || len(s) > 1 && s[0] == '0' {
		return false
	}
	for i := range s {
		if s[i] < '0' || s[i] > '9' {
			return false
		}
	}
	return true
}

func nameWord(s string) bool {
	if len(s) == 0 || len(s) > 8 || s[0] < 'a' || s[0] > 'z' {
		return false
	}
	for i := range s {
		if !(s[i] >= 'a' && s[i] <= 'z' || s[i] >= '0' && s[i] <= '9') {
			return false
		}
	}
	return true
}

func number(s string) int {
	n, _ := strconv.Atoi(s)
	return n
}

func edgeWord(s string) bool {
	fields := strings.Split(s, "-")
	return len(fields) == 2 && numberWord(fields[0]) && numberWord(fields[1])
}

func contains(xs []string, value string) bool {
	for _, x := range xs {
		if x == value {
			return true
		}
	}
	return false
}

var definitions = []string{"GRAPH", "CYCLE", "PATH", "COMPLETE", "BIPARTITE", "STAR", "WHEEL", "PETERSEN", "HYPERCUBE", "CIRCULANT", "GRID", "COMPLEMENT", "LINE", "PRODUCT", "UNION", "RELABEL", "INDUCED", "CANONIZE"}

type lab struct {
	graphs map[string]*graph
	out    *bufio.Writer
}

func (l *lab) command(words []string) error {
	command, args := words[0], words[1:]
	defining := contains(definitions, command)
	if !defining && !contains([]string{
		"DELETE", "LIST", "SHOW", "INVARIANTS", "REFINE", "CANON", "ISO", "AUT", "SUBISO", "CLASSIFY",
	}, command) {
		return fmt.Errorf("unknown command %s", command)
	}
	minimum, maximum := 1, 1
	switch command {
	case "LIST":
		minimum, maximum = 0, 0
	case "GRAPH", "RELABEL", "REFINE":
		minimum, maximum = 2, -1
		if command == "REFINE" {
			minimum = 1
		}
	case "CIRCULANT", "INDUCED":
		minimum, maximum = 3, -1
	case "BIPARTITE", "GRID", "PRODUCT", "UNION":
		minimum, maximum = 3, 3
	case "CYCLE", "PATH", "COMPLETE", "STAR", "WHEEL", "HYPERCUBE", "COMPLEMENT", "LINE", "CANONIZE", "ISO", "SUBISO":
		minimum, maximum = 2, 2
	}
	if len(args) < minimum || maximum >= 0 && len(args) > maximum {
		return fmt.Errorf("bad arguments")
	}
	namePositions := map[int]bool{}
	if defining {
		namePositions[0] = true
	}
	existing := []int{}
	switch command {
	case "COMPLEMENT", "LINE", "RELABEL", "INDUCED", "CANONIZE":
		existing = []int{1}
	case "PRODUCT", "UNION":
		existing = []int{1, 2}
	case "DELETE", "SHOW", "INVARIANTS", "REFINE", "CANON", "AUT":
		existing = []int{0}
	case "ISO", "SUBISO":
		existing = []int{0, 1}
	}
	for _, i := range existing {
		namePositions[i] = true
	}
	for i, arg := range args {
		valid := numberWord(arg)
		if namePositions[i] {
			valid = nameWord(arg)
		} else if command == "GRAPH" && i > 1 {
			valid = edgeWord(arg)
		}
		if !valid {
			return fmt.Errorf("bad arguments")
		}
	}
	for _, i := range existing {
		if l.graphs[args[i]] == nil {
			return fmt.Errorf("no graph %s", args[i])
		}
	}
	var g *graph
	if defining {
		source := func(i int) *graph {
			return l.graphs[args[i]]
		}
		switch command {
		case "GRAPH", "CYCLE", "PATH", "COMPLETE", "STAR", "WHEEL", "HYPERCUBE", "CIRCULANT":
			n := number(args[1])
			minimum, maximum := 1, 16
			if command == "CYCLE" || command == "CIRCULANT" {
				minimum = 3
			}
			if command == "WHEEL" {
				minimum = 3
				maximum = 15
			}
			if command == "STAR" {
				maximum = 15
			}
			if command == "HYPERCUBE" {
				maximum = 4
			}
			if n < minimum {
				return fmt.Errorf("bad value")
			}
			if n > maximum {
				return fmt.Errorf("too large")
			}
			if command == "STAR" || command == "WHEEL" {
				n++
			} else if command == "HYPERCUBE" {
				n = 1 << n
			}
			g = newGraph(n)
			switch command {
			case "GRAPH":
				for _, word := range args[2:] {
					fields := strings.Split(word, "-")
					a, b := number(fields[0]), number(fields[1])
					if a >= n || b >= n || a == b {
						return fmt.Errorf("bad edge %s", word)
					}
					if g.has(a, b) {
						return fmt.Errorf("duplicate edge %s", word)
					}
					g.join(a, b)
				}
			case "CYCLE":
				for v := 0; v < n; v++ {
					g.join(v, (v+1)%n)
				}
			case "PATH":
				for v := 0; v+1 < n; v++ {
					g.join(v, v+1)
				}
			case "COMPLETE":
				for a := 0; a < n; a++ {
					for b := a + 1; b < n; b++ {
						g.join(a, b)
					}
				}
			case "STAR", "WHEEL":
				for v := 1; v < n; v++ {
					g.join(0, v)
					if command == "WHEEL" {
						next := v + 1
						if next == n {
							next = 1
						}
						g.join(v, next)
					}
				}
			case "HYPERCUBE":
				for v := 0; v < n; v++ {
					for bit := 1; bit < n; bit <<= 1 {
						g.join(v, v^bit)
					}
				}
			case "CIRCULANT":
				previous := 0
				for _, word := range args[2:] {
					jump := number(word)
					if jump <= previous || 2*jump > n {
						return fmt.Errorf("bad value")
					}
					for v := 0; v < n; v++ {
						g.join(v, (v+jump)%n)
					}
					previous = jump
				}
			}
		case "BIPARTITE", "GRID":
			a, b := number(args[1]), number(args[2])
			if a == 0 || b == 0 {
				return fmt.Errorf("bad value")
			}
			n := a + b
			if command == "GRID" {
				n = a * b
			}
			if n > 16 {
				return fmt.Errorf("too large")
			}
			g = newGraph(n)
			for x := 0; x < a; x++ {
				for y := 0; y < b; y++ {
					if command == "BIPARTITE" {
						g.join(x, a+y)
					} else {
						if y+1 < b {
							g.join(x*b+y, x*b+y+1)
						}
						if x+1 < a {
							g.join(x*b+y, (x+1)*b+y)
						}
					}
				}
			}
		case "PETERSEN":
			g = newGraph(10)
			for i := 0; i < 5; i++ {
				g.join(i, (i+1)%5)
				g.join(i, i+5)
				g.join(i+5, 5+(i+2)%5)
			}
		case "COMPLEMENT":
			a := source(1)
			g = newGraph(a.n)
			for x := 0; x < a.n; x++ {
				for y := x + 1; y < a.n; y++ {
					if !a.has(x, y) {
						g.join(x, y)
					}
				}
			}
		case "LINE":
			edges := source(1).edges()
			if len(edges) == 0 {
				return fmt.Errorf("no edges")
			}
			if len(edges) > 16 {
				return fmt.Errorf("too large")
			}
			g = newGraph(len(edges))
			for i, a := range edges {
				for j := i + 1; j < len(edges); j++ {
					b := edges[j]
					if a.a == b.a || a.a == b.b || a.b == b.a || a.b == b.b {
						g.join(i, j)
					}
				}
			}
		case "PRODUCT", "UNION":
			a, b := source(1), source(2)
			n := a.n + b.n
			if command == "PRODUCT" {
				n = a.n * b.n
			}
			if n > 16 {
				return fmt.Errorf("too large")
			}
			g = newGraph(n)
			if command == "UNION" {
				for _, edge := range a.edges() {
					g.join(edge.a, edge.b)
				}
				for _, edge := range b.edges() {
					g.join(edge.a+a.n, edge.b+a.n)
				}
			} else {
				for x := 0; x < a.n; x++ {
					for _, edge := range b.edges() {
						g.join(x*b.n+edge.a, x*b.n+edge.b)
					}
				}
				for y := 0; y < b.n; y++ {
					for _, edge := range a.edges() {
						g.join(edge.a*b.n+y, edge.b*b.n+y)
					}
				}
			}
		case "RELABEL", "INDUCED":
			a := source(1)
			values, seen := []int{}, map[int]bool{}
			if command == "RELABEL" && len(args)-2 != a.n {
				return fmt.Errorf("bad permutation")
			}
			for _, word := range args[2:] {
				value := number(word)
				if value >= a.n || seen[value] {
					if command == "RELABEL" {
						return fmt.Errorf("bad permutation")
					}
					return fmt.Errorf("bad vertices")
				}
				seen[value] = true
				values = append(values, value)
			}
			if command == "RELABEL" {
				g = relabel(a, values)
			} else {
				g = newGraph(len(values))
				for i, x := range values {
					for j := i + 1; j < len(values); j++ {
						if a.has(x, values[j]) {
							g.join(i, j)
						}
					}
				}
			}
		case "CANONIZE":
			g = relabel(source(1), source(1).canon().labels)
		}
		action := "defined"
		if l.graphs[args[0]] != nil {
			action = "redefined"
		}
		l.graphs[args[0]] = g
		fmt.Fprintf(l.out, "%s %s n %d m %d\n", action, args[0], g.n, len(g.edges()))
		return nil
	}
	if len(existing) > 0 {
		g = l.graphs[args[0]]
	}
	switch command {
	case "DELETE":
		delete(l.graphs, args[0])
		fmt.Fprintln(l.out, "deleted "+args[0])
	case "LIST":
		names := []string{}
		for name := range l.graphs {
			names = append(names, name)
		}
		sort.Strings(names)
		fmt.Fprintf(l.out, "graphs %d\n", len(names))
		for _, name := range names {
			graph := l.graphs[name]
			fmt.Fprintf(l.out, "%s n %d m %d\n", name, graph.n, len(graph.edges()))
		}
	case "SHOW":
		fmt.Fprintf(l.out, "graph %s n %d m %d\n", args[0], g.n, len(g.edges()))
		for v := 0; v < g.n; v++ {
			fmt.Fprintf(l.out, "%d:", v)
			for w := 0; w < g.n; w++ {
				if g.has(v, w) {
					fmt.Fprintf(l.out, " %d", w)
				}
			}
			fmt.Fprintln(l.out)
		}
	case "INVARIANTS":
		data := g.invariants()
		fmt.Fprintln(l.out, "invariants "+args[0])
		fmt.Fprintln(l.out, "degrees "+integers(data.degrees))
		fmt.Fprintf(l.out, "edges %d triangles %d\n", data.edges, data.triangles)
		fmt.Fprintf(l.out, "components %d sizes %s\n", data.components, integers(data.sizes))
		fmt.Fprintf(l.out, "girth %s diameter %s radius %s\n", data.girth, data.diameter, data.radius)
		fmt.Fprintln(l.out, "bipartite "+yes(data.bipartite))
		if g.n > 12 {
			fmt.Fprintln(l.out, "clique -\nchromatic -")
		} else {
			clique := g.clique()
			chromatic, colors := g.chromatic()
			fmt.Fprintf(l.out, "clique %d %s\nchromatic %d %s\n", len(clique), integers(clique), chromatic, integers(colors))
		}
	case "REFINE":
		for _, word := range args[1:] {
			if number(word) >= g.n {
				return fmt.Errorf("bad vertices")
			}
		}
		colors, rounds := refine(g, degreeColors(g))
		for _, word := range args[1:] {
			v := number(word)
			if cellSizes(colors)[colors[v]] == 1 {
				return fmt.Errorf("singleton %d", v)
			}
			next, count := refine(g, individualize(colors, v))
			colors, rounds = next, rounds+count
		}
		fmt.Fprintf(l.out, "refine %s rounds %d cells %d\n", args[0], rounds, colorsCount(colors))
		for color := 0; color < colorsCount(colors); color++ {
			fmt.Fprintf(l.out, "%d:", color)
			for v, c := range colors {
				if c == color {
					fmt.Fprintf(l.out, " %d", v)
				}
			}
			fmt.Fprintln(l.out)
		}
	case "CANON":
		data := g.canon()
		text := data.text
		if text == "" {
			text = "-"
		}
		fmt.Fprintf(l.out, "canon %s nodes %d leaves %d\nlabels %s\nstring %s\n", args[0], data.nodes, data.leaves, integers(data.labels), text)
	case "ISO":
		b := l.graphs[args[1]]
		aData, bData := g.invariants(), b.invariants()
		message := ""
		if g.n != b.n {
			message = fmt.Sprintf("vertices %d %d", g.n, b.n)
		} else if aData.edges != bData.edges {
			message = fmt.Sprintf("edges %d %d", aData.edges, bData.edges)
		} else if compare(aData.degrees, bData.degrees) != 0 {
			message = "degrees"
		} else if aData.triangles != bData.triangles {
			message = fmt.Sprintf("triangles %d %d", aData.triangles, bData.triangles)
		} else if aData.components != bData.components {
			message = fmt.Sprintf("components %d %d", aData.components, bData.components)
		} else if aData.girth != bData.girth {
			message = "girth " + aData.girth + " " + bData.girth
		} else if aData.diameter != bData.diameter {
			message = "diameter " + aData.diameter + " " + bData.diameter
		} else if aData.bipartite != bData.bipartite {
			message = "bipartite " + yes(aData.bipartite) + " " + yes(bData.bipartite)
		} else {
			ac, ar := refine(g, degreeColors(g))
			bc, br := refine(b, degreeColors(b))
			if ar != br || compare(cellSizes(ac), cellSizes(bc)) != 0 {
				message = "refinement"
			} else if g.canon().text != b.canon().text {
				message = "canonical"
			}
		}
		if message != "" {
			fmt.Fprintln(l.out, "not isomorphic "+message)
		} else {
			a, other := g.canon(), b.canon()
			inverse := make([]int, b.n)
			for v, label := range other.labels {
				inverse[label] = v
			}
			mapping := make([]int, g.n)
			for v, label := range a.labels {
				mapping[v] = inverse[label]
			}
			fmt.Fprintln(l.out, "isomorphic\nmapping "+integers(mapping))
		}
	case "AUT":
		l.automorphisms(args[0], g)
	case "SUBISO":
		l.subiso(args[0], args[1], g, l.graphs[args[1]])
	case "CLASSIFY":
		n := number(args[0])
		if n == 0 {
			return fmt.Errorf("bad value")
		}
		if n > 5 {
			return fmt.Errorf("too large")
		}
		levels := [][]string{}
		current := map[string]bool{strings.Repeat("0", n*(n-1)/2): true}
		for m := 0; m <= n*(n-1)/2; m++ {
			level := []string{}
			for text := range current {
				level = append(level, text)
			}
			sort.Strings(level)
			levels = append(levels, level)
			next := map[string]bool{}
			for _, text := range level {
				source := newGraph(n)
				index := 0
				for a := 0; a < n; a++ {
					for b := a + 1; b < n; b++ {
						if text[index] == '1' {
							source.join(a, b)
						}
						index++
					}
				}
				for a := 0; a < n; a++ {
					for b := a + 1; b < n; b++ {
						if !source.has(a, b) {
							changed := newGraph(n)
							copy(changed.adjacent, source.adjacent)
							changed.join(a, b)
							next[changed.canon().text] = true
						}
					}
				}
			}
			current = next
		}
		total := 0
		for _, level := range levels {
			total += len(level)
		}
		fmt.Fprintf(l.out, "classify %d total %d\n", n, total)
		for m, level := range levels {
			fmt.Fprintf(l.out, "edges %d count %d", m, len(level))
			for _, text := range level {
				if text == "" {
					text = "-"
				}
				fmt.Fprint(l.out, " "+text)
			}
			fmt.Fprintln(l.out)
		}
	}
	return nil
}

type dsu struct {
	parents []int
}

func newDSU(n int) *dsu {
	d := &dsu{make([]int, n)}
	for i := range d.parents {
		d.parents[i] = i
	}
	return d
}

func (d *dsu) find(x int) int {
	if d.parents[x] != x {
		d.parents[x] = d.find(d.parents[x])
	}
	return d.parents[x]
}

func (d *dsu) union(a, b int) {
	a, b = d.find(a), d.find(b)
	if a != b {
		d.parents[b] = a
	}
}

func (d *dsu) groups() [][]int {
	groups, where := [][]int{}, map[int]int{}
	for i := range d.parents {
		root := d.find(i)
		at, exists := where[root]
		if !exists {
			at = len(groups)
			where[root] = at
			groups = append(groups, []int{})
		}
		groups[at] = append(groups[at], i)
	}
	return groups
}

func (l *lab) automorphisms(name string, g *graph) {
	data, edges := g.canon(), g.edges()
	vertices, edgeSets := newDSU(g.n), newDSU(len(edges))
	inverse := make([]int, g.n)
	for v, label := range data.labels {
		inverse[label] = v
	}
	edgeNumbers := map[pair]int{}
	for i, edge := range edges {
		edgeNumbers[edge] = i
	}
	for _, labeling := range data.best {
		sigma := make([]int, g.n)
		for v, label := range labeling {
			sigma[v] = inverse[label]
			vertices.union(v, sigma[v])
		}
		for i, edge := range edges {
			a, b := sigma[edge.a], sigma[edge.b]
			if a > b {
				a, b = b, a
			}
			edgeSets.union(i, edgeNumbers[pair{a, b}])
		}
	}
	vertexOrbits, edgeOrbits := vertices.groups(), edgeSets.groups()
	fmt.Fprintf(l.out, "aut %s order %d\nvertex orbits %d\n", name, len(data.best), len(vertexOrbits))
	for _, orbit := range vertexOrbits {
		fmt.Fprintln(l.out, "orbit "+integers(orbit))
	}
	fmt.Fprintf(l.out, "edge orbits %d\n", len(edgeOrbits))
	for _, orbit := range edgeOrbits {
		words := []string{}
		for _, index := range orbit {
			edge := edges[index]
			words = append(words, fmt.Sprintf("%d-%d", edge.a, edge.b))
		}
		fmt.Fprintln(l.out, "orbit "+strings.Join(words, " "))
	}
	fmt.Fprintf(l.out, "transitive vertex %s edge %s\n", yes(len(vertexOrbits) == 1), yes(len(edgeOrbits) == 1))
}

func (l *lab) subiso(aName, bName string, pattern, target *graph) {
	embeddings, induced := 0, 0
	type example struct {
		mapping []int
		induced bool
	}
	examples := []example{}
	mapping, used := make([]int, pattern.n), make([]bool, target.n)
	var search func(int, bool)
	search = func(v int, isInduced bool) {
		if v == pattern.n {
			embeddings++
			if isInduced {
				induced++
			}
			if len(examples) < 5 {
				examples = append(examples, example{copyInts(mapping), isInduced})
			}
			return
		}
		for w := 0; w < target.n; w++ {
			if used[w] {
				continue
			}
			valid, nextInduced := true, isInduced
			for u := 0; u < v; u++ {
				if pattern.has(u, v) && !target.has(mapping[u], w) {
					valid = false
					break
				}
				if !pattern.has(u, v) && target.has(mapping[u], w) {
					nextInduced = false
				}
			}
			if valid {
				mapping[v], used[w] = w, true
				search(v+1, nextInduced)
				used[w] = false
			}
		}
	}
	if pattern.n <= target.n {
		search(0, true)
	}
	order := len(pattern.canon().best)
	fmt.Fprintf(l.out, "subiso %s %s embeddings %d induced %d\ncopies %d induced %d\n", aName, bName, embeddings, induced, embeddings/order, induced/order)
	for _, example := range examples {
		suffix := ""
		if example.induced {
			suffix = " induced"
		}
		fmt.Fprintln(l.out, "embedding "+integers(example.mapping)+suffix)
	}
}

func main() {
	input, _ := io.ReadAll(os.Stdin)
	lines := strings.Split(string(input), "\n")
	n, _ := strconv.Atoi(lines[0])
	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()
	l := lab{graphs: map[string]*graph{}, out: out}
	for _, line := range lines[1 : n+1] {
		if err := l.command(strings.Split(line, " ")); err != nil {
			fmt.Fprintln(out, "error: "+err.Error())
		}
	}
}
