package main

import (
	"fmt"
	"math"
	"sort"
	"strings"
)

type FoldResult struct {
	Train, Test, Correct, Support, Passes, Steps int
	Converged                                    bool
}
type CV struct {
	Kernel, CIndex, Correct, Support, Passes, Steps int
	C                                               float64
	Values                                          []float64
	Folds                                           []FoldResult
}
type Application struct {
	Train, Test             []Example
	Params                  Params
	Matrices                [][][]float64
	Grid                    [][]CV
	Best                    []int
	Selected                int
	Models                  []*Model
	TrainValues, TestValues [][]float64
}

func decisions(m *Model, data []Example) []float64 {
	a := make([]float64, len(data))
	for i, e := range data {
		a[i] = m.decision(e.Point)
	}
	return a
}
func runInfo(m *Model) string {
	return fmt.Sprintf("passes %d steps %d converged %s", len(m.Passes), m.Steps, yes(m.Converged))
}
func svInfo(m *Model) string {
	total, bound, free := m.counts()
	return fmt.Sprintf("support_vectors %d bound %d free %d", total, bound, free)
}
func (a *Application) prepare() {
	n := len(a.Train)
	p := a.Params
	a.Best = make([]int, len(p.Kernels))
	a.Selected = 0
	for ki, k := range p.Kernels {
		q := kernelMatrix(a.Train, k)
		a.Matrices = append(a.Matrices, q)
		row := []CV{}
		for ci, c := range p.Cs {
			cv := CV{Kernel: ki, CIndex: ci, C: c, Values: make([]float64, n)}
			for fold := 0; fold < p.Folds; fold++ {
				training, validation := folds(n, p.Folds, fold)
				data, matrix := subset(a.Train, q, training)
				m := train(data, matrix, k, c, p)
				count := 0
				for _, i := range validation {
					v := m.decision(a.Train[i].Point)
					cv.Values[i] = v
					if sign(v) == a.Train[i].Label {
						count++
					}
				}
				support, _, _ := m.counts()
				cv.Folds = append(cv.Folds, FoldResult{len(training), len(validation), count, support, len(m.Passes), m.Steps, m.Converged})
				cv.Correct += count
				cv.Support += support
				cv.Passes += len(m.Passes)
				cv.Steps += m.Steps
			}
			row = append(row, cv)
			if ci == 0 || cv.Correct > row[a.Best[ki]].Correct {
				a.Best[ki] = ci
			}
		}
		a.Grid = append(a.Grid, row)
		chosen := a.Grid[ki][a.Best[ki]]
		current := a.Grid[a.Selected][a.Best[a.Selected]]
		if chosen.Correct > current.Correct || (chosen.Correct == current.Correct && chosen.C < current.C) {
			a.Selected = ki
		}
		m := train(a.Train, q, k, chosen.C, p)
		a.Models = append(a.Models, m)
		a.TrainValues = append(a.TrainValues, m.trainingValues())
		a.TestValues = append(a.TestValues, decisions(m, a.Test))
	}
}
func (a *Application) cvOutput() []string {
	n, p := len(a.Train), a.Params
	out := []string{fmt.Sprintf("cross_validation folds %d examples %d", p.Folds, n)}
	ranked := []CV{}
	header := []string{"kernel", "C"}
	for i := 1; i <= p.Folds; i++ {
		header = append(header, fmt.Sprint("fold", i))
	}
	header = append(header, "correct", "accuracy", "support_vectors", "passes", "steps")
	csv := []string{strings.Join(header, ",")}
	for ki, k := range p.Kernels {
		best := a.Grid[ki][a.Best[ki]]
		out = append(out, fmt.Sprintf("best %s C %s correct %d/%d accuracy %s", k.Name, fixed(best.C, 4), best.Correct, n, ratio(best.Correct, n)))
		for _, cv := range a.Grid[ki] {
			ranked = append(ranked, cv)
			row := []string{k.Name, fixed(cv.C, 4)}
			for _, fold := range cv.Folds {
				row = append(row, fmt.Sprint(fold.Correct))
			}
			row = append(row, fmt.Sprint(cv.Correct), ratio(cv.Correct, n), fmt.Sprint(cv.Support), fmt.Sprint(cv.Passes), fmt.Sprint(cv.Steps))
			csv = append(csv, strings.Join(row, ","))
		}
	}
	selected := a.Grid[a.Selected][a.Best[a.Selected]]
	name := p.Kernels[a.Selected].Name
	out = append(out, fmt.Sprintf("selected %s C %s", name, fixed(selected.C, 4)), "ranking")
	sort.Slice(ranked, func(i, j int) bool {
		x, y := ranked[i], ranked[j]
		if x.Correct != y.Correct {
			return x.Correct > y.Correct
		}
		if x.C != y.C {
			return x.C < y.C
		}
		return x.Kernel < y.Kernel
	})
	for i, cv := range ranked {
		out = append(out, fmt.Sprintf("%d %s C %s correct %d/%d", i+1, p.Kernels[cv.Kernel].Name, fixed(cv.C, 4), cv.Correct, n))
	}
	out = append(out, fmt.Sprintf("cv_detail %s C %s", name, fixed(selected.C, 4)))
	for i, fold := range selected.Folds {
		out = append(out, fmt.Sprintf("fold %d train %d test %d correct %d support_vectors %d passes %d steps %d converged %s",
			i+1, fold.Train, fold.Test, fold.Correct, fold.Support, fold.Passes, fold.Steps, yes(fold.Converged)))
	}
	writeLines("cv_grid.csv", csv)
	return out
}
func (a *Application) modelOutput(ki int) []string {
	m := a.Models[ki]
	q := a.Matrices[ki]
	trainF, testF := a.TrainValues[ki], a.TestValues[ki]
	n, nt := len(a.Train), len(a.Test)
	alignmentY, alignmentG, equality := 0.0, 0.0, 0.0
	maximumDiagonal, minimumEntry := q[0][0], q[0][0]
	weights := Point{}
	counts := [2][2]int{}
	for i, e := range a.Train {
		equality += m.Alpha[i] * float64(e.Label)
		weights[0] += m.Alpha[i] * float64(e.Label) * e.Point[0]
		weights[1] += m.Alpha[i] * float64(e.Label) * e.Point[1]
		if m.Alpha[i] > 0 {
			cl, bound := 0, 1
			if e.Label == -1 {
				cl = 1
			}
			if m.Alpha[i] == m.C {
				bound = 0
			}
			counts[cl][bound]++
		}
		maximumDiagonal = math.Max(maximumDiagonal, q[i][i])
		for j, f := range a.Train {
			alignmentY += float64(e.Label*f.Label) * q[i][j]
			alignmentG += q[i][j] * q[i][j]
			minimumEntry = math.Min(minimumEntry, q[i][j])
		}
	}
	quadratic, dual := objective(m.Alpha, m.Data, m.Q)
	norm := math.Sqrt(quadratic)
	hinge, maximumViolation := 0.0, 0.0
	violations, estimate := 0, 0
	radius := maximumDiagonal - minimumEntry
	for i, e := range a.Train {
		yf := float64(e.Label) * trainF[i]
		xi := math.Max(0, 1-yf)
		hinge += xi
		r := yf - 1
		v := math.Abs(r)
		if m.Alpha[i] == 0 {
			v = math.Max(0, -r)
		} else if m.Alpha[i] == m.C {
			v = math.Max(0, r)
		}
		if v > a.Params.Tolerance {
			violations++
		}
		maximumViolation = math.Max(maximumViolation, v)
		if 2*m.Alpha[i]*radius+xi >= 1 {
			estimate++
		}
	}
	primal := quadratic/2 + m.C*hinge
	metrics := evaluate(a.Test, testF)
	trainCorrect := correct(a.Train, trainF)
	out := []string{"model " + m.Kernel.Name, "kernel " + m.Kernel.description(), "C " + fixed(m.C, 4),
		"alignment " + fixed(alignmentY/(float64(n)*math.Sqrt(alignmentG)), 6), fmt.Sprintf("passes %d full %d nonbound %d converged %s",
			len(m.Passes), m.Full, m.Nonbound, yes(m.Converged)), fmt.Sprintf("examined %d steps %d",
			m.Examined, m.Steps), fmt.Sprintf("choice heuristic %d nonbound_loop %d full_loop %d", m.Choice[0],
			m.Choice[1], m.Choice[2]), fmt.Sprintf("clipping none %d lower %d upper %d", m.Clipping[0],
			m.Clipping[1], m.Clipping[2]), svInfo(m), "b " + fixed(m.B, 6), "equality " + fixed(equality,
			6)}
	if m.Kernel.Kind == "linear" {
		out = append(out, fmt.Sprintf("w %s %s", fixed(weights[0], 6), fixed(weights[1], 6)))
	}
	out = append(out, fmt.Sprintf("sv_by_class positive bound %d free %d negative bound %d free %d",
		counts[0][0], counts[0][1], counts[1][0], counts[1][1]), fmt.Sprintf("norm %s margin %s",
		fixed(norm, 6), fixed(2/norm, 6)), "dual_objective "+fixed(dual, 6), "primal_objective "+fixed(primal,
		6), "duality_gap "+fixed(primal-dual, 6), fmt.Sprintf("kkt_violations %d max %s", violations,
		fixed(maximumViolation, 6)), fmt.Sprintf("xi_alpha radius %s errors %d/%d accuracy %s", fixed(radius,
		6), estimate, n, ratio(n-estimate, n)), fmt.Sprintf("train correct %d/%d accuracy %s", trainCorrect,
		n, ratio(trainCorrect, n)), fmt.Sprintf("test correct %d/%d accuracy %s tp %d fp %d tn %d fn %d",
		metrics.Correct, nt, ratio(metrics.Correct, nt), metrics.TP, metrics.FP, metrics.TN, metrics.FN),
		fmt.Sprintf("test precision %s recall %s f1 %s auc %s", ratio(metrics.TP, metrics.TP+metrics.FP),
			ratio(metrics.TP, metrics.TP+metrics.FN), ratio(2*metrics.TP, 2*metrics.TP+metrics.FP+metrics.FN),
			fixed(metrics.AUC, 4)), fmt.Sprint("test inside_margin ", metrics.Inside), fmt.Sprintf("test mean_decision positive %s negative %s",
			fixed(metrics.PositiveMean, 4), fixed(metrics.NegativeMean, 4)))
	for i, e := range a.Train {
		if m.Alpha[i] <= 0 {
			continue
		}
		kind := "free"
		if m.Alpha[i] == m.C {
			kind = "bound"
		}
		out = append(out, fmt.Sprintf("sv %s y %d alpha %s f %s %s", e.ID, e.Label, fixed(m.Alpha[i], 6), fixed(trainF[i], 4), kind))
	}
	return out
}
func (a *Application) progressOutput() []string {
	m := a.Models[a.Selected]
	out := []string{"training_log " + m.Kernel.Name}
	for i := 0; i < len(m.Passes); {
		pass := m.Passes[i]
		if pass.Full {
			_, dual := objective(pass.Alpha, m.Data, m.Q)
			out = append(out, fmt.Sprintf("pass %d full examined %d changed %d dual_objective %s", i+1, pass.Examined, pass.Changed, fixed(dual, 6)))
			i++
		} else {
			j, examined, changed := i, 0, 0
			for j < len(m.Passes) && !m.Passes[j].Full {
				examined += m.Passes[j].Examined
				changed += m.Passes[j].Changed
				j++
			}
			out = append(out, fmt.Sprintf("passes %d-%d nonbound examined %d changed %d", i+1, j, examined, changed))
			i = j
		}
	}
	return out
}
func (a *Application) pathOutput() []string {
	selected := a.Models[a.Selected]
	out := []string{"c_path " + selected.Kernel.Name}
	for _, c := range a.Params.Cs {
		m := train(a.Train, a.Matrices[a.Selected], selected.Kernel, c, a.Params)
		_, dual := objective(m.Alpha, m.Data, m.Q)
		out = append(out, fmt.Sprintf("C %s %s dual_objective %s train %d/%d test %d/%d %s", fixed(c, 4),
			svInfo(m), fixed(dual, 6), correct(a.Train, m.trainingValues()), len(a.Train), correct(a.Test,
				decisions(m, a.Test)), len(a.Test), runInfo(m)))
	}
	return out
}
func (a *Application) learningOutput() []string {
	selected := a.Models[a.Selected]
	out := []string{fmt.Sprintf("learning_curve %s C %s", selected.Kernel.Name, fixed(selected.C, 4))}
	for _, fraction := range a.Params.Learning {
		s := len(a.Train) * fraction / 100
		indices := make([]int, s)
		for i := range indices {
			indices[i] = i
		}
		data, q := subset(a.Train, a.Matrices[a.Selected], indices)
		m := train(data, q, selected.Kernel, selected.C, a.Params)
		support, _, _ := m.counts()
		out = append(out, fmt.Sprintf("size %d support_vectors %d train %d/%d test %d/%d %s", s, support,
			correct(data, m.trainingValues()), s, correct(a.Test, decisions(m, a.Test)), len(a.Test),
			runInfo(m)))
	}
	return out
}

