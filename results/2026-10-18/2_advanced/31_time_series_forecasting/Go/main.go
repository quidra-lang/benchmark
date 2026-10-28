package main

import (
	"fmt"
	"math"
	"strings"
)

var methods = []string{"naive", "snaive", "drift", "ses", "holt", "damped", "hw_add", "hw_mult", "decomp_add", "decomp_mult", "ar"}
var accuracyFields = []string{"me", "mae", "rmse", "mape", "smape", "mase", "fva", "cv_rmse", "cover80", "cover95", "winkler80", "winkler95", "rank"}

func line(parts ...any) string {
	fields := []string{}
	for _, p := range parts {
		fields = append(fields, fmt.Sprint(p))
	}
	return strings.Join(fields, " ")
}
func realList(values []float64) string {
	fields := []string{}
	for _, v := range values {
		fields = append(fields, real(v))
	}
	return strings.Join(fields, " ")
}
func squaredTotal(values []float64) float64 {
	total := 0.0
	for _, v := range values {
		total += v * v
	}
	return total
}
func rmse(errors []float64) float64 { return math.Sqrt(squaredTotal(errors) / float64(len(errors))) }
func smoothParameterNames(name string) []string {
	switch name {
	case "ses":
		return []string{"alpha"}
	case "holt":
		return []string{"alpha", "beta"}
	case "damped":
		return []string{"alpha", "beta", "phi"}
	case "hw_add", "hw_mult":
		return []string{"alpha", "beta", "gamma"}
	default:
		return nil
	}
}

type Model struct {
	Name                                                             string
	Values                                                           []float64
	Season                                                           int
	Parameters                                                       SmoothParameters
	States                                                           []SmoothState
	Residuals, Seasonal                                              []float64
	Intercept, Slope                                                 float64
	Members                                                          []*Model
	Kind                                                             string
	Differenced, Variances, AIC, Coefficients, Correlations, Partial []float64
	Offset, Order                                                    int
	Mean, Sigma2                                                     float64
}

