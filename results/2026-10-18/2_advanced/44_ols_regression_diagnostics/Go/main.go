package main

import (
	"fmt"
	"math"
	"os"
	"sort"
	"strconv"
	"strings"
)

type Statistics struct {
	DF                                                                                  int
	Sigma, WeightSum, TSS, R2, Adjusted, F, P, LL, AIC, BIC, PRESS, Predicted, Critical float64
	Quantiles                                                                           []float64
}
type Coefficient struct{ Estimate, SE, T, P, Lower, Upper, RobustSE, RobustT, RobustP float64 }
type Anova struct {
	Index             int
	Name              string
	DF                int
	SS, MS, RSS, F, P float64
}
type VIFResult struct {
	Name  string
	Value float64
	High  bool
}
type ResetResult struct {
	F                   float64
	AddedDF, ResidualDF int
	P                   float64
}
type PredictionCheck struct {
	Predicted, Actual int
	RMSE              float64
	Covered           int
}
type Report struct {
	Number          int
	Design          *Design
	Fit             *Fit
	Stats           Statistics
	Coefficients    []Coefficient
	ANOVA, Marginal []Anova
	VIF             []VIFResult
	Diagnostic      Diagnostic
	Reset           ResetResult
	Predictions     []string
	Check           PredictionCheck
}

