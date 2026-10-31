package main

import (
	"fmt"
	"math"
	"os"
	"sort"
	"strconv"
	"strings"
)

type Summary struct {
	Rows                                   []KMRow
	Life                                   []LifeRow
	Events, Maximum, PersonDays, Followup  int
	Rate, RateLower, RateUpper, LifeMedian float64
	Percentiles                            [3][4]int
	RMST                                   [4]float64
}
type Analysis struct {
	Subjects    []Subject
	Params      Params
	Names       []string
	Collections [][]Subject
	Summaries   []Summary
}

func number(v float64) string {
	if math.IsNaN(v) {
		return "NA"
	}
	s := fmt.Sprintf("%.4f", v)
	if s == "-0.0000" {
		return "0.0000"
	}
	return s
}
func day(t int) string {
	if t == 0 {
		return "NA"
	}
	return strconv.Itoa(t)
}
func reals(values []float64) string {
	s := make([]string, len(values))
	for i, v := range values {
		s[i] = number(v)
	}
	return strings.Join(s, " ")
}
func ints(values []int) string {
	s := make([]string, len(values))
	for i, v := range values {
		s[i] = strconv.Itoa(v)
	}
	return strings.Join(s, " ")
}
func selectSubjects(subjects []Subject, accept func(Subject) bool) []Subject {
	out := []Subject{}
	for _, s := range subjects {
		if accept(s) {
			out = append(out, s)
		}
	}
	return out
}
func eventCount(subjects []Subject) int {
	count := 0
	for _, s := range subjects {
		count += s.Event
	}
	return count
}
func riskCount(subjects []Subject, time int) int {
	count := 0
	for _, s := range subjects {
		if s.Time >= time {
			count++
		}
	}
	return count
}
func percentileTime(rows []KMRow, threshold float64, column int) int {
	for _, r := range rows {
		v := r.Survival
		if column == 1 {
			v = r.Lower
		} else if column == 2 {
			v = r.Upper
		}
		if r.Survival == 0 {
			v = 0
		}
		if !math.IsNaN(v) && v <= threshold {
			return r.Time
		}
	}
	return 0
}
func restrictedMean(rows []KMRow, tau int) [4]float64 {
	selected := []KMRow{}
	for _, r := range rows {
		if r.Time <= tau {
			selected = append(selected, r)
		}
	}
	times := []int{0}
	survival := []float64{1}
	for _, r := range selected {
		times = append(times, r.Time)
		survival = append(survival, r.Survival)
	}
	times = append(times, tau)
	tails := make([]float64, len(survival))
	for i, s := range survival {
		tails[i] = s * float64(times[i+1]-times[i])
	}
	for i := len(tails) - 2; i >= 0; i-- {
		tails[i] = tails[i] + tails[i+1]
	}
	variance := 0.0
	for j, r := range selected {
		i := j + 1
		variance += tails[i] * tails[i] * (float64(r.Events) / float64(r.Risk*(r.Risk-r.Events)))
	}
	mean, se := tails[0], math.Sqrt(variance)
	return [4]float64{mean, se, mean - z95*se, mean + z95*se}
}
func collectionSummary(subjects []Subject, p Params) Summary {
	rows := kaplanMeier(subjects)
	life := lifeTable(subjects, p.Width, p.Intervals)
	s := Summary{Rows: rows, Life: life, Events: eventCount(subjects), LifeMedian: math.NaN()}
	reverse := make([]Subject, len(subjects))
	for j, row := range subjects {
		s.PersonDays += row.Time
		s.Maximum = max(s.Maximum, row.Time)
		reverse[j] = row
		reverse[j].Event = 1 - row.Event
	}
	s.Rate = float64(1000*s.Events) / float64(s.PersonDays)
	eta := z95 / math.Sqrt(float64(s.Events))
	s.RateLower = math.Exp(math.Log(s.Rate) - eta)
	s.RateUpper = math.Exp(math.Log(s.Rate) + eta)
	s.Followup = percentileTime(kaplanMeier(reverse), 0.5, 0)
	previous := 1.0
	for _, r := range life {
		if r.Survival <= 0.5 {
			s.LifeMedian = float64(r.Start) + float64(p.Width)*(previous-0.5)/(previous-r.Survival)
			break
		}
		previous = r.Survival
	}
	for j, q := range []float64{0.75, 0.5, 0.25} {
		s.Percentiles[j] = [4]int{25 * (j + 1), percentileTime(rows, q, 0), percentileTime(rows, q, 1), percentileTime(rows, q, 2)}
	}
	s.RMST = restrictedMean(rows, p.Tau)
	return s
}
func newAnalysis(subjects []Subject, p Params) Analysis {
	a := Analysis{Subjects: subjects, Params: p, Names: append(append([]string{}, p.Groups...), "all")}
	for _, name := range a.Names {
		rows := subjects
		if name != "all" {
			rows = selectSubjects(subjects, func(s Subject) bool { return s.Group == name })
		}
		a.Collections = append(a.Collections, rows)
		a.Summaries = append(a.Summaries, collectionSummary(rows, p))
	}
	return a
}
func (a Analysis) kmTables() []string {
	sections := [][]string{}
	for k, name := range a.Names {
		s := a.Summaries[k]
		subjects := a.Collections[k]
		lines := []string{fmt.Sprintf("group %s subjects %d events %d censored %d max_time %d", name, len(subjects),
			s.Events, len(subjects)-s.Events, s.Maximum), fmt.Sprintf("person_days %d rate %s lower %s upper %s",
			s.PersonDays, number(s.Rate), number(s.RateLower), number(s.RateUpper)), "followup_median " + day(s.Followup),
			"life_table_median " + number(s.LifeMedian)}
		for _, v := range s.Percentiles {
			lines = append(lines, fmt.Sprintf("percentile %d time %s lower %s upper %s", v[0], day(v[1]), day(v[2]), day(v[3])))
		}
		v := s.RMST
		lines = append(lines, fmt.Sprintf("rmst tau %d estimate %s se %s lower %s upper %s", a.Params.Tau, number(v[0]), number(v[1]), number(v[2]), number(v[3])))
		for _, time := range a.Params.Times {
			r := rowAt(s.Rows, time)
			events := 0
			for _, row := range subjects {
				if row.Time <= time {
					events += row.Event
				}
			}
			lines = append(lines, fmt.Sprintf("at %d at_risk %d events %d survival %s std_err %s lower %s upper %s cum_hazard %s hazard_se %s",
				time, riskCount(subjects, time), events, number(r.Survival), number(r.SE), number(r.Lower),
				number(r.Upper), number(r.Hazard), number(r.HazardSE)))
		}
		header := []string{"time", "at_risk", "events", "censored", "survival", "std_err", "lower", "upper", "cum_haz", "haz_se"}
		text := ""
		for _, v := range header {
			text += fmt.Sprintf("%9s", v)
		}
		lines = append(lines, text)
		for _, r := range s.Rows {
			fields := []string{strconv.Itoa(r.Time), strconv.Itoa(r.Risk), strconv.Itoa(r.Events), strconv.Itoa(r.Censored),
				number(r.Survival), number(r.SE), number(r.Lower), number(r.Upper), number(r.Hazard),
				number(r.HazardSE)}
			text := ""
			for _, v := range fields {
				text += fmt.Sprintf("%9s", v)
			}
			lines = append(lines, text)
		}
		sections = append(sections, lines)
	}
	return joinSections(sections)
}
func (a Analysis) lifeLines() []string {
	lines := []string{"group,interval,at_risk,events,withdrawn,exposed,q,survival,std_err,hazard"}
	for k, name := range a.Names {
		for _, r := range a.Summaries[k].Life {
			lines = append(lines, fmt.Sprintf("%s,%d-%d,%d,%d,%d,%.1f,%s,%s,%s,%s", name, r.Start, r.End, r.Risk,
				r.Events, r.Withdrawn, r.Exposed, number(r.Q), number(r.Survival), number(r.SE),
				number(r.Hazard)))
		}
	}
	return lines
}
func variableValue(s Subject, name string) string {
	if name == "sex" {
		return s.Sex
	}
	return strconv.Itoa(s.Stage)
}
func variableLevels(subjects []Subject, name string) []string {
	set := map[string]bool{}
	for _, s := range subjects {
		set[variableValue(s, name)] = true
	}
	values := []string{}
	for v := range set {
		values = append(values, v)
	}
	sort.Strings(values)
	return values
}
func (a Analysis) baselineLines() []string {
	lines := []string{"baseline"}
	for k, name := range a.Names {
		rows := a.Collections[k]
		ages := make([]int, len(rows))
		sum, male := 0, 0
		stages := [4]int{}
		for i, s := range rows {
			ages[i] = s.Age
			sum += s.Age
			if s.Sex == "M" {
				male++
			}
			stages[s.Stage-1]++
		}
		mean := float64(sum) / float64(len(rows))
		variance := 0.0
		for _, s := range rows {
			d := float64(s.Age) - mean
			variance += d * d
		}
		sort.Ints(ages)
		median := float64(ages[(len(rows)-1)/2]+ages[len(rows)/2]) / 2
		lines = append(lines, fmt.Sprintf("  group %s subjects %d age_mean %s age_sd %s age_median %.1f male %d stage %s",
			name, len(rows), number(mean), number(math.Sqrt(variance/float64(len(rows)-1))), median,
			male, ints(stages[:])))
	}
	ranked := append([]Subject{}, a.Subjects...)
	sort.SliceStable(ranked, func(i, j int) bool { return ranked[i].Age < ranked[j].Age })
	ranks := map[int]float64{}
	ties := 0
	for start := 0; start < len(ranked); {
		end := start + 1
		for end < len(ranked) && ranked[end].Age == ranked[start].Age {
			end++
		}
		rank := float64(start+1+end) / 2
		for _, s := range ranked[start:end] {
			ranks[s.ID] = rank
		}
		n := end - start
		ties += n*n*n - n
		start = end
	}
	weighted := 0.0
	for _, rows := range a.Collections[:len(a.Params.Groups)] {
		sum := 0.0
		for _, s := range rows {
			sum += ranks[s.ID]
		}
		weighted += sum * sum / float64(len(rows))
	}
	n := len(a.Subjects)
	raw := 12*weighted/float64(n*(n+1)) - float64(3*(n+1))
	stat := raw / (1 - float64(ties)/float64(n*n*n-n))
	df := len(a.Params.Groups) - 1
	lines = append(lines, fmt.Sprintf("  age kruskal_wallis chisq %s df %d p %s", number(stat), df, number(chiP(stat, df))))
	for _, variable := range []string{"sex", "stage"} {
		levels := variableLevels(a.Subjects, variable)
		counts := make([]int, len(levels))
		for j, level := range levels {
			for _, s := range a.Subjects {
				if variableValue(s, variable) == level {
					counts[j]++
				}
			}
		}
		stat := 0.0
		for _, rows := range a.Collections[:len(a.Params.Groups)] {
			for j, level := range levels {
				observed := 0
				for _, s := range rows {
					if variableValue(s, variable) == level {
						observed++
					}
				}
				expected := float64(len(rows)*counts[j]) / float64(n)
				d := float64(observed) - expected
				stat += d * d / expected
			}
		}
		df := (len(a.Params.Groups) - 1) * (len(levels) - 1)
		lines = append(lines, fmt.Sprintf("  %s chisq %s df %d p %s", variable, number(stat), df, number(chiP(stat, df))))
	}
	return lines
}
func groupLines(t WeightedTest) []string {
	lines := []string{}
	for h, name := range t.Groups {
		o, x := t.Observed[h], t.Expected[h]
		lines = append(lines, fmt.Sprintf("  group %s events %d observed %s expected %s o_minus_e %s variance %s",
			name, t.Events[h], number(o), number(x), number(o-x), number(t.Covariance[h][h])))
	}
	return lines
}
func testFields(t WeightedTest) string {
	return fmt.Sprintf("chisq %s df %d p %s", number(t.Statistic), t.Degrees, number(t.P))
}
func (a Analysis) overallLines() []string {
	lines := []string{}
	var lr WeightedTest
	for _, weight := range weights {
		t := weightedTest(a.Subjects, a.Params.Groups, weight, len(a.Subjects))
		if weight == "logrank" {
			lr = t
		}
		lines = append(lines, "test "+weight+" "+testFields(t))
		lines = append(lines, groupLines(t)...)
	}
	trend, variance := 0.0, 0.0
	for g := range a.Params.Groups {
		trend += float64(g+1) * (lr.Observed[g] - lr.Expected[g])
		inner := 0.0
		for h := range a.Params.Groups {
			inner += float64((g+1)*(h+1)) * lr.Covariance[g][h]
		}
		variance += inner
	}
	stat := trend * trend / variance
	return append(lines, fmt.Sprintf("test logrank_trend chisq %s df 1 p %s", number(stat), number(chiP(stat, 1))))
}
func (a Analysis) stratifiedLines() []string {
	variable := a.Params.Strata
	levels := variableLevels(a.Subjects, variable)
	strata := [][]Subject{}
	for _, level := range levels {
		strata = append(strata, selectSubjects(a.Subjects, func(s Subject) bool { return variableValue(s, variable) == level }))
	}
	lines := []string{}
	for _, weight := range weights {
		tests := []WeightedTest{}
		for _, rows := range strata {
			tests = append(tests, weightedTest(rows, a.Params.Groups, weight, len(a.Subjects)))
		}
		combined := combineStrata(tests, a.Params.Groups)
		lines = append(lines, "stratified "+weight+" by "+variable+" "+testFields(combined))
		for i, t := range tests {
			lines = append(lines, fmt.Sprintf("  stratum %s subjects %d events %d chisq %s p %s", levels[i],
				len(strata[i]), eventCount(strata[i]), number(t.Statistic), number(t.P)))
		}
		lines = append(lines, groupLines(combined)...)
	}
	return lines
}

