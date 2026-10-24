package main

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"unicode"
)

type argumentKind int

const (
	numberArgument argumentKind = iota
	stepsArgument
	directionArgument
	nameArgument
	transformArgument
	textArgument
)

const (
	directions      = "udlr"
	stepLetters     = "udlrUDLR"
	levelCharacters = "#-.$*@+"
	maxSide         = 10
	maxLimit        = 100000
	undefined       = -1
	noCell          = -1
	noLimit         = -1
	noParent        = -1
)

var (
	deltas = [4][2]int{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}
	turns  = map[string]string{
		"ROT90":  "rlud",
		"ROT180": "durl",
		"ROT270": "lrdu",
		"FLIPH":  "udrl",
		"FLIPV":  "dulr",
	}
	numberWord        = regexp.MustCompile(`^(0|[1-9][0-9]{0,5})$`)
	nameWord          = regexp.MustCompile(`^[a-z]{1,8}$`)
	cellCounts        = map[string]int{"PATH": 1, "PUSH": 1, "BRING": 2}
	levelFreeCommands = []string{"IMPORT", "VALID"}
	errWall           = errors.New("wall")
	errBlocked        = errors.New("blocked")
	errBadArguments   = errors.New("bad arguments")
	errBadValue       = errors.New("bad value")
	errBadLevel       = errors.New("bad level")
	errUnreachable    = errors.New("unreachable")
)

type command struct {
	kinds   []argumentKind
	handler func(*Sokoban, []string) error
}

var commands = map[string]command{
	"IMPORT": {[]argumentKind{textArgument}, (*Sokoban).importLevel},
	"VALID":  {nil, (*Sokoban).valid},
	"INFO":   {nil, (*Sokoban).info},
	"SHOW":   {nil, (*Sokoban).show},
	"EXPORT": {nil, (*Sokoban).exportLevel},
	"MOVE":   {[]argumentKind{stepsArgument}, (*Sokoban).move},
	"PUSH": {
		[]argumentKind{numberArgument, numberArgument, directionArgument},
		(*Sokoban).push,
	},
	"BRING": {
		[]argumentKind{numberArgument, numberArgument, numberArgument, numberArgument},
		(*Sokoban).bring,
	},
	"PATH":        {[]argumentKind{numberArgument, numberArgument}, (*Sokoban).path},
	"UNDO":        {[]argumentKind{numberArgument}, (*Sokoban).undo},
	"REDO":        {[]argumentKind{numberArgument}, (*Sokoban).redo},
	"RESET":       {nil, (*Sokoban).reset},
	"STATUS":      {nil, (*Sokoban).status},
	"HISTORY":     {nil, (*Sokoban).showHistory},
	"BOXES":       {nil, (*Sokoban).showBoxes},
	"REACH":       {nil, (*Sokoban).reach},
	"DEADSQUARES": {nil, (*Sokoban).deadSquares},
	"DEADLOCK":    {nil, (*Sokoban).deadlock},
	"BOUND":       {nil, (*Sokoban).bound},
	"SAVE":        {[]argumentKind{nameArgument}, (*Sokoban).save},
	"RESTORE":     {[]argumentKind{nameArgument}, (*Sokoban).restore},
	"CHECK":       {[]argumentKind{stepsArgument}, (*Sokoban).check},
	"SOLVE":       {[]argumentKind{numberArgument}, (*Sokoban).solve},
	"HINT":        {[]argumentKind{numberArgument}, (*Sokoban).hint},
	"PLAY":        {nil, (*Sokoban).play},
	"TRANSFORM":   {[]argumentKind{transformArgument}, (*Sokoban).transform},
}

func parseNumber(text string) int {
	value, _ := strconv.Atoi(text)
	return value
}

func dimensions(height, width int) string {
	return fmt.Sprintf("%dx%d", height, width)
}

func countTrue(flags []bool) int {
	count := 0
	for _, flag := range flags {
		if flag {
			count++
		}
	}
	return count
}

func isPush(letter byte) bool {
	return unicode.IsUpper(rune(letter))
}

func lowerLetter(letter byte) byte {
	return byte(unicode.ToLower(rune(letter)))
}

func upperLetter(letter byte) byte {
	return byte(unicode.ToUpper(rune(letter)))
}

func decode(text, allowed string) (string, bool) {
	var result strings.Builder
	index := 0
	for index < len(text) {
		start := index
		for index < len(text) && '0' <= text[index] && text[index] <= '9' {
			index++
		}
		count := text[start:index]
		if len(count) > 2 || strings.HasPrefix(count, "0") || index == len(text) {
			return "", false
		}
		if strings.IndexByte(allowed, text[index]) < 0 {
			return "", false
		}
		repeat := 1
		if count != "" {
			repeat = parseNumber(count)
		}
		result.WriteString(strings.Repeat(text[index:index+1], repeat))
		index++
	}
	return result.String(), true
}

