package main

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"slices"
	"strconv"
	"strings"
)

type MarketKind uint8

const (
	TwoSided MarketKind = iota
	Roommate
	Housing
)

type Side uint8

const (
	AnyAgent Side = iota
	Proposer
	Receiver
)

type Source string

const (
	GS Source = "GS"
	GSR Source = "GSR"
	BostonSource Source = "BOSTON"
	Egalitarian Source = "EGALITARIAN"
	MinRegret Source = "MINREGRET"
)

type Agent struct {
	Name string
	Preference []int
	Capacity int
}

type Matching []int

type SavedMatching struct {
	Source Source
	Partners Matching
}

type Market struct {
	Name string
	Kind MarketKind
	Agents []Agent
	Houses []string
	Proposers int
	Current *SavedMatching
}

type Run struct {
	Partners Matching
	Count int
	History []string
}

type Pair struct { Left, Right int }
type Rotation []Pair

type Candidate struct {
	Partners Matching
	Origin, Via int
	Cost, Regret int
}

type Lattice struct {
	Matchings []Candidate
	Rotations []Rotation
}

func integer(text string) int {
	value, _ := strconv.Atoi(text)
	return value
}

func emptyMatching(size int) Matching {
	result := make(Matching, size)
	for i := range result {
		result[i] = -1
	}
	return result
}

func listText(names []string) string {
	if len(names) == 0 {
		return "-"
	}
	return strings.Join(names, " ")
}

func (m *Market) Require(kind MarketKind) error {
	if m.Kind != kind {
		return fmt.Errorf("WRONG TYPE %s", m.Name)
	}
	return nil
}

func (m *Market) FindAgent(name string) int {
	for i, agent := range m.Agents {
		if agent.Name == name {
			return i
		}
	}
	return -1
}

func (m *Market) Agent(name string, side Side) (int, error) {
	index := m.FindAgent(name)
	if index < 0 {
		return -1, fmt.Errorf("UNKNOWN AGENT %s", name)
	}
	if side == Proposer && index >= m.Proposers {
		return -1, fmt.Errorf("NOT PROPOSER %s", name)
	}
	if side == Receiver && index < m.Proposers {
		return -1, fmt.Errorf("NOT RECEIVER %s", name)
	}
	return index, nil
}

func (m *Market) Rank(agent, partner int) int {
	preference := m.Agents[agent].Preference
	if index := slices.Index(preference, partner); index >= 0 {
		return index + 1
	}
	return len(preference) + 1
}

func (m *Market) Accepts(agent, partner int) bool {
	return slices.Contains(m.Agents[agent].Preference, partner)
}

func (m *Market) PartnerName(partner int) string {
	if partner < 0 {
		return "*"
	}
	return m.Agents[partner].Name
}

func (m *Market) Pairs(partners Matching) string {
	result := make([]string, m.Proposers)
	for p := range m.Proposers {
		result[p] = m.Agents[p].Name + "-" + m.PartnerName(partners[p])
	}
	return strings.Join(result, " ")
}

func (m *Market) Allocation(allocation Matching) string {
	result := make([]string, len(m.Agents))
	for a, house := range allocation {
		name := "*"
		if house >= 0 {
			name = m.Houses[house]
		}
		result[a] = m.Agents[a].Name + "-" + name
	}
	return strings.Join(result, " ")
}

func (m *Market) Effective(agent int) []int {
	preference := m.Agents[agent].Preference
	if own := slices.Index(preference, agent); own >= 0 {
		return slices.Clone(preference[:own + 1])
	}
	return append(slices.Clone(preference), agent)
}

