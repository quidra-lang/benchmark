package main

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

type Phase int

const (
	setup Phase = iota
	battle
	over
)

type Strategy int

const (
	human Strategy = iota - 1
	hunt
	prob
	random
)

type CellView int

const (
	reefView CellView = iota
	unknownView
	missView
	hitView
	sunkView
)

type Result int

const (
	already Result = iota
	miss
	hit
	sunk
)

type Output int

const (
	normal Output = iota
	sinksOnly
	quiet
)

var shipNames = [5]string{"CARRIER", "BATTLESHIP", "CRUISER", "SUBMARINE", "DESTROYER"}
var lengths = [5]int{5, 4, 3, 3, 2}
var strategyNames = [3]string{"HUNT", "PROB", "RANDOM"}

const symbols = "CBRSD"

type Ship struct {
	start, step int
}

func (s Ship) inBounds(length int) bool {
	if s.step == 1 {
		return s.start%10+length <= 10
	}
	return s.start/10+length <= 10
}

func (s Ship) span(length int) string {
	return cellName(s.start) + "-" + cellName(s.start+(length-1)*s.step)
}

func (s Ship) touches(length int, other Ship, otherLength int) bool {
	for i := 0; i < length; i++ {
		for j := 0; j < otherLength; j++ {
			if adjacent(s.start+i*s.step, other.start+j*other.step) {
				return true
			}
		}
	}
	return false
}

type Stats struct {
	shots, hits, sunk, turns, streak, longest, wins int64
}

func (s *Stats) record(result Result) {
	s.shots++
	if result == hit || result == sunk {
		s.hits++
		s.streak++
		s.longest = max(s.longest, s.streak)
	} else {
		s.streak = 0
	}
	if result == sunk {
		s.sunk++
	}
}

type Player struct {
	fleet                   [5]*Ship
	board                   [100]int
	attacked                [100]bool
	candidates              []int
	random                  int64
	controller              Strategy
	torpedoUsed, sonarUsed  bool
	stats                   Stats
}

func (p *Player) clearFleet() {
	p.fleet = [5]*Ship{}
	for c := range p.board {
		p.board[c] = -1
	}
}

func (p *Player) putShip(s int, ship Ship) {
	p.fleet[s] = &ship
	for i := 0; i < lengths[s]; i++ {
		p.board[ship.start+i*ship.step] = s
	}
}

func (p *Player) attackedCount(s int) int {
	count := 0
	if ship := p.fleet[s]; ship != nil {
		for i := 0; i < lengths[s]; i++ {
			if p.attacked[ship.start+i*ship.step] {
				count++
			}
		}
	}
	return count
}

func (p *Player) sunk(s int) bool {
	return p.fleet[s] != nil && p.attackedCount(s) == lengths[s]
}

func (p *Player) placed() int {
	count := 0
	for _, ship := range p.fleet {
		if ship != nil {
			count++
		}
	}
	return count
}

func (p *Player) afloat() int {
	count := 0
	for s, ship := range p.fleet {
		if ship != nil && !p.sunk(s) {
			count++
		}
	}
	return count
}

type Game struct {
	players             [2]Player
	reefs               [100]bool
	salvo, chain, touch bool
	phase               Phase
	current, winner     int
}

func newGame() *Game {
	g := &Game{phase: setup, winner: -1}
	for p := range g.players {
		g.players[p].clearFleet()
		g.players[p].random = int64(p + 1)
		g.players[p].controller = human
	}
	return g
}

func advance(state int64) int64 { return state * 48271 % 2147483647 }

func number(text string) int {
	value, _ := strconv.Atoi(text)
	return value
}

func seedNumber(text string) int64 {
	value, _ := strconv.ParseInt(text, 10, 64)
	return value
}

func cellNumber(text string) int { return int(text[0]-'A')*10 + number(text[1:]) - 1 }
func cellName(cell int) string   { return fmt.Sprintf("%c%d", 'A'+cell/10, cell%10+1) }

func shipNumber(name string) int {
	for s, candidate := range shipNames {
		if name == candidate {
			return s
		}
	}
	panic("invalid ship")
}

func parseStrategy(name string) Strategy {
	for s, candidate := range strategyNames {
		if name == candidate {
			return Strategy(s)
		}
	}
	return human
}

