package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

const noNet = 1 << 30

func number(s string) int {
	n, _ := strconv.Atoi(s)
	return n
}

func total(values []int) int {
	n := 0
	for _, value := range values {
		n += value
	}
	return n
}

func floorDiv(n, d int) int {
	if n >= 0 {
		return n / d
	}
	return -((-n + d - 1) / d)
}

func halfUp(n, d int) int {
	return floorDiv(2*n+d, 2*d)
}

func halfAway(n, d int) int {
	if n < 0 {
		return -halfUp(-n, d)
	}
	return halfUp(n, d)
}

func decimal(n int, negative string) string {
	if n < 0 {
		return negative + fmt.Sprintf("%d.%d", -n/10, -n%10)
	}
	return fmt.Sprintf("%d.%d", n/10, n%10)
}

func indexText(n *int) string {
	if n == nil {
		return "none"
	}
	return decimal(*n, "+")
}

func handicapText(n *int) string {
	if n == nil {
		return "none"
	}
	if *n < 0 {
		return fmt.Sprint("+", -*n)
	}
	return strconv.Itoa(*n)
}

func average(total, count int) string {
	if count == 0 {
		return "-"
	}
	hundredths := total * 100 / count
	return fmt.Sprintf("%d.%02d", hundredths/100, hundredths%100)
}

func pointer(n int) *int {
	return &n
}

func strokes(handicap int, si []int) []int {
	absolute := handicap
	if absolute < 0 {
		absolute = -absolute
	}
	q, r := absolute/18, absolute%18
	result := make([]int, len(si))
	for hole, rank := range si {
		if handicap >= 0 {
			result[hole] = q
			if rank <= r {
				result[hole]++
			}
		} else {
			result[hole] = -q
			if rank >= 19-r {
				result[hole]--
			}
		}
	}
	return result
}

func countback(values []int) [5]int {
	return [5]int{
		total(values),
		total(values[9:]),
		total(values[12:]),
		total(values[15:]),
		values[17],
	}
}

func ranked(indices []int, values [][]int, ids []string, larger bool) []int {
	result := append([]int(nil), indices...)
	sort.Slice(result, func(i, j int) bool {
		left, right := countback(values[result[i]]), countback(values[result[j]])
		for k := range left {
			if left[k] != right[k] {
				if larger {
					return left[k] > right[k]
				}
				return left[k] < right[k]
			}
		}
		return ids[result[i]] < ids[result[j]]
	})
	return result
}

func matchStatus(lead int) string {
	if lead == 0 {
		return "AS"
	}
	if lead > 0 {
		return fmt.Sprintf("%d UP", lead)
	}
	return fmt.Sprintf("%d DN", -lead)
}

type Tee struct {
	ID            string
	Rating, Slope int
}

type Course struct {
	ID       string
	Pars, SI []int
	Par      int
	Tees     map[string]*Tee
}

func (t *Tee) handicap(index int, course *Course) int {
	return halfUp(index*t.Slope+113*(t.Rating-10*course.Par), 1130)
}

type IndexRecord struct {
	Day, Value int
}

type Calculation struct {
	K, Average, Adjustment int
	Low                    *int
	Hard, Soft, Maximum    bool
}

type Player struct {
	ID, Name    string
	Index       *int
	Rounds      []*Round
	Records     []IndexRecord
	Calculation *Calculation
}

func (p *Player) lowIndex(day int) (IndexRecord, bool) {
	var result IndexRecord
	found := false
	for _, record := range p.Records {
		if record.Day < day-365 || record.Day >= day {
			continue
		}
		if !found || record.Value < result.Value || (record.Value == result.Value && record.Day < result.Day) {
			result = record
			found = true
		}
	}
	return result, found
}

type Eligible struct {
	Number, Adjusted int
	Round            *Round
}

func (p *Player) eligible() []Eligible {
	first := len(p.Rounds) - 20
	if first < 0 {
		first = 0
	}
	rows := make([]Eligible, 0, len(p.Rounds)-first)
	reduction := 0
	for i := len(p.Rounds) - 1; i >= first; i-- {
		record := p.Rounds[i]
		reduction += record.Exceptional
		rows = append(rows, Eligible{i + 1, record.Differential - reduction, record})
	}
	for i, j := 0, len(rows)-1; i < j; i, j = i+1, j-1 {
		rows[i], rows[j] = rows[j], rows[i]
	}
	return rows
}

