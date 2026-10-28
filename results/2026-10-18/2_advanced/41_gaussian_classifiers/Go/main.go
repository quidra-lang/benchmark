package main

import (
	"fmt"
	"math"
	"sort"
	"strings"
)

type CrossValidation struct {
	Predictions, FoldCorrect []int
	Correct                  int
}
type Analysis struct {
	Data                                           Dataset
	N, M, D, C                                     int
	All, TrainActual, TestActual, Folds, FoldSizes []int
	Upper, Lower                                   []byte
	Models                                         []*GaussianModel
	Results                                        [][]Prediction
	Predictions                                    [][]int
	Cache                                          map[string]CrossValidation
}

func newAnalysis(data Dataset) *Analysis {
	a := &Analysis{Data: data, N: len(data.Train), M: len(data.Test), D: len(data.Features), C: len(data.Classes), Cache: map[string]CrossValidation{}}
	for j := 0; j < a.D; j++ {
		a.All = append(a.All, j)
	}
	a.FoldSizes = make([]int, data.Params.Folds)
	for _, row := range data.Train {
		a.TrainActual = append(a.TrainActual, row.Class)
		f := row.ID % data.Params.Folds
		a.Folds = append(a.Folds, f)
		a.FoldSizes[f]++
	}
	for _, row := range data.Test {
		a.TestActual = append(a.TestActual, row.Class)
	}
	for _, name := range data.Classes {
		a.Lower = append(a.Lower, name[0])
		a.Upper = append(a.Upper, name[0]-32)
	}
	for _, name := range modelNames {
		m := a.fit(name, a.All, data.Train)
		a.Models = append(a.Models, m)
		results := []Prediction{}
		pred := []int{}
		for _, r := range data.Test {
			p := m.infer(r.Values, data.Costs)
			results = append(results, p)
			pred = append(pred, p.Predicted)
		}
		a.Results = append(a.Results, results)
		a.Predictions = append(a.Predictions, pred)
	}
	return a
}
func (a *Analysis) fit(name string, features []int, rows []Row) *GaussianModel {
	p := a.Data.Params
	return trainModel(rows, features, a.C, name, p.Prior, p.Epsilon, p.Gamma)
}
func (a *Analysis) cv(name string, features []int, epsilon, gamma float64) CrossValidation {
	key := fmt.Sprintf("%s|%v|%g|%g", name, features, epsilon, gamma)
	if r, ok := a.Cache[key]; ok {
		return r
	}
	r := CrossValidation{Predictions: make([]int, a.N), FoldCorrect: make([]int, a.Data.Params.Folds)}
	for f := range r.FoldCorrect {
		rows := []Row{}
		for i, row := range a.Data.Train {
			if a.Folds[i] != f {
				rows = append(rows, row)
			}
		}
		model := trainModel(rows, features, a.C, name, a.Data.Params.Prior, epsilon, gamma)
		for i, row := range a.Data.Train {
			if a.Folds[i] == f {
				r.Predictions[i] = model.predict(row.Values)
				if r.Predictions[i] == row.Class {
					r.FoldCorrect[f]++
					r.Correct++
				}
			}
		}
	}
	a.Cache[key] = r
	return r
}
func (a *Analysis) crossValidate(name string, features []int) CrossValidation {
	return a.cv(name, features, a.Data.Params.Epsilon, a.Data.Params.Gamma)
}
func (a *Analysis) featureNames(features []int) string {
	names := []string{}
	for _, f := range features {
		names = append(names, a.Data.Features[f])
	}
	return strings.Join(names, " ")
}
func correctCount(model *GaussianModel, rows []Row) int {
	n := 0
	for _, r := range rows {
		if model.predict(r.Values) == r.Class {
			n++
		}
	}
	return n
}
func confusionLines(classes []string, m [][]int) []string {
	lines := []string{}
	for i, name := range classes {
		lines = append(lines, "confusion "+name+" "+ints(m[i]))
	}
	return lines
}
func comparisonLines(title string, names []string, predictions [][]int, actual []int) []string {
	lines := []string{title}
	for i := 0; i < len(names); i++ {
		for j := i + 1; j < len(names); j++ {
			b01, b10, chi := mcnemar(actual, predictions[i], predictions[j])
			sig := "no"
			if chi > 3.841 {
				sig = "yes"
			}
			lines = append(lines, fmt.Sprintf("%s %s b01 %d b10 %d chi2 %s significant %s", names[i], names[j], b01, b10, real(chi), sig))
		}
	}
	return lines
}

