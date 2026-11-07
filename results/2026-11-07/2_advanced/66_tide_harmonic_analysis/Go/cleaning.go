package main

import (
	"math"
	"sort"
)

type FlatRun struct {
	First, Last int
	Value       float64
}
type Spike struct {
	Time                         int
	Residual, Median, MAD, Limit float64
}
type Gap struct {
	First, Last int
	Cause       string
}

func median(a []float64) float64 {
	a = append([]float64(nil), a...)
	sort.Float64s(a)
	n := len(a)
	if n%2 == 1 {
		return a[n/2]
	}
	return (a[n/2-1] + a[n/2]) / 2
}
func flatRuns(values map[int]float64, first, last, length int, reasons map[int]string) []FlatRun {
	var runs []FlatRun
	for t := first; t <= last; {
		value,
			ok := values[t]
		if !ok {
			t++
			continue
		}
		end := t
		for end < last {
			v, found := values[end+1]
			if !found || v != value {
				break
			}
			end++
		}
		if end-t+1 >= length {
			runs = append(runs,
				FlatRun{t, end, value})
			for u := t + 1; u <= end; u++ {
				reasons[u] = "flat"
			}
		}
		t = end + 1
	}
	return runs
}
func spikeTest(times []int, residual map[int]float64, p Settings, reasons map[int]string) ([]Spike, int) {
	var spikes []Spike
	tested := 0
	for _, t := range times {
		var a []float64
		for _, u := range times {
			if u >= t-p.W && u <= t+p.W {
				a = append(a, residual[u])
			}
		}
		if len(a) < p.C {
			continue
		}
		tested++
		me := median(a)
		d := make([]float64,
			len(a))
		for i, v := range a {
			d[i] = math.Abs(v - me)
		}
		mad := median(d)
		limit := math.Max(p.KS*1.4826*mad,
			p.D)
		if math.Abs(residual[t]-me) > limit {
			reasons[t] = "spike"
			spikes = append(spikes, Spike{t, residual[t],
				me, mad, limit})
		}
	}
	return spikes, tested
}
func listGaps(first, last int, reasons map[int]string) []Gap {
	var a []Gap
	for t := first; t <= last; {
		cause := reasons[t]
		if cause == "" {
			t++
			continue
		}
		end := t
		for end < last && reasons[end+1] != "" {
			end++
			if reasons[end] != cause {
				cause = "mixed"
			}
		}
		a = append(a,
			Gap{t, end, cause})
		t = end + 1
	}
	return a
}