func switchName(enabled bool) string {
	if enabled {
		return "ON"
	}
	return "OFF"
}

func adjacent(a, b int) bool {
	dr, dc := a/10-b/10, a%10-b%10
	return dr >= -1 && dr <= 1 && dc >= -1 && dc <= 1
}

func neighbour(cell, dr, dc int) int {
	row, col := cell/10+dr, cell%10+dc
	if row >= 0 && row < 10 && col >= 0 && col < 10 {
		return row*10 + col
	}
	return -1
}

func (g *Game) allowance(p int) int {
	if g.salvo {
		return g.players[p].afloat()
	}
	return 1
}

func (g *Game) placementError(p *Player, s int, ship Ship) error {
	if !ship.inBounds(lengths[s]) {
		return errors.New("out of bounds")
	}
	for i := 0; i < lengths[s]; i++ {
		if g.reefs[ship.start+i*ship.step] {
			return errors.New("on reef")
		}
	}
	for other, name := range shipNames {
		for i := 0; i < lengths[s]; i++ {
			if p.board[ship.start+i*ship.step] == other {
				return fmt.Errorf("overlaps %s", name)
			}
		}
	}
	if !g.touch {
		for other, placed := range p.fleet {
			if placed != nil && ship.touches(lengths[s], *placed, lengths[other]) {
				return fmt.Errorf("touches %s", shipNames[other])
			}
		}
	}
	return nil
}

func (g *Game) printPlaced(p, s int, out *bufio.Writer) {
	fmt.Fprintf(out, "PLACED %d %s %s\n", p+1, shipNames[s], g.players[p].fleet[s].span(lengths[s]))
}

func (g *Game) autoplace(owner int, seed int64) int64 {
	p := &g.players[owner]
	p.clearFleet()
	p.random = seed
	var attempts int64
	for s, length := range lengths {
		for {
			attempts++
			p.random = advance(p.random)
			step := 10
			if p.random%2 == 0 {
				step = 1
			}
			p.random = advance(p.random)
			k := int(p.random % int64(10*(11-length)))
			start := k
			if step == 1 {
				start = k/(11-length)*10 + k%(11-length)
			}
			ship := Ship{start, step}
			if g.placementError(p, s, ship) == nil {
				p.putShip(s, ship)
				break
			}
		}
	}
	return attempts
}

func (g *Game) parseLayout(layout string) ([5]Ship, error) {
	var fleet [5]Ship
	for s, length := range lengths {
		cells := make([]int, 0, length)
		for c := 0; c < 100; c++ {
			if layout[c/10*11+c%10] == symbols[s] {
				cells = append(cells, c)
			}
		}
		if len(cells) != length {
			return fleet, fmt.Errorf("%s has %d cells", shipNames[s], len(cells))
		}
		ship := Ship{cells[0], cells[1] - cells[0]}
		straight := (ship.step == 1 || ship.step == 10) && ship.inBounds(length)
		for i, c := range cells {
			straight = straight && c == ship.start+i*ship.step
		}
		if !straight {
			return fleet, fmt.Errorf("%s not straight", shipNames[s])
		}
		for _, c := range cells {
			if g.reefs[c] {
				return fleet, fmt.Errorf("%s on reef", shipNames[s])
			}
		}
		fleet[s] = ship
	}
	if !g.touch {
		for a := 0; a < 5; a++ {
			for b := a + 1; b < 5; b++ {
				if fleet[a].touches(lengths[a], fleet[b], lengths[b]) {
					return fleet, fmt.Errorf("%s touches %s", shipNames[a], shipNames[b])
				}
			}
		}
	}
	return fleet, nil
}

type View struct {
	cells     [100]CellView
	excluded  [100]bool
	remaining [5]bool
}

func (g *Game) view(p int) View {
	var view View
	opponent := &g.players[1-p]
	for s := range view.remaining {
		view.remaining[s] = !opponent.sunk(s)
	}
	for c := range view.cells {
		s := opponent.board[c]
		switch {
		case g.reefs[c]:
			view.cells[c] = reefView
		case !opponent.attacked[c]:
			view.cells[c] = unknownView
		case s < 0:
			view.cells[c] = missView
		case view.remaining[s]:
			view.cells[c] = hitView
		default:
			view.cells[c] = sunkView
		}
	}
	if !g.touch {
		for c, state := range view.cells {
			if state != sunkView {
				continue
			}
			for dr := -1; dr <= 1; dr++ {
				for dc := -1; dc <= 1; dc++ {
					if dr == 0 && dc == 0 {
						continue
					}
					if other := neighbour(c, dr, dc); other >= 0 {
						view.excluded[other] = true
					}
				}
			}
		}
	}
	return view
}

