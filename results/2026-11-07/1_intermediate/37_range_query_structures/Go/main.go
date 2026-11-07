package main

import (
	"bufio"
	"cmp"
	"fmt"
	"os"
	"slices"
	"strconv"
	"strings"
)

type Kind int

const (
	SEG Kind = iota
	LAZY
	FEN
	RFEN
	SPARSE
	SQRT
	PERSIST
	GRID
)

var kindNames = [...]string{"SEG", "LAZY", "FEN", "RFEN", "SPARSE", "SQRT", "PERSIST", "GRID"}

func (k Kind) String() string { return kindNames[k] }

type Operation int

const (
	SUM Operation = iota
	MIN
	MAX
	GCD
)

var opNames = [...]string{"SUM", "MIN", "MAX", "GCD"}
var valueNames = [...]string{"sum", "min", "max", "gcd"}

func (op Operation) String() string { return opNames[op] }
func (op Operation) combine(a, b int64) int64 {
	switch op {
	case SUM:
		return a + b
	case MIN:
		return min(a, b)
	case MAX:
		return max(a, b)
	default:
		return gcd(a, b)
	}
}
func (op Operation) leaf(value int64) int64 {
	if op == GCD && value < 0 {
		return -value
	}
	return value
}
func gcd(a, b int64) int64 {
	if a < 0 {
		a = -a
	}
	if b < 0 {
		b = -b
	}
	for b != 0 {
		a, b = b, a%b
	}
	return a
}
func isqrt(n int) int {
	result := 1
	for (result+1)*(result+1) <= n {
		result++
	}
	return result
}
func joined[T ~int | ~int64](values []T) string {
	words := make([]string, len(values))
	for i, value := range values {
		words[i] = strconv.FormatInt(int64(value), 10)
	}
	return strings.Join(words, " ")
}
func total(values []int64) int64 {
	var sum int64
	for _, value := range values {
		sum += value
	}
	return sum
}

type Span struct{ left, right int }

func whole(n int) Span { return Span{0, n - 1} }
func (s Span) leaf() bool { return s.left == s.right }
func (s Span) length() int { return s.right - s.left + 1 }
func (s Span) covers(other Span) bool { return s.left <= other.left && other.right <= s.right }
func (s Span) split() (Span, Span) {
	mid := (s.left + s.right) / 2
	return Span{s.left, mid}, Span{mid + 1, s.right}
}

type NumberedSpan struct {
	node int
	span Span
}

func shape(n int) []NumberedSpan {
	nodes := make([]NumberedSpan, 0, 2*n-1)
	var visit func(int, Span)
	visit = func(node int, span Span) {
		nodes = append(nodes, NumberedSpan{node, span})
		if !span.leaf() {
			left, right := span.split()
			visit(2*node, left)
			visit(2*node+1, right)
		}
	}
	visit(1, whole(n))
	slices.SortFunc(nodes, func(a, b NumberedSpan) int { return cmp.Compare(a.node, b.node) })
	return nodes
}

type Aggregate struct{ sum, min, max int64 }

func (a Aggregate) combine(b Aggregate) Aggregate {
	return Aggregate{a.sum + b.sum, min(a.min, b.min), max(a.max, b.max)}
}
func (a Aggregate) text() string {
	return fmt.Sprintf("sum=%d min=%d max=%d", a.sum, a.min, a.max)
}

type Counts struct{ visited, covered, pushes int }
type Answer struct {
	value int64
	visited int
}
type Report struct {
	text string
	values []int64
}

func sumReport(answer Answer) Report {
	return Report{fmt.Sprintf("sum=%d visited=%d", answer.value, answer.visited), []int64{answer.value}}
}

type Segment struct {
	op Operation
	n, maxNode int
	tree []int64
}

