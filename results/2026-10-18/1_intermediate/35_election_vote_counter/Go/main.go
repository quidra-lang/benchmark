package main

import (
	"bufio"
	"cmp"
	"errors"
	"fmt"
	"math/bits"
	"os"
	"slices"
	"strconv"
	"strings"
)

const limit = 7

type Field uint8
type Row [limit]int
type Matrix [limit]Row
type Relation [limit][limit]bool

type Ballot struct {
	votes   int
	ranking []int
}

type Tallies struct {
	first, last, borda Row
	approval          Matrix
	nonblank          int
	ready             bool
}

type MethodKind int

const (
	Plurality MethodKind = iota
	Runoff
	IRV
	Coombs
	Bucklin
	Borda
	Baldwin
	Nanson
	Black
	Veto
	Condorcet
	Copeland
	Minimax
	Schulze
	RankedPairs
	Kemeny
	Approval
	STV
)

type MinimaxKind int

const (
	Winning MinimaxKind = iota
	Margin
	Opposition
)

type Method struct {
	kind      MethodKind
	parameter int
	minimax   MinimaxKind
}

var methodNames = [...]string{
	"PLURALITY", "RUNOFF", "IRV", "COOMBS", "BUCKLIN", "BORDA", "BALDWIN", "NANSON", "BLACK",
	"VETO", "CONDORCET", "COPELAND", "MINIMAX", "SCHULZE", "RANKEDPAIRS", "KEMENY", "APPROVAL", "STV",
}

var summaryMethods = [...]Method{
	{kind: Plurality}, {kind: Runoff}, {kind: IRV}, {kind: Coombs}, {kind: Bucklin},
	{kind: Borda}, {kind: Baldwin}, {kind: Nanson}, {kind: Black}, {kind: Veto},
	{kind: Copeland}, {kind: Minimax}, {kind: Schulze}, {kind: RankedPairs}, {kind: Kemeny},
}

func number(text string) int {
	value, _ := strconv.Atoi(text)
	return value
}

func parseMethod(words []string) Method {
	method := Method{kind: MethodKind(slices.Index(methodNames[:], words[0]))}
	switch method.kind {
	case Minimax:
		method.minimax = map[string]MinimaxKind{"WINNING": Winning, "MARGIN": Margin, "OPPOSITION": Opposition}[words[1]]
	case Approval, STV:
		method.parameter = number(words[1])
	}
	return method
}

func (method Method) String() string {
	name := methodNames[method.kind]
	switch method.kind {
	case Minimax:
		return name + " " + [...]string{"WINNING", "MARGIN", "OPPOSITION"}[method.minimax]
	case Approval, STV:
		return fmt.Sprintf("%s %d", name, method.parameter)
	}
	return name
}

func (method Method) rankable() bool { return method.kind != Condorcet && method.kind != STV }

type Outcome struct {
	order []int
	lines []string
}

type Election struct {
	number     int
	names      []string
	active     Field
	tiebreak   []int
	priority   Row
	groups     []Ballot
	entryEnds  []int
	total      int
	cache      [1 << limit]Tallies
	pairs      Matrix
	pairsReady bool
}

func bit(candidate int) Field { return 1 << candidate }

func (field Field) members() []int {
	var result []int
	for a := range limit {
		if field&bit(a) != 0 {
			result = append(result, a)
		}
	}
	return result
}

func (field Field) count() int { return bits.OnesCount8(uint8(field)) }

func mask(list []int) Field {
	var field Field
	for _, a := range list {
		field |= bit(a)
	}
	return field
}

func effective(ranking []int, field Field) []int {
	var result []int
	for _, a := range ranking {
		if field&bit(a) != 0 {
			result = append(result, a)
		}
	}
	return result
}

func money(value int) string { return fmt.Sprintf("%d.%02d", value/100, value%100) }

func tieMark(tie bool) string {
	if tie {
		return " (tie)"
	}
	return ""
}

func sum(field Field, scores Row) int {
	result := 0
	for _, a := range field.members() {
		result += scores[a]
	}
	return result
}

func majority(field Field, scores Row) bool {
	total := sum(field, scores)
	for _, a := range field.members() {
		if 2*scores[a] > total {
			return true
		}
	}
	return false
}

