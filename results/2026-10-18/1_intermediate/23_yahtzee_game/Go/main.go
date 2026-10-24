package main

import (
	"bufio"
	"fmt"
	"os"
	"regexp"
	"slices"
	"sort"
	"strconv"
	"strings"
)

var categories = []string{
	"ONES", "TWOS", "THREES", "FOURS", "FIVES", "SIXES",
	"THREEKIND", "FOURKIND", "FULLHOUSE", "SMALL", "LARGE", "YAHTZEE", "CHANCE",
}
var strategies = map[string]bool{"KIND": true, "STRAIGHT": true, "HIGH": true, "UPPER": true}
var integerSyntax = regexp.MustCompile(`^-?(0|[1-9][0-9]*)$`)
var playerSyntax = regexp.MustCompile(`^[A-Z]{1,8}$`)
var patternSyntax = regexp.MustCompile(`^[01]{5}$`)

const modulus int64 = 2147483647
const multiplier int64 = 48271
const outcomeScale int64 = 7776

func intText(i int) string             { return strconv.Itoa(i) }
func errorLine(reason string) []string { return []string{"error: " + reason} }
func validNumber(word string, lo, hi int) (int, string) {
	if word == "-0" || !integerSyntax.MatchString(word) {
		return 0, "bad value " + word
	}
	value, err := strconv.ParseInt(word, 10, 64)
	if err != nil || value < int64(lo) || value > int64(hi) {
		return 0, "bad value " + word
	}
	return int(value), ""
}
func validName(word string) string {
	if !playerSyntax.MatchString(word) {
		return "bad name " + word
	}
	return ""
}
func validCategory(word string) string {
	if !slices.Contains(categories, word) {
		return "bad category " + word
	}
	return ""
}
func validStrategy(word string) string {
	if !strategies[word] {
		return "bad strategy " + word
	}
	return ""
}
func validPattern(word string) ([5]bool, string) {
	var holds [5]bool
	if !patternSyntax.MatchString(word) {
		return holds, "bad pattern " + word
	}
	for i, c := range word {
		holds[i] = c == '1'
	}
	return holds, ""
}
func holdText(holds [5]bool) string {
	var text [5]byte
	for i, hold := range holds {
		if hold {
			text[i] = '1'
		} else {
			text[i] = '0'
		}
	}
	return string(text[:])
}
func faceText(faces []int) string {
	if len(faces) == 0 {
		return "-"
	}
	parts := make([]string, len(faces))
	for i, face := range faces {
		parts[i] = strconv.Itoa(face)
	}
	return strings.Join(parts, " ")
}
func heldFaces(faces [5]int, holds [5]bool) []int {
	result := make([]int, 0, 5)
	for i, hold := range holds {
		if hold {
			result = append(result, faces[i])
		}
	}
	return result
}
func gcd(a, b int64) int64 {
	for b != 0 {
		a, b = b, a%b
	}
	return a
}
func fractionText(a, b int64) string {
	d := gcd(a, b)
	a /= d
	b /= d
	if b == 1 {
		return strconv.FormatInt(a, 10)
	}
	return strconv.FormatInt(a, 10) + "/" + strconv.FormatInt(b, 10)
}
func averageText(total, count int) string {
	value := 0
	if count > 0 {
		value = 100 * total / count
	}
	return fmt.Sprintf("%d.%02d", value/100, value%100)
}
func isYahtzee(faces [5]int) bool {
	for _, face := range faces {
		if face != faces[0] {
			return false
		}
	}
	return true
}
func normalScore(category string, faces [5]int) int {
	var counts [6]int
	sum := 0
	for _, face := range faces {
		counts[face-1]++
		sum += face
	}
	for f := 0; f < 6; f++ {
		if categories[f] == category {
			return (f + 1) * counts[f]
		}
	}
	maxCount := 0
	for _, count := range counts {
		if count > maxCount {
			maxCount = count
		}
	}
	switch category {
	case "THREEKIND":
		if maxCount >= 3 {
			return sum
		}
	case "FOURKIND":
		if maxCount >= 4 {
			return sum
		}
	case "FULLHOUSE":
		three, two := false, false
		for _, count := range counts {
			if count == 3 {
				three = true
			}
			if count == 2 {
				two = true
			}
		}
		if three && two {
			return 25
		}
	case "SMALL":
		for start := 0; start < 3; start++ {
			if counts[start] > 0 && counts[start+1] > 0 && counts[start+2] > 0 && counts[start+3] > 0 {
				return 30
			}
		}
	case "LARGE":
		for start := 0; start < 2; start++ {
			if counts[start] > 0 && counts[start+1] > 0 && counts[start+2] > 0 && counts[start+3] > 0 && counts[start+4] > 0 {
				return 40
			}
		}
	case "YAHTZEE":
		if maxCount == 5 {
			return 50
		}
	case "CHANCE":
		return sum
	}
	return 0
}
func mostFrequent(faces [5]int) int {
	var counts [6]int
	for _, face := range faces {
		counts[face-1]++
	}
	best := 1
	for face := 2; face <= 6; face++ {
		if counts[face-1] >= counts[best-1] {
			best = face
		}
	}
	return best
}
func botHolds(strategy string, faces [5]int) [5]bool {
	var holds [5]bool
	if strategy == "HIGH" {
		for i, face := range faces {
			holds[i] = face >= 5
		}
		return holds
	}
	if strategy == "STRAIGHT" {
		var present [7]bool
		for _, face := range faces {
			present[face] = true
		}
		bestStart, bestLength := 0, 0
		for start := 1; start <= 6; start++ {
			length := 0
			for start+length <= 6 && present[start+length] {
				length++
			}
			if length > 0 && length >= bestLength {
				bestStart, bestLength = start, length
			}
		}
		if bestLength >= 3 {
			for face := bestStart; face < bestStart+bestLength; face++ {
				for i, actual := range faces {
					if actual == face {
						holds[i] = true
						break
					}
				}
			}
			return holds
		}
	}
	most := mostFrequent(faces)
	for i, face := range faces {
		holds[i] = face == most
	}
	return holds
}
func allHeld(holds [5]bool) bool {
	for _, hold := range holds {
		if !hold {
			return false
		}
	}
	return true
}

