package main

import (
	"fmt"
	"math"
	"slices"
	"strings"
)

type Candidate struct {
	Text  string
	Value float64
}
type Params struct {
	Iterations                                                 int
	Pseudocount                                                float64
	Smoothing                                                  []Candidate
	Folds, MinLength, MaxMissing, Target, MergeGap, MinSegment int
	Motif                                                      [2]int
	Rich                                                       map[int]bool
	MinRich, MinMotif                                          int
	Confidence                                                 float64
	BoundaryTolerance                                          int
	PosteriorSeed                                              int64
	PosteriorSamples                                           int
	SampleSeed                                                 int64
	SampleCount, SampleLength                                  int
}

func interpretParams(raw map[string][]string, model *Model) Params {
	integer := func(key string) int { return parseInt(raw[key][0]) }
	p := Params{Iterations: integer("iterations"), Pseudocount: parseReal(raw["pseudocount"][0]), Folds: integer("folds"),
		MinLength: integer("min_sequence_length"), MaxMissing: integer("max_missing_percent"), Target: slices.Index(model.States,
			raw["segment_state"][0]), MergeGap: integer("merge_gap"), MinSegment: integer("min_segment_length"),
		Motif: [2]int{slices.Index(model.Symbols, raw["motif"][0]), slices.Index(model.Symbols, raw["motif"][1])},
		Rich:  map[int]bool{}, MinRich: integer("min_rich_percent"), MinMotif: integer("min_motif_percent"),
		Confidence: parseReal(raw["confidence"][0]), BoundaryTolerance: integer("boundary_tolerance"),
		PosteriorSeed: int64(integer("posterior_seed")), PosteriorSamples: integer("posterior_samples"),
		SampleSeed: int64(integer("sample_seed")), SampleCount: integer("sample_count"), SampleLength: integer("sample_length")}
	for _, text := range raw["smoothing"] {
		p.Smoothing = append(p.Smoothing, Candidate{text, parseReal(text)})
	}
	for _, symbol := range raw["rich_symbols"] {
		p.Rich[slices.Index(model.Symbols, symbol)] = true
	}
	return p
}

type Record struct {
	Name, Role, Upper  string
	Observations, Path []int
	Missing            int
}
type Validated struct {
	Unlabeled, Train, Test             []Record
	Rejections                         []string
	UnlabeledRejected, LabeledRejected int
}

