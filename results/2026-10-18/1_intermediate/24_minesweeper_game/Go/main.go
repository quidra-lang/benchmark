package main

import (
	"bufio"
	"fmt"
	"math/bits"
	"os"
	"slices"
	"strconv"
	"strings"
)

var output = bufio.NewWriter(os.Stdout)
var commandArgs = map[string]int{
	"NEW": 4, "PRESET": 2, "LAYOUT": 2, "SAFETY": 1, "RESTART": 0,
	"REVEAL": 2, "FLAG": 2, "UNFLAG": 2, "QUESTION": 2, "CHORD": 2,
	"UNDO": 0, "SHOW": 0, "STATUS": 0, "CELL": 2, "HISTORY": 1,
	"REPLAY": 1, "HINT": 0, "AUTO": 0, "ANALYZE": 0, "PROB": 2,
	"FRONTIER": 0, "SOLVE": 0, "BOARDINFO": 0, "STATS": 0,
}

type State string
type Safety string
type Mark uint8
type MoveKind string

const (
	ready State = "ready"
	playing State = "playing"
	won State = "won"
	lost State = "lost"
)

const (
	blockSafety Safety = "block"
	cellSafety Safety = "cell"
	noSafety Safety = "none"
)

const (
	unmarked Mark = iota
	flagged
	questioned
)

const (
	revealMove MoveKind = "reveal"
	flagMove MoveKind = "flag"
	unflagMove MoveKind = "unflag"
	questionMove MoveKind = "question"
	chordMove MoveKind = "chord"
	autoReveal MoveKind = "auto-reveal"
	autoFlag MoveKind = "auto-flag"
	guessMove MoveKind = "guess"
)

func line(format string, args ...any) { fmt.Fprintf(output, format+"\n", args...) }
func (s State) finished() bool { return s == won || s == lost }

type Move struct {
	kind MoveKind
	cell int
}

type Snapshot struct {
	name string
	revealed []bool
	marks []Mark
	moves int
}

type Game struct {
	width, height, mineCount int
	seed int64
	determined bool
	mine, revealed []bool
	numbers []int
	marks []Mark
	neighbors [][]int
	state State
	exploded int
	moves []Move
	undo []Snapshot
}

func newGame(width, height, mines int, seed int64) *Game {
	cells := width * height
	game := &Game{
		width: width, height: height, mineCount: mines, seed: seed,
		mine: make([]bool, cells), revealed: make([]bool, cells), numbers: make([]int, cells),
		marks: make([]Mark, cells), neighbors: make([][]int, cells), state: ready, exploded: -1,
	}
	for cell := 0; cell < cells; cell++ {
		x, y := cell%width, cell/width
		for dy := -1; dy <= 1; dy++ {
			for dx := -1; dx <= 1; dx++ {
				if (dx != 0 || dy != 0) && x+dx >= 0 && x+dx < width && y+dy >= 0 && y+dy < height {
					game.neighbors[cell] = append(game.neighbors[cell], (y+dy)*width+x+dx)
				}
			}
		}
	}
	return game
}

func (g *Game) cells() int { return g.width * g.height }
func (g *Game) safeCells() int { return g.cells() - g.mineCount }
func (g *Game) coord(cell int) string { return fmt.Sprintf("%d,%d", cell%g.width, cell/g.width) }
func (g *Game) unknown(cell int) bool { return !g.revealed[cell] && g.marks[cell] != flagged }

func (g *Game) remaining() int {
	remaining := g.mineCount
	for _, mark := range g.marks {
		if mark == flagged { remaining-- }
	}
	return remaining
}

func (g *Game) opened() int {
	count := 0
	for _, open := range g.revealed {
		if open { count++ }
	}
	return count
}

func (g *Game) clone(keepMoves bool) *Game {
	copy := *g
	copy.mine = slices.Clone(g.mine)
	copy.numbers = slices.Clone(g.numbers)
	copy.revealed = slices.Clone(g.revealed)
	copy.marks = slices.Clone(g.marks)
	copy.moves = nil
	if keepMoves { copy.moves = slices.Clone(g.moves) }
	copy.undo = nil
	return &copy
}

func (g *Game) restart() {
	clear(g.revealed)
	clear(g.marks)
	g.moves = nil
	g.undo = nil
	g.exploded = -1
	g.state = ready
	if g.determined { g.state = playing }
}