func newSegment(values []int64, op Operation) *Segment {
	tree := &Segment{op: op, n: len(values), tree: make([]int64, 4*len(values))}
	tree.build(1, whole(len(values)), values)
	return tree
}
func (t *Segment) build(node int, span Span, values []int64) {
	t.maxNode = max(t.maxNode, node)
	if span.leaf() {
		t.tree[node] = t.op.leaf(values[span.left])
		return
	}
	left, right := span.split()
	t.build(2*node, left, values)
	t.build(2*node+1, right, values)
	t.tree[node] = t.op.combine(t.tree[2*node], t.tree[2*node+1])
}
func (t *Segment) queryAt(node int, span, wanted Span) Answer {
	if wanted.covers(span) {
		return Answer{t.tree[node], 1}
	}
	left, right := span.split()
	var answer Answer
	if wanted.right <= left.right {
		answer = t.queryAt(2*node, left, wanted)
	} else if wanted.left >= right.left {
		answer = t.queryAt(2*node+1, right, wanted)
	} else {
		a := t.queryAt(2*node, left, wanted)
		b := t.queryAt(2*node+1, right, wanted)
		answer = Answer{t.op.combine(a.value, b.value), a.visited + b.visited}
	}
	answer.visited++
	return answer
}
func (t *Segment) query(span Span) Report {
	a := t.queryAt(1, whole(t.n), span)
	return Report{fmt.Sprintf("%s=%d visited=%d", valueNames[t.op], a.value, a.visited), []int64{a.value}}
}
func (t *Segment) updateAt(node int, span Span, index int, value int64) int {
	if span.leaf() {
		t.tree[node] = t.op.leaf(value)
		return 1
	}
	left, right := span.split()
	var visited int
	if index <= left.right {
		visited = t.updateAt(2*node, left, index, value)
	} else {
		visited = t.updateAt(2*node+1, right, index, value)
	}
	t.tree[node] = t.op.combine(t.tree[2*node], t.tree[2*node+1])
	return visited + 1
}
func (t *Segment) dump() []string {
	rows := []string{fmt.Sprintf("SEG DUMP %s nodes=%d", t.op, 2*t.n-1)}
	for _, entry := range shape(t.n) {
		rows = append(rows, fmt.Sprintf("NODE %d %d %d %d", entry.node, entry.span.left, entry.span.right, t.tree[entry.node]))
	}
	return rows
}

type LazyNode struct {
	value Aggregate
	assign, add int64
	assigned bool
}
type Lazy struct {
	n int
	nodes []LazyNode
}

func newLazy(values []int64) *Lazy {
	tree := &Lazy{len(values), make([]LazyNode, 4*len(values))}
	tree.build(1, whole(len(values)), values)
	return tree
}
func (t *Lazy) build(node int, span Span, values []int64) {
	if span.leaf() {
		x := values[span.left]
		t.nodes[node].value = Aggregate{x, x, x}
		return
	}
	left, right := span.split()
	t.build(2*node, left, values)
	t.build(2*node+1, right, values)
	t.pull(node)
}
func (t *Lazy) pull(node int) {
	t.nodes[node].value = t.nodes[2*node].value.combine(t.nodes[2*node+1].value)
}
func (t *Lazy) apply(node int, span Span, value int64, assign bool) {
	current := &t.nodes[node]
	if assign {
		current.value = Aggregate{value * int64(span.length()), value, value}
	} else {
		current.value.sum += value * int64(span.length())
		current.value.min += value
		current.value.max += value
	}
	if !span.leaf() {
		if assign {
			current.assigned, current.assign, current.add = true, value, 0
		} else {
			current.add += value
		}
	}
}
func (t *Lazy) push(node int, span Span, counts *Counts) {
	current := t.nodes[node]
	if !current.assigned && current.add == 0 {
		return
	}
	counts.pushes++
	left, right := span.split()
	for _, child := range []NumberedSpan{{2 * node, left}, {2*node + 1, right}} {
		if current.assigned {
			t.apply(child.node, child.span, current.assign, true)
		}
		if current.add != 0 {
			t.apply(child.node, child.span, current.add, false)
		}
	}
	t.nodes[node].assigned, t.nodes[node].add = false, 0
}
func (t *Lazy) updateAt(node int, span, wanted Span, value int64, assign bool, counts *Counts) {
	counts.visited++
	if wanted.covers(span) {
		counts.covered++
		t.apply(node, span, value, assign)
		return
	}
	t.push(node, span, counts)
	left, right := span.split()
	if wanted.left <= left.right {
		t.updateAt(2*node, left, wanted, value, assign, counts)
	}
	if wanted.right >= right.left {
		t.updateAt(2*node+1, right, wanted, value, assign, counts)
	}
	t.pull(node)
}
func (t *Lazy) update(span Span, value int64, assign bool) Counts {
	var counts Counts
	t.updateAt(1, whole(t.n), span, value, assign, &counts)
	return counts
}
func (t *Lazy) queryAt(node int, span, wanted Span, counts *Counts) Aggregate {
	counts.visited++
	if wanted.covers(span) {
		return t.nodes[node].value
	}
	t.push(node, span, counts)
	left, right := span.split()
	if wanted.right <= left.right {
		return t.queryAt(2*node, left, wanted, counts)
	}
	if wanted.left >= right.left {
		return t.queryAt(2*node+1, right, wanted, counts)
	}
	a := t.queryAt(2*node, left, wanted, counts)
	b := t.queryAt(2*node+1, right, wanted, counts)
	return a.combine(b)
}
func (t *Lazy) query(span Span) Report {
	var counts Counts
	a := t.queryAt(1, whole(t.n), span, &counts)
	return Report{fmt.Sprintf("%s visited=%d pushes=%d", a.text(), counts.visited, counts.pushes), []int64{a.sum, a.min, a.max}}
}
func (t *Lazy) dump() []string {
	rows := []string{fmt.Sprintf("LAZY DUMP nodes=%d", 2*t.n-1)}
	for _, entry := range shape(t.n) {
		node := t.nodes[entry.node]
		assign := "-"
		if node.assigned {
			assign = strconv.FormatInt(node.assign, 10)
		}
		rows = append(rows, fmt.Sprintf("NODE %d %d %d %s assign=%s add=%d", entry.node, entry.span.left, entry.span.right, node.value.text(), assign, node.add))
	}
	return rows
}

