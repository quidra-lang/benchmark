package main

import (
	"fmt"
	"os"
	"sort"
	"strings"
)

var labels = []string{"N", "V", "A"}
var peakClasses = []string{"qrs", "searchback", "twave", "refractory", "noise"}

type Thresholds struct{ I1, I2, F1, F2 int64 }

func thresholds(l Levels) Thresholds {
	i := l.NPKI + floorDiv(l.SPKI-l.NPKI, 4)
	f := l.NPKF + floorDiv(l.SPKF-l.NPKF, 4)
	return Thresholds{i, floorDiv(i, 2), f, floorDiv(f, 2)}
}

type Detection struct {
	Registered     []*Peak
	Initial, Final Levels
	Thresholds     Thresholds
	RA1, RA2       int64
}

func detectBeats(peaks []*Peak, s *Signals, p map[string]int64) *Detection {
	initial := initialLevels(s)
	levels := initial
	registered := []*Peak{}
	intervals := []int64{}
	ra1, ra2 := int64(200), int64(200)
	register := func(peak *Peak) {
		if len(registered) > 0 {
			elapsed := int64(peak.Time - registered[len(registered)-1].Time)
			intervals = append(intervals, elapsed)
			if len(intervals) > 8 {
				intervals = intervals[1:]
			}
			ra1 = sum(intervals) / int64(len(intervals))
			if 92*ra1 <= 100*elapsed && 100*elapsed <= 116*ra1 {
				ra2 = ra1
			}
		}
		registered = append(registered, peak)
	}
	update := func(peak *Peak, category string) {
		switch category {
		case "signal":
			levels.SPKI = floorDiv(peak.PeakI+7*levels.SPKI, 8)
			levels.SPKF = floorDiv(peak.PeakF+7*levels.SPKF, 8)
		case "noise":
			levels.NPKI = floorDiv(peak.PeakI+7*levels.NPKI, 8)
			levels.NPKF = floorDiv(peak.PeakF+7*levels.NPKF, 8)
		default:
			levels.SPKI = floorDiv(peak.PeakI+3*levels.SPKI, 4)
			levels.SPKF = floorDiv(peak.PeakF+3*levels.SPKF, 4)
		}
	}
	searchBack := func(time int) {
		for {
			lastTime := 0
			if len(registered) > 0 {
				lastTime = registered[len(registered)-1].Time
			}
			if int64(time-lastTime) <= ra2*p["searchback_percent"]/100 {
				break
			}
			t := thresholds(levels)
			var chosen *Peak
			for _, candidate := range peaks {
				if candidate.Class == "noise" && lastTime < candidate.Time && candidate.Time < time && candidate.PeakI > t.I2 && candidate.PeakF > t.F2 {
					if chosen == nil || candidate.PeakI > chosen.PeakI {
						chosen = candidate
					}
				}
			}
			if chosen == nil {
				break
			}
			update(chosen, "searchback")
			chosen.Class = "searchback"
			register(chosen)
		}
	}
	for _, peak := range peaks {
		searchBack(peak.Time)
		t := thresholds(levels)
		peak.ThresholdI, peak.ThresholdF = t.I1, t.F1
		var last *Peak
		if len(registered) > 0 {
			last = registered[len(registered)-1]
		}
		if last != nil && int64(peak.Time-last.Time) < p["refractory_ms"]/5 {
			peak.Class = "refractory"
			continue
		}
		if peak.PeakI > t.I1 && peak.PeakF > t.F1 {
			if last != nil && int64(peak.Time-last.Time) < p["twave_ms"]/5 && 2*peak.Slope < last.Slope {
				peak.Class = "twave"
				update(peak, "noise")
			} else {
				peak.Class = "qrs"
				update(peak, "signal")
				register(peak)
			}
		} else {
			peak.Class = "noise"
			update(peak, "noise")
		}
	}
	searchBack(len(s.Integrated))
	return &Detection{registered, initial, levels, thresholds(levels), ra1, ra2}
}

type Beat struct {
	Number, Sample int
	Peak           *Peak
	RR, HR, Width  int64
	Label, Method  string
	Annotation     *Annotation
	Offset         int64
}

