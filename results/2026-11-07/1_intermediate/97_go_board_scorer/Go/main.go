package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

const columns = "ABCDEFGHJKLMNOPQRST"

var handicapPoints = map[int][]string{9: strings.Fields("C3 G7 C7 G3 C5 G5 E3 E7 E5"), 13: strings.Fields("D4 K10 D10 K4 D7 K7 G4 G10 G7"), 19: strings.Fields("D4 Q16 D16 Q4 D10 Q10 K4 K16 K10")}
var arity = map[string]int{"BOARD": 2, "KOMI": 1, "SUPERKO": 1, "HANDICAP": 1, "PLAY": 2, "PASS": 1, "REPLAY": 1, "UNDO": 0, "SHOW": 0, "MAP": 0, "STATUS": 0, "CAPTURES": 0, "HISTORY": 0, "MOVES": 0, "GROUP": 1, "GROUPS": 0, "ATARI": 0, "LEGAL": 1, "EYES": 1, "SAFE": 1, "LADDER": 1, "DEAD": 1, "REGIONS": 0, "SCORE": 1}

func other(c byte) byte {
	if c == 'B' {
		return 'W'
	}
	return 'B'
}
func colorIndex(c byte) int {
	if c == 'B' {
		return 0
	}
	return 1
}
func half(x int) string {
	sign := ""
	if x < 0 {
		sign = "-"
		x = -x
	}
	return fmt.Sprintf("%s%d.%d", sign, x/2, (x%2)*5)
}

var komiPattern = regexp.MustCompile(`^-?(0|[1-9][0-9]*)(?:\.[05])?$`)

func komi(s string) (int, bool) {
	if !komiPattern.MatchString(s) {
		return 0, false
	}
	negative := s[0] == '-'
	unsigned := s
	if negative {
		unsigned = s[1:]
	}
	a := strings.Split(unsigned, ".")
	whole, err := strconv.Atoi(a[0])
	if err != nil || whole > 100 {
		return 0, false
	}
	x := 2 * whole
	if len(a) == 2 && a[1] == "5" {
		x++
	}
	if negative {
		if x == 0 {
			return 0, false
		}
		x = -x
	}
	return x, true
}

type Points map[int]bool

func (s Points) sorted() []int {
	a := make([]int, 0, len(s))
	for p := range s {
		a = append(a, p)
	}
	sort.Ints(a)
	return a
}
func (s Points) copy() Points {
	r := Points{}
	for p := range s {
		r[p] = true
	}
	return r
}
func (s Points) union(b Points) {
	for p := range b {
		s[p] = true
	}
}
func (s Points) subset(b Points) bool {
	for p := range s {
		if !b[p] {
			return false
		}
	}
	return true
}
func adjacent(p, n int, diagonal bool) []int {
	r, c := p/n, p%n
	steps := [][2]int{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}
	if diagonal {
		steps = [][2]int{{-1, -1}, {-1, 1}, {1, -1}, {1, 1}}
	}
	a := []int{}
	for _, d := range steps {
		rr, cc := r+d[0], c+d[1]
		if rr >= 0 && rr < n && cc >= 0 && cc < n {
			a = append(a, rr*n+cc)
		}
	}
	return a
}
func flood(b string, n, p int, allowed string) Points {
	seen, todo := Points{p: true}, []int{p}
	for len(todo) > 0 {
		q := todo[len(todo)-1]
		todo = todo[:len(todo)-1]
		for _, t := range adjacent(q, n, false) {
			if !seen[t] && strings.ContainsRune(allowed, rune(b[t])) {
				seen[t] = true
				todo = append(todo, t)
			}
		}
	}
	return seen
}

type Group struct {
	Color             byte
	First             int
	Stones, Liberties Points
}

func group(b string, n, p int) Group {
	s := flood(b, n, p, string(b[p]))
	l := Points{}
	for q := range s {
		for _, t := range adjacent(q, n, false) {
			if b[t] == '.' {
				l[t] = true
			}
		}
	}
	return Group{b[p], s.sorted()[0], s, l}
}
func groups(b string, n int, color byte) []Group {
	out := []Group{}
	seen := Points{}
	for p := range len(b) {
		if b[p] != '.' && !seen[p] && (color == 0 || b[p] == color) {
			g := group(b, n, p)
			seen.union(g.Stones)
			out = append(out, g)
		}
	}
	return out
}

type Placement struct {
	Board    string
	Captured int
	Reason   string
}

