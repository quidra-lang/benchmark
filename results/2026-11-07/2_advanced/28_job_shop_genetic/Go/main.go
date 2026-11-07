package main

import (
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

func integer(s string) int {
	n, e := strconv.Atoi(s)
	if e != nil {
		panic(e)
	}
	return n
}
func readLines(path string) []string {
	b, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	return strings.Split(strings.TrimSuffix(string(b), "\n"), "\n")
}
func writeLines(name string, lines []string) {
	if e := os.WriteFile("output/"+name, []byte(strings.Join(lines, "\n")+"\n"), 0644); e != nil {
		panic(e)
	}
}
func line(parts ...any) string {
	fields := []string{}
	for _, p := range parts {
		fields = append(fields, fmt.Sprint(p))
	}
	return strings.Join(fields, " ")
}
func integers(values []int) string {
	fields := []string{}
	for _, v := range values {
		fields = append(fields, fmt.Sprint(v))
	}
	return strings.Join(fields, " ")
}
func percentage(a, b int) string {
	t := (2000*a + b) / (2 * b)
	return fmt.Sprintf("%d.%d%%", t/10, t%10)
}
func jobLetter(j int) string { return string(rune('A' + j - 1)) }
func sum(v []int) int {
	n := 0
	for _, x := range v {
		n += x
	}
	return n
}
func maximum(v []int) int {
	n := v[0]
	for _, x := range v[1:] {
		n = max(n, x)
	}
	return n
}
func gcd(a, b int) int {
	for b != 0 {
		a, b = b, a%b
	}
	return a
}
func makespan(starts, durations []int) int {
	result := 0
	for i, start := range starts {
		result = max(result, start+durations[i])
	}
	return result
}
func indexOf(values []int, value int) int {
	for i, x := range values {
		if x == value {
			return i
		}
	}
	return -1
}
func copyOrder(order [][]int) [][]int {
	result := make([][]int, len(order))
	for i, row := range order {
		result[i] = append([]int(nil), row...)
	}
	return result
}

var rules = []string{"SPT", "LPT", "MWKR", "FIFO"}

type Parameters struct {
	Seed                                                                            int64
	Population, Generations, Tournament, Elitism, TabuIterations, TabuTenure, Width int
	Crossover, Swap, Insert                                                         [2]int
	Checkpoints                                                                     map[int]bool
}

func loadParameters() Parameters {
	f := map[string][]string{}
	for _, l := range readLines("input/ga_params.txt") {
		p := strings.Fields(l)
		f[p[0]] = p[1:]
	}
	n := func(key string) int { return integer(f[key][0]) }
	fraction := func(key string) [2]int {
		p := strings.Split(f[key][0], "/")
		return [2]int{integer(p[0]), integer(p[1])}
	}
	p := Parameters{Seed: int64(n("seed")), Population: n("population"), Generations: n("generations"),
		Tournament: n("tournament"), Elitism: n("elitism"), TabuIterations: n("tabu_iterations"),
		TabuTenure: n("tabu_tenure"), Width: n("gantt_width"), Crossover: fraction("crossover"),
		Swap: fraction("swap_mutation"), Insert: fraction("insert_mutation"), Checkpoints: map[int]bool{}}
	for _, v := range f["checkpoints"] {
		p.Checkpoints[integer(v)] = true
	}
	return p
}
func jacksonBound(in *Instance, m Machine) int {
	remaining := []int{}
	for _, id := range m.Operations {
		remaining = append(remaining, in.Operations[id].Duration)
	}
	time, bound := 0, 0
	for sum(remaining) > 0 {
		released := false
		next := 1 << 30
		for i, id := range m.Operations {
			if remaining[i] > 0 {
				head := in.Operations[id].Head
				if head <= time {
					released = true
				}
				next = min(next, head)
			}
		}
		if !released {
			time = next
		}
		best := -1
		for i, id := range m.Operations {
			o := in.Operations[id]
			if remaining[i] > 0 && o.Head <= time && (best < 0 || o.Tail > in.Operations[m.Operations[best]].Tail) {
				best = i
			}
		}
		step := remaining[best]
		for _, id := range m.Operations {
			h := in.Operations[id].Head
			if h > time {
				step = min(step, h-time)
			}
		}
		time += step
		remaining[best] -= step
		if remaining[best] == 0 {
			bound = max(bound, time+in.Operations[m.Operations[best]].Tail)
		}
	}
	return bound
}
func orderStarts(in *Instance, order [][]int, durations []int) []int {
	starts, ends := make([]int, len(in.Operations)), make([]int, len(in.Operations))
	for i := range starts {
		starts[i] = -1
	}
	positions := make([]int, in.MachineCount)
	placed := 0
	for placed < len(starts) {
		for m, row := range order {
			for positions[m] < len(row) {
				pos := positions[m]
				id := row[pos]
				prev := in.Operations[id].Prev
				if prev >= 0 && starts[prev] < 0 {
					break
				}
				ready, free := 0, 0
				if prev >= 0 {
					ready = ends[prev]
				}
				if pos > 0 {
					free = ends[row[pos-1]]
				}
				starts[id] = max(ready, free)
				ends[id] = starts[id] + durations[id]
				positions[m]++
				placed++
			}
		}
	}
	return starts
}

type Schedule struct {
	Instance                               *Instance
	Starts, Ends, MachinePrev, MachineNext []int
	Order                                  [][]int
	Makespan                               int
}

func newSchedule(in *Instance, starts []int) *Schedule {
	s := &Schedule{Instance: in, Starts: starts, Ends: make([]int, len(starts)), MachinePrev: make([]int,
		len(starts)), MachineNext: make([]int, len(starts)), Order: make([][]int, in.MachineCount)}
	for i, start := range starts {
		s.Ends[i] = start + in.Durations[i]
		s.Makespan = max(s.Makespan, s.Ends[i])
		s.MachinePrev[i], s.MachineNext[i] = -1, -1
	}
	for _, id := range s.ByStart() {
		m := in.Operations[id].Machine - 1
		s.Order[m] = append(s.Order[m], id)
	}
	for _, row := range s.Order {
		for i := 1; i < len(row); i++ {
			a, b := row[i-1], row[i]
			s.MachinePrev[b] = a
			s.MachineNext[a] = b
		}
	}
	return s
}
func scheduleOfOrder(in *Instance, order [][]int) *Schedule {
	return newSchedule(in, orderStarts(in, order, in.Durations))
}
func (s *Schedule) ByStart() []int {
	ids := make([]int, len(s.Starts))
	for i := range ids {
		ids[i] = i
	}
	sort.Slice(ids, func(i, j int) bool {
		a, b := ids[i], ids[j]
		if s.Starts[a] != s.Starts[b] {
			return s.Starts[a] < s.Starts[b]
		}
		return a < b
	})
	return ids
}
func (s *Schedule) Chromosome() []int {
	genes := []int{}
	for _, id := range s.ByStart() {
		genes = append(genes, s.Instance.Operations[id].Job)
	}
	return genes
}
func (s *Schedule) Path() []int {
	current := indexOf(s.Ends, s.Makespan)
	path := []int{current}
	for s.Starts[current] != 0 {
		prev := s.MachinePrev[current]
		if prev >= 0 && s.Ends[prev] == s.Starts[current] {
			current = prev
		} else {
			current = s.Instance.Operations[current].Prev
		}
		path = append(path, current)
	}
	for i, j := 0, len(path)-1; i < j; i, j = i+1, j-1 {
		path[i], path[j] = path[j], path[i]
	}
	return path
}
func (s *Schedule) Blocks(path []int) [][]int {
	blocks := [][]int{}
	for _, id := range path {
		if len(blocks) > 0 && s.Instance.Operations[blocks[len(blocks)-1][0]].Machine == s.Instance.Operations[id].Machine {
			k := len(blocks) - 1
			blocks[k] = append(blocks[k], id)
		} else {
			blocks = append(blocks, []int{id})
		}
	}
	return blocks
}
func (s *Schedule) Moves() [][2]int {
	moves := [][2]int{}
	for _, block := range s.Blocks(s.Path()) {
		for i := 1; i < len(block); i++ {
			moves = append(moves, [2]int{block[i-1], block[i]})
		}
	}
	return moves
}
func (s *Schedule) PathCount() int {
	ways := make([]int, len(s.Starts))
	for _, id := range s.ByStart() {
		if s.Starts[id] == 0 {
			ways[id] = 1
		} else {
			for _, prev := range []int{s.Instance.Operations[id].Prev, s.MachinePrev[id]} {
				if prev >= 0 && s.Ends[prev] == s.Starts[id] {
					ways[id] += ways[prev]
				}
			}
		}
	}
	count := 0
	for id, end := range s.Ends {
		if end == s.Makespan {
			count += ways[id]
		}
	}
	return count
}
func (s *Schedule) LeftShift(id int) (int, int, bool) {
	o := s.Instance.Operations[id]
	row := s.Order[o.Machine-1]
	position := indexOf(row, id)
	if position == 0 {
		return 0, 0, false
	}
	ready := 0
	if o.Prev >= 0 {
		ready = s.Ends[o.Prev]
	}
	for insertion := 0; insertion < position; insertion++ {
		begin := 0
		if insertion > 0 {
			begin = s.Ends[row[insertion-1]]
		}
		start := max(begin, ready)
		if start+o.Duration <= s.Starts[row[insertion]] {
			return start, insertion, true
		}
	}
	return 0, 0, false
}
func (s *Schedule) ShiftableCount() int {
	count := 0
	for id := range s.Starts {
		if _, _, ok := s.LeftShift(id); ok {
			count++
		}
	}
	return count
}
func (s *Schedule) Slacks() ([]int, []int) {
	latest, slack, free := make([]int, len(s.Starts)), make([]int, len(s.Starts)), make([]int, len(s.Starts))
	order := s.ByStart()
	for i := len(order) - 1; i >= 0; i-- {
		id := order[i]
		limit, startLimit := s.Makespan, s.Makespan
		hasNext := false
		for _, next := range []int{s.Instance.Operations[id].Next, s.MachineNext[id]} {
			if next >= 0 {
				if !hasNext {
					limit, startLimit = latest[next], s.Starts[next]
				} else {
					limit = min(limit, latest[next])
					startLimit = min(startLimit, s.Starts[next])
				}
				hasNext = true
			}
		}
		latest[id] = limit - s.Instance.Durations[id]
		slack[id] = latest[id] - s.Starts[id]
		free[id] = startLimit - s.Ends[id]
	}
	return slack, free
}
func (s *Schedule) PathCounts() []int {
	counts := make([]int, s.Instance.MachineCount)
	for _, id := range s.Path() {
		counts[s.Instance.Operations[id].Machine-1]++
	}
	return counts
}
func (s *Schedule) Bottleneck() (int, int) {
	counts := s.PathCounts()
	best := 0
	for m, c := range counts {
		if c > counts[best] {
			best = m
		}
	}
	return best + 1, counts[best]
}
func (s *Schedule) JobCompletion(j Job) int { return s.Ends[j.Operations[len(j.Operations)-1]] }
func (s *Schedule) Flow() int {
	total := 0
	for _, j := range s.Instance.Jobs {
		total += s.JobCompletion(j)
	}
	return total
}
func (s *Schedule) Idle() int {
	total := 0
	for _, m := range s.Instance.Machines {
		total += s.Makespan - m.Load
	}
	return total
}
func (s *Schedule) Letters(m int) string {
	letters := ""
	for _, id := range s.Order[m-1] {
		letters += jobLetter(s.Instance.Operations[id].Job)
	}
	return letters
}
func applyMove(in *Instance, order [][]int, move [2]int) [][]int {
	result := copyOrder(order)
	row := result[in.Operations[move[0]].Machine-1]
	pos := indexOf(row, move[0])
	row[pos], row[pos+1] = row[pos+1], row[pos]
	return result
}
func machineDistances(a, b *Schedule) []int {
	distances := []int{}
	for m, row := range a.Order {
		ranks := map[int]int{}
		for i, id := range b.Order[m] {
			ranks[id] = i
		}
		count := 0
		for i := range row {
			for j := i + 1; j < len(row); j++ {
				if ranks[row[i]] > ranks[row[j]] {
					count++
				}
			}
		}
		distances = append(distances, count)
	}
	return distances
}

type TabuRecord struct {
	Iteration, Moves, Tabu int
	Move                   [2]int
	Aspiration             bool
	Value, Best            int
}
type Search struct {
	BestOrder                    [][]int
	StartValue, BestValue, Found int
	Records                      []TabuRecord
	Reason                       string
}

func tabuSearch(in *Instance, order [][]int, p Parameters) *Search {
	start := scheduleOfOrder(in, order).Makespan
	s := &Search{BestOrder: order, StartValue: start, BestValue: start, Reason: "limit"}
	current := order
	expiry := map[[2]int]int{}
	for it := 1; it <= p.TabuIterations; it++ {
		moves := scheduleOfOrder(in, current).Moves()
		if len(moves) == 0 {
			s.Reason = "no_moves"
			break
		}
		best, bestValue, tabuCount := -1, 0, 0
		chosenTabu := false
		for i, move := range moves {
			value := scheduleOfOrder(in, applyMove(in, current, move)).Makespan
			until, exists := expiry[move]
			tabu := exists && until >= it
			if tabu {
				tabuCount++
			}
			if (!tabu || value < s.BestValue) && (best < 0 || value < bestValue) {
				best, bestValue, chosenTabu = i, value, tabu
			}
		}
		if best < 0 {
			s.Reason = "all_tabu"
			break
		}
		move := moves[best]
		current = applyMove(in, current, move)
		expiry[[2]int{move[1], move[0]}] = it + p.TabuTenure
		if bestValue < s.BestValue {
			s.BestOrder, s.BestValue, s.Found = current, bestValue, it
		}
		s.Records = append(s.Records, TabuRecord{it, len(moves), tabuCount, move, chosenTabu, bestValue, s.BestValue})
	}
	return s
}

type Shift struct{ Ident, Old, New int }

func activate(in *Instance, order [][]int) ([][]int, []Shift) {
	current := copyOrder(order)
	shifts := []Shift{}
	for {
		s := scheduleOfOrder(in, current)
		found := false
		for _, id := range s.ByStart() {
			start, insertion, ok := s.LeftShift(id)
			if !ok {
				continue
			}
			m := in.Operations[id].Machine - 1
			row := current[m]
			pos := indexOf(row, id)
			row = append(row[:pos], row[pos+1:]...)
			row = append(row, 0)
			copy(row[insertion+1:], row[insertion:])
			row[insertion] = id
			current[m] = row
			shifts = append(shifts, Shift{id, s.Starts[id], start})
			found = true
			break
		}
		if !found {
			return current, shifts
		}
	}
}

type Baseline struct {
	Rule            string
	Schedule        *Schedule
	Decisions, Ties int
	Search          *Search
}
type GA struct {
	Instance                   *Instance
	Params                     Parameters
	Rng                        Minstd
	Population                 [][]int
	Values                     []int
	Records                    [][3]int
	Progress                   []string
	Crossovers, Swaps, Inserts int
}

func ranking(values []int) []int {
	order := make([]int, len(values))
	for i := range order {
		order[i] = i
	}
	sort.SliceStable(order, func(i, j int) bool { return values[order[i]] < values[order[j]] })
	return order
}
func (g *GA) mutate(c []int) {
	if g.Rng.Chance(g.Params.Swap) {
		g.Swaps++
		swapMutation(&g.Rng, c)
	}
	if g.Rng.Chance(g.Params.Insert) {
		g.Inserts++
		insertMutation(&g.Rng, c)
	}
}
func (g *GA) Run() {
	p := g.Params
	for len(g.Population) < p.Population {
		sequence := []int{}
		for _, j := range g.Instance.Jobs {
			for range j.Operations {
				sequence = append(sequence, j.Number)
			}
		}
		g.Rng.Shuffle(sequence)
		g.Population = append(g.Population, sequence)
	}
	previous := -1
	for generation := 0; generation <= p.Generations; generation++ {
		g.Values = nil
		distinct := map[string]bool{}
		for _, c := range g.Population {
			g.Values = append(g.Values, makespan(decode(g.Instance, c), g.Instance.Durations))
			distinct[integers(c)] = true
		}
		order := ranking(g.Values)
		best := order[0]
		if generation == 0 || g.Values[best] < previous {
			g.Records = append(g.Records, [3]int{generation, g.Values[best], best + 1})
		}
		previous = g.Values[best]
		if p.Checkpoints[generation] {
			total := sum(g.Values)
			d := gcd(total, p.Population)
			g.Progress = append(g.Progress, fmt.Sprintf("%d,%d,%d/%d,%d,%d", generation, g.Values[best], total/d, p.Population/d, maximum(g.Values), len(distinct)))
		}
		if generation == p.Generations {
			break
		}
		next := [][]int{}
		for _, i := range order[:p.Elitism] {
			next = append(next, append([]int(nil), g.Population[i]...))
		}
		for len(next) < p.Population {
			first := g.Population[tournament(&g.Rng, g.Values, p.Tournament)]
			second := g.Population[tournament(&g.Rng, g.Values, p.Tournament)]
			var a, b []int
			if g.Rng.Chance(p.Crossover) {
				g.Crossovers++
				a, b = crossover(&g.Rng, first, second, g.Instance.Jobs)
			} else {
				a, b = append([]int(nil), first...), append([]int(nil), second...)
			}
			g.mutate(a)
			g.mutate(b)
			next = append(next, a, b)
		}
		g.Population = next
	}
}

type Solver struct {
	Instance                                     *Instance
	Params                                       Parameters
	Jacksons                                     []int
	JobBound                                     Job
	MachineBound                                 Machine
	JacksonIndex, Lower                          int
	Baselines                                    []Baseline
	Genetic                                      *GA
	GASchedule, Final                            *Schedule
	ActiveValue, ActiveDecisions, ActivatedValue int
	Shifts                                       []Shift
	Search                                       *Search
}

func solve(in *Instance, p Parameters) *Solver {
	s := &Solver{Instance: in, Params: p, JobBound: in.Jobs[0], MachineBound: in.Machines[0]}
	for _, j := range in.Jobs {
		if j.Work > s.JobBound.Work {
			s.JobBound = j
		}
	}
	for _, m := range in.Machines {
		if m.Bound > s.MachineBound.Bound {
			s.MachineBound = m
		}
		s.Jacksons = append(s.Jacksons, jacksonBound(in, m))
	}
	for i, v := range s.Jacksons {
		if v > s.Jacksons[s.JacksonIndex] {
			s.JacksonIndex = i
		}
	}
	s.Lower = max(s.JobBound.Work, s.MachineBound.Bound, s.Jacksons[s.JacksonIndex])
	seeds := [][]int{}
	for _, rule := range rules {
		starts, decisions, ties := dispatch(in, rule, nil)
		schedule := newSchedule(in, starts)
		s.Baselines = append(s.Baselines, Baseline{rule, schedule, decisions, ties, tabuSearch(in, schedule.Order, p)})
		seeds = append(seeds, schedule.Chromosome())
	}
	g := &GA{Instance: in, Params: p, Rng: Minstd{p.Seed}, Population: seeds}
	g.Run()
	s.Genetic = g
	chromosome := g.Population[ranking(g.Values)[0]]
	s.GASchedule = newSchedule(in, decode(in, chromosome))
	positions := make([]int, len(in.Operations))
	for i, id := range geneOperations(in, chromosome) {
		positions[id] = i + 1
	}
	starts, decisions, _ := dispatch(in, "GENES", positions)
	s.ActiveValue, s.ActiveDecisions = makespan(starts, in.Durations), decisions
	order, shifts := activate(in, s.GASchedule.Order)
	s.Shifts = shifts
	s.ActivatedValue = scheduleOfOrder(in, order).Makespan
	s.Search = tabuSearch(in, order, p)
	s.Final = scheduleOfOrder(in, s.Search.BestOrder)
	return s
}
func (s *Solver) baselineLines() []string {
	in := s.Instance
	total := sum(in.Durations)
	lines := []string{line("INSTANCE", "jobs", len(in.Jobs), "machines", in.MachineCount, "operations",
		len(in.Operations), "work", total, "errors", len(in.Errors))}
	for _, e := range in.Errors {
		lines = append(lines, "ERROR "+e)
	}
	for _, j := range in.Jobs {
		route := []string{}
		for _, id := range j.Operations {
			route = append(route, fmt.Sprintf("M%d", in.Operations[id].Machine))
		}
		lines = append(lines, line("JOB", fmt.Sprintf("J%d", j.Number), "operations", len(j.Operations), "work", j.Work, "route", strings.Join(route, " ")))
	}
	for i, m := range in.Machines {
		lines = append(lines, line("MACHINE", fmt.Sprintf("M%d", m.Number), "operations", len(m.Operations),
			"load", m.Load, "head", m.Head, "tail", m.Tail, "bound", m.Bound, "jackson", s.Jacksons[i]))
	}
	lines = append(lines, line("BOUND", "job", s.JobBound.Work, fmt.Sprintf("J%d", s.JobBound.Number)),
		line("BOUND", "machine", s.MachineBound.Bound, fmt.Sprintf("M%d", s.MachineBound.Number)),
		line("BOUND", "jackson", s.Jacksons[s.JacksonIndex], fmt.Sprintf("M%d", s.JacksonIndex+1)),
		line("BOUND", "lower", s.Lower))
	best := s.Baselines[0]
	for _, b := range s.Baselines {
		x := b.Schedule
		path := x.Path()
		bottleneck, _ := x.Bottleneck()
		search := b.Search
		lines = append(lines, line("RULE", b.Rule, "makespan", x.Makespan, "gap", percentage(x.Makespan-s.Lower,
			s.Lower), "flow", x.Flow(), "idle", x.Idle(), "decisions", b.Decisions, "ties", b.Ties),
			line("PATH", b.Rule, "operations", len(path), "blocks", len(x.Blocks(path)), "critical_paths",
				x.PathCount(), "bottleneck", fmt.Sprintf("M%d", bottleneck)), line("TABU", b.Rule, "makespan",
				x.Makespan, "->", search.BestValue, "found", search.Found, "iterations", len(search.Records),
				"stop", search.Reason))
		if x.Makespan < best.Schedule.Makespan {
			best = b
		}
	}
	lines = append(lines, line("BEST", best.Rule, "makespan", best.Schedule.Makespan))
	for _, m := range in.Machines {
		parts := []any{"UTILIZATION", fmt.Sprintf("M%d", m.Number)}
		for _, b := range s.Baselines {
			parts = append(parts, b.Rule, percentage(m.Load, b.Schedule.Makespan))
		}
		lines = append(lines, line(parts...))
	}
	return lines
}
func (s *Solver) ganttLines() []string {
	in, x := s.Instance, s.Final
	scale, columns := chartScale(x.Makespan, s.Params.Width)
	onPath := map[int]bool{}
	for _, id := range x.Path() {
		onPath[id] = true
	}
	rows := make([][]Interval, in.MachineCount)
	for id, o := range in.Operations {
		mark := jobLetter(o.Job)
		if onPath[id] {
			mark = strings.ToLower(mark)
		}
		rows[o.Machine-1] = append(rows[o.Machine-1], Interval{x.Starts[id], x.Ends[id], mark})
	}
	lines := []string{line("GANTT", "scale", scale, "columns", columns), timeRow(scale, columns), ruleRow(columns)}
	for i, row := range rows {
		lines = append(lines, chartRow(fmt.Sprintf("M%d", i+1), row, scale, columns))
	}
	lines = append(lines, busyRow(rows, scale, columns))
	for _, j := range in.Jobs {
		intervals := []Interval{}
		for _, id := range j.Operations {
			intervals = append(intervals, Interval{x.Starts[id], x.Ends[id], fmt.Sprint(in.Operations[id].Machine % 10)})
		}
		lines = append(lines, chartRow(fmt.Sprintf("J%d", j.Number), intervals, scale, columns))
	}
	return lines
}
func (s *Solver) scheduleLines() []string {
	in, g, x := s.Instance, s.Genetic, s.Final
	bestIndex := ranking(g.Values)[0]
	lines := []string{line("GA", "best", s.GASchedule.Makespan, "generation", g.Records[len(g.Records)-1][0],
		"crossovers", g.Crossovers, "swaps", g.Swaps, "inserts", g.Inserts)}
	for _, r := range g.Records {
		lines = append(lines, line("RECORD", "generation", r[0], "makespan", r[1], "individual", r[2]))
	}
	seen := map[string]bool{}
	rank := 0
	for _, i := range ranking(g.Values) {
		key := integers(g.Population[i])
		if seen[key] {
			continue
		}
		seen[key] = true
		rank++
		other := newSchedule(in, decode(in, g.Population[i]))
		lines = append(lines, line("TOP", rank, "individual", i+1, "makespan", g.Values[i], "distance", sum(machineDistances(other, s.GASchedule))))
		if rank == 5 {
			break
		}
	}
	lines = append(lines, "GA_CHROMOSOME "+integers(g.Population[bestIndex]), line("ACTIVE_DECODE", "makespan", s.ActiveValue, "decisions", s.ActiveDecisions))
	for i, shift := range s.Shifts {
		o := in.Operations[shift.Ident]
		lines = append(lines, line("SHIFT", i+1, o.Code(), fmt.Sprintf("M%d", o.Machine), "start", shift.Old, "->", shift.New))
	}
	lines = append(lines, line("ACTIVATED", "makespan", s.GASchedule.Makespan, "->", s.ActivatedValue,
		"shifts", len(s.Shifts)), line("SCHEDULE", "makespan", x.Makespan, "lower_bound", s.Lower,
		"gap", percentage(x.Makespan-s.Lower, s.Lower), "improvement", s.GASchedule.Makespan-x.Makespan,
		"shiftable", x.ShiftableCount()), "CHROMOSOME "+integers(x.Chromosome()))
	legend := []string{}
	for _, j := range in.Jobs {
		legend = append(legend, fmt.Sprintf("%s=J%d", jobLetter(j.Number), j.Number))
	}
	lines = append(lines, "LEGEND "+strings.Join(legend, " "))
	lines = append(lines, s.ganttLines()...)
	for _, m := range in.Machines {
		parts := []any{"ORDER", fmt.Sprintf("M%d", m.Number), "FINAL", x.Letters(m.Number)}
		for _, b := range s.Baselines {
			parts = append(parts, b.Rule, b.Schedule.Letters(m.Number))
		}
		lines = append(lines, line(parts...))
	}
	for _, m := range in.Machines {
		row := x.Order[m.Number-1]
		gaps, longest := 0, 0
		sequence, idle := []string{}, []string{}
		last := 0
		for i, id := range row {
			if x.Starts[id] > last {
				idle = append(idle, fmt.Sprintf("%d-%d", last, x.Starts[id]))
				if i > 0 {
					gaps++
					longest = max(longest, x.Starts[id]-last)
				}
			}
			sequence = append(sequence, fmt.Sprintf("J%d:%d-%d", in.Operations[id].Job, x.Starts[id], x.Ends[id]))
			last = x.Ends[id]
		}
		if last < x.Makespan {
			idle = append(idle, fmt.Sprintf("%d-%d", last, x.Makespan))
		}
		idleText := strings.Join(idle, " ")
		if len(idle) == 0 {
			idleText = "none"
		}
		lines = append(lines, line("MACHINE", fmt.Sprintf("M%d", m.Number), "load", m.Load, "idle", x.Makespan-m.Load,
			"utilization", percentage(m.Load, x.Makespan), "gaps", gaps, "longest_gap", longest,
			"sequence", strings.Join(sequence, " ")), line("IDLE", fmt.Sprintf("M%d", m.Number),
			idleText))
	}
	waiting := 0
	for _, j := range in.Jobs {
		completion := x.JobCompletion(j)
		waiting += completion - j.Work
		lines = append(lines, line("JOB", fmt.Sprintf("J%d", j.Number), "operations", len(j.Operations),
			"work", j.Work, "start", x.Starts[j.Operations[0]], "completion", completion, "waiting",
			completion-j.Work))
	}
	lines = append(lines, line("TOTAL", "flow", x.Flow(), "waiting", waiting, "idle", x.Idle()))
	labels := append(append([]string(nil), rules...), "GA")
	others := []*Schedule{}
	for _, b := range s.Baselines {
		others = append(others, b.Schedule)
	}
	others = append(others, s.GASchedule)
	distances := [][]int{}
	for _, other := range others {
		distances = append(distances, machineDistances(x, other))
	}
	pairsTotal := 0
	for i, m := range in.Machines {
		q := len(m.Operations)
		pairs := q * (q - 1) / 2
		pairsTotal += pairs
		parts := []any{"DISTANCE", fmt.Sprintf("M%d", m.Number), "pairs", pairs}
		for j, label := range labels {
			parts = append(parts, label, distances[j][i])
		}
		lines = append(lines, line(parts...))
	}
	parts := []any{"DISTANCE", "total", "pairs", pairsTotal}
	for j, label := range labels {
		parts = append(parts, label, sum(distances[j]))
	}
	return append(lines, line(parts...))
}
func (s *Solver) pathLines() []string {
	in, x, search := s.Instance, s.Final, s.Search
	lines := []string{line("SEARCH", "start", search.StartValue, "iterations", s.Params.TabuIterations, "tenure", s.Params.TabuTenure)}
	for _, r := range search.Records {
		a, b := in.Operations[r.Move[0]], in.Operations[r.Move[1]]
		kind := "free"
		if r.Aspiration {
			kind = "aspiration"
		}
		lines = append(lines, line("ITER", r.Iteration, "moves", r.Moves, "tabu", r.Tabu, "swap", fmt.Sprintf("M%d",
			a.Machine), a.Code(), b.Code(), kind, "makespan", r.Value, "best", r.Best))
	}
	path := x.Path()
	blocks := x.Blocks(path)
	lines = append(lines, line("STOP", "iterations", len(search.Records), "reason", search.Reason, "best",
		search.BestValue, "found", search.Found), line("PATH", "operations", len(path), "blocks",
		len(blocks), "makespan", x.Makespan, "critical_paths", x.PathCount()))
	for i, id := range path {
		o := in.Operations[id]
		link := "start"
		if i > 0 {
			link = "job"
			if x.MachinePrev[id] == path[i-1] {
				link = "machine"
			}
		}
		lines = append(lines, line("NODE", i+1, o.Code(), fmt.Sprintf("M%d", o.Machine), fmt.Sprintf("%d-%d", x.Starts[id], x.Ends[id]), link))
	}
	for i, block := range blocks {
		codes := []string{}
		for _, id := range block {
			codes = append(codes, in.Operations[id].Code())
		}
		lines = append(lines, line("BLOCK", i+1, fmt.Sprintf("M%d", in.Operations[block[0]].Machine), fmt.Sprintf("%d-%d",
			x.Starts[block[0]], x.Ends[block[len(block)-1]]), strings.Join(codes, " ")))
	}
	for i, move := range x.Moves() {
		a, b := in.Operations[move[0]], in.Operations[move[1]]
		value := scheduleOfOrder(in, applyMove(in, x.Order, move)).Makespan
		lines = append(lines, line("NEIGHBOUR", i+1, fmt.Sprintf("M%d", a.Machine), a.Code(), b.Code(), "makespan", value))
	}
	slack, free := x.Slacks()
	critical := 0
	for _, value := range slack {
		if value == 0 {
			critical++
		}
	}
	lines = append(lines, line("CRITICAL", "operations", critical, "total", len(in.Operations)))
	for _, kind := range []string{"SLACK", "FREE"} {
		values := slack
		if kind == "FREE" {
			values = free
		}
		for _, j := range in.Jobs {
			row := []int{}
			for _, id := range j.Operations {
				row = append(row, values[id])
			}
			lines = append(lines, line(kind, fmt.Sprintf("J%d", j.Number), integers(row)))
		}
	}
	counts := x.PathCounts()
	for i, m := range in.Machines {
		critical := 0
		durations := append([]int(nil), in.Durations...)
		for _, id := range m.Operations {
			if slack[id] == 0 {
				critical++
			}
			durations[id] += (durations[id] + 9) / 10
		}
		value := makespan(orderStarts(in, x.Order, durations), durations)
		lines = append(lines, line("MACHINE", fmt.Sprintf("M%d", m.Number), "critical", critical, "path", counts[i], "sensitivity", value, "delta", value-x.Makespan))
	}
	bottleneck, count := x.Bottleneck()
	return append(lines, line("BOTTLENECK", fmt.Sprintf("M%d", bottleneck), "path", count))
}
func main() {
	s := solve(loadInstance(), loadParameters())
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	writeLines("baselines.txt", s.baselineLines())
	writeLines("ga_progress.csv", append([]string{"generation,best,mean,worst,distinct"}, s.Genetic.Progress...))
	writeLines("best_schedule.txt", s.scheduleLines())
	writeLines("critical_path.txt", s.pathLines())
}