type Bit struct{ tree []int64 }

func emptyBit(n int) Bit { return Bit{make([]int64, n+1)} }
func newBit(values []int64) Bit {
	bit := emptyBit(len(values))
	for i, value := range values {
		bit.add(i+1, value)
	}
	return bit
}
func (t *Bit) add(position int, value int64) int {
	visited := 0
	for ; position < len(t.tree); position += position & -position {
		t.tree[position] += value
		visited++
	}
	return visited
}
func (t *Bit) prefix(position int) Answer {
	var answer Answer
	for ; position > 0; position -= position & -position {
		answer.value += t.tree[position]
		answer.visited++
	}
	return answer
}
func (t *Bit) query(span Span) Answer {
	a := t.prefix(span.right + 1)
	b := t.prefix(span.left)
	return Answer{a.value - b.value, a.visited + b.visited}
}
func (t *Bit) lower(rest int64) (int, int) {
	n := len(t.tree) - 1
	step, position, visited := 1, 0, 0
	for 2*step <= n {
		step *= 2
	}
	for ; step > 0; step /= 2 {
		if position+step <= n {
			visited++
			if t.tree[position+step] < rest {
				rest -= t.tree[position+step]
				position += step
			}
		}
	}
	if position == n {
		position = -1
	}
	return position, visited
}

type Fenwick struct {
	values []int64
	bit Bit
}
type RangeFenwick struct{ first, second Bit }

func newRangeFenwick(values []int64) *RangeFenwick {
	tree := &RangeFenwick{emptyBit(len(values)), emptyBit(len(values))}
	for i, value := range values {
		difference := value
		if i > 0 {
			difference -= values[i-1]
		}
		tree.first.add(i+1, difference)
		tree.second.add(i+1, difference*int64(i))
	}
	return tree
}
func (t *RangeFenwick) add(span Span, value int64) int {
	visited := t.first.add(span.left+1, value)
	visited += t.first.add(span.right+2, -value)
	visited += t.second.add(span.left+1, value*int64(span.left))
	visited += t.second.add(span.right+2, -value*int64(span.right+1))
	return visited
}
func (t *RangeFenwick) prefix(position int) Answer {
	a := t.first.prefix(position)
	b := t.second.prefix(position)
	return Answer{int64(position)*a.value - b.value, a.visited + b.visited}
}
func (t *RangeFenwick) query(span Span) Answer {
	a := t.prefix(span.right + 1)
	b := t.prefix(span.left)
	return Answer{a.value - b.value, a.visited + b.visited}
}

type Sparse struct {
	values []int64
	minimum, maximum [][]int
	entries int
}

func newSparse(values []int64) *Sparse {
	tree := &Sparse{values: slices.Clone(values)}
	base := make([]int, len(values))
	for i := range base {
		base[i] = i
	}
	tree.minimum, tree.maximum = [][]int{base}, [][]int{slices.Clone(base)}
	tree.entries = len(values)
	for length := 2; length <= len(values); length *= 2 {
		level := len(tree.minimum)
		lows, highs := make([]int, len(values)-length+1), make([]int, len(values)-length+1)
		for i := range lows {
			a, b := tree.minimum[level-1][i], tree.minimum[level-1][i+length/2]
			lows[i] = a
			if values[a] > values[b] {
				lows[i] = b
			}
			a, b = tree.maximum[level-1][i], tree.maximum[level-1][i+length/2]
			highs[i] = a
			if values[a] < values[b] {
				highs[i] = b
			}
		}
		tree.minimum = append(tree.minimum, lows)
		tree.maximum = append(tree.maximum, highs)
		tree.entries += len(lows)
	}
	return tree
}
func (t *Sparse) query(span Span) Report {
	level, length := 0, 1
	for 2*length <= span.length() {
		level++
		length *= 2
	}
	end := span.right + 1 - length
	a, b := t.minimum[level][span.left], t.minimum[level][end]
	low := a
	if t.values[a] > t.values[b] {
		low = b
	}
	a, b = t.maximum[level][span.left], t.maximum[level][end]
	high := a
	if t.values[a] < t.values[b] {
		high = b
	}
	return Report{fmt.Sprintf("min=%d minpos=%d max=%d maxpos=%d level=%d", t.values[low], low, t.values[high], high, level), []int64{t.values[low], t.values[high]}}
}
func (t *Sparse) dump() []string {
	rows := []string{fmt.Sprintf("SPARSE DUMP levels=%d", len(t.minimum))}
	for level := range t.minimum {
		rows = append(rows, fmt.Sprintf("MIN %d %s", level, joined(t.minimum[level])), fmt.Sprintf("MAX %d %s", level, joined(t.maximum[level])))
	}
	return rows
}