func closure(field Field, relation *Relation) {
	list := field.members()
	for _, via := range list {
		for _, a := range list {
			for _, b := range list {
				relation[a][b] = relation[a][b] || relation[a][via] && relation[via][b]
			}
		}
	}
}

func newElection(number int, names []string) *Election {
	e := &Election{number: number, names: slices.Clone(names), active: bit(len(names)) - 1}
	order := e.active.members()
	slices.SortFunc(order, func(a, b int) int { return strings.Compare(e.names[a], e.names[b]) })
	e.setTiebreak(order)
	return e
}

func (e *Election) candidate(name string) (int, error) {
	a := slices.Index(e.names, name)
	if a < 0 {
		return 0, fmt.Errorf("unknown candidate %s", name)
	}
	return a, nil
}

func (e *Election) checkNames(names []string) ([]int, error) {
	var result []int
	var seen Field
	for _, name := range names {
		a, err := e.candidate(name)
		if err != nil {
			return nil, err
		}
		if seen&bit(a) != 0 {
			return nil, fmt.Errorf("duplicate candidate %s", name)
		}
		seen |= bit(a)
		result = append(result, a)
	}
	return result, nil
}

func (e *Election) namesText(list []int, separator string) string {
	names := make([]string, len(list))
	for i, a := range list {
		names[i] = e.names[a]
	}
	return strings.Join(names, separator)
}

func (e *Election) values(field Field, scores Row, cents bool) string {
	var values []string
	for _, a := range field.members() {
		value := strconv.Itoa(scores[a])
		if cents {
			value = money(scores[a])
		}
		values = append(values, e.names[a]+" "+value)
	}
	return strings.Join(values, ", ")
}

func (e *Election) ordered(field Field, scores Row, descending bool) []int {
	order := field.members()
	slices.SortFunc(order, func(a, b int) int {
		comparison := cmp.Compare(scores[a], scores[b])
		if descending {
			comparison = -comparison
		}
		if comparison != 0 {
			return comparison
		}
		return cmp.Compare(e.priority[a], e.priority[b])
	})
	return order
}

func (e *Election) finish(order []int, tie bool, lines []string) Outcome {
	lines = append(lines, "winner: "+e.names[order[0]]+tieMark(tie))
	return Outcome{order: order, lines: lines}
}

func (e *Election) setTiebreak(order []int) {
	e.tiebreak = order
	for i, a := range order {
		e.priority[a] = i
	}
}

func (e *Election) invalidate() {
	for i := range e.cache {
		e.cache[i].ready = false
	}
	e.pairsReady = false
}

func (e *Election) finishEntry() {
	e.entryEnds = append(e.entryEnds, len(e.groups))
	e.invalidate()
}

func (e *Election) tallies(field Field) Tallies {
	if result := e.cache[field]; result.ready {
		return result
	}
	result := Tallies{ready: true}
	m := field.count()
	for _, group := range e.groups {
		ranking := effective(group.ranking, field)
		ranked := mask(ranking)
		if len(ranking) > 0 {
			result.first[ranking[0]] += group.votes
			result.nonblank += group.votes
		}
		if len(ranking) == m {
			result.last[ranking[m-1]] += group.votes
		} else {
			for _, a := range (field &^ ranked).members() {
				result.last[a] += group.votes
			}
		}
		for j, a := range ranking {
			result.borda[a] += group.votes * (m - j - 1)
			for depth := j; depth < m; depth++ {
				result.approval[depth][a] += group.votes
			}
		}
	}
	e.cache[field] = result
	return result
}

func (e *Election) pairwise() Matrix {
	if e.pairsReady {
		return e.pairs
	}
	var matrix Matrix
	for _, group := range e.groups {
		positions := Row{}
		for a := range e.names {
			positions[a] = limit
		}
		for i, a := range group.ranking {
			positions[a] = i
		}
		for a := range e.names {
			for b := range e.names {
				if positions[a] < positions[b] {
					matrix[a][b] += group.votes
				}
			}
		}
	}
	e.pairs, e.pairsReady = matrix, true
	return matrix
}

