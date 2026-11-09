package main

import (
	"fmt"
	"math"
	"os"
	"sort"
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
func pValue(numerator, denominator int64) string {
	first, second := reducedFraction(numerator, denominator)
	return fmt.Sprintf("%d/%d %s", first, second, realText(float64(first)/float64(second)))
}
func numberList(numbers []int) string {
	if len(numbers) == 0 {
		return "none"
	}
	ordered := append([]int(nil), numbers...)
	sort.Ints(ordered)
	fields := make([]string, len(ordered))
	for i, value := range ordered {
		fields[i] = strconv.Itoa(value)
	}
	return strings.Join(fields, " ")
}
func binNumber(value, low, high float64, bins int) int {
	return min(int(math.Floor(float64(bins)*(value-low)/(high-low))), bins-1) + 1
}
func bar(count, top int) string { return strings.Repeat("#", (40*count+top-1)/top) }
func writeLines(name string, lines []string) {
	if err := os.WriteFile("output/"+name, []byte(strings.Join(lines, "\n")+"\n"), 0644); err != nil {
		panic(err)
	}
}