func validate(raws []RawRecord, labeled bool, model *Model, p Params) ([]Record, []string) {
	seen := map[string]bool{}
	accepted := []Record{}
	rejected := []string{}
	for _, raw := range raws {
		reason := ""
		if seen[raw.Name] {
			reason = "duplicate name"
		}
		seen[raw.Name] = true
		upper := strings.ToUpper(raw.Observation)
		observations := []int{}
		missing := 0
		if reason == "" {
			for i := range len(upper) {
				letter := upper[i : i+1]
				index := slices.Index(model.Symbols, letter)
				if index < 0 && letter != model.Missing {
					reason = fmt.Sprintf("invalid symbol %s at position %d", letter, i+1)
					break
				}
				observations = append(observations, index)
				if index < 0 {
					missing++
				}
			}
		}
		path := []int{}
		if reason == "" && labeled {
			for i := range len(raw.Labels) {
				letter := raw.Labels[i : i+1]
				index := slices.Index(model.States, letter)
				if index < 0 {
					reason = fmt.Sprintf("invalid label %s at position %d", letter, i+1)
					break
				}
				path = append(path, index)
			}
		}
		if reason == "" && labeled && len(upper) != len(raw.Labels) {
			reason = fmt.Sprintf("length mismatch %d %d", len(upper), len(raw.Labels))
		}
		if reason == "" && len(upper) < p.MinLength {
			reason = fmt.Sprintf("too short %d", len(upper))
		}
		if reason == "" && 100*missing > p.MaxMissing*len(upper) {
			reason = fmt.Sprintf("too many missing %d", missing)
		}
		if reason != "" {
			file := "sequences.txt"
			if labeled {
				file = "labeled.txt"
			}
			rejected = append(rejected, fmt.Sprintf("REJECT %s line %d %s %s", file, raw.Line, raw.Name, reason))
		} else {
			accepted = append(accepted, Record{raw.Name, raw.Role, upper, observations, path, missing})
		}
	}
	return accepted, rejected
}
func validateInputs(raw RawInputs, p Params) Validated {
	unlabeled, reject1 := validate(raw.Sequences, false, raw.Initial, p)
	labeled, reject2 := validate(raw.Labeled, true, raw.Initial, p)
	out := Validated{Unlabeled: unlabeled, Rejections: append(reject1, reject2...), UnlabeledRejected: len(reject1), LabeledRejected: len(reject2)}
	for _, record := range labeled {
		if record.Role == "TRAIN" {
			out.Train = append(out.Train, record)
		} else {
			out.Test = append(out.Test, record)
		}
	}
	return out
}
func observationLists(records []Record) [][]int {
	out := [][]int{}
	for _, record := range records {
		out = append(out, record.Observations)
	}
	return out
}
func truePairs(records []Record) []TrainingPair {
	out := []TrainingPair{}
	for _, record := range records {
		out = append(out, TrainingPair{record.Observations, record.Path})
	}
	return out
}
func totalPositions(records []Record) int {
	total := 0
	for _, record := range records {
		total += len(record.Observations)
	}
	return total
}
func totalMissing(records []Record) int {
	total := 0
	for _, record := range records {
		total += record.Missing
	}
	return total
}
func ratio(a, b int) string {
	if b == 0 {
		return "-"
	}
	return number(float64(a) / float64(b))
}
func segments(path []int, p Params) []Segment {
	out := []Segment{}
	for _, run := range runs(path) {
		if run.State != p.Target {
			continue
		}
		if len(out) > 0 && run.Start-out[len(out)-1].End-1 <= p.MergeGap {
			out[len(out)-1].End = run.End
		} else {
			out = append(out, Segment{run.Start, run.End})
		}
	}
	kept := []Segment{}
	for _, segment := range out {
		if segment.End-segment.Start+1 >= p.MinSegment {
			kept = append(kept, segment)
		}
	}
	return kept
}
func trueRegions(path []int, target int) []Segment {
	out := []Segment{}
	for _, run := range runs(path) {
		if run.State == target {
			out = append(out, Segment{run.Start, run.End})
		}
	}
	return out
}

type Composition struct {
	Observed, Rich, Pairs, First, Second int
	Island                               bool
}

func composition(observations []int, segment Segment, p Params) Composition {
	out := Composition{}
	for t := segment.Start; t <= segment.End; t++ {
		symbol := observations[t]
		if symbol >= 0 {
			out.Observed++
			if p.Rich[symbol] {
				out.Rich++
			}
			if symbol == p.Motif[0] {
				out.First++
			}
			if symbol == p.Motif[1] {
				out.Second++
			}
		}
		if t < segment.End && symbol == p.Motif[0] && observations[t+1] == p.Motif[1] {
			out.Pairs++
		}
	}
	denominator := out.First * out.Second
	out.Island = denominator > 0 && 100*out.Rich >= p.MinRich*out.Observed && 100*out.Pairs*out.Observed >= p.MinMotif*denominator
	return out
}

type BWTrace struct {
	Loglik, Heldout, Change, MaxChange float64
	Violation                          bool
}
type BWTraining struct {
	Model                   *Model
	Trace                   []BWTrace
	BestHeldout, Violations int
}

