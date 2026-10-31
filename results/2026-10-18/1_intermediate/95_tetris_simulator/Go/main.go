package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

const kinds = "IOTSZJL"

var movements = []string{"L", "R", "LL", "RR", "SD", "DD", "CW", "CCW"}
var stateNames = [4]string{"0", "R", "2", "L"}
var intervals = [12]int{60, 48, 37, 28, 21, 16, 11, 8, 6, 4, 3, 2}
var comboSent = [11]int{0, 1, 1, 2, 2, 3, 3, 4, 4, 4, 5}
var clearNames = [11]string{"SINGLE", "DOUBLE", "TRIPLE", "TETRIS", "TSPIN_MINI", "TSPIN_MINI_SINGLE", "TSPIN_MINI_DOUBLE", "TSPIN", "TSPIN_SINGLE", "TSPIN_DOUBLE", "TSPIN_TRIPLE"}

var commands = map[string]bool{"NEW": true, "PRINT": true, "NEXT": true, "PREVIEW": true, "STATUS": true, "ANALYZE": true, "ROW": true, "GARBAGE": true, "ATTACK": true, "TICK": true, "UNDO": true, "SAVE": true, "LOAD": true, "SPINS": true, "HINT": true, "AUTO": true}
var afterEnd = map[string]bool{"PRINT": true, "NEXT": true, "PREVIEW": true, "STATUS": true, "ANALYZE": true, "LOAD": true}
var operations = map[string]bool{"L": true, "R": true, "LL": true, "RR": true, "SD": true, "DD": true, "CW": true, "CCW": true, "HD": true, "LOCK": true, "HOLD": true}

type point struct{ x, y int }
type position struct{ rotation, x, y int }
type movement struct {
	position position
	test     int
}
type route struct {
	position position
	keys     []string
}
type candidate struct {
	value int
	kind  byte
	keys  []string
}
type evaluation struct {
	heights                 [10]int
	holes, bumpiness, value int
}
type placement struct {
	board [22]int
	lines int
}
type clearInfo struct {
	name                string
	points, sent, index int
}
type gameEnd struct{}

type statistics struct {
	drops      int64
	holds      int
	operations int
	faults     int
	perfect    int
	sent       int
	cancelled  int
	received   int
	combo      int
	chain      int
	kinds      [7]int
	clears     [11]int
}

type state struct {
	board        [22]int
	random       int64
	queue        []byte
	hold         byte
	usedHold     bool
	kind         byte
	position     position
	last         int
	test         int
	keys         int
	drop         int
	fall         int
	ground       int
	resets       int
	lowest       int
	initialLevel int
	level        int
	score        int64
	lines        int
	pieces       int
	streak       int
	chain        int
	pending      []int
	ended        bool
	stats        statistics
}

func (s state) clone() state {
	s.queue = append([]byte(nil), s.queue...)
	s.pending = append([]int(nil), s.pending...)
	return s
}

type snapshot struct {
	state   state
	history []state
	start   state
}
type game struct {
	serial  int
	state   state
	history []state
	start   state
	saves   map[string]snapshot
}

func copyStates(history []state) []state {
	result := make([]state, len(history))
	for i, entry := range history {
		result[i] = entry.clone()
	}
	return result
}

func nextRandom(value int64) int64 { return value * 48271 % 2147483647 }
func spawn(kind byte) position {
	if kind == 'O' {
		return position{0, 5, 22}
	}
	return position{0, 4, 22}
}

var frames = map[byte][]string{
	'I': {"....", "####", "....", "...."},
	'O': {"##", "##"},
	'T': {".#.", "###", "..."},
	'S': {".##", "##.", "..."},
	'Z': {"##.", ".##", "..."},
	'J': {"#..", "###", "..."},
	'L': {"..#", "###", "..."},
}

func cells(kind byte, pos position) [4]point {
	frame := frames[kind]
	size := len(frame)
	var result [4]point
	count := 0
	for j, row := range frame {
		for i := range row {
			if row[i] != '#' {
				continue
			}
			x, y := i, j
			for r := 0; r < pos.rotation; r++ {
				x, y = size-1-y, x
			}
			result[count] = point{pos.x + x, pos.y - y}
			count++
		}
	}
	return result
}

