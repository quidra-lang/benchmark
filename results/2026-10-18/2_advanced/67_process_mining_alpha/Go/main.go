package main

import (
	"fmt"
	"os"
	"sort"
	"strings"
)

type Variant struct {
	Trace []string
	Cases []*Case
	Keep  bool
}
type Discovery struct {
	Net                Net
	Names              []string
	Pairs              []Masks
	Candidates, Causal int
	Relation           func(string,
		string) string
	LoopBefore, LoopAfter map[string][]string
	LoopPlace             map[string]string
}
type Reachability struct {
	Markings, Edges, Unsafe, Deadlocks, Stuck int
	Final, Sound                              bool
	Dead                                      []string
	Follows                                   map[Pair]int
}
type Prefix struct {
	Trace     []string
	Weight    int
	Followers map[string]bool
}
type Precision struct {
	Prefixes, Allowed, Escaping int
	Escapes                     map[string]int
}

func pairLess(a, b Pair) bool { return a.A < b.A || a.A == b.A && a.B < b.B }
func pairs(d map[Pair]int) []Pair {
	a := make([]Pair, 0, len(d))
	for p := range d {
		a = append(a, p)
	}
	sort.Slice(a, func(i, j int) bool { return pairLess(a[i], a[j]) })
	return a
}
func sum(a []int) int {
	s := 0
	for _, v := range a {
		s += v
	}
	return s
}
func average(a []int) string {
	if len(a) == 0 {
		return "-"
	}
	return ratio(sum(a), len(a)).String()
}
func traceActivities(log []Trace) []string {
	s := map[string]bool{}
	for _, v := range log {
		for _, a := range v.Activities {
			s[a] = true
		}
	}
	return names(s)
}
func discover(log []Trace, activities []string, rel func(string, string) string) Discovery {
	d := Discovery{Names: activities,
		Relation: rel, LoopBefore: map[string][]string{}, LoopAfter: map[string][]string{}, LoopPlace: map[string]string{}}
	var queue []Masks
	seen := map[Masks]bool{}
	add := func(m Masks) {
		if !seen[m] && candidate(m,
			activities, rel) {
			seen[m] = true
			queue = append(queue, m)
		}
	}
	for i, a := range activities {
		for j, b := range activities {
			if rel(a,
				b) == "->" {
				d.Causal++
				add(Masks{1 << i, 1 << j})
			}
		}
	}
	for pos := 0; pos < len(queue); pos++ {
		m := queue[pos]
		maximal := true
		for i := range activities {
			bit := 1 << i
			if m.A&bit == 0 {
				v := Masks{m.A | bit,
					m.B}
				if candidate(v, activities, rel) {
					maximal = false
					add(v)
				}
			}
			if m.B&bit == 0 {
				v := Masks{m.A, m.B | bit}
				if candidate(v,
					activities, rel) {
					maximal = false
					add(v)
				}
			}
		}
		if maximal {
			d.Pairs = append(d.Pairs, m)
		}
	}
	d.Candidates = len(queue)
	sort.Slice(d.Pairs,
		func(i, j int) bool { return compareMasks(d.Pairs[i], d.Pairs[j], activities) < 0 })
	places := []string{"start"}
	for i := range d.Pairs {
		places = append(places,
			fmt.Sprintf("p%d", i+1))
	}
	places = append(places, "end")
	n := newNet(places, append([]string(nil), activities...),
		0, len(places)-1)
	start, end := map[string]bool{}, map[string]bool{}
	for _, v := range log {
		start[v.Activities[0]] = true
		end[v.Activities[len(v.Activities)-1]] = true
	}
	for _, t := range activities {
		if start[t] {
			n.In[t] = append(n.In[t], 0)
			n.Arcs++
		}
		for i, pair := range d.Pairs {
			for _, a := range maskMembers(pair.B, activities) {
				if a == t {
					n.In[t] = append(n.In[t], i+1)
					n.Arcs++
				}
			}
			for _, a := range maskMembers(pair.A, activities) {
				if a == t {
					n.Out[t] = append(n.Out[t], i+1)
					n.Arcs++
				}
			}
		}
		if end[t] {
			n.Out[t] = append(n.Out[t],
				len(places)-1)
			n.Arcs++
		}
	}
	d.Net = n
	return d
}
func discoverPlus(w []Trace, tw, loops []string, dw map[Pair]int) (Discovery, map[Pair]int) {
	loopSet := map[string]bool{}
	for _, a := range loops {
		loopSet[a] = true
	}
	var v []Trace
	for _, tr := range w {
		var a []string
		for _, name := range tr.Activities {
			if !loopSet[name] {
				a = append(a,
					name)
			}
		}
		v = append(v, Trace{a, tr.Weight})
	}
	tv := traceActivities(v)
	dv, tri := follows(v), triangles(v)
	rel := func(a,
		b string) string {
		return alphaRelation(dv, tri, a, b)
	}
	d := discover(v, tv, rel)
	d.Net.Transitions = append([]string(nil),
		tw...)
	for _, t := range loops {
		d.Net.In[t] = nil
		d.Net.Out[t] = nil
		var before, after []string
		for _, a := range tv {
			if dw[Pair{a, t}] > 0 {
				before = append(before, a)
			}
			if dw[Pair{t, a}] > 0 {
				after = append(after,
					a)
			}
		}
		d.LoopBefore[t], d.LoopAfter[t] = before, after
		for i, pair := range d.Pairs {
			if compareSequence(before,
				maskMembers(pair.A, tv)) == 0 && compareSequence(after, maskMembers(pair.B, tv)) == 0 {
				place := i + 1
				d.Net.In[t] = []int{place}
				d.Net.Out[t] = []int{place}
				d.Net.Arcs += 2
				d.LoopPlace[t] = d.Net.Places[place]
				break
			}
		}
	}
	return d,
		tri
}
func reportDiscovery(s *strings.Builder, d Discovery) {
	n := d.Net
	for pi, p := range n.Places {
		var in, out []string
		for _, t := range n.Transitions {
			for _, x := range n.Out[t] {
				if x == pi {
					in = append(in, t)
				}
			}
			for _, x := range n.In[t] {
				if x == pi {
					out = append(out,
						t)
				}
			}
		}
		if pi > 0 && pi < len(n.Places)-1 {
			in = maskMembers(d.Pairs[pi-1].A, d.Names)
			out = maskMembers(d.Pairs[pi-1].B,
				d.Names)
		}
		line(s, "PLACE %s %s %s", p, list(in), list(out))
	}
	for _, t := range n.Transitions {
		var in,
			out []string
		for _, pi := range n.In[t] {
			in = append(in, n.Places[pi])
		}
		for _, pi := range n.Out[t] {
			out = append(out,
				n.Places[pi])
		}
		line(s, "TRANSITION %s in %s out %s", t, list(in), list(out))
	}
	line(s, "NET places %d transitions %d arcs %d",
		len(n.Places), len(n.Transitions), n.Arcs)
}
func markingKey(a []int) string {
	b := make([]byte, len(a))
	for i, v := range a {
		b[i] = byte(v)
	}
	return string(b)
}
func initialMarking(n Net) []int { a := make([]int, len(n.Places)); a[n.Initial] = 1; return a }
func reachability(n Net) Reachability {
	r := Reachability{Follows: map[Pair]int{}}
	initial := initialMarking(n)
	states := [][]int{initial}
	index := map[string]int{markingKey(initial): 0}
	var reverse [][]int
	reverse = append(reverse,
		nil)
	enabledEver := map[string]bool{}
	for pos := 0; pos < len(states); pos++ {
		m := states[pos]
		enabled := 0
		for _, t := range n.Transitions {
			if !n.enabled(m, t) {
				continue
			}
			enabled++
			enabledEver[t] = true
			next := n.fire(m,
				t)
			safe := true
			for _, v := range next {
				if v > 1 {
					safe = false
					break
				}
			}
			if !safe {
				r.Unsafe++
				continue
			}
			r.Edges++
			key := markingKey(next)
			j,
				found := index[key]
			if !found {
				j = len(states)
				index[key] = j
				states = append(states, next)
				reverse = append(reverse,
					nil)
			}
			reverse[j] = append(reverse[j], pos)
			for _, u := range n.Transitions {
				if n.enabled(next, u) {
					r.Follows[Pair{t,
						u}] = 1
				}
			}
		}
		if enabled == 0 {
			final := true
			for i, v := range m {
				want := 0
				if i == n.Final {
					want = 1
				}
				if v != want {
					final = false
				}
			}
			if !final {
				r.Deadlocks++
			}
		}
	}
	r.Markings = len(states)
	finalMark := make([]int,
		len(n.Places))
	finalMark[n.Final] = 1
	fi, found := index[markingKey(finalMark)]
	r.Final = found
	can := map[int]bool{}
	if found {
		queue := []int{fi}
		can[fi] = true
		for pos := 0; pos < len(queue); pos++ {
			for _, parent := range reverse[queue[pos]] {
				if !can[parent] {
					can[parent] = true
					queue = append(queue, parent)
				}
			}
		}
	}
	r.Stuck = len(states) - len(can)
	for _, t := range n.Transitions {
		if !enabledEver[t] {
			r.Dead = append(r.Dead, t)
		}
	}
	r.Sound = r.Unsafe == 0 && r.Stuck == 0 && len(r.Dead) == 0
	return r
}
func prefixes(cases []*Case) []Prefix {
	m := map[string]*Prefix{}
	for _, c := range cases {
		for k := 0; k <= len(c.Trace); k++ {
			key := strings.Join(c.Trace[:k],
				"\x00")
			p := m[key]
			if p == nil {
				p = &Prefix{Trace: append([]string(nil), c.Trace[:k]...), Followers: map[string]bool{}}
				m[key] = p
			}
			p.Weight++
			if k < len(c.Trace) {
				p.Followers[c.Trace[k]] = true
			}
		}
	}
	a := make([]Prefix,
		0, len(m))
	for _, p := range m {
		a = append(a, *p)
	}
	return a
}
func precision(n Net, prefixes []Prefix) Precision {
	r := Precision{Escapes: map[string]int{}}
	for _, p := range prefixes {
		m := initialMarking(n)
		fits := true
		for _, t := range p.Trace {
			if _, ok := n.In[t]; !ok || !n.enabled(m, t) {
				fits = false
				break
			}
			m = n.fire(m, t)
		}
		if !fits {
			continue
		}
		r.Prefixes++
		for _, t := range n.Transitions {
			if n.enabled(m, t) {
				r.Allowed += p.Weight
				if !p.Followers[t] {
					r.Escaping += p.Weight
					r.Escapes[t] += p.Weight
				}
			}
		}
	}
	return r
}
func tokenReplay(n Net, c *Case) Replay {
	r := replayRecord(n)
	tokens := make([][]int, len(n.Places))
	tokens[n.Initial] = []int{c.Events[0].Time}
	r.Produced = 1
	for _, e := range c.Events {
		input, exists := n.In[e.Activity]
		if !exists {
			r.Skipped++
			continue
		}
		for _, p := range input {
			r.Consumed++
			if len(tokens[p]) > 0 {
				produced := tokens[p][0]
				tokens[p] = tokens[p][1:]
				r.Places[p].Waits = append(r.Places[p].Waits,
					e.Time-produced)
				r.Places[p].Routes[e.Activity]++
			} else {
				r.Missing++
				r.Places[p].Missing++
			}
		}
		for _, p := range n.Out[e.Activity] {
			tokens[p] = append(tokens[p], e.Time)
			r.Produced++
		}
	}
	r.Consumed++
	if len(tokens[n.Final]) > 0 {
		tokens[n.Final] = tokens[n.Final][1:]
	} else {
		r.Missing++
		r.Places[n.Final].Missing++
	}
	for p := range tokens {
		r.Places[p].Remaining = len(tokens[p])
		r.Remaining += len(tokens[p])
		if r.Places[p].Missing > 0 || r.Places[p].Remaining > 0 {
			r.Places[p].Deviating = 1
		}
	}
	if r.Missing == 0 && r.Remaining == 0 {
		r.Fitting = 1
	}
	return r
}
func aggregateReplay(total *Replay, r Replay) {
	total.Missing += r.Missing
	total.Remaining += r.Remaining
	total.Consumed += r.Consumed
	total.Produced += r.Produced
	total.Skipped += r.Skipped
	total.Fitting += r.Fitting
	for i, p := range r.Places {
		v := &total.Places[i]
		v.Missing += p.Missing
		v.Remaining += p.Remaining
		v.Deviating += p.Deviating
		v.Waits = append(v.Waits,
			p.Waits...)
		for t, n := range p.Routes {
			v.Routes[t] += n
		}
	}
}
func reportLog(out *strings.Builder, cases []*Case, events []Event, activities, resources []string, model Net,
	sla, rows int, errors []string) {
	for _, e := range errors {
		line(out, "ERROR %s", e)
	}
	first, last := events[0],
		events[0]
	for _, e := range events {
		if e.Time < first.Time {
			first = e
		}
		if e.Time > last.Time {
			last = e
		}
	}
	line(out,
		"LOG rows %d adopted %d rejected %d cases %d activities %d resources %d first %s last %s", rows,
		len(events), len(errors), len(cases), len(activities), len(resources), first.Timestamp, last.Timestamp)
	for _, a := range activities {
		eventCount, caseCount, start, end, rework := 0, 0, 0, 0, 0
		var waits []int
		rs := map[string]bool{}
		for _, c := range cases {
			count := 0
			for i, e := range c.Events {
				if e.Activity == a {
					count++
					rs[e.Resource] = true
					if i > 0 {
						waits = append(waits,
							e.Time-c.Events[i-1].Time)
					}
				}
			}
			eventCount += count
			if count > 0 {
				caseCount++
			}
			if count > 1 {
				rework++
			}
			if c.Trace[0] == a {
				start++
			}
			if c.Trace[len(c.Trace)-1] == a {
				end++
			}
		}
		_,
			inModel := model.In[a]
		line(out, "ACTIVITY %s events %d cases %d start %d end %d rework %d wait %s resources %d model %s",
			a, eventCount, caseCount, start, end, rework, average(waits), len(rs), yes(inModel))
	}
	var lengths, durations []int
	days := map[int]int{}
	late,
		maxDays := 0, 0
	var weekdayEvents, weekdayStarts, weekdayEnds [7]int
	for _, e := range events {
		weekdayEvents[(e.Time/1440+3)%7]++
	}
	for _, c := range cases {
		lengths = append(lengths, len(c.Events))
		durations = append(durations, c.Duration)
		d := c.Duration / 1440
		days[d]++
		maxDays = max(maxDays,
			d)
		if c.Duration > sla {
			late++
		}
		weekdayStarts[(c.Events[0].Time/1440+3)%7]++
		weekdayEnds[(c.Events[len(c.Events)-1].Time/1440+3)%7]++
	}
	for i, a := range [][]int{lengths, durations} {
		name := "LENGTH"
		if i == 1 {
			name = "DURATION"
		}
		sort.Ints(a)
		line(out,
			"%s min %d max %d mean %s median %s", name, a[0], a[len(a)-1], average(a), median(a))
	}
	for d := 0; d <= maxDays; d++ {
		line(out,
			"DAYS %d cases %d share %s", d, days[d], percent(days[d], len(cases)))
	}
	line(out, "SLA limit %d late %d share %s",
		sla, late, percent(late, len(cases)))
	weekdays := []string{"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}
	for i, name := range weekdays {
		line(out, "WEEKDAY %s events %d starts %d ends %d", name, weekdayEvents[i],
			weekdayStarts[i], weekdayEnds[i])
	}
}
func reportDFG(out *strings.Builder, cases []*Case, activities []string, d map[Pair]int) {
	start, end := map[string]int{},
		map[string]int{}
	durations := map[string][]int{}
	waits := map[Pair][]int{}
	caseCounts := map[Pair]int{}
	for _, c := range cases {
		start[c.Trace[0]]++
		last := c.Trace[len(c.Trace)-1]
		end[last]++
		durations[last] = append(durations[last],
			c.Duration)
		seen := map[Pair]bool{}
		for i := 1; i < len(c.Events); i++ {
			a, b := c.Events[i-1], c.Events[i]
			pair := Pair{a.Activity,
				b.Activity}
			waits[pair] = append(waits[pair], b.Time-a.Time)
			seen[pair] = true
		}
		for pair := range seen {
			caseCounts[pair]++
		}
	}
	for k, count := range []map[string]int{start, end} {
		var a []string
		for name := range count {
			a = append(a, name)
		}
		sort.Slice(a,
			func(i, j int) bool { return count[a[i]] > count[a[j]] || count[a[i]] == count[a[j]] && a[i] < a[j] })
		for _, name := range a {
			if k == 0 {
				line(out, "START %s count %d", name, count[name])
			} else {
				line(out, "END %s count %d duration %s",
					name, count[name], average(durations[name]))
			}
		}
	}
	edges := pairs(d)
	sort.SliceStable(edges, func(i, j int) bool { return d[edges[i]] > d[edges[j]] })
	for _, pair := range edges {
		a := waits[pair]
		sort.Ints(a)
		line(out, "EDGE %s %s count %d cases %d mean %s min %d max %d",
			pair.A, pair.B, d[pair], caseCounts[pair], average(a), a[0], a[len(a)-1])
	}
	footprint(out, activities,
		func(a, b string) string { return relation(d, a, b) })
}
func reportHeuristic(out *strings.Builder, activities []string, d, tri map[Pair]int, params map[string]string) {
	sigma := integer(params["positive_observations"])
	td,
		rho, t1, t2, ta := parseRatio(params["dependency_threshold"]), parseRatio(params["relative_to_best"]),
		parseRatio(params["loop1_threshold"]), parseRatio(params["loop2_threshold"]), parseRatio(params["and_threshold"])
	l1 := map[string]bool{}
	l2 := map[Pair]bool{}
	graph := map[Pair]int{}
	for _, a := range activities {
		count := d[Pair{a, a}]
		if count == 0 {
			continue
		}
		measure := loopMeasure(count)
		verdict := "REJECT"
		if count >= sigma && measure.compare(t1) >= 0 {
			l1[a] = true
			graph[Pair{a,
				a}] = 1
			verdict = "ACCEPT"
		}
		line(out, "L1 %s count %d measure %s %s", a, count, measure, verdict)
	}
	for i, a := range activities {
		for _, b := range activities[i+1:] {
			if l1[a] || l1[b] {
				continue
			}
			count := tri[Pair{a,
				b}] + tri[Pair{b, a}]
			if count == 0 {
				continue
			}
			measure := loopMeasure(count)
			verdict := "REJECT"
			if count >= sigma && measure.compare(t2) >= 0 {
				l2[Pair{a,
					b}] = true
				l2[Pair{b, a}] = true
				verdict = "ACCEPT"
			}
			line(out, "L2 %s %s count %d measure %s %s", a, b,
				count, measure, verdict)
		}
	}
	bestOut, bestIn := map[string]Ratio{}, map[string]Ratio{}
	for _, pair := range pairs(d) {
		if pair.A == pair.B {
			continue
		}
		measure := dependency(d,
			pair.A, pair.B)
		if b, ok := bestOut[pair.A]; !ok || measure.compare(b) > 0 {
			bestOut[pair.A] = measure
		}
		if b,
			ok := bestIn[pair.B]; !ok || measure.compare(b) > 0 {
			bestIn[pair.B] = measure
		}
	}
	for _, pair := range pairs(d) {
		a,
			b := pair.A, pair.B
		if a == b {
			continue
		}
		measure := dependency(d, a, b)
		verdict := "ACCEPT"
		switch {
		case l2[pair]:
			verdict = "LOOP2"
		case d[pair] < sigma:
			verdict = "REJECT_COUNT"
		case measure.compare(td) < 0:
			verdict = "REJECT_MEASURE"
		case bestOut[a].subtract(measure).compare(rho) > 0 && bestIn[b].subtract(measure).compare(rho) > 0:
			verdict = "REJECT_BEST"
		}
		if verdict == "ACCEPT" || verdict == "LOOP2" {
			graph[pair] = 1
		}
		line(out,
			"DEP %s %s count %d reverse %d measure %s %s", a, b, d[pair], d[Pair{b, a}], measure, verdict)
	}
	inputs,
		outputs := map[string][]string{}, map[string][]string{}
	for _, a := range activities {
		for _, b := range activities {
			if graph[Pair{b,
				a}] > 0 {
				inputs[a] = append(inputs[a], b)
			}
			if graph[Pair{a, b}] > 0 {
				outputs[a] = append(outputs[a], b)
			}
		}
		line(out,
			"NODE %s in %s out %s", a, list(inputs[a]), list(outputs[a]))
	}
	for _, a := range activities {
		for k, all := range [][]string{outputs[a], inputs[a]} {
			var others []string
			for _, b := range all {
				if b != a {
					others = append(others,
						b)
				}
			}
			for i, b := range others {
				for _, c := range others[i+1:] {
					measure := splitMeasure(d, a, b, c, k == 1)
					kind := "XOR"
					if measure.compare(ta) >= 0 {
						kind = "AND"
					}
					name := "SPLIT"
					if k == 1 {
						name = "JOIN"
					}
					line(out,
						"%s %s %s %s measure %s %s", name, a, b, c, measure, kind)
				}
			}
		}
	}
	line(out, "GRAPH activities %d edges %d loops1 %d loops2 %d",
		len(activities), len(graph), len(l1), len(l2)/2)
}
func reportResources(out *strings.Builder, cases []*Case, events []Event, activities, resources []string) {
	for i, r := range resources {
		work := map[string]int{}
		count, casesCount := 0, 0
		for _, c := range cases {
			seen := false
			for _, e := range c.Events {
				if e.Resource == r {
					work[e.Activity]++
					count++
					seen = true
				}
			}
			if seen {
				casesCount++
			}
		}
		var items []string
		for _, a := range activities {
			if work[a] > 0 {
				items = append(items, fmt.Sprintf("%s=%d", a, work[a]))
			}
		}
		line(out,
			"RESOURCE %d %s events %d cases %d work %s", i+1, r, count, casesCount, strings.Join(items, ","))
	}
	handover,
		handCases, subcontract, together := map[Pair]int{}, map[Pair]int{}, map[Pair]int{}, map[Pair]int{}
	total,
		self := 0, 0
	for _, c := range cases {
		seen := map[Pair]bool{}
		rs := map[string]bool{}
		for i, e := range c.Events {
			rs[e.Resource] = true
			if i > 0 {
				pair := Pair{c.Events[i-1].Resource,
					e.Resource}
				handover[pair]++
				seen[pair] = true
				total++
				if pair.A == pair.B {
					self++
				}
			}
			if i >= 2 {
				a, b := c.Events[i-2].Resource,
					c.Events[i-1].Resource
				if a == e.Resource && a != b {
					subcontract[Pair{a, b}]++
				}
			}
		}
		for pair := range seen {
			handCases[pair]++
		}
		a := names(rs)
		for i, r := range a {
			for _, s := range a[i+1:] {
				together[Pair{r, s}]++
			}
		}
	}
	ordered := func(d map[Pair]int) []Pair {
		a := pairs(d)
		sort.SliceStable(a,
			func(i, j int) bool { return d[a[i]] > d[a[j]] })
		return a
	}
	for _, pair := range ordered(handover) {
		if pair.A != pair.B {
			line(out,
				"HANDOVER %s %s count %d cases %d", pair.A, pair.B, handover[pair], handCases[pair])
		}
	}
	table(out,
		len(resources), 5, func(i, j int) string { return fmt.Sprint(handover[Pair{resources[i], resources[j]}]) })
	for _, pair := range ordered(subcontract) {
		line(out, "SUBCONTRACT %s %s count %d", pair.A, pair.B, subcontract[pair])
	}
	for _, pair := range ordered(together) {
		line(out, "TOGETHER %s %s cases %d", pair.A, pair.B, together[pair])
	}
	line(out,
		"TOTAL handovers %d self %d other %d", total, self, total-self)
}
func reportConformance(out, csv *strings.Builder, nets []Net, netNames, activities []string, cases []*Case,
	d map[Pair]int, referenceReplays []Replay) {
	line(out, "MODEL places %d transitions %d arcs %d",
		len(nets[0].Places), len(nets[0].Transitions), nets[0].Arcs)
	reach := make([]Reachability, len(nets))
	for i, n := range nets {
		r := reachability(n)
		reach[i] = r
		line(out, "REACHABILITY %s markings %d edges %d unsafe %d deadlocks %d stuck %d final %s dead %s sound %s",
			netNames[i], r.Markings, r.Edges, r.Unsafe, r.Deadlocks, r.Stuck, yes(r.Final), list(r.Dead), yes(r.Sound))
	}
	for i, n := range nets {
		union := map[string]bool{}
		for _, a := range activities {
			union[a] = true
		}
		for _, a := range n.Transitions {
			union[a] = true
		}
		u := names(union)
		different := 0
		var differences []Pair
		for _, a := range u {
			for _, b := range u {
				if relation(d, a, b) != relation(reach[i].Follows, a, b) {
					different++
					if a <= b {
						differences = append(differences,
							Pair{a, b})
					}
				}
			}
		}
		cells := len(u) * len(u)
		line(out, "FOOTPRINT %s activities %d cells %d differing %d fitness %s",
			netNames[i], len(u), cells, different, ratio(cells-different, cells))
		if i == 0 {
			for _, pair := range differences {
				line(out,
					"DIFF %s %s log %s model %s", pair.A, pair.B, relation(d, pair.A, pair.B), relation(reach[i].Follows,
						pair.A, pair.B))
			}
		}
	}
	prefixes := prefixes(cases)
	for i, n := range nets {
		r := precision(n, prefixes)
		value := ratio(1,
			1)
		if r.Allowed > 0 {
			value = ratio(r.Allowed-r.Escaping, r.Allowed)
		}
		line(out, "PRECISION %s prefixes %d allowed %d escaping %d precision %s",
			netNames[i], r.Prefixes, r.Allowed, r.Escaping, value)
		var escapes []string
		for a, v := range r.Escapes {
			if v > 0 {
				escapes = append(escapes,
					a)
			}
		}
		sort.Slice(escapes, func(i, j int) bool {
			a, b := escapes[i], escapes[j]
			return r.Escapes[a] > r.Escapes[b] || r.Escapes[a] == r.Escapes[b] && a < b
		})
		for _, a := range escapes {
			line(out, "ESCAPE %s %s weight %d", netNames[i], a, r.Escapes[a])
		}
	}
	line(csv, "case_id,variant,events,skipped,missing,remaining,consumed,produced,fitness")
	for i, n := range nets {
		total := replayRecord(n)
		for ci, c := range cases {
			r := Replay{}
			if i == 0 {
				r = referenceReplays[ci]
				line(csv,
					"%s,%d,%d,%d,%d,%d,%d,%d,%s", c.ID, c.Variant, len(c.Events), r.Skipped, r.Missing, r.Remaining, r.Consumed,
					r.Produced, r.fitness())
			} else {
				r = tokenReplay(n, c)
			}
			aggregateReplay(&total, r)
		}
		line(out, "REPLAY %s cases %d fitting %d skipped %d missing %d remaining %d consumed %d produced %d fitness %s",
			netNames[i], len(cases), total.Fitting, total.Skipped, total.Missing, total.Remaining, total.Consumed,
			total.Produced, total.fitness())
		for pi, place := range n.Places {
			v := total.Places[pi]
			maximum := "-"
			if len(v.Waits) > 0 {
				m := v.Waits[0]
				for _, w := range v.Waits {
					m = max(m, w)
				}
				maximum = fmt.Sprint(m)
			}
			line(out, "PLACE %s %s missing %d remaining %d deviating %d tokens %d mean %s max %s",
				netNames[i], place, v.Missing, v.Remaining, v.Deviating, len(v.Waits), average(v.Waits), maximum)
		}
		for pi, place := range n.Places {
			var routes []string
			for _, t := range n.Transitions {
				for _, p := range n.In[t] {
					if p == pi {
						routes = append(routes,
							fmt.Sprintf("%s=%d", t, total.Places[pi].Routes[t]))
					}
				}
			}
			if len(routes) >= 2 {
				line(out, "ROUTE %s %s %s",
					netNames[i], place, strings.Join(routes, ","))
			}
		}
	}
}
func main() {
	rows, params := inputRows()
	var events []Event
	var errors []string
	adopted := map[string]bool{}
	activitySet,
		resourceSet := map[string]bool{}, map[string]bool{}
	for i, row := range rows {
		a := strings.Split(row,
			",")
		time, valid := timestamp(a[2])
		if !valid {
			errors = append(errors, fmt.Sprintf("line %d: bad timestamp %s",
				i+2, a[2]))
			continue
		}
		key := a[0] + "\x00" + a[1] + "\x00" + a[2]
		if adopted[key] {
			errors = append(errors,
				fmt.Sprintf("line %d: duplicate event %s %s %s", i+2, a[0], a[1], a[2]))
			continue
		}
		adopted[key] = true
		events = append(events,
			Event{a[0], a[1], a[2], a[3], time, i + 2})
		activitySet[a[1]], resourceSet[a[3]] = true, true
	}
	activities,
		resources := names(activitySet), names(resourceSet)
	cases := groupCases(events)
	model := readModel()
	var log []Trace
	for _, c := range cases {
		log = append(log, Trace{c.Trace, 1})
	}
	d := follows(log)
	sla, filter := integer(params["sla_minutes"]),
		integer(params["filter_min_follows"])
	byTrace := map[string]*Variant{}
	for _, c := range cases {
		key := strings.Join(c.Trace,
			"\x00")
		v := byTrace[key]
		if v == nil {
			v = &Variant{Trace: c.Trace, Keep: true}
			byTrace[key] = v
			for i := 1; i < len(c.Trace); i++ {
				if d[Pair{c.Trace[i-1],
					c.Trace[i]}] < filter {
					v.Keep = false
				}
			}
		}
		v.Cases = append(v.Cases, c)
	}
	var variants []*Variant
	for _, v := range byTrace {
		variants = append(variants, v)
	}
	sort.Slice(variants, func(i, j int) bool {
		a, b := variants[i],
			variants[j]
		return len(a.Cases) > len(b.Cases) || len(a.Cases) == len(b.Cases) && compareSequence(a.Trace,
			b.Trace) < 0
	})
	var w []Trace
	keptVariants, keptCases, keptEvents := 0, 0, 0
	for i, v := range variants {
		for _, c := range v.Cases {
			c.Variant = i + 1
		}
		if v.Keep {
			w = append(w, Trace{v.Trace, len(v.Cases)})
			keptVariants++
			keptCases += len(v.Cases)
			keptEvents += len(v.Cases) * len(v.Trace)
		}
	}
	referenceReplays := make([]Replay,
		len(cases))
	replayByCase := map[string]Replay{}
	for i, c := range cases {
		referenceReplays[i] = tokenReplay(model,
			c)
		replayByCase[c.ID] = referenceReplays[i]
	}
	var logOut, variantsOut, dfgOut, alphaOut, heuristicOut,
		conformanceCSV, conformanceOut, resourcesOut strings.Builder
	reportLog(&logOut, cases, events, activities,
		resources, model, sla, len(rows), errors)
	for i, v := range variants {
		duration, late := 0, 0
		for _, c := range v.Cases {
			duration += c.Duration
			if c.Duration > sla {
				late++
			}
		}
		verdict := "DROP"
		if v.Keep {
			verdict = "KEEP"
		}
		line(&variantsOut,
			"VARIANT %d count %d share %s length %d first %s duration %s late %d fitness %s %s %s", i+1, len(v.Cases),
			percent(len(v.Cases), len(cases)), len(v.Trace), v.Cases[0].ID, ratio(duration, len(v.Cases)), late,
			replayByCase[v.Cases[0].ID].fitness(), verdict, strings.Join(v.Trace, ","))
	}
	line(&variantsOut, "FILTER min_follows %d variants %d of %d cases %d of %d events %d of %d",
		filter, keptVariants, len(variants), keptCases, len(cases), keptEvents, len(events))
	reportDFG(&dfgOut,
		cases, activities, d)
	tw := traceActivities(w)
	dw := follows(w)
	var loops []string
	for _, a := range tw {
		if dw[Pair{a,
			a}] > 0 {
			loops = append(loops, a)
		}
	}
	alpha := discover(w, tw, func(a, b string) string {
		return relation(dw,
			a, b)
	})
	plus, tri := discoverPlus(w, tw, loops, dw)
	line(&alphaOut, "LOG variants %d cases %d activities %s",
		keptVariants, keptCases, list(tw))
	line(&alphaOut, "LOOPS %s", list(loops))
	line(&alphaOut, "MINER alpha")
	footprint(&alphaOut,
		alpha.Names, alpha.Relation)
	line(&alphaOut, "PAIRS causal %d candidates %d maximal %d", alpha.Causal,
		alpha.Candidates, len(alpha.Pairs))
	reportDiscovery(&alphaOut, alpha)
	line(&alphaOut, "MINER alpha_plus")
	for _, pair := range pairs(tri) {
		line(&alphaOut, "TRIANGLE %s %s count %d", pair.A, pair.B, tri[pair])
	}
	footprint(&alphaOut,
		plus.Names, plus.Relation)
	line(&alphaOut, "PAIRS causal %d candidates %d maximal %d", plus.Causal,
		plus.Candidates, len(plus.Pairs))
	for _, t := range loops {
		place := plus.LoopPlace[t]
		if place == "" {
			place = "-"
		}
		line(&alphaOut,
			"LOOP %s before %s after %s place %s", t, list(plus.LoopBefore[t]), list(plus.LoopAfter[t]), place)
	}
	reportDiscovery(&alphaOut,
		plus)
	reportHeuristic(&heuristicOut, activities, d, triangles(log), params)
	reportConformance(&conformanceOut,
		&conformanceCSV, []Net{model, alpha.Net, plus.Net}, []string{"reference", "alpha", "alpha_plus"}, activities,
		cases, d, referenceReplays)
	reportResources(&resourcesOut, cases, events, activities, resources)
	must(os.MkdirAll("output",
		0755))
	for path, s := range map[string]*strings.Builder{"log_summary.txt": &logOut, "variants.txt": &variantsOut,
		"dfg.txt": &dfgOut, "alpha_net.txt": &alphaOut, "heuristic_net.txt": &heuristicOut, "conformance.csv": &conformanceCSV,
		"conformance.txt": &conformanceOut, "resources.txt": &resourcesOut} {
		write("output/"+path, s)
	}
}