func maxChange(a, b *Model) float64 {
	maximum := 0.0
	for i, v := range a.Initial {
		maximum = math.Max(maximum, math.Abs(v-b.Initial[i]))
	}
	for i, row := range a.Transition {
		for j, v := range row {
			maximum = math.Max(maximum, math.Abs(v-b.Transition[i][j]))
		}
	}
	for i, row := range a.Emission {
		for c, v := range row {
			maximum = math.Max(maximum, math.Abs(v-b.Emission[i][c]))
		}
	}
	return maximum
}
func trainBaumWelch(initial *Model, unlabeled, heldout [][]int, p Params) BWTraining {
	out := BWTraining{Model: initial}
	out.Trace = append(out.Trace, BWTrace{Loglik: totalLoglik(initial, unlabeled), Heldout: totalLoglik(initial, heldout)})
	for t := 1; t <= p.Iterations; t++ {
		next := baumWelchStep(out.Model, unlabeled, p.Pseudocount)
		loglik := totalLoglik(next, unlabeled)
		previous := out.Trace[t-1].Loglik
		record := BWTrace{loglik, totalLoglik(next, heldout), loglik - previous, maxChange(next, out.Model), loglik < previous-0.000001*math.Abs(previous)}
		if record.Violation {
			out.Violations++
		}
		out.Trace = append(out.Trace, record)
		if record.Heldout > out.Trace[out.BestHeldout].Heldout {
			out.BestHeldout = t
		}
		out.Model = next
	}
	return out
}
func bwTraceLines(training BWTraining) []string {
	lines := []string{"iteration,loglik,heldout,change,max_change,status"}
	for t, r := range training.Trace {
		line := fmt.Sprintf("%d,%s,%s,", t, number(r.Loglik), number(r.Heldout))
		if t == 0 {
			line += ",,"
		} else {
			status := "ok"
			if r.Violation {
				status = "violation"
			}
			line += number(r.Change) + "," + numberDigits(r.MaxChange, 6) + "," + status
		}
		lines = append(lines, line)
	}
	return lines
}

type ViterbiTrace struct {
	Logprob, Loglik float64
	Changed         int
}
type ViterbiTraining struct {
	Model     *Model
	Trace     []ViterbiTrace
	Converged bool
}

func viterbiTrainingValues(model *Model, sequences [][]int) ([][]int, ViterbiTrace) {
	paths := [][]int{}
	record := ViterbiTrace{}
	for _, observations := range sequences {
		path, logprob := viterbi(model, observations)
		paths = append(paths, path)
		record.Logprob += logprob
		record.Loglik += scaledForward(model, observations).Loglik
	}
	return paths, record
}
func trainViterbi(initial *Model, sequences [][]int, p Params) ViterbiTraining {
	paths, first := viterbiTrainingValues(initial, sequences)
	out := ViterbiTraining{Model: initial, Trace: []ViterbiTrace{first}}
	for t := 1; t <= p.Iterations; t++ {
		pairs := []TrainingPair{}
		for i, observations := range sequences {
			pairs = append(pairs, TrainingPair{observations, paths[i]})
		}
		model := estimateByCounting(initial, pairs, p.Pseudocount, "VITERBI_TRAINING")
		nextPaths, record := viterbiTrainingValues(model, sequences)
		for i, path := range paths {
			record.Changed += len(path) - correctCount(path, nextPaths[i])
		}
		out.Trace = append(out.Trace, record)
		out.Model = model
		paths = nextPaths
		if record.Changed == 0 {
			out.Converged = true
			break
		}
	}
	return out
}
func viterbiTraceLines(training ViterbiTraining) []string {
	lines := []string{"iteration,logprob,loglik,changed"}
	for t, r := range training.Trace {
		changed := ""
		if t > 0 {
			changed = fmt.Sprint(r.Changed)
		}
		lines = append(lines, fmt.Sprintf("%d,%s,%s,%s", t, number(r.Logprob), number(r.Loglik), changed))
	}
	return lines
}

type FoldResult struct{ Records, Positions, Correct int }
type CVResult struct {
	Candidate Candidate
	Folds     []FoldResult
	Correct   int
	Confusion [][]int
}
type SupervisedTraining struct {
	Model      *Model
	Candidates []CVResult
	Selected   int
	Learning   []int
}

