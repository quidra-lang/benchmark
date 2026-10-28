package main

import "math"

func clip(p float64) float64 {
	if p < 1 {
		return 1
	}
	if p > 5 {
		return 5
	}
	return p
}
func rmse(errors []float64) float64 {
	if len(errors) == 0 {
		return math.NaN()
	}
	sum := 0.0
	for _, e := range errors {
		sum += e * e
	}
	return math.Sqrt(sum / float64(len(errors)))
}
func mae(errors []float64) float64 {
	if len(errors) == 0 {
		return math.NaN()
	}
	sum := 0.0
	for _, e := range errors {
		sum += math.Abs(e)
	}
	return sum / float64(len(errors))
}
func trainingRMSE(training []Rating, predict func(int, int) float64) float64 {
	sum := 0.0
	for _, r := range training {
		e := float64(r.Value) - predict(r.User, r.Item)
		sum += e * e
	}
	return math.Sqrt(sum / float64(len(training)))
}
func rankWeight(rank int) float64 { return 1 / math.Log2(float64(rank+1)) }

type RankingMetrics struct {
	Hits                 int
	Recall, NDCG, AP, RR float64
}

func rankingMetrics(ranked []int, relevant map[int]bool, cutoff int) RankingMetrics {
	hits := 0
	dcg, ap, rr := 0.0, 0.0, 0.0
	for j, i := range ranked[:cutoff] {
		rank := j + 1
		if relevant[i] {
			hits++
			dcg += rankWeight(rank)
			ap += float64(hits) / float64(rank)
			if rr == 0 {
				rr = 1 / float64(rank)
			}
		}
	}
	ideal := min(cutoff, len(relevant))
	idcg := 0.0
	for t := 1; t <= ideal; t++ {
		idcg += rankWeight(t)
	}
	return RankingMetrics{hits, float64(hits) / float64(len(relevant)), dcg / idcg, ap / float64(ideal), rr}
}
