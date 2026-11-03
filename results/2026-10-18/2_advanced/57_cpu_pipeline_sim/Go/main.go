package main

import (
	"fmt"
	"sort"
	"strings"
)

var classes = []string{"ALU", "MUL", "LOAD", "STORE", "BRANCH", "JUMP", "NOP"}
var causes = []string{"control", "structural", "load_use", "raw"}
var stages = []string{"IF", "ID", "EX", "MEM", "WB"}

type Rejection struct {
	Line   int
	Reason string
}
type Gap struct{ Line, Expected, Found int }
type Trace struct {
	Lines        int
	Instructions []Instruction
	Rejected     []Rejection
	Gaps         []Gap
	Static       map[int][]int
	PCs          []int
}
type Prediction struct {
	Next  int
	Wrong bool
	Kind  int
}
type PredictionResult struct {
	Config                                                  PredictorConfig
	Predictions                                             []Prediction
	Control, Wrong, Branches, Jumps, BranchWrong, JumpWrong int
	Kinds                                                   [3]int
	PCWrong                                                 map[int]int
	BTBHits, RASPredictions, RASCorrect, Calls, Returns     int
}

func sumInts(a []int) int {
	s := 0
	for _, v := range a {
		s += v
	}
	return s
}
func traceCheck() Trace {
	lines := readLines("input/trace.txt")
	out := Trace{Lines: len(lines), Static: map[int][]int{}}
	first := map[int]Instruction{}
	classSet := map[string]bool{}
	for _, c := range classes {
		classSet[c] = true
	}
	for line, text := range lines {
		a := strings.Split(text, " ")
		reason := ""
		ins := Instruction{Line: line + 1}
		if len(a) != 8 {
			reason = "fields"
		} else {
			for _, s := range a {
				if s == "" {
					reason = "fields"
					break
				}
			}
		}
		if reason == "" {
			var ok bool
			ins.PC, ok = hexValue(a[0])
			if !ok || ins.PC%4 != 0 {
				reason = "pc"
			}
		}
		if reason == "" {
			ins.Class = a[1]
			if !classSet[ins.Class] {
				reason = "class"
			}
		}
		if reason == "" {
			rd, rdOK := register(a[2])
			rs1, s1OK := register(a[3])
			rs2, s2OK := register(a[4])
			ins.RD, ins.RS1, ins.RS2 = rd, rs1, rs2
			if !rdOK || !s1OK || !s2OK {
				reason = "register"
			}
		}
		if reason == "" {
			d, s1, s2 := ins.RD >= 0, ins.RS1 >= 0, ins.RS2 >= 0
			valid := false
			switch ins.Class {
			case "ALU":
				valid = d && s1
			case "MUL":
				valid = d && s1 && s2
			case "LOAD":
				valid = d && s1 && !s2
			case "STORE":
				valid = !d && s1 && s2
			case "BRANCH":
				valid = !d && s1
			case "JUMP":
				valid = !s2
			case "NOP":
				valid = !d && !s1 && !s2
			}
			if !valid {
				reason = "operands"
			}
		}
		if reason == "" {
			valid := a[5] == "-"
			if ins.Class == "BRANCH" {
				valid = a[5] == "T" || a[5] == "N"
			} else if ins.Class == "JUMP" {
				valid = a[5] == "T"
			}
			if !valid {
				reason = "taken"
			}
			ins.Taken = a[5] == "T"
		}
		if reason == "" {
			if ins.control() {
				v, ok := hexValue(a[6])
				ins.Target = v
				if !ok || v%4 != 0 || v == ins.PC+4 {
					reason = "target"
				}
			} else if a[6] != "-" {
				reason = "target"
			}
		}
		if reason == "" {
			if ins.Class == "LOAD" || ins.Class == "STORE" {
				v, ok := hexValue(a[7])
				ins.Address = v
				if !ok || v%4 != 0 {
					reason = "address"
				}
			} else if a[7] != "-" {
				reason = "address"
			}
		}
		if reason == "" {
			if old, ok := first[ins.PC]; ok {
				if ins.Class != old.Class || ins.RD != old.RD || ins.RS1 != old.RS1 || ins.RS2 != old.RS2 || ((ins.Class == "BRANCH" || (ins.Class == "JUMP" && ins.RS1 < 0)) && ins.Target != old.Target) {
					reason = "conflict"
				}
			}
		}
		if reason != "" {
			out.Rejected = append(out.Rejected, Rejection{line + 1, reason})
			continue
		}
		if _, ok := first[ins.PC]; !ok {
			first[ins.PC] = ins
			out.PCs = append(out.PCs, ins.PC)
		}
		n := len(out.Instructions)
		if n > 0 {
			expected := out.Instructions[n-1].nextPC()
			if ins.PC != expected {
				out.Gaps = append(out.Gaps, Gap{line + 1, expected, ins.PC})
			}
		}
		out.Static[ins.PC] = append(out.Static[ins.PC], n)
		out.Instructions = append(out.Instructions, ins)
	}
	sort.Ints(out.PCs)
	dependences(out.Instructions)
	return out
}
func predict(a []Instruction, c Config, p PredictorConfig) PredictionResult {
	out := PredictionResult{Config: p, Predictions: make([]Prediction, len(a)), PCWrong: map[int]int{}}
	btb, ras, d := newBTB(c.BTB), &RAS{Depth: c.RAS}, newDirection(p)
	for i, ins := range a {
		if !ins.control() {
			continue
		}
		out.Control++
		if ins.Class == "BRANCH" {
			out.Branches++
		} else {
			out.Jumps++
		}
		candidate, has := btb.lookup(ins.PC)
		if has {
			out.BTBHits++
		}
		if ins.Class == "JUMP" && ins.RD < 0 && ins.RS1 == 31 {
			out.Returns++
			if v, ok := ras.pop(); ok {
				candidate, has = v, true
				out.RASPredictions++
				if v == ins.Target {
					out.RASCorrect++
				}
			}
		}
		if ins.Class == "JUMP" && ins.RD == 31 {
			out.Calls++
			ras.push(ins.PC + 4)
		}
		direction := false
		if ins.Class == "BRANCH" {
			direction = d.predict(ins)
		}
		next := ins.PC + 4
		if p.Scheme == "PERFECT" {
			next = ins.nextPC()
		} else if has && (ins.Class == "JUMP" || direction) {
			next = candidate
		}
		wrong := next != ins.nextPC()
		kind := -1
		if wrong {
			if ins.Class == "BRANCH" && direction != ins.Taken {
				kind = 0
			} else if !has {
				kind = 1
			} else {
				kind = 2
			}
			out.Wrong++
			out.Kinds[kind]++
			out.PCWrong[ins.PC]++
			if ins.Class == "BRANCH" {
				out.BranchWrong++
			} else {
				out.JumpWrong++
			}
		}
		out.Predictions[i] = Prediction{next, wrong, kind}
		if ins.Class == "BRANCH" {
			d.update(ins)
		}
		if ins.Taken {
			btb.insert(ins.PC, ins.Target)
		}
	}
	return out
}
func rows(a []Instruction, v Variant, p PredictionResult, run Run) []DiagramRow {
	out := []DiagramRow{}
	annotations := make([]string, len(a))
	for _, s := range run.Stalls {
		if s.Waiting >= 0 {
			annotations[s.Waiting] += fmt.Sprintf(" %s %d", causes[s.Cause], s.Cycles)
		}
	}
	for i, ins := range a {
		t := run.Timings[i]
		annotation := annotations[i]
		if p.Predictions[i].Wrong {
			annotation += " mispredict " + []string{"direction", "btb_miss", "wrong_target"}[p.Predictions[i].Kind]
		}
		out = append(out, DiagramRow{i, ins.PC, ins.Class, false, []Span{{t.F, t.F, 'F', 0}, {t.F + 1, t.D - 1,
			'*', 0}, {t.D, t.D, 'D', 1}, {t.D + 1, t.X - 1, '*', 1}, {t.X, t.M - 1, 'X', 2}, {t.M,
			t.M, 'M', 3}, {t.W, t.W, 'W', 4}}, annotation})
		if !p.Predictions[i].Wrong {
			continue
		}
		first := DiagramRow{PC: p.Predictions[i].Next, Wrong: true, Spans: []Span{{t.D, t.D, 'F', 0}, {t.D + 1, t.X - 1, '*', 0}}}
		if idResolved(ins, v) {
			first.Spans = append(first.Spans, Span{t.X, t.X, 'x', -1})
			out = append(out, first)
		} else {
			first.Spans = append(first.Spans, Span{t.X, t.X, 'D', 1}, Span{t.X + 1, t.X + 1, 'x', -1})
			out = append(out, first, DiagramRow{PC: first.PC + 4, Wrong: true, Spans: []Span{{t.X, t.X, 'F', 0}, {t.X + 1, t.X + 1, 'x', -1}}})
		}
	}
	return out
}
func pipelineOutput(c Config, run Run, diagram []DiagramRow) {
	lines := []string{fmt.Sprintf("pipeline variant=%s predictor=%s cycles %d-%d", c.PrimaryVariant,
		c.PrimaryPredictor, c.Start, c.End), "cycle" + strings.Repeat(" ", 18) + cycleDigits(c.Start,
		c.End)}
	count, stars, flush := 0, 0, 0
	contents := make([][5]string, c.End-c.Start+1)
	for i := range contents {
		for j := 0; j < 5; j++ {
			contents[i][j] = "."
		}
	}
	for _, row := range diagram {
		text, visible, s, f := row.render(c.Start, c.End)
		if visible {
			lines = append(lines, text)
			count++
			stars += s
			flush += f
		}
		id := fmt.Sprint(row.Instruction + 1)
		if row.Wrong {
			id = "w"
		}
		for _, span := range row.Spans {
			if span.Stage < 0 {
				continue
			}
			for cycle := max(c.Start, span.First); cycle <= min(c.End, span.Last); cycle++ {
				contents[cycle-c.Start][span.Stage] = id
			}
		}
	}
	completed := 0
	for _, t := range run.Timings {
		if t.W >= c.Start && t.W <= c.End {
			completed++
		}
	}
	lines = append(lines, fmt.Sprintf("rows %d completed %d stall_cells %d flushed %d", count, completed, stars, flush), "", "stages", "cycle IF ID EX MEM WB")
	for i, row := range contents {
		lines = append(lines, fmt.Sprint(c.Start+i, " ", strings.Join(row[:], " ")))
	}
	writeLines("pipeline.txt", lines)
}

