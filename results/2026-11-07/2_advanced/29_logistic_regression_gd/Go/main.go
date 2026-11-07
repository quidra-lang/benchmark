package main

import (
	"fmt"
	"math"
	"os"
	"sort"
	"strings"
)

func f4(v float64) string { return fixed(v, 4) }
func f6(v float64) string { return fixed(v, 6) }
func line(parts ...any) string {
	out := []string{}
	for _, p := range parts {
		out = append(out, fmt.Sprint(p))
	}
	return strings.Join(out, " ")
}
func realText(values []float64, places int) string {
	out := []string{}
	for _, v := range values {
		out = append(out, fixed(v, places))
	}
	return strings.Join(out, " ")
}
func integerText(values []int) string {
	out := []string{}
	for _, v := range values {
		out = append(out, fmt.Sprint(v))
	}
	return strings.Join(out, " ")
}
func sequentialSum(values []float64) float64 {
	total := 0.0
	for _, v := range values {
		total += v
	}
	return total
}
func sum(values []int) int {
	total := 0
	for _, v := range values {
		total += v
	}
	return total
}
func length(values []float64) float64 {
	total := 0.0
	for _, v := range values {
		total += v * v
	}
	return math.Sqrt(total)
}
func countEqual(a, b []int) int {
	total := 0
	for i, v := range a {
		if v == b[i] {
			total++
		}
	}
	return total
}
func predict(p []float64, threshold float64) []int {
	result := make([]int, len(p))
	for i, v := range p {
		if v >= threshold {
			result[i] = 1
		}
	}
	return result
}
func probabilities(w []float64, x [][]float64) []float64 {
	result := []float64{}
	for _, v := range x {
		result = append(result, probability(score(w, v)))
	}
	return result
}
func targets(labels []int, class int) []int {
	result := make([]int, len(labels))
	for i, label := range labels {
		if label == class {
			result[i] = 1
		}
	}
	return result
}
func firstColumns(rows [][]float64, count int) [][]float64 {
	result := [][]float64{}
	for _, row := range rows {
		result = append(result, row[:count])
	}
	return result
}
func inverse(a [][]float64) [][]float64 {
	n := len(a)
	lower := cholesky(a)
	result := matrix(n, n)
	for k := 0; k < n; k++ {
		unit := make([]float64, n)
		unit[k] = 1
		column := solve(lower, unit)
		for j := 0; j < n; j++ {
			result[j][k] = column[j]
		}
	}
	return result
}
func originalUnits(w []float64, s Statistics) []float64 {
	result := make([]float64, len(w))
	shift := 0.0
	for j := 1; j < len(w); j++ {
		result[j] = w[j] / s.Deviations[j-1]
		shift += result[j] * s.Means[j-1]
	}
	result[0] = w[0] - shift
	return result
}
func writeLines(name string, lines []string) {
	if e := os.WriteFile("output/"+name, []byte(strings.Join(lines, "\n")+"\n"), 0644); e != nil {
		panic(e)
	}
}
func writeParts(name string, parts [][]string) {
	lines := []string{}
	for i, part := range parts {
		if i > 0 {
			lines = append(lines, "")
		}
		lines = append(lines, part...)
	}
	writeLines(name, lines)
}

type Data struct {
	Names, FeatureNames                                    []string
	Train, Test                                            []Example
	Settings                                               Settings
	Tuples                                                 [][]int
	DegreeCounts                                           []int
	Classes, Count                                         int
	TrainExpanded, TestExpanded, TrainVectors, TestVectors [][]float64
	Overall                                                Statistics
	TrainTargets, TestTargets, TrainLabels, TestLabels     []int
	MeanValues                                             []float64
}

func readData() *Data {
	names, train := readExamples("input/train.csv")
	_, test := readExamples("input/test.csv")
	s := readSettings()
	tuples := expansionTuples(len(names), s.Int("DEGREE", 0))
	d := &Data{Names: names, Train: train, Test: test, Settings: s, Tuples: tuples, Count: len(tuples), FeatureNames: expandedNames(names, tuples)}
	for degree := 1; degree <= s.Int("DEGREE", 0); degree++ {
		count := 0
		for _, t := range tuples {
			if len(t) <= degree {
				count++
			}
		}
		d.DegreeCounts = append(d.DegreeCounts, count)
	}
	for _, row := range train {
		d.TrainExpanded = append(d.TrainExpanded, expandedValues(tuples, row.Values))
		d.TrainLabels = append(d.TrainLabels, row.Label)
		d.Classes = max(d.Classes, row.Label+1)
	}
	for _, row := range test {
		d.TestExpanded = append(d.TestExpanded, expandedValues(tuples, row.Values))
		d.TestLabels = append(d.TestLabels, row.Label)
	}
	d.Overall = computeStatistics(d.TrainExpanded, d.Count)
	d.TrainVectors = standardizedRows(d.TrainExpanded, d.Overall, d.Count)
	d.TestVectors = standardizedRows(d.TestExpanded, d.Overall, d.Count)
	d.TrainTargets = targets(d.TrainLabels, s.Int("POSITIVE", 0))
	d.TestTargets = targets(d.TestLabels, s.Int("POSITIVE", 0))
	d.MeanValues = append([]float64(nil), d.Overall.Means[:len(names)]...)
	return d
}
func (d *Data) Vector(values []float64) []float64 {
	return standardize(expandedValues(d.Tuples, values), d.Overall, d.Count)
}
func (d *Data) Range(base int) (float64, float64) {
	lo, hi := d.Train[0].Values[base], d.Train[0].Values[base]
	for _, row := range d.Train[1:] {
		lo = math.Min(lo, row.Values[base])
		hi = math.Max(hi, row.Values[base])
	}
	return lo, hi
}