func lowest(kind byte, pos position) int {
	row := 23
	for _, p := range cells(kind, pos) {
		if p.y < row {
			row = p.y
		}
	}
	return row
}

func fits(board [22]int, kind byte, pos position) bool {
	for _, p := range cells(kind, pos) {
		if p.x < 1 || p.x > 10 || p.y < 1 || p.y > 22 {
			return false
		}
		if board[p.y-1]&(1<<uint(p.x-1)) != 0 {
			return false
		}
	}
	return true
}

var ordinaryKicks = map[string][]point{
	"01": {{0, 0}, {-1, 0}, {-1, 1}, {0, -2}, {-1, -2}},
	"10": {{0, 0}, {1, 0}, {1, -1}, {0, 2}, {1, 2}},
	"12": {{0, 0}, {1, 0}, {1, -1}, {0, 2}, {1, 2}},
	"21": {{0, 0}, {-1, 0}, {-1, 1}, {0, -2}, {-1, -2}},
	"23": {{0, 0}, {1, 0}, {1, 1}, {0, -2}, {1, -2}},
	"32": {{0, 0}, {-1, 0}, {-1, -1}, {0, 2}, {-1, 2}},
	"30": {{0, 0}, {-1, 0}, {-1, -1}, {0, 2}, {-1, 2}},
	"03": {{0, 0}, {1, 0}, {1, 1}, {0, -2}, {1, -2}},
}

var iKicks = map[string][]point{
	"01": {{0, 0}, {-2, 0}, {1, 0}, {-2, -1}, {1, 2}},
	"10": {{0, 0}, {2, 0}, {-1, 0}, {2, 1}, {-1, -2}},
	"12": {{0, 0}, {-1, 0}, {2, 0}, {-1, 2}, {2, -1}},
	"21": {{0, 0}, {1, 0}, {-2, 0}, {1, -2}, {-2, 1}},
	"23": {{0, 0}, {2, 0}, {-1, 0}, {2, 1}, {-1, -2}},
	"32": {{0, 0}, {-2, 0}, {1, 0}, {-2, -1}, {1, 2}},
	"30": {{0, 0}, {1, 0}, {-2, 0}, {1, -2}, {-2, 1}},
	"03": {{0, 0}, {-1, 0}, {2, 0}, {-1, 2}, {2, -1}},
}

func moved(board [22]int, kind byte, pos position, action string) (movement, bool) {
	if action == "CW" || action == "CCW" {
		increment := 1
		if action == "CCW" {
			increment = 3
		}
		target := (pos.rotation + increment) % 4
		offsets := []point{{0, 0}}
		if kind != 'O' {
			key := strconv.Itoa(pos.rotation) + strconv.Itoa(target)
			if kind == 'I' {
				offsets = iKicks[key]
			} else {
				offsets = ordinaryKicks[key]
			}
		}
		for i, delta := range offsets {
			to := position{target, pos.x + delta.x, pos.y + delta.y}
			if fits(board, kind, to) {
				return movement{to, i + 1}, true
			}
		}
		return movement{}, false
	}
	dx := 0
	if action == "L" || action == "LL" {
		dx = -1
	}
	if action == "R" || action == "RR" {
		dx = 1
	}
	dy := 0
	if dx == 0 {
		dy = -1
	}
	repeat := action == "LL" || action == "RR" || action == "DD"
	changed := false
	current := pos
	for {
		next := position{current.rotation, current.x + dx, current.y + dy}
		if !fits(board, kind, next) {
			break
		}
		current = next
		changed = true
		if !repeat {
			break
		}
	}
	return movement{current, 0}, changed
}

func landing(board [22]int, kind byte, pos position) position {
	result, ok := moved(board, kind, pos, "DD")
	if ok {
		return result.position
	}
	return pos
}

func placed(board [22]int, kind byte, pos position) placement {
	result := board
	for _, p := range cells(kind, pos) {
		result[p.y-1] |= 1 << uint(p.x-1)
	}
	var filtered [22]int
	length := 0
	for _, row := range result {
		if row != 1023 {
			filtered[length] = row
			length++
		}
	}
	return placement{filtered, 22 - length}
}

