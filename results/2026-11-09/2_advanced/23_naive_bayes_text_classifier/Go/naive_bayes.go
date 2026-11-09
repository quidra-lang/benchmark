package main

import (
	"math"
	"sort"
)

type TrainingCounts struct {
	ClassCount, Size              int
	DocumentTotal                 int64
	Documents, Totals, TermTotals []int64
	Occurrences, Containing       [][]int64
	Total                         int64
}

func countTraining(sequences [][]int, labels []int, classCount, size int) TrainingCounts {
	counts := TrainingCounts{ClassCount: classCount, Size: size, DocumentTotal: int64(len(sequences)), Documents: make([]int64, classCount), Totals: make([]int64, classCount), TermTotals: make([]int64, size), Occurrences: make([][]int64, classCount), Containing: make([][]int64, classCount)}
	for c := 0; c < classCount; c++ {
		counts.Occurrences[c] = make([]int64, size)
		counts.Containing[c] = make([]int64, size)
	}
	for i, sequence := range sequences {
		label := labels[i]
		counts.Documents[label]++
		for _, term := range sequence {
			counts.Occurrences[label][term]++
		}
		for _, term := range firstOccurrences(sequence) {
			counts.Containing[label][term]++
		}
	}
	for c, row := range counts.Occurrences {
		for term, count := range row {
			counts.Totals[c] += count
			counts.TermTotals[term] += count
		}
		counts.Total += counts.Totals[c]
	}
	return counts
}
func smoothedLog(count, total, alpha, outcomes int64) float64 {
	return math.Log(float64(100*count+alpha) / float64(100*total+alpha*outcomes))
}

type Prediction struct {
	Label                 int
	Score                 float64
	Ranking               []int
	Scores, Probabilities []float64
	Normalizer, Margin    float64
	RunnerUp              int
}

func classRanking(scores []float64) []int {
	order := make([]int, len(scores))
	for i := range order {
		order[i] = i
	}
	sort.SliceStable(order, func(i, j int) bool { return scores[order[i]] > scores[order[j]] })
	return order
}
func posterior(scores []float64) Prediction {
	ranking := classRanking(scores)
	label := ranking[0]
	best := scores[label]
	values := make([]float64, len(scores))
	normalizer := 0.0
	for i, score := range scores {
		values[i] = math.Exp(score - best)
		normalizer += values[i]
	}
	for i := range values {
		values[i] /= normalizer
	}
	return Prediction{Label: label, Score: values[label], Ranking: ranking, Scores: scores, Probabilities: values, Normalizer: normalizer, Margin: best - scores[ranking[1]], RunnerUp: ranking[1]}
}

type NaiveBayes struct {
	Kind         int
	Priors, Base []float64
	Weights      [][]float64
}

func (model NaiveBayes) Predict(sequence []int) Prediction {
	terms := sequence
	if model.Kind == 1 {
		terms = firstOccurrences(sequence)
	}
	scores := make([]float64, len(model.Weights))
	for label, row := range model.Weights {
		score := model.Base[label]
		for _, term := range terms {
			score += row[term]
		}
		scores[label] = score + model.Priors[label]
	}
	return posterior(scores)
}
func trainModel(kind int, counts TrainingCounts, alpha int64) NaiveBayes {
	model := NaiveBayes{Kind: kind, Priors: make([]float64, counts.ClassCount), Base: make([]float64, counts.ClassCount), Weights: make([][]float64, counts.ClassCount)}
	for label := 0; label < counts.ClassCount; label++ {
		model.Priors[label] = math.Log(float64(counts.Documents[label]) / float64(counts.DocumentTotal))
		row := make([]float64, counts.Size)
		for term := 0; term < counts.Size; term++ {
			if kind == 0 {
				row[term] = smoothedLog(counts.Occurrences[label][term], counts.Totals[label], alpha, int64(counts.Size))
			} else if kind == 1 {
				present := smoothedLog(counts.Containing[label][term], counts.Documents[label], alpha, 2)
				absent := smoothedLog(counts.Documents[label]-counts.Containing[label][term], counts.Documents[label], alpha, 2)
				model.Base[label] += absent
				row[term] = present - absent
			} else {
				row[term] = -smoothedLog(counts.TermTotals[term]-counts.Occurrences[label][term], counts.Total-counts.Totals[label], alpha, int64(counts.Size))
			}
		}
		model.Weights[label] = row
	}
	return model
}