func counting(rows []Eligible) ([]Eligible, int) {
	n := len(rows)
	if n < 3 {
		return nil, 0
	}
	k := 1
	switch {
	case n <= 5:
		k = 1
	case n <= 8:
		k = 2
	case n <= 11:
		k = 3
	case n <= 14:
		k = 4
	case n <= 16:
		k = 5
	case n <= 18:
		k = 6
	case n == 19:
		k = 7
	default:
		k = 8
	}
	adjustment := 0
	if n == 3 {
		adjustment = -20
	} else if n == 4 || n == 6 {
		adjustment = -10
	}
	ordered := append([]Eligible(nil), rows...)
	sort.Slice(ordered, func(i, j int) bool {
		if ordered[i].Adjusted != ordered[j].Adjusted {
			return ordered[i].Adjusted < ordered[j].Adjusted
		}
		return ordered[i].Number > ordered[j].Number
	})
	return ordered[:k], adjustment
}

func (p *Player) updateIndex(day int) {
	selected, adjustment := counting(p.eligible())
	if len(selected) == 0 {
		p.Calculation = nil
		return
	}
	sum := 0
	for _, row := range selected {
		sum += row.Adjusted
	}
	avg := halfAway(sum, len(selected))
	candidate := avg + adjustment
	lowRecord, hasLow := p.lowIndex(day)
	var low *int
	soft, hard, maximum := false, false, false
	if hasLow {
		low = pointer(lowRecord.Value)
		if candidate-*low > 30 {
			candidate = *low + 30 + (candidate-*low-30)/2
			soft = true
		}
		if candidate-*low > 50 {
			candidate = *low + 50
			hard = true
		}
	}
	if candidate > 540 {
		candidate = 540
		maximum = true
	}
	p.Index = pointer(candidate)
	p.Calculation = &Calculation{len(selected), avg, adjustment, low, hard, soft, maximum}
}

type Round struct {
	Course                *Course
	Tee                   *Tee
	Day                   int
	Scores, Adjusted      []int
	Handicap, Previous    *int
	PreviousRecords       int
	PreviousCalculation   *Calculation
	AGS, Differential     int
	Exceptional           int
}

func newRound(p *Player, course *Course, tee *Tee, day int, scores []int) *Round {
	r := &Round{
		Course: course, Tee: tee, Day: day, Scores: scores,
		Previous: p.Index, PreviousRecords: len(p.Records),
		PreviousCalculation: p.Calculation,
	}
	if p.Index != nil {
		r.Handicap = pointer(tee.handicap(*p.Index, course))
	}
	hcp := 0
	if r.Handicap != nil {
		hcp = *r.Handicap
	}
	allocation := strokes(hcp, course.SI)
	r.Adjusted = make([]int, 18)
	for hole, score := range scores {
		par, stroke := course.Pars[hole], allocation[hole]
		limit := par + 5
		if r.Handicap != nil {
			limit = par + 2 + stroke
		}
		switch {
		case score == 0:
			r.Adjusted[hole] = par + stroke
		case score < 0:
			r.Adjusted[hole] = limit
		case score > limit:
			r.Adjusted[hole] = limit
		default:
			r.Adjusted[hole] = score
		}
	}
	r.AGS = total(r.Adjusted)
	r.Differential = halfAway(113*(10*r.AGS-tee.Rating), tee.Slope)
	if p.Index != nil && *p.Index-r.Differential >= 70 {
		r.Exceptional = 10
		if *p.Index-r.Differential >= 100 {
			r.Exceptional = 20
		}
	}
	return r
}

func (r *Round) complete() bool {
	for _, score := range r.Scores {
		if score <= 0 {
			return false
		}
	}
	return true
}

func (r *Round) nets(allocation []int) []int {
	result := make([]int, 18)
	for hole, score := range r.Scores {
		if score <= 0 {
			result[hole] = noNet
		} else {
			result[hole] = score - allocation[hole]
		}
	}
	return result
}

func (r *Round) points(nets []int) []int {
	result := make([]int, 18)
	for hole, net := range nets {
		if net == noNet {
			continue
		}
		value := r.Course.Pars[hole] + 2 - net
		if value > 0 {
			result[hole] = value
		}
	}
	return result
}

type Event struct {
	ID, Format   string
	Course       *Course
	Tee          *Tee
	Day, Allowance int
	Players      []*Player
}

type EventData struct {
	Rounds    []*Round
	Handicaps []int
	Nets      [][]int
	Points    [][]int
}

type Golf struct {
	Courses    map[string]*Course
	Players    map[string]*Player
	Events     map[string]*Event
	EventOrder []*Event
	Output     []string
}