type Sqrt struct {
	block int
	values, tags, sums []int64
}

func newSqrt(values []int64, block int) *Sqrt {
	blocks := (len(values) + block - 1) / block
	tree := &Sqrt{block, slices.Clone(values), make([]int64, blocks), make([]int64, blocks)}
	for i, value := range values {
		tree.sums[i/block] += value
	}
	return tree
}
func (t *Sqrt) split(span Span) (cells, blocks []int) {
	first, last := span.left/t.block, span.right/t.block
	for i := span.left; i <= span.right; i++ {
		if i/t.block == first || i/t.block == last {
			cells = append(cells, i)
		}
	}
	for block := first + 1; block < last; block++ {
		blocks = append(blocks, block)
	}
	return
}
func (t *Sqrt) add(span Span, value int64) (int, int) {
	cells, blocks := t.split(span)
	for _, i := range cells {
		t.values[i] += value
		t.sums[i/t.block] += value
	}
	for _, block := range blocks {
		t.tags[block] += value
		t.sums[block] += value * int64(t.block)
	}
	return len(blocks), len(cells)
}
func (t *Sqrt) query(span Span) Report {
	cells, blocks := t.split(span)
	var sum int64
	for _, i := range cells {
		sum += t.values[i] + t.tags[i/t.block]
	}
	for _, block := range blocks {
		sum += t.sums[block]
	}
	return Report{fmt.Sprintf("sum=%d whole=%d cells=%d", sum, len(blocks), len(cells)), []int64{sum}}
}
func (t *Sqrt) dump() []string {
	rows := []string{fmt.Sprintf("SQRT DUMP block=%d blocks=%d", t.block, len(t.tags))}
	for block := range t.tags {
		first, end := block*t.block, min((block+1)*t.block, len(t.values))
		rows = append(rows, fmt.Sprintf("BLOCK %d %d %d add=%d sum=%d %s", block, first, end-1, t.tags[block], t.sums[block], joined(t.values[first:end])))
	}
	return rows
}

type PersistentNode struct {
	value int64
	left, right *PersistentNode
}

func buildNode(values []int64, span Span, created *int) *PersistentNode {
	*created += 1
	if span.leaf() {
		var value int64
		if values != nil {
			value = values[span.left]
		}
		return &PersistentNode{value: value}
	}
	leftSpan, rightSpan := span.split()
	left := buildNode(values, leftSpan, created)
	right := buildNode(values, rightSpan, created)
	return &PersistentNode{left.value + right.value, left, right}
}
func setNode(source *PersistentNode, span Span, index int, value int64, increment bool, created *int) *PersistentNode {
	*created += 1
	node := *source
	if span.leaf() {
		if increment {
			node.value += value
		} else {
			node.value = value
		}
	} else {
		left, right := span.split()
		if index <= left.right {
			node.left = setNode(node.left, left, index, value, increment, created)
		} else {
			node.right = setNode(node.right, right, index, value, increment, created)
		}
		node.value = node.left.value + node.right.value
	}
	return &node
}
func (t *PersistentNode) query(span, wanted Span) Answer {
	if wanted.covers(span) {
		return Answer{t.value, 1}
	}
	left, right := span.split()
	var answer Answer
	if wanted.right <= left.right {
		answer = t.left.query(left, wanted)
	} else if wanted.left >= right.left {
		answer = t.right.query(right, wanted)
	} else {
		a := t.left.query(left, wanted)
		b := t.right.query(right, wanted)
		answer = Answer{a.value + b.value, a.visited + b.visited}
	}
	answer.visited++
	return answer
}

type Persistent struct {
	n int
	roots, prefixes []*PersistentNode
	values []int64
	positionNodes, valueNodes int
}

func newPersistent(values []int64) *Persistent {
	tree := &Persistent{n: len(values), values: slices.Clone(values)}
	tree.roots = []*PersistentNode{buildNode(values, whole(len(values)), &tree.positionNodes)}
	slices.Sort(tree.values)
	tree.values = slices.Compact(tree.values)
	span := whole(len(tree.values))
	tree.prefixes = []*PersistentNode{buildNode(nil, span, &tree.valueNodes)}
	for _, value := range values {
		rank, _ := slices.BinarySearch(tree.values, value)
		root := setNode(tree.prefixes[len(tree.prefixes)-1], span, rank, 1, true, &tree.valueNodes)
		tree.prefixes = append(tree.prefixes, root)
	}
	return tree
}
func (t *Persistent) set(version, index int, value int64) (int, int) {
	before, next := t.positionNodes, len(t.roots)
	root := setNode(t.roots[version], whole(t.n), index, value, false, &t.positionNodes)
	t.roots = append(t.roots, root)
	return next, t.positionNodes - before
}
func (t *Persistent) query(version int, span Span) Report {
	return sumReport(t.roots[version].query(whole(t.n), span))
}
func (t *Persistent) kth(span Span, k int64) Answer {
	u, w := t.prefixes[span.right+1], t.prefixes[span.left]
	position, visited := whole(len(t.values)), 1
	for !position.leaf() {
		left, right := position.split()
		count := u.left.value - w.left.value
		if k <= count {
			u, w, position = u.left, w.left, left
		} else {
			k -= count
			u, w, position = u.right, w.right, right
		}
		visited++
	}
	return Answer{t.values[position.left], visited}
}