func buildBeatList(registered []*Peak, band []int64, p map[string]int64) []*Beat {
	beats := []*Beat{}
	for _, peak := range registered {
		number := len(beats) + 1
		sample := max(0, peak.R-21)
		var rr, hr int64
		if len(beats) > 0 {
			rr = int64(5 * (sample - beats[len(beats)-1].Sample))
			hr = rdiv(6000000, rr)
		}
		width := widthMS(band, peak.R)
		label := "N"
		if number >= 10 {
			var preceding int64
			for k := number - 8; k < number; k++ {
				preceding += beats[k-1].RR
			}
			if 800*rr < p["premature_percent"]*preceding {
				label = "A"
				if width > p["qrs_width_ms"] {
					label = "V"
				}
			}
		}
		method := "threshold"
		if peak.Class == "searchback" {
			method = "searchback"
		}
		beats = append(beats, &Beat{Number: number, Sample: sample, Peak: peak, RR: rr, HR: hr, Width: width, Label: label, Method: method})
	}
	return beats
}
func matchAnnotations(beats []*Beat, refs []*Annotation, p map[string]int64) {
	tolerance := p["match_ms"] / 5
	for _, b := range beats {
		var chosen *Annotation
		best := int64(0)
		for _, ref := range refs {
			distance := abs(int64(ref.Sample - b.Sample))
			if ref.Beat == nil && distance <= tolerance && (chosen == nil || distance < best) {
				chosen = ref
				best = distance
			}
		}
		if chosen != nil {
			chosen.Beat = b
			b.Annotation = chosen
			b.Offset = int64(5 * (b.Sample - chosen.Sample))
		}
	}
}
func beatLines(beats []*Beat) []string {
	lines := []string{"beat,sample,time_ms,rr_ms,hr_bpm,width_ms,label,method,ref_sample,ref_label"}
	for _, b := range beats {
		hr := "-"
		if b.RR > 0 {
			hr = two(b.HR)
		}
		refSample, refLabel := "-", "-"
		if b.Annotation != nil {
			refSample = fmt.Sprint(b.Annotation.Sample)
			refLabel = b.Annotation.Label
		}
		lines = append(lines, fmt.Sprintf("%d,%d,%d,%s,%s,%d,%s,%s,%s,%s", b.Number, b.Sample, 5*b.Sample,
			optional(b.RR), hr, b.Width, b.Label, b.Method, refSample, refLabel))
	}
	return lines
}
func peakLines(peaks []*Peak) []string {
	lines := []string{"peak,sample,r_sample,peak_i,peak_f,slope,thr_i,thr_f,class"}
	for i, p := range peaks {
		lines = append(lines, fmt.Sprintf("%d,%d,%d,%d,%d,%d,%d,%d,%s", i+1, p.Time, p.R, p.PeakI, p.PeakF, p.Slope, p.ThresholdI, p.ThresholdF, p.Class))
	}
	return lines
}

type OrderedLine struct {
	Sample, Priority int
	Text             string
}

func orderedTexts(records []OrderedLine) []string {
	sort.Slice(records, func(i, j int) bool {
		a, b := records[i], records[j]
		if a.Sample != b.Sample {
			return a.Sample < b.Sample
		}
		return a.Priority < b.Priority
	})
	lines := []string{}
	for _, r := range records {
		lines = append(lines, r.Text)
	}
	return lines
}
func matchingLines(beats []*Beat, refs []*Annotation) []string {
	records := []OrderedLine{}
	for _, ref := range refs {
		text := fmt.Sprintf("%d,%s,-,-,-,-,FN,-", ref.Sample, ref.Label)
		if b := ref.Beat; b != nil {
			agree := "no"
			if ref.Label == b.Label {
				agree = "yes"
			}
			text = fmt.Sprintf("%d,%s,%d,%d,%s,%d,TP,%s", ref.Sample, ref.Label, b.Number, b.Sample, b.Label, b.Offset, agree)
		}
		records = append(records, OrderedLine{ref.Sample, 0, text})
	}
	for _, b := range beats {
		if b.Annotation == nil {
			records = append(records, OrderedLine{b.Sample, 1, fmt.Sprintf("-,-,%d,%d,%s,-,FP,-", b.Number, b.Sample, b.Label)})
		}
	}
	return append([]string{"ref_sample,ref_label,beat,beat_sample,beat_label,offset_ms,status,agree"}, orderedTexts(records)...)
}
func signalExcerpt(samples []int64, s *Signals, p map[string]int64) []string {
	lines := []string{"sample,ecg,lowpass,bandpass,derivative,squared,integrated"}
	for n := 0; n < int(p["excerpt_ms"]/5); n++ {
		lines = append(lines, fmt.Sprintf("%d,%d,%d,%d,%d,%d,%d", n, samples[n], s.Lowpass[n], s.Bandpass[n], s.Derivative[n], s.Squared[n], s.Integrated[n]))
	}
	return lines
}