func newGolf() *Golf {
	return &Golf{
		Courses: make(map[string]*Course),
		Players: make(map[string]*Player),
		Events: make(map[string]*Event),
	}
}

func (g *Golf) emit(parts ...interface{}) {
	fields := make([]string, len(parts))
	for i, part := range parts {
		fields[i] = fmt.Sprint(part)
	}
	g.Output = append(g.Output, strings.Join(fields, " "))
}

func (g *Golf) player(id string) (*Player, string) {
	p := g.Players[id]
	if p == nil {
		return nil, "unknown player"
	}
	return p, ""
}

func (g *Golf) course(id string) (*Course, string) {
	c := g.Courses[id]
	if c == nil {
		return nil, "unknown course"
	}
	return c, ""
}

func (g *Golf) tee(courseID, teeID string) (*Course, *Tee, string) {
	c, err := g.course(courseID)
	if err != "" {
		return nil, nil, err
	}
	t := c.Tees[teeID]
	if t == nil {
		return nil, nil, "unknown tee"
	}
	return c, t, ""
}

func (g *Golf) eventData(event *Event) (*EventData, string) {
	d := &EventData{
		Rounds: make([]*Round, len(event.Players)),
		Handicaps: make([]int, len(event.Players)),
		Nets: make([][]int, len(event.Players)),
		Points: make([][]int, len(event.Players)),
	}
	for i, p := range event.Players {
		var found *Round
		for _, r := range p.Rounds {
			if r.Course == event.Course && r.Tee == event.Tee && r.Day == event.Day {
				found = r
				break
			}
		}
		if found == nil {
			return nil, "missing round"
		}
		if found.Handicap == nil {
			return nil, "no index"
		}
		d.Rounds[i] = found
		d.Handicaps[i] = halfUp(*found.Handicap*event.Allowance, 100)
	}
	minimum := 0
	if event.Format == "MATCH" || event.Format == "NASSAU" || event.Format == "FOURBALL" {
		minimum = d.Handicaps[0]
		for _, hcp := range d.Handicaps[1:] {
			if hcp < minimum {
				minimum = hcp
			}
		}
	}
	for i, r := range d.Rounds {
		d.Nets[i] = r.nets(strokes(d.Handicaps[i]-minimum, event.Course.SI))
		d.Points[i] = r.points(d.Nets[i])
	}
	return d, ""
}

func (g *Golf) individualRanking(event *Event, data *EventData) ([]int, [][]int) {
	n := len(event.Players)
	ids := make([]string, n)
	positions := make([]int, 0, n)
	values := make([][]int, n)
	for i, p := range event.Players {
		ids[i] = p.ID
		if event.Format == "STROKE" {
			if data.Rounds[i].complete() {
				positions = append(positions, i)
			}
			values[i] = data.Nets[i]
		} else if event.Format == "STABLEFORD" {
			positions = append(positions, i)
			values[i] = data.Points[i]
		} else {
			positions = append(positions, i)
			values[i] = make([]int, 18)
			for hole, net := range data.Nets[i] {
				if net == noNet || net > event.Course.Pars[hole] {
					values[i][hole] = -1
				} else if net < event.Course.Pars[hole] {
					values[i][hole] = 1
				}
			}
		}
	}
	return ranked(positions, values, ids, event.Format != "STROKE"), values
}

func (g *Golf) individualResults(event *Event, data *EventData) {
	order, values := g.individualRanking(event, data)
	for rank, i := range order {
		p := event.Players[i]
		hcp := handicapText(pointer(data.Handicaps[i]))
		switch event.Format {
		case "STROKE":
			g.emit(rank+1, p.ID, "net", total(data.Nets[i]), "gross", total(data.Rounds[i].Scores), "hcp", hcp)
		case "STABLEFORD":
			g.emit(rank+1, p.ID, "points", total(data.Points[i]), "hcp", hcp)
		case "PAR":
			g.emit(rank+1, p.ID, matchStatus(total(values[i])), "hcp", hcp)
		}
	}
	if event.Format != "STROKE" {
		return
	}
	nonreturns := make([]int, 0)
	for i, r := range data.Rounds {
		if !r.complete() {
			nonreturns = append(nonreturns, i)
		}
	}
	sort.Slice(nonreturns, func(i, j int) bool {
		return event.Players[nonreturns[i]].ID < event.Players[nonreturns[j]].ID
	})
	for _, i := range nonreturns {
		g.emit("NR", event.Players[i].ID, "hcp", handicapText(pointer(data.Handicaps[i])))
	}
	if len(order) > 0 {
		gross := make([][]int, len(event.Players))
		ids := make([]string, len(event.Players))
		for i, p := range event.Players {
			ids[i] = p.ID
			if data.Rounds[i].complete() {
				gross[i] = data.Rounds[i].Scores
			}
		}
		winner := ranked(order, gross, ids, false)[0]
		g.emit("gross", event.Players[winner].ID, total(gross[winner]))
	}
}

