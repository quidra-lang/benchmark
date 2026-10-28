package main

import (
	"fmt"
	"math"
	"os"
	"sort"
	"strings"
)

type System struct {
	K, KFF, G [][]float64
	Results   []Result
	Unstable  int
}
type Change struct {
	Group, Before, After int
	Utilization          float64
}
type Grid struct {
	Cells          [][]byte
	X0, Y1, WC, HC int
}

func format(x float64, digits int) string {
	s := fmt.Sprintf("%.*f", digits, x)
	if strings.HasPrefix(s, "-") && strings.Trim(s[1:], "0.") == "" {
		return s[1:]
	}
	return s
}
func f(x float64) string    { return format(x, 4) }
func key(x float64) float64 { return math.Round(x * 10000) }
func largest(a []float64) int {
	best := 0
	for i := 1; i < len(a); i++ {
		if key(a[i]) > key(a[best]) {
			best = i
		}
	}
	return best
}
func smallest(a []float64) int {
	best := 0
	for i := 1; i < len(a); i++ {
		if key(a[i]) < key(a[best]) {
			best = i
		}
	}
	return best
}
func line(s *strings.Builder, template string, a ...any) { fmt.Fprintf(s, template+"\n", a...) }
func write(path string, s *strings.Builder)              { must(os.WriteFile(path, []byte(s.String()), 0644)) }
func yes(b bool) string {
	if b {
		return "yes"
	}
	return "no"
}
func renumber(m *Model) (int, int, int, int) {
	n := len(m.Nodes)
	adj := make([][]int, n)
	for _, member := range m.Members {
		adj[member.I] = append(adj[member.I],
			member.J)
		adj[member.J] = append(adj[member.J], member.I)
	}
	start := 0
	for i := 1; i < n; i++ {
		if len(adj[i]) < len(adj[start]) {
			start = i
		}
	}
	queue := []int{start}
	seen := map[int]bool{start: true}
	for pos := 0; pos < len(queue); pos++ {
		var neighbors []int
		for _, v := range adj[queue[pos]] {
			if !seen[v] {
				neighbors = append(neighbors, v)
			}
		}
		sort.Slice(neighbors, func(i,
			j int) bool {
			a, b := neighbors[i], neighbors[j]
			return len(adj[a]) < len(adj[b]) || len(adj[a]) == len(adj[b]) && m.Nodes[a].ID < m.Nodes[b].ID
		})
		for _, v := range neighbors {
			seen[v] = true
			queue = append(queue, v)
		}
	}
	m.Number = make([]int, n)
	m.Order = make([]int,
		n)
	for newNumber := 0; newNumber < n; newNumber++ {
		old := queue[n-1-newNumber]
		m.Order[newNumber] = old
		m.Number[old] = newNumber
	}
	metrics := func(number []int) (int,
		int) {
		bandwidth, profile := 0, 0
		for i := 0; i < n; i++ {
			low := number[i]
			for _, j := range adj[i] {
				low = min(low,
					number[j])
				difference := number[i] - number[j]
				if difference < 0 {
					difference = -difference
				}
				bandwidth = max(bandwidth,
					difference)
			}
			profile += number[i] - low
		}
		return bandwidth, profile
	}
	original := make([]int, n)
	for i := range original {
		original[i] = i
	}
	beforeBand,
		beforeProfile := metrics(original)
	afterBand, afterProfile := metrics(m.Number)
	nd := 2 * n
	m.Prescribed = make([]float64,
		nd)
	m.DOFNode = make([]int, nd)
	restrained := make([]bool, nd)
	for node, newNumber := range m.Number {
		m.DOFNode[2*newNumber],
			m.DOFNode[2*newNumber+1] = node, node
	}
	for _, support := range m.Supports {
		for axis, fixed := range support.Fixed {
			if fixed {
				d := 2*m.Number[support.Node] + axis
				restrained[d] = true
				m.Prescribed[d] = support.Prescribed[axis]
			}
		}
	}
	for d := 0; d < nd; d++ {
		if restrained[d] {
			m.Restrained = append(m.Restrained,
				d)
		} else {
			m.Free = append(m.Free, d)
		}
	}
	geometry(m)
	return beforeBand, afterBand, beforeProfile, afterProfile
}
func displacements(system System, force []float64, settlement bool, m Model) []float64 {
	d := make([]float64,
		2*len(m.Nodes))
	if settlement {
		for _, r := range m.Restrained {
			d[r] = m.Prescribed[r]
		}
	}
	b := make([]float64,
		len(m.Free))
	for i, free := range m.Free {
		b[i] = force[free]
		for _, r := range m.Restrained {
			b[i] -= system.K[free][r] * d[r]
		}
	}
	x := solve(system.G,
		b)
	for i, free := range m.Free {
		d[free] = x[i]
	}
	return d
}
func analyze(m Model, sections []int, removed int) System {
	system := System{K: stiffness(m, sections, removed),
		Unstable: -1}
	system.KFF = matrix(len(m.Free), len(m.Free))
	for i, a := range m.Free {
		for j, b := range m.Free {
			system.KFF[i][j] = system.K[a][b]
		}
	}
	var failed int
	system.G,
		failed = cholesky(system.KFF)
	if failed >= 0 {
		system.Unstable = m.Free[failed]
		return system
	}
	for _, load := range m.Cases {
		l := loadVectors(load, m, sections, removed)
		d := displacements(system, l.Total,
			l.Settlement, m)
		r := Result{Name: load.Name, Displacements: d, Forces: axialForces(d, l.P0, m, sections,
			removed), Reactions: reactions(system.K, d, l.Total, m.Restrained), External: l.External}
		system.Results = append(system.Results,
			r)
	}
	for _, combo := range m.Combinations {
		system.Results = append(system.Results, combination(combo,
			system.Results[:len(m.Cases)]))
	}
	return system
}
func unit(system System, node int, m Model, sections []int) Result {
	force := make([]float64, 2*len(m.Nodes))
	force[2*m.Number[node]+1] = -1000
	d := displacements(system,
		force, false, m)
	return Result{Displacements: d, Forces: axialForces(d, make([]float64, len(m.Members)),
		m, sections, -1), Reactions: reactions(system.K, d, force, m.Restrained), External: force}
}
func weight(m Model, sections []int) float64 {
	w := 0.0
	for i, member := range m.Members {
		w += memberWeight(member,
			m.Sections[sections[i]], m.Materials[member.Material])
	}
	return w
}
func memberUtilization(i int, force float64, m Model, sections []int) float64 {
	member := m.Members[i]
	return utilization(force,
		member, m.Sections[sections[i]], m.Materials[member.Material])
}
func magnitudes(d []float64, m Model) []float64 {
	a := make([]float64, len(m.Nodes))
	for node, newNumber := range m.Number {
		x,
			y := d[2*newNumber], d[2*newNumber+1]
		a[node] = math.Sqrt(x*x + y*y)
	}
	return a
}
func newGrid(m Model, wc, hc int) Grid {
	x0, x1, y0, y1 := m.Nodes[0].X, m.Nodes[0].X, m.Nodes[0].Y, m.Nodes[0].Y
	for _, node := range m.Nodes {
		x0 = min(x0, node.X)
		x1 = max(x1, node.X)
		y0 = min(y0, node.Y)
		y1 = max(y1, node.Y)
	}
	w := int(math.Floor(float64(x1-x0)/float64(wc)+0.5)) + 5
	h := int(math.Floor(float64(y1-y0)/float64(hc)+0.5)) + 5
	g := Grid{X0: x0,
		Y1: y1, WC: wc, HC: hc, Cells: make([][]byte, h)}
	for i := range g.Cells {
		g.Cells[i] = []byte(strings.Repeat(" ",
			w))
	}
	return g
}
func (g Grid) point(x, y float64) (int, int) {
	return int(math.Floor((x-float64(g.X0))/float64(g.WC)+0.5)) + 2,
		int(math.Floor((float64(g.Y1)-y)/float64(g.HC)+0.5)) + 2
}
func (g Grid) put(c, r int, value byte) {
	if r >= 0 && r < len(g.Cells) && c >= 0 && c < len(g.Cells[r]) {
		g.Cells[r][c] = value
	}
}
func (g Grid) segment(c0, r0, c1, r1 int, value byte) {
	dc, dr := c1-c0, r1-r0
	if dc < 0 {
		dc = -dc
	}
	if dr > 0 {
		dr = -dr
	}
	sc,
		sr := -1, -1
	if c0 < c1 {
		sc = 1
	}
	if r0 < r1 {
		sr = 1
	}
	err := dc + dr
	c, r := c0, r0
	for {
		g.put(c, r, value)
		if c == c1 && r == r1 {
			break
		}
		e2 := 2 * err
		if e2 >= dr {
			err += dr
			c += sc
		}
		if e2 <= dc {
			err += dc
			r += sr
		}
	}
}
func (g Grid) frame(out *strings.Builder) {
	border := "+" + strings.Repeat("-", len(g.Cells[0])) + "+"
	line(out,
		"%s", border)
	for _, row := range g.Cells {
		line(out, "|%s|", string(row))
	}
	line(out, "%s", border)
}
func ordinate(values []float64, x int, m Model) float64 {
	deck := m.Settings.Deck
	first, last := m.Nodes[deck[0]].X,
		m.Nodes[deck[len(deck)-1]].X
	if x < first || x > last {
		return 0
	}
	if x == last {
		return values[len(values)-1]
	}
	for k := 0; k+1 < len(deck); k++ {
		a,
			b := m.Nodes[deck[k]].X, m.Nodes[deck[k+1]].X
		if a <= x && x < b {
			return values[k] + (values[k+1]-values[k])*float64(x-a)/float64(b-a)
		}
	}
	return 0
}
func vehicleEffects(values []float64, positions []int, m Model) []float64 {
	a := make([]float64, len(positions))
	for i, p := range positions {
		sum := 0.0
		for _, axle := range m.Settings.Axles {
			sum += axle.Force * ordinate(values,
				p-axle.Offset, m)
		}
		a[i] = sum
	}
	return a
}
func main() {
	m := readModel()
	beforeBand, afterBand, beforeProfile, afterProfile := renumber(&m)
	sections := make([]int,
		len(m.Members))
	for i, member := range m.Members {
		sections[i] = member.Section
	}
	var analysis, displacementOut,
		forcesOut, reactionsOut, designOut, influenceOut, drawingOut, vibrationOut strings.Builder
	var system System
	lastRound := 0
	converged := false
	for round := 1; round <= 10; round++ {
		lastRound = round
		system = analyze(m,
			sections, -1)
		combinations := system.Results[len(m.Cases):]
		bestMember, bestCombo := -1, 0
		bestUtil := 0.0
		for i := range m.Members {
			for j, result := range combinations {
				u := memberUtilization(i, result.Forces[i], m, sections)
				if bestMember < 0 || key(u) > key(bestUtil) {
					bestMember,
						bestCombo, bestUtil = i, j, u
				}
			}
		}
		var changes []Change
		for group := range m.Groups {
			next := selectSection(group,
				combinations, m)
			first := -1
			groupMax := 0.0
			found := false
			for i, member := range m.Members {
				if member.Group != group {
					continue
				}
				if first < 0 {
					first = i
				}
				for _, result := range combinations {
					u := memberUtilization(i, result.Forces[i], m, sections)
					if !found || key(u) > key(groupMax) {
						groupMax = u
						found = true
					}
				}
			}
			if next != sections[first] {
				changes = append(changes,
					Change{group, sections[first], next, groupMax})
			}
		}
		line(&designOut, "round %d weight %s max_utilization %s at %d %s changes %d",
			round, f(weight(m, sections)/1000), f(bestUtil), m.Members[bestMember].ID, combinations[bestCombo].Name,
			len(changes))
		for _, change := range changes {
			line(&designOut, "change %s %s %s utilization %s", m.Groups[change.Group],
				m.Sections[change.Before].Name, m.Sections[change.After].Name, f(change.Utilization))
		}
		if len(changes) == 0 {
			converged = true
			break
		}
		if round == 10 {
			break
		}
		for _, change := range changes {
			for i, member := range m.Members {
				if member.Group == change.Group {
					sections[i] = change.After
				}
			}
		}
	}
	status := "not_converged"
	if converged {
		status = "converged"
	}
	line(&designOut,
		"result %s rounds %d", status, lastRound)
	combinations := system.Results[len(m.Cases):]
	governing := make([]float64,
		len(m.Members))
	governingCombo := make([]int, len(m.Members))
	limits := make([]float64, len(m.Members))
	for i := range m.Members {
		u := make([]float64,
			len(combinations))
		for j, result := range combinations {
			u[j] = memberUtilization(i, result.Forces[i],
				m, sections)
		}
		governingCombo[i] = largest(u)
		governing[i] = u[governingCombo[i]]
		limits[i] = slendernessLimit(i,
			combinations, m)
	}
	for group, name := range m.Groups {
		var members []int
		var values []float64
		for i, member := range m.Members {
			if member.Group == group {
				members = append(members, i)
				values = append(values,
					governing[i])
			}
		}
		best := members[largest(values)]
		line(&designOut, "group %s section %s members %d utilization %s at %d",
			name, m.Sections[sections[members[0]]].Name, len(members), f(governing[best]), m.Members[best].ID)
	}
	for i, member := range m.Members {
		section := m.Sections[sections[i]]
		lambda := slenderness(member, section)
		verdict := "over"
		if governing[i] <= 1 && lambda <= limits[i] {
			verdict = "ok"
		}
		line(&designOut,
			"member %d group %s section %s utilization %s governing %s slenderness %s limit %s %s", member.ID,
			m.Groups[member.Group], section.Name, f(governing[i]), combinations[governingCombo[i]].Name, f(lambda),
			f(limits[i]), verdict)
	}
	ranking := make([]int, len(m.Members))
	for i := range ranking {
		ranking[i] = i
	}
	sort.SliceStable(ranking,
		func(i, j int) bool { return key(governing[ranking[i]]) > key(governing[ranking[j]]) })
	for rank, i := range ranking[:min(5,
		len(ranking))] {
		line(&designOut, "rank %d member %d utilization %s", rank+1, m.Members[i].ID, f(governing[i]))
	}
	for i, member := range m.Members {
		values := make([]float64, len(combinations))
		for j, result := range combinations {
			values[j] = result.Forces[i] / 1000
		}
		hi,
			lo := largest(values), smallest(values)
		line(&designOut, "envelope %d max %s %s min %s %s", member.ID,
			f(values[hi]), combinations[hi].Name, f(values[lo]), combinations[lo].Name)
	}
	for section, value := range m.Sections {
		count,
			length := 0, 0.0
		for i, member := range m.Members {
			if sections[i] == section {
				count++
				length += member.Length
			}
		}
		if count > 0 {
			line(&designOut,
				"section %s members %d length %s", value.Name, count, f(length))
		}
	}
	line(&designOut, "weight %s", f(weight(m,
		sections)/1000))
	line(&analysis, "model nodes %d members %d supports %d free_dofs %d restrained_dofs %d indeterminacy %d",
		len(m.Nodes), len(m.Members), len(m.Supports), len(m.Free), len(m.Restrained), len(m.Members)+len(m.Restrained)-2*len(m.Nodes))
	var renumbered []string
	for _, node := range m.Order {
		renumbered = append(renumbered, fmt.Sprint(m.Nodes[node].ID))
	}
	line(&analysis,
		"renumbering %s", strings.Join(renumbered, " "))
	line(&analysis, "bandwidth before %d after %d",
		beforeBand, afterBand)
	line(&analysis, "profile before %d after %d", beforeProfile, afterProfile)
	for _, member := range m.Members {
		line(&analysis, "member %d nodes %d %d length %s cos %s sin %s", member.ID,
			m.Nodes[member.I].ID, m.Nodes[member.J].ID, f(member.Length), format(member.C, 6), format(member.S,
				6))
	}
	line(&displacementOut, "case,node,dx,dy")
	line(&forcesOut, "case,member,force,stress,utilization")
	line(&reactionsOut,
		"case,node,rx,ry")
	for ri, result := range system.Results {
		values := magnitudes(result.Displacements,
			m)
		at := largest(values)
		energy := 0.0
		for i, member := range m.Members {
			force := result.Forces[i]
			material,
				section := m.Materials[member.Material], m.Sections[sections[i]]
			energy += force * force * member.Length / (2 * material.E * section.Area)
			line(&forcesOut,
				"%s,%d,%s,%s,%s", result.Name, member.ID, f(force/1000), f(force/section.Area), f(memberUtilization(i,
					force, m, sections)))
		}
		var totalR, totalFE [2]float64
		for node, newNumber := range m.Number {
			dx,
				dy := result.Displacements[2*newNumber], result.Displacements[2*newNumber+1]
			line(&displacementOut,
				"%s,%d,%s,%s", result.Name, m.Nodes[node].ID, f(dx), f(dy))
			for axis := 0; axis < 2; axis++ {
				d := 2*newNumber + axis
				totalR[axis] += result.Reactions[d]
				totalFE[axis] += result.External[d]
			}
		}
		for _, support := range m.Supports {
			d := 2 * m.Number[support.Node]
			line(&reactionsOut, "%s,%d,%s,%s", result.Name,
				m.Nodes[support.Node].ID, f(result.Reactions[d]/1000), f(result.Reactions[d+1]/1000))
		}
		error,
			scale := equilibrium(result, m)
		verdict := "failed"
		if error <= 0.000001*scale {
			verdict = "ok"
		}
		kind := "case"
		if ri >= len(m.Cases) {
			kind = "combination"
		}
		line(&analysis,
			"%s %s equilibrium %s max_displacement %s at %d energy %s reactions %s %s loads %s %s", kind,
			result.Name, verdict, f(values[at]), m.Nodes[at].ID, f(energy/1000), f(totalR[0]/1000), f(totalR[1]/1000),
			f(totalFE[0]/1000), f(totalFE[1]/1000))
	}
	axes := []string{"x", "y"}
	for _, support := range m.Supports {
		for axis, fixed := range support.Fixed {
			if !fixed {
				continue
			}
			d := 2*m.Number[support.Node] + axis
			values := make([]float64,
				len(combinations))
			uplift := false
			for j, result := range combinations {
				values[j] = result.Reactions[d] / 1000
				if result.Reactions[d] < 0 {
					uplift = true
				}
			}
			hi,
				lo := largest(values), smallest(values)
			fmt.Fprintf(&analysis, "reaction_envelope %d %s max %s %s min %s %s",
				m.Nodes[support.Node].ID, axes[axis], f(values[hi]), combinations[hi].Name, f(values[lo]), combinations[lo].Name)
			if axis == 1 {
				fmt.Fprintf(&analysis,
					" uplift %s", yes(uplift))
			}
			analysis.WriteByte('\n')
		}
	}
	for node := range m.Nodes {
		values := make([]float64,
			len(combinations))
		for j, result := range combinations {
			values[j] = magnitudes(result.Displacements,
				m)[node]
		}
		at := largest(values)
		line(&analysis, "displacement_envelope %d max %s %s", m.Nodes[node].ID,
			f(values[at]), combinations[at].Name)
	}
	deflection := system.Results[m.Settings.Deflection]
	supportY := map[int]bool{}
	for _, support := range m.Supports {
		if support.Fixed[1] {
			supportY[support.Node] = true
		}
	}
	var deckSupports []int
	for i, node := range m.Settings.Deck {
		if supportY[node] {
			deckSupports = append(deckSupports, i)
		}
	}
	for span := 1; span < len(deckSupports); span++ {
		start,
			end := deckSupports[span-1], deckSupports[span]
		a, b := m.Settings.Deck[start], m.Settings.Deck[end]
		xa,
			xb := m.Nodes[a].X, m.Nodes[b].X
		va, vb := deflection.Displacements[2*m.Number[a]+1], deflection.Displacements[2*m.Number[b]+1]
		var deltas []float64
		for i := start; i <= end; i++ {
			node := m.Settings.Deck[i]
			v := deflection.Displacements[2*m.Number[node]+1]
			deltas = append(deltas,
				math.Abs(v-(va+(vb-va)*float64(m.Nodes[node].X-xa)/float64(xb-xa))))
		}
		at := largest(deltas)
		node := m.Settings.Deck[start+at]
		limit := float64(xb-xa) / float64(m.Settings.Ratio)
		verdict := "exceeded"
		if deltas[at] <= limit {
			verdict = "ok"
		}
		line(&analysis,
			"deflection %s span %d %d max %s at %d limit %s %s", deflection.Name, m.Nodes[a].ID, m.Nodes[b].ID,
			f(deltas[at]), m.Nodes[node].ID, f(limit), verdict)
		virtual := unit(system, node, m, sections)
		sum := 0.0
		for i, member := range m.Members {
			sum += deflection.Forces[i] * (virtual.Forces[i] / 1000) * member.Length / (m.Materials[member.Material].E * m.Sections[sections[i]].Area)
		}
		stiffness := -deflection.Displacements[2*m.Number[node]+1]
		check := "failed"
		if math.Abs(sum-stiffness) <= 0.000001*math.Max(1,
			math.Abs(stiffness)) {
			check = "ok"
		}
		line(&analysis, "virtual_work %s node %d stiffness %s virtual %s %s",
			deflection.Name, m.Nodes[node].ID, f(stiffness), f(sum), check)
	}
	for removed, member := range m.Members {
		study := analyze(m,
			sections, removed)
		if study.Unstable >= 0 {
			node := m.DOFNode[study.Unstable]
			line(&analysis, "removal %d unstable at %d %s",
				member.ID, m.Nodes[node].ID, axes[study.Unstable%2])
			continue
		}
		result := study.Results[m.Settings.Removal]
		var remaining []int
		var values []float64
		for i := range m.Members {
			if i != removed {
				remaining = append(remaining,
					i)
				values = append(values, memberUtilization(i, result.Forces[i], m, sections))
			}
		}
		at := largest(values)
		disps := magnitudes(result.Displacements,
			m)
		node := largest(disps)
		line(&analysis, "removal %d stable max_utilization %s at %d max_displacement %s at %d",
			member.ID, f(values[at]), m.Members[remaining[at]].ID, f(disps[node]), m.Nodes[node].ID)
	}
	q := len(m.Settings.Deck)
	forceOrdinates := matrix(len(m.Members), q)
	reactionOrdinates := matrix(2*len(m.Nodes),
		q)
	for k, node := range m.Settings.Deck {
		result := unit(system, node, m, sections)
		for i, value := range result.Forces {
			forceOrdinates[i][k] = value / 1000
		}
		for d, value := range result.Reactions {
			reactionOrdinates[d][k] = value / 1000
		}
	}
	for _, memberIndex := range m.Settings.Influence {
		member,
			values := m.Members[memberIndex], forceOrdinates[memberIndex]
		line(&influenceOut, "influence %d",
			member.ID)
		positive, negative := 0.0, 0.0
		var crossings []float64
		for k, value := range values {
			line(&influenceOut,
				"node %d %s", m.Nodes[m.Settings.Deck[k]].ID, f(value))
			if value > 0 {
				positive += value
			}
			if value < 0 {
				negative += value
			}
			if k+1 < len(values) && ((value > 0 && values[k+1] < 0) || (value < 0 && values[k+1] > 0)) {
				x0,
					x1 := m.Nodes[m.Settings.Deck[k]].X, m.Nodes[m.Settings.Deck[k+1]].X
				crossings = append(crossings,
					float64(x0)+float64(x1-x0)*value/(value-values[k+1]))
			}
		}
		hi, lo := largest(values), smallest(values)
		line(&influenceOut,
			"max %s at %d min %s at %d positive %s negative %s", f(values[hi]), m.Nodes[m.Settings.Deck[hi]].ID,
			f(values[lo]), m.Nodes[m.Settings.Deck[lo]].ID, f(positive), f(negative))
		parts := []string{"crossings",
			fmt.Sprint(len(crossings))}
		for _, x := range crossings {
			parts = append(parts, format(x, 1))
		}
		line(&influenceOut,
			strings.Join(parts, " "))
	}
	var positions []int
	for p := m.Nodes[m.Settings.Deck[0]].X; p <= m.Nodes[m.Settings.Deck[q-1]].X+m.Settings.Axles[len(m.Settings.Axles)-1].Offset; p += m.Settings.Step {
		positions = append(positions,
			p)
	}
	line(&influenceOut, "vehicle axles %d positions %d", len(m.Settings.Axles), len(positions))
	vehicleMax,
		vehicleMin := make([]float64, len(m.Members)), make([]float64, len(m.Members))
	for i, member := range m.Members {
		effects := vehicleEffects(forceOrdinates[i],
			positions, m)
		hi, lo := largest(effects), smallest(effects)
		vehicleMax[i], vehicleMin[i] = effects[hi],
			effects[lo]
		line(&influenceOut, "vehicle_member %d max %s at %d min %s at %d", member.ID, f(effects[hi]),
			positions[hi], f(effects[lo]), positions[lo])
	}
	for _, support := range m.Supports {
		for axis, fixed := range support.Fixed {
			if !fixed {
				continue
			}
			d := 2*m.Number[support.Node] + axis
			effects := vehicleEffects(reactionOrdinates[d],
				positions, m)
			hi, lo := largest(effects), smallest(effects)
			line(&influenceOut, "vehicle_reaction %d %s max %s at %d min %s at %d",
				m.Nodes[support.Node].ID, axes[axis], f(effects[hi]), positions[hi], f(effects[lo]), positions[lo])
		}
	}
	ratingMinimum := 0.0
	ratingMember := -1
	ratingKind := ""
	dead := system.Results[m.Settings.Rating]
	for i, member := range m.Members {
		material, section := m.Materials[member.Material], m.Sections[sections[i]]
		nd := dead.Forces[i] / 1000
		t,
			c := vehicleMax[i], vehicleMin[i]
		pt := section.Area * material.FY / 1000
		pc := math.Min(section.Area*material.FY,
			buckling(member, section, material)) / 1000
		names := [2]string{"none", "none"}
		values := [2]float64{}
		exists := [2]bool{key(t) > 0,
			key(c) < 0}
		if exists[0] {
			values[0] = (pt - m.Settings.GammaD*nd) / (m.Settings.GammaL * t)
			names[0] = f(values[0])
		}
		if exists[1] {
			values[1] = (pc + m.Settings.GammaD*nd) / (m.Settings.GammaL * (-c))
			names[1] = f(values[1])
		}
		for k, value := range values {
			if exists[k] && (ratingMember < 0 || key(value) < key(ratingMinimum)) {
				ratingMember,
					ratingMinimum = i, value
				ratingKind = "tension"
				if k == 1 {
					ratingKind = "compression"
				}
			}
		}
		line(&influenceOut,
			"rating %d tension %s compression %s", member.ID, names[0], names[1])
	}
	line(&influenceOut, "rating_min %s at %d %s",
		f(ratingMinimum), m.Members[ratingMember].ID, ratingKind)
	vibration := system.Results[m.Settings.Vibration]
	mass := make([]float64, len(m.Nodes))
	totalMass := 0.0
	for node, newNumber := range m.Number {
		mass[node] = -vibration.External[2*newNumber+1] / 9.81
		totalMass += mass[node]
	}
	freeMass := make([]float64,
		len(m.Free))
	for i, d := range m.Free {
		freeMass[i] = mass[m.DOFNode[d]]
	}
	line(&vibrationOut, "vibration %s mass %s iterations %d",
		vibration.Name, f(totalMass), m.Settings.Iterations)
	var modes [][]float64
	for mode := 1; mode <= m.Settings.Modes; mode++ {
		x := make([]float64,
			len(m.Free))
		for i := range x {
			x[i] = 1
		}
		for iteration := 0; iteration < m.Settings.Iterations; iteration++ {
			for _, phi := range modes {
				beta := 0.0
				for i := range x {
					beta += phi[i] * freeMass[i] * x[i]
				}
				for i := range x {
					x[i] = x[i] - beta*phi[i]
				}
			}
			b := make([]float64,
				len(x))
			for i := range x {
				b[i] = freeMass[i] * x[i]
			}
			y := solve(system.G, b)
			sum := 0.0
			for i := range y {
				sum += freeMass[i] * y[i] * y[i]
			}
			nu := math.Sqrt(sum)
			for i := range x {
				x[i] = y[i] / nu
			}
		}
		modes = append(modes,
			append([]float64(nil), x...))
		numerator, denominator := 0.0, 0.0
		for i := range x {
			kx := 0.0
			for j := range x {
				kx += system.KFF[i][j] * x[j]
			}
			numerator += x[i] * kx
			denominator += freeMass[i] * x[i] * x[i]
		}
		lambda := numerator / denominator
		frequency := math.Sqrt(1000*lambda) / (2 * 3.141592653589793)
		line(&vibrationOut,
			"mode %d frequency %s period %s", mode, f(frequency), f(1/frequency))
		imax := 0
		for i := 1; i < len(x); i++ {
			if math.Abs(x[i]) > math.Abs(x[imax]) {
				imax = i
			}
		}
		shape := make([]float64,
			2*len(m.Nodes))
		for i, d := range m.Free {
			shape[d] = x[i] / x[imax]
		}
		for node, newNumber := range m.Number {
			line(&vibrationOut,
				"node %d %s %s", m.Nodes[node].ID, f(shape[2*newNumber]), f(shape[2*newNumber+1]))
		}
	}
	for _, drawing := range m.Settings.Drawings {
		g := newGrid(m, drawing.WC, drawing.HC)
		result := system.Results[drawing.Result]
		positions := make([][2]int,
			len(m.Nodes))
		deformed := make([][2]int, len(m.Nodes))
		for node, value := range m.Nodes {
			positions[node][0],
				positions[node][1] = g.point(float64(value.X), float64(value.Y))
			d := 2 * m.Number[node]
			deformed[node][0],
				deformed[node][1] = g.point(float64(value.X)+float64(drawing.Scale)*result.Displacements[d],
				float64(value.Y)+float64(drawing.Scale)*result.Displacements[d+1])
		}
		for _, member := range m.Members {
			a,
				b := positions[member.I], positions[member.J]
			g.segment(a[0], a[1], b[0], b[1], '.')
		}
		for _, p := range positions {
			g.put(p[0],
				p[1], '+')
		}
		for _, member := range m.Members {
			a, b := deformed[member.I], deformed[member.J]
			g.segment(a[0],
				a[1], b[0], b[1], '*')
		}
		for _, p := range deformed {
			g.put(p[0], p[1], 'o')
		}
		line(&drawingOut, "drawing %s magnification %d columns %d rows %d",
			result.Name, drawing.Scale, len(g.Cells[0]), len(g.Cells))
		g.frame(&drawingOut)
	}
	g := newGrid(m,
		m.Settings.MapWC, m.Settings.MapHC)
	for i, member := range m.Members {
		a, b := m.Nodes[member.I],
			m.Nodes[member.J]
		c0, r0 := g.point(float64(a.X), float64(a.Y))
		c1, r1 := g.point(float64(b.X), float64(b.Y))
		value := byte('#')
		if governing[i] < 1 {
			value = byte('0' + int(math.Floor(10*governing[i])))
		}
		g.segment(c0,
			r0, c1, r1, value)
	}
	for _, node := range m.Nodes {
		c, r := g.point(float64(node.X), float64(node.Y))
		g.put(c,
			r, 'o')
	}
	line(&drawingOut, "utilization_map columns %d rows %d", len(g.Cells[0]), len(g.Cells))
	g.frame(&drawingOut)
	must(os.MkdirAll("output",
		0755))
	for name, out := range map[string]*strings.Builder{"analysis.txt": &analysis, "displacements.csv": &displacementOut,
		"member_forces.csv": &forcesOut, "reactions.csv": &reactionsOut, "design.txt": &designOut, "influence.txt": &influenceOut,
		"drawing.txt": &drawingOut, "vibration.txt": &vibrationOut} {
		write("output/"+name, out)
	}
}
