package main

import (
	"fmt"
	"os"
	"sort"
	"strings"
)

var methods = []string{"mc", "sarsa", "q_learning", "expected_sarsa", "dyna_q"}
var policyNames = append([]string{"value_iteration", "policy_iteration"}, methods...)
var endings = []string{"goal", "pit", "timeout"}

const absorptionUnit int64 = 100000000

type Settings struct {
	Gamma, StepReward, SlipTotal, FloorSlip, IceSlip, Theta, Seed, RolloutSeed int64
	Episodes, StepLimit, BlockSize, PlanningSteps, Rollouts                    int
	GammaSweep                                                                 []int
	SlipSweep, Alpha, Epsilon                                                  [][2]int
}

func pairs(values []int) [][2]int {
	result := [][2]int{}
	for i := 0; i < len(values); i += 2 {
		result = append(result, [2]int{values[i], values[i+1]})
	}
	return result
}
func readSettings() *Settings {
	f := map[string][]int{}
	for _, line := range readLines("input/params.txt") {
		words := strings.Fields(line)
		f[words[0]] = numbers(words[1:])
	}
	return &Settings{Gamma: int64(f["GAMMA"][0]), StepReward: int64(f["STEP_REWARD"][0]), SlipTotal: int64(f["SLIP"][0]),
		FloorSlip: int64(f["SLIP"][1]), IceSlip: int64(f["SLIP"][2]), Theta: int64(f["THETA"][0]),
		GammaSweep: f["GAMMA_SWEEP"], SlipSweep: pairs(f["SLIP_SWEEP"]), Episodes: f["EPISODES"][0],
		StepLimit: f["STEP_LIMIT"][0], BlockSize: f["BLOCK_SIZE"][0], Alpha: pairs(f["ALPHA"]), Epsilon: pairs(f["EPSILON"]),
		PlanningSteps: f["PLANNING_STEPS"][0], Seed: int64(f["SEED"][0]), Rollouts: f["ROLLOUTS"][0],
		RolloutSeed: int64(f["ROLLOUT_SEED"][0])}
}
func scheduleValue(schedule [][2]int, episode int) int64 {
	value := schedule[0][1]
	for _, p := range schedule {
		if p[0] <= episode {
			value = p[1]
		}
	}
	return int64(value)
}
func phaseRanges(s *Settings) [][2]int {
	set := map[int]bool{}
	for _, schedule := range [][][2]int{s.Alpha, s.Epsilon} {
		for _, p := range schedule {
			set[p[0]] = true
		}
	}
	starts := []int{}
	for v := range set {
		starts = append(starts, v)
	}
	sort.Ints(starts)
	ranges := [][2]int{}
	for i, start := range starts {
		end := s.Episodes
		if i+1 < len(starts) {
			end = starts[i+1] - 1
		}
		ranges = append(ranges, [2]int{start, end})
	}
	return ranges
}
func agreements(a, b []int) int {
	count := 0
	for i, v := range a {
		if v == b[i] {
			count++
		}
	}
	return count
}
func sum64(values []int64) int64 {
	var total int64
	for _, v := range values {
		total += v
	}
	return total
}
func valueErrors(q [][4]int64, optimal []int64) []int64 {
	errors := make([]int64, len(q))
	for s, row := range q {
		errors[s] = abs(rowMax(row) - optimal[s])
	}
	return errors
}
func maxIndex(values []int64) int {
	best := 0
	for i, v := range values {
		if v > values[best] {
			best = i
		}
	}
	return best
}
func endingCounts(episodes []*Episode) [3]int {
	var counts [3]int
	for _, e := range episodes {
		for i, name := range endings {
			if e.Ending == name {
				counts[i]++
			}
		}
	}
	return counts
}