func (e *Election) condorcet(field Field, loser bool) int {
	matrix := e.pairwise()
	list := field.members()
	for _, a := range list {
		all := true
		for _, b := range list {
			if a == b {
				continue
			}
			if loser && matrix[a][b] >= matrix[b][a] || !loser && matrix[a][b] <= matrix[b][a] {
				all = false
			}
		}
		if all {
			return a
		}
	}
	return -1
}

func (e *Election) lookBack(field Field, history []Row) (int, bool) {
	choices := field.members()
	tie := false
	for r := len(history) - 1; r >= 0; r-- {
		minimum := history[r][choices[0]]
		for _, a := range choices {
			minimum = min(minimum, history[r][a])
		}
		choices = slices.DeleteFunc(choices, func(a int) bool { return history[r][a] != minimum })
		if r == len(history)-1 {
			tie = len(choices) > 1
		}
	}
	eliminated := choices[0]
	for _, a := range choices {
		if e.priority[a] > e.priority[eliminated] {
			eliminated = a
		}
	}
	return eliminated, tie
}

func (e *Election) elimination(field Field, coombs, exhausted bool) Outcome {
	remaining := field
	var removed []int
	var history []Row
	var lines []string
	for {
		scores := e.tallies(remaining)
		round := len(lines) + 1
		line := fmt.Sprintf("round %d: %s", round, e.values(remaining, scores.first, false))
		if exhausted {
			active := sum(remaining, scores.first)
			line = fmt.Sprintf("round %d: active %d, exhausted %d", round, active, e.total-active)
		}
		if remaining.count() == 1 || majority(remaining, scores.first) {
			lines = append(lines, line)
			order := e.ordered(remaining, scores.first, true)
			slices.Reverse(removed)
			order = append(order, removed...)
			if exhausted {
				return Outcome{order: order, lines: lines}
			}
			return e.finish(order, false, lines)
		}
		var eliminated int
		var tie bool
		if coombs {
			list := e.ordered(remaining, scores.last, true)
			maximum := scores.last[list[0]]
			choices := slices.DeleteFunc(list, func(a int) bool { return scores.last[a] != maximum })
			tie = len(choices) > 1
			least := e.ordered(mask(choices), scores.first, true)
			eliminated = least[len(least)-1]
			line += "; last " + e.values(remaining, scores.last, false)
		} else {
			history = append(history, scores.first)
			eliminated, tie = e.lookBack(remaining, history)
		}
		if !exhausted {
			line += "; eliminated " + e.names[eliminated] + tieMark(tie)
		}
		lines = append(lines, line)
		removed = append(removed, eliminated)
		remaining &^= bit(eliminated)
	}
}

func (e *Election) runoff(field Field) Outcome {
	first := e.tallies(field)
	order := e.ordered(field, first.first, true)
	lines := []string{"round 1: " + e.values(field, first.first, false)}
	tie := false
	if !majority(field, first.first) {
		a, b := order[0], order[1]
		finalists := bit(a) | bit(b)
		advancementTie := len(order) >= 3 && first.first[b] == first.first[order[2]]
		second := e.tallies(finalists)
		tie = second.first[a] == second.first[b]
		if second.first[b] > second.first[a] {
			order[0], order[1] = b, a
		}
		lines = append(lines, "finalists: "+e.namesText(finalists.members(), ", ")+tieMark(advancementTie),
			"round 2: "+e.values(finalists, second.first, false))
	}
	return e.finish(order, tie, lines)
}

func (e *Election) bucklin(field Field) Outcome {
	scores := e.tallies(field)
	majority := scores.nonblank/2 + 1
	lines := []string{fmt.Sprintf("majority: %d", majority)}
	order := field.members()
	final := 0
	for depth := range len(order) {
		final = depth
		lines = append(lines, fmt.Sprintf("round %d: %s", depth+1, e.values(field, scores.approval[depth], false)))
		done := false
		for _, a := range order {
			if scores.approval[depth][a] >= majority {
				done = true
			}
		}
		if done {
			break
		}
	}
	slices.SortFunc(order, func(a, b int) int {
		for depth := final; depth >= 0; depth-- {
			if comparison := cmp.Compare(scores.approval[depth][b], scores.approval[depth][a]); comparison != 0 {
				return comparison
			}
		}
		return cmp.Compare(e.priority[a], e.priority[b])
	})
	tie := scores.approval[final][order[0]] == scores.approval[final][order[1]]
	return e.finish(order, tie, lines)
}