func (g *Game) numberBoard() {
	clear(g.numbers)
	for cell, neighbors := range g.neighbors {
		for _, next := range neighbors {
			if g.mine[next] { g.numbers[cell]++ }
		}
	}
}

func abs(n int) int {
	if n < 0 { return -n }
	return n
}

func (g *Game) placeMines(first int, safety Safety) {
	sx, sy := first%g.width, first/g.width
	var candidates []int
	for cell := 0; cell < g.cells(); cell++ {
		x, y := cell%g.width, cell/g.width
		if safety == noSafety || safety == cellSafety && cell != first || safety == blockSafety && (abs(x-sx) >= 2 || abs(y-sy) >= 2) {
			candidates = append(candidates, cell)
		}
	}
	state := g.seed
	for i := 0; i < g.mineCount; i++ {
		state = 48271 * state % 2147483647
		index := int(state % int64(len(candidates)))
		g.mine[candidates[index]] = true
		candidates = slices.Delete(candidates, index, index+1)
	}
	g.numberBoard()
	g.determined = true
	g.state = playing
}

func (g *Game) reveal(cell int, safety Safety) int {
	if !g.determined { g.placeMines(cell, safety) }
	if g.mine[cell] {
		g.state, g.exploded = lost, cell
		return 0
	}
	queue := []int{cell}
	g.revealed[cell], g.marks[cell] = true, unmarked
	for head := 0; head < len(queue); head++ {
		current := queue[head]
		if g.numbers[current] != 0 { continue }
		for _, next := range g.neighbors[current] {
			if !g.unknown(next) { continue }
			g.revealed[next], g.marks[next] = true, unmarked
			queue = append(queue, next)
		}
	}
	return len(queue)
}

func (g *Game) chord(cell int, safety Safety) int {
	opened := 0
	for _, next := range g.neighbors[cell] {
		if g.unknown(next) { opened += g.reveal(next, safety) }
		if g.state == lost { break }
	}
	return opened
}

func (g *Game) checkWin() {
	if g.state != playing || g.opened() != g.safeCells() { return }
	g.state = won
	for cell, mine := range g.mine {
		if mine { g.marks[cell] = flagged }
	}
}

func (g *Game) show() {
	for y := 0; y < g.height; y++ {
		row := make([]byte, g.width)
		for x := 0; x < g.width; x++ {
			cell := y*g.width+x
			switch {
			case g.state == lost && g.mine[cell]:
				row[x] = '*'
				if g.marks[cell] == flagged { row[x] = 'F' }
				if cell == g.exploded { row[x] = '!' }
			case g.state == lost && g.marks[cell] == flagged:
				row[x] = 'X'
			case g.revealed[cell]:
				row[x] = '.'
				if g.numbers[cell] > 0 { row[x] = byte('0' + g.numbers[cell]) }
			case g.marks[cell] == flagged:
				row[x] = 'F'
			case g.marks[cell] == questioned:
				row[x] = '?'
			default:
				row[x] = '#'
			}
		}
		line("%s", row)
	}
}

func (g *Game) endingOutput() {
	if g.state == lost {
		line("boom %s", g.coord(g.exploded))
		g.show()
	} else if g.state == won {
		line("win moves %d", len(g.moves))
	}
}

type Constraint struct {
	cell, remaining int
	unknown []int
}

func (g *Game) constraints() []Constraint {
	var result []Constraint
	for cell := 0; cell < g.cells(); cell++ {
		if !g.revealed[cell] || g.numbers[cell] == 0 { continue }
		c := Constraint{cell: cell, remaining: g.numbers[cell]}
		for _, next := range g.neighbors[cell] {
			if g.marks[next] == flagged { c.remaining-- }
			if g.unknown(next) { c.unknown = append(c.unknown, next) }
		}
		if len(c.unknown) > 0 { result = append(result, c) }
	}
	return result
}

type Reason struct {
	kind string
	a, b int
}

func (r Reason) text(g *Game) string {
	switch r.kind {
	case "single":
		return "single " + g.coord(r.a)
	case "subset":
		return "subset " + g.coord(r.a) + " " + g.coord(r.b)
	default:
		return "count"
	}
}

type Deduction struct {
	safe, mines []Reason
	any bool
}

func (d *Deduction) add(safe bool, cell int, reason Reason) {
	side := d.mines
	if safe { side = d.safe }
	if side[cell].kind == "" { side[cell] = reason }
	d.any = true
}