func (g *Golf) matchHoles(event *Event, data *EventData) ([2]string, []int) {
	var sides [2][]int
	if event.Format == "FOURBALL" {
		sides[0], sides[1] = []int{0, 1}, []int{2, 3}
	} else {
		sides[0], sides[1] = []int{0}, []int{1}
	}
	var names [2]string
	for side := range sides {
		ids := make([]string, len(sides[side]))
		for i, index := range sides[side] {
			ids[i] = event.Players[index].ID
		}
		names[side] = strings.Join(ids, "+")
	}
	holes := make([]int, 18)
	for h := range holes {
		var scores [2]int
		for side := range sides {
			scores[side] = noNet
			for _, index := range sides[side] {
				net := data.Nets[index][h]
				if net < scores[side] {
					scores[side] = net
				}
			}
		}
		if scores[0] == scores[1] {
			holes[h] = 0
		} else if scores[0] < scores[1] {
			holes[h] = 1
		} else {
			holes[h] = -1
		}
	}
	return names, holes
}

func playMatch(names [2]string, holes []int, first, last int) ([]string, string) {
	lead := 0
	statuses := []string{}
	remaining := 0
	for hole := first; hole < last; hole++ {
		lead += holes[hole]
		statuses = append(statuses, matchStatus(lead))
		remaining = last - hole - 1
		if abs(lead) > remaining || remaining == 0 {
			break
		}
	}
	if lead == 0 {
		return statuses, "AS"
	}
	winner := names[0]
	if lead < 0 {
		winner = names[1]
	}
	if remaining > 0 {
		return statuses, fmt.Sprintf("%s %d&%d", winner, abs(lead), remaining)
	}
	return statuses, fmt.Sprintf("%s %d UP", winner, abs(lead))
}

func abs(n int) int {
	if n < 0 {
		return -n
	}
	return n
}

func (g *Golf) matchResults(event *Event, data *EventData) {
	minimum := data.Handicaps[0]
	for _, hcp := range data.Handicaps {
		if hcp < minimum {
			minimum = hcp
		}
	}
	parts := []interface{}{"strokes"}
	for i, p := range event.Players {
		parts = append(parts, p.ID, data.Handicaps[i]-minimum)
	}
	g.emit(parts...)
	names, holes := g.matchHoles(event, data)
	if event.Format == "NASSAU" {
		for _, section := range []struct {
			Name string
			First, Last int
		}{{"front", 0, 9}, {"back", 9, 18}, {"total", 0, 18}} {
			_, result := playMatch(names, holes, section.First, section.Last)
			g.emit(section.Name, result)
		}
	} else {
		statuses, result := playMatch(names, holes, 0, 18)
		g.emit("status", strings.Join(statuses, ", "))
		g.emit("result", result)
	}
}

func (g *Golf) betterballResults(event *Event, data *EventData) {
	type Team struct {
		First, Second int
		Values        []int
	}
	teams := []Team{}
	for i := 0; i < len(event.Players); i += 2 {
		values := make([]int, 18)
		for hole := range values {
			values[hole] = data.Points[i][hole]
			if data.Points[i+1][hole] > values[hole] {
				values[hole] = data.Points[i+1][hole]
			}
		}
		teams = append(teams, Team{i, i + 1, values})
	}
	ids := make([]string, len(teams))
	values := make([][]int, len(teams))
	positions := make([]int, len(teams))
	for i, team := range teams {
		ids[i], values[i], positions[i] = event.Players[team.First].ID, team.Values, i
	}
	for rank, index := range ranked(positions, values, ids, true) {
		team := teams[index]
		g.emit(rank+1, event.Players[team.First].ID+"+"+event.Players[team.Second].ID,
			"points", total(team.Values), "hcp",
			handicapText(pointer(data.Handicaps[team.First])),
			handicapText(pointer(data.Handicaps[team.Second])))
	}
}

