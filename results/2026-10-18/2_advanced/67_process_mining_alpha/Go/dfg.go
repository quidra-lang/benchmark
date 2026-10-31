package main

import (
	"fmt"
	"strings"
)

type Pair struct{ A, B string }
type Trace struct {
	Activities []string
	Weight     int
}

func follows(log []Trace) map[Pair]int {
	d := map[Pair]int{}
	for _, v := range log {
		for i := 1; i < len(v.Activities); i++ {
			d[Pair{v.Activities[i-1],
				v.Activities[i]}] += v.Weight
		}
	}
	return d
}
func relation(d map[Pair]int, a, b string) string {
	ab, ba := d[Pair{a, b}] > 0, d[Pair{b, a}] > 0
	if ab && ba {
		return "||"
	}
	if ab {
		return "->"
	}
	if ba {
		return "<-"
	}
	return "#"
}
func table(s *strings.Builder, n, width int, value func(int, int) string) {
	s.WriteString("    ")
	for j := 1; j <= n; j++ {
		fmt.Fprintf(s,
			"%*d", width, j)
	}
	s.WriteByte('\n')
	for i := 0; i < n; i++ {
		fmt.Fprintf(s, "%4d", i+1)
		for j := 0; j < n; j++ {
			fmt.Fprintf(s,
				"%*s", width, value(i, j))
		}
		s.WriteByte('\n')
	}
}
func footprint(s *strings.Builder, names []string, rel func(string, string) string) {
	for i, name := range names {
		line(s,
			"ACTIVITY %d %s", i+1, name)
	}
	table(s, len(names), 4, func(i, j int) string { return rel(names[i], names[j]) })
}
