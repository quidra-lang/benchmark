package main

import (
	"fmt"
	"math"
	"os"
	"sort"
	"strconv"
	"strings"
)

var filterNames = []string{"cv", "ca", "abg", "imm", "rts"}

type Point [2]float64
type Scan struct {
	Time         float64
	Measurements []Point
}
type Target struct {
	ID, First, Last int
	Positions       map[int]Point
}
type Params struct {
	Model                                         string
	QCV, QCA, Sigma, Velocity, Acceleration, Gate float64
	M, N, Delete                                  int
	ABG                                           [3]float64
	IMMQ                                          [2]float64
	IMMTransition                                 [2][2]float64
	IMMInitial                                    [2]float64
	Match, Cutoff, Bound                          float64
	Edges                                         []float64
	XMin, XMax, YMin, YMax                        float64
	W, H                                          int
}
type Data struct {
	Scans        []Scan
	Targets      []Target
	Params       Params
	Measurements int
}

func lines(path string) []string {
	b, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	return strings.Split(strings.TrimSuffix(string(b), "\n"), "\n")
}
func integer(s string) int {
	v, e := strconv.Atoi(s)
	if e != nil {
		panic(e)
	}
	return v
}
func number(s string) float64 {
	v, e := strconv.ParseFloat(s, 64)
	if e != nil {
		panic(e)
	}
	return v
}
func readData() Data {
	out := Data{}
	for _, line := range lines("input/measurements.csv")[1:] {
		a := strings.Split(line, ",")
		k := integer(a[0]) - 1
		for len(out.Scans) <= k {
			out.Scans = append(out.Scans, Scan{Time: number(a[1])})
		}
		out.Scans[k].Measurements = append(out.Scans[k].Measurements, Point{number(a[2]), number(a[3])})
		out.Measurements++
	}
	index := map[int]int{}
	for _, line := range lines("input/truth.csv")[1:] {
		a := strings.Split(line, ",")
		id, k := integer(a[0]), integer(a[1])-1
		i, ok := index[id]
		if !ok {
			i = len(out.Targets)
			index[id] = i
			out.Targets = append(out.Targets, Target{id, k, k, map[int]Point{}})
		}
		out.Targets[i].Last = k
		out.Targets[i].Positions[k] = Point{number(a[2]), number(a[3])}
	}
	p := &out.Params
	for _, line := range lines("input/params.txt") {
		a := strings.Fields(line)
		switch a[0] {
		case "MODEL":
			p.Model = a[1]
		case "Q_CV":
			p.QCV = number(a[1])
		case "Q_CA":
			p.QCA = number(a[1])
		case "SIGMA":
			p.Sigma = number(a[1])
		case "INIT_VELOCITY_VARIANCE":
			p.Velocity = number(a[1])
		case "INIT_ACCELERATION_VARIANCE":
			p.Acceleration = number(a[1])
		case "GATE":
			p.Gate = number(a[1])
		case "CONFIRM":
			p.M, p.N = integer(a[1]), integer(a[2])
		case "DELETE":
			p.Delete = integer(a[1])
		case "ABG":
			for i := range p.ABG {
				p.ABG[i] = number(a[i+1])
			}
		case "IMM_Q":
			p.IMMQ = [2]float64{number(a[1]), number(a[2])}
		case "IMM_TRANSITION":
			p.IMMTransition = [2][2]float64{{number(a[1]), number(a[2])}, {number(a[3]), number(a[4])}}
		case "IMM_INITIAL":
			p.IMMInitial = [2]float64{number(a[1]), number(a[2])}
		case "MATCH_DISTANCE":
			p.Match = number(a[1])
		case "OSPA_CUTOFF":
			p.Cutoff = number(a[1])
		case "CONSISTENCY_BOUND":
			p.Bound = number(a[1])
		case "NIS_EDGES":
			for _, s := range a[1:] {
				p.Edges = append(p.Edges, number(s))
			}
		case "PLOT_X":
			p.XMin, p.XMax = number(a[1]), number(a[2])
		case "PLOT_Y":
			p.YMin, p.YMax = number(a[1]), number(a[2])
		case "PLOT_SIZE":
			p.W, p.H = integer(a[1]), integer(a[2])
		}
	}
	return out
}
func writeLines(name string, a []string) {
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	if e := os.WriteFile("output/"+name, []byte(strings.Join(a, "\n")+"\n"), 0644); e != nil {
		panic(e)
	}
}