type Calibration struct {
	A, B          float64
	Probabilities []float64
	Lines         []string
}

func probability(v, a, b float64) float64 { return 1 / (1 + math.Exp(a*v+b)) }
func (a *Application) calibrate() Calibration {
	selected := a.Models[a.Selected]
	values := a.Grid[a.Selected][a.Best[a.Selected]].Values
	positive := 0
	for _, e := range a.Train {
		if e.Label == 1 {
			positive++
		}
	}
	negative := len(a.Train) - positive
	targets := make([]float64, len(values))
	for i, e := range a.Train {
		targets[i] = 1 / float64(negative+2)
		if e.Label == 1 {
			targets[i] = float64(positive+1) / float64(positive+2)
		}
	}
	out := Calibration{B: math.Log(float64(negative+1) / float64(positive+1))}
	nll := func() float64 {
		s := 0.0
		for i, v := range values {
			p := probability(v, out.A, out.B)
			s += targets[i]*math.Log(p) + (1-targets[i])*math.Log(1-p)
		}
		return -s
	}
	out.Lines = []string{fmt.Sprintf("calibration %s C %s positives %d negatives %d", selected.Kernel.Name,
		fixed(selected.C, 4), positive, negative), fmt.Sprintf("start A %s B %s nll %s", fixed(out.A,
		6), fixed(out.B, 6), fixed(nll(), 6))}
	for iteration := 1; iteration <= a.Params.Newton; iteration++ {
		g1, g2, h11, h21, h22 := 0.0, 0.0, 0.0, 0.0, 0.0
		for i, v := range values {
			p := probability(v, out.A, out.B)
			g1 += v * (targets[i] - p)
			g2 += targets[i] - p
			h11 += v * v * p * (1 - p)
			h21 += v * p * (1 - p)
			h22 += p * (1 - p)
		}
		det := h11*h22 - h21*h21
		da, db := (h22*g1-h21*g2)/det, (h11*g2-h21*g1)/det
		out.A -= da
		out.B -= db
		out.Lines = append(out.Lines, fmt.Sprintf("iteration %d A %s B %s nll %s", iteration, fixed(out.A, 6), fixed(out.B, 6), fixed(nll(), 6)))
	}
	logLoss, brier := 0.0, 0.0
	counts, positiveBins := [5]int{}, [5]int{}
	means := [5]float64{}
	for j, e := range a.Test {
		p := probability(a.TestValues[a.Selected][j], out.A, out.B)
		out.Probabilities = append(out.Probabilities, p)
		expected := 0.0
		if e.Label == 1 {
			logLoss += math.Log(p)
			expected = 1
		} else {
			logLoss += math.Log(1 - p)
		}
		d := p - expected
		brier += d * d
		bin := min(4, int(math.Floor(p*5)))
		counts[bin]++
		means[bin] += p
		if e.Label == 1 {
			positiveBins[bin]++
		}
	}
	out.Lines = append(out.Lines, fmt.Sprintf("test log_loss %s brier %s", fixed(-logLoss/float64(len(a.Test)), 6), fixed(brier/float64(len(a.Test)), 6)))
	ranges := []string{"0.0-0.2", "0.2-0.4", "0.4-0.6", "0.6-0.8", "0.8-1.0"}
	for bin, count := range counts {
		mean := "-"
		if count > 0 {
			mean = fixed(means[bin]/float64(count), 4)
		}
		out.Lines = append(out.Lines, fmt.Sprintf("bin %s count %d mean_probability %s positive_rate %s", ranges[bin], count, mean, ratio(positiveBins[bin], count)))
	}
	closest := make([]int, len(a.Test))
	for j := range closest {
		closest[j] = j
	}
	sort.Slice(closest, func(i, j int) bool {
		x, y := math.Abs(a.TestValues[a.Selected][closest[i]]), math.Abs(a.TestValues[a.Selected][closest[j]])
		if x != y {
			return x < y
		}
		return closest[i] < closest[j]
	})
	for _, j := range closest[:5] {
		out.Lines = append(out.Lines, fmt.Sprintf("closest %s label %d decision %s probability %s", a.Test[j].ID,
			a.Test[j].Label, fixed(a.TestValues[a.Selected][j], 4), fixed(out.Probabilities[j], 4)))
	}
	return out
}