func placement(b string, n int, c byte, p int) Placement {
	if b[p] != '.' {
		return Placement{b, 0, "occupied"}
	}
	next := []byte(b)
	next[p] = c
	captured := 0
	seen := Points{}
	for _, q := range adjacent(p, n, false) {
		if next[q] == other(c) && !seen[q] {
			g := group(string(next), n, q)
			seen.union(g.Stones)
			if len(g.Liberties) == 0 {
				for t := range g.Stones {
					next[t] = '.'
				}
				captured += len(g.Stones)
			}
		}
	}
	value := string(next)
	reason := ""
	if len(group(value, n, p).Liberties) == 0 {
		reason = "suicide"
	}
	return Placement{value, captured, reason}
}

type Region struct {
	First  int
	Points Points
	Owner  string
}

func regions(b string, n int) []Region {
	out := []Region{}
	seen := Points{}
	for p := range len(b) {
		if b[p] == '.' && !seen[p] {
			points := flood(b, n, p, ".")
			seen.union(points)
			border := map[byte]bool{}
			for q := range points {
				for _, t := range adjacent(q, n, false) {
					if b[t] != '.' {
						border[b[t]] = true
					}
				}
			}
			owner := "neutral"
			if len(border) == 1 {
				for c := range border {
					owner = string(c)
				}
			}
			out = append(out, Region{p, points, owner})
		}
	}
	return out
}
func safeGroups(b string, n int, c byte) []Group {
	own := groups(b, n, c)
	touch, vital := []Points{}, []Points{}
	seen := Points{}
	for p := range len(b) {
		if b[p] != c && !seen[p] {
			area := flood(b, n, p, "."+string(other(c)))
			seen.union(area)
			empty := Points{}
			for q := range area {
				if b[q] == '.' {
					empty[q] = true
				}
			}
			t, v := Points{}, Points{}
			for i, g := range own {
				touches := false
				for q := range area {
					for _, a := range adjacent(q, n, false) {
						if g.Stones[a] {
							touches = true
						}
					}
				}
				if touches {
					t[i] = true
				}
				if empty.subset(g.Liberties) {
					v[i] = true
				}
			}
			touch = append(touch, t)
			vital = append(vital, v)
		}
	}
	s, t := Points{}, Points{}
	for i := range own {
		s[i] = true
	}
	for j := range touch {
		t[j] = true
	}
	for {
		before := len(s) + len(t)
		nextS, nextT := Points{}, Points{}
		for i := range s {
			count := 0
			for j := range t {
				if vital[j][i] {
					count++
				}
			}
			if count >= 2 {
				nextS[i] = true
			}
		}
		s = nextS
		for j := range t {
			if touch[j].subset(s) {
				nextT[j] = true
			}
		}
		t = nextT
		if before == len(s)+len(t) {
			break
		}
	}
	out := []Group{}
	for _, i := range s.sorted() {
		out = append(out, own[i])
	}
	return out
}

type ReadKey struct {
	Board     string
	Depth     int
	Defending bool
}
type Reading struct {
	Success bool
	Move    int
}

func ladder(b string, n, p int) (string, int) {
	defender, attacker := b[p], other(b[p])
	memo := map[ReadKey]Reading{}
	var read func(string, int, bool) Reading
	read = func(current string, depth int, defending bool) Reading {
		if depth >= 40 {
			return Reading{defending, -1}
		}
		key := ReadKey{current, depth, defending}
		if r, ok := memo[key]; ok {
			return r
		}
		g := group(current, n, p)
		candidates := g.Liberties.copy()
		seen := Points{}
		if defending {
			for q := range g.Stones {
				for _, t := range adjacent(q, n, false) {
					if current[t] == attacker && !seen[t] {
						e := group(current, n, t)
						seen.union(e.Stones)
						if len(e.Liberties) == 1 {
							candidates.union(e.Liberties)
						}
					}
				}
			}
		}
		for _, q := range candidates.sorted() {
			color := attacker
			if defending {
				color = defender
			}
			next := placement(current, n, color, q)
			if next.Reason != "" {
				continue
			}
			success := false
			if defending {
				count := len(group(next.Board, n, p).Liberties)
				success = count >= 3 || (count == 2 && !read(next.Board, depth+1, false).Success)
			} else {
				success = !read(next.Board, depth+1, true).Success
			}
			if success {
				r := Reading{true, q}
				memo[key] = r
				return r
			}
		}
		r := Reading{false, -1}
		memo[key] = r
		return r
	}
	count := len(group(b, n, p).Liberties)
	if count >= 3 {
		return "safe", -1
	}
	r := read(b, 0, count == 1)
	escapes := !r.Success
	if count == 1 {
		escapes = r.Success
	}
	if escapes {
		return "escapes", r.Move
	}
	return "captured", r.Move
}