func text(v int) string { return strconv.Itoa(v) }
func table(header []string, rows [][]string, marks []string) []string {
	all := append([][]string{header}, rows...)
	widths := make([]int, len(header))
	for _, row := range all {
		for c, field := range row {
			widths[c] = max(widths[c], len(field))
		}
	}
	lines := []string{}
	for i, row := range all {
		line := row[0] + strings.Repeat(" ", widths[0]-len(row[0]))
		for c, field := range row[1:] {
			line += "  " + strings.Repeat(" ", widths[c+1]-len(field)) + field
		}
		if i > 0 && i-1 < len(marks) && marks[i-1] != "" {
			line += " " + marks[i-1]
		}
		lines = append(lines, strings.TrimRight(line, " "))
	}
	return lines
}
func orderedSum(values []float64) float64 {
	sum := 0.0
	for _, v := range values {
		sum += v
	}
	return sum
}
func informationCriteria(f *Fit) (float64, float64, float64) {
	logs := 0.0
	for _, w := range f.Weights {
		logs += math.Log(w)
	}
	n := float64(f.N)
	ll := 0.5 * (logs - n*(math.Log(2*math.Pi)+1-math.Log(n)+math.Log(f.RSS)))
	aic := -2*ll + 2*float64(f.Rank+1)
	bic := -2*ll + math.Log(n)*float64(f.Rank+1)
	return ll, aic, bic
}
func modelStatistics(f *Fit, confidence float64) Statistics {
	n, r := f.N, f.Rank
	df := n - r
	sumWeights := orderedSum(f.Weights)
	sumY := 0.0
	for i, y := range f.Response {
		sumY += f.Weights[i] * y
	}
	mean := sumY / sumWeights
	tss := 0.0
	for i, y := range f.Response {
		tss += f.Weights[i] * (y - mean) * (y - mean)
	}
	r2 := 1 - f.RSS/tss
	adjusted := 1 - (1-r2)*float64(n-1)/float64(df)
	stat := ((tss - f.RSS) / float64(r-1)) / (f.RSS / float64(df))
	ll, aic, bic := informationCriteria(f)
	press := 0.0
	for i, eps := range f.WeightedResidual {
		v := eps / (1 - f.Leverage[i])
		press += v * v
	}
	residuals := append([]float64{}, f.WeightedResidual...)
	sort.Float64s(residuals)
	quantiles := []float64{}
	for _, p := range []float64{0, 0.25, 0.5, 0.75, 1} {
		g := float64(n-1) * p
		k := int(math.Floor(g))
		q := residuals[k]
		if k+1 < n {
			q = q + (g-float64(k))*(residuals[k+1]-q)
		}
		quantiles = append(quantiles, q)
	}
	return Statistics{df, math.Sqrt(f.RSS / float64(df)), sumWeights, tss, r2, adjusted, stat, fP(stat,
		r-1, df), ll, aic, bic, press, 1 - press/tss, tQuantile(confidence, df), quantiles}
}
func coefficientInference(f *Fit, s Statistics) []Coefficient {
	omega := make([]float64, f.N)
	for i, eps := range f.WeightedResidual {
		omega[i] = eps * eps / ((1 - f.Leverage[i]) * (1 - f.Leverage[i]))
	}
	indices := map[int]int{}
	for k, j := range f.Accepted {
		indices[j] = k
	}
	out := []Coefficient{}
	for j, estimate := range f.Beta {
		if math.IsNaN(estimate) {
			v := math.NaN()
			out = append(out, Coefficient{v, v, v, v, v, v, v, v, v})
			continue
		}
		k := indices[j]
		se := s.Sigma * math.Sqrt(f.Variance[k])
		t := estimate / se
		half := s.Critical * se
		sum := 0.0
		for i := 0; i < f.N; i++ {
			sum += omega[i] * f.G[i][k] * f.G[i][k]
		}
		robust := math.Sqrt(sum)
		rt := estimate / robust
		out = append(out, Coefficient{estimate, se, t, tP(t, s.DF), estimate - half, estimate + half, robust, rt, tP(rt, s.DF)})
	}
	return out
}
func allTerms(model Model) []int {
	terms := make([]int, len(model.Terms))
	for i := range terms {
		terms[i] = i
	}
	return terms
}
func fitSubset(d *Design, terms []int, tolerance float64) *Fit {
	return fit(d.subsetMatrix(terms), d.Response, d.Weights, tolerance)
}
func removeTerm(terms []int, index int) []int {
	out := []int{}
	for _, i := range terms {
		if i != index {
			out = append(out, i)
		}
	}
	return out
}
func marginalTests(d *Design, f *Fit, terms []int, tolerance float64) []Anova {
	out := []Anova{}
	for _, i := range d.Model.removable(terms) {
		reduced := fitSubset(d, removeTerm(terms, i), tolerance)
		df := f.Rank - reduced.Rank
		ss := reduced.RSS - f.RSS
		stat, p := math.NaN(), math.NaN()
		if df > 0 {
			stat = (ss / float64(df)) / (f.RSS / float64(f.N-f.Rank))
			p = fP(stat, df, f.N-f.Rank)
		}
		out = append(out, Anova{Index: i, Name: d.Model.Terms[i].Name, DF: df, SS: ss, RSS: reduced.RSS, F: stat, P: p})
	}
	return out
}
func sequentialANOVA(d *Design, f *Fit) []Anova {
	out := []Anova{}
	for i, t := range d.Model.Terms {
		ss := 0.0
		df := 0
		for k, j := range f.Accepted {
			if d.Columns[j].Term == i {
				ss += f.Effects[k] * f.Effects[k]
				df++
			}
		}
		if df == 0 {
			continue
		}
		ms := ss / float64(df)
		stat := ms / (f.RSS / float64(f.N-f.Rank))
		out = append(out, Anova{Name: t.Name, DF: df, SS: ss, MS: ms, F: stat, P: fP(stat, df, f.N-f.Rank)})
	}
	return out
}
func varianceInflation(d *Design, f *Fit, s Statistics, p Params) []VIFResult {
	out := []VIFResult{}
	for _, column := range f.Accepted[1:] {
		response := make([]float64, f.N)
		x := make([][]float64, f.N)
		sum := 0.0
		for i, row := range f.Matrix {
			response[i] = row[column]
			sum += f.Weights[i] * response[i]
			for _, j := range f.Accepted {
				if j != column {
					x[i] = append(x[i], row[j])
				}
			}
		}
		aux := fit(x, response, f.Weights, p.Tolerance)
		mean := sum / s.WeightSum
		tss := 0.0
		for i, v := range response {
			tss += f.Weights[i] * (v - mean) * (v - mean)
		}
		r2 := 1 - aux.RSS/tss
		vif := 1 / (1 - r2)
		out = append(out, VIFResult{d.Columns[column].Name, vif, vif > p.VIF})
	}
	return out
}
func resetTest(f *Fit, tolerance float64) ResetResult {
	x := make([][]float64, f.N)
	for i, row := range f.Matrix {
		for _, j := range f.Accepted {
			x[i] = append(x[i], row[j])
		}
		v := f.Fitted[i]
		x[i] = append(x[i], v*v, v*v*v)
	}
	aug := fit(x, f.Response, f.Weights, tolerance)
	q, df := aug.Rank-f.Rank, f.N-aug.Rank
	stat := ((f.RSS - aug.RSS) / float64(q)) / (aug.RSS / float64(df))
	return ResetResult{stat, q, df, fP(stat, q, df)}
}
func predictionReport(number int, d *Design, f *Fit, s Statistics, data DataFrame) ([]string, PredictionCheck) {
	lines := []string{}
	check := PredictionCheck{RMSE: math.NaN()}
	squared := 0.0
	for i, row := range data.Rows {
		fields := []string{text(number), text(i + 1)}
		if !d.predictable(row) {
			for j := 0; j < 9; j++ {
				fields = append(fields, "NA")
			}
			lines = append(lines, strings.Join(fields, ","))
			continue
		}
		check.Predicted++
		values := d.values(row)
		predicted := 0.0
		for _, j := range f.Accepted {
			predicted += values[j] * f.Beta[j]
		}
		sum := 0.0
		for k := 0; k < f.Rank; k++ {
			u := 0.0
			for m, j := range f.Accepted {
				u += values[j] * f.Inverse[m][k]
			}
			sum += u * u
		}
		se := s.Sigma * math.Sqrt(sum)
		cw := s.Critical * se
		pw := s.Critical * math.Sqrt(s.Sigma*s.Sigma+se*se)
		lower, upper := predicted-pw, predicted+pw
		for _, v := range []float64{predicted, se, predicted - cw, predicted + cw, lower, upper} {
			fields = append(fields, four(v))
		}
		actual := row[d.Model.Response]
		if !actual.Present {
			fields = append(fields, "NA", "NA", "NA")
		} else {
			check.Actual++
			err := actual.Number - predicted
			squared += err * err
			covered := "no"
			if lower <= actual.Number && actual.Number <= upper {
				covered = "yes"
				check.Covered++
			}
			fields = append(fields, four(actual.Number), four(err), covered)
		}
		lines = append(lines, strings.Join(fields, ","))
	}
	if check.Actual > 0 {
		check.RMSE = math.Sqrt(squared / float64(check.Actual))
	}
	return lines, check
}
func analyzeModel(number int, d *Design, p Params, predict DataFrame) Report {
	f := fit(d.Matrix, d.Response, d.Weights, p.Tolerance)
	s := modelStatistics(f, p.Confidence)
	pred, check := predictionReport(number, d, f, s, predict)
	return Report{number, d, f, s, coefficientInference(f, s), sequentialANOVA(d, f), marginalTests(d,
		f, allTerms(d.Model), p.Tolerance), varianceInflation(d, f, s, p), calculateDiagnostics(f,
		p), resetTest(f, p.Tolerance), pred, check}
}
func dataSummary(data DataFrame) []string {
	numeric := []string{}
	rows := [][]string{}
	for _, c := range data.Columns {
		if data.Categorical[c] {
			continue
		}
		numeric = append(numeric, c)
		values := []float64{}
		for _, row := range data.Rows {
			if v := row[c]; v.Present {
				values = append(values, v.Number)
			}
		}
		n := len(values)
		mean := orderedSum(values) / float64(n)
		sum := 0.0
		lo, hi := values[0], values[0]
		for _, v := range values {
			sum += (v - mean) * (v - mean)
			lo = math.Min(lo, v)
			hi = math.Max(hi, v)
		}
		rows = append(rows, []string{c, text(n), text(len(data.Rows) - n), four(mean), four(math.Sqrt(sum / float64(n-1))), four(lo), four(hi)})
	}
	lines := []string{fmt.Sprintf("Data: %d rows, %d columns", len(data.Rows), len(data.Columns)), "", "Numeric columns:"}
	lines = append(lines, table([]string{"column", "n", "missing", "Mean", "SD", "Min", "Max"}, rows, nil)...)
	lines = append(lines, "", "Categorical columns:")
	for _, c := range data.Columns {
		if !data.Categorical[c] {
			continue
		}
		counts := map[string]int{}
		present := 0
		for _, row := range data.Rows {
			if v := row[c]; v.Present {
				present++
				counts[v.Label]++
			}
		}
		levels := []string{}
		for label := range counts {
			levels = append(levels, label)
		}
		sort.Strings(levels)
		fields := []string{}
		for _, label := range levels {
			fields = append(fields, label+" "+text(counts[label]))
		}
		lines = append(lines, fmt.Sprintf("%s: %d values, %d missing, %d levels: %s", c, present, len(data.Rows)-present, len(levels), strings.Join(fields, ", ")))
	}
	lines = append(lines, "", "Correlations (pairwise complete observations):")
	rows = [][]string{}
	for _, a := range numeric {
		fields := []string{a}
		for _, b := range numeric {
			pairs := [][2]float64{}
			sx, sy := 0.0, 0.0
			for _, row := range data.Rows {
				x, y := row[a], row[b]
				if x.Present && y.Present {
					pairs = append(pairs, [2]float64{x.Number, y.Number})
					sx += x.Number
					sy += y.Number
				}
			}
			mx, my := sx/float64(len(pairs)), sy/float64(len(pairs))
			cross, xx, yy := 0.0, 0.0, 0.0
			for _, pair := range pairs {
				x, y := pair[0]-mx, pair[1]-my
				cross += x * y
				xx += x * x
				yy += y * y
			}
			fields = append(fields, four(cross/math.Sqrt(xx*yy)))
		}
		rows = append(rows, fields)
	}
	header := append([]string{"column"}, numeric...)
	lines = append(lines, table(header, rows, nil)...)
	return append(lines, "")
}
func coefficientTables(r Report, confidence float64) ([]string, []string, []string) {
	ordinary, intervals, robust := [][]string{}, [][]string{}, [][]string{}
	marks, robustMarks := []string{}, []string{}
	for j, c := range r.Coefficients {
		name := r.Design.Columns[j].Name
		ordinary = append(ordinary, []string{name, four(c.Estimate), four(c.SE), four(c.T), probability(c.P)})
		intervals = append(intervals, []string{name, four(c.Lower), four(c.Upper)})
		robust = append(robust, []string{name, four(c.RobustSE), four(c.RobustT), probability(c.RobustP)})
		marks = append(marks, significance(c.P))
		robustMarks = append(robustMarks, significance(c.RobustP))
	}
	ci := []string{fmt.Sprintf("Confidence intervals (level %s, t %s):", four(confidence), four(r.Stats.Critical))}
	ci = append(ci, table([]string{"term", "Lower", "Upper"}, intervals, nil)...)
	return table([]string{"term", "Estimate", "Std. Error", "t value", "Pr(>|t|)"}, ordinary, marks),
		ci, table([]string{"term", "Std. Error", "t value", "Pr(>|t|)"}, robust, robustMarks)
}
func anovaTables(r Report) ([]string, []string) {
	rows, marks := [][]string{}, []string{}
	for _, t := range r.ANOVA {
		rows = append(rows, []string{t.Name, text(t.DF), four(t.SS), four(t.MS), four(t.F), probability(t.P)})
		marks = append(marks, significance(t.P))
	}
	rows = append(rows, []string{"Residuals", text(r.Stats.DF), four(r.Fit.RSS), four(r.Fit.RSS / float64(r.Stats.DF))})
	marks = append(marks, "")
	seq := table([]string{"term", "Df", "Sum Sq", "Mean Sq", "F value", "Pr(>F)"}, rows, marks)
	rows, marks = [][]string{}, []string{}
	for _, t := range r.Marginal {
		rows = append(rows, []string{t.Name, text(t.DF), four(t.SS), four(t.RSS), four(t.F), probability(t.P)})
		marks = append(marks, significance(t.P))
	}
	return seq, table([]string{"term", "Df", "Sum Sq", "RSS", "F value", "Pr(>F)"}, rows, marks)
}
func diagnosticSummary(r Report, p Params) []string {
	f, d, design := r.Fit, r.Diagnostic, r.Design
	dwLabel := "no autocorrelation"
	if d.DW < p.DW {
		dwLabel = "positive autocorrelation"
	} else if d.DW > 4-p.DW {
		dwLabel = "negative autocorrelation"
	}
	bpLabel := "homoscedastic"
	if d.BPP < p.BP {
		bpLabel = "heteroscedastic"
	}
	jbLabel := "normal"
	if d.JBP < p.Normal {
		jbLabel = "non-normal"
	}
	outlier := 0
	counts := map[byte]int{}
	any := 0
	order := make([]int, f.N)
	for i, row := range d.Rows {
		order[i] = i
		if math.Abs(row.Studentized) > math.Abs(d.Rows[outlier].Studentized) {
			outlier = i
		}
		if row.Flags != "-" {
			any++
			for j := 0; j < len(row.Flags); j++ {
				counts[row.Flags[j]]++
			}
		}
	}
	unadjusted := tP(d.Rows[outlier].Studentized, f.N-f.Rank-1)
	bonferroni := math.Min(1, float64(f.N)*unadjusted)
	sort.SliceStable(order, func(i, j int) bool { return d.Rows[order[i]].Cooks > d.Rows[order[j]].Cooks })
	reset := r.Reset
	lines := []string{"Diagnostics:", fmt.Sprintf("Durbin-Watson: %s (%s)", four(d.DW), dwLabel), fmt.Sprintf("Breusch-Pagan: %s on %d DF, p-value: %s (%s)",
		four(d.BP), d.BPDF, probability(d.BPP), bpLabel), fmt.Sprintf("Jarque-Bera: %s on 2 DF, p-value: %s, skewness %s, kurtosis %s (%s)",
		four(d.JB), probability(d.JBP), four(d.Skewness), four(d.Kurtosis), jbLabel), fmt.Sprintf("RESET (powers 2 and 3): F %s on %d and %d DF, p-value: %s",
		four(reset.F), reset.AddedDF, reset.ResidualDF, probability(reset.P)), fmt.Sprintf("Outlier test: row %d, studentized %s, unadjusted p-value: %s, Bonferroni p-value: %s",
		design.RowNumbers[outlier], four(d.Rows[outlier].Studentized), probability(unadjusted), probability(bonferroni)),
		fmt.Sprintf("Flagged rows: leverage %d, outlier %d, cooks %d, dffits %d, any %d", counts['H'],
			counts['O'], counts['C'], counts['F'], any), "Largest Cook's distances:"}
	for _, i := range order[:min(3, f.N)] {
		row := d.Rows[i]
		lines = append(lines, fmt.Sprintf("row %d: cooks_d %s, leverage %s, studentized %s, flags %s", design.RowNumbers[i],
			four(row.Cooks), four(f.Leverage[i]), four(row.Studentized), row.Flags))
	}
	lines = append(lines, "Largest absolute DFBETAS:")
	rows := [][]string{}
	for k, column := range f.Accepted {
		best := 0
		for i := 1; i < f.N; i++ {
			if math.Abs(d.Rows[i].DFBETAS[k]) > math.Abs(d.Rows[best].DFBETAS[k]) {
				best = i
			}
		}
		rows = append(rows, []string{design.Columns[column].Name, text(design.RowNumbers[best]), four(d.Rows[best].DFBETAS[k])})
	}
	return append(lines, table([]string{"column", "row", "DFBETAS"}, rows, nil)...)
}
func modelSummary(r Report, total int, p Params) []string {
	d, f, s := r.Design, r.Fit, r.Stats
	aliases := []string{}
	for _, j := range f.Aliases {
		aliases = append(aliases, d.Columns[j].Name)
	}
	aliasText := "none"
	if len(aliases) > 0 {
		aliasText = strings.Join(aliases, ", ")
	}
	terms := []string{}
	for _, t := range d.Model.Terms {
		terms = append(terms, t.Name)
	}
	weight := d.Model.Weight
	if weight == "" {
		weight = "none"
	}
	q := s.Quantiles
	coef, intervals, robust := coefficientTables(r, p.Confidence)
	seq, marginal := anovaTables(r)
	lines := []string{fmt.Sprintf("Model %d: %s", r.Number, d.Model.Original), "Terms: " + strings.Join(terms,
		", "), "Weights: " + weight, fmt.Sprintf("Observations: %d used, %d dropped", f.N, total-f.N),
		fmt.Sprintf("Columns: %d, rank %d, aliased: %s", f.P, f.Rank, aliasText), "", fmt.Sprintf("Residuals: Min %s, 1Q %s, Median %s, 3Q %s, Max %s",
			four(q[0]), four(q[1]), four(q[2]), four(q[3]), four(q[4])), "", "Coefficients:"}
	lines = append(lines, coef...)
	lines = append(lines, "---", "Signif. codes: 0 '***' 0.001 '**' 0.01 '*' 0.05 '.' 0.1 ' ' 1", "",
		fmt.Sprintf("Residual standard error: %s on %d degrees of freedom", four(s.Sigma), s.DF),
		fmt.Sprintf("Multiple R-squared: %s, Adjusted R-squared: %s", four(s.R2), four(s.Adjusted)),
		fmt.Sprintf("F-statistic: %s on %d and %d DF, p-value: %s", four(s.F), f.Rank-1, s.DF, probability(s.P)),
		fmt.Sprintf("Log-likelihood: %s, AIC: %s, BIC: %s", four(s.LL), four(s.AIC), four(s.BIC)),
		fmt.Sprintf("PRESS: %s, Predicted R-squared: %s", four(s.PRESS), four(s.Predicted)), "")
	lines = append(lines, intervals...)
	lines = append(lines, "", "Robust standard errors (HC3):")
	lines = append(lines, robust...)
	lines = append(lines, "", "Analysis of variance (sequential):")
	lines = append(lines, seq...)
	lines = append(lines, "", "Marginal F tests (drop one term):")
	lines = append(lines, marginal...)
	lines = append(lines, "", "Variance inflation factors:")
	rows, marks := [][]string{}, []string{}
	for _, v := range r.VIF {
		rows = append(rows, []string{v.Name, four(v.Value)})
		mark := ""
		if v.High {
			mark = "high"
		}
		marks = append(marks, mark)
	}
	lines = append(lines, table([]string{"column", "VIF"}, rows, marks)...)
	lines = append(lines, "")
	return append(lines, diagnosticSummary(r, p)...)
}
func summaryReport(data DataFrame, reports []Report, p Params) []string {
	lines := dataSummary(data)
	for i, r := range reports {
		if i > 0 {
			lines = append(lines, "")
		}
		lines = append(lines, modelSummary(r, len(data.Rows), p)...)
	}
	lines = append(lines, "", "Model comparison:")
	rows := [][]string{}
	for _, r := range reports {
		f, s := r.Fit, r.Stats
		rows = append(rows, []string{text(r.Number), text(f.N), text(f.Rank), four(s.Sigma), four(s.R2),
			four(s.Adjusted), four(s.Predicted), four(s.AIC), four(s.BIC)})
	}
	lines = append(lines, table([]string{"model", "n", "rank", "sigma", "R-squared", "Adj. R-squared", "Pred. R-squared", "AIC", "BIC"}, rows, nil)...)
	lines = append(lines, "", "Prediction check:")
	for _, r := range reports {
		c := r.Check
		lines = append(lines, fmt.Sprintf("model %d: %d predicted, %d with actual values, RMSE %s, inside prediction interval %d",
			r.Number, c.Predicted, c.Actual, four(c.RMSE), c.Covered))
	}
	return lines
}
func diagnosticsCSV(reports []Report) []string {
	lines := []string{"model,row,fitted,residual,leverage,studentized,cooks_d,dffits,flags"}
	for _, r := range reports {
		f := r.Fit
		for i, d := range r.Diagnostic.Rows {
			lines = append(lines, strings.Join([]string{text(r.Number), text(r.Design.RowNumbers[i]), four(f.Fitted[i]),
				four(f.Residual[i]), four(f.Leverage[i]), four(d.Studentized), four(d.Cooks), four(d.DFFITS),
				d.Flags}, ","))
		}
	}
	return lines
}
func backwardSelection(r Report, p Params) []string {
	d := r.Design
	terms := allTerms(d.Model)
	lines := []string{fmt.Sprintf("Backward elimination (model 1, alpha %s, rows %d)", four(p.Alpha), len(d.Rows))}
	step := 1
	f := r.Fit
	for {
		_, aic, _ := informationCriteria(f)
		df := f.N - f.Rank
		lines = append(lines, fmt.Sprintf("Step %d: %s (RSS %s, df %d, AIC %s)", step, d.Model.format(terms), four(f.RSS), df, four(aic)))
		if len(terms) == 0 {
			lines = append(lines, "  stop: no removable terms")
			break
		}
		tests := marginalTests(d, f, terms, p.Tolerance)
		best := 0
		for i, t := range tests {
			lines = append(lines, fmt.Sprintf("  - %s: F %s on %d and %d DF, p-value %s", t.Name, four(t.F), t.DF, df, probability(t.P)))
			if t.P > tests[best].P {
				best = i
			}
		}
		largest := tests[best]
		if largest.P <= p.Alpha {
			lines = append(lines, fmt.Sprintf("  stop: largest p-value %s is not above %s", probability(largest.P), four(p.Alpha)))
			break
		}
		lines = append(lines, "  remove "+largest.Name)
		terms = removeTerm(terms, largest.Index)
		f = fitSubset(d, terms, p.Tolerance)
		step++
	}
	return append(lines, "Final model: "+d.Model.format(terms))
}
func addTerm(terms []int, index int) []int {
	out := append(append([]int{}, terms...), index)
	sort.Ints(out)
	return out
}
func forwardSelection(r Report, p Params) []string {
	d := r.Design
	terms := []int{}
	lines := []string{fmt.Sprintf("Forward selection by AIC (model 1, rows %d)", len(d.Rows))}
	step := 1
	for {
		f := fitSubset(d, terms, p.Tolerance)
		_, aic, _ := informationCriteria(f)
		lines = append(lines, fmt.Sprintf("Step %d: %s (AIC %s)", step, d.Model.format(terms), four(aic)))
		candidates := d.Model.candidates(terms)
		if len(candidates) == 0 {
			lines = append(lines, "  stop: no candidate terms remain")
			break
		}
		best := -1
		bestAIC := math.Inf(1)
		for _, i := range candidates {
			candidate := fitSubset(d, addTerm(terms, i), p.Tolerance)
			_, value, _ := informationCriteria(candidate)
			lines = append(lines, fmt.Sprintf("  + %s: AIC %s", d.Model.Terms[i].Name, four(value)))
			if value < bestAIC {
				best, bestAIC = i, value
			}
		}
		if bestAIC >= aic {
			lines = append(lines, "  stop: no candidate lowers the AIC")
			break
		}
		lines = append(lines, "  add "+d.Model.Terms[best].Name)
		terms = addTerm(terms, best)
		step++
	}
	return append(lines, "Final model: "+d.Model.format(terms))
}