type Track struct {
	ID, Birth, Confirmation, Deletion, LastHit, Hits, Misses int
	Status                                                   string
	State                                                    State
	Measurements                                             []*Point
	NIS                                                      []float64
}
type Segment struct{ First, Last, Target int }
type Evaluated struct {
	Track                               *Track
	Sequence                            []*Point
	Filters                             [5][][]float64
	Primary                             []State
	Likelihood                          [2]float64
	High                                []float64
	MatchedScans, MatchedTarget, Common int
	MeanDistance                        float64
	ScanTargets                         []int
	Segments                            []Segment
}
type Application struct {
	Data                                                    Data
	Tracks                                                  []*Track
	Evaluated                                               []*Evaluated
	Primary                                                 int
	ConflictMeasurements, ConflictTracks, GreedyDifferences int
	Labels                                                  [5][][]int
	OSPA                                                    [][5]float64
	ScanTracks, ScanTargets                                 []int
	TargetTracks                                            []int
}

func listLine(keyword string, items []string) string {
	if len(items) == 0 {
		return keyword + " none"
	}
	return keyword + " " + strings.Join(items, " ")
}
func (a *Application) tracking() {
	p := a.Data.Params
	q := p.QCV
	if p.Model == "CA" {
		q = p.QCA
		a.Primary = 1
	}
	csv := []string{"track,scan,x,y,vx,vy,status"}
	log := []string{}
	for k, scan := range a.Data.Scans {
		live := []*Track{}
		for _, track := range a.Tracks {
			if track.Status != "deleted" {
				live = append(live, track)
			}
		}
		if k > 0 {
			t := scan.Time - a.Data.Scans[k-1].Time
			for _, track := range live {
				track.State, _ = predict(track.State, p.Model, t, q)
			}
		}
		cost := zeros(len(live), len(scan.Measurements))
		usable := make([][]bool, len(live))
		rowGates := make([]int, len(live))
		columnGates := make([]int, len(scan.Measurements))
		gates := []string{}
		type Candidate struct {
			Row, Column int
			Cost        float64
		}
		candidates := []Candidate{}
		for i, track := range live {
			usable[i] = make([]bool, len(scan.Measurements))
			for j, z := range scan.Measurements {
				d2 := innovation(track.State, z, p.Sigma).Distance
				cost[i][j] = d2
				if d2 <= p.Gate {
					usable[i][j] = true
					rowGates[i]++
					columnGates[j]++
					gates = append(gates, fmt.Sprintf("%d:%d=%s", track.ID, j+1, fixed(d2)))
					candidates = append(candidates, Candidate{i, j, d2})
				}
			}
		}
		conflictMeasurements, conflictTracks := 0, 0
		for _, count := range rowGates {
			if count >= 2 {
				conflictTracks++
			}
		}
		for _, count := range columnGates {
			if count >= 2 {
				conflictMeasurements++
			}
		}
		a.ConflictMeasurements += conflictMeasurements
		a.ConflictTracks += conflictTracks
		chosen := assignment(cost, usable, len(scan.Measurements))
		sort.Slice(candidates, func(i, j int) bool {
			x, y := candidates[i], candidates[j]
			if x.Cost != y.Cost {
				return x.Cost < y.Cost
			}
			if x.Row != y.Row {
				return x.Row < y.Row
			}
			return x.Column < y.Column
		})
		greedy := make([]int, len(live))
		for i := range greedy {
			greedy[i] = -1
		}
		usedColumns := make([]bool, len(scan.Measurements))
		for _, c := range candidates {
			if greedy[c.Row] < 0 && !usedColumns[c.Column] {
				greedy[c.Row] = c.Column
				usedColumns[c.Column] = true
			}
		}
		difference := false
		for i := range chosen {
			if chosen[i] != greedy[i] {
				difference = true
				break
			}
		}
		if difference {
			a.GreedyDifferences++
		}
		assigned, greedyPairs, missed, created, confirmed, deleted := []string{}, []string{}, []string{}, []string{}, []string{}, []string{}
		usedColumns = make([]bool, len(scan.Measurements))
		for i, track := range live {
			j := chosen[i]
			if j >= 0 {
				z := scan.Measurements[j]
				var v Innovation
				track.State, v, _ = update(track.State, z, p.Sigma)
				track.NIS = append(track.NIS, v.Distance)
				track.Hits++
				track.Misses = 0
				track.LastHit = k
				track.Measurements = append(track.Measurements, &z)
				usedColumns[j] = true
				assigned = append(assigned, fmt.Sprintf("%d:%d", track.ID, j+1))
			} else {
				track.Misses++
				track.Measurements = append(track.Measurements, nil)
				missed = append(missed, fmt.Sprint(track.ID))
			}
			if greedy[i] >= 0 {
				greedyPairs = append(greedyPairs, fmt.Sprintf("%d:%d", track.ID, greedy[i]+1))
			}
		}
		for _, track := range live {
			if track.Status == "confirmed" {
				if track.Misses >= p.Delete {
					track.Status = "deleted"
					track.Deletion = k
					deleted = append(deleted, fmt.Sprint(track.ID))
				}
			} else {
				if track.Hits >= p.M {
					track.Status = "confirmed"
					track.Confirmation = k
					confirmed = append(confirmed, fmt.Sprint(track.ID))
				} else if k-track.Birth+1 >= p.N {
					track.Status = "deleted"
					track.Deletion = k
					deleted = append(deleted, fmt.Sprint(track.ID))
				}
			}
		}
		processed := append([]*Track(nil), live...)
		for j, z := range scan.Measurements {
			if usedColumns[j] {
				continue
			}
			position := z
			track := &Track{ID: len(a.Tracks) + 1, Birth: k, Confirmation: -1, Deletion: -1, LastHit: k, Hits: 1,
				Status: "tentative", State: initialize(p.Model, z, p), Measurements: []*Point{&position}}
			a.Tracks = append(a.Tracks, track)
			processed = append(processed, track)
			created = append(created, fmt.Sprintf("%d:%d", track.ID, j+1))
		}
		for _, track := range processed {
			x := track.State.X
			csv = append(csv, fmt.Sprintf("%d,%d,%s,%s,%s,%s,%s", track.ID, k+1, fixed(x[0]), fixed(x[1]), fixed(x[2]), fixed(x[3]), track.Status))
		}
		tentative, activeConfirmed := 0, 0
		for _, track := range a.Tracks {
			if track.Status == "tentative" {
				tentative++
			} else if track.Status == "confirmed" {
				activeConfirmed++
			}
		}
		log = append(log, fmt.Sprintf("scan %d tracks %d measurements %d", k+1, len(live), len(scan.Measurements)),
			listLine("gate", gates), listLine("assign", assigned), listLine("greedy", greedyPairs),
			listLine("missed", missed), listLine("new", created), listLine("confirmed", confirmed),
			listLine("deleted", deleted), fmt.Sprintf("status tentative %d confirmed %d", tentative,
				activeConfirmed), fmt.Sprintf("conflicts measurements %d tracks %d", conflictMeasurements,
				conflictTracks))
	}
	writeLines("tracks.csv", csv)
	writeLines("association_log.txt", log)
}
func (a *Application) replay(track *Track, sequence []*Point, kind string, q float64) ([]State, []State, []Matrix, float64) {
	states, predicted, fs := make([]State, len(sequence)), make([]State, len(sequence)), make([]Matrix, len(sequence))
	state := initialize(kind, *sequence[0], a.Data.Params)
	states[0] = state
	logLikelihood := 0.0
	for i := 1; i < len(sequence); i++ {
		scan := track.Birth + i
		t := a.Data.Scans[scan].Time - a.Data.Scans[scan-1].Time
		var f Matrix
		state, f = predict(state, kind, t, q)
		predicted[i], fs[i] = state, f
		if sequence[i] != nil {
			var l float64
			state, _, l = update(state, *sequence[i], a.Data.Params.Sigma)
			logLikelihood += l
		}
		states[i] = state
	}
	return states, predicted, fs, logLikelihood
}
func (a *Application) filters() {
	p := a.Data.Params
	out := []string{"track,scan,x,y,vx,vy"}
	for _, track := range a.Tracks {
		if track.Confirmation < 0 {
			continue
		}
		length := track.LastHit - track.Birth + 1
		sequence := track.Measurements[:length]
		e := &Evaluated{Track: track, Sequence: sequence, MatchedTarget: -1, ScanTargets: make([]int, len(a.Data.Scans))}
		for i := range e.ScanTargets {
			e.ScanTargets[i] = -1
		}
		for f, kind := range []string{"CV", "CA"} {
			q := p.QCV
			if f == 1 {
				q = p.QCA
			}
			states, predicted, fs, likelihood := a.replay(track, sequence, kind, q)
			e.Likelihood[f] = likelihood
			e.Filters[f] = make([][]float64, length)
			for i, state := range states {
				e.Filters[f][i] = append([]float64(nil), state.X[:4]...)
			}
			if f == a.Primary {
				e.Primary = states
				e.Filters[4] = smooth(states, predicted, fs)
			}
		}
		abg := []float64{sequence[0][0], sequence[0][1], 0, 0, 0, 0}
		e.Filters[2] = make([][]float64, length)
		e.Filters[2][0] = append([]float64(nil), abg[:4]...)
		imm := newIMM(*sequence[0], p)
		e.Filters[3] = make([][]float64, length)
		e.Filters[3][0] = imm.estimate()
		e.High = append(e.High, imm.Mu[1])
		for i := 1; i < length; i++ {
			scan := track.Birth + i
			t := a.Data.Scans[scan].Time - a.Data.Scans[scan-1].Time
			for axis := 0; axis < 2; axis++ {
				position, velocity, acceleration := abg[axis], abg[axis+2], abg[axis+4]
				abg[axis] = position + t*velocity + t*t*acceleration/2
				abg[axis+2] = velocity + t*acceleration
			}
			if sequence[i] != nil {
				for axis := 0; axis < 2; axis++ {
					r := sequence[i][axis] - abg[axis]
					abg[axis] = abg[axis] + p.ABG[0]*r
					abg[axis+2] = abg[axis+2] + p.ABG[1]*r/t
					abg[axis+4] = abg[axis+4] + 2*p.ABG[2]*r/(t*t)
				}
			}
			e.Filters[2][i] = append([]float64(nil), abg[:4]...)
			imm.step(t, sequence[i], p)
			e.Filters[3][i] = imm.estimate()
			e.High = append(e.High, imm.Mu[1])
		}
		a.Evaluated = append(a.Evaluated, e)
		for i, x := range e.Filters[4] {
			out = append(out, fmt.Sprintf("%d,%d,%s,%s,%s,%s", track.ID, track.Birth+i+1, fixed(x[0]), fixed(x[1]), fixed(x[2]), fixed(x[3])))
		}
	}
	writeLines("smoothed.csv", out)
}
func pointOf(v []float64) Point { return Point{v[0], v[1]} }
func (a *Application) associations() {
	s, b := len(a.Data.Scans), len(a.Data.Targets)
	a.OSPA = make([][5]float64, s)
	a.ScanTracks, a.ScanTargets = make([]int, s), make([]int, s)
	for f := 0; f < 5; f++ {
		a.Labels[f] = make([][]int, b)
		for target := 0; target < b; target++ {
			a.Labels[f][target] = make([]int, s)
			for k := 0; k < s; k++ {
				a.Labels[f][target][k] = -1
			}
		}
	}
	for k := 0; k < s; k++ {
		estimated, truth := []int{}, []int{}
		y := []Point{}
		for i, e := range a.Evaluated {
			if e.Track.Birth <= k && k <= e.Track.LastHit {
				estimated = append(estimated, i)
			}
		}
		for i, target := range a.Data.Targets {
			if z, ok := target.Positions[k]; ok {
				truth = append(truth, i)
				y = append(y, z)
			}
		}
		a.ScanTracks[k], a.ScanTargets[k] = len(estimated), len(truth)
		for f := 0; f < 5; f++ {
			x := []Point{}
			cost := zeros(len(estimated), len(truth))
			usable := make([][]bool, len(estimated))
			for i, index := range estimated {
				e := a.Evaluated[index]
				position := pointOf(e.Filters[f][k-e.Track.Birth])
				x = append(x, position)
				usable[i] = make([]bool, len(truth))
				for j, point := range y {
					cost[i][j] = distance(position, point)
					usable[i][j] = cost[i][j] <= a.Data.Params.Match
				}
			}
			chosen := assignment(cost, usable, len(truth))
			for i, j := range chosen {
				if j >= 0 {
					eIndex, tIndex := estimated[i], truth[j]
					a.Labels[f][tIndex][k] = eIndex
					if f == a.Primary {
						a.Evaluated[eIndex].MatchedScans++
						a.Evaluated[eIndex].ScanTargets[k] = tIndex
					}
				}
			}
			a.OSPA[k][f] = ospa(x, y, a.Data.Params.Cutoff)
		}
	}
	for _, e := range a.Evaluated {
		for k := e.Track.Birth; k <= e.Track.LastHit; {
			target := e.ScanTargets[k]
			if target < 0 {
				k++
				continue
			}
			end := k
			for end+1 <= e.Track.LastHit && e.ScanTargets[end+1] == target {
				end++
			}
			e.Segments = append(e.Segments, Segment{k, end, target})
			k = end + 1
		}
	}
	cost := zeros(len(a.Evaluated), b)
	usable := make([][]bool, len(a.Evaluated))
	for i, e := range a.Evaluated {
		usable[i] = make([]bool, b)
		for j, target := range a.Data.Targets {
			first, last := max(e.Track.Birth, target.First), min(e.Track.LastHit, target.Last)
			if first > last {
				continue
			}
			total := 0.0
			for k := min(e.Track.Birth, target.First); k <= max(e.Track.LastHit, target.Last); k++ {
				d := a.Data.Params.Cutoff
				if k >= first && k <= last {
					d = distance(pointOf(e.Filters[a.Primary][k-e.Track.Birth]), target.Positions[k])
					if d < a.Data.Params.Cutoff {
						usable[i][j] = true
					}
					d = math.Min(d, a.Data.Params.Cutoff)
				}
				total += d
			}
			count := max(e.Track.LastHit, target.Last) - min(e.Track.Birth, target.First) + 1
			cost[i][j] = total / float64(count)
		}
	}
	chosen := assignment(cost, usable, b)
	a.TargetTracks = make([]int, b)
	for j := range a.TargetTracks {
		a.TargetTracks[j] = -1
	}
	for i, j := range chosen {
		if j >= 0 {
			e := a.Evaluated[i]
			target := a.Data.Targets[j]
			e.MatchedTarget = j
			e.MeanDistance = cost[i][j]
			e.Common = min(e.Track.LastHit, target.Last) - max(e.Track.Birth, target.First) + 1
			a.TargetTracks[j] = i
		}
	}
}
func sum(v []float64) float64 {
	s := 0.0
	for _, x := range v {
		s += x
	}
	return s
}
func optionalScan(k int) string {
	if k < 0 {
		return "-"
	}
	return fmt.Sprint(k + 1)
}
func (a *Application) segmentText(e *Evaluated) string {
	if len(e.Segments) == 0 {
		return "none"
	}
	out := []string{}
	for _, s := range e.Segments {
		out = append(out, fmt.Sprintf("%d-%d:%d", s.First+1, s.Last+1, a.Data.Targets[s.Target].ID))
	}
	return strings.Join(out, " ")
}
func (a *Application) evaluationOutput() {
	d, p := a.Data, a.Data.Params
	s := len(d.Scans)
	falseTracks, lost, used := 0, 0, 0
	for _, e := range a.Evaluated {
		if e.MatchedScans == 0 {
			falseTracks++
		}
		used += e.Track.Hits
	}
	for _, track := range a.TargetTracks {
		if track < 0 {
			lost++
		}
	}
	parts := [][]string{{"summary", fmt.Sprint("scans ", s), fmt.Sprint("measurements ", d.Measurements),
		fmt.Sprint("targets ", len(d.Targets)), fmt.Sprint("tracks_created ", len(a.Tracks)), fmt.Sprint("tracks_confirmed ",
			len(a.Evaluated)), fmt.Sprint("false_tracks ", falseTracks), fmt.Sprint("missed_targets ",
			lost), fmt.Sprint("measurements_used ", used), fmt.Sprint("conflict_measurements ", a.ConflictMeasurements),
		fmt.Sprint("conflict_tracks ", a.ConflictTracks), fmt.Sprint("greedy_differences ", a.GreedyDifferences)}}
	targets := []string{"targets"}
	for _, target := range d.Targets {
		length := 0.0
		for k := target.First + 1; k <= target.Last; k++ {
			length += distance(target.Positions[k-1], target.Positions[k])
		}
		speed := length / (d.Scans[target.Last].Time - d.Scans[target.First].Time)
		targets = append(targets, fmt.Sprintf("target %d first %d last %d scans %d path %s mean_speed %s",
			target.ID, target.First+1, target.Last+1, target.Last-target.First+1, fixed(length),
			fixed(speed)))
	}
	parts = append(parts, targets)
	tracks := []string{"tracks"}
	matching := []string{"matching"}
	models := []string{"models"}
	allNIS := []float64{}
	for _, e := range a.Evaluated {
		track := e.Track
		hits, gap, longest := 0, 0, 0
		for _, z := range e.Sequence {
			if z != nil {
				hits++
				gap = 0
			} else {
				gap++
				longest = max(longest, gap)
			}
		}
		length := 0.0
		for i := 1; i < len(e.Sequence); i++ {
			length += distance(pointOf(e.Filters[4][i-1]), pointOf(e.Filters[4][i]))
		}
		inside := 0
		for _, v := range track.NIS {
			if v <= p.Bound {
				inside++
			}
		}
		allNIS = append(allNIS, track.NIS...)
		tracks = append(tracks, fmt.Sprintf("track %d birth %d confirmed %d end %d deleted %s hits %d misses %d longest_gap %d path %s nis %s nis_inside %d/%d",
			track.ID, track.Birth+1, track.Confirmation+1, track.LastHit+1, optionalScan(track.Deletion),
			hits, len(e.Sequence)-hits, longest, fixed(length), fixed(sum(track.NIS)/float64(len(track.NIS))),
			inside, len(track.NIS)))
		line := fmt.Sprintf("track %d target -", track.ID)
		if e.MatchedTarget >= 0 {
			line = fmt.Sprintf("track %d target %d common %d mean_distance %s", track.ID, d.Targets[e.MatchedTarget].ID, e.Common, fixed(e.MeanDistance))
		}
		line += fmt.Sprintf(" matched_scans %d segments %s", e.MatchedScans, a.segmentText(e))
		matching = append(matching, line)
		better := "cv"
		if e.Likelihood[1] > e.Likelihood[0] {
			better = "ca"
		}
		models = append(models, fmt.Sprintf("track %d updates %d cv %s ca %s better %s", track.ID, len(track.NIS),
			fixed(e.Likelihood[0]), fixed(e.Likelihood[1]), better))
	}
	parts = append(parts, tracks, matching)
	rmseLines, consistency := []string{"rmse"}, []string{"consistency"}
	overallP, overallV := [5]float64{}, [5]float64{}
	positionCount, velocityCount := 0, 0
	for targetIndex, target := range d.Targets {
		index := a.TargetTracks[targetIndex]
		if index < 0 {
			rmseLines = append(rmseLines, fmt.Sprintf("target %d track -", target.ID))
			consistency = append(consistency, fmt.Sprintf("target %d track -", target.ID))
			continue
		}
		e := a.Evaluated[index]
		position, velocity := [5]float64{}, [5]float64{}
		count, velCount, inside := 0, 0, 0
		nees := 0.0
		first, last := max(target.First, e.Track.Birth), min(target.Last, e.Track.LastHit)
		for k := first; k <= last; k++ {
			i := k - e.Track.Birth
			truth := target.Positions[k]
			count++
			positionCount++
			previous, hasPrevious := target.Positions[k-1]
			next, hasNext := target.Positions[k+1]
			trueVelocity := Point{}
			hasVelocity := hasPrevious && hasNext
			if hasVelocity {
				dt := d.Scans[k+1].Time - d.Scans[k-1].Time
				trueVelocity = Point{(next[0] - previous[0]) / dt, (next[1] - previous[1]) / dt}
				velCount++
				velocityCount++
			}
			for f := 0; f < 5; f++ {
				x := e.Filters[f][i]
				ex, ey := x[0]-truth[0], x[1]-truth[1]
				error := ex*ex + ey*ey
				position[f] += error
				overallP[f] += error
				if hasVelocity {
					vx, vy := x[2]-trueVelocity[0], x[3]-trueVelocity[1]
					error := vx*vx + vy*vy
					velocity[f] += error
					overallV[f] += error
				}
			}
			x := e.Filters[a.Primary][i]
			v := []float64{x[0] - truth[0], x[1] - truth[1]}
			value := quadratic(v, inverse(positionCovariance(e.Primary[i].P)))
			nees += value
			if value <= p.Bound {
				inside++
			}
		}
		for f := 0; f < 5; f++ {
			position[f] = math.Sqrt(position[f] / float64(count))
			velocity[f] = math.Sqrt(velocity[f] / float64(velCount))
		}
		rmseLines = append(rmseLines, fmt.Sprintf("target %d track %d common %d %s best %s", target.ID,
			e.Track.ID, count, filterValues(position), bestFilter(position)), fmt.Sprintf("target %d velocity %d %s best %s",
			target.ID, velCount, filterValues(velocity), bestFilter(velocity)))
		consistency = append(consistency, fmt.Sprintf("target %d track %d nees %s inside %d/%d", target.ID, e.Track.ID, fixed(nees/float64(count)), inside, count))
	}
	for f := 0; f < 5; f++ {
		overallP[f] = math.Sqrt(overallP[f] / float64(positionCount))
		overallV[f] = math.Sqrt(overallV[f] / float64(velocityCount))
	}
	rmseLines = append(rmseLines, "overall position "+filterValues(overallP)+" best "+bestFilter(overallP),
		"overall velocity "+filterValues(overallV)+" best "+bestFilter(overallV))
	parts = append(parts, rmseLines)
	histogram := make([]int, len(p.Edges)+1)
	for _, v := range allNIS {
		bin := 0
		for bin < len(p.Edges) && v >= p.Edges[bin] {
			bin++
		}
		histogram[bin]++
	}
	line := []string{fmt.Sprintf("nis_histogram total %d observed", len(allNIS))}
	for _, count := range histogram {
		line = append(line, fmt.Sprint(count))
	}
	line = append(line, "expected")
	lower := 0.0
	for bin := range histogram {
		upperTerm := 0.0
		if bin < len(p.Edges) {
			upperTerm = math.Exp(-p.Edges[bin] / 2)
		}
		expected := float64(len(allNIS)) * (math.Exp(-lower/2) - upperTerm)
		line = append(line, fixed(expected))
		if bin < len(p.Edges) {
			lower = p.Edges[bin]
		}
	}
	consistency = append(consistency, strings.Join(line, " "))
	parts = append(parts, consistency, models)
	ospaLines := []string{"ospa cutoff " + fixed(p.Cutoff) + " order 2", "scan targets tracks cv ca abg imm rts"}
	mean := [5]float64{}
	for k, row := range a.OSPA {
		line := []string{fmt.Sprint(k + 1), fmt.Sprint(a.ScanTargets[k]), fmt.Sprint(a.ScanTracks[k])}
		for f, v := range row {
			line = append(line, fixed(v))
			mean[f] += v
		}
		ospaLines = append(ospaLines, strings.Join(line, " "))
	}
	line = []string{"mean"}
	for _, v := range mean {
		line = append(line, fixed(v/float64(s)))
	}
	ospaLines = append(ospaLines, strings.Join(line, " "))
	parts = append(parts, ospaLines)
	continuityLines := []string{"continuity"}
	for f, name := range filterNames {
		rows := []string{}
		covered, breaks, swaps := 0, 0, 0
		for j, target := range d.Targets {
			c := continuity(a.Labels[f][j][target.First : target.Last+1])
			covered += c.Covered
			breaks += c.Breaks
			swaps += c.Swaps
			delay := "-"
			if c.Delay >= 0 {
				delay = fmt.Sprint(c.Delay)
			}
			rows = append(rows, fmt.Sprintf("  target %d scans %d covered %d breaks %d swaps %d delay %s",
				target.ID, target.Last-target.First+1, c.Covered, c.Breaks, c.Swaps, delay))
		}
		continuityLines = append(continuityLines, fmt.Sprintf("%s covered %d breaks %d swaps %d", name, covered, breaks, swaps))
		continuityLines = append(continuityLines, rows...)
	}
	parts = append(parts, continuityLines)
	immLines := []string{"imm"}
	for _, e := range a.Evaluated {
		maximum, high := 0, 0
		segments := []string{}
		for i := 0; i < len(e.High); {
			if e.High[i] > e.High[maximum] {
				maximum = i
			}
			if e.High[i] <= .5 {
				i++
				continue
			}
			start, end := i, i
			for end+1 < len(e.High) && e.High[end+1] > .5 {
				end++
				if e.High[end] > e.High[maximum] {
					maximum = end
				}
			}
			high += end - start + 1
			segments = append(segments, fmt.Sprintf("%d-%d", e.Track.Birth+start+1, e.Track.Birth+end+1))
			i = end + 1
		}
		if len(segments) == 0 {
			segments = append(segments, "none")
		}
		immLines = append(immLines, fmt.Sprintf("track %d mean_high %s max_high %s at %d high_scans %d segments %s",
			e.Track.ID, fixed(sum(e.High)/float64(len(e.High))), fixed(e.High[maximum]), e.Track.Birth+maximum+1,
			high, strings.Join(segments, " ")))
	}
	parts = append(parts, immLines)
	out := []string{}
	for i, part := range parts {
		if i > 0 {
			out = append(out, "")
		}
		out = append(out, part...)
	}
	writeLines("evaluation.txt", out)
}
func trackCharacter(index int) byte {
	if index < 26 {
		return byte('A' + index)
	}
	return byte('a' + index - 26)
}
func frame(grid [][]byte) []string {
	w := len(grid[0])
	out := []string{"+" + strings.Repeat("-", w) + "+"}
	for _, row := range grid {
		out = append(out, "|"+string(row)+"|")
	}
	return append(out, "+"+strings.Repeat("-", w)+"+")
}
func (a *Application) plots() {
	p := a.Data.Params
	dx, dy := (p.XMax-p.XMin)/float64(p.W), (p.YMax-p.YMin)/float64(p.H)
	position := func(point Point) (int, int, bool) {
		c := int(math.Floor((point[0] - p.XMin) / dx))
		r := int(math.Floor((p.YMax - point[1]) / dy))
		return r, c, r >= 0 && r < p.H && c >= 0 && c < p.W
	}
	trajectory := make([][]byte, p.H)
	measurementCounts := make([][]int, p.H)
	measurements := make([][]byte, p.H)
	for r := 0; r < p.H; r++ {
		trajectory[r] = []byte(strings.Repeat(" ", p.W))
		measurementCounts[r] = make([]int, p.W)
		measurements[r] = []byte(strings.Repeat(" ", p.W))
	}
	for _, target := range a.Data.Targets {
		for k := target.First; k <= target.Last; k++ {
			r, c, inside := position(target.Positions[k])
			if inside {
				trajectory[r][c] = '.'
			}
		}
	}
	for i, e := range a.Evaluated {
		for _, x := range e.Filters[4] {
			r, c, inside := position(pointOf(x))
			if inside {
				trajectory[r][c] = trackCharacter(i)
			}
		}
	}
	for _, scan := range a.Data.Scans {
		for _, z := range scan.Measurements {
			r, c, inside := position(z)
			if inside {
				measurementCounts[r][c]++
			}
		}
	}
	for r := range measurements {
		for c, count := range measurementCounts[r] {
			if count >= 10 {
				measurements[r][c] = '#'
			} else if count > 0 {
				measurements[r][c] = byte('0' + count)
			}
		}
	}
	out := []string{fmt.Sprintf("tracks x %s %s y %s %s size %d %d", fixed(p.XMin), fixed(p.XMax), fixed(p.YMin), fixed(p.YMax), p.W, p.H)}
	out = append(out, frame(trajectory)...)
	for i, e := range a.Evaluated {
		target := "-"
		if e.MatchedTarget >= 0 {
			target = fmt.Sprint(a.Data.Targets[e.MatchedTarget].ID)
		}
		out = append(out, fmt.Sprintf("%c track %d target %s", trackCharacter(i), e.Track.ID, target))
	}
	out = append(out, "", "measurements")
	out = append(out, frame(measurements)...)
	out = append(out, "", "timeline")
	s := len(a.Data.Scans)
	for j, target := range a.Data.Targets {
		row := []byte(strings.Repeat(" ", s))
		for k := target.First; k <= target.Last; k++ {
			row[k] = '.'
			label := a.Labels[a.Primary][j][k]
			if label >= 0 {
				row[k] = trackCharacter(label)
			}
		}
		out = append(out, fmt.Sprintf("%d |%s|", target.ID, string(row)))
	}
	out = append(out, "", "ospa "+filterNames[a.Primary])
	grid := make([][]byte, 10)
	for r := range grid {
		grid[r] = []byte(strings.Repeat(" ", s))
		for k, v := range a.OSPA {
			height := int(math.Floor(10 * v[a.Primary] / p.Cutoff))
			if height >= 10-r {
				grid[r][k] = '#'
			}
		}
	}
	out = append(out, frame(grid)...)
	writeLines("track_plot.txt", out)
}
func main() {
	a := Application{Data: readData()}
	a.tracking()
	a.filters()
	a.associations()
	a.evaluationOutput()
	a.plots()
}
