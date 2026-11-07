package main

import (
	"fmt"
	"math"
	"strings"
)

type Application struct {
	Data                                                       Data
	Multipliers                                                []float64
	FitLines                                                   []string
	Beta, Gamma, Rho, R0, SSE, SEBeta, SpacingBeta, SpacingRho float64
	States, AgeStates                                          [][]float64
	Incidence, Reported, Residual, ModelDeaths, Average, Rt    []float64
	W                                                          [][]float64
	Kbar                                                       float64
}

func sum(a []float64) float64 {
	s := 0.0
	for _, v := range a {
		s += v
	}
	return s
}
func sumInts(a []int) int {
	s := 0
	for _, v := range a {
		s += v
	}
	return s
}
func squares(a []float64) float64 {
	s := 0.0
	for _, v := range a {
		s += v * v
	}
	return s
}
func largest(a []float64) int {
	best := 0
	for i := 1; i < len(a); i++ {
		if a[i] > a[best] {
			best = i
		}
	}
	return best
}
func intReals(a []int) []float64 {
	v := make([]float64, len(a))
	for i, x := range a {
		v[i] = float64(x)
	}
	return v
}
func constant(n int, x float64) []float64 {
	v := make([]float64, n)
	for i := range v {
		v[i] = x
	}
	return v
}
func multiply(a []float64, x float64) []float64 {
	v := make([]float64, len(a))
	for i, y := range a {
		v[i] = x * y
	}
	return v
}
func multiplierSequence(interventions []Intervention, n int) []float64 {
	out := make([]float64, n)
	for d := 1; d <= n; d++ {
		for _, line := range interventions {
			if line.Day <= d {
				out[d-1] = line.Multiplier
			}
		}
	}
	return out
}
func sse(series []float64, scale float64, observed []int) float64 {
	value := 0.0
	for i, x := range series {
		e := scale*x - float64(observed[i])
		value += e * e
	}
	return value
}
func rmse(sse float64, n int) float64 { return math.Sqrt(sse / float64(n)) }
func (a *Application) model(kind string, beta, gamma, sigma float64, w [][]float64) Model {
	return Model{kind, beta, gamma, sigma, float64(a.Data.Population), a.Data.Fatality, a.Data.Groups, w}
}
func (a *Application) course(kind string, beta, gamma, sigma float64, multipliers []float64, w [][]float64) [][]float64 {
	return simulate(a.model(kind, beta, gamma, sigma, w), initial(a.Data, kind), multipliers)
}
func incidence(states [][]float64, kind string) []float64 {
	out := make([]float64, len(states))
	for d, state := range states {
		if kind == "sir" {
			out[d] = state[3]
		} else if kind == "age" {
			for g := 0; g < len(state)/6; g++ {
				out[d] += state[6*g+5]
			}
		} else {
			out[d] = state[5]
		}
	}
	return out
}
func (a *Application) objective(beta, gamma, rho float64, m []float64) float64 {
	return sse(incidence(a.course("seir", beta, gamma, a.Data.Params.Sigma, m, nil), "seir"), rho, a.Data.Cases[:len(m)])
}
func (a *Application) fit() {
	p := a.Data.Params
	t := len(a.Data.Cases)
	a.Multipliers = multiplierSequence(a.Data.Interventions, t)
	a.SpacingBeta = (p.BetaMax - p.BetaMin) / float64(p.BetaCount-1)
	a.SpacingRho = (p.RhoMax - p.RhoMin) / float64(p.RhoCount-1)
	a.FitLines = []string{fmt.Sprintf("data days %d cases %d deaths %d population %d fatality %s", t,
		sumInts(a.Data.Cases), sumInts(a.Data.Deaths), a.Data.Population, fixed(a.Data.Fatality,
			6))}
	rhoGrid := make([]float64, p.RhoCount)
	header := []string{"grid gamma " + fixed(p.Gamma, 4) + " rho"}
	for j := range rhoGrid {
		rhoGrid[j] = p.RhoMin + (p.RhoMax-p.RhoMin)*float64(j)/float64(p.RhoCount-1)
		header = append(header, fixed(rhoGrid[j], 4))
	}
	a.FitLines = append(a.FitLines, strings.Join(header, " "))
	betaGrid, bestRho, bestValue := 0.0, 0.0, 0.0
	for i := 0; i < p.BetaCount; i++ {
		beta := p.BetaMin + (p.BetaMax-p.BetaMin)*float64(i)/float64(p.BetaCount-1)
		series := incidence(a.course("seir", beta, p.Gamma, p.Sigma, a.Multipliers, nil), "seir")
		line := []string{"grid beta " + fixed(beta, 4) + " rmse"}
		for j, rho := range rhoGrid {
			value := sse(series, rho, a.Data.Cases)
			line = append(line, fixed(rmse(value, t), 2))
			if (i == 0 && j == 0) || value < bestValue {
				betaGrid, bestRho, bestValue = beta, rho, value
			}
		}
		a.FitLines = append(a.FitLines, strings.Join(line, " "))
	}
	a.FitLines = append(a.FitLines, fmt.Sprintf("grid_best beta %s rho %s sse %s rmse %s", fixed(betaGrid,
		4), fixed(bestRho, 4), fixed(bestValue, 1), fixed(rmse(bestValue, t), 4)))
	beta, rho := betaGrid, bestRho
	goldenValue := bestValue
	appendGolden := func(round int, name string, g GoldenResult) {
		for i, r := range g.Records {
			a.FitLines = append(a.FitLines, fmt.Sprintf("golden %d %s %d a %s b %s c %s d %s rmse %s %s", round,
				name, i, fixed(r.A, 6), fixed(r.B, 6), fixed(r.C, 6), fixed(r.D, 6), fixed(rmse(r.FC,
					t), 4), fixed(rmse(r.FD, t), 4)))
		}
		a.FitLines = append(a.FitLines, fmt.Sprintf("golden_result %d %s %s sse %s", round, name, fixed(g.X, 6), fixed(g.Value, 1)))
	}
	for round := 1; round <= p.Rounds; round++ {
		g := golden(func(x float64) float64 { return a.objective(x, p.Gamma, rho, a.Multipliers) }, beta-a.SpacingBeta, beta+a.SpacingBeta, p.Golden)
		beta = g.X
		appendGolden(round, "beta", g)
		g = golden(func(x float64) float64 { return a.objective(beta, p.Gamma, x, a.Multipliers) }, rho-a.SpacingRho, rho+a.SpacingRho, p.Golden)
		rho, goldenValue = g.X, g.Value
		appendGolden(round, "rho", g)
	}
	nm := nelder(func(b, g float64) float64 { return a.objective(b, g, rho, a.Multipliers) }, beta, p.Gamma, p)
	for _, v := range nm.Initial {
		a.FitLines = append(a.FitLines, fmt.Sprintf("simplex %d beta %s gamma %s rmse %s", v.Number, fixed(v.Beta, 6), fixed(v.Gamma, 6), fixed(rmse(v.Value, t), 4)))
	}
	for i, r := range nm.Records {
		v := r.Best
		a.FitLines = append(a.FitLines, fmt.Sprintf("nelder_mead %d %s beta %s gamma %s rmse %s", i+1, r.Operation,
			fixed(v.Beta, 6), fixed(v.Gamma, 6), fixed(rmse(v.Value, t), 4)))
	}
	for i, v := range nm.Final {
		a.FitLines = append(a.FitLines, fmt.Sprintf("final_simplex %d beta %s gamma %s rmse %s", i+1, fixed(v.Beta,
			6), fixed(v.Gamma, 6), fixed(rmse(v.Value, t), 4)))
	}
	v := nm.Final[0]
	a.Beta, a.Gamma, a.Rho, a.SSE = v.Beta, v.Gamma, rho, v.Value
	a.R0 = a.Beta / a.Gamma
	a.States = a.course("seir", a.Beta, a.Gamma, p.Sigma, a.Multipliers, nil)
	a.Incidence = incidence(a.States, "seir")
	a.Reported = multiply(a.Incidence, a.Rho)
	a.Residual, a.ModelDeaths, a.Average, a.Rt = make([]float64, t), make([]float64, t), make([]float64, t), make([]float64, t)
	previousDeath, previousS := 0.0, float64(a.Data.Population)-p.E0-p.I0
	for d, state := range a.States {
		a.Residual[d] = float64(a.Data.Cases[d]) - a.Reported[d]
		a.ModelDeaths[d] = state[4] - previousDeath
		previousDeath = state[4]
		a.Rt[d] = a.R0 * a.Multipliers[d] * previousS / float64(a.Data.Population)
		previousS = state[0]
		a.Average[d] = float64(sumInts(a.Data.Cases[max(0, d-6):d+1])) / float64(min(d+1, 7))
	}
	mean := float64(sumInts(a.Data.Cases)) / float64(t)
	sst := 0.0
	for _, c := range a.Data.Cases {
		e := float64(c) - mean
		sst += e * e
	}
	a.FitLines = append(a.FitLines, fmt.Sprintf("fitted beta %s gamma %s rho %s sigma %s r0 %s", fixed(a.Beta,
		6), fixed(a.Gamma, 6), fixed(a.Rho, 6), fixed(p.Sigma, 6), fixed(a.R0, 4)), fmt.Sprintf("sse grid %s golden %s nelder_mead %s rmse %s r2 %s",
		fixed(bestValue, 1), fixed(goldenValue, 1), fixed(a.SSE, 1), fixed(rmse(a.SSE, t), 4), fixed(1-a.SSE/sst,
			4)))
	for _, stage := range []struct {
		Name       string
		B, G, R, S float64
	}{{"grid", betaGrid, p.Gamma, bestRho, bestValue}, {"golden", beta, p.Gamma, rho, goldenValue}, {"nelder_mead", a.Beta, a.Gamma, a.Rho, a.SSE}} {
		a.FitLines = append(a.FitLines, fmt.Sprintf("stage %s beta %s gamma %s rho %s r0 %s rmse %s", stage.Name,
			fixed(stage.B, 6), fixed(stage.G, 6), fixed(stage.R, 6), fixed(stage.B/stage.G, 4), fixed(rmse(stage.S,
				t), 4)))
	}
}
func (a *Application) diagnostics() {
	t := len(a.Data.Cases)
	p := a.Data.Params
	e := a.Residual
	u := squares(e)
	residualSum, mae, dw := sum(e), 0.0, 0.0
	positive, runs, maximum := 0, 1, 0
	for d, v := range e {
		mae += math.Abs(v)
		if v > 0 {
			positive++
		}
		if math.Abs(v) > math.Abs(e[maximum]) {
			maximum = d
		}
		if d > 0 {
			difference := v - e[d-1]
			dw += difference * difference
			if (v > 0) != (e[d-1] > 0) {
				runs++
			}
		}
	}
	a.FitLines = append(a.FitLines, fmt.Sprintf("residuals sum %s mae %s max %s day %d positive %d runs %d durbin_watson %s",
		fixed(residualSum, 1), fixed(mae/float64(t), 1), fixed(e[maximum], 1), maximum+1, positive,
		runs, fixed(dw/u, 4)))
	acf := []string{"autocorrelation"}
	for lag := 1; lag <= 7; lag++ {
		value := 0.0
		for d := 0; d < t-lag; d++ {
			value += e[d] * e[d+lag]
		}
		acf = append(acf, fixed(value/u, 4))
	}
	a.FitLines = append(a.FitLines, strings.Join(acf, " "))
	outliers := 0
	for d, v := range e {
		z := v / math.Sqrt(a.Reported[d])
		if math.Abs(z) > p.Outlier {
			outliers++
			a.FitLines = append(a.FitLines, fmt.Sprintf("outlier %d observed %d fitted %s z %s", d+1, a.Data.Cases[d], fixed(a.Reported[d], 1), fixed(z, 4)))
		}
	}
	a.FitLines = append(a.FitLines, fmt.Sprint("outliers ", outliers))
	weekdayObserved := [7]int{}
	weekdayFitted := [7]float64{}
	factors := [7]float64{}
	for d, c := range a.Data.Cases {
		weekdayObserved[d%7] += c
		weekdayFitted[d%7] += a.Reported[d]
	}
	for k := 0; k < 7; k++ {
		factors[k] = float64(weekdayObserved[k]) / weekdayFitted[k]
		a.FitLines = append(a.FitLines, fmt.Sprintf("weekday %d observed %d fitted %s factor %s", k+1, weekdayObserved[k],
			fixed(weekdayFitted[k], 1), fixed(factors[k], 4)))
	}
	adjusted := make([]float64, t)
	for d, v := range a.Reported {
		adjusted[d] = v * factors[d%7]
	}
	infections := sum(a.Incidence)
	a.FitLines = append(a.FitLines, "weekday_adjusted rmse "+fixed(rmse(sse(adjusted, 1, a.Data.Cases),
		t), 4), fmt.Sprintf("burden infections %s ascertainment %s deaths_per_infection %s", fixed(infections,
		1), fixed(float64(sumInts(a.Data.Cases))/infections, 4), fixed(float64(sumInts(a.Data.Deaths))/infections,
		6)))
	cross := 0.0
	for d, v := range a.ModelDeaths {
		cross += v * float64(a.Data.Deaths[d])
	}
	scale := cross / squares(a.ModelDeaths)
	a.FitLines = append(a.FitLines, fmt.Sprintf("deaths observed %d model %s rmse %s scale %s implied_fatality %s cfr %s",
		sumInts(a.Data.Deaths), fixed(a.States[t-1][4], 1), fixed(rmse(sse(a.ModelDeaths, 1, a.Data.Deaths),
			t), 4), fixed(scale, 4), fixed(a.Data.Fatality*scale, 6), fixed(float64(sumInts(a.Data.Deaths))/float64(sumInts(a.Data.Cases)),
			4)))
	bestLag, bestCorrelation := 0, 0.0
	for lag := 0; lag <= p.DeathLag; lag++ {
		cross, squareCases, squareDeaths := 0, 0, 0
		for d := 0; d < t-lag; d++ {
			c, q := a.Data.Cases[d], a.Data.Deaths[d+lag]
			cross += c * q
			squareCases += c * c
			squareDeaths += q * q
		}
		correlation := float64(cross) / math.Sqrt(float64(squareCases)*float64(squareDeaths))
		if lag == 0 || correlation > bestCorrelation {
			bestLag, bestCorrelation = lag, correlation
		}
		cfr := float64(sumInts(a.Data.Deaths[lag:])) / float64(sumInts(a.Data.Cases[:t-lag]))
		a.FitLines = append(a.FitLines, fmt.Sprintf("death_lag %d correlation %s cfr %s", lag, fixed(correlation, 4), fixed(cfr, 4)))
	}
	a.FitLines = append(a.FitLines, fmt.Sprint("death_best_lag ", bestLag))
	previous := 0
	for start := 0; start < t; start += 7 {
		end := min(t, start+7)
		observed := sumInts(a.Data.Cases[start:end])
		growth := "-"
		if start > 0 {
			growth = fixed(float64(observed)/float64(previous), 4)
		}
		a.FitLines = append(a.FitLines, fmt.Sprintf("weekly %d days %d %d observed %d fitted %s deaths_observed %d deaths_model %s growth %s",
			start/7+1, start+1, end, observed, fixed(sum(a.Reported[start:end]), 1), sumInts(a.Data.Deaths[start:end]),
			fixed(sum(a.ModelDeaths[start:end]), 1), growth))
		previous = observed
	}
	for parameter, name := range []string{"beta", "gamma", "rho"} {
		values := [3]float64{a.Beta, a.Gamma, a.Rho}
		v := values[parameter]
		profile := make([]float64, 11)
		for k := -5; k <= 5; k++ {
			point := values
			point[parameter] = v * (1 + float64(k)/100)
			profile[k+5] = a.objective(point[0], point[1], point[2], a.Multipliers)
			a.FitLines = append(a.FitLines, fmt.Sprintf("profile %s %d value %s rmse %s", name, k, fixed(point[parameter], 6), fixed(rmse(profile[k+5], t), 4)))
		}
		h := v / 100
		curvature := (profile[6] - 2*profile[5] + profile[4]) / (h * h)
		variance := a.SSE / float64(t-3)
		se := math.Sqrt(2 * variance / curvature)
		if parameter == 0 {
			a.SEBeta = se
		}
		a.FitLines = append(a.FitLines, fmt.Sprintf("profile_se %s %s", name, fixed(se, 6)))
	}
}
func (a *Application) furtherFit() {
	p := a.Data.Params
	t := len(a.Data.Cases)
	trainingDays := t - p.Holdout
	g := golden(func(beta float64) float64 { return a.objective(beta, a.Gamma, a.Rho, a.Multipliers[:trainingDays]) },
		a.Beta-a.SpacingBeta, a.Beta+a.SpacingBeta, p.Golden)
	backBeta := g.X
	g = golden(func(rho float64) float64 { return a.objective(backBeta, a.Gamma, rho, a.Multipliers[:trainingDays]) },
		a.Rho-a.SpacingRho, a.Rho+a.SpacingRho, p.Golden)
	backRho := g.X
	forecast := multiply(incidence(a.course("seir", backBeta, a.Gamma, p.Sigma, a.Multipliers, nil), "seir"), backRho)
	a.FitLines = append(a.FitLines, fmt.Sprintf("backtest train_days %d beta %s rho %s train_rmse %s test_rmse %s full_fit_test_rmse %s",
		trainingDays, fixed(backBeta, 6), fixed(backRho, 6), fixed(rmse(g.Value, trainingDays), 4),
		fixed(rmse(sse(forecast[trainingDays:], 1, a.Data.Cases[trainingDays:]), p.Holdout), 4),
		fixed(rmse(sse(a.Reported[trainingDays:], 1, a.Data.Cases[trainingDays:]), p.Holdout), 4)))
	for d := trainingDays; d < t; d++ {
		a.FitLines = append(a.FitLines, fmt.Sprintf("backtest_day %d observed %d forecast %s error %s",
			d+1, a.Data.Cases[d], fixed(forecast[d], 1), fixed(float64(a.Data.Cases[d])-forecast[d],
				1)))
	}
	estimated := append([]Intervention(nil), a.Data.Interventions...)
	effectSSE := a.SSE
	for k := 1; k < len(estimated); k++ {
		index := k
		given := a.Data.Interventions[k]
		g := golden(func(x float64) float64 {
			copy := append([]Intervention(nil), estimated...)
			copy[index].Multiplier = x
			return a.objective(a.Beta, a.Gamma, a.Rho, multiplierSequence(copy, t))
		}, given.Multiplier-p.EffectWidth, given.Multiplier+p.EffectWidth, p.Golden)
		estimated[k].Multiplier = g.X
		effectSSE = g.Value
		a.FitLines = append(a.FitLines, fmt.Sprintf("effect %d day %d given %s estimated %s sse %s", k+1,
			given.Day, fixed(given.Multiplier, 4), fixed(g.X, 6), fixed(g.Value, 1)))
	}
	a.FitLines = append(a.FitLines, fmt.Sprintf("effect_sse before %s after %s rmse %s", fixed(a.SSE, 1), fixed(effectSSE, 1), fixed(rmse(effectSSE, t), 4)))
	for parameter, name := range []string{"beta", "gamma", "sigma", "rho"} {
		for _, factor := range []float64{.9, 1.1} {
			point := [4]float64{a.Beta, a.Gamma, p.Sigma, a.Rho}
			point[parameter] *= factor
			states := a.course("seir", point[0], point[1], point[2], a.Multipliers, nil)
			j := incidence(states, "seir")
			peak := largest(j)
			a.FitLines = append(a.FitLines, fmt.Sprintf("sensitivity %s %s r0 %s rmse %s peak_day %d peak %s attack %s",
				name, fixed(factor, 2), fixed(point[0]/point[1], 4), fixed(rmse(sse(j, point[3],
					a.Data.Cases), t), 4), peak+1, fixed(point[3]*j[peak], 1), fixed((float64(a.Data.Population)-states[t-1][0])/float64(a.Data.Population),
					4)))
		}
	}
}
func (a *Application) prepareAge() {
	groups := a.Data.Groups
	n := float64(a.Data.Population)
	weighted := 0.0
	for g, group := range groups {
		weighted += float64(group.Population) * sum(a.Data.Contacts[g])
	}
	a.Kbar = weighted / n
	a.W = make([][]float64, len(groups))
	for g := range groups {
		a.W[g] = make([]float64, len(groups))
		for h := range groups {
			a.W[g][h] = a.Data.Contacts[g][h] / a.Kbar
		}
	}
	a.AgeStates = a.course("age", a.Beta, a.Gamma, a.Data.Params.Sigma, a.Multipliers, a.W)
}
func (a *Application) modelComparison() {
	p := a.Data.Params
	t := len(a.Data.Cases)
	sir := incidence(a.course("sir", a.Beta, a.Gamma, p.Sigma, a.Multipliers, nil), "sir")
	for i, j := range [][]float64{sir, a.Incidence, incidence(a.AgeStates, "age")} {
		name := []string{"sir", "seir", "age"}[i]
		cross := 0.0
		for d, v := range j {
			cross += float64(a.Data.Cases[d]) * v
		}
		rho := cross / squares(j)
		a.FitLines = append(a.FitLines, fmt.Sprintf("model %s rmse %s peak_day %d rho_opt %s rmse_opt %s",
			name, fixed(rmse(sse(j, a.Rho, a.Data.Cases), t), 4), largest(j)+1, fixed(rho, 6), fixed(rmse(sse(j,
				rho, a.Data.Cases), t), 4)))
	}
	g := golden(func(beta float64) float64 {
		return sse(incidence(a.course("sir", beta, a.Gamma, p.Sigma, a.Multipliers, nil), "sir"), a.Rho, a.Data.Cases)
	}, p.BetaMin, p.BetaMax, p.Golden)
	j := incidence(a.course("sir", g.X, a.Gamma, p.Sigma, a.Multipliers, nil), "sir")
	a.FitLines = append(a.FitLines, fmt.Sprintf("model sir_fit beta %s rmse %s peak_day %d", fixed(g.X, 6), fixed(rmse(g.Value, t), 4), largest(j)+1))
}
func finalSize(r float64) float64 {
	if r <= 1 {
		return 0
	}
	lo, hi := 1-1/r, 1.0
	for i := 0; i < 20; i++ {
		mid := (lo + hi) / 2
		g := 1 - mid - math.Exp(-r*mid)
		if g > 0 {
			lo = mid
		} else {
			hi = mid
		}
	}
	return (lo + hi) / 2
}
func power(matrix [][]float64) (float64, []float64) {
	n := len(matrix)
	v := constant(n, 1/float64(n))
	nu := 0.0
	for iteration := 0; iteration < 200; iteration++ {
		u := make([]float64, n)
		for g := range u {
			for h, x := range matrix[g] {
				u[g] += x * v[h]
			}
		}
		nu = sum(u)
		for g := range v {
			v[g] = u[g] / nu
		}
	}
	return nu, v
}
func (a *Application) ngm(w [][]float64, multiplier float64, susceptible []float64) [][]float64 {
	out := make([][]float64, len(w))
	for g := range w {
		out[g] = make([]float64, len(w))
		for h := range w {
			if susceptible == nil {
				out[g][h] = a.R0 * w[g][h] * float64(a.Data.Groups[g].Population) / float64(a.Data.Groups[h].Population)
			} else {
				out[g][h] = multiplier * a.R0 * w[g][h] * susceptible[6*g] / float64(a.Data.Groups[h].Population)
			}
		}
	}
	return out
}
func (a *Application) reproduction() ([]string, []string) {
	data, p := a.Data, a.Data.Params
	t := len(data.Cases)
	n := float64(data.Population)
	states := a.course("seir", a.Beta, a.Gamma, p.Sigma, constant(730, 1), nil)
	final := states[len(states)-1]
	out := []string{fmt.Sprintf("r0 %s herd_immunity %s", fixed(a.R0, 4), fixed(1-1/a.R0, 4)), fmt.Sprintf("final_size equation %s simulated %s",
		fixed(finalSize(a.R0), 4), fixed((n-final[0])/n, 4))}
	generation := simulate(a.model("generation", a.Beta, a.Gamma, p.Sigma, nil), initial(data, "generation"), constant(p.Generation, 1))
	daily := make([]float64, len(generation))
	for i, state := range generation {
		daily[i] = state[2]
	}
	coverage := sum(daily)
	weights := make([]float64, len(daily))
	mean := 0.0
	for i, v := range daily {
		weights[i] = v / coverage
		mean += (float64(i+1) - .5) * weights[i]
	}
	out = append(out, fmt.Sprintf("generation mean %s theory %s coverage %s", fixed(mean, 4), fixed(1/p.Sigma+1/a.Gamma, 4), fixed(coverage, 4)))
	for i, w := range weights {
		out = append(out, fmt.Sprintf("generation_weight %d %s", i+1, fixed(w, 6)))
	}
	peak := largest(a.Incidence)
	infectious := make([]float64, t)
	for d, state := range a.States {
		infectious[d] = state[2]
	}
	ip := largest(infectious)
	observed := intReals(data.Cases)
	op, ap := largest(observed), largest(a.Average)
	out = append(out, fmt.Sprintf("peak model day %d incidence %s reported %s infectious_day %d infectious %s",
		peak+1, fixed(a.Incidence[peak], 1), fixed(a.Reported[peak], 1), ip+1, fixed(infectious[ip],
			1)), fmt.Sprintf("peak observed day %d cases %d average7_day %d average7 %s", op+1, data.Cases[op],
		ap+1, fixed(a.Average[ap], 2)))
	for k, line := range data.Interventions {
		start, end := line.Day-1, t
		if k+1 < len(data.Interventions) {
			end = data.Interventions[k+1].Day - 1
		}
		count := end - start
		out = append(out, fmt.Sprintf("period %d days %d %d multiplier %s rt_start %s rt_end %s observed %d fitted %s rmse %s bias %s",
			k+1, start+1, end, fixed(line.Multiplier, 4), fixed(a.Rt[start], 4), fixed(a.Rt[end-1],
				4), sumInts(data.Cases[start:end]), fixed(sum(a.Reported[start:end]), 1), fixed(rmse(squares(a.Residual[start:end]),
				count), 4), fixed(sum(a.Residual[start:end])/float64(count), 1)))
	}
	for _, target := range p.Milestones {
		co, cr := 0, 0.0
		od, fd := "never", "never"
		for d, c := range data.Cases {
			co += c
			cr += a.Reported[d]
			if od == "never" && co >= target {
				od = fmt.Sprint(d + 1)
			}
			if fd == "never" && cr >= float64(target) {
				fd = fmt.Sprint(d + 1)
			}
		}
		out = append(out, fmt.Sprintf("milestone %d observed %s fitted %s", target, od, fd))
	}
	total := sum(a.Reported)
	counterfactual := multiply(incidence(a.course("seir", a.Beta, a.Gamma, p.Sigma, constant(t, data.Interventions[0].Multiplier), nil), "seir"), a.Rho)
	cp := largest(counterfactual)
	ctotal := sum(counterfactual)
	out = append(out, fmt.Sprintf("counterfactual none reported %s peak_day %d peak %s averted %s", fixed(ctotal,
		1), cp+1, fixed(counterfactual[cp], 1), fixed(ctotal-total, 1)))
	for k := 1; k < len(data.Interventions); k++ {
		removed := append([]Intervention(nil), data.Interventions[:k]...)
		removed = append(removed, data.Interventions[k+1:]...)
		cases := multiply(incidence(a.course("seir", a.Beta, a.Gamma, p.Sigma, multiplierSequence(removed, t), nil), "seir"), a.Rho)
		value := sum(cases)
		out = append(out, fmt.Sprintf("counterfactual without %d reported %s averted %s", k+1, fixed(value, 1), fixed(value-total, 1)))
	}
	for k := 1; k < len(data.Interventions); k++ {
		for _, shift := range []int{-7, 7} {
			changed := append([]Intervention(nil), data.Interventions...)
			changed[k].Day += shift
			cases := multiply(incidence(a.course("seir", a.Beta, a.Gamma, p.Sigma, multiplierSequence(changed, t), nil), "seir"), a.Rho)
			value := sum(cases)
			out = append(out, fmt.Sprintf("timing %d shift %d reported %s change %s", k+1, shift, fixed(value, 1), fixed(value-total, 1)))
		}
	}
	for d := 1; d < t; d++ {
		if (a.Rt[d] < 1) != (a.Rt[d-1] < 1) {
			direction := "up"
			if a.Rt[d] < 1 {
				direction = "down"
			}
			out = append(out, fmt.Sprintf("rt_cross day %d %s", d+1, direction))
		}
	}
	pressure := make([]float64, t)
	for d := 0; d < t; d++ {
		for s := 1; s <= min(p.Generation, d); s++ {
			pressure[d] += weights[s-1] * float64(data.Cases[d-s])
		}
	}
	for d := 0; d < t; d++ {
		empirical := "-"
		if d+1 >= p.Generation+7 {
			empirical = fixed(float64(sumInts(data.Cases[d-6:d+1]))/sum(pressure[d-6:d+1]), 4)
		}
		out = append(out, fmt.Sprintf("rt %d model %s empirical %s", d+1, fixed(a.Rt[d], 4), empirical))
	}
	matrix := a.ngm(a.W, 1, nil)
	eigenvalue, eigenvector := power(matrix)
	for g, row := range matrix {
		items := []string{"ngm " + data.Groups[g].Name}
		for _, v := range row {
			items = append(items, fixed(v, 4))
		}
		out = append(out, strings.Join(items, " "))
	}
	items := []string{fmt.Sprintf("r0_age %s ratio %s kbar %s eigenvector", fixed(eigenvalue, 4), fixed(eigenvalue/a.R0, 4), fixed(a.Kbar, 4))}
	for _, v := range eigenvector {
		items = append(items, fixed(v, 4))
	}
	out = append(out, strings.Join(items, " "))
	z := constant(len(data.Groups), 1)
	for iteration := 0; iteration < 100; iteration++ {
		next := make([]float64, len(z))
		for g := range z {
			force := 0.0
			for h := range z {
				force += a.R0 * a.W[g][h] * z[h]
			}
			next[g] = 1 - math.Exp(-force)
		}
		z = next
	}
	longAge := a.course("age", a.Beta, a.Gamma, p.Sigma, constant(730, 1), a.W)
	longFinal := longAge[len(longAge)-1]
	equationTotal, simulationTotal := 0.0, 0.0
	for g, group := range data.Groups {
		population := float64(group.Population)
		simulated := (population - longFinal[6*g]) / population
		equationTotal += population * z[g]
		simulationTotal += population * simulated
		out = append(out, fmt.Sprintf("final_size_age %s equation %s simulated %s", group.Name, fixed(z[g], 4), fixed(simulated, 4)))
	}
	out = append(out, fmt.Sprintf("final_size_age total equation %s simulated %s", fixed(equationTotal/n, 4), fixed(simulationTotal/n, 4)))
	ageInitial := initial(data, "age")
	for d := 0; d < t; d += 7 {
		previous := ageInitial
		if d > 0 {
			previous = a.AgeStates[d-1]
		}
		value, _ := power(a.ngm(a.W, a.Multipliers[d], previous))
		out = append(out, fmt.Sprintf("age_rt %d %s homogeneous %s", d+1, fixed(value, 4), fixed(a.Rt[d], 4)))
	}
	for start := 0; start < t; start += 7 {
		end := min(t, start+7)
		items := []string{fmt.Sprintf("age_weekly %d days %d %d", start/7+1, start+1, end)}
		for g := range data.Groups {
			value := 0.0
			for d := start; d < end; d++ {
				value += a.AgeStates[d][6*g+5]
			}
			items = append(items, fixed(value, 1))
		}
		out = append(out, strings.Join(items, " "))
	}
	ageInfections := make([]float64, len(data.Groups))
	ageFinal := a.AgeStates[t-1]
	for g := range data.Groups {
		for d := 0; d < t; d++ {
			ageInfections[g] += a.AgeStates[d][6*g+5]
		}
	}
	ageTotal := sum(ageInfections)
	for g, group := range data.Groups {
		series := make([]float64, t)
		for d := range series {
			series[d] = a.AgeStates[d][6*g+5]
		}
		peak := largest(series)
		out = append(out, fmt.Sprintf("age %s attack %s infections %s share %s deaths %s peak_day %d peak %s",
			group.Name, fixed((float64(group.Population)-ageFinal[6*g])/float64(group.Population),
				4), fixed(ageInfections[g], 1), fixed(ageInfections[g]/ageTotal, 4), fixed(ageFinal[6*g+4],
				1), peak+1, fixed(series[peak], 1)))
	}
	for _, change := range p.Changes {
		target := 0
		for g, group := range data.Groups {
			if group.Name == change.Group {
				target = g
				break
			}
		}
		changed := make([][]float64, len(a.W))
		for g := range changed {
			changed[g] = make([]float64, len(a.W))
			tauG := 1.0
			if g == target {
				tauG = change.Factor
			}
			for h := range changed[g] {
				tauH := 1.0
				if h == target {
					tauH = change.Factor
				}
				changed[g][h] = a.W[g][h] * tauG * tauH
			}
		}
		value, _ := power(a.ngm(changed, 1, nil))
		states := a.course("age", a.Beta, a.Gamma, p.Sigma, a.Multipliers, changed)
		infections := sum(incidence(states, "age"))
		final := states[t-1]
		deaths, infected := 0.0, 0.0
		for g, group := range data.Groups {
			deaths += final[6*g+4]
			infected += float64(group.Population) - final[6*g]
		}
		out = append(out, fmt.Sprintf("contact_change %s group %s factor %s r0_age %s infections %s deaths %s attack %s",
			change.Name, change.Group, fixed(change.Factor, 4), fixed(value, 4), fixed(infections,
				1), fixed(deaths, 1), fixed(infected/n, 4)))
	}
	scenarioCSV := []string{"scenario,day,incidence,reported"}
	firstTotal := 0.0
	for index, scenario := range p.Scenarios {
		multipliers := constant(p.Horizon, scenario.Multiplier)
		states := simulate(a.model("seir", a.Beta, a.Gamma, p.Sigma, nil), a.States[t-1], multipliers)
		j := incidence(states, "seir")
		reported := multiply(j, a.Rho)
		value := sum(reported)
		if index == 0 {
			firstTotal = value
		}
		peak := largest(reported)
		below := "never"
		above := 0
		for d, v := range reported {
			scenarioCSV = append(scenarioCSV, fmt.Sprintf("%s,%d,%s,%s", scenario.Name, t+d+1, fixed(j[d], 1), fixed(v, 1)))
			if v < p.Threshold && below == "never" {
				below = fmt.Sprint(t + d + 1)
			}
			if v >= p.Threshold {
				above++
			}
		}
		out = append(out, fmt.Sprintf("scenario %s multiplier %s rt %s reported %s peak_day %d peak %s attack %s final_size %s averted %s below %s days_above %d",
			scenario.Name, fixed(scenario.Multiplier, 4), fixed(a.R0*scenario.Multiplier*a.States[t-1][0]/n,
				4), fixed(value, 1), t+peak+1, fixed(reported[peak], 1), fixed((n-states[len(states)-1][0])/n,
				4), fixed(finalSize(a.R0*scenario.Multiplier), 4), fixed(firstTotal-value, 1), below,
			above))
		sequence := append(append([]float64(nil), a.Multipliers...), multipliers...)
		bounds := [2]float64{a.Beta - 2*a.SEBeta, a.Beta + 2*a.SEBeta}
		totals := [2]float64{}
		for i, beta := range bounds {
			series := incidence(a.course("seir", beta, a.Gamma, p.Sigma, sequence, nil), "seir")
			totals[i] = sum(multiply(series[t:], a.Rho))
		}
		out = append(out, fmt.Sprintf("scenario_band %s beta_low %s reported_low %s beta_high %s reported_high %s",
			scenario.Name, fixed(bounds[0], 6), fixed(totals[0], 1), fixed(bounds[1], 6), fixed(totals[1],
				1)))
		ageStates := simulate(a.model("age", a.Beta, a.Gamma, p.Sigma, a.W), ageFinal, multipliers)
		last := ageStates[len(ageStates)-1]
		items := []string{"scenario_age " + scenario.Name + " attack"}
		deaths := 0.0
		for g, group := range data.Groups {
			items = append(items, fixed((float64(group.Population)-last[6*g])/float64(group.Population), 4))
			deaths += last[6*g+4]
		}
		items = append(items, "deaths", fixed(deaths, 1))
		out = append(out, strings.Join(items, " "))
	}
	return out, scenarioCSV
}
func (a *Application) trajectoryOutput() {
	out := []string{"day,S,E,I,R,D,incidence,reported,observed,average7,cumulative_observed,cumulative_reported"}
	co, cr := 0, 0.0
	for d, state := range a.States {
		co += a.Data.Cases[d]
		cr += a.Reported[d]
		row := []string{fmt.Sprint(d + 1)}
		for _, v := range state[:5] {
			row = append(row, fixed(v, 1))
		}
		row = append(row, fixed(a.Incidence[d], 1), fixed(a.Reported[d], 1), fmt.Sprint(a.Data.Cases[d]), fixed(a.Average[d], 2), fmt.Sprint(co), fixed(cr, 1))
		out = append(out, strings.Join(row, ","))
	}
	writeLines("trajectories.csv", out)
}
func main() {
	a := Application{Data: readData()}
	a.fit()
	a.diagnostics()
	a.furtherFit()
	a.prepareAge()
	a.modelComparison()
	reproduction, scenarios := a.reproduction()
	writeLines("fit.txt", a.FitLines)
	a.trajectoryOutput()
	writeLines("scenarios.csv", scenarios)
	writeLines("reproduction.txt", reproduction)
	writeLines("curve_plot.txt", curvePlot(a.Data.Cases, a.Reported))
}
