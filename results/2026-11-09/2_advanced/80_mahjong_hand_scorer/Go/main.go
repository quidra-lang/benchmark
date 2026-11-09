package main

import (
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

type Rule struct {
	name                                    string
	openTanyao, red, double, kazoe, kiriage bool
	honba                                   int
}
type Meld struct {
	kind  string
	tiles Tiles
	block Block
	valid bool
}
type Situation struct {
	label                          string
	rule                           *Rule
	hand, win, dora, ura, discards Tiles
	melds                          []Meld
	by, seat,
	from, round string
	flags         map[string]bool
	honba, sticks int
	notation      bool
}
type Candidate struct {
	kind, form, wait, category                         string
	pair                                               int
	sets, blocks                                       []Block
	yaku, yakuman, fuItems                             []Award
	multiplier, dora, aka, ura, han, fuTotal, fu, base int
}

func number(s string) int { v, _ := strconv.Atoi(s); return v }
func readLines(path string) []string {
	b, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	if len(b) == 0 {
		return nil
	}
	return strings.Split(strings.TrimSuffix(string(b),
		"\n"), "\n")
}
func readRecord(line string) (string, map[string]string) {
	a := strings.Fields(line)
	values := map[string]string{}
	for _, part := range a[1:] {
		v := strings.SplitN(part, "=", 2)
		values[v[0]] = v[1]
	}
	return a[0], values
}
func windKind(wind string) int { return 27 + strings.Index("ESWN", wind) }
func (s *Situation) closed() bool {
	for _, meld := range s.melds {
		if meld.kind != "A" {
			return false
		}
	}
	return true
}
func (s *Situation) allTiles() Tiles {
	out := combineTiles(s.hand, s.win)
	for _, meld := range s.melds {
		out = combineTiles(out, meld.tiles)
	}
	return out
}
func checkCopies(tiles Tiles, rule *Rule) string {
	if !rule.red && tiles.reds[0]+tiles.reds[1]+tiles.reds[2] > 0 {
		return "red five not allowed"
	}
	for kind, count := range tiles.counts {
		if count > 4 {
			return "too many copies of " + tileName(kind)
		}
	}
	for suit, count := range tiles.reds {
		if count > 1 {
			return "too many copies of 0" + string("mps"[suit])
		}
	}
	return ""
}
func readMeld(s string) (Meld, bool) {
	m := Meld{kind: s[:1]}
	tiles, ok := parseTiles(s[1:], false)
	if !ok {
		return m,
			false
	}
	m.tiles = tiles
	var kinds []int
	for kind, count := range tiles.counts {
		for j := 0; j < count; j++ {
			kinds = append(kinds,
				kind)
		}
	}
	size := len(kinds)
	m.block = Block{kind: kinds[0], source: m.kind}
	switch m.kind {
	case "C":
		m.valid = size == 3 && kinds[0] < 27 && kinds[0]/9 == kinds[2]/9 && kinds[1] == kinds[0]+1 && kinds[2] == kinds[0]+2
		m.block.sequence = true
	case "P":
		m.valid = size == 3 && kinds[0] == kinds[size-1]
	case "K",
		"A":
		m.valid = size == 4 && kinds[0] == kinds[size-1]
		m.block.kan = true
	}
	return m, true
}
func readSituation(label string, a map[string]string, rule *Rule) *Situation {
	s := &Situation{label: label,
		rule: rule, by: a["by"], seat: a["seat"], from: a["from"], round: a["round"], honba: number(a["honba"]),
		sticks: number(a["sticks"]), flags: map[string]bool{}, notation: true}
	var ok bool
	for _, part := range []struct {
		name        string
		destination *Tiles
		empty       bool
	}{{"hand",
		&s.hand, false}, {"win", &s.win, false}, {"dora", &s.dora, false}, {"ura", &s.ura, true}, {"discards", &s.discards,
		true}} {
		*part.destination, ok = parseTiles(a[part.name], part.empty)
		s.notation = s.notation && ok
	}
	if a["melds"] != "-" {
		for _, part := range strings.Split(a["melds"], ",") {
			meld, valid := readMeld(part)
			s.notation = s.notation && valid
			s.melds = append(s.melds,
				meld)
		}
	}
	if a["flags"] != "-" {
		for _, flag := range strings.Split(a["flags"], ",") {
			s.flags[flag] = true
		}
	}
	return s
}
func (s *Situation) check() string {
	if !s.notation || len(s.win.tiles) != 1 {
		return "bad tile notation"
	}
	if len(s.melds) > 4 {
		return "bad meld"
	}
	kans := 0
	for _, meld := range s.melds {
		if !meld.valid {
			return "bad meld"
		}
		if meld.block.kan {
			kans++
		}
	}
	if len(s.hand.tiles) != 13-3*len(s.melds) {
		return "wrong tile count"
	}
	if errorText := checkCopies(combineTiles(s.allTiles(),
		s.dora, s.ura, s.discards), s.rule); errorText != "" {
		return errorText
	}
	if s.by == "tsumo" && s.from != "-" || s.by == "ron" && (s.from == "-" || s.from == s.seat) {
		return "invalid discarder"
	}
	riichi := s.flags["riichi"] || s.flags["double_riichi"]
	for _, flag := range flagsOrder {
		if !s.flags[flag] {
			continue
		}
		valid := true
		switch flag {
		case "riichi":
			valid = s.closed()
		case "double_riichi":
			valid = s.closed() && !s.flags["riichi"]
		case "ippatsu":
			valid = riichi && !s.flags["rinshan"]
		case "haitei":
			valid = s.by == "tsumo" && !s.flags["rinshan"]
		case "houtei":
			valid = s.by == "ron" && !s.flags["chankan"]
		case "rinshan":
			valid = s.by == "tsumo" && kans > 0
		case "chankan":
			valid = s.by == "ron"
		case "tenhou":
			valid = s.seat == "E" && s.by == "tsumo" && len(s.melds) == 0 && len(s.flags) == 1
		case "chiihou":
			valid = s.seat != "E" && s.by == "tsumo" && len(s.melds) == 0 && len(s.flags) == 1
		}
		if !valid {
			return "invalid flag " + flag
		}
	}
	if len(s.dora.tiles) != 1+kans {
		return "invalid dora indicators"
	}
	if riichi && len(s.ura.tiles) != len(s.dora.tiles) || !riichi && len(s.ura.tiles) != 0 {
		return "invalid ura indicators"
	}
	if riichi && s.sticks == 0 {
		return "invalid sticks"
	}
	if !winningForm(combineTiles(s.hand,
		s.win).counts, len(s.melds)) {
		return "not a winning hand"
	}
	return ""
}
func makeCandidates(s *Situation) []*Candidate {
	counts := combineTiles(s.hand, s.win).counts
	win := s.win.tiles[0].kind
	var out []*Candidate
	for _, decomposition := range standardDecompositions(counts, len(s.melds)) {
		seen := map[string]bool{}
		for winning := -1; winning < len(decomposition.sets); winning++ {
			if winning < 0 {
				if decomposition.pair != win {
					continue
				}
			} else {
				b := decomposition.sets[winning]
				if b.sequence {
					if win < b.kind || win > b.kind+2 {
						continue
					}
				} else if win != b.kind {
					continue
				}
			}
			shape := blockNotation(decomposition.pair,
				2, false)
			if winning >= 0 {
				shape = decomposition.sets[winning].notation()
			}
			if seen[shape] {
				continue
			}
			seen[shape] = true
			c := &Candidate{kind: "standard",
				pair: decomposition.pair, wait: "tanki", sets: append([]Block(nil), decomposition.sets...), category: "none"}
			if winning >= 0 {
				c.sets[winning].winning = true
				c.wait = waitShape(c.sets[winning],
					win)
			}
			pair := blockNotation(c.pair, 2, false)
			if winning < 0 {
				pair += "*"
			}
			parts := []string{"standard",
				pair}
			for _, b := range c.sets {
				name := b.notation()
				if b.winning {
					name += "*"
				}
				parts = append(parts, name)
			}
			c.blocks = append(c.blocks,
				c.sets...)
			for _, meld := range s.melds {
				parts = append(parts, meld.kind+meld.block.notation())
				c.blocks = append(c.blocks,
					meld.block)
			}
			c.form = strings.Join(parts, " ")
			out = append(out, c)
		}
	}
	if sevenPairs(counts, len(s.melds)) {
		c := &Candidate{kind: "chiitoitsu",
			wait: "tanki", category: "none"}
		parts := []string{"chiitoitsu"}
		for kind, n := range counts {
			if n == 2 {
				name := blockNotation(kind,
					2, false)
				if kind == win {
					name += "*"
				}
				parts = append(parts, name)
			}
		}
		c.form = strings.Join(parts, " ")
		out = append(out,
			c)
	}
	if thirteenOrphans(counts, len(s.melds)) {
		c := &Candidate{kind: "kokushi", wait: "thirteen", category: "none"}
		parts := []string{"kokushi"}
		for kind, n := range counts {
			if n == 0 {
				continue
			}
			name := blockNotation(kind, n, false)
			if kind == win {
				name += "*"
			}
			parts = append(parts,
				name)
			if s.hand.counts[kind] != 1 {
				c.wait = "single"
			}
		}
		c.form = strings.Join(parts, " ")
		out = append(out,
			c)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].form < out[j].form })
	for _, c := range out {
		evaluateCandidate(c,
			s)
	}
	return out
}
func doraCount(indicators Tiles, counts [34]int) int {
	n := 0
	for _, tile := range indicators.tiles {
		n += counts[nextDora(tile.kind)]
	}
	return n
}
func evaluateCandidate(c *Candidate, s *Situation) {
	all := s.allTiles()
	closed := s.closed()
	yaku, yakuman := map[string]bool{},
		map[string]bool{}
	allSimple, allYao, allHonor, allTerminal, allGreen := true, true, true, true, true
	suitMask := 0
	hasHonor := false
	green := map[int]bool{19: true,
		20: true, 21: true, 23: true, 25: true, 32: true}
	for kind, n := range all.counts {
		if n == 0 {
			continue
		}
		if yaochuu(kind) {
			allSimple = false
		} else {
			allYao = false
		}
		if honor(kind) {
			hasHonor = true
		} else {
			allHonor = false
			suitMask |= 1 << (kind / 9)
		}
		if !terminal(kind) {
			allTerminal = false
		}
		if !green[kind] {
			allGreen = false
		}
	}
	for _, name := range []string{"riichi", "double_riichi", "ippatsu", "haitei", "houtei", "rinshan", "chankan"} {
		yaku[name] = s.flags[name]
	}
	yaku["menzen_tsumo"] = closed && s.by == "tsumo"
	yaku["tanyao"] = allSimple && (closed || s.rule.openTanyao)
	yaku["honroutou"] = allYao
	oneSuit := suitMask != 0 && suitMask&(suitMask-1) == 0
	yaku["honitsu"] = oneSuit && hasHonor
	yaku["chinitsu"] = oneSuit && !hasHonor
	yakuman["tenhou"] = s.flags["tenhou"]
	yakuman["chiihou"] = s.flags["chiihou"]
	yakuman["tsuuiisou"] = allHonor
	yakuman["chinroutou"] = allTerminal
	yakuman["ryuuiisou"] = allGreen
	if len(s.melds) == 0 && oneSuit && !hasHonor {
		suit := 0
		for suitMask>>suit&1 == 0 {
			suit++
		}
		chuuren,
			pure := true, true
		for rank := 0; rank < 9; rank++ {
			required := 1
			if rank == 0 || rank == 8 {
				required = 3
			}
			if all.counts[suit*9+rank] < required {
				chuuren = false
			}
			if s.hand.counts[suit*9+rank] != required {
				pure = false
			}
		}
		if chuuren {
			if pure {
				yakuman["junsei_chuuren"] = true
			} else {
				yakuman["chuuren"] = true
			}
		}
	}
	switch c.kind {
	case "chiitoitsu":
		yaku["chiitoitsu"] = true
	case "kokushi":
		if c.wait == "thirteen" {
			yakuman["kokushi_13"] = true
		} else {
			yakuman["kokushi"] = true
		}
	case "standard":
		triplets,
			sequences, concealedCount, kans, dragons, winds := map[int]bool{}, map[int]bool{}, 0, 0, 0, 0
		allBlocksYao := yaochuu(c.pair)
		for _, b := range c.blocks {
			if b.sequence {
				sequences[b.kind] = true
				if b.kind%9 != 0 && b.kind%9 != 6 {
					allBlocksYao = false
				}
			} else {
				triplets[b.kind] = true
				if concealed(b,
					s.by) {
					concealedCount++
				}
				if b.kan {
					kans++
				}
				if b.kind >= 31 {
					dragons++
				} else if b.kind >= 27 {
					winds++
				}
				if !yaochuu(b.kind) {
					allBlocksYao = false
				}
			}
		}
		closedSequences := map[int]int{}
		allSequences := len(c.sets) == 4
		for _, b := range c.sets {
			if b.sequence {
				closedSequences[b.kind]++
			} else {
				allSequences = false
			}
		}
		pairs := 0
		hasDuplicate := false
		for _, n := range closedSequences {
			pairs += n / 2
			if n >= 2 {
				hasDuplicate = true
			}
		}
		yaku["pinfu"] = closed && len(s.melds) == 0 && allSequences && pairFu(c.pair,
			windKind(s.seat), windKind(s.round)) == 0 && c.wait == "ryanmen"
		yaku["ryanpeikou"] = closed && allSequences && pairs == 2
		yaku["iipeikou"] = closed && !yaku["ryanpeikou"] && hasDuplicate
		yaku["haku"],
			yaku["hatsu"], yaku["chun"] = triplets[31], triplets[32], triplets[33]
		yaku["jikaze"] = triplets[windKind(s.seat)]
		yaku["bakaze"] = triplets[windKind(s.round)]
		yaku["toitoi"] = len(triplets) == 4
		yaku["sanankou"] = concealedCount == 3
		for rank := 0; rank < 9; rank++ {
			if rank <= 6 && sequences[rank] && sequences[9+rank] && sequences[18+rank] {
				yaku["sanshoku_doujun"] = true
			}
			if triplets[rank] && triplets[9+rank] && triplets[18+rank] {
				yaku["sanshoku_doukou"] = true
			}
		}
		for suit := 0; suit < 3; suit++ {
			if sequences[suit*9] && sequences[suit*9+3] && sequences[suit*9+6] {
				yaku["ittsu"] = true
			}
		}
		if len(sequences) > 0 && allBlocksYao {
			if hasHonor {
				yaku["chanta"] = true
			} else {
				yaku["junchan"] = true
			}
		}
		yaku["sankantsu"] = kans == 3
		yaku["shousangen"] = dragons == 2 && c.pair >= 31
		if concealedCount == 4 {
			if c.wait == "tanki" {
				yakuman["suuankou_tanki"] = true
			} else {
				yakuman["suuankou"] = true
			}
		}
		yakuman["daisangen"] = dragons == 3
		yakuman["daisuushii"] = winds == 4
		yakuman["shousuushii"] = winds == 3 && c.pair >= 27 && c.pair <= 30
		yakuman["suukantsu"] = kans == 4
	}
	c.yakuman = yakumanAwards(yakuman,
		s.rule.double)
	if len(c.yakuman) > 0 {
		for _, award := range c.yakuman {
			c.multiplier += award.value
		}
		c.category = "yakuman"
		c.base = 8000 * c.multiplier
		return
	}
	c.yaku = yakuAwards(yaku,
		closed)
	c.dora = doraCount(s.dora, all.counts)
	c.ura = doraCount(s.ura, all.counts)
	c.aka = all.reds[0] + all.reds[1] + all.reds[2]
	c.han = c.dora + c.ura + c.aka
	for _, award := range c.yaku {
		c.han += award.value
	}
	c.fuItems, c.fuTotal, c.fu = fuBreakdown(c, s, closed, yaku["pinfu"])
	if len(c.yaku) > 0 {
		c.category,
			c.base = limitScore(c.han, c.fu, s.rule)
	}
}
func bestCandidate(candidates []*Candidate) *Candidate {
	var best *Candidate
	for _, c := range candidates {
		if c.base <= 0 {
			continue
		}
		better := best == nil
		if best != nil {
			switch {
			case c.base != best.base:
				better = c.base > best.base
			case (c.multiplier > 0) != (best.multiplier > 0):
				better = c.multiplier > 0
			case c.multiplier == 0 && c.han != best.han:
				better = c.han > best.han
			case c.multiplier == 0 && c.fu != best.fu:
				better = c.fu > best.fu
			default:
				better = c.form < best.form
			}
		}
		if better {
			best = c
		}
	}
	return best
}
func awardNames(a []Award, separator string) string {
	names := make([]string, len(a))
	for i, v := range a {
		names[i] = v.name
	}
	return strings.Join(names, separator)
}
func candidateText(c *Candidate) string {
	if c.multiplier > 0 {
		return fmt.Sprintf("yakuman %d base %d yaku %s",
			c.multiplier, c.base, awardNames(c.yakuman, ","))
	}
	if c.base == 0 {
		return "no_yaku"
	}
	return fmt.Sprintf("han %d fu %d base %d yaku %s",
		c.han, c.fu, c.base, awardNames(c.yaku, ","))
}
func discardedWait(discards Tiles, waits []int) bool {
	for _, kind := range waits {
		if discards.counts[kind] > 0 {
			return true
		}
	}
	return false
}

