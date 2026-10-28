package main

import (
	"math"
	"sort"
)

func sum(values []float64) float64 {
	total := 0.0
	for _, x := range values {
		total += x
	}
	return total
}

type Stump struct {
	Feature            int
	Thresholds, Values []float64
}

func (s Stump) output(values []float64) float64 {
	return s.Values[sort.SearchFloat64s(s.Thresholds, values[s.Feature])]
}

type SearchSpace struct {
	Rows       []Row
	Orders     [][]int
	Groups     [][][]int
	Thresholds [][]float64
}

func newSearchSpace(rows []Row) *SearchSpace {
	out := &SearchSpace{Rows: rows}
	for feature := range rows[0].Values {
		order := make([]int, len(rows))
		for i := range order {
			order[i] = i
		}
		sort.SliceStable(order, func(i, j int) bool { return rows[order[i]].Values[feature] < rows[order[j]].Values[feature] })
		groups := [][]int{}
		distinct := []float64{}
		for _, i := range order {
			v := rows[i].Values[feature]
			if len(distinct) == 0 || v != distinct[len(distinct)-1] {
				distinct = append(distinct, v)
				groups = append(groups, []int{})
			}
			groups[len(groups)-1] = append(groups[len(groups)-1], i)
		}
		thresholds := []float64{distinct[0] - 1}
		for k := 0; k < len(distinct)-1; k++ {
			thresholds = append(thresholds, (distinct[k]+distinct[k+1])/2)
		}
		out.Orders = append(out.Orders, order)
		out.Groups = append(out.Groups, groups)
		out.Thresholds = append(out.Thresholds, thresholds)
	}
	return out
}
func leftCumulative(groups [][]int, values []float64) []float64 {
	out := make([]float64, len(groups))
	total := 0.0
	for k, group := range groups[:len(groups)-1] {
		for _, i := range group {
			total += values[i]
		}
		out[k+1] = total
	}
	return out
}

type Candidate struct {
	Error              float64
	Feature            int
	Threshold          float64
	Polarity           int
	Left, Right        float64
	Positive, Negative []float64
}

func choose(candidates []Candidate) Candidate {
	minimum := candidates[0].Error
	for _, c := range candidates[1:] {
		minimum = math.Min(minimum, c.Error)
	}
	for _, c := range candidates {
		if c.Error <= minimum+1e-9 {
			return c
		}
	}
	panic("no stump candidate")
}
func discreteSearch(space *SearchSpace, labels []int, weights []float64) Candidate {
	positive, negative := make([]float64, len(weights)), make([]float64, len(weights))
	for i, w := range weights {
		if labels[i] == 1 {
			positive[i] = w
		} else {
			negative[i] = w
		}
	}
	wp, wn := sum(positive), sum(negative)
	candidates := []Candidate{}
	for feature, thresholds := range space.Thresholds {
		lp, ln := leftCumulative(space.Groups[feature], positive), leftCumulative(space.Groups[feature], negative)
		for k, t := range thresholds {
			candidates = append(candidates, Candidate{Error: lp[k] + (wn - ln[k]), Feature: feature, Threshold: t,
				Polarity: 1}, Candidate{Error: ln[k] + (wp - lp[k]), Feature: feature, Threshold: t,
				Polarity: -1})
		}
	}
	return choose(candidates)
}
func regressionSearch(space *SearchSpace, targets, weights []float64) (Stump, float64) {
	w := sum(weights)
	products := make([]float64, len(weights))
	q := 0.0
	for i, x := range weights {
		products[i] = x * targets[i]
		q += x * targets[i] * targets[i]
	}
	s := sum(products)
	candidates := []Candidate{}
	for feature, thresholds := range space.Thresholds {
		lw, ls := leftCumulative(space.Groups[feature], weights), leftCumulative(space.Groups[feature], products)
		for k, t := range thresholds {
			wr, sr := w-lw[k], s-ls[k]
			left := 0.0
			gain := sr * sr / wr
			if k > 0 {
				left = ls[k] / lw[k]
				gain = ls[k]*ls[k]/lw[k] + sr*sr/wr
			}
			candidates = append(candidates, Candidate{Error: q - gain, Feature: feature, Threshold: t, Left: left, Right: sr / wr})
		}
	}
	c := choose(candidates)
	return Stump{c.Feature, []float64{c.Threshold}, []float64{c.Left, c.Right}}, c.Error
}
func multiclassSearch(space *SearchSpace, labels []int, weights []float64, classes int) (Stump, float64) {
	total := sum(weights)
	totals := make([]float64, classes)
	for c := 0; c < classes; c++ {
		for i, w := range weights {
			if labels[i] == c+1 {
				totals[c] += w
			}
		}
	}
	candidates := []Candidate{}
	for feature, thresholds := range space.Thresholds {
		left := make([]float64, classes)
		for k, t := range thresholds {
			if k > 0 {
				for _, i := range space.Groups[feature][k-1] {
					left[labels[i]-1] += weights[i]
				}
			}
			right := make([]float64, classes)
			for c, x := range totals {
				right[c] = x - left[c]
			}
			a, b := 0, 0
			for c := 1; c < classes; c++ {
				if left[c] > left[a] {
					a = c
				}
				if right[c] > right[b] {
					b = c
				}
			}
			candidates = append(candidates, Candidate{Error: total - (left[a] + right[b]), Feature: feature, Threshold: t, Left: float64(a + 1), Right: float64(b + 1)})
		}
	}
	c := choose(candidates)
	return Stump{c.Feature, []float64{c.Threshold}, []float64{c.Left, c.Right}}, c.Error
}
func realGeometry(space *SearchSpace, bins int) ([][]float64, [][]int) {
	cuts := make([][]float64, len(space.Orders))
	assignments := make([][]int, len(cuts))
	for feature, order := range space.Orders {
		values := make([]float64, len(order))
		for i, j := range order {
			values[i] = space.Rows[j].Values[feature]
		}
		for b := 1; b < bins; b++ {
			r := b * len(order) / bins
			cuts[feature] = append(cuts[feature], (values[r-1]+values[r])/2)
		}
		assignments[feature] = make([]int, len(order))
		for i, row := range space.Rows {
			assignments[feature][i] = sort.SearchFloat64s(cuts[feature], row.Values[feature])
		}
	}
	return cuts, assignments
}
func realSearch(assignments [][]int, labels []int, weights []float64, bins int) Candidate {
	candidates := []Candidate{}
	for feature, memberships := range assignments {
		positive, negative := make([]float64, bins), make([]float64, bins)
		for i, b := range memberships {
			if labels[i] == 1 {
				positive[b] += weights[i]
			} else {
				negative[b] += weights[i]
			}
		}
		z := 0.0
		for b, p := range positive {
			z += math.Sqrt(p * negative[b])
		}
		candidates = append(candidates, Candidate{Error: 2 * z, Feature: feature, Positive: positive, Negative: negative})
	}
	return choose(candidates)
}
