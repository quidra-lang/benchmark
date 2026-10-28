package main

import (
	"fmt"
	"math"
	"os"
	"sort"
	"strings"
)

type Fit interface {
	Estimate(int) float64
	Weights(int) []float64
	FittedValues() []float64
	Leverages() []float64
	Degrees() float64
}
type BaseFit struct {
	Fitted, Leverage []float64
	EDF              float64
}

func (f *BaseFit) FittedValues() []float64 { return f.Fitted }
func (f *BaseFit) Leverages() []float64    { return f.Leverage }
func (f *BaseFit) Degrees() float64        { return f.EDF }
func absInt(v int) int {
	if v < 0 {
		return -v
	}
	return v
}

type LinearFit struct {
	BaseFit
	X                           []float64
	XBar, SXX, Slope, Intercept float64
}

func newLinearFit(points []Point) *LinearFit {
	f := &LinearFit{BaseFit: BaseFit{EDF: 2}}
	_, y := pointData(points)
	for _, p := range points {
		f.X = append(f.X, float64(p.X)/100)
	}
	n := float64(len(points))
	f.XBar = orderedSum(f.X) / n
	ybar := orderedSum(y) / n
	var sxy float64
	for i, x := range f.X {
		d := x - f.XBar
		f.SXX += d * d
		sxy += d * (y[i] - ybar)
	}
	f.Slope = sxy / f.SXX
	f.Intercept = ybar - f.Slope*f.XBar
	for _, x := range f.X {
		f.Fitted = append(f.Fitted, f.Intercept+f.Slope*x)
		d := x - f.XBar
		f.Leverage = append(f.Leverage, 1/n+d*d/f.SXX)
	}
	return f
}
func (f *LinearFit) Estimate(position int) float64 {
	return f.Intercept + f.Slope*(float64(position)/100)
}
func (f *LinearFit) Weights(position int) []float64 {
	weights := make([]float64, len(f.X))
	for i, x := range f.X {
		weights[i] = 1/float64(len(f.X)) + (float64(position)/100-f.XBar)*(x-f.XBar)/f.SXX
	}
	return weights
}

type RunningFit struct {
	BaseFit
	Positions []int
	Windows   [][2]int
}

func newRunningFit(points []Point, width int, useMedian bool) *RunningFit {
	f := &RunningFit{}
	n := len(points)
	for i, p := range points {
		f.Positions = append(f.Positions, p.X)
		radius := min((width-1)/2, i, n-1-i)
		left, right := i-radius, i+radius+1
		f.Windows = append(f.Windows, [2]int{left, right})
		ys := []int{}
		total := 0
		for _, p := range points[left:right] {
			ys = append(ys, p.Y)
			total += p.Y
		}
		value := float64(total) / float64(100*len(ys))
		if useMedian {
			sort.Ints(ys)
			value = float64(ys[radius]) / 100
		}
		f.Fitted = append(f.Fitted, value)
		f.Leverage = append(f.Leverage, 1/float64(len(ys)))
	}
	f.EDF = orderedSum(f.Leverage)
	if useMedian {
		f.Leverage = nil
		f.EDF = math.NaN()
	}
	return f
}
func (f *RunningFit) Nearest(position int) int {
	best := 0
	for i, x := range f.Positions {
		if absInt(x-position) < absInt(f.Positions[best]-position) {
			best = i
		}
	}
	return best
}
func (f *RunningFit) Estimate(position int) float64 { return f.Fitted[f.Nearest(position)] }
func (f *RunningFit) Weights(position int) []float64 {
	window := f.Windows[f.Nearest(position)]
	weights := make([]float64, len(f.Positions))
	for i := window[0]; i < window[1]; i++ {
		weights[i] = 1 / float64(window[1]-window[0])
	}
	return weights
}

type IsoBlock struct{ Start, Stop, Total, Count int }
type IsotonicFit struct {
	BaseFit
	Positions                    []int
	Mode, Direction              string
	Blocks                       []IsoBlock
	RSSIncreasing, RSSDecreasing float64
}