func (g *Game) deduce() Deduction {
	list := g.constraints()
	result := Deduction{safe: make([]Reason, g.cells()), mines: make([]Reason, g.cells())}
	for rule := 1; rule <= 2; rule++ {
		for _, c := range list {
			target := 0
			if rule == 2 { target = len(c.unknown) }
			if c.remaining != target { continue }
			for _, cell := range c.unknown { result.add(rule == 1, cell, Reason{kind: "single", a: c.cell}) }
		}
		if result.any { return result }
	}
	at := make([]int, g.cells())
	for i := range at { at[i] = -1 }
	for i, c := range list { at[c.cell] = i }
	for _, a := range list {
		ax, ay := a.cell%g.width, a.cell/g.width
		for y := max(0, ay-2); y <= min(g.height-1, ay+2); y++ {
			for x := max(0, ax-2); x <= min(g.width-1, ax+2); x++ {
				index := at[y*g.width+x]
				if index < 0 { continue }
				b := list[index]
				if len(a.unknown) >= len(b.unknown) { continue }
				subset := true
				for _, cell := range a.unknown {
					if !slices.Contains(b.unknown, cell) { subset = false; break }
				}
				if !subset { continue }
				difference := b.remaining - a.remaining
				if difference != 0 && difference != len(b.unknown)-len(a.unknown) { continue }
				for _, cell := range b.unknown {
					if !slices.Contains(a.unknown, cell) { result.add(difference == 0, cell, Reason{kind: "subset", a: a.cell, b: b.cell}) }
				}
			}
		}
	}
	if result.any { return result }
	if g.state == playing && g.remaining() == 0 {
		for cell := 0; cell < g.cells(); cell++ {
			if g.unknown(cell) { result.add(true, cell, Reason{kind: "count"}) }
		}
	}
	return result
}

func (g *Game) hint() {
	result := g.deduce()
	for side, reasons := range [][]Reason{result.safe, result.mines} {
		for cell, reason := range reasons {
			if reason.kind != "" {
				line("hint %s %s by %s", []string{"safe", "mine"}[side], g.coord(cell), reason.text(g))
				return
			}
		}
	}
	line("hint none")
}

type Component struct {
	cells []int
	configs int64
	minimum, maximum int
}

type Frontier struct {
	constraints []Constraint
	componentOf []int
	components []Component
	ways []int64
}

func root(parent []int, cell int) int {
	for parent[cell] != cell {
		parent[cell] = parent[parent[cell]]
		cell = parent[cell]
	}
	return cell
}

func makeFrontier(g *Game) *Frontier {
	f := &Frontier{constraints: g.constraints(), componentOf: make([]int, g.cells()), ways: make([]int64, g.cells())}
	parent, ids := make([]int, g.cells()), make([]int, g.cells())
	present := make([]bool, g.cells())
	for i := range parent { parent[i], ids[i], f.componentOf[i] = i, -1, -1 }
	for _, c := range f.constraints {
		for _, cell := range c.unknown {
			present[cell] = true
			left, right := root(parent, cell), root(parent, c.unknown[0])
			parent[left] = right
		}
	}
	for cell, exists := range present {
		if !exists { continue }
		representative := root(parent, cell)
		if ids[representative] < 0 {
			ids[representative] = len(f.components)
			f.components = append(f.components, Component{})
		}
		id := ids[representative]
		f.componentOf[cell] = id
		f.components[id].cells = append(f.components[id].cells, cell)
	}
	return f
}

type Restriction struct {
	mask uint32
	target int
}

type Search struct {
	size int
	constraints []Restriction
	configs int64
	minimum, maximum int
	ways []int64
}

func (s *Search) visit(depth int, mines uint32) {
	assigned := (uint32(1) << depth) - 1
	for _, c := range s.constraints {
		used := bits.OnesCount32(c.mask & mines)
		left := bits.OnesCount32(c.mask & ^assigned)
		if used > c.target || used+left < c.target { return }
	}
	if depth == s.size {
		count := bits.OnesCount32(mines)
		s.configs++
		s.minimum, s.maximum = min(s.minimum, count), max(s.maximum, count)
		for i := range s.ways {
			if mines&(uint32(1)<<i) != 0 { s.ways[i]++ }
		}
		return
	}
	s.visit(depth+1, mines)
	s.visit(depth+1, mines|(uint32(1)<<depth))
}