func encode(text string) string {
	var result strings.Builder
	start := 0
	for start < len(text) {
		end := start
		for end < len(text) && text[end] == text[start] {
			end++
		}
		if run := end - start; run > 1 {
			result.WriteString(strconv.Itoa(run))
		}
		result.WriteByte(text[start])
		start = end
	}
	return result.String()
}

func stepSequence(word string) string {
	steps, _ := decode(word, stepLetters)
	return strings.ToLower(steps)
}

func validArgument(kind argumentKind, text string) bool {
	switch kind {
	case numberArgument:
		return numberWord.MatchString(text)
	case stepsArgument:
		_, ok := decode(text, stepLetters)
		return ok
	case directionArgument:
		return len(text) == 1 && strings.Contains(directions, text)
	case nameArgument:
		return nameWord.MatchString(text)
	case transformArgument:
		_, ok := turns[text]
		return ok
	}
	return true
}

func pushCount(letters string) int {
	count := 0
	for index := range len(letters) {
		if isPush(letters[index]) {
			count++
		}
	}
	return count
}

func turnLetters(letters []byte, kind string) []byte {
	turn := turns[kind]
	turned := make([]byte, len(letters))
	for index, letter := range letters {
		direction := turn[strings.IndexByte(directions, lowerLetter(letter))]
		if isPush(letter) {
			direction = upperLetter(direction)
		}
		turned[index] = direction
	}
	return turned
}

func moveBox(boxes []int, source, destination int) []int {
	moved := slices.Clone(boxes)
	moved[slices.Index(moved, source)] = destination
	slices.Sort(moved)
	return moved
}

func counted(label, letters string) string {
	if letters == "" {
		return label + " 0"
	}
	return fmt.Sprintf("%s %d %s", label, len(letters), letters)
}

func permutations(items []int) [][]int {
	if len(items) == 0 {
		return [][]int{{}}
	}
	var result [][]int
	for index, item := range items {
		rest := slices.Concat(items[:index], items[index+1:])
		for _, tail := range permutations(rest) {
			result = append(result, append([]int{item}, tail...))
		}
	}
	return result
}

func findInterior(height, width int, walls []bool, start int) []bool {
	interior := make([]bool, height*width)
	interior[start] = true
	stack := []int{start}
	for len(stack) > 0 {
		cell := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		row, column := cell/width, cell%width
		for _, delta := range deltas {
			nextRow, nextColumn := row+delta[0], column+delta[1]
			if nextRow >= 0 && nextRow < height && nextColumn >= 0 && nextColumn < width {
				neighbor := nextRow*width + nextColumn
				if !walls[neighbor] && !interior[neighbor] {
					interior[neighbor] = true
					stack = append(stack, neighbor)
				}
			}
		}
	}
	return interior
}

type Position struct {
	player int
	boxes  []int
}

func (p Position) same(other Position) bool {
	return p.player == other.player && slices.Equal(p.boxes, other.boxes)
}

type Level struct {
	height    int
	width     int
	size      int
	walls     []bool
	goals     []bool
	interior  []bool
	offsets   [4]int
	goalCells []int
	reason    string
	distances [][]int
	dead      []bool
}

func newLevel(height, width int, walls, goals, interior []bool) *Level {
	level := &Level{
		height:   height,
		width:    width,
		size:     height * width,
		walls:    walls,
		goals:    goals,
		interior: interior,
		dead:     make([]bool, height*width),
	}
	for index, delta := range deltas {
		level.offsets[index] = delta[0]*width + delta[1]
	}
	for cell, goal := range goals {
		if goal {
			level.goalCells = append(level.goalCells, cell)
		}
	}
	return level
}

func (l *Level) offsetOf(direction byte) int {
	return l.offsets[strings.IndexByte(directions, direction)]
}

func (l *Level) cellText(cell int) string {
	return fmt.Sprintf("%d %d", cell/l.width+1, cell%l.width+1)
}

func (l *Level) cellAt(row, column int) int {
	return (row-1)*l.width + column - 1
}

func (l *Level) contains(row, column int) bool {
	return 1 <= row && row <= l.height && 1 <= column && column <= l.width
}

func (l *Level) onBorder(cell int) bool {
	row, column := cell/l.width, cell%l.width
	return row == 0 || row == l.height-1 || column == 0 || column == l.width-1
}