func isotonicDirection(points []Point, direction string) ([]float64, []IsoBlock) {
	blocks := []IsoBlock{}
	for i, p := range points {
		blocks = append(blocks, IsoBlock{i, i, p.Y, 1})
		for len(blocks) >= 2 {
			a, b := blocks[len(blocks)-2], blocks[len(blocks)-1]
			left, right := a.Total*b.Count, b.Total*a.Count
			violates := left > right
			if direction == "decreasing" {
				violates = left < right
			}
			if !violates {
				break
			}
			blocks = append(blocks[:len(blocks)-2], IsoBlock{a.Start, b.Stop, a.Total + b.Total, a.Count + b.Count})
		}
	}
	fitted := make([]float64, len(points))
	for _, b := range blocks {
		value := float64(b.Total) / float64(100*b.Count)
		for i := b.Start; i <= b.Stop; i++ {
			fitted[i] = value
		}
	}
	return fitted, blocks
}
func newIsotonicFit(points []Point, mode string) *IsotonicFit {
	f := &IsotonicFit{Mode: mode, Direction: mode}
	for _, p := range points {
		f.Positions = append(f.Positions, p.X)
	}
	if mode == "auto" {
		increasing, ib := isotonicDirection(points, "increasing")
		decreasing, db := isotonicDirection(points, "decreasing")
		_, y := pointData(points)
		f.RSSIncreasing = residualSquare(y, increasing)
		f.RSSDecreasing = residualSquare(y, decreasing)
		f.Direction = "increasing"
		f.Fitted, f.Blocks = increasing, ib
		if f.RSSDecreasing < f.RSSIncreasing {
			f.Direction = "decreasing"
			f.Fitted, f.Blocks = decreasing, db
		}
	} else {
		f.Fitted, f.Blocks = isotonicDirection(points, mode)
	}
	f.EDF = float64(len(f.Blocks))
	return f
}
func (f *IsotonicFit) Estimate(position int) float64 {
	index := sort.Search(len(f.Positions), func(i int) bool { return f.Positions[i] > position }) - 1
	return f.Fitted[max(0, index)]
}
func (f *IsotonicFit) Weights(position int) []float64 { return nil }
func methodsInOrder(s *Settings) []string {
	methods := []string{"linear", "running_mean", "running_median"}
	for _, k := range s.Kernels {
		methods = append(methods, "nw_"+k)
	}
	for _, k := range s.Kernels {
		methods = append(methods, "ll_"+k)
	}
	for _, d := range s.Degrees {
		methods = append(methods, "loess"+d)
	}
	return append(methods, "spline", "isotonic")
}
func parametersFor(method string, s *Settings) []string {
	if strings.HasPrefix(method, "running_") {
		return s.Windows
	}
	if strings.HasPrefix(method, "nw_") || strings.HasPrefix(method, "ll_") {
		return s.Bandwidths
	}
	if strings.HasPrefix(method, "loess") {
		return s.Spans
	}
	if method == "spline" {
		return s.Lambdas
	}
	return nil
}
func fitModel(method, parameter string, points []Point, s *Settings, direction string, robust, diagnostics bool) Fit {
	if method == "linear" {
		return newLinearFit(points)
	}
	if strings.HasPrefix(method, "running_") {
		return newRunningFit(points, integer(parameter), method == "running_median")
	}
	if method == "isotonic" {
		return newIsotonicFit(points, direction)
	}
	positions, values := pointData(points)
	if strings.HasPrefix(method, "nw_") || strings.HasPrefix(method, "ll_") {
		return newKernelFit(positions, values, hundredths(parameter), method[3:], strings.HasPrefix(method, "ll_"), diagnostics)
	}
	if strings.HasPrefix(method, "loess") {
		iterations := 0
		if robust {
			iterations = s.RobustIterations
		}
		return newLoessFit(positions, values, hundredths(parameter), integer(method[5:]), iterations, diagnostics)
	}
	return newSplineFit(positions, values, decimal(parameter), diagnostics)
}
func validationPredictions(method, parameter string, points []Point, s *Settings, direction string, folds int) []float64 {
	predictions := make([]float64, len(points))
	for group := range folds {
		training := []Point{}
		for i, p := range points {
			if i%folds != group {
				training = append(training, p)
			}
		}
		model := fitModel(method, parameter, training, s, direction, false, false)
		for i := group; i < len(points); i += folds {
			predictions[i] = model.Estimate(points[i].X)
		}
	}
	return predictions
}

type Candidate struct {
	Parameter  string
	Score, EDF float64
	Selected   bool
}
type Entry struct {
	Model           Fit
	Parameter       string
	Loo, KFold, GCV float64
	Candidates      []Candidate
	GridValues      []float64
	Stats           *Diagnostics
}

