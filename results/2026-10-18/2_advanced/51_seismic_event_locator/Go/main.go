package main

import (
	"fmt"
	"math"
	"os"
	"sort"
	"strconv"
	"strings"
)

type Jack struct {
	Station           *Station
	DX, DY, DZ, Shift float64
}
type Quality struct {
	Ellipse           Ellipse
	Gap, DMIN, DH, DZ float64
	Grade             string
	Jackknife         []Jack
	Maximum           Jack
}
type Event struct {
	Number       int
	Used         []*Pick
	First, Final LocationRun
	Observations []Observation
	StartRMS     float64
	Quality      Quality
	Magnitudes   []PickMagnitude
	HasML        bool
	ML, MD, MLC  float64
	Cluster      int
}
type Cluster struct {
	Number  int
	Members []int
	Center  [3]float64
	Span    float64
}
type Regression struct {
	N                        int
	Velocity, Intercept, RMS float64
}

func scaledDecimal(value float64, digits int) int64 {
	scale := math.Pow10(digits)
	magnitude := int64(math.Floor(math.Abs(value)*scale + 0.5))
	if value < 0 {
		return -magnitude
	}
	return magnitude
}
func decimal(value float64, digits int) string {
	n := scaledDecimal(value, digits)
	sign := ""
	if n < 0 {
		sign = "-"
		n = -n
	}
	scale := int64(1)
	for i := 0; i < digits; i++ {
		scale *= 10
	}
	if digits == 0 {
		return sign + strconv.FormatInt(n, 10)
	}
	return fmt.Sprintf("%s%d.%0*d", sign, n/scale, digits, n%scale)
}
func timeNotation(sample int) string { return fmt.Sprintf("%d.%02d", sample/100, sample%100) }
func writeLines(name string, lines []string) {
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	if e := os.WriteFile("output/"+name, []byte(strings.Join(lines, "\n")+"\n"), 0644); e != nil {
		panic(e)
	}
}
func stationOrdered(picks []*Pick) []*Pick {
	out := append([]*Pick{}, picks...)
	sort.Slice(out, func(i, j int) bool { return out[i].Station.Order < out[j].Station.Order })
	return out
}
func observations(picks []*Pick, corrected bool) []Observation {
	out := []Observation{}
	for _, pick := range picks {
		time := float64(pick.Sample) / 100
		if corrected {
			time -= pick.Station.TimeCorrection
		}
		out = append(out, Observation{pick.Station, time})
	}
	return out
}
func locateCandidates(candidates []*Candidate, p Params) []*Event {
	events := []*Event{}
	for _, candidate := range candidates {
		ordered := stationOrdered(candidate.Picks)
		first := runLocation(observations(ordered, false), p)
		candidate.Passes = append(candidate.Passes, LocationPass{ordered, first})
		retained := []*Pick{}
		for i, pick := range ordered {
			error := first.Residuals[i]
			if math.Abs(error) > p.real("residual_limit", 0) {
				candidate.Dropped = append(candidate.Dropped, Drop{pick, error})
			} else {
				retained = append(retained, pick)
			}
		}
		if len(candidate.Dropped) > 0 && len(retained) < p.integer("min_stations", 0) {
			candidate.Rejected = true
			for _, pick := range ordered {
				pick.State = "rejected"
			}
			continue
		}
		adopted := first
		if len(candidate.Dropped) > 0 {
			adopted = runLocation(observations(retained, false), p)
			candidate.Passes = append(candidate.Passes, LocationPass{retained, adopted})
		}
		number := len(events) + 1
		candidate.Event = number
		for i, pick := range retained {
			pick.State, pick.Event, pick.FirstResidual = "used", number, adopted.Residuals[i]
			pick.Station.FirstResiduals = append(pick.Station.FirstResiduals, pick.FirstResidual)
		}
		for _, drop := range candidate.Dropped {
			drop.Pick.State, drop.Pick.Event = "dropped", number
		}
		events = append(events, &Event{Number: number, Used: retained, First: adopted})
	}
	return events
}
func qualityForEvent(event *Event, p Params) Quality {
	solution := event.Final.Solution
	quality := Quality{Ellipse: errorEllipse(solution, event.Observations, p.real("velocity", 0)), DMIN: math.Inf(1)}
	angles := []float64{}
	for _, pick := range event.Used {
		station := pick.Station
		angle := math.Atan2(float64(station.X)-solution[0], float64(station.Y)-solution[1]) * 180 / pi
		if angle < 0 {
			angle += 360
		}
		angles = append(angles, angle)
		dx, dy := float64(station.X)-solution[0], float64(station.Y)-solution[1]
		quality.DMIN = math.Min(quality.DMIN, math.Sqrt(dx*dx+dy*dy))
	}
	sort.Float64s(angles)
	quality.Gap = angles[0] + 360 - angles[len(angles)-1]
	for i := 0; i < len(angles)-1; i++ {
		quality.Gap = math.Max(quality.Gap, angles[i+1]-angles[i])
	}
	fits := func(key string) bool {
		return quality.Gap <= p.real(key, 0) && event.Final.RMS <= p.real(key, 1) && quality.Ellipse.SMaj <= p.real(key, 2)
	}
	quality.Grade = "C"
	if fits("quality_a") {
		quality.Grade = "A"
	} else if fits("quality_b") {
		quality.Grade = "B"
	}
	dx, dy := solution[0]-event.First.Solution[0], solution[1]-event.First.Solution[1]
	quality.DH = math.Sqrt(dx*dx + dy*dy)
	quality.DZ = solution[2] - event.First.Solution[2]
	for i, pick := range event.Used {
		remaining := []Observation{}
		for j, o := range event.Observations {
			if i != j {
				remaining = append(remaining, o)
			}
		}
		run := geiger(solution, remaining, p.real("velocity", 0))
		dx, dy, dz := run.Solution[0]-solution[0], run.Solution[1]-solution[1], run.Solution[2]-solution[2]
		jack := Jack{pick.Station, dx, dy, dz, math.Sqrt(dx*dx + dy*dy)}
		quality.Jackknife = append(quality.Jackknife, jack)
		if i == 0 || jack.Shift > quality.Maximum.Shift {
			quality.Maximum = jack
		}
	}
	return quality
}
func relocateEvents(events []*Event, stations []*Station, p Params) {
	for _, station := range stations {
		if len(station.FirstResiduals) > 0 {
			station.TimeCorrection = sum(station.FirstResiduals) / float64(len(station.FirstResiduals))
		}
	}
	for _, event := range events {
		event.Observations = observations(event.Used, true)
		event.StartRMS = rms(event.First.Solution, event.Observations, p.real("velocity", 0))
		event.Final = geiger(event.First.Solution, event.Observations, p.real("velocity", 0))
		for i, pick := range event.Used {
			pick.Residual = event.Final.Residuals[i]
			pick.Station.FinalResiduals = append(pick.Station.FinalResiduals, pick.Residual)
		}
		event.Quality = qualityForEvent(event, p)
	}
}
func computeMagnitudes(events []*Event, stations []*Station, p Params) {
	for _, event := range events {
		local, duration := []float64{}, []float64{}
		for _, pick := range event.Used {
			data := perPickMagnitude(pick, distance(event.Final.Solution, pick.Station)/1000, p)
			event.Magnitudes = append(event.Magnitudes, data)
			duration = append(duration, data.MD)
			if data.HasML {
				local = append(local, data.ML)
			}
		}
		event.HasML = len(local) > 0
		if event.HasML {
			event.ML = median(local)
		}
		event.MD = median(duration)
		for _, m := range event.Magnitudes {
			if m.HasML {
				m.Pick.Station.MagResiduals = append(m.Pick.Station.MagResiduals, m.ML-event.ML)
			}
		}
	}
	for _, s := range stations {
		if len(s.MagResiduals) > 0 {
			s.MagCorrection = sum(s.MagResiduals) / float64(len(s.MagResiduals))
		}
	}
	for _, event := range events {
		corrected := []float64{}
		for _, m := range event.Magnitudes {
			if m.HasML {
				corrected = append(corrected, m.ML-m.Pick.Station.MagCorrection)
			}
		}
		if len(corrected) > 0 {
			event.MLC = median(corrected)
		}
	}
}
func travelTimeRegression(events []*Event) Regression {
	points := [][2]float64{}
	sd, st, sdd, sdt := 0.0, 0.0, 0.0, 0.0
	for _, event := range events {
		for _, pick := range event.Used {
			d, t := distance(event.Final.Solution, pick.Station)/1000, float64(pick.Sample)/100-event.Final.Solution[3]
			points = append(points, [2]float64{d, t})
			sd += d
			st += t
			sdd += d * d
			sdt += d * t
		}
	}
	n := float64(len(points))
	slope := (n*sdt - sd*st) / (n*sdd - sd*sd)
	intercept := (st - slope*sd) / n
	total := 0.0
	for _, point := range points {
		error := point[1] - intercept - slope*point[0]
		total += error * error
	}
	return Regression{len(points), 1000 / slope, intercept, math.Sqrt(total / n)}
}
func clusterEvents(events []*Event, p Params) []Cluster {
	neighbors := make([][]int, len(events))
	for i, a := range events {
		for j := i + 1; j < len(events); j++ {
			b := events[j]
			x, y := a.Final.Solution, b.Final.Solution
			if math.Abs(x[3]-y[3]) > p.real("cluster", 1) {
				continue
			}
			total := 0.0
			for axis := 0; axis < 3; axis++ {
				d := x[axis] - y[axis]
				total += d * d
			}
			if math.Sqrt(total) <= p.real("cluster", 0) {
				neighbors[i] = append(neighbors[i], j)
				neighbors[j] = append(neighbors[j], i)
			}
		}
	}
	seen := make([]bool, len(events))
	clusters := []Cluster{}
	for first := range events {
		if seen[first] {
			continue
		}
		seen[first] = true
		queue := []int{first}
		for cursor := 0; cursor < len(queue); cursor++ {
			for _, other := range neighbors[queue[cursor]] {
				if !seen[other] {
					seen[other] = true
					queue = append(queue, other)
				}
			}
		}
		sort.Ints(queue)
		c := Cluster{Number: len(clusters) + 1}
		earliest, latest := math.Inf(1), math.Inf(-1)
		for _, index := range queue {
			event := events[index]
			event.Cluster = c.Number
			c.Members = append(c.Members, event.Number)
			for axis := 0; axis < 3; axis++ {
				c.Center[axis] += event.Final.Solution[axis]
			}
			earliest = math.Min(earliest, event.Final.Solution[3])
			latest = math.Max(latest, event.Final.Solution[3])
		}
		for axis := range c.Center {
			c.Center[axis] /= float64(len(queue))
		}
		c.Span = latest - earliest
		clusters = append(clusters, c)
	}
	return clusters
}
func reassociate(picks []*Pick, events []*Event, p Params) []*Pick {
	stationSets := make([]map[int]bool, len(events))
	for i, event := range events {
		stationSets[i] = map[int]bool{}
		for _, pick := range event.Used {
			stationSets[i][pick.Station.Order] = true
		}
	}
	added := []*Pick{}
	for _, pick := range picks {
		if pick.State != "unassociated" {
			continue
		}
		best := -1
		bestAbsolute := math.Inf(1)
		residual := 0.0
		for i, event := range events {
			if stationSets[i][pick.Station.Order] {
				continue
			}
			rho := float64(pick.Sample)/100 - event.Final.Solution[3] - distance(event.Final.Solution, pick.Station)/p.real("velocity", 0) - pick.Station.TimeCorrection
			if math.Abs(rho) <= p.real("residual_limit", 0) && math.Abs(rho) < bestAbsolute {
				best, bestAbsolute, residual = i, math.Abs(rho), rho
			}
		}
		if best >= 0 {
			pick.State, pick.Event, pick.Residual = "added", events[best].Number, residual
			stationSets[best][pick.Station.Order] = true
			added = append(added, pick)
		}
	}
	return added
}
func picksFile(picks []*Pick) []string {
	lines := []string{"station,sample,time_s,duration,snr,amplitude,clipped,event,status,residual"}
	for _, pick := range picks {
		clipped := "no"
		if pick.Clipped {
			clipped = "yes"
		}
		event := 0
		if pick.State == "used" || pick.State == "dropped" || pick.State == "added" {
			event = pick.Event
		}
		residual := "-"
		if pick.State == "used" || pick.State == "added" {
			residual = decimal(pick.Residual, 4)
		}
		lines = append(lines, fmt.Sprintf("%s,%d,%s,%d,%s,%d,%s,%d,%s,%s", pick.Station.Code, pick.Sample,
			timeNotation(pick.Sample), pick.Duration, decimal(pick.Ratio, 2), pick.Amplitude, clipped,
			event, pick.State, residual))
	}
	return lines
}
func formatSolution(label string, solution Solution, rms float64) string {
	return fmt.Sprintf("%s x=%s y=%s z=%s t0=%s rms=%s", label, decimal(solution[0], 1), decimal(solution[1],
		1), decimal(solution[2], 1), decimal(solution[3], 3), decimal(rms, 4))
}
func iterationLines(run LocationRun) []string {
	lines := []string{}
	for _, iteration := range run.Trace {
		lines = append(lines, formatSolution(fmt.Sprintf("ITER %d", iteration.Number), iteration.Solution, iteration.RMS))
	}
	return lines
}
func locationPassLines(number int, pass LocationPass, velocity float64) []string {
	codes := []string{}
	for _, pick := range pass.Picks {
		codes = append(codes, pick.Station.Code)
	}
	profile := []string{}
	for _, v := range pass.Run.Grid.Profile {
		profile = append(profile, decimal(v, 4))
	}
	lines := []string{fmt.Sprintf("PASS %d stations=%s", number, strings.Join(codes, ",")), formatSolution("GRID",
		pass.Run.Grid.Solution, pass.Run.Grid.RMS), "PROFILE " + strings.Join(profile, " ")}
	lines = append(lines, iterationLines(pass.Run)...)
	for i, pick := range pass.Picks {
		d := distance(pass.Run.Solution, pick.Station)
		lines = append(lines, fmt.Sprintf("RES %s dist=%s tt=%s obs=%s res=%s", pick.Station.Code, decimal(d,
			1), decimal(d/velocity, 4), timeNotation(pick.Sample), decimal(pass.Run.Residuals[i],
			4)))
	}
	return lines
}
func locationFile(picks []*Pick, candidates []*Candidate, events []*Event, stations []*Station, regression Regression,
	clusters []Cluster, added []*Pick, p Params) []string {
	lines := []string{}
	velocity := p.real("velocity", 0)
	for _, candidate := range candidates {
		lines = append(lines, fmt.Sprintf("CANDIDATE %d picks=%d first=%s", candidate.Number, len(candidate.Picks), timeNotation(candidate.First.Sample)))
		lines = append(lines, locationPassLines(1, candidate.Passes[0], velocity)...)
		for _, drop := range candidate.Dropped {
			lines = append(lines, "DROP "+drop.Pick.Station.Code+" res="+decimal(drop.Residual, 4))
		}
		if candidate.Rejected {
			lines = append(lines, fmt.Sprintf("RESULT REJECTED stations=%d", len(candidate.Picks)-len(candidate.Dropped)))
		} else {
			if len(candidate.Passes) == 2 {
				lines = append(lines, locationPassLines(2, candidate.Passes[1], velocity)...)
			}
			lines = append(lines, fmt.Sprintf("RESULT EVENT %d", candidate.Event))
		}
	}
	lines = append(lines, "CORRECTIONS")
	for _, s := range stations {
		lines = append(lines, fmt.Sprintf("%s n=%d correction=%s", s.Code, len(s.FirstResiduals), decimal(s.TimeCorrection, 4)))
	}
	for _, event := range events {
		lines = append(lines, fmt.Sprintf("EVENT %d", event.Number), formatSolution("START", event.First.Solution, event.StartRMS))
		lines = append(lines, iterationLines(event.Final)...)
		for _, pick := range event.Used {
			d := distance(event.Final.Solution, pick.Station)
			lines = append(lines, fmt.Sprintf("RES %s dist=%s tt=%s obs=%s corr=%s res=%s", pick.Station.Code,
				decimal(d, 1), decimal(d/velocity, 4), timeNotation(pick.Sample), decimal(pick.Station.TimeCorrection,
					4), decimal(pick.Residual, 4)))
		}
		q := event.Quality
		e := q.Ellipse
		lines = append(lines, fmt.Sprintf("ELLIPSE smaj=%s smin=%s az=%s erz=%s ert=%s", decimal(e.SMaj,
			1), decimal(e.SMin, 1), decimal(e.Az, 1), decimal(e.Erz, 1), decimal(e.Ert, 4)), "SHIFT dh="+decimal(q.DH,
			1)+" dz="+decimal(q.DZ, 1), "GAP "+decimal(q.Gap, 1)+" DMIN "+decimal(q.DMIN, 1)+" QUALITY "+q.Grade)
		for _, j := range q.Jackknife {
			lines = append(lines, fmt.Sprintf("JACK %s dx=%s dy=%s dz=%s shift=%s", j.Station.Code, decimal(j.DX,
				1), decimal(j.DY, 1), decimal(j.DZ, 1), decimal(j.Shift, 1)))
		}
		lines = append(lines, "JACKKNIFE max="+decimal(q.Maximum.Shift, 1)+" station="+q.Maximum.Station.Code)
	}
	lines = append(lines, fmt.Sprintf("FIT n=%d velocity=%s intercept=%s rms=%s", regression.N, decimal(regression.Velocity,
		1), decimal(regression.Intercept, 4), decimal(regression.RMS, 4)))
	for _, c := range clusters {
		if len(c.Members) < 2 {
			continue
		}
		members := []string{}
		for _, v := range c.Members {
			members = append(members, strconv.Itoa(v))
		}
		lines = append(lines, fmt.Sprintf("CLUSTER %d events=%s x=%s y=%s z=%s span=%s", c.Number, strings.Join(members,
			","), decimal(c.Center[0], 1), decimal(c.Center[1], 1), decimal(c.Center[2], 1), decimal(c.Span,
			3)))
	}
	lines = append(lines, "ADDED")
	for _, pick := range added {
		lines = append(lines, fmt.Sprintf("%s sample=%d event=%d res=%s", pick.Station.Code, pick.Sample, pick.Event, decimal(pick.Residual, 4)))
	}
	rejected, unassociated := 0, 0
	for _, c := range candidates {
		if c.Rejected {
			rejected++
		}
	}
	for _, pick := range picks {
		if pick.State == "unassociated" {
			unassociated++
		}
	}
	lines = append(lines, fmt.Sprintf("SUMMARY picks=%d candidates=%d events=%d rejected=%d unassociated=%d",
		len(picks), len(candidates), len(events), rejected, unassociated))
	depths := []float64{}
	qualities := map[string]int{}
	rmsTotal := 0.0
	for _, event := range events {
		depths = append(depths, event.Final.Solution[2])
		qualities[event.Quality.Grade]++
		rmsTotal += event.Final.RMS
	}
	ordered := append([]float64{}, depths...)
	sort.Float64s(ordered)
	lines = append(lines, "DEPTH min="+decimal(ordered[0], 1)+" median="+decimal(median(depths), 1)+" max="+decimal(ordered[len(ordered)-1],
		1), fmt.Sprintf("QUALITY A=%d B=%d C=%d mean_rms=%s", qualities["A"], qualities["B"], qualities["C"],
		decimal(rmsTotal/float64(len(events)), 4)))
	return lines
}
func optionalMagnitude(value float64, present bool) string {
	if !present {
		return "-"
	}
	return decimal(value, 2)
}
func catalogFile(events []*Event) []string {
	lines := []string{"event,origin_time,x,y,depth,rms,stations,gap,dmin,smaj,smin,azimuth,erz,ml,md,quality,cluster"}
	for _, event := range events {
		s, q := event.Final.Solution, event.Quality
		e := q.Ellipse
		fields := []string{strconv.Itoa(event.Number), decimal(s[3], 3), decimal(s[0], 1), decimal(s[1],
			1), decimal(s[2], 1), decimal(event.Final.RMS, 4), strconv.Itoa(len(event.Used)), decimal(q.Gap,
			1), decimal(q.DMIN, 1), decimal(e.SMaj, 1), decimal(e.SMin, 1), decimal(e.Az, 1), decimal(e.Erz,
			1), optionalMagnitude(event.ML, event.HasML), decimal(event.MD, 2), q.Grade, strconv.Itoa(event.Cluster)}
		lines = append(lines, strings.Join(fields, ","))
	}
	return lines
}
func blankCanvas(width, height int) [][]byte {
	rows := make([][]byte, height)
	for i := range rows {
		rows[i] = []byte(strings.Repeat(" ", width))
	}
	return rows
}
func framed(rows [][]byte) []string {
	border := "+" + strings.Repeat("-", len(rows[0])) + "+"
	out := []string{border}
	for _, row := range rows {
		out = append(out, "|"+string(row)+"|")
	}
	return append(out, border)
}
func timeline(events []*Event, p Params) []string {
	duration, width, low, high, height := p.integer("timeline", 0), p.integer("timeline", 1), p.integer("timeline",
		2), p.integer("timeline", 3), p.integer("timeline", 4)
	rows := blankCanvas(width, height)
	for _, event := range events {
		if !event.HasML {
			continue
		}
		t, h := scaledDecimal(event.Final.Solution[3], 3), scaledDecimal(event.ML, 2)
		if t < 0 || t >= 1000*int64(duration) || h < 100*int64(low) {
			continue
		}
		column := int(t * int64(width) / (1000 * int64(duration)))
		level := min(int((h-100*int64(low))*int64(height)/(100*int64(high-low))), height-1)
		for k := 0; k <= level; k++ {
			row := height - 1 - k
			if k == level {
				rows[row][column] = 'o'
			} else if rows[row][column] == ' ' {
				rows[row][column] = '|'
			}
		}
	}
	return append([]string{fmt.Sprintf("TIMELINE t=0..%d ML=%d..%d", duration, low, high)}, framed(rows)...)
}
func magnitudeFile(events []*Event, stats FrequencyStats, p Params) []string {
	lines := []string{}
	for _, event := range events {
		available := 0
		for _, m := range event.Magnitudes {
			if m.HasML {
				available++
			}
		}
		lines = append(lines, fmt.Sprintf("EVENT %d ML=%s n=%d MD=%s", event.Number, optionalMagnitude(event.ML, event.HasML), available, decimal(event.MD, 2)))
		for _, m := range event.Magnitudes {
			pick := m.Pick
			prefix := fmt.Sprintf("%s r=%s amp=%d ", pick.Station.Code, decimal(m.R, 3), pick.Amplitude)
			if m.HasML {
				prefix += "ml=" + decimal(m.ML, 2) + " res=" + decimal(m.ML-event.ML, 2) + " "
			} else {
				prefix += "clipped "
			}
			lines = append(lines, prefix+fmt.Sprintf("dur=%d md=%s", pick.Duration, decimal(m.MD, 2)))
		}
	}
	lines = append(lines, "CORRECTED")
	for _, event := range events {
		lines = append(lines, fmt.Sprintf("EVENT %d MLC=%s", event.Number, optionalMagnitude(event.MLC, event.HasML)))
	}
	lines = append(lines, "FMD")
	cumulative := 0
	for _, count := range stats.Classes {
		cumulative += count
	}
	for c := stats.Minimum; c <= stats.Maximum; c++ {
		lines = append(lines, fmt.Sprintf("M=%s N=%d CUM=%d", magnitudeClass(c), stats.Classes[c], cumulative))
		cumulative -= stats.Classes[c]
	}
	lines = append(lines, "MC "+magnitudeClass(stats.Completeness), fmt.Sprintf("BVALUE %s SIGMA %s N %d",
		decimal(stats.BValue, 3), decimal(stats.Sigma, 3), stats.NB), "AVALUE "+decimal(stats.AValue,
		3), fmt.Sprintf("MLMD n=%d slope=%s intercept=%s r=%s mean_diff=%s", stats.N, decimal(stats.Slope,
		3), decimal(stats.Intercept, 3), decimal(stats.R, 3), decimal(stats.MeanDiff, 3)))
	return append(lines, timeline(events, p)...)
}
func residualRMS(values []float64) string {
	if len(values) == 0 {
		return "-"
	}
	total := 0.0
	for _, v := range values {
		total += v * v
	}
	return decimal(math.Sqrt(total/float64(len(values))), 4)
}
func stationFile(stations []*Station) []string {
	lines := []string{}
	for _, s := range stations {
		states := map[string]int{}
		for _, pick := range s.Picks {
			states[pick.State]++
		}
		lines = append(lines, fmt.Sprintf("STATION %s x=%d y=%d elevation=%d", s.Code, s.X, s.Y, s.Elevation),
			fmt.Sprintf("SAMPLES start=%d count=%d mean=%d noise=%s peak=%d clipped=%d", s.Start,
				len(s.Samples), s.Mean, decimal(s.Noise, 1), s.Peak, s.ClippedSamples), fmt.Sprintf("TRIGGERS total=%d short=%d picks=%d",
				s.Triggers, s.ShortTriggers, len(s.Picks)), fmt.Sprintf("PICKS used=%d dropped=%d added=%d rejected=%d unassociated=%d",
				states["used"], states["dropped"], states["added"], states["rejected"], states["unassociated"]),
			fmt.Sprintf("RESIDUALS n=%d rms=%s correction=%s after=%s", len(s.FirstResiduals), residualRMS(s.FirstResiduals),
				decimal(s.TimeCorrection, 4), residualRMS(s.FinalResiduals)), fmt.Sprintf("MAGNITUDES n=%d correction=%s",
				len(s.MagResiduals), decimal(s.MagCorrection, 2)))
	}
	return lines
}