type CrossValidation struct {
	Lambda, Loss              float64
	FoldLosses, Probabilities []float64
	Errors                    int
}

func crossValidate(d *Data, lambda float64, count int) CrossValidation {
	result := CrossValidation{Lambda: lambda, Probabilities: make([]float64, len(d.Train))}
	losses := make([]float64, len(d.Train))
	for fold := 0; fold < 5; fold++ {
		rows := [][]float64{}
		y := []int{}
		for i, row := range d.TrainExpanded {
			if i%5 != fold {
				rows = append(rows, row)
				y = append(y, d.TrainTargets[i])
			}
		}
		stats := computeStatistics(rows, count)
		w := finalWeights(newtonMethod(standardizedRows(rows, stats, count), y, lambda))
		total := 0.0
		size := 0
		for i, row := range d.TrainExpanded {
			if i%5 == fold {
				u := score(w, standardize(row, stats, count))
				losses[i] = loss(u, d.TrainTargets[i])
				result.Probabilities[i] = probability(u)
				total += losses[i]
				size++
				p := 0
				if result.Probabilities[i] >= d.Settings.Real("THRESHOLD", 0) {
					p = 1
				}
				if p != d.TrainTargets[i] {
					result.Errors++
				}
			}
		}
		result.FoldLosses = append(result.FoldLosses, total/float64(size))
	}
	result.Loss = sequentialSum(losses) / float64(len(losses))
	return result
}

type Evaluation struct {
	Probabilities []float64
	Predictions   []int
	Loss          float64
	Correct       int
	AUC           Fraction
}

func evaluate(w []float64, x [][]float64, y []int, threshold float64) Evaluation {
	p := probabilities(w, x)
	prediction := predict(p, threshold)
	return Evaluation{p, prediction, averageLoss(w, x, y), countEqual(prediction, y), auc(p, y)}
}

type BinaryModel struct {
	Name        string
	Checkpoints []Checkpoint
	Weights     []float64
	Train, Test Evaluation
	Roc         []RocPoint
}

func newBinaryModel(name string, checkpoints []Checkpoint, d *Data) BinaryModel {
	w := finalWeights(checkpoints)
	threshold := d.Settings.Real("THRESHOLD", 0)
	train, test := evaluate(w, d.TrainVectors, d.TrainTargets, threshold), evaluate(w, d.TestVectors, d.TestTargets, threshold)
	return BinaryModel{name, checkpoints, w, train, test, rocPoints(test.Probabilities, d.TestTargets)}
}

type SoftmaxModel struct {
	Checkpoints            []SoftCheckpoint
	Weights, Probabilities [][]float64
	Predictions            []int
}

func newSoftmaxModel(c []SoftCheckpoint, d *Data) SoftmaxModel {
	m := SoftmaxModel{Checkpoints: c, Weights: c[len(c)-1].Weights}
	for _, v := range d.TestVectors {
		p := softmaxProbabilities(m.Weights, v)
		m.Probabilities = append(m.Probabilities, p)
		m.Predictions = append(m.Predictions, predictedClass(p))
	}
	return m
}

type Influence struct {
	Matrix                                         [][]float64
	Probabilities, Leverages, Residuals, Distances []float64
	EDF, Deviance, AIC, BIC                        float64
}

func influence(w []float64, x [][]float64, y []int, lambda float64) Influence {
	in := Influence{Matrix: inverse(hessian(w, x, lambda))}
	n, size := float64(len(x)), len(w)
	for i, v := range x {
		p := probability(score(w, v))
		variance := p * (1 - p)
		q := 0.0
		for j := 0; j < size; j++ {
			for k := 0; k < size; k++ {
				q += v[j] * in.Matrix[j][k] * v[k]
			}
		}
		leverage := variance * q / n
		pearson := (float64(y[i]) - p) / math.Sqrt(variance)
		in.Probabilities = append(in.Probabilities, p)
		in.Leverages = append(in.Leverages, leverage)
		in.Residuals = append(in.Residuals, pearson/math.Sqrt(1-leverage))
		in.Distances = append(in.Distances, pearson*pearson*leverage/(float64(size)*((1-leverage)*(1-leverage))))
	}
	in.EDF = sequentialSum(in.Leverages)
	in.Deviance = 2 * n * averageLoss(w, x, y)
	in.AIC = in.Deviance + 2*in.EDF
	in.BIC = in.Deviance + math.Log(n)*in.EDF
	return in
}

type Bin struct {
	Count, Hits int
	Total       float64
}

