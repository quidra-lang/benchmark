package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)
var algorithms = []string{"FCFS", "SJF", "SRTF", "RR", "PRIORITY", "HRRN", "EDF", "LOTTERY", "MLFQ"}
var keys = []string{"cs", "q", "k", "s", "seed"}

type Process struct {
	id string
	arrival, priority, deadline int
	bursts []int
}

type State struct {
	state string
	burst, left, effective, wait, level, used, enqueued, start, finish, slices int
}

type Burst struct {
	ready, start, end, slices int
}

type Snapshot struct {
	states []State
	queues [3][]int
	cpu, mode int
}

type Result struct {
	p []Process
	states []State
	bursts [][]Burst
	labels, events []string
	snapshots []Snapshot
	end, switches, busy, swtime, idle, qmax, qsum, met, missed int
	totals [3]int
}

func integer(s string) int {
	n, _ := strconv.Atoi(s)
	return n
}

func has(a []string, s string) bool {
	for _, x := range a {
		if x == s {
			return true
		}
	}
	return false
}

func ratio(u, v int) string {
	n := 100*u/v
	return fmt.Sprintf("%d.%02d", n/100, n%100)
}

func allowed(a, k string) bool {
	return k == "cs" || k == "q" && (a == "RR" || a == "LOTTERY") || k == "seed" && a == "LOTTERY" || k == "k" && a == "PRIORITY" || k == "s" && a == "MLFQ"
}

func valid(k string, v int) bool {
	switch k {
	case "cs":
		return v <= 5
	case "q":
		return v >= 1 && v <= 20
	case "k":
		return v >= 1 && v <= 50
	case "s":
		return v <= 500
	case "seed":
		return v >= 1 && v <= 2147483646
	}
	return false
}

func notation(a string, p map[string]int, full bool) string {
	r := []string{}
	for _, k := range keys {
		if full || allowed(a, k) {
			r = append(r, fmt.Sprintf("%s=%d", k, p[k]))
		}
	}
	return strings.Join(r, " ")
}