func (v *View) candidate(c int) bool {
	return c >= 0 && c < 100 && v.cells[c] == unknownView && !v.excluded[c]
}

func (v *View) density() [100]int {
	var scores [100]int
	for s, length := range lengths {
		if !v.remaining[s] {
			continue
		}
		for start := 0; start < 100; start++ {
			for _, step := range [2]int{1, 10} {
				ship := Ship{start, step}
				if !ship.inBounds(length) {
					continue
				}
				possible, hits := true, 0
				for i := 0; i < length; i++ {
					c := start + i*step
					if v.excluded[c] || (v.cells[c] != unknownView && v.cells[c] != hitView) {
						possible = false
						break
					}
					if v.cells[c] == hitView {
						hits++
					}
				}
				if possible {
					for i := 0; i < length; i++ {
						scores[start+i*step] += 1 + 10*hits
					}
				}
			}
		}
	}
	return scores
}

func (v *View) best(scores *[100]int) int {
	best := -1
	for c := range v.cells {
		if v.cells[c] == unknownView && (best < 0 || scores[c] > scores[best]) {
			best = c
		}
	}
	return best
}

type Choice struct {
	cell, value int
	step        string
	nextRandom  int64
}

func (c Choice) info() string {
	if c.step != "" {
		return c.step
	}
	return strconv.Itoa(c.value)
}

func (g *Game) choose(p int, method Strategy) Choice {
	view := g.view(p)
	player := &g.players[p]
	if method == prob {
		scores := view.density()
		cell := view.best(&scores)
		return Choice{cell: cell, value: scores[cell], nextRandom: player.random}
	}
	if method == random {
		cells := make([]int, 0, 100)
		for c := 0; c < 100; c++ {
			if view.candidate(c) {
				cells = append(cells, c)
			}
		}
		next := advance(player.random)
		return Choice{cell: cells[next%int64(len(cells))], value: len(cells), nextRandom: next}
	}
	for h, state := range view.cells {
		if state != hitView {
			continue
		}
		for _, direction := range [2][2]int{{0, 1}, {1, 0}} {
			dr, dc := direction[0], direction[1]
			front := neighbour(h, dr, dc)
			if front < 0 || view.cells[front] != hitView {
				continue
			}
			for front >= 0 && view.cells[front] == hitView {
				front = neighbour(front, dr, dc)
			}
			for _, cell := range [2]int{front, neighbour(h, -dr, -dc)} {
				if view.candidate(cell) {
					return Choice{cell: cell, step: "LINE", nextRandom: player.random}
				}
			}
		}
	}
	for i := len(player.candidates) - 1; i >= 0; i-- {
		if cell := player.candidates[i]; view.candidate(cell) {
			return Choice{cell: cell, step: "STACK", nextRandom: player.random}
		}
	}
	shortest := 10
	for s, remains := range view.remaining {
		if remains {
			shortest = min(shortest, lengths[s])
		}
	}
	for c := 0; c < 100; c++ {
		if view.candidate(c) && (c/10+c%10)%shortest == 0 {
			return Choice{cell: c, step: "PARITY", nextRandom: player.random}
		}
	}
	panic("no candidate")
}

type Shot struct {
	result Result
	ship   int
}

func (s Shot) isHit() bool { return s.result == hit || s.result == sunk }

func (s Shot) String() string {
	if s.result == sunk {
		return "SUNK " + shipNames[s.ship]
	}
	return [3]string{"ALREADY", "MISS", "HIT"}[s.result]
}

func (g *Game) shoot(p, cell int) Shot {
	player, opponent := &g.players[p], &g.players[1-p]
	shot := Shot{already, opponent.board[cell]}
	if !opponent.attacked[cell] {
		opponent.attacked[cell] = true
		switch {
		case shot.ship < 0:
			shot.result = miss
		case opponent.sunk(shot.ship):
			shot.result = sunk
		default:
			shot.result = hit
		}
	}
	if shot.result == hit {
		for _, direction := range [4][2]int{{0, -1}, {1, 0}, {0, 1}, {-1, 0}} {
			if c := neighbour(cell, direction[0], direction[1]); c >= 0 {
				player.candidates = append(player.candidates, c)
			}
		}
	}
	player.stats.record(shot.result)
	return shot
}

