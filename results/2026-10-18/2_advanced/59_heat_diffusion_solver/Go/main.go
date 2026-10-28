package main

import (
	"fmt"
	"math"
	"strings"
)

type Segment struct {
	Name, Edge, Kind string
	Cells            []int
	Face             int
	H, Theta         float64
}
type Source struct {
	Name        string
	Cells       []int
	Power, Duty float64
	Periods     [][2]int
}
type Probe struct {
	Name string
	Cell int
}
type RunConfig struct {
	Name, Method string
	D            int
}
type Params struct {
	Initial, Tolerance, Omega, Alarm, Limit float64
	End, ProbeEvery, MaxIterations          int
	Snapshots                               []int
	Probes                                  []Probe
	Runs                                    []RunConfig
	Reference                               string
	Bands                                   []float64
}
type Snapshot struct {
	Field   []float64
	U, B, Q float64
}
type ProbeRecord struct {
	Time   int
	Values []float64
}
type Run struct {
	Config                                          RunConfig
	Reason                                          string
	Snapshots                                       map[int]Snapshot
	Probes                                          []ProbeRecord
	Final                                           []float64
	Boundary                                        []float64
	Source, Stored, Peak                            float64
	PeakTime, PeakCell, AlarmTime, AlarmCell, Above int
}