func (m *Market) Deferred(reverse, verbose bool) Run {
	n := len(m.Agents)
	next, counts := make([]int, n), make([]int, n)
	holding := make([][]int, n)
	queued := make([]bool, n)
	queue := []int{}
	able := func(a int) bool {
		return counts[a] < m.Agents[a].Capacity && next[a] < len(m.Agents[a].Preference)
	}
	enqueue := func(a int) {
		if able(a) && !queued[a] {
			queue = append(queue, a)
			queued[a] = true
		}
	}
	begin, end := 0, m.Proposers
	if reverse {
		begin, end = m.Proposers, n
	}
	for a := begin; a < end; a++ {
		enqueue(a)
	}
	result := Run{Partners: emptyMatching(m.Proposers)}
	for head := 0; head < len(queue); head++ {
		x := queue[head]
		queued[x] = false
		y := m.Agents[x].Preference[next[x]]
		next[x]++
		result.Count++
		action := "REJECT"
		if m.Accepts(y, x) {
			if len(holding[y]) < m.Agents[y].Capacity {
				holding[y] = append(holding[y], x)
				counts[x]++
				action = "HOLD"
			} else {
				worst := 0
				for i := 1; i < len(holding[y]); i++ {
					if m.Rank(y, holding[y][i]) > m.Rank(y, holding[y][worst]) {
						worst = i
					}
				}
				rejected := holding[y][worst]
				if m.Rank(y, x) < m.Rank(y, rejected) {
					holding[y][worst] = x
					counts[rejected]--
					counts[x]++
					action = "HOLD REJECT " + m.Agents[rejected].Name
					enqueue(rejected)
				}
			}
		}
		if verbose {
			result.History = append(result.History, fmt.Sprintf("PROPOSE %s %s %s", m.Agents[x].Name, m.Agents[y].Name, action))
		}
		enqueue(x)
	}
	for y, held := range holding {
		for _, x := range held {
			if reverse {
				result.Partners[y] = x
			} else {
				result.Partners[x] = y
			}
		}
	}
	return result
}

func (m *Market) Boston() Run {
	result := Run{Partners: emptyMatching(m.Proposers)}
	remaining := make([]int, len(m.Agents))
	for r := m.Proposers; r < len(m.Agents); r++ {
		remaining[r] = m.Agents[r].Capacity
	}
	rounds := 0
	for p := range m.Proposers {
		rounds = max(rounds, len(m.Agents[p].Preference))
	}
	for round := range rounds {
		applications := emptyMatching(m.Proposers)
		for p := range m.Proposers {
			if result.Partners[p] < 0 && round < len(m.Agents[p].Preference) {
				applications[p] = m.Agents[p].Preference[round]
				result.Count++
			}
		}
		for r := m.Proposers; r < len(m.Agents); r++ {
			for _, p := range m.Agents[r].Preference {
				if remaining[r] > 0 && applications[p] == r {
					result.Partners[p] = r
					remaining[r]--
				}
			}
		}
	}
	return result
}

func (m *Market) Rotations(partners Matching) []Rotation {
	owners, successors := emptyMatching(len(m.Agents)), emptyMatching(m.Proposers)
	for p, r := range partners {
		if r >= 0 {
			owners[r] = p
		}
	}
	for p, partner := range partners {
		if partner < 0 {
			continue
		}
		for _, r := range m.Agents[p].Preference[m.Rank(p, partner):] {
			if m.Accepts(r, p) && (owners[r] < 0 || m.Rank(r, p) < m.Rank(r, owners[r])) {
				successors[p] = owners[r]
				break
			}
		}
	}
	var result []Rotation
	covered := make([]bool, m.Proposers)
	for start := range m.Proposers {
		if covered[start] {
			continue
		}
		seen := make([]bool, m.Proposers)
		var path []int
		p := start
		for p >= 0 && !seen[p] {
			seen[p] = true
			path = append(path, p)
			p = successors[p]
		}
		if p == start {
			rotation := make(Rotation, len(path))
			for i, a := range path {
				rotation[i] = Pair{a, partners[a]}
				covered[a] = true
			}
			result = append(result, rotation)
		}
	}
	return result
}

func (m *Market) Candidate(partners Matching, origin, via int) Candidate {
	result := Candidate{Partners: partners, Origin: origin, Via: via}
	for p, r := range partners {
		if r < 0 {
			continue
		}
		a, b := m.Rank(p, r), m.Rank(r, p)
		result.Cost += a + b
		result.Regret = max(result.Regret, a, b)
	}
	return result
}

