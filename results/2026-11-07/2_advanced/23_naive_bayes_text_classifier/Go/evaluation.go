package main

import (
	"fmt"
	"strconv"
	"strings"
)

func realText(value float64) string {
	text := strconv.FormatFloat(value, 'f', 4, 64)
	if text == "-0.0000" {
		return "0.0000"
	}
	return text
}
func proportionText(numerator, denominator int) string {
	return fmt.Sprintf("%d/%d %s", numerator, denominator, realText(float64(numerator)/float64(denominator)))
}
func gcd(a, b int) int {
	for b != 0 {
		a, b = b, a%b
	}
	return a
}
func fractionText(numerator, denominator int) string {
	if denominator == 0 {
		return "- -"
	}
	divisor := gcd(numerator, denominator)
	return proportionText(numerator/divisor, denominator/divisor)
}

type Evaluation struct {
	Matrix         [][]int
	Total, Correct int
	Micro, Macro   float64
}

func evaluate(classCount int, truths, predictions []int) Evaluation {
	e := Evaluation{Matrix: make([][]int, classCount), Total: len(truths)}
	for c := range e.Matrix {
		e.Matrix[c] = make([]int, classCount)
	}
	for i, truth := range truths {
		e.Matrix[truth][predictions[i]]++
	}
	sum, scored := 0.0, 0
	for label := 0; label < classCount; label++ {
		e.Correct += e.Matrix[label][label]
		denominator := e.PredictedCount(label) + e.Support(label)
		if denominator > 0 {
			sum += float64(2*e.Matrix[label][label]) / float64(denominator)
			scored++
		}
	}
	e.Micro = float64(e.Correct) / float64(e.Total)
	e.Macro = sum / float64(scored)
	return e
}
func (e Evaluation) Support(label int) int {
	total := 0
	for _, count := range e.Matrix[label] {
		total += count
	}
	return total
}
func (e Evaluation) PredictedCount(label int) int {
	total := 0
	for _, row := range e.Matrix {
		total += row[label]
	}
	return total
}
func (e Evaluation) Lines(names []string) []string {
	lines := []string{"true\\predicted " + strings.Join(names, " ")}
	for label, name := range names {
		values := []string{name}
		for _, count := range e.Matrix[label] {
			values = append(values, strconv.Itoa(count))
		}
		lines = append(lines, strings.Join(values, " "))
	}
	for label, name := range names {
		hits, predicted, support := e.Matrix[label][label], e.PredictedCount(label), e.Support(label)
		lines = append(lines, fmt.Sprintf("class %s precision %s recall %s f1 %s support %d", name, fractionText(hits, predicted), fractionText(hits, support), fractionText(2*hits, predicted+support), support))
	}
	return append(lines, "micro_f1 "+realText(e.Micro)+" macro_f1 "+realText(e.Macro))
}