type TwoGroup struct {
	Test                              WeightedTest
	HR, LogHR, Variance, Lower, Upper float64
}

func twoGroup(subjects []Subject, groups []string, population int) TwoGroup {
	t := weightedTest(subjects, groups, "logrank", population)
	hr := (t.Observed[1] / t.Expected[1]) / (t.Observed[0] / t.Expected[0])
	v := 1/t.Expected[0] + 1/t.Expected[1]
	l := math.Log(hr)
	return TwoGroup{t, hr, l, v, math.Exp(l - z95*math.Sqrt(v)), math.Exp(l + z95*math.Sqrt(v))}
}
func (a Analysis) pairwiseLines() []string {
	pairs := [][2]string{}
	tests := []TwoGroup{}
	for i, g := range a.Params.Groups {
		for _, h := range a.Params.Groups[i+1:] {
			pairs = append(pairs, [2]string{g, h})
			rows := selectSubjects(a.Subjects, func(s Subject) bool { return s.Group == g || s.Group == h })
			tests = append(tests, twoGroup(rows, []string{g, h}, len(a.Subjects)))
		}
	}
	order := make([]int, len(tests))
	for i := range order {
		order[i] = i
	}
	sort.SliceStable(order, func(i, j int) bool { return tests[order[i]].Test.P < tests[order[j]].Test.P })
	adjusted := make([]float64, len(tests))
	previous := 0.0
	for rank, i := range order {
		candidate := float64(len(tests)-rank) * tests[i].Test.P
		previous = math.Max(previous, math.Min(1, candidate))
		adjusted[i] = previous
	}
	lines := []string{"pairwise logrank adjust holm"}
	for i, t := range tests {
		lines = append(lines, fmt.Sprintf("  %s %s chisq %s p %s p_holm %s hr %s lower %s upper %s", pairs[i][0],
			pairs[i][1], number(t.Test.Statistic), number(t.Test.P), number(adjusted[i]), number(t.HR),
			number(t.Lower), number(t.Upper)))
	}
	return lines
}
func (a Analysis) subgroupLines() []string {
	groups := a.Params.Groups
	lines := []string{"subgroups reference " + groups[0]}
	for _, variable := range a.Params.Subgroups {
		levels := variableLevels(a.Subjects, variable)
		for _, group := range groups[1:] {
			tests := []TwoGroup{}
			for _, level := range levels {
				rows := selectSubjects(a.Subjects, func(s Subject) bool {
					return variableValue(s, variable) == level && (s.Group == groups[0] || s.Group == group)
				})
				t := twoGroup(rows, []string{groups[0], group}, len(a.Subjects))
				tests = append(tests, t)
				lines = append(lines, fmt.Sprintf("  %s %s %s subjects %d events %d hr %s lower %s upper %s p %s",
					variable, level, group, len(rows), eventCount(rows), number(t.HR), number(t.Lower),
					number(t.Upper), number(t.Test.P)))
			}
			sum, total := 0.0, 0.0
			for _, t := range tests {
				w := 1 / t.Variance
				sum += w * t.LogHR
				total += w
			}
			mean := sum / total
			stat := 0.0
			for _, t := range tests {
				w := 1 / t.Variance
				stat += w * (t.LogHR - mean) * (t.LogHR - mean)
			}
			df := len(levels) - 1
			lines = append(lines, fmt.Sprintf("  %s %s heterogeneity chisq %s df %d p %s", variable, group, number(stat), df, number(chiP(stat, df))))
		}
	}
	return lines
}
func differenceFields(delta, se float64) string {
	stat := delta / se
	return fmt.Sprintf("difference %s se %s lower %s upper %s z %s p %s", number(delta), number(se),
		number(delta-z95*se), number(delta+z95*se), number(stat), number(chiP(stat*stat, 1)))
}
func (a Analysis) comparisonSections() [][]string {
	groups := a.Params.Groups
	selected := selectSubjects(a.Subjects, func(s Subject) bool { return s.Time > a.Params.Landmark })
	t := weightedTest(selected, groups, "logrank", len(a.Subjects))
	landmark := []string{fmt.Sprintf("landmark %d subjects %d %s", a.Params.Landmark, len(selected), testFields(t))}
	landmark = append(landmark, groupLines(t)...)
	rmst := []string{fmt.Sprintf("rmst_difference tau %d reference %s", a.Params.Tau, groups[0])}
	rates := []string{"rate_ratio reference " + groups[0]}
	survival := []string{"survival_difference reference " + groups[0]}
	control := a.Summaries[0]
	for g, group := range groups[1:] {
		s := a.Summaries[g+1]
		se := math.Sqrt(s.RMST[1]*s.RMST[1] + control.RMST[1]*control.RMST[1])
		rmst = append(rmst, "  "+group+" "+differenceFields(s.RMST[0]-control.RMST[0], se))
		ratio := s.Rate / control.Rate
		error := math.Sqrt(1/float64(s.Events) + 1/float64(control.Events))
		l := math.Log(ratio)
		stat := l / error
		rates = append(rates, fmt.Sprintf("  %s ratio %s lower %s upper %s z %s p %s", group, number(ratio),
			number(math.Exp(l-z95*error)), number(math.Exp(l+z95*error)), number(stat), number(chiP(stat*stat,
				1))))
	}
	for _, time := range a.Params.Times {
		c := rowAt(control.Rows, time)
		for g, group := range groups[1:] {
			r := rowAt(a.Summaries[g+1].Rows, time)
			se := math.Sqrt(r.SE*r.SE + c.SE*c.SE)
			survival = append(survival, fmt.Sprintf("  at %d %s %s", time, group, differenceFields(r.Survival-c.Survival, se)))
		}
	}
	return [][]string{a.baselineLines(), a.overallLines(), a.stratifiedLines(), landmark, a.pairwiseLines(), a.subgroupLines(), rmst, rates, survival}
}
func baselineName(name string) bool { return name == "age" || name == "male" || name == "stage" }
func covariateVectors(subjects []Subject, names []string) [][]int {
	vectors := make([][]int, len(subjects))
	for j, s := range subjects {
		vectors[j] = make([]int, len(names))
		for c, name := range names {
			v := 0
			switch name {
			case "age":
				v = s.Age
			case "stage":
				v = s.Stage
			case "male":
				if s.Sex == "M" {
					v = 1
				}
			default:
				if s.Group == name {
					v = 1
				}
			}
			vectors[j][c] = v
		}
	}
	return vectors
}
func coefficientFields(coef, se float64) string {
	stat := coef / se
	return fmt.Sprintf("coef %s se %s z %s p %s hr %s lower %s upper %s", number(coef), number(se), number(stat),
		number(chiP(stat*stat, 1)), number(math.Exp(coef)), number(math.Exp(coef-z95*se)), number(math.Exp(coef+z95*se)))
}
func coefficientLines(names []string, beta []float64, cov [][]float64) []string {
	lines := []string{}
	indices := []int{}
	for i, name := range names {
		lines = append(lines, "term "+name+" "+coefficientFields(beta[i], math.Sqrt(cov[i][i])))
		if !baselineName(name) {
			indices = append(indices, i)
		}
	}
	for i, c := range indices {
		for _, d := range indices[i+1:] {
			coef := beta[d] - beta[c]
			se := math.Sqrt(cov[d][d] + cov[c][c] - 2*cov[c][d])
			lines = append(lines, "contrast "+names[d]+" vs "+names[c]+" "+coefficientFields(coef, se))
		}
	}
	return lines
}
func coxTestLines(subjects []Subject, vectors [][]int, names []string, m CoxModel) []string {
	p := len(names)
	lr := 2 * (m.Final.Loglik - m.Null.Loglik)
	wald := 0.0
	for c, b := range m.Beta {
		inner := 0.0
		for d, x := range m.Beta {
			inner += m.Final.Information[c][d] * x
		}
		wald += b * inner
	}
	solution := solve(m.Null.Information, m.Null.Score)
	score := 0.0
	for c, u := range m.Null.Score {
		score += u * solution[c]
	}
	lines := []string{}
	for i, label := range []string{"likelihood_ratio", "wald", "score"} {
		stat := []float64{lr, wald, score}[i]
		lines = append(lines, fmt.Sprintf("%s chisq %s df %d p %s", label, number(stat), p, number(chiP(stat, p))))
	}
	for c, name := range names {
		ll := m.Null.Loglik
		if p >= 2 {
			reduced := make([][]int, len(vectors))
			for i, x := range vectors {
				reduced[i] = append(append([]int{}, x[:c]...), x[c+1:]...)
			}
			ll = fitCox(subjects, reduced).Final.Loglik
		}
		stat := 2 * (m.Final.Loglik - ll)
		lines = append(lines, fmt.Sprintf("drop %s loglik %s chisq %s df 1 p %s", name, number(ll), number(stat), number(chiP(stat, 1))))
	}
	return lines
}
func concordanceLine(subjects []Subject, vectors [][]int, predictors []float64) string {
	comparable, concordant, tied := 0, 0, 0
	for i, first := range subjects {
		if first.Event == 0 {
			continue
		}
		for j, second := range subjects {
			if i == j || !(first.Time < second.Time || first.Time == second.Time && second.Event == 0) {
				continue
			}
			comparable++
			equal := true
			for c, v := range vectors[i] {
				if v != vectors[j][c] {
					equal = false
					break
				}
			}
			if equal {
				tied++
			} else if predictors[i] > predictors[j] {
				concordant++
			}
		}
	}
	return fmt.Sprintf("concordance %s comparable %d concordant %d tied %d", number(float64(2*concordant+tied)/float64(2*comparable)),
		comparable, concordant, tied)
}
func proportionalLines(subjects []Subject, vectors [][]int, names []string, e CoxEvaluation) []string {
	order := []int{}
	timeSum := 0
	for i, s := range subjects {
		if s.Event == 1 {
			order = append(order, i)
			timeSum += s.Time
		}
	}
	sort.SliceStable(order, func(i, j int) bool { return subjects[order[i]].Time < subjects[order[j]].Time })
	count := len(order)
	meanTime := float64(timeSum) / float64(count)
	lines := []string{}
	for c, name := range names {
		residuals := make([]float64, count)
		sum := 0.0
		for j, i := range order {
			sums := e.Sums[subjects[i].Time]
			residuals[j] = float64(vectors[i][c]) - sums.S1[c]/sums.S0
			sum += residuals[j]
		}
		mean := sum / float64(count)
		sxy, sxx, syy := 0.0, 0.0, 0.0
		for j, i := range order {
			x, y := residuals[j]-mean, float64(subjects[i].Time)-meanTime
			sxy += x * y
			sxx += x * x
			syy += y * y
		}
		rho := sxy / math.Sqrt(sxx*syy)
		stat := 0.5 * math.Log((1+rho)/(1-rho)) * math.Sqrt(float64(count-3))
		lines = append(lines, fmt.Sprintf("ph_check %s rho %s z %s p %s", name, number(rho), number(stat), number(chiP(stat*stat, 1))))
	}
	return lines
}