type DependencyKey struct{ Producer, Waiting, Cause int }
type DependencyGroup struct {
	Key            DependencyKey
	Cycles, Events int
}
type Combination struct {
	Variant, Predictor int
	Run                Run
}

func statsOutput(trace Trace, c Config, predictions []PredictionResult, runs [][]Run, pv, pp int, diagram []DiagramRow) {
	a := trace.Instructions
	n := len(a)
	v, pr, run := c.Variants[pv], predictions[pp], runs[pv][pp]
	parts := [][]string{}
	input := []string{fmt.Sprintf("input lines %d accepted %d rejected %d gaps %d", trace.Lines, n, len(trace.Rejected), len(trace.Gaps))}
	for _, r := range trace.Rejected {
		input = append(input, fmt.Sprintf("reject line %d %s", r.Line, r.Reason))
	}
	for _, g := range trace.Gaps {
		input = append(input, fmt.Sprintf("gap line %d expected %s found %s", g.Line, hex(g.Expected), hex(g.Found)))
	}
	parts = append(parts, input)
	mix := map[string]int{}
	taken, backward, indirect, link, staticBranches, staticJumps, sources, produced := 0, 0, 0, 0, 0, 0, 0, 0
	distances := [5]int{}
	addresses := map[int]bool{}
	for _, ins := range a {
		mix[ins.Class]++
		if ins.Class == "BRANCH" {
			if ins.Taken {
				taken++
			}
			if ins.Target < ins.PC {
				backward++
			}
		}
		if ins.Class == "JUMP" {
			if ins.RS1 >= 0 {
				indirect++
			}
			if ins.RD >= 0 {
				link++
			}
		}
		if ins.Class == "LOAD" || ins.Class == "STORE" {
			addresses[ins.Address] = true
		}
	}
	for _, pc := range trace.PCs {
		ins := a[trace.Static[pc][0]]
		if ins.Class == "BRANCH" {
			staticBranches++
		}
		if ins.Class == "JUMP" {
			staticJumps++
		}
	}
	for i, ins := range a {
		for _, s := range ins.Sources {
			sources++
			if s.Producer >= 0 {
				produced++
				distances[min(5, i-s.Producer)-1]++
			}
		}
	}
	mixLine := "mix"
	for _, cl := range classes {
		mixLine += fmt.Sprintf(" %s %d", cl, mix[cl])
	}
	parts = append(parts, []string{"trace", fmt.Sprint("instructions ", n), fmt.Sprint("static_instructions ",
		len(trace.PCs)), mixLine, fmt.Sprintf("branches %d taken %d backward %d", mix["BRANCH"],
		taken, backward), fmt.Sprintf("jumps %d indirect %d link %d", mix["JUMP"], indirect, link),
		fmt.Sprintf("static_control branches %d jumps %d", staticBranches, staticJumps), fmt.Sprintf("memory loads %d stores %d distinct_addresses %d",
			mix["LOAD"], mix["STORE"], len(addresses)), fmt.Sprintf("operands %d with_producer %d distance 1 %d 2 %d 3 %d 4 %d 5+ %d",
			sources, produced, distances[0], distances[1], distances[2], distances[3], distances[4])})
	pl := []string{"prediction"}
	for _, p := range predictions {
		pl = append(pl, fmt.Sprintf("%s %s bits %d control %d mispredicted %d accuracy %s branches %s jumps %s direction %d btb_miss %d wrong_target %d",
			p.Config.Name, p.Config.Scheme, storage(p.Config), p.Control, p.Wrong, percent(p.Control-p.Wrong,
				p.Control), percent(p.Branches-p.BranchWrong, p.Branches), percent(p.Jumps-p.JumpWrong,
				p.Jumps), p.Kinds[0], p.Kinds[1], p.Kinds[2]))
	}
	first := predictions[0]
	pl = append(pl, fmt.Sprintf("btb entries %d lookups %d hits %d misses %d", c.BTB, first.Control,
		first.BTBHits, first.Control-first.BTBHits), fmt.Sprintf("ras depth %d calls %d returns %d predicted %d correct %d",
		c.RAS, first.Calls, first.Returns, first.RASPredictions, first.RASCorrect))
	parts = append(parts, pl)
	sum := sumInts(run.Totals[:])
	lengths := [5]int{}
	for i := 1; i < n; i++ {
		g := run.Timings[i].X - run.Timings[i-1].X - 1
		if g > 0 {
			lengths[min(5, g)-1]++
		}
	}
	finish := make([]int, n)
	height := 0
	for i, ins := range a {
		start := 0
		for _, source := range ins.Sources {
			if source.Producer >= 0 {
				start = max(start, finish[source.Producer])
			}
		}
		latency := 1
		if ins.Class == "LOAD" {
			latency = 2
		} else if ins.Class == "MUL" {
			latency = v.Latency
		}
		finish[i] = start + latency
		height = max(height, finish[i])
	}
	forward := "off"
	if v.Forward {
		forward = "on"
	}
	parts = append(parts, []string{fmt.Sprintf("timing variant=%s predictor=%s", v.Name, pr.Config.Name),
		fmt.Sprintf("forwarding %s branch_stage %s mul_latency %d", forward, v.Stage, v.Latency),
		fmt.Sprint("cycles ", run.Cycles), fmt.Sprintf("cpi %s %s", fraction(run.Cycles, n), decimal(run.Cycles,
			n)), fmt.Sprint("ipc ", decimal(n, run.Cycles)), fmt.Sprintf("stall_cycles total %d control %d structural %d load_use %d raw %d",
			sum, run.Totals[0], run.Totals[1], run.Totals[2], run.Totals[3]), fmt.Sprintf("stall_events control %d structural %d load_use %d raw %d",
			run.Events[0], run.Events[1], run.Events[2], run.Events[3]), fmt.Sprint("flushed ", run.Refetch),
		fmt.Sprintf("cycle_check %d + 4 + %d = %d", n, sum, n+4+sum), fmt.Sprintf("cpi_stack base 1.0000 fill %s control %s structural %s load_use %s raw %s",
			decimal(4, n), decimal(run.Totals[0], n), decimal(run.Totals[1], n), decimal(run.Totals[2],
				n), decimal(run.Totals[3], n)), fmt.Sprintf("stall_lengths 1 %d 2 %d 3 %d 4 %d 5+ %d", lengths[0],
			lengths[1], lengths[2], lengths[3], lengths[4]), fmt.Sprintf("dataflow height %d ilp %s",
			height, decimal(n, height))})
	what := []string{"whatif"}
	names := []string{"perfect_prediction", "single_cycle_mul", "forwarding_on", "branch_stage_EX"}
	if v.Forward {
		names[2] = "forwarding_off"
	}
	if v.Stage == "EX" {
		names[3] = "branch_stage_ID"
	}
	for i, name := range names {
		variant, flags := v, pr.Predictions
		switch i {
		case 0:
			flags = make([]Prediction, n)
		case 1:
			variant.Latency = 1
		case 2:
			variant.Forward = !v.Forward
		case 3:
			if v.Stage == "EX" {
				variant.Stage = "ID"
			} else {
				variant.Stage = "EX"
			}
		}
		cycles := simulate(a, variant, flags).Cycles
		what = append(what, fmt.Sprintf("%s cycles %d saved %d speedup %s", name, cycles, run.Cycles-cycles, decimal(run.Cycles, cycles)))
	}
	parts = append(parts, what)
	classStalls := map[string]int{}
	hot := map[int][4]int{}
	dependencies := map[DependencyKey]*DependencyGroup{}
	for _, s := range run.Stalls {
		ins := a[s.Responsible]
		classStalls[ins.Class] += s.Cycles
		counts := hot[ins.PC]
		counts[s.Cause] += s.Cycles
		hot[ins.PC] = counts
		if s.Cause >= 2 {
			key := DependencyKey{a[s.Producer].PC, a[s.Waiting].PC, s.Cause}
			if dependencies[key] == nil {
				dependencies[key] = &DependencyGroup{Key: key}
			}
			dependencies[key].Cycles += s.Cycles
			dependencies[key].Events++
		}
	}
	cl := []string{"classes"}
	for _, name := range classes {
		rate := "-"
		if mix[name] > 0 {
			rate = decimal(classStalls[name], mix[name])
		}
		cl = append(cl, fmt.Sprintf("%s count %d stall_cycles %d per_instruction %s", name, mix[name], classStalls[name], rate))
	}
	parts = append(parts, cl)
	paths := [3]int{}
	for i, ins := range a {
		for _, source := range ins.Sources {
			paths[forwardingPath(i, ins, source, run.Timings, v)]++
		}
	}
	parts = append(parts, []string{fmt.Sprintf("forwarding regfile %d ex_mem %d mem_wb %d", paths[0], paths[1], paths[2])})
	occupancy := [5][2]int{}
	for _, row := range diagram {
		kind := 0
		if row.Wrong {
			kind = 1
		}
		for _, span := range row.Spans {
			if span.Stage >= 0 && span.Last >= span.First {
				occupancy[span.Stage][kind] += span.Last - span.First + 1
			}
		}
	}
	occ := []string{fmt.Sprint("occupancy cycles ", run.Cycles)}
	for i, name := range stages {
		correct, wrong := occupancy[i][0], occupancy[i][1]
		occ = append(occ, fmt.Sprintf("%s correct %d wrong %d idle %d busy %s", name, correct, wrong, run.Cycles-correct-wrong, percent(correct+wrong, run.Cycles)))
	}
	parts = append(parts, occ)
	hotPCs := []int{}
	for pc := range hot {
		hotPCs = append(hotPCs, pc)
	}
	sort.Slice(hotPCs, func(i, j int) bool {
		ci, cj := hot[hotPCs[i]], hot[hotPCs[j]]
		si, sj := sumInts(ci[:]), sumInts(cj[:])
		if si != sj {
			return si > sj
		}
		return hotPCs[i] < hotPCs[j]
	})
	hl := []string{"hotspots"}
	for rank, pc := range hotPCs[:min(c.Top, len(hotPCs))] {
		t := hot[pc]
		hl = append(hl, fmt.Sprintf("%d %s %s stall_cycles %d control %d structural %d load_use %d raw %d",
			rank+1, hex(pc), a[trace.Static[pc][0]].Class, sumInts(t[:]), t[0], t[1], t[2], t[3]))
	}
	parts = append(parts, hl)
	groups := []*DependencyGroup{}
	for _, g := range dependencies {
		groups = append(groups, g)
	}
	sort.Slice(groups, func(i, j int) bool {
		x, y := groups[i], groups[j]
		if x.Cycles != y.Cycles {
			return x.Cycles > y.Cycles
		}
		if x.Key.Producer != y.Key.Producer {
			return x.Key.Producer < y.Key.Producer
		}
		if x.Key.Waiting != y.Key.Waiting {
			return x.Key.Waiting < y.Key.Waiting
		}
		return x.Key.Cause < y.Key.Cause
	})
	dl := []string{fmt.Sprint("dependencies total ", len(groups))}
	for rank, g := range groups[:min(c.Top, len(groups))] {
		key := g.Key
		dl = append(dl, fmt.Sprintf("%d %s %s -> %s %s %s stall_cycles %d events %d", rank+1, hex(key.Producer),
			a[trace.Static[key.Producer][0]].Class, hex(key.Waiting), a[trace.Static[key.Waiting][0]].Class,
			causes[key.Cause], g.Cycles, g.Events))
	}
	parts = append(parts, dl)
	intervals := []string{fmt.Sprint("intervals size ", c.Interval)}
	for lo := 0; lo < n; lo += c.Interval {
		hi := min(n, lo+c.Interval) - 1
		cycles := run.Timings[hi].W
		if lo > 0 {
			cycles -= run.Timings[lo-1].W
		}
		intervals = append(intervals, fmt.Sprintf("%d-%d cycles %d cpi %s", lo+1, hi+1, cycles, decimal(cycles, hi-lo+1)))
	}
	parts = append(parts, intervals)
	names = nil
	for _, p := range c.Predictors {
		names = append(names, p.Name)
	}
	table := []string{"cycles_table " + strings.Join(names, " ")}
	for i, variant := range c.Variants {
		row := []string{variant.Name}
		for _, r := range runs[i] {
			row = append(row, fmt.Sprint(r.Cycles))
		}
		table = append(table, strings.Join(row, " "))
	}
	parts = append(parts, table)
	writeParts("stats.txt", parts)
}
func writeParts(name string, parts [][]string) {
	lines := []string{}
	for i, p := range parts {
		if i > 0 {
			lines = append(lines, "")
		}
		lines = append(lines, p...)
	}
	writeLines(name, lines)
}
func profileOutput(trace Trace, c Config, predictions []PredictionResult, run Run) {
	a := trace.Instructions
	branches, loops, indirect, instructions := []string{"branches"}, []string{"loops"}, []string{"indirect"}, []string{"instructions"}
	stallPC := map[int]int{}
	for _, s := range run.Stalls {
		stallPC[a[s.Responsible].PC] += s.Cycles
	}
	for _, pc := range trace.PCs {
		executions := trace.Static[pc]
		ins := a[executions[0]]
		if ins.Class == "BRANCH" {
			taken, transitions, longT, longN, current, trip, longTrip, trips := 0, 0, 0, 0, 0, 0, 0, 0
			previous := false
			for j, index := range executions {
				t := a[index].Taken
				if t {
					taken++
				}
				if j > 0 && t != previous {
					transitions++
				}
				if j == 0 || t != previous {
					current = 1
				} else {
					current++
				}
				if t {
					longT = max(longT, current)
				} else {
					longN = max(longN, current)
				}
				previous = t
				trip++
				if !t {
					trips++
					longTrip = max(longTrip, trip)
					trip = 0
				}
			}
			if trip > 0 {
				trips++
				longTrip = max(longTrip, trip)
			}
			best := -1
			for i, p := range predictions {
				if p.Config.Scheme != "PERFECT" && (best < 0 || p.PCWrong[pc] < predictions[best].PCWrong[pc]) {
					best = i
				}
			}
			direction := "forward"
			if ins.Target < pc {
				direction = "backward"
			}
			branches = append(branches, fmt.Sprintf("%s %s executions %d taken %d transitions %d longest_taken %d longest_not_taken %d best %s %d",
				hex(pc), direction, len(executions), taken, transitions, longT, longN, predictions[best].Config.Name,
				predictions[best].PCWrong[pc]))
			if direction == "backward" {
				loops = append(loops, fmt.Sprintf("%s-%s body %d entries %d iterations %d avg_trip %s max_trip %d",
					hex(ins.Target), hex(pc), (pc-ins.Target)/4+1, trips, len(executions), decimal(len(executions),
						trips), longTrip))
			}
		}
		if ins.Class == "JUMP" && ins.RS1 >= 0 {
			counts := map[int]int{}
			for _, index := range executions {
				counts[a[index].Target]++
			}
			targets := []int{}
			for target := range counts {
				targets = append(targets, target)
			}
			sort.Slice(targets, func(i, j int) bool {
				if counts[targets[i]] != counts[targets[j]] {
					return counts[targets[i]] > counts[targets[j]]
				}
				return targets[i] < targets[j]
			})
			items := []string{}
			for _, target := range targets {
				items = append(items, fmt.Sprintf("%s:%d", hex(target), counts[target]))
			}
			indirect = append(indirect, fmt.Sprintf("%s executions %d distinct %d targets %s", hex(pc), len(executions), len(targets), strings.Join(items, " ")))
		}
		instructions = append(instructions, fmt.Sprintf("%s %s %s %s %s executions %d stall_cycles %d",
			hex(pc), ins.Class, registerText(ins.RD), registerText(ins.RS1), registerText(ins.RS2),
			len(executions), stallPC[pc]))
	}
	type Segment struct{ PC, Instances, Instructions, Cycles int }
	groups := map[int]*Segment{}
	lo := 0
	for i, ins := range a {
		if ins.control() || i == len(a)-1 {
			pc := a[lo].PC
			if groups[pc] == nil {
				groups[pc] = &Segment{PC: pc}
			}
			g := groups[pc]
			g.Instances++
			g.Instructions += i - lo + 1
			cycles := run.Timings[i].W
			if lo > 0 {
				cycles -= run.Timings[lo-1].W
			}
			g.Cycles += cycles
			lo = i + 1
		}
	}
	segments := []*Segment{}
	for _, s := range groups {
		segments = append(segments, s)
	}
	sort.Slice(segments, func(i, j int) bool {
		if segments[i].Cycles != segments[j].Cycles {
			return segments[i].Cycles > segments[j].Cycles
		}
		return segments[i].PC < segments[j].PC
	})
	sl := []string{fmt.Sprint("segments total ", len(segments))}
	for rank, s := range segments[:min(c.Top, len(segments))] {
		sl = append(sl, fmt.Sprintf("%d %s instances %d instructions %d cycles %d cpi %s", rank+1, hex(s.PC),
			s.Instances, s.Instructions, s.Cycles, decimal(s.Cycles, s.Instructions)))
	}
	writeParts("profile.txt", [][]string{branches, loops, sl, indirect, instructions})
}
func comparisons(trace Trace, c Config, p []PredictionResult, runs [][]Run, primary int) {
	a := trace.Instructions
	branches := []string{"predictor,pc,class,executions,taken,mispredictions,accuracy"}
	for _, pr := range p {
		for _, pc := range trace.PCs {
			executions := trace.Static[pc]
			ins := a[executions[0]]
			if !ins.control() {
				continue
			}
			taken := 0
			for _, i := range executions {
				if a[i].Taken {
					taken++
				}
			}
			wrong := pr.PCWrong[pc]
			branches = append(branches, fmt.Sprintf("%s,%s,%s,%d,%d,%d,%s", pr.Config.Name, hex(pc), ins.Class,
				len(executions), taken, wrong, percent(len(executions)-wrong, len(executions))))
		}
	}
	writeLines("branches.csv", branches)
	combinations := []Combination{}
	for vi, variants := range runs {
		for pi, run := range variants {
			combinations = append(combinations, Combination{vi, pi, run})
		}
	}
	sort.Slice(combinations, func(i, j int) bool {
		x, y := combinations[i], combinations[j]
		if x.Run.Cycles != y.Run.Cycles {
			return x.Run.Cycles < y.Run.Cycles
		}
		vx, vy := c.Variants[x.Variant].Name, c.Variants[y.Variant].Name
		if vx != vy {
			return vx < vy
		}
		return p[x.Predictor].Config.Name < p[y.Predictor].Config.Name
	})
	out := []string{"rank,variant,predictor,cycles,cpi,speedup,accuracy,mispredictions,control,structural,load_use,raw"}
	for rank, x := range combinations {
		pr, run := p[x.Predictor], x.Run
		out = append(out, fmt.Sprintf("%d,%s,%s,%d,%s,%s,%s,%d,%d,%d,%d,%d", rank+1, c.Variants[x.Variant].Name,
			pr.Config.Name, run.Cycles, decimal(run.Cycles, len(a)), decimal(primary, run.Cycles),
			percent(pr.Control-pr.Wrong, pr.Control), pr.Wrong, run.Totals[0], run.Totals[1], run.Totals[2],
			run.Totals[3]))
	}
	writeLines("comparison.csv", out)
}
func main() {
	trace, c := traceCheck(), readConfig()
	p := []PredictionResult{}
	pp, pv := 0, 0
	for i, pc := range c.Predictors {
		p = append(p, predict(trace.Instructions, c, pc))
		if pc.Name == c.PrimaryPredictor {
			pp = i
		}
	}
	runs := make([][]Run, len(c.Variants))
	for vi, v := range c.Variants {
		if v.Name == c.PrimaryVariant {
			pv = vi
		}
		for _, pr := range p {
			runs[vi] = append(runs[vi], simulate(trace.Instructions, v, pr.Predictions))
		}
	}
	primary := runs[pv][pp]
	diagram := rows(trace.Instructions, c.Variants[pv], p[pp], primary)
	pipelineOutput(c, primary, diagram)
	statsOutput(trace, c, p, runs, pv, pp, diagram)
	profileOutput(trace, c, p, primary)
	comparisons(trace, c, p, runs, primary.Cycles)
}