func (m *Market) Enumerate() (Lattice, error) {
	for r := m.Proposers; r < len(m.Agents); r++ {
		if m.Agents[r].Capacity != 1 {
			return Lattice{}, errors.New("NOT ONE TO ONE")
		}
	}
	result := Lattice{Matchings: []Candidate{m.Candidate(m.Deferred(false, false).Partners, 0, 0)}}
	for index := 0; index < len(result.Matchings); index++ {
		partners := result.Matchings[index].Partners
		for _, rotation := range m.Rotations(partners) {
			number := slices.IndexFunc(result.Rotations, func(old Rotation) bool { return slices.Equal(old, rotation) })
			if number < 0 {
				number = len(result.Rotations)
				result.Rotations = append(result.Rotations, rotation)
			}
			next := slices.Clone(partners)
			for i, pair := range rotation {
				next[pair.Left] = rotation[(i + 1) % len(rotation)].Right
			}
			if slices.ContainsFunc(result.Matchings, func(old Candidate) bool { return slices.Equal(old.Partners, next) }) {
				continue
			}
			if len(result.Matchings) == 50 {
				return Lattice{}, errors.New("TOO MANY MATCHINGS")
			}
			result.Matchings = append(result.Matchings, m.Candidate(next, index + 1, number + 1))
		}
	}
	return result, nil
}

func (m *Market) Check(words []string) ([]string, error) {
	if m.Kind == Housing {
		return nil, fmt.Errorf("WRONG TYPE %s", m.Name)
	}
	partners := emptyMatching(len(m.Agents))
	counts := make([]int, len(m.Agents))
	for _, word := range words[2:] {
		left, right, _ := strings.Cut(word, "-")
		leftSide, rightSide := AnyAgent, AnyAgent
		if m.Kind == TwoSided {
			leftSide, rightSide = Proposer, Receiver
		}
		x, err := m.Agent(left, leftSide)
		if err != nil {
			return nil, err
		}
		y, err := m.Agent(right, rightSide)
		if err != nil {
			return nil, err
		}
		if partners[x] >= 0 {
			return nil, fmt.Errorf("DUPLICATE AGENT %s", left)
		}
		if m.Kind == TwoSided {
			counts[y]++
			if counts[y] > m.Agents[y].Capacity {
				return nil, fmt.Errorf("OVER CAPACITY %s", right)
			}
		} else {
			if x == y || partners[y] >= 0 {
				return nil, fmt.Errorf("DUPLICATE AGENT %s", right)
			}
			partners[y] = x
		}
		partners[x] = y
	}
	var unacceptable, blocking []Pair
	if m.Kind == TwoSided {
		for p := range m.Proposers {
			if r := partners[p]; r >= 0 && (!m.Accepts(p, r) || !m.Accepts(r, p)) {
				unacceptable = append(unacceptable, Pair{p, r})
			}
			for r := m.Proposers; r < len(m.Agents); r++ {
				if partners[p] == r || !m.Accepts(p, r) || !m.Accepts(r, p) || m.Rank(p, r) >= m.Rank(p, partners[p]) {
					continue
				}
				worst := 0
				for a := range m.Proposers {
					if partners[a] == r {
						worst = max(worst, m.Rank(r, a))
					}
				}
				if counts[r] < m.Agents[r].Capacity || m.Rank(r, p) < worst {
					blocking = append(blocking, Pair{p, r})
				}
			}
		}
	} else {
		for a := range m.Agents {
			for b := a + 1; b < len(m.Agents); b++ {
				mutual := m.Accepts(a, b) && m.Accepts(b, a)
				if partners[a] == b {
					if !mutual {
						unacceptable = append(unacceptable, Pair{a, b})
					}
				} else if mutual && m.Rank(a, b) < m.Rank(a, partners[a]) && m.Rank(b, a) < m.Rank(b, partners[b]) {
					blocking = append(blocking, Pair{a, b})
				}
			}
		}
	}
	if len(unacceptable) == 0 && len(blocking) == 0 {
		return []string{fmt.Sprintf("CHECK %s STABLE", m.Name)}, nil
	}
	output := []string{fmt.Sprintf("CHECK %s UNSTABLE unacceptable=%d blocking=%d", m.Name, len(unacceptable), len(blocking))}
	for _, group := range []struct { label string; pairs []Pair }{{"UNACCEPTABLE", unacceptable}, {"BLOCKING", blocking}} {
		for _, pair := range group.pairs {
			output = append(output, fmt.Sprintf("%s %s %s", group.label, m.Agents[pair.Left].Name, m.Agents[pair.Right].Name))
		}
	}
	return output, nil
}

