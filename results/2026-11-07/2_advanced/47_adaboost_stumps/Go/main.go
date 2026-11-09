package main

import (
	"fmt"
	"math"
	"sort"
	"strings"
)

type Minstd struct{ State int64 }

func (r *Minstd) draw() int64 { r.State = 48271 * r.State % 2147483647; return r.State }
func trainVariant(variant string, rows []Row, p Params) Model {
	switch variant {
	case "discrete":
		return trainDiscrete(rows, p.Rounds, nil, 1, nil)
	case "real":
		return trainReal(rows, p.Rounds, p.Bins, p.Smoothing, p.Convergence)
	case "gentle":
		return trainGentle(rows, p.Rounds)
	case "logit":
		return trainLogit(rows, p.Rounds, p.Clip)
	}
	panic("unknown variant")
}
func rowScore(rounds []Round, values []float64) float64 {
	total := 0.0
	for _, r := range rounds {
		total += r.Stump.output(values)
	}
	return total
}
func scoreRows(rounds []Round, rows []Row) []float64 {
	out := make([]float64, len(rows))
	for i, row := range rows {
		out[i] = rowScore(rounds, row.Values)
	}
	return out
}
func addRoundScores(r Round, rows []Row, scores []float64) {
	for i, row := range rows {
		scores[i] += r.Stump.output(row.Values)
	}
}
func magnitude(r Round) float64 {
	value := 0.0
	for _, v := range r.Stump.Values {
		value = math.Max(value, math.Abs(v))
	}
	return value
}
func totalMagnitude(rounds []Round) float64 {
	s := 0.0
	for _, r := range rounds {
		s += magnitude(r)
	}
	return s
}
func contributions(rounds []Round, values []float64, features int) []float64 {
	out := make([]float64, features)
	for _, r := range rounds {
		out[r.Stump.Feature] += r.Stump.output(values)
	}
	return out
}
func countErrors(rows []Row, scores []float64) int {
	count := 0
	for i, row := range rows {
		if prediction(scores[i]) != row.Label {
			count++
		}
	}
	return count
}
func loss(rows []Row, scores []float64, variant string) float64 {
	total := 0.0
	for i, row := range rows {
		if variant == "logit" {
			total += math.Log(1 + math.Exp(-2*float64(row.Label)*scores[i]))
		} else {
			total += math.Exp(-float64(row.Label) * scores[i])
		}
	}
	return total / float64(len(rows))
}
func metricsLine(kind, variant string, rounds int, rows []Row, scores []float64) string {
	tp, fp, tn, fn := 0, 0, 0, 0
	for i, row := range rows {
		if prediction(scores[i]) == 1 {
			if row.Label == 1 {
				tp++
			} else {
				fp++
			}
		} else if row.Label == -1 {
			tn++
		} else {
			fn++
		}
	}
	a, b := auc(rows, scores)
	return fmt.Sprintf("%s %s rounds %d correct %d/%d accuracy %s tp %d fp %d tn %d fn %d precision %s recall %s f1 %s auc %s loss %s",
		kind, variant, rounds, tp+tn, len(rows), ratio(tp+tn, len(rows)), tp, fp, tn, fn, ratio(tp,
			tp+fp), ratio(tp, tp+fn), ratio(2*tp, 2*tp+fp+fn), ratio(a, b), number(loss(rows, scores,
			variant)))
}

type CurvePoint struct {
	Round, TrainErrors, TestErrors int
	TrainLoss, TestLoss, Margin    float64
}

func trainingCurve(rounds []Round, training, testing []Row, variant string) []CurvePoint {
	trainScores, testScores := make([]float64, len(training)), make([]float64, len(testing))
	scale := 0.0
	curve := []CurvePoint{}
	for j, r := range rounds {
		addRoundScores(r, training, trainScores)
		addRoundScores(r, testing, testScores)
		scale += magnitude(r)
		minimum := math.Inf(1)
		for i, row := range training {
			minimum = math.Min(minimum, float64(row.Label)*trainScores[i])
		}
		curve = append(curve, CurvePoint{j + 1, countErrors(training, trainScores), countErrors(testing,
			testScores), loss(training, trainScores, variant), loss(testing, testScores, variant),
			minimum / scale})
	}
	return curve
}

type Fold struct {
	Indices []int
	Train   int
	Model   Model
	Errors  []int
}
type CrossValidation struct {
	Folds    []Fold
	Errors   []int
	Selected int
	Scores   []float64
}