type Snapshot struct {
	Board    string
	Turn     byte
	Captures [2]int
	Passes   int
	Over     bool
}
type Move struct {
	Color           byte
	Point, Captured int
	Before          Snapshot
}
type Game struct {
	N, Komi, Passes int
	Board           string
	Turn            byte
	Captures        [2]int
	Over, Superko   bool
	Handicap        []int
	History         []Move
	Positions       []string
	Dead            Points
	Out             io.Writer
}

func (g *Game) emit(a ...any) { fmt.Fprintln(g.Out, a...) }
func (g *Game) reset(n, k int) {
	g.N = n
	g.Komi = k
	g.Board = strings.Repeat(".", n*n)
	g.Turn = 'B'
	g.Captures = [2]int{}
	g.Passes = 0
	g.Over = false
	g.Handicap = nil
	g.History = nil
	g.Positions = []string{g.Board}
	g.Dead = Points{}
}

var pointPattern = regexp.MustCompile(`^[A-HJ-T](?:[1-9]|1[0-9])$`)

func (g *Game) point(s string) int {
	if !pointPattern.MatchString(s) {
		return -1
	}
	c := strings.IndexByte(columns, s[0])
	r, _ := strconv.Atoi(s[1:])
	if c < g.N && r <= g.N {
		return (r-1)*g.N + c
	}
	return -1
}
func (g *Game) name(p int) string { return string(columns[p%g.N]) + strconv.Itoa(p/g.N+1) }
func (g *Game) sgf(p int) string  { return string([]byte{byte(97 + p%g.N), byte(97 + g.N - 1 - p/g.N)}) }
func (g *Game) check(c byte, p int) Placement {
	r := placement(g.Board, g.N, c, p)
	if r.Reason == "" && len(g.Positions) >= 2 && r.Board == g.Positions[len(g.Positions)-2] {
		r.Reason = "ko"
	}
	if r.Reason == "" && g.Superko {
		for _, old := range g.Positions {
			if old == r.Board {
				r.Reason = "superko"
				break
			}
		}
	}
	return r
}
func (g *Game) move(c byte, p int, checked *Placement) int {
	before := Snapshot{g.Board, g.Turn, g.Captures, g.Passes, g.Over}
	captured := 0
	if p < 0 {
		g.Passes++
		if g.Passes == 2 {
			g.Over = true
		}
	} else {
		r := checked
		if r == nil {
			value := g.check(c, p)
			r = &value
		}
		g.Board = r.Board
		captured = r.Captured
		g.Captures[colorIndex(c)] += captured
		g.Passes = 0
	}
	g.Turn = other(c)
	g.History = append(g.History, Move{c, p, captured, before})
	g.Positions = append(g.Positions, g.Board)
	g.Dead = Points{}
	return captured
}
func (g *Game) clean() string {
	b := []byte(g.Board)
	for p := range g.Dead {
		b[p] = '.'
	}
	return string(b)
}
func (g *Game) show(regionMap bool) {
	b := g.Board
	if regionMap {
		b = g.clean()
	}
	chars := []byte(b)
	stars := Points{}
	for i, s := range handicapPoints[g.N] {
		if g.N == 19 || i < 4 || i == 8 {
			stars[g.point(s)] = true
		}
	}
	if regionMap {
		for _, r := range regions(b, g.N) {
			c := byte('.')
			if r.Owner == "B" {
				c = 'x'
			} else if r.Owner == "W" {
				c = 'o'
			}
			for p := range r.Points {
				chars[p] = c
			}
		}
	}
	for p := range len(b) {
		if b[p] != '.' {
			c := byte('X')
			if b[p] == 'W' {
				c = 'O'
			}
			if !regionMap && g.Dead[p] {
				c += 32
			}
			chars[p] = c
		} else if !regionMap {
			chars[p] = '.'
			if stars[p] {
				chars[p] = '+'
			}
		}
	}
	letters := strings.Split(columns[:g.N], "")
	header := "   " + strings.Join(letters, " ")
	g.emit(header)
	for r := g.N; r >= 1; r-- {
		row := strings.Split(string(chars[(r-1)*g.N:r*g.N]), "")
		g.emit(fmt.Sprintf("%2d", r), strings.Join(row, " "), r)
	}
	g.emit(header)
}
func (g *Game) score(method string) {
	b := g.clean()
	territory, total := [2]int{}, [2]int{}
	for _, r := range regions(b, g.N) {
		if r.Owner != "neutral" {
			territory[colorIndex(r.Owner[0])] += len(r.Points)
		}
	}
	for _, c := range []byte{'B', 'W'} {
		i := colorIndex(c)
		fields := []any{string(c)}
		if method == "AREA" {
			stones := strings.Count(b, string(c))
			total[i] = 2 * (stones + territory[i])
			fields = append(fields, "stones", stones, "territory", territory[i])
		} else {
			prisoners := g.Captures[i]
			for p := range g.Dead {
				if g.Board[p] == other(c) {
					prisoners++
				}
			}
			total[i] = 2 * (territory[i] + prisoners)
			fields = append(fields, "territory", territory[i], "prisoners", prisoners)
		}
		if c == 'W' {
			total[i] += g.Komi
			fields = append(fields, "komi", half(g.Komi))
		}
		fields = append(fields, "total", half(total[i]))
		g.emit(fields...)
	}
	d := total[0] - total[1]
	result := "Draw"
	if d > 0 {
		result = "B+" + half(d)
	} else if d < 0 {
		result = "W+" + half(-d)
	}
	g.emit("result", result)
}