func removePair(lists [][]int, a, b int) {
	lists[a] = slices.DeleteFunc(lists[a], func(x int) bool { return x == b })
	lists[b] = slices.DeleteFunc(lists[b], func(x int) bool { return x == a })
}

func firstEmpty(lists [][]int) int {
	return slices.IndexFunc(lists, func(list []int) bool { return len(list) == 0 })
}

func (m *Market) Table(lists [][]int) []string {
	output := make([]string, len(m.Agents))
	for a, list := range lists {
		names := make([]string, len(list))
		for i, b := range list {
			names[i] = m.Agents[b].Name
		}
		output[a] = fmt.Sprintf("TABLE %s %s", m.Agents[a].Name, listText(names))
	}
	return output
}

func (m *Market) Roommates(verbose bool) ([]string, error) {
	if err := m.Require(Roommate); err != nil {
		return nil, err
	}
	n := len(m.Agents)
	for _, agent := range m.Agents {
		if len(agent.Preference) < n - 1 {
			return nil, fmt.Errorf("INCOMPLETE %s", agent.Name)
		}
	}
	lists := make([][]int, n)
	held := emptyMatching(n)
	queue := make([]int, n)
	for a, agent := range m.Agents {
		lists[a] = slices.Clone(agent.Preference)
		queue[a] = a
	}
	proposals, failure := 0, -1
	for head := 0; head < len(queue); head++ {
		x := queue[head]
		y := lists[x][0]
		if held[y] >= 0 {
			queue = append(queue, held[y])
		}
		held[y] = x
		proposals++
		removed := slices.Clone(lists[y][slices.Index(lists[y], x) + 1:])
		for _, w := range removed {
			removePair(lists, y, w)
		}
		failure = firstEmpty(lists)
		if failure >= 0 {
			break
		}
	}
	var history []string
	rotations := 0
	if failure < 0 && verbose {
		history = append(history, m.Table(lists)...)
	}
	for failure < 0 {
		p := slices.IndexFunc(lists, func(list []int) bool { return len(list) >= 2 })
		if p < 0 {
			break
		}
		positions := emptyMatching(n)
		var path []int
		for positions[p] < 0 {
			positions[p] = len(path)
			path = append(path, p)
			q := lists[p][1]
			p = lists[q][len(lists[q]) - 1]
		}
		cycle := path[positions[p]:]
		front := make([]int, len(cycle))
		notation := make([]string, len(cycle))
		for i, x := range cycle {
			front[i] = lists[x][0]
			notation[i] = m.Agents[x].Name + "-" + m.Agents[front[i]].Name
		}
		rotations++
		history = append(history, fmt.Sprintf("ROTATION %d %s", rotations, strings.Join(notation, " ")))
		var removals []Pair
		for i, x := range cycle {
			u := front[(i + 1) % len(front)]
			for _, w := range lists[u][slices.Index(lists[u], x) + 1:] {
				removals = append(removals, Pair{u, w})
			}
		}
		for _, pair := range removals {
			removePair(lists, pair.Left, pair.Right)
		}
		if verbose {
			history = append(history, m.Table(lists)...)
		}
		failure = firstEmpty(lists)
	}
	output := append([]string{fmt.Sprintf("ROOMMATES %s proposals=%d", m.Name, proposals)}, history...)
	if failure >= 0 {
		output = append(output, "NO STABLE MATCHING " + m.Agents[failure].Name)
	} else {
		var pairs []string
		for a, list := range lists {
			if a < list[0] {
				pairs = append(pairs, m.Agents[a].Name + "-" + m.Agents[list[0]].Name)
			}
		}
		output = append(output, "MATCHING " + strings.Join(pairs, " "))
	}
	return output, nil
}

