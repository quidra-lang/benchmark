package main

import (
	"fmt"
	"math"
	"os"
	"sort"
	"strings"
)

type Classification struct {
	LevelA, LevelB, TrackA, TrackB, Angle float64
	Geometry, Severity                    string
	Sector                                int
}
type Transit struct {
	Flight, Sector, Previous, Next int
	Entry, Exit                    float64
}
type Alert struct {
	A, B, First, Last, Samples int
	Predicted, Minimum, Lead   float64
	True                       bool
}
type LevelUsage struct {
	Flights map[int]bool
	Time    float64
}

func pair(a, b int) [2]int {
	if a > b {
		a, b = b, a
	}
	return [2]int{a, b}
}
func pairName(a, b int, plans []Plan) string { return plans[a].Callsign + "-" + plans[b].Callsign }
func track(s Segment) float64 {
	theta := math.Atan2(s.Velocity.X, s.Velocity.Y) * 180 / 3.141592653589793
	if theta < 0 {
		theta += 360
	}
	return theta
}
func contains(s Sector, p Vec) bool {
	return float64(s.X1)/10 <= p.X && p.X < float64(s.X2)/10 && float64(s.Y1)/10 <= p.Y && p.Y < float64(s.Y2)/10 && float64(s.Lower*100) <= p.Z && p.Z < float64(s.Upper*100)
}
func classify(c Conflict, trajectories []Trajectory, in Input) Classification {
	a, b := trajectories[c.A].Segments[c.Closest.A],
		trajectories[c.B].Segments[c.Closest.B]
	pa, pb := a.at(c.Closest.Loss.Time), b.at(c.Closest.Loss.Time)
	r := Classification{LevelA: pa.Z / 100,
		LevelB: pb.Z / 100, TrackA: track(a), TrackB: track(b), Sector: -1}
	g := math.Abs(r.TrackA - r.TrackB)
	r.Angle = g
	if g > 180 {
		r.Angle = 360 - g
	}
	dot := a.Velocity.X*b.Velocity.X + a.Velocity.Y*b.Velocity.Y
	cross := a.Velocity.X*b.Velocity.Y - a.Velocity.Y*b.Velocity.X
	r.Geometry = "crossing"
	if dot*dot > cross*cross {
		r.Geometry = "trailing"
		if dot < 0 {
			r.Geometry = "head_on"
		}
	}
	r.Severity = "LOW"
	d := c.Closest.Loss.Distance
	if 10*d < 4*float64(in.Settings.DH) {
		r.Severity = "HIGH"
	} else if 10*d < 7*float64(in.Settings.DH) {
		r.Severity = "MEDIUM"
	}
	midpoint := Vec{(pa.X + pb.X) / 2,
		(pa.Y + pb.Y) / 2, (pa.Z + pb.Z) / 2}
	for i, s := range in.Sectors {
		if contains(s, midpoint) {
			r.Sector = i
			break
		}
	}
	return r
}
func active(c Conflict, time float64) bool { return c.Start <= time && time < c.End }
func sectorName(index int, in Input) string {
	if index < 0 {
		return "-"
	}
	return in.Sectors[index].Name
}
func segmentInside(segment Segment, sector Sector) (float64, float64, bool) {
	lo, hi := segment.Start, segment.End
	positions := [3]float64{segment.Position.X,
		segment.Position.Y, segment.Position.Z}
	velocities := [3]float64{segment.Velocity.X, segment.Velocity.Y,
		segment.Velocity.Z}
	lower := [3]float64{float64(sector.X1) / 10, float64(sector.Y1) / 10, float64(sector.Lower * 100)}
	upper := [3]float64{float64(sector.X2) / 10,
		float64(sector.Y2) / 10, float64(sector.Upper * 100)}
	for axis := 0; axis < 3; axis++ {
		p, v, a, b := positions[axis],
			velocities[axis], lower[axis], upper[axis]
		if v == 0 {
			if !(a <= p && p < b) {
				return 0, 0, false
			}
		} else {
			r1,
				r2 := (a-p)/v, (b-p)/v
			lo = math.Max(lo, segment.Start+math.Min(r1, r2))
			hi = math.Min(hi, segment.Start+math.Max(r1,
				r2))
		}
	}
	return lo, hi, hi-lo > 1e-6
}
func transits(trajectories []Trajectory, in Input) []Transit {
	var result []Transit
	for flight, trajectory := range trajectories {
		var times []Transit
		for sector, s := range in.Sectors {
			var joined []Transit
			for _, segment := range trajectory.Segments {
				lo, hi, exists := segmentInside(segment,
					s)
				if !exists {
					continue
				}
				if len(joined) > 0 && lo-joined[len(joined)-1].Exit <= 1e-6 {
					joined[len(joined)-1].Exit = hi
				} else {
					joined = append(joined,
						Transit{flight, sector, -1, -1, lo, hi})
				}
			}
			times = append(times, joined...)
		}
		sort.SliceStable(times, func(i,
			j int) bool {
			a, b := times[i], times[j]
			return a.Entry < b.Entry || a.Entry == b.Entry && a.Sector < b.Sector
		})
		for i := 1; i < len(times); i++ {
			if math.Abs(times[i].Entry-times[i-1].Exit) <= 1e-6 {
				times[i-1].Next = times[i].Sector
				times[i].Previous = times[i-1].Sector
			}
		}
		result = append(result,
			times...)
	}
	return result
}
func sampleTimes(settings Settings) []int {
	var a []int
	for t := settings.Ta; t < settings.Tb; t += 60 {
		a = append(a, t)
	}
	return a
}
func occupancy(trajectories []Trajectory, in Input, times []int) [][]int {
	a := make([][]int, len(in.Sectors))
	for i := range a {
		a[i] = make([]int,
			len(times))
	}
	for j, time := range times {
		for _, trajectory := range trajectories {
			p, _, exists := trajectory.at(float64(time))
			if !exists {
				continue
			}
			for sector, s := range in.Sectors {
				if contains(s, p) {
					a[sector][j]++
				}
			}
		}
	}
	return a
}
func reportConflicts(out *strings.Builder, name string, list []Conflict, classes []Classification, trajectories []Trajectory,
	in Input, resolved, finalPairs map[[2]int]bool) {
	line(out, "CONFLICTS plan=%s count=%d", name, len(list))
	counts := map[string]int{}
	total := 0.0
	minDistance := "-"
	minimum := math.MaxFloat64
	for i, c := range list {
		cl := classes[i]
		outcome := "indirect"
		if finalPairs[pair(c.A, c.B)] {
			outcome = "remaining"
		} else if resolved[pair(c.A,
			c.B)] {
			outcome = "resolved"
		}
		piece := c.Closest
		a, b := trajectories[c.A].Segments[piece.A], trajectories[c.B].Segments[piece.B]
		line(out,
			"CONFLICT %d %s start=%s end=%s duration=%s outcome=%s", i+1, pairName(c.A, c.B, in.Plans), f(c.Start),
			f(c.End), f(c.End-c.Start), outcome)
		line(out, "  CPA t=%s dist=%s vert=%s levels=%s/%s tracks=%s/%s angle=%s",
			f(piece.Loss.Time), f(piece.Loss.Distance), format(piece.Loss.Vertical, 1), format(cl.LevelA, 2), format(cl.LevelB,
				2), format(cl.TrackA, 1), format(cl.TrackB, 1), format(cl.Angle, 1))
		line(out, "  TYPE geometry=%s phases=%s/%s segments=%d/%d sector=%s severity=%s",
			cl.Geometry, a.Phase, b.Phase, a.Number, b.Number, sectorName(cl.Sector, in), cl.Severity)
		for _, p := range c.Pieces {
			line(out,
				"  PIECE %d/%d %s %s", p.A+1, p.B+1, f(p.Loss.Lo), f(p.Loss.Hi))
		}
		total += c.End - c.Start
		minimum = math.Min(minimum,
			piece.Loss.Distance)
		counts[cl.Geometry]++
		counts[cl.Severity]++
	}
	if len(list) > 0 {
		minDistance = f(minimum)
	}
	line(out,
		"SUMMARY count=%d total=%s min_dist=%s head_on=%d crossing=%d trailing=%d high=%d medium=%d low=%d",
		len(list), f(total), minDistance, counts["head_on"], counts["crossing"], counts["trailing"], counts["HIGH"],
		counts["MEDIUM"], counts["LOW"])
	involved := map[int]bool{}
	for flight, plan := range in.Plans {
		number := 0
		first := 0.0
		partners := map[int]bool{}
		for _, c := range list {
			if c.A == flight || c.B == flight {
				if number == 0 {
					first = c.Start
				}
				number++
				other := c.A
				if c.A == flight {
					other = c.B
				}
				partners[other] = true
			}
		}
		if number == 0 {
			continue
		}
		involved[flight] = true
		var names []string
		for i, plan := range in.Plans {
			if partners[i] {
				names = append(names, plan.Callsign)
			}
		}
		line(out, "FLIGHT %s conflicts=%d first=%s partners=%s",
			plan.Callsign, number, f(first), strings.Join(names, ","))
	}
	line(out, "TIMELINE from=%d to=%d step=60",
		in.Settings.Ta, in.Settings.Tb)
	for flight, plan := range in.Plans {
		if !involved[flight] {
			continue
		}
		var timeline strings.Builder
		for _, time := range sampleTimes(in.Settings) {
			_, _, exists := trajectories[flight].at(float64(time))
			mark := byte('.')
			if exists {
				mark = '-'
				for _, c := range list {
					if (c.A == flight || c.B == flight) && active(c, float64(time)) {
						mark = 'X'
						break
					}
				}
			}
			timeline.WriteByte(mark)
		}
		line(out,
			"%s %s", plan.Callsign, timeline.String())
	}
}
func levelUsage(trajectories []Trajectory) map[int]*LevelUsage {
	result := map[int]*LevelUsage{}
	for flight, trajectory := range trajectories {
		for _, s := range trajectory.Segments {
			if s.Phase != "LVL" {
				continue
			}
			level := int(s.Position.Z / 100)
			usage := result[level]
			if usage == nil {
				usage = &LevelUsage{Flights: map[int]bool{}}
				result[level] = usage
			}
			usage.Flights[flight] = true
			usage.Time += s.End - s.Start
		}
	}
	return result
}
func reportSectors(loadOut, report *strings.Builder, trajectories [2][]Trajectory, lists [2][]Transit,
	classes [2][]Classification, in Input, times []int) {
	occ := [2][][]int{occupancy(trajectories[0],
		in, times), occupancy(trajectories[1], in, times)}
	line(loadOut, "sector,period,start,end,entries_initial,entries_final,peak_initial,peak_final,mean_final,capacity,status")
	for si, sector := range in.Sectors {
		over := [2]int{}
		for period := 0; period < len(times)/5; period++ {
			start := in.Settings.Ta + 300*period
			end := start + 300
			var entries,
				peak, sum [2]int
			for plan := 0; plan < 2; plan++ {
				for _, transit := range lists[plan] {
					if transit.Sector == si && float64(start) <= transit.Entry && transit.Entry < float64(end) {
						entries[plan]++
					}
				}
				for j := 5 * period; j < 5*(period+1); j++ {
					count := occ[plan][si][j]
					sum[plan] += count
					peak[plan] = max(peak[plan],
						count)
				}
				if peak[plan] > sector.Capacity {
					over[plan]++
				}
			}
			status := "OK"
			if peak[1] > sector.Capacity {
				status = "OVER"
			} else if peak[0] > sector.Capacity {
				status = "RELIEVED"
			}
			line(loadOut,
				"%s,%d,%d,%d,%d,%d,%d,%d,%s,%d,%s", sector.Name, period+1, start, end, entries[0], entries[1], peak[0],
				peak[1], format(float64(sum[1])/5, 1), sector.Capacity, status)
		}
		line(report, "SECTOR %s x=%d..%d y=%d..%d fl=%d..%d capacity=%d",
			sector.Name, sector.X1, sector.X2, sector.Y1, sector.Y2, sector.Lower, sector.Upper, sector.Capacity)
		maxFinal := 0
		for plan, label := range []string{"INITIAL", "FINAL"} {
			entries := 0
			dwell := 0.0
			for _, transit := range lists[plan] {
				if transit.Sector == si {
					entries++
					dwell += transit.Exit - transit.Entry
				}
			}
			peak := 0
			for _, v := range occ[plan][si] {
				peak = max(peak, v)
			}
			if plan == 1 {
				maxFinal = peak
			}
			conflictCount := 0
			for _, c := range classes[plan] {
				if c.Sector == si {
					conflictCount++
				}
			}
			mean := "-"
			if entries > 0 {
				mean = f(dwell / float64(entries))
			}
			line(report,
				"%s entries=%d time=%s mean=%s peak=%d over=%d conflicts=%d", label, entries, f(dwell), mean, peak,
				over[plan], conflictCount)
		}
		top := max(sector.Capacity+1, maxFinal)
		grid := make([][]byte, top)
		for row := 0; row < top; row++ {
			k := top - row
			grid[row] = make([]byte,
				len(times))
			for j, count := range occ[1][si] {
				mark := byte('.')
				if count >= k {
					mark = '#'
				} else if k == sector.Capacity {
					mark = '-'
				}
				grid[row][j] = mark
			}
		}
		chart(report,
			grid)
	}
	line(report, "LEVELS")
	usage := [2]map[int]*LevelUsage{levelUsage(trajectories[0]), levelUsage(trajectories[1])}
	levelsSet := map[int]bool{}
	for _, u := range usage {
		for level := range u {
			levelsSet[level] = true
		}
	}
	var levels []int
	for level := range levelsSet {
		levels = append(levels,
			level)
	}
	sort.Sort(sort.Reverse(sort.IntSlice(levels)))
	for _, level := range levels {
		var count [2]int
		var duration [2]float64
		for plan := 0; plan < 2; plan++ {
			if value := usage[plan][level]; value != nil {
				count[plan] = len(value.Flights)
				duration[plan] = value.Time
			}
		}
		line(report,
			"LEVEL %d flights=%d->%d time=%s->%s", level, count[0], count[1], f(duration[0]), f(duration[1]))
	}
	handoffs := map[[2]int]int{}
	total := 0
	for _, transit := range lists[1] {
		if transit.Next >= 0 {
			handoffs[[2]int{transit.Sector, transit.Next}]++
			total++
		}
	}
	line(report,
		"HANDOFFS plan=final count=%d", total)
	for a, sector := range in.Sectors {
		for b, next := range in.Sectors {
			if count := handoffs[[2]int{a,
				b}]; count > 0 {
				line(report, "HANDOFF %s %s %d", sector.Name, next.Name, count)
			}
		}
	}
}
func alertReplay(trajectories []Trajectory, list []Conflict, in Input, times []int) ([]Alert, map[int]bool) {
	var alerts []Alert
	for a := 0; a < len(trajectories); a++ {
		for b := a + 1; b < len(trajectories); b++ {
			var grouped []Alert
			for _, time := range times {
				pa, sa, fa := trajectories[a].at(float64(time))
				pb, sb, fb := trajectories[b].at(float64(time))
				if !fa || !fb {
					continue
				}
				loss,
					exists := lossInterval(pa.subtract(pb), sa.Velocity.subtract(sb.Velocity), 0, float64(in.Settings.Alert),
					in.Settings)
				if !exists {
					continue
				}
				if len(grouped) > 0 && time-grouped[len(grouped)-1].Last == 60 {
					last := &grouped[len(grouped)-1]
					last.Last = time
					last.Samples++
					last.Minimum = math.Min(last.Minimum,
						loss.Distance)
				} else {
					grouped = append(grouped, Alert{A: a, B: b, First: time, Last: time, Samples: 1, Predicted: float64(time) + loss.Lo,
						Minimum: loss.Distance})
				}
			}
			alerts = append(alerts, grouped...)
		}
	}
	sort.SliceStable(alerts, func(i, j int) bool {
		a,
			b := alerts[i], alerts[j]
		return a.First < b.First || a.First == b.First && (a.A < b.A || a.A == b.A && a.B < b.B)
	})
	detected := map[int]bool{}
	for i := range alerts {
		alert := &alerts[i]
		for ci, c := range list {
			if c.A == alert.A && c.B == alert.B && c.Start < float64(alert.Last+in.Settings.Alert) && c.End > float64(alert.First) {
				if !alert.True {
					alert.True = true
					alert.Lead = c.Start - float64(alert.First)
				}
				detected[ci] = true
			}
		}
	}
	return alerts,
		detected
}
func reportAlerts(out *strings.Builder, name string, trajectories []Trajectory, list []Conflict, in Input,
	times []int) {
	alerts, detected := alertReplay(trajectories, list, in, times)
	line(out, "ALERTS plan=%s horizon=%d count=%d",
		name, in.Settings.Alert, len(alerts))
	trueCount := 0
	lead := 0.0
	for i, a := range alerts {
		status := "status=false lead=-"
		if a.True {
			trueCount++
			lead += a.Lead
			status = "status=true lead=" + f(a.Lead)
		}
		line(out,
			"ALERT %d %s first=%d last=%d samples=%d predicted=%s min_dist=%s %s", i+1, pairName(a.A, a.B, in.Plans),
			a.First, a.Last, a.Samples, f(a.Predicted), f(a.Minimum), status)
	}
	missed := 0
	for i, c := range list {
		if !detected[i] {
			missed++
			line(out,
				"MISSED %s start=%s end=%s", pairName(c.A, c.B, in.Plans), f(c.Start), f(c.End))
		}
	}
	mean := "-"
	if trueCount > 0 {
		mean = f(lead / float64(trueCount))
	}
	line(out,
		"SUMMARY alerts=%d true=%d false=%d missed=%d mean_lead=%s", len(alerts), trueCount, len(alerts)-trueCount,
		missed, mean)
}
func cell(p Vec, settings Settings) (int, int, bool) {
	r := settings.Radar
	fx := (10*p.X - float64(r[0])) * float64(r[4]) / float64(r[2]-r[0])
	fy := (10*p.Y - float64(r[1])) * float64(r[5]) / float64(r[3]-r[1])
	col,
		row := int(math.Floor(fx)), int(math.Floor(fy))
	if col >= 0 && col < r[4] && row >= 0 && row < r[5] {
		return col,
			r[5] - 1 - row, true
	}
	return 0, 0, false
}
func blankGrid(settings Settings, mark byte) [][]byte {
	grid := make([][]byte, settings.Radar[5])
	for row := range grid {
		grid[row] = []byte(strings.Repeat(string(mark),
			settings.Radar[4]))
	}
	return grid
}
func reportRadar(out *strings.Builder, trajectories [2][]Trajectory, lists [2][]Conflict, in Input, times []int) {
	for _, time := range in.Settings.Snapshots {
		for plan, name := range []string{"initial", "final"} {
			grid := blankGrid(in.Settings,
				'.')
			counts := make([][]int, len(grid))
			for row := range counts {
				counts[row] = make([]int, len(grid[row]))
			}
			conflicted := map[int]bool{}
			conflictCount := 0
			for _, c := range lists[plan] {
				if active(c, float64(time)) {
					conflicted[c.A], conflicted[c.B] = true, true
					conflictCount++
				}
			}
			aircraft := 0
			for flight, trajectory := range trajectories[plan] {
				p, _, exists := trajectory.at(float64(time))
				if !exists {
					continue
				}
				aircraft++
				col,
					row, inside := cell(p, in.Settings)
				if !inside {
					continue
				}
				counts[row][col]++
				if counts[row][col] >= 2 {
					grid[row][col] = byte('0' + counts[row][col])
				} else {
					mark := in.Plans[flight].Callsign[0]
					if conflicted[flight] {
						mark += 'a' - 'A'
					}
					grid[row][col] = mark
				}
			}
			for _, trajectory := range trajectories[plan] {
				_, _, now := trajectory.at(float64(time))
				p, _, later := trajectory.at(float64(time + in.Settings.Leader))
				if now && later {
					col,
						row, inside := cell(p, in.Settings)
					if inside && grid[row][col] == '.' {
						grid[row][col] = '*'
					}
				}
			}
			line(out,
				"RADAR plan=%s t=%d aircraft=%d conflicts=%d", name, time, aircraft, conflictCount)
			chart(out, grid)
			for flight, trajectory := range trajectories[plan] {
				p, segment, exists := trajectory.at(float64(time))
				if !exists {
					continue
				}
				col,
					row, inside := cell(p, in.Settings)
				at := "outside"
				if inside {
					at = fmt.Sprintf("%d,%d", col, row)
				}
				line(out,
					"%s x=%s y=%s fl=%s track=%s phase=%s cell=%s", in.Plans[flight].Callsign, f(p.X), f(p.Y), format(p.Z/100,
						2), format(track(segment), 1), segment.Phase, at)
			}
			for _, c := range lists[plan] {
				if active(c, float64(time)) {
					pa,
						_, _ := trajectories[plan][c.A].at(float64(time))
					pb, _, _ := trajectories[plan][c.B].at(float64(time))
					d := pa.subtract(pb)
					line(out,
						"CONFLICT %s dist=%s vert=%s", pairName(c.A, c.B, in.Plans), f(math.Sqrt(d.X*d.X+d.Y*d.Y)), format(math.Abs(d.Z),
							1))
				}
			}
		}
	}
	for plan, name := range []string{"initial", "final"} {
		grid := blankGrid(in.Settings, '.')
		counts := make([][]int,
			len(grid))
		for row := range counts {
			counts[row] = make([]int, len(grid[row]))
		}
		maximum := 0
		for _, time := range times {
			for _, trajectory := range trajectories[plan] {
				p, _, exists := trajectory.at(float64(time))
				if exists {
					col,
						row, inside := cell(p, in.Settings)
					if inside {
						counts[row][col]++
						maximum = max(maximum, counts[row][col])
					}
				}
			}
		}
		for row := range grid {
			for col, count := range counts[row] {
				if count >= 10 {
					grid[row][col] = '#'
				} else if count > 0 {
					grid[row][col] = byte('0' + count)
				}
			}
		}
		line(out,
			"DENSITY plan=%s from=%d to=%d step=60 max=%d", name, in.Settings.Ta, in.Settings.Tb, maximum)
		chart(out,
			grid)
	}
}
func flightConflictCount(flight int, list []Conflict) int {
	count := 0
	for _, c := range list {
		if c.A == flight || c.B == flight {
			count++
		}
	}
	return count
}
func waypointPass(trajectory Trajectory, index int) (float64, int) {
	if index == 0 {
		s := trajectory.Segments[0]
		return s.Start,
			int(s.Position.Z / 100)
	}
	var result Segment
	for _, s := range trajectory.Segments {
		if s.Leg == index {
			result = s
		}
	}
	return result.End,
		int(result.Final.Z / 100)
}
func main() {
	in := readInput()
	n := len(in.Plans)
	initial := make([]Trajectory, n)
	for i, p := range in.Plans {
		initial[i] = buildTrajectory(p,
			in.Types[p.Type])
	}
	plans := append([]Plan(nil), in.Plans...)
	final := append([]Trajectory(nil), initial...)
	initialConflicts := conflicts(initial,
		in.Settings)
	unresolvedPairs, resolvedPairs := map[[2]int]bool{}, map[[2]int]bool{}
	var unresolved []Conflict
	history := make([][]string,
		n)
	var trajectoriesOut, conflictsOut, resolutionsOut, transitsOut, loadOut, sectorsOut, alertsOut, radarOut,
		stripsOut strings.Builder
	rounds, resolvedCount, trials, infeasible, blocked, levelChanges, speedChanges,
		delayChanges := 0, 0, 0, 0, 0, 0, 0, 0
	moves := manoeuvres(in.Settings)
	for {
		current := conflicts(final, in.Settings)
		targetIndex := -1
		for i, c := range current {
			if !unresolvedPairs[pair(c.A, c.B)] {
				targetIndex = i
				break
			}
		}
		if targetIndex < 0 {
			break
		}
		target := current[targetIndex]
		rounds++
		line(&resolutionsOut,
			"ROUND %d %s start=%s end=%s dist=%s", rounds, pairName(target.A, target.B, in.Plans), f(target.Start),
			f(target.End), f(target.Closest.Loss.Distance))
		low, high := target.A, target.B
		if !lowerPriority(plans[low],
			plans[high]) {
			low, high = high, low
		}
		accepted := false
		for _, flight := range []int{low, high} {
			partner := target.A
			if partner == flight {
				partner = target.B
			}
			for _, move := range moves {
				trials++
				candidate, feasible := apply(plans[flight], move, in.Types[plans[flight].Type],
					in.Settings)
				if !feasible {
					infeasible++
					line(&resolutionsOut, "  TRY %s %s infeasible", plans[flight].Callsign,
						move.Name)
					continue
				}
				trajectory := buildTrajectory(candidate, in.Types[candidate.Type])
				var blocker Conflict
				hasBlocker := false
				for other := 0; other < n; other++ {
					if other == flight || unresolvedPairs[pair(flight,
						other)] {
						continue
					}
					a, b := flight, other
					ta, tb := trajectory, final[other]
					if a > b {
						a, b = b, a
						ta, tb = tb,
							ta
					}
					for _, c := range pairConflicts(a, b, ta, tb, in.Settings) {
						if other == partner || c.Start < target.Start+float64(in.Settings.Lookahead) {
							if !hasBlocker || conflictLess(c,
								blocker) {
								blocker = c
								hasBlocker = true
							}
						}
					}
				}
				if hasBlocker {
					blocked++
					line(&resolutionsOut, "  TRY %s %s blocked %s start=%s",
						plans[flight].Callsign, move.Name, pairName(blocker.A, blocker.B, in.Plans), f(blocker.Start))
					continue
				}
				accepted = true
				plans[flight] = candidate
				final[flight] = trajectory
				history[flight] = append(history[flight],
					move.Name)
				resolvedPairs[pair(target.A, target.B)] = true
				resolvedCount++
				switch move.Kind {
				case "level":
					levelChanges++
				case "speed":
					speedChanges++
				case "delay":
					delayChanges++
				}
				line(&resolutionsOut,
					"  TRY %s %s accepted", plans[flight].Callsign, move.Name)
				line(&resolutionsOut, "  RESULT resolved %s %s",
					plans[flight].Callsign, move.Name)
				break
			}
			if accepted {
				break
			}
		}
		if !accepted {
			unresolvedPairs[pair(target.A,
				target.B)] = true
			unresolved = append(unresolved, target)
			line(&resolutionsOut, "  RESULT unresolved")
		}
	}
	finalConflicts := conflicts(final,
		in.Settings)
	finalPairs := map[[2]int]bool{}
	for _, c := range finalConflicts {
		finalPairs[pair(c.A,
			c.B)] = true
	}
	lists := [2][]Conflict{initialConflicts, finalConflicts}
	trajectories := [2][]Trajectory{initial,
		final}
	var classes [2][]Classification
	for plan := 0; plan < 2; plan++ {
		for _, c := range lists[plan] {
			classes[plan] = append(classes[plan],
				classify(c, trajectories[plan], in))
		}
	}
	reportConflicts(&conflictsOut, "initial", initialConflicts,
		classes[0], initial, in, resolvedPairs, finalPairs)
	reportConflicts(&conflictsOut, "final", finalConflicts,
		classes[1], final, in, resolvedPairs, finalPairs)
	totalDelay := 0
	totalExtra := 0.0
	for i, p := range plans {
		extra := final[i].arrival() - initial[i].arrival()
		totalDelay += p.Delay
		totalExtra += extra
		manoeuvreNames := "-"
		if len(history[i]) > 0 {
			manoeuvreNames = strings.Join(history[i],
				",")
		}
		line(&resolutionsOut, "FLIGHT %s departure=%d delay=%d level=%s speed=%d->%d arrival=%s->%s extra=%s length=%s conflicts=%d->%d manoeuvres=%s",
			p.Callsign, p.Departure+p.Delay, p.Delay, signed(p.Offset), p.OriginalSpeed, p.Speed, f(initial[i].arrival()),
			f(final[i].arrival()), f(extra), f(final[i].Length), flightConflictCount(i, initialConflicts), flightConflictCount(i,
				finalConflicts), manoeuvreNames)
	}
	for _, c := range unresolved {
		line(&resolutionsOut, "UNRESOLVED %s start=%s dist=%s",
			pairName(c.A, c.B, in.Plans), f(c.Start), f(c.Closest.Loss.Distance))
	}
	line(&resolutionsOut, "TOTAL rounds=%d resolved=%d unresolved=%d level=%d speed=%d delay=%d total_delay=%d total_extra=%s trials=%d infeasible=%d blocked=%d",
		rounds, resolvedCount, len(unresolved), levelChanges, speedChanges, delayChanges, totalDelay, f(totalExtra),
		trials, infeasible, blocked)
	line(&trajectoriesOut, "callsign,segment,leg,phase,t_start,t_end,x_start,y_start,fl_start,x_end,y_end,fl_end")
	for i, trajectory := range final {
		for _, s := range trajectory.Segments {
			line(&trajectoriesOut, "%s,%d,%d,%s,%s,%s,%s,%s,%d,%s,%s,%d",
				plans[i].Callsign, s.Number, s.Leg, s.Phase, f(s.Start), f(s.End), f(s.Position.X), f(s.Position.Y),
				int(s.Position.Z/100), f(s.Final.X), f(s.Final.Y), int(s.Final.Z/100))
		}
	}
	transitLists := [2][]Transit{transits(initial,
		in), transits(final, in)}
	line(&transitsOut, "callsign,sector,entry,exit,duration,from,to")
	for _, t := range transitLists[1] {
		line(&transitsOut, "%s,%s,%s,%s,%s,%s,%s", plans[t.Flight].Callsign,
			in.Sectors[t.Sector].Name, f(t.Entry), f(t.Exit), f(t.Exit-t.Entry), sectorName(t.Previous, in),
			sectorName(t.Next, in))
	}
	times := sampleTimes(in.Settings)
	reportSectors(&loadOut, &sectorsOut,
		trajectories, transitLists, classes, in, times)
	reportAlerts(&alertsOut, "initial", initial, initialConflicts,
		in, times)
	reportAlerts(&alertsOut, "final", final, finalConflicts, in, times)
	reportRadar(&radarOut,
		trajectories, lists, in, times)
	for i, p := range plans {
		manoeuvreNames := "-"
		if len(history[i]) > 0 {
			manoeuvreNames = strings.Join(history[i],
				",")
		}
		line(&stripsOut, "STRIP %s type=%s waypoints=%d length=%s manoeuvres=%s", p.Callsign,
			in.Types[p.Type].Name, len(p.Waypoints), f(final[i].Length), manoeuvreNames)
		for k, w := range p.Waypoints {
			t0,
				fl0 := waypointPass(initial[i], k)
			t1, fl1 := waypointPass(final[i], k)
			line(&stripsOut, "WPT %d at=%d:%d eta=%s->%s fl=%d->%d",
				k, w.X, w.Y, f(t0), f(t1), fl0, fl1)
		}
		var sequence []string
		for _, t := range transitLists[1] {
			if t.Flight == i {
				sequence = append(sequence,
					in.Sectors[t.Sector].Name+"@"+f(t.Entry))
			}
		}
		sectors := "-"
		if len(sequence) > 0 {
			sectors = strings.Join(sequence,
				",")
		}
		line(&stripsOut, "SECTORS %s", sectors)
	}
	must(os.MkdirAll("output", 0755))
	for name, out := range map[string]*strings.Builder{"trajectories.csv": &trajectoriesOut,
		"conflicts.txt": &conflictsOut, "resolutions.txt": &resolutionsOut, "sector_transits.csv": &transitsOut,
		"sector_load.csv": &loadOut, "sector_report.txt": &sectorsOut, "alerts.txt": &alertsOut, "radar.txt": &radarOut,
		"strips.txt": &stripsOut} {
		write("output/"+name, out)
	}
}
