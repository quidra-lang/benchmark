package main

import (
	"math"
	"sort"
)

func seasonalScale(values []float64, season int) float64 {
	sum := 0.0
	for t := season; t < len(values); t++ {
		sum += math.Abs(values[t] - values[t-season])
	}
	return sum / float64(len(values)-season)
}
func accuracy(actual, predicted []float64, scale float64) map[string]float64 {
	n := float64(len(actual))
	me, absolute, squares, mape, smape := 0.0, 0.0, 0.0, 0.0, 0.0
	for i, a := range actual {
		f := predicted[i]
		e := a - f
		me += e
		absolute += math.Abs(e)
		squares += e * e
		mape += math.Abs(e) / a
		smape += 2 * math.Abs(e) / (math.Abs(a) + math.Abs(f))
	}
	mae := absolute / n
	return map[string]float64{"me": me / n, "mae": mae, "rmse": math.Sqrt(squares / n), "mape": 100 * mape / n, "smape": 100 * smape / n, "mase": mae / scale}
}
func winkler(actual, low, high, multiplier float64) float64 {
	if actual < low {
		return high - low + multiplier*(low-actual)
	}
	if actual > high {
		return high - low + multiplier*(actual-high)
	}
	return high - low
}
func rankValues(values []float64) []int {
	order := make([]int, len(values))
	for i := range order {
		order[i] = i
	}
	sort.SliceStable(order, func(i, j int) bool { return values[order[i]] < values[order[j]] })
	return order
}