type Outcome struct {
	Faces  []int
	Weight int64
}

var rerolls [6][]Outcome

func init() {
	factorial := []int64{1, 1, 2, 6, 24, 120}
	for count := 0; count <= 5; count++ {
		var visit func(minimum, remain int, faces []int)
		visit = func(minimum, remain int, faces []int) {
			if remain == 0 {
				weight := factorial[count]
				for face := 1; face <= 6; face++ {
					frequency := 0
					for _, v := range faces {
						if v == face {
							frequency++
						}
					}
					weight /= factorial[frequency]
				}
				rerolls[count] = append(rerolls[count], Outcome{append([]int(nil), faces...), weight})
				return
			}
			for face := minimum; face <= 6; face++ {
				visit(face, remain-1, append(faces, face))
			}
		}
		visit(1, count, nil)
	}
}

type Roller struct {
	state  int64
	loaded []int
	counts [6]int
}

func newRoller(seed int) *Roller { return &Roller{state: int64(seed)} }
func (r *Roller) rollDie() int {
	var face int
	if len(r.loaded) > 0 {
		face = r.loaded[0]
		r.loaded = r.loaded[1:]
	} else {
		r.state = multiplier * r.state % modulus
		face = int(r.state%6) + 1
	}
	r.counts[face-1]++
	return face
}

type Player struct {
	Name, Strategy string
	Boxes          map[string]int
	YBonus         int
}

func newPlayer(name, strategy string) *Player {
	return &Player{Name: name, Strategy: strategy, Boxes: make(map[string]int)}
}
func (p *Player) open() []string {
	result := make([]string, 0, 13)
	for _, category := range categories {
		if _, used := p.Boxes[category]; !used {
			result = append(result, category)
		}
	}
	return result
}
func (p *Player) round() int { return len(p.Boxes) + 1 }
func (p *Player) upper() int {
	total := 0
	for _, category := range categories[:6] {
		total += p.Boxes[category]
	}
	return total
}
func (p *Player) upperBonus() int {
	if p.upper() >= 63 {
		return 35
	}
	return 0
}
func (p *Player) total() int {
	total := p.YBonus + p.upperBonus()
	for _, points := range p.Boxes {
		total += points
	}
	return total
}

type Turn struct {
	Seat, Rolls int
	Faces       [5]int
	Holds       [5]bool
}
type Entry struct {
	Player        *Player
	Category      string
	Points, Bonus int
	Joker         bool
	Turn          Turn
}
type Redo struct {
	Turn  *Turn
	Entry Entry
}
type Game struct {
	Players []*Player
	Rules   *Rules
	Roller  *Roller
	Turn    *Turn
	Entries []Entry
	Redos   []Redo
}
type Rules struct {
	Rolls int
	Joker string
}