type HandStats struct {
	hands, wins, furiten, noYaku, errors, totalPoints, maxPoints int
	maxHand                                                      string
	winsBy,
	waits, limits, yaku map[string]int
	han, fu map[int]int
	rules   map[string][3]int
}

func newHandStats() *HandStats {
	return &HandStats{maxHand: "-", winsBy: map[string]int{}, waits: map[string]int{},
		limits: map[string]int{}, yaku: map[string]int{}, han: map[int]int{}, fu: map[int]int{}, rules: map[string][3]int{}}
}
func tileList(kinds []int) string {
	names := make([]string, len(kinds))
	for i, kind := range kinds {
		names[i] = tileName(kind)
	}
	return strings.Join(names, " ")
}
func signed(n int) string {
	if n > 0 {
		return "+" + strconv.Itoa(n)
	}
	return strconv.Itoa(n)
}
func outputHand(s *Situation, stats *HandStats) ([]string, string) {
	out := []string{"HAND " + s.label}
	stats.hands++
	ruleStats := stats.rules[s.rule.name]
	ruleStats[0]++
	stats.rules[s.rule.name] = ruleStats
	if errorText := s.check(); errorText != "" {
		stats.errors++
		out = append(out,
			"ERROR "+errorText)
		return out, s.label + ",-,-,0,ERROR"
	}
	waits := waitingTiles(s.hand, s.melds)
	out = append(out,
		"WAITS "+tileList(waits))
	candidates := makeCandidates(s)
	for _, candidate := range candidates {
		out = append(out,
			"CANDIDATE "+candidate.form+" = "+candidate.wait+" "+candidateText(candidate))
	}
	if s.by == "ron" && discardedWait(s.discards,
		waits) {
		stats.furiten++
		out = append(out, "RESULT furiten")
		return out, s.label + ",-,-,0,FURITEN"
	}
	best := bestCandidate(candidates)
	if best == nil {
		stats.noYaku++
		out = append(out,
			"RESULT no_yaku")
		return out, s.label + ",-,-,0,NO_YAKU"
	}
	stats.wins++
	winKind := "nondealer_" + s.by
	if s.seat == "E" {
		winKind = "dealer_" + s.by
	}
	stats.winsBy[winKind]++
	stats.waits[best.wait]++
	stats.limits[best.category]++
	out = append(out,
		"FORM "+best.form, "WAIT "+best.wait)
	summary := ""
	payment := payments(best.base, s.seat, s.by)
	if best.multiplier > 0 {
		for _, a := range best.yakuman {
			out = append(out, fmt.Sprintf("YAKUMAN %s %d", a.name, a.value))
			stats.yaku[a.name]++
		}
		out = append(out,
			fmt.Sprintf("SCORE yakuman %d base %d", best.multiplier, best.base))
		summary = fmt.Sprintf("%s,Y%d,-,%d,%s",
			s.label, best.multiplier, payment.points, awardNames(best.yakuman, ";"))
	} else {
		stats.han[best.han]++
		stats.fu[best.fu]++
		for _, a := range best.yaku {
			out = append(out, fmt.Sprintf("YAKU %s %d", a.name, a.value))
			stats.yaku[a.name]++
		}
		out = append(out,
			fmt.Sprintf("DORA dora %d aka %d ura %d", best.dora, best.aka, best.ura))
		for _, a := range best.fuItems {
			out = append(out,
				fmt.Sprintf("FU %s %d", a.name, a.value))
		}
		out = append(out, fmt.Sprintf("FU total %d %d", best.fuTotal,
			best.fu), fmt.Sprintf("SCORE han %d fu %d limit %s base %d", best.han, best.fu, best.category, best.base))
		summary = fmt.Sprintf("%s,%d,%d,%d,%s",
			s.label, best.han, best.fu, payment.points, awardNames(best.yaku, ";"))
	}
	if s.by == "ron" {
		out = append(out,
			fmt.Sprintf("PAY ron %d", payment.ron))
	} else if s.seat == "E" {
		out = append(out, fmt.Sprintf("PAY tsumo all %d",
			payment.all))
	} else {
		out = append(out, fmt.Sprintf("PAY tsumo dealer %d nondealer %d", payment.dealer,
			payment.nondealer))
	}
	honba, sticks := s.honba*s.rule.honba, s.sticks*1000
	gain := payment.points + honba + sticks
	out = append(out,
		fmt.Sprintf("BONUS honba %d sticks %d", honba, sticks), fmt.Sprintf("TOTAL points %d gain %d", payment.points,
			gain))
	var delta [4]int
	winner := strings.Index("ESWN", s.seat)
	delta[winner] = gain
	if s.by == "ron" {
		delta[strings.Index("ESWN",
			s.from)] = -(payment.ron + honba)
	} else {
		for player := 0; player < 4; player++ {
			if player == winner {
				continue
			}
			pay := payment.nondealer
			if s.seat == "E" {
				pay = payment.all
			} else if player == 0 {
				pay = payment.dealer
			}
			delta[player] = -(pay + honba/3)
		}
	}
	out = append(out,
		fmt.Sprintf("DELTA E %s S %s W %s N %s", signed(delta[0]), signed(delta[1]), signed(delta[2]), signed(delta[3])))
	stats.totalPoints += payment.points
	if payment.points > stats.maxPoints {
		stats.maxPoints = payment.points
		stats.maxHand = s.label
	}
	ruleStats = stats.rules[s.rule.name]
	ruleStats[1]++
	ruleStats[2] += payment.points
	stats.rules[s.rule.name] = ruleStats
	return out,
		summary
}
func sortedIntKeys(a map[int]int) []int {
	var keys []int
	for key := range a {
		keys = append(keys, key)
	}
	sort.Ints(keys)
	return keys
}
func (s *HandStats) lines(rules []*Rule) []string {
	out := []string{fmt.Sprintf("STATS hands %d wins %d furiten %d no_yaku %d errors %d",
		s.hands, s.wins, s.furiten, s.noYaku, s.errors), fmt.Sprintf("WINS dealer_ron %d dealer_tsumo %d nondealer_ron %d nondealer_tsumo %d",
		s.winsBy["dealer_ron"], s.winsBy["dealer_tsumo"], s.winsBy["nondealer_ron"], s.winsBy["nondealer_tsumo"])}
	text := "WAIT_COUNT"
	for _, shape := range waitShapes {
		text += fmt.Sprintf(" %s %d", shape, s.waits[shape])
	}
	out = append(out, text)
	for _, han := range sortedIntKeys(s.han) {
		out = append(out, fmt.Sprintf("HAN_COUNT %d %d", han, s.han[han]))
	}
	for _, fu := range sortedIntKeys(s.fu) {
		out = append(out, fmt.Sprintf("FU_COUNT %d %d", fu, s.fu[fu]))
	}
	for _, category := range categories {
		out = append(out, fmt.Sprintf("LIMIT %s %d", category, s.limits[category]))
	}
	var names []string
	for _, yaku := range yakuTable {
		names = append(names, yaku.name)
	}
	for _, yakuman := range yakumanTable {
		names = append(names,
			yakuman.name)
	}
	for _, name := range names {
		if s.yaku[name] > 0 {
			out = append(out, fmt.Sprintf("YAKU_COUNT %s %d",
				name, s.yaku[name]))
		}
	}
	out = append(out, fmt.Sprintf("POINTS total %d max %d hand %s", s.totalPoints,
		s.maxPoints, s.maxHand))
	for _, rule := range rules {
		values := s.rules[rule.name]
		out = append(out, fmt.Sprintf("RULE %s hands %d wins %d points %d",
			rule.name, values[0], values[1], values[2]))
	}
	return out
}

