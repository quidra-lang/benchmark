package main

import (
	"math"
	"sort"
)

var weights = []string{"logrank", "gehan_wilcoxon", "tarone_ware"}

type WeightedTest struct {
	Groups             []string
	Events             []int
	Observed, Expected []float64
	Covariance         [][]float64
	Statistic, P       float64
	Degrees            int
}

func emptyTotals(groups []string) WeightedTest {
	n := len(groups)
	return WeightedTest{Groups: groups, Events: make([]int, n), Observed: make([]float64, n), Expected: make([]float64, n), Covariance: zeros(n)}
}
func weightedTotals(subjects []Subject, groups []string, weight string, population int) WeightedTest {
	result := emptyTotals(groups)
	collections := make([][]Subject, len(groups))
	for k, g := range groups {
		for _, s := range subjects {
			if s.Group == g {
				collections[k] = append(collections[k], s)
			}
		}
	}
	set := map[int]bool{}
	for _, s := range subjects {
		if s.Event == 1 {
			set[s.Time] = true
		}
	}
	times := []int{}
	for t := range set {
		times = append(times, t)
	}
	sort.Ints(times)
	for _, time := range times {
		risk, deaths := make([]int, len(groups)), make([]int, len(groups))
		n, d := 0, 0
		for k, rows := range collections {
			for _, s := range rows {
				if s.Time >= time {
					risk[k]++
				}
				if s.Time == time {
					deaths[k] += s.Event
				}
			}
			n += risk[k]
			d += deaths[k]
		}
		value := 1.0
		if weight == "gehan_wilcoxon" {
			value = float64(n) / float64(population)
		} else if weight == "tarone_ware" {
			value = math.Sqrt(float64(n) / float64(population))
		}
		for h := range groups {
			result.Events[h] += deaths[h]
			result.Observed[h] += value * float64(deaths[h])
			result.Expected[h] += value * (float64(d*risk[h]) / float64(n))
			if n < 2 {
				continue
			}
			factor := value * value * (float64(d*(n-d)) / float64((n-1)*n*n))
			for l := range groups {
				multiple := -risk[h] * risk[l]
				if h == l {
					multiple = risk[h] * (n - risk[h])
				}
				result.Covariance[h][l] += factor * float64(multiple)
			}
		}
	}
	return result
}
func finishTest(result WeightedTest) WeightedTest {
	n := len(result.Groups) - 1
	u := make([]float64, n)
	matrix := zeros(n)
	for h := range u {
		u[h] = result.Observed[h] - result.Expected[h]
		copy(matrix[h], result.Covariance[h][:n])
	}
	x := solve(matrix, u)
	stat := 0.0
	for h, v := range u {
		stat += v * x[h]
	}
	result.Statistic = stat
	result.Degrees = n
	result.P = chiP(stat, n)
	return result
}
func weightedTest(subjects []Subject, groups []string, weight string, population int) WeightedTest {
	return finishTest(weightedTotals(subjects, groups, weight, population))
}
func combineStrata(strata []WeightedTest, groups []string) WeightedTest {
	r := emptyTotals(groups)
	for _, s := range strata {
		for h := range groups {
			r.Events[h] += s.Events[h]
			r.Observed[h] += s.Observed[h]
			r.Expected[h] += s.Expected[h]
			for l := range groups {
				r.Covariance[h][l] += s.Covariance[h][l]
			}
		}
	}
	return finishTest(r)
}
