package main

import (
	"fmt"
	"strings"
)

func fixed(v float64, digits int) string {
	s := fmt.Sprintf("%.*f", digits, v)
	if strings.HasPrefix(s, "-") {
		zero := true
		for _, c := range s[1:] {
			if c != '0' && c != '.' {
				zero = false
			}
		}
		if zero {
			s = s[1:]
		}
	}
	return s
}
func ratio(a, b int) string {
	if b == 0 {
		return "-"
	}
	q := (20000*a + b) / (2 * b)
	return fmt.Sprintf("%d.%04d", q/10000, q%10000)
}
func prediction(scores []float64) int {
	best := 0
	for k := 1; k < len(scores); k++ {
		if scores[k] > scores[best] {
			best = k
		}
	}
	return best
}
func second(scores []float64, first int) int {
	best := -1
	for k, v := range scores {
		if k != first && (best < 0 || v > scores[best]) {
			best = k
		}
	}
	return best
}
func confusion(data []Image, results []Forward, k int) [][]int {
	out := make([][]int, k)
	for cl := range out {
		out[cl] = make([]int, k)
	}
	for i, e := range data {
		out[e.Label][results[i].Prediction]++
	}
	return out
}
func classMetrics(matrix [][]int, k int) (int, int, string, string, string) {
	support, predicted := 0, 0
	for j := range matrix {
		support += matrix[k][j]
		predicted += matrix[j][k]
	}
	correct := matrix[k][k]
	return support, predicted, ratio(correct, predicted), ratio(correct, support), ratio(2*correct, support+predicted)
}
func levelLines(levels [][]int, w, h int) []string {
	out := []string{}
	for r := 0; r < h; r++ {
		parts := []string{}
		for _, values := range levels {
			row := make([]byte, w)
			for c := 0; c < w; c++ {
				row[c] = byte('0' + values[r*w+c])
			}
			parts = append(parts, string(row))
		}
		out = append(out, strings.Join(parts, " "))
	}
	return out
}
func imageLines(image Image, w, h int) []string {
	out := []string{}
	for r := 0; r < h; r++ {
		row := make([]byte, w)
		for c := 0; c < w; c++ {
			row[c] = '.'
			if image.Pixels[r*w+c] == '1' {
				row[c] = '#'
			}
		}
		out = append(out, string(row))
	}
	return out
}