func (e *Election) bordaElimination(field Field, nanson bool) Outcome {
	remaining := field
	var tail []int
	var lines []string
	var history []Row
	for remaining.count() >= 2 {
		scores := e.tallies(remaining).borda
		line := fmt.Sprintf("round %d: %s", len(lines)+1, e.values(remaining, scores, false))
		var removed []int
		if nanson {
			total := sum(remaining, scores)
			var below Field
			for _, a := range remaining.members() {
				if scores[a]*remaining.count() < total {
					below |= bit(a)
				}
			}
			if below == 0 {
				lines = append(lines, line)
				break
			}
			line += "; eliminated " + e.namesText(below.members(), ", ")
			removed = e.ordered(below, scores, true)
		} else {
			history = append(history, scores)
			a, tie := e.lookBack(remaining, history)
			line += "; eliminated " + e.names[a] + tieMark(tie)
			removed = []int{a}
		}
		lines = append(lines, line)
		remaining &^= mask(removed)
		tail = append(removed, tail...)
	}
	order := e.ordered(remaining, Row{}, true)
	tie := nanson && len(order) > 1
	return e.finish(append(order, tail...), tie, lines)
}

func (e *Election) pairLines(field Field, matrix Matrix) []string {
	list := field.members()
	var lines []string
	for i, a := range list {
		for _, b := range list[i+1:] {
			result := "tie"
			if matrix[a][b] > matrix[b][a] {
				result = e.names[a]
			} else if matrix[a][b] < matrix[b][a] {
				result = e.names[b]
			}
			lines = append(lines, fmt.Sprintf("%s vs %s: %d-%d (%s)", e.names[a], e.names[b], matrix[a][b], matrix[b][a], result))
		}
	}
	return lines
}

func (e *Election) condorcetReport(field Field) Outcome {
	win, lose := e.condorcet(field, false), e.condorcet(field, true)
	matrix := e.pairwise()
	var weak, strong Relation
	list := field.members()
	for _, a := range list {
		for _, b := range list {
			weak[a][b] = matrix[a][b] >= matrix[b][a]
			strong[a][b] = matrix[a][b] > matrix[b][a]
		}
	}
	closure(field, &weak)
	closure(field, &strong)
	var smith, schwartz []int
	for _, a := range list {
		top, unbeaten := true, true
		for _, b := range list {
			top = top && weak[a][b]
			unbeaten = unbeaten && (!strong[b][a] || strong[a][b])
		}
		if top {
			smith = append(smith, a)
		}
		if unbeaten {
			schwartz = append(schwartz, a)
		}
	}
	winner, loser := "NONE", "NONE"
	if win >= 0 {
		winner = e.names[win]
	}
	if lose >= 0 {
		loser = e.names[lose]
	}
	return Outcome{lines: []string{"winner: " + winner, "loser: " + loser,
		"smith: " + e.namesText(smith, ", "), "schwartz: " + e.namesText(schwartz, ", ")}}
}

func (e *Election) topological(field Field, relation Relation) ([]int, bool) {
	remaining := field
	var order []int
	tie := false
	for remaining != 0 {
		var choices Field
		list := remaining.members()
		for _, a := range list {
			incoming := false
			for _, b := range list {
				if a != b && relation[b][a] {
					incoming = true
				}
			}
			if !incoming {
				choices |= bit(a)
			}
		}
		if len(order) == 0 {
			tie = choices.count() > 1
		}
		for _, a := range e.tiebreak {
			if choices&bit(a) != 0 {
				order = append(order, a)
				remaining &^= bit(a)
				break
			}
		}
	}
	return order, tie
}

func (e *Election) schulze(field Field) Outcome {
	matrix := e.pairwise()
	list := field.members()
	var paths Matrix
	for _, a := range list {
		for _, b := range list {
			if matrix[a][b] > matrix[b][a] {
				paths[a][b] = matrix[a][b]
			}
		}
	}
	for _, via := range list {
		for _, a := range list {
			for _, b := range list {
				if a != via && b != via && a != b {
					paths[a][b] = max(paths[a][b], min(paths[a][via], paths[via][b]))
				}
			}
		}
	}
	var relation Relation
	for _, a := range list {
		for _, b := range list {
			relation[a][b] = paths[a][b] > paths[b][a]
		}
	}
	order, tie := e.topological(field, relation)
	lines := append(e.pairLines(field, paths), "ranking: "+e.namesText(order, " > "))
	return e.finish(order, tie, lines)
}