func evaluate(board [22]int, cleared int) evaluation {
	result := evaluation{}
	sum := 0
	for col := 0; col < 10; col++ {
		for row := 21; row >= 0; row-- {
			if board[row]&(1<<uint(col)) != 0 {
				result.heights[col] = row + 1
				break
			}
		}
		sum += result.heights[col]
		for row := 0; row < result.heights[col]; row++ {
			if board[row]&(1<<uint(col)) == 0 {
				result.holes++
			}
		}
		if col > 0 {
			delta := result.heights[col] - result.heights[col-1]
			if delta < 0 {
				delta = -delta
			}
			result.bumpiness += delta
		}
	}
	result.value = 76*cleared - 51*sum - 36*result.holes - 18*result.bumpiness
	return result
}

func routes(board [22]int, kind byte, first position, target *position) []route {
	if !fits(board, kind, first) {
		return nil
	}
	queue := []route{{first, nil}}
	seen := map[position]bool{first: true}
	for i := 0; i < len(queue); i++ {
		entry := queue[i]
		if target != nil && landing(board, kind, entry.position) == *target {
			return []route{entry}
		}
		for _, action := range movements {
			next, ok := moved(board, kind, entry.position, action)
			if ok && !seen[next.position] {
				seen[next.position] = true
				keys := append(append([]string(nil), entry.keys...), action)
				queue = append(queue, route{next.position, keys})
			}
		}
	}
	if target != nil {
		return nil
	}
	return queue
}

func spinType(board [22]int, pos position, test int) string {
	corners := [4]point{{pos.x, pos.y}, {pos.x + 2, pos.y}, {pos.x + 2, pos.y - 2}, {pos.x, pos.y - 2}}
	var occupied [4]bool
	count := 0
	for i, p := range corners {
		occupied[i] = p.x < 1 || p.x > 10 || p.y < 1 || p.y > 22 || board[p.y-1]&(1<<uint(p.x-1)) != 0
		if occupied[i] {
			count++
		}
	}
	if count < 3 {
		return ""
	}
	if (occupied[pos.rotation] && occupied[(pos.rotation+1)%4]) || test == 5 {
		return "full"
	}
	return "mini"
}

func cleared(spin string, lines int) clearInfo {
	if spin == "full" {
		points, sent := [4]int{400, 800, 1200, 1600}, [4]int{0, 2, 4, 6}
		return clearInfo{clearNames[7+lines], points[lines], sent[lines], 7 + lines}
	}
	if spin == "mini" {
		points, sent := [3]int{100, 200, 400}, [3]int{0, 0, 1}
		return clearInfo{clearNames[4+lines], points[lines], sent[lines], 4 + lines}
	}
	if lines == 0 {
		return clearInfo{"", 0, 0, -1}
	}
	points, sent := [5]int{0, 100, 300, 500, 800}, [5]int{0, 0, 1, 2, 4}
	return clearInfo{clearNames[lines-1], points[lines], sent[lines], lines - 1}
}

func sumPending(items []int) int {
	total := 0
	for _, n := range items {
		total += n
	}
	return total
}
func ratio(a, b int64) string {
	value := int64(0)
	if b != 0 {
		value = 100 * a / b
	}
	return fmt.Sprintf("%d.%02d", value/100, value%100)
}

func newGame(serial int, seed int64, level int) *game {
	g := &game{serial: serial, saves: make(map[string]snapshot)}
	g.state.random = seed
	g.state.level, g.state.initialLevel = level, level
	g.state.hold = '-'
	g.addBag()
	g.spawnPiece(g.takeNext())
	g.start = g.state.clone()
	return g
}

func (g *game) addBag() {
	pieces := []byte(kinds)
	for i := 6; i >= 1; i-- {
		g.state.random = nextRandom(g.state.random)
		j := int(g.state.random % int64(i+1))
		pieces[i], pieces[j] = pieces[j], pieces[i]
	}
	g.state.queue = append(g.state.queue, pieces...)
}

func (g *game) takeNext() byte {
	kind := g.state.queue[0]
	g.state.queue = g.state.queue[1:]
	if len(g.state.queue) < 5 {
		g.addBag()
	}
	return kind
}

func (g *game) gameOver(reason string) {
	fmt.Println("game over", reason)
	g.summary()
	g.state.ended = true
	panic(gameEnd{})
}

