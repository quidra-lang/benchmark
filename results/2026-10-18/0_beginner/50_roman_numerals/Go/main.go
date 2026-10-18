package main

import (
	"fmt"
)

func value(c byte) int {
	switch c {
	case 'I':
		return 1
	case 'V':
		return 5
	case 'X':
		return 10
	case 'L':
		return 50
	case 'C':
		return 100
	case 'D':
		return 500
	case 'M':
		return 1000
	}
	return 0
}

func main() {
	values := []int{1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1}
	symbols := []string{"M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"}
	for _, n := range []int{9, 14, 49, 94, 444, 1994, 2768, 3999} {
		remaining := n
		roman := ""
		for i, v := range values {
			for remaining >= v {
				roman += symbols[i]
				remaining -= v
			}
		}
		result := 0
		for i := range roman {
			v, next := value(roman[i]), 0
			if i + 1 < len(roman) {
				next = value(roman[i + 1])
			}
			if v < next {
				result -= v
			} else {
				result += v
			}
		}
		fmt.Printf("%d -> %s -> %d\n", n, roman, result)
	}
}