func (l *Level) invalidity(players int, boxes []int) string {
	if players != 1 {
		return fmt.Sprintf("players %d", players)
	}
	if len(boxes) == 0 {
		return "no boxes"
	}
	if len(boxes) != len(l.goalCells) {
		return fmt.Sprintf("boxes %d goals %d", len(boxes), len(l.goalCells))
	}
	for cell := range l.size {
		if l.interior[cell] && l.onBorder(cell) {
			return "open " + l.cellText(cell)
		}
	}
	for cell := range l.size {
		if (l.goals[cell] || slices.Contains(boxes, cell)) && !l.interior[cell] {
			return "outside " + l.cellText(cell)
		}
	}
	return ""
}

func (l *Level) analyze() {
	l.distances = nil
	for _, goal := range l.goalCells {
		l.distances = append(l.distances, l.pushDistances(goal))
	}
	for cell := range l.size {
		_, defined := l.goalDistance(cell)
		l.dead[cell] = l.interior[cell] && !defined
	}
}

func (l *Level) pushDistances(goal int) []int {
	distance := make([]int, l.size)
	for cell := range distance {
		distance[cell] = undefined
	}
	distance[goal] = 0
	queue := []int{goal}
	for len(queue) > 0 {
		cell := queue[0]
		queue = queue[1:]
		for _, offset := range l.offsets {
			box := cell - offset
			if l.interior[box] && l.interior[box-offset] && distance[box] == undefined {
				distance[box] = distance[cell] + 1
				queue = append(queue, box)
			}
		}
	}
	return distance
}

func (l *Level) goalDistance(cell int) (int, bool) {
	best, found := 0, false
	for _, distance := range l.distances {
		if distance[cell] != undefined && (!found || distance[cell] < best) {
			best, found = distance[cell], true
		}
	}
	return best, found
}

func (l *Level) boxesOnGoals(boxes []int) int {
	count := 0
	for _, box := range boxes {
		if l.goals[box] {
			count++
		}
	}
	return count
}

func (l *Level) solved(boxes []int) bool {
	return l.boxesOnGoals(boxes) == len(boxes)
}

func (l *Level) reachable(player int, boxes []int) []bool {
	seen := make([]bool, l.size)
	seen[player] = true
	stack := []int{player}
	for len(stack) > 0 {
		cell := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		for _, offset := range l.offsets {
			neighbor := cell + offset
			if l.interior[neighbor] && !seen[neighbor] && !slices.Contains(boxes, neighbor) {
				seen[neighbor] = true
				stack = append(stack, neighbor)
			}
		}
	}
	return seen
}

func (l *Level) representative(player int, boxes []int) int {
	return slices.Index(l.reachable(player, boxes), true)
}

type trace struct {
	cell      int
	direction byte
}

func (l *Level) walkPath(start, target int, boxes []int) string {
	cameFrom := make([]*trace, l.size)
	queue := []int{start}
	for len(queue) > 0 {
		cell := queue[0]
		queue = queue[1:]
		for _, direction := range []byte(directions) {
			neighbor := cell + l.offsetOf(direction)
			if l.interior[neighbor] && !slices.Contains(boxes, neighbor) && neighbor != start &&
				cameFrom[neighbor] == nil {
				cameFrom[neighbor] = &trace{cell, direction}
				queue = append(queue, neighbor)
			}
		}
	}
	var path []byte
	for cell := target; cell != start; cell = cameFrom[cell].cell {
		path = append(path, cameFrom[cell].direction)
	}
	slices.Reverse(path)
	return string(path)
}

func (l *Level) step(position Position, direction byte) (Position, byte, error) {
	offset := l.offsetOf(direction)
	target := position.player + offset
	if l.walls[target] {
		return position, 0, errWall
	}
	if !slices.Contains(position.boxes, target) {
		return Position{target, position.boxes}, direction, nil
	}
	beyond := target + offset
	if l.walls[beyond] || slices.Contains(position.boxes, beyond) {
		return position, 0, errBlocked
	}
	return Position{target, moveBox(position.boxes, target, beyond)}, upperLetter(direction), nil
}

func (l *Level) pushable(box int, direction byte, boxes []int, reachable []bool) bool {
	offset := l.offsetOf(direction)
	destination := box + offset
	return reachable[box-offset] && l.interior[destination] && !slices.Contains(boxes, destination)
}

func (l *Level) sideBlocked(box int, sides [2]int, boxes, assumed []int) bool {
	for _, side := range sides {
		if l.walls[side] || slices.Contains(assumed, side) {
			return true
		}
	}
	if l.dead[sides[0]] && l.dead[sides[1]] {
		return true
	}
	extended := append(slices.Clone(assumed), box)
	for _, side := range sides {
		if slices.Contains(boxes, side) && l.frozen(side, boxes, extended) {
			return true
		}
	}
	return false
}

