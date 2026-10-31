package main

import (
	"fmt"
	"math"
	"os"
	"sort"
	"strconv"
	"strings"
)

var criteria = []string{"kaiser", "broken_stick", "parallel", "cumulative"}

type VariableSummary struct {
	Observed, Missing          int
	Mean, SD, Minimum, Maximum float64
}
type AnalysisData struct {
	IDs    []string
	Values [][]float64
}
type Decomposition struct {
	Data                            AnalysisData
	Means, Deviations, Scales       []float64
	Covariance, Correlation, Matrix [][]float64
	Eigen                           EigenSystem
}
type Adequacy struct {
	MSA                        []float64
	KMO, Determinant, Bartlett float64
	DF                         int
}
type VarianceTable struct {
	Total, Average                               float64
	Ratios, Cumulative, Broken, Parallel, Errors []float64
	Separated                                    []bool
	Retention                                    map[string]int
}
type Varimax struct {
	Criteria, Squares, Congruences []float64
	Columns                        [][]float64
	Closest                        []int
}
type Observation struct {
	ID                   string
	Z, Scores, Residuals []float64
	T2, SPE              float64
	Flag                 string
}
type Sensitivity struct {
	Strategy, Scaling      string
	Rows, Sweeps           int
	Eigenvalues, Agreement []float64
	Cumulative             float64
}
type PcaReport struct {
	Dataset                   Dataset
	Names, IDs, Incomplete    []string
	Size, Rows, Components    int
	Summaries                 []VariableSummary
	ObservedMeans             []float64
	Fit                       Decomposition
	Adequacy                  Adequacy
	Power                     []PowerComponent
	Variance                  VarianceTable
	Strongest                 [][2]int
	Loadings, Circle          [][]float64
	Communalities             []float64
	Varimax                   Varimax
	Observations, Projections []Observation
	Sensitivity               []Sensitivity
}