type Edge struct{ from, to int }

func (e *Election) rankedPairs(field Field) Outcome {
	matrix := e.pairwise()
	list := field.members()
	var pairs []Edge
	for _, a := range list {
		for _, b := range list {
			if matrix[a][b] > matrix[b][a] {
				pairs = append(pairs, Edge{a, b})
			}
		}
	}
	slices.SortFunc(pairs, func(a, b Edge) int {
		if comparison := cmp.Compare(matrix[b.from][b.to], matrix[a.from][a.to]); comparison != 0 {
			return comparison
		}
		if comparison := cmp.Compare(matrix[a.to][a.from], matrix[b.to][b.from]); comparison != 0 {
			return comparison
		}
		if comparison := cmp.Compare(e.priority[a.from], e.priority[b.from]); comparison != 0 {
			return comparison
		}
		return cmp.Compare(e.priority[a.to], e.priority[b.to])
	})
	var locked, reached Relation
	var lines []string
	for _, edge := range pairs {
		a, b := edge.from, edge.to
		action := "skip"
		if !reached[b][a] {
			action = "lock"
			locked[a][b], reached[a][b] = true, true
			closure(field, &reached)
		}
		lines = append(lines, fmt.Sprintf("%s %s>%s %d-%d", action, e.names[a], e.names[b], matrix[a][b], matrix[b][a]))
	}
	order, tie := e.topological(field, locked)
	return e.finish(order, tie, lines)
}

func (e *Election) kemeny(field Field) Outcome {
	matrix := e.pairwise()
	var best, ways [1 << limit]int
	var heads [1 << limit]Field
	ways[0] = 1
	for subset := Field(1); subset <= field; subset++ {
		if subset &^ field != 0 {
			continue
		}
		best[subset] = -1
		list := subset.members()
		for _, a := range list {
			rest := subset &^ bit(a)
			score := best[rest]
			for _, b := range list {
				if a != b {
					score += matrix[a][b]
				}
			}
			if score > best[subset] {
				best[subset], ways[subset], heads[subset] = score, 0, 0
			}
			if score == best[subset] {
				ways[subset] += ways[rest]
				heads[subset] |= bit(a)
			}
		}
	}
	var order []int
	for remaining := field; remaining != 0; {
		for _, a := range e.tiebreak {
			if heads[remaining]&bit(a) != 0 {
				order = append(order, a)
				remaining &^= bit(a)
				break
			}
		}
	}
	return e.finish(order, heads[field].count() > 1, []string{
		fmt.Sprintf("score: %d", best[field]), fmt.Sprintf("optimal: %d", ways[field]), "ranking: " + e.namesText(order, " > "),
	})
}

type Parcel struct {
	value, owner int
}

func (e *Election) stv(field Field, seats int) Outcome {
	parcels := make([]Parcel, len(e.groups))
	for i, group := range e.groups {
		if len(effective(group.ranking, field)) > 0 {
			parcels[i].value = 100
		}
	}
	quota := e.tallies(field).nonblank*100/(seats+1) + 1
	lines := []string{"quota: " + money(quota)}
	continuing := field
	var elected []int
	var history []Row
	for {
		var scores Row
		exhausted := 0
		for i, group := range e.groups {
			parcel := &parcels[i]
			parcel.owner = -1
			if parcel.value == 0 {
				continue
			}
			for _, a := range group.ranking {
				if continuing&bit(a) != 0 {
					parcel.owner = a
					break
				}
			}
			value := group.votes * parcel.value
			if parcel.owner >= 0 {
				scores[parcel.owner] += value
			} else {
				exhausted += value
			}
		}
		history = append(history, scores)
		line := fmt.Sprintf("round %d: %s; exhausted %s", len(history), e.values(continuing, scores, true), money(exhausted))
		order := e.ordered(continuing, scores, true)
		if len(order) == seats-len(elected) {
			line += "; elected " + e.namesText(order, ", ")
			elected = append(elected, order...)
			lines = append(lines, line)
			break
		}
		a := order[0]
		if scores[a] >= quota {
			surplus := scores[a] - quota
			elected = append(elected, a)
			continuing &^= bit(a)
			for i := range parcels {
				if parcels[i].owner == a {
					parcels[i].value = parcels[i].value * surplus / scores[a]
				}
			}
			line += "; elected " + e.names[a] + " (surplus " + money(surplus) + ")"
			lines = append(lines, line)
			if len(elected) == seats {
				break
			}
		} else {
			excluded, tie := e.lookBack(continuing, history)
			continuing &^= bit(excluded)
			line += "; excluded " + e.names[excluded] + tieMark(tie)
			lines = append(lines, line)
		}
	}
	lines = append(lines, "elected: "+e.namesText(elected, ", "))
	return Outcome{lines: lines}
}