func (m *Model) DecompositionPrediction(t int) float64 {
	base := m.Intercept + m.Slope*float64(t+1)
	component := m.Seasonal[t%m.Season]
	if m.Name == "decomp_add" {
		return base + component
	}
	return base * component
}
func fit(name string, values []float64, s Settings) *Model {
	n, season := len(values), s.Int("season")
	m := &Model{Name: name, Values: values, Season: season}
	switch name {
	case "naive":
		for t := 1; t < n; t++ {
			m.Residuals = append(m.Residuals, values[t]-values[t-1])
		}
	case "snaive":
		for t := season; t < n; t++ {
			m.Residuals = append(m.Residuals, values[t]-values[t-season])
		}
	case "drift":
		m.Slope = (values[n-1] - values[0]) / float64(n-1)
		for t := 1; t < n; t++ {
			m.Residuals = append(m.Residuals, values[t]-values[t-1]-m.Slope)
		}
	case "ses", "holt", "damped", "hw_add", "hw_mult":
		names := smoothParameterNames(name)
		best := math.Inf(1)
		var visit func(int, SmoothParameters)
		visit = func(index int, p SmoothParameters) {
			if index == len(names) {
				errors, states := smoothRecurse(name, values, season, p)
				score := squaredTotal(errors)
				if score < best {
					best = score
					m.Parameters, m.Residuals, m.States = p, errors, states
				}
				return
			}
			for _, v := range s.Reals(names[index]) {
				next := p
				switch names[index] {
				case "alpha":
					next.Alpha = v
				case "beta":
					next.Beta = v
				case "gamma":
					next.Gamma = v
				case "phi":
					next.Phi = v
				}
				visit(index+1, next)
			}
		}
		visit(0, SmoothParameters{Phi: 1})
	case "decomp_add", "decomp_mult":
		d := decompose(values, season)
		indices := d.Additive
		if name == "decomp_mult" {
			indices = d.Multiplicative
		}
		adjusted := []float64{}
		for t, v := range values {
			if name == "decomp_add" {
				adjusted = append(adjusted, v-indices[t%season])
			} else {
				adjusted = append(adjusted, v/indices[t%season])
			}
		}
		m.Intercept, m.Slope = leastSquares(adjusted)
		m.Seasonal = indices
		for t, v := range values {
			m.Residuals = append(m.Residuals, v-m.DecompositionPrediction(t))
		}
	case "ar":
		best := math.Inf(1)
		for _, kind := range differenceKinds {
			transformed, offset := difference(values, season, kind)
			average, variance, _ := autocorrelation(transformed, 0)
			m.Variances = append(m.Variances, variance)
			if variance < best {
				best = variance
				m.Kind, m.Differenced, m.Offset, m.Mean = kind, transformed, offset, average
			}
		}
		average, variance, correlations := autocorrelation(m.Differenced, s.Int("max_lag"))
		coefficients, partial, variances := durbinLevinson(correlations)
		m.Mean, m.Correlations, m.Partial = average, correlations, partial
		best = math.Inf(1)
		for p := 0; p <= s.Int("max_ar"); p++ {
			aic := float64(len(m.Differenced))*math.Log(variance*variances[p]) + float64(2*p)
			m.AIC = append(m.AIC, aic)
			if aic < best {
				best = aic
				m.Order = p
			}
		}
		m.Coefficients = coefficients[m.Order]
		m.Sigma2 = variance * variances[m.Order]
		m.Residuals = arResiduals(m.Differenced, m.Mean, m.Coefficients)
	}
	return m
}
func combo(members []*Model, values []float64, season int) *Model {
	return &Model{Name: "combo", Members: members, Values: values, Season: season}
}
func forecast(m *Model, origin, steps int) []float64 {
	result := make([]float64, steps)
	values, season := m.Values, m.Season
	switch m.Name {
	case "combo":
		predictions := [][]float64{}
		for _, member := range m.Members {
			predictions = append(predictions, forecast(member, origin, steps))
		}
		for i := range result {
			sum := 0.0
			for _, p := range predictions {
				sum += p[i]
			}
			result[i] = sum / float64(len(predictions))
		}
	case "naive":
		for i := range result {
			result[i] = values[origin-1]
		}
	case "snaive":
		for i := range result {
			result[i] = values[origin-season+i%season]
		}
	case "drift":
		slope := (values[origin-1] - values[0]) / float64(origin-1)
		for i := range result {
			result[i] = values[origin-1] + float64(i+1)*slope
		}
	case "ses", "holt", "damped", "hw_add", "hw_mult":
		return smoothForecast(m.Name, m.States[origin], m.Parameters, origin, steps, season)
	case "decomp_add", "decomp_mult":
		for i := range result {
			result[i] = m.DecompositionPrediction(origin + i)
		}
	default:
		return arForecast(values, m.Differenced, m.Offset, m.Kind, m.Mean, m.Coefficients, origin, steps, season)
	}
	return result
}
func modelLines(m *Model) []string {
	common := line("rmse", real(rmse(m.Residuals)), "residuals", len(m.Residuals))
	name := m.Name
	switch name {
	case "naive", "snaive":
		return []string{name + " " + common}
	case "drift":
		return []string{line(name, "slope", real(m.Slope), common)}
	case "ses", "holt", "damped", "hw_add", "hw_mult":
		fields := []any{name}
		for _, key := range smoothParameterNames(name) {
			value := m.Parameters.Alpha
			switch key {
			case "beta":
				value = m.Parameters.Beta
			case "gamma":
				value = m.Parameters.Gamma
			case "phi":
				value = m.Parameters.Phi
			}
			fields = append(fields, key, real(value))
		}
		state := m.States[len(m.States)-1]
		fields = append(fields, common, "level", real(state.Level))
		if name != "ses" {
			fields = append(fields, "slope", real(state.Slope))
		}
		lines := []string{line(fields...)}
		if state.Seasonal != nil {
			seasonal := []float64{}
			for j := 0; j < m.Season; j++ {
				seasonal = append(seasonal, state.Seasonal[(len(m.Values)+j)%m.Season])
			}
			lines = append(lines, line(name, "seasonal", realList(seasonal)))
		}
		return lines
	case "decomp_add", "decomp_mult":
		return []string{line(name, "intercept", real(m.Intercept), "slope", real(m.Slope), common), line(name, "seasonal", realList(m.Seasonal))}
	default:
		fields := []any{"ar", "variance"}
		for i, kind := range differenceKinds {
			fields = append(fields, kind, real(m.Variances[i]))
		}
		coefficients := realList(m.Coefficients)
		if len(m.Coefficients) == 0 {
			coefficients = "none"
		}
		return []string{line(fields...), line("ar", "difference", m.Kind, "n", len(m.Differenced), "mean",
			real(m.Mean), "order", m.Order, "sigma2", real(m.Sigma2), common), line("ar", "aic",
			realList(m.AIC)), line("ar", "coefficients", coefficients)}
	}
}

