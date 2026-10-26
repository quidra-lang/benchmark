package main

import (
	"bufio"
	"fmt"
	"math/bits"
	"os"
	"slices"
	"sort"
	"strconv"
	"strings"
)

var output = bufio.NewWriter(os.Stdout)

func say(s string) { fmt.Fprintln(output, s) }
func yes(b bool) string {
	if b {
		return "yes"
	}
	return "no"
}
func listed(a []string) string {
	if len(a) == 0 {
		return "none"
	}
	return strings.Join(a, " ")
}
func key(a []int64) string {
	s := make([]string, len(a))
	for i, v := range a {
		s[i] = strconv.FormatInt(v, 10)
	}
	return strings.Join(s, ",")
}
func marking(a []int64) string {
	s := make([]string, len(a))
	for i, v := range a {
		if v < 0 {
			s[i] = "w"
		} else {
			s[i] = strconv.FormatInt(v, 10)
		}
	}
	return "(" + strings.Join(s, ",") + ")"
}
func number(s string, lo, hi int64) int64 {
	if len(s) == 0 || len(s) > 10 || len(s) > 1 && s[0] == '0' {
		return -1
	}
	for _, c := range s {
		if c < '0' || c > '9' {
			return -1
		}
	}
	n, e := strconv.ParseInt(s, 10, 64)
	if e != nil || n < lo || n > hi {
		return -1
	}
	return n
}
func visit(adj [][]int, start int) []bool {
	seen := make([]bool, len(adj))
	q := []int{start}
	seen[start] = true
	for i := 0; i < len(q); i++ {
		for _, v := range adj[q[i]] {
			if !seen[v] {
				seen[v] = true
				q = append(q, v)
			}
		}
	}
	return seen
}
func all(a []bool) bool {
	for _, v := range a {
		if !v {
			return false
		}
	}
	return true
}
func count(a []bool) int {
	n := 0
	for _, v := range a {
		if v {
			n++
		}
	}
	return n
}
func gcd(a, b int64) int64 {
	for b != 0 {
		a, b = b, a%b
	}
	if a < 0 {
		return -a
	}
	return a
}
func flows(a [][]int64) [][]int64 {
	n, m := len(a), len(a[0])
	rows := make([][]int64, n)
	for i, r := range a {
		rows[i] = append(slices.Clone(r), make([]int64, n)...)
		rows[i][m+i] = 1
	}
	for j := 0; j < m; j++ {
		unique := map[string][]int64{}
		for _, r := range rows {
			if r[j] == 0 {
				unique[key(r)] = r
			}
		}
		for _, r := range rows {
			if r[j] <= 0 {
				continue
			}
			for _, s := range rows {
				if s[j] >= 0 {
					continue
				}
				v := make([]int64, m+n)
				d := int64(0)
				for k := range v {
					v[k] = -s[j]*r[k] + r[j]*s[k]
					d = gcd(d, v[k])
				}
				for k := range v {
					v[k] /= d
				}
				unique[key(v)] = v
			}
		}
		candidates := [][]int64{}
		supports := []int{}
		for _, r := range unique {
			candidates = append(candidates, r)
			mask := 0
			for i := 0; i < n; i++ {
				if r[m+i] > 0 {
					mask |= 1 << i
				}
			}
			supports = append(supports, mask)
		}
		rows = nil
		for i, r := range candidates {
			minimal := true
			for _, s := range supports {
				if s != supports[i] && s&supports[i] == s {
					minimal = false
					break
				}
			}
			if minimal {
				rows = append(rows, r)
			}
		}
	}
	result := [][]int64{}
	for _, r := range rows {
		result = append(result, slices.Clone(r[m:]))
	}
	sort.Slice(result, func(i, j int) bool { return slices.Compare(result[i], result[j]) > 0 })
	return result
}

type Edge struct{ transition, target int }
type Graph struct {
	states      [][]int64
	parent, via []int
	edges       [][]Edge
	found       int
	aborted     bool
}

func (g *Graph) add(m []int64, p, t int) {
	g.states = append(g.states, m)
	g.parent = append(g.parent, p)
	g.via = append(g.via, t)
	g.edges = append(g.edges, []Edge{})
}

type Net struct {
	name                                 string
	places, transitions                  []string
	initial, capacity, priority, current []int64
	history                              [][]int64
	pre, post, inhibitor                 [16][16]int64
	arcs, inhibitors                     int
}