func newGame(players []*Player, rules *Rules, roller *Roller) *Game {
	return &Game{Players: players, Rules: rules, Roller: roller, Turn: &Turn{Seat: 0}}
}
func (g *Game) finished() bool   { return g.Turn == nil }
func (g *Game) current() *Player { return g.Players[g.Turn.Seat] }
func (g *Game) ranking() []*Player {
	result := append([]*Player(nil), g.Players...)
	seat := make(map[*Player]int, len(g.Players))
	for i, p := range g.Players {
		seat[p] = i
	}
	sort.Slice(result, func(i, j int) bool {
		a, b := result[i], result[j]
		if a.total() != b.total() {
			return a.total() > b.total()
		}
		return seat[a] < seat[b]
	})
	return result
}
func (g *Game) roll() string {
	t := g.Turn
	if t.Rolls == 0 {
		for i := range t.Faces {
			t.Faces[i] = g.Roller.rollDie()
		}
	} else {
		for i := range t.Faces {
			if !t.Holds[i] {
				t.Faces[i] = g.Roller.rollDie()
			}
		}
	}
	t.Rolls++
	g.Redos = nil
	return fmt.Sprintf("%s roll %d: %s", g.current().Name, t.Rolls, faceText(t.Faces[:]))
}
func (g *Game) setHolds(holds [5]bool) string {
	g.Turn.Holds = holds
	g.Redos = nil
	return fmt.Sprintf("%s holds %s: %s", g.current().Name, holdText(holds), faceText(heldFaces(g.Turn.Faces, holds)))
}
func (g *Game) jokerSituation(p *Player, faces [5]int) bool {
	_, used := p.Boxes["YAHTZEE"]
	return g.Rules.Joker != "OFF" && isYahtzee(faces) && used
}
func (g *Game) allowed(p *Player, faces [5]int, joker bool) []string {
	open := p.open()
	if !joker || g.Rules.Joker == "FREE" {
		return open
	}
	upper := categories[faces[0]-1]
	if _, used := p.Boxes[upper]; !used {
		return []string{upper}
	}
	lower := make([]string, 0, 7)
	for _, category := range open {
		if slices.Contains(categories[6:], category) {
			lower = append(lower, category)
		}
	}
	if len(lower) > 0 {
		return lower
	}
	return open
}
func (g *Game) points(faces [5]int, category string, joker bool) int {
	if joker {
		switch category {
		case "FULLHOUSE":
			return 25
		case "SMALL":
			return 30
		case "LARGE":
			return 40
		}
	}
	return normalScore(category, faces)
}

type Candidate struct {
	Category string
	Score    int
}