type CV struct {
	Counts     []int
	Sigma, MAE []float64
	RMSE       float64
}

func crossValidate(m *Model, s Settings) CV {
	horizon := s.Int("horizon")
	cv := CV{Counts: make([]int, horizon), Sigma: make([]float64, horizon), MAE: make([]float64, horizon)}
	squared, absolute := make([]float64, horizon), make([]float64, horizon)
	for origin := s.Int("cv_start"); origin < len(m.Values); origin++ {
		predictions := forecast(m, origin, min(horizon, len(m.Values)-origin))
		for i, p := range predictions {
			e := m.Values[origin+i] - p
			cv.Counts[i]++
			squared[i] += e * e
			absolute[i] += math.Abs(e)
		}
	}
	for i := range cv.Counts {
		cv.Sigma[i] = math.Sqrt(squared[i] / float64(cv.Counts[i]))
		cv.MAE[i] = absolute[i] / float64(cv.Counts[i])
	}
	sum, count := 0.0, 0
	for i := 0; i < s.Int("holdout"); i++ {
		sum += squared[i]
		count += cv.Counts[i]
	}
	cv.RMSE = math.Sqrt(sum / float64(count))
	return cv
}

type Interval struct{ Forecast, Lo80, Hi80, Lo95, Hi95 float64 }

func (r Interval) Fields() string {
	fields := []string{real(r.Forecast), real(r.Lo80), real(r.Hi80), real(r.Lo95), real(r.Hi95)}
	return strings.Join(fields, ",")
}
func intervalRows(predicted, sigma, coefficients, multipliers []float64) []Interval {
	rows := []Interval{}
	for i, v := range predicted {
		multiplier := 1.0
		if multipliers != nil {
			multiplier = multipliers[i]
		}
		e := sigma[i]
		rows = append(rows, Interval{v * multiplier, (v - coefficients[0]*e) * multiplier, (v + coefficients[0]*e) * multiplier,
			(v - coefficients[1]*e) * multiplier, (v + coefficients[1]*e) * multiplier})
	}
	return rows
}

type Lift struct {
	Kind        string
	Occurrences int
	Value       float64
}
type Analysis struct {
	Series                          *Series
	Values, Corrected               []float64
	Future                          []string
	Missing                         map[int]bool
	Past                            map[int]string
	Outliers                        map[int]float64
	Lifts                           []Lift
	Decomposition                   Decomposition
	StrengthTrend, StrengthSeasonal float64
	TrainingCount                   int
	Models                          []*Model
	CVs                             []CV
	Members                         []int
	Metrics                         []map[string]float64
	Intervals                       [][]Interval
	Best                            int
	FinalFits                       []*Model
	Final                           *Model
	FutureRows                      []Interval
}