func (g *game) spawnPiece(kind byte) {
	s := &g.state
	s.kind = kind
	s.position = spawn(kind)
	s.last, s.test, s.keys, s.drop, s.fall, s.ground, s.resets = 0, 0, 0, 0, 0, 0, 0
	s.lowest = lowest(kind, s.position)
	if !fits(s.board, kind, s.position) {
		g.gameOver("block out")
	}
}

func (g *game) updatePosition(pos position, last, test int) {
	s := &g.state
	s.position, s.last, s.test = pos, last, test
	low := lowest(s.kind, pos)
	if low < s.lowest {
		s.lowest, s.resets = low, 0
	}
}

func (g *game) grounded() bool {
	_, ok := moved(g.state.board, g.state.kind, g.state.position, "SD")
	return !ok
}

func (g *game) drops(amount int) {
	s := &g.state
	s.score += int64(amount)
	s.drop += amount
	s.stats.drops += int64(amount)
}

func (g *game) garbage(count, hole int) {
	s := &g.state
	for r := 22 - count; r < 22; r++ {
		if s.board[r] != 0 {
			g.gameOver("top out")
		}
	}
	for r := 21; r >= count; r-- {
		s.board[r] = s.board[r-count]
	}
	for r := 0; r < count; r++ {
		s.board[r] = 1023 ^ (1 << uint(hole-1))
	}
}

func (g *game) operation(action string) {
	s := &g.state
	for _, candidate := range movements {
		if candidate != action {
			continue
		}
		s.keys++
		result, ok := moved(s.board, s.kind, s.position, action)
		if !ok {
			fmt.Println("fail", action)
			return
		}
		if action == "SD" || action == "DD" {
			g.drops(s.position.y - result.position.y)
			g.updatePosition(result.position, 1, 0)
			s.fall, s.ground = 0, 0
		} else {
			rotate := action == "CW" || action == "CCW"
			last := 1
			if rotate {
				last = 2
			}
			g.updatePosition(result.position, last, result.test)
			if s.ground > 0 && s.resets < 15 {
				s.ground = 0
				s.resets++
			}
		}
		return
	}
	switch action {
	case "HD":
		to := landing(s.board, s.kind, s.position)
		rows := s.position.y - to.y
		g.drops(2 * rows)
		if rows > 0 {
			g.updatePosition(to, 1, 0)
		}
		g.lock()
	case "LOCK":
		if g.grounded() {
			g.lock()
		} else {
			fmt.Println("fail LOCK")
		}
	case "HOLD":
		if s.usedHold {
			fmt.Println("fail HOLD")
			return
		}
		s.usedHold = true
		s.stats.holds++
		current := s.kind
		next := s.hold
		if next == '-' {
			next = g.takeNext()
		}
		s.hold = current
		g.spawnPiece(next)
	}
}

func (g *game) tick() {
	s := &g.state
	if !g.grounded() {
		s.ground = 0
		s.fall++
		interval := 1
		if s.level < 13 {
			interval = intervals[s.level-1]
		}
		if s.fall >= interval {
			g.updatePosition(position{s.position.rotation, s.position.x, s.position.y - 1}, 1, 0)
			s.fall = 0
		}
	} else {
		s.ground++
		if s.ground >= 30 {
			g.lock()
		}
	}
}