type Segment struct {
	StartMS, EndMS                      int
	Refs, TP, FP, FN, NoisePeaks, Beats int
	RR                                  []int64
}

func segmentRows(beats []*Beat, refs []*Annotation, peaks []*Peak, count int, p map[string]int64) []*Segment {
	g := int(p["segment_ms"] / 5)
	segments := []*Segment{}
	for start := 0; start < count; start += g {
		stop := min(start+g, count)
		s := &Segment{StartMS: 5 * start, EndMS: 5 * stop}
		for _, ref := range refs {
			if start <= ref.Sample && ref.Sample < stop {
				s.Refs++
				if ref.Beat != nil {
					s.TP++
				}
			}
		}
		s.FN = s.Refs - s.TP
		for _, b := range beats {
			if start <= b.Sample && b.Sample < stop {
				s.Beats++
				if b.Annotation == nil {
					s.FP++
				}
				if b.RR > 0 {
					s.RR = append(s.RR, b.RR)
				}
			}
		}
		for _, peak := range peaks {
			if peak.Class == "noise" && start <= peak.Time && peak.Time < stop {
				s.NoisePeaks++
			}
		}
		segments = append(segments, s)
	}
	return segments
}
func matchingErrors(beats []*Beat, refs []*Annotation) []string {
	records := []OrderedLine{}
	for _, b := range beats {
		if b.Annotation == nil {
			records = append(records, OrderedLine{b.Sample, 0, fmt.Sprintf("false_positive beat=%d sample=%d time_ms=%d label=%s",
				b.Number, b.Sample, 5*b.Sample, b.Label)})
		}
	}
	for _, ref := range refs {
		if ref.Beat == nil {
			records = append(records, OrderedLine{ref.Sample, 1, fmt.Sprintf("false_negative sample=%d time_ms=%d label=%s", ref.Sample, 5*ref.Sample, ref.Label)})
		}
	}
	return orderedTexts(records)
}
func levelsText(l Levels) string {
	return fmt.Sprintf("spki=%d npki=%d spkf=%d npkf=%d", l.SPKI, l.NPKI, l.SPKF, l.NPKF)
}
func performanceLines(beats []*Beat, refs []*Annotation, peaks []*Peak, d *Detection, p map[string]int64, segments []*Segment, count int) []string {
	classes, referenceTypes, detectedTypes := map[string]int{}, map[string]int{}, map[string]int{}
	for _, peak := range peaks {
		classes[peak.Class]++
	}
	tp, fp := 0, 0
	confusion := map[[2]string]int{}
	for _, ref := range refs {
		referenceTypes[ref.Label]++
		label := "miss"
		if ref.Beat != nil {
			tp++
			label = ref.Beat.Label
		}
		confusion[[2]string{ref.Label, label}]++
	}
	offsets := []int64{}
	for _, b := range beats {
		detectedTypes[b.Label]++
		if b.Annotation == nil {
			fp++
			confusion[[2]string{"extra", b.Label}]++
		} else {
			offsets = append(offsets, b.Offset)
		}
	}
	fn := len(refs) - tp
	parts := []string{}
	for _, kind := range peakClasses {
		parts = append(parts, fmt.Sprintf("%s=%d", kind, classes[kind]))
	}
	referenceParts, detectedParts := []string{}, []string{}
	for _, label := range labels {
		referenceParts = append(referenceParts, fmt.Sprintf("%s=%d", label, referenceTypes[label]))
		detectedParts = append(detectedParts, fmt.Sprintf("%s=%d", label, detectedTypes[label]))
	}
	lines := []string{"DETECTOR", fmt.Sprintf("samples %d", count), fmt.Sprintf("duration_ms %d", 5*count),
		fmt.Sprintf("peaks %d %s", len(peaks), strings.Join(parts, " ")), "initial_levels " + levelsText(d.Initial),
		"final_levels " + levelsText(d.Final), fmt.Sprintf("final_thresholds thr_i=%d thr_f=%d",
			d.Thresholds.I1, d.Thresholds.F1), fmt.Sprintf("final_rr_averages rravg1_ms=%d rravg2_ms=%d",
			5*d.RA1, 5*d.RA2), "MATCHING", fmt.Sprintf("tolerance_ms %d", p["match_ms"]), fmt.Sprintf("references %d %s",
			len(refs), strings.Join(referenceParts, " ")), fmt.Sprintf("detections %d %s", len(beats),
			strings.Join(detectedParts, " ")), fmt.Sprintf("true_positives %d", tp), fmt.Sprintf("false_positives %d",
			fp), fmt.Sprintf("false_negatives %d", fn), "sensitivity " + ratio(int64(tp), int64(tp+fn)),
		"positive_predictivity " + ratio(int64(tp), int64(tp+fp)), "detection_error_rate " + ratio(int64(fp+fn),
			int64(len(refs)))}
	parts = []string{}
	for _, method := range []string{"threshold", "searchback"} {
		selected, matched := 0, 0
		for _, b := range beats {
			if b.Method == method {
				selected++
				if b.Annotation != nil {
					matched++
				}
			}
		}
		parts = append(parts, fmt.Sprintf("%s=%d/%d", method, matched, selected))
	}
	lines = append(lines, "by_method "+strings.Join(parts, " "))
	if len(offsets) > 0 {
		var absolute, maximum int64
		for _, v := range offsets {
			absolute += abs(v)
			maximum = max(maximum, abs(v))
		}
		lines = append(lines, fmt.Sprintf("offset_ms mean=%s mean_abs=%s max_abs=%d", two(rdiv(100*sum(offsets),
			int64(len(offsets)))), two(rdiv(100*absolute, int64(len(offsets)))), maximum))
	} else {
		lines = append(lines, "offset_ms none")
	}
	lines = append(lines, "CONFUSION", fmt.Sprintf("ref  %6s%6s%6s  miss", "N", "V", "A"))
	for _, refLabel := range labels {
		text := refLabel + "    "
		for _, label := range append(append([]string(nil), labels...), "miss") {
			text += fmt.Sprintf("%6d", confusion[[2]string{refLabel, label}])
		}
		lines = append(lines, text)
	}
	text := "extra"
	for _, label := range labels {
		text += fmt.Sprintf("%6d", confusion[[2]string{"extra", label}])
	}
	lines = append(lines, text)
	for _, item := range [][2]string{{"V", "veb"}, {"A", "sveb"}} {
		label, prefix := item[0], item[1]
		correct := int64(confusion[[2]string{label, label}])
		lines = append(lines, prefix+"_sensitivity "+ratio(correct, int64(referenceTypes[label])), prefix+"_positive_predictivity "+ratio(correct,
			int64(detectedTypes[label])))
	}
	lines = append(lines, fmt.Sprintf("SEGMENTS segment_ms=%d segments=%d", p["segment_ms"], len(segments)))
	for _, s := range segments {
		lines = append(lines, fmt.Sprintf("%6d-%6d refs=%d tp=%d fp=%d fn=%d noise_peaks=%d", s.StartMS, s.EndMS, s.Refs, s.TP, s.FP, s.FN, s.NoisePeaks))
	}
	lines = append(lines, fmt.Sprintf("ERRORS count=%d", fp+fn))
	return append(lines, matchingErrors(beats, refs)...)
}

