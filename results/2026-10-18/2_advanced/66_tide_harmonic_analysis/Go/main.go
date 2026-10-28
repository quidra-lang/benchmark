package main

import (
	"math"
	"os"
	"sort"
	"strings"
)

type Harmonic struct{ Amp, Phase, AmpError, PhaseError, SNR float64 }
type Day struct {
	Hour, NHigh, NLow int
	High, Low         float64
	HasHigh, HasLow   bool
}
type DailyMean struct {
	Hour, Filled int
	Level        float64
}
type Result struct {
	Station     *Station
	First, Last int
	Times       []int
	Model       Model
	Residual    map[int]float64
	Harmonics   map[string]Harmonic
	Extremes    []Extremum
	Days        []Day
	Predictions []float64
	MHHW,
	MLLW, MHW, MLW, MTL, DTL, MN, GT float64
}

func selectConstituents(tau int, c []Constituent, rayleigh float64) ([]int, []string) {
	var selected []int
	status := make([]string,
		len(c))
	for i, co := range c {
		if co.Speed*float64(tau) < 360*rayleigh {
			status[i] = "short"
			continue
		}
		for _, j := range selected {
			if math.Abs(co.Speed-c[j].Speed)*float64(tau) < 360*rayleigh {
				status[i] = "conflict:" + c[j].Name
				break
			}
		}
		if status[i] == "" {
			status[i] = "fitted"
			selected = append(selected,
				i)
		}
	}
	return selected, status
}
func mean(a []float64) float64 {
	s := 0.0
	for _, v := range a {
		s += v
	}
	return s / float64(len(a))
}
func squareSum(a []float64) float64 {
	s := 0.0
	for _, v := range a {
		s += v * v
	}
	return s
}
func extremaDate(p Settings, e Extremum) string { return datetime(p, e.Minute)[:10] }
func processStation(s *Station, c []Constituent, p Settings, cleaning, constants, extremesOut, summary *strings.Builder) Result {
	numeric := make([]int,
		0, len(s.Values))
	for t := range s.Values {
		numeric = append(numeric, t)
	}
	sort.Ints(numeric)
	first, last := numeric[0],
		numeric[len(numeric)-1]
	reason := map[int]string{}
	for t := first; t <= last; t++ {
		if s.NA[t] {
			reason[t] = "na"
		} else if _,
			ok := s.Values[t]; !ok {
			reason[t] = "absent"
		}
	}
	runs := flatRuns(s.Values, first, last, p.Flat, reason)
	var candidates []int
	for _, t := range numeric {
		if reason[t] == "" {
			candidates = append(candidates, t)
		}
	}
	selected, status := selectConstituents(last-first,
		c, p.Rayleigh)
	pre := fit(candidates, s.Values, selected, c)
	preResidual := map[int]float64{}
	preSS := 0.0
	for _, t := range candidates {
		v := s.Values[t] - predict(pre, c, float64(t))
		preResidual[t] = v
		preSS += v * v
	}
	spikes,
		tested := spikeTest(candidates, preResidual, p, reason)
	var times []int
	for _, t := range candidates {
		if reason[t] == "" {
			times = append(times,
				t)
		}
	}
	gaps := listGaps(first, last, reason)
	counts := map[string]int{}
	for _, cause := range reason {
		counts[cause]++
	}
	line(cleaning,
		"station=%s name=%s", s.Code, s.Name)
	line(cleaning, "span start=%s end=%s hours=%d record_length=%d",
		datetime(p, first*60), datetime(p, last*60), last-first+1, last-first)
	line(cleaning, "counts rows=%d numeric=%d na=%d absent=%d flat=%d spikes=%d usable=%d",
		s.Rows, len(numeric), counts["na"], counts["absent"], counts["flat"], counts["spike"], len(times))
	for _, run := range runs {
		line(cleaning, "flat start=%s end=%s value=%s removed=%d", datetime(p, run.First*60),
			datetime(p, run.Last*60), format(run.Value, 3), run.Last-run.First)
	}
	line(cleaning, "spike_test window=%d candidates=%d tested=%d prefit_rms=%s",
		p.W, len(candidates), tested, format(math.Sqrt(preSS/float64(len(candidates))), 4))
	for _, sp := range spikes {
		line(cleaning,
			"spike time=%s value=%s residual=%s median=%s mad=%s limit=%s", datetime(p, sp.Time*60), format(s.Values[sp.Time],
				3), format(sp.Residual, 4), format(sp.Median, 4), format(sp.MAD, 4), format(sp.Limit, 4))
	}
	for _, gap := range gaps {
		line(cleaning,
			"gap start=%s end=%s hours=%d cause=%s", datetime(p, gap.First*60), datetime(p, gap.Last*60), gap.Last-gap.First+1,
			gap.Cause)
	}
	model := fit(times, s.Values, selected, c)
	r := Result{Station: s, First: first, Last: last, Times: times, Model: model,
		Residual: map[int]float64{}, Harmonics: map[string]Harmonic{}}
	ss, maxAbs, hm := 0.0, 0.0, 0.0
	for _, t := range times {
		v := s.Values[t] - predict(model, c, float64(t))
		r.Residual[t] = v
		ss += v * v
		maxAbs = math.Max(maxAbs,
			math.Abs(v))
		hm += s.Values[t]
	}
	hm /= float64(len(times))
	total, lagN, lagD := 0.0, 0.0, 0.0
	for _, t := range times {
		delta := s.Values[t] - hm
		total += delta * delta
		if next, ok := r.Residual[t+1]; ok {
			lagN += r.Residual[t] * next
			lagD += r.Residual[t] * r.Residual[t]
		}
	}
	unknowns := len(model.Coefficients)
	dof := len(times) - unknowns
	s2 := ss / float64(dof)
	byIndex := map[int]Harmonic{}
	for k, i := range selected {
		ia, ib := 2*k+1, 2*k+2
		a, b := model.Coefficients[ia], model.Coefficients[ib]
		amp,
			phase := amplitudePhase(a, b)
		va, vb, cab := s2*model.Inverse[ia][ia], s2*model.Inverse[ib][ib], s2*model.Inverse[ia][ib]
		ae := math.Sqrt(a*a*va+b*b*vb+2*a*b*cab) / amp
		pe := math.Sqrt(b*b*va+a*a*vb-2*a*b*cab) / (amp * amp) * 180 / 3.141592653589793
		snr := (amp / ae) * (amp / ae)
		h := Harmonic{amp,
			phase, ae, pe, snr}
		r.Harmonics[c[i].Name] = h
		byIndex[i] = h
	}
	for i, co := range c {
		if status[i] != "fitted" {
			line(constants,
				"%s,%s,%s,%s,,,,,,", s.Code, co.Name, format(co.Speed, 7), status[i])
			continue
		}
		h := byIndex[i]
		sig := "no"
		if h.SNR >= p.SNR {
			sig = "yes"
		}
		line(constants,
			"%s,%s,%s,fitted,%s,%s,%s,%s,%s,%s", s.Code, co.Name, format(co.Speed, 7), format(h.Amp, 4), format(h.Phase,
				2), format(h.AmpError, 4), format(h.PhaseError, 2), format(h.SNR, 1), sig)
	}
	r.Predictions = make([]float64, p.Hours+1)
	for i := range r.Predictions {
		r.Predictions[i] = predict(model,
			c, float64(p.Start+i))
	}
	ext := extrema(model, c, p)
	raw := len(ext)
	for len(ext) >= 2 {
		best := 0
		distance := math.Abs(ext[0].Height - ext[1].Height)
		for i := 1; i+1 < len(ext); i++ {
			d := math.Abs(ext[i].Height - ext[i+1].Height)
			if d < distance {
				best,
					distance = i, d
			}
		}
		if distance >= p.MinRange {
			break
		}
		ext = append(ext[:best], ext[best+2:]...)
	}
	for i := range ext {
		best := i
		for j := range ext {
			if ext[j].High == ext[i].High && extremaDate(p,
				ext[j]) == extremaDate(p, ext[i]) {
				if ext[i].High && ext[j].Height > ext[best].Height || !ext[i].High && ext[j].Height < ext[best].Height {
					best = j
				}
			}
		}
		if ext[i].High {
			ext[i].Label = "LHW"
			if i == best {
				ext[i].Label = "HHW"
			}
		} else {
			ext[i].Label = "HLW"
			if i == best {
				ext[i].Label = "LLW"
			}
		}
	}
	r.Extremes = ext
	line(extremesOut,
		"station=%s extremes=%d raw=%d removed=%d", s.Code, len(ext), raw, raw-len(ext))
	for i, e := range ext {
		change := "none"
		if i > 0 {
			change = format(e.Height-ext[i-1].Height,
				3)
		}
		line(extremesOut, "%s %s %s change=%s", datetime(p, e.Minute), e.Label, format(e.Height, 3),
			change)
	}
	var highs, lows, dailyHigh, dailyLow []float64
	for _, e := range ext {
		if e.High {
			highs = append(highs,
				e.Height)
		} else {
			lows = append(lows, e.Height)
		}
	}
	for hour := p.Start; hour < p.Start+p.Hours; hour += 24 {
		d := Day{Hour: hour}
		for _, e := range ext {
			if extremaDate(p, e) != date(p, hour) {
				continue
			}
			if e.High {
				d.NHigh++
				if !d.HasHigh || e.Height > d.High {
					d.High = e.Height
				}
				d.HasHigh = true
			} else {
				d.NLow++
				if !d.HasLow || e.Height < d.Low {
					d.Low = e.Height
				}
				d.HasLow = true
			}
		}
		hhw,
			llw, ran := "none", "none", "none"
		if d.HasHigh {
			hhw = format(d.High, 3)
			dailyHigh = append(dailyHigh,
				d.High)
		}
		if d.HasLow {
			llw = format(d.Low, 3)
			dailyLow = append(dailyLow, d.Low)
		}
		if d.HasHigh && d.HasLow {
			ran = format(d.High-d.Low,
				3)
		}
		r.Days = append(r.Days, d)
		line(extremesOut, "day date=%s high_waters=%d low_waters=%d hhw=%s llw=%s range=%s",
			date(p, hour), d.NHigh, d.NLow, hhw, llw, ran)
	}
	r.MHHW, r.MLLW, r.MHW, r.MLW = mean(dailyHigh), mean(dailyLow),
		mean(highs), mean(lows)
	r.MTL = (r.MHW + r.MLW) / 2
	r.DTL = (r.MHHW + r.MLLW) / 2
	r.MN = r.MHW - r.MLW
	r.GT = r.MHHW - r.MLLW
	line(summary, "[station %s] %s", s.Code, s.Name)
	line(summary, "record first=%s last=%s length=%d usable=%d",
		datetime(p, first*60), datetime(p, last*60), last-first, len(times))
	line(summary, "fit constituents=%d unknowns=%d dof=%d mean_level=%s",
		len(selected), unknowns, dof, format(model.Coefficients[0], 4))
	line(summary, "residual rms=%s max_abs=%s explained_percent=%s lag1_autocorrelation=%s",
		format(math.Sqrt(ss/float64(len(times))), 4), format(maxAbs, 4), format(100*(1-ss/total), 4), format(lagN/lagD,
			4))
	top := append([]int(nil), times...)
	sort.SliceStable(top, func(i, j int) bool { return math.Abs(r.Residual[top[i]]) > math.Abs(r.Residual[top[j]]) })
	for i, t := range top[:p.Top] {
		line(summary, "top_residual rank=%d time=%s observed=%s fitted=%s residual=%s",
			i+1, datetime(p, t*60), format(s.Values[t], 3), format(predict(model, c, float64(t)), 4), format(r.Residual[t],
				4))
	}
	mid := first + (last-first)/2
	var train, test []int
	for _, t := range times {
		if t <= mid {
			train = append(train,
				t)
		} else {
			test = append(test, t)
		}
	}
	validationSelected, _ := selectConstituents(train[len(train)-1]-train[0],
		c, p.Rayleigh)
	validation := fit(train, s.Values, validationSelected, c)
	valSS, inSS, testMean := 0.0,
		0.0, 0.0
	for _, t := range test {
		e := s.Values[t] - predict(validation, c, float64(t))
		valSS += e * e
		inSS += r.Residual[t] * r.Residual[t]
		testMean += s.Values[t]
	}
	testMean /= float64(len(test))
	testTotal := 0.0
	for _, t := range test {
		d := s.Values[t] - testMean
		testTotal += d * d
	}
	line(summary, "validation split=%s train=%d test=%d constituents=%d rms=%s in_sample_rms=%s skill=%s",
		datetime(p, mid*60), len(train), len(test), len(validationSelected), format(math.Sqrt(valSS/float64(len(test))),
			4), format(math.Sqrt(inSS/float64(len(test))), 4), format(1-valSS/testTotal, 4))
	m2, s2h, k1, o1, m4 := r.Harmonics["M2"], r.Harmonics["S2"], r.Harmonics["K1"], r.Harmonics["O1"], r.Harmonics["M4"]
	form := (k1.Amp + o1.Amp) / (m2.Amp + s2h.Amp)
	kind := "diurnal"
	if form < 0.25 {
		kind = "semidiurnal"
	} else if form < 1.5 {
		kind = "mixed_semidiurnal"
	} else if form < 3 {
		kind = "mixed_diurnal"
	}
	line(summary,
		"form_number=%s type=%s", format(form, 4), kind)
	line(summary, "ranges spring=%s neap=%s mn=%s gt=%s",
		format(2*(m2.Amp+s2h.Amp), 3), format(2*(m2.Amp-s2h.Amp), 3), format(r.MN, 3), format(r.GT, 3))
	var rise,
		fall []float64
	for i := 1; i < len(ext); i++ {
		if !ext[i-1].High && ext[i].High {
			rise = append(rise,
				float64(ext[i].Minute-ext[i-1].Minute))
		}
		if ext[i-1].High && !ext[i].High {
			fall = append(fall,
				float64(ext[i].Minute-ext[i-1].Minute))
		}
	}
	phase := 2*m2.Phase - m4.Phase
	for phase < 0 {
		phase += 360
	}
	for phase >= 360 {
		phase -= 360
	}
	dominance := "ebb"
	if phase < 180 {
		dominance = "flood"
	}
	line(summary,
		"asymmetry rise_minutes=%s fall_minutes=%s m4_m2_ratio=%s relative_phase=%s dominance=%s",
		format(mean(rise), 1), format(mean(fall), 1), format(m4.Amp/m2.Amp, 4), format(phase, 2), dominance)
	line(summary,
		"datums mhhw=%s mhw=%s mtl=%s dtl=%s mlw=%s mllw=%s", format(r.MHHW, 3), format(r.MHW, 3), format(r.MTL,
			3), format(r.DTL, 3), format(r.MLW, 3), format(r.MLLW, 3))
	ampSum := 0.0
	for _, i := range selected {
		ampSum += byIndex[i].Amp
	}
	line(summary,
		"bounds hat=%s lat=%s", format(model.Coefficients[0]+ampSum, 3), format(model.Coefficients[0]-ampSum,
			3))
	highest, lowest := -1, -1
	for i, e := range ext {
		if e.High && (highest < 0 || e.Height > ext[highest].Height) {
			highest = i
		}
		if !e.High && (lowest < 0 || e.Height < ext[lowest].Height) {
			lowest = i
		}
	}
	line(summary,
		"window high_waters=%d low_waters=%d highest=%s highest_time=%s lowest=%s lowest_time=%s",
		len(highs), len(lows), format(ext[highest].Height, 3), datetime(p, ext[highest].Minute), format(ext[lowest].Height,
			3), datetime(p, ext[lowest].Minute))
	widest, narrowest := -1, -1
	for i, d := range r.Days {
		if !d.HasHigh || !d.HasLow {
			continue
		}
		if widest < 0 || d.High-d.Low > r.Days[widest].High-r.Days[widest].Low {
			widest = i
		}
		if narrowest < 0 || d.High-d.Low < r.Days[narrowest].High-r.Days[narrowest].Low {
			narrowest = i
		}
	}
	line(summary,
		"daily_range widest=%s widest_date=%s narrowest=%s narrowest_date=%s", format(r.Days[widest].High-r.Days[widest].Low,
			3), date(p, r.Days[widest].Hour), format(r.Days[narrowest].High-r.Days[narrowest].Low, 3), date(p,
			r.Days[narrowest].Hour))
	above, below := 0, 0
	for _, v := range r.Predictions {
		if v > r.MHHW {
			above++
		}
		if v < r.MLLW {
			below++
		}
	}
	line(summary,
		"exceedance above_mhhw=%s below_mllw=%s", format(100*float64(above)/float64(p.Hours+1), 2),
		format(100*float64(below)/float64(p.Hours+1), 2))
	speed := map[string]float64{}
	for _, co := range c {
		speed[co.Name] = co.Speed
	}
	dw,
		dg := speed["S2"]-speed["M2"], s2h.Phase-m2.Phase
	a, b := (dw*float64(p.Start)-dg)/180, (dw*float64(p.Start+p.Hours)-dg)/180
	for q := int(math.Ceil(math.Min(a,
		b))); q <= int(math.Floor(math.Max(a, b))); q++ {
		t := (dg + 180*float64(q)) / dw
		if t < float64(p.Start) || t > float64(p.Start+p.Hours) {
			continue
		}
		tide := "neap"
		if q%2 == 0 {
			tide = "spring"
		}
		line(summary,
			"%s time=%s", tide, datetime(p, int(math.Floor(t*60+0.5))))
	}
	type Event struct{ First, Last, Peak, Sign int }
	var events []Event
	sign := func(t int) int {
		if r.Residual[t] > p.Surge {
			return 1
		}
		if r.Residual[t] < -p.Surge {
			return -1
		}
		return 0
	}
	for i := 0; i < len(times); {
		t := times[i]
		sg := sign(t)
		if sg == 0 {
			i++
			continue
		}
		j,
			peak := i, t
		for j+1 < len(times) && times[j+1] == times[j]+1 && sign(times[j+1]) == sg {
			j++
			if sg == 1 && r.Residual[times[j]] > r.Residual[peak] || sg == -1 && r.Residual[times[j]] < r.Residual[peak] {
				peak = times[j]
			}
		}
		if j-i+1 >= p.SurgeHours {
			events = append(events,
				Event{t, times[j], peak, sg})
		}
		i = j + 1
	}
	line(summary, "surges count=%d threshold=%s min_hours=%d",
		len(events), format(p.Surge, 3), p.SurgeHours)
	for _, event := range events {
		name := "positive"
		if event.Sign < 0 {
			name = "negative"
		}
		line(summary,
			"surge type=%s start=%s end=%s hours=%d peak=%s peak_time=%s", name, datetime(p, event.First*60),
			datetime(p, event.Last*60), event.Last-event.First+1, format(r.Residual[event.Peak], 4), datetime(p,
				event.Peak*60))
	}
	weights := []int{0, 2, 1, 1, 2, 0, 1, 1, 0, 2, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1}
	var daily []DailyMean
	for day := first / 24 * 24; day <= last; day += 24 {
		noon := day + 12
		if noon-19 < first || noon+19 > last {
			continue
		}
		sum := 0.0
		filled := 0
		for j := -19; j <= 19; j++ {
			t := noon + j
			v := s.Values[t]
			if reason[t] != "" {
				v = predict(model,
					c, float64(t))
				filled++
			}
			sum += float64(weights[abs(j)]) * v
		}
		daily = append(daily, DailyMean{day,
			filled, sum / 30})
	}
	xm, vm := 0.0, 0.0
	imax, imin := 0, 0
	for i, d := range daily {
		xm += float64((d.Hour - daily[0].Hour) / 24)
		vm += d.Level
		if d.Level > daily[imax].Level {
			imax = i
		}
		if d.Level < daily[imin].Level {
			imin = i
		}
	}
	xm /= float64(len(daily))
	vm /= float64(len(daily))
	sxy,
		sxx := 0.0, 0.0
	for _, d := range daily {
		x := float64((d.Hour-daily[0].Hour)/24) - xm
		sxy += x * (d.Level - vm)
		sxx += x * x
	}
	line(summary,
		"daily_mean days=%d average=%s slope_mm_per_day=%s max=%s max_date=%s min=%s min_date=%s",
		len(daily), format(vm, 4), format(1000*(sxy/sxx), 3), format(daily[imax].Level, 4), date(p, daily[imax].Hour),
		format(daily[imin].Level, 4), date(p, daily[imin].Hour))
	for _, d := range daily {
		line(summary,
			"daily_mean date=%s level=%s filled=%d", date(p, d.Hour), format(d.Level, 4), d.Filled)
	}
	return r
}
func abs(a int) int {
	if a < 0 {
		return -a
	}
	return a
}
func lagMean(a, b Result, high bool) float64 {
	var differences []float64
	for _, e := range a.Extremes {
		if e.High != high {
			continue
		}
		best := -1
		for i, f := range b.Extremes {
			if f.High == high && (best < 0 || abs(e.Minute-f.Minute) < abs(e.Minute-b.Extremes[best].Minute)) {
				best = i
			}
		}
		differences = append(differences,
			float64(e.Minute-b.Extremes[best].Minute))
	}
	return mean(differences)
}
func correlation(a, b Result, lag int) (float64, int) {
	var x, y []float64
	for _, t := range a.Times {
		if v,
			ok := b.Residual[t+lag]; ok {
			x = append(x, a.Residual[t])
			y = append(y, v)
		}
	}
	mx, my := mean(x), mean(y)
	sxy,
		sxx, syy := 0.0, 0.0, 0.0
	for i := range x {
		dx, dy := x[i]-mx, y[i]-my
		sxy += dx * dy
		sxx += dx * dx
		syy += dy * dy
	}
	return sxy / math.Sqrt(sxx*syy),
		len(x)
}
func main() {
	p, c, stations := readInput()
	must(os.MkdirAll("output", 0755))
	var cleaning, constants, predictions,
		extremesOut, summary strings.Builder
	line(&constants, "station,constituent,speed,status,amplitude,phase,amplitude_error,phase_error,snr,significant")
	var results []Result
	reference,
		plot := 0, 0
	for i, s := range stations {
		results = append(results, processStation(s, c, p, &cleaning, &constants,
			&extremesOut, &summary))
		if s.Code == p.Reference {
			reference = i
		}
		if s.Code == p.Plot {
			plot = i
		}
	}
	codes := []string{"time"}
	for _, s := range stations {
		codes = append(codes, s.Code)
	}
	line(&predictions, strings.Join(codes, ","))
	for i := 0; i <= p.Hours; i++ {
		a := []string{datetime(p,
			(p.Start+i)*60)}
		for _, r := range results {
			a = append(a, format(r.Predictions[i], 3))
		}
		line(&predictions,
			strings.Join(a, ","))
	}
	line(&summary, "[comparison] reference=%s", p.Reference)
	ref := results[reference]
	for i, r := range results {
		if i == reference {
			continue
		}
		line(&summary, "%s tide hw_lag_min=%s lw_lag_min=%s range_ratio=%s mtl_diff=%s",
			r.Station.Code, format(lagMean(r, ref, true), 1), format(lagMean(r, ref, false), 1), format(r.GT/ref.GT,
				4), format(r.MTL-ref.MTL, 3))
		for _, name := range []string{"M2", "S2", "K1", "O1"} {
			h, base := r.Harmonics[name],
				ref.Harmonics[name]
			phase := h.Phase - base.Phase
			if phase > 180 {
				phase -= 360
			}
			if phase <= -180 {
				phase += 360
			}
			speed := 0.0
			for _, co := range c {
				if co.Name == name {
					speed = co.Speed
					break
				}
			}
			line(&summary, "%s %s amplitude_ratio=%s phase_diff=%s time_lag_min=%s",
				r.Station.Code, name, format(h.Amp/base.Amp, 4), format(phase, 2), format(phase/speed*60, 1))
		}
	}
	line(&summary,
		"[correlation] max_lag=%d", p.Lag)
	for i := 0; i < len(results); i++ {
		for j := i + 1; j < len(results); j++ {
			bestLag,
				bestPairs := 0, 0
			best := -math.MaxFloat64
			lag0 := 0.0
			for lag := -p.Lag; lag <= p.Lag; lag++ {
				rho, n := correlation(results[i],
					results[j], lag)
				if lag == 0 {
					lag0 = rho
				}
				if rho > best || rho == best && (abs(lag) < abs(bestLag) || abs(lag) == abs(bestLag) && lag < bestLag) {
					bestLag,
						bestPairs, best = lag, n, rho
				}
			}
			line(&summary, "%s-%s lag0=%s best_lag=%d best=%s pairs=%d", results[i].Station.Code,
				results[j].Station.Code, format(lag0, 4), bestLag, format(best, 4), bestPairs)
		}
	}
	line(&summary, "[plot] station=%s start=%s hours=%d step_cm=%d",
		p.Plot, datetime(p, p.Start*60), p.PlotWidth, p.ZS)
	r := results[plot]
	rows := (p.ZT-p.ZB)/p.ZS + 1
	cells := make([][]byte,
		rows)
	for q := range cells {
		cells[q] = []byte(strings.Repeat(" ", p.PlotWidth))
	}
	qz := int(math.Floor((float64(p.ZT)-100*r.Model.Coefficients[0])/float64(p.ZS) + 0.5))
	if qz >= 0 && qz < rows {
		cells[qz] = []byte(strings.Repeat("-",
			p.PlotWidth))
	}
	marks := make([]byte, p.PlotWidth)
	for _, e := range r.Extremes {
		col := (e.Minute - 60*p.Start + 30) / 60
		if col >= 0 && col < p.PlotWidth {
			marks[col] = 'L'
			if e.High {
				marks[col] = 'H'
			}
		}
	}
	for col := 0; col < p.PlotWidth; col++ {
		q := int(math.Floor((float64(p.ZT)-100*r.Predictions[col])/float64(p.ZS) + 0.5))
		if q < 0 {
			cells[0][col] = '^'
		} else if q >= rows {
			cells[rows-1][col] = 'v'
		} else {
			cells[q][col] = '*'
			if marks[col] != 0 {
				cells[q][col] = marks[col]
			}
		}
	}
	for _, s := range plotLines(cells, p) {
		line(&summary, s)
	}
	writeLines("output/cleaning.txt", &cleaning)
	writeLines("output/constituents.csv",
		&constants)
	writeLines("output/predictions.csv", &predictions)
	writeLines("output/extremes.txt",
		&extremesOut)
	writeLines("output/summary.txt", &summary)
}