type Grid struct {
	height, width int
	tree [][]int64
}

func newGrid(height, width int, values []int64) *Grid {
	grid := &Grid{height, width, make([][]int64, height+1)}
	for i := range grid.tree {
		grid.tree[i] = make([]int64, width+1)
	}
	for i, value := range values {
		grid.add(i/width, i%width, value)
	}
	return grid
}
func (g *Grid) cell(row, col int) error {
	if row < 0 || row >= g.height || col < 0 || col >= g.width {
		return fmt.Errorf("BAD CELL %d %d", row, col)
	}
	return nil
}
func (g *Grid) add(row, col int, value int64) int {
	visited := 0
	for y := row + 1; y <= g.height; y += y & -y {
		for x := col + 1; x <= g.width; x += x & -x {
			g.tree[y][x] += value
			visited++
		}
	}
	return visited
}
func (g *Grid) prefix(row, col int) Answer {
	var answer Answer
	for y := row; y > 0; y -= y & -y {
		for x := col; x > 0; x -= x & -x {
			answer.value += g.tree[y][x]
			answer.visited++
		}
	}
	return answer
}
func (g *Grid) query(row, col, bottom, right int) Answer {
	a := g.prefix(bottom+1, right+1)
	b := g.prefix(row, right+1)
	c := g.prefix(bottom+1, col)
	d := g.prefix(row, col)
	return Answer{a.value - b.value - c.value + d.value, a.visited + b.visited + c.visited + d.visited}
}
func (g *Grid) dump() []string {
	rows := []string{fmt.Sprintf("GRID DUMP rows=%d cols=%d", g.height, g.width)}
	for row := 1; row <= g.height; row++ {
		rows = append(rows, fmt.Sprintf("ROW %d %s", row, joined(g.tree[row][1:])))
	}
	return rows
}

type Lab struct {
	values, original []int64
	seg *Segment
	lazy *Lazy
	fen *Fenwick
	rfen *RangeFenwick
	sparse *Sparse
	sqrt *Sqrt
	persist *Persistent
	grid *Grid
}