func (l *Level) frozen(box int, boxes, assumed []int) bool {
	horizontal := [2]int{box + l.offsetOf('l'), box + l.offsetOf('r')}
	vertical := [2]int{box + l.offsetOf('u'), box + l.offsetOf('d')}
	return l.sideBlocked(box, horizontal, boxes, assumed) &&
		l.sideBlocked(box, vertical, boxes, assumed)
}

func (l *Level) hasFrozenBox(boxes []int) bool {
	for _, box := range boxes {
		if !l.goals[box] && l.frozen(box, boxes, nil) {
			return true
		}
	}
	return false
}

func (l *Level) splitRows(symbols []byte) []string {
	var rows []string
	for start := 0; start < l.size; start += l.width {
		rows = append(rows, string(symbols[start:start+l.width]))
	}
	return rows
}

func (l *Level) symbol(cell int, position Position) byte {
	if l.walls[cell] {
		return '#'
	}
	if cell == position.player {
		if l.goals[cell] {
			return '+'
		}
		return '@'
	}
	if slices.Contains(position.boxes, cell) {
		if l.goals[cell] {
			return '*'
		}
		return '$'
	}
	if l.goals[cell] {
		return '.'
	}
	return '-'
}

func (l *Level) render(position Position) []string {
	symbols := make([]byte, l.size)
	for cell := range symbols {
		symbols[cell] = l.symbol(cell, position)
	}
	return l.splitRows(symbols)
}

func (l *Level) deadSymbol(cell int) byte {
	if l.walls[cell] {
		return '#'
	}
	if l.goals[cell] {
		return '.'
	}
	if l.dead[cell] {
		return 'x'
	}
	return '-'
}

func (l *Level) deadMap() []string {
	symbols := make([]byte, l.size)
	for cell := range symbols {
		symbols[cell] = l.deadSymbol(cell)
	}
	return l.splitRows(symbols)
}

func (l *Level) mapCell(kind string, cell int) int {
	row, column := cell/l.width, cell%l.width
	lastRow, lastColumn := l.height-1, l.width-1
	switch kind {
	case "ROT90":
		return column*l.height + lastRow - row
	case "ROT180":
		return (lastRow-row)*l.width + lastColumn - column
	case "ROT270":
		return (lastColumn-column)*l.height + row
	case "FLIPH":
		return row*l.width + lastColumn - column
	}
	return (lastRow-row)*l.width + column
}

func (l *Level) mapPosition(kind string, position Position) Position {
	boxes := make([]int, len(position.boxes))
	for index, box := range position.boxes {
		boxes[index] = l.mapCell(kind, box)
	}
	slices.Sort(boxes)
	return Position{l.mapCell(kind, position.player), boxes}
}

func (l *Level) transformed(kind string) *Level {
	height, width := l.height, l.width
	if kind == "ROT90" || kind == "ROT270" {
		height, width = l.width, l.height
	}
	walls := make([]bool, l.size)
	goals := make([]bool, l.size)
	interior := make([]bool, l.size)
	for cell := range l.size {
		moved := l.mapCell(kind, cell)
		walls[moved] = l.walls[cell]
		goals[moved] = l.goals[cell]
		interior[moved] = l.interior[cell]
	}
	level := newLevel(height, width, walls, goals, interior)
	level.analyze()
	return level
}

func buildLevel(rows []string) (*Level, Position) {
	height, width := len(rows), len(rows[0])
	cells := strings.Join(rows, "")
	walls := make([]bool, len(cells))
	goals := make([]bool, len(cells))
	var players, boxes []int
	for cell := range len(cells) {
		symbol := cells[cell]
		walls[cell] = symbol == '#'
		goals[cell] = strings.IndexByte(".*+", symbol) >= 0
		if symbol == '@' || symbol == '+' {
			players = append(players, cell)
		}
		if symbol == '$' || symbol == '*' {
			boxes = append(boxes, cell)
		}
	}
	interior := make([]bool, len(cells))
	if len(players) == 1 {
		interior = findInterior(height, width, walls, players[0])
	}
	level := newLevel(height, width, walls, goals, interior)
	level.reason = level.invalidity(len(players), boxes)
	if level.reason == "" {
		level.analyze()
	}
	player := noCell
	if len(players) > 0 {
		player = players[0]
	}
	return level, Position{player, boxes}
}

type boxPush struct {
	box       int
	direction byte
}