func (e *Election) tally(field Field, method Method) Outcome {
	switch method.kind {
	case Runoff:
		return e.runoff(field)
	case IRV, Coombs:
		return e.elimination(field, method.kind == Coombs, false)
	case Bucklin:
		return e.bucklin(field)
	case Baldwin, Nanson:
		return e.bordaElimination(field, method.kind == Nanson)
	case Condorcet:
		return e.condorcetReport(field)
	case Schulze:
		return e.schulze(field)
	case RankedPairs:
		return e.rankedPairs(field)
	case Kemeny:
		return e.kemeny(field)
	case STV:
		return e.stv(field, method.parameter)
	}
	base := e.tallies(field)
	var scores Row
	var lines []string
	label, descending := "scores", true
	condorcetWinner := -1
	switch method.kind {
	case Plurality:
		scores, label = base.first, "votes"
	case Borda, Black:
		scores = base.borda
		if method.kind == Black {
			condorcetWinner = e.condorcet(field, false)
			name := "NONE"
			if condorcetWinner >= 0 {
				name = e.names[condorcetWinner]
			}
			lines = append(lines, "condorcet: "+name)
		}
	case Veto:
		scores, label, descending = base.last, "vetoes", false
	case Approval:
		scores, label = base.approval[min(method.parameter, field.count())-1], "approvals"
	case Copeland:
		matrix := e.pairwise()
		var descriptions []string
		list := field.members()
		for _, a := range list {
			wins, draws, losses := 0, 0, 0
			for _, b := range list {
				if a == b {
					continue
				}
				switch cmp.Compare(matrix[a][b], matrix[b][a]) {
				case 1:
					wins++
				case 0:
					draws++
				case -1:
					losses++
				}
			}
			scores[a] = 2*wins + draws
			descriptions = append(descriptions, fmt.Sprintf("%s %d.%d (%d-%d-%d)", e.names[a], scores[a]/2, scores[a]%2*5, wins, draws, losses))
		}
		lines = append(lines, "scores: "+strings.Join(descriptions, ", "))
	case Minimax:
		matrix := e.pairwise()
		descending = false
		list := field.members()
		for _, a := range list {
			for _, b := range list {
				if a == b {
					continue
				}
				opposition, support, value := matrix[b][a], matrix[a][b], 0
				if method.minimax == Opposition || opposition > support {
					value = opposition
					if method.minimax == Margin {
						value -= support
					}
				}
				scores[a] = max(scores[a], value)
			}
		}
	default:
		panic("unreachable method")
	}
	order := e.ordered(field, scores, descending)
	tie := scores[order[0]] == scores[order[1]]
	if condorcetWinner >= 0 {
		index := slices.Index(order, condorcetWinner)
		copy(order[1:index+1], order[:index])
		order[0] = condorcetWinner
		tie = false
	}
	if method.kind != Copeland {
		lines = append(lines, label+": "+e.values(field, scores, false))
	}
	return e.finish(order, tie, lines)
}

