package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

func realText(value float64) string {
	text := fmt.Sprintf("%.4f", value)
	if text == "-0.0000" {
		return "0.0000"
	}
	return text
}
func reals(values []float64) string {
	fields := make([]string, len(values))
	for i, value := range values {
		fields[i] = realText(value)
	}
	return strings.Join(fields, " ")
}
func fourDecimal(value float64) float64 {
	rounded, err := strconv.ParseFloat(realText(value), 64)
	if err != nil {
		panic(err)
	}
	return rounded
}
func amount(cents int64) string {
	sign := ""
	if cents < 0 {
		sign = "-"
		cents = -cents
	}
	return fmt.Sprintf("%s%d.%02d", sign, cents/100, cents%100)
}
func writeLines(name string, lines []string) {
	if err := os.WriteFile("output/"+name, []byte(strings.Join(lines, "\n")+"\n"), 0644); err != nil {
		panic(err)
	}
}