func (g *Game) candidates(p *Player, faces [5]int) []Candidate {
	joker := g.jokerSituation(p, faces)
	allowed := g.allowed(p, faces, joker)
	result := make([]Candidate, 0, 13)
	for _, category := range p.open() {
		score := 0
		if slices.Contains(allowed, category) {
			score = g.points(faces, category, joker)
		}
		result = append(result, Candidate{category, score})
	}
	return result
}
func bestCandidate(candidates []Candidate) Candidate {
	best := candidates[0]
	for _, candidate := range candidates[1:] {
		if candidate.Score > best.Score {
			best = candidate
		}
	}
	return best
}
func (g *Game) best(p *Player, faces [5]int) Candidate { return bestCandidate(g.candidates(p, faces)) }
func (g *Game) prepare(category string) (Entry, string) {
	p := g.current()
	faces := g.Turn.Faces
	if _, used := p.Boxes[category]; used {
		return Entry{}, category + " already used"
	}
	joker := g.jokerSituation(p, faces)
	if !slices.Contains(g.allowed(p, faces, joker), category) {
		upper := categories[faces[0]-1]
		if _, used := p.Boxes[upper]; !used {
			return Entry{}, "joker requires " + upper
		}
		return Entry{}, "joker requires lower box"
	}
	bonus := 0
	if isYahtzee(faces) && p.Boxes["YAHTZEE"] == 50 {
		bonus = 100
	}
	return Entry{p, category, g.points(faces, category, joker), bonus, joker, *g.Turn}, ""
}
func (g *Game) scoreLine(e Entry, verb string) string {
	p := e.Player
	parts := []string{p.Name, verb, intText(e.Points), "in", e.Category}
	if e.Joker {
		parts = append(parts, "joker")
	}
	if e.Bonus > 0 {
		parts = append(parts, "ybonus", intText(e.Bonus))
	}
	subtotal := p.upper()
	if slices.Contains(categories[:6], e.Category) {
		subtotal += e.Points
	}
	gained := 0
	if p.upperBonus() == 0 && subtotal >= 63 {
		gained = 35
		parts = append(parts, "ubonus", "35")
	}
	parts = append(parts, "total", intText(p.total()+e.Points+e.Bonus+gained))
	return strings.Join(parts, " ")
}
func (g *Game) enter(e Entry) {
	e.Player.Boxes[e.Category] = e.Points
	e.Player.YBonus += e.Bonus
	g.Entries = append(g.Entries, e)
}
func (g *Game) score(e Entry) []string {
	line := g.scoreLine(e, "scores")
	g.enter(e)
	g.Redos = nil
	completed := true
	for _, player := range g.Players {
		if len(player.Boxes) != 13 {
			completed = false
			break
		}
	}
	if completed {
		g.Turn = nil
		return []string{line, "game over"}
	}
	g.Turn = &Turn{Seat: (g.Turn.Seat + 1) % len(g.Players)}
	p := g.current()
	return []string{line, fmt.Sprintf("turn %d %s", p.round(), p.Name)}
}
func (g *Game) undo() Entry {
	i := len(g.Entries) - 1
	e := g.Entries[i]
	g.Entries = g.Entries[:i]
	delete(e.Player.Boxes, e.Category)
	e.Player.YBonus -= e.Bonus
	g.Redos = append(g.Redos, Redo{g.Turn, e})
	restored := e.Turn
	g.Turn = &restored
	return e
}
func (g *Game) redo() Entry {
	i := len(g.Redos) - 1
	row := g.Redos[i]
	g.Redos = g.Redos[:i]
	g.enter(row.Entry)
	g.Turn = row.Turn
	return row.Entry
}
func (g *Game) botCategory() string {
	p, faces := g.current(), g.Turn.Faces
	if p.Strategy == "UPPER" {
		face := mostFrequent(faces)
		category := categories[face-1]
		count := 0
		for _, v := range faces {
			if v == face {
				count++
			}
		}
		if count >= 3 && slices.Contains(g.allowed(p, faces, g.jokerSituation(p, faces)), category) {
			return category
		}
	}
	return g.best(p, faces).Category
}
func (g *Game) botTurn() []string {
	result := make([]string, 0, 9)
	if g.Turn.Rolls == 0 {
		result = append(result, g.roll())
	}
	for g.Turn.Rolls < g.Rules.Rolls {
		holds := botHolds(g.current().Strategy, g.Turn.Faces)
		if allHeld(holds) {
			break
		}
		result = append(result, g.setHolds(holds), g.roll())
	}
	entry, msg := g.prepare(g.botCategory())
	if msg != "" {
		panic(msg)
	}
	return append(result, g.score(entry)...)
}

type Advisor struct {
	game         *Game
	player       *Player
	values       map[string]int64
	expectations map[string]int64
}

func newAdvisor(g *Game, p *Player) *Advisor {
	return &Advisor{g, p, make(map[string]int64), make(map[string]int64)}
}
func sortedFaces(faces []int) []int {
	sorted := append([]int(nil), faces...)
	sort.Ints(sorted)
	return sorted
}
func encodeFaces(faces []int) string {
	buf := make([]byte, len(faces))
	for i, f := range faces {
		buf[i] = byte(f) + '0'
	}
	return string(buf)
}
func holdForPattern(faces []int, pattern int) []int {
	held := make([]int, 0, 5)
	for i, face := range faces {
		if pattern&(1<<(4-i)) != 0 {
			held = append(held, face)
		}
	}
	return held
}
func (a *Advisor) value(hand []int, level int) int64 {
	key := intText(level) + ":" + encodeFaces(hand)
	if v, ok := a.values[key]; ok {
		return v
	}
	var value int64
	if level == 0 {
		var faces [5]int
		copy(faces[:], hand)
		value = int64(a.game.best(a.player, faces).Score)
	} else {
		for pattern := 0; pattern < 32; pattern++ {
			expected := a.expectation(holdForPattern(hand, pattern), level)
			if pattern == 0 || expected > value {
				value = expected
			}
		}
	}
	a.values[key] = value
	return value
}
func (a *Advisor) expectation(held []int, level int) int64 {
	key := intText(level) + ":" + encodeFaces(held)
	if v, ok := a.expectations[key]; ok {
		return v
	}
	var total int64
	for _, outcome := range rerolls[5-len(held)] {
		combined := append(append([]int(nil), held...), outcome.Faces...)
		sort.Ints(combined)
		total += outcome.Weight * a.value(combined, level-1)
	}
	for range len(held) {
		total *= 6
	}
	a.expectations[key] = total
	return total
}
func (a *Advisor) bestHold(faces [5]int, level int) ([5]bool, int64) {
	var best [5]bool
	var bestValue int64 = -1
	for pattern := 0; pattern < 32; pattern++ {
		held := holdForPattern(faces[:], pattern)
		value := a.expectation(held, level)
		if value > bestValue {
			bestValue = value
			for i := 0; i < 5; i++ {
				best[i] = pattern&(1<<(4-i)) != 0
			}
		}
	}
	return best, bestValue
}