func (f *Frontier) count(id int) {
	component := &f.components[id]
	local := make([]int, len(f.componentOf))
	for i, cell := range component.cells { local[cell] = i }
	search := Search{size: len(component.cells), minimum: len(component.cells)+1, ways: make([]int64, len(component.cells))}
	for _, c := range f.constraints {
		if f.componentOf[c.unknown[0]] != id { continue }
		var mask uint32
		for _, cell := range c.unknown { mask |= uint32(1) << local[cell] }
		search.constraints = append(search.constraints, Restriction{mask: mask, target: c.remaining})
	}
	search.visit(0, 0)
	component.configs, component.minimum, component.maximum = search.configs, search.minimum, search.maximum
	for i, cell := range component.cells { f.ways[cell] = search.ways[i] }
}

func fraction(numerator, denominator int64) string {
	a, b := numerator, denominator
	for b != 0 { a, b = b, a%b }
	return fmt.Sprintf("%d/%d", numerator/a, denominator/a)
}

func (g *Game) probability(cell int) {
	f := makeFrontier(g)
	id := f.componentOf[cell]
	if id < 0 {
		line("prob %s unconstrained", g.coord(cell))
		return
	}
	f.count(id)
	component := f.components[id]
	if component.configs == 0 {
		line("prob %s inconsistent", g.coord(cell))
	} else {
		line("prob %s %s size %d configs %d", g.coord(cell), fraction(f.ways[cell], component.configs), len(component.cells), component.configs)
	}
}

func (g *Game) frontierReport() {
	f := makeFrontier(g)
	total := 0
	for _, c := range f.components { total += len(c.cells) }
	line("frontier %d components %d", total, len(f.components))
	for id := range f.components {
		f.count(id)
		c := f.components[id]
		if c.configs == 0 {
			line("component %s size %d inconsistent", g.coord(c.cells[0]), len(c.cells))
		} else {
			line("component %s size %d configs %d min %d max %d", g.coord(c.cells[0]), len(c.cells), c.configs, c.minimum, c.maximum)
		}
	}
}

type AutoResult struct { rounds, flagged, opened, guesses int }

func (g *Game) autoPlay(safety Safety) AutoResult {
	var total AutoResult
	for g.state == playing {
		result := g.deduce()
		if !result.any { break }
		total.rounds++
		for cell, reason := range result.safe {
			if reason.kind == "" || g.revealed[cell] { continue }
			g.moves = append(g.moves, Move{autoReveal, cell})
			total.opened += g.reveal(cell, safety)
			g.checkWin()
			if g.state.finished() { return total }
		}
		for cell, reason := range result.mines {
			if reason.kind == "" || !g.unknown(cell) { continue }
			g.marks[cell] = flagged
			total.flagged++
			g.moves = append(g.moves, Move{autoFlag, cell})
		}
	}
	return total
}

func (g *Game) solve(safety Safety) AutoResult {
	var total AutoResult
	for !g.state.finished() {
		step := g.autoPlay(safety)
		total.rounds += step.rounds
		total.flagged += step.flagged
		total.opened += step.opened
		if g.state.finished() { break }
		f := makeFrontier(g)
		for id := range f.components { f.count(id) }
		unknown := int64(0)
		for cell := 0; cell < g.cells(); cell++ {
			if g.unknown(cell) { unknown++ }
		}
		remaining := int64(max(g.remaining(), 0))
		choice := -1
		bestNumerator, bestDenominator := int64(0), int64(1)
		for cell := 0; cell < g.cells(); cell++ {
			if !g.unknown(cell) { continue }
			numerator, denominator := remaining, unknown
			if id := f.componentOf[cell]; id >= 0 { numerator, denominator = f.ways[cell], f.components[id].configs }
			if denominator == 0 { continue }
			if choice < 0 || numerator*bestDenominator < bestNumerator*denominator {
				choice = cell
				bestNumerator, bestDenominator = numerator, denominator
			}
		}
		if choice < 0 { break }
		total.guesses++
		g.moves = append(g.moves, Move{guessMove, choice})
		total.opened += g.reveal(choice, safety)
		g.checkWin()
	}
	return total
}