func (g *game) lock() {
	s := &g.state
	kind, pos := s.kind, s.position
	oldCells := cells(kind, pos)
	shortest := routes(s.board, kind, spawn(kind), &pos)
	spin := ""
	if kind == 'T' && s.last == 2 {
		spin = spinType(s.board, pos, s.test)
	}
	p := placed(s.board, kind, pos)
	s.board = p.board
	n := p.lines
	g.history = append(g.history, g.start.clone())
	s.pieces++
	s.stats.kinds[strings.IndexByte(kinds, kind)]++
	s.stats.operations += s.keys
	info := cleared(spin, n)
	level := s.level
	points, sent := info.points*level, info.sent
	backToBack := false
	if n > 0 {
		s.streak++
		if n == 4 || spin != "" {
			s.chain++
			backToBack = s.chain >= 2
		} else {
			s.chain = 0
		}
	} else {
		s.streak = 0
	}
	if backToBack {
		points = points * 3 / 2
		sent++
	}
	combo := s.streak - 1
	comboPoints := 0
	if combo >= 1 {
		comboPoints = 50 * combo * level
	}
	if combo >= 0 {
		i := combo
		if i > 10 {
			i = 10
		}
		sent += comboSent[i]
	}
	perfect := n > 0
	for _, row := range s.board {
		if row != 0 {
			perfect = false
			break
		}
	}
	perfectPoints := 0
	if perfect {
		table := [4]int{800, 1200, 1800, 2000}
		value := table[n-1]
		if n == 4 && backToBack {
			value = 3200
		}
		perfectPoints = value * level
		sent += 10
		s.stats.perfect++
	}
	gained := points + comboPoints + perfectPoints
	s.score += int64(gained)
	s.lines += n
	s.stats.sent += sent
	if combo > s.stats.combo {
		s.stats.combo = combo
	}
	if s.chain > s.stats.chain {
		s.stats.chain = s.chain
	}
	distance := "-"
	if len(shortest) > 0 {
		distance = strconv.Itoa(len(shortest[0].keys))
	}
	fmt.Printf("lock %d %c %s %d %d keys %d %s drop %d lines %d sent %d +%d total %d\n", s.pieces, kind, stateNames[pos.rotation], pos.x, pos.y, s.keys, distance, s.drop, n, sent, gained, s.score)
	if len(shortest) > 0 && s.keys > len(shortest[0].keys) {
		s.stats.faults++
		sequence := strings.Join(shortest[0].keys, " ")
		if sequence == "" {
			sequence = "none"
		}
		fmt.Println("finesse", sequence)
	}
	if info.index >= 0 {
		s.stats.clears[info.index]++
		output := fmt.Sprintf("clear %s %d", info.name, points)
		if backToBack {
			output += " b2b"
		}
		if combo >= 1 {
			output += fmt.Sprintf(" combo %d %d", combo, comboPoints)
		}
		if perfect {
			output += fmt.Sprintf(" perfect %d", perfectPoints)
		}
		fmt.Println(output)
	}
	nextLevel := s.initialLevel + s.lines/10
	if nextLevel > level {
		s.level = nextLevel
		fmt.Println("level", s.level)
	}
	lockOut := true
	for _, c := range oldCells {
		if c.y < 21 {
			lockOut = false
		}
	}
	if lockOut {
		g.gameOver("lock out")
	}
	cancelled := sent
	if pending := sumPending(s.pending); pending < cancelled {
		cancelled = pending
	}
	remaining := cancelled
	for remaining > 0 {
		count := s.pending[0]
		if count > remaining {
			count = remaining
		}
		s.pending[0] -= count
		remaining -= count
		if s.pending[0] == 0 {
			s.pending = s.pending[1:]
		}
	}
	if cancelled > 0 {
		s.stats.cancelled += cancelled
		fmt.Printf("cancel %d pending %d\n", cancelled, sumPending(s.pending))
	}
	if n == 0 {
		risen := 0
		for len(s.pending) > 0 && risen < 8 {
			count := s.pending[0]
			if count > 8-risen {
				count = 8 - risen
			}
			s.random = nextRandom(s.random)
			hole := int(s.random%10) + 1
			g.garbage(count, hole)
			s.stats.received += count
			risen += count
			s.pending[0] -= count
			if s.pending[0] == 0 {
				s.pending = s.pending[1:]
			}
			fmt.Printf("rise %d hole %d pending %d\n", count, hole, sumPending(s.pending))
		}
	}
	s.usedHold = false
	g.spawnPiece(g.takeNext())
	g.start = s.clone()
}

func (g *game) appendCandidate(list *[]candidate, seen map[[4]int]bool, kind byte, pos position, prefix, turns, shifts []string) {
	down := landing(g.state.board, kind, pos)
	var id [4]int
	for i, p := range cells(kind, down) {
		id[i] = (p.y-1)*10 + p.x - 1
	}
	sort.Ints(id[:])
	if seen[id] {
		return
	}
	seen[id] = true
	p := placed(g.state.board, kind, down)
	keys := make([]string, 0, len(prefix)+len(turns)+len(shifts)+1)
	keys = append(keys, prefix...)
	keys = append(keys, turns...)
	keys = append(keys, shifts...)
	keys = append(keys, "HD")
	*list = append(*list, candidate{evaluate(p.board, p.lines).value, kind, keys})
}