func (n *Net) define(w []string) error {
	cmd := w[0]
	arity := len(w) - 1
	if cmd != "place" && cmd != "transition" && cmd != "arc" && cmd != "inhibit" {
		return fmt.Errorf("unknown definition %s", cmd)
	}
	valid := arity == 3
	if cmd == "place" {
		valid = arity == 2 || arity == 3
	}
	if cmd == "transition" {
		valid = arity == 1 || arity == 2
	}
	if !valid {
		return fmt.Errorf("wrong number of arguments")
	}
	a := w[1]
	if cmd == "place" || cmd == "transition" {
		if slices.Contains(n.places, a) || slices.Contains(n.transitions, a) {
			return fmt.Errorf("duplicate name %s", a)
		}
		if cmd == "place" {
			tokens, _ := strconv.ParseInt(w[2], 10, 64)
			cap := int64(0)
			if arity == 3 {
				cap, _ = strconv.ParseInt(w[3], 10, 64)
				if tokens > cap {
					return fmt.Errorf("tokens exceed capacity of %s", a)
				}
			}
			n.places = append(n.places, a)
			n.initial = append(n.initial, tokens)
			n.capacity = append(n.capacity, cap)
		} else {
			priority := int64(0)
			if arity == 2 {
				priority, _ = strconv.ParseInt(w[2], 10, 64)
			}
			n.transitions = append(n.transitions, a)
			n.priority = append(n.priority, priority)
		}
	} else if cmd == "arc" {
		b := w[2]
		for _, x := range []string{a, b} {
			if !slices.Contains(n.places, x) && !slices.Contains(n.transitions, x) {
				return fmt.Errorf("unknown node %s", x)
			}
		}
		pa, pb := slices.Index(n.places, a), slices.Index(n.places, b)
		if (pa >= 0) == (pb >= 0) {
			return fmt.Errorf("arc must connect a place and a transition")
		}
		p := pa
		t := slices.Index(n.transitions, b)
		matrix := &n.pre
		if pa < 0 {
			p = pb
			t = slices.Index(n.transitions, a)
			matrix = &n.post
		}
		if matrix[p][t] != 0 {
			return fmt.Errorf("duplicate arc %s %s", a, b)
		}
		matrix[p][t], _ = strconv.ParseInt(w[3], 10, 64)
		n.arcs++
	} else {
		p, t := slices.Index(n.places, a), slices.Index(n.transitions, w[2])
		if p < 0 {
			return fmt.Errorf("unknown place %s", a)
		}
		if t < 0 {
			return fmt.Errorf("unknown transition %s", w[2])
		}
		if n.inhibitor[p][t] != 0 {
			return fmt.Errorf("duplicate inhibitor %s %s", a, w[2])
		}
		n.inhibitor[p][t], _ = strconv.ParseInt(w[3], 10, 64)
		n.inhibitors++
	}
	return nil
}
func (n *Net) reason(m []int64, t int) string {
	for p, name := range n.places {
		if m[p] >= 0 && m[p] < n.pre[p][t] {
			return "insufficient tokens in " + name
		}
	}
	for p, name := range n.places {
		if n.inhibitor[p][t] > 0 && (m[p] < 0 || m[p] >= n.inhibitor[p][t]) {
			return "inhibited by " + name
		}
	}
	for p, name := range n.places {
		if n.capacity[p] > 0 && (m[p] < 0 || m[p]-n.pre[p][t]+n.post[p][t] > n.capacity[p]) {
			return "capacity of " + name + " exceeded"
		}
	}
	return ""
}
func (n *Net) enabled(m []int64) []int {
	r := []int{}
	for t := range n.transitions {
		if n.reason(m, t) == "" {
			r = append(r, t)
		}
	}
	return r
}
func (n *Net) fire(m []int64, t int) []int64 {
	r := slices.Clone(m)
	for p := range r {
		if r[p] >= 0 {
			r[p] += n.post[p][t] - n.pre[p][t]
		}
	}
	return r
}
func (n *Net) commit(t int) {
	n.history = append(n.history, n.current)
	n.current = n.fire(n.current, t)
}
func (n *Net) names(ts []int) []string {
	r := make([]string, len(ts))
	for i, t := range ts {
		r[i] = n.transitions[t]
	}
	return r
}
func (n *Net) graph(start []int64, limit int, target [][2]int64) Graph {
	g := Graph{found: -1}
	g.add(slices.Clone(start), -1, -1)
	index := map[string]int{key(start): 0}
	matches := func(m []int64) bool {
		if target == nil {
			return false
		}
		for p, v := range m {
			if v < target[p][0] || target[p][1] >= 0 && v != target[p][1] {
				return false
			}
		}
		return true
	}
	if matches(start) {
		g.found = 0
		return g
	}
	for q := 0; q < len(g.states); q++ {
		for _, t := range n.enabled(g.states[q]) {
			m := n.fire(g.states[q], t)
			k, known := index[key(m)]
			if !known {
				if len(g.states) == limit {
					g.aborted = true
					return g
				}
				k = len(g.states)
				index[key(m)] = k
				g.add(m, q, t)
				if matches(m) {
					g.found = k
					return g
				}
			}
			g.edges[q] = append(g.edges[q], Edge{t, k})
		}
	}
	return g
}
func path(g Graph, k int) []int {
	r := []int{}
	for g.parent[k] >= 0 {
		r = append(r, g.via[k])
		k = g.parent[k]
	}
	slices.Reverse(r)
	return r
}
func (n *Net) reach(limit int, display bool) {
	g := n.graph(n.current, limit, nil)
	if g.aborted {
		say(fmt.Sprintf("reachability graph limit %d exceeded", limit))
		return
	}
	N := len(g.states)
	if display {
		for i, m := range g.states {
			a := []string{}
			for _, e := range g.edges[i] {
				a = append(a, fmt.Sprintf("%s->M%d", n.transitions[e.transition], e.target))
			}
			text := strings.Join(a, " ")
			if len(a) == 0 {
				text = "dead"
			}
			say(fmt.Sprintf("M%d %s: %s", i, marking(m), text))
		}
		return
	}
	adj := make([][]int, N)
	for i, e := range g.edges {
		for _, v := range e {
			adj[i] = append(adj[i], v.target)
		}
	}
	closure := make([][]bool, N)
	for i := range closure {
		closure[i] = visit(adj, i)
	}
	comp := make([]int, N)
	for i := range comp {
		comp[i] = -1
	}
	components := 0
	for i := range comp {
		if comp[i] >= 0 {
			continue
		}
		for j := i; j < N; j++ {
			if closure[i][j] && closure[j][i] {
				comp[j] = components
			}
		}
		components++
	}
	terminal, home := make([]bool, components), make([]bool, N)
	for i := range terminal {
		terminal[i] = true
	}
	for i := range home {
		home[i] = true
	}
	maximum := make([]int64, len(n.places))
	dead := []int{}
	edges := 0
	persistent := true
	for i, m := range g.states {
		if len(g.edges[i]) == 0 {
			dead = append(dead, i)
		}
		edges += len(g.edges[i])
		for p, v := range m {
			maximum[p] = max(maximum[p], v)
		}
		for j := range home {
			home[j] = home[j] && closure[i][j]
		}
		for _, e := range g.edges[i] {
			if comp[i] != comp[e.target] {
				terminal[comp[i]] = false
			}
			for _, u := range g.edges[i] {
				if e.transition != u.transition && n.reason(g.states[e.target], u.transition) != "" {
					persistent = false
				}
			}
		}
	}
	say(fmt.Sprintf("reachable markings: %d\nedges: %d\ncomponents: %d (terminal %d)\ndead markings: %d", N, edges, components, count(terminal), len(dead)))
	for _, i := range dead {
		a := n.names(path(g, i))
		text := strings.Join(a, " ")
		if len(a) == 0 {
			text = "empty"
		}
		say(fmt.Sprintf("  M%d %s path %s", i, marking(g.states[i]), text))
	}
	bound := slices.Max(maximum)
	say(fmt.Sprintf("max tokens: %s\nbound: %d\nsafe: %s\nhome markings: %d\nreversible: %s\npersistent: %s", marking(maximum), bound, yes(bound <= 1), count(home), yes(home[0]), yes(persistent)))
	levels := []string{}
	for t, name := range n.transitions {
		present := make([]bool, components)
		used, cycle := false, false
		for i, e := range g.edges {
			for _, v := range e {
				if v.transition == t {
					used = true
					present[comp[i]] = true
					if comp[i] == comp[v.target] {
						cycle = true
					}
				}
			}
		}
		live := true
		for c, v := range terminal {
			if v && !present[c] {
				live = false
			}
		}
		level := "L0"
		if live {
			level = "L4"
		} else if cycle {
			level = "L3"
		} else if used {
			level = "L1"
		}
		levels = append(levels, name+"="+level)
	}
	say("liveness: " + strings.Join(levels, " "))
}
func rank(v int64) int64 {
	if v < 0 {
		return 1<<63 - 1
	}
	return v
}
func (n *Net) cover(limit int) {
	g := Graph{}
	g.add(slices.Clone(n.current), -1, -1)
	old, dead := []bool{false}, []bool{false}
	seen := map[string]bool{key(n.current): true}
	for q := 0; q < len(g.states); q++ {
		if old[q] {
			continue
		}
		es := n.enabled(g.states[q])
		dead[q] = len(es) == 0
		anc := []int{}
		for a := q; a >= 0; a = g.parent[a] {
			anc = append(anc, a)
		}
		slices.Reverse(anc)
		for _, t := range es {
			m := n.fire(g.states[q], t)
			for _, a := range anc {
				ge, gt := true, false
				for p, v := range m {
					ge = ge && rank(v) >= rank(g.states[a][p])
					gt = gt || rank(v) > rank(g.states[a][p])
				}
				if ge && gt {
					for p, v := range m {
						if n.capacity[p] == 0 && rank(v) > rank(g.states[a][p]) {
							m[p] = -1
						}
					}
				}
			}
			if len(g.states) == limit {
				say(fmt.Sprintf("coverability tree limit %d exceeded", limit))
				return
			}
			old = append(old, seen[key(m)])
			seen[key(m)] = true
			dead = append(dead, false)
			g.add(m, q, t)
		}
	}
	say(fmt.Sprintf("coverability tree nodes: %d", len(g.states)))
	maximum := make([]int64, len(n.places))
	for i, m := range g.states {
		text := "root"
		if i > 0 {
			text = fmt.Sprintf("<- %d %s", g.parent[i], n.transitions[g.via[i]])
		}
		if old[i] {
			text += " old"
		}
		if dead[i] {
			text += " dead"
		}
		say(fmt.Sprintf("  %d %s %s", i, marking(m), text))
		for p, v := range m {
			if rank(v) > rank(maximum[p]) {
				maximum[p] = v
			}
		}
	}
	a := []string{}
	for p, v := range maximum {
		if v < 0 {
			a = append(a, n.places[p])
		}
	}
	say("bounds: " + marking(maximum))
	say("unbounded: " + listed(a))
}
func (n *Net) bits(mask int) []int {
	a := []int{}
	for p := range n.places {
		if mask&(1<<p) != 0 {
			a = append(a, p)
		}
	}
	return a
}
func (n *Net) sets(trap bool) []int {
	found := []int{}
	for mask := 1; mask < 1<<len(n.places); mask++ {
		valid := true
		for t := range n.transitions {
			input, output := false, false
			for _, p := range n.bits(mask) {
				input = input || n.post[p][t] > 0
				output = output || n.pre[p][t] > 0
			}
			if trap && output && !input || !trap && input && !output {
				valid = false
				break
			}
		}
		if valid {
			found = append(found, mask)
		}
	}
	r := []int{}
	for _, m := range found {
		minimal := true
		for _, s := range found {
			if s != m && s&m == s {
				minimal = false
				break
			}
		}
		if minimal {
			r = append(r, m)
		}
	}
	sort.Slice(r, func(i, j int) bool {
		a, b := r[i], r[j]
		x, y := bits.OnesCount(uint(a)), bits.OnesCount(uint(b))
		if x != y {
			return x < y
		}
		return slices.Compare(n.bits(a), n.bits(b)) < 0
	})
	return r
}
func (n *Net) setText(mask int) string {
	a := []string{}
	for _, p := range n.bits(mask) {
		a = append(a, n.places[p])
	}
	return "{" + strings.Join(a, ",") + "}"
}
func (n *Net) realize(counts []int64) ([]int, bool) {
	used := make([]int64, len(counts))
	stack := [][]int64{n.current}
	choices, path := []int{0}, []int{}
	seen := map[string]bool{}
	total := int64(0)
	for _, c := range counts {
		total += c
	}
	for len(stack) > 0 {
		d := len(path)
		if int64(d) == total {
			return path, true
		}
		chosen := -1
		for t := choices[d]; t < len(counts); t++ {
			choices[d] = t + 1
			if used[t] >= counts[t] || n.reason(stack[d], t) != "" {
				continue
			}
			used[t]++
			k := key(used)
			used[t]--
			if seen[k] {
				continue
			}
			seen[k] = true
			chosen = t
			break
		}
		if chosen >= 0 {
			used[chosen]++
			path = append(path, chosen)
			stack = append(stack, n.fire(stack[d], chosen))
			choices = append(choices, 0)
		} else {
			stack = stack[:len(stack)-1]
			choices = choices[:len(choices)-1]
			if len(path) > 0 {
				used[path[len(path)-1]]--
				path = path[:len(path)-1]
			}
		}
	}
	return nil, false
}
func (n *Net) invariants(transpose bool) {
	a := [][]int64{}
	ns := n.places
	if transpose {
		ns = n.transitions
		for t := range n.transitions {
			r := []int64{}
			for p := range n.places {
				r = append(r, n.post[p][t]-n.pre[p][t])
			}
			a = append(a, r)
		}
	} else {
		for p := range n.places {
			r := []int64{}
			for t := range n.transitions {
				r = append(r, n.post[p][t]-n.pre[p][t])
			}
			a = append(a, r)
		}
	}
	f := flows(a)
	tag := "P"
	if transpose {
		tag = "T"
	}
	say(fmt.Sprintf("%s-semiflows: %d", tag, len(f)))
	bounds := make([]int64, len(ns))
	covered := make([]bool, len(ns))
	for i := range bounds {
		bounds[i] = -1
	}
	for _, c := range f {
		terms := []string{}
		value := int64(0)
		for i, v := range c {
			if v > 0 {
				covered[i] = true
				prefix := ""
				if v != 1 {
					prefix = fmt.Sprintf("%d*", v)
				}
				terms = append(terms, prefix+ns[i])
				if !transpose {
					value += v * n.current[i]
				}
			}
		}
		text := "  " + strings.Join(terms, " + ")
		if transpose {
			path, ok := n.realize(c)
			if ok {
				say(text + ": realizable " + strings.Join(n.names(path), " "))
			} else {
				say(text + ": not realizable")
			}
		} else {
			say(fmt.Sprintf("%s = %d", text, value))
			for p, v := range c {
				if v > 0 {
					b := value / v
					if bounds[p] < 0 || b < bounds[p] {
						bounds[p] = b
					}
				}
			}
		}
	}
	if !transpose {
		s := []string{}
		for _, b := range bounds {
			if b < 0 {
				s = append(s, "-")
			} else {
				s = append(s, strconv.FormatInt(b, 10))
			}
		}
		say("bounds: (" + strings.Join(s, ",") + ")")
	}
	label := "conservative: "
	if transpose {
		label = "consistent: "
	}
	say(label + yes(all(covered)))
}
func (n *Net) classify() {
	P, T := len(n.places), len(n.transitions)
	inputs, outputs := make([][]int, T), make([][]int, P)
	ordinary, pure, sm, mg, fc, efc := true, true, true, true, true, true
	for p := range n.places {
		for t := range n.transitions {
			ordinary = ordinary && n.pre[p][t] <= 1 && n.post[p][t] <= 1
			pure = pure && !(n.pre[p][t] > 0 && n.post[p][t] > 0)
			if n.pre[p][t] > 0 {
				inputs[t] = append(inputs[t], p)
				outputs[p] = append(outputs[p], t)
			}
		}
	}
	for t := range n.transitions {
		c := 0
		for p := range n.places {
			if n.post[p][t] > 0 {
				c++
			}
		}
		sm = sm && len(inputs[t]) == 1 && c == 1
	}
	for p, a := range outputs {
		c := 0
		for t := range n.transitions {
			if n.post[p][t] > 0 {
				c++
			}
		}
		mg = mg && len(a) == 1 && c == 1
		for _, t := range a {
			if len(a) != 1 && len(inputs[t]) != 1 {
				fc = false
			}
			for q, b := range outputs {
				if n.pre[q][t] > 0 && !slices.Equal(a, b) {
					efc = false
				}
			}
		}
	}
	sm = sm && ordinary
	mg = mg && ordinary
	fc = fc && ordinary
	efc = efc && ordinary
	labels := []string{"ordinary", "pure", "state machine", "marked graph", "free choice", "extended free choice"}
	values := []bool{ordinary, pure, sm, mg, fc, efc}
	for i, label := range labels {
		say(label + ": " + yes(values[i]))
	}
	verdict := "holds"
	if !fc {
		verdict = "not applicable"
	} else if P > 12 {
		verdict = "too many places"
	} else {
		traps := n.sets(true)
		for _, s := range n.sets(false) {
			holds := false
			for _, q := range traps {
				if s&q == q {
					for _, p := range n.bits(q) {
						if n.current[p] > 0 {
							holds = true
						}
					}
				}
			}
			if !holds {
				verdict = "fails at " + n.setText(s)
				break
			}
		}
	}
	say("commoner: " + verdict)
}
func (n *Net) workflow(limit int) {
	P, T := len(n.places), len(n.transitions)
	sources, sinks := []int{}, []int{}
	for p := range n.places {
		input, output := false, false
		for t := range n.transitions {
			input = input || n.post[p][t] > 0
			output = output || n.pre[p][t] > 0
		}
		if !input {
			sources = append(sources, p)
		}
		if !output {
			sinks = append(sinks, p)
		}
	}
	if len(sources) != 1 {
		say(fmt.Sprintf("workflow: no (%d source places)", len(sources)))
		return
	}
	if len(sinks) != 1 {
		say(fmt.Sprintf("workflow: no (%d sink places)", len(sinks)))
		return
	}
	i, o := sources[0], sinks[0]
	adj, rev := make([][]int, P+T), make([][]int, P+T)
	for p := range n.places {
		for t := range n.transitions {
			if n.pre[p][t] > 0 {
				adj[p] = append(adj[p], P+t)
				rev[P+t] = append(rev[P+t], p)
			}
			if n.post[p][t] > 0 {
				adj[P+t] = append(adj[P+t], p)
				rev[p] = append(rev[p], P+t)
			}
		}
	}
	ns := append(slices.Clone(n.places), n.transitions...)
	f, b := visit(adj, i), visit(rev, o)
	for v, name := range ns {
		if !f[v] || !b[v] {
			say(fmt.Sprintf("workflow: no (%s is not on a path from %s to %s)", name, n.places[i], n.places[o]))
			return
		}
	}
	say(fmt.Sprintf("workflow: source %s sink %s", n.places[i], n.places[o]))
	start, goal := make([]int64, P), make([]int64, P)
	start[i] = 1
	goal[o] = 1
	g := n.graph(start, limit, nil)
	if g.aborted {
		say(fmt.Sprintf("reachability graph limit %d exceeded", limit))
		return
	}
	finish := -1
	rev = make([][]int, len(g.states))
	used := make([]bool, T)
	proper := true
	for u, m := range g.states {
		if slices.Equal(m, goal) {
			finish = u
		}
		if m[o] >= 1 && !slices.Equal(m, goal) {
			proper = false
		}
		for _, e := range g.edges[u] {
			rev[e.target] = append(rev[e.target], u)
			used[e.transition] = true
		}
	}
	option := finish >= 0 && all(visit(rev, finish))
	live := all(used)
	say("option to complete: " + yes(option))
	say("proper completion: " + yes(proper))
	say("no dead transitions: " + yes(live))
	say("sound: " + yes(option && proper && live))
}
func (n *Net) execute(w []string) error {
	arity := map[string]int{"MARKING": 0, "RESET": 0, "SET": 2, "ENABLED": 0, "FIRE": -1, "UNDO": 1, "SIMULATE": 3, "CONFLICTS": 0, "REACH": 1, "GRAPH": 1, "COVER": 1, "PATH": 2, "INCIDENCE": 0, "PINV": 0, "TINV": 0, "SIPHONS": 0, "TRAPS": 0, "CLASSIFY": 0, "WORKFLOW": 1, "SHOW": 0}
	cmd := w[0]
	expected, known := arity[cmd]
	if !known {
		return fmt.Errorf("unknown command %s", cmd)
	}
	if expected < 0 && len(w) < 2 || expected >= 0 && len(w) != expected+1 {
		return fmt.Errorf("wrong number of arguments")
	}
	limit := 0
	if slices.Contains([]string{"REACH", "GRAPH", "COVER", "PATH", "WORKFLOW"}, cmd) {
		limit = int(number(w[1], 1, 2000))
		if limit < 0 {
			return fmt.Errorf("invalid limit %s", w[1])
		}
	}
	switch cmd {
	case "MARKING", "RESET":
		if cmd == "RESET" {
			n.current = slices.Clone(n.initial)
			n.history = nil
		}
		say("marking " + marking(n.current))
	case "SET":
		p := slices.Index(n.places, w[1])
		if p < 0 {
			return fmt.Errorf("unknown place %s", w[1])
		}
		v := number(w[2], 0, 999)
		if v < 0 {
			return fmt.Errorf("invalid tokens %s", w[2])
		}
		if n.capacity[p] > 0 && v > n.capacity[p] {
			return fmt.Errorf("tokens exceed capacity of %s", w[1])
		}
		n.current = slices.Clone(n.current)
		n.current[p] = v
		n.history = nil
		say("marking " + marking(n.current))
	case "ENABLED":
		say("enabled: " + listed(n.names(n.enabled(n.current))))
	case "FIRE":
		ts := []int{}
		for _, name := range w[1:] {
			t := slices.Index(n.transitions, name)
			if t < 0 {
				return fmt.Errorf("unknown transition %s", name)
			}
			ts = append(ts, t)
		}
		for i, t := range ts {
			r := n.reason(n.current, t)
			if r != "" {
				say(fmt.Sprintf("step %d: %s not enabled (%s) at %s", i+1, n.transitions[t], r, marking(n.current)))
				return nil
			}
			n.commit(t)
		}
		say(fmt.Sprintf("fired %d -> %s", len(ts), marking(n.current)))
	case "UNDO":
		k := int(number(w[1], 1, 1000))
		if k < 0 {
			return fmt.Errorf("invalid count %s", w[1])
		}
		h := len(n.history)
		if k > h {
			return fmt.Errorf("cannot undo %d: history size %d", k, h)
		}
		n.current = n.history[h-k]
		n.history = n.history[:h-k]
		say("marking " + marking(n.current))
	case "SIMULATE":
		steps := int(number(w[1], 1, 1000))
		x := number(w[2], 1, 2147483646)
		if steps < 0 {
			return fmt.Errorf("invalid steps %s", w[1])
		}
		if x < 0 {
			return fmt.Errorf("invalid seed %s", w[2])
		}
		if w[3] != "PRIORITY" && w[3] != "RANDOM" {
			return fmt.Errorf("invalid mode %s", w[3])
		}
		counts := make([]int, len(n.transitions))
		done := 0
		for ; done < steps; done++ {
			es := n.enabled(n.current)
			if len(es) == 0 {
				say(fmt.Sprintf("dead (steps=%d)", done))
				break
			}
			t := es[0]
			if w[3] == "RANDOM" {
				x = x * 48271 % 2147483647
				t = es[x%int64(len(es))]
			} else {
				for _, u := range es {
					if n.priority[u] > n.priority[t] {
						t = u
					}
				}
			}
			n.commit(t)
			counts[t]++
			say(fmt.Sprintf("step %d: %s -> %s", done+1, n.transitions[t], marking(n.current)))
		}
		if done == steps {
			say(fmt.Sprintf("completed (steps=%d)", steps))
		}
		a := []string{}
		for t, name := range n.transitions {
			a = append(a, fmt.Sprintf("%s=%d", name, counts[t]))
		}
		say("counts: " + strings.Join(a, " "))
	case "CONFLICTS":
		s, e := []string{}, []string{}
		for u := range n.transitions {
			for v := u + 1; v < len(n.transitions); v++ {
				pair := n.transitions[u] + "/" + n.transitions[v]
				conflict := false
				for p := range n.places {
					if n.pre[p][u] > 0 && n.pre[p][v] > 0 {
						conflict = true
					}
				}
				if conflict {
					s = append(s, pair)
				}
				if n.reason(n.current, u) == "" && n.reason(n.current, v) == "" && (n.reason(n.fire(n.current, u), v) != "" || n.reason(n.fire(n.current, v), u) != "") {
					e = append(e, pair)
				}
			}
		}
		say("structural: " + listed(s))
		say("effective: " + listed(e))
	case "REACH", "GRAPH":
		n.reach(limit, cmd == "GRAPH")
	case "COVER":
		n.cover(limit)
	case "PATH":
		entries := strings.Split(w[2], ",")
		if len(entries) != len(n.places) {
			return fmt.Errorf("target needs %d entries", len(n.places))
		}
		target := make([][2]int64, len(entries))
		for p, s := range entries {
			if s == "*" {
				target[p] = [2]int64{0, -1}
				continue
			}
			plus := strings.HasSuffix(s, "+")
			raw := s
			if plus {
				raw = s[:len(s)-1]
			}
			v := number(raw, 0, 9999999999)
			if v < 0 {
				return fmt.Errorf("invalid target entry %s", s)
			}
			target[p] = [2]int64{v, v}
			if plus {
				target[p][1] = -1
			}
		}
		g := n.graph(n.current, limit, target)
		if g.found >= 0 {
			a := n.names(path(g, g.found))
			suffix := ""
			if len(a) > 0 {
				suffix = ": " + strings.Join(a, " ")
			}
			say(fmt.Sprintf("reached %s length=%d%s", marking(g.states[g.found]), len(a), suffix))
		} else if g.aborted {
			say(fmt.Sprintf("search limit %d exceeded", limit))
		} else {
			say(fmt.Sprintf("unreachable (markings explored: %d)", len(g.states)))
		}
	case "INCIDENCE":
		rows := [][]string{append([]string{""}, n.transitions...)}
		for p, name := range n.places {
			r := []string{name}
			for t := range n.transitions {
				r = append(r, strconv.FormatInt(n.post[p][t]-n.pre[p][t], 10))
			}
			rows = append(rows, r)
		}
		width := make([]int, len(n.transitions)+1)
		for _, r := range rows {
			for i, s := range r {
				width[i] = max(width[i], len(s))
			}
		}
		for _, r := range rows {
			a := []string{}
			for i, s := range r {
				pad := strings.Repeat(" ", width[i]-len(s))
				if i == 0 {
					a = append(a, s+pad)
				} else {
					a = append(a, pad+s)
				}
			}
			say(strings.TrimRight(strings.Join(a, "  "), " "))
		}
	case "PINV", "TINV":
		n.invariants(cmd == "TINV")
	case "SIPHONS", "TRAPS":
		if len(n.places) > 12 {
			return fmt.Errorf("more than 12 places")
		}
		ss := n.sets(cmd == "TRAPS")
		label := "siphons"
		if cmd == "TRAPS" {
			label = "traps"
		}
		say(fmt.Sprintf("minimal %s: %d", label, len(ss)))
		for _, s := range ss {
			tokens := int64(0)
			for _, p := range n.bits(s) {
				tokens += n.current[p]
			}
			say(fmt.Sprintf("  %s tokens=%d", n.setText(s), tokens))
		}
	case "CLASSIFY":
		n.classify()
	case "WORKFLOW":
		n.workflow(limit)
	case "SHOW":
		for p, name := range n.places {
			cap := "none"
			if n.capacity[p] > 0 {
				cap = strconv.FormatInt(n.capacity[p], 10)
			}
			say(fmt.Sprintf("place %s tokens=%d capacity=%s", name, n.initial[p], cap))
		}
		for t, name := range n.transitions {
			list := func(matrix [16][16]int64) string {
				a := []string{}
				for p, pn := range n.places {
					if matrix[p][t] > 0 {
						a = append(a, fmt.Sprintf("%s:%d", pn, matrix[p][t]))
					}
				}
				if len(a) == 0 {
					return "-"
				}
				return strings.Join(a, ",")
			}
			say(fmt.Sprintf("transition %s priority=%d pre=%s post=%s inhibit=%s", name, n.priority[t], list(n.pre), list(n.post), list(n.inhibitor)))
		}
	}
	return nil
}
func main() {
	defer output.Flush()
	scanner := bufio.NewScanner(os.Stdin)
	line := func() string {
		scanner.Scan()
		return scanner.Text()
	}
	blocks, _ := strconv.Atoi(line())
	for range blocks {
		net := Net{name: strings.Fields(line())[1]}
		for {
			w := strings.Fields(line())
			if len(w) == 2 && w[0] == "END" && w[1] == "NET" {
				break
			}
			if err := net.define(w); err != nil {
				say("error: " + err.Error())
			}
		}
		net.current = slices.Clone(net.initial)
		say(fmt.Sprintf("net %s: places=%d transitions=%d arcs=%d inhibitors=%d", net.name, len(net.places), len(net.transitions), net.arcs, net.inhibitors))
		n, _ := strconv.Atoi(line())
		for range n {
			if err := net.execute(strings.Fields(line())); err != nil {
				say("error: " + err.Error())
			}
		}
	}
}