type Episode struct {
	Total  int64
	Steps  int
	Ending string
	Cells  []int
}
type BlockRecord struct {
	Agree, Coverage int
	Error           int64
}
type Learner struct {
	Method         string
	Environment    *Environment
	Settings       *Settings
	Generator      RandomGenerator
	Q, Visits      [][4]int64
	Model          *DynaModel
	Averages       *ReturnAverages
	Alpha, Epsilon int64
	Episodes       []*Episode
	Blocks         []BlockRecord
}

func newLearner(method string, e *Environment, s *Settings) *Learner {
	n := len(e.World.States)
	return &Learner{Method: method, Environment: e, Settings: s, Generator: RandomGenerator{s.Seed},
		Q: make([][4]int64, n), Visits: make([][4]int64, n), Model: newDynaModel(n), Averages: newReturnAverages(n)}
}
func (l *Learner) Policy() []int {
	p := make([]int, len(l.Q))
	for s, row := range l.Q {
		p[s] = firstMax(row)
	}
	return p
}
func (l *Learner) StateVisits() []int64 {
	counts := make([]int64, len(l.Visits))
	for s, row := range l.Visits {
		for _, v := range row {
			counts[s] += v
		}
	}
	return counts
}
func (l *Learner) Select(state int) int { return choose(&l.Generator, l.Q[state], l.Epsilon) }
func (l *Learner) Learn(optimal []int64, policy []int) {
	for ep := 1; ep <= l.Settings.Episodes; ep++ {
		l.Alpha = scheduleValue(l.Settings.Alpha, ep)
		l.Epsilon = scheduleValue(l.Settings.Epsilon, ep)
		l.Episodes = append(l.Episodes, l.Play())
		if ep%l.Settings.BlockSize == 0 {
			coverage := 0
			for _, v := range l.StateVisits() {
				if v > 0 {
					coverage++
				}
			}
			l.Blocks = append(l.Blocks, BlockRecord{agreements(l.Policy(), policy), coverage, floorDiv(sum64(valueErrors(l.Q, optimal)), int64(len(optimal)))})
		}
	}
}
func (l *Learner) Play() *Episode {
	w, s := l.Environment.World, l.Settings
	state := w.StartState
	ep := &Episode{Ending: "timeout", Cells: []int{w.Start}}
	history := []HistoryStep{}
	action := 0
	if l.Method == "sarsa" {
		action = l.Select(state)
	}
	for ep.Steps < s.StepLimit {
		if l.Method != "sarsa" {
			action = l.Select(state)
		}
		cell, reward := l.Environment.Step(&l.Generator, state, action)
		l.Visits[state][action]++
		ep.Total += reward
		ep.Steps++
		ep.Cells = append(ep.Cells, cell)
		next := w.StateIndex[cell]
		if l.Method == "mc" {
			history = append(history, HistoryStep{state, action, reward})
		} else {
			var future int64
			nextAction := action
			if next >= 0 {
				if l.Method == "sarsa" {
					nextAction = l.Select(next)
					future = l.Q[next][nextAction]
				} else if l.Method == "expected_sarsa" {
					future = expectedValue(l.Q[next], l.Epsilon)
				} else {
					future = rowMax(l.Q[next])
				}
			}
			tdUpdate(&l.Q[state], action, tdTarget(reward, next < 0, future, s.Gamma), l.Alpha)
			if l.Method == "dyna_q" {
				l.Model.Record(state, action, reward, next)
				l.Model.Plan(&l.Generator, l.Q, s.Gamma, l.Alpha, s.PlanningSteps)
			}
			action = nextAction
		}
		if next < 0 {
			ep.Ending = w.TerminalName(cell)
			break
		}
		state = next
	}
	if l.Method == "mc" {
		l.Averages.Update(l.Q, history, s.Gamma)
	}
	return ep
}
func (l *Learner) BlockEpisodes(number int) []*Episode {
	size := l.Settings.BlockSize
	return l.Episodes[(number-1)*size : number*size]
}
func (l *Learner) BlockReturns() []int64 {
	totals := make([]int64, len(l.Blocks))
	for i := range totals {
		for _, e := range l.BlockEpisodes(i + 1) {
			totals[i] += e.Total
		}
	}
	return totals
}
func nominalPath(e *Environment, policy []int, origin, limit int) (string, []int) {
	cells := []int{origin}
	seen := map[int]bool{origin: true}
	for {
		s := e.World.StateIndex[cells[len(cells)-1]]
		target := e.Moves[s][policy[s]]
		repeated := seen[target]
		cells = append(cells, target)
		seen[target] = true
		if e.World.IsTerminal(target) {
			return e.World.TerminalName(target), cells
		}
		if repeated {
			return "loop", cells
		}
		if len(cells)-1 == limit {
			return "limit", cells
		}
	}
}
func basinSymbols(e *Environment, policy []int, limit int) []string {
	symbols := []string{}
	for _, cell := range e.World.States {
		ending, path := nominalPath(e, policy, cell, limit)
		symbol := "*"
		if ending == "goal" || ending == "pit" {
			symbol = string(rune('a' + e.World.TerminalIndex[path[len(path)-1]]))
		}
		symbols = append(symbols, symbol)
	}
	return symbols
}
func riskyStates(e *Environment, policy []int) int {
	count := 0
	for s, a := range policy {
		for _, t := range e.Transitions[s][a] {
			if e.World.Kinds[t.Cell] == 'P' {
				count++
				break
			}
		}
	}
	return count
}
func distances(e *Environment) []int {
	w := e.World
	distance := make([]int, len(w.Kinds))
	for i := range distance {
		distance[i] = -1
	}
	distance[w.Start] = 0
	queue := []int{w.Start}
	for head := 0; head < len(queue); head++ {
		cell := queue[head]
		for _, ts := range e.Transitions[w.StateIndex[cell]] {
			for _, t := range ts {
				if distance[t.Cell] < 0 {
					distance[t.Cell] = distance[cell] + 1
					if !w.IsTerminal(t.Cell) {
						queue = append(queue, t.Cell)
					}
				}
			}
		}
	}
	return distance
}
func symmetry(w *World, values []int64, policy []int) (int, int, int) {
	pairs, equal, mirrored := 0, 0, 0
	mirrorActions := [4]int{0, 3, 2, 1}
	for s, cell := range w.States {
		col := cell % w.Cols
		mirrorCol := w.Cols - 1 - col
		other := w.StateIndex[cell/w.Cols*w.Cols+mirrorCol]
		if col < mirrorCol && other >= 0 {
			pairs++
			if values[s] == values[other] {
				equal++
			}
			if policy[other] == mirrorActions[policy[s]] {
				mirrored++
			}
		}
	}
	return pairs, equal, mirrored
}
func absorption(e *Environment, policy []int, limit int) [3]int64 {
	n := len(policy)
	goal, pit, expected := make([]int64, n), make([]int64, n), make([]int64, n)
	for range limit {
		ng, np, ne := make([]int64, n), make([]int64, n), make([]int64, n)
		for s, a := range policy {
			var g, p, t int64
			for _, tr := range e.Transitions[s][a] {
				target, m := e.World.StateIndex[tr.Cell], tr.Numerator
				if target >= 0 {
					g += m * goal[target]
					p += m * pit[target]
					t += m * expected[target]
				} else if e.World.Kinds[tr.Cell] == 'G' {
					g += m * absorptionUnit
				} else {
					p += m * absorptionUnit
				}
			}
			ng[s] = g / e.SlipTotal
			np[s] = p / e.SlipTotal
			ne[s] = absorptionUnit + t/e.SlipTotal
		}
		goal, pit, expected = ng, np, ne
	}
	s := e.World.StartState
	return [3]int64{goal[s], pit[s], expected[s]}
}
func behaviourValue(e *Environment, policy []int, epsilon, gamma, theta int64) (int64, int) {
	values := make([]int64, len(policy))
	for sweep := 1; ; sweep++ {
		var delta int64
		for s, chosen := range policy {
			var total int64
			for a, v := range actionValues(e, values, gamma, s) {
				weight := epsilon
				if a == chosen {
					weight += 4 * (1000 - epsilon)
				}
				total += weight * v
			}
			value := floorDiv(total, 4000)
			delta = max(delta, abs(value-values[s]))
			values[s] = value
		}
		if delta <= theta {
			return values[e.World.StartState], sweep
		}
	}
}