type PrematureDetail struct {
	Beat                      *Beat
	NextRR, Mean, Prematurity int64
	Compensation              string
}

func prematureDetails(beats []*Beat) []PrematureDetail {
	details := []PrematureDetail{}
	for _, b := range beats {
		if b.Label == "N" {
			continue
		}
		var preceding int64
		for k := b.Number - 8; k < b.Number; k++ {
			preceding += beats[k-1].RR
		}
		next := int64(0)
		compensation := "-"
		if b.Number < len(beats) {
			next = beats[b.Number].RR
			total := b.RR + next
			if 10*abs(4*total-preceding) <= preceding {
				compensation = "full"
			} else if 4*total < preceding {
				compensation = "partial"
			} else {
				compensation = "long"
			}
		}
		details = append(details, PrematureDetail{b, next, rdiv(100*preceding, 8), rdiv(80000*b.RR, preceding), compensation})
	}
	return details
}

type PrematureRun struct {
	Label, Kind                  string
	First, Last, Length, StartMS int
}

func prematureRuns(beats []*Beat) []PrematureRun {
	runs := []PrematureRun{}
	for _, label := range []string{"V", "A"} {
		indices := []int{}
		for _, b := range beats {
			if b.Label == label {
				indices = append(indices, b.Number)
			}
		}
		for _, r := range consecutiveRanges(indices) {
			length := r[1] - r[0] + 1
			kind := "run"
			if length == 1 {
				kind = "isolated"
			} else if length == 2 {
				kind = "couplet"
			}
			runs = append(runs, PrematureRun{label, kind, r[0], r[1], length, 5 * beats[r[0]-1].Sample})
		}
	}
	sort.Slice(runs, func(i, j int) bool { return runs[i].First < runs[j].First })
	return runs
}

