package main

import (
	"fmt"
	"os"
	"strings"
)

func sign(v float64) int {
	if v > 0 {
		return 1
	}
	return -1
}
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
	return fixed(float64(a)/float64(b), 4)
}
func yes(b bool) string {
	if b {
		return "yes"
	}
	return "no"
}
func folds(n, k, fold int) ([]int, []int) {
	train, test := []int{}, []int{}
	for i := 0; i < n; i++ {
		if i%k == fold {
			test = append(test, i)
		} else {
			train = append(train, i)
		}
	}
	return train, test
}

type TestMetrics struct {
	TP, FP, TN, FN, Correct, Inside int
	AUC, PositiveMean, NegativeMean float64
}

func evaluate(data []Example, values []float64) TestMetrics {
	out := TestMetrics{}
	positive, negative := 0, 0
	for j, e := range data {
		v := values[j]
		if e.Label == 1 {
			positive++
			out.PositiveMean += v
			if sign(v) == 1 {
				out.TP++
			} else {
				out.FN++
			}
		} else {
			negative++
			out.NegativeMean += v
			if sign(v) == 1 {
				out.FP++
			} else {
				out.TN++
			}
		}
		if v > -1 && v < 1 {
			out.Inside++
		}
	}
	out.Correct = out.TP + out.TN
	out.PositiveMean /= float64(positive)
	out.NegativeMean /= float64(negative)
	sum := 0.0
	for i, a := range data {
		if a.Label != 1 {
			continue
		}
		for j, b := range data {
			if b.Label != -1 {
				continue
			}
			if values[i] > values[j] {
				sum++
			} else if values[i] == values[j] {
				sum += .5
			}
		}
	}
	out.AUC = sum / float64(positive*negative)
	return out
}
func correct(data []Example, values []float64) int {
	n := 0
	for i, e := range data {
		if sign(values[i]) == e.Label {
			n++
		}
	}
	return n
}
func writeLines(name string, lines []string) {
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	if e := os.WriteFile("output/"+name, []byte(strings.Join(lines, "\n")+"\n"), 0644); e != nil {
		panic(e)
	}
}
func confusion(data []Example, predictions []int) [3][3]int {
	out := [3][3]int{}
	for i, e := range data {
		out[e.Label-1][predictions[i]-1]++
	}
	return out
}