func prepare(record *Series, s Settings) *Analysis {
	n, season := len(record.Raw), s.Int("season")
	a := &Analysis{Series: record, Values: make([]float64, n), Missing: map[int]bool{}, Past: map[int]string{},
		Outliers: map[int]float64{}, TrainingCount: n - s.Int("holdout")}
	for t, v := range record.Raw {
		if v == nil {
			a.Missing[t] = true
		} else {
			a.Values[t] = *v
		}
	}
	for left := 0; left < n-1; {
		right := left + 1
		for record.Raw[right] == nil {
			right++
		}
		for t := left + 1; t < right; t++ {
			a.Values[t] = *record.Raw[left] + (*record.Raw[right]-*record.Raw[left])*float64(t-left)/float64(right-left)
		}
		left = right
	}
	period := record.Periods[n-1]
	for i := 0; i < s.Int("horizon"); i++ {
		period = nextMonth(period)
		a.Future = append(a.Future, period)
	}
	d := decompose(a.Values, season)
	a.Decomposition = d
	residuals, trendResiduals, seasonResiduals := []float64{}, []float64{}, []float64{}
	for _, t := range d.Defined {
		r := *d.ResidualAdd[t]
		residuals = append(residuals, r)
		trendResiduals = append(trendResiduals, *d.Trend[t]+r)
		seasonResiduals = append(seasonResiduals, d.Additive[t%season]+r)
	}
	average, deviation := mean(residuals), math.Sqrt(sampleVariance(residuals))
	groups := map[string][]int{}
	kinds := []string{}
	for t, p := range record.Periods {
		if kind, ok := record.Events[p]; ok {
			a.Past[t] = kind
			if _, exists := groups[kind]; !exists {
				kinds = append(kinds, kind)
			}
			groups[kind] = append(groups[kind], t)
		}
	}
	for _, t := range d.Defined {
		_, event := a.Past[t]
		if !a.Missing[t] && !event && math.Abs(*d.ResidualAdd[t]-average) > s.Real("outlier")*deviation {
			a.Outliers[t] = (*d.ResidualAdd[t] - average) / deviation
		}
	}
	for _, kind := range kinds {
		values := []float64{}
		for _, t := range groups[kind] {
			values = append(values, a.Values[t]/(*d.Trend[t]+d.Additive[t%season]))
		}
		a.Lifts = append(a.Lifts, Lift{kind, len(values), mean(values)})
	}
	a.Corrected = append([]float64(nil), a.Values...)
	for t := range a.Values {
		_, event := a.Past[t]
		_, outlier := a.Outliers[t]
		if event || outlier {
			a.Corrected[t] = *d.Trend[t] + d.Additive[t%season]
		}
	}
	vr := sampleVariance(residuals)
	a.StrengthTrend = math.Max(0, 1-vr/sampleVariance(trendResiduals))
	a.StrengthSeasonal = math.Max(0, 1-vr/sampleVariance(seasonResiduals))
	return a
}
func analyze(record *Series, s Settings) *Analysis {
	a := prepare(record, s)
	training := a.Corrected[:a.TrainingCount]
	cvScores := []float64{}
	for _, name := range methods {
		m := fit(name, training, s)
		a.Models = append(a.Models, m)
		cv := crossValidate(m, s)
		a.CVs = append(a.CVs, cv)
		cvScores = append(cvScores, cv.RMSE)
	}
	selected := map[int]bool{}
	for _, i := range rankValues(cvScores)[:s.Int("combo")] {
		selected[i] = true
	}
	comboModels := []*Model{}
	for i, m := range a.Models {
		if selected[i] {
			a.Members = append(a.Members, i)
			comboModels = append(comboModels, m)
		}
	}
	combined := combo(comboModels, training, s.Int("season"))
	a.Models = append(a.Models, combined)
	a.CVs = append(a.CVs, crossValidate(combined, s))
	actual := a.Values[a.TrainingCount:]
	scale := seasonalScale(training, s.Int("season"))
	scores := []float64{}
	for i, m := range a.Models {
		predicted := forecast(m, len(training), len(actual))
		rows := intervalRows(predicted, a.CVs[i].Sigma, s.Reals("interval"), nil)
		a.Intervals = append(a.Intervals, rows)
		metrics := accuracy(actual, predicted, scale)
		metrics["cv_rmse"] = a.CVs[i].RMSE
		cover80, cover95, w80, w95 := 0, 0, 0.0, 0.0
		for j, v := range actual {
			r := rows[j]
			if r.Lo80 <= v && v <= r.Hi80 {
				cover80++
			}
			if r.Lo95 <= v && v <= r.Hi95 {
				cover95++
			}
			w80 += winkler(v, r.Lo80, r.Hi80, 10)
			w95 += winkler(v, r.Lo95, r.Hi95, 40)
		}
		metrics["cover80"], metrics["cover95"], metrics["winkler80"], metrics["winkler95"] = float64(cover80),
			float64(cover95), w80/float64(len(actual)), w95/float64(len(actual))
		a.Metrics = append(a.Metrics, metrics)
		scores = append(scores, metrics["rmse"])
	}
	naiveMAE := a.Metrics[0]["mae"]
	for _, metrics := range a.Metrics {
		metrics["fva"] = 100 * (naiveMAE - metrics["mae"]) / naiveMAE
	}
	ranking := rankValues(scores)
	for i, index := range ranking {
		a.Metrics[index]["rank"] = float64(i + 1)
	}
	a.Best = ranking[0]
	finalIndices := []int{a.Best}
	if a.Best == 11 {
		finalIndices = a.Members
	}
	for _, i := range finalIndices {
		a.FinalFits = append(a.FinalFits, fit(methods[i], a.Corrected, s))
	}
	a.Final = a.FinalFits[0]
	if a.Best == 11 {
		a.Final = combo(a.FinalFits, a.Corrected, s.Int("season"))
	}
	cv := crossValidate(a.Final, s)
	multipliers := []float64{}
	for _, p := range a.Future {
		multiplier := 1.0
		if kind, exists := record.Events[p]; exists {
			for _, lift := range a.Lifts {
				if lift.Kind == kind {
					multiplier = lift.Value
					break
				}
			}
		}
		multipliers = append(multipliers, multiplier)
	}
	a.FutureRows = intervalRows(forecast(a.Final, len(a.Values), s.Int("horizon")), cv.Sigma, s.Reals("interval"), multipliers)
	return a
}
func (a *Analysis) BestName() string { return a.Models[a.Best].Name }
func (a *Analysis) decompositionLines() []string {
	lines := []string{}
	d := a.Decomposition
	season := len(d.Additive)
	for t, p := range a.Series.Periods {
		flag := "ok"
		if kind, exists := a.Past[t]; exists {
			flag = kind
		} else if a.Missing[t] {
			flag = "missing"
		} else if _, exists := a.Outliers[t]; exists {
			flag = "outlier"
		}
		lines = append(lines, strings.Join([]string{a.Series.Name, p, real(a.Values[t]), real(a.Corrected[t]),
			optional(d.Trend[t]), real(d.Additive[t%season]), optional(d.ResidualAdd[t]), real(d.Multiplicative[t%season]),
			optional(d.ResidualMult[t]), flag}, ","))
	}
	return lines
}
func (a *Analysis) fittedLines(s Settings) []string {
	lines := []string{line("series", a.Series.Name), line("data", "observations", len(a.Values), "train",
		a.TrainingCount, "holdout", s.Int("holdout"), "missing", len(a.Missing), "outliers", len(a.Outliers),
		"events", len(a.Past))}
	for _, l := range a.Lifts {
		lines = append(lines, line("event", l.Kind, "occurrences", l.Occurrences, "lift", real(l.Value)))
	}
	for t := range a.Values {
		if score, ok := a.Outliers[t]; ok {
			lines = append(lines, line("outlier", a.Series.Periods[t], "value", real(a.Values[t]), "expected", real(a.Corrected[t]), "score", real(score)))
		}
	}
	lines = append(lines, line("strength", "trend", real(a.StrengthTrend), "seasonal", real(a.StrengthSeasonal)))
	for _, m := range a.Models[:11] {
		lines = append(lines, modelLines(m)...)
	}
	names := []string{}
	for _, i := range a.Members {
		names = append(names, methods[i])
	}
	lines = append(lines, line("combo", "members", strings.Join(names, " ")), line("best", a.BestName(), "rmse", real(a.Metrics[a.Best]["rmse"])))
	for _, m := range a.FinalFits {
		for _, l := range modelLines(m) {
			lines = append(lines, "final "+l)
		}
	}
	return lines
}
func (a *Analysis) forecastLines() []string {
	lines := []string{}
	for i, m := range a.Models {
		for j, row := range a.Intervals[i] {
			t := a.TrainingCount + j
			lines = append(lines, fmt.Sprintf("%s,holdout,%s,%s,%.0f,%s", a.Series.Name, m.Name, a.Series.Periods[t], *a.Series.Raw[t], row.Fields()))
		}
	}
	for i, row := range a.FutureRows {
		lines = append(lines, fmt.Sprintf("%s,future,%s,%s,NA,%s", a.Series.Name, a.BestName(), a.Future[i], row.Fields()))
	}
	return lines
}
func (a *Analysis) accuracyLines() []string {
	lines := []string{}
	for i, m := range a.Models {
		fields := []string{a.Series.Name, m.Name}
		for _, key := range accuracyFields {
			v := a.Metrics[i][key]
			text := real(v)
			if key == "cover80" || key == "cover95" || key == "rank" {
				text = fmt.Sprint(int(v))
			}
			fields = append(fields, text)
		}
		lines = append(lines, strings.Join(fields, ","))
	}
	return lines
}
func (a *Analysis) cvLines() []string {
	lines := []string{}
	for i, m := range a.Models {
		cv := a.CVs[i]
		for j, n := range cv.Counts {
			lines = append(lines, fmt.Sprintf("%s,%s,%d,%d,%s,%s", a.Series.Name, m.Name, j+1, n, real(cv.MAE[j]), real(cv.Sigma[j])))
		}
	}
	return lines
}
func correlationBar(v, band float64) string {
	width, threshold := int(math.Floor(math.Abs(v)*20+0.5)), int(math.Floor(band*20+0.5))
	cells := []byte(strings.Repeat(" ", 41))
	cells[20-threshold], cells[20+threshold], cells[20] = ':', ':', '|'
	if v > 0 {
		for i := 21; i < 21+width; i++ {
			cells[i] = '#'
		}
	} else if v < 0 {
		for i := 20 - width; i < 20; i++ {
			cells[i] = '#'
		}
	}
	return string(cells)
}
func (a *Analysis) correlogramLines(s Settings) []string {
	ar := a.Models[10]
	band := 2 / math.Sqrt(float64(len(ar.Differenced)))
	lines := []string{line("series", a.Series.Name, "difference", ar.Kind, "n", len(ar.Differenced), "band", real(band))}
	for i, sequence := range [][]float64{ar.Correlations, ar.Partial} {
		label := "acf"
		if i == 1 {
			label = "pacf"
		}
		for lag, v := range sequence[1:] {
			text := fmt.Sprintf("%s %2d %7s [%s]", label, lag+1, real(v), correlationBar(v, band))
			if math.Abs(v) > band {
				text += " *"
			}
			lines = append(lines, text)
		}
	}
	lags := []int{}
	for _, v := range s["ljung_box"] {
		lags = append(lags, integer(v))
	}
	for _, m := range a.Models[:11] {
		errors := m.Residuals
		n := float64(len(errors))
		average := mean(errors)
		squared, m3, m4, differences := 0.0, 0.0, 0.0, 0.0
		for i, e := range errors {
			d := e - average
			squared += d * d
			m3 += d * d * d
			m4 += d * d * d * d
			if i > 0 {
				delta := e - errors[i-1]
				differences += delta * delta
			}
		}
		m2 := squared / n
		m3 /= n
		m4 /= n
		sd := math.Sqrt(squared / (n - 1))
		dw := differences / squaredTotal(errors)
		skewness := m3 / (m2 * math.Sqrt(m2))
		kurtosis := m4/(m2*m2) - 3
		jb := n / 6 * (skewness*skewness + kurtosis*kurtosis/4)
		lines = append(lines, line("residuals", m.Name, "n", len(errors), "mean", real(average), "sd", real(sd),
			"dw", real(dw), "skewness", real(skewness), "kurtosis", real(kurtosis), "jb", real(jb)))
		fields := []any{"ljung_box", m.Name}
		for _, v := range ljungBox(errors, lags) {
			fields = append(fields, "lag", v.Lag, "q", real(v.Q), "p", real(v.P))
		}
		lines = append(lines, line(fields...))
	}
	return lines
}
func chartRow(row Interval, actual *float64, low, high float64) string {
	column := func(v float64) int { return int(math.Floor((v-low)/(high-low)*60 + 0.5)) }
	cells := []byte(strings.Repeat(" ", 61))
	for i := column(row.Lo95); i <= column(row.Hi95); i++ {
		cells[i] = '-'
	}
	for i := column(row.Lo80); i <= column(row.Hi80); i++ {
		cells[i] = '='
	}
	cells[column(row.Forecast)] = 'o'
	if actual != nil {
		cells[column(*actual)] = '*'
	}
	return string(cells)
}
func (a *Analysis) chartLines() []string {
	rows := append(append([]Interval(nil), a.Intervals[a.Best]...), a.FutureRows...)
	periods := append(append([]string(nil), a.Series.Periods[a.TrainingCount:]...), a.Future...)
	low, high := math.Inf(1), math.Inf(-1)
	for _, row := range rows {
		low = math.Min(low, row.Lo95)
		high = math.Max(high, row.Hi95)
	}
	for _, v := range a.Values[a.TrainingCount:] {
		low = math.Min(low, v)
		high = math.Max(high, v)
	}
	lines := []string{line("chart", a.Series.Name, "method", a.BestName()), line("scale", "low", real(low), "high", real(high))}
	holdout := len(a.Intervals[a.Best])
	for i, row := range rows {
		var actual *float64
		if i < holdout {
			actual = pointer(a.Values[a.TrainingCount+i])
		}
		lines = append(lines, periods[i]+" |"+chartRow(row, actual, low, high)+"|")
	}
	peak := 0.0
	for _, v := range a.Decomposition.Multiplicative {
		peak = math.Max(peak, math.Abs(v-1))
	}
	lines = append(lines, line("profile", "peak", real(peak)))
	for j, v := range a.Decomposition.Multiplicative {
		width := int(math.Floor(math.Abs(v-1)/peak*30 + 0.5))
		cells := []byte(strings.Repeat(" ", 61))
		cells[30] = '|'
		if v > 1 {
			for i := 31; i < 31+width; i++ {
				cells[i] = '#'
			}
		} else if v < 1 {
			for i := 30 - width; i < 30; i++ {
				cells[i] = '#'
			}
		}
		lines = append(lines, fmt.Sprintf("season %2d %s [%s]", j+1, real(v), string(cells)))
	}
	return lines
}
func (a *Analysis) planLines(s Settings) []string {
	p := a.Series.Policy
	protection := p.Lead + p.Review
	demands := []float64{}
	for _, r := range a.FutureRows {
		demands = append(demands, r.Forecast)
	}
	errors := []float64{}
	for origin := s.Int("cv_start"); origin <= len(a.Corrected)-protection; origin++ {
		predicted := forecast(a.Final, origin, protection)
		sum := 0.0
		for i, f := range predicted {
			sum += a.Corrected[origin+i] - f
		}
		errors = append(errors, sum)
	}
	safety := p.Service * rmse(errors)
	lines := []string{line("series", a.Series.Name, "method", a.BestName()), line("policy", "on_hand",
		p.OnHand, "lead_time", p.Lead, "review", p.Review, "service", real(p.Service), "safety_stock",
		real(safety))}
	reviews := map[int]bool{}
	end := 0
	for k := 1; k-1+protection <= len(demands); k += p.Review {
		reviews[k] = true
		end = k - 1 + protection
	}
	onHand := float64(p.OnHand)
	outstanding, orders, ordered, short := 0, 0, 0, 0
	receipts := map[int]int{}
	lowest, totalStock := math.Inf(1), 0.0
	for k := 1; k <= end; k++ {
		receipt := receipts[k]
		onHand += float64(receipt)
		outstanding -= receipt
		period := a.Future[k-1]
		if reviews[k] {
			position := onHand + float64(outstanding)
			target := total(demands[k-1:k-1+protection]) + safety
			quantity := max(0, int(math.Ceil(target-position)))
			if quantity > 0 {
				orders++
				ordered += quantity
				outstanding += quantity
				receipts[k+p.Lead] = quantity
			}
			lines = append(lines, line("review", period, "position", real(position), "target", real(target), "order", quantity))
		}
		onHand -= demands[k-1]
		status := "ok"
		if onHand < 0 {
			status = "short"
			short++
		} else if onHand < safety {
			status = "low"
		}
		lowest = math.Min(lowest, onHand)
		totalStock += onHand
		lines = append(lines, line("period", period, "demand", real(demands[k-1]), "receipt", receipt, "on_hand", real(onHand), "status", status))
	}
	lines = append(lines, line("summary", "orders", orders, "ordered", ordered, "short_periods", short,
		"lowest", real(lowest), "average", real(totalStock/float64(end))))
	type Year struct {
		Name                         string
		ActualMonths, ForecastMonths int
		Actual, Forecast             float64
	}
	years := []*Year{}
	named := map[string]*Year{}
	add := func(period string, v float64, future bool) {
		key := period[:4]
		y := named[key]
		if y == nil {
			y = &Year{Name: key}
			named[key] = y
			years = append(years, y)
		}
		if future {
			y.ForecastMonths++
			y.Forecast += v
		} else {
			y.ActualMonths++
			y.Actual += v
		}
	}
	for i, p := range a.Series.Periods {
		add(p, a.Values[i], false)
	}
	for i, p := range a.Future {
		add(p, demands[i], true)
	}
	for i, y := range years {
		sum := y.Actual + y.Forecast
		growth := "NA"
		if i > 0 && y.ActualMonths+y.ForecastMonths == 12 {
			previous := years[i-1]
			if previous.ActualMonths+previous.ForecastMonths == 12 {
				before := previous.Actual + previous.Forecast
				growth = real(100 * (sum - before) / before)
			}
		}
		lines = append(lines, line("year", y.Name, "actual_months", y.ActualMonths, "actual", real(y.Actual),
			"forecast_months", y.ForecastMonths, "forecast", real(y.Forecast), "total", real(sum),
			"growth", growth))
	}
	return lines
}
func main() {
	series, settings := readInputs()
	decomposition := []string{"series,period,value,cleaned,trend,seasonal_add,residual_add,seasonal_mult,residual_mult,flag"}
	models := []string{}
	forecasts := []string{"series,stage,method,period,actual,forecast,lo80,hi80,lo95,hi95"}
	accuracies := []string{"series,method," + strings.Join(accuracyFields, ",")}
	cv := []string{"series,method,step,origins,mae,rmse"}
	correlogram, chart, plan := []string{}, []string{}, []string{}
	for _, record := range series {
		a := analyze(record, settings)
		decomposition = append(decomposition, a.decompositionLines()...)
		models = append(models, a.fittedLines(settings)...)
		forecasts = append(forecasts, a.forecastLines()...)
		accuracies = append(accuracies, a.accuracyLines()...)
		cv = append(cv, a.cvLines()...)
		correlogram = append(correlogram, a.correlogramLines(settings)...)
		chart = append(chart, a.chartLines()...)
		plan = append(plan, a.planLines(settings)...)
	}
	writeLines("decomposition.csv", decomposition)
	writeLines("models.txt", models)
	writeLines("forecasts.csv", forecasts)
	writeLines("accuracy.csv", accuracies)
	writeLines("cv.csv", cv)
	writeLines("correlogram.txt", correlogram)
	writeLines("chart.txt", chart)
	writeLines("plan.txt", plan)
}
