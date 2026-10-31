package main

import (
	"math"
	"sort"
)

type SparseValue struct {
	Term  int
	Value float64
}
type Rocchio struct {
	IDF       []float64
	Centroids [][]float64
	Lengths   []float64
}

func vectorLength(values []SparseValue) float64 {
	total := 0.0
	for _, value := range values {
		total += value.Value * value.Value
	}
	return math.Sqrt(total)
}
func (r Rocchio) Vector(sequence []int) []SparseValue {
	frequencies := map[int]int{}
	for _, term := range sequence {
		frequencies[term]++
	}
	terms := []int{}
	for term := range frequencies {
		terms = append(terms, term)
	}
	sort.Ints(terms)
	vector := []SparseValue{}
	for _, term := range terms {
		vector = append(vector, SparseValue{term, float64(frequencies[term]) * r.IDF[term]})
	}
	return vector
}
func trainRocchio(sequences [][]int, labels []int, classCount int, frequencies []int) Rocchio {
	model := Rocchio{IDF: make([]float64, len(frequencies)), Centroids: make([][]float64, classCount), Lengths: make([]float64, classCount)}
	for i, frequency := range frequencies {
		model.IDF[i] = math.Log(float64(len(sequences)) / float64(frequency))
	}
	for c := range model.Centroids {
		model.Centroids[c] = make([]float64, len(frequencies))
	}
	documents := make([]int, classCount)
	for i, sequence := range sequences {
		label := labels[i]
		documents[label]++
		vector := model.Vector(sequence)
		length := vectorLength(vector)
		if length > 0 {
			for _, value := range vector {
				model.Centroids[label][value.Term] += value.Value / length
			}
		}
	}
	for label, row := range model.Centroids {
		total := 0.0
		for term := range row {
			row[term] /= float64(documents[label])
			total += row[term] * row[term]
		}
		model.Lengths[label] = math.Sqrt(total)
	}
	return model
}
func (r Rocchio) Predict(sequence []int) Prediction {
	vector := r.Vector(sequence)
	length := vectorLength(vector)
	similarities := make([]float64, len(r.Centroids))
	for label, centroid := range r.Centroids {
		if length > 0 && r.Lengths[label] > 0 {
			total := 0.0
			for _, value := range vector {
				total += value.Value * centroid[value.Term]
			}
			similarities[label] = total / (length * r.Lengths[label])
		}
	}
	ranking := classRanking(similarities)
	return Prediction{Label: ranking[0], Score: similarities[ranking[0]], Ranking: ranking}
}