type Pegasos struct {
	Weights, Average [3]float64
	Values           []float64
	Lines            []string
}

func linearValue(w [3]float64, p Point) float64 { return w[0]*p[0] + w[1]*p[1] + w[2] }
func linearValues(w [3]float64, data []Example) []float64 {
	v := make([]float64, len(data))
	for i, e := range data {
		v[i] = linearValue(w, e.Point)
	}
	return v
}
func (a *Application) pegasos() Pegasos {
	p := a.Params
	out := Pegasos{Lines: []string{fmt.Sprintf("pegasos lambda %s iterations %d seed %d", fixed(p.Lambda, 4), p.Iterations, p.Seed)}}
	state := int64(p.Seed)
	sums := [3]float64{}
	updates := 0
	n := len(a.Train)
	for t := 1; t <= p.Iterations; t++ {
		state = 48271 * state % 2147483647
		i := int(state % int64(n))
		e := a.Train[i]
		eta := 1 / (p.Lambda * float64(t))
		sigma := 1 - eta*p.Lambda
		violation := float64(e.Label)*linearValue(out.Weights, e.Point) < 1
		if violation {
			out.Weights[0] = sigma*out.Weights[0] + eta*float64(e.Label)*e.Point[0]
			out.Weights[1] = sigma*out.Weights[1] + eta*float64(e.Label)*e.Point[1]
			out.Weights[2] = sigma*out.Weights[2] + eta*float64(e.Label)
			updates++
		} else {
			for j := range out.Weights {
				out.Weights[j] = sigma * out.Weights[j]
			}
		}
		for j, v := range out.Weights {
			sums[j] += v
		}
		if t%(p.Iterations/10) == 0 {
			values := linearValues(out.Weights, a.Train)
			hinge := 0.0
			for i, e := range a.Train {
				hinge += math.Max(0, 1-float64(e.Label)*values[i])
			}
			w := out.Weights
			objective := p.Lambda/2*(w[0]*w[0]+w[1]*w[1]+w[2]*w[2]) + hinge/float64(n)
			out.Lines = append(out.Lines, fmt.Sprintf("checkpoint %d objective %s train %d/%d", t, fixed(objective, 6), correct(a.Train, values), n))
		}
	}
	for j, v := range sums {
		out.Average[j] = v / float64(p.Iterations)
	}
	out.Values = linearValues(out.Weights, a.Test)
	trainCorrect, testCorrect, averageCorrect := correct(a.Train, linearValues(out.Weights, a.Train)),
		correct(a.Test, out.Values), correct(a.Test, linearValues(out.Average, a.Test))
	comparison := 0
	for i, k := range p.Kernels {
		if k.Kind == "linear" {
			comparison = i
			break
		}
	}
	m := a.Models[comparison]
	v := Point{}
	for i, e := range a.Train {
		v[0] += m.Alpha[i] * float64(e.Label) * e.Point[0]
		v[1] += m.Alpha[i] * float64(e.Label) * e.Point[1]
	}
	w := out.Weights
	cosine := (w[0]*v[0] + w[1]*v[1]) / (math.Sqrt(w[0]*w[0]+w[1]*w[1]) * math.Sqrt(v[0]*v[0]+v[1]*v[1]))
	agreement := 0
	for j, f := range out.Values {
		if sign(f) == sign(a.TestValues[comparison][j]) {
			agreement++
		}
	}
	out.Lines = append(out.Lines, fmt.Sprint("updates ", updates), fmt.Sprintf("w %s %s bias %s", fixed(w[0],
		6), fixed(w[1], 6), fixed(w[2], 6)), fmt.Sprintf("train correct %d/%d accuracy %s", trainCorrect,
		n, ratio(trainCorrect, n)), fmt.Sprintf("test correct %d/%d accuracy %s", testCorrect, len(a.Test),
		ratio(testCorrect, len(a.Test))), fmt.Sprintf("average w %s %s bias %s test correct %d/%d",
		fixed(out.Average[0], 6), fixed(out.Average[1], 6), fixed(out.Average[2], 6), averageCorrect,
		len(a.Test)), fmt.Sprintf("compare %s cosine %s test_agreement %d/%d", p.Kernels[comparison].Name,
		fixed(cosine, 6), agreement, len(a.Test)))
	return out
}
func (a *Application) mcnemar(peg Pegasos) []string {
	out := []string{"mcnemar"}
	names := []string{}
	values := append([][]float64(nil), a.TestValues...)
	for _, k := range a.Params.Kernels {
		names = append(names, k.Name)
	}
	names = append(names, "pegasos")
	values = append(values, peg.Values)
	for i := range names {
		for j := i + 1; j < len(names); j++ {
			first, second := 0, 0
			for k, e := range a.Test {
				x, y := sign(values[i][k]) == e.Label, sign(values[j][k]) == e.Label
				if x && !y {
					first++
				}
				if y && !x {
					second++
				}
			}
			chi := "-"
			if first+second > 0 {
				difference := first - second
				if difference < 0 {
					difference = -difference
				}
				numerator := (difference - 1) * (difference - 1)
				chi = fixed(float64(numerator)/float64(first+second), 4)
			}
			out = append(out, fmt.Sprintf("%s %s only_first %d only_second %d chi2 %s", names[i], names[j], first, second, chi))
		}
	}
	return out
}
func multiclassOutput(model Multiclass, k Kernel, c float64, trainData, testData []Example) {
	out := []string{fmt.Sprintf("multiclass kernel %s C %s classes 3 train %d test %d", k.Name, fixed(c, 4), len(trainData), len(testData)), "ovr"}
	for i, m := range model.Rest {
		positive, testCorrect := 0, 0
		for _, e := range m.Data {
			if e.Label == 1 {
				positive++
			}
		}
		for _, e := range testData {
			label := -1
			if e.Label == i+1 {
				label = 1
			}
			if sign(m.decision(e.Point)) == label {
				testCorrect++
			}
		}
		out = append(out, fmt.Sprintf("model %d-rest examples %d positives %d %s b %s %s test %d/%d", i+1,
			len(m.Data), positive, svInfo(m), fixed(m.B, 6), runInfo(m), testCorrect, len(testData)))
	}
	out = append(out, "ovo")
	for i, m := range model.Pair {
		pair := classPairs[i]
		positive, testCorrect, testCount := 0, 0, 0
		for _, e := range m.Data {
			if e.Label == 1 {
				positive++
			}
		}
		for _, e := range testData {
			if e.Label != pair[0] && e.Label != pair[1] {
				continue
			}
			testCount++
			label := -1
			if e.Label == pair[0] {
				label = 1
			}
			if sign(m.decision(e.Point)) == label {
				testCorrect++
			}
		}
		out = append(out, fmt.Sprintf("model %d-%d examples %d positives %d %s b %s %s test %d/%d", pair[0],
			pair[1], len(m.Data), positive, svInfo(m), fixed(m.B, 6), runInfo(m), testCorrect, testCount))
	}
	out = append(out, "predictions")
	testPredictions := make([]MultiPrediction, len(testData))
	for i, e := range testData {
		p := model.classify(e.Point)
		testPredictions[i] = p
		out = append(out, fmt.Sprintf("%s class %d ovr %s %s %s pred %d ovo %s %s %s votes %d %d %d pred %d",
			e.ID, e.Label, fixed(p.Rest[0], 4), fixed(p.Rest[1], 4), fixed(p.Rest[2], 4), p.OVR,
			fixed(p.Pair[0], 4), fixed(p.Pair[1], 4), fixed(p.Pair[2], 4), p.Votes[0], p.Votes[1],
			p.Votes[2], p.OVO))
	}
	for index, data := range [][]Example{trainData, testData} {
		ovr, ovo, agreement, ties := 0, 0, 0, 0
		for _, e := range data {
			p := model.classify(e.Point)
			if p.OVR == e.Label {
				ovr++
			}
			if p.OVO == e.Label {
				ovo++
			}
			if p.OVR == p.OVO {
				agreement++
			}
			if p.Tie {
				ties++
			}
		}
		name := "train"
		if index == 1 {
			name = "test"
		}
		n := len(data)
		out = append(out, fmt.Sprintf("%s ovr %d/%d %s ovo %d/%d %s agreement %d/%d vote_ties %d", name,
			ovr, n, ratio(ovr, n), ovo, n, ratio(ovo, n), agreement, n, ties))
	}
	for index, name := range []string{"ovr", "ovo"} {
		predictions := make([]int, len(testData))
		for i, p := range testPredictions {
			predictions[i] = p.OVR
			if index == 1 {
				predictions[i] = p.OVO
			}
		}
		matrix := confusion(testData, predictions)
		out = append(out, "confusion "+name)
		for _, row := range matrix {
			out = append(out, fmt.Sprintf("%d %d %d", row[0], row[1], row[2]))
		}
		for cl := 0; cl < 3; cl++ {
			column, row := 0, 0
			for j := 0; j < 3; j++ {
				column += matrix[j][cl]
				row += matrix[cl][j]
			}
			out = append(out, fmt.Sprintf("class %d precision %s recall %s", cl+1, ratio(matrix[cl][cl], column), ratio(matrix[cl][cl], row)))
		}
	}
	writeLines("multiclass.txt", out)
}
func framed(grid [][]byte) []string {
	w := len(grid[0])
	out := []string{"+" + strings.Repeat("-", w) + "+"}
	for _, row := range grid {
		out = append(out, "|"+string(row)+"|")
	}
	return append(out, "+"+strings.Repeat("-", w)+"+")
}
func (a *Application) plots(cal Calibration, multi Multiclass, multiKernel Kernel, multiData []Example) {
	p := a.Params
	selected := a.Models[a.Selected]
	dx, dy := (p.XMax-p.XMin)/float64(p.W), (p.YMax-p.YMin)/float64(p.H)
	binary, probabilities, multiplot := make([][]byte, p.H), make([][]byte, p.H), make([][]byte, p.H)
	gridSigns := make([][]int, len(a.Models))
	positiveCounts := make([]int, len(a.Models))
	for i := range gridSigns {
		gridSigns[i] = make([]int, p.W*p.H)
	}
	levels := [10]int{}
	for r := 0; r < p.H; r++ {
		binary[r], probabilities[r], multiplot[r] = make([]byte, p.W), make([]byte, p.W), make([]byte, p.W)
		for c := 0; c < p.W; c++ {
			point := Point{p.XMin + (float64(c)+.5)*dx, p.YMax - (float64(r)+.5)*dy}
			value := selected.decision(point)
			ch := byte(' ')
			if value >= 1 {
				ch = '+'
			} else if value > 0 {
				ch = '.'
			} else if value > -1 {
				ch = '-'
			}
			binary[r][c] = ch
			level := min(9, int(math.Floor(probability(value, cal.A, cal.B)*10)))
			probabilities[r][c] = byte('0' + level)
			levels[level]++
			for i, m := range a.Models {
				sgn := sign(m.decision(point))
				gridSigns[i][r*p.W+c] = sgn
				if sgn == 1 {
					positiveCounts[i]++
				}
			}
			mp := multi.classify(point)
			ch = '?'
			if mp.OVR == mp.OVO {
				ch = []byte{' ', '.', ':'}[mp.OVR-1]
			}
			multiplot[r][c] = ch
		}
	}
	position := func(point Point) (int, bool) {
		c := int(math.Floor((point[0] - p.XMin) / dx))
		r := int(math.Floor((p.YMax - point[1]) / dy))
		return r*p.W + c, r >= 0 && r < p.H && c >= 0 && c < p.W
	}
	owners := make([]int, p.W*p.H)
	for i := range owners {
		owners[i] = -1
	}
	outside, points := 0, 0
	for i, e := range a.Train {
		index, inside := position(e.Point)
		if !inside {
			outside++
			continue
		}
		old := owners[index]
		if old < 0 || (selected.Alpha[i] > 0 && selected.Alpha[old] == 0) {
			owners[index] = i
		}
	}
	for index, i := range owners {
		if i < 0 {
			continue
		}
		points++
		ch := byte('o')
		if a.Train[i].Label == 1 {
			ch = 'x'
		}
		if selected.Alpha[i] > 0 {
			if ch == 'x' {
				ch = 'X'
			} else {
				ch = 'O'
			}
		}
		binary[index/p.W][index%p.W] = ch
	}
	counts := map[byte]int{}
	for _, row := range binary {
		for _, ch := range row {
			counts[ch]++
		}
	}
	out := []string{fmt.Sprintf("binary %s C %s", selected.Kernel.Name, fixed(selected.C, 4)), fmt.Sprintf("x %s %s y %s %s grid %dx%d",
		fixed(p.XMin, 4), fixed(p.XMax, 4), fixed(p.YMin, 4), fixed(p.YMax, 4), p.W, p.H)}
	out = append(out, framed(binary)...)
	out = append(out, fmt.Sprintf("cells outer_positive %d inner_positive %d inner_negative %d outer_negative %d points %d outside %d",
		counts['+'], counts['.'], counts['-'], counts[' '], points, outside), "", fmt.Sprintf("probability %s A %s B %s",
		selected.Kernel.Name, fixed(cal.A, 6), fixed(cal.B, 6)))
	out = append(out, framed(probabilities)...)
	levelLine := []string{"levels"}
	for _, count := range levels {
		levelLine = append(levelLine, fmt.Sprint(count))
	}
	out = append(out, strings.Join(levelLine, " "), "", "grid_agreement")
	for i, k := range p.Kernels {
		for j := i + 1; j < len(p.Kernels); j++ {
			agreement := 0
			for index, v := range gridSigns[i] {
				if v == gridSigns[j][index] {
					agreement++
				}
			}
			out = append(out, fmt.Sprintf("%s %s %d/%d positive %d %d", k.Name, p.Kernels[j].Name, agreement, p.W*p.H, positiveCounts[i], positiveCounts[j]))
		}
	}
	for i := range owners {
		owners[i] = -1
	}
	outside, points = 0, 0
	for i, e := range multiData {
		index, inside := position(e.Point)
		if !inside {
			outside++
			continue
		}
		if owners[index] < 0 {
			owners[index] = i
		}
	}
	for index, i := range owners {
		if i >= 0 {
			points++
			multiplot[index/p.W][index%p.W] = byte('0' + multiData[i].Label)
		}
	}
	counts = map[byte]int{}
	for _, row := range multiplot {
		for _, ch := range row {
			counts[ch]++
		}
	}
	out = append(out, "", fmt.Sprintf("multiclass %s C %s", multiKernel.Name, fixed(p.MulticlassC, 4)))
	out = append(out, framed(multiplot)...)
	out = append(out, fmt.Sprintf("cells class1 %d class2 %d class3 %d disagree %d points %d outside %d",
		counts[' '], counts['.'], counts[':'], counts['?'], points, outside))
	writeLines("decision_plot.txt", out)
}
func (a *Application) predictionsOutput(cal Calibration, peg Pegasos) {
	header := []string{"id", "label"}
	for _, k := range a.Params.Kernels {
		header = append(header, k.Name)
	}
	header = append(header, "pegasos", "predicted", "probability")
	out := []string{strings.Join(header, ",")}
	for i, e := range a.Test {
		row := []string{e.ID, fmt.Sprint(e.Label)}
		for _, values := range a.TestValues {
			row = append(row, fixed(values[i], 4))
		}
		row = append(row, fixed(peg.Values[i], 4), fmt.Sprint(sign(a.TestValues[a.Selected][i])), fixed(cal.Probabilities[i], 4))
		out = append(out, strings.Join(row, ","))
	}
	writeLines("predictions.csv", out)
}
func main() {
	a := Application{Train: readExamples("input/train.csv"), Test: readExamples("input/test.csv"), Params: readParams()}
	a.prepare()
	parts := [][]string{a.cvOutput()}
	for i := range a.Params.Kernels {
		parts = append(parts, a.modelOutput(i))
	}
	parts = append(parts, a.progressOutput(), a.pathOutput(), a.learningOutput())
	cal := a.calibrate()
	peg := a.pegasos()
	parts = append(parts, cal.Lines, peg.Lines, a.mcnemar(peg))
	out := []string{}
	for i, part := range parts {
		if i > 0 {
			out = append(out, "")
		}
		out = append(out, part...)
	}
	writeLines("model.txt", out)
	a.predictionsOutput(cal, peg)
	multiTrain, multiTest := readMulticlass()
	var kernel Kernel
	for _, k := range a.Params.Kernels {
		if k.Name == a.Params.Multiclass {
			kernel = k
			break
		}
	}
	multi := trainMulticlass(multiTrain, kernel, a.Params.MulticlassC, a.Params)
	multiclassOutput(multi, kernel, a.Params.MulticlassC, multiTrain, multiTest)
	a.plots(cal, multi, kernel, multiTrain)
}