func selectModels(points []Point, s *Settings, methods []string, mode string) map[string]*Entry {
	_, observed := pointData(points)
	entries := map[string]*Entry{}
	for _, method := range methods {
		entry := &Entry{GCV: math.NaN()}
		for _, parameter := range parametersFor(method, s) {
			candidate := fitModel(method, parameter, points, s, mode, false, true)
			score := math.NaN()
			if method == "spline" {
				score = generalizedScore(observed, candidate.FittedValues(), candidate.Degrees())
			} else {
				score = crossValidationScore(observed, validationPredictions(method, parameter, points, s, mode, len(points)))
			}
			entry.Candidates = append(entry.Candidates, Candidate{parameter, score, candidate.Degrees(), false})
		}
		best := -1
		if len(entry.Candidates) > 0 {
			best = chooseCandidate(entry.Candidates)
			entry.Candidates[best].Selected = true
			entry.Parameter = entry.Candidates[best].Parameter
		} else if method == "linear" {
			entry.Parameter = "-"
		} else {
			entry.Parameter = mode
		}
		entry.Model = fitModel(method, entry.Parameter, points, s, mode, true, true)
		direction := mode
		if method == "isotonic" {
			direction = entry.Model.(*IsotonicFit).Direction
			entry.Parameter = direction
		}
		if best >= 0 && method != "spline" {
			entry.Loo = entry.Candidates[best].Score
		} else {
			entry.Loo = crossValidationScore(observed, validationPredictions(method, entry.Parameter, points, s, direction, len(points)))
		}
		if method == "spline" {
			entry.GCV = entry.Candidates[best].Score
		}
		entry.KFold = crossValidationScore(observed, validationPredictions(method, entry.Parameter, points, s, direction, s.Folds))
		entries[method] = entry
	}
	return entries
}

type Diagnostics struct {
	Residuals, ACF, Quantiles                  []float64
	RSS, EDF, DF, RSE, R2, Nonlinear, DW, RunZ float64
	Runs, Positive, Negative, Largest, Turning int
}

func diagnostics(method string, model Fit, observed, grid []float64, linearRSS float64) *Diagnostics {
	n := len(observed)
	d := &Diagnostics{EDF: model.Degrees(), DF: math.NaN(), RSE: math.NaN(), Nonlinear: math.NaN()}
	for i, y := range observed {
		d.Residuals = append(d.Residuals, y-model.FittedValues()[i])
	}
	d.RSS = residualSquare(observed, model.FittedValues())
	mean := orderedSum(observed) / float64(n)
	tss := 0.0
	for _, y := range observed {
		tss += (y - mean) * (y - mean)
	}
	d.R2 = 1 - d.RSS/tss
	if !math.IsNaN(d.EDF) {
		d.DF = float64(n) - d.EDF
		d.RSE = math.Sqrt(d.RSS / d.DF)
		if method != "linear" && d.EDF > 2 {
			d.Nonlinear = ((linearRSS - d.RSS) / (d.EDF - 2)) / (d.RSS / d.DF)
		}
	}
	emean := orderedSum(d.Residuals) / float64(n)
	centered := make([]float64, n)
	denominator := 0.0
	for i, e := range d.Residuals {
		centered[i] = e - emean
		denominator += centered[i] * centered[i]
	}
	for lag := 1; lag <= 5; lag++ {
		total := 0.0
		for i := 0; i < n-lag; i++ {
			total += centered[i] * centered[i+lag]
		}
		d.ACF = append(d.ACF, total/denominator)
	}
	dw := 0.0
	previous := 0
	for i, e := range d.Residuals {
		if i > 0 {
			delta := e - d.Residuals[i-1]
			dw += delta * delta
		}
		if math.Abs(e) > math.Abs(d.Residuals[d.Largest]) {
			d.Largest = i
		}
		sign := 0
		if e > 0 {
			sign = 1
			d.Positive++
		} else if e < 0 {
			sign = -1
			d.Negative++
		}
		if sign != 0 {
			if sign != previous {
				d.Runs++
			}
			previous = sign
		}
	}
	d.DW = dw / d.RSS
	count := d.Positive + d.Negative
	product := 2 * d.Positive * d.Negative
	mu := 1 + float64(product)/float64(count)
	variance := float64(product*(product-count)) / float64(count*count*(count-1))
	d.RunZ = (float64(d.Runs) - mu) / math.Sqrt(variance)
	ordered := append([]float64(nil), d.Residuals...)
	sort.Float64s(ordered)
	for k := range 5 {
		j, r := (n-1)*k/4, (n-1)*k%4
		v := ordered[j]
		if r != 0 {
			v += float64(r) / 4 * (ordered[j+1] - ordered[j])
		}
		d.Quantiles = append(d.Quantiles, v)
	}
	defined := []float64{}
	for _, v := range grid {
		if !math.IsNaN(v) {
			defined = append(defined, v)
		}
	}
	previous = 0
	for i := 1; i < len(defined); i++ {
		diff := defined[i] - defined[i-1]
		if diff != 0 {
			sign := 1
			if diff < 0 {
				sign = -1
			}
			if previous != 0 && sign != previous {
				d.Turning++
			}
			previous = sign
		}
	}
	return d
}