func crossValidate(rows []Row, p Params) CrossValidation {
	space := newSearchSpace(rows)
	cv := CrossValidation{Errors: make([]int, p.Rounds), Scores: make([]float64, len(rows))}
	for fold := 0; fold < p.Folds; fold++ {
		indices := []int{}
		for i := range rows {
			if i%p.Folds == fold {
				indices = append(indices, i)
			}
		}
		n := len(rows) - len(indices)
		weights := make([]float64, len(rows))
		for i := range weights {
			if i%p.Folds != fold {
				weights[i] = 1 / float64(n)
			}
		}
		model := trainDiscrete(rows, p.Rounds, weights, 1, space)
		validation := []Row{}
		for _, i := range indices {
			validation = append(validation, rows[i])
		}
		scores := make([]float64, len(validation))
		errors := make([]int, p.Rounds)
		for t := 0; t < p.Rounds; t++ {
			if t < len(model.Rounds) {
				addRoundScores(model.Rounds[t], validation, scores)
			}
			errors[t] = countErrors(validation, scores)
			cv.Errors[t] += errors[t]
		}
		cv.Folds = append(cv.Folds, Fold{indices, n, model, errors})
	}
	best := 0
	for t := 1; t < p.Rounds; t++ {
		if cv.Errors[t] < cv.Errors[best] {
			best = t
		}
	}
	cv.Selected = best + 1
	for _, fold := range cv.Folds {
		rounds := fold.Model.Rounds[:min(cv.Selected, len(fold.Model.Rounds))]
		for _, i := range fold.Indices {
			cv.Scores[i] = rowScore(rounds, rows[i].Values)
		}
	}
	return cv
}

type Importance struct {
	Scores        []float64
	Counts, Order []int
	Total         float64
}

func magnitudeImportance(rounds []Round, features int, samme bool) Importance {
	out := Importance{Scores: make([]float64, features), Counts: make([]int, features), Order: make([]int, features)}
	for _, r := range rounds {
		value := magnitude(r)
		if samme {
			value = r.Alpha
		}
		out.Scores[r.Stump.Feature] += value
		out.Counts[r.Stump.Feature]++
	}
	out.Total = sum(out.Scores)
	for j := range out.Order {
		out.Order[j] = j
	}
	sort.SliceStable(out.Order, func(i, j int) bool { return out.Scores[out.Order[i]] > out.Scores[out.Order[j]] })
	return out
}
func importanceLines(v Importance, features []string) []string {
	lines := []string{"importance"}
	for rank, j := range v.Order {
		lines = append(lines, fmt.Sprintf("%d %s score %s share %s rounds %d", rank+1, features[j], number(v.Scores[j]),
			ratioReal(v.Scores[j], v.Total), v.Counts[j]))
	}
	return lines
}

type VariantAnalysis struct {
	Name        string
	Full        Model
	Rounds      []Round
	Scale       float64
	Train, Test []float64
	Curve       []CurvePoint
	Importance  Importance
}