func (g *Game) emitShot(p, cell int, shot Shot, output Output, out *bufio.Writer) {
	if output == normal {
		fmt.Fprintf(out, "SHOT %d %s %s\n", p+1, cellName(cell), shot)
	} else if output == sinksOnly && shot.result == sunk {
		fmt.Fprintf(out, "SINK %d %s %d\n", p+1, shipNames[shot.ship], g.players[p].stats.shots)
	}
}

func (g *Game) finishTurn(p int, hit bool, output Output, out *bufio.Writer) {
	g.players[p].stats.turns++
	if g.players[1-p].afloat() == 0 {
		g.phase, g.winner = over, p
		g.players[p].stats.wins++
		if output == normal {
			fmt.Fprintf(out, "WINNER %d\n", p+1)
		}
	} else if g.chain && hit {
		g.current = p
	} else {
		g.current = 1 - p
	}
}

func (g *Game) aiTurn(p int, method Strategy, output Output, out *bufio.Writer) {
	allowance, hit := g.allowance(p), false
	for i := 0; i < allowance; i++ {
		choice := g.choose(p, method)
		g.players[p].random = choice.nextRandom
		shot := g.shoot(p, choice.cell)
		g.emitShot(p, choice.cell, shot, output, out)
		hit = hit || shot.isHit()
		if g.players[1-p].afloat() == 0 {
			break
		}
	}
	g.finishTurn(p, hit, output, out)
}

func (g *Game) automaticControl(out *bufio.Writer) {
	for g.phase == battle && g.players[g.current].controller != human {
		p := g.current
		g.aiTurn(p, g.players[p].controller, normal, out)
	}
}

func (g *Game) turn(w []string, out *bufio.Writer) error {
	cmd, p := w[0], number(w[1])-1
	if g.phase == over {
		return errors.New("game over")
	}
	if g.phase == setup && (g.players[0].placed() != 5 || g.players[1].placed() != 5) {
		return errors.New("fleets not ready")
	}
	if p != g.current {
		return errors.New("not your turn")
	}
	player, opponent := &g.players[p], &g.players[1-p]
	if cmd == "FIRE" {
		if expected := g.allowance(p); len(w)-2 != expected {
			return fmt.Errorf("expected %d shots", expected)
		}
		for _, text := range w[2:] {
			if g.reefs[cellNumber(text)] {
				return fmt.Errorf("reef at %s", text)
			}
		}
	} else if cmd == "TORPEDO" && player.torpedoUsed {
		return errors.New("torpedo used")
	} else if cmd == "SONAR" && player.sonarUsed {
		return errors.New("sonar used")
	}
	g.phase = battle
	if cmd == "AI" {
		g.aiTurn(p, parseStrategy(w[2]), normal, out)
		return nil
	}
	hit := false
	switch cmd {
	case "FIRE":
		for _, text := range w[2:] {
			cell := cellNumber(text)
			shot := g.shoot(p, cell)
			g.emitShot(p, cell, shot, normal, out)
			hit = hit || shot.isHit()
			if opponent.afloat() == 0 {
				break
			}
		}
	case "SONAR":
		player.sonarUsed = true
		centre, count := cellNumber(w[2]), 0
		for c := 0; c < 100; c++ {
			if adjacent(c, centre) && opponent.board[c] >= 0 && !opponent.attacked[c] {
				count++
			}
		}
		fmt.Fprintf(out, "SONAR %d %s %d\n", p+1, w[2], count)
	case "TORPEDO":
		player.torpedoUsed = true
		result, stoppedAtShip := "MISS", false
		for i := 0; i < 10; i++ {
			col := i
			if w[3] == "E" {
				col = 9 - i
			}
			cell := int(w[2][0]-'A')*10 + col
			if g.reefs[cell] {
				result = "REEF " + cellName(cell)
				break
			}
			if opponent.board[cell] >= 0 {
				shot := g.shoot(p, cell)
				hit = shot.isHit()
				result = shot.String() + " " + cellName(cell)
				stoppedAtShip = true
				break
			}
			opponent.attacked[cell] = true
		}
		if !stoppedAtShip {
			player.stats.record(miss)
		}
		fmt.Fprintf(out, "TORPEDO %d %s %s %s\n", p+1, w[2], w[3], result)
	}
	g.finishTurn(p, hit, normal, out)
	return nil
}