func (g *Game) replay(count int, safety Safety) {
	copy := g.clone(false)
	copy.restart()
	for _, move := range g.moves[:count] {
		switch move.kind {
		case revealMove, autoReveal, guessMove:
			copy.reveal(move.cell, safety)
		case chordMove:
			copy.chord(move.cell, safety)
		case flagMove, autoFlag:
			copy.marks[move.cell] = flagged
		case unflagMove:
			copy.marks[move.cell] = unmarked
		case questionMove:
			if copy.marks[move.cell] == questioned { copy.marks[move.cell] = unmarked } else { copy.marks[move.cell] = questioned }
		}
		copy.checkWin()
	}
	line("replay %d/%d", count, len(g.moves))
	copy.show()
}

func (g *Game) boardInfo() {
	visited := make([]bool, g.cells())
	openings, largest, isolated := 0, 0, 0
	for cell := 0; cell < g.cells(); cell++ {
		if g.mine[cell] { continue }
		if g.numbers[cell] != 0 {
			adjacentBlank := false
			for _, next := range g.neighbors[cell] { adjacentBlank = adjacentBlank || !g.mine[next] && g.numbers[next] == 0 }
			if !adjacentBlank { isolated++ }
		} else if !visited[cell] {
			openings++
			covered := make([]bool, g.cells())
			queue := []int{cell}
			visited[cell], covered[cell] = true, true
			for head := 0; head < len(queue); head++ {
				for _, next := range g.neighbors[queue[head]] {
					covered[next] = true
					if g.numbers[next] == 0 && !visited[next] { visited[next] = true; queue = append(queue, next) }
				}
			}
			size := 0
			for _, cell := range covered { if cell { size++ } }
			largest = max(largest, size)
		}
	}
	line("3bv %d openings %d largest %d mines %d safe %d", openings+isolated, openings, largest, g.mineCount, g.safeCells())
}

func (g *Game) neighborCounts(cell int) (flags, unknown, opened int) {
	for _, next := range g.neighbors[cell] {
		if g.marks[next] == flagged { flags++ }
		if g.unknown(next) { unknown++ }
		if g.revealed[next] { opened++ }
	}
	return
}

func (g *Game) process(command string, cell int, value int64, safety Safety) error {
	switch command {
	case "REVEAL", "FLAG", "UNFLAG", "QUESTION", "PROB":
		if g.revealed[cell] { return fmt.Errorf("already revealed") }
		if (command == "REVEAL" || command == "PROB") && g.marks[cell] == flagged { return fmt.Errorf("flagged") }
		if command == "FLAG" && g.marks[cell] == flagged { return fmt.Errorf("already flagged") }
		if command == "UNFLAG" && g.marks[cell] != flagged { return fmt.Errorf("not flagged") }
	}
	switch command {
	case "RESTART":
		g.restart()
		line("restart %dx%d mines %d", g.width, g.height, g.mineCount)
	case "REVEAL":
		g.moves = append(g.moves, Move{revealMove, cell})
		opened := g.reveal(cell, safety)
		if g.state != lost { line("revealed %d", opened); g.checkWin() }
		g.endingOutput()
	case "FLAG":
		g.marks[cell] = flagged
		g.moves = append(g.moves, Move{flagMove, cell})
		line("flagged %s left %d", g.coord(cell), g.remaining())
	case "UNFLAG":
		g.marks[cell] = unmarked
		g.moves = append(g.moves, Move{unflagMove, cell})
		line("unflagged %s left %d", g.coord(cell), g.remaining())
	case "QUESTION":
		g.moves = append(g.moves, Move{questionMove, cell})
		name := "questioned"
		if g.marks[cell] == questioned { g.marks[cell], name = unmarked, "unmarked" } else { g.marks[cell] = questioned }
		line("%s %s left %d", name, g.coord(cell), g.remaining())
	case "CHORD":
		if !g.revealed[cell] { return fmt.Errorf("not revealed") }
		if g.numbers[cell] == 0 { return fmt.Errorf("no number") }
		flags, unknown, _ := g.neighborCounts(cell)
		if flags != g.numbers[cell] { return fmt.Errorf("flags %d of %d", flags, g.numbers[cell]) }
		if unknown == 0 { return fmt.Errorf("nothing to reveal") }
		g.moves = append(g.moves, Move{chordMove, cell})
		opened := g.chord(cell, safety)
		if g.state != lost { line("chorded %d", opened); g.checkWin() }
		g.endingOutput()
	case "UNDO":
		if len(g.undo) == 0 { return fmt.Errorf("nothing to undo") }
		snapshot := g.undo[len(g.undo)-1]
		g.undo = g.undo[:len(g.undo)-1]
		g.revealed, g.marks = snapshot.revealed, snapshot.marks
		g.moves = g.moves[:snapshot.moves]
		line("undo %s moves %d", snapshot.name, len(g.moves))
	case "SHOW":
		g.show()
	case "STATUS":
		line("status %s left %d moves %d revealed %d/%d", g.state, g.remaining(), len(g.moves), g.opened(), g.safeCells())
	case "CELL":
		flags, unknown, opened := g.neighborCounts(cell)
		if g.revealed[cell] {
			line("cell %s number %d flags %d unknown %d", g.coord(cell), g.numbers[cell], flags, unknown)
		} else {
			mark := []string{"none", "flag", "question"}[g.marks[cell]]
			line("cell %s hidden mark %s open %d", g.coord(cell), mark, opened)
		}
	case "HISTORY":
		line("history %d", len(g.moves))
		count := int(min(value, int64(len(g.moves))))
		for i := len(g.moves)-count; i < len(g.moves); i++ {
			move := g.moves[i]
			line("%d %s %s", i+1, move.kind, g.coord(move.cell))
		}
	case "REPLAY":
		if value > int64(len(g.moves)) { return fmt.Errorf("no move %d", value) }
		g.replay(int(value), safety)
	case "HINT":
		g.hint()
	case "AUTO", "SOLVE":
		var result AutoResult
		if command == "AUTO" { result = g.autoPlay(safety) } else { result = g.solve(safety) }
		if command == "SOLVE" {
			line("solve guesses %d rounds %d flagged %d revealed %d", result.guesses, result.rounds, result.flagged, result.opened)
		} else {
			line("auto rounds %d flagged %d revealed %d", result.rounds, result.flagged, result.opened)
		}
		g.endingOutput()
	case "ANALYZE":
		copy := g.clone(true)
		result := copy.autoPlay(safety)
		switch copy.state {
		case lost:
			line("analyze boom %s rounds %d", copy.coord(copy.exploded), result.rounds)
		case won:
			line("analyze clear rounds %d", result.rounds)
		default:
			line("analyze stuck rounds %d revealed %d/%d", result.rounds, copy.opened(), copy.safeCells())
		}
	case "PROB":
		g.probability(cell)
	case "FRONTIER":
		g.frontierReport()
	case "BOARDINFO":
		g.boardInfo()
	}
	return nil
}