type Agreement struct {
	Count, Position int
	RMS, Maximum    float64
}
type Slopes struct {
	Maximum, Minimum float64
	AtMax, AtMin     int
}
type OutlierData struct {
	Method                string
	Standardized, Cooks   map[int]float64
	Outliers, Influential []int
}

func outliersAndInfluence(entries map[string]*Entry, ranking []string, threshold float64) *OutlierData {
	data := &OutlierData{Standardized: map[int]float64{}, Cooks: map[int]float64{}}
	for _, name := range ranking {
		if entries[name].Model.Leverages() != nil {
			data.Method = name
			break
		}
	}
	entry := entries[data.Method]
	for i, lev := range entry.Model.Leverages() {
		if lev < 1 {
			t := entry.Stats.Residuals[i] / (entry.Stats.RSE * math.Sqrt(1-lev))
			data.Standardized[i] = t
			data.Cooks[i] = t * t * lev / ((1 - lev) * entry.Model.Degrees())
			data.Influential = append(data.Influential, i)
			if math.Abs(t) > threshold {
				data.Outliers = append(data.Outliers, i)
			}
		}
	}
	sort.Slice(data.Outliers, func(i, j int) bool {
		a, b := data.Outliers[i], data.Outliers[j]
		va, vb := math.Abs(data.Standardized[a]), math.Abs(data.Standardized[b])
		if va != vb {
			return va > vb
		}
		return a < b
	})
	sort.Slice(data.Influential, func(i, j int) bool {
		a, b := data.Influential[i], data.Influential[j]
		if data.Cooks[a] != data.Cooks[b] {
			return data.Cooks[a] > data.Cooks[b]
		}
		return a < b
	})
	data.Influential = data.Influential[:min(3, len(data.Influential))]
	return data
}
func standardError(model Fit, rse float64, position int) float64 {
	total := 0.0
	for _, w := range model.Weights(position) {
		total += w * w
	}
	return rse * math.Sqrt(total)
}
func variabilityBands(model Fit, rse float64, grid []int, z float64) [][4]float64 {
	rows := [][4]float64{}
	for _, p := range grid {
		value := model.Estimate(p)
		if math.IsNaN(value) {
			rows = append(rows, [4]float64{value, value, value, value})
			continue
		}
		se := standardError(model, rse, p)
		rows = append(rows, [4]float64{value, se, value - z*se, value + z*se})
	}
	return rows
}

type BandSummary struct {
	MeanSE  float64
	Covered int
}

func bandSummary(entry *Entry, positions []int, bands [][4]float64, z float64) BandSummary {
	total, count, covered := 0.0, 0, 0
	for _, row := range bands {
		if !math.IsNaN(row[0]) {
			total += row[1]
			count++
		}
	}
	rse := entry.Stats.RSE
	for i, p := range positions {
		se := standardError(entry.Model, rse, p)
		if math.Abs(entry.Stats.Residuals[i]) <= z*math.Sqrt(rse*rse+se*se) {
			covered++
		}
	}
	return BandSummary{total / float64(count), covered}
}

type Minstd struct{ State int64 }

func (g *Minstd) Index(count int) int {
	g.State = g.State * 48271 % 2147483647
	return int(g.State % int64(count))
}
func bootstrapIntervals(entry *Entry, grid []int, count, trim int, g *Minstd) [][4]float64 {
	model := entry.Model.(*SplineFit)
	residuals := entry.Stats.Residuals
	mean := orderedSum(residuals) / float64(len(residuals))
	centered := make([]float64, len(residuals))
	for i, v := range residuals {
		centered[i] = v - mean
	}
	estimates := make([][]float64, len(grid))
	for range count {
		response := make([]float64, len(centered))
		for i, v := range model.Fitted {
			response[i] = v + centered[g.Index(len(centered))]
		}
		fit := model.FitValues(response)
		for i, p := range grid {
			estimates[i] = append(estimates[i], model.EvaluateFit(fit, p))
		}
	}
	rows := [][4]float64{}
	for i, values := range estimates {
		average := orderedSum(values) / float64(count)
		total := 0.0
		for _, v := range values {
			total += (v - average) * (v - average)
		}
		se := math.Sqrt(total / float64(count-1))
		ordered := append([]float64(nil), values...)
		sort.Float64s(ordered)
		rows = append(rows, [4]float64{model.Estimate(grid[i]), se, ordered[trim], ordered[count-trim-1]})
	}
	return rows
}