type searchNode struct {
	boxes          []int
	representative int
	parent         int
	push           boxPush
}

type searchState struct {
	boxes          string
	representative int
}

type searchResult struct {
	outcome  string
	expanded int
	states   int
	notation string
}

func solutionPushes(nodes []searchNode) []boxPush {
	var pushes []boxPush
	for node := nodes[len(nodes)-1]; node.parent != noParent; node = nodes[node.parent] {
		pushes = append(pushes, node.push)
	}
	slices.Reverse(pushes)
	return pushes
}

func solutionNotation(level *Level, position Position, pushes []boxPush) string {
	var notation strings.Builder
	for _, push := range pushes {
		offset := level.offsetOf(push.direction)
		notation.WriteString(level.walkPath(position.player, push.box-offset, position.boxes))
		notation.WriteByte(upperLetter(push.direction))
		position = Position{push.box, moveBox(position.boxes, push.box, push.box+offset)}
	}
	return notation.String()
}

func pushSearch(
	level *Level, start Position, fixed []int, target int, pruning bool, limit int,
) searchResult {
	root := searchNode{
		start.boxes, level.representative(start.player, start.boxes), noParent, boxPush{},
	}
	nodes := []searchNode{root}
	known := map[searchState]bool{{fmt.Sprint(root.boxes), root.representative}: true}
	expanded := 0
	for expanded < len(nodes) {
		if expanded == limit {
			return searchResult{outcome: "limit", expanded: expanded, states: len(nodes)}
		}
		node := nodes[expanded]
		expanded++
		reachable := level.reachable(node.representative, node.boxes)
		for _, box := range node.boxes {
			if slices.Contains(fixed, box) {
				continue
			}
			for _, direction := range []byte(directions) {
				if !level.pushable(box, direction, node.boxes, reachable) {
					continue
				}
				destination := box + level.offsetOf(direction)
				boxes := moveBox(node.boxes, box, destination)
				if pruning && (level.dead[destination] || level.hasFrozenBox(boxes)) {
					continue
				}
				representative := level.representative(box, boxes)
				state := searchState{fmt.Sprint(boxes), representative}
				if known[state] {
					continue
				}
				known[state] = true
				push := boxPush{box, direction}
				nodes = append(nodes, searchNode{boxes, representative, expanded - 1, push})
				reached := level.solved(boxes)
				if target != noCell {
					reached = destination == target
				}
				if reached {
					notation := solutionNotation(level, start, solutionPushes(nodes))
					return searchResult{"found", expanded, len(nodes), notation}
				}
			}
		}
	}
	return searchResult{outcome: "no solution", expanded: expanded, states: len(nodes)}
}

type snapshot struct {
	position Position
	history  []byte
}

type solution struct {
	notation string
	position Position
}

type assignment struct {
	order  []int
	pushes []int
	total  int
}

type Sokoban struct {
	out       *bufio.Writer
	level     *Level
	initial   Position
	current   Position
	history   []byte
	redoList  []byte
	snapshots map[string]snapshot
	solution  *solution
}

func newSokoban(out *bufio.Writer, rows []string) *Sokoban {
	game := &Sokoban{out: out}
	game.load(rows)
	return game
}

func (g *Sokoban) emit(parts ...any) {
	fmt.Fprintln(g.out, parts...)
}

func (g *Sokoban) load(rows []string) {
	g.level, g.initial = buildLevel(rows)
	g.current = g.initial
	g.history = nil
	g.redoList = nil
	g.snapshots = map[string]snapshot{}
	g.solution = nil
}

func (g *Sokoban) cellArgument(arguments []string, index int) int {
	return g.level.cellAt(parseNumber(arguments[index]), parseNumber(arguments[index+1]))
}

func (g *Sokoban) simulate(steps string) (Position, []byte, error) {
	position := g.current
	var letters []byte
	for _, direction := range []byte(steps) {
		next, letter, err := g.level.step(position, direction)
		if err != nil {
			return position, letters, fmt.Errorf("step %d %w", len(letters)+1, err)
		}
		position = next
		letters = append(letters, letter)
	}
	return position, letters, nil
}

func (g *Sokoban) takeSteps(steps string) ([]byte, error) {
	position, letters, err := g.simulate(steps)
	g.current = position
	g.history = append(g.history, letters...)
	if len(letters) > 0 {
		g.redoList = nil
	}
	return letters, err
}

func (g *Sokoban) progress(boxes []int) string {
	onGoals := g.level.boxesOnGoals(boxes)
	text := fmt.Sprintf("goals %d/%d", onGoals, len(boxes))
	if onGoals == len(boxes) {
		text += " solved"
	}
	return text
}