func analyzeVariants(in Inputs, selected int) []VariantAnalysis {
	out := []VariantAnalysis{}
	for _, name := range in.Params.Variants {
		model := trainVariant(name, in.Train, in.Params)
		rounds := model.Rounds
		if name == "discrete" {
			rounds = rounds[:min(selected, len(rounds))]
		}
		out = append(out, VariantAnalysis{name, model, rounds, totalMagnitude(rounds), scoreRows(rounds,
			in.Train), scoreRows(rounds, in.Test), trainingCurve(model.Rounds, in.Train, in.Test,
			name), magnitudeImportance(rounds, len(in.Features), false)})
	}
	return out
}
func numberList(values []float64) string {
	out := make([]string, len(values))
	for i, v := range values {
		out[i] = number(v)
	}
	return strings.Join(out, " ")
}
func ensembleLines(in Inputs, analysis []VariantAnalysis, cv CrossValidation) []string {
	sections := [][]string{}
	p := in.Params
	for _, a := range analysis {
		model := a.Full
		header := fmt.Sprintf("variant %s rounds %d stop %s", a.Name, len(model.Rounds), model.Stop)
		if a.Name == "real" {
			header += fmt.Sprintf(" bins %d smoothing %s convergence %s", p.Bins, number(p.Smoothing), numberDigits(p.Convergence, 6))
		} else if a.Name == "logit" {
			header += " clip " + number(p.Clip)
		}
		lines := []string{header}
		if a.Name == "real" {
			for j, cuts := range model.Cuts {
				lines = append(lines, "cuts "+in.Features[j]+" "+numberList(cuts))
			}
		}
		for t, r := range model.Rounds {
			s := r.Stump
			line := fmt.Sprintf("round %d feature %s", t+1, in.Features[s.Feature])
			if a.Name == "real" {
				line += fmt.Sprintf(" z %s bound %s values %s", number(r.Z), number(r.Bound), numberList(s.Values))
			} else {
				line += " threshold " + number(s.Thresholds[0])
				if a.Name == "discrete" {
					line += fmt.Sprintf(" polarity %d error %s alpha %s z %s bound %s", r.Polarity, number(r.Error), number(r.Alpha), number(r.Z), number(r.Bound))
				} else {
					line += fmt.Sprintf(" left %s right %s error %s", number(s.Values[0]), number(s.Values[1]), number(r.Error))
					if a.Name == "logit" {
						line += " loss " + number(r.Loss)
					}
				}
			}
			lines = append(lines, line)
			if a.Name == "discrete" {
				maximum := 0
				squared := 0.0
				for i, w := range r.Weights {
					if w > r.Weights[maximum] {
						maximum = i
					}
					squared += w * w
				}
				lines = append(lines, fmt.Sprintf("weights %d max %s id %s ess %s", t+1, numberDigits(r.Weights[maximum], 6), in.Train[maximum].ID, number(1/squared)))
			}
		}
		if a.Name == "discrete" {
			lines = append(lines, fmt.Sprintf("cv folds %d selected %d errors %d/%d", p.Folds, cv.Selected, cv.Errors[cv.Selected-1], len(in.Train)))
			for f, fold := range cv.Folds {
				v := len(fold.Indices)
				lines = append(lines, fmt.Sprintf("fold %d train %d validation %d rounds %d stop %s selected %d/%d final %d/%d",
					f+1, fold.Train, v, len(fold.Model.Rounds), fold.Model.Stop, fold.Errors[cv.Selected-1],
					v, fold.Errors[len(fold.Errors)-1], v))
			}
			lines = append(lines, "cv_errors "+ints(cv.Errors))
		}
		sections = append(sections, lines)
	}
	return separateSections(sections)
}
func errorCurveLines(in Inputs, analysis []VariantAnalysis, sammeCurve [][3]int) []string {
	lines := []string{"variant,round,train_error,test_error,train_loss,test_loss,min_margin"}
	for _, a := range analysis {
		for _, c := range a.Curve {
			lines = append(lines, fmt.Sprintf("%s,%d,%s,%s,%s,%s,%s", a.Name, c.Round, ratio(c.TrainErrors,
				len(in.Train)), ratio(c.TestErrors, len(in.Test)), number(c.TrainLoss), number(c.TestLoss),
				number(c.Margin)))
		}
	}
	for _, c := range sammeCurve {
		lines = append(lines, fmt.Sprintf("samme,%d,%s,%s,-,-,-", c[0], ratio(c[1], len(in.MultiTrain)), ratio(c[2], len(in.MultiTest))))
	}
	return lines
}
func predictionLines(in Inputs, analysis []VariantAnalysis) []string {
	lines := []string{"id,variant,score,label," + strings.Join(in.Features, ",")}
	for i, row := range in.Test {
		for _, a := range analysis {
			parts := contributions(a.Rounds, row.Values, len(in.Features))
			fields := []string{row.ID, a.Name, number(a.Test[i]), fmt.Sprint(prediction(a.Test[i]))}
			for _, v := range parts {
				fields = append(fields, number(v))
			}
			lines = append(lines, strings.Join(fields, ","))
		}
	}
	return lines
}
func rocLines(in Inputs, analysis []VariantAnalysis) []string {
	lines := []string{"variant,threshold,tp,fp"}
	for _, a := range analysis {
		set := map[float64]bool{}
		for _, s := range a.Test {
			set[s] = true
		}
		values := []float64{}
		for v := range set {
			values = append(values, v)
		}
		sort.Sort(sort.Reverse(sort.Float64Slice(values)))
		for _, threshold := range values {
			tp, fp := 0, 0
			for i, row := range in.Test {
				if a.Test[i] >= threshold {
					if row.Label == 1 {
						tp++
					} else {
						fp++
					}
				}
			}
			lines = append(lines, fmt.Sprintf("%s,%s,%d,%d", a.Name, number(threshold), tp, fp))
		}
	}
	return lines
}

type PermutationResult struct{ Feature, Drop, Minimum, Maximum int }