func (g *Golf) skinsResults(event *Event, data *EventData) {
	totals := make([]int, len(event.Players))
	carry := 0
	var lastWinners []int
	for hole := 0; hole < 18; hole++ {
		carry++
		best := noNet
		winners := []int{}
		for i, nets := range data.Nets {
			if nets[hole] == noNet {
				continue
			}
			if nets[hole] < best {
				best, winners = nets[hole], []int{i}
			} else if nets[hole] == best {
				winners = append(winners, i)
			}
		}
		lastWinners = winners
		if len(winners) == 1 {
			g.emit("hole", hole+1, event.Players[winners[0]].ID, carry)
			totals[winners[0]] += 100 * carry
			carry = 0
		}
	}
	if carry > 0 {
		sharing := lastWinners
		if len(sharing) == 0 {
			sharing = make([]int, len(event.Players))
			for i := range sharing {
				sharing[i] = i
			}
		}
		sort.Slice(sharing, func(i, j int) bool {
			return event.Players[sharing[i]].ID < event.Players[sharing[j]].ID
		})
		parts := []interface{}{"carry", carry}
		for _, i := range sharing {
			totals[i] += carry * 100 / len(sharing)
			parts = append(parts, event.Players[i].ID)
		}
		g.emit(parts...)
	}
	positions := make([]int, len(event.Players))
	for i := range positions {
		positions[i] = i
	}
	sort.Slice(positions, func(i, j int) bool {
		a, b := positions[i], positions[j]
		if totals[a] != totals[b] {
			return totals[a] > totals[b]
		}
		return event.Players[a].ID < event.Players[b].ID
	})
	for _, i := range positions {
		g.emit(event.Players[i].ID, fmt.Sprintf("%d.%02d", totals[i]/100, totals[i]%100))
	}
}

func (g *Golf) results(event *Event, data *EventData) {
	g.emit("results", event.ID+":", event.Format, event.Course.ID, event.Tee.ID,
		"day", event.Day, "allowance", event.Allowance)
	switch event.Format {
	case "STROKE", "STABLEFORD", "PAR":
		g.individualResults(event, data)
	case "MATCH", "NASSAU", "FOURBALL":
		g.matchResults(event, data)
	case "BETTERBALL":
		g.betterballResults(event, data)
	case "SKINS":
		g.skinsResults(event, data)
	}
}

func (g *Golf) merit() {
	type Standing struct {
		ID                       string
		Points, Wins, Appearances int
	}
	standings := make(map[string]*Standing)
	counted := 0
	awards := []int{10, 8, 6, 5, 4, 3, 2, 1}
	for _, event := range g.EventOrder {
		if event.Format != "STROKE" && event.Format != "STABLEFORD" && event.Format != "PAR" {
			continue
		}
		data, err := g.eventData(event)
		if err != "" {
			continue
		}
		counted++
		order, _ := g.individualRanking(event, data)
		for _, p := range event.Players {
			if standings[p.ID] == nil {
				standings[p.ID] = &Standing{ID: p.ID}
			}
			standings[p.ID].Appearances++
		}
		for rank, i := range order {
			standing := standings[event.Players[i].ID]
			standing.Points += awards[rank]
			if rank == 0 {
				standing.Wins++
			}
		}
	}
	g.emit("merit:", "events", counted)
	sorted := make([]*Standing, 0, len(standings))
	for _, entry := range standings {
		sorted = append(sorted, entry)
	}
	sort.Slice(sorted, func(i, j int) bool {
		a, b := sorted[i], sorted[j]
		if a.Points != b.Points {
			return a.Points > b.Points
		}
		if a.Wins != b.Wins {
			return a.Wins > b.Wins
		}
		return a.ID < b.ID
	})
	for rank, entry := range sorted {
		g.emit(rank+1, entry.ID, entry.Points, "wins", entry.Wins, "played", entry.Appearances)
	}
}

func (g *Golf) cardTotal(label string, r *Round, allocation, nets, points []int, first, last int) {
	complete, scores, netTotal := true, 0, 0
	for hole := first; hole < last; hole++ {
		if r.Scores[hole] <= 0 {
			complete = false
		} else {
			scores += r.Scores[hole]
			netTotal += nets[hole]
		}
	}
	scoreText, netText := "-", "-"
	if complete {
		scoreText, netText = strconv.Itoa(scores), strconv.Itoa(netTotal)
	}
	g.emit(label, total(r.Course.Pars[first:last]), scoreText,
		total(r.Adjusted[first:last]), total(allocation[first:last]),
		netText, total(points[first:last]))
}