func filled(n int, v float64) []float64 {
	a := make([]float64, n)
	for i := range a {
		a[i] = v
	}
	return a
}
func sum(a []float64) float64 {
	s := 0.0
	for _, v := range a {
		s += v
	}
	return s
}
func hottest(x []float64) int {
	p := 0
	for i := 1; i < len(x); i++ {
		if x[i] > x[p] {
			p = i
		}
	}
	return p
}
func minimum(x []float64) float64 {
	v := x[0]
	for _, a := range x[1:] {
		v = math.Min(v, a)
	}
	return v
}
func maxDifference(a, b []float64) float64 {
	m := 0.0
	for i, v := range a {
		m = math.Max(m, math.Abs(v-b[i]))
	}
	return m
}
func verdict(b bool) string {
	if b {
		return "ok"
	}
	return "failed"
}
func yes(b bool) string {
	if b {
		return "yes"
	}
	return "no"
}
func readParams(mesh Mesh) Params {
	p := Params{}
	for _, line := range readLines("input/params.txt") {
		a := strings.Fields(line)
		switch a[0] {
		case "initial":
			p.Initial = number(a[1])
		case "end_time":
			p.End = integer(a[1])
		case "snapshots":
			for _, s := range a[1:] {
				p.Snapshots = append(p.Snapshots, integer(s))
			}
		case "probe_every":
			p.ProbeEvery = integer(a[1])
		case "probe":
			p.Probes = append(p.Probes, Probe{a[1], integer(a[2])*mesh.W + integer(a[3])})
		case "run":
			p.Runs = append(p.Runs, RunConfig{a[1], a[2], integer(a[3])})
		case "reference":
			p.Reference = a[1]
		case "tolerance":
			p.Tolerance = number(a[1])
		case "max_iterations":
			p.MaxIterations = integer(a[1])
		case "omega":
			p.Omega = number(a[1])
		case "bands":
			for _, s := range a[1:] {
				p.Bands = append(p.Bands, number(s))
			}
		case "alarm":
			p.Alarm = number(a[1])
		case "limit":
			p.Limit = number(a[1])
		}
	}
	return p
}
func readBoundary(mesh Mesh, end int) ([]Segment, []Source) {
	segments, sources := []Segment{}, []Source{}
	for _, line := range readLines("input/boundary.txt") {
		a := strings.Fields(line)
		if a[0] == "segment" {
			cells, face := mesh.segmentCells(a[2], integer(a[3]), integer(a[4]))
			s := Segment{Name: a[1], Edge: a[2], Kind: a[5], Cells: cells, Face: face}
			if s.Kind == "fixed" {
				s.Theta = number(a[6])
			} else if s.Kind == "convective" {
				s.H, s.Theta = number(a[6]), number(a[7])
			}
			segments = append(segments, s)
		} else {
			s := Source{Name: a[1], Cells: mesh.sourceCells(integer(a[2]), integer(a[3]), integer(a[4]), integer(a[5])), Power: number(a[6])}
			active := 0
			for i := 7; i < len(a); i += 2 {
				on, off := integer(a[i]), integer(a[i+1])
				s.Periods = append(s.Periods, [2]int{on, off})
				active += min(off, end) - min(on, end)
			}
			s.Duty = float64(active) / float64(end)
			sources = append(sources, s)
		}
	}
	return segments, sources
}
func buildPlate(mesh Mesh, materials []Material, index []int, segments []Segment, sources []Source) Plate {
	n := len(mesh.Codes)
	plate := Plate{Mesh: mesh, Materials: materials, MaterialIndex: index, Faces: make([][4]Face, n),
		C: make([]float64, n), A: make([]float64, n), Beta: make([]float64, n), Sall: make([]float64,
			n)}
	for p := 0; p < n; p++ {
		m := materials[index[p]]
		plate.C[p] = capacity(m, mesh)
		for face, q := range mesh.Neighbors[p] {
			plate.Faces[p][face].Neighbor = q
			if q >= 0 {
				plate.Faces[p][face].G = interiorConductance(m.K, materials[index[q]].K, mesh.Thickness)
			}
		}
	}
	for _, s := range segments {
		for _, p := range s.Cells {
			f := &plate.Faces[p][s.Face]
			k := materials[index[p]].K
			if s.Kind == "fixed" {
				f.G, f.Theta, f.Boundary = fixedConductance(k, mesh.Thickness), s.Theta, true
			} else if s.Kind == "convective" {
				f.G, f.Theta, f.Boundary = convectiveConductance(k, s.H, mesh), s.Theta, true
			}
		}
	}
	for p := 0; p < n; p++ {
		for _, f := range plate.Faces[p] {
			plate.A[p] += f.G
			if f.Boundary {
				plate.Beta[p] += f.G * f.Theta
			}
		}
	}
	for _, s := range sources {
		w := s.Power / float64(len(s.Cells))
		for _, p := range s.Cells {
			plate.Sall[p] += w
		}
	}
	return plate
}
func sourceAt(sources []Source, n, time int) ([]float64, float64) {
	out := make([]float64, n)
	power := 0.0
	for _, s := range sources {
		active := false
		for _, period := range s.Periods {
			if period[0] <= time && time < period[1] {
				active = true
				break
			}
		}
		if active {
			power += s.Power
			w := s.Power / float64(len(s.Cells))
			for _, p := range s.Cells {
				out[p] += w
			}
		}
	}
	return out, power
}
func stored(plate *Plate, x []float64, initial float64) float64 {
	s := 0.0
	for p, v := range x {
		s += plate.C[p] * (v - initial)
	}
	return s
}
func runTransient(plate *Plate, params Params, config RunConfig, segments []Segment, sources []Source, dtMax float64) Run {
	out := Run{Config: config, Snapshots: map[int]Snapshot{}, Boundary: make([]float64, len(segments)), AlarmTime: -1}
	times := append([]int{params.End, params.ProbeEvery}, params.Snapshots...)
	for _, source := range sources {
		for _, period := range source.Periods {
			times = append(times, period[0], period[1])
		}
	}
	for _, t := range times {
		if t%config.D != 0 {
			out.Reason = "step"
			return out
		}
	}
	dt := float64(config.D) / 1000
	if config.Method == "ftcs" && dt > dtMax {
		out.Reason = "unstable"
		return out
	}
	x := filled(len(plate.C), params.Initial)
	observe := func(time int) {
		hot := hottest(x)
		if time == 0 || x[hot] > out.Peak {
			out.Peak, out.PeakTime, out.PeakCell = x[hot], time, hot
		}
		if x[hot] >= params.Alarm {
			if out.AlarmTime < 0 {
				out.AlarmTime, out.AlarmCell = time, hot
			}
			if time > 0 {
				out.Above += config.D
			}
		}
		if time%params.ProbeEvery == 0 {
			values := make([]float64, len(params.Probes))
			for i, p := range params.Probes {
				values[i] = x[p.Cell]
			}
			out.Probes = append(out.Probes, ProbeRecord{time, values})
		}
		for _, t := range params.Snapshots {
			if time == t {
				out.Snapshots[time] = Snapshot{append([]float64(nil), x...), stored(plate, x, params.Initial), sum(out.Boundary), out.Source}
				break
			}
		}
	}
	observe(0)
	for time := 0; time < params.End; time += config.D {
		source, power := sourceAt(sources, len(x), time)
		next, y := step(plate, x, source, dt, config.Method)
		for j, segment := range segments {
			if segment.Kind == "insulated" {
				continue
			}
			s := 0.0
			for _, p := range segment.Cells {
				temperature := x[p]
				if config.Method != "ftcs" {
					if segment.Face < 2 {
						temperature = y[p]
					} else if config.Method == "backward_euler" {
						temperature = next[p]
					} else {
						temperature = (x[p] + next[p]) / 2
					}
				}
				f := plate.Faces[p][segment.Face]
				s += f.G * (f.Theta - temperature)
			}
			out.Boundary[j] += dt * s
		}
		out.Source += dt * power
		x = next
		observe(time + config.D)
	}
	out.Final = x
	out.Stored = stored(plate, x, params.Initial)
	return out
}
func summary(mesh Mesh, x []float64) string {
	hot := hottest(x)
	return fmt.Sprintf("max %s at %s min %s mean %s", fixed(x[hot], 2), cell(mesh, hot), fixed(minimum(x), 2), fixed(sum(x)/float64(len(x)), 2))
}
func runPrefix(c RunConfig) string {
	return fmt.Sprintf("run %s %s dt %s", c.Name, c.Method, timeText(c.D))
}
func snapshotsOutput(plate *Plate, params Params, runs []Run, dtMax float64) {
	out, probes := []string{}, []string{"run,time,probe,temperature"}
	for _, run := range runs {
		prefix := runPrefix(run.Config)
		if run.Reason != "" {
			line := prefix + " rejected " + run.Reason
			if run.Reason == "unstable" {
				line += " max_dt " + fixed(dtMax, 4)
			}
			out = append(out, line)
			continue
		}
		for _, time := range params.Snapshots {
			x := run.Snapshots[time].Field
			out = append(out, prefix+" time "+timeText(time)+" "+summary(plate.Mesh, x))
			out = append(out, fieldLines(plate.Mesh, x)...)
		}
		for _, record := range run.Probes {
			for i, p := range params.Probes {
				probes = append(probes, fmt.Sprintf("%s,%s,%s,%s", run.Config.Name, timeText(record.Time), p.Name, fixed(record.Values[i], 3)))
			}
		}
	}
	writeLines("snapshots.txt", out)
	writeLines("probes.csv", probes)
}
func selectedStats(x []float64, cells []int) (float64, float64, float64) {
	lo, hi, total := x[cells[0]], x[cells[0]], 0.0
	for _, p := range cells {
		lo = math.Min(lo, x[p])
		hi = math.Max(hi, x[p])
		total += x[p]
	}
	return lo, hi, total / float64(len(cells))
}
func solverLine(s Solver) string {
	prefix := "solver " + s.Name
	if s.Name == "sor" || s.Name == "sor_estimated" {
		prefix += " omega " + fixed(s.Omega, 4)
	}
	milestones := []string{}
	for _, k := range s.Milestones {
		t := "never"
		if k > 0 {
			t = fmt.Sprint(k)
		}
		milestones = append(milestones, t)
	}
	return fmt.Sprintf("%s iterations %d converged %s rate %s milestones %s", prefix, len(s.Deltas),
		yes(s.Converged), fixed(s.Rate, 6), strings.Join(milestones, " "))
}
func steadyOutput(plate *Plate, params Params, segments []Segment, sources []Source, solution [][]float64, solvers []Solver) {
	mesh := plate.Mesh
	steady, base := solution[0], solution[1]
	units := solution[2:]
	out := []string{"steady " + summary(mesh, steady)}
	out = append(out, fieldLines(mesh, steady)...)
	for _, material := range plate.Materials {
		lo, hi, mean := selectedStats(steady, material.Cells)
		out = append(out, fmt.Sprintf("material %c %s cells %d min %s max %s mean %s", material.Code, material.Name,
			len(material.Cells), fixed(lo, 2), fixed(hi, 2), fixed(mean, 2)))
	}
	for _, source := range sources {
		_, hi, mean := selectedStats(steady, source.Cells)
		out = append(out, fmt.Sprintf("source %s power %s duty %s mean %s max %s", source.Name, fixed(source.Power,
			4), fixed(source.Duty, 4), fixed(mean, 2), fixed(hi, 2)))
	}
	for _, s := range sources {
		for j, t := range sources {
			total := 0.0
			for _, p := range s.Cells {
				total += units[j][p]
			}
			out = append(out, fmt.Sprintf("influence %s %s %s", s.Name, t.Name, fixed(total/float64(len(s.Cells)), 4)))
		}
	}
	super, duty := append([]float64(nil), base...), append([]float64(nil), base...)
	for p := range steady {
		for j, source := range sources {
			super[p] += source.Power * units[j][p]
			duty[p] += (source.Duty * source.Power) * units[j][p]
		}
	}
	out = append(out, "superposition "+verdict(maxDifference(super, steady) <= .000001))
	for j, source := range sources {
		for _, segment := range segments {
			escape := 0.0
			if segment.Kind != "insulated" {
				for _, p := range segment.Cells {
					escape += plate.Faces[p][segment.Face].G * units[j][p]
				}
			}
			out = append(out, fmt.Sprintf("path %s %s %s", source.Name, segment.Name, fixed(escape, 4)))
		}
	}
	out = append(out, "duty_steady "+summary(mesh, duty))
	for j, source := range sources {
		best, power := 0, 0.0
		for p := range steady {
			v := (params.Limit - (steady[p] - source.Power*units[j][p])) / units[j][p]
			if p == 0 || v < power {
				best, power = p, v
			}
		}
		out = append(out, fmt.Sprintf("headroom %s max_power %s at %s", source.Name, fixed(power, 4), cell(mesh, best)))
	}
	type Interface struct {
		Count             int
		Forward, Backward float64
	}
	interfaces := map[[2]int]Interface{}
	gradient, gp, gq := 0.0, 0, -1
	for p := range steady {
		for _, face := range []int{1, 3} {
			f := plate.Faces[p][face]
			q := f.Neighbor
			if q < 0 {
				continue
			}
			g := math.Abs(steady[p]-steady[q]) / mesh.DX
			if gq < 0 || g > gradient {
				gradient, gp, gq = g, p, q
			}
			a, b := plate.MaterialIndex[p], plate.MaterialIndex[q]
			if a == b {
				continue
			}
			phi := f.G * (steady[p] - steady[q])
			if a > b {
				a, b = b, a
				phi = -phi
			}
			key := [2]int{a, b}
			v := interfaces[key]
			v.Count++
			if phi > 0 {
				v.Forward += phi
			} else if phi < 0 {
				v.Backward += -phi
			}
			interfaces[key] = v
		}
	}
	for a, m1 := range plate.Materials {
		for b := a + 1; b < len(plate.Materials); b++ {
			v := interfaces[[2]int{a, b}]
			if v.Count > 0 {
				out = append(out, fmt.Sprintf("interface %c %c faces %d forward %s backward %s", m1.Code, plate.Materials[b].Code,
					v.Count, fixed(v.Forward, 4), fixed(v.Backward, 4)))
			}
		}
	}
	flows, absoluteFlows := 0.0, 0.0
	for _, segment := range segments {
		flow := 0.0
		if segment.Kind != "insulated" {
			for _, p := range segment.Cells {
				f := plate.Faces[p][segment.Face]
				flow += f.G * (f.Theta - steady[p])
			}
		}
		flows += flow
		absoluteFlows += math.Abs(flow)
		out = append(out, fmt.Sprintf("segment %s %s %s flow %s", segment.Name, segment.Edge, segment.Kind, fixed(flow, 4)))
	}
	totalPower := 0.0
	for _, source := range sources {
		totalPower += source.Power
	}
	out = append(out, "sources "+fixed(totalPower, 4), "balance "+verdict(math.Abs(flows+totalPower) <= .000001*(absoluteFlows+totalPower)),
		fmt.Sprintf("max_gradient %s between %s and %s", fixed(gradient, 2), cell(mesh, gp), cell(mesh,
			gq)))
	for _, s := range solvers {
		out = append(out, solverLine(s))
	}
	writeLines("steady_state.txt", out)
}
func comparisonOutput(plate *Plate, params Params, segments []Segment, runs []Run, reference Run,
	steady, b []float64, solvers []Solver, dtMax, rho, omega float64) {
	out := []string{"ftcs_max_dt " + fixed(dtMax, 4)}
	for _, run := range runs {
		prefix := runPrefix(run.Config)
		if run.Reason != "" {
			out = append(out, prefix+" rejected "+run.Reason)
			continue
		}
		alarm := "never"
		if run.AlarmTime >= 0 {
			alarm = timeText(run.AlarmTime) + " at " + cell(plate.Mesh, run.AlarmCell)
		}
		out = append(out, fmt.Sprintf("%s steps %d peak %s time %s at %s alarm %s above %s", prefix, params.End/run.Config.D,
			fixed(run.Peak, 2), timeText(run.PeakTime), cell(plate.Mesh, run.PeakCell), alarm, timeText(run.Above)))
		boundary := sum(run.Boundary)
		balance := math.Abs(run.Stored-boundary-run.Source) <= .000001*(math.Abs(run.Stored)+math.Abs(boundary)+math.Abs(run.Source))
		out = append(out, fmt.Sprintf("energy %s stored %s boundary %s source %s balance %s", run.Config.Name,
			fixed(run.Stored, 2), fixed(boundary, 2), fixed(run.Source, 2), verdict(balance)))
		for _, time := range params.Snapshots {
			snap := run.Snapshots[time]
			out = append(out, fmt.Sprintf("energy_at %s time %s stored %s boundary %s source %s", run.Config.Name,
				timeText(time), fixed(snap.U, 2), fixed(snap.B, 2), fixed(snap.Q, 2)))
		}
		for _, material := range plate.Materials {
			energy := 0.0
			for _, p := range material.Cells {
				energy += plate.C[p] * (run.Final[p] - params.Initial)
			}
			out = append(out, fmt.Sprintf("energy_material %s %c %s", run.Config.Name, material.Code, fixed(energy, 2)))
		}
		for j, segment := range segments {
			out = append(out, fmt.Sprintf("energy_segment %s %s %s", run.Config.Name, segment.Name, fixed(run.Boundary[j], 2)))
		}
		for j, probe := range params.Probes {
			hi, lo := run.Probes[0].Values[j], run.Probes[0].Values[j]
			maxTime, minTime := run.Probes[0].Time, run.Probes[0].Time
			for _, record := range run.Probes[1:] {
				v := record.Values[j]
				if v > hi {
					hi, maxTime = v, record.Time
				}
				if v < lo {
					lo, minTime = v, record.Time
				}
			}
			out = append(out, fmt.Sprintf("probe_summary %s %s max %s time %s min %s time %s", run.Config.Name,
				probe.Name, fixed(hi, 3), timeText(maxTime), fixed(lo, 3), timeText(minTime)))
		}
		if run.Config.Name != params.Reference {
			for _, time := range params.Snapshots {
				x, z := run.Snapshots[time].Field, reference.Snapshots[time].Field
				squared := 0.0
				for p, v := range x {
					e := math.Abs(v - z[p])
					squared += e * e
				}
				out = append(out, fmt.Sprintf("compare %s %s time %s max_diff %s rms_diff %s", run.Config.Name,
					params.Reference, timeText(time), fixed(maxDifference(x, z), 6), fixed(math.Sqrt(squared/float64(len(x))),
						6)))
			}
		}
		out = append(out, fmt.Sprintf("final %s steady_max_diff %s", run.Config.Name, fixed(maxDifference(run.Final, steady), 6)))
	}
	out = append(out, "steady direct max_residual "+fixed(residual(plate, steady, b), 6))
	for _, s := range solvers {
		out = append(out, fmt.Sprintf("steady %s iterations %d max_diff %s max_residual %s", s.Name, len(s.Deltas), fixed(s.Error, 6), fixed(s.Residual, 6)))
	}
	out = append(out, fmt.Sprintf("jacobi_spectral_radius %s squared %s", fixed(rho, 6), fixed(rho*rho, 6)), "omega_estimated "+fixed(omega, 4))
	writeLines("solver_comparison.txt", out)
}
func isothermsOutput(plate *Plate, params Params, steady []float64, reference Run) {
	out := []string{}
	appendMap := func(label string, x []float64) {
		lines, counts := isotherm(plate.Mesh, x, params.Bands)
		items := []string{}
		for _, c := range counts {
			items = append(items, fmt.Sprint(c))
		}
		out = append(out, label+" counts "+strings.Join(items, " "))
		out = append(out, lines...)
	}
	appendMap("isotherms steady", steady)
	for _, time := range params.Snapshots {
		appendMap("isotherms "+params.Reference+" time "+timeText(time), reference.Snapshots[time].Field)
	}
	writeLines("isotherms.txt", out)
}
func main() {
	mesh := readMesh()
	materials, index := readMaterials(mesh)
	params := readParams(mesh)
	segments, sources := readBoundary(mesh, params.End)
	plate := buildPlate(mesh, materials, index, segments, sources)
	dtMax := plate.C[0] / plate.A[0]
	for p := range plate.C {
		dtMax = math.Min(dtMax, plate.C[p]/plate.A[p])
	}
	b := make([]float64, len(plate.C))
	for p := range b {
		b[p] = plate.Beta[p] + plate.Sall[p]
	}
	right := [][]float64{b, plate.Beta}
	for _, source := range sources {
		unit := make([]float64, len(b))
		for _, p := range source.Cells {
			unit[p] = 1 / float64(len(source.Cells))
		}
		right = append(right, unit)
	}
	solutions := direct(&plate, right)
	jacobi := iterate(&plate, "jacobi", 1, params.Initial, params.Tolerance, params.MaxIterations)
	rho := jacobi.Rate
	omega := 2 / (1 + math.Sqrt(1-rho*rho))
	solvers := []Solver{jacobi, iterate(&plate, "gauss_seidel", 1, params.Initial, params.Tolerance,
		params.MaxIterations), iterate(&plate, "sor", params.Omega, params.Initial, params.Tolerance,
		params.MaxIterations), iterate(&plate, "sor_estimated", omega, params.Initial, params.Tolerance,
		params.MaxIterations)}
	for i := range solvers {
		solvers[i].Error = maxDifference(solvers[i].Field, solutions[0])
		solvers[i].Residual = residual(&plate, solvers[i].Field, b)
	}
	runs := []Run{}
	var reference Run
	for _, config := range params.Runs {
		run := runTransient(&plate, params, config, segments, sources, dtMax)
		runs = append(runs, run)
		if config.Name == params.Reference {
			reference = run
		}
	}
	snapshotsOutput(&plate, params, runs, dtMax)
	steadyOutput(&plate, params, segments, sources, solutions, solvers)
	comparisonOutput(&plate, params, segments, runs, reference, solutions[0], b, solvers, dtMax, rho, omega)
	isothermsOutput(&plate, params, solutions[0], reference)
}
