package main

import (
	"fmt"
	"math"
	"os"
	"strconv"
	"strings"
)

func real(v float64) string {
	if math.IsNaN(v) {
		return "-"
	}
	s := fmt.Sprintf("%.4f", v)
	if s == "-0.0000" {
		return "0.0000"
	}
	return s
}
func optional(v int) string {
	if v == 0 {
		return "-"
	}
	return strconv.Itoa(v)
}
func ints(values []int) string {
	s := make([]string, len(values))
	for j, v := range values {
		s[j] = strconv.Itoa(v)
	}
	return strings.Join(s, " ")
}
func writeLines(name string, lines []string) {
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	if e := os.WriteFile("output/"+name, []byte(strings.Join(lines, "\n")+"\n"), 0644); e != nil {
		panic(e)
	}
}
func separateSections(sections [][]string) []string {
	lines := []string{}
	for _, s := range sections {
		if len(lines) > 0 {
			lines = append(lines, "")
		}
		lines = append(lines, s...)
	}
	return lines
}