type PlayerRecord struct{ Games, Wins, Best, Total int }

func (r *PlayerRecord) add(score int, won bool) {
	r.Games++
	if won {
		r.Wins++
	}
	if score > r.Best {
		r.Best = score
	}
	r.Total += score
}

type SeatSummary struct {
	Strategy                          string
	Wins, Total, Best, Bonus, Yahtzee int
}

func (s *SeatSummary) add(p *Player, won bool) {
	score := p.total()
	if won {
		s.Wins++
	}
	s.Total += score
	if score > s.Best {
		s.Best = score
	}
	if p.upperBonus() == 35 {
		s.Bonus++
	}
	if p.Boxes["YAHTZEE"] == 50 {
		s.Yahtzee++
	}
}

type Table struct {
	rules   Rules
	game    *Game
	records map[string]*PlayerRecord
}

func newTable() *Table {
	return &Table{rules: Rules{Rolls: 3, Joker: "FORCED"}, records: make(map[string]*PlayerRecord)}
}
func (t *Table) requireGame() (*Game, string) {
	if t.game == nil {
		return nil, "no game"
	}
	return t.game, ""
}
func (t *Table) requireTurn() (*Game, string) {
	g, msg := t.requireGame()
	if msg != "" {
		return nil, msg
	}
	if g.finished() {
		return nil, "game over"
	}
	return g, ""
}
func (t *Table) requireRolled() (*Game, string) {
	g, msg := t.requireTurn()
	if msg != "" {
		return nil, msg
	}
	if g.Turn.Rolls == 0 {
		return nil, "not rolled"
	}
	return g, ""
}
func (t *Table) requireRollsLeft() (*Game, string) {
	g, msg := t.requireRolled()
	if msg != "" {
		return nil, msg
	}
	if g.Turn.Rolls == t.rules.Rolls {
		return nil, "no rolls left"
	}
	return g, ""
}
func (t *Table) command(command string, args []string) []string {
	switch command {
	case "RULE":
		rule, value := args[0], args[1]
		if rule == "ROLLS" {
			rolls, msg := validNumber(value, 1, 4)
			if msg != "" {
				return errorLine(msg)
			}
			if t.game != nil {
				return errorLine("game in progress")
			}
			t.rules.Rolls = rolls
		} else if rule == "JOKER" {
			if value != "FORCED" && value != "FREE" && value != "OFF" {
				return errorLine("bad value " + value)
			}
			if t.game != nil {
				return errorLine("game in progress")
			}
			t.rules.Joker = value
		} else {
			return errorLine("unknown rule " + rule)
		}
		return []string{"rule " + rule + " " + value}
	case "GAME":
		seed, msg := validNumber(args[0], 1, int(modulus-1))
		if msg != "" {
			return errorLine(msg)
		}
		names := args[1:]
		for _, name := range names {
			if msg := validName(name); msg != "" {
				return errorLine(msg)
			}
		}
		if len(names) > 6 {
			return errorLine("too many players")
		}
		if t.game != nil {
			return errorLine("game in progress")
		}
		seen := make(map[string]bool)
		for _, name := range names {
			if seen[name] {
				return errorLine("duplicate name " + name)
			}
			seen[name] = true
		}
		players := make([]*Player, len(names))
		for i, name := range names {
			players[i] = newPlayer(name, "KIND")
		}
		t.game = newGame(players, &t.rules, newRoller(seed))
		return []string{fmt.Sprintf("game seed %d players %s", seed, strings.Join(names, " ")), "turn 1 " + names[0]}
	case "BOT":
		name, strategy := args[0], args[1]
		if msg := validName(name); msg != "" {
			return errorLine(msg)
		}
		if msg := validStrategy(strategy); msg != "" {
			return errorLine(msg)
		}
		g, msg := t.requireGame()
		if msg != "" {
			return errorLine(msg)
		}
		for _, p := range g.Players {
			if p.Name == name {
				p.Strategy = strategy
				return []string{"bot " + name + " " + strategy}
			}
		}
		return errorLine("no player " + name)
	case "LOAD":
		faces := make([]int, len(args))
		for i, word := range args {
			value, msg := validNumber(word, 1, 6)
			if msg != "" {
				return errorLine(msg)
			}
			faces[i] = value
		}
		g, msg := t.requireGame()
		if msg != "" {
			return errorLine(msg)
		}
		g.Roller.loaded = append(g.Roller.loaded, faces...)
		return []string{fmt.Sprintf("loaded %d", len(g.Roller.loaded))}
	case "ROLL":
		g, msg := t.requireTurn()
		if msg != "" {
			return errorLine(msg)
		}
		if g.Turn.Rolls == t.rules.Rolls {
			return errorLine("no rolls left")
		}
		if allHeld(g.Turn.Holds) {
			return errorLine("all dice held")
		}
		return []string{g.roll()}
	case "HOLD":
		holds, msg := validPattern(args[0])
		if msg != "" {
			return errorLine(msg)
		}
		g, msg := t.requireRollsLeft()
		if msg != "" {
			return errorLine(msg)
		}
		return []string{g.setHolds(holds)}
	case "KEEP":
		values := make([]int, len(args))
		for i, word := range args {
			value, msg := validNumber(word, 1, 6)
			if msg != "" {
				return errorLine(msg)
			}
			values[i] = value
		}
		g, msg := t.requireRollsLeft()
		if msg != "" {
			return errorLine(msg)
		}
		var holds [5]bool
		for _, value := range values {
			found := false
			for i, face := range g.Turn.Faces {
				if face == value && !holds[i] {
					holds[i] = true
					found = true
					break
				}
			}
			if !found {
				return errorLine("not showing " + intText(value))
			}
		}
		return []string{g.setHolds(holds)}
	case "SCORE", "WHATIF":
		category := args[0]
		if msg := validCategory(category); msg != "" {
			return errorLine(msg)
		}
		g, msg := t.requireRolled()
		if msg != "" {
			return errorLine(msg)
		}
		entry, msg := g.prepare(category)
		if msg != "" {
			return errorLine(msg)
		}
		if command == "WHATIF" {
			return []string{g.scoreLine(entry, "would score")}
		}
		return g.score(entry)
	case "UNDO":
		g, msg := t.requireGame()
		if msg != "" {
			return errorLine(msg)
		}
		if len(g.Entries) == 0 {
			return errorLine("nothing to undo")
		}
		e := g.undo()
		return []string{fmt.Sprintf("undo %s %s %d", e.Player.Name, e.Category, e.Points)}
	case "REDO":
		g, msg := t.requireGame()
		if msg != "" {
			return errorLine(msg)
		}
		if len(g.Redos) == 0 {
			return errorLine("nothing to redo")
		}
		e := g.redo()
		return []string{fmt.Sprintf("redo %s %s %d", e.Player.Name, e.Category, e.Points)}
	case "SUGGEST":
		g, msg := t.requireRolled()
		if msg != "" {
			return errorLine(msg)
		}
		candidates := g.candidates(g.current(), g.Turn.Faces)
		parts := []string{"suggest"}
		for _, candidate := range candidates {
			parts = append(parts, candidate.Category, intText(candidate.Score))
		}
		best := bestCandidate(candidates)
		parts = append(parts, "best", best.Category, intText(best.Score))
		return []string{strings.Join(parts, " ")}
	case "ODDS":
		holds, msg := validPattern(args[0])
		if msg != "" {
			return errorLine(msg)
		}
		g, msg := t.requireRollsLeft()
		if msg != "" {
			return errorLine(msg)
		}
		held := heldFaces(g.Turn.Faces, holds)
		open := g.current().open()
		expected := make(map[string]int64, len(open))
		chances := make(map[string]int64, len(open))
		var bestTotal int64
		for _, outcome := range rerolls[5-len(held)] {
			faces := append(append([]int(nil), held...), outcome.Faces...)
			var hand [5]int
			copy(hand[:], faces)
			candidates := g.candidates(g.current(), hand)
			for _, c := range candidates {
				expected[c.Category] += outcome.Weight * int64(c.Score)
				if c.Score > 0 {
					chances[c.Category] += outcome.Weight
				}
			}
			bestTotal += outcome.Weight * int64(bestCandidate(candidates).Score)
		}
		var outcomes int64 = 1
		for i := len(held); i < 5; i++ {
			outcomes *= 6
		}
		result := []string{fmt.Sprintf("odds %s outcomes %d", holdText(holds), outcomes)}
		for _, category := range open {
			result = append(result, fmt.Sprintf("%s expect %s chance %s", category,
				fractionText(expected[category], outcomes), fractionText(chances[category], outcomes)))
		}
		return append(result, "best expect "+fractionText(bestTotal, outcomes))
	case "ADVISE":
		g, msg := t.requireRollsLeft()
		if msg != "" {
			return errorLine(msg)
		}
		levels := t.rules.Rolls - g.Turn.Rolls
		holds, value := newAdvisor(g, g.current()).bestHold(g.Turn.Faces, levels)
		denominator := int64(1)
		for i := 0; i < levels; i++ {
			denominator *= outcomeScale
		}
		return []string{fmt.Sprintf("advise %s: %s expect %s", holdText(holds),
			faceText(heldFaces(g.Turn.Faces, holds)), fractionText(value, denominator))}
	case "AUTO":
		count, msg := validNumber(args[0], 1, 100)
		if msg != "" {
			return errorLine(msg)
		}
		g, msg := t.requireTurn()
		if msg != "" {
			return errorLine(msg)
		}
		result := make([]string, 0, count*8)
		for i := 0; i < count; i++ {
			result = append(result, g.botTurn()...)
			if g.finished() {
				break
			}
		}
		return result
	case "STATUS":
		g, msg := t.requireGame()
		if msg != "" {
			return errorLine(msg)
		}
		if g.finished() {
			return []string{"status game over"}
		}
		faces := "-"
		if g.Turn.Rolls > 0 {
			faces = faceText(g.Turn.Faces[:])
		}
		return []string{fmt.Sprintf("status round %d player %s rolls %d dice %s holds %s",
			g.current().round(), g.current().Name, g.Turn.Rolls, faces, holdText(g.Turn.Holds))}
	case "CARD":
		g, msg := t.requireGame()
		if msg != "" {
			return errorLine(msg)
		}
		widths := make([]int, len(g.Players))
		for i, p := range g.Players {
			widths[i] = len(p.Name)
			if widths[i] < 4 {
				widths[i] = 4
			}
		}
		render := func(heading string, cells []string) string {
			row := fmt.Sprintf("%-9s", heading)
			for i, cell := range cells {
				row += fmt.Sprintf(" %*s", widths[i], cell)
			}
			return row
		}
		names := make([]string, len(g.Players))
		for i, p := range g.Players {
			names[i] = p.Name
		}
		result := []string{render("CATEGORY", names)}
		for _, category := range categories {
			values := make([]string, len(g.Players))
			for i, p := range g.Players {
				if score, used := p.Boxes[category]; used {
					values[i] = intText(score)
				} else {
					values[i] = "-"
				}
			}
			result = append(result, render(category, values))
		}
		for _, row := range []struct {
			name  string
			value func(*Player) int
		}{
			{"UPPER", (*Player).upper}, {"BONUS", (*Player).upperBonus},
			{"YBONUS", func(p *Player) int { return p.YBonus }}, {"TOTAL", (*Player).total},
		} {
			values := make([]string, len(g.Players))
			for i, p := range g.Players {
				values[i] = intText(row.value(p))
			}
			result = append(result, render(row.name, values))
		}
		return result
	case "BONUS":
		g, msg := t.requireGame()
		if msg != "" {
			return errorLine(msg)
		}
		result := make([]string, 0, len(g.Players))
		for _, p := range g.Players {
			subtotal := p.upper()
			maxTotal := subtotal
			for f, category := range categories[:6] {
				if _, used := p.Boxes[category]; !used {
					maxTotal += 5 * (f + 1)
				}
			}
			need := 63 - subtotal
			if need < 0 {
				need = 0
			}
			state := "open"
			if subtotal >= 63 {
				state = "made"
			} else if maxTotal < 63 {
				state = "lost"
			}
			result = append(result, fmt.Sprintf("bonus %s upper %d need %d max %d %s", p.Name, subtotal, need, maxTotal, state))
		}
		return result
	case "STATS":
		g, msg := t.requireGame()
		if msg != "" {
			return errorLine(msg)
		}
		result := make([]string, 0, len(g.Players))
		for _, p := range g.Players {
			turns, rolls, zeros, yahtzees, total := 0, 0, 0, 0, 0
			for _, e := range g.Entries {
				if e.Player != p {
					continue
				}
				turns++
				rolls += e.Turn.Rolls
				total += e.Points
				if e.Points == 0 {
					zeros++
				}
				if isYahtzee(e.Turn.Faces) {
					yahtzees++
				}
			}
			result = append(result, fmt.Sprintf("stats %s turns %d rolls %d zeros %d yahtzees %d average %s",
				p.Name, turns, rolls, zeros, yahtzees, averageText(total, turns)))
		}
		return result
	case "LOG":
		g, msg := t.requireGame()
		if msg != "" {
			return errorLine(msg)
		}
		if len(g.Entries) == 0 {
			return []string{"no scores"}
		}
		result := make([]string, 0, len(g.Entries))
		for index, e := range g.Entries {
			parts := []string{"log", intText(index + 1), e.Player.Name, faceText(e.Turn.Faces[:]), e.Category, intText(e.Points)}
			if e.Joker {
				parts = append(parts, "joker")
			}
			if e.Bonus > 0 {
				parts = append(parts, "ybonus", intText(e.Bonus))
			}
			result = append(result, strings.Join(parts, " "))
		}
		return result
	case "FACES":
		g, msg := t.requireGame()
		if msg != "" {
			return errorLine(msg)
		}
		counts := g.Roller.counts
		total := 0
		var squares int64
		words := make([]string, 6)
		for i, n := range counts {
			total += n
			squares += int64(n * n)
			words[i] = intText(n)
		}
		chi2 := "0"
		if total > 0 {
			chi2 = fractionText(6*squares-int64(total*total), int64(total))
		}
		return []string{fmt.Sprintf("faces %s total %d chi2 %s", strings.Join(words, " "), total, chi2)}
	case "STANDINGS":
		g, msg := t.requireGame()
		if msg != "" {
			return errorLine(msg)
		}
		ranking := g.ranking()
		leader := ranking[0].total()
		result := make([]string, 0, len(ranking))
		for i, p := range ranking {
			result = append(result, fmt.Sprintf("standing %d %s %d behind %d", i+1, p.Name, p.total(), leader-p.total()))
		}
		return result
	case "END":
		g, msg := t.requireGame()
		if msg != "" {
			return errorLine(msg)
		}
		finished := g.finished()
		result := []string{"end abandoned"}
		if finished {
			result[0] = "end final"
		}
		for i, p := range g.ranking() {
			result = append(result, fmt.Sprintf("rank %d %s %d", i+1, p.Name, p.total()))
			if finished {
				record := t.records[p.Name]
				if record == nil {
					record = &PlayerRecord{}
					t.records[p.Name] = record
				}
				record.add(p.total(), i == 0)
			}
		}
		t.game = nil
		return result
	case "RECORDS":
		if len(t.records) == 0 {
			return []string{"no records"}
		}
		names := make([]string, 0, len(t.records))
		for name := range t.records {
			names = append(names, name)
		}
		sort.Slice(names, func(i, j int) bool {
			a, b := t.records[names[i]], t.records[names[j]]
			if a.Wins != b.Wins {
				return a.Wins > b.Wins
			}
			if a.Best != b.Best {
				return a.Best > b.Best
			}
			return names[i] < names[j]
		})
		result := make([]string, 0, len(names))
		for _, name := range names {
			r := t.records[name]
			result = append(result, fmt.Sprintf("record %s games %d wins %d best %d average %s",
				name, r.Games, r.Wins, r.Best, averageText(r.Total, r.Games)))
		}
		return result
	case "SIM":
		seed, msg := validNumber(args[0], 1, int(modulus-1))
		if msg != "" {
			return errorLine(msg)
		}
		count, msg := validNumber(args[1], 1, 50)
		if msg != "" {
			return errorLine(msg)
		}
		kinds := args[2:]
		for _, strategy := range kinds {
			if msg := validStrategy(strategy); msg != "" {
				return errorLine(msg)
			}
		}
		if len(kinds) > 6 {
			return errorLine("too many players")
		}
		roller := newRoller(seed)
		summaries := make([]SeatSummary, len(kinds))
		for i, strategy := range kinds {
			summaries[i].Strategy = strategy
		}
		for gameIndex := 0; gameIndex < count; gameIndex++ {
			players := make([]*Player, len(kinds))
			for seat, strategy := range kinds {
				players[seat] = newPlayer(intText(seat+1), strategy)
			}
			game := newGame(players, &t.rules, roller)
			for !game.finished() {
				game.botTurn()
			}
			winner := game.ranking()[0]
			for seat, player := range players {
				summaries[seat].add(player, player == winner)
			}
		}
		result := []string{fmt.Sprintf("sim seed %d games %d players %d", seed, count, len(kinds))}
		for seat, s := range summaries {
			result = append(result, fmt.Sprintf(
				"seat %d %s wins %d average %s best %d bonus %d yahtzee %d",
				seat+1, s.Strategy, s.Wins, averageText(s.Total, count), s.Best, s.Bonus, s.Yahtzee))
		}
		return result
	default:
		return errorLine("unknown command " + command)
	}
}

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 4096), 1024*1024)
	if !scanner.Scan() {
		return
	}
	count, _ := strconv.Atoi(scanner.Text())
	writer := bufio.NewWriter(os.Stdout)
	defer writer.Flush()
	table := newTable()
	for i := 0; i < count && scanner.Scan(); i++ {
		words := strings.Fields(scanner.Text())
		if len(words) == 0 {
			continue
		}
		for _, line := range table.command(words[0], words[1:]) {
			fmt.Fprintln(writer, line)
		}
	}
}