func (g *Sokoban) searchSolution(limit int) (string, string, bool) {
	if g.level.solved(g.current.boxes) {
		return "already solved", "", false
	}
	result := pushSearch(g.level, g.current, nil, noCell, true, limit)
	counts := fmt.Sprintf("expanded %d states %d", result.expanded, result.states)
	if result.outcome != "found" {
		return result.outcome + " " + counts, "", false
	}
	notation := result.notation
	summary := fmt.Sprintf(
		"solution pushes %d moves %d %s", pushCount(notation), len(notation), counts,
	)
	return summary, notation, true
}

func (g *Sokoban) loadRows(width int, rows []string) error {
	for index, row := range rows {
		unknown := strings.ContainsFunc(row, func(symbol rune) bool {
			return !strings.ContainsRune(levelCharacters, symbol)
		})
		if len(row) != width || unknown {
			return fmt.Errorf("bad row %d", index+1)
		}
	}
	g.load(rows)
	g.emit("loaded", dimensions(len(rows), width))
	return nil
}

func (g *Sokoban) importLevel(arguments []string) error {
	parts := strings.Split(arguments[0], "|")
	rows := make([]string, len(parts))
	for index, part := range parts {
		row, ok := decode(part, levelCharacters)
		if !ok {
			return errBadLevel
		}
		rows[index] = row
	}
	width := len(rows[0])
	uneven := slices.ContainsFunc(rows, func(row string) bool { return len(row) != width })
	if len(rows) > maxSide || uneven || width < 1 || width > maxSide {
		return errBadLevel
	}
	g.load(rows)
	g.emit("loaded", dimensions(len(rows), width))
	return nil
}

func (g *Sokoban) valid(_ []string) error {
	if g.level.reason == "" {
		g.emit("valid")
	} else {
		g.emit("invalid", g.level.reason)
	}
	return nil
}

func (g *Sokoban) info(_ []string) error {
	level := g.level
	g.emit("size", dimensions(level.height, level.width), "walls", countTrue(level.walls),
		"cells", countTrue(level.interior), "boxes", len(g.current.boxes),
		"dead", countTrue(level.dead))
	return nil
}

func (g *Sokoban) show(_ []string) error {
	for _, row := range g.level.render(g.current) {
		g.emit(row)
	}
	return nil
}

func (g *Sokoban) exportLevel(_ []string) error {
	rows := g.level.render(g.current)
	for index, row := range rows {
		rows[index] = encode(row)
	}
	g.emit("level", strings.Join(rows, "|"))
	return nil
}

func (g *Sokoban) move(arguments []string) error {
	letters, err := g.takeSteps(stepSequence(arguments[0]))
	if len(letters) > 0 {
		g.emit("moved", string(letters))
	}
	return err
}

func (g *Sokoban) push(arguments []string) error {
	level, position := g.level, g.current
	box := g.cellArgument(arguments, 0)
	direction := arguments[2][0]
	offset := level.offsetOf(direction)
	if !slices.Contains(position.boxes, box) {
		return errors.New("no box")
	}
	destination := box + offset
	if !level.interior[destination] || slices.Contains(position.boxes, destination) {
		return errors.New("blocked")
	}
	if !level.reachable(position.player, position.boxes)[box-offset] {
		return errUnreachable
	}
	path := level.walkPath(position.player, box-offset, position.boxes)
	letters, _ := g.takeSteps(path + string(direction))
	g.emit("pushed", string(letters))
	return nil
}

func (g *Sokoban) bring(arguments []string) error {
	position := g.current
	source := g.cellArgument(arguments, 0)
	target := g.cellArgument(arguments, 2)
	if !slices.Contains(position.boxes, source) {
		return errors.New("no box")
	}
	if source == target {
		g.emit("brought", 0)
		return nil
	}
	var fixed []int
	for _, box := range position.boxes {
		if box != source {
			fixed = append(fixed, box)
		}
	}
	result := pushSearch(g.level, position, fixed, target, false, noLimit)
	if result.outcome != "found" {
		return errors.New("no route")
	}
	g.takeSteps(strings.ToLower(result.notation))
	g.emit("brought", pushCount(result.notation), result.notation)
	return nil
}

func (g *Sokoban) path(arguments []string) error {
	level, position := g.level, g.current
	target := g.cellArgument(arguments, 0)
	if !level.reachable(position.player, position.boxes)[target] {
		return errUnreachable
	}
	letters, _ := g.takeSteps(level.walkPath(position.player, target, position.boxes))
	g.emit(counted("path", string(letters)))
	return nil
}