func (g *game) candidates(kind byte, first position, prefix []string) []candidate {
	result := []candidate{}
	seen := make(map[[4]int]bool)
	rotations := [][]string{{}, {"CW"}, {"CW", "CW"}, {"CCW"}}
	for _, turns := range rotations {
		pos := first
		valid := true
		for _, turn := range turns {
			next, ok := moved(g.state.board, kind, pos, turn)
			if !ok {
				valid = false
				break
			}
			pos = next.position
		}
		if !valid {
			continue
		}
		g.appendCandidate(&result, seen, kind, pos, prefix, turns, nil)
		for _, direction := range []string{"L", "R"} {
			shifted := pos
			shifts := []string{}
			for {
				next, ok := moved(g.state.board, kind, shifted, direction)
				if !ok {
					break
				}
				shifted = next.position
				shifts = append(shifts, direction)
				g.appendCandidate(&result, seen, kind, shifted, prefix, turns, shifts)
			}
		}
	}
	return result
}

func (g *game) ranked() []candidate {
	s := &g.state
	result := g.candidates(s.kind, s.position, nil)
	held := s.hold
	if held == '-' {
		held = s.queue[0]
	}
	if !s.usedHold && fits(s.board, held, spawn(held)) {
		result = append(result, g.candidates(held, spawn(held), []string{"HOLD"})...)
	}
	sort.SliceStable(result, func(i, j int) bool { return result[i].value > result[j].value })
	return result
}

func (g *game) spins() {
	s := &g.state
	if s.kind != 'T' {
		fmt.Println("spins 0")
		return
	}
	found := map[position]string{}
	for _, r := range routes(s.board, 'T', s.position, nil) {
		for _, action := range []string{"CW", "CCW"} {
			next, ok := moved(s.board, 'T', r.position, action)
			if !ok {
				continue
			}
			if _, ok = moved(s.board, 'T', next.position, "SD"); ok {
				continue
			}
			spin := spinType(s.board, next.position, next.test)
			if spin != "" && (found[next.position] == "" || spin == "full") {
				found[next.position] = spin
			}
		}
	}
	positions := make([]position, 0, len(found))
	for pos := range found {
		positions = append(positions, pos)
	}
	sort.Slice(positions, func(i, j int) bool {
		a, b := positions[i], positions[j]
		if a.y != b.y {
			return a.y < b.y
		}
		if a.x != b.x {
			return a.x < b.x
		}
		return a.rotation < b.rotation
	})
	for _, pos := range positions {
		n := placed(s.board, 'T', pos).lines
		fmt.Printf("spin %s %d %d %s\n", stateNames[pos.rotation], pos.x, pos.y, cleared(found[pos], n).name)
	}
	fmt.Println("spins", len(positions))
}

func (g *game) summary() {
	s := &g.state
	a := s.stats
	c, k := a.clears, a.kinds
	fmt.Printf("summary game %d score %d level %d lines %d pieces %d\n", g.serial, s.score, s.level, s.lines, s.pieces)
	fmt.Printf("clears single %d double %d triple %d tetris %d perfect %d\n", c[0], c[1], c[2], c[3], a.perfect)
	fmt.Printf("tspins mini %d mini_single %d mini_double %d zero %d single %d double %d triple %d\n", c[4], c[5], c[6], c[7], c[8], c[9], c[10])
	fmt.Printf("pieces I %d O %d T %d S %d Z %d J %d L %d\n", k[0], k[1], k[2], k[3], k[4], k[5], k[6])
	fmt.Printf("best combo %d chain %d holds %d drops %d faults %d\n", a.combo, a.chain, a.holds, a.drops, a.faults)
	fmt.Printf("garbage sent %d cancelled %d received %d\n", a.sent, a.cancelled, a.received)
	fmt.Printf("rates app %s apl %s kpp %s\n", ratio(int64(a.sent), int64(s.pieces)), ratio(int64(a.sent), int64(s.lines)), ratio(int64(a.operations), int64(s.pieces)))
}

