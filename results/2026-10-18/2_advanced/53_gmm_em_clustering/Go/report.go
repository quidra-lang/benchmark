package main

import (
	"fmt"
	"math"
	"os"
	"strconv"
	"strings"
)

func numberDigits(value float64, digits int) string {
	v := fmt.Sprintf("%.*f", digits, value)
	if strings.HasPrefix(v, "-") {
		parsed, e := strconv.ParseFloat(v, 64)
		if e == nil && parsed == 0 {
			return v[1:]
		}
	}
	return v
}
func number(value float64) string { return numberDigits(value, 4) }
func optional(value float64) string {
	if math.IsNaN(value) {
		return "-"
	}
	return number(value)
}
func rounded4(value float64) int64 { return int64(math.Round(value * 10000)) }
func integerList(values []int) string {
	fields := make([]string, len(values))
	for i, v := range values {
		fields[i] = strconv.Itoa(v)
	}
	return strings.Join(fields, " ")
}
func numberList(values []float64) string {
	fields := make([]string, len(values))
	for i, v := range values {
		fields[i] = number(v)
	}
	return strings.Join(fields, " ")
}
func framed(rows [][]byte) []string {
	border := "+" + strings.Repeat("-", len(rows[0])) + "+"
	out := []string{border}
	for _, row := range rows {
		out = append(out, "|"+string(row)+"|")
	}
	return append(out, border)
}
func writeLines(name string, lines []string) {
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	if e := os.WriteFile("output/"+name, []byte(strings.Join(lines, "\n")+"\n"), 0644); e != nil {
		panic(e)
	}
}