func realText(v float64, digits int) string {
	s := fmt.Sprintf("%.*f", digits, v)
	if strings.HasPrefix(s, "-") {
		x, e := strconv.ParseFloat(s, 64)
		if e == nil && x == 0 {
			s = s[1:]
		}
	}
	return s
}
func real(v float64) string { return realText(v, 4) }
func reals(values []float64) []string {
	out := make([]string, len(values))
	for i, v := range values {
		out[i] = real(v)
	}
	return out
}
func componentNames(prefix string, count int) []string {
	out := make([]string, count)
	for k := range out {
		out[k] = fmt.Sprintf("%s%d", prefix, k+1)
	}
	return out
}
func hasMissing(row []float64) bool {
	for _, x := range row {
		if math.IsNaN(x) {
			return true
		}
	}
	return false
}
func largestIndex(values []float64) int {
	best := 0
	for i := 1; i < len(values); i++ {
		if values[i] > values[best] {
			best = i
		}
	}
	return best
}
func smallestIndex(values []float64) int {
	best := 0
	for i := 1; i < len(values); i++ {
		if values[i] < values[best] {
			best = i
		}
	}
	return best
}
func topIndices(values []float64, count int) []int {
	order := make([]int, len(values))
	for i := range order {
		order[i] = i
	}
	sort.SliceStable(order, func(i, j int) bool { return values[order[i]] > values[order[j]] })
	return order[:min(count, len(order))]
}
func congruence(a, b []float64) float64 { return dot(a, b) / math.Sqrt(dot(a, a)*dot(b, b)) }
func ratios(values []float64) []float64 {
	total := sum(values)
	out := make([]float64, len(values))
	for i, v := range values {
		out[i] = v / total
	}
	return out
}
func cumulativeRatios(values []float64) []float64 {
	out := make([]float64, len(values))
	running := 0.0
	for i, v := range values {
		running += v
		out[i] = running
	}
	return out
}
func analysisData(t Table, strategy string, means []float64) AnalysisData {
	out := AnalysisData{}
	for i, row := range t.Rows {
		if strategy == "listwise" && hasMissing(row) {
			continue
		}
		values := append([]float64{}, row...)
		for j, x := range values {
			if math.IsNaN(x) {
				values[j] = means[j]
			}
		}
		out.IDs = append(out.IDs, t.IDs[i])
		out.Values = append(out.Values, values)
	}
	return out
}
func decompose(data AnalysisData, scaling string) Decomposition {
	means := columnMeans(data.Values)
	cov := covarianceMatrix(data.Values, means)
	sd := standardDeviations(cov)
	corr := correlationMatrix(cov, sd)
	matrix := cov
	scales := make([]float64, len(means))
	for j := range scales {
		scales[j] = 1
	}
	if scaling == "correlation" {
		matrix = corr
		scales = sd
	}
	return Decomposition{data, means, sd, scales, cov, corr, matrix, jacobi(matrix)}
}
func samplingAdequacy(correlation [][]float64, rows int) Adequacy {
	p := len(correlation)
	inverse, det := gaussJordan(correlation)
	msa := make([]float64, p)
	rr, pp := make([]float64, p), make([]float64, p)
	for j := 0; j < p; j++ {
		for k := 0; k < p; k++ {
			if j == k {
				continue
			}
			r := correlation[j][k]
			pr := -inverse[j][k] / math.Sqrt(inverse[j][j]*inverse[k][k])
			rr[j] += r * r
			pp[j] += pr * pr
		}
		msa[j] = rr[j] / (rr[j] + pp[j])
	}
	totalR, totalP := sum(rr), sum(pp)
	bartlett := -(float64(rows-1) - float64(2*p+5)/6) * math.Log(det)
	return Adequacy{msa, totalR / (totalR + totalP), det, bartlett, p * (p - 1) / 2}
}
func parallelAnalysis(n, p, iterations int, seed int64) []float64 {
	totals := make([]float64, p)
	state := seed
	for iteration := 0; iteration < iterations; iteration++ {
		values := zeros(n, p)
		for i := range values {
			for j := range values[i] {
				state = 48271 * state % 2147483647
				values[i][j] = float64(state) / 2147483647
			}
		}
		cov := covarianceMatrix(values, columnMeans(values))
		corr := correlationMatrix(cov, standardDeviations(cov))
		r := ratios(jacobi(corr).Values)
		for k, x := range r {
			totals[k] += x
		}
	}
	for k := range totals {
		totals[k] /= float64(iterations)
	}
	return totals
}
func firstCrossing(ratios, thresholds []float64) int {
	for k, v := range ratios {
		if v <= thresholds[k] {
			return k
		}
	}
	return len(ratios)
}
func varianceTable(values []float64, rows int, parallel []float64, target float64) VarianceTable {
	p := len(values)
	v := VarianceTable{Total: sum(values), Ratios: ratios(values), Parallel: parallel, Retention: map[string]int{},
		Broken: make([]float64, p), Errors: make([]float64, p), Separated: make([]bool, p)}
	v.Average = v.Total / float64(p)
	v.Cumulative = cumulativeRatios(v.Ratios)
	for k, value := range values {
		for i := k + 1; i <= p; i++ {
			v.Broken[k] += 1 / float64(i)
		}
		v.Broken[k] /= float64(p)
		v.Errors[k] = value * math.Sqrt(2/float64(rows))
		v.Separated[k] = true
		for _, h := range []int{k - 1, k + 1} {
			if h >= 0 && h < p && !(math.Abs(value-values[h]) > v.Errors[k]) {
				v.Separated[k] = false
			}
		}
		if value > v.Average {
			v.Retention["kaiser"]++
		}
	}
	v.Retention["broken_stick"] = firstCrossing(v.Ratios, v.Broken)
	v.Retention["parallel"] = firstCrossing(v.Ratios, parallel)
	v.Retention["cumulative"] = p
	for k, x := range v.Cumulative {
		if x >= target {
			v.Retention["cumulative"] = k + 1
			break
		}
	}
	return v
}
func varimaxCriterion(g [][]float64) float64 {
	p := float64(len(g))
	total := 0.0
	for k := range g[0] {
		q4, q2 := 0.0, 0.0
		for _, row := range g {
			q4 += (row[k] * row[k]) * (row[k] * row[k])
			q2 += row[k] * row[k]
		}
		total += q4/p - (q2/p)*(q2/p)
	}
	return total
}
func rotatePair(g [][]float64, a, b int) {
	p := float64(len(g))
	sa, sb, sc, sd := 0.0, 0.0, 0.0, 0.0
	for _, row := range g {
		phi := row[a]*row[a] - row[b]*row[b]
		psi := 2 * row[a] * row[b]
		sa += phi
		sb += psi
		sc += phi*phi - psi*psi
		sd += 2 * phi * psi
	}
	num := sd - 2*sa*sb/p
	den := sc - (sa*sa-sb*sb)/p
	omega := math.Sqrt(num*num + den*den)
	if omega == 0 {
		return
	}
	cos4, sin4 := den/omega, num/omega
	cos2 := math.Sqrt((1 + cos4) / 2)
	sin2 := 1.0
	if cos2 != 0 {
		sin2 = sin4 / (2 * cos2)
	}
	cos1 := math.Sqrt((1 + cos2) / 2)
	sin1 := sin2 / (2 * cos1)
	for _, row := range g {
		x, y := row[a], row[b]
		row[a] = cos1*x + sin1*y
		row[b] = -sin1*x + cos1*y
	}
}
func rotateVarimax(loadings [][]float64, components, cycles int) Varimax {
	p := len(loadings)
	etas := make([]float64, p)
	g := zeros(p, components)
	for j, row := range loadings {
		s := 0.0
		for k := 0; k < components; k++ {
			s += row[k] * row[k]
		}
		etas[j] = math.Sqrt(s)
		for k := 0; k < components; k++ {
			g[j][k] = row[k] / etas[j]
		}
	}
	out := Varimax{Criteria: []float64{varimaxCriterion(g)}}
	for cycle := 0; cycle < cycles; cycle++ {
		for a := 0; a < components-1; a++ {
			for b := a + 1; b < components; b++ {
				rotatePair(g, a, b)
			}
		}
		out.Criteria = append(out.Criteria, varimaxCriterion(g))
	}
	columns := make([][]float64, components)
	squares := make([]float64, components)
	for k := range columns {
		v := make([]float64, p)
		for j := range v {
			v[j] = g[j][k] * etas[j]
		}
		columns[k] = orient(v)
		squares[k] = dot(v, v)
	}
	for _, k := range topIndices(squares, components) {
		out.Columns = append(out.Columns, columns[k])
		out.Squares = append(out.Squares, squares[k])
	}
	for _, v := range out.Columns {
		matches := make([]float64, components)
		for k := range matches {
			matches[k] = math.Abs(congruence(v, column(loadings, k)))
		}
		best := largestIndex(matches)
		out.Closest = append(out.Closest, best)
		out.Congruences = append(out.Congruences, matches[best])
	}
	return out
}
func flagText(t2, spe float64, s Settings) string {
	flag := ""
	if t2 > s.T2Limit {
		flag += "T"
	}
	if spe > s.SPELimit {
		flag += "Q"
	}
	if flag == "" {
		flag = "-"
	}
	return flag
}
func (r *PcaReport) observation(id string, values []float64) Observation {
	z := standardize(values, r.Fit.Means, r.Fit.Scales)
	scores := componentScores(z, r.Fit.Eigen.Vectors)
	res := residuals(z, scores, r.Fit.Eigen.Vectors, r.Components)
	t2 := hotelling(scores, r.Fit.Eigen.Values, r.Components)
	spe := dot(res, res)
	return Observation{id, z, scores, res, t2, spe, flagText(t2, spe, r.Dataset.Settings)}
}
func newReport(ds Dataset) *PcaReport {
	r := &PcaReport{Dataset: ds, Names: ds.Data.Names, Size: len(ds.Data.Names)}
	p := r.Size
	s := ds.Settings
	for j := 0; j < p; j++ {
		values := []float64{}
		for _, row := range ds.Data.Rows {
			if !math.IsNaN(row[j]) {
				values = append(values, row[j])
			}
		}
		mean := sum(values) / float64(len(values))
		squares := 0.0
		lo, hi := values[0], values[0]
		for _, x := range values {
			squares += (x - mean) * (x - mean)
			lo = math.Min(lo, x)
			hi = math.Max(hi, x)
		}
		r.Summaries = append(r.Summaries, VariableSummary{len(values), len(ds.Data.Rows) - len(values), mean, math.Sqrt(squares / float64(len(values)-1)), lo, hi})
		r.ObservedMeans = append(r.ObservedMeans, mean)
	}
	for i, row := range ds.Data.Rows {
		if hasMissing(row) {
			r.Incomplete = append(r.Incomplete, ds.Data.IDs[i])
		}
	}
	main := analysisData(ds.Data, s.Missing, r.ObservedMeans)
	r.Fit = decompose(main, s.Scaling)
	r.IDs = main.IDs
	r.Rows = len(main.IDs)
	r.Adequacy = samplingAdequacy(r.Fit.Correlation, r.Rows)
	r.Power = powerIteration(r.Fit.Matrix, r.Fit.Eigen.Vectors)
	parallel := parallelAnalysis(r.Rows, p, s.Parallel, s.Seed)
	r.Variance = varianceTable(r.Fit.Eigen.Values, r.Rows, parallel, s.Target)
	if count, ok := r.Variance.Retention[s.Components]; ok {
		r.Components = max(1, count)
	} else {
		r.Components = integer(s.Components)
	}
	r.Loadings = zeros(p, p)
	r.Circle = zeros(p, 2)
	r.Communalities = make([]float64, p)
	for j := 0; j < p; j++ {
		for k, value := range r.Fit.Eigen.Values {
			r.Loadings[j][k] = r.Fit.Eigen.Vectors[k][j] * math.Sqrt(value)
		}
		sq := 0.0
		for k := 0; k < r.Components; k++ {
			sq += r.Loadings[j][k] * r.Loadings[j][k]
		}
		r.Communalities[j] = sq / r.Fit.Matrix[j][j]
		for k := 0; k < 2; k++ {
			r.Circle[j][k] = r.Loadings[j][k] / math.Sqrt(r.Fit.Matrix[j][j])
		}
	}
	pairs := [][2]int{}
	strength := []float64{}
	for j := 0; j < p; j++ {
		for k := j + 1; k < p; k++ {
			pairs = append(pairs, [2]int{j, k})
			strength = append(strength, math.Abs(r.Fit.Correlation[j][k]))
		}
	}
	for _, i := range topIndices(strength, s.Top) {
		r.Strongest = append(r.Strongest, pairs[i])
	}
	r.Varimax = rotateVarimax(r.Loadings, r.Components, s.Cycles)
	for i, values := range main.Values {
		r.Observations = append(r.Observations, r.observation(main.IDs[i], values))
	}
	for i, values := range ds.Supplementary.Rows {
		r.Projections = append(r.Projections, r.observation(ds.Supplementary.IDs[i], values))
	}
	for _, strategy := range []string{"listwise", "mean"} {
		for _, scaling := range []string{"covariance", "correlation"} {
			fit := decompose(analysisData(ds.Data, strategy, r.ObservedMeans), scaling)
			agreement := make([]float64, r.Components)
			for k := range agreement {
				agreement[k] = math.Abs(dot(fit.Eigen.Vectors[k], r.Fit.Eigen.Vectors[k]))
			}
			r.Sensitivity = append(r.Sensitivity, Sensitivity{strategy, scaling, len(fit.Data.IDs), fit.Eigen.Sweeps,
				append([]float64{}, fit.Eigen.Values[:r.Components]...), agreement, cumulativeRatios(ratios(fit.Eigen.Values))[r.Components-1]})
		}
	}
	return r
}
func (r *PcaReport) eigenFile() []string {
	s := r.Dataset.Settings
	incomplete := "0 -"
	if len(r.Incomplete) > 0 {
		incomplete = fmt.Sprintf("%d %s", len(r.Incomplete), strings.Join(r.Incomplete, " "))
	}
	sections := [][]string{{fmt.Sprintf("pca rows %d used %d variables %d missing %s scaling %s", len(r.Dataset.Data.Rows),
		r.Rows, r.Size, s.Missing, s.Scaling), "incomplete " + incomplete}}
	lines := []string{"variable observed missing mean sd min max msa"}
	for j, name := range r.Names {
		v := r.Summaries[j]
		lines = append(lines, fmt.Sprintf("%s %d %d %s", name, v.Observed, v.Missing, strings.Join(reals([]float64{v.Mean,
			v.SD, v.Minimum, v.Maximum, r.Adequacy.MSA[j]}), " ")))
	}
	a := r.Adequacy
	lines = append(lines, fmt.Sprintf("adequacy kmo %s determinant %s bartlett %s df %d", real(a.KMO), realText(a.Determinant, 6), real(a.Bartlett), a.DF))
	sections = append(sections, lines)
	lines = []string{"matrix " + s.Scaling}
	for j, name := range r.Names {
		lines = append(lines, name+" "+strings.Join(reals(r.Fit.Matrix[j]), " "))
	}
	line := "strongest"
	for _, pair := range r.Strongest {
		j, k := pair[0], pair[1]
		line += " " + r.Names[j] + ":" + r.Names[k] + ":" + real(r.Fit.Correlation[j][k])
	}
	lines = append(lines, line)
	sections = append(sections, lines)
	v := r.Variance
	lines = []string{fmt.Sprintf("jacobi sweeps %d", r.Fit.Eigen.Sweeps), fmt.Sprintf("eigenvalues total %s average %s",
		real(v.Total), real(v.Average)), "k eigenvalue ratio cumulative broken_stick parallel se separated"}
	for k, value := range r.Fit.Eigen.Values {
		separated := "no"
		if v.Separated[k] {
			separated = "yes"
		}
		lines = append(lines, fmt.Sprintf("%d %s %s", k+1, strings.Join(reals([]float64{value, v.Ratios[k],
			v.Cumulative[k], v.Broken[k], v.Parallel[k], v.Errors[k]}), " "), separated))
	}
	line = "retention"
	for _, name := range criteria {
		line += fmt.Sprintf(" %s %d", name, v.Retention[name])
	}
	lines = append(lines, line+" target "+real(s.Target), fmt.Sprintf("components %d rule %s", r.Components, s.Components))
	sections = append(sections, lines)
	lines = []string{"eigenvectors", "variable " + strings.Join(componentNames("pc", r.Size), " ")}
	for j, name := range r.Names {
		values := make([]float64, r.Size)
		for k := range values {
			values[k] = r.Fit.Eigen.Vectors[k][j]
		}
		lines = append(lines, name+" "+strings.Join(reals(values), " "))
	}
	sections = append(sections, lines)
	lines = []string{"power_iteration iterations 1000", "k jacobi power agree_at match"}
	matches := 0
	for k, p := range r.Power {
		match := math.Abs(p.Value-r.Fit.Eigen.Values[k]) <= 1e-8*r.Fit.Eigen.Values[0] && maxDifference(p.Vector, r.Fit.Eigen.Vectors[k]) <= 0.000001
		word := "no"
		if match {
			word = "yes"
			matches++
		}
		agreement := "-"
		if p.Agreement > 0 {
			agreement = strconv.Itoa(p.Agreement)
		}
		lines = append(lines, fmt.Sprintf("%d %s %s %s %s", k+1, real(r.Fit.Eigen.Values[k]), real(p.Value), agreement, word))
	}
	lines = append(lines, fmt.Sprintf("cross_check %d/%d", matches, r.Size))
	sections = append(sections, lines)
	lines = []string{"scores", "component sd min min_id max max_id contributors"}
	for k := 0; k < r.Components; k++ {
		scores := make([]float64, r.Rows)
		contributions := make([]float64, r.Rows)
		squares := 0.0
		for i, o := range r.Observations {
			x := o.Scores[k]
			scores[i] = x
			squares += x * x
			contributions[i] = x * x / (float64(r.Rows-1) * r.Fit.Eigen.Values[k])
		}
		low, high := smallestIndex(scores), largestIndex(scores)
		line := fmt.Sprintf("pc%d %s %s %s %s %s", k+1, real(math.Sqrt(squares/float64(r.Rows-1))), real(scores[low]), r.IDs[low], real(scores[high]), r.IDs[high])
		for _, i := range topIndices(contributions, s.Top) {
			line += " " + r.IDs[i] + ":" + real(contributions[i])
		}
		lines = append(lines, line)
	}
	sections = append(sections, lines)
	lines = []string{fmt.Sprintf("varimax components %d cycles %d", r.Components, s.Cycles)}
	for c, value := range r.Varimax.Criteria {
		lines = append(lines, fmt.Sprintf("cycle %d criterion %s", c, realText(value, 6)))
	}
	for k, value := range r.Varimax.Squares {
		lines = append(lines, fmt.Sprintf("rc%d ss %s ratio %s closest pc%d congruence %s", k+1, real(value),
			real(value/r.Variance.Total), r.Varimax.Closest[k]+1, real(r.Varimax.Congruences[k])))
	}
	sections = append(sections, lines)
	lines = []string{"sensitivity", "missing scaling rows sweeps eigenvalues cumulative congruence"}
	for _, v := range r.Sensitivity {
		line := fmt.Sprintf("%s %s %d %d ", v.Strategy, v.Scaling, v.Rows, v.Sweeps) + strings.Join(reals(v.Eigenvalues),
			" ") + " " + real(v.Cumulative) + " " + strings.Join(reals(v.Agreement), " ")
		lines = append(lines, line)
	}
	sections = append(sections, lines)
	return joinSections(sections)
}
func (r *PcaReport) loadingsFile() []string {
	header := append([]string{"variable"}, componentNames("pc", r.Components)...)
	header = append(header, "communality")
	header = append(header, componentNames("rc", r.Components)...)
	lines := []string{strings.Join(header, ",")}
	for j, name := range r.Names {
		values := append([]float64{}, r.Loadings[j][:r.Components]...)
		values = append(values, r.Communalities[j])
		for _, v := range r.Varimax.Columns {
			values = append(values, v[j])
		}
		lines = append(lines, name+","+strings.Join(reals(values), ","))
	}
	return lines
}
func (r *PcaReport) scoresFile() []string {
	header := append([]string{"id", "set"}, componentNames("pc", r.Components)...)
	lines := []string{strings.Join(header, ",")}
	for _, o := range r.Observations {
		lines = append(lines, o.ID+",data,"+strings.Join(reals(o.Scores[:r.Components]), ","))
	}
	for _, o := range r.Projections {
		lines = append(lines, o.ID+",supplementary,"+strings.Join(reals(o.Scores[:r.Components]), ","))
	}
	return lines
}
func (r *PcaReport) t2Contributions(o Observation) []float64 {
	out := make([]float64, r.Size)
	for j, z := range o.Z {
		w := 0.0
		for k := 0; k < r.Components; k++ {
			w += o.Scores[k] / r.Fit.Eigen.Values[k] * r.Fit.Eigen.Vectors[k][j]
		}
		out[j] = z * w
	}
	return out
}
func (r *PcaReport) topSection(label string, values []float64, contributions [][]float64) []string {
	lines := []string{"top " + label, "rank id " + label + " variable contribution"}
	for rank, i := range topIndices(values, r.Dataset.Settings.Top) {
		j := largestIndex(contributions[i])
		lines = append(lines, fmt.Sprintf("%d %s %s %s %s", rank+1, r.IDs[i], real(values[i]), r.Names[j], real(contributions[i][j])))
	}
	return lines
}
func (r *PcaReport) outliersFile() []string {
	s := r.Dataset.Settings
	lines := []string{fmt.Sprintf("diagnostics components %d t2_limit %s spe_limit %s", r.Components, real(s.T2Limit), real(s.SPELimit)), "id t2 spe quality flag"}
	tCount, qCount, both, any := 0, 0, 0, 0
	t2, spe := make([]float64, r.Rows), make([]float64, r.Rows)
	tc, qc := make([][]float64, r.Rows), make([][]float64, r.Rows)
	for i, o := range r.Observations {
		quality := dot(o.Scores[:r.Components], o.Scores[:r.Components]) / dot(o.Z, o.Z)
		lines = append(lines, o.ID+" "+strings.Join(reals([]float64{o.T2, o.SPE, quality}), " ")+" "+o.Flag)
		if strings.Contains(o.Flag, "T") {
			tCount++
		}
		if strings.Contains(o.Flag, "Q") {
			qCount++
		}
		if o.Flag == "TQ" {
			both++
		}
		if o.Flag != "-" {
			any++
		}
		t2[i], spe[i] = o.T2, o.SPE
		tc[i] = r.t2Contributions(o)
		qc[i] = make([]float64, r.Size)
		for j, e := range o.Residuals {
			qc[i][j] = e * e
		}
	}
	lines = append(lines, fmt.Sprintf("flagged t2 %d spe %d both %d any %d", tCount, qCount, both, any))
	sections := [][]string{lines, r.topSection("t2", t2, tc), r.topSection("spe", spe, qc)}
	lines = []string{"reconstruction", "k mean_spe max_spe max_id"}
	for k := 1; k < r.Size; k++ {
		errors := make([]float64, r.Rows)
		for i, o := range r.Observations {
			e := residuals(o.Z, o.Scores, r.Fit.Eigen.Vectors, k)
			errors[i] = dot(e, e)
		}
		worst := largestIndex(errors)
		lines = append(lines, fmt.Sprintf("%d %s %s %s", k, real(sum(errors)/float64(r.Rows)), real(errors[worst]), r.IDs[worst]))
	}
	sections = append(sections, lines)
	header := append([]string{"id"}, componentNames("pc", r.Components)...)
	header = append(header, "t2", "spe", "flag", "nearest", "distance")
	lines = []string{"supplementary", strings.Join(header, " ")}
	for _, o := range r.Projections {
		distances := make([]float64, r.Rows)
		for i, other := range r.Observations {
			d := make([]float64, r.Components)
			for k := range d {
				d[k] = o.Scores[k] - other.Scores[k]
			}
			distances[i] = dot(d, d)
		}
		nearest := smallestIndex(distances)
		values := append(append([]float64{}, o.Scores[:r.Components]...), o.T2, o.SPE)
		lines = append(lines, o.ID+" "+strings.Join(reals(values), " ")+" "+o.Flag+" "+r.IDs[nearest]+" "+real(math.Sqrt(distances[nearest])))
	}
	return joinSections(append(sections, lines))
}
func drawAxes(grid [][]byte, center Cell) {
	for c := range grid[center.Row] {
		grid[center.Row][c] = '-'
	}
	for r := range grid {
		grid[r][center.Column] = '|'
	}
	grid[center.Row][center.Column] = '+'
}
func markCells(grid [][]byte, cells []Cell, character byte) {
	for _, c := range cells {
		grid[c.Row][c.Column] = character
	}
}
func drawPoints(grid [][]byte, cells []Cell) {
	counts := map[Cell]int{}
	for _, c := range cells {
		counts[c]++
	}
	for c, n := range counts {
		v := byte('@')
		if n == 1 {
			v = '.'
		} else if n <= 3 {
			v = 'o'
		}
		grid[c.Row][c.Column] = v
	}
}
func insideCircle(row, col int, center Cell, radius int) bool {
	x, y := col-center.Column, 2*(row-center.Row)
	return x*x+y*y <= radius*radius
}
func (r *PcaReport) screeSection() []string {
	width := r.Dataset.Settings.ScreeWidth
	first := r.Fit.Eigen.Values[0]
	kaiser := roundedPosition(r.Variance.Average/first, float64(width))
	lines := []string{fmt.Sprintf("scree width %d kaiser_column %d", width, kaiser)}
	for k, value := range r.Fit.Eigen.Values {
		length := roundedPosition(value/first, float64(width))
		broken := roundedPosition(r.Variance.Broken[k]*r.Variance.Total/first, float64(width))
		lines = append(lines, fmt.Sprintf("%s pc%d %s", screeLine(length, kaiser, broken, width), k+1, real(value)))
	}
	return lines
}
func (r *PcaReport) biplotSection() []string {
	w, h := r.Dataset.Settings.BiplotWidth, r.Dataset.Settings.BiplotHeight
	points := append(append([]Observation{}, r.Observations...), r.Projections...)
	xLimit, yLimit := 0.0, 0.0
	for _, o := range points {
		xLimit = math.Max(xLimit, math.Abs(o.Scores[0]))
		yLimit = math.Max(yLimit, math.Abs(o.Scores[1]))
	}
	xLoading, yLoading := 0.0, 0.0
	for _, v := range r.Loadings {
		xLoading = math.Max(xLoading, math.Abs(v[0]))
		yLoading = math.Max(yLoading, math.Abs(v[1]))
	}
	scale := 0.9 * math.Min(xLimit/xLoading, yLimit/yLoading)
	origin := biplotCell(0, 0, xLimit, yLimit, w, h)
	tips := make([]Cell, r.Size)
	for j, v := range r.Loadings {
		tips[j] = biplotCell(scale*v[0], scale*v[1], xLimit, yLimit, w, h)
	}
	cells := make([]Cell, len(points))
	for i, o := range points {
		cells[i] = biplotCell(o.Scores[0], o.Scores[1], xLimit, yLimit, w, h)
	}
	grid := newGrid(h, w)
	drawAxes(grid, origin)
	for _, tip := range tips {
		markCells(grid, shaftCells(origin, tip), shaftCharacter(origin, tip))
	}
	drawPoints(grid, cells[:r.Rows])
	for i, o := range r.Observations {
		if o.Flag != "-" {
			markCells(grid, []Cell{cells[i]}, 'X')
		}
	}
	markCells(grid, cells[r.Rows:], '*')
	for j, tip := range tips {
		markCells(grid, []Cell{tip}, byte('A'+j))
	}
	lines := []string{fmt.Sprintf("biplot pc1 pc2 width %d height %d", w, h), fmt.Sprintf("x %s %s y %s %s arrow_scale %s",
		real(-xLimit), real(xLimit), real(-yLimit), real(yLimit), real(scale))}
	lines = append(lines, framed(grid)...)
	for j, name := range r.Names {
		lines = append(lines, fmt.Sprintf("%c %s %s %s", 'A'+j, name, real(r.Loadings[j][0]), real(r.Loadings[j][1])))
	}
	return lines
}
func (r *PcaReport) circleSection() []string {
	radius := r.Dataset.Settings.Radius
	center := Cell{radius/2 + 1, radius + 1}
	grid := newGrid(radius+3, 2*radius+3)
	drawAxes(grid, center)
	for row := range grid {
		for col := range grid[row] {
			if !insideCircle(row, col, center, radius) {
				continue
			}
			for _, d := range []Cell{{-1, 0}, {1, 0}, {0, -1}, {0, 1}} {
				if !insideCircle(row+d.Row, col+d.Column, center, radius) {
					grid[row][col] = '.'
					break
				}
			}
		}
	}
	for j, v := range r.Circle {
		markCells(grid, []Cell{circleCell(v[0], v[1], radius)}, byte('A'+j))
	}
	lines := []string{fmt.Sprintf("circle radius %d", radius)}
	lines = append(lines, framed(grid)...)
	for j, name := range r.Names {
		v := r.Circle[j]
		lines = append(lines, fmt.Sprintf("%c %s %s", 'A'+j, name, strings.Join(reals([]float64{v[0], v[1], v[0]*v[0] + v[1]*v[1]}), " ")))
	}
	return lines
}
func (r *PcaReport) diagnosticSection() []string {
	s := r.Dataset.Settings
	w, h := s.DiagnosticWidth, s.DiagnosticHeight
	x, y := 2*s.T2Limit, 2*s.SPELimit
	grid := newGrid(h, w)
	drawAxes(grid, diagnosticCell(s.T2Limit, s.SPELimit, x, y, w, h))
	cells := []Cell{}
	for _, o := range r.Observations {
		cells = append(cells, diagnosticCell(o.T2, o.SPE, x, y, w, h))
	}
	drawPoints(grid, cells)
	for _, o := range r.Projections {
		markCells(grid, []Cell{diagnosticCell(o.T2, o.SPE, x, y, w, h)}, '*')
	}
	lines := []string{fmt.Sprintf("diagnostic width %d height %d t2_max %s spe_max %s", w, h, real(x), real(y))}
	return append(lines, framed(grid)...)
}
func joinSections(sections [][]string) []string {
	lines := []string{}
	for _, s := range sections {
		if len(lines) > 0 {
			lines = append(lines, "")
		}
		lines = append(lines, s...)
	}
	return lines
}
func writeLines(name string, lines []string) {
	if e := os.WriteFile("output/"+name, []byte(strings.Join(lines, "\n")+"\n"), 0644); e != nil {
		panic(e)
	}
}
func main() {
	r := newReport(readDataset())
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	writeLines("eigen.txt", r.eigenFile())
	writeLines("loadings.csv", r.loadingsFile())
	writeLines("scores.csv", r.scoresFile())
	writeLines("outliers.txt", r.outliersFile())
	writeLines("plots.txt", joinSections([][]string{r.screeSection(), r.biplotSection(), r.circleSection(), r.diagnosticSection()}))
}