func (g *game) command(name string, args []string) {
	s := &g.state
	switch name {
	case "PRINT":
		current, ghost := map[int]bool{}, map[int]bool{}
		if !s.ended {
			for _, p := range cells(s.kind, s.position) {
				current[p.y*10+p.x] = true
			}
			for _, p := range cells(s.kind, landing(s.board, s.kind, s.position)) {
				ghost[p.y*10+p.x] = true
			}
		}
		for row := 22; row >= 1; row-- {
			text := fmt.Sprintf("%2d ", row)
			for col := 1; col <= 10; col++ {
				id := row*10 + col
				if s.board[row-1]&(1<<uint(col-1)) != 0 {
					text += "#"
				} else if current[id] {
					text += "@"
				} else if ghost[id] {
					text += "+"
				} else {
					text += "."
				}
			}
			fmt.Println(text)
		}
	case "NEXT":
		fmt.Printf("hold %c next %s\n", s.hold, string(s.queue[:5]))
	case "PREVIEW":
		n, _ := strconv.Atoi(args[0])
		queue := append([]byte(nil), s.queue...)
		random := s.random
		for len(queue) < n {
			pieces := []byte(kinds)
			for i := 6; i >= 1; i-- {
				random = nextRandom(random)
				j := int(random % int64(i+1))
				pieces[i], pieces[j] = pieces[j], pieces[i]
			}
			queue = append(queue, pieces...)
		}
		fmt.Println("preview", string(queue[:n]))
	case "STATUS":
		fmt.Printf("score %d level %d lines %d pieces %d\n", s.score, s.level, s.lines, s.pieces)
		piece := "-"
		if !s.ended {
			piece = fmt.Sprintf("%c %s %d %d", s.kind, stateNames[s.position.rotation], s.position.x, s.position.y)
		}
		fmt.Printf("piece %s streak %d chain %d pending %d\n", piece, s.streak, s.chain, sumPending(s.pending))
	case "ANALYZE":
		e := evaluate(s.board, 0)
		text := "heights"
		for _, value := range e.heights {
			text += " " + strconv.Itoa(value)
		}
		fmt.Println(text)
		fmt.Printf("holes %d bumpiness %d value %d\n", e.holes, e.bumpiness, e.value)
	case "ROW":
		row, _ := strconv.Atoi(args[0])
		pattern := args[1]
		for _, p := range cells(s.kind, s.position) {
			if p.y == row && pattern[p.x-1] == '#' {
				fmt.Println("ERROR overlap")
				return
			}
		}
		mask := 0
		for c := range pattern {
			if pattern[c] == '#' {
				mask |= 1 << uint(c)
			}
		}
		s.board[row-1] = mask
		fmt.Println("OK")
	case "GARBAGE":
		n, _ := strconv.Atoi(args[0])
		hole, _ := strconv.Atoi(args[1])
		g.garbage(n, hole)
		for j := 0; j <= n; j++ {
			next := position{s.position.rotation, s.position.x, s.position.y + j}
			if fits(s.board, s.kind, next) {
				s.position = next
				fmt.Println("OK")
				return
			}
		}
		g.gameOver("top out")
	case "ATTACK":
		n, _ := strconv.Atoi(args[0])
		s.pending = append(s.pending, n)
		fmt.Println("pending", sumPending(s.pending))
	case "TICK":
		n, _ := strconv.Atoi(args[0])
		for i := 0; i < n; i++ {
			g.tick()
		}
	case "UNDO":
		if len(g.history) == 0 {
			fmt.Println("ERROR nothing to undo")
		} else {
			s = &g.state
			g.state = g.history[len(g.history)-1].clone()
			g.history = g.history[:len(g.history)-1]
			g.start = g.state.clone()
			fmt.Printf("undo %d %c\n", g.state.pieces, g.state.kind)
		}
	case "SAVE":
		g.saves[args[0]] = snapshot{s.clone(), copyStates(g.history), g.start.clone()}
		fmt.Println("OK")
	case "LOAD":
		snap, ok := g.saves[args[0]]
		if !ok {
			fmt.Println("ERROR unknown save")
		} else {
			g.state = snap.state.clone()
			g.history = copyStates(snap.history)
			g.start = snap.start.clone()
			fmt.Printf("load %d %c\n", g.state.pieces, g.state.kind)
		}
	case "SPINS":
		g.spins()
	case "HINT":
		n, _ := strconv.Atoi(args[0])
		ranked := g.ranked()
		if n > len(ranked) {
			n = len(ranked)
		}
		for i := 0; i < n; i++ {
			entry := ranked[i]
			fmt.Printf("hint %d %c %s value %d\n", i+1, entry.kind, strings.Join(entry.keys, " "), entry.value)
		}
	case "AUTO":
		n, _ := strconv.Atoi(args[0])
		for i := 0; i < n; i++ {
			ranked := g.ranked()
			if len(ranked) == 0 {
				break
			}
			best := ranked[0]
			fmt.Printf("auto %c %s\n", best.kind, strings.Join(best.keys, " "))
			for _, action := range best.keys {
				g.operation(action)
			}
		}
	}
}