func (m *Market) TTC() []string {
	n := len(m.Agents)
	remaining := make([]bool, n)
	effective := make([][]int, n)
	for a := range n {
		remaining[a] = true
		effective[a] = m.Effective(a)
	}
	allocation := emptyMatching(n)
	var history []string
	for {
		start := slices.Index(remaining, true)
		if start < 0 {
			break
		}
		points := make([]int, n)
		for a := range n {
			if remaining[a] {
				for _, house := range effective[a] {
					if remaining[house] {
						points[a] = house
						break
					}
				}
			}
		}
		seen := make([]bool, n)
		p := start
		for !seen[p] {
			seen[p] = true
			p = points[p]
		}
		first := p
		var cycle []string
		for {
			allocation[p] = points[p]
			remaining[p] = false
			cycle = append(cycle, m.Agents[p].Name + ":" + m.Houses[points[p]])
			p = points[p]
			if p == first {
				break
			}
		}
		history = append(history, fmt.Sprintf("CYCLE %d %s", len(history) + 1, strings.Join(cycle, " ")))
	}
	output := append([]string{fmt.Sprintf("TTC %s cycles=%d", m.Name, len(history))}, history...)
	return append(output, "ALLOCATION " + m.Allocation(allocation))
}

func (m *Market) Serial(words []string) ([]string, error) {
	var order []int
	for _, name := range words[2:] {
		a, err := m.Agent(name, AnyAgent)
		if err != nil {
			return nil, err
		}
		if slices.Contains(order, a) {
			return nil, fmt.Errorf("DUPLICATE AGENT %s", name)
		}
		order = append(order, a)
	}
	if len(order) != len(m.Agents) {
		return nil, errors.New("BAD ORDER")
	}
	taken := make([]bool, len(m.Agents))
	allocation := emptyMatching(len(m.Agents))
	assigned := 0
	for _, a := range order {
		for _, house := range m.Agents[a].Preference {
			if !taken[house] {
				allocation[a] = house
				taken[house] = true
				assigned++
				break
			}
		}
	}
	var worse []string
	for a, house := range allocation {
		if house < 0 || !slices.Contains(m.Effective(a), house) {
			worse = append(worse, m.Agents[a].Name)
		}
	}
	return []string{fmt.Sprintf("SERIAL %s assigned=%d", m.Name, assigned), "ALLOCATION " + m.Allocation(allocation), "WORSE " + listText(worse)}, nil
}

func (m *Market) HR() []string {
	a, h := m.Deferred(false, false).Partners, m.Deferred(true, false).Partners
	var unmatched []string
	rural := true
	for p := range m.Proposers {
		if a[p] < 0 {
			unmatched = append(unmatched, m.Agents[p].Name)
		}
		if (a[p] < 0) != (h[p] < 0) {
			rural = false
		}
	}
	output := []string{fmt.Sprintf("HR %s residents=%d hospitals=%d", m.Name, m.Proposers, len(m.Agents) - m.Proposers),
		"RESIDENT-OPTIMAL " + m.Pairs(a), "HOSPITAL-OPTIMAL " + m.Pairs(h), "UNMATCHED " + listText(unmatched)}
	for r := m.Proposers; r < len(m.Agents); r++ {
		resident, hospital, same := 0, 0, true
		for p := range m.Proposers {
			if a[p] == r {
				resident++
			}
			if h[p] == r {
				hospital++
			}
			if (a[p] == r) != (h[p] == r) {
				same = false
			}
		}
		label := "NO"
		if same {
			label = "YES"
		}
		output = append(output, fmt.Sprintf("HOSPITAL %s cap=%d resident=%d hospital=%d same=%s", m.Agents[r].Name, m.Agents[r].Capacity, resident, hospital, label))
		if resident != hospital || (resident < m.Agents[r].Capacity && !same) {
			rural = false
		}
	}
	verdict := "RURAL FAILS"
	if rural {
		verdict = "RURAL HOLDS"
	}
	return append(output, verdict)
}