type SubsetResult struct {
	BIC, AIC   float64
	Mask, Rank int
	Terms      []int
}

func bestSubsets(r Report, p Params) []string {
	d := r.Design
	subsets := []SubsetResult{}
	for mask := 0; mask < 1<<len(d.Model.Terms); mask++ {
		terms := []int{}
		for j := range d.Model.Terms {
			if mask&(1<<j) != 0 {
				terms = append(terms, j)
			}
		}
		if !d.Model.hierarchical(terms) {
			continue
		}
		f := fitSubset(d, terms, p.Tolerance)
		_, aic, bic := informationCriteria(f)
		subsets = append(subsets, SubsetResult{bic, aic, mask, f.Rank, terms})
	}
	sort.SliceStable(subsets, func(i, j int) bool { return subsets[i].BIC < subsets[j].BIC })
	lines := []string{fmt.Sprintf("Best subsets by BIC (model 1, rows %d, subsets %d)", len(d.Rows), len(subsets))}
	for i, s := range subsets[:min(p.Best, len(subsets))] {
		lines = append(lines, fmt.Sprintf("%d. BIC %s, AIC %s, rank %d: %s", i+1, four(s.BIC), four(s.AIC), s.Rank, d.Model.format(s.Terms)))
	}
	return lines
}
func selectionReport(r Report, p Params) []string {
	lines := backwardSelection(r, p)
	lines = append(lines, "")
	lines = append(lines, forwardSelection(r, p)...)
	lines = append(lines, "")
	return append(lines, bestSubsets(r, p)...)
}
func plotGrid(horizontal, vertical []float64, lo, hi float64, p Params) [][]int {
	grid := make([][]int, p.Height)
	for r := range grid {
		grid[r] = make([]int, p.Width)
	}
	for i, x := range horizontal {
		c := min(int(math.Floor((x-lo)/(hi-lo)*float64(p.Width))), p.Width-1)
		r := int(math.Floor((p.Limit - vertical[i]) / (2 * p.Limit) * float64(p.Height)))
		r = max(0, min(r, p.Height-1))
		grid[r][c]++
	}
	return grid
}
func plotFrame(grid [][]int) []string {
	border := "+" + strings.Repeat("-", len(grid[0])) + "+"
	lines := []string{border}
	for r, row := range grid {
		cells := make([]byte, len(row))
		for c, n := range row {
			if n >= 10 {
				cells[c] = '*'
			} else if n > 0 {
				cells[c] = byte('0' + n)
			} else if r == len(grid)/2 {
				cells[c] = '-'
			} else {
				cells[c] = '.'
			}
		}
		lines = append(lines, "|"+string(cells)+"|")
	}
	return append(lines, border)
}
func minMax(values []float64) (float64, float64) {
	lo, hi := values[0], values[0]
	for _, v := range values[1:] {
		lo = math.Min(lo, v)
		hi = math.Max(hi, v)
	}
	return lo, hi
}
func residualPlot(r Report, p Params) []string {
	f := r.Fit
	vertical := make([]float64, f.N)
	above, below, outside := 0, 0, 0
	for i, d := range r.Diagnostic.Rows {
		v := d.Studentized
		vertical[i] = v
		if v > 2 {
			above++
		}
		if v < -2 {
			below++
		}
		if math.Abs(v) > p.Limit {
			outside++
		}
	}
	lo, hi := minMax(f.Fitted)
	grid := plotGrid(f.Fitted, vertical, lo, hi, p)
	lines := []string{fmt.Sprintf("Model %d: studentized residuals vs fitted values", r.Number), fmt.Sprintf("fitted %s to %s, studentized %s to %s",
		four(lo), four(hi), four(-p.Limit), four(p.Limit))}
	lines = append(lines, plotFrame(grid)...)
	lines = append(lines, fmt.Sprintf("points: %d, above +2: %d, below -2: %d, outside range: %d", f.N,
		above, below, outside), "Histogram of studentized residuals:")
	counts := make([]int, p.Height)
	maximum := 0
	for i, row := range grid {
		for _, v := range row {
			counts[i] += v
		}
		maximum = max(maximum, counts[i])
	}
	for i, n := range counts {
		lower := p.Limit - 2*p.Limit*float64(i+1)/float64(p.Height)
		upper := p.Limit - 2*p.Limit*float64(i)/float64(p.Height)
		length := (n*40 + maximum - 1) / maximum
		line := fmt.Sprintf("%s to %s: %d", four(lower), four(upper), n)
		if length > 0 {
			line += " " + strings.Repeat("#", length)
		}
		lines = append(lines, line)
	}
	_, hi = minMax(f.Leverage)
	lines = append(lines, fmt.Sprintf("Model %d: studentized residuals vs leverage", r.Number), fmt.Sprintf("leverage 0.0000 to %s, studentized %s to %s",
		four(hi), four(-p.Limit), four(p.Limit)))
	return append(lines, plotFrame(plotGrid(f.Leverage, vertical, 0, hi, p))...)
}
func writeLines(name string, lines []string) {
	if e := os.WriteFile("output/"+name, []byte(strings.Join(lines, "\n")+"\n"), 0644); e != nil {
		panic(e)
	}
}
func main() {
	data := readCSV("input/data.csv", nil)
	predict := readCSV("input/predict.csv", data.Categorical)
	p := readParams()
	reports := []Report{}
	for i, line := range readLines("input/model.txt") {
		reports = append(reports, analyzeModel(i+1, buildDesign(parseModel(line), data), p, predict))
	}
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	writeLines("summary.txt", summaryReport(data, reports, p))
	writeLines("diagnostics.csv", diagnosticsCSV(reports))
	writeLines("selection.txt", selectionReport(reports[0], p))
	predictions := []string{"model,row,fit,se_fit,conf_lower,conf_upper,pred_lower,pred_upper,actual,error,covered"}
	plots := []string{}
	for i, r := range reports {
		predictions = append(predictions, r.Predictions...)
		if i > 0 {
			plots = append(plots, "")
		}
		plots = append(plots, residualPlot(r, p)...)
	}
	writeLines("predictions.csv", predictions)
	writeLines("residual_plot.txt", plots)
}