func (g *Sokoban) undo(arguments []string) error {
	if len(g.history) == 0 {
		return errors.New("nothing to undo")
	}
	count := min(parseNumber(arguments[0]), len(g.history))
	for range count {
		letter := g.history[len(g.history)-1]
		g.history = g.history[:len(g.history)-1]
		direction := lowerLetter(letter)
		offset := g.level.offsetOf(direction)
		player, boxes := g.current.player, g.current.boxes
		if isPush(letter) {
			boxes = moveBox(boxes, player+offset, player)
		}
		g.current = Position{player - offset, boxes}
		g.redoList = append(g.redoList, direction)
	}
	g.emit("undone", count)
	return nil
}

func (g *Sokoban) redo(arguments []string) error {
	if len(g.redoList) == 0 {
		return errors.New("nothing to redo")
	}
	count := min(parseNumber(arguments[0]), len(g.redoList))
	for range count {
		direction := g.redoList[len(g.redoList)-1]
		g.redoList = g.redoList[:len(g.redoList)-1]
		position, letter, _ := g.level.step(g.current, direction)
		g.current = position
		g.history = append(g.history, letter)
	}
	g.emit("redone", count)
	return nil
}

func (g *Sokoban) reset(_ []string) error {
	g.current = g.initial
	g.history = nil
	g.redoList = nil
	g.emit("reset")
	return nil
}

func (g *Sokoban) status(_ []string) error {
	history := string(g.history)
	g.emit("moves", len(history), "pushes", pushCount(history), g.progress(g.current.boxes))
	return nil
}

func (g *Sokoban) showHistory(_ []string) error {
	g.emit(counted("history", string(g.history)))
	return nil
}

func (g *Sokoban) showBoxes(_ []string) error {
	level, position := g.level, g.current
	reachable := level.reachable(position.player, position.boxes)
	g.emit("boxes", len(position.boxes))
	for _, box := range position.boxes {
		distance := "dead"
		if value, defined := level.goalDistance(box); defined {
			distance = strconv.Itoa(value)
		}
		var pushable []byte
		for _, direction := range []byte(directions) {
			if level.pushable(box, direction, position.boxes, reachable) {
				pushable = append(pushable, direction)
			}
		}
		if len(pushable) == 0 {
			pushable = []byte("-")
		}
		g.emit("box", level.cellText(box), distance, string(pushable))
	}
	return nil
}

func (g *Sokoban) reach(_ []string) error {
	reachable := g.level.reachable(g.current.player, g.current.boxes)
	first := g.level.cellText(slices.Index(reachable, true))
	g.emit("reach", countTrue(reachable), "first", first)
	return nil
}

func (g *Sokoban) deadSquares(_ []string) error {
	g.emit("dead", countTrue(g.level.dead))
	for _, row := range g.level.deadMap() {
		g.emit(row)
	}
	return nil
}

func (g *Sokoban) deadlock(_ []string) error {
	level, boxes := g.level, g.current.boxes
	for _, box := range boxes {
		if level.dead[box] {
			g.emit("deadlock", "dead", level.cellText(box))
			return nil
		}
	}
	for _, box := range boxes {
		if !level.goals[box] && level.frozen(box, boxes, nil) {
			g.emit("deadlock", "frozen", level.cellText(box))
			return nil
		}
	}
	g.emit("no deadlock")
	return nil
}

func (g *Sokoban) bound(_ []string) error {
	level, boxes := g.level, g.current.boxes
	goalIndices := make([]int, len(level.goalCells))
	for index := range goalIndices {
		goalIndices[index] = index
	}
	var best *assignment
	for _, order := range permutations(goalIndices) {
		pushes := make([]int, len(boxes))
		total := 0
		for index, box := range boxes {
			pushes[index] = level.distances[order[index]][box]
			total += pushes[index]
		}
		if slices.Contains(pushes, undefined) {
			continue
		}
		if best == nil || total < best.total {
			best = &assignment{order, pushes, total}
		}
	}
	if best == nil {
		g.emit("bound", "none")
		return nil
	}
	g.emit("bound", best.total)
	for index, box := range boxes {
		goal := level.goalCells[best.order[index]]
		g.emit("box", level.cellText(box), "goal", level.cellText(goal),
			"pushes", best.pushes[index])
	}
	return nil
}

func (g *Sokoban) save(arguments []string) error {
	name := arguments[0]
	g.snapshots[name] = snapshot{g.current, slices.Clone(g.history)}
	g.emit("saved", name, "moves", len(g.history))
	return nil
}

