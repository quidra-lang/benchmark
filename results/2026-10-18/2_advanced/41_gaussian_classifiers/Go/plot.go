package main

import (
	"fmt"
	"math"
	"os"
	"strconv"
	"strings"
)

func real(v float64) string {
	s := fmt.Sprintf("%.4f", v)
	if s == "-0.0000" {
		return "0.0000"
	}
	return s
}
func reals(v []float64) string {
	a := make([]string, len(v))
	for i, x := range v {
		a[i] = real(x)
	}
	return strings.Join(a, " ")
}
func ints(v []int) string {
	a := make([]string, len(v))
	for i, x := range v {
		a[i] = strconv.Itoa(x)
	}
	return strings.Join(a, " ")
}
func fractionText(v Fraction) string {
	if v.B == 0 {
		return "-"
	}
	return fmt.Sprintf("%d/%d %s", v.A, v.B, real(float64(v.A)/float64(v.B)))
}
func ratio(a, b int) string { return fractionText(fraction(a, b)) }
func frame(grid [][]byte) []string {
	border := "+" + strings.Repeat("-", len(grid[0])) + "+"
	lines := []string{border}
	for _, r := range grid {
		lines = append(lines, "|"+string(r)+"|")
	}
	return append(lines, border)
}
func cell(v, lo, hi float64, size int) int {
	return int(math.Floor((v-lo)/(hi-lo)*float64(size-1) + 0.5))
}
func joinSections(sections [][]string) []string {
	lines := []string{}
	for _, s := range sections {
		if len(lines) > 0 {
			lines = append(lines, "")
		}
		lines = append(lines, s...)
	}
	return lines
}
func writeLines(name string, lines []string) {
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	if err := os.WriteFile("output/"+name, []byte(strings.Join(lines, "\n")+"\n"), 0644); err != nil {
		panic(err)
	}
}