func (m *Market) Manipulate(a int) []string {
	truth := m.Agents[a].Preference
	b0, g0 := m.Boston().Partners[a], m.Deferred(false, false).Partners[a]
	output := []string{fmt.Sprintf("MANIPULATE %s %s boston=%s gs=%s swaps=%d", m.Name, m.Agents[a].Name, m.PartnerName(b0), m.PartnerName(g0), max(0, len(truth) - 1))}
	for i := 0; i + 1 < len(truth); i++ {
		trial := *m
		trial.Agents = slices.Clone(m.Agents)
		trial.Agents[a].Preference = slices.Clone(truth)
		trial.Agents[a].Preference[i], trial.Agents[a].Preference[i + 1] = truth[i + 1], truth[i]
		b, g := trial.Boston().Partners[a], trial.Deferred(false, false).Partners[a]
		for _, result := range []struct { source string; partner, baseline int }{{"BOSTON", b, b0}, {"GS", g, g0}} {
			if m.Rank(a, result.partner) < m.Rank(a, result.baseline) {
				output = append(output, fmt.Sprintf("IMPROVE %s %d %s %s result=%s", result.source, i + 1,
					m.Agents[truth[i]].Name, m.Agents[truth[i + 1]].Name, m.PartnerName(result.partner)))
			}
		}
	}
	if len(output) == 1 {
		output = append(output, "NO IMPROVEMENT")
	}
	return output
}

func gcd(a, b int) int {
	for b != 0 {
		a, b = b, a % b
	}
	return a
}

func (m *Market) Stats() ([]string, error) {
	if m.Current == nil {
		return nil, errors.New("NO MATCHING")
	}
	var sum, first [2]int
	pairs := 0
	occupied := make([]bool, len(m.Agents))
	for p, r := range m.Current.Partners {
		if r < 0 {
			continue
		}
		pairs++
		occupied[r] = true
		for i, rank := range [2]int{m.Rank(p, r), m.Rank(r, p)} {
			sum[i] += rank
			if rank == 1 {
				first[i]++
			}
		}
	}
	unmatched := [2]int{m.Proposers - pairs, 0}
	for _, used := range occupied[m.Proposers:] {
		if !used {
			unmatched[1]++
		}
	}
	output := []string{fmt.Sprintf("STATS %s source=%s pairs=%d", m.Name, m.Current.Source, pairs)}
	for i, label := range [2]string{"PROPOSERS", "RECEIVERS"} {
		average, truncated := "-", "-"
		if pairs > 0 {
			divisor, cents := gcd(sum[i], pairs), 100 * sum[i] / pairs
			average = fmt.Sprintf("%d/%d", sum[i] / divisor, pairs / divisor)
			truncated = fmt.Sprintf("%d.%02d", cents / 100, cents % 100)
		}
		output = append(output, fmt.Sprintf("%s sum=%d average=%s truncated=%s first=%d unmatched=%d", label, sum[i], average, truncated, first[i], unmatched[i]))
	}
	return output, nil
}

func (m *Market) Show() []string {
	var header string
	switch m.Kind {
	case TwoSided:
		header = fmt.Sprintf("SHOW %s MARKET proposers=%d receivers=%d", m.Name, m.Proposers, len(m.Agents) - m.Proposers)
	case Roommate:
		header = fmt.Sprintf("SHOW %s ROOMS agents=%d", m.Name, len(m.Agents))
	case Housing:
		header = fmt.Sprintf("SHOW %s HOUSES agents=%d", m.Name, len(m.Agents))
	}
	output := []string{header}
	for a, agent := range m.Agents {
		var prefix string
		switch m.Kind {
		case TwoSided:
			if a < m.Proposers {
				prefix = "PROPOSER " + agent.Name
			} else {
				prefix = fmt.Sprintf("RECEIVER %s cap=%d", agent.Name, agent.Capacity)
			}
		case Roommate:
			prefix = "AGENT " + agent.Name
		case Housing:
			prefix = fmt.Sprintf("AGENT %s house=%s", agent.Name, m.Houses[a])
		}
		names := make([]string, len(agent.Preference))
		for i, b := range agent.Preference {
			if m.Kind == Housing {
				names[i] = m.Houses[b]
			} else {
				names[i] = m.Agents[b].Name
			}
		}
		output = append(output, prefix + " " + listText(names))
	}
	if m.Kind == TwoSided {
		source := Source("-")
		if m.Current != nil {
			source = m.Current.Source
		}
		output = append(output, "CURRENT " + string(source))
	}
	return output
}