type HazardRow struct {
	Time       int
	Cumulative float64
}

func baselineHazard(e CoxEvaluation) []HazardRow {
	times := []int{}
	for t := range e.Sums {
		times = append(times, t)
	}
	sort.Ints(times)
	rows := []HazardRow{}
	cumulative := 0.0
	for _, t := range times {
		s := e.Sums[t]
		cumulative += float64(s.Events) / s.S0
		rows = append(rows, HazardRow{t, cumulative})
	}
	return rows
}
func hazardAt(rows []HazardRow, time int) float64 {
	for j := len(rows) - 1; j >= 0; j-- {
		if rows[j].Time <= time {
			return rows[j].Cumulative
		}
	}
	return 0
}

type Residual struct {
	Subject              Subject
	Martingale, Deviance float64
}

func residualLines(subjects []Subject, e CoxEvaluation, hazard []HazardRow, count int) []string {
	rows := []Residual{}
	for i, s := range subjects {
		m := float64(s.Event) - hazardAt(hazard, s.Time)*math.Exp(e.Predictors[i])
		d := 0.0
		if s.Event == 1 {
			d = math.Sqrt(-2 * (m + math.Log(1-m)))
		} else {
			d = math.Sqrt(-2 * m)
		}
		if !(m > 0) {
			d = -d
		}
		rows = append(rows, Residual{s, m, d})
	}
	sort.SliceStable(rows, func(i, j int) bool { return math.Abs(rows[i].Deviance) > math.Abs(rows[j].Deviance) })
	lines := []string{fmt.Sprintf("residuals top %d", count)}
	for _, r := range rows[:count] {
		s := r.Subject
		lines = append(lines, fmt.Sprintf("  id %d group %s time %d event %d martingale %s deviance %s",
			s.ID, s.Group, s.Time, s.Event, number(r.Martingale), number(r.Deviance)))
	}
	return lines
}
func adjustedLines(vectors [][]int, names []string, beta []float64, groups []string, times []int, hazard []HazardRow) []string {
	means := map[string]float64{}
	fields := []string{}
	for c, name := range names {
		if baselineName(name) {
			sum := 0
			for _, x := range vectors {
				sum += x[c]
			}
			means[name] = float64(sum) / float64(len(vectors))
			fields = append(fields, name+" "+number(means[name]))
		}
	}
	text := "none"
	if len(fields) > 0 {
		text = strings.Join(fields, " ")
	}
	lines := []string{"adjusted_survival mean " + text}
	risks := make([]float64, len(groups))
	for g, group := range groups {
		theta := 0.0
		for c, name := range names {
			v, ok := means[name]
			if !ok {
				v = 0
				if name == group {
					v = 1
				}
			}
			theta += beta[c] * v
		}
		risks[g] = math.Exp(theta)
	}
	for _, time := range times {
		cumulative := hazardAt(hazard, time)
		line := fmt.Sprintf("  at %d", time)
		for g, group := range groups {
			line += " " + group + " " + number(math.Exp(-cumulative*risks[g]))
		}
		lines = append(lines, line)
	}
	line := "  median"
	for g, group := range groups {
		median := 0
		for _, r := range hazard {
			if math.Exp(-r.Cumulative*risks[g]) <= 0.5 {
				median = r.Time
				break
			}
		}
		line += " " + group + " " + day(median)
	}
	return append(lines, line)
}
func (a Analysis) coxLines() []string {
	names := a.Params.Covariates
	vectors := covariateVectors(a.Subjects, names)
	model := fitCox(a.Subjects, vectors)
	final := model.Final
	covariance := inverse(final.Information)
	lines := []string{fmt.Sprintf("cox covariates %s subjects %d events %d event_times %d", strings.Join(names,
		" "), len(a.Subjects), eventCount(a.Subjects), len(final.Sums))}
	for _, r := range model.Iterations {
		lines = append(lines, fmt.Sprintf("iter %d loglik %s beta %s", r.Number, number(r.Loglik), reals(r.Beta)))
	}
	lines = append(lines, "final loglik "+number(final.Loglik)+" null_loglik "+number(model.Null.Loglik))
	lines = append(lines, coefficientLines(names, model.Beta, covariance)...)
	lines = append(lines, coxTestLines(a.Subjects, vectors, names, model)...)
	lines = append(lines, concordanceLine(a.Subjects, vectors, final.Predictors))
	lines = append(lines, proportionalLines(a.Subjects, vectors, names, final)...)
	hazard := baselineHazard(final)
	lines = append(lines, residualLines(a.Subjects, final, hazard, a.Params.Residuals)...)
	return append(lines, adjustedLines(vectors, names, model.Beta, a.Params.Groups, a.Params.Times, hazard)...)
}
func (a Analysis) plotLines() []string {
	p := a.Params.Plot
	w, h, limit, divisions := p[0], p[1], p[2], p[3]
	legend := "legend"
	estimates := [][]KMRow{}
	for g, name := range a.Params.Groups {
		legend += fmt.Sprintf(" %c %s", 'A'+g, name)
		estimates = append(estimates, a.Summaries[g].Rows)
	}
	lines := []string{fmt.Sprintf("km_plot width %d height %d time %d", w, h, limit), legend}
	lines = append(lines, curveLines(a.Collections[:len(a.Params.Groups)], estimates, w, h, limit)...)
	lines = append(lines, fmt.Sprintf("time 0 to %d days, %d days per column", limit, limit/w))
	times := make([]int, divisions+1)
	for i := range times {
		times[i] = i * (limit / divisions)
	}
	lines = append(lines, "at_risk "+ints(times))
	for g, name := range a.Params.Groups {
		counts := []int{}
		for _, time := range times {
			counts = append(counts, riskCount(a.Collections[g], time))
		}
		lines = append(lines, name+" "+ints(counts))
	}
	return lines
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
	subjects, p := readDataset()
	a := newAnalysis(subjects, p)
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	writeLines("km_tables.txt", a.kmTables())
	writeLines("life_table.csv", a.lifeLines())
	writeLines("tests.txt", joinSections(a.comparisonSections()))
	writeLines("cox.txt", a.coxLines())
	writeLines("km_plot.txt", a.plotLines())
}
