package main

import (
	"fmt"
	"math"
	"os"
	"strings"
)

func gcd(a, b int64) int64 {
	if a < 0 {
		a = -a
	}
	for b != 0 {
		a, b = b, a%b
	}
	return a
}
func fractionText(a, b int64) string { d := gcd(a, b); return fmt.Sprintf("%d/%d", a/d, b/d) }
func rootText(value int64) string    { return fmt.Sprintf("%.3f", math.Sqrt(float64(value))) }
func ariText(a, b int64) string {
	text := fmt.Sprintf("%.4f", float64(a)/float64(b))
	if text == "-0.0000" {
		text = "0.0000"
	}
	return fractionText(a, b) + " " + text
}
func framed(rows []string, width int) []string {
	border := "+" + strings.Repeat("-", width) + "+"
	lines := []string{border}
	for _, row := range rows {
		lines = append(lines, "|"+row+"|")
	}
	return append(lines, border)
}
func writeLines(name string, lines []string) {
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	text := ""
	if len(lines) > 0 {
		text = strings.Join(lines, "\n") + "\n"
	}
	if e := os.WriteFile("output/"+name, []byte(text), 0644); e != nil {
		panic(e)
	}
}