type RolloutSummary struct {
	Returns, Discounted, Steps []int64
	Endings                    []string
	TerminalCounts             []int
}

func performRollouts(e *Environment, policy []int, s *Settings) *RolloutSummary {
	w := e.World
	g := RandomGenerator{s.RolloutSeed}
	summary := &RolloutSummary{TerminalCounts: make([]int, len(w.Terminals))}
	for range s.Rollouts {
		state := w.StartState
		rewards := []int64{}
		ending := "timeout"
		for len(rewards) < s.StepLimit {
			cell, r := e.Step(&g, state, policy[state])
			rewards = append(rewards, r)
			state = w.StateIndex[cell]
			if state < 0 {
				ending = w.TerminalName(cell)
				summary.TerminalCounts[w.TerminalIndex[cell]]++
				break
			}
		}
		summary.Returns = append(summary.Returns, sum64(rewards))
		summary.Discounted = append(summary.Discounted, discountedReturn(rewards, s.Gamma))
		summary.Steps = append(summary.Steps, int64(len(rewards)))
		summary.Endings = append(summary.Endings, ending)
	}
	return summary
}

type PolicyEvaluation struct {
	Values                                                                     []int64
	Sweeps, Agree, OptimalActions, MaxGapState, ImprovedChanges, ImprovedAgree int
	MaxGap, ImprovedStart                                                      int64
	Absorption                                                                 [3]int64
	Rollouts                                                                   *RolloutSummary
}