func (e *Election) ballotsReport() []string {
	counts := make(map[string]int)
	for _, group := range e.groups {
		ranking := effective(group.ranking, e.active)
		notation := "-"
		if len(ranking) > 0 {
			notation = e.namesText(ranking, ">")
		}
		counts[notation] += group.votes
	}
	type distribution struct {
		notation string
		votes    int
	}
	groups := make([]distribution, 0, len(counts))
	for notation, votes := range counts {
		groups = append(groups, distribution{notation, votes})
	}
	slices.SortFunc(groups, func(a, b distribution) int {
		if comparison := cmp.Compare(b.votes, a.votes); comparison != 0 {
			return comparison
		}
		return strings.Compare(a.notation, b.notation)
	})
	lines := []string{fmt.Sprintf("total %d, blank %d, distinct %d", e.total, counts["-"], len(groups))}
	for _, group := range groups {
		lines = append(lines, fmt.Sprintf("%d %s", group.votes, group.notation))
	}
	return lines
}

type Lab struct {
	election *Election
	number   int
}

func (lab *Lab) execute(line string) ([]string, error) {
	words := strings.Split(line, " ")
	command := words[0]
	if command == "CANDIDATES" {
		names := words[1:]
		if len(names) == 1 {
			return nil, errors.New("too few candidates")
		}
		seen := make(map[string]bool)
		for _, name := range names {
			if seen[name] {
				return nil, fmt.Errorf("duplicate candidate %s", name)
			}
			seen[name] = true
		}
		lab.number++
		lab.election = newElection(lab.number, names)
		return []string{fmt.Sprintf("election %d: %d candidates", lab.number, len(names))}, nil
	}
	e := lab.election
	if e == nil {
		return nil, errors.New("no election")
	}
	switch command {
	case "BALLOT":
		var ranking []int
		if words[2] != "-" {
			var err error
			ranking, err = e.checkNames(strings.Split(words[2], ">"))
			if err != nil {
				return nil, err
			}
		}
		votes := number(words[1])
		e.groups = append(e.groups, Ballot{votes, ranking})
		e.total += votes
		e.finishEntry()
		return nil, nil
	case "RANDOM":
		count := number(words[1])
		state, _ := strconv.ParseInt(words[2], 10, 64)
		for range count {
			ranking := e.active.members()
			for i := len(ranking) - 1; i > 0; i-- {
				state = 48271 * state % 2147483647
				j := int(state % int64(i+1))
				ranking[i], ranking[j] = ranking[j], ranking[i]
			}
			state = 48271 * state % 2147483647
			ranking = ranking[:int(state%int64(len(ranking)))+1]
			e.groups = append(e.groups, Ballot{1, ranking})
		}
		e.total += count
		e.finishEntry()
		return nil, nil
	case "UNDO":
		if len(e.entryEnds) == 0 {
			return nil, errors.New("nothing to undo")
		}
		e.entryEnds = e.entryEnds[:len(e.entryEnds)-1]
		end := 0
		if len(e.entryEnds) > 0 {
			end = e.entryEnds[len(e.entryEnds)-1]
		}
		for _, group := range e.groups[end:] {
			e.total -= group.votes
		}
		clear(e.groups[end:])
		e.groups = e.groups[:end]
		e.invalidate()
		return nil, nil
	case "WITHDRAW", "RESTORE":
		a, err := e.candidate(words[1])
		if err != nil {
			return nil, err
		}
		active := e.active&bit(a) != 0
		if command == "WITHDRAW" {
			if !active {
				return nil, fmt.Errorf("already withdrawn %s", words[1])
			}
			if e.active.count() <= 2 {
				return nil, errors.New("too few candidates")
			}
			e.active &^= bit(a)
		} else {
			if active {
				return nil, fmt.Errorf("not withdrawn %s", words[1])
			}
			e.active |= bit(a)
		}
		return nil, nil
	case "TIEBREAK":
		order, err := e.checkNames(words[1:])
		if err != nil {
			return nil, err
		}
		if len(order) != len(e.names) {
			return nil, errors.New("incomplete tiebreak")
		}
		e.setTiebreak(order)
		return nil, nil
	case "STATUS":
		withdrawn := ((bit(len(e.names)) - 1) &^ e.active).members()
		names := "none"
		if len(withdrawn) > 0 {
			names = e.namesText(withdrawn, ", ")
		}
		return []string{"[" + line + "]", fmt.Sprintf("election %d", e.number),
			"active: " + e.namesText(e.active.members(), ", "), "withdrawn: " + names,
			"tiebreak: " + e.namesText(e.tiebreak, ", "), fmt.Sprintf("ballots: %d in %d entries", e.total, len(e.entryEnds))}, nil
	}
	if len(e.entryEnds) == 0 {
		return nil, errors.New("no ballots")
	}
	var requested Method
	if command == "RANKING" || command == "SPOILERS" {
		requested = parseMethod(words[1:])
		if !requested.rankable() {
			return nil, errors.New("not rankable")
		}
		if command == "SPOILERS" && e.active.count() < 3 {
			return nil, errors.New("too few candidates")
		}
	}
	var compared [2]int
	if command == "COMPARE" {
		for i := range 2 {
			a, err := e.candidate(words[i+1])
			if err != nil {
				return nil, err
			}
			if e.active&bit(a) == 0 {
				return nil, fmt.Errorf("withdrawn candidate %s", words[i+1])
			}
			compared[i] = a
		}
		if compared[0] == compared[1] {
			return nil, errors.New("same candidate")
		}
	}
	if command == "STV" && number(words[1]) >= e.active.count() {
		return nil, errors.New("too many seats")
	}
	lines := []string{"[" + line + "]"}
	switch command {
	case "RANKING", "SPOILERS":
		result := e.tally(e.active, requested)
		if command == "RANKING" {
			lines = append(lines, e.namesText(result.order, " > "))
		} else {
			win := result.order[0]
			lines = append(lines, "winner: "+e.names[win])
			for _, a := range e.active.members() {
				if a == win {
					continue
				}
				other := e.tally(e.active &^ bit(a), requested).order[0]
				mark := ""
				if other != win {
					mark = " (changed)"
				}
				lines = append(lines, "without "+e.names[a]+": "+e.names[other]+mark)
			}
		}
	case "BALLOTS":
		lines = append(lines, e.ballotsReport()...)
	case "PROFILE":
		scores := e.tallies(e.active)
		size := e.active.count()
		for _, a := range e.active.members() {
			counts := make([]string, size)
			previous := 0
			for j := range size {
				counts[j] = strconv.Itoa(scores.approval[j][a] - previous)
				previous = scores.approval[j][a]
			}
			lines = append(lines, fmt.Sprintf("%s: %s unranked %d", e.names[a], strings.Join(counts, " "), e.total-previous))
		}
	case "PAIRWISE":
		lines = append(lines, e.pairLines(e.active, e.pairwise())...)
	case "EXHAUSTED":
		lines = append(lines, e.elimination(e.active, false, true).lines...)
	case "SUMMARY", "COMPARE":
		var wins Row
		var ahead [2][]string
		for _, method := range summaryMethods {
			result := e.tally(e.active, method)
			if command == "SUMMARY" {
				win := result.order[0]
				wins[win]++
				lines = append(lines, fmt.Sprintf("%s: %s", method, e.names[win]))
			} else {
				side := 0
				if slices.Index(result.order, compared[0]) > slices.Index(result.order, compared[1]) {
					side = 1
				}
				ahead[side] = append(ahead[side], method.String())
			}
		}
		if command == "SUMMARY" {
			lines = append(lines, "wins: "+e.values(e.active, wins, false))
		} else {
			matrix := e.pairwise()
			a, b := compared[0], compared[1]
			lines = append(lines, fmt.Sprintf("%s %d, %s %d, neither %d", e.names[a], matrix[a][b], e.names[b], matrix[b][a], e.total-matrix[a][b]-matrix[b][a]))
			for i := range 2 {
				methods := "none"
				if len(ahead[i]) > 0 {
					methods = strings.Join(ahead[i], ", ")
				}
				lines = append(lines, e.names[compared[i]]+" ahead: "+methods)
			}
		}
	default:
		lines = append(lines, e.tally(e.active, parseMethod(words)).lines...)
	}
	return lines, nil
}

func main() {
	input := bufio.NewScanner(os.Stdin)
	if !input.Scan() {
		return
	}
	count := number(input.Text())
	output := bufio.NewWriter(os.Stdout)
	defer output.Flush()
	var lab Lab
	for range count {
		if !input.Scan() {
			break
		}
		lines, err := lab.execute(input.Text())
		if err != nil {
			fmt.Fprintln(output, "ERROR", err)
		} else {
			for _, line := range lines {
				fmt.Fprintln(output, line)
			}
		}
	}
}