func (g *Sokoban) restore(arguments []string) error {
	name := arguments[0]
	saved, found := g.snapshots[name]
	if !found {
		return fmt.Errorf("no snapshot %s", name)
	}
	g.current = saved.position
	g.history = slices.Clone(saved.history)
	g.redoList = nil
	g.emit("restored", name, "moves", len(g.history))
	return nil
}

func (g *Sokoban) check(arguments []string) error {
	position, letters, err := g.simulate(stepSequence(arguments[0]))
	if err != nil {
		g.emit("check", "fail", err)
		return nil
	}
	g.emit("check", "ok", "moves", len(letters), "pushes", pushCount(string(letters)),
		g.progress(position.boxes))
	return nil
}

func (g *Sokoban) solve(arguments []string) error {
	summary, notation, found := g.searchSolution(parseNumber(arguments[0]))
	g.emit(summary)
	g.solution = nil
	if found {
		g.emit(notation)
		g.solution = &solution{notation, g.current}
	}
	return nil
}

func (g *Sokoban) hint(arguments []string) error {
	summary, notation, found := g.searchSolution(parseNumber(arguments[0]))
	if !found {
		g.emit(summary)
		return nil
	}
	part := notation[:strings.IndexFunc(notation, unicode.IsUpper)+1]
	g.takeSteps(strings.ToLower(part))
	g.emit("hint", part)
	return nil
}

func (g *Sokoban) play(_ []string) error {
	if g.solution == nil || !g.solution.position.same(g.current) {
		return errors.New("no solution")
	}
	notation := g.solution.notation
	g.takeSteps(strings.ToLower(notation))
	g.emit("played", "pushes", pushCount(notation), "moves", len(notation))
	return nil
}

func (g *Sokoban) transform(arguments []string) error {
	kind := arguments[0]
	old := g.level
	g.level = old.transformed(kind)
	g.initial = old.mapPosition(kind, g.initial)
	g.current = old.mapPosition(kind, g.current)
	g.history = turnLetters(g.history, kind)
	g.redoList = turnLetters(g.redoList, kind)
	for name, saved := range g.snapshots {
		g.snapshots[name] = snapshot{
			old.mapPosition(kind, saved.position), turnLetters(saved.history, kind),
		}
	}
	if g.solution != nil {
		g.solution = &solution{
			string(turnLetters([]byte(g.solution.notation), kind)),
			old.mapPosition(kind, g.solution.position),
		}
	}
	g.emit("transformed", dimensions(g.level.height, g.level.width))
	return nil
}

func (g *Sokoban) checkValues(name string, arguments []string) error {
	for index := 0; index < 2*cellCounts[name]; index += 2 {
		if !g.level.contains(parseNumber(arguments[index]), parseNumber(arguments[index+1])) {
			return errBadValue
		}
	}
	if (name == "UNDO" || name == "REDO") && parseNumber(arguments[0]) < 1 {
		return errBadValue
	}
	if name == "SOLVE" || name == "HINT" {
		if limit := parseNumber(arguments[0]); limit < 1 || limit > maxLimit {
			return errBadValue
		}
	}
	return nil
}

func (g *Sokoban) runCommand(name string, arguments []string) error {
	command, known := commands[name]
	if !known {
		return fmt.Errorf("unknown command %s", name)
	}
	if len(arguments) != len(command.kinds) {
		return errBadArguments
	}
	for index, kind := range command.kinds {
		if !validArgument(kind, arguments[index]) {
			return errBadArguments
		}
	}
	if !slices.Contains(levelFreeCommands, name) {
		if g.level.reason != "" {
			return errors.New("invalid level")
		}
		if err := g.checkValues(name, arguments); err != nil {
			return err
		}
	}
	return command.handler(g, arguments)
}

func (g *Sokoban) execute(words, rows []string) {
	var err error
	if words[0] == "LOAD" {
		err = g.loadRows(parseNumber(words[2]), rows)
	} else {
		err = g.runCommand(words[0], words[1:])
	}
	if err != nil {
		g.emit("error:", err)
	}
}

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	readLine := func() string {
		scanner.Scan()
		return scanner.Text()
	}
	readRows := func(count int) []string {
		rows := make([]string, count)
		for index := range rows {
			rows[index] = readLine()
		}
		return rows
	}
	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()
	height := parseNumber(strings.Fields(readLine())[0])
	game := newSokoban(out, readRows(height))
	count := parseNumber(strings.TrimSpace(readLine()))
	for range count {
		words := strings.Split(readLine(), " ")
		var rows []string
		if words[0] == "LOAD" {
			rows = readRows(parseNumber(words[1]))
		}
		game.execute(words, rows)
	}
}
