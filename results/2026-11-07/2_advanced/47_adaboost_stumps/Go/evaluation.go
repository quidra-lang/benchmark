package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

func numberDigits(v float64, decimals int) string {
	s := fmt.Sprintf("%.*f", decimals, v)
	if strings.HasPrefix(s, "-") {
		x, e := strconv.ParseFloat(s, 64)
		if e == nil && x == 0 {
			s = s[1:]
		}
	}
	return s
}
func number(v float64) string { return numberDigits(v, 4) }
func ratio(a, b int) string {
	if b == 0 {
		return "-"
	}
	return number(float64(a) / float64(b))
}
func ratioReal(a, b float64) string {
	if b == 0 {
		return "-"
	}
	return number(a / b)
}
func prediction(score float64) int {
	if score > 0 {
		return 1
	}
	return -1
}
func auc(rows []Row, scores []float64) (int, int) {
	positive, negative := []float64{}, []float64{}
	for i, row := range rows {
		if row.Label == 1 {
			positive = append(positive, scores[i])
		} else {
			negative = append(negative, scores[i])
		}
	}
	wins, ties := 0, 0
	for _, p := range positive {
		for _, n := range negative {
			if p > n {
				wins++
			} else if p == n {
				ties++
			}
		}
	}
	return 2*wins + ties, 2 * len(positive) * len(negative)
}
func confusion(rows []Row, predictions []int, classes int) [][]int {
	out := make([][]int, classes)
	for c := range out {
		out[c] = make([]int, classes)
	}
	for i, row := range rows {
		out[row.Label-1][predictions[i]-1]++
	}
	return out
}
func countAtMost(margins []float64, threshold float64) int {
	n := 0
	for _, v := range margins {
		if v <= threshold {
			n++
		}
	}
	return n
}
func ints(values []int) string {
	s := make([]string, len(values))
	for i, x := range values {
		s[i] = strconv.Itoa(x)
	}
	return strings.Join(s, " ")
}
func writeLines(name string, lines []string) {
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	if e := os.WriteFile("output/"+name, []byte(strings.Join(lines, "\n")+"\n"), 0644); e != nil {
		panic(e)
	}
}