type RhythmEvent struct {
	Kind                                    string
	First, Last, Intervals, Cycles, StartMS int
	RR, MeanHR                              int64
}

func arrhythmiaEvents(beats []*Beat, p map[string]int64) []RhythmEvent {
	events := []RhythmEvent{}
	for _, b := range beats[1:] {
		if b.RR > p["pause_ms"] {
			events = append(events, RhythmEvent{Kind: "pause", First: b.Number - 1, Last: b.Number, RR: b.RR, StartMS: 5 * beats[b.Number-2].Sample})
		}
	}
	for _, kind := range []string{"bradycardia", "tachycardia"} {
		indices := []int{}
		for _, b := range beats[1:] {
			if kind == "bradycardia" && b.RR > p["brady_ms"] || kind == "tachycardia" && b.RR < p["tachy_ms"] {
				indices = append(indices, b.Number)
			}
		}
		for _, r := range consecutiveRanges(indices) {
			count := r[1] - r[0] + 1
			if count < 3 {
				continue
			}
			var total int64
			for k := r[0]; k <= r[1]; k++ {
				total += beats[k-1].RR
			}
			events = append(events, RhythmEvent{Kind: kind, First: r[0] - 1, Last: r[1], Intervals: count,
				MeanHR: rdiv(6000000*int64(count), total), StartMS: 5 * beats[r[0]-2].Sample})
		}
	}
	indices := []int{}
	lookup := map[int]string{}
	for _, b := range beats {
		lookup[b.Number] = b.Label
		if b.Label == "V" {
			indices = append(indices, b.Number)
		}
	}
	for _, item := range []struct {
		Kind string
		Span int
	}{{"bigeminy", 2}, {"trigeminy", 3}} {
		for _, chain := range linkedSequences(indices, item.Span, lookup) {
			if len(chain) >= 3 {
				events = append(events, RhythmEvent{Kind: item.Kind, First: chain[0], Last: chain[len(chain)-1], Cycles: len(chain), StartMS: 5 * beats[chain[0]-1].Sample})
			}
		}
	}
	return events
}
func eventLine(e RhythmEvent) string {
	if e.Kind == "pause" {
		return fmt.Sprintf("pause beats=%d-%d rr_ms=%d start_ms=%d", e.First, e.Last, e.RR, e.StartMS)
	}
	if e.Kind == "bradycardia" || e.Kind == "tachycardia" {
		return fmt.Sprintf("%s beats=%d-%d intervals=%d mean_hr=%s start_ms=%d", e.Kind, e.First, e.Last, e.Intervals, two(e.MeanHR), e.StartMS)
	}
	return fmt.Sprintf("%s beats=%d-%d cycles=%d start_ms=%d", e.Kind, e.First, e.Last, e.Cycles, e.StartMS)
}
func hrvLines(beats []*Beat, segments []*Segment, p map[string]int64) []string {
	rr, nn := rrStatistics(beats), nnStatistics(beats)
	lines := []string{"RR", fmt.Sprintf("beats %d", len(beats)), fmt.Sprintf("intervals %d", rr.Count), "mean_rr_ms " + maybeTwo(rr.MeanRR)}
	if rr.Shortest == nil {
		lines = append(lines, "min_rr_ms none", "max_rr_ms none", "mean_hr_bpm none")
	} else {
		lines = append(lines, fmt.Sprintf("min_rr_ms %d beat=%d", rr.Shortest.RR, rr.Shortest.Number), fmt.Sprintf("max_rr_ms %d beat=%d",
			rr.Longest.RR, rr.Longest.Number), "mean_hr_bpm "+maybeTwo(rr.MeanHR))
	}
	pnn := "none"
	if nn.PNN50 != nil {
		pnn = two(*nn.PNN50) + "%"
	}
	lines = append(lines, "NN", fmt.Sprintf("intervals %d", nn.E), "mean_nn_ms "+maybeTwo(nn.MeanNN),
		"sdnn_ms "+maybeTwo(nn.SDNN), fmt.Sprintf("differences %d", nn.K), "rmssd_ms "+maybeTwo(nn.RMSSD),
		"sdsd_ms "+maybeTwo(nn.SDSD), fmt.Sprintf("nn50 %d", nn.NN50), "pnn50 "+pnn, "sd1_ms "+maybeTwo(nn.SD1),
		"sd2_ms "+maybeTwo(nn.SD2), fmt.Sprintf("HISTOGRAM bin_ms=7.8125 bins=%d max=%d", len(nn.Histogram),
			nn.HistogramMax))
	bins := []int64{}
	for bin := range nn.Histogram {
		bins = append(bins, bin)
	}
	sort.Slice(bins, func(i, j int) bool { return bins[i] < bins[j] })
	for _, bin := range bins {
		count := nn.Histogram[bin]
		lines = append(lines, fmt.Sprintf("%10s %10s %3d |%s", four(78125*bin), four(78125*(bin+1)), count, strings.Repeat("#", count)))
	}
	if nn.E == 0 {
		lines = append(lines, "triangular_index none")
	} else {
		lines = append(lines, "triangular_index "+fraction(int64(nn.E), int64(nn.HistogramMax))+" "+two(*nn.Triangular))
	}
	premature := prematureDetails(beats)
	counts := map[string]int{}
	for _, d := range premature {
		counts[d.Beat.Label]++
	}
	lines = append(lines, fmt.Sprintf("PREMATURE count=%d V=%d A=%d", len(premature), counts["V"], counts["A"]))
	for _, d := range premature {
		b := d.Beat
		reference := "-"
		if b.Annotation != nil {
			reference = b.Annotation.Label
		}
		lines = append(lines, fmt.Sprintf("beat=%d sample=%d label=%s rr_ms=%d next_rr_ms=%s mean_ms=%s prematurity=%s%% compensation=%s width_ms=%d ref=%s",
			b.Number, b.Sample, b.Label, b.RR, optional(d.NextRR), two(d.Mean), two(d.Prematurity),
			d.Compensation, b.Width, reference))
	}
	runs := prematureRuns(beats)
	lines = append(lines, fmt.Sprintf("RUNS count=%d", len(runs)))
	for _, r := range runs {
		lines = append(lines, fmt.Sprintf("%s %s beats=%d-%d length=%d start_ms=%d", r.Label, r.Kind, r.First, r.Last, r.Length, r.StartMS))
	}
	events := arrhythmiaEvents(beats, p)
	lines = append(lines, fmt.Sprintf("EVENTS count=%d", len(events)))
	for _, e := range events {
		lines = append(lines, eventLine(e))
	}
	lines = append(lines, fmt.Sprintf("TREND segment_ms=%d segments=%d", p["segment_ms"], len(segments)))
	for _, s := range segments {
		header := fmt.Sprintf("%6d-%6d beats=%d ", s.StartMS, s.EndMS, s.Beats)
		if len(s.RR) == 0 {
			lines = append(lines, header+"mean_hr=none min_hr=none max_hr=none |")
			continue
		}
		lo, hi := s.RR[0], s.RR[0]
		for _, v := range s.RR {
			lo = min(lo, v)
			hi = max(hi, v)
		}
		hr := rdiv(6000000*int64(len(s.RR)), sum(s.RR))
		lines = append(lines, header+fmt.Sprintf("mean_hr=%s min_hr=%s max_hr=%s |%s", two(hr), two(rdiv(6000000,
			hi)), two(rdiv(6000000, lo)), strings.Repeat("#", int(rdiv(hr, 500)))))
	}
	return lines
}
func scale(value, top, bottom int64, rows int) int {
	if top <= bottom {
		return 0
	}
	return int(rdiv((top-value)*int64(rows-1), top-bottom))
}
func drawAxis(columns int, marker func(int) bool) string {
	marks := make([]byte, columns)
	for i := range columns {
		marks[i] = '-'
		if marker(i) {
			marks[i] = '+'
		}
	}
	return "       +" + string(marks) + "+"
}

