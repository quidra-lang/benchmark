package main

import (
	"fmt"
	"sort"
	"strings"
)

func fixed(value float64, places int) string {
	text := fmt.Sprintf("%.*f", places, value)
	if strings.HasPrefix(text, "-") && strings.Trim(text[1:], "0.") == "" {
		return text[1:]
	}
	return text
}
func ratio(a, b int) string {
	if b == 0 {
		return "-"
	}
	q := (20000*int64(a) + int64(b)) / (2 * int64(b))
	return fmt.Sprintf("%d.%04d", q/10000, q%10000)
}
func gcd(a, b int) int {
	for b != 0 {
		a, b = b, a%b
	}
	return a
}

type Fraction struct{ A, B int }

func (f Fraction) Text() string {
	d := gcd(f.A, f.B)
	return fmt.Sprintf("%d/%d %s", f.A/d, f.B/d, ratio(f.A, f.B))
}
func (f Fraction) Value() float64 { return float64(f.A) / float64(f.B) }

type Confusion struct{ TP, FP, TN, FN int }

func confusion(predicted, targets []int) Confusion {
	c := Confusion{}
	for i, p := range predicted {
		if p == 1 && targets[i] == 1 {
			c.TP++
		} else if p == 1 {
			c.FP++
		} else if targets[i] == 0 {
			c.TN++
		} else {
			c.FN++
		}
	}
	return c
}
func ordered(values []float64, descending bool) []int {
	indices := make([]int, len(values))
	for i := range indices {
		indices[i] = i
	}
	sort.SliceStable(indices, func(i, j int) bool {
		if descending {
			return values[indices[i]] > values[indices[j]]
		}
		return values[indices[i]] < values[indices[j]]
	})
	return indices
}
func auc(scores []float64, y []int) Fraction {
	order := ordered(scores, false)
	positives := 0
	for _, v := range y {
		positives += v
	}
	ranks := 0
	for start := 0; start < len(order); {
		end := start
		for end+1 < len(order) && scores[order[end+1]] == scores[order[start]] {
			end++
		}
		for i := start; i <= end; i++ {
			if y[order[i]] == 1 {
				ranks += start + end + 2
			}
		}
		start = end + 1
	}
	return Fraction{ranks - positives*(positives+1), 2 * positives * (len(y) - positives)}
}

type RocPoint struct {
	Threshold float64
	TP, FP    int
}

func rocPoints(probabilities []float64, targets []int) []RocPoint {
	order := ordered(probabilities, true)
	points := []RocPoint{}
	tp, fp := 0, 0
	for i, j := range order {
		if targets[j] == 1 {
			tp++
		} else {
			fp++
		}
		if i+1 == len(order) || probabilities[order[i+1]] != probabilities[j] {
			points = append(points, RocPoint{probabilities[j], tp, fp})
		}
	}
	return points
}