func simulate(p []Process, a string, params map[string]int) *Result {
	n := len(p)
	r := &Result{p: p, states: make([]State, n), bursts: make([][]Burst, n)}
	for i, x := range p {
		r.states[i] = State{state:"FUTURE", left: x.bursts[0], effective: x.priority, start: -1, finish: -1}
		r.bursts[i] = make([]Burst, (len(x.bursts)+1)/2)
		for j := range r.bursts[i] {
			r.bursts[i][j].start = -1
		}
	}
	var queues [3][]int
	cpu, previous, mode, sw, run := -1, -1, 0, 0, 0
	x := int64(params["seed"])
	for t := 0; ; t++ {
		log := func(event string) {
			r.events = append(r.events, fmt.Sprintf("%d %s", t, event))
		}
		enqueue := func(i int) {
			s := &r.states[i]
			s.state = "READY"
			s.enqueued = t
			l := 0
			if a == "MLFQ" {
				l = s.level
			}
			queues[l] = append(queues[l], i)
		}
		start := func(i int) {
			cpu = i
			mode = 2
			run = 0
			s := &r.states[i]
			s.state = "RUN"
			if s.start < 0 {
				s.start = t
			}
			b := &r.bursts[i][s.burst/2]
			if b.start < 0 {
				b.start = t
			}
		}
		deadline := func(i int) int {
			if p[i].deadline == 0 {
				return 1<<60
			}
			return p[i].arrival+p[i].deadline
		}
		if a == "PRIORITY" {
			for _, i := range queues[0] {
				s := &r.states[i]
				s.wait++
				if s.wait == params["k"] {
					s.wait = 0
					if s.effective > 0 {
						s.effective--
						log(fmt.Sprintf("AGE %s %d", p[i].id, s.effective))
					}
				}
			}
		}
		for i := range p {
			s := &r.states[i]
			if s.state == "IO" && s.left == 0 {
				s.burst++
				s.left = p[i].bursts[s.burst]
				r.bursts[i][s.burst/2].ready = t
				enqueue(i)
				log("IODONE "+p[i].id)
			}
		}
		for i := range p {
			if r.states[i].state == "FUTURE" && p[i].arrival == t {
				r.bursts[i][0].ready = t
				enqueue(i)
				log("ARRIVE "+p[i].id)
			}
		}
		if mode == 1 && sw == 0 {
			start(cpu)
			log("START "+p[cpu].id)
		} else if mode == 2 {
			i := cpu
			s := &r.states[i]
			if s.left == 0 && s.burst == len(p[i].bursts)-1 {
				s.state = "DONE"
				s.finish = t
				log("DONE "+p[i].id)
				mode = 0
				cpu = -1
			} else {
				demoted := false
				if a == "MLFQ" && s.level < 2 && s.used == []int{4, 8}[s.level] {
					s.level++
					s.used = 0
					demoted = true
					log(fmt.Sprintf("DEMOTE %s %d", p[i].id, s.level))
				}
				preempt := false
				for l, q := range queues {
					for _, j := range q {
						z := r.states[j]
						if a == "SRTF" && z.left < s.left || a == "PRIORITY" && z.effective < s.effective || a == "EDF" && deadline(j) < deadline(i) || a == "MLFQ" && l < s.level {
							preempt = true
						}
					}
				}
				if s.left == 0 {
					s.burst++
					s.left = p[i].bursts[s.burst]
					s.state = "IO"
					log(fmt.Sprintf("IO %s %d", p[i].id, s.left))
					mode = 0
					cpu = -1
				} else if demoted {
					enqueue(i)
					mode = 0
					cpu = -1
				} else if (a == "RR" || a == "LOTTERY") && run == params["q"] {
					enqueue(i)
					log("EXPIRE "+p[i].id)
					mode = 0
					cpu = -1
				} else if preempt {
					enqueue(i)
					log("PREEMPT "+p[i].id)
					mode = 0
					cpu = -1
				}
			}
		}
		finished := true
		for _, s := range r.states {
			if s.state != "DONE" {
				finished = false
			}
		}
		if finished {
			r.end = t
			shot := Snapshot{states: append([]State(nil), r.states...), cpu: -1}
			r.snapshots = append(r.snapshots, shot)
			break
		}
		if a == "MLFQ" && params["s"] > 0 && t > 0 && t%params["s"] == 0 {
			queues[0] = append(queues[0], queues[1]...)
			queues[0] = append(queues[0], queues[2]...)
			queues[1] = nil
			queues[2] = nil
			for i := range r.states {
				r.states[i].level = 0
				r.states[i].used = 0
			}
			log("BOOST")
		}
		if mode == 0 {
			l := 0
			for l < 3 && len(queues[l]) == 0 {
				l++
			}
			if l < 3 {
				q := queues[l]
				selected := 0
				if a == "LOTTERY" {
					total := 0
					for _, i := range q {
						total += 10-p[i].priority
					}
					x = 48271*x%2147483647
					draw := int(x%int64(total))
					sum := 0
					for j, i := range q {
						sum += 10-p[i].priority
						if sum > draw {
							selected = j
							break
						}
					}
				} else {
					for j := 1; j < len(q); j++ {
						i, b := q[j], q[selected]
						u, v := r.states[i], r.states[b]
						better := false
						switch a {
						case "SJF", "SRTF":
							better = u.left < v.left
						case "PRIORITY":
							better = u.effective < v.effective
						case "EDF":
							better = deadline(i) < deadline(b)
						case "HRRN":
							better = (t-u.enqueued+u.left)*v.left > (t-v.enqueued+v.left)*u.left
						}
						if better {
							selected = j
						}
					}
				}
				i := q[selected]
				queues[l] = append(q[:selected], q[selected+1: ]...)
				s := &r.states[i]
				s.effective = p[i].priority
				s.wait = 0
				s.slices++
				r.bursts[i][s.burst/2].slices++
				change := i != previous
				if change {
					r.switches++
				}
				if change && params["cs"] > 0 {
					cpu = i
					mode = 1
					sw = params["cs"]
					s.state = "SWITCH"
					log("SWITCH "+p[i].id)
				} else {
					start(i)
					log("DISPATCH "+p[i].id)
				}
			}
		}
		shot := Snapshot{states: append([]State(nil), r.states...), cpu: cpu, mode: mode}
		qlen := 0
		for l, q := range queues {
			shot.queues[l] = append([]int(nil), q...)
			qlen += len(q)
		}
		r.snapshots = append(r.snapshots, shot)
		r.qsum += qlen
		r.qmax = max(r.qmax, qlen)
		label := "IDLE"
		if mode == 2 {
			s := &r.states[cpu]
			s.left--
			s.used++
			run++
			previous = cpu
			label = p[cpu].id
			r.busy++
			if s.left == 0 {
				r.bursts[cpu][s.burst/2].end = t+1
			}
		} else if mode == 1 {
			sw--
			label = "CS"
			r.swtime++
		} else {
			r.idle++
		}
		r.labels = append(r.labels, label)
		for i := range r.states {
			if r.states[i].state == "IO" {
				r.states[i].left--
			}
		}
	}
	for i, z := range p {
		s := r.states[i]
		turn := s.finish-z.arrival
		total := 0
		for _, b := range z.bursts {
			total += b
		}
		r.totals[0] += turn
		r.totals[1] += turn-total
		r.totals[2] += s.start-z.arrival
		if z.deadline > 0 {
			if s.finish <= z.arrival+z.deadline {
				r.met++
			} else {
				r.missed++
			}
		}
	}
	return r
}