type Match struct {
	winner int
	shots  [2]int64
	hits   [2]int64
}

func (g *Game) playMatch(seed1, seed2 int64, methods [2]Strategy, output Output, out *bufio.Writer) Match {
	match := newGame()
	match.salvo, match.chain, match.touch, match.reefs = g.salvo, g.chain, g.touch, g.reefs
	match.autoplace(0, seed1)
	match.autoplace(1, seed2)
	match.phase = battle
	for match.phase == battle {
		p := match.current
		match.aiTurn(p, methods[p], output, out)
	}
	return Match{match.winner, [2]int64{match.players[0].stats.shots, match.players[1].stats.shots},
		[2]int64{match.players[0].stats.hits, match.players[1].stats.hits}}
}

func (g *Game) showBoard(p int, radar bool, out *bufio.Writer) {
	label := "BOARD"
	if radar {
		label = "RADAR"
	}
	fmt.Fprintf(out, "%s %d\n  1 2 3 4 5 6 7 8 9 10\n", label, p+1)
	view, player := g.view(p), &g.players[p]
	for row := 0; row < 10; row++ {
		fmt.Fprintf(out, "%c", 'A'+row)
		for col := 0; col < 10; col++ {
			c := row*10 + col
			mark := byte('.')
			switch {
			case radar:
				mark = "~.ox#"[view.cells[c]]
			case g.reefs[c]:
				mark = '~'
			case player.board[c] >= 0:
				mark = symbols[player.board[c]]
				if player.attacked[c] {
					mark += 'a' - 'A'
				}
			case player.attacked[c]:
				mark = 'o'
			}
			fmt.Fprintf(out, " %c", mark)
		}
		fmt.Fprintln(out)
	}
}