func (g *Golf) card(p *Player, number int) {
	r := p.Rounds[number-1]
	hcp := 0
	if r.Handicap != nil {
		hcp = *r.Handicap
	}
	allocation := strokes(hcp, r.Course.SI)
	nets, points := r.nets(allocation), r.points(r.nets(allocation))
	g.emit("card", p.ID, fmt.Sprint(number, ":"), r.Course.ID, r.Tee.ID,
		"day", r.Day, "handicap", handicapText(r.Handicap))
	for hole, score := range r.Scores {
		scoreText, netText := strconv.Itoa(score), "-"
		if score == 0 {
			scoreText = "-"
		} else if score < 0 {
			scoreText = "X"
		} else {
			netText = strconv.Itoa(nets[hole])
		}
		g.emit(hole+1, r.Course.Pars[hole], r.Course.SI[hole], scoreText,
			r.Adjusted[hole], allocation[hole], netText, points[hole])
		if hole == 8 {
			g.cardTotal("OUT", r, allocation, nets, points, 0, 9)
		} else if hole == 17 {
			g.cardTotal("IN", r, allocation, nets, points, 9, 18)
			g.cardTotal("TOTAL", r, allocation, nets, points, 0, 18)
		}
	}
	g.emit("ags", r.AGS, "diff", decimal(r.Differential, "-"))
}

func (g *Golf) stats(p *Player) {
	labels := []string{"eagles", "birdies", "pars", "bogeys", "doubles", "others", "pickups"}
	categories := make([]int, len(labels))
	parTotal := [3]int{}
	parCount := [3]int{}
	complete := []int{}
	for _, r := range p.Rounds {
		if r.complete() {
			complete = append(complete, total(r.Scores))
		}
		for hole, score := range r.Scores {
			par := r.Course.Pars[hole]
			if score == -1 {
				categories[6]++
			} else if score > 0 {
				bucket := score - par + 2
				if bucket < 0 {
					bucket = 0
				}
				if bucket > 5 {
					bucket = 5
				}
				categories[bucket]++
				parTotal[par-3] += score
				parCount[par-3]++
			}
		}
	}
	best := "-"
	if len(complete) != 0 {
		sort.Ints(complete)
		best = strconv.Itoa(complete[0])
	}
	parts := []interface{}{"stats", p.ID+":", "rounds", len(p.Rounds),
		"best", best, "average", average(total(complete), len(complete))}
	for i, label := range labels {
		parts = append(parts, label, categories[i])
	}
	for i := 0; i < 3; i++ {
		parts = append(parts, fmt.Sprint("par", i+3), average(parTotal[i], parCount[i]))
	}
	g.emit(parts...)
}

func (g *Golf) holeStats(course *Course) {
	sums, counts := [18]int{}, [18]int{}
	rounds := 0
	for _, p := range g.Players {
		for _, r := range p.Rounds {
			if r.Course != course {
				continue
			}
			rounds++
			for h, score := range r.Scores {
				if score > 0 {
					sums[h] += score
					counts[h]++
				}
			}
		}
	}
	order := make([]int, 18)
	ranks := make([]int, 18)
	for h := range order {
		order[h] = h
	}
	sort.Slice(order, func(i, j int) bool {
		a, b := order[i], order[j]
		if counts[a] == 0 || counts[b] == 0 {
			if counts[a] == 0 && counts[b] == 0 {
				return a < b
			}
			return counts[a] != 0
		}
		ar := (sums[a] - course.Pars[a]*counts[a]) * counts[b]
		br := (sums[b] - course.Pars[b]*counts[b]) * counts[a]
		if ar != br {
			return ar > br
		}
		return a < b
	})
	for rank, hole := range order {
		ranks[hole] = rank + 1
	}
	g.emit("holestats", course.ID+":", "rounds", rounds)
	for hole := 0; hole < 18; hole++ {
		g.emit(hole+1, "par", course.Pars[hole], "si", course.SI[hole],
			"scores", counts[hole], "avg", average(sums[hole], counts[hole]), "rank", ranks[hole])
	}
}

func (g *Golf) playersList() {
	players := make([]*Player, 0, len(g.Players))
	for _, p := range g.Players {
		players = append(players, p)
	}
	sort.Slice(players, func(i, j int) bool {
		a, b := players[i], players[j]
		if a.Index == nil || b.Index == nil {
			if a.Index == nil && b.Index == nil {
				return a.ID < b.ID
			}
			return a.Index != nil
		}
		if *a.Index != *b.Index {
			return *a.Index < *b.Index
		}
		return a.ID < b.ID
	})
	g.emit("players", len(players))
	for _, p := range players {
		g.emit(p.ID, p.Name, indexText(p.Index), "rounds", len(p.Rounds))
	}
}

