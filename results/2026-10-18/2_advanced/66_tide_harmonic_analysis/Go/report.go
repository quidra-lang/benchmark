package main

import (
	"fmt"
	"os"
	"strings"
)

func format(x float64, d int) string {
	s := fmt.Sprintf("%.*f", d, x)
	if strings.HasPrefix(s, "-") && strings.Trim(s[1:], "0.") == "" {
		return s[1:]
	}
	return s
}
func line(s *strings.Builder, template string, a ...any) { fmt.Fprintf(s, template+"\n", a...) }
func writeLines(path string, s *strings.Builder)         { must(os.WriteFile(path, []byte(s.String()), 0644)) }
func plotLines(cells [][]byte, p Settings) []string {
	labels := make([]string, len(cells))
	width := 0
	for q := range cells {
		labels[q] = format(float64(p.ZT-q*p.ZS)/100,
			2)
		width = max(width, len(labels[q]))
	}
	a := make([]string, 0, len(cells)+1)
	for q, row := range cells {
		a = append(a,
			strings.Repeat(" ", width-len(labels[q]))+labels[q]+" |"+string(row)+"|")
	}
	axis := make([]byte, p.PlotWidth)
	for i := range axis {
		axis[i] = '-'
		if i%6 == 0 {
			axis[i] = '+'
		}
	}
	a = append(a,
		strings.Repeat(" ", width)+" +"+string(axis)+"+")
	return a
}