func evaluate(x *Experiment, policy []int) *PolicyEvaluation {
	e, s := x.Environment, x.Settings
	values, sweeps := evaluatePolicy(e, policy, make([]int64, len(policy)), s.Gamma, s.Theta)
	v := &PolicyEvaluation{Values: values, Sweeps: sweeps, Agree: agreements(policy, x.OptimalPolicy)}
	gaps := make([]int64, len(policy))
	for state, a := range policy {
		for _, optimal := range x.OptimalActions[state] {
			if a == optimal {
				v.OptimalActions++
				break
			}
		}
		gaps[state] = x.OptimalValues[state] - values[state]
	}
	v.MaxGapState = maxIndex(gaps)
	v.MaxGap = gaps[v.MaxGapState]
	improved := greedyPolicy(e, values, s.Gamma)
	v.ImprovedChanges = len(policy) - agreements(improved, policy)
	improvedValues, _ := evaluatePolicy(e, improved, make([]int64, len(policy)), s.Gamma, s.Theta)
	v.ImprovedStart = improvedValues[e.World.StartState]
	v.ImprovedAgree = agreements(improved, x.OptimalPolicy)
	v.Absorption = absorption(e, policy, s.StepLimit)
	v.Rollouts = performRollouts(e, policy, s)
	return v
}

type Experiment struct {
	World                                   *World
	Settings                                *Settings
	Environment                             *Environment
	OptimalValues, Changes, IterationValues []int64
	OptimalQ                                [][4]int64
	OptimalPolicy, IterationPolicy          []int
	OptimalActions                          [][]int
	InPlaceSweeps                           int
	Rounds                                  []PolicyRound
	Learners                                []*Learner
	Policies                                [][]int
	Evaluations                             []*PolicyEvaluation
}