func number(word string, low, high int64) bool {
	if len(word) == 0 || (len(word) > 1 && word[0] == '0') {
		return false
	}
	var value int64
	for _, c := range word {
		if c < '0' || c > '9' {
			return false
		}
		value = value*10 + int64(c-'0')
		if value > high {
			return false
		}
	}
	return value >= low
}

func argumentsValid(name string, args []string) bool {
	switch name {
	case "NEW":
		return len(args) == 2 && number(args[0], 1, 2147483646) && number(args[1], 1, 15)
	case "ROW":
		if len(args) != 2 || !number(args[0], 1, 22) || len(args[1]) != 10 || !strings.Contains(args[1], ".") {
			return false
		}
		for _, c := range args[1] {
			if c != '#' && c != '.' {
				return false
			}
		}
		return true
	case "GARBAGE":
		return len(args) == 2 && number(args[0], 1, 10) && number(args[1], 1, 10)
	case "SAVE", "LOAD":
		if len(args) != 1 || len(args[0]) == 0 || len(args[0]) > 8 {
			return false
		}
		for _, c := range args[0] {
			if c < 'a' || c > 'z' {
				return false
			}
		}
		return true
	}
	limits := map[string]int{"PREVIEW": 14, "ATTACK": 20, "TICK": 1000, "HINT": 10, "AUTO": 50}
	if high, ok := limits[name]; ok {
		return len(args) == 1 && number(args[0], 1, int64(high))
	}
	return len(args) == 0
}

func process(line string, current **game, serial *int) {
	defer func() {
		if value := recover(); value != nil {
			if _, ok := value.(gameEnd); !ok {
				panic(value)
			}
		}
	}()
	words := strings.Fields(line)
	if len(words) == 0 {
		return
	}
	name, args := words[0], words[1:]
	if commands[name] {
		if !argumentsValid(name, args) {
			fmt.Println("ERROR bad arguments")
			return
		}
		if name == "NEW" {
			if *current != nil && !(*current).state.ended {
				fmt.Println("game stopped")
				(*current).summary()
			}
			seed, _ := strconv.ParseInt(args[0], 10, 64)
			level, _ := strconv.Atoi(args[1])
			*serial = *serial + 1
			fmt.Printf("game %d seed %d level %d\n", *serial, seed, level)
			*current = newGame(*serial, seed, level)
		} else if *current == nil {
			fmt.Println("ERROR no game")
		} else if (*current).state.ended && !afterEnd[name] {
			fmt.Println("ERROR game over")
		} else {
			(*current).command(name, args)
		}
	} else {
		for _, word := range words {
			if !operations[word] {
				fmt.Println("ERROR unknown", word)
				return
			}
		}
		if *current == nil {
			fmt.Println("ERROR no game")
			return
		}
		if (*current).state.ended {
			fmt.Println("ERROR game over")
			return
		}
		for _, action := range words {
			(*current).operation(action)
		}
	}
}

func main() {
	input := bufio.NewScanner(os.Stdin)
	input.Buffer(make([]byte, 1024), 1024*1024)
	if !input.Scan() {
		return
	}
	count, _ := strconv.Atoi(strings.TrimSpace(input.Text()))
	var current *game
	serial := 0
	for i := 0; i < count && input.Scan(); i++ {
		process(input.Text(), &current, &serial)
	}
	if current != nil && !current.state.ended {
		fmt.Println("game stopped")
		current.summary()
	}
}