func (g *Golf) dispatch(command string, a []string) string {
	switch command {
	case "COURSE":
		id := a[0]
		if g.Courses[id] != nil {
			return "duplicate course"
		}
		pars, si := make([]int, 18), make([]int, 18)
		seen := make(map[int]bool)
		for i := 0; i < 18; i++ {
			pars[i], si[i] = number(a[i+1]), number(a[i+19])
			if pars[i] < 3 || pars[i] > 5 || si[i] < 1 || si[i] > 18 || seen[si[i]] {
				return "invalid course"
			}
			seen[si[i]] = true
		}
		g.Courses[id] = &Course{id, pars, si, total(pars), make(map[string]*Tee)}
	case "TEE":
		c, err := g.course(a[0])
		if err != "" {
			return err
		}
		if c.Tees[a[1]] != nil {
			return "duplicate tee"
		}
		rating, slope := number(a[2]), number(a[3])
		if rating < 500 || rating > 900 || slope < 55 || slope > 155 {
			return "invalid tee"
		}
		c.Tees[a[1]] = &Tee{a[1], rating, slope}
	case "PLAYER":
		if g.Players[a[0]] != nil {
			return "duplicate player"
		}
		var index *int
		if len(a) == 3 {
			n := number(a[2])
			if n < -100 || n > 540 {
				return "invalid index"
			}
			index = pointer(n)
		}
		g.Players[a[0]] = &Player{ID: a[0], Name: a[1], Index: index}
	case "EVENT":
		id, form := a[0], a[1]
		if g.Events[id] != nil {
			return "duplicate event"
		}
		c, t, err := g.tee(a[2], a[3])
		if err != "" {
			return err
		}
		allowance := number(a[5])
		if allowance < 1 || allowance > 100 {
			return "invalid allowance"
		}
		players := make([]*Player, 0, len(a)-6)
		seen := make(map[string]bool)
		duplicate := false
		for _, pid := range a[6:] {
			if g.Players[pid] == nil {
				return "unknown player"
			}
			if seen[pid] {
				duplicate = true
			}
			seen[pid] = true
			players = append(players, g.Players[pid])
		}
		n := len(players)
		valid := n >= 2 && n <= 8
		switch form {
		case "MATCH", "NASSAU":
			valid = n == 2
		case "FOURBALL":
			valid = n == 4
		case "BETTERBALL":
			valid = n == 4 || n == 6 || n == 8
		}
		if duplicate || !valid {
			return "invalid players"
		}
		event := &Event{id, form, c, t, number(a[4]), allowance, players}
		g.Events[id] = event
		g.EventOrder = append(g.EventOrder, event)
	case "RESULTS":
		event := g.Events[a[0]]
		if event == nil {
			return "unknown event"
		}
		data, err := g.eventData(event)
		if err != "" {
			return err
		}
		g.results(event, data)
	case "MERIT":
		g.merit()
	case "PLAYERS":
		g.playersList()
	case "HOLESTATS":
		c, err := g.course(a[0])
		if err != "" {
			return err
		}
		g.holeStats(c)
	case "HCPTABLE":
		c, t, err := g.tee(a[0], a[1])
		if err != "" {
			return err
		}
		first, last := number(a[2]), number(a[3])
		if first < -100 || first > last || last > 540 {
			return "invalid index"
		}
		g.emit("hcptable", c.ID, t.ID+":", indexText(pointer(first)), "to", indexText(pointer(last)))
		begin := first
		hcp := t.handicap(first, c)
		for i := first+1; i <= last; i++ {
			next := t.handicap(i, c)
			if next != hcp {
				g.emit(indexText(pointer(begin)), "to", indexText(pointer(i-1))+":", handicapText(pointer(hcp)))
				begin, hcp = i, next
			}
		}
		g.emit(indexText(pointer(begin)), "to", indexText(pointer(last))+":", handicapText(pointer(hcp)))
	case "REMOVE", "INDEX", "HISTORY", "LOWINDEX", "COURSEHCP", "ROUND", "CARD", "STATS":
		p, err := g.player(a[0])
		if err != "" {
			return err
		}
		switch command {
		case "COURSEHCP", "ROUND":
			c, t, err := g.tee(a[1], a[2])
			if err != "" {
				return err
			}
			if command == "COURSEHCP" {
				if p.Index == nil {
					return "no index"
				}
				hcp := t.handicap(*p.Index, c)
				parts := []interface{}{"coursehcp", p.ID, c.ID, t.ID+":", handicapText(pointer(hcp)), "strokes"}
				for _, stroke := range strokes(hcp, c.SI) {
					parts = append(parts, stroke)
				}
				g.emit(parts...)
			} else {
				day := number(a[3])
				if len(p.Rounds) != 0 && day < p.Rounds[len(p.Rounds)-1].Day {
					return "invalid day"
				}
				scores, missing := make([]int, 18), 0
				for i, text := range a[4:] {
					if text == "-" {
						missing++
					} else if text == "X" {
						scores[i] = -1
					} else {
						scores[i] = number(text)
					}
				}
				if missing >= 5 {
					return "too few holes"
				}
				r := newRound(p, c, t, day, scores)
				p.Rounds = append(p.Rounds, r)
				p.updateIndex(day)
				if p.Index != nil {
					p.Records = append(p.Records, IndexRecord{day, *p.Index})
				}
				parts := []interface{}{"round", p.ID, fmt.Sprint(len(p.Rounds), ":"),
					"ags", r.AGS, "diff", decimal(r.Differential, "-")}
				if r.Exceptional != 0 {
					parts = append(parts, "exceptional", decimal(-r.Exceptional, "-"))
				}
				parts = append(parts, "index", indexText(p.Index))
				g.emit(parts...)
			}
		case "REMOVE":
			if len(p.Rounds) == 0 {
				return "no rounds"
			}
			n := len(p.Rounds)
			r := p.Rounds[n-1]
			p.Rounds = p.Rounds[:n-1]
			p.Index = r.Previous
			p.Records = p.Records[:r.PreviousRecords]
			p.Calculation = r.PreviousCalculation
			g.emit("removed", p.ID, fmt.Sprint(n, ":"), "index", indexText(p.Index))
		case "INDEX":
			parts := []interface{}{"index", p.ID+":", indexText(p.Index), "rounds", len(p.Rounds)}
			if c := p.Calculation; c != nil {
				parts = append(parts, "lowest", c.K, "average", decimal(c.Average, "-"),
					"adjustment", decimal(c.Adjustment, "-"))
				if c.Low != nil {
					parts = append(parts, "low", indexText(c.Low))
				}
				if c.Hard {
					parts = append(parts, "hard", "cap")
				} else if c.Soft {
					parts = append(parts, "soft", "cap")
				}
				if c.Maximum {
					parts = append(parts, "maximum")
				}
			}
			g.emit(parts...)
		case "HISTORY":
			rows := p.eligible()
			selected, _ := counting(rows)
			marked := make(map[int]bool)
			for _, row := range selected {
				marked[row.Number] = true
			}
			g.emit("history", p.ID+":", "rounds", len(p.Rounds))
			for _, row := range rows {
				r := row.Round
				parts := []interface{}{row.Number, "day", r.Day, r.Course.ID, r.Tee.ID,
					"ags", r.AGS, "diff", decimal(r.Differential, "-")}
				if row.Adjusted != r.Differential {
					parts = append(parts, "adjusted", decimal(row.Adjusted, "-"))
				}
				if marked[row.Number] {
					parts = append(parts, "*")
				}
				g.emit(parts...)
			}
		case "LOWINDEX":
			day := number(a[1])
			record, ok := p.lowIndex(day)
			if !ok {
				g.emit("lowindex", p.ID, fmt.Sprint(day, ":"), "none")
			} else {
				g.emit("lowindex", p.ID, fmt.Sprint(day, ":"), indexText(pointer(record.Value)), "day", record.Day)
			}
		case "CARD":
			n := number(a[1])
			if n > len(p.Rounds) {
				return "unknown round"
			}
			g.card(p, n)
		case "STATS":
			g.stats(p)
		}
	}
	return ""
}

func (g *Golf) execute(line string) {
	words := strings.Fields(line)
	if len(words) == 0 {
		return
	}
	if err := g.dispatch(words[0], words[1:]); err != "" {
		g.emit("ERROR", err)
	}
}

func main() {
	in := bufio.NewScanner(os.Stdin)
	in.Buffer(make([]byte, 4096), 1<<20)
	if !in.Scan() {
		return
	}
	n := number(strings.TrimSpace(in.Text()))
	golf := newGolf()
	for i := 0; i < n && in.Scan(); i++ {
		golf.execute(in.Text())
	}
	if len(golf.Output) > 0 {
		fmt.Println(strings.Join(golf.Output, "\n"))
	}
}