func newMarket(words []string) (*Market, string, error) {
	op, name := words[0], words[1]
	market := &Market{Name: name, Kind: TwoSided}
	if op == "ROOMS" {
		market.Kind = Roommate
	} else if op == "HOUSES" {
		market.Kind = Housing
	}
	if op == "RANDOM" {
		n := integer(words[2])
		seed, _ := strconv.ParseInt(words[3], 10, 64)
		state := seed
		market.Proposers = n
		for a := range 2 * n {
			prefix, offset := "P", n
			if a >= n {
				prefix, offset = "R", 0
			}
			agent := Agent{Name: fmt.Sprintf("%s%d", prefix, a % n + 1), Capacity: 1, Preference: make([]int, n)}
			for i := range n {
				agent.Preference[i] = offset + i
			}
			for i := n; i > 1; i-- {
				state = 48271 * state % 2147483647
				j := int(state % int64(i))
				agent.Preference[i - 1], agent.Preference[j] = agent.Preference[j], agent.Preference[i - 1]
			}
			market.Agents = append(market.Agents, agent)
		}
		return market, fmt.Sprintf("RANDOM %s n=%d seed=%d", name, n, seed), nil
	}
	for _, word := range words[2:] {
		if word == "|" {
			market.Proposers = len(market.Agents)
			continue
		}
		agent, house := word, ""
		if market.Kind == Housing {
			agent, house, _ = strings.Cut(word, ":")
		}
		if market.FindAgent(agent) >= 0 {
			return nil, "", fmt.Errorf("DUPLICATE AGENT %s", agent)
		}
		if market.Kind == Housing {
			if slices.Contains(market.Houses, house) {
				return nil, "", fmt.Errorf("DUPLICATE HOUSE %s", house)
			}
			market.Houses = append(market.Houses, house)
		}
		market.Agents = append(market.Agents, Agent{Name: agent, Capacity: 1})
	}
	if market.Kind == TwoSided {
		return market, fmt.Sprintf("MARKET %s proposers=%d receivers=%d", name, market.Proposers, len(market.Agents) - market.Proposers), nil
	}
	return market, fmt.Sprintf("%s %s agents=%d", op, name, len(market.Agents)), nil
}

type Lab struct { Markets map[string]*Market }