func newLab(values []int64) *Lab {
	return &Lab{values: values, original: slices.Clone(values)}
}
func (l *Lab) has(kind Kind) bool {
	switch kind {
	case SEG:
		return l.seg != nil
	case LAZY:
		return l.lazy != nil
	case FEN:
		return l.fen != nil
	case RFEN:
		return l.rfen != nil
	case SPARSE:
		return l.sparse != nil
	case SQRT:
		return l.sqrt != nil
	case PERSIST:
		return l.persist != nil
	default:
		return l.grid != nil
	}
}
func (l *Lab) index(index int) error {
	if index < 0 || index >= len(l.values) {
		return fmt.Errorf("BAD INDEX %d", index)
	}
	return nil
}
func (l *Lab) checkRange(span Span) error {
	if err := l.index(span.left); err != nil {
		return err
	}
	if err := l.index(span.right); err != nil {
		return err
	}
	if span.left > span.right {
		return fmt.Errorf("BAD RANGE %d %d", span.left, span.right)
	}
	return nil
}
func (l *Lab) version(version int) error {
	if version < 0 || version >= len(l.persist.roots) {
		return fmt.Errorf("BAD VERSION %d", version)
	}
	return nil
}
func (l *Lab) build(kind Kind, op Operation, block int) string {
	n := len(l.values)
	switch kind {
	case SEG:
		l.seg = newSegment(l.values, op)
		return fmt.Sprintf("SEG BUILD %s nodes=%d maxnode=%d root=%d", op, 2*n-1, l.seg.maxNode, l.seg.tree[1])
	case LAZY:
		l.lazy = newLazy(l.values)
		return fmt.Sprintf("LAZY BUILD nodes=%d %s", 2*n-1, l.lazy.nodes[1].value.text())
	case FEN:
		l.fen = &Fenwick{slices.Clone(l.values), newBit(l.values)}
		return fmt.Sprintf("FEN BUILD n=%d total=%d", n, total(l.values))
	case RFEN:
		l.rfen = newRangeFenwick(l.values)
		return fmt.Sprintf("RFEN BUILD n=%d total=%d", n, total(l.values))
	case SPARSE:
		l.sparse = newSparse(l.values)
		return fmt.Sprintf("SPARSE BUILD levels=%d entries=%d", len(l.sparse.minimum), l.sparse.entries)
	case SQRT:
		l.sqrt = newSqrt(l.values, block)
		return fmt.Sprintf("SQRT BUILD block=%d blocks=%d", block, len(l.sqrt.tags))
	case PERSIST:
		l.persist = newPersistent(l.values)
		return fmt.Sprintf("PERSIST BUILD nodes=%d distinct=%d valuenodes=%d", l.persist.positionNodes, len(l.persist.values), l.persist.valueNodes)
	}
	panic("unreachable array build")
}
func (l *Lab) query(kind Kind, version int, span Span) Report {
	switch kind {
	case SEG:
		return l.seg.query(span)
	case LAZY:
		return l.lazy.query(span)
	case FEN:
		return sumReport(l.fen.bit.query(span))
	case RFEN:
		return sumReport(l.rfen.query(span))
	case SPARSE:
		return l.sparse.query(span)
	case SQRT:
		return l.sqrt.query(span)
	case PERSIST:
		return l.persist.query(version, span)
	}
	panic("unreachable array query")
}
func (l *Lab) dump(kind Kind) []string {
	switch kind {
	case SEG:
		return l.seg.dump()
	case LAZY:
		return l.lazy.dump()
	case FEN:
		return []string{fmt.Sprintf("FEN DUMP n=%d", len(l.values)), "T " + joined(l.fen.bit.tree[1:])}
	case RFEN:
		return []string{fmt.Sprintf("RFEN DUMP n=%d", len(l.values)), "B1 " + joined(l.rfen.first.tree[1:]), "B2 " + joined(l.rfen.second.tree[1:])}
	case SPARSE:
		return l.sparse.dump()
	case SQRT:
		return l.sqrt.dump()
	case GRID:
		return l.grid.dump()
	}
	panic("unreachable dump")
}
func (l *Lab) check(span Span) []string {
	aggregate := Aggregate{0, l.values[span.left], l.values[span.left]}
	var common int64
	for _, value := range l.values[span.left : span.right+1] {
		aggregate.sum += value
		aggregate.min = min(aggregate.min, value)
		aggregate.max = max(aggregate.max, value)
		common = gcd(common, value)
	}
	rows := []string{fmt.Sprintf("CHECK %d %d %s gcd=%d", span.left, span.right, aggregate.text(), common)}
	ok, diff := 0, 0
	for kind := SEG; kind < GRID; kind++ {
		if !l.has(kind) {
			continue
		}
		expected := []int64{aggregate.sum}
		switch kind {
		case SEG:
			expected[0] = []int64{aggregate.sum, aggregate.min, aggregate.max, common}[l.seg.op]
		case LAZY:
			expected = []int64{aggregate.sum, aggregate.min, aggregate.max}
		case SPARSE:
			expected = []int64{aggregate.min, aggregate.max}
		}
		version := 0
		if kind == PERSIST {
			version = len(l.persist.roots) - 1
		}
		answer := l.query(kind, version, span)
		verdict := "DIFF"
		if slices.Equal(answer.values, expected) {
			verdict = "OK"
			ok++
		} else {
			diff++
		}
		prefix := ""
		if kind == PERSIST {
			prefix = fmt.Sprintf("version=%d ", version)
		}
		rows = append(rows, fmt.Sprintf("%s %s %s%s", kind, verdict, prefix, answer.text))
	}
	return append(rows, fmt.Sprintf("RESULT ok=%d diff=%d", ok, diff))
}
func (l *Lab) mo(queries []Span) []string {
	blockSize := isqrt(len(l.values))
	order := make([]int, len(queries))
	for i := range order {
		order[i] = i
	}
	slices.SortFunc(order, func(a, b int) int {
		first, second := queries[a], queries[b]
		block := first.left / blockSize
		if compared := cmp.Compare(block, second.left/blockSize); compared != 0 {
			return compared
		}
		compared := cmp.Compare(first.right, second.right)
		if compared != 0 {
			if block%2 == 1 {
				return -compared
			}
			return compared
		}
		return cmp.Compare(a, b)
	})
	unique := slices.Clone(l.values)
	slices.Sort(unique)
	unique = slices.Compact(unique)
	ranks := make([]int, len(l.values))
	for i, value := range l.values {
		ranks[i], _ = slices.BinarySearch(unique, value)
	}
	frequencies, answers := make([]int, len(unique)), make([]int, len(queries))
	left, right, moves, distinct := 0, 0, 0, 0
	for _, index := range order {
		span := queries[index]
		end := span.right + 1
		moves += max(left, span.left) - min(left, span.left) + max(right, end) - min(right, end)
		for left > span.left {
			left--
			rank := ranks[left]
			if frequencies[rank] == 0 {
				distinct++
			}
			frequencies[rank]++
		}
		for right < end {
			rank := ranks[right]
			if frequencies[rank] == 0 {
				distinct++
			}
			frequencies[rank]++
			right++
		}
		for left < span.left {
			rank := ranks[left]
			frequencies[rank]--
			if frequencies[rank] == 0 {
				distinct--
			}
			left++
		}
		for right > end {
			right--
			rank := ranks[right]
			frequencies[rank]--
			if frequencies[rank] == 0 {
				distinct--
			}
		}
		answers[index] = distinct
	}
	numbers := make([]int, len(order))
	for i, index := range order {
		numbers[i] = index + 1
	}
	rows := []string{fmt.Sprintf("MO queries=%d block=%d moves=%d", len(queries), blockSize, moves), "ORDER " + joined(numbers)}
	for i, span := range queries {
		rows = append(rows, fmt.Sprintf("ANSWER %d %d %d distinct=%d", i+1, span.left, span.right, answers[i]))
	}
	return rows
}
func (l *Lab) execute(line string) ([]string, error) {
	words := strings.Fields(line)
	number := func(index int) int64 { value, _ := strconv.ParseInt(words[index], 10, 64); return value }
	index := func(i int) int { return int(number(i)) }
	switch words[0] {
	case "LOAD":
		removed := 0
		for kind := SEG; kind < GRID; kind++ {
			if l.has(kind) {
				removed++
			}
		}
		values := make([]int64, len(words)-1)
		for i := range values {
			values[i] = number(i + 1)
		}
		grid := l.grid
		*l = *newLab(values)
		l.grid = grid
		return []string{fmt.Sprintf("LOAD n=%d removed=%d", len(values), removed)}, nil
	case "RESET":
		l.values = slices.Clone(l.original)
		op, block, rebuilt := SUM, 0, 0
		if l.seg != nil {
			op = l.seg.op
		}
		if l.sqrt != nil {
			block = l.sqrt.block
		}
		for kind := SEG; kind < GRID; kind++ {
			if l.has(kind) {
				l.build(kind, op, block)
				rebuilt++
			}
		}
		return []string{fmt.Sprintf("RESET rebuilt=%d", rebuilt)}, nil
	case "ARRAY", "CHECK":
		span := Span{index(1), index(2)}
		if err := l.checkRange(span); err != nil {
			return nil, err
		}
		if words[0] == "CHECK" {
			return l.check(span), nil
		}
		return []string{fmt.Sprintf("ARRAY %d %d %s", span.left, span.right, joined(l.values[span.left:span.right+1]))}, nil
	case "MO":
		queries := make([]Span, 0, (len(words)-1)/2)
		for i := 1; i < len(words); i += 2 {
			span := Span{index(i), index(i + 1)}
			if err := l.checkRange(span); err != nil {
				return nil, err
			}
			queries = append(queries, span)
		}
		return l.mo(queries), nil
	}
	kind := Kind(slices.Index(kindNames[:], words[0]))
	action := words[1]
	if action == "BUILD" {
		op, block := SUM, 0
		if kind == SEG {
			found := slices.Index(opNames[:], words[2])
			if found < 0 {
				return nil, fmt.Errorf("BAD OP %s", words[2])
			}
			op = Operation(found)
		}
		if kind == SQRT {
			block = isqrt(len(l.values))
			if len(words) == 3 {
				block = index(2)
			}
			if block > len(l.values) {
				return nil, fmt.Errorf("BAD BLOCK %d", block)
			}
		}
		if kind == GRID {
			height, width := index(2), index(3)
			if len(words)-4 != height*width {
				return nil, fmt.Errorf("BAD COUNT %d %d", len(words)-4, height*width)
			}
			values := make([]int64, len(words)-4)
			for i := range values {
				values[i] = number(i + 4)
			}
			l.grid = newGrid(height, width, values)
			return []string{fmt.Sprintf("GRID BUILD rows=%d cols=%d total=%d", height, width, total(values))}, nil
		}
		return []string{l.build(kind, op, block)}, nil
	}
	if !l.has(kind) {
		return nil, fmt.Errorf("NOT BUILT %s", kind)
	}
	if action == "DUMP" {
		return l.dump(kind), nil
	}
	if kind == GRID {
		row, col := index(2), index(3)
		if err := l.grid.cell(row, col); err != nil {
			return nil, err
		}
		if action == "ADD" {
			value := number(4)
			visited := l.grid.add(row, col, value)
			return []string{fmt.Sprintf("GRID ADD %d %d %d visited=%d", row, col, value, visited)}, nil
		}
		bottom, right := index(4), index(5)
		if err := l.grid.cell(bottom, right); err != nil {
			return nil, err
		}
		if row > bottom || col > right {
			return nil, fmt.Errorf("BAD RECT %d %d %d %d", row, col, bottom, right)
		}
		answer := l.grid.query(row, col, bottom, right)
		return []string{fmt.Sprintf("GRID SUM %d %d %d %d sum=%d visited=%d", row, col, bottom, right, answer.value, answer.visited)}, nil
	}
	if kind == PERSIST {
		if action == "NODES" {
			return []string{fmt.Sprintf("PERSIST NODES versions=%d position=%d value=%d", len(l.persist.roots), l.persist.positionNodes, l.persist.valueNodes)}, nil
		}
		if action == "KTH" {
			span, k := Span{index(2), index(3)}, number(4)
			if err := l.checkRange(span); err != nil {
				return nil, err
			}
			if k < 1 || k > int64(span.length()) {
				return nil, fmt.Errorf("BAD K %d", k)
			}
			answer := l.persist.kth(span, k)
			return []string{fmt.Sprintf("PERSIST KTH %d %d %d value=%d visited=%d", span.left, span.right, k, answer.value, answer.visited)}, nil
		}
		version := index(2)
		if err := l.version(version); err != nil {
			return nil, err
		}
		position := index(3)
		if action == "SET" {
			if err := l.index(position); err != nil {
				return nil, err
			}
			value := number(4)
			next, created := l.persist.set(version, position, value)
			return []string{fmt.Sprintf("PERSIST SET %d %d %d version=%d created=%d", version, position, value, next, created)}, nil
		}
		span := Span{position, index(4)}
		if err := l.checkRange(span); err != nil {
			return nil, err
		}
		return []string{fmt.Sprintf("PERSIST QUERY %d %d %d %s", version, span.left, span.right, l.persist.query(version, span).text)}, nil
	}
	if kind == FEN && action == "LOWER" {
		for i, value := range l.fen.values {
			if value < 0 {
				return nil, fmt.Errorf("NEGATIVE %d", i)
			}
		}
		k := number(2)
		position, visited := l.fen.bit.lower(k)
		answer := "none"
		if position >= 0 {
			answer = strconv.Itoa(position)
		}
		return []string{fmt.Sprintf("FEN LOWER %d index=%s visited=%d", k, answer, visited)}, nil
	}
	if kind == SEG && action == "UPDATE" {
		position := index(2)
		if err := l.index(position); err != nil {
			return nil, err
		}
		value := number(3)
		visited := l.seg.updateAt(1, whole(len(l.values)), position, value)
		l.values[position] = value
		return []string{fmt.Sprintf("SEG UPDATE %d %d root=%d visited=%d", position, value, l.seg.tree[1], visited)}, nil
	}
	if kind == FEN && (action == "ADD" || action == "PREFIX") {
		position := index(2)
		if err := l.index(position); err != nil {
			return nil, err
		}
		if action == "ADD" {
			value := number(3)
			l.values[position] += value
			l.fen.values[position] += value
			visited := l.fen.bit.add(position+1, value)
			return []string{fmt.Sprintf("FEN ADD %d %d visited=%d", position, value, visited)}, nil
		}
		answer := l.fen.bit.prefix(position + 1)
		return []string{fmt.Sprintf("FEN PREFIX %d sum=%d visited=%d", position, answer.value, answer.visited)}, nil
	}
	span := Span{index(2), index(3)}
	if err := l.checkRange(span); err != nil {
		return nil, err
	}
	if action == "ADD" || action == "ASSIGN" {
		value, assign := number(4), action == "ASSIGN"
		var details string
		switch kind {
		case LAZY:
			counts := l.lazy.update(span, value, assign)
			details = fmt.Sprintf("visited=%d covered=%d pushes=%d", counts.visited, counts.covered, counts.pushes)
		case RFEN:
			details = fmt.Sprintf("visited=%d", l.rfen.add(span, value))
		case SQRT:
			whole, cells := l.sqrt.add(span, value)
			details = fmt.Sprintf("whole=%d cells=%d", whole, cells)
		}
		for i := span.left; i <= span.right; i++ {
			if assign {
				l.values[i] = value
			} else {
				l.values[i] += value
			}
		}
		return []string{fmt.Sprintf("%s %s %d %d %d %s", kind, action, span.left, span.right, value, details)}, nil
	}
	answer := l.query(kind, 0, span)
	return []string{fmt.Sprintf("%s %s %d %d %s", kind, action, span.left, span.right, answer.text)}, nil
}

func main() {
	input := bufio.NewScanner(os.Stdin)
	input.Buffer(make([]byte, 4096), 30004)
	if !input.Scan() {
		return
	}
	n, _ := strconv.Atoi(input.Text())
	if !input.Scan() {
		return
	}
	words := strings.Fields(input.Text())
	values := make([]int64, n)
	for i := range values {
		values[i], _ = strconv.ParseInt(words[i], 10, 64)
	}
	lab := newLab(values)
	if !input.Scan() {
		return
	}
	commands, _ := strconv.Atoi(input.Text())
	output := bufio.NewWriter(os.Stdout)
	defer output.Flush()
	for i := 0; i < commands && input.Scan(); i++ {
		rows, err := lab.execute(input.Text())
		if err != nil {
			fmt.Fprintln(output, "ERROR", err)
		} else {
			for _, row := range rows {
				fmt.Fprintln(output, row)
			}
		}
		output.Flush()
	}
}