var sequencePattern = regexp.MustCompile(`^(?:;[BW]\[[a-z]{0,2}\])+$`)
var recordPattern = regexp.MustCompile(`;([BW])\[([a-z]*)\]`)

func (g *Game) execute(line string) {
	words := strings.Split(line, " ")
	c, a := words[0], words[1:]
	count, ok := arity[c]
	if !ok {
		g.emit("ERROR unknown command")
		return
	}
	if len(a) != count {
		g.emit("ERROR bad arguments")
		return
	}
	valid := true
	switch c {
	case "BOARD":
		_, ok := komi(a[1])
		valid = (a[0] == "9" || a[0] == "13" || a[0] == "19") && ok
	case "KOMI":
		_, valid = komi(a[0])
	case "SUPERKO":
		valid = a[0] == "ON" || a[0] == "OFF"
	case "HANDICAP":
		valid = len(a[0]) == 1 && a[0][0] >= '2' && a[0][0] <= '9'
	case "PLAY", "PASS", "LEGAL", "EYES", "SAFE":
		valid = a[0] == "B" || a[0] == "W"
	case "SCORE":
		valid = a[0] == "AREA" || a[0] == "TERRITORY"
	}
	if !valid {
		g.emit("ERROR bad arguments")
		return
	}
	p := -1
	switch c {
	case "PLAY", "GROUP", "LADDER", "DEAD":
		i := 0
		if c == "PLAY" {
			i = 1
		}
		p = g.point(a[i])
		if p < 0 {
			g.emit("ERROR bad point")
			return
		}
	}
	type record struct {
		Color byte
		Point int
	}
	records := []record{}
	if c == "REPLAY" {
		if !sequencePattern.MatchString(a[0]) {
			g.emit("ERROR bad sequence")
			return
		}
		for _, m := range recordPattern.FindAllStringSubmatch(a[0], -1) {
			s := m[2]
			if s != "" && (len(s) != 2 || int(s[0]-'a') >= g.N || int(s[1]-'a') >= g.N) {
				g.emit("ERROR bad sequence")
				return
			}
			q := -1
			if s != "" {
				q = (g.N-1-int(s[1]-'a'))*g.N + int(s[0]-'a')
			}
			records = append(records, record{m[1][0], q})
		}
	}
	if (c == "PLAY" || c == "PASS" || c == "REPLAY") && g.Over {
		g.emit("ERROR game over")
		return
	}
	switch c {
	case "BOARD":
		n, _ := strconv.Atoi(a[0])
		k, _ := komi(a[1])
		g.reset(n, k)
		g.emit("board", g.N, "komi", half(g.Komi))
	case "KOMI":
		g.Komi, _ = komi(a[0])
		g.emit("komi", half(g.Komi))
	case "SUPERKO":
		g.Superko = a[0] == "ON"
		setting := "off"
		if g.Superko {
			setting = "on"
		}
		g.emit("superko", setting)
	case "HANDICAP":
		if len(g.History) > 0 || strings.ContainsAny(g.Board, "BW") {
			g.emit("ERROR handicap not allowed")
			return
		}
		k, _ := strconv.Atoi(a[0])
		ix := []int{}
		if k == 5 {
			ix = []int{0, 1, 2, 3, 8}
		} else if k == 7 {
			ix = []int{0, 1, 2, 3, 4, 5, 8}
		} else {
			for i := range k {
				ix = append(ix, i)
			}
		}
		b := []byte(g.Board)
		g.Handicap = nil
		fields := []any{"handicap", k}
		for _, i := range ix {
			q := g.point(handicapPoints[g.N][i])
			g.Handicap = append(g.Handicap, q)
			b[q] = 'B'
			fields = append(fields, g.name(q))
		}
		g.Board = string(b)
		g.Turn = 'W'
		g.Positions = []string{g.Board}
		g.Dead = Points{}
		g.emit(fields...)
	case "PLAY":
		color := a[0][0]
		r := g.check(color, p)
		reason := r.Reason
		if color != g.Turn {
			reason = "turn"
		}
		if reason != "" {
			g.emit("ILLEGAL", a[0], a[1], reason)
		} else {
			count := g.move(color, p, &r)
			fields := []any{a[0], a[1]}
			if count > 0 {
				fields = append(fields, "captures", count)
			}
			g.emit(fields...)
		}
	case "PASS":
		if a[0][0] != g.Turn {
			g.emit("ILLEGAL", a[0], "pass turn")
		} else {
			g.move(a[0][0], -1, nil)
			g.emit(a[0], "pass")
			if g.Over {
				g.emit("game over")
			}
		}
	case "REPLAY":
		played := 0
		stop := []any{}
		for _, m := range records {
			var checked *Placement
			if m.Point >= 0 {
				r := g.check(m.Color, m.Point)
				checked = &r
			}
			reason := ""
			if g.Over {
				reason = "game over"
			} else if m.Color != g.Turn {
				reason = "turn"
			} else if checked != nil {
				reason = checked.Reason
			}
			if reason != "" {
				label := "pass"
				if m.Point >= 0 {
					label = g.name(m.Point)
				}
				stop = []any{"stopped", string(m.Color), label, reason}
				break
			}
			g.move(m.Color, m.Point, checked)
			played++
		}
		g.emit(append([]any{"replay", played, "moves"}, stop...)...)
		if g.Over {
			g.emit("game over")
		}
	case "UNDO":
		if len(g.History) == 0 {
			g.emit("ERROR nothing to undo")
			return
		}
		m := g.History[len(g.History)-1]
		g.History = g.History[:len(g.History)-1]
		s := m.Before
		g.Board, g.Turn, g.Captures, g.Passes, g.Over = s.Board, s.Turn, s.Captures, s.Passes, s.Over
		g.Positions = g.Positions[:len(g.Positions)-1]
		g.Dead = Points{}
		label := "pass"
		if m.Point >= 0 {
			label = g.name(m.Point)
		}
		g.emit("undo", string(m.Color), label)
	case "SHOW", "MAP":
		g.show(c == "MAP")
	case "STATUS":
		setting := "off"
		if g.Superko {
			setting = "on"
		}
		g.emit("size", g.N, "komi", half(g.Komi), "handicap", len(g.Handicap), "superko", setting)
		if g.Over {
			g.emit("moves", len(g.History), "game over")
		} else {
			g.emit("moves", len(g.History), "next", string(g.Turn), "passes", g.Passes)
		}
	case "CAPTURES":
		g.emit("captures B", g.Captures[0], "W", g.Captures[1])
	case "HISTORY":
		g.emit("history", len(g.History))
		for i, m := range g.History {
			label := "pass"
			if m.Point >= 0 {
				label = g.name(m.Point)
			}
			fields := []any{i + 1, string(m.Color), label}
			if m.Captured > 0 {
				fields = append(fields, "captures", m.Captured)
			}
			g.emit(fields...)
		}
	case "MOVES":
		var s strings.Builder
		fmt.Fprintf(&s, "(;GM[1]FF[4]SZ[%d]KM[%s]", g.N, half(g.Komi))
		if len(g.Handicap) > 0 {
			fmt.Fprintf(&s, "HA[%d]AB", len(g.Handicap))
			for _, q := range g.Handicap {
				fmt.Fprintf(&s, "[%s]", g.sgf(q))
			}
		}
		for _, m := range g.History {
			coordinate := ""
			if m.Point >= 0 {
				coordinate = g.sgf(m.Point)
			}
			fmt.Fprintf(&s, ";%c[%s]", m.Color, coordinate)
		}
		s.WriteByte(')')
		g.emit(s.String())
	case "GROUP", "DEAD", "LADDER":
		if g.Board[p] == '.' {
			g.emit("ERROR no stone")
			return
		}
		gr := group(g.Board, g.N, p)
		if c == "GROUP" {
			g.emit("group", string(gr.Color), g.name(gr.First), "size", len(gr.Stones), "liberties", len(gr.Liberties))
			stones, liberties := []any{"stones"}, []any{"liberties"}
			for _, q := range gr.Stones.sorted() {
				stones = append(stones, g.name(q))
			}
			for _, q := range gr.Liberties.sorted() {
				liberties = append(liberties, g.name(q))
			}
			g.emit(stones...)
			g.emit(liberties...)
		} else if c == "DEAD" {
			alive := g.Dead[p]
			status := "dead"
			for q := range gr.Stones {
				if alive {
					delete(g.Dead, q)
				} else {
					g.Dead[q] = true
				}
			}
			if alive {
				status = "alive"
			}
			g.emit(status, string(gr.Color), g.name(gr.First), "size", len(gr.Stones))
		} else {
			status, q := ladder(g.Board, g.N, p)
			fields := []any{"ladder", a[0], status}
			if q >= 0 {
				fields = append(fields, g.name(q))
			}
			g.emit(fields...)
		}
	case "GROUPS":
		gs := groups(g.Board, g.N, 0)
		g.emit("groups", len(gs))
		for _, gr := range gs {
			fields := []any{string(gr.Color), g.name(gr.First), "size", len(gr.Stones), "liberties", len(gr.Liberties)}
			if g.Dead[gr.First] {
				fields = append(fields, "dead")
			}
			g.emit(fields...)
		}
	case "ATARI":
		found := false
		for _, gr := range groups(g.Board, g.N, 0) {
			if len(gr.Liberties) == 1 {
				found = true
				g.emit("atari", string(gr.Color), g.name(gr.First), "size", len(gr.Stones), "at", g.name(gr.Liberties.sorted()[0]))
			}
		}
		if !found {
			g.emit("atari none")
		}
	case "LEGAL":
		rejected := [][2]string{}
		legal := 0
		for q := range len(g.Board) {
			if g.Board[q] == '.' {
				reason := g.check(a[0][0], q).Reason
				if reason == "" {
					legal++
				} else {
					rejected = append(rejected, [2]string{g.name(q), reason})
				}
			}
		}
		g.emit("legal", a[0], legal)
		for _, r := range rejected {
			g.emit(r[0], r[1])
		}
	case "EYES":
		found := [][2]string{}
		for q := range len(g.Board) {
			if g.Board[q] == '.' {
				ns := adjacent(q, g.N, false)
				all := true
				for _, t := range ns {
					if g.Board[t] != a[0][0] {
						all = false
					}
				}
				if all {
					enemies := 0
					for _, t := range adjacent(q, g.N, true) {
						if g.Board[t] == other(a[0][0]) {
							enemies++
						}
					}
					limit := 0
					if len(ns) == 4 {
						limit = 1
					}
					kind := "false"
					if enemies <= limit {
						kind = "real"
					}
					found = append(found, [2]string{g.name(q), kind})
				}
			}
		}
		g.emit("eyes", a[0], len(found))
		for _, r := range found {
			g.emit(r[0], r[1])
		}
	case "SAFE":
		gs := safeGroups(g.Board, g.N, a[0][0])
		g.emit("safe", a[0], len(gs))
		for _, gr := range gs {
			g.emit(g.name(gr.First), "size", len(gr.Stones))
		}
	case "REGIONS":
		rs := regions(g.clean(), g.N)
		g.emit("regions", len(rs))
		for _, r := range rs {
			g.emit(g.name(r.First), "size", len(r.Points), r.Owner)
		}
	case "SCORE":
		g.score(a[0])
	}
}
func main() {
	input := bufio.NewScanner(os.Stdin)
	input.Scan()
	count, _ := strconv.Atoi(input.Text())
	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()
	g := Game{Out: out}
	g.reset(19, 13)
	for i := 0; i < count && input.Scan(); i++ {
		g.execute(input.Text())
	}
}