func numberWord(word string) (int64, error) {
	if len(word) == 0 || len(word) > 10 || len(word) > 1 && word[0] == '0' { return 0, fmt.Errorf("bad arguments") }
	for i := 0; i < len(word); i++ {
		if word[i] < '0' || word[i] > '9' { return 0, fmt.Errorf("bad arguments") }
	}
	return strconv.ParseInt(word, 10, 64)
}

func hasCell(command string) bool {
	switch command { case "REVEAL", "FLAG", "UNFLAG", "QUESTION", "CHORD", "CELL", "PROB": return true }
	return false
}

func needsUnfinished(command string) bool {
	switch command { case "REVEAL", "FLAG", "UNFLAG", "QUESTION", "CHORD", "UNDO", "HINT", "AUTO", "ANALYZE", "PROB", "FRONTIER", "SOLVE": return true }
	return false
}

func recordsUndo(command string) bool {
	switch command { case "REVEAL", "FLAG", "UNFLAG", "QUESTION", "CHORD", "AUTO", "SOLVE": return true }
	return false
}

type Statistics struct {
	played, won, lost, streak, best int
	fastest int
	hasFastest bool
}

func (s *Statistics) finish(g *Game) {
	s.played++
	if g.state == won {
		s.won++
		s.streak++
		s.best = max(s.best, s.streak)
		if !s.hasFastest || len(g.moves) < s.fastest { s.fastest, s.hasFastest = len(g.moves), true }
	} else {
		s.lost++
		s.streak = 0
	}
}

func (s *Statistics) show() {
	rate, fastest := "-", "-"
	if s.played > 0 { rate = strconv.Itoa(s.won*100/s.played) + "%" }
	if s.hasFastest { fastest = strconv.Itoa(s.fastest) }
	line("stats played %d won %d lost %d rate %s streak %d best %d fastest %s", s.played, s.won, s.lost, rate, s.streak, s.best, fastest)
}

type Table struct {
	game *Game
	safety Safety
	stats Statistics
}

