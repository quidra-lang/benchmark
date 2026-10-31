package main

import (
	"fmt"
	"math"
	"os"
	"sort"
	"strconv"
	"strings"
)

var modelNames = []string{"multinomial", "bernoulli", "complement", "rocchio", "vote"}
var modelPairs = [][2]int{{0, 1}, {0, 2}, {0, 3}, {1, 2}, {1, 3}, {2, 3}}

type Settings struct {
	Alphas                            []int64
	MinDF, Features                   int
	Bigrams                           bool
	Top                               int
	Curve, Sizes, Thresholds, Lengths []int
	Iterations, Weight, Resamples     int
	Seed                              int64
}

func readLines(name string) []string {
	data, err := os.ReadFile("input/" + name)
	if err != nil {
		panic(err)
	}
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
}
func integer(text string) int { value, _ := strconv.Atoi(text); return value }
func hundredths(text string) int {
	parts := strings.Split(text, ".")
	return 100*integer(parts[0]) + integer(parts[1])
}
func hundredthsText(value int) string { return fmt.Sprintf("%d.%02d", value/100, value%100) }
func loadSettings() Settings {
	values := map[string][]string{}
	for _, line := range readLines("params.txt") {
		fields := strings.Split(line, " ")
		values[fields[0]] = fields[1:]
	}
	value := func(key string) int { return integer(values[key][0]) }
	list := func(key string, decimal bool) []int {
		result := []int{}
		for _, text := range values[key] {
			if decimal {
				result = append(result, hundredths(text))
			} else {
				result = append(result, integer(text))
			}
		}
		return result
	}
	settings := Settings{MinDF: value("MIN_DF"), Features: value("FEATURES"), Bigrams: values["BIGRAMS"][0] == "yes", Top: value("TOP"), Curve: list("CURVE", false), Sizes: list("SIZES", false), Thresholds: list("THRESHOLDS", true), Lengths: list("LENGTHS", false), Iterations: value("EM_ITERATIONS"), Weight: hundredths(values["EM_WEIGHT"][0]), Resamples: value("BOOTSTRAP"), Seed: int64(integer(values["BOOTSTRAP"][1]))}
	for _, text := range values["ALPHAS"] {
		settings.Alphas = append(settings.Alphas, int64(hundredths(text)))
	}
	return settings
}
func writeLines(name string, lines []string) {
	text := ""
	if len(lines) > 0 {
		text = strings.Join(lines, "\n") + "\n"
	}
	if err := os.WriteFile("output/"+name, []byte(text), 0644); err != nil {
		panic(err)
	}
}
func joinParts(parts [][]string) []string {
	lines := []string{}
	for _, part := range parts {
		if len(lines) > 0 {
			lines = append(lines, "")
		}
		lines = append(lines, part...)
	}
	return lines
}
func classCountsText(names []string, counts []int) string {
	parts := []string{}
	for i, name := range names {
		parts = append(parts, fmt.Sprintf("%s %d", name, counts[i]))
	}
	return strings.Join(parts, " ")
}
func bucketOf(value float64, boundaries []float64) int {
	bucket := 0
	for _, boundary := range boundaries {
		if value >= boundary {
			bucket++
		}
	}
	return bucket
}
func realBoundaries(values []int, scale float64) []float64 {
	result := make([]float64, len(values))
	for i, value := range values {
		result[i] = float64(value) / scale
	}
	return result
}
func rounded4(value float64) int64 { return int64(math.RoundToEven(value * 10000)) }
func evaluationFields(e Evaluation) string {
	return fmt.Sprintf("%d,%s,%s", e.Correct, realText(e.Micro), realText(e.Macro))
}
func classLabels(predictions []Prediction) []int {
	result := make([]int, len(predictions))
	for i, prediction := range predictions {
		result[i] = prediction.Label
	}
	return result
}

type RatioEntry struct {
	P, Q int64
	Term int
}

func rankRatios(entries []RatioEntry) {
	sort.Slice(entries, func(i, j int) bool {
		a, b := entries[i], entries[j]
		left, right := a.P*b.Q, b.P*a.Q
		if left != right {
			return left > right
		}
		return a.Term < b.Term
	})
}

type Document struct {
	Name   string
	Label  int
	Tokens Tokens
}
type FoldSummary struct{ Train, Validate, Candidates, Vocabulary int }
type CVRun struct {
	Predictions []int
	Evaluation  Evaluation
	FoldCorrect [5]int
}
type Training struct {
	Bigrams    bool
	Vocabulary Vocabulary
	Counts     TrainingCounts
	Rocchio    Rocchio
	Models     [3]NaiveBayes
}

