package main

import (
	"fmt"
	"math"
	"os"
	"sort"
	"strings"
)

type Structure struct {
	Children, Ancestors, Descendants, Blankets, Spouses [][]int
	Topological, Depth                                  []int
	MoralEdges                                          int
}
type Posterior struct {
	Relevant, Eliminate []int
	Factors             []Factor
	Minfill, Given      Plan
	Final               Factor
	Probabilities       []float64
	Z                   float64
	Marginals           map[int][]float64
}

func format(x float64) string {
	s := fmt.Sprintf("%.4f", x)
	if s == "-0.0000" {
		return "0.0000"
	}
	return s
}
func line(s *strings.Builder, template string, a ...any) { fmt.Fprintf(s, template+"\n", a...) }
func write(path string, s *strings.Builder)              { must(os.WriteFile(path, []byte(s.String()), 0644)) }
func yes(b bool) string {
	if b {
		return "yes"
	}
	return "no"
}
func allVariables(n Network) []int {
	a := make([]int, len(n.Variables))
	for i := range a {
		a[i] = i
	}
	return a
}
func variableNames(vars []int, n Network) string {
	if len(vars) == 0 {
		return "-"
	}
	a := make([]string, len(vars))
	for i, v := range vars {
		a[i] = n.Variables[v].Name
	}
	return strings.Join(a, " ")
}
func numbers(a []float64) string {
	parts := make([]string, len(a))
	for i, v := range a {
		parts[i] = format(v)
	}
	return strings.Join(parts, " ")
}
func integers(a []int) string {
	parts := make([]string, len(a))
	for i, v := range a {
		parts[i] = fmt.Sprint(v)
	}
	return strings.Join(parts, " ")
}
func closure(start []int, links [][]int) []int {
	seen := map[int]bool{}
	queue := append([]int(nil), start...)
	for _, v := range start {
		seen[v] = true
	}
	for p := 0; p < len(queue); p++ {
		for _, v := range links[queue[p]] {
			if !seen[v] {
				seen[v] = true
				queue = append(queue,
					v)
			}
		}
	}
	sort.Ints(queue)
	return queue
}
func structure(n Network) Structure {
	size := len(n.Variables)
	s := Structure{Children: make([][]int, size),
		Ancestors: make([][]int, size), Descendants: make([][]int, size), Blankets: make([][]int, size), Spouses: make([][]int,
			size), Depth: make([]int, size)}
	parents := make([][]int, size)
	for v, variable := range n.Variables {
		parents[v] = variable.Parents
		for _, p := range variable.Parents {
			s.Children[p] = append(s.Children[p], v)
		}
	}
	chosen := map[int]bool{}
	for len(s.Topological) < size {
		for v, variable := range n.Variables {
			if chosen[v] {
				continue
			}
			ready := true
			depth := 0
			for _, p := range variable.Parents {
				if !chosen[p] {
					ready = false
					break
				}
				depth = max(depth,
					s.Depth[p]+1)
			}
			if ready {
				chosen[v] = true
				s.Topological = append(s.Topological, v)
				s.Depth[v] = depth
				break
			}
		}
	}
	moral := map[[2]int]bool{}
	for v, variable := range n.Variables {
		s.Ancestors[v] = without(closure([]int{v}, parents), map[int]bool{v: true})
		s.Descendants[v] = without(closure([]int{v},
			s.Children), map[int]bool{v: true})
		spouses := map[int]bool{}
		for _, c := range s.Children[v] {
			for _, p := range parents[c] {
				if p != v && !contains(parents[v], p) && !contains(s.Children[v], p) {
					spouses[p] = true
				}
			}
		}
		for p := range spouses {
			s.Spouses[v] = append(s.Spouses[v],
				p)
		}
		sort.Ints(s.Spouses[v])
		s.Blankets[v] = variableUnion(parents[v], s.Children[v], s.Spouses[v])
		family := variableUnion([]int{v},
			variable.Parents)
		for i, a := range family {
			for _, b := range family[i+1:] {
				moral[[2]int{a, b}] = true
			}
		}
	}
	s.MoralEdges = len(moral)
	return s
}
func evidenceVariables(e []Evidence) []int {
	var vars []int
	for _, ev := range e {
		vars = append(vars, ev.V)
	}
	return variableUnion(vars)
}
func set(vars []int) map[int]bool {
	m := map[int]bool{}
	for _, v := range vars {
		m[v] = true
	}
	return m
}
func ancestorClosure(vars []int, n Network) []int {
	parents := make([][]int, len(n.Variables))
	for i, v := range n.Variables {
		parents[i] = v.Parents
	}
	return closure(vars,
		parents)
}
func initialFactors(relevant []int, e []Evidence, n Network) []Factor {
	factors := make([]Factor, 0, len(relevant))
	for _, v := range relevant {
		factors = append(factors, reduce(cptFactor(v, n), e, n))
	}
	return factors
}
func normalize(f Factor) ([]float64, float64) {
	z := 0.0
	for _, v := range f.Values {
		z += v
	}
	a := make([]float64,
		len(f.Values))
	for i, v := range f.Values {
		a[i] = v / z
	}
	return a, z
}
func posterior(q []int, e []Evidence, n Network) Posterior {
	r := Posterior{Marginals: map[int][]float64{}}
	ev := evidenceVariables(e)
	r.Relevant = ancestorClosure(variableUnion(q,
		ev), n)
	r.Factors = initialFactors(r.Relevant, e, n)
	r.Eliminate = without(r.Relevant, set(variableUnion(q,
		ev)))
	r.Minfill = plan(r.Factors, r.Eliminate, "minfill", n)
	r.Given = plan(r.Factors, r.Eliminate, "given",
		n)
	used := r.Minfill
	if n.Settings.Method == "given" {
		used = r.Given
	}
	r.Final = execute(r.Factors, used,
		false, e, n).Final
	r.Probabilities, r.Z = normalize(r.Final)
	for _, v := range q {
		r.Marginals[v] = make([]float64,
			len(n.Variables[v].States))
	}
	i := 0
	assignments(r.Final.Variables, n, func(a []int) {
		for _, v := range q {
			r.Marginals[v][a[v]] += r.Probabilities[i]
		}
		i++
	})
	return r
}
func agree(a, b []float64) bool {
	if len(a) != len(b) {
		return false
	}
	for i, v := range a {
		if math.Abs(v-b[i]) > 1e-9 {
			return false
		}
	}
	return true
}
func jointProbability(vars, a []int, n Network) float64 {
	value := 1.0
	for _, v := range vars {
		co := n.Variables[v]
		value *= co.Theta[parentCombination(co.Parents,
			a, n)][a[v]]
	}
	return value
}
func enumerateQuery(r Posterior, e []Evidence, n Network) (int, string) {
	u := without(r.Relevant, set(evidenceVariables(e)))
	count := assignmentCount(u,
		n)
	if count > n.Settings.Enumeration {
		return count, "skipped"
	}
	values := make([]float64, len(r.Probabilities))
	assignments(u,
		n, func(a []int) {
			for _, ev := range e {
				a[ev.V] = ev.S
			}
			i := factorIndex(r.Final.Variables, a, n)
			values[i] += jointProbability(r.Relevant,
				a, n)
		})
	p, z := normalize(Factor{Values: values})
	if agree(p, r.Probabilities) && math.Abs(math.Log(z)-math.Log(r.Z)) <= 1e-9 {
		return count,
			"agree"
	}
	return count, "disagree"
}
func enumerateMPE(elimination []int, e []Evidence, result EliminationResult, n Network) (int, string) {
	count := assignmentCount(elimination,
		n)
	if count > n.Settings.Enumeration {
		return count, "skipped"
	}
	best := -1.0
	var assignment []int
	all := allVariables(n)
	assignments(elimination,
		n, func(a []int) {
			for _, ev := range e {
				a[ev.V] = ev.S
			}
			value := jointProbability(all, a, n)
			if value > best {
				best = value
				assignment = append([]int(nil),
					a...)
			}
		})
	same := true
	for i, v := range assignment {
		if result.Assignment[i] != v {
			same = false
		}
	}
	if same && math.Abs(math.Log(best)-math.Log(result.Final.Values[0])) <= 1e-9 {
		return count,
			"agree"
	}
	return count, "disagree"
}
func evidence(token string, n Network) Evidence {
	a := strings.Split(token, "=")
	v := n.Names[a[0]]
	for s, name := range n.Variables[v].States {
		if name == a[1] {
			return Evidence{v, s}
		}
	}
	panic("unknown evidence")
}
func evidenceName(e Evidence, n Network) string {
	return n.Variables[e.V].Name + "=" + n.Variables[e.V].States[e.S]
}
func parseQuery(fields []string, n Network) ([]int, []Evidence, []int) {
	var q []int
	var e []Evidence
	var counts []int
	observed := false
	for i := 1; i < len(fields); i++ {
		token := fields[i]
		if token == "COUNTS" {
			for _, s := range fields[i+1:] {
				counts = append(counts, integer(s))
			}
			break
		}
		if token == "|" {
			observed = true
			continue
		}
		if observed {
			e = append(e,
				evidence(token, n))
		} else {
			q = append(q, n.Names[token])
		}
	}
	return q, e, counts
}
func reportPlan(s *strings.Builder, name string, p Plan, n Network) {
	line(s, "order %s", name)
	for _, step := range p.Steps {
		line(s,
			"step %s fill %d scope %s entries %d", n.Variables[step.V].Name, step.Fill, variableNames(step.Scope,
				n), step.Size)
	}
	line(s, "cost max %d total %d", p.Max, p.Total)
}
func reportElimination(s *strings.Builder, relevant, elimination []int, minfill, given Plan, agreement bool,
	count int, enumeration string, n Network) {
	line(s, "relevant %s", variableNames(relevant, n))
	line(s,
		"pruned %s", variableNames(without(allVariables(n), set(relevant)), n))
	line(s, "eliminate %s", variableNames(elimination,
		n))
	reportPlan(s, "minfill", minfill, n)
	reportPlan(s, "given", given, n)
	line(s, "used %s", n.Settings.Method)
	line(s,
		"orders_agree %s", yes(agreement))
	line(s, "enumeration %d %s", count, enumeration)
}
func bayesBall(x, y, z []int, n Network, s Structure) ([]int, bool) {
	observed, ancestors, xset := set(z), set(ancestorClosure(z,
		n)), set(x)
	type Ball struct{ V, Direction int }
	var queue []Ball
	seen := map[Ball]bool{}
	push := func(b Ball) {
		if !seen[b] {
			seen[b] = true
			queue = append(queue,
				b)
		}
	}
	for _, v := range x {
		push(Ball{v, 0})
	}
	reachable := map[int]bool{}
	for pos := 0; pos < len(queue); pos++ {
		b := queue[pos]
		v := b.V
		if !observed[v] && !xset[v] {
			reachable[v] = true
		}
		if b.Direction == 0 && !observed[v] {
			for _, p := range n.Variables[v].Parents {
				push(Ball{p, 0})
			}
			for _, c := range s.Children[v] {
				push(Ball{c, 1})
			}
		}
		if b.Direction == 1 {
			if !observed[v] {
				for _, c := range s.Children[v] {
					push(Ball{c, 1})
				}
			}
			if ancestors[v] {
				for _, p := range n.Variables[v].Parents {
					push(Ball{p,
						0})
				}
			}
		}
	}
	var result []int
	for v := range reachable {
		result = append(result, v)
	}
	sort.Ints(result)
	separated := true
	for _, v := range y {
		if reachable[v] {
			separated = false
		}
	}
	return result, separated
}
func decodeAssignment(vars []int, index int, n Network) []int {
	a := make([]int, len(n.Variables))
	for i := len(vars) - 1; i >= 0; i-- {
		v := vars[i]
		a[v] = index % len(n.Variables[v].States)
		index /= len(n.Variables[v].States)
	}
	return a
}
func conditionalInformation(x, y, z []int, n Network) (float64, int) {
	w, xz, yz := variableUnion(x, y, z), variableUnion(x,
		z), variableUnion(y, z)
	cw, cxz, cyz, cz := map[int]int{}, map[int]int{}, map[int]int{}, map[int]int{}
	for _, a := range n.Samples {
		cw[factorIndex(w, a, n)]++
		cxz[factorIndex(xz, a, n)]++
		cyz[factorIndex(yz, a,
			n)]++
		cz[factorIndex(z, a, n)]++
	}
	var keys []int
	for key := range cw {
		keys = append(keys, key)
	}
	sort.Ints(keys)
	cmi := 0.0
	for _, key := range keys {
		a := decodeAssignment(w, key, n)
		count := cw[key]
		num := count * cz[factorIndex(z, a, n)]
		den := cxz[factorIndex(xz,
			a, n)] * cyz[factorIndex(yz, a, n)]
		cmi += float64(count) / float64(len(n.Samples)) * math.Log(float64(num)/float64(den))
	}
	df := (assignmentCount(x,
		n) - 1) * (assignmentCount(y, n) - 1) * assignmentCount(z, n)
	return cmi, df
}
func path(a, b, ignoreX, ignoreY int, s Structure) []int {
	queue := []int{a}
	predecessor := map[int]int{a: -1}
	for pos := 0; pos < len(queue); pos++ {
		v := queue[pos]
		for _, c := range s.Children[v] {
			if v == ignoreX && c == ignoreY {
				continue
			}
			if _, seen := predecessor[c]; seen {
				continue
			}
			predecessor[c] = v
			if c == b {
				var result []int
				for x := b; x >= 0; x = predecessor[x] {
					result = append(result,
						x)
				}
				for i, j := 0, len(result)-1; i < j; i, j = i+1, j-1 {
					result[i], result[j] = result[j], result[i]
				}
				return result
			}
			queue = append(queue,
				c)
		}
	}
	return nil
}
func reportQuery(answer, eliminationOut *strings.Builder, q []int, e []Evidence, n Network) {
	r := posterior(q,
		e, n)
	line(answer, "log_evidence %s", format(math.Log(r.Z)))
	if len(e) > 0 {
		conflict := 0.0
		for _, ev := range e {
			conflict += math.Log(posterior(nil,
				[]Evidence{ev}, n).Z)
		}
		conflict -= math.Log(r.Z)
		line(answer, "conflict %s", format(conflict))
	}
	if len(q) >= 2 {
		index := 0
		assignments(r.Final.Variables,
			n, func(a []int) {
				var names []string
				for _, v := range r.Final.Variables {
					names = append(names, evidenceName(Evidence{v,
						a[v]}, n))
				}
				line(answer, "joint %s %s", strings.Join(names, " "), format(r.Probabilities[index]))
				index++
			})
	}
	for _, v := range q {
		parts := []string{"marginal", n.Variables[v].Name}
		for state, name := range n.Variables[v].States {
			parts = append(parts,
				name, format(r.Marginals[v][state]))
		}
		line(answer, strings.Join(parts, " "))
	}
	for j, ev := range e {
		var rest []Evidence
		for i, x := range e {
			if i != j {
				rest = append(rest, x)
			}
		}
		dropped := posterior(q, rest, n)
		shift := 0.0
		for _, v := range q {
			for state, value := range r.Marginals[v] {
				shift = math.Max(shift, math.Abs(value-dropped.Marginals[v][state]))
			}
		}
		line(answer,
			"drop %s shift %s", evidenceName(ev, n), format(shift))
	}
	a, za := normalize(execute(r.Factors, r.Minfill,
		false, e, n).Final)
	b, zb := normalize(execute(r.Factors, r.Given, false, e, n).Final)
	agreement := agree(a,
		b) && math.Abs(math.Log(za)-math.Log(zb)) <= 1e-9
	count, enumeration := enumerateQuery(r, e, n)
	reportElimination(eliminationOut,
		r.Relevant, r.Eliminate, r.Minfill, r.Given, agreement, count, enumeration, n)
}
func reportMPE(answer, eliminationOut *strings.Builder, e []Evidence, n Network) {
	all := allVariables(n)
	initial := initialFactors(all,
		e, n)
	elim := without(all, set(evidenceVariables(e)))
	minfill, given := plan(initial, elim, "minfill",
		n), plan(initial, elim, "given", n)
	a, b := execute(initial, minfill, true, e, n), execute(initial, given,
		true, e, n)
	result := a
	if n.Settings.Method == "given" {
		result = b
	}
	assignment := make([]string, len(all))
	for _, v := range all {
		assignment[v] = evidenceName(Evidence{v, result.Assignment[v]}, n)
	}
	m := result.Final.Values[0]
	z := 1.0
	if len(e) > 0 {
		z = posterior(nil,
			e, n).Z
	}
	line(answer, "assignment %s", strings.Join(assignment, " "))
	line(answer, "log_joint %s",
		format(math.Log(m)))
	line(answer, "log_evidence %s", format(math.Log(z)))
	line(answer, "posterior %s",
		format(m/z))
	for _, v := range elim {
		keep := without(elim, map[int]bool{v: true})
		p := plan(initial, keep,
			n.Settings.Method, n)
		f := execute(initial, p, true, e, n).Final
		second := -1
		best := -1.0
		for state, value := range f.Values {
			if state != result.Assignment[v] && value > best {
				best,
					second = value, state
			}
		}
		line(answer, "margin %s %s %s", n.Variables[v].Name, n.Variables[v].States[second],
			format(math.Log(m)-math.Log(best)))
	}
	agreement := math.Abs(math.Log(a.Final.Values[0])-math.Log(b.Final.Values[0])) <= 1e-9
	for i, v := range a.Assignment {
		if v != b.Assignment[i] {
			agreement = false
		}
	}
	count, enumeration := enumerateMPE(elim,
		e, result, n)
	reportElimination(eliminationOut, all, elim, minfill, given, agreement, count, enumeration,
		n)
}
func reportSample(answer, csv *strings.Builder, queryNumber int, q []int, e []Evidence, counts []int, generator *Generator,
	s Structure, n Network) {
	exact := posterior(q, e, n)
	for _, v := range q {
		parts := []string{"exact", n.Variables[v].Name}
		for state, name := range n.Variables[v].States {
			parts = append(parts, name, format(exact.Marginals[v][state]))
		}
		line(answer,
			strings.Join(parts, " "))
	}
	weighted := map[int][]float64{}
	for _, v := range q {
		weighted[v] = make([]float64,
			len(n.Variables[v].States))
	}
	weight, squared := 0.0, 0.0
	target := 0
	for count := 1; count <= counts[len(counts)-1]; count++ {
		a,
			w := generator.weightedSample(e, s.Topological, n)
		weight += w
		squared += w * w
		for _, v := range q {
			weighted[v][a[v]] += w
		}
		if count != counts[target] {
			continue
		}
		maximumError := 0.0
		for _, v := range q {
			for state, name := range n.Variables[v].States {
				estimate := weighted[v][state] / weight
				truth := exact.Marginals[v][state]
				error := math.Abs(estimate - truth)
				maximumError = math.Max(maximumError,
					error)
				line(csv, "%d,%d,%s,%s,%s,%s,%s", queryNumber, count, n.Variables[v].Name, name, format(estimate),
					format(truth), format(error))
			}
		}
		line(answer, "after %d weight %s ess %s max_error %s", count, format(weight),
			format(weight*weight/squared), format(maximumError))
		target++
	}
}
func reportPrediction(answer *strings.Builder, v int, s Structure, n Network) {
	k := len(n.Variables[v].States)
	confusion := make([][]int,
		k)
	for i := range confusion {
		confusion[i] = make([]int, k)
	}
	loss := 0.0
	for _, sample := range n.Samples {
		a := append([]int(nil),
			sample...)
		values := make([]float64, k)
		total := 0.0
		for state := 0; state < k; state++ {
			a[v] = state
			co := n.Variables[v]
			g := co.Theta[parentCombination(co.Parents,
				a, n)][state]
			for _, c := range s.Children[v] {
				child := n.Variables[c]
				g *= child.Theta[parentCombination(child.Parents,
					a, n)][a[c]]
			}
			values[state] = g
			total += g
		}
		prediction := 0
		best := -1.0
		for state, value := range values {
			p := value / total
			if p > best {
				best,
					prediction = p, state
			}
		}
		actual := sample[v]
		confusion[actual][prediction]++
		loss += math.Log(values[actual] / total)
	}
	correct := 0
	for state := 0; state < k; state++ {
		correct += confusion[state][state]
	}
	line(answer,
		"blanket %s", variableNames(s.Blankets[v], n))
	line(answer, "accuracy %d/%d %s", correct, len(n.Samples),
		format(float64(correct)/float64(len(n.Samples))))
	line(answer, "log_loss %s", format(-loss/float64(len(n.Samples))))
	line(answer,
		"predicted %s", strings.Join(n.Variables[v].States, " "))
	for state, name := range n.Variables[v].States {
		line(answer,
			"actual %s %s", name, integers(confusion[state]))
	}
}
func namedVariables(names []string, n Network) []int {
	var a []int
	for _, name := range names {
		a = append(a, n.Names[name])
	}
	return variableUnion(a)
}
func reportStructureQuery(out *strings.Builder, query string, fields []string, n Network, s Structure) {
	switch fields[0] {
	case "DSEP":
		parts := strings.Split(query,
			" | ")
		x := namedVariables(strings.Fields(parts[0])[1:], n)
		y := namedVariables(strings.Fields(parts[1]),
			n)
		var z []int
		if len(parts) == 3 {
			z = namedVariables(strings.Fields(parts[2]), n)
		}
		reachable, separated := bayesBall(x,
			y, z, n, s)
		result := "connected"
		if separated {
			result = "separated"
		}
		line(out, "result %s", result)
		line(out,
			"reachable %s", variableNames(reachable, n))
		cmi, df := conditionalInformation(x, y, z, n)
		line(out, "data cmi %s g2 %s df %d",
			format(cmi), format(2*float64(len(n.Samples))*cmi), df)
	case "BLANKET":
		v := n.Names[fields[1]]
		rest := without(allVariables(n),
			set(variableUnion([]int{v}, s.Blankets[v])))
		_, separated := bayesBall([]int{v}, rest, s.Blankets[v],
			n, s)
		line(out, "parents %s", variableNames(n.Variables[v].Parents, n))
		line(out, "children %s", variableNames(s.Children[v],
			n))
		line(out, "spouses %s", variableNames(s.Spouses[v], n))
		line(out, "blanket %s", variableNames(s.Blankets[v],
			n))
		line(out, "rest %s", variableNames(rest, n))
		line(out, "rest_separated %s", yes(separated))
	case "EDGE":
		operation,
			x, y := fields[1], n.Names[fields[2]], n.Names[fields[3]]
		exists := contains(n.Variables[y].Parents,
			x)
		if operation == "ADD" && exists {
			line(out, "result exists")
			return
		}
		if operation != "ADD" && !exists {
			line(out,
				"result missing")
			return
		}
		var cycle []int
		if operation == "ADD" {
			if p := path(y, x, -1, -1, s); len(p) > 0 {
				cycle = append([]int{x},
					p...)
			}
		}
		if operation == "REVERSE" {
			if p := path(x, y, x, y, s); len(p) > 0 {
				cycle = append([]int{y}, p...)
			}
		}
		if len(cycle) > 0 {
			a := make([]string,
				len(cycle))
			for i, v := range cycle {
				a[i] = n.Variables[v].Name
			}
			line(out, "result cycle %s", strings.Join(a,
				" -> "))
			return
		}
		line(out, "result ok")
		parentsY := variableUnion(n.Variables[y].Parents)
		beforeY := familyScore(y,
			parentsY, n)
		afterParentsY := without(parentsY, map[int]bool{x: true})
		if operation == "ADD" {
			afterParentsY = variableUnion(parentsY,
				[]int{x})
		}
		afterY := familyScore(y, afterParentsY, n)
		line(out, "family %s before %s after %s", n.Variables[y].Name,
			format(beforeY), format(afterY))
		change := afterY - beforeY
		if operation == "REVERSE" {
			parentsX := variableUnion(n.Variables[x].Parents)
			beforeX := familyScore(x,
				parentsX, n)
			afterX := familyScore(x, variableUnion(parentsX, []int{y}), n)
			line(out, "family %s before %s after %s",
				n.Variables[x].Name, format(beforeX), format(afterX))
			change += (afterX - beforeX)
		}
		verdict := "worsens"
		if change > 0 {
			verdict = "improves"
		}
		line(out,
			"delta %s %s", format(change), verdict)
	}
}
func main() {
	n := readInput()
	for v := range n.Variables {
		f := learn(v, n.Variables[v].Parents, n)
		co := &n.Variables[v]
		co.Counts,
			co.Learned = f.Counts, f.Learned
		co.Theta = co.Learned
		if co.Source == "GIVEN" {
			co.Theta = co.Given
		}
	}
	s := structure(n)
	all := allVariables(n)
	initial := initialFactors(all,
		nil, n)
	minfill, given := plan(initial, all, "minfill", n), plan(initial, all, "given", n)
	var cpts, structureOut,
		answers, eliminationOut, samplingCSV strings.Builder
	ll := 0.0
	parameters := 0
	for v, co := range n.Variables {
		line(&cpts,
			"variable %s source %s", co.Name, co.Source)
		line(&cpts, "states %s", strings.Join(co.States, " "))
		line(&cpts,
			"parents %s", variableNames(co.Parents, n))
		row := 0
		assignments(co.Parents, n, func(a []int) {
			var combination []string
			for _, p := range co.Parents {
				combination = append(combination, evidenceName(Evidence{p, a[p]}, n))
			}
			name := "-"
			if len(combination) > 0 {
				name = strings.Join(combination,
					" ")
			}
			line(&cpts, "row %s counts %s probs %s", name, integers(co.Counts[row]), numbers(co.Theta[row]))
			row++
		})
		localLL := logLikelihood(co.Counts,
			co.Theta)
		d := (len(co.States) - 1) * len(co.Counts)
		ll += localLL
		parameters += d
		line(&cpts, "loglik %s parameters %d bic %s",
			format(localLL), d, format(localLL-float64(d)*math.Log(float64(len(n.Samples)))/2))
		marginal := posterior([]int{v},
			nil, n).Marginals[v]
		frequencies := make([]float64, len(co.States))
		for _, a := range n.Samples {
			frequencies[a[v]]++
		}
		for i := range frequencies {
			frequencies[i] /= float64(len(n.Samples))
		}
		line(&cpts,
			"marginal model %s data %s", numbers(marginal), numbers(frequencies))
		if co.Source == "LEARNED" {
			difference := "-"
			if len(co.Given) > 0 {
				value := 0.0
				for r, row := range co.Learned {
					for state, p := range row {
						value = math.Max(value, math.Abs(p-co.Given[r][state]))
					}
				}
				difference = format(value)
			}
			line(&cpts,
				"given_difference %s", difference)
		}
		line(&cpts, "")
	}
	line(&cpts, "network samples %d pseudocount %s loglik %s parameters %d bic %s",
		len(n.Samples), format(n.Settings.Alpha), format(ll), parameters, format(ll-float64(parameters)*math.Log(float64(len(n.Samples)))/2))
	edges := 0
	var roots,
		leaves []int
	for v, co := range n.Variables {
		edges += len(co.Parents)
		if len(co.Parents) == 0 {
			roots = append(roots,
				v)
		}
		if len(s.Children[v]) == 0 {
			leaves = append(leaves, v)
		}
	}
	line(&structureOut, "variables %d edges %d",
		len(all), edges)
	line(&structureOut, "topological_order %s", variableNames(s.Topological, n))
	line(&structureOut,
		"roots %s", variableNames(roots, n))
	line(&structureOut, "leaves %s", variableNames(leaves, n))
	line(&structureOut,
		"moral_edges %d width minfill %d given %d", s.MoralEdges, minfill.Width, given.Width)
	for v, co := range n.Variables {
		line(&structureOut,
			"variable %s states %d parents %d children %d depth %d ancestors %d descendants %d blanket %d",
			co.Name, len(co.States), len(co.Parents), len(s.Children[v]), s.Depth[v], len(s.Ancestors[v]), len(s.Descendants[v]),
			len(s.Blankets[v]))
	}
	line(&samplingCSV, "query,samples,variable,state,estimate,exact,abs_error")
	generator := Generator{n.Settings.Seed}
	answerBlocks,
		eliminationBlocks := 0, 0
	for index, query := range n.Queries {
		fields := strings.Fields(query)
		number := index + 1
		switch fields[0] {
		case "DSEP",
			"BLANKET", "EDGE":
			line(&structureOut, "")
			line(&structureOut, "query %d %s", number, query)
			reportStructureQuery(&structureOut,
				query, fields, n, s)
		default:
			if answerBlocks > 0 {
				line(&answers, "")
			}
			answerBlocks++
			line(&answers,
				"query %d %s", number, query)
			switch fields[0] {
			case "QUERY":
				if eliminationBlocks > 0 {
					line(&eliminationOut,
						"")
				}
				eliminationBlocks++
				line(&eliminationOut, "query %d %s", number, query)
				q, e, _ := parseQuery(fields,
					n)
				reportQuery(&answers, &eliminationOut, q, e, n)
			case "MPE":
				if eliminationBlocks > 0 {
					line(&eliminationOut,
						"")
				}
				eliminationBlocks++
				line(&eliminationOut, "query %d %s", number, query)
				var e []Evidence
				for _, token := range fields[1:] {
					e = append(e, evidence(token, n))
				}
				reportMPE(&answers, &eliminationOut, e,
					n)
			case "SAMPLE":
				q, e, counts := parseQuery(fields, n)
				reportSample(&answers, &samplingCSV, number, q,
					e, counts, &generator, s, n)
			case "PREDICT":
				reportPrediction(&answers, n.Names[fields[1]], s, n)
			}
		}
	}
	must(os.MkdirAll("output",
		0755))
	for name, out := range map[string]*strings.Builder{"cpts.txt": &cpts, "structure.txt": &structureOut,
		"answers.txt": &answers, "elimination.txt": &eliminationOut, "sampling.csv": &samplingCSV} {
		write("output/"+name,
			out)
	}
}