func (t *Table) layout(width, height int, rows []string) error {
	for i, row := range rows {
		if len(row) != width { return fmt.Errorf("bad row %d", i+1) }
		for _, c := range row {
			if c != '*' && c != '.' { return fmt.Errorf("bad row %d", i+1) }
		}
	}
	mines := make([]bool, width*height)
	count := 0
	for y, row := range rows {
		for x, c := range row {
			if c == '*' { mines[y*width+x] = true; count++ }
		}
	}
	if count == 0 || count == width*height { return fmt.Errorf("bad mine count %d", count) }
	game := newGame(width, height, count, 0)
	game.mine, game.determined, game.state = mines, true, playing
	game.numberBoard()
	t.game = game
	line("layout %dx%d mines %d", width, height, count)
	return nil
}

func (t *Table) execute(words []string) error {
	command := words[0]
	arguments, exists := commandArgs[command]
	if !exists { return fmt.Errorf("unknown command %s", command) }
	if len(words) != arguments+1 { return fmt.Errorf("bad arguments") }
	values := make([]int64, arguments)
	safety := t.safety
	if command == "PRESET" {
		var dimensions []int64
		switch words[1] {
		case "beginner": dimensions = []int64{9, 9, 10}
		case "intermediate": dimensions = []int64{16, 16, 40}
		case "expert": dimensions = []int64{30, 16, 99}
		default: return fmt.Errorf("bad arguments")
		}
		seed, err := numberWord(words[2])
		if err != nil { return err }
		values = append(dimensions, seed)
	} else if command == "SAFETY" {
		switch words[1] {
		case "block": safety = blockSafety
		case "cell": safety = cellSafety
		case "none": safety = noSafety
		default: return fmt.Errorf("bad arguments")
		}
	} else {
		for i, word := range words[1:] {
			value, err := numberWord(word)
			if err != nil { return err }
			values[i] = value
		}
	}
	if command == "NEW" || command == "PRESET" {
		width, height, mines, seed := values[0], values[1], values[2], values[3]
		if width < 1 || width > 30 || height < 1 || height > 30 || mines < 1 || mines > width*height-9 || seed < 1 || seed > 2147483646 {
			return fmt.Errorf("bad value")
		}
		t.game = newGame(int(width), int(height), int(mines), seed)
		line("new %dx%d mines %d", width, height, mines)
		return nil
	}
	if command == "HISTORY" && values[0] == 0 { return fmt.Errorf("bad value") }
	if command == "SAFETY" { t.safety = safety; line("safety %s", safety); return nil }
	if command == "STATS" { t.stats.show(); return nil }
	game := t.game
	if game == nil { return fmt.Errorf("no game") }
	if hasCell(command) && (values[0] >= int64(game.width) || values[1] >= int64(game.height)) { return fmt.Errorf("out of range") }
	if needsUnfinished(command) && game.state.finished() { return fmt.Errorf("game over") }
	if (command == "ANALYZE" || command == "BOARDINFO") && !game.determined { return fmt.Errorf("not started") }
	snapshot := Snapshot{name: strings.ToLower(command), moves: len(game.moves)}
	if recordsUndo(command) { snapshot.revealed, snapshot.marks = slices.Clone(game.revealed), slices.Clone(game.marks) }
	wasFinished := game.state.finished()
	cell, value := 0, int64(0)
	if hasCell(command) { cell = int(values[1])*game.width + int(values[0]) }
	if len(values) > 0 { value = values[0] }
	if err := game.process(command, cell, value, safety); err != nil { return err }
	if recordsUndo(command) && len(game.moves) > snapshot.moves { game.undo = append(game.undo, snapshot) }
	if !wasFinished && game.state.finished() { t.stats.finish(game) }
	return nil
}

func readLine(input *bufio.Reader) string {
	text, _ := input.ReadString('\n')
	return strings.TrimSuffix(strings.TrimSuffix(text, "\n"), "\r")
}

func main() {
	input := bufio.NewReader(os.Stdin)
	count, _ := strconv.Atoi(readLine(input))
	table := Table{safety: blockSafety}
	for i := 0; i < count; i++ {
		words := strings.Split(readLine(input), " ")
		var err error
		if words[0] == "LAYOUT" {
			width, _ := strconv.Atoi(words[1])
			height, _ := strconv.Atoi(words[2])
			rows := make([]string, height)
			for y := range rows { rows[y] = readLine(input) }
			err = table.layout(width, height, rows)
		} else { err = table.execute(words) }
		if err != nil { line("error: %s", err) }
	}
	output.Flush()
}