func metrics(r *Result, i int) [3]int {
	p, s := r.p[i], r.states[i]
	total := 0
	for _, b := range p.bursts {
		total += b
	}
	t := s.finish-p.arrival
	return [3]int{t, t-total, s.start-p.arrival}
}

func summary(r *Result) string {
	n := len(r.p)
	return fmt.Sprintf("turnaround=%s waiting=%s response=%s util=%s end=%d switches=%d", ratio(r.totals[0], n), ratio(r.totals[1], n), ratio(r.totals[2], n), ratio(r.busy*100, r.end), r.end, r.switches)
}

func listline(p Process) string {
	b := []string{}
	for i, n := range p.bursts {
		c := "C"
		if i%2 == 1 {
			c = "I"
		}
		b = append(b, c+strconv.Itoa(n))
	}
	d := "none"
	if p.deadline > 0 {
		d = strconv.Itoa(p.deadline)
	}
	return fmt.Sprintf("%s arrival=%d priority=%d deadline=%s bursts=%s", p.id, p.arrival, p.priority, d, strings.Join(b, ","))
}

type App struct {
	registry map[string]Process
	out *bufio.Writer
}

func (app *App) emit(a ...any) {
	fmt.Fprintln(app.out, a...)
}

func (app *App) command(w []string) {
	c := w[0]
	err := func(s string) {
		panic(s)
	}
	n := func(i int) int {
		return integer(w[i])
	}
	p, found := Process{}, false
	if len(w) > 1 {
		p, found = app.registry[w[1]]
	}
	switch c {
	case "PROC":
		if found {
			err("duplicate process "+w[1])
		}
		if len(app.registry) == 10 {
			err("too many processes")
		}
		if n(2) > 200 {
			err("invalid arrival "+w[1])
		}
		if n(3) > 9 {
			err("invalid priority "+w[1])
		}
		b := []int{}
		ok := (len(w)-4)%2 == 1
		for i, s := range w[4: ] {
			v := integer(s[1: ])
			expected := byte('C')
			if i%2 == 1 {
				expected = 'I'
			}
			if s[0] != expected || v < 1 || v > 30 {
				ok = false
			}
			b = append(b, v)
		}
		if !ok {
			err("invalid bursts "+w[1])
		}
		p = Process{w[1], n(2), n(3), 0, b}
		app.registry[p.id] = p
		cpu, io := 0, 0
		for i, v := range b {
			if i%2 == 0 {
				cpu += v
			} else {
				io += v
			}
		}
		app.emit("PROC", p.id, fmt.Sprintf("cpu=%d io=%d", cpu, io))
		return
	case "GEN":
		count := n(2)
		for i := 1; i <= count; i++ {
			id := w[1]+strconv.Itoa(i)
			if _, ok := app.registry[id]; ok {
				err("duplicate process "+id)
			}
		}
		if len(app.registry)+count > 10 {
			err("too many processes")
		}
		app.emit("GEN", fmt.Sprintf("count=%d", count))
		x := int64(n(3))
		next := func() int {
			x = x*48271%2147483647
			return int(x)
		}
		for i := 1; i <= count; i++ {
			id := w[1]+strconv.Itoa(i)
			arrival, priority, m := next()%21, next()%10, 1+next()%3
			b := []int{}
			for j := 0; j < m; j++ {
				if j > 0 {
					b = append(b, 1+next()%8)
				}
				b = append(b, 1+next()%9)
			}
			p := Process{id, arrival, priority, 0, b}
			app.registry[id] = p
			app.emit(listline(p))
		}
		return
	case "SETPRIO", "DEADLINE", "DROP":
		if !found {
			err("unknown process "+w[1])
		}
		if c == "DROP" {
			delete(app.registry, w[1])
			app.emit(c, w[1])
		} else if c == "SETPRIO" {
			if n(2) > 9 {
				err("invalid priority "+w[1])
			}
			p.priority = n(2)
			app.registry[p.id] = p
			app.emit(c, p.id, fmt.Sprintf("priority=%d", p.priority))
		} else {
			if n(2) > 1000 {
				err("invalid deadline "+w[1])
			}
			p.deadline = n(2)
			app.registry[p.id] = p
			d := "none"
			if p.deadline > 0 {
				d = strconv.Itoa(p.deadline)
			}
			app.emit(c, p.id, d)
		}
		return
	case "CLEAR":
		app.emit("CLEAR", fmt.Sprintf("count=%d", len(app.registry)))
		app.registry = map[string]Process{}
		return
	case "LIST":
		ids := []string{}
		for id := range app.registry {
			ids = append(ids, id)
		}
		sort.Strings(ids)
		app.emit("LIST", fmt.Sprintf("count=%d", len(ids)))
		for _, id := range ids {
			app.emit(listline(app.registry[id]))
		}
		return
	}
	a, metric, start := "", "", 2
	multi := c == "COMPARE" || c == "RANK" || c == "DIFF"
	if c == "COMPARE" {
		start = 1
	} else if c == "RANK" {
		metric = w[1]
		if !has([]string{"turnaround", "waiting", "response", "end", "switches", "missed"}, metric) {
			err("unknown metric "+metric)
		}
	} else {
		a = w[1]
		if !has(algorithms, a) {
			err("unknown algorithm "+a)
		}
		if c == "DIFF" {
			if !has(algorithms, w[2]) {
				err("unknown algorithm "+w[2])
			}
			start = 3
		}
	}
	if c == "SNAPSHOT" || c == "WINDOW" {
		start = 3
	}
	if c == "WINDOW" && (n(2) < 1 || n(2) > 1000) {
		err("invalid window")
	}
	seen := map[string]bool{}
	if c == "SWEEP" {
		start = 5
		k := w[2]
		if !has(keys, k) {
			err("unknown key "+k)
		}
		if !allowed(a, k) {
			err("key "+k+" not allowed for "+a)
		}
		if n(3) > n(4) || !valid(k, n(3)) || !valid(k, n(4)) || n(4)-n(3) > 20 {
			err("invalid range")
		}
		seen[k] = true
	}
	params := map[string]int{"cs":0, "q":4, "k":5, "s":0, "seed":1}
	for _, word := range w[start: ] {
		kv := strings.Split(word, "=")
		k, v := kv[0], integer(kv[1])
		if !has(keys, k) {
			err("unknown key "+k)
		}
		if !multi && !allowed(a, k) {
			err("key "+k+" not allowed for "+a)
		}
		if seen[k] {
			err("duplicate key "+k)
		}
		if !valid(k, v) {
			err("invalid "+k)
		}
		seen[k] = true
		params[k] = v
	}
	if len(app.registry) == 0 {
		err("no processes")
	}
	ps := []Process{}
	for _, p := range app.registry {
		ps = append(ps, p)
	}
	sort.Slice(ps, func(i, j int) bool {
		return ps[i].id < ps[j].id
	})
	if c == "SWEEP" {
		app.emit(c, a, w[2], n(3), n(4))
		best, bestv := -1, 0
		for v := n(3); v <= n(4); v++ {
			params[w[2]] = v
			r := simulate(ps, a, params)
			app.emit(notation(a, params, false), summary(r))
			if best < 0 || r.totals[1] < best {
				best = r.totals[1]
				bestv = v
			}
		}
		app.emit("BEST", fmt.Sprintf("%s=%d", w[2], bestv))
		return
	}
	if multi {
		if c == "DIFF" {
			r, s := simulate(ps, a, params), simulate(ps, w[2], params)
			app.emit(c, a, w[2], notation("", params, true))
			wins, loss, ties := 0, 0, 0
			for i, p := range ps {
				u, v := metrics(r, i), metrics(s, i)
				app.emit(fmt.Sprintf("%s turnaround=%d/%d waiting=%d/%d response=%d/%d", p.id, u[0], v[0], u[1], v[1], u[2], v[2]))
				if u[0] < v[0] {
					wins++
				} else if u[0] > v[0] {
					loss++
				} else {
					ties++
				}
			}
			app.emit("WINS", fmt.Sprintf("%s=%d %s=%d ties=%d", a, wins, w[2], loss, ties))
			return
		}
		results := make([]*Result, 9)
		for i, a := range algorithms {
			results[i] = simulate(ps, a, params)
		}
		if c == "COMPARE" {
			app.emit(c, notation("", params, true))
			row := func(v []string) {
				fmt.Fprintf(app.out, "%-8s", v[0])
				for _, x := range v[1: ] {
					fmt.Fprintf(app.out, " %8s", x)
				}
				fmt.Fprintln(app.out)
			}
			row([]string{"ALGO", "TURN", "WAIT", "RESP", "UTIL", "END", "SWITCH", "MISS"})
			for i, r := range results {
				row([]string{algorithms[i], ratio(r.totals[0], len(ps)), ratio(r.totals[1], len(ps)), ratio(r.totals[2], len(ps)), ratio(r.busy*100, r.end), strconv.Itoa(r.end), strconv.Itoa(r.switches), strconv.Itoa(r.missed)})
			}
			best := []string{}
			for j, k := range []string{"turnaround", "waiting", "response"} {
				b := 0
				for i := 1; i < 9; i++ {
					if results[i].totals[j] < results[b].totals[j] {
						b = i
					}
				}
				best = append(best, k+"="+algorithms[b])
			}
			app.emit("BEST", strings.Join(best, " "))
		} else {
			app.emit(c, metric, notation("", params, true))
			value := func(i int) int {
				r := results[i]
				switch metric {
				case "turnaround":
					return r.totals[0]
				case "waiting":
					return r.totals[1]
				case "response":
					return r.totals[2]
				case "end":
					return r.end
				case "switches":
					return r.switches
				}
				return r.missed
			}
			ids := []int{0, 1, 2, 3, 4, 5, 6, 7, 8}
			sort.SliceStable(ids, func(i, j int) bool {
				return value(ids[i]) < value(ids[j])
			})
			rank := 1
			for j, i := range ids {
				if j > 0 && value(i) != value(ids[j-1]) {
					rank = j+1
				}
				v := strconv.Itoa(value(i))
				if metric == "turnaround" || metric == "waiting" || metric == "response" {
					v = ratio(value(i), len(ps))
				}
				app.emit(rank, algorithms[i], v)
			}
		}
		return
	}
	r := simulate(ps, a, params)
	note := notation(a, params, false)
	switch c {
	case "TRACE":
		app.emit(c, a, note)
		for _, s := range r.events {
			app.emit(s)
		}
		app.emit("END", r.end)
	case "TIMELINE":
		if r.end > 100 {
			err(fmt.Sprintf("too long %d", r.end))
		}
		app.emit(c, a, note, fmt.Sprintf("end=%d", r.end))
		for i, p := range ps {
			var line strings.Builder
			for t := 0; t < r.end; t++ {
				ch := byte('-')
				switch r.snapshots[t].states[i].state {
				case "READY":
					ch = '.'
				case "SWITCH":
					ch = 's'
				case "RUN":
					ch = '#'
				case "IO":
					ch = 'i'
				}
				line.WriteByte(ch)
			}
			app.emit(fmt.Sprintf("%-8s %s", p.id, line.String()))
		}
	case "SNAPSHOT":
		t := n(2)
		s := r.snapshots[min(t, r.end)]
		app.emit(c, a, note, fmt.Sprintf("t=%d", t))
		if s.mode == 0 {
			app.emit("CPU IDLE")
		} else {
			mode := "RUN"
			if s.mode == 1 {
				mode = "SWITCH"
			}
			app.emit("CPU", mode, ps[s.cpu].id)
		}
		count := 1
		if a == "MLFQ" {
			count = 3
		}
		for l := 0; l < count; l++ {
			name := "QUEUE"
			if a == "MLFQ" {
				name += strconv.Itoa(l)
			}
			ids := []string{}
			for _, i := range s.queues[l] {
				ids = append(ids, ps[i].id)
			}
			text := "none"
			if len(ids) > 0 {
				text = strings.Join(ids, " ")
			}
			app.emit(name, text)
		}
		for i, p := range ps {
			z := s.states[i]
			switch z.state {
			case "FUTURE":
				app.emit(p.id, "FUTURE", fmt.Sprintf("at=%d", p.arrival))
			case "DONE":
				app.emit(p.id, "DONE", fmt.Sprintf("at=%d", z.finish))
			default:
				text := fmt.Sprintf("%s %s burst=%d left=%d", p.id, z.state, z.burst+1, z.left)
				if a == "PRIORITY" {
					text += fmt.Sprintf(" prio=%d", z.effective)
				}
				if a == "MLFQ" {
					text += fmt.Sprintf(" level=%d used=%d", z.level, z.used)
				}
				app.emit(text)
			}
		}
	case "BURSTS":
		app.emit(c, a, note)
		for i, p := range ps {
			for j, b := range r.bursts[i] {
				length := p.bursts[2*j]
				app.emit(fmt.Sprintf("%s #%d len=%d ready=%d start=%d end=%d wait=%d slices=%d", p.id, j+1, length, b.ready, b.start, b.end, b.end-b.ready-length, b.slices))
			}
		}
	case "WINDOW":
		width := n(2)
		app.emit(c, a, note, fmt.Sprintf("width=%d", width))
		for lo := 0; lo < r.end; lo += width {
			hi := min(lo+width, r.end)
			busy, cs, idle := 0, 0, 0
			counts := map[string]int{}
			for tick := lo; tick < hi; tick++ {
				shot := r.snapshots[tick]
				if shot.mode == 1 {
					cs++
				} else if shot.mode == 0 {
					idle++
				} else {
					busy++
					counts[ps[shot.cpu].id]++
				}
			}
			top, best := "none", 0
			for _, p := range ps {
				if counts[p.id] > best {
					best = counts[p.id]
					top = p.id
				}
			}
			app.emit(fmt.Sprintf("%d-%d busy=%d switch=%d idle=%d util=%s top=%s", lo, hi, busy, cs, idle, ratio(busy*100, hi-lo), top))
		}
	case "STATS":
		app.emit(c, a, note)
		for j, k := range []string{"turnaround", "waiting", "response"} {
			v := []int{}
			imin, imax := 0, 0
			for i := range ps {
				m := metrics(r, i)
				v = append(v, m[j])
				if v[i] < v[imin] {
					imin = i
				}
				if v[i] > v[imax] {
					imax = i
				}
			}
			lo, hi := v[imin], v[imax]
			sort.Ints(v)
			med := v[len(v)/2]*2
			if len(v)%2 == 0 {
				med = v[len(v)/2-1]+v[len(v)/2]
			}
			app.emit(fmt.Sprintf("%s min=%d (%s) max=%d (%s) median=%d.%d total=%d", k, lo, ps[imin].id, hi, ps[imax].id, med/2, med%2*5, r.totals[j]))
		}
	case "RUN":
		app.emit(c, a, note)
		segments := []string{}
		for lo := 0; lo < r.end; {
			hi := lo+1
			for hi < r.end && r.labels[hi] == r.labels[lo] {
				hi++
			}
			segments = append(segments, fmt.Sprintf("[%d-%d %s]", lo, hi, r.labels[lo]))
			lo = hi
		}
		for i := 0; i < len(segments); i += 8 {
			app.emit("GANTT", strings.Join(segments[i: min(i+8, len(segments))], ""))
		}
		for i, p := range ps {
			s := r.states[i]
			m := metrics(r, i)
			line := fmt.Sprintf("%s arrival=%d done=%d turnaround=%d waiting=%d response=%d slices=%d", p.id, p.arrival, s.finish, m[0], m[1], m[2], s.slices)
			if p.deadline > 0 {
				d := p.arrival+p.deadline
				line += fmt.Sprintf(" deadline=%d late=%d", d, max(0, s.finish-d))
			}
			app.emit(line)
		}
		app.emit(fmt.Sprintf("AVERAGE turnaround=%s waiting=%s response=%s", ratio(r.totals[0], len(ps)), ratio(r.totals[1], len(ps)), ratio(r.totals[2], len(ps))))
		app.emit(fmt.Sprintf("CPU end=%d busy=%d switch=%d idle=%d switches=%d util=%s", r.end, r.busy, r.swtime, r.idle, r.switches, ratio(r.busy*100, r.end)))
		app.emit(fmt.Sprintf("QUEUE max=%d avg=%s", r.qmax, ratio(r.qsum, r.end)))
		counts := map[string]int{}
		for _, s := range r.events {
			counts[strings.Fields(s)[1]]++
		}
		app.emit(fmt.Sprintf("EVENTS preempt=%d expire=%d demote=%d boost=%d age=%d", counts["PREEMPT"], counts["EXPIRE"], counts["DEMOTE"], counts["BOOST"], counts["AGE"]))
		app.emit(fmt.Sprintf("DEADLINE met=%d missed=%d", r.met, r.missed))
	}
}

func main() {
	in := bufio.NewReader(os.Stdin)
	first, _ := in.ReadString('\n')
	n := integer(strings.TrimSpace(first))
	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()
	app := App{map[string]Process{}, out}
	for i := 0; i < n; i++ {
		line, _ := in.ReadString('\n')
		func() {
			defer func() {
				if e := recover(); e != nil {
					app.emit("ERROR", e)
				}
			}()
			app.command(strings.Fields(line))
		}()
	}
}