func (g *Game) execute(w []string, out *bufio.Writer) error {
	cmd := w[0]
	switch cmd {
	case "PLACE", "REMOVE", "AUTOPLACE", "LAYOUT", "REEF", "SALVO", "CHAIN", "TOUCH":
		if g.phase != setup {
			return errors.New("setup closed")
		}
	}
	switch cmd {
	case "NEW":
		wins := [2]int64{g.players[0].stats.wins, g.players[1].stats.wins}
		*g = *newGame()
		for p, count := range wins {
			g.players[p].stats.wins = count
		}
		fmt.Fprintln(out, "NEW")
	case "SEED", "CONTROL":
		p := number(w[1]) - 1
		if cmd == "SEED" {
			g.players[p].random = seedNumber(w[2])
			fmt.Fprintf(out, "SEED %d %d\n", p+1, g.players[p].random)
		} else {
			g.players[p].controller = parseStrategy(w[2])
			fmt.Fprintf(out, "CONTROL %d %s\n", p+1, w[2])
		}
	case "SALVO", "CHAIN", "TOUCH":
		enabled := w[1] == "ON"
		switch cmd {
		case "SALVO":
			g.salvo = enabled
		case "CHAIN":
			g.chain = enabled
		case "TOUCH":
			g.touch = enabled
		}
		fmt.Fprintf(out, "%s %s\n", cmd, w[1])
	case "PLACE":
		p, s := number(w[1])-1, shipNumber(w[2])
		if g.players[p].fleet[s] != nil {
			return fmt.Errorf("%s already placed", shipNames[s])
		}
		step := 1
		if w[4] == "V" {
			step = 10
		}
		ship := Ship{cellNumber(w[3]), step}
		if err := g.placementError(&g.players[p], s, ship); err != nil {
			return err
		}
		g.players[p].putShip(s, ship)
		g.printPlaced(p, s, out)
	case "REMOVE":
		p, s := number(w[1])-1, shipNumber(w[2])
		ship := g.players[p].fleet[s]
		if ship == nil {
			return fmt.Errorf("%s not placed", shipNames[s])
		}
		for i := 0; i < lengths[s]; i++ {
			g.players[p].board[ship.start+i*ship.step] = -1
		}
		g.players[p].fleet[s] = nil
		fmt.Fprintf(out, "REMOVED %d %s\n", p+1, shipNames[s])
	case "AUTOPLACE":
		p := number(w[1]) - 1
		attempts := g.autoplace(p, seedNumber(w[2]))
		fmt.Fprintf(out, "AUTOPLACE %d attempts %d\n", p+1, attempts)
		for s := 0; s < 5; s++ {
			g.printPlaced(p, s, out)
		}
	case "LAYOUT":
		p := number(w[1]) - 1
		fleet, err := g.parseLayout(w[2])
		if err != nil {
			return err
		}
		g.players[p].clearFleet()
		for s, ship := range fleet {
			g.players[p].putShip(s, ship)
		}
		fmt.Fprintf(out, "LAYOUT %d\n", p+1)
		for s := 0; s < 5; s++ {
			g.printPlaced(p, s, out)
		}
	case "REEF":
		c := cellNumber(w[1])
		if g.reefs[c] {
			return fmt.Errorf("reef exists at %s", w[1])
		}
		for p := range g.players {
			if s := g.players[p].board[c]; s >= 0 {
				return fmt.Errorf("%s occupied by %d %s", w[1], p+1, shipNames[s])
			}
		}
		g.reefs[c] = true
		fmt.Fprintf(out, "REEF %s\n", w[1])
	case "FIRE", "AI", "TORPEDO", "SONAR":
		if err := g.turn(w, out); err != nil {
			return err
		}
		g.automaticControl(out)
	case "RESIGN":
		if g.phase != battle {
			return errors.New("not in battle")
		}
		p := number(w[1]) - 1
		g.phase, g.winner = over, 1-p
		g.players[1-p].stats.wins++
		fmt.Fprintf(out, "RESIGN %d\nWINNER %d\n", p+1, 2-p)
	case "HINT", "DENSITY":
		if g.phase == over {
			return errors.New("game over")
		}
		p := number(w[1]) - 1
		if cmd == "HINT" {
			choice := g.choose(p, parseStrategy(w[2]))
			fmt.Fprintf(out, "HINT %d %s %s %s\n", p+1, w[2], cellName(choice.cell), choice.info())
		} else {
			view := g.view(p)
			scores := view.density()
			fmt.Fprintf(out, "DENSITY %d\n ", p+1)
			for col := 1; col <= 10; col++ {
				fmt.Fprintf(out, "%5d", col)
			}
			fmt.Fprintln(out)
			for row := 0; row < 10; row++ {
				fmt.Fprintf(out, "%c", 'A'+row)
				for col := 0; col < 10; col++ {
					c := row*10 + col
					switch view.cells[c] {
					case unknownView:
						fmt.Fprintf(out, "%5d", scores[c])
					case reefView:
						fmt.Fprintf(out, "%5s", "~")
					default:
						fmt.Fprintf(out, "%5s", "-")
					}
				}
				fmt.Fprintln(out)
			}
			best := view.best(&scores)
			fmt.Fprintf(out, "BEST %s %d\n", cellName(best), scores[best])
		}
	case "SHOW", "RADAR":
		g.showBoard(number(w[1])-1, cmd == "RADAR", out)
	case "EXPORT":
		p := number(w[1]) - 1
		var layout strings.Builder
		for c, s := range g.players[p].board {
			if c > 0 && c%10 == 0 {
				layout.WriteByte('/')
			}
			if s < 0 {
				layout.WriteByte('.')
			} else {
				layout.WriteByte(symbols[s])
			}
		}
		fmt.Fprintf(out, "EXPORT %d %s\n", p+1, layout.String())
	case "FLEET":
		p := number(w[1]) - 1
		player := &g.players[p]
		fmt.Fprintf(out, "FLEET %d afloat %d\n", p+1, player.afloat())
		for s, ship := range player.fleet {
			if ship == nil {
				fmt.Fprintf(out, "%s unplaced\n", shipNames[s])
			} else {
				state := "AFLOAT"
				if player.sunk(s) {
					state = "SUNK"
				}
				fmt.Fprintf(out, "%s %s %d/%d %s\n", shipNames[s], ship.span(lengths[s]), player.attackedCount(s), lengths[s], state)
			}
		}
	case "STATUS":
		reefs := 0
		for _, reef := range g.reefs {
			if reef {
				reefs++
			}
		}
		fmt.Fprintf(out, "STATUS %s salvo %s chain %s touch %s reefs %d", [3]string{"SETUP", "BATTLE", "OVER"}[g.phase], switchName(g.salvo), switchName(g.chain), switchName(g.touch), reefs)
		switch g.phase {
		case setup:
			fmt.Fprintf(out, " placed %d %d\n", g.players[0].placed(), g.players[1].placed())
		case battle:
			fmt.Fprintf(out, " turn %d shots %d afloat %d %d\n", g.current+1, g.allowance(g.current), g.players[0].afloat(), g.players[1].afloat())
		case over:
			fmt.Fprintf(out, " winner %d afloat %d %d\n", g.winner+1, g.players[0].afloat(), g.players[1].afloat())
		}
	case "STATS":
		for p := range g.players {
			s := &g.players[p].stats
			accuracy := "-"
			if s.shots > 0 {
				accuracy = fmt.Sprintf("%d%%", s.hits*100/s.shots)
			}
			fmt.Fprintf(out, "STATS %d shots %d hits %d sunk %d turns %d streak %d accuracy %s wins %d\n", p+1, s.shots, s.hits, s.sunk, s.turns, s.longest, accuracy, s.wins)
		}
	case "MATCH":
		methods := [2]Strategy{parseStrategy(w[3]), parseStrategy(w[4])}
		fmt.Fprintf(out, "MATCH 1 %s 2 %s\n", w[3], w[4])
		result := g.playMatch(seedNumber(w[1]), seedNumber(w[2]), methods, sinksOnly, out)
		fmt.Fprintf(out, "RESULT winner %d shots %d %d hits %d %d\n", result.winner+1, result.shots[0], result.shots[1], result.hits[0], result.hits[1])
	case "SERIES":
		count, state := number(w[1]), seedNumber(w[2])
		methods := [2]Strategy{parseStrategy(w[3]), parseStrategy(w[4])}
		var wins, shots, fastest [2]int64
		for i := 0; i < count; i++ {
			state = advance(state)
			seed1 := state
			state = advance(state)
			result := g.playMatch(seed1, state, methods, quiet, out)
			winner := result.winner
			wins[winner]++
			for p := range shots {
				shots[p] += result.shots[p]
			}
			if fastest[winner] == 0 || result.shots[winner] < fastest[winner] {
				fastest[winner] = result.shots[winner]
			}
		}
		fmt.Fprintf(out, "SERIES %d wins %d %d shots %d %d fastest", count, wins[0], wins[1], shots[0], shots[1])
		for _, best := range fastest {
			if best == 0 {
				fmt.Fprint(out, " -")
			} else {
				fmt.Fprintf(out, " %d", best)
			}
		}
		fmt.Fprintln(out)
	case "TOURNEY":
		count, state := number(w[1]), seedNumber(w[2])
		var wins, shots [3]int64
		for a := hunt; a <= random; a++ {
			for b := hunt; b <= random; b++ {
				if a == b {
					continue
				}
				for i := 0; i < count; i++ {
					state = advance(state)
					seed1 := state
					state = advance(state)
					result := g.playMatch(seed1, state, [2]Strategy{a, b}, quiet, out)
					winner := a
					if result.winner == 1 {
						winner = b
					}
					wins[winner]++
					shots[a] += result.shots[0]
					shots[b] += result.shots[1]
				}
			}
		}
		order := []int{0, 1, 2}
		sort.Slice(order, func(i, j int) bool {
			a, b := order[i], order[j]
			if wins[a] != wins[b] {
				return wins[a] > wins[b]
			}
			if shots[a] != shots[b] {
				return shots[a] < shots[b]
			}
			return a < b
		})
		fmt.Fprintf(out, "TOURNEY %d\n", count)
		for rank, s := range order {
			fmt.Fprintf(out, "%d %s wins %d shots %d\n", rank+1, strategyNames[s], wins[s], shots[s])
		}
	}
	return nil
}

func main() {
	reader := bufio.NewReader(os.Stdin)
	line, _ := reader.ReadString('\n')
	count := number(strings.TrimSpace(line))
	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()
	game := newGame()
	for i := 0; i < count; i++ {
		line, _ = reader.ReadString('\n')
		if err := game.execute(strings.Fields(line), out); err != nil {
			fmt.Fprintln(out, "ERROR", err)
		}
	}
}
