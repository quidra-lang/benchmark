package main

import (
	"fmt"
	"math"
	"strings"
)

func distance(a, b Point) float64 { x, y := a[0]-b[0], a[1]-b[1]; return math.Sqrt(x*x + y*y) }
func fixed(v float64) string {
	s := fmt.Sprintf("%.4f", v)
	if s == "-0.0000" {
		return "0.0000"
	}
	return s
}
func ospa(x, y []Point, cutoff float64) float64 {
	if len(x) == 0 && len(y) == 0 {
		return 0
	}
	if len(x) == 0 || len(y) == 0 {
		return cutoff
	}
	if len(x) > len(y) {
		x, y = y, x
	}
	cost := zeros(len(x), len(y))
	usable := make([][]bool, len(x))
	for i, a := range x {
		usable[i] = make([]bool, len(y))
		for j, b := range y {
			d := math.Min(cutoff, distance(a, b))
			cost[i][j] = d * d
			usable[i][j] = true
		}
	}
	chosen := assignment(cost, usable, len(y))
	sum := 0.0
	for i, j := range chosen {
		sum += cost[i][j]
	}
	return math.Sqrt((sum + cutoff*cutoff*float64(len(y)-len(x))) / float64(len(y)))
}

type Continuity struct{ Covered, Breaks, Swaps, Delay int }

func continuity(labels []int) Continuity {
	out := Continuity{Delay: -1}
	groups := 0
	previous := -1
	active := false
	for scan, label := range labels {
		if label < 0 {
			active = false
			continue
		}
		out.Covered++
		if out.Delay < 0 {
			out.Delay = scan
		}
		if !active {
			groups++
		}
		if previous >= 0 && previous != label {
			out.Swaps++
		}
		previous = label
		active = true
	}
	out.Breaks = max(0, groups-1)
	return out
}
func bestFilter(v [5]float64) string {
	best := 0
	for i := 1; i < 5; i++ {
		if number(fixed(v[i])) < number(fixed(v[best])) {
			best = i
		}
	}
	return filterNames[best]
}
func filterValues(v [5]float64) string {
	items := []string{}
	for i, name := range filterNames {
		items = append(items, name, fixed(v[i]))
	}
	return strings.Join(items, " ")
}