type Analysis struct {
	Name        string
	Points      []Point
	Grid        []int
	Entries     map[string]*Entry
	Ranking     []string
	Agreement   map[string]Agreement
	Slope       Slopes
	Outlier     *OutlierData
	Bands       map[string][][4]float64
	BandSummary map[string]BandSummary
}

func analyzeSeries(series *Series, s *Settings, methods []string, mode string, g *Minstd) *Analysis {
	points := series.Points
	positions, values := pointData(points)
	a := &Analysis{Name: series.Name, Points: points, Entries: selectModels(points, s, methods, mode),
		Agreement: map[string]Agreement{}, Bands: map[string][][4]float64{}, BandSummary: map[string]BandSummary{}}
	for k := range s.GridPoints {
		a.Grid = append(a.Grid, positions[0]+k*(positions[len(positions)-1]-positions[0])/(s.GridPoints-1))
	}
	linearRSS := residualSquare(values, a.Entries["linear"].Model.FittedValues())
	for _, name := range methods {
		entry := a.Entries[name]
		for _, p := range a.Grid {
			entry.GridValues = append(entry.GridValues, entry.Model.Estimate(p))
		}
		entry.Stats = diagnostics(name, entry.Model, values, entry.GridValues, linearRSS)
	}
	a.Ranking = append([]string(nil), methods...)
	sort.SliceStable(a.Ranking, func(i, j int) bool { return a.Entries[a.Ranking[i]].Loo < a.Entries[a.Ranking[j]].Loo })
	best := a.Entries[a.Ranking[0]].GridValues
	for _, name := range methods {
		if name == a.Ranking[0] {
			continue
		}
		own := a.Entries[name].GridValues
		result := Agreement{Maximum: -1}
		total := 0.0
		for i, v := range own {
			if !math.IsNaN(v) && !math.IsNaN(best[i]) {
				d := math.Abs(v - best[i])
				result.Count++
				total += d * d
				if d > result.Maximum {
					result.Maximum = d
					result.Position = a.Grid[i]
				}
			}
		}
		result.RMS = math.Sqrt(total / float64(result.Count))
		a.Agreement[name] = result
	}
	spline := a.Entries["spline"].GridValues
	a.Slope = Slopes{Maximum: math.Inf(-1), Minimum: math.Inf(1)}
	for k := 1; k < len(a.Grid)-1; k++ {
		sigma := (spline[k+1] - spline[k-1]) / (float64(a.Grid[k+1]-a.Grid[k-1]) / 100)
		if sigma > a.Slope.Maximum {
			a.Slope.Maximum = sigma
			a.Slope.AtMax = a.Grid[k]
		}
		if sigma < a.Slope.Minimum {
			a.Slope.Minimum = sigma
			a.Slope.AtMin = a.Grid[k]
		}
	}
	a.Outlier = outliersAndInfluence(a.Entries, a.Ranking, s.Threshold)
	for _, method := range s.BandMethods {
		entry := a.Entries[method]
		a.Bands[method] = variabilityBands(entry.Model, entry.Stats.RSE, a.Grid, s.BandZ)
		a.BandSummary[method] = bandSummary(entry, positions, a.Bands[method], s.BandZ)
	}
	a.Bands["spline_bootstrap"] = bootstrapIntervals(a.Entries["spline"], a.Grid, s.Bootstrap, s.Trim, g)
	return a
}
func realPlaces(value float64, places int) string {
	if math.IsNaN(value) {
		return "NA"
	}
	text := fmt.Sprintf("%.*f", places, value)
	if strings.HasPrefix(text, "-") {
		zero := true
		for _, c := range text[1:] {
			if c != '0' && c != '.' {
				zero = false
			}
		}
		if zero {
			return text[1:]
		}
	}
	return text
}
func real(value float64) string { return realPlaces(value, 4) }
func positionText(value int) string {
	sign := ""
	if value < 0 {
		sign = "-"
		value = -value
	}
	return fmt.Sprintf("%s%d.%02d", sign, value/100, value%100)
}
func realList(values []float64) string {
	texts := make([]string, len(values))
	for i, v := range values {
		texts[i] = real(v)
	}
	return strings.Join(texts, " ")
}
func joinBlocks(blocks [][]string) []string {
	lines := []string{}
	for i, b := range blocks {
		if i > 0 {
			lines = append(lines, "")
		}
		lines = append(lines, b...)
	}
	return lines
}
func writeLines(name string, lines []string) {
	if err := os.WriteFile("output/"+name, []byte(strings.Join(lines, "\n")+"\n"), 0644); err != nil {
		panic(err)
	}
}
func selectionLines(analyses []*Analysis, methods []string) []string {
	lines := []string{"series,method,parameter,score,edf,selected"}
	for _, a := range analyses {
		for _, method := range methods {
			for _, c := range a.Entries[method].Candidates {
				selected := 0
				if c.Selected {
					selected = 1
				}
				lines = append(lines, fmt.Sprintf("%s,%s,%s,%s,%s,%d", a.Name, method, c.Parameter, real(c.Score), real(c.EDF), selected))
			}
		}
	}
	return lines
}
func fitLines(analyses []*Analysis, methods []string) []string {
	lines := []string{"series,x," + strings.Join(methods, ",")}
	for _, a := range analyses {
		for i, p := range a.Grid {
			fields := []string{a.Name, positionText(p)}
			for _, method := range methods {
				fields = append(fields, real(a.Entries[method].GridValues[i]))
			}
			lines = append(lines, strings.Join(fields, ","))
		}
	}
	return lines
}
func predictionLines(table map[string]*Analysis, tests []TestPoint, methods []string) []string {
	lines := []string{"series,x," + strings.Join(methods, ",")}
	for _, t := range tests {
		fields := []string{t.Name, positionText(t.X)}
		for _, method := range methods {
			fields = append(fields, real(table[t.Name].Entries[method].Model.Estimate(t.X)))
		}
		lines = append(lines, strings.Join(fields, ","))
	}
	return lines
}
func bandLines(analyses []*Analysis, s *Settings) []string {
	lines := []string{"series,method,x,fit,se,lower,upper"}
	for _, a := range analyses {
		methods := append(append([]string(nil), s.BandMethods...), "spline_bootstrap")
		for _, method := range methods {
			for i, p := range a.Grid {
				fields := []string{a.Name, method, positionText(p)}
				for _, v := range a.Bands[method][i] {
					fields = append(fields, real(v))
				}
				lines = append(lines, strings.Join(fields, ","))
			}
		}
	}
	return lines
}
func methodDiagnosticLines(method string, e *Entry, points []Point) []string {
	d := e.Stats
	first := fmt.Sprintf("method %s parameter %s loo %s", method, e.Parameter, real(e.Loo))
	if method == "spline" {
		first += " gcv " + real(e.GCV)
	}
	lines := []string{first, fmt.Sprintf("  rss %s edf %s df %s rse %s r2 %s f_nonlinear %s", real(d.RSS),
		real(d.EDF), real(d.DF), real(d.RSE), real(d.R2), real(d.Nonlinear)), "  acf " + realList(d.ACF) + " dw " + real(d.DW),
		fmt.Sprintf("  runs %d positive %d negative %d z %s", d.Runs, d.Positive, d.Negative, real(d.RunZ)),
		fmt.Sprintf("  max_residual %s at %s turning %d", real(d.Residuals[d.Largest]), positionText(points[d.Largest].X),
			d.Turning), "  quantiles " + realList(d.Quantiles)}
	if model, ok := e.Model.(*LoessFit); ok {
		for _, r := range model.Records {
			lines = append(lines, fmt.Sprintf("  robust %d scale %s zero_weight %d max_change %s", r.Iteration, real(r.Scale), r.ZeroCount, real(r.Change)))
		}
		zeros := []string{}
		for i, w := range model.Rho {
			if w == 0 {
				zeros = append(zeros, positionText(points[i].X))
			}
		}
		text := "none"
		if len(zeros) > 0 {
			text = strings.Join(zeros, " ")
		}
		lines = append(lines, "  zero_weight_points "+text)
	}
	return lines
}
func diagnosticsBlock(a *Analysis, methods []string, s *Settings) []string {
	points := a.Points
	low, high := points[0].Y, points[0].Y
	for _, p := range points {
		low = min(low, p.Y)
		high = max(high, p.Y)
	}
	lines := []string{fmt.Sprintf("series %s n %d x %s %s y %s %s", a.Name, len(points), positionText(points[0].X),
		positionText(points[len(points)-1].X), positionText(low), positionText(high))}
	for _, method := range methods {
		lines = append(lines, methodDiagnosticLines(method, a.Entries[method], points)...)
	}
	lines = append(lines, "ranking")
	for i, name := range a.Ranking {
		e := a.Entries[name]
		lines = append(lines, fmt.Sprintf("  %d %s %s kfold %s", i+1, name, real(e.Loo), real(e.KFold)))
	}
	lines = append(lines, "agreement with "+a.Ranking[0])
	for _, name := range methods {
		if name == a.Ranking[0] {
			continue
		}
		r := a.Agreement[name]
		lines = append(lines, fmt.Sprintf("  %s points %d rms %s max %s at %s", name, r.Count, real(r.RMS), real(r.Maximum), positionText(r.Position)))
	}
	slope := a.Slope
	lines = append(lines, fmt.Sprintf("slope spline max %s at %s min %s at %s", real(slope.Maximum),
		positionText(slope.AtMax), real(slope.Minimum), positionText(slope.AtMin)))
	o := a.Outlier
	entry := a.Entries[o.Method]
	lines = append(lines, fmt.Sprintf("outliers method %s threshold %s", o.Method, realPlaces(s.Threshold, 2)))
	for _, i := range o.Outliers {
		lines = append(lines, fmt.Sprintf("  x %s y %s fit %s residual %s standardized %s", positionText(points[i].X),
			positionText(points[i].Y), real(entry.Model.FittedValues()[i]), real(entry.Stats.Residuals[i]),
			real(o.Standardized[i])))
	}
	if len(o.Outliers) == 0 {
		lines = append(lines, "  none")
	}
	lines = append(lines, "influence method "+o.Method)
	for _, i := range o.Influential {
		lines = append(lines, fmt.Sprintf("  x %s lev %s cook %s", positionText(points[i].X), real(entry.Model.Leverages()[i]), real(o.Cooks[i])))
	}
	lines = append(lines, "bands")
	for _, method := range s.BandMethods {
		b := a.BandSummary[method]
		lines = append(lines, fmt.Sprintf("  %s mean_se %s coverage %d of %d", method, real(b.MeanSE), b.Covered, len(points)))
	}
	return lines
}
func isotonicBlock(a *Analysis) []string {
	entry := a.Entries["isotonic"]
	model := entry.Model.(*IsotonicFit)
	first := fmt.Sprintf("series %s direction %s mode %s", a.Name, model.Direction, model.Mode)
	if model.Mode == "auto" {
		first += fmt.Sprintf(" rss_increasing %s rss_decreasing %s", real(model.RSSIncreasing), real(model.RSSDecreasing))
	}
	lines := []string{first, fmt.Sprintf("blocks %d rss %s loo %s", len(model.Blocks), real(entry.Stats.RSS), real(entry.Loo))}
	for i, b := range model.Blocks {
		lines = append(lines, fmt.Sprintf("block %d x %s %s count %d value %s", i+1, positionText(model.Positions[b.Start]),
			positionText(model.Positions[b.Stop]), b.Count, real(float64(b.Total)/float64(100*b.Count))))
	}
	return lines
}
func framed(grid [][]byte) []string {
	border := "+" + strings.Repeat("-", len(grid[0])) + "+"
	lines := []string{border}
	for _, row := range grid {
		lines = append(lines, "|"+string(row)+"|")
	}
	return append(lines, border)
}
func emptyGrid(width, height int) [][]byte {
	grid := make([][]byte, height)
	for i := range grid {
		grid[i] = []byte(strings.Repeat(" ", width))
	}
	return grid
}
func histogramLines(standardized map[int]float64) []string {
	counts := [14]int{}
	for _, v := range standardized {
		index := 0
		if v >= 3 {
			index = 13
		} else if v >= -3 {
			index = 1 + int(math.Floor((v+3)/0.5))
		}
		counts[index]++
	}
	lines := []string{}
	for i, count := range counts {
		lower, upper := "-inf", "inf"
		if i > 0 {
			lower = realPlaces(-3+0.5*float64(i-1), 2)
		}
		if i < 13 {
			upper = realPlaces(-3+0.5*float64(i), 2)
		}
		lines = append(lines, fmt.Sprintf("%s %s %d |%s", lower, upper, count, strings.Repeat("#", count)))
	}
	return lines
}
func plotBlock(a *Analysis, s *Settings) []string {
	points := a.Points
	width, height := s.Width, s.Height
	xa, xb := points[0].X, points[len(points)-1].X
	ya, yb := points[0].Y, points[0].Y
	for _, p := range points {
		ya = min(ya, p.Y)
		yb = max(yb, p.Y)
	}
	columns := make([]int, len(points))
	grid := emptyGrid(width, height)
	for i, p := range points {
		columns[i] = min(width-1, width*(p.X-xa)/(xb-xa))
		row := min(height-1, height*(yb-p.Y)/(yb-ya))
		grid[row][columns[i]] = '.'
	}
	for number, name := range s.PlotMethods {
		model := a.Entries[name].Model
		for col := range width {
			position := xa + (2*col+1)*(xb-xa)/(2*width)
			v := model.Estimate(position)
			if math.IsNaN(v) {
				continue
			}
			pi := float64(height) * (float64(yb)/100 - v) / (float64(yb)/100 - float64(ya)/100)
			row := max(0, min(height-1, int(math.Floor(pi))))
			digit := byte('1' + number)
			old := grid[row][col]
			if old == ' ' || old == '.' || old == digit {
				grid[row][col] = digit
			} else {
				grid[row][col] = '*'
			}
		}
	}
	legend := []string{}
	for i, name := range s.PlotMethods {
		legend = append(legend, fmt.Sprintf("%d %s", i+1, name))
	}
	lines := []string{fmt.Sprintf("plot %s size %dx%d x %s %s y %s %s", a.Name, width, height, positionText(xa),
		positionText(xb), positionText(ya), positionText(yb)), "legend . data " + strings.Join(legend,
		" ")}
	lines = append(lines, framed(grid)...)
	data, curve, overlap := 0, 0, 0
	for _, row := range grid {
		for _, c := range row {
			if c == '.' {
				data++
			} else if c == '*' {
				overlap++
			} else if c >= '1' && c <= '9' {
				curve++
			}
		}
	}
	lines = append(lines, fmt.Sprintf("cells data %d curve %d overlap %d", data, curve, overlap))
	best := a.Ranking[0]
	residuals := a.Entries[best].Stats.Residuals
	limit := 0.0
	for _, v := range residuals {
		limit = max(limit, math.Abs(v))
	}
	grid = emptyGrid(width, height)
	grid[height/2] = []byte(strings.Repeat("-", width))
	for i, v := range residuals {
		row := max(0, min(height-1, int(math.Floor(float64(height)*((limit-v)/(2*limit))))))
		grid[row][columns[i]] = 'o'
	}
	lines = append(lines, "", fmt.Sprintf("residuals %s method %s limit %s", a.Name, best, real(limit)))
	lines = append(lines, framed(grid)...)
	lines = append(lines, "", "histogram "+a.Name+" method "+a.Outlier.Method)
	return append(lines, histogramLines(a.Outlier.Standardized)...)
}
func main() {
	series, tests, s := readDataset()
	methods := methodsInOrder(s)
	generator := &Minstd{s.Seed}
	analyses := []*Analysis{}
	table := map[string]*Analysis{}
	for i, series := range series {
		a := analyzeSeries(series, s, methods, s.Isotonic[i], generator)
		analyses = append(analyses, a)
		table[a.Name] = a
	}
	diagnosticBlocks, isotonicBlocks, plots := [][]string{}, [][]string{}, [][]string{}
	for _, a := range analyses {
		diagnosticBlocks = append(diagnosticBlocks, diagnosticsBlock(a, methods, s))
		isotonicBlocks = append(isotonicBlocks, isotonicBlock(a))
	}
	for _, name := range s.PlotSeries {
		plots = append(plots, plotBlock(table[name], s))
	}
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	writeLines("selection.csv", selectionLines(analyses, methods))
	writeLines("fits.csv", fitLines(analyses, methods))
	writeLines("predictions.csv", predictionLines(table, tests, methods))
	writeLines("bands.csv", bandLines(analyses, s))
	writeLines("diagnostics.txt", joinBlocks(diagnosticBlocks))
	writeLines("isotonic.txt", joinBlocks(isotonicBlocks))
	writeLines("plots.txt", joinBlocks(plots))
}