type DistanceRow struct {
	Distance     float64
	Index, Class int
	Row          Row
}

func orderDistances(rows []DistanceRow) {
	sort.SliceStable(rows, func(i, j int) bool { return rows[i].Distance > rows[j].Distance })
}
func (a *Analysis) modelSections() [][]string {
	nb, lda, qda := a.Models[0], a.Models[1], a.Models[2]
	s := nb.Stats
	sections := [][]string{}
	lines := []string{"features " + strings.Join(a.Data.Features, " "), "classes " + strings.Join(a.Data.Classes, " "), "prior_mode " + a.Data.Params.Prior}
	for k, name := range a.Data.Classes {
		lines = append(lines, fmt.Sprintf("class %s letter %c count %d prior %s mean %s", name, a.Upper[k], s.Counts[k], real(nb.Priors[k]), reals(s.Means[k])))
	}
	sections = append(sections, lines)
	lines = []string{"model NB", fmt.Sprintf("smoothing epsilon %s max_variance %s added %s", real(nb.Epsilon), real(nb.MaxVariance), real(nb.Added))}
	for k, name := range a.Data.Classes {
		diag := make([]float64, a.D)
		for j := range diag {
			diag[j] = nb.Covariances[k][j][j]
		}
		lines = append(lines, fmt.Sprintf("class %s variance %s log_det %s", name, reals(diag), real(nb.LogDets[k])))
	}
	sections = append(sections, lines)
	lower := lda.Factors[0]
	lines = []string{"model LDA", "log_det " + real(lda.LogDets[0])}
	for _, r := range lda.Covariances[0] {
		lines = append(lines, "  "+reals(r))
	}
	for k, name := range a.Data.Classes {
		coef := backward(lower, forward(lower, s.Means[k]))
		intercept := math.Log(lda.Priors[k]) - dot(s.Means[k], coef)/2
		lines = append(lines, fmt.Sprintf("class %s intercept %s coef %s", name, real(intercept), reals(coef)))
	}
	sections = append(sections, lines)
	lines = []string{"model QDA gamma " + real(qda.Gamma)}
	for k, name := range a.Data.Classes {
		e := jacobi(qda.Covariances[k]).Values
		sort.Sort(sort.Reverse(sort.Float64Slice(e)))
		lines = append(lines, fmt.Sprintf("class %s log_det %s eigenvalues %s condition %s", name, real(qda.LogDets[k]), reals(e), real(e[0]/e[len(e)-1])))
		for _, r := range qda.Covariances[k] {
			lines = append(lines, "  "+reals(r))
		}
	}
	sections = append(sections, lines)
	lines = []string{"separation"}
	for i := 0; i < a.C; i++ {
		for j := i + 1; j < a.C; j++ {
			delta := make([]float64, a.D)
			for f := range delta {
				delta[f] = s.Means[i][f] - s.Means[j][f]
			}
			average := zeros(a.D)
			for r := range average {
				for c := range average[r] {
					average[r][c] = (qda.Covariances[i][r][c] + qda.Covariances[j][r][c]) / 2
				}
			}
			l := cholesky(average)
			bh := quadratic(l, delta)/8 + (logDet(l)-(qda.LogDets[i]+qda.LogDets[j])/2)/2
			lines = append(lines, fmt.Sprintf("%s %s mahalanobis %s bhattacharyya %s", a.Data.Classes[i], a.Data.Classes[j],
				real(math.Sqrt(quadratic(lower, delta))), real(bh)))
		}
	}
	sections = append(sections, lines)
	outliers := []DistanceRow{}
	for i, row := range a.Data.Train {
		q := qda.distances(row.Values)[row.Class]
		if q > a.Data.Params.Outlier {
			outliers = append(outliers, DistanceRow{q, i, row.Class, row})
		}
	}
	orderDistances(outliers)
	lines = []string{"outliers threshold " + real(a.Data.Params.Outlier)}
	for _, r := range outliers {
		lines = append(lines, fmt.Sprintf("%d %s q %s", r.Row.ID, r.Row.Label, real(r.Distance)))
	}
	lines = append(lines, fmt.Sprintf("count %d", len(outliers)))
	return append(sections, lines)
}
func (a *Analysis) predictionLines() []string {
	lines := []string{"id,model,actual,predicted,decision," + strings.Join(a.Data.Classes, ",")}
	for i, row := range a.Data.Test {
		for k, name := range modelNames {
			r := a.Results[k][i]
			fields := []string{fmt.Sprint(row.ID), name, row.Label, a.Data.Classes[r.Predicted], a.Data.Classes[r.Decision]}
			for _, p := range r.Posterior {
				fields = append(fields, real(p))
			}
			lines = append(lines, strings.Join(fields, ","))
		}
	}
	return lines
}
func (a *Analysis) modelEvaluation(k int) []string {
	results := a.Results[k]
	m := measures(a.TestActual, a.Predictions[k], a.C)
	lines := []string{"model " + modelNames[k]}
	lines = append(lines, confusionLines(a.Data.Classes, m.Matrix)...)
	lines = append(lines, "accuracy "+fractionText(m.Accuracy), "balanced_accuracy "+fractionText(m.Balanced), "kappa "+fractionText(m.Kappa))
	for c, name := range a.Data.Classes {
		lines = append(lines, fmt.Sprintf("class %s support %d recall %s precision %s f1 %s", name, m.Support[c],
			fractionText(m.Recall[c]), fractionText(m.Precision[c]), fractionText(m.F1[c])))
	}
	loss := 0.0
	errors := []string{}
	for i, row := range a.Data.Test {
		r := results[i]
		loss += r.LogPosterior[row.Class]
		if r.Predicted != row.Class {
			errors = append(errors, fmt.Sprintf("error %d actual %s predicted %s confidence %s", row.ID, row.Label, a.Data.Classes[r.Predicted], real(r.Confidence)))
		}
	}
	lines = append(lines, "macro_f1 "+real(m.MacroF1), "log_loss "+real(-loss/float64(a.M)), fmt.Sprintf("errors %d", len(errors)))
	lines = append(lines, errors...)
	edges := append([]float64{0}, a.Data.Params.Edges...)
	edges = append(edges, 1)
	ece := 0.0
	for bin := 0; bin < len(edges)-1; bin++ {
		lo, hi := edges[bin], edges[bin+1]
		count, correct := 0, 0
		conf := 0.0
		for i, r := range results {
			if r.Confidence >= lo && (r.Confidence < hi || (bin == len(edges)-2 && r.Confidence == hi)) {
				count++
				conf += r.Confidence
				if r.Predicted == a.TestActual[i] {
					correct++
				}
			}
		}
		text := "-"
		if count > 0 {
			text = real(conf / float64(count))
		}
		lines = append(lines, fmt.Sprintf("bin %s %s count %d confidence %s accuracy %s", real(lo), real(hi), count, text, ratio(correct, count)))
		ece += math.Abs(float64(correct) - conf)
	}
	lines = append(lines, "ece "+real(ece/float64(a.M)))
	for _, threshold := range a.Data.Params.Reject {
		count, correct := 0, 0
		for i, r := range results {
			if r.Confidence >= threshold {
				count++
				if r.Predicted == a.TestActual[i] {
					correct++
				}
			}
		}
		lines = append(lines, fmt.Sprintf("reject %s accepted %d coverage %s accuracy %s", real(threshold), count, ratio(count, a.M), ratio(correct, count)))
	}
	return lines
}
func (a *Analysis) ensemble() []int {
	pred := make([]int, a.M)
	for i := range pred {
		p := make([]float64, a.C)
		for k := range p {
			for m := 0; m < 3; m++ {
				p[k] += a.Results[m][i].Posterior[k]
			}
			p[k] /= 3
		}
		pred[i] = argmax(p)
	}
	return pred
}
func (a *Analysis) costLines() []string {
	lines := []string{"costs"}
	for k, name := range modelNames {
		total, decision := 0.0, 0.0
		changed, correct := 0, 0
		for i, r := range a.Results[k] {
			y := a.TestActual[i]
			total += a.Data.Costs[y][r.Predicted]
			decision += a.Data.Costs[y][r.Decision]
			if r.Decision != r.Predicted {
				changed++
			}
			if r.Decision == y {
				correct++
			}
		}
		lines = append(lines, fmt.Sprintf("%s argmax_total %s decision_total %s changed %d decision_accuracy %s",
			name, real(total), real(decision), changed, ratio(correct, a.M)))
	}
	return lines
}
func (a *Analysis) noveltyLines() []string {
	novel := []DistanceRow{}
	for i, row := range a.Data.Test {
		q := a.Models[2].distances(row.Values)
		k := argmin(q)
		if q[k] > a.Data.Params.Outlier {
			novel = append(novel, DistanceRow{q[k], i, k, row})
		}
	}
	orderDistances(novel)
	lines := []string{"novelty threshold " + real(a.Data.Params.Outlier)}
	for _, r := range novel {
		lines = append(lines, fmt.Sprintf("%d nearest %s q %s", r.Row.ID, a.Data.Classes[r.Class], real(r.Distance)))
	}
	return append(lines, fmt.Sprintf("count %d", len(novel)))
}
func (a *Analysis) bootstrapLines() []string {
	count := a.Data.Params.Bootstrap
	rng := RandomGenerator{a.Data.Params.Seed}
	samples := make([][]int, 3)
	for k := range samples {
		samples[k] = make([]int, count)
	}
	for b := 0; b < count; b++ {
		for i := 0; i < a.M; i++ {
			j := int(rng.draw() % int64(a.M))
			for k := 0; k < 3; k++ {
				if a.Predictions[k][j] == a.TestActual[j] {
					samples[k][b]++
				}
			}
		}
	}
	lines := []string{fmt.Sprintf("bootstrap resamples %d seed %d", count, a.Data.Params.Seed)}
	offset := count / 40
	for k, name := range modelNames {
		ordered := append([]int{}, samples[k]...)
		sort.Ints(ordered)
		total := 0
		for _, n := range ordered {
			total += n
		}
		mean := float64(total) / float64(count) / float64(a.M)
		lines = append(lines, fmt.Sprintf("%s mean %s interval %s %s", name, real(mean), ratio(ordered[offset], a.M), ratio(ordered[count-offset-1], a.M)))
	}
	for i := 0; i < 3; i++ {
		for j := i + 1; j < 3; j++ {
			wins, ties := 0, 0
			for b := 0; b < count; b++ {
				if samples[i][b] > samples[j][b] {
					wins++
				} else if samples[i][b] == samples[j][b] {
					ties++
				}
			}
			lines = append(lines, fmt.Sprintf("%s %s wins %d ties %d losses %d", modelNames[i], modelNames[j], wins, ties, count-wins-ties))
		}
	}
	return lines
}
func (a *Analysis) priorLines() []string {
	p := a.Data.Params
	alternative := "empirical"
	if p.Prior == "empirical" {
		alternative = "uniform"
	}
	lines := []string{"prior_sensitivity alternative " + alternative}
	for k, name := range modelNames {
		model := trainModel(a.Data.Train, a.All, a.C, name, alternative, p.Epsilon, p.Gamma)
		pred := make([]int, a.M)
		changed := 0
		for i, row := range a.Data.Test {
			pred[i] = model.predict(row.Values)
			if pred[i] != a.Predictions[k][i] {
				changed++
			}
		}
		m := measures(a.TestActual, pred, a.C)
		lines = append(lines, fmt.Sprintf("%s accuracy %s balanced_accuracy %s changed %d", name, fractionText(m.Accuracy), fractionText(m.Balanced), changed))
	}
	return lines
}
func (a *Analysis) learningLines() []string {
	lines := []string{"learning_curve"}
	for _, size := range a.Data.Params.Curve {
		taken := make([]int, a.C)
		rows := []Row{}
		for _, r := range a.Data.Train {
			if taken[r.Class] < size {
				rows = append(rows, r)
				taken[r.Class]++
			}
		}
		line := fmt.Sprintf("size %d rows %d", size, len(rows))
		for _, name := range modelNames {
			line += " " + name + " " + ratio(correctCount(a.fit(name, a.All, rows), a.Data.Test), a.M)
		}
		lines = append(lines, line)
	}
	return lines
}
func (a *Analysis) subsetLines() []string {
	lines := []string{fmt.Sprintf("cross_validation folds %d", a.Data.Params.Folds), "fold_sizes " + ints(a.FoldSizes)}
	bestSubset, bestModel, bestCorrect := 0, 0, -1
	for i, s := range a.Data.Params.Subsets {
		lines = append(lines, "subset "+s.Name+" features "+a.featureNames(s.Features))
		for k, name := range modelNames {
			r := a.crossValidate(name, s.Features)
			lines = append(lines, fmt.Sprintf("  %s fold_correct %s correct %d accuracy %s", name, ints(r.FoldCorrect), r.Correct, ratio(r.Correct, a.N)))
			if r.Correct > bestCorrect || (r.Correct == bestCorrect && len(s.Features) < len(a.Data.Params.Subsets[bestSubset].Features)) {
				bestSubset, bestModel, bestCorrect = i, k, r.Correct
			}
		}
	}
	s := a.Data.Params.Subsets[bestSubset]
	name := modelNames[bestModel]
	lines = append(lines, fmt.Sprintf("best subset %s model %s correct %d accuracy %s", s.Name, name, bestCorrect, ratio(bestCorrect, a.N)))
	correct := correctCount(a.fit(name, s.Features, a.Data.Train), a.Data.Test)
	return append(lines, fmt.Sprintf("refit_test correct %d accuracy %s", correct, ratio(correct, a.M)))
}
func (a *Analysis) looLines() []string {
	lines := []string{"leave_one_out"}
	for _, name := range modelNames {
		correct := 0
		for i, row := range a.Data.Train {
			rows := make([]Row, 0, a.N-1)
			rows = append(rows, a.Data.Train[:i]...)
			rows = append(rows, a.Data.Train[i+1:]...)
			if a.fit(name, a.All, rows).predict(row.Values) == row.Class {
				correct++
			}
		}
		lines = append(lines, fmt.Sprintf("%s correct %d accuracy %s", name, correct, ratio(correct, a.N)))
	}
	return lines
}
func (a *Analysis) forwardSections() [][]string {
	sections := [][]string{}
	for _, name := range modelNames {
		lines := []string{"forward_selection model " + name}
		selected := []int{}
		used := make([]bool, a.D)
		bestStep, bestCorrect := 0, -1
		for step := 1; step <= a.D; step++ {
			added, stepCorrect := 0, -1
			for _, f := range a.All {
				if used[f] {
					continue
				}
				features := append(append([]int{}, selected...), f)
				r := a.crossValidate(name, features)
				if r.Correct > stepCorrect {
					added, stepCorrect = f, r.Correct
				}
			}
			selected = append(selected, added)
			used[added] = true
			lines = append(lines, fmt.Sprintf("step %d add %s correct %d accuracy %s", step, a.Data.Features[added], stepCorrect, ratio(stepCorrect, a.N)))
			if stepCorrect > bestCorrect {
				bestStep, bestCorrect = step, stepCorrect
			}
		}
		lines = append(lines, fmt.Sprintf("best_step %d features %s", bestStep, a.featureNames(selected[:bestStep])))
		sections = append(sections, lines)
	}
	return sections
}
func (a *Analysis) tuningLines(name string, values []float64, title string) []string {
	lines := []string{title}
	p := a.Data.Params
	bestValue := 0.0
	bestCorrect := -1
	for _, v := range values {
		epsilon, gamma := p.Epsilon, p.Gamma
		if name == "NB" {
			epsilon = v
		} else {
			gamma = v
		}
		r := a.cv(name, a.All, epsilon, gamma)
		lines = append(lines, fmt.Sprintf("value %s correct %d accuracy %s", real(v), r.Correct, ratio(r.Correct, a.N)))
		if r.Correct >= bestCorrect {
			bestValue, bestCorrect = v, r.Correct
		}
	}
	epsilon, gamma := p.Epsilon, p.Gamma
	if name == "NB" {
		epsilon = bestValue
	} else {
		gamma = bestValue
	}
	model := trainModel(a.Data.Train, a.All, a.C, name, p.Prior, epsilon, gamma)
	correct := correctCount(model, a.Data.Test)
	return append(lines, fmt.Sprintf("best %s test correct %d accuracy %s", real(bestValue), correct, ratio(correct, a.M)))
}
func (a *Analysis) evaluationSections() [][]string {
	sections := [][]string{{fmt.Sprintf("test rows %d", a.M)}}
	for k := 0; k < 3; k++ {
		sections = append(sections, a.modelEvaluation(k))
	}
	ensemble := a.ensemble()
	m := measures(a.TestActual, ensemble, a.C)
	sections = append(sections, []string{"ensemble soft_vote", fmt.Sprintf("accuracy %s balanced_accuracy %s kappa %s",
		fractionText(m.Accuracy), fractionText(m.Balanced), fractionText(m.Kappa))})
	predictions := append(append([][]int{}, a.Predictions...), ensemble)
	names := append(append([]string{}, modelNames...), "ENSEMBLE")
	sections = append(sections, comparisonLines("mcnemar test", names, predictions, a.TestActual), a.costLines(),
		a.noveltyLines(), a.bootstrapLines(), a.priorLines(), a.learningLines(), a.subsetLines())
	cv := []CrossValidation{}
	predictions = [][]int{}
	for _, name := range modelNames {
		r := a.crossValidate(name, a.All)
		cv = append(cv, r)
		predictions = append(predictions, r.Predictions)
	}
	sections = append(sections, comparisonLines("mcnemar cross_validation", modelNames, predictions, a.TrainActual))
	for k, name := range modelNames {
		m := measures(a.TrainActual, cv[k].Predictions, a.C)
		lines := []string{"cv_confusion model " + name}
		lines = append(lines, confusionLines(a.Data.Classes, m.Matrix)...)
		lines = append(lines, fmt.Sprintf("balanced_accuracy %s kappa %s", fractionText(m.Balanced), fractionText(m.Kappa)))
		sections = append(sections, lines)
	}
	sections = append(sections, a.looLines())
	sections = append(sections, a.forwardSections()...)
	return append(sections, a.tuningLines("NB", a.Data.Params.Smoothing, "nb_smoothing_path"), a.tuningLines("QDA", a.Data.Params.GammaGrid, "qda_gamma_path"))
}
func pointGrid(points [][2]float64, actual []int, letters []byte, limits [4]float64, size [2]int) [][]byte {
	w, h := size[0], size[1]
	grid := make([][]byte, h)
	for r := range grid {
		grid[r] = []byte(strings.Repeat(" ", w))
	}
	for i, p := range points {
		c := cell(p[0], limits[0], limits[1], w)
		r := h - 1 - cell(p[1], limits[2], limits[3], h)
		letter := letters[actual[i]]
		if grid[r][c] == ' ' || grid[r][c] == letter {
			grid[r][c] = letter
		} else {
			grid[r][c] = '*'
		}
	}
	return grid
}
func pointLimits(points [][2]float64) [4]float64 {
	v := [4]float64{points[0][0], points[0][0], points[0][1], points[0][1]}
	for _, p := range points[1:] {
		v[0] = math.Min(v[0], p[0])
		v[1] = math.Max(v[1], p[0])
		v[2] = math.Min(v[2], p[1])
		v[3] = math.Max(v[3], p[1])
	}
	return v
}
func (a *Analysis) boundarySections() [][]string {
	sections := [][]string{}
	w, h := a.Data.Params.MapSize[0], a.Data.Params.MapSize[1]
	for _, pair := range a.Data.Params.Pairs {
		fx, fy := pair[0], pair[1]
		points := make([][2]float64, a.N)
		for i, r := range a.Data.Train {
			points[i] = [2]float64{r.Values[fx], r.Values[fy]}
		}
		limits := pointLimits(points)
		xmin, xmax, ymin, ymax := limits[0], limits[1], limits[2], limits[3]
		dx, dy := (xmax-xmin)/float64(w-1), (ymax-ymin)/float64(h-1)
		lines := []string{"pair " + a.Data.Features[fx] + " " + a.Data.Features[fy], fmt.Sprintf("x %s %s %s y %s %s %s grid %dx%d",
			a.Data.Features[fx], real(xmin), real(xmax), a.Data.Features[fy], real(ymin), real(ymax),
			w, h)}
		all := make([][][]Prediction, 3)
		for k, name := range modelNames {
			features := []int{fx, fy}
			model := a.fit(name, features, a.Data.Train)
			cv := a.crossValidate(name, features)
			lines = append(lines, fmt.Sprintf("model %s train_accuracy %s cv_accuracy %s", name, ratio(correctCount(model, a.Data.Train), a.N), ratio(cv.Correct, a.N)))
			all[k] = make([][]Prediction, h)
			grid := make([][]byte, h)
			counts := make([]int, a.C)
			for r := 0; r < h; r++ {
				grid[r] = make([]byte, w)
				all[k][r] = make([]Prediction, w)
				for c := 0; c < w; c++ {
					p := model.inferVector([]float64{xmin + float64(c)*dx, ymax - float64(r)*dy}, nil)
					all[k][r][c] = p
					grid[r][c] = a.Upper[p.Predicted]
					counts[p.Predicted]++
				}
			}
			lines = append(lines, frame(grid)...)
			line := "cells"
			for c, n := range counts {
				line += fmt.Sprintf(" %c %d", a.Upper[c], n)
			}
			lines = append(lines, line)
		}
		agreement, uncertainty := make([][]byte, h), make([][]byte, h)
		disagreements := 0
		for r := 0; r < h; r++ {
			agreement[r] = make([]byte, w)
			uncertainty[r] = make([]byte, w)
			for c := 0; c < w; c++ {
				distinct := map[int]bool{}
				for k := 0; k < 3; k++ {
					distinct[all[k][r][c].Predicted] = true
				}
				n := len(distinct)
				agreement[r][c] = '.'
				if n > 1 {
					agreement[r][c] = byte('0' + n)
					disagreements++
				}
				u := (1 - all[2][r][c].Confidence) / (1 - 1/float64(a.C))
				level := min(9, int(math.Floor(10*u)))
				uncertainty[r][c] = " .:-=+*#%@"[level]
			}
		}
		lines = append(lines, "agreement")
		lines = append(lines, frame(agreement)...)
		lines = append(lines, fmt.Sprintf("disagreement_cells %d", disagreements), "uncertainty QDA")
		lines = append(lines, frame(uncertainty)...)
		lines = append(lines, "points")
		lines = append(lines, frame(pointGrid(points, a.TrainActual, a.Lower, limits, a.Data.Params.MapSize))...)
		sections = append(sections, lines)
	}
	return sections
}
func nearestCorrect(points [][2]float64, actual []int, centroids [][2]float64, dimensions int) int {
	correct := 0
	for i, p := range points {
		distances := make([]float64, len(centroids))
		for k, c := range centroids {
			delta := p[0] - c[0]
			d := delta * delta
			if dimensions == 2 {
				delta = p[1] - c[1]
				d = d + delta*delta
			}
			distances[k] = d
		}
		if argmin(distances) == actual[i] {
			correct++
		}
	}
	return correct
}
func (a *Analysis) projectionSections() [][]string {
	s := a.Models[0].Stats
	within, between := zeros(a.D), zeros(a.D)
	for i := 0; i < a.D; i++ {
		for j := 0; j < a.D; j++ {
			for k := 0; k < a.C; k++ {
				within[i][j] += s.Scatter[k][i][j]
				between[i][j] += float64(s.Counts[k]) * (s.Means[k][i] - s.Center[i]) * (s.Means[k][j] - s.Center[j])
			}
		}
	}
	fv := make([]float64, a.D)
	order := append([]int{}, a.All...)
	for j := range fv {
		fv[j] = (between[j][j] / float64(a.C-1)) / (within[j][j] / float64(a.N-a.C))
	}
	sort.SliceStable(order, func(i, j int) bool { return fv[order[i]] > fv[order[j]] })
	univariate := []string{"univariate"}
	for rank, j := range order {
		univariate = append(univariate, fmt.Sprintf("rank %d %s f %s between %s within %s", rank+1, a.Data.Features[j],
			real(fv[j]), real(between[j][j]), real(within[j][j])))
	}
	lower := cholesky(within)
	y := zeros(a.D)
	for j := 0; j < a.D; j++ {
		column := make([]float64, a.D)
		for i := range column {
			column[i] = between[i][j]
		}
		column = forward(lower, column)
		for i, v := range column {
			y[i][j] = v
		}
	}
	z := zeros(a.D)
	for i := 0; i < a.D; i++ {
		column := forward(lower, y[i])
		for j, v := range column {
			z[j][i] = v
		}
	}
	symmetric := zeros(a.D)
	for i := range symmetric {
		for j := range symmetric[i] {
			symmetric[i][j] = (z[i][j] + z[j][i]) / 2
		}
	}
	eigen := jacobi(symmetric)
	order = append([]int{}, a.All...)
	sort.SliceStable(order, func(i, j int) bool { return eigen.Values[order[i]] > eigen.Values[order[j]] })
	sum := 0.0
	for _, v := range eigen.Values {
		sum += v
	}
	directions := [][]float64{}
	for _, index := range order[:2] {
		vec := make([]float64, a.D)
		for j := range vec {
			vec[j] = eigen.Vectors[j][index]
		}
		v := backward(lower, vec)
		norm := math.Sqrt(dot(v, v))
		absolute := make([]float64, a.D)
		for j := range v {
			v[j] /= norm
			absolute[j] = math.Abs(v[j])
		}
		if v[argmax(absolute)] < 0 {
			for j := range v {
				v[j] = -v[j]
			}
		}
		directions = append(directions, v)
	}
	project := func(values []float64) [2]float64 {
		p := [2]float64{}
		for t, v := range directions {
			for j, x := range v {
				p[t] += x * (values[j] - s.Center[j])
			}
		}
		return p
	}
	trainPoints, testPoints, centroids := make([][2]float64, a.N), make([][2]float64, a.M), make([][2]float64, a.C)
	for i, r := range a.Data.Train {
		trainPoints[i] = project(r.Values)
	}
	for i, r := range a.Data.Test {
		testPoints[i] = project(r.Values)
	}
	for k, mean := range s.Means {
		centroids[k] = project(mean)
	}
	values, ratios := []float64{}, []float64{}
	for _, j := range order {
		values = append(values, eigen.Values[j])
		ratios = append(ratios, eigen.Values[j]/sum)
	}
	fisher := []string{"fisher features " + strings.Join(a.Data.Features, " "), "center " + reals(s.Center),
		fmt.Sprintf("sweeps %d", eigen.Sweeps), "eigenvalues " + reals(values), "ratios " + reals(ratios)}
	for t, v := range directions {
		standard := make([]float64, a.D)
		for j, x := range v {
			standard[j] = x * math.Sqrt(a.Models[1].Covariances[0][j][j])
		}
		fisher = append(fisher, fmt.Sprintf("direction %d %s", t+1, reals(v)), fmt.Sprintf("standardized %d %s", t+1, reals(standard)))
	}
	for k, name := range a.Data.Classes {
		spread := []float64{0, 0}
		for t := 0; t < 2; t++ {
			total := 0.0
			for i, p := range trainPoints {
				if a.TrainActual[i] == k {
					d := p[t] - centroids[k][t]
					total += d * d
				}
			}
			spread[t] = math.Sqrt(total / float64(s.Counts[k]))
		}
		fisher = append(fisher, fmt.Sprintf("centroid %s %s spread %s", name, reals(centroids[k][:]), reals(spread)))
	}
	for dims := 1; dims <= 2; dims++ {
		fisher = append(fisher, fmt.Sprintf("nearest_centroid dims %d train %s test %s", dims, ratio(nearestCorrect(trainPoints,
			a.TrainActual, centroids, dims), a.N), ratio(nearestCorrect(testPoints, a.TestActual,
			centroids, dims), a.M)))
	}
	limits := pointLimits(trainPoints)
	w, h := a.Data.Params.PlotSize[0], a.Data.Params.PlotSize[1]
	grid := pointGrid(trainPoints, a.TrainActual, a.Lower, limits, a.Data.Params.PlotSize)
	for k, p := range centroids {
		c := cell(p[0], limits[0], limits[1], w)
		r := h - 1 - cell(p[1], limits[2], limits[3], h)
		grid[r][c] = a.Upper[k]
	}
	plot := []string{fmt.Sprintf("plot x %s %s y %s %s size %dx%d", real(limits[0]), real(limits[1]), real(limits[2]), real(limits[3]), w, h)}
	plot = append(plot, frame(grid)...)
	return [][]string{univariate, fisher, plot}
}
func main() {
	a := newAnalysis(readInputs())
	writeLines("models.txt", joinSections(a.modelSections()))
	writeLines("predictions.csv", a.predictionLines())
	writeLines("evaluation.txt", joinSections(a.evaluationSections()))
	writeLines("boundaries.txt", joinSections(a.boundarySections()))
	writeLines("projection.txt", joinSections(a.projectionSections()))
}