func (lab *Lab) Execute(words []string) ([]string, error) {
	op, name := words[0], words[1]
	if op == "MARKET" || op == "ROOMS" || op == "HOUSES" || op == "RANDOM" {
		if _, exists := lab.Markets[name]; exists {
			return nil, fmt.Errorf("DUPLICATE MARKET %s", name)
		}
		market, output, err := newMarket(words)
		if err != nil {
			return nil, err
		}
		lab.Markets[name] = market
		return []string{output}, nil
	}
	market, exists := lab.Markets[name]
	if !exists {
		return nil, fmt.Errorf("UNKNOWN MARKET %s", name)
	}
	switch op {
	case "SHOW":
		return market.Show(), nil
	case "PREF":
		a, err := market.Agent(words[2], AnyAgent)
		if err != nil {
			return nil, err
		}
		var preference []int
		for _, word := range words[3:] {
			b := market.FindAgent(word)
			if market.Kind == Housing {
				b = slices.Index(market.Houses, word)
			}
			if b < 0 || (market.Kind == TwoSided && (a < market.Proposers) == (b < market.Proposers)) || (market.Kind == Roommate && a == b) {
				return nil, fmt.Errorf("BAD CHOICE %s", word)
			}
			if slices.Contains(preference, b) {
				return nil, fmt.Errorf("DUPLICATE CHOICE %s", word)
			}
			preference = append(preference, b)
		}
		market.Agents[a].Preference = preference
		if market.Kind == TwoSided {
			market.Current = nil
		}
		return []string{fmt.Sprintf("PREF %s %s length=%d", name, words[2], len(preference))}, nil
	case "CHECK":
		return market.Check(words)
	case "ROOMMATES":
		return market.Roommates(len(words) == 3)
	case "TTC", "SERIAL":
		if err := market.Require(Housing); err != nil {
			return nil, err
		}
		if op == "TTC" {
			return market.TTC(), nil
		}
		return market.Serial(words)
	}
	if err := market.Require(TwoSided); err != nil {
		return nil, err
	}
	switch op {
	case "CAPACITY":
		r, err := market.Agent(words[2], Receiver)
		if err != nil {
			return nil, err
		}
		capacity := integer(words[3])
		market.Agents[r].Capacity = capacity
		market.Current = nil
		return []string{fmt.Sprintf("CAPACITY %s %s %d", name, words[2], capacity)}, nil
	case "GS", "GSR", "BOSTON":
		var result Run
		label := "proposals"
		if op == "BOSTON" {
			result = market.Boston()
			label = "applications"
		} else {
			result = market.Deferred(op == "GSR", len(words) == 3)
		}
		market.Current = &SavedMatching{Source(op), result.Partners}
		output := append([]string{fmt.Sprintf("%s %s %s=%d", op, name, label, result.Count)}, result.History...)
		return append(output, "MATCHING " + market.Pairs(result.Partners)), nil
	case "HR":
		return market.HR(), nil
	case "MANIPULATE":
		a, err := market.Agent(words[2], Proposer)
		if err != nil {
			return nil, err
		}
		return market.Manipulate(a), nil
	case "STATS":
		return market.Stats()
	case "LATTICE", "EGALITARIAN", "MINREGRET":
		lattice, err := market.Enumerate()
		if err != nil {
			return nil, err
		}
		if op == "LATTICE" {
			output := []string{fmt.Sprintf("LATTICE %s matchings=%d rotations=%d", name, len(lattice.Matchings), len(lattice.Rotations))}
			for i, candidate := range lattice.Matchings {
				origin, via := "-", "-"
				if candidate.Origin > 0 {
					origin, via = strconv.Itoa(candidate.Origin), strconv.Itoa(candidate.Via)
				}
				output = append(output, fmt.Sprintf("MATCHING %d from=%s via=%s cost=%d regret=%d %s", i + 1,
					origin, via, candidate.Cost, candidate.Regret, market.Pairs(candidate.Partners)))
			}
			for i, rotation := range lattice.Rotations {
				notation := make([]string, len(rotation))
				for j, pair := range rotation {
					notation[j] = market.Agents[pair.Left].Name + "-" + market.Agents[pair.Right].Name
				}
				output = append(output, fmt.Sprintf("ROTATION %d %s", i + 1, strings.Join(notation, " ")))
			}
			return output, nil
		}
		best, value := 0, 0
		for i, candidate := range lattice.Matchings {
			metric := candidate.Regret
			if op == "EGALITARIAN" {
				metric = candidate.Cost
			}
			if i == 0 || metric < value {
				best, value = i, metric
			}
		}
		selected := lattice.Matchings[best].Partners
		market.Current = &SavedMatching{Source(op), selected}
		label := "regret"
		if op == "EGALITARIAN" {
			label = "cost"
		}
		return []string{fmt.Sprintf("%s %s matching=%d %s=%d", op, name, best + 1, label, value), "MATCHING " + market.Pairs(selected)}, nil
	}
	panic("unknown command in well-formed input")
}

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	if !scanner.Scan() {
		return
	}
	count := integer(scanner.Text())
	lab := Lab{Markets: make(map[string]*Market)}
	writer := bufio.NewWriter(os.Stdout)
	defer writer.Flush()
	for i := 0; i < count && scanner.Scan(); i++ {
		output, err := lab.Execute(strings.Split(scanner.Text(), " "))
		if err != nil {
			fmt.Fprintln(writer, "ERROR " + err.Error())
		} else {
			for _, line := range output {
				fmt.Fprintln(writer, line)
			}
		}
	}
}