func makeTraining(documents []Document, bigrams bool, classCount, minDF, size int) Training {
	sequences := make([][]string, len(documents))
	labels := make([]int, len(documents))
	for i, document := range documents {
		sequences[i] = document.Tokens.Terms(bigrams)
		labels[i] = document.Label
	}
	vocabulary := buildVocabulary(sequences, labels, classCount, minDF, size)
	encoded := make([][]int, len(sequences))
	for i, sequence := range sequences {
		encoded[i] = vocabulary.Encode(sequence)
	}
	return Training{Bigrams: bigrams, Vocabulary: vocabulary, Counts: countTraining(encoded, labels, classCount, len(vocabulary.Terms)), Rocchio: trainRocchio(encoded, labels, classCount, vocabulary.Frequencies)}
}
func (t *Training) Train(alphas [3]int64) {
	for kind := 0; kind < 3; kind++ {
		t.Models[kind] = trainModel(kind, t.Counts, alphas[kind])
	}
}
func (t Training) Encode(document Document) []int {
	return t.Vocabulary.Encode(document.Tokens.Terms(t.Bigrams))
}
func (t Training) Classify(model int, sequence []int) Prediction {
	if model == 3 {
		return t.Rocchio.Predict(sequence)
	}
	return t.Models[model].Predict(sequence)
}

type Experiment struct {
	Settings                    Settings
	Classes                     []string
	Training, Tests, Unlabelled []Document
	Labelled, Truths            []int
	Folds                       []FoldSummary
	CVRuns                      [4][]CVRun
	Selected                    [3]int64
	SelectedRuns                [4]CVRun
	Final                       Training
	TestSequences               [][]int
	Predictions                 [5][]Prediction
	Correct                     [5][]bool
}