func trainSupervised(initial *Model, training, testing []Record, p Params) SupervisedTraining {
	out := SupervisedTraining{}
	for _, candidate := range p.Smoothing {
		result := CVResult{Candidate: candidate, Confusion: intMatrix(len(initial.States), len(initial.States))}
		for f := 0; f < p.Folds; f++ {
			fitting, validation := []Record{}, []Record{}
			for i, record := range training {
				if i%p.Folds == f {
					validation = append(validation, record)
				} else {
					fitting = append(fitting, record)
				}
			}
			model := estimateByCounting(initial, truePairs(fitting), candidate.Value, "SUPERVISED")
			fold := FoldResult{Records: len(validation), Positions: totalPositions(validation)}
			for _, record := range validation {
				path, _ := viterbi(model, record.Observations)
				fold.Correct += correctCount(record.Path, path)
				addConfusion(result.Confusion, record.Path, path)
			}
			result.Correct += fold.Correct
			result.Folds = append(result.Folds, fold)
		}
		out.Candidates = append(out.Candidates, result)
		if result.Correct > out.Candidates[out.Selected].Correct {
			out.Selected = len(out.Candidates) - 1
		}
	}
	chosen := out.Candidates[out.Selected].Candidate.Value
	out.Model = estimateByCounting(initial, truePairs(training), chosen, "SUPERVISED")
	for r := 1; r <= len(training); r++ {
		model := estimateByCounting(initial, truePairs(training[:r]), chosen, "SUPERVISED")
		correct := 0
		for _, record := range testing {
			path, _ := viterbi(model, record.Observations)
			correct += correctCount(record.Path, path)
		}
		out.Learning = append(out.Learning, correct)
	}
	return out
}

type ModelEvaluation struct {
	Blocks    [][]string
	Correct   [2]int
	Decodings []Decoding
}