func permutationImportance(rounds []Round, rows []Row, features, repeats int, rng *Minstd) (int, []PermutationResult) {
	base := len(rows) - countErrors(rows, scoreRows(rounds, rows))
	out := []PermutationResult{}
	for j := 0; j < features; j++ {
		drop, minimum, maximum := 0, len(rows), 0
		for r := 0; r < repeats; r++ {
			permutation := make([]int, len(rows))
			for i := range permutation {
				permutation[i] = i
			}
			for i := len(rows) - 1; i >= 1; i-- {
				other := int(rng.draw() % int64(i+1))
				permutation[i], permutation[other] = permutation[other], permutation[i]
			}
			correct := 0
			for i, row := range rows {
				values := append([]float64{}, row.Values...)
				values[j] = rows[permutation[i]].Values[j]
				if prediction(rowScore(rounds, values)) == row.Label {
					correct++
				}
			}
			drop += base - correct
			minimum = min(minimum, correct)
			maximum = max(maximum, correct)
		}
		out = append(out, PermutationResult{j, drop, minimum, maximum})
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].Drop > out[j].Drop })
	return base, out
}
func margins(rows []Row, scores []float64, scale float64) []float64 {
	out := make([]float64, len(rows))
	for i, row := range rows {
		out[i] = float64(row.Label) * scores[i] / scale
	}
	return out
}
func minimum(values []float64) float64 {
	v := values[0]
	for _, x := range values[1:] {
		v = math.Min(v, x)
	}
	return v
}
func maximum(values []float64) float64 {
	v := values[0]
	for _, x := range values[1:] {
		v = math.Max(v, x)
	}
	return v
}
func marginLines(in Inputs, analysis []VariantAnalysis) []string {
	sections := [][]string{}
	p := in.Params
	rng := Minstd{p.PermutationSeed}
	for _, a := range analysis {
		train, test := margins(in.Train, a.Train, a.Scale), margins(in.Test, a.Test, a.Scale)
		lines := []string{fmt.Sprintf("variant %s rounds %d scale %s", a.Name, len(a.Rounds), number(a.Scale)),
			fmt.Sprintf("train min %s mean %s", number(minimum(train)), number(sum(train)/float64(len(train))))}
		for _, theta := range p.Margins {
			count := countAtMost(train, theta)
			lines = append(lines, fmt.Sprintf("train le %s %d/%d %s", number(theta), count, len(train), ratio(count, len(train))))
		}
		hist := make([]int, 20)
		for _, v := range train {
			hist[min(19, int(math.Floor((v+1)*10)))]++
		}
		lines = append(lines, "histogram "+ints(hist))
		hardest := make([]int, len(train))
		for i := range hardest {
			hardest[i] = i
		}
		sort.SliceStable(hardest, func(i, j int) bool { return train[hardest[i]] < train[hardest[j]] })
		for _, i := range hardest[:5] {
			lines = append(lines, fmt.Sprintf("hardest %s label %d margin %s", in.Train[i].ID, in.Train[i].Label, number(train[i])))
		}
		lines = append(lines, fmt.Sprintf("test min %s mean %s", number(minimum(test)), number(sum(test)/float64(len(test)))))
		for _, theta := range p.Margins {
			count := countAtMost(test, theta)
			lines = append(lines, fmt.Sprintf("test le %s %d/%d %s", number(theta), count, len(test), ratio(count, len(test))))
		}
		for _, theta := range p.Margins {
			confident, correct := 0, 0
			for i, v := range test {
				if math.Abs(v) > theta {
					confident++
					if prediction(a.Test[i]) == in.Test[i].Label {
						correct++
					}
				}
			}
			lines = append(lines, fmt.Sprintf("test confident %s %d/%d correct %d/%d %s", number(theta), confident,
				len(test), correct, confident, ratio(correct, confident)))
		}
		lines = append(lines, importanceLines(a.Importance, in.Features)...)
		base, permutation := permutationImportance(a.Rounds, in.Test, len(in.Features), p.Permutations, &rng)
		lines = append(lines, fmt.Sprintf("permutation repeats %d base %d/%d", p.Permutations, base, len(in.Test)))
		for rank, v := range permutation {
			lines = append(lines, fmt.Sprintf("%d %s drop %s min %d/%d max %d/%d", rank+1, in.Features[v.Feature],
				ratio(v.Drop, p.Permutations*len(in.Test)), v.Minimum, len(in.Test), v.Maximum, len(in.Test)))
		}
		sections = append(sections, lines)
	}
	return separateSections(sections)
}
func shapeLines(in Inputs, analysis []VariantAnalysis) []string {
	sections := [][]string{}
	for _, a := range analysis {
		lines := []string{fmt.Sprintf("variant %s rounds %d", a.Name, len(a.Rounds))}
		for j, name := range in.Features {
			collected := []Round{}
			set := map[float64]bool{}
			for _, r := range a.Rounds {
				if r.Stump.Feature == j {
					collected = append(collected, r)
					for _, cut := range r.Stump.Thresholds {
						set[cut] = true
					}
				}
			}
			cuts := []float64{}
			for c := range set {
				cuts = append(cuts, c)
			}
			sort.Float64s(cuts)
			values := make([]float64, len(cuts)+1)
			for _, r := range collected {
				values[0] += r.Stump.Values[0]
			}
			for k, cut := range cuts {
				for _, r := range collected {
					index := sort.Search(len(r.Stump.Thresholds), func(i int) bool { return r.Stump.Thresholds[i] > cut })
					values[k+1] += r.Stump.Values[index]
				}
			}
			lines = append(lines, fmt.Sprintf("feature %s rounds %d cuts %d range %s", name, len(collected), len(cuts), number(maximum(values)-minimum(values))))
			for i, v := range values {
				lower, upper := "-inf", "inf"
				if i > 0 {
					lower = number(cuts[i-1])
				}
				if i < len(cuts) {
					upper = number(cuts[i])
				}
				lines = append(lines, "interval "+lower+" "+upper+" value "+number(v))
			}
		}
		sections = append(sections, lines)
	}
	return separateSections(sections)
}
func calibrationLines(variant string, rows []Row, scores []float64) []string {
	counts, positive := [5]int{}, [5]int{}
	totals := [5]float64{}
	brier := 0.0
	for i, row := range rows {
		p := 1 / (1 + math.Exp(-2*scores[i]))
		target := 0
		if row.Label == 1 {
			target = 1
		}
		d := p - float64(target)
		brier += d * d
		b := min(4, int(math.Floor(p*5)))
		counts[b]++
		totals[b] += p
		positive[b] += target
	}
	lines := []string{fmt.Sprintf("calibration %s brier %s", variant, number(brier/float64(len(rows))))}
	ranges := []string{"0.0-0.2", "0.2-0.4", "0.4-0.6", "0.6-0.8", "0.8-1.0"}
	for b, interval := range ranges {
		lines = append(lines, fmt.Sprintf("bin %s count %d mean %s positives %d", interval, counts[b], ratioReal(totals[b], float64(counts[b])), positive[b]))
	}
	return lines
}
func comparisonLines(in Inputs, analysis []VariantAnalysis) []string {
	wrong := []string{}
	for i, row := range in.Test {
		all := true
		for _, a := range analysis {
			if prediction(a.Test[i]) == row.Label {
				all = false
				break
			}
		}
		if all {
			wrong = append(wrong, row.ID)
		}
	}
	line := fmt.Sprintf("all_wrong %d", len(wrong))
	if len(wrong) > 0 {
		line += " " + strings.Join(wrong, " ")
	}
	lines := []string{line, "agreement"}
	for i, a := range analysis {
		for _, b := range analysis[i+1:] {
			agree, first, second := 0, 0, 0
			for j, row := range in.Test {
				x, y := prediction(a.Test[j]), prediction(b.Test[j])
				if x == y {
					agree++
				}
				if x == row.Label && y != row.Label {
					first++
				}
				if y == row.Label && x != row.Label {
					second++
				}
			}
			d := abs(first-second) - 1
			lines = append(lines, fmt.Sprintf("%s %s agree %d/%d only_first %d only_second %d chi2 %s", a.Name,
				b.Name, agree, len(in.Test), first, second, ratio(d*d, first+second)))
		}
	}
	return lines
}
func abs(v int) int {
	if v < 0 {
		return -v
	}
	return v
}
func bootstrapLines(in Inputs, analysis []VariantAnalysis) []string {
	p := in.Params
	rng := Minstd{p.BootstrapSeed}
	counts := make([][]int, len(analysis))
	for v := range counts {
		counts[v] = make([]int, p.Bootstrap)
	}
	for b := 0; b < p.Bootstrap; b++ {
		selected := make([]int, len(in.Test))
		for i := range selected {
			selected[i] = int(rng.draw() % int64(len(in.Test)))
		}
		for v, a := range analysis {
			for _, i := range selected {
				if prediction(a.Test[i]) == in.Test[i].Label {
					counts[v][b]++
				}
			}
		}
	}
	lines := []string{fmt.Sprintf("bootstrap samples %d seed %d", p.Bootstrap, p.BootstrapSeed)}
	trim := p.Bootstrap / 40
	for v, a := range analysis {
		ordered := append([]int{}, counts[v]...)
		sort.Ints(ordered)
		total := 0
		for _, n := range ordered {
			total += n
		}
		lines = append(lines, fmt.Sprintf("%s mean %s low %s high %s", a.Name, ratio(total, p.Bootstrap*len(in.Test)),
			ratio(ordered[trim], len(in.Test)), ratio(ordered[p.Bootstrap-trim-1], len(in.Test))))
	}
	for a := range analysis {
		for b := a + 1; b < len(analysis); b++ {
			first, tie, second := 0, 0, 0
			for j, x := range counts[a] {
				y := counts[b][j]
				if x > y {
					first++
				} else if x == y {
					tie++
				} else {
					second++
				}
			}
			lines = append(lines, fmt.Sprintf("%s %s first %d tie %d second %d", analysis[a].Name, analysis[b].Name, first, tie, second))
		}
	}
	return lines
}
func featureSummary(rows []Row, j int) string {
	values := make([]float64, len(rows))
	set := map[float64]bool{}
	for i, row := range rows {
		values[i] = row.Values[j]
		set[values[i]] = true
	}
	return fmt.Sprintf("%s %s %s %d", number(minimum(values)), number(maximum(values)), number(sum(values)/float64(len(rows))), len(set))
}
func positiveCount(rows []Row) int {
	n := 0
	for _, r := range rows {
		if r.Label == 1 {
			n++
		}
	}
	return n
}
func curveMinima(curve []CurvePoint) (CurvePoint, CurvePoint) {
	train, test := curve[0], curve[0]
	for _, c := range curve[1:] {
		if c.TrainErrors < train.TrainErrors {
			train = c
		}
		if c.TestErrors < test.TestErrors {
			test = c
		}
	}
	return train, test
}
func summaryLines(in Inputs, analysis []VariantAnalysis, cv CrossValidation) []string {
	n, m := len(in.Train), len(in.Test)
	lines := []string{fmt.Sprintf("data train %d test %d features %d positives %d %d", n, m, len(in.Features), positiveCount(in.Train), positiveCount(in.Test))}
	for j, name := range in.Features {
		lines = append(lines, "feature "+name+" train "+featureSummary(in.Train, j)+" test "+featureSummary(in.Test, j))
	}
	errors := cv.Errors[cv.Selected-1]
	lines = append(lines, fmt.Sprintf("cv selected %d errors %d/%d rate %s", cv.Selected, errors, n,
		ratio(errors, n)), metricsLine("oof", "discrete", cv.Selected, in.Train, cv.Scores))
	ct, ce := make([]float64, n), make([]float64, m)
	rounds := 0
	for _, a := range analysis {
		lines = append(lines, metricsLine("train", a.Name, len(a.Rounds), in.Train, a.Train), metricsLine("test", a.Name, len(a.Rounds), in.Test, a.Test))
		rounds += len(a.Rounds)
		for i, s := range a.Train {
			ct[i] += s / a.Scale
		}
		for i, s := range a.Test {
			ce[i] += s / a.Scale
		}
	}
	lines = append(lines, metricsLine("train", "committee", rounds, in.Train, ct), metricsLine("test", "committee", rounds, in.Test, ce))
	for _, a := range analysis {
		train, test := curveMinima(a.Curve)
		lines = append(lines, fmt.Sprintf("curve %s rounds %d train_min %d/%d at %d test_min %d/%d at %d",
			a.Name, len(a.Curve), train.TrainErrors, n, train.Round, test.TestErrors, m, test.Round))
	}
	lines = append(lines, comparisonLines(in, analysis)...)
	lines = append(lines, bootstrapLines(in, analysis)...)
	for _, a := range analysis {
		lines = append(lines, calibrationLines(a.Name, in.Test, a.Test)...)
	}
	return lines
}
func classPrediction(scores []float64) int {
	best := 0
	for k := 1; k < len(scores); k++ {
		if scores[k] > scores[best] {
			best = k
		}
	}
	return best + 1
}
func classPredictions(scores [][]float64) []int {
	out := make([]int, len(scores))
	for i, s := range scores {
		out[i] = classPrediction(s)
	}
	return out
}
func classErrors(rows []Row, predictions []int) int {
	n := 0
	for i, row := range rows {
		if row.Label != predictions[i] {
			n++
		}
	}
	return n
}
func sammeProgression(rounds []Round, training, testing []Row, classes int) ([][]float64, [][]float64, [][3]int) {
	train, test := make([][]float64, len(training)), make([][]float64, len(testing))
	for i := range train {
		train[i] = make([]float64, classes)
	}
	for i := range test {
		test[i] = make([]float64, classes)
	}
	curve := [][3]int{}
	for t, r := range rounds {
		for i, row := range training {
			train[i][int(r.Stump.output(row.Values))-1] += r.Alpha
		}
		for i, row := range testing {
			test[i][int(r.Stump.output(row.Values))-1] += r.Alpha
		}
		curve = append(curve, [3]int{t + 1, classErrors(training, classPredictions(train)), classErrors(testing, classPredictions(test))})
	}
	return train, test, curve
}
func confusionLines(rows []Row, predictions []int, classes int) []string {
	m := confusion(rows, predictions, classes)
	lines := []string{"confusion"}
	for _, row := range m {
		lines = append(lines, ints(row))
	}
	for c := 0; c < classes; c++ {
		predicted, actual := 0, 0
		for k := 0; k < classes; k++ {
			predicted += m[k][c]
			actual += m[c][k]
		}
		lines = append(lines, fmt.Sprintf("class %d precision %s recall %s", c+1, ratio(m[c][c], predicted), ratio(m[c][c], actual)))
	}
	return lines
}
func binaryRows(rows []Row, class int) []Row {
	out := make([]Row, len(rows))
	for i, r := range rows {
		label := -1
		if r.Label == class {
			label = 1
		}
		out[i] = Row{r.ID, r.Values, label}
	}
	return out
}
func multiclassReport(in Inputs) ([]string, [][3]int) {
	p := in.Params
	training, testing := in.MultiTrain, in.MultiTest
	model := trainSamme(training, p.SammeRounds, p.Classes)
	trainScores, testScores, curve := sammeProgression(model.Rounds, training, testing, p.Classes)
	trainPred, testPred := classPredictions(trainScores), classPredictions(testScores)
	lines := []string{fmt.Sprintf("samme classes %d train %d test %d rounds %d stop %s", p.Classes, len(training), len(testing), len(model.Rounds), model.Stop)}
	for t, r := range model.Rounds {
		s := r.Stump
		lines = append(lines, fmt.Sprintf("round %d feature %s threshold %s left %d right %d error %s alpha %s",
			t+1, in.MultiFeatures[s.Feature], number(s.Thresholds[0]), int(s.Values[0]), int(s.Values[1]),
			number(r.Error), number(r.Alpha)))
	}
	te, ve := classErrors(training, trainPred), classErrors(testing, testPred)
	lines = append(lines, fmt.Sprintf("train errors %d/%d rate %s", te, len(training), ratio(te, len(training))),
		fmt.Sprintf("test errors %d/%d rate %s", ve, len(testing), ratio(ve, len(testing))))
	lines = append(lines, confusionLines(testing, testPred, p.Classes)...)
	lines = append(lines, importanceLines(magnitudeImportance(model.Rounds, len(in.MultiFeatures), true), in.MultiFeatures)...)
	lines = append(lines, "", fmt.Sprintf("ovr classes %d rounds %d", p.Classes, p.SammeRounds))
	ovrTrain, ovrTest := make([][]float64, len(training)), make([][]float64, len(testing))
	for i := range ovrTrain {
		ovrTrain[i] = make([]float64, p.Classes)
	}
	for i := range ovrTest {
		ovrTest[i] = make([]float64, p.Classes)
	}
	for class := 1; class <= p.Classes; class++ {
		bt, bv := binaryRows(training, class), binaryRows(testing, class)
		bm := trainDiscrete(bt, p.SammeRounds, nil, 1, nil)
		ts, vs := scoreRows(bm.Rounds, bt), scoreRows(bm.Rounds, bv)
		for i, s := range ts {
			ovrTrain[i][class-1] = s
		}
		for i, s := range vs {
			ovrTest[i][class-1] = s
		}
		lines = append(lines, fmt.Sprintf("class %d rounds %d stop %s positives %d train_errors %d/%d test_errors %d/%d",
			class, len(bm.Rounds), bm.Stop, positiveCount(bt), countErrors(bt, ts), len(training),
			countErrors(bv, vs), len(testing)))
	}
	ovrTrainPred, ovrTestPred := classPredictions(ovrTrain), classPredictions(ovrTest)
	te, ve = classErrors(training, ovrTrainPred), classErrors(testing, ovrTestPred)
	lines = append(lines, fmt.Sprintf("train errors %d/%d rate %s", te, len(training), ratio(te, len(training))),
		fmt.Sprintf("test errors %d/%d rate %s", ve, len(testing), ratio(ve, len(testing))))
	lines = append(lines, confusionLines(testing, ovrTestPred, p.Classes)...)
	agreement := 0
	for i, a := range testPred {
		if a == ovrTestPred[i] {
			agreement++
		}
	}
	lines = append(lines, fmt.Sprintf("agreement %d/%d", agreement, len(testing)), "", "predictions")
	for i, row := range testing {
		lines = append(lines, fmt.Sprintf("%s class %d samme %d ovr %d scores %s", row.ID, row.Label, testPred[i], ovrTestPred[i], numberList(testScores[i])))
	}
	return lines, curve
}
func modelErrors(model Model, training, testing []Row) (int, int) {
	return countErrors(training, scoreRows(model.Rounds, training)), countErrors(testing, scoreRows(model.Rounds, testing))
}
func testMinimum(rounds []Round, testing []Row) (int, int) {
	scores := make([]float64, len(testing))
	minimum, at := len(testing)+1, 0
	for t, r := range rounds {
		addRoundScores(r, testing, scores)
		n := countErrors(testing, scores)
		if n < minimum {
			minimum, at = n, t+1
		}
	}
	return minimum, at
}
func reducedRows(rows []Row, features []int) []Row {
	out := make([]Row, len(rows))
	for i, r := range rows {
		values := make([]float64, len(features))
		for j, f := range features {
			values[j] = r.Values[f]
		}
		out[i] = Row{r.ID, values, r.Label}
	}
	return out
}
func experimentLines(in Inputs, analysis []VariantAnalysis, selected int) []string {
	p := in.Params
	n, m := len(in.Train), len(in.Test)
	lines := []string{}
	for _, q := range p.Sizes {
		size := n * q / 100
		subset := in.Train[:size]
		lines = append(lines, fmt.Sprintf("size %d rows %d", q, size))
		for _, name := range p.Variants {
			model := trainVariant(name, subset, p)
			te, ve := modelErrors(model, subset, in.Test)
			lines = append(lines, fmt.Sprintf("%s rounds %d stop %s train_errors %d/%d test_errors %d/%d", name, len(model.Rounds), model.Stop, te, size, ve, m))
		}
	}
	for _, nu := range p.Shrinkage {
		model := trainDiscrete(in.Train, p.Rounds, nil, nu, nil)
		te, ve := modelErrors(model, in.Train, in.Test)
		minimum, at := testMinimum(model.Rounds, in.Test)
		lines = append(lines, fmt.Sprintf("shrinkage %s rounds %d stop %s train_errors %d/%d test_errors %d/%d test_min %d/%d at %d",
			number(nu), len(model.Rounds), model.Stop, te, n, ve, m, minimum, m, at))
	}
	var ranked []int
	for _, a := range analysis {
		if a.Name == "discrete" {
			ranked = a.Importance.Order
			break
		}
	}
	for count := 1; count <= len(in.Features); count++ {
		features := append([]int{}, ranked[:count]...)
		sort.Ints(features)
		training, testing := reducedRows(in.Train, features), reducedRows(in.Test, features)
		model := trainDiscrete(training, selected, nil, 1, nil)
		te, ve := modelErrors(model, training, testing)
		names := []string{}
		for _, j := range features {
			names = append(names, in.Features[j])
		}
		lines = append(lines, fmt.Sprintf("top %d features %s rounds %d train_errors %d/%d test_errors %d/%d",
			count, strings.Join(names, " "), len(model.Rounds), te, n, ve, m))
	}
	for _, q := range p.Noise {
		count := n * q / 100
		rng := Minstd{p.NoiseSeed}
		permutation := make([]int, n)
		for i := range permutation {
			permutation[i] = i
		}
		for i := 0; i < count; i++ {
			other := int(rng.draw()%int64(n-i)) + i
			permutation[i], permutation[other] = permutation[other], permutation[i]
		}
		flipped := make([]bool, n)
		for _, i := range permutation[:count] {
			flipped[i] = true
		}
		noisy := append([]Row{}, in.Train...)
		for i := range noisy {
			if flipped[i] {
				noisy[i].Label = -noisy[i].Label
			}
		}
		lines = append(lines, fmt.Sprintf("noise %d flipped %d", q, count))
		for _, name := range p.Variants {
			model := trainVariant(name, noisy, p)
			te, ve := modelErrors(model, noisy, in.Test)
			minimum, at := testMinimum(model.Rounds, in.Test)
			weight := 0.0
			for i, w := range model.Rounds[len(model.Rounds)-1].Weights {
				if flipped[i] {
					weight += w
				}
			}
			lines = append(lines, fmt.Sprintf("%s rounds %d stop %s train_errors %d/%d test_errors %d/%d test_min %d/%d at %d flipped_weight %s",
				name, len(model.Rounds), model.Stop, te, n, ve, m, minimum, m, at, number(weight)))
		}
	}
	return lines
}
func separateSections(sections [][]string) []string {
	lines := []string{}
	for _, s := range sections {
		if len(lines) > 0 {
			lines = append(lines, "")
		}
		lines = append(lines, s...)
	}
	return lines
}
func main() {
	in := readInputs()
	cv := crossValidate(in.Train, in.Params)
	analysis := analyzeVariants(in, cv.Selected)
	samme, curve := multiclassReport(in)
	writeLines("ensemble.txt", ensembleLines(in, analysis, cv))
	writeLines("error_curve.csv", errorCurveLines(in, analysis, curve))
	writeLines("predictions.csv", predictionLines(in, analysis))
	writeLines("roc.csv", rocLines(in, analysis))
	writeLines("margins.txt", marginLines(in, analysis))
	writeLines("shapes.txt", shapeLines(in, analysis))
	writeLines("samme.txt", samme)
	writeLines("summary.txt", summaryLines(in, analysis, cv))
	writeLines("experiments.txt", experimentLines(in, analysis, cv.Selected))
}