func binIndex(p float64) int { return min(9, int(math.Floor(p*10))) }
func fillBins(p []float64, y []int) []Bin {
	bins := make([]Bin, 10)
	for i, v := range p {
		b := &bins[binIndex(v)]
		b.Count++
		b.Total += v
		b.Hits += y[i]
	}
	return bins
}
func binLines(bins []Bin, meanLabel, rateLabel string) []string {
	lines := []string{}
	for i, b := range bins {
		mean := "-"
		if b.Count > 0 {
			mean = f4(b.Total / float64(b.Count))
		}
		lines = append(lines, line("bin", fmt.Sprintf("%.1f-%.1f", float64(i)/10, float64(i+1)/10), "count",
			b.Count, meanLabel, mean, rateLabel, ratio(b.Hits, b.Count)))
	}
	return lines
}
func calibrationError(bins []Bin, n int) float64 {
	total := 0.0
	for _, b := range bins {
		if b.Count > 0 {
			total += math.Abs(b.Total - float64(b.Hits))
		}
	}
	return total / float64(n)
}
func termLines(names []string, w []float64, stats Statistics) []string {
	original := originalUnits(w, stats)
	terms := append([]string{"intercept"}, names...)
	lines := []string{}
	for j, name := range terms {
		lines = append(lines, line("term", name, "standardized", f4(w[j]), "original", f4(original[j])))
	}
	return lines
}
func weightsParts(d *Data, models []BinaryModel, soft SoftmaxModel, in Influence, lambda float64) [][]string {
	n, p := len(d.Train), d.Count
	corr := matrix(p, p)
	for j := 0; j < p; j++ {
		for k := 0; k < p; k++ {
			total := 0.0
			for _, v := range d.TrainVectors {
				total += v[j+1] * v[k+1]
			}
			corr[j][k] = total / float64(n-1)
		}
	}
	vif := inverse(corr)
	feature := []string{line("features", len(d.Names), "degree", d.Settings.Int("DEGREE", 0), "expanded", p), "standardization"}
	for j, name := range d.FeatureNames {
		feature = append(feature, line(name, "mean", f6(d.Overall.Means[j]), "sd", f6(d.Overall.Deviations[j]), "vif", f4(vif[j][j])))
	}
	feature = append(feature, "correlation")
	for _, row := range corr {
		feature = append(feature, realText(row, 4))
	}
	parts := [][]string{feature}
	nw := models[2].Weights
	for _, m := range models {
		lines := []string{line("model", m.Name, "lambda", f4(lambda))}
		lines = append(lines, termLines(d.FeatureNames, m.Weights, d.Overall)...)
		lines = append(lines, line("norm", f4(length(m.Weights[1:]))))
		if m.Name != "newton" {
			diff := make([]float64, len(nw))
			for j := range diff {
				diff[j] = m.Weights[j] - nw[j]
			}
			lines = append(lines, line("distance_to_newton", f6(length(diff))))
		}
		parts = append(parts, lines)
	}
	coefficients := []string{line("coefficients", "newton", "lambda", f4(lambda))}
	for j, name := range append([]string{"intercept"}, d.FeatureNames...) {
		w := nw[j]
		se := math.Sqrt(in.Matrix[j][j] / float64(n))
		coefficients = append(coefficients, line(name, "weight", f4(w), "se", f4(se), "z", f4(w/se), "lower",
			f4(w-1.96*se), "upper", f4(w+1.96*se), "odds_ratio", f4(math.Exp(w))))
	}
	parts = append(parts, coefficients)
	lines := []string{line("model", "softmax", "lambda", f4(d.Settings.Real("SOFTMAX", 2)))}
	for k, w := range soft.Weights {
		lines = append(lines, line("class", k))
		lines = append(lines, termLines(d.FeatureNames, w, d.Overall)...)
	}
	return append(parts, lines)
}
func traceLines(d *Data, models []BinaryModel, soft SoftmaxModel, lambda float64) []string {
	lines := []string{"optimizer,iteration,loss,gradient_norm,test_loss"}
	for _, m := range models {
		for _, c := range m.Checkpoints {
			w := c.Weights
			lines = append(lines, fmt.Sprintf("%s,%d,%s,%s,%s", m.Name, c.Iteration, f6(objective(w, d.TrainVectors,
				d.TrainTargets, lambda)), f6(length(gradient(w, d.TrainVectors, d.TrainTargets, lambda))),
				f6(averageLoss(w, d.TestVectors, d.TestTargets))))
		}
	}
	l := d.Settings.Real("SOFTMAX", 2)
	for _, c := range soft.Checkpoints {
		g := softmaxGradient(c.Weights, d.TrainVectors, d.TrainLabels, l)
		flattened := []float64{}
		for _, row := range g {
			flattened = append(flattened, row...)
		}
		lines = append(lines, fmt.Sprintf("softmax,%d,%s,%s,%s", c.Iteration, f6(softmaxObjective(c.Weights,
			d.TrainVectors, d.TrainLabels, l)), f6(length(flattened)), f6(softmaxAverage(c.Weights,
			d.TestVectors, d.TestLabels))))
	}
	return lines
}
func predictionLines(d *Data, models []BinaryModel, soft SoftmaxModel) []string {
	lines := []string{"id,model,probability,predicted,actual"}
	for _, m := range models {
		for j, row := range d.Test {
			lines = append(lines, fmt.Sprintf("%s,%s,%s,%d,%d", row.Ident, m.Name, f6(m.Test.Probabilities[j]), m.Test.Predictions[j], d.TestTargets[j]))
		}
	}
	for j, row := range d.Test {
		k := soft.Predictions[j]
		lines = append(lines, fmt.Sprintf("%s,softmax,%s,%d,%d", row.Ident, f6(soft.Probabilities[j][k]), k, row.Label))
	}
	return lines
}
func rocLines(d *Data, models []BinaryModel) []string {
	pos := sum(d.TestTargets)
	neg := len(d.Test) - pos
	lines := []string{"model,threshold,tpr,fpr,precision"}
	for _, m := range models {
		lines = append(lines, m.Name+",inf,0.0000,0.0000,-")
		for _, p := range m.Roc {
			lines = append(lines, fmt.Sprintf("%s,%s,%s,%s,%s", m.Name, f6(p.Threshold), ratio(p.TP, pos), ratio(p.FP, neg), ratio(p.TP, p.TP+p.FP)))
		}
	}
	return lines
}
func dataPart(d *Data) []string {
	train, test := make([]int, d.Classes), make([]int, d.Classes)
	for _, k := range d.TrainLabels {
		train[k]++
	}
	for _, k := range d.TestLabels {
		test[k]++
	}
	return []string{line("data", "train", len(d.Train), "test", len(d.Test), "base_features", len(d.Names),
		"degree", d.Settings.Int("DEGREE", 0), "features", d.Count), line("binary", "positive_class",
		d.Settings.Int("POSITIVE", 0), "train", fmt.Sprintf("%d/%d", sum(d.TrainTargets), len(d.Train)),
		"test", fmt.Sprintf("%d/%d", sum(d.TestTargets), len(d.Test))), line("classes", d.Classes,
		"train", integerText(train), "test", integerText(test))}
}
func crossValidationPart(d *Data, results []CrossValidation, best CrossValidation, se, oneSE float64) []string {
	n := len(d.Train)
	lines := []string{"cross_validation folds 5 newton_iterations 10"}
	for _, r := range results {
		lines = append(lines, line("lambda", f4(r.Lambda), "fold_loss", realText(r.FoldLosses, 6), "cv_loss",
			f6(r.Loss), "errors", fmt.Sprintf("%d/%d", r.Errors, n)))
	}
	lines = append(lines, line("selected", "lambda", f4(best.Lambda), "cv_loss", f6(best.Loss), "se", f6(se), "lambda_1se", f4(oneSE)))
	c := confusion(predict(best.Probabilities, d.Settings.Real("THRESHOLD", 0)), d.TrainTargets)
	return append(lines, line("out_of_fold", "tp", c.TP, "fp", c.FP, "tn", c.TN, "fn", c.FN, "accuracy",
		ratio(c.TP+c.TN, n), "auc", auc(best.Probabilities, d.TrainTargets).Text()))
}
func lambdaPathPart(d *Data) []string {
	lines := []string{"lambda_path"}
	for i := range d.Settings["LAMBDAS"] {
		l := d.Settings.Real("LAMBDAS", i)
		w := finalWeights(newtonMethod(d.TrainVectors, d.TrainTargets, l))
		train, test := evaluate(w, d.TrainVectors, d.TrainTargets, d.Settings.Real("THRESHOLD", 0)), evaluate(w,
			d.TestVectors, d.TestTargets, d.Settings.Real("THRESHOLD", 0))
		lines = append(lines, line("lambda", f4(l), "objective", f6(objective(w, d.TrainVectors, d.TrainTargets,
			l)), "train_loss", f6(train.Loss), "test_loss", f6(test.Loss), "train_accuracy", ratio(train.Correct,
			len(d.Train)), "test_accuracy", ratio(test.Correct, len(d.Test)), "norm", f4(length(w[1:]))))
	}
	return lines
}
func degreePart(d *Data, l float64) []string {
	lines := []string{line("degrees", "lambda", f4(l))}
	for i, q := range d.DegreeCounts {
		x, z := firstColumns(d.TrainVectors, q+1), firstColumns(d.TestVectors, q+1)
		w := finalWeights(newtonMethod(x, d.TrainTargets, l))
		cv := crossValidate(d, l, q)
		train, test := evaluate(w, x, d.TrainTargets, d.Settings.Real("THRESHOLD", 0)), evaluate(w, z, d.TestTargets, d.Settings.Real("THRESHOLD", 0))
		in := influence(w, x, d.TrainTargets, l)
		lines = append(lines, line("degree", i+1, "features", q, "cv_loss", f6(cv.Loss), "train_loss", f6(train.Loss),
			"test_loss", f6(test.Loss), "test_accuracy", ratio(test.Correct, len(d.Test)), "auc",
			test.AUC.Text(), "edf", f4(in.EDF), "aic", f4(in.AIC), "bic", f4(in.BIC)))
	}
	return lines
}
func learningPart(d *Data, l float64) []string {
	lines := []string{line("learning_curve", "lambda", f4(l))}
	for k := 1; k <= 4; k++ {
		n := k * len(d.Train) / 4
		stats := computeStatistics(d.TrainExpanded[:n], d.Count)
		x, z := standardizedRows(d.TrainExpanded[:n], stats, d.Count), standardizedRows(d.TestExpanded, stats, d.Count)
		y := d.TrainTargets[:n]
		w := finalWeights(newtonMethod(x, y, l))
		train, test := evaluate(w, x, y, d.Settings.Real("THRESHOLD", 0)), evaluate(w, z, d.TestTargets, d.Settings.Real("THRESHOLD", 0))
		lines = append(lines, line("size", n, "train_loss", f6(train.Loss), "test_loss", f6(test.Loss),
			"test_accuracy", ratio(test.Correct, len(d.Test)), "auc", test.AUC.Text()))
	}
	return lines
}
func calibrationLines(p []float64, y []int) []string {
	bins := fillBins(p, y)
	lines := append([]string{"calibration"}, binLines(bins, "mean_probability", "positive_rate")...)
	mce, hl := 0.0, 0.0
	groups := 0
	for _, b := range bins {
		if b.Count > 0 {
			groups++
			c, o := float64(b.Count), float64(b.Hits)
			mce = math.Max(mce, math.Abs(b.Total/c-o/c))
			diff := o - b.Total
			hl += diff * diff / (b.Total * (1 - b.Total/c))
		}
	}
	return append(lines, line("ece", f4(calibrationError(bins, len(y))), "mce", f4(mce), "hosmer_lemeshow", f4(hl), "groups", groups))
}
func gainsLines(p []float64, y []int) []string {
	lines := []string{"gains"}
	order := ordered(p, true)
	pos, n := sum(y), len(y)
	for g := 1; g <= 10; g++ {
		size := g * n / 10
		hits := 0
		for _, j := range order[:size] {
			hits += y[j]
		}
		lines = append(lines, line("decile", g, "rows", size, "positives", hits, "gain", ratio(hits, pos), "lift", ratio(hits*n, size*pos)))
	}
	return lines
}
func binaryPart(d *Data, m BinaryModel, l float64) []string {
	n, pos := len(d.Test), sum(d.TestTargets)
	neg := n - pos
	c := confusion(m.Test.Predictions, d.TestTargets)
	brier := 0.0
	for j, p := range m.Test.Probabilities {
		e := p - float64(d.TestTargets[j])
		brier += e * e
	}
	brier /= float64(n)
	youden, bestF1, cheapest := m.Roc[0], m.Roc[0], m.Roc[0]
	cost := func(p RocPoint) int { return d.Settings.Int("COST", 0)*p.FP + d.Settings.Int("COST", 1)*(pos-p.TP) }
	ap := 0.0
	prev := 0
	for _, p := range m.Roc {
		if p.TP*neg-p.FP*pos > youden.TP*neg-youden.FP*pos {
			youden = p
		}
		if int64(p.TP)*int64(pos+bestF1.TP+bestF1.FP) > int64(bestF1.TP)*int64(pos+p.TP+p.FP) {
			bestF1 = p
		}
		if cost(p) < cost(cheapest) {
			cheapest = p
		}
		ap += float64((p.TP-prev)*p.TP) / float64(p.TP+p.FP)
		prev = p.TP
	}
	ap /= float64(pos)
	lines := []string{line("model", m.Name, "lambda", f4(l)), line("train", "correct", fmt.Sprintf("%d/%d",
		m.Train.Correct, len(d.Train)), "accuracy", ratio(m.Train.Correct, len(d.Train))), line("test",
		"tp", c.TP, "fp", c.FP, "tn", c.TN, "fn", c.FN), line("test", "accuracy", ratio(c.TP+c.TN,
		n), "precision", ratio(c.TP, c.TP+c.FP), "recall", ratio(c.TP, c.TP+c.FN), "specificity",
		ratio(c.TN, c.TN+c.FP), "f1", ratio(2*c.TP, 2*c.TP+c.FP+c.FN)), line("log_loss", f6(m.Test.Loss),
		"brier", f6(brier)), line("auc", m.Test.AUC.Text(), "average_precision", f4(ap)), line("youden",
		"threshold", f6(youden.Threshold), "tpr", ratio(youden.TP, pos), "fpr", ratio(youden.FP,
			neg), "j", ratio(youden.TP*neg-youden.FP*pos, pos*neg)), line("best_f1", "threshold", f6(bestF1.Threshold),
		"precision", ratio(bestF1.TP, bestF1.TP+bestF1.FP), "recall", ratio(bestF1.TP, pos), "f1",
		ratio(2*bestF1.TP, pos+bestF1.TP+bestF1.FP)), line("min_cost", "threshold", f6(cheapest.Threshold),
		"cost", cost(cheapest), "fp", cheapest.FP, "fn", pos-cheapest.TP)}
	lines = append(lines, calibrationLines(m.Test.Probabilities, d.TestTargets)...)
	return append(lines, gainsLines(m.Test.Probabilities, d.TestTargets)...)
}
func comparisonPart(d *Data, models []BinaryModel) []string {
	lines := []string{}
	for _, pair := range [][2]int{{0, 1}, {0, 2}, {1, 2}} {
		a, b := models[pair[0]], models[pair[1]]
		onlyA, onlyB := 0, 0
		for j, y := range d.TestTargets {
			if a.Test.Predictions[j] == y && b.Test.Predictions[j] != y {
				onlyA++
			}
			if b.Test.Predictions[j] == y && a.Test.Predictions[j] != y {
				onlyB++
			}
		}
		gap := onlyA - onlyB
		if gap < 0 {
			gap = -gap
		}
		gap--
		lines = append(lines, line("agreement", a.Name, b.Name, "same", fmt.Sprintf("%d/%d", countEqual(a.Test.Predictions,
			b.Test.Predictions), len(d.Test)), "only_first", onlyA, "only_second", onlyB, "mcnemar",
			ratio(gap*gap, onlyA+onlyB)))
	}
	return lines
}
func slope(tuples [][]int, original, values []float64, base int) float64 {
	total := 0.0
	for j, indices := range tuples {
		count := 0
		removed := false
		product := 1.0
		for _, index := range indices {
			if index == base {
				count++
				if !removed {
					removed = true
					continue
				}
			}
			product *= values[index]
		}
		if count > 0 {
			total += original[j+1] * (float64(count) * product)
		}
	}
	return total
}
func diagnosticsPart(d *Data, m BinaryModel, in Influence, l float64) []string {
	n, size := len(d.Train), len(d.Test)
	base := float64(sum(d.TrainTargets)) / float64(n)
	nullLoss := -(base*math.Log(base) + (1-base)*math.Log(1-base))
	lines := []string{line("diagnostics", "newton", "lambda", f4(l)), line("fit", "null_loss", f6(nullLoss),
		"train_loss", f6(m.Train.Loss), "mcfadden_r2", f4(1-m.Train.Loss/nullLoss), "deviance", f4(in.Deviance),
		"edf", f4(in.EDF), "aic", f4(in.AIC), "bic", f4(in.BIC))}
	order := ordered(in.Probabilities, false)
	hl := 0.0
	groups := []string{}
	for g := 1; g <= 10; g++ {
		members := order[(g-1)*n/10 : g*n/10]
		observed, expected := 0, 0.0
		for _, i := range members {
			observed += d.TrainTargets[i]
			expected += in.Probabilities[i]
		}
		diff := float64(observed) - expected
		hl += diff * diff / (expected * (1 - expected/float64(len(members))))
		groups = append(groups, line("group", g, "rows", len(members), "observed", observed, "expected", f4(expected)))
	}
	lines = append(lines, line("hosmer_lemeshow_train", "groups", 10, "statistic", f4(hl)))
	lines = append(lines, groups...)
	lines = append(lines, "newton_iterations")
	for t := 1; t <= 10; t++ {
		w := m.Checkpoints[t-1].Weights
		g, step := newtonDirection(w, d.TrainVectors, d.TrainTargets, l)
		decrease := 0.0
		for j := range g {
			decrease += g[j] * step[j]
		}
		lines = append(lines, line("iteration", t, "objective", f6(objective(w, d.TrainVectors, d.TrainTargets,
			l)), "gradient_norm", f6(length(g)), "step_norm", f6(length(step)), "predicted_decrease",
			f6(decrease/2)))
	}
	original := originalUnits(m.Weights, d.Overall)
	centre := probability(score(m.Weights, d.Vector(d.MeanValues)))
	for k, name := range d.Names {
		total := 0.0
		for i, row := range d.Train {
			p := in.Probabilities[i]
			total += p * (1 - p) * slope(d.Tuples, original, row.Values, k)
		}
		atMean := centre * (1 - centre) * slope(d.Tuples, original, d.MeanValues, k)
		lines = append(lines, line("marginal", name, "average", f4(total/float64(n)), "at_mean", f4(atMean)))
	}
	for k := 1; k <= 9; k++ {
		c := confusion(predict(m.Test.Probabilities, float64(k)/10), d.TestTargets)
		lines = append(lines, line("cut", fmt.Sprintf("0.%d", k), "positive", c.TP+c.FP, "tp", c.TP, "fp",
			c.FP, "precision", ratio(c.TP, c.TP+c.FP), "recall", ratio(c.TP, c.TP+c.FN), "accuracy",
			ratio(c.TP+c.TN, size)))
	}
	wrong := []int{}
	for j, y := range d.TestTargets {
		if m.Test.Predictions[j] != y {
			wrong = append(wrong, j)
		}
	}
	threshold := d.Settings.Real("THRESHOLD", 0)
	sort.SliceStable(wrong, func(a, b int) bool {
		return math.Abs(m.Test.Probabilities[wrong[a]]-threshold) > math.Abs(m.Test.Probabilities[wrong[b]]-threshold)
	})
	for _, j := range wrong[:min(5, len(wrong))] {
		lines = append(lines, line("error", d.Test[j].Ident, "actual", d.TestTargets[j], "probability", f6(m.Test.Probabilities[j])))
	}
	count := d.Settings.Int("BOOTSTRAP", 0)
	seed := int64(d.Settings.Int("BOOTSTRAP", 1))
	rng := Minstd{seed}
	samples := []Fraction{}
	values := []float64{}
	for b := 0; b < count; b++ {
		scores, y := []float64{}, []int{}
		for j := 0; j < size; j++ {
			i := int(rng.Draw() % int64(size))
			scores = append(scores, m.Test.Probabilities[i])
			y = append(y, d.TestTargets[i])
		}
		f := auc(scores, y)
		samples = append(samples, f)
		values = append(values, f.Value())
	}
	mean := sequentialSum(values) / float64(count)
	squares := 0.0
	for _, v := range values {
		diff := v - mean
		squares += diff * diff
	}
	sort.SliceStable(samples, func(i, j int) bool { return samples[i].Value() < samples[j].Value() })
	tail := count / 40
	lines = append(lines, line("bootstrap", "resamples", count, "seed", seed, "auc_mean", f4(mean), "auc_sd",
		f4(math.Sqrt(squares/float64(count-1))), "lower", samples[tail].Text(), "upper", samples[count-tail-1].Text()))
	large := 0
	for _, v := range in.Residuals {
		if math.Abs(v) > 2 {
			large++
		}
	}
	lines = append(lines, line("influence", "effective_parameters", f4(in.EDF), "large_residuals", large))
	for _, i := range ordered(in.Distances, true)[:min(5, n)] {
		lines = append(lines, line("cook", d.Train[i].Ident, "actual", d.TrainTargets[i], "probability",
			f4(in.Probabilities[i]), "leverage", f4(in.Leverages[i]), "residual", f4(in.Residuals[i]),
			"distance", f4(in.Distances[i])))
	}
	return lines
}
func softmaxCorrect(w, x [][]float64, y []int) int {
	correct := 0
	for i, v := range x {
		if predictedClass(softmaxProbabilities(w, v)) == y[i] {
			correct++
		}
	}
	return correct
}
func importancePart(d *Data, m BinaryModel, soft SoftmaxModel) []string {
	n, repeats, seed := len(d.Test), d.Settings.Int("PERMUTATION", 0), d.Settings.Int("PERMUTATION", 1)
	lines := []string{line("importance", "repeats", repeats, "seed", seed), line("baseline", "log_loss",
		f6(m.Test.Loss), "auc", m.Test.AUC.Text(), "softmax_accuracy", ratio(countEqual(soft.Predictions,
			d.TestLabels), n))}
	rng := Minstd{int64(seed)}
	for base, name := range d.Names {
		losses := 0.0
		numerator, correct := 0, 0
		for t := 0; t < repeats; t++ {
			order := make([]int, n)
			for j := range order {
				order[j] = j
			}
			rng.Shuffle(order)
			vectors := [][]float64{}
			for j, row := range d.Test {
				values := append([]float64(nil), row.Values...)
				values[base] = d.Test[order[j]].Values[base]
				vectors = append(vectors, d.Vector(values))
			}
			losses += averageLoss(m.Weights, vectors, d.TestTargets)
			numerator += auc(probabilities(m.Weights, vectors), d.TestTargets).A
			correct += softmaxCorrect(soft.Weights, vectors, d.TestLabels)
		}
		lines = append(lines, line("feature", name, "log_loss_increase", f6(losses/float64(repeats)-m.Test.Loss),
			"auc", Fraction{numerator, repeats * m.Test.AUC.B}.Text(), "softmax_accuracy", ratio(correct,
				repeats*n)))
	}
	return lines
}
func profilePart(d *Data, m BinaryModel, soft SoftmaxModel) []string {
	lines := []string{"profiles"}
	for base, name := range d.Names {
		lo, hi := d.Range(base)
		for g := 0; g <= 4; g++ {
			values := append([]float64(nil), d.MeanValues...)
			values[base] = lo + (hi-lo)*float64(g)/4
			v := d.Vector(values)
			lines = append(lines, line("profile", name, "value", f4(values[base]), "newton", f4(probability(score(m.Weights,
				v))), "softmax", realText(softmaxProbabilities(soft.Weights, v), 4)))
		}
	}
	return lines
}
func softmaxPart(d *Data, soft SoftmaxModel, newton BinaryModel) []string {
	n, k := len(d.Test), d.Classes
	table := make([][]int, k)
	for c := range table {
		table[c] = make([]int, k)
	}
	for j, label := range d.TestLabels {
		table[label][soft.Predictions[j]]++
	}
	rows, columns := make([]int, k), make([]int, k)
	for c, row := range table {
		for j, v := range row {
			rows[c] += v
			columns[j] += v
		}
	}
	lines := []string{line("softmax", "classes", k, "lambda", f4(d.Settings.Real("SOFTMAX", 2)), "iterations", d.Settings.Int("SOFTMAX", 1)), "confusion"}
	for _, row := range table {
		lines = append(lines, integerText(row))
	}
	diagonal, chance := 0, 0
	for c := 0; c < k; c++ {
		scores := []float64{}
		for _, p := range soft.Probabilities {
			scores = append(scores, p[c])
		}
		hits := table[c][c]
		diagonal += hits
		chance += rows[c] * columns[c]
		lines = append(lines, line("class", c, "precision", ratio(hits, columns[c]), "recall", ratio(hits,
			rows[c]), "f1", ratio(2*hits, columns[c]+rows[c]), "auc", auc(scores, targets(d.TestLabels,
			c)).Text()))
	}
	lines = append(lines, line("accuracy", ratio(diagonal, n), "kappa", ratio(n*diagonal-chance, n*n-chance)))
	brier := 0.0
	for j, p := range soft.Probabilities {
		total := 0.0
		for c, v := range p {
			delta := 0.0
			if d.TestLabels[j] == c {
				delta = 1
			}
			e := v - delta
			total += e * e
		}
		brier += total
	}
	lines = append(lines, line("log_loss", f6(softmaxAverage(soft.Weights, d.TestVectors, d.TestLabels)), "brier", f6(brier/float64(n))))
	scores, confidences := []float64{}, []float64{}
	hits := []int{}
	positive := d.Settings.Int("POSITIVE", 0)
	binaryLoss := 0.0
	for j, p := range soft.Probabilities {
		value := p[positive]
		scores = append(scores, value)
		q := value
		if d.TestTargets[j] == 0 {
			q = 1 - value
		}
		binaryLoss += -math.Log(q)
		predicted := soft.Predictions[j]
		confidences = append(confidences, p[predicted])
		hit := 0
		if predicted == d.TestLabels[j] {
			hit = 1
		}
		hits = append(hits, hit)
	}
	prediction := predict(scores, d.Settings.Real("THRESHOLD", 0))
	lines = append(lines, line("binary_view", "positive_class", positive, "auc", auc(scores, d.TestTargets).Text(),
		"log_loss", f6(binaryLoss/float64(n)), "accuracy", ratio(countEqual(prediction, d.TestTargets),
			n), "agreement_with_newton", fmt.Sprintf("%d/%d", countEqual(prediction, newton.Test.Predictions),
			n)), "confidence")
	bins := fillBins(confidences, hits)
	lines = append(lines, binLines(bins, "mean_confidence", "accuracy")...)
	return append(lines, line("ece", f4(calibrationError(bins, n))))
}
func oneVsRestPart(d *Data, soft SoftmaxModel) []string {
	l := d.Settings.Real("SOFTMAX", 2)
	lines := []string{line("one_vs_rest", "lambda", f4(l), "newton_iterations", 10)}
	classProbabilities := [][]float64{}
	for k := 0; k < d.Classes; k++ {
		y := targets(d.TrainLabels, k)
		w := finalWeights(newtonMethod(d.TrainVectors, y, l))
		p := probabilities(w, d.TestVectors)
		classProbabilities = append(classProbabilities, p)
		lines = append(lines, line("class", k, "objective", f6(objective(w, d.TrainVectors, y, l)), "auc", auc(p, targets(d.TestLabels, k)).Text()))
	}
	prediction := []int{}
	for j := range d.Test {
		column := []float64{}
		for _, p := range classProbabilities {
			column = append(column, p[j])
		}
		prediction = append(prediction, predictedClass(column))
	}
	n := len(d.Test)
	return append(lines, line("accuracy", ratio(countEqual(prediction, d.TestLabels), n), "agreement_with_softmax",
		fmt.Sprintf("%d/%d", countEqual(prediction, soft.Predictions), n)))
}
func mapPart(d *Data, m BinaryModel, soft SoftmaxModel) []string {
	w, h := d.Settings.Int("MAP", 0), d.Settings.Int("MAP", 1)
	loX, hiX := d.Range(0)
	loY, hiY := d.Range(1)
	cells := make([]int, d.Classes)
	classes, probabilityRows := []string{}, []string{}
	for r := 0; r < h; r++ {
		classRow, probabilityRow := "", ""
		for c := 0; c < w; c++ {
			values := append([]float64(nil), d.MeanValues...)
			values[0] = loX + (float64(c)+0.5)*(hiX-loX)/float64(w)
			values[1] = hiY - (float64(r)+0.5)*(hiY-loY)/float64(h)
			v := d.Vector(values)
			k := predictedClass(softmaxProbabilities(soft.Weights, v))
			cells[k]++
			classRow += fmt.Sprint(k)
			probabilityRow += fmt.Sprint(binIndex(probability(score(m.Weights, v))))
		}
		classes = append(classes, classRow)
		probabilityRows = append(probabilityRows, probabilityRow)
	}
	lines := []string{line("map", d.Names[0], d.Names[1], "width", w, "height", h), "softmax_classes"}
	lines = append(lines, classes...)
	lines = append(lines, "cells "+integerText(cells), "newton_probability")
	return append(lines, probabilityRows...)
}
func main() {
	d := readData()
	s := d.Settings
	results := []CrossValidation{}
	for i := range s["LAMBDAS"] {
		results = append(results, crossValidate(d, s.Real("LAMBDAS", i), d.Count))
	}
	best := results[0]
	for _, r := range results {
		if r.Loss <= best.Loss {
			best = r
		}
	}
	mean := sequentialSum(best.FoldLosses) / 5
	spread := 0.0
	for _, v := range best.FoldLosses {
		diff := v - mean
		spread += diff * diff
	}
	se := math.Sqrt(spread/4) / math.Sqrt(5)
	oneSE := best.Lambda
	for _, r := range results {
		if r.Loss <= best.Loss+se {
			oneSE = r.Lambda
		}
	}
	l := best.Lambda
	gd := gradientDescent(d.TrainVectors, d.TrainTargets, l, s.Real("GD", 0), s.Int("GD", 1))
	sgd := stochasticDescent(d.TrainVectors, d.TrainTargets, l, s.Real("SGD", 0), s.Int("SGD", 1), s.Int("SGD", 2), int64(s.Int("SGD", 3)))
	newton := newBinaryModel("newton", newtonMethod(d.TrainVectors, d.TrainTargets, l), d)
	models := []BinaryModel{newBinaryModel("gd", gd, d), newBinaryModel("sgd", sgd, d), newton}
	soft := newSoftmaxModel(softmaxTrain(d.TrainVectors, d.TrainLabels, d.Classes, s.Real("SOFTMAX", 2), s.Real("SOFTMAX", 0), s.Int("SOFTMAX", 1)), d)
	in := influence(newton.Weights, d.TrainVectors, d.TrainTargets, l)
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	writeParts("weights.txt", weightsParts(d, models, soft, in, l))
	writeLines("loss_trace.csv", traceLines(d, models, soft, l))
	writeLines("predictions.csv", predictionLines(d, models, soft))
	parts := [][]string{dataPart(d), crossValidationPart(d, results, best, se, oneSE), lambdaPathPart(d), degreePart(d, l), learningPart(d, l)}
	for _, m := range models {
		parts = append(parts, binaryPart(d, m, l))
	}
	parts = append(parts, comparisonPart(d, models), diagnosticsPart(d, newton, in, l), importancePart(d,
		newton, soft), profilePart(d, newton, soft), softmaxPart(d, soft, newton), oneVsRestPart(d,
		soft), mapPart(d, newton, soft))
	writeParts("evaluation.txt", parts)
	writeLines("roc.csv", rocLines(d, models))
}