func loadExperiment() Experiment {
	experiment := Experiment{Settings: loadSettings()}
	stopwords := map[string]bool{}
	for _, word := range readLines("stopwords.txt") {
		stopwords[word] = true
	}
	rows := [][]string{}
	classes := map[string]bool{}
	for _, line := range readLines("train.txt") {
		fields := strings.Split(line, "\t")
		rows = append(rows, fields)
		classes[fields[0]] = true
	}
	for name := range classes {
		experiment.Classes = append(experiment.Classes, name)
	}
	sort.Strings(experiment.Classes)
	positions := map[string]int{}
	for i, name := range experiment.Classes {
		positions[name] = i
	}
	for i, row := range rows {
		experiment.Training = append(experiment.Training, Document{strconv.Itoa(i + 1), positions[row[0]], tokenize(row[1], stopwords)})
	}
	for _, line := range readLines("test.txt") {
		fields := strings.Split(line, "\t")
		label := -1
		if fields[1] != "?" {
			label = positions[fields[1]]
		}
		experiment.Tests = append(experiment.Tests, Document{fields[0], label, tokenize(fields[2], stopwords)})
	}
	for i, text := range readLines("unlabelled.txt") {
		experiment.Unlabelled = append(experiment.Unlabelled, Document{strconv.Itoa(i + 1), -1, tokenize(text, stopwords)})
	}
	for i, document := range experiment.Tests {
		if document.Label >= 0 {
			experiment.Labelled = append(experiment.Labelled, i)
			experiment.Truths = append(experiment.Truths, document.Label)
		}
	}
	return experiment
}
func (e Experiment) trained(documents []Document, bigrams bool, size int) Training {
	training := makeTraining(documents, bigrams, len(e.Classes), e.Settings.MinDF, size)
	training.Train(e.Selected)
	return training
}
func (e Experiment) alphaText(model int) string {
	if model < 3 {
		return hundredthsText(int(e.Selected[model]))
	}
	return "-"
}
func (e Experiment) cvRun(predictions []int) CVRun {
	truths := make([]int, len(e.Training))
	run := CVRun{Predictions: predictions}
	for i, document := range e.Training {
		truths[i] = document.Label
		if predictions[i] == document.Label {
			run.FoldCorrect[i%5]++
		}
	}
	run.Evaluation = evaluate(len(e.Classes), truths, predictions)
	return run
}
func (e *Experiment) crossValidate() {
	count := len(e.Training)
	var predictions [4][][]int
	for model := 0; model < 4; model++ {
		runs := len(e.Settings.Alphas)
		if model == 3 {
			runs = 1
		}
		predictions[model] = make([][]int, runs)
		for i := range predictions[model] {
			predictions[model][i] = make([]int, count)
		}
	}
	for fold := 0; fold < 5; fold++ {
		members := []Document{}
		heldOut := []int{}
		for i, document := range e.Training {
			if i%5 == fold {
				heldOut = append(heldOut, i)
			} else {
				members = append(members, document)
			}
		}
		training := makeTraining(members, e.Settings.Bigrams, len(e.Classes), e.Settings.MinDF, e.Settings.Features)
		e.Folds = append(e.Folds, FoldSummary{len(members), len(heldOut), training.Vocabulary.CandidateCount, len(training.Vocabulary.Terms)})
		sequences := make([][]int, len(heldOut))
		for i, index := range heldOut {
			sequences[i] = training.Encode(e.Training[index])
		}
		for kind := 0; kind < 3; kind++ {
			for position, alpha := range e.Settings.Alphas {
				model := trainModel(kind, training.Counts, alpha)
				for i, index := range heldOut {
					predictions[kind][position][index] = model.Predict(sequences[i]).Label
				}
			}
		}
		for i, index := range heldOut {
			predictions[3][0][index] = training.Rocchio.Predict(sequences[i]).Label
		}
	}
	for model := 0; model < 4; model++ {
		for _, labels := range predictions[model] {
			e.CVRuns[model] = append(e.CVRuns[model], e.cvRun(labels))
		}
	}
}
func (e *Experiment) selectAlphas() {
	for model := 0; model < 3; model++ {
		best := 0
		for i := 1; i < len(e.CVRuns[model]); i++ {
			if rounded4(e.CVRuns[model][i].Evaluation.Macro) > rounded4(e.CVRuns[model][best].Evaluation.Macro) {
				best = i
			}
		}
		e.Selected[model] = e.Settings.Alphas[best]
		e.SelectedRuns[model] = e.CVRuns[model][best]
	}
	e.SelectedRuns[3] = e.CVRuns[3][0]
}
func (e *Experiment) trainFinal() {
	e.Final = e.trained(e.Training, e.Settings.Bigrams, e.Settings.Features)
	for _, document := range e.Tests {
		e.TestSequences = append(e.TestSequences, e.Final.Encode(document))
	}
	for model := 0; model < 4; model++ {
		for _, sequence := range e.TestSequences {
			e.Predictions[model] = append(e.Predictions[model], e.Final.Classify(model, sequence))
		}
	}
	for index := range e.Tests {
		votes := make([]int, len(e.Classes))
		labels := []int{}
		for model := 0; model < 4; model++ {
			label := e.Predictions[model][index].Label
			labels = append(labels, label)
			votes[label]++
		}
		winner := labels[0]
		for _, label := range labels {
			if votes[label] > votes[winner] {
				winner = label
			}
		}
		e.Predictions[4] = append(e.Predictions[4], Prediction{Label: winner, Score: float64(votes[winner]) / 4})
	}
	for model := 0; model < 5; model++ {
		for _, index := range e.Labelled {
			e.Correct[model] = append(e.Correct[model], e.Predictions[model][index].Label == e.Tests[index].Label)
		}
	}
}
func (e Experiment) testEvaluations(training Training) []Evaluation {
	evaluations := []Evaluation{}
	for model := 0; model < 4; model++ {
		predictions := []int{}
		for _, index := range e.Labelled {
			predictions = append(predictions, training.Classify(model, training.Encode(e.Tests[index])).Label)
		}
		evaluations = append(evaluations, evaluate(len(e.Classes), e.Truths, predictions))
	}
	return evaluations
}
func (e Experiment) vocabularyLines() []string {
	vocabulary := e.Final.Vocabulary
	lines := []string{fmt.Sprintf("documents %d terms %d candidates %d vocabulary %d", len(e.Training), vocabulary.TermCount, vocabulary.CandidateCount, len(vocabulary.Terms))}
	for rank, entry := range vocabulary.Ranking {
		lines = append(lines, fmt.Sprintf("%d %s %d %s %s", rank+1, entry.Term, entry.Frequency, realText(entry.Score), e.Classes[entry.BestClass]))
	}
	return lines
}
func (e Experiment) cvLines() []string {
	lines := []string{"model,alpha,correct,accuracy,macro_f1,selected"}
	for model := 0; model < 3; model++ {
		for i, alpha := range e.Settings.Alphas {
			selected := "no"
			if alpha == e.Selected[model] {
				selected = "yes"
			}
			lines = append(lines, modelNames[model]+","+hundredthsText(int(alpha))+","+evaluationFields(e.CVRuns[model][i].Evaluation)+","+selected)
		}
	}
	return append(lines, "rocchio,-,"+evaluationFields(e.CVRuns[3][0].Evaluation)+",yes")
}
func (e Experiment) predictionLines() []string {
	lines := []string{"id,model,label,score"}
	for index, document := range e.Tests {
		for model, name := range modelNames {
			prediction := e.Predictions[model][index]
			lines = append(lines, document.Name+","+name+","+e.Classes[prediction.Label]+","+realText(prediction.Score))
		}
	}
	return lines
}
func (e Experiment) curveLines() []string {
	lines := []string{"size,vocabulary,model,correct,accuracy,macro_f1"}
	for _, size := range e.Settings.Curve {
		training := e.trained(e.Training[:size], e.Settings.Bigrams, e.Settings.Features)
		for model, evaluation := range e.testEvaluations(training) {
			lines = append(lines, fmt.Sprintf("%d,%d,%s,%s", size, len(training.Vocabulary.Terms), modelNames[model], evaluationFields(evaluation)))
		}
	}
	return lines
}
func (e Experiment) featureLines() []string {
	lines := []string{"terms,features,vocabulary,model,correct,accuracy,macro_f1"}
	for _, bigrams := range []bool{false, true} {
		kind := "unigrams"
		if bigrams {
			kind = "bigrams"
		}
		for _, size := range e.Settings.Sizes {
			training := e.trained(e.Training, bigrams, size)
			for model, evaluation := range e.testEvaluations(training) {
				lines = append(lines, fmt.Sprintf("%s,%d,%d,%s,%s", kind, size, len(training.Vocabulary.Terms), modelNames[model], evaluationFields(evaluation)))
			}
		}
	}
	return lines
}
func (e Experiment) dataPart() []string {
	classCount := len(e.Classes)
	vocabulary := e.Final.Vocabulary
	lines := []string{fmt.Sprintf("documents train %d test %d labelled %d unlabelled %d classes %d", len(e.Training), len(e.Tests), len(e.Labelled), len(e.Unlabelled), classCount)}
	trainCounts, testCounts := make([]int, classCount), make([]int, classCount)
	for _, document := range e.Training {
		trainCounts[document.Label]++
	}
	for _, truth := range e.Truths {
		testCounts[truth]++
	}
	for label, name := range e.Classes {
		lines = append(lines, fmt.Sprintf("class %s train %d test %d", name, trainCounts[label], testCounts[label]))
	}
	raw, stopwords, short, kept, bigrams := 0, 0, 0, 0, 0
	terms := map[string]bool{}
	for _, document := range e.Training {
		tokens := document.Tokens
		raw += tokens.Raw
		stopwords += tokens.Stopwords
		short += tokens.Short
		kept += len(tokens.Words)
		if e.Settings.Bigrams {
			bigrams += len(tokens.Bigrams)
		}
		for _, term := range tokens.Terms(e.Settings.Bigrams) {
			terms[term] = true
		}
	}
	distinctBigrams := 0
	for term := range terms {
		if isBigram(term) {
			distinctBigrams++
		}
	}
	lines = append(lines, fmt.Sprintf("train_tokens raw %d stopwords %d short %d unigrams %d bigrams %d", raw, stopwords, short, kept, bigrams), fmt.Sprintf("train_terms unigrams %d bigrams %d candidates %d vocabulary %d", len(terms)-distinctBigrams, distinctBigrams, vocabulary.CandidateCount, len(vocabulary.Terms)))
	total, inVocabulary := 0, 0
	occurrences := map[string]int{}
	for index, document := range e.Tests {
		total += len(document.Tokens.Terms(e.Settings.Bigrams))
		inVocabulary += len(e.TestSequences[index])
		for _, word := range document.Tokens.Words {
			if _, exists := vocabulary.Index[word]; !exists {
				occurrences[word]++
			}
		}
	}
	lines = append(lines, fmt.Sprintf("test_terms total %d in_vocabulary %d", total, inVocabulary))
	ranked := []string{}
	for word := range occurrences {
		ranked = append(ranked, word)
	}
	sort.Slice(ranked, func(i, j int) bool {
		if occurrences[ranked[i]] != occurrences[ranked[j]] {
			return occurrences[ranked[i]] > occurrences[ranked[j]]
		}
		return ranked[i] < ranked[j]
	})
	line := "test_oov"
	for i, word := range ranked {
		if i >= e.Settings.Top {
			break
		}
		line += fmt.Sprintf(" %s %d", word, occurrences[word])
	}
	return append(lines, line)
}
func (e Experiment) foldsPart() []string {
	lines := []string{"folds 5"}
	for fold, summary := range e.Folds {
		lines = append(lines, fmt.Sprintf("fold %d train %d validate %d candidates %d vocabulary %d", fold+1, summary.Train, summary.Validate, summary.Candidates, summary.Vocabulary))
	}
	return lines
}
func (e Experiment) selectionPart() []string {
	lines := []string{"selection"}
	for model := 0; model < 4; model++ {
		run := e.SelectedRuns[model]
		folds := []string{}
		for _, count := range run.FoldCorrect {
			folds = append(folds, strconv.Itoa(count))
		}
		lines = append(lines, modelNames[model]+" alpha "+e.alphaText(model)+" correct "+proportionText(run.Evaluation.Correct, run.Evaluation.Total)+" macro_f1 "+realText(run.Evaluation.Macro)+" folds "+strings.Join(folds, " "))
	}
	return lines
}
func (e Experiment) crossValidationPart(model int) []string {
	return append([]string{"cross_validation " + modelNames[model] + " alpha " + e.alphaText(model)}, e.SelectedRuns[model].Evaluation.Lines(e.Classes)...)
}
func (e Experiment) testPart(model int) []string {
	labels := []int{}
	topTwo := 0
	for position, index := range e.Labelled {
		prediction := e.Predictions[model][index]
		labels = append(labels, prediction.Label)
		if model < 4 && (prediction.Ranking[0] == e.Truths[position] || prediction.Ranking[1] == e.Truths[position]) {
			topTwo++
		}
	}
	evaluation := evaluate(len(e.Classes), e.Truths, labels)
	lines := []string{"test " + modelNames[model] + " alpha " + e.alphaText(model), fmt.Sprintf("labelled %d correct %s", len(labels), proportionText(evaluation.Correct, len(labels)))}
	if model < 4 {
		lines = append(lines, "top2 "+proportionText(topTwo, len(labels)))
	}
	return append(lines, evaluation.Lines(e.Classes)...)
}
func (e Experiment) probabilityPart(model int) []string {
	thresholds := e.Settings.Thresholds
	limits := realBoundaries(thresholds, 100)
	count := len(e.Labelled)
	binRows, binCorrect := make([]int, len(limits)+1), make([]int, len(limits)+1)
	binSums := make([]float64, len(limits)+1)
	accepted, acceptedCorrect := make([]int, len(limits)), make([]int, len(limits))
	loss, brier := 0.0, 0.0
	for position, index := range e.Labelled {
		prediction := e.Predictions[model][index]
		truth := e.Truths[position]
		correct := e.Correct[model][position]
		gap := prediction.Scores[truth] - prediction.Scores[prediction.Label]
		loss += math.Log(prediction.Normalizer) - gap
		squares := 0.0
		for label, probability := range prediction.Probabilities {
			expected := 0.0
			if label == truth {
				expected = 1
			}
			difference := probability - expected
			squares += difference * difference
		}
		brier += squares
		bucket := bucketOf(prediction.Score, limits)
		binRows[bucket]++
		binSums[bucket] += prediction.Score
		if correct {
			binCorrect[bucket]++
		}
		for threshold, limit := range limits {
			if prediction.Score >= limit {
				accepted[threshold]++
				if correct {
					acceptedCorrect[threshold]++
				}
			}
		}
	}
	lines := []string{"probability " + modelNames[model] + " alpha " + e.alphaText(model), "log_loss " + realText(loss/float64(count)) + " brier " + realText(brier/float64(count))}
	bounds := append([]int{0}, thresholds...)
	for bucket, bound := range bounds {
		rows := binRows[bucket]
		line := fmt.Sprintf("bin %s rows %d", hundredthsText(bound), rows)
		if rows > 0 {
			line += " correct " + proportionText(binCorrect[bucket], rows) + " mean " + realText(binSums[bucket]/float64(rows))
		}
		lines = append(lines, line)
	}
	for i, threshold := range thresholds {
		precise := "-"
		if accepted[i] > 0 {
			precise = proportionText(acceptedCorrect[i], accepted[i])
		}
		lines = append(lines, "threshold "+hundredthsText(threshold)+" covered "+proportionText(accepted[i], count)+" correct "+precise)
	}
	return lines
}
func (e Experiment) lengthsPart() []string {
	boundaries := realBoundaries(e.Settings.Lengths, 1)
	rows := make([]int, len(boundaries)+1)
	var correct [5][]int
	for model := range correct {
		correct[model] = make([]int, len(rows))
	}
	for position, index := range e.Labelled {
		bucket := bucketOf(float64(len(e.TestSequences[index])), boundaries)
		rows[bucket]++
		for model := range correct {
			if e.Correct[model][position] {
				correct[model][bucket]++
			}
		}
	}
	lines := []string{"lengths"}
	for bucket, bound := range append([]int{0}, e.Settings.Lengths...) {
		line := fmt.Sprintf("length %d rows %d", bound, rows[bucket])
		if rows[bucket] > 0 {
			for model, name := range modelNames {
				line += " " + name + " " + proportionText(correct[model][bucket], rows[bucket])
			}
		}
		lines = append(lines, line)
	}
	return lines
}
func (e Experiment) comparisonPart() []string {
	lines := []string{"comparison"}
	for _, pair := range modelPairs {
		first, second := pair[0], pair[1]
		agree, b, c := 0, 0, 0
		for i := range e.Tests {
			if e.Predictions[first][i].Label == e.Predictions[second][i].Label {
				agree++
			}
		}
		for i := range e.Labelled {
			if e.Correct[first][i] && !e.Correct[second][i] {
				b++
			}
			if e.Correct[second][i] && !e.Correct[first][i] {
				c++
			}
		}
		statistic := fractionText(0, 1)
		if b+c > 0 {
			difference := b - c
			if difference < 0 {
				difference = -difference
			}
			difference--
			if difference < 0 {
				difference = 0
			}
			statistic = fractionText(difference*difference, b+c)
		}
		lines = append(lines, fmt.Sprintf("%s %s agree %s b %d c %d statistic %s", modelNames[first], modelNames[second], proportionText(agree, len(e.Tests)), b, c, statistic))
	}
	errors := [5]int{}
	for position := range e.Labelled {
		wrong := 0
		for model := 0; model < 4; model++ {
			if !e.Correct[model][position] {
				wrong++
			}
		}
		errors[wrong]++
	}
	line := "errors"
	for wrong, count := range errors {
		line += fmt.Sprintf(" %d %d", wrong, count)
	}
	return append(lines, line)
}
func (e Experiment) bootstrapPart() []string {
	count := len(e.Labelled)
	state := e.Settings.Seed
	var totals [5][]int
	for repetition := 0; repetition < e.Settings.Resamples; repetition++ {
		hits := [5]int{}
		for draw := 0; draw < count; draw++ {
			state = 48271 * state % 2147483647
			position := int(state % int64(count))
			for model := range hits {
				if e.Correct[model][position] {
					hits[model]++
				}
			}
		}
		for model, hit := range hits {
			totals[model] = append(totals[model], hit)
		}
	}
	rank := e.Settings.Resamples / 40
	lines := []string{fmt.Sprintf("bootstrap resamples %d seed %d", e.Settings.Resamples, e.Settings.Seed)}
	for model, name := range modelNames {
		ordered := append([]int(nil), totals[model]...)
		sort.Ints(ordered)
		total := 0
		for _, value := range ordered {
			total += value
		}
		lines = append(lines, name+" mean "+realText(float64(total)/float64(e.Settings.Resamples*count))+" low "+proportionText(ordered[rank], count)+" high "+proportionText(ordered[len(ordered)-1-rank], count))
	}
	for _, pair := range modelPairs {
		wins, ties, losses := 0, 0, 0
		for i, value := range totals[pair[0]] {
			other := totals[pair[1]][i]
			if value > other {
				wins++
			} else if value == other {
				ties++
			} else {
				losses++
			}
		}
		lines = append(lines, fmt.Sprintf("pair %s %s wins %d ties %d losses %d", modelNames[pair[0]], modelNames[pair[1]], wins, ties, losses))
	}
	return lines
}
func (e Experiment) hardPart() []string {
	indices := []int{}
	counts := make([]int, len(e.Classes))
	for i, document := range e.Training {
		hard := true
		for model := 0; model < 4; model++ {
			if e.SelectedRuns[model].Predictions[i] == document.Label {
				hard = false
			}
		}
		if hard {
			indices = append(indices, i)
			counts[document.Label]++
		}
	}
	lines := []string{fmt.Sprintf("hard_documents %d %s", len(indices), classCountsText(e.Classes, counts))}
	for i, index := range indices {
		if i >= e.Settings.Top {
			break
		}
		predicted := []string{}
		for model := 0; model < 4; model++ {
			predicted = append(predicted, e.Classes[e.SelectedRuns[model].Predictions[index]])
		}
		document := e.Training[index]
		lines = append(lines, document.Name+" true "+e.Classes[document.Label]+" predicted "+strings.Join(predicted, " "))
	}
	return lines
}
func (e Experiment) uncertainPart() []string {
	order := make([]int, len(e.Tests))
	for i := range order {
		order[i] = i
	}
	sort.SliceStable(order, func(i, j int) bool {
		return rounded4(e.Predictions[0][order[i]].Margin) < rounded4(e.Predictions[0][order[j]].Margin)
	})
	if len(order) > e.Settings.Top {
		order = order[:e.Settings.Top]
	}
	lines := []string{fmt.Sprintf("uncertain multinomial %d", len(order))}
	for _, index := range order {
		document := e.Tests[index]
		prediction := e.Predictions[0][index]
		truth := "?"
		if document.Label >= 0 {
			truth = e.Classes[document.Label]
		}
		lines = append(lines, fmt.Sprintf("%s predicted %s runner_up %s margin %s posterior %s true %s", document.Name, e.Classes[prediction.Label], e.Classes[prediction.RunnerUp], realText(prediction.Margin), realText(prediction.Score), truth))
	}
	return lines
}
func (e Experiment) evidenceLines(sequence []int, predicted, truth int) []string {
	alpha := e.Selected[0]
	counts := e.Final.Counts.Occurrences
	weights := e.Final.Models[0].Weights
	entries := []RatioEntry{}
	frequencies := map[int]int{}
	for _, term := range sequence {
		frequencies[term]++
	}
	for _, term := range firstOccurrences(sequence) {
		entries = append(entries, RatioEntry{100*counts[predicted][term] + alpha, 100*counts[truth][term] + alpha, term})
	}
	rankRatios(entries)
	lines := []string{}
	for i, entry := range entries {
		if i >= 3 {
			break
		}
		term := entry.Term
		lines = append(lines, fmt.Sprintf("  %s count %d evidence %s", e.Final.Vocabulary.Terms[term], frequencies[term], realText(weights[predicted][term]-weights[truth][term])))
	}
	return lines
}
func (e Experiment) misclassifiedPart() []string {
	misclassified := []int{}
	for _, index := range e.Labelled {
		if e.Predictions[0][index].Label != e.Tests[index].Label {
			misclassified = append(misclassified, index)
		}
	}
	lines := []string{fmt.Sprintf("misclassified multinomial %d", len(misclassified))}
	for _, index := range misclassified {
		document := e.Tests[index]
		prediction := e.Predictions[0][index]
		lines = append(lines, document.Name+" true "+e.Classes[document.Label]+" predicted "+e.Classes[prediction.Label]+" posterior "+realText(prediction.Score))
		lines = append(lines, e.evidenceLines(e.TestSequences[index], prediction.Label, document.Label)...)
	}
	return lines
}
func (e Experiment) maximization(posteriors []Prediction, sequences [][]int) NaiveBayes {
	counts := e.Final.Counts
	occurrences := make([][]float64, len(e.Classes))
	documents := make([]float64, len(e.Classes))
	for label, row := range counts.Occurrences {
		occurrences[label] = make([]float64, len(row))
		for term, count := range row {
			occurrences[label][term] = float64(count)
		}
		documents[label] = float64(counts.Documents[label])
	}
	weight := float64(e.Settings.Weight) / 100
	for i, sequence := range sequences {
		frequencies := map[int]int{}
		for _, term := range sequence {
			frequencies[term]++
		}
		terms := firstOccurrences(sequence)
		for label := range e.Classes {
			share := weight * posteriors[i].Probabilities[label]
			documents[label] += share
			for _, term := range terms {
				occurrences[label][term] += share * float64(frequencies[term])
			}
		}
	}
	model := NaiveBayes{Kind: 0, Priors: make([]float64, len(e.Classes)), Base: make([]float64, len(e.Classes)), Weights: make([][]float64, len(e.Classes))}
	alpha := float64(e.Selected[0])
	size := len(e.Final.Vocabulary.Terms)
	scale := float64(len(e.Training)) + float64(e.Settings.Weight*len(e.Unlabelled))/100
	for label, row := range occurrences {
		total := 0.0
		for _, value := range row {
			total += value
		}
		model.Weights[label] = make([]float64, size)
		for term, value := range row {
			model.Weights[label][term] = math.Log((100*value + alpha) / (100*total + alpha*float64(size)))
		}
		model.Priors[label] = math.Log(documents[label] / scale)
	}
	return model
}
func (e Experiment) semiSupervisedPart() []string {
	sequences := make([][]int, len(e.Unlabelled))
	for i, document := range e.Unlabelled {
		sequences[i] = e.Final.Encode(document)
	}
	model := e.Final.Models[0]
	lines := []string{fmt.Sprintf("semi_supervised multinomial alpha %s weight %s unlabelled %d", e.alphaText(0), hundredthsText(e.Settings.Weight), len(e.Unlabelled))}
	var previous []int
	for iteration := 0; iteration <= e.Settings.Iterations; iteration++ {
		posteriors := make([]Prediction, len(sequences))
		assignments := make([]int, len(sequences))
		assigned := make([]int, len(e.Classes))
		for i, sequence := range sequences {
			posteriors[i] = model.Predict(sequence)
			assignments[i] = posteriors[i].Label
			assigned[assignments[i]]++
		}
		predicted := []int{}
		for _, index := range e.Labelled {
			predicted = append(predicted, model.Predict(e.TestSequences[index]).Label)
		}
		evaluation := evaluate(len(e.Classes), e.Truths, predicted)
		changed := "-"
		if previous != nil {
			count := 0
			for i, label := range assignments {
				if previous[i] != label {
					count++
				}
			}
			changed = strconv.Itoa(count)
		}
		lines = append(lines, fmt.Sprintf("iteration %d correct %s macro_f1 %s changed %s assigned %s", iteration, proportionText(evaluation.Correct, evaluation.Total), realText(evaluation.Macro), changed, classCountsText(e.Classes, assigned)))
		if iteration < e.Settings.Iterations {
			model = e.maximization(posteriors, sequences)
		}
		previous = assignments
	}
	return lines
}
func (e Experiment) metricsParts() [][]string {
	parts := [][]string{e.dataPart(), e.foldsPart(), e.selectionPart()}
	for model := 0; model < 4; model++ {
		parts = append(parts, e.crossValidationPart(model))
	}
	for model := 0; model < 5; model++ {
		parts = append(parts, e.testPart(model))
	}
	for model := 0; model < 3; model++ {
		parts = append(parts, e.probabilityPart(model))
	}
	return append(parts, e.lengthsPart(), e.comparisonPart(), e.bootstrapPart(), e.hardPart(), e.uncertainPart(), e.misclassifiedPart(), e.semiSupervisedPart())
}
func (e Experiment) characteristicParts(kind int) [][]string {
	counts := e.Final.Counts
	terms := e.Final.Vocabulary.Terms
	size := len(terms)
	alpha := e.Selected[kind]
	table, totals, overall, outcomes := counts.Occurrences, counts.Totals, counts.Total, int64(size)
	if kind == 1 {
		table, totals, overall, outcomes = counts.Containing, counts.Documents, counts.DocumentTotal, 2
	}
	termTotals := make([]int64, size)
	for _, row := range table {
		for term, count := range row {
			termTotals[term] += count
		}
	}
	parts := [][]string{{fmt.Sprintf("model %s alpha %s vocabulary %d top %d", modelNames[kind], hundredthsText(int(alpha)), size, e.Settings.Top)}}
	for label, name := range e.Classes {
		total, other := totals[label], overall-totals[label]
		lines := []string{fmt.Sprintf("class %s total %d other %d", name, total, other)}
		entries := []RatioEntry{}
		for term, count := range table[label] {
			entries = append(entries, RatioEntry{100*count + alpha, 100*(termTotals[term]-count) + alpha, term})
		}
		rankRatios(entries)
		for rank, entry := range entries {
			if rank >= e.Settings.Top {
				break
			}
			term := entry.Term
			count := table[label][term]
			otherCount := termTotals[term] - count
			odds := smoothedLog(count, total, alpha, outcomes) - smoothedLog(otherCount, other, alpha, outcomes)
			lines = append(lines, fmt.Sprintf("%d %s %d %d %s", rank+1, terms[term], count, otherCount, realText(odds)))
		}
		parts = append(parts, lines)
	}
	return parts
}
func (e Experiment) topFeatureParts() [][]string {
	return append(e.characteristicParts(0), e.characteristicParts(1)...)
}
func main() {
	experiment := loadExperiment()
	experiment.crossValidate()
	experiment.selectAlphas()
	experiment.trainFinal()
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	writeLines("vocabulary.txt", experiment.vocabularyLines())
	writeLines("cv_results.csv", experiment.cvLines())
	writeLines("predictions.csv", experiment.predictionLines())
	writeLines("learning_curve.csv", experiment.curveLines())
	writeLines("feature_study.csv", experiment.featureLines())
	writeLines("metrics.txt", joinParts(experiment.metricsParts()))
	writeLines("top_features.txt", joinParts(experiment.topFeatureParts()))
}
