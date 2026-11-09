package main

import (
	"fmt"
	"math"
	"sort"
)

func sum(values []float64) float64 {
	total := 0.0
	for _, v := range values {
		total += v
	}
	return total
}
func median(values []float64) float64 {
	ordered := append([]float64{}, values...)
	sort.Float64s(ordered)
	middle := len(ordered) / 2
	if len(ordered)%2 == 1 {
		return ordered[middle]
	}
	return (ordered[middle-1] + ordered[middle]) / 2
}
func log10(v float64) float64 { return math.Log(v) / 2.302585092994046 }

type PickMagnitude struct {
	Pick      *Pick
	R, ML, MD float64
	HasML     bool
}

func perPickMagnitude(pick *Pick, r float64, p Params) PickMagnitude {
	out := PickMagnitude{Pick: pick, R: r, HasML: !pick.Clipped}
	out.MD = p.real("duration_magnitude", 0) + p.real("duration_magnitude", 1)*log10(float64(pick.Duration)/100) + p.real("duration_magnitude", 2)*r
	if out.HasML {
		out.ML = log10(float64(pick.Amplitude)) + p.real("local_magnitude", 0)*log10(r/100) + p.real("local_magnitude", 1)*(r-100) + p.real("local_magnitude", 2)
	}
	return out
}
func magnitudeClass(value int) string {
	sign := ""
	if value < 0 {
		sign = "-"
		value = -value
	}
	return fmt.Sprintf("%s%d.%d", sign, value/10, value%10)
}
func classNumber(magnitude float64) int { return int(floorDiv(scaledDecimal(magnitude, 2)+5, 10)) }

type FrequencyStats struct {
	Classes                                              map[int]int
	Minimum, Maximum, Completeness, NB, N                int
	BValue, Sigma, AValue, Slope, Intercept, R, MeanDiff float64
}

func frequencyStatistics(events []*Event) FrequencyStats {
	out := FrequencyStats{Classes: map[int]int{}}
	classes := []int{}
	x, y := []float64{}, []float64{}
	for _, event := range events {
		if event.HasML {
			c := classNumber(event.ML)
			classes = append(classes, c)
			out.Classes[c]++
			x = append(x, event.MD)
			y = append(y, event.ML)
		}
	}
	out.Minimum, out.Maximum = classes[0], classes[0]
	for _, c := range classes {
		out.Minimum = min(out.Minimum, c)
		out.Maximum = max(out.Maximum, c)
	}
	out.Completeness = out.Minimum
	for c := out.Minimum + 1; c <= out.Maximum; c++ {
		if out.Classes[c] > out.Classes[out.Completeness] {
			out.Completeness = c
		}
	}
	total := 0
	for _, c := range classes {
		if c >= out.Completeness {
			out.NB++
			total += c
		}
	}
	mc := float64(out.Completeness) / 10
	mean := float64(total) / float64(10*out.NB)
	out.BValue = 0.4342944819032518 / (mean - (mc - 0.05))
	out.Sigma = out.BValue / math.Sqrt(float64(out.NB))
	out.AValue = log10(float64(out.NB)) + out.BValue*mc
	out.N = len(x)
	xm, ym := sum(x)/float64(out.N), sum(y)/float64(out.N)
	xx, xy, yy := 0.0, 0.0, 0.0
	for i, v := range x {
		dx, dy := v-xm, y[i]-ym
		xx += dx * dx
		xy += dx * dy
		yy += dy * dy
	}
	out.Slope = xy / xx
	out.Intercept = ym - out.Slope*xm
	out.R = xy / math.Sqrt(xx*yy)
	out.MeanDiff = ym - xm
	return out
}
