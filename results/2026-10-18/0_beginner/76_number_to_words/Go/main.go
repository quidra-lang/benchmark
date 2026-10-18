package main

import (
	"fmt"
	"strings"
)

func under(n int) string {
	small := []string{"zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
		"ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen",
		"nineteen"}
	tens := []string{"", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"}
	out := ""
	if n >= 100 {
		out = small[n / 100] + " hundred"
		n %= 100
		if n > 0 {
			out += " "
		}
	}
	if n >= 20 {
		out += tens[n / 10]
		if n % 10 > 0 {
			out += "-" + small[n % 10]
		}
	} else if n > 0 {
		out += small[n]
	}
	return out
}

func main() {
	for _, n := range []int{0, 13, 40, 100, 568, 71000, 300019, 999999} {
		parts := []string{}
		if n == 0 {
			parts = append(parts, "zero")
		}
		if n >= 1000 {
			parts = append(parts, under(n / 1000) + " thousand")
		}
		if n % 1000 > 0 {
			parts = append(parts, under(n % 1000))
		}
		fmt.Printf("%d: %s\n", n, strings.Join(parts, " "))
	}
}
