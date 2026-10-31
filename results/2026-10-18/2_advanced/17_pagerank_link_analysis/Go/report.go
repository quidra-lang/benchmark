package main

import (
	"fmt"
	"math"
	"os"
	"strconv"
	"strings"
)

func fixed(value float64, places ...int) string {
	digits := 6
	if len(places) > 0 {
		digits = places[0]
	}
	text := fmt.Sprintf("%.*f", digits, value)
	if strings.HasPrefix(text, "-") {
		rounded, err := strconv.ParseFloat(text, 64)
		if err != nil {
			panic(err)
		}
		if rounded == 0 {
			return text[1:]
		}
	}
	return text
}
func scaled(value float64, places ...int) int64 {
	digits := 6
	if len(places) > 0 {
		digits = places[0]
	}
	factor := int64(1)
	for i := 0; i < digits; i++ {
		factor *= 10
	}
	return int64(math.Round(value * float64(factor)))
}
func fraction(numerator, denominator int) string {
	a, b := numerator, denominator
	if a < 0 {
		a = -a
	}
	for b != 0 {
		a, b = b, a%b
	}
	return fmt.Sprintf("%d/%d %s", numerator/a, denominator/a, fixed(float64(numerator/a)/float64(denominator/a), 4))
}
func writeLines(name string, lines []string) {
	if err := os.WriteFile("output/"+name, []byte(strings.Join(lines, "\n")+"\n"), 0644); err != nil {
		panic(err)
	}
}