func evaluateModel(model *Model, testing []Record, p Params) ModelEvaluation {
	out := ModelEvaluation{}
	for _, record := range testing {
		out.Decodings = append(out.Decodings, decode(model, record.Observations))
	}
	for decoder := 0; decoder < 2; decoder++ {
		name := "VITERBI"
		if decoder == 1 {
			name = "POSTERIOR"
		}
		table := intMatrix(len(model.States), len(model.States))
		predictedRegions, trueRegionCount, matchedPredictedRegions, matchedTrueRegions := 0, 0, 0, 0
		predictedBoundaries, trueBoundaryCount, matchedPredictedBoundaries, matchedTrueBoundaries := 0, 0, 0, 0
		calibration, calibrationCorrect := [10]int{}, [10]int{}
		recordLines := []string{}
		for i, record := range testing {
			d := out.Decodings[i]
			path := d.Viterbi
			if decoder == 1 {
				path = d.Posterior
			}
			correct := correctCount(record.Path, path)
			out.Correct[decoder] += correct
			addConfusion(table, record.Path, path)
			predicted, truth := segments(path, p), trueRegions(record.Path, p.Target)
			a, b := regionMatches(predicted, truth)
			predictedRegions += len(predicted)
			trueRegionCount += len(truth)
			matchedPredictedRegions += a
			matchedTrueRegions += b
			predictedB, truthB := boundaries(path), boundaries(record.Path)
			a, b = boundaryMatches(predictedB, truthB, p.BoundaryTolerance)
			predictedBoundaries += len(predictedB)
			trueBoundaryCount += len(truthB)
			matchedPredictedBoundaries += a
			matchedTrueBoundaries += b
			if decoder == 1 {
				for t, confidence := range d.Confidence {
					bin := min(9, int(math.Floor(10*confidence)))
					calibration[bin]++
					if path[t] == record.Path[t] {
						calibrationCorrect[bin]++
					}
				}
			}
			recordLines = append(recordLines, fmt.Sprintf("RECORD %s length %d correct %d", record.Name, len(record.Path), correct))
		}
		lines := []string{"EVALUATION " + model.Name + " " + name}
		lines = append(lines, confusionLines(table, model.States)...)
		lines = append(lines, metricsLines(table, model.States)...)
		lines = append(lines, fmt.Sprintf("REGIONS %s predicted %d true %d precision %s recall %s", model.States[p.Target],
			predictedRegions, trueRegionCount, fraction(int64(matchedPredictedRegions), int64(predictedRegions)),
			fraction(int64(matchedTrueRegions), int64(trueRegionCount))), fmt.Sprintf("BOUNDARIES predicted %d true %d precision %s recall %s",
			predictedBoundaries, trueBoundaryCount, fraction(int64(matchedPredictedBoundaries), int64(predictedBoundaries)),
			fraction(int64(matchedTrueBoundaries), int64(trueBoundaryCount))))
		if decoder == 1 {
			for bin, count := range calibration {
				if count == 0 {
					continue
				}
				interval := fmt.Sprintf("0.%d-0.%d", bin, bin+1)
				if bin == 9 {
					interval = "0.9-1.0"
				}
				lines = append(lines, fmt.Sprintf("CALIBRATION %s positions %d correct %d accuracy %s", interval,
					count, calibrationCorrect[bin], fraction(int64(calibrationCorrect[bin]), int64(count))))
			}
		}
		lines = append(lines, recordLines...)
		out.Blocks = append(out.Blocks, lines)
	}
	return out
}
func evaluationFile(models []*Model, evaluations []ModelEvaluation, supervised SupervisedTraining, training, testing []Record, p Params) []string {
	blocks := [][]string{}
	for _, evaluation := range evaluations {
		blocks = append(blocks, evaluation.Blocks...)
	}
	lines := []string{fmt.Sprintf("CROSS_VALIDATION folds %d", p.Folds)}
	positions := totalPositions(training)
	for _, result := range supervised.Candidates {
		lines = append(lines, fmt.Sprintf("SMOOTHING %s positions %d correct %d accuracy %s", result.Candidate.Text,
			positions, result.Correct, fraction(int64(result.Correct), int64(positions))))
	}
	selected := supervised.Candidates[supervised.Selected]
	lines = append(lines, "SELECTED "+selected.Candidate.Text)
	for f, fold := range selected.Folds {
		lines = append(lines, fmt.Sprintf("FOLD %d records %d positions %d correct %d accuracy %s", f+1,
			fold.Records, fold.Positions, fold.Correct, fraction(int64(fold.Correct), int64(fold.Positions))))
	}
	lines = append(lines, confusionLines(selected.Confusion, models[0].States)...)
	lines = append(lines, metricsLines(selected.Confusion, models[0].States)...)
	blocks = append(blocks, lines)
	lines = []string{"LEARNING_CURVE"}
	for i, correct := range supervised.Learning {
		lines = append(lines, fmt.Sprintf("RECORDS %d correct %d accuracy %s", i+1, correct, fraction(int64(correct), int64(totalPositions(testing)))))
	}
	blocks = append(blocks, lines)
	return combineBlocks(blocks)
}
func combineBlocks(blocks [][]string) []string {
	out := []string{}
	for i, block := range blocks {
		if i > 0 {
			out = append(out, "")
		}
		out = append(out, block...)
	}
	return out
}
func annotationFiles(records []Record, model *Model, decodings []Decoding, p Params) ([]string, []string) {
	decodingLines := []string{}
	segmentLines := []string{"sequence,decoder,start,end,length,mean_posterior,support,rich_fraction,motif_ratio,island"}
	rng := Minstd{p.PosteriorSeed}
	for i, record := range records {
		d := decodings[i]
		samplePaths := [][]int{}
		totalSegments := 0
		for sample := 0; sample < p.PosteriorSamples; sample++ {
			path := posteriorPath(model, d.FB.Forward.Values, &rng)
			samplePaths = append(samplePaths, path)
			totalSegments += len(segments(path, p))
		}
		differences := len(record.Observations) - correctCount(d.Viterbi, d.Posterior)
		uncertain := 0
		confident := []byte(encode(d.Posterior, model.States))
		imputed := []byte(record.Upper)
		for t, confidence := range d.Confidence {
			if confidence < p.Confidence {
				uncertain++
				confident[t] = '.'
			}
			if record.Observations[t] < 0 {
				weights := make([]float64, len(model.Symbols))
				for c := range weights {
					for state := range model.States {
						weights[c] += d.FB.Posterior[t][state] * model.Emission[state][c]
					}
				}
				symbol := maximumIndex(weights)
				imputed[t] = strings.ToLower(model.Symbols[symbol])[0]
			}
		}
		decodingLines = append(decodingLines, fmt.Sprintf("SEQUENCE %s length %d loglik %s viterbi %s differences %d uncertain %d expected_segments %s",
			record.Name, len(record.Observations), number(d.FB.Forward.Loglik), number(d.ViterbiLogprob),
			differences, uncertain, number(float64(totalSegments)/float64(p.PosteriorSamples))),
			"VITERBI "+encode(d.Viterbi, model.States), "POSTERIOR "+encode(d.Posterior, model.States),
			"CONFIDENT "+string(confident), "IMPUTED "+string(imputed))
		for decoder, path := range [][]int{d.Viterbi, d.Posterior} {
			name := "viterbi"
			if decoder == 1 {
				name = "posterior"
			}
			for _, segment := range segments(path, p) {
				length := segment.End - segment.Start + 1
				posterior := 0.0
				for t := segment.Start; t <= segment.End; t++ {
					posterior += d.FB.Posterior[t][p.Target]
				}
				support := 0
				for _, sample := range samplePaths {
					targetCount := 0
					for t := segment.Start; t <= segment.End; t++ {
						if sample[t] == p.Target {
							targetCount++
						}
					}
					if 2*targetCount > length {
						support++
					}
				}
				c := composition(record.Observations, segment, p)
				island := "no"
				if c.Island {
					island = "yes"
				}
				segmentLines = append(segmentLines, fmt.Sprintf("%s,%s,%d,%d,%d,%s,%d,%s,%s,%s", record.Name,
					name, segment.Start+1, segment.End+1, length, number(posterior/float64(length)),
					support, ratio(c.Rich, c.Observed), ratio(c.Pairs*c.Observed, c.First*c.Second),
					island))
			}
		}
	}
	return decodingLines, segmentLines
}
func sampleFile(model *Model, p Params) []string {
	rng := Minstd{p.SampleSeed}
	lines := []string{}
	viterbiCorrect, posteriorCorrect := 0, 0
	for sample := 1; sample <= p.SampleCount; sample++ {
		states, observations := syntheticSequence(model, p.SampleLength, &rng)
		d := decode(model, observations)
		vc, pc := correctCount(states, d.Viterbi), correctCount(states, d.Posterior)
		viterbiCorrect += vc
		posteriorCorrect += pc
		lines = append(lines, fmt.Sprintf("SAMPLE %d loglik %s viterbi %s viterbi_correct %d posterior_correct %d",
			sample, number(d.FB.Forward.Loglik), number(d.ViterbiLogprob), vc, pc), "STATES "+encode(states,
			model.States), "SYMBOLS "+encode(observations, model.Symbols), "VITERBI "+encode(d.Viterbi,
			model.States), "POSTERIOR "+encode(d.Posterior, model.States))
	}
	positions := p.SampleCount * p.SampleLength
	return append(lines, fmt.Sprintf("TOTAL positions %d viterbi_accuracy %s posterior_accuracy %s",
		positions, fraction(int64(viterbiCorrect), int64(positions)), fraction(int64(posteriorCorrect),
			int64(positions))))
}
func stationary(model *Model) []float64 {
	k := len(model.States)
	a := matrix(k, k+1)
	for j := 0; j < k-1; j++ {
		for i := 0; i < k; i++ {
			a[j][i] = model.Transition[i][j]
			if i == j {
				a[j][i] -= 1
			}
		}
	}
	for i := 0; i < k; i++ {
		a[k-1][i] = 1
	}
	a[k-1][k] = 1
	for column := 0; column < k; column++ {
		pivot := column
		for row := column + 1; row < k; row++ {
			if math.Abs(a[row][column]) > math.Abs(a[pivot][column]) {
				pivot = row
			}
		}
		a[column], a[pivot] = a[pivot], a[column]
		divisor := a[column][column]
		for j := column; j <= k; j++ {
			a[column][j] /= divisor
		}
		for row := 0; row < k; row++ {
			if row == column {
				continue
			}
			factor := a[row][column]
			for j := column; j <= k; j++ {
				a[row][j] -= factor * a[column][j]
			}
		}
	}
	out := make([]float64, k)
	for i := range out {
		out[i] = a[i][k]
	}
	return out
}