type PlotPosition struct {
	Column, Row int
	Valid       bool
}

func positionText(p PlotPosition) string {
	if !p.Valid {
		return "outside"
	}
	return fmt.Sprintf("%d,%d", p.Column, p.Row)
}
func eventSymbol(event *Event) byte {
	if !event.HasML {
		return '?'
	}
	h := scaledDecimal(event.ML, 2)
	if h < 100 {
		return '.'
	}
	if h < 200 {
		return 'o'
	}
	if h < 300 {
		return 'O'
	}
	return '@'
}
func eventPositions(event *Event, p Params) [3]PlotPosition {
	x, y, z := scaledDecimal(event.Final.Solution[0], 1), scaledDecimal(event.Final.Solution[1], 1), scaledDecimal(event.Final.Solution[2], 1)
	left, right, bottom, top := int64(p.integer("map_area", 0)), int64(p.integer("map_area", 1)), int64(p.integer("map_area", 2)), int64(p.integer("map_area", 3))
	width, height := int64(p.integer("map_size", 0)), int64(p.integer("map_size", 1))
	limit, sectionHeight := int64(p.integer("section", 0)), int64(p.integer("section", 1))
	positions := [3]PlotPosition{}
	if 10*left <= x && x < 10*right && 10*bottom <= y && y < 10*top {
		positions[0] = PlotPosition{int((x - 10*left) * width / (10 * (right - left))), int(height - 1 - (y-10*bottom)*height/(10*(top-bottom))), true}
	}
	if 10*left <= x && x < 10*right && z < 10*limit {
		positions[1] = PlotPosition{int((x - 10*left) * width / (10 * (right - left))), int(z * sectionHeight / (10 * limit)), true}
	}
	if 10*bottom <= y && y < 10*top && z < 10*limit {
		positions[2] = PlotPosition{int((y - 10*bottom) * width / (10 * (top - bottom))), int(z * sectionHeight / (10 * limit)), true}
	}
	return positions
}
func stationPosition(s *Station, p Params) PlotPosition {
	left, right, bottom, top := p.integer("map_area", 0), p.integer("map_area", 1), p.integer("map_area", 2), p.integer("map_area", 3)
	if s.X < left || s.X >= right || s.Y < bottom || s.Y >= top {
		return PlotPosition{}
	}
	return PlotPosition{(s.X - left) * p.integer("map_size", 0) / (right - left), p.integer("map_size",
		1) - 1 - (s.Y-bottom)*p.integer("map_size", 1)/(top-bottom), true}
}
func placePoint(rows [][]byte, position PlotPosition, symbol byte) {
	if !position.Valid {
		return
	}
	rank := map[byte]int{' ': -1, '?': 0, '.': 1, 'o': 2, 'O': 3, '@': 4, '^': 5}
	if rank[symbol] > rank[rows[position.Row][position.Column]] {
		rows[position.Row][position.Column] = symbol
	}
}
func mapFile(events []*Event, stations []*Station, p Params) []string {
	width, height, sectionHeight := p.integer("map_size", 0), p.integer("map_size", 1), p.integer("section", 1)
	grids := [3][][]byte{blankCanvas(width, height), blankCanvas(width, sectionHeight), blankCanvas(width, sectionHeight)}
	locations := make([][3]PlotPosition, len(events))
	for i, event := range events {
		locations[i] = eventPositions(event, p)
		for j, position := range locations[i] {
			placePoint(grids[j], position, eventSymbol(event))
		}
	}
	stationLocations := []PlotPosition{}
	for _, s := range stations {
		position := stationPosition(s, p)
		stationLocations = append(stationLocations, position)
		placePoint(grids[0], position, '^')
	}
	left, right, bottom, top, limit := p.integer("map_area", 0), p.integer("map_area", 1), p.integer("map_area",
		2), p.integer("map_area", 3), p.integer("section", 0)
	headings := []string{fmt.Sprintf("MAP x=%d..%d y=%d..%d", left, right, bottom, top), fmt.Sprintf("SECTION EW x=%d..%d z=0..%d",
		left, right, limit), fmt.Sprintf("SECTION NS y=%d..%d z=0..%d", bottom, top, limit)}
	lines := []string{}
	for i, heading := range headings {
		lines = append(lines, heading)
		lines = append(lines, framed(grids[i])...)
	}
	lines = append(lines, "LEGEND ^ station . ML<1 o ML<2 O ML<3 @ ML>=3 ? no ML")
	for i, s := range stations {
		lines = append(lines, "STATION "+s.Code+" map="+positionText(stationLocations[i]))
	}
	for i, event := range events {
		positions := locations[i]
		lines = append(lines, fmt.Sprintf("EVENT %d %c map=%s ew=%s ns=%s", event.Number, eventSymbol(event),
			positionText(positions[0]), positionText(positions[1]), positionText(positions[2])))
	}
	return lines
}
func main() {
	stations, p := loadInputs()
	picks := []*Pick{}
	for _, station := range stations {
		picks = append(picks, detectStation(station, p)...)
	}
	sort.Slice(picks, func(i, j int) bool {
		return picks[i].Sample < picks[j].Sample || picks[i].Sample == picks[j].Sample && picks[i].Station.Order < picks[j].Station.Order
	})
	candidates := associate(picks, p.integer("association_window", 0), p.integer("min_stations", 0))
	events := locateCandidates(candidates, p)
	relocateEvents(events, stations, p)
	computeMagnitudes(events, stations, p)
	regression := travelTimeRegression(events)
	clusters := clusterEvents(events, p)
	added := reassociate(picks, events, p)
	stats := frequencyStatistics(events)
	writeLines("picks.csv", picksFile(picks))
	writeLines("locations.txt", locationFile(picks, candidates, events, stations, regression, clusters, added, p))
	writeLines("catalog.csv", catalogFile(events))
	writeLines("magnitudes.txt", magnitudeFile(events, stats, p))
	writeLines("stations.txt", stationFile(stations))
	writeLines("map.txt", mapFile(events, stations, p))
}