type WaitStats struct {
	hands, errors, tenpai, furiten int
	shanten                        [7]int
}

func analyzeWait(label string, a map[string]string, rule *Rule, stats *WaitStats) []string {
	out := []string{"HAND " + label}
	stats.hands++
	hand,
		handOK := parseTiles(a["hand"], false)
	dora, doraOK := parseTiles(a["dora"], false)
	discards, discardsOK := parseTiles(a["discards"],
		true)
	visible, visibleOK := parseTiles(a["visible"], true)
	errorText := ""
	if !handOK || !doraOK || !discardsOK || !visibleOK {
		errorText = "bad tile notation"
	} else if len(hand.tiles) != 13 {
		errorText = "wrong tile count"
	} else {
		errorText = checkCopies(combineTiles(hand,
			dora, discards, visible), rule)
	}
	if errorText != "" {
		stats.errors++
		return append(out, "ERROR "+errorText)
	}
	analyzer := newShanten()
	numbers := analyzer.numbers(hand.counts)
	shanten := minimumShanten(numbers)
	stats.shanten[shanten]++
	out = append(out,
		fmt.Sprintf("SHANTEN standard %d chiitoitsu %d kokushi %d", numbers[0], numbers[1], numbers[2]))
	all := combineTiles(hand,
		dora, discards, visible)
	var accept, left []int
	remaining := 0
	for kind := 0; kind < 34; kind++ {
		if hand.counts[kind] >= 4 {
			continue
		}
		counts := hand.counts
		counts[kind]++
		if minimumShanten(analyzer.numbers(counts)) < shanten {
			accept = append(accept,
				kind)
			count := 4 - all.counts[kind]
			left = append(left, count)
			remaining += count
		}
	}
	if shanten > 0 {
		text := fmt.Sprintf("ACCEPT kinds %d tiles %d",
			len(accept), remaining)
		for i, kind := range accept {
			text += fmt.Sprintf(" %s:%d", tileName(kind), left[i])
		}
		return append(out,
			text)
	}
	stats.tenpai++
	furiten := discardedWait(discards, accept)
	furitenText := "no"
	if furiten {
		furitenText = "yes"
		stats.furiten++
	}
	out = append(out,
		fmt.Sprintf("TENPAI kinds %d tiles %d furiten %s", len(accept), remaining, furitenText))
	bestRon,
		bestTsumo := "none", "none"
	ronPoints, tsumoPoints := 0, 0
	for i, kind := range accept {
		values := make([]string,
			2)
		for method, by := range []string{"ron", "tsumo"} {
			if method == 0 && furiten {
				values[method] = "furiten"
				continue
			}
			flags := map[string]bool{}
			if a["riichi"] == "yes" {
				flags["riichi"] = true
			}
			s := &Situation{rule: rule,
				hand: hand, win: Tiles{tiles: []Tile{{kind: kind}}}, dora: dora, by: by, seat: a["seat"], round: a["round"],
				flags: flags}
			s.win.counts[kind] = 1
			best := bestCandidate(makeCandidates(s))
			if best == nil {
				values[method] = "no_yaku"
				continue
			}
			points := payments(best.base,
				s.seat, by).points
			values[method] = strconv.Itoa(points)
			if method == 0 && points > ronPoints {
				ronPoints = points
				bestRon = fmt.Sprintf("%s %d",
					tileName(kind), points)
			}
			if method == 1 && points > tsumoPoints {
				tsumoPoints = points
				bestTsumo = fmt.Sprintf("%s %d",
					tileName(kind), points)
			}
		}
		out = append(out, fmt.Sprintf("WAIT %s left %d ron %s tsumo %s", tileName(kind),
			left[i], values[0], values[1]))
	}
	out = append(out, "BEST ron "+bestRon+" tsumo "+bestTsumo)
	return out
}
func (s WaitStats) lines() []string {
	out := []string{fmt.Sprintf("STATS hands %d errors %d tenpai %d furiten %d",
		s.hands, s.errors, s.tenpai, s.furiten)}
	for n, count := range s.shanten {
		out = append(out, fmt.Sprintf("SHANTEN_COUNT %d %d",
			n, count))
	}
	return out
}
func writeLines(name string, lines []string) {
	if err := os.WriteFile("output/"+name, []byte(strings.Join(lines, "\n")+"\n"), 0644); err != nil {
		panic(err)
	}
}
func main() {
	var rules []*Rule
	byName := map[string]*Rule{}
	for _, line := range readLines("input/rules.txt") {
		label,
			a := readRecord(line)
		rule := &Rule{label, a["open_tanyao"] == "yes", a["red_fives"] == "yes", a["double_yakuman"] == "yes",
			a["kazoe_yakuman"] == "yes", a["kiriage"] == "yes", number(a["honba"])}
		rules = append(rules, rule)
		byName[label] = rule
	}
	stats := newHandStats()
	var scores,
		waits []string
	summary := []string{"hand,han,fu,points,yaku"}
	for _, line := range readLines("input/hands.txt") {
		label,
			a := readRecord(line)
		out, row := outputHand(readSituation(label, a, byName[a["rules"]]), stats)
		scores = append(scores,
			out...)
		summary = append(summary, row)
	}
	scores = append(scores, stats.lines(rules)...)
	waitStats := &WaitStats{}
	for _, line := range readLines("input/waits.txt") {
		label, a := readRecord(line)
		waits = append(waits, analyzeWait(label,
			a, byName[a["rules"]], waitStats)...)
	}
	waits = append(waits, waitStats.lines()...)
	if err := os.MkdirAll("output",
		0755); err != nil {
		panic(err)
	}
	writeLines("scores.txt", scores)
	writeLines("waits.txt", waits)
	writeLines("summary.csv",
		summary)
}