func newExperiment(w *World, s *Settings) *Experiment {
	x := &Experiment{World: w, Settings: s}
	x.Environment = x.EnvironmentWith(s.FloorSlip, s.IceSlip)
	e := x.Environment
	x.OptimalValues, x.Changes = valueIteration(e, s.Gamma, s.Theta)
	for state := range w.States {
		row := actionValues(e, x.OptimalValues, s.Gamma, state)
		x.OptimalQ = append(x.OptimalQ, row)
		x.OptimalPolicy = append(x.OptimalPolicy, firstMax(row))
		actions := []int{}
		for a, v := range row {
			if v == rowMax(row) {
				actions = append(actions, a)
			}
		}
		x.OptimalActions = append(x.OptimalActions, actions)
	}
	_, x.InPlaceSweeps = inPlaceValueIteration(e, s.Gamma, s.Theta)
	x.IterationPolicy, x.IterationValues, x.Rounds = policyIteration(e, s.Gamma, s.Theta)
	x.Policies = [][]int{x.OptimalPolicy, x.IterationPolicy}
	for _, method := range methods {
		l := newLearner(method, e, s)
		l.Learn(x.OptimalValues, x.OptimalPolicy)
		x.Learners = append(x.Learners, l)
		x.Policies = append(x.Policies, l.Policy())
	}
	for _, p := range x.Policies {
		x.Evaluations = append(x.Evaluations, evaluate(x, p))
	}
	return x
}
func (x *Experiment) EnvironmentWith(floor, ice int64) *Environment {
	s := x.Settings
	return newEnvironment(x.World, s.StepReward, s.SlipTotal, floor, ice)
}
func (x *Experiment) StateText(state int) string { return cellText(x.World, x.World.States[state]) }
func (x *Experiment) Sensitivity(e *Environment, gamma int64) string {
	v, changes := valueIteration(e, gamma, x.Settings.Theta)
	p := greedyPolicy(e, v, gamma)
	ending, path := nominalPath(e, p, x.World.Start, x.Settings.StepLimit)
	return fmt.Sprintf("iterations %d value_start %s path %s steps %d last %s differences %d", len(changes),
		fixedText(v[x.World.StartState]), ending, len(path)-1, cellText(x.World, path[len(path)-1]),
		len(p)-agreements(p, x.OptimalPolicy))
}
func (x *Experiment) ValuesReport() []string {
	w, s := x.World, x.Settings
	d := distances(x.Environment)
	reachable := 0
	for _, cell := range w.States {
		if d[cell] >= 0 {
			reachable++
		}
	}
	world := []string{fmt.Sprintf("world rows %d cols %d states %d walls %d floor %d ice %d goals %d pits %d",
		w.Rows, w.Cols, len(w.States), strings.Count(w.Kinds, "#"), strings.Count(w.Kinds, ".")+strings.Count(w.Kinds,
			"S"), strings.Count(w.Kinds, "~"), strings.Count(w.Kinds, "G"), strings.Count(w.Kinds, "P")),
		fmt.Sprintf("start %s reachable %d", cellText(w, w.Start), reachable)}
	for i, cell := range w.Terminals {
		distance := "-"
		if d[cell] >= 0 {
			distance = fmt.Sprint(d[cell])
		}
		world = append(world, fmt.Sprintf("terminal %s %s reward %d distance %s", cellText(w, cell), w.TerminalName(cell), w.Rewards[i], distance))
	}
	vi := []string{fmt.Sprintf("value_iteration gamma %d theta %s iterations %d", s.Gamma, fixedText(s.Theta), len(x.Changes))}
	for i, v := range x.Changes {
		vi = append(vi, fmt.Sprintf("iteration %d max_change %s", i+1, fixedText(v)))
	}
	sizes := []string{}
	ties := []string{}
	for state, actions := range x.OptimalActions {
		sizes = append(sizes, fmt.Sprint(len(actions)))
		if len(actions) > 1 {
			letters := ""
			for _, a := range actions {
				letters += string(actionLetters[a])
			}
			ties = append(ties, fmt.Sprintf("tie %s %s", x.StateText(state), letters))
		}
	}
	ties = append([]string{fmt.Sprintf("ties %d", len(ties))}, ties...)
	pairs, equal, mirrored := symmetry(w, x.OptimalValues, x.OptimalPolicy)
	ties = append(ties, fmt.Sprintf("symmetry pairs %d equal_values %d mirrored_actions %d", pairs, equal, mirrored))
	pi := []string{fmt.Sprintf("policy_iteration rounds %d", len(x.Rounds))}
	totalSweeps := 0
	for i, r := range x.Rounds {
		totalSweeps += r.Sweeps
		pi = append(pi, fmt.Sprintf("round %d sweeps %d changed %d value_start %s", i+1, r.Sweeps, r.Changes, fixedText(r.StartValue)))
	}
	differences := make([]int64, len(w.States))
	for i, v := range x.IterationValues {
		differences[i] = abs(v - x.OptimalValues[i])
	}
	largest := maxIndex(differences)
	n := len(w.States)
	comparison := []string{fmt.Sprintf("comparison policy_differences %d max_value_difference %s at %s",
		n-agreements(x.IterationPolicy, x.OptimalPolicy), fixedText(differences[largest]), x.StateText(largest)),
		fmt.Sprintf("backups value_iteration %d in_place_iterations %d in_place %d policy_iteration %d",
			len(x.Changes)*n*4, x.InPlaceSweeps, x.InPlaceSweeps*n*4, totalSweeps*n+len(x.Rounds)*n*4)}
	gamma := []string{"gamma_sweep"}
	for _, g := range s.GammaSweep {
		gamma = append(gamma, fmt.Sprintf("gamma %d %s", g, x.Sensitivity(x.Environment, int64(g))))
	}
	slip := []string{"slip_sweep"}
	for _, p := range s.SlipSweep {
		slip = append(slip, fmt.Sprintf("slip %d %d %s", p[0], p[1], x.Sensitivity(x.EnvironmentWith(int64(p[0]), int64(p[1])), s.Gamma)))
	}
	return joinParts([][]string{world, vi, append([]string{"optimal_values"}, valueGrid(w, x.OptimalValues)...),
		append([]string{"optimal_action_counts"}, gridLines(w, sizes, "")...), ties, pi, append([]string{"policy_iteration_values"},
			valueGrid(w, x.IterationValues)...), comparison, gamma, slip})
}
func (x *Experiment) PoliciesReport() []string {
	parts := [][]string{}
	for i, policy := range x.Policies {
		ending, path := nominalPath(x.Environment, policy, x.World.Start, x.Settings.StepLimit)
		counts := [4]int{}
		for _, a := range policy {
			counts[a]++
		}
		lines := append([]string{policyNames[i]}, policyGrid(x.World, policy)...)
		lines = append(lines, fmt.Sprintf("path %s steps %d %s", ending, len(path)-1, cellsText(x.World,
			path)), fmt.Sprintf("actions N %d E %d S %d W %d risk %d", counts[0], counts[1], counts[2],
			counts[3], riskyStates(x.Environment, policy)), "basins")
		lines = append(lines, gridLines(x.World, basinSymbols(x.Environment, policy, x.Settings.StepLimit), "")...)
		if i >= 2 {
			digits := []string{}
			for _, v := range x.Learners[i-2].StateVisits() {
				text := "0"
				if v > 0 {
					text = fmt.Sprint(len(fmt.Sprint(v)))
				}
				digits = append(digits, text)
			}
			lines = append(lines, "visits")
			lines = append(lines, gridLines(x.World, digits, "")...)
		}
		parts = append(parts, lines)
	}
	return joinParts(parts)
}
func (x *Experiment) QTable() []string {
	lines := []string{"method,row,col,action,value,visits"}
	lines = append(lines, qTableRows(x.World, "value_iteration", x.OptimalQ, nil)...)
	for _, l := range x.Learners {
		lines = append(lines, qTableRows(x.World, l.Method, l.Q, l.Visits)...)
	}
	return lines
}
func episodeTotals(episodes []*Episode) (int64, int64) {
	var total, steps int64
	for _, e := range episodes {
		total += e.Total
		steps += int64(e.Steps)
	}
	return total, steps
}
func (x *Experiment) LearningCurves() []string {
	lines := []string{"method,block,mean_return,mean_steps,goals,pits,timeouts,agree,value_error,coverage"}
	for _, l := range x.Learners {
		for i, b := range l.Blocks {
			eps := l.BlockEpisodes(i + 1)
			total, steps := episodeTotals(eps)
			c := endingCounts(eps)
			lines = append(lines, fmt.Sprintf("%s,%d,%s,%s,%d,%d,%d,%d,%s,%d", l.Method, i+1, averageText(total,
				len(eps)), averageText(steps, len(eps)), c[0], c[1], c[2], b.Agree, fixedText(b.Error),
				b.Coverage))
		}
	}
	return lines
}
func (x *Experiment) EvaluationReport() []string {
	n, s := len(x.World.States), x.Settings
	summary := []string{fmt.Sprintf("summary states %d start %s rollouts %d step_limit %d", n, cellText(x.World, x.World.Start), s.Rollouts, s.StepLimit)}
	values := []string{"policies", "policy agree optimal_actions value_start sweeps max_gap at"}
	improvement := []string{"improvement", "policy changed value_start agree"}
	absorb := []string{"absorption", "policy p_goal p_pit p_timeout expected_steps"}
	rollouts := []string{"rollouts", "policy mean_return mean_discounted mean_steps goals pits timeouts min median max"}
	terminals := []string{"terminals", "policy " + cellsText(x.World, x.World.Terminals)}
	agreement := []string{"agreement", "policy " + strings.Join(policyNames, " ")}
	for i, v := range x.Evaluations {
		name := policyNames[i]
		values = append(values, fmt.Sprintf("%s %d %d %s %d %s %s", name, v.Agree, v.OptimalActions, fixedText(v.Values[x.World.StartState]),
			v.Sweeps, fixedText(v.MaxGap), x.StateText(v.MaxGapState)))
		improvement = append(improvement, fmt.Sprintf("%s %d %s %d", name, v.ImprovedChanges, fixedText(v.ImprovedStart), v.ImprovedAgree))
		a := v.Absorption
		absorb = append(absorb, fmt.Sprintf("%s %s %s %s %s", name, fixedText(a[0]/10000), fixedText(a[1]/10000),
			fixedText((absorptionUnit-a[0]-a[1])/10000), fixedText(a[2]/10000)))
		r := v.Rollouts
		ordered := append([]int64(nil), r.Returns...)
		sort.Slice(ordered, func(i, j int) bool { return ordered[i] < ordered[j] })
		c := [3]int{}
		for _, ending := range r.Endings {
			for j, e := range endings {
				if ending == e {
					c[j]++
				}
			}
		}
		rollouts = append(rollouts, fmt.Sprintf("%s %s %s %s %d %d %d %d %d %d", name, averageText(sum64(r.Returns),
			s.Rollouts), fixedText(floorDiv(sum64(r.Discounted), int64(s.Rollouts))), averageText(sum64(r.Steps),
			s.Rollouts), c[0], c[1], c[2], ordered[0], ordered[(s.Rollouts+1)/2-1], ordered[len(ordered)-1]))
		counts := []string{name}
		for _, v := range r.TerminalCounts {
			counts = append(counts, fmt.Sprint(v))
		}
		terminals = append(terminals, strings.Join(counts, " "))
		counts = []string{name}
		for _, other := range x.Policies {
			counts = append(counts, fmt.Sprint(agreements(x.Policies[i], other)))
		}
		agreement = append(agreement, strings.Join(counts, " "))
	}
	behaviour := []string{"behaviour", "method epsilon value_start sweeps"}
	qErrors := []string{"q_errors", "method mean_abs max_abs at unvisited tied"}
	actionErrors := []string{"q_action_errors", "method N E S W"}
	training := []string{"training", "method steps goals pits timeouts best_block best_mean last_mean reach"}
	visited := []string{"visited"}
	last := []string{"last_episodes"}
	phases := []string{"phases"}
	epsilon := scheduleValue(s.Epsilon, s.Episodes)
	optimalReturn := sum64(x.Evaluations[0].Rollouts.Returns)
	for _, l := range x.Learners {
		policy := l.Policy()
		value, sweeps := behaviourValue(x.Environment, policy, epsilon, s.Gamma, s.Theta)
		behaviour = append(behaviour, fmt.Sprintf("%s %d %s %d", l.Method, epsilon, fixedText(value), sweeps))
		errors := valueErrors(l.Q, x.OptimalValues)
		largest := maxIndex(errors)
		unvisited, tied := 0, 0
		visits := l.StateVisits()
		for state, row := range l.Q {
			if visits[state] == 0 {
				unvisited++
			}
			count := 0
			for _, v := range row {
				if v == rowMax(row) {
					count++
				}
			}
			if count > 1 {
				tied++
			}
		}
		qErrors = append(qErrors, fmt.Sprintf("%s %s %s %s %d %d", l.Method, fixedText(sum64(errors)/int64(n)),
			fixedText(errors[largest]), x.StateText(largest), unvisited, tied))
		fields := []string{l.Method}
		for a := range 4 {
			var total, count int64
			for state, row := range l.Q {
				if l.Visits[state][a] > 0 {
					total += abs(row[a] - x.OptimalQ[state][a])
					count++
				}
			}
			text := "-"
			if count > 0 {
				text = fixedText(total / count)
			}
			fields = append(fields, text)
		}
		actionErrors = append(actionErrors, strings.Join(fields, " "))
		c := endingCounts(l.Episodes)
		_, steps := episodeTotals(l.Episodes)
		totals := l.BlockReturns()
		best := maxIndex(totals)
		reach := "-"
		for i, total := range totals {
			if 10*int64(s.Rollouts)*total >= 9*int64(s.BlockSize)*optimalReturn {
				reach = fmt.Sprint(i + 1)
				break
			}
		}
		training = append(training, fmt.Sprintf("%s %d %d %d %d %d %s %s %s", l.Method, steps, c[0], c[1],
			c[2], best+1, averageText(totals[best], s.BlockSize), averageText(totals[len(totals)-1],
				s.BlockSize), reach))
		order := make([]int, n)
		for i := range order {
			order[i] = i
		}
		sort.Slice(order, func(i, j int) bool {
			a, b := order[i], order[j]
			if visits[a] != visits[b] {
				return visits[a] > visits[b]
			}
			return a < b
		})
		fields = []string{l.Method}
		for _, state := range order[:min(3, n)] {
			fields = append(fields, fmt.Sprintf("%s:%d", x.StateText(state), visits[state]))
		}
		visited = append(visited, strings.Join(fields, " "))
		episode := l.Episodes[len(l.Episodes)-1]
		last = append(last, fmt.Sprintf("%s return %d steps %d end %s %s", l.Method, episode.Total, episode.Steps, episode.Ending, cellsText(x.World, episode.Cells)))
		for _, p := range phaseRanges(s) {
			eps := l.Episodes[p[0]-1 : p[1]]
			total, steps := episodeTotals(eps)
			c := endingCounts(eps)
			phases = append(phases, fmt.Sprintf("%s %d-%d alpha %d epsilon %d mean_return %s mean_steps %s goals %d",
				l.Method, p[0], p[1], scheduleValue(s.Alpha, p[0]), scheduleValue(s.Epsilon, p[0]),
				averageText(total, len(eps)), averageText(steps, len(eps)), c[0]))
		}
	}
	return joinParts([][]string{summary, values, improvement, absorb, behaviour, qErrors, actionErrors,
		rollouts, terminals, agreement, training, visited, last, phases})
}
func main() {
	x := newExperiment(readWorld(), readSettings())
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	writeLines("values.txt", x.ValuesReport())
	writeLines("policies.txt", x.PoliciesReport())
	writeLines("q_tables.csv", x.QTable())
	writeLines("learning_curves.csv", x.LearningCurves())
	writeLines("evaluation.txt", x.EvaluationReport())
}