type PathStats struct {
	Positions, Runs []int
	Total           int
}

func pathStatistics(paths [][]int, k int) PathStats {
	out := PathStats{Positions: make([]int, k), Runs: make([]int, k)}
	for _, path := range paths {
		out.Total += len(path)
		for _, state := range path {
			out.Positions[state]++
		}
		for _, run := range runs(path) {
			out.Runs[run.State]++
		}
	}
	return out
}
func truePaths(records []Record) [][]int {
	out := [][]int{}
	for _, record := range records {
		out = append(out, record.Path)
	}
	return out
}
func truthLines(records []Record, role string, states []string) []string {
	stats := pathStatistics(truePaths(records), len(states))
	lines := []string{}
	for i, state := range states {
		lines = append(lines, fmt.Sprintf("TRUTH %s %s occupancy %s mean_run %s", role, state, ratio(stats.Positions[i],
			stats.Total), ratio(stats.Positions[i], stats.Runs[i])))
	}
	return lines
}
func alignment(model *Model, training []Record) ([]int, int) {
	k := len(model.States)
	table := intMatrix(k, k)
	for _, record := range training {
		path, _ := viterbi(model, record.Observations)
		addConfusion(table, record.Path, path)
	}
	best := []int{}
	maximum := -1
	used := make([]bool, k)
	var visit func([]int)
	visit = func(permutation []int) {
		if len(permutation) == k {
			agreement := 0
			for j, state := range permutation {
				agreement += table[state][j]
			}
			if agreement > maximum {
				maximum = agreement
				best = append([]int{}, permutation...)
			}
			return
		}
		for state := 0; state < k; state++ {
			if !used[state] {
				used[state] = true
				visit(append(permutation, state))
				used[state] = false
			}
		}
	}
	visit(nil)
	return best, maximum
}
func modelReport(model *Model, unlabeled, training, testing []Record, decodings []Decoding, p Params) []string {
	loglik := 0.0
	paths := [][]int{}
	segmentCount, totalSegmentLength, islands := 0, 0, 0
	for i, record := range unlabeled {
		d := decodings[i]
		loglik += d.FB.Forward.Loglik
		paths = append(paths, d.Viterbi)
		for _, segment := range segments(d.Viterbi, p) {
			segmentCount++
			totalSegmentLength += segment.End - segment.Start + 1
			if composition(record.Observations, segment, p).Island {
				islands++
			}
		}
	}
	phi := stationary(model)
	stats := pathStatistics(paths, len(model.States))
	permutation, agreement := alignment(model, training)
	mapping := []string{}
	for j, state := range model.States {
		mapping = append(mapping, state+"="+model.States[permutation[j]])
	}
	observed := totalPositions(unlabeled) - totalMissing(unlabeled)
	lines := []string{"MODEL " + model.Name, fmt.Sprintf("LOGLIK unlabeled %s per_symbol %s test %s",
		number(loglik), number(loglik/float64(observed)), number(totalLoglik(model, observationLists(testing)))),
		fmt.Sprintf("SEGMENTS count %d mean_length %s islands %d", segmentCount, ratio(totalSegmentLength,
			segmentCount), islands), "ALIGNMENT " + strings.Join(mapping, " ") + " agreement " + fraction(int64(agreement),
			int64(totalPositions(training)))}
	for i, state := range model.States {
		lines = append(lines, fmt.Sprintf("STATE %s stationary %s duration %s occupancy %s mean_run %s",
			state, number(phi[i]), number(1/(1-model.Transition[i][i])), ratio(stats.Positions[i],
				stats.Total), ratio(stats.Positions[i], stats.Runs[i])))
	}
	return lines
}
func reportFile(initial *Model, input Validated, models []*Model, allDecodings [][]Decoding, evaluations []ModelEvaluation,
	bw BWTraining, vt ViterbiTraining, supervised SupervisedTraining, p Params) []string {
	unlabeled, training, testing := input.Unlabeled, input.Train, input.Test
	lines := []string{"INPUT", fmt.Sprintf("SEQUENCES accepted %d rejected %d positions %d missing %d",
		len(unlabeled), input.UnlabeledRejected, totalPositions(unlabeled), totalMissing(unlabeled)),
		fmt.Sprintf("LABELED train %d test %d rejected %d positions %d missing %d", len(training),
			len(testing), input.LabeledRejected, totalPositions(training)+totalPositions(testing), totalMissing(training)+totalMissing(testing))}
	lines = append(lines, input.Rejections...)
	symbolCounts := make([]int, len(initial.Symbols))
	observed := 0
	for _, record := range unlabeled {
		for _, symbol := range record.Observations {
			if symbol >= 0 {
				symbolCounts[symbol]++
				observed++
			}
		}
	}
	compositionLine := "COMPOSITION"
	for c, symbol := range initial.Symbols {
		compositionLine += " " + symbol + " " + ratio(symbolCounts[c], observed)
	}
	lines = append(lines, compositionLine)
	lines = append(lines, truthLines(training, "TRAIN", initial.States)...)
	lines = append(lines, truthLines(testing, "TEST", initial.States)...)
	blocks := [][]string{lines}
	converged := "no"
	if vt.Converged {
		converged = "yes"
	}
	lines = []string{fmt.Sprintf("TRAINING BAUM_WELCH iterations %d initial_loglik %s final_loglik %s violations %d best_heldout_iteration %d",
		p.Iterations, number(bw.Trace[0].Loglik), number(bw.Trace[len(bw.Trace)-1].Loglik), bw.Violations,
		bw.BestHeldout), fmt.Sprintf("TRAINING VITERBI_TRAINING iterations %d converged %s", len(vt.Trace)-1,
		converged), "TRAINING SUPERVISED smoothing " + supervised.Candidates[supervised.Selected].Candidate.Text}
	preference := make([]int, len(models))
	for i := range unlabeled {
		best := 0
		for m := 1; m < len(models); m++ {
			if allDecodings[m][i].FB.Forward.Loglik > allDecodings[best][i].FB.Forward.Loglik {
				best = m
			}
		}
		preference[best]++
	}
	line := "PREFERENCE"
	for m, model := range models {
		line += fmt.Sprintf(" %s %d", model.Name, preference[m])
	}
	lines = append(lines, line)
	for a := 0; a < len(models); a++ {
		for b := a + 1; b < len(models); b++ {
			correct := 0
			for i := range unlabeled {
				correct += correctCount(allDecodings[a][i].Viterbi, allDecodings[b][i].Viterbi)
			}
			lines = append(lines, "AGREEMENT "+models[a].Name+" "+models[b].Name+" "+fraction(int64(correct), int64(totalPositions(unlabeled))))
		}
	}
	for decoder, name := range []string{"VITERBI", "POSTERIOR"} {
		best := 0
		for m := 1; m < len(models); m++ {
			if evaluations[m].Correct[decoder] > evaluations[best].Correct[decoder] {
				best = m
			}
		}
		lines = append(lines, "BEST "+name+" "+models[best].Name+" accuracy "+fraction(int64(evaluations[best].Correct[decoder]), int64(totalPositions(testing))))
	}
	blocks = append(blocks, lines)
	for m, model := range models {
		blocks = append(blocks, modelReport(model, unlabeled, training, testing, allDecodings[m], p))
	}
	return combineBlocks(blocks)
}
func main() {
	raw := readInputs()
	p := interpretParams(raw.Params, raw.Initial)
	input := validateInputs(raw, p)
	unlabeled := observationLists(input.Unlabeled)
	heldout := append(observationLists(input.Train), observationLists(input.Test)...)
	bw := trainBaumWelch(raw.Initial, unlabeled, heldout, p)
	vt := trainViterbi(raw.Initial, unlabeled, p)
	supervised := trainSupervised(raw.Initial, input.Train, input.Test, p)
	models := []*Model{raw.Initial, bw.Model, vt.Model, supervised.Model}
	evaluations := []ModelEvaluation{}
	allDecodings := [][]Decoding{}
	for _, model := range models {
		evaluations = append(evaluations, evaluateModel(model, input.Test, p))
		decodings := []Decoding{}
		for _, record := range input.Unlabeled {
			decodings = append(decodings, decode(model, record.Observations))
		}
		allDecodings = append(allDecodings, decodings)
	}
	blocks := [][]string{}
	for _, model := range models[1:] {
		blocks = append(blocks, modelLines(model))
	}
	decodingLines, segmentLines := annotationFiles(input.Unlabeled, bw.Model, allDecodings[1], p)
	writeLines("trained_model.txt", combineBlocks(blocks))
	writeLines("loglik_trace.csv", bwTraceLines(bw))
	writeLines("viterbi_trace.csv", viterbiTraceLines(vt))
	writeLines("decodings.txt", decodingLines)
	writeLines("segments.csv", segmentLines)
	writeLines("samples.txt", sampleFile(bw.Model, p))
	writeLines("evaluation.txt", evaluationFile(models, evaluations, supervised, input.Train, input.Test, p))
	writeLines("report.txt", reportFile(raw.Initial, input, models, allDecodings, evaluations, bw, vt, supervised, p))
}