type ChartLabel struct {
	Column int
	Text   string
}

func drawLabels(heading string, markers []ChartLabel) string {
	buffer := []byte(fmt.Sprintf("%6s  ", heading))
	for _, m := range markers {
		position := 8 + m.Column
		for len(buffer) < position+len(m.Text) {
			buffer = append(buffer, ' ')
		}
		copy(buffer[position:], m.Text)
	}
	return strings.TrimRight(string(buffer), " ")
}
func waveformChart(upper, lower []int64, height int) []string {
	top, bottom := upper[0], lower[0]
	for _, v := range upper {
		top = max(top, v)
	}
	for _, v := range lower {
		bottom = min(bottom, v)
	}
	zero := -1
	if bottom <= 0 && top >= 0 {
		zero = scale(0, top, bottom, height)
	}
	lines := []string{}
	for row := range height {
		label := ""
		if row == 0 {
			label = fmt.Sprint(top)
		} else if row == height-1 {
			label = fmt.Sprint(bottom)
		} else if row == zero {
			label = "0"
		}
		cells := make([]byte, len(upper))
		for i, hi := range upper {
			cells[i] = ' '
			if scale(hi, top, bottom, height) <= row && row <= scale(lower[i], top, bottom, height) {
				cells[i] = '#'
			} else if row == zero {
				cells[i] = '-'
			}
		}
		lines = append(lines, fmt.Sprintf("%6s |%s|", label, string(cells)))
	}
	return lines
}
func tachogramChart(beats []*Beat, height int) []string {
	intervals := []int64{}
	for _, b := range beats[1:] {
		intervals = append(intervals, b.RR)
	}
	if len(intervals) == 0 {
		return []string{"TACHOGRAM intervals=0", "POINCARE points=0"}
	}
	lo, hi := intervals[0], intervals[0]
	for _, v := range intervals {
		lo = min(lo, v)
		hi = max(hi, v)
	}
	lines := []string{fmt.Sprintf("TACHOGRAM intervals=%d min_ms=%d max_ms=%d rows=%d", len(intervals), lo, hi, height)}
	for row := range height {
		label := ""
		if row == 0 {
			label = fmt.Sprint(hi)
		} else if row == height-1 {
			label = fmt.Sprint(lo)
		}
		cells := make([]byte, len(intervals))
		for j, v := range intervals {
			cells[j] = ' '
			if scale(v, hi, lo, height) == row {
				cells[j] = '*'
			}
		}
		lines = append(lines, fmt.Sprintf("%6s |%s|", label, string(cells)))
	}
	lines = append(lines, drawAxis(len(intervals), func(j int) bool { return (j+2)%10 == 0 }))
	markers := []ChartLabel{}
	for j := range intervals {
		if (j+2)%10 == 0 {
			markers = append(markers, ChartLabel{j, fmt.Sprint(j + 2)})
		}
	}
	lines = append(lines, drawLabels("beat", markers))
	text := ""
	for _, b := range beats[1:] {
		text += b.Label
	}
	return append(lines, " label |"+text+"|")
}
func poincareChart(beats []*Beat, size int) []string {
	intervals := []int64{}
	for _, b := range beats[1:] {
		intervals = append(intervals, b.RR)
	}
	if len(intervals) == 0 {
		return nil
	}
	lo, hi := intervals[0], intervals[0]
	for _, v := range intervals {
		lo = min(lo, v)
		hi = max(hi, v)
	}
	points := map[[2]int]int{}
	for i := 0; i < len(intervals)-1; i++ {
		left, right := intervals[i], intervals[i+1]
		column := 0
		if hi > lo {
			column = int(rdiv((left-lo)*int64(size-1), hi-lo))
		}
		row := scale(right, hi, lo, size)
		points[[2]int{row, column}]++
	}
	lines := []string{fmt.Sprintf("POINCARE points=%d size=%d min_ms=%d max_ms=%d", len(intervals)-1, size, lo, hi)}
	for row := range size {
		label := ""
		if row == 0 {
			label = fmt.Sprint(hi)
		} else if row == size-1 {
			label = fmt.Sprint(lo)
		}
		cells := ""
		for column := range size {
			count := points[[2]int{row, column}]
			if count == 0 {
				cells += "."
			} else if count <= 9 {
				cells += fmt.Sprint(count)
			} else {
				cells += "#"
			}
		}
		lines = append(lines, fmt.Sprintf("%6s |%s|", label, cells))
	}
	lines = append(lines, drawAxis(size, func(int) bool { return false }))
	text := strings.Repeat(" ", 8) + fmt.Sprint(lo)
	highText := fmt.Sprint(hi)
	highStart := 8 + size - len(highText)
	return append(lines, text+strings.Repeat(" ", max(0, highStart-len(text)))+highText)
}
func averageTemplate(samples []int64, beats []*Beat, label string, height int) []string {
	chosen := []*Beat{}
	for _, b := range beats {
		if b.Label == label && b.Sample >= 60 && b.Sample <= len(samples)-100 {
			chosen = append(chosen, b)
		}
	}
	count := len(chosen)
	if count == 0 {
		return []string{"TEMPLATE " + label + " beats=0"}
	}
	baseline := make([]int64, count)
	for i, b := range chosen {
		baseline[i] = sum(samples[b.Sample-60 : b.Sample-50])
	}
	averaged := []int64{}
	for offset := -60; offset < 100; offset++ {
		var total int64
		for i, b := range chosen {
			total += 10*samples[b.Sample+offset] - baseline[i]
		}
		averaged = append(averaged, rdiv(total, int64(10*count)))
	}
	maxIndex, minIndex := 0, 0
	for i, v := range averaged {
		if v > averaged[maxIndex] {
			maxIndex = i
		}
		if v < averaged[minIndex] {
			minIndex = i
		}
	}
	lines := []string{fmt.Sprintf("TEMPLATE %s beats=%d max_uv=%d max_ms=%d min_uv=%d min_ms=%d rows=%d",
		label, count, averaged[maxIndex], 5*(maxIndex-60), averaged[minIndex], 5*(minIndex-60), height)}
	upper, lower := []int64{}, []int64{}
	for i := range 80 {
		upper = append(upper, max(averaged[2*i], averaged[2*i+1]))
		lower = append(lower, min(averaged[2*i], averaged[2*i+1]))
	}
	lines = append(lines, waveformChart(upper, lower, height)...)
	lines = append(lines, drawAxis(80, func(i int) bool { return i%10 == 0 }))
	markers := []ChartLabel{}
	for i := 0; i < 80; i += 10 {
		markers = append(markers, ChartLabel{i, fmt.Sprint(10*i - 300)})
	}
	return append(lines, drawLabels("ms", markers))
}
func chartLines(samples []int64, beats []*Beat, p map[string]int64) []string {
	lines := tachogramChart(beats, int(p["chart_rows"]))
	lines = append(lines, poincareChart(beats, int(p["poincare_size"]))...)
	for _, label := range labels {
		lines = append(lines, averageTemplate(samples, beats, label, int(p["chart_rows"]))...)
	}
	return lines
}
func rhythmStripLines(samples []int64, beats []*Beat, refs []*Annotation, p map[string]int64) []string {
	start, count := int(p["strip_start_ms"]/5), int(p["strip_ms"]/5)
	columns, height := count/10, int(p["strip_rows"])
	end := start + count
	excerpt := samples[start:end]
	upper, lower := []int64{}, []int64{}
	lo, hi := excerpt[0], excerpt[0]
	for _, v := range excerpt {
		lo = min(lo, v)
		hi = max(hi, v)
	}
	for col := range columns {
		piece := excerpt[10*col : 10*col+10]
		low, high := piece[0], piece[0]
		for _, v := range piece {
			low = min(low, v)
			high = max(high, v)
		}
		upper = append(upper, high)
		lower = append(lower, low)
	}
	lines := []string{fmt.Sprintf("RHYTHM start_ms=%d end_ms=%d columns=%d rows=%d max_uv=%d min_uv=%d",
		p["strip_start_ms"], p["strip_start_ms"]+p["strip_ms"], columns, height, hi, lo)}
	lines = append(lines, waveformChart(upper, lower, height)...)
	lines = append(lines, drawAxis(columns, func(c int) bool { return c%20 == 0 }))
	markers := []ChartLabel{}
	for col := 0; col < columns; col += 20 {
		markers = append(markers, ChartLabel{col, fmt.Sprint((p["strip_start_ms"] + 50*int64(col)) / 1000)})
	}
	lines = append(lines, drawLabels("s", markers))
	beatMarkers, refMarkers := []byte(strings.Repeat(" ", columns)), []byte(strings.Repeat(" ", columns))
	for _, b := range beats {
		if start <= b.Sample && b.Sample < end {
			beatMarkers[(b.Sample-start)/10] = b.Label[0]
		}
	}
	for _, ref := range refs {
		if start <= ref.Sample && ref.Sample < end {
			refMarkers[(ref.Sample-start)/10] = ref.Label[0]
		}
	}
	return append(lines, " beats |"+string(beatMarkers)+"|", "  refs |"+string(refMarkers)+"|")
}
func main() {
	samples, refs, p := readECG(), readAnnotations(), readParams()
	signals := filterECG(samples)
	peaks := findPeaks(signals)
	detection := detectBeats(peaks, signals, p)
	beats := buildBeatList(detection.Registered, signals.Bandpass, p)
	matchAnnotations(beats, refs, p)
	segments := segmentRows(beats, refs, peaks, len(samples), p)
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	writeLines("beats.csv", beatLines(beats))
	writeLines("peaks.csv", peakLines(peaks))
	writeLines("matching.csv", matchingLines(beats, refs))
	writeLines("signals_excerpt.csv", signalExcerpt(samples, signals, p))
	writeLines("performance.txt", performanceLines(beats, refs, peaks, detection, p, segments, len(samples)))
	writeLines("hrv.txt", hrvLines(beats, segments, p))
	writeLines("charts.txt", chartLines(samples, beats, p))
	writeLines("rhythm_strip.txt", rhythmStripLines(samples, beats, refs, p))
}
