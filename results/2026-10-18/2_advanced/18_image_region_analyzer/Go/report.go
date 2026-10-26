package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type Rational struct{ P, Q int64 }

func abs64(value int64) int64 {
	if value < 0 {
		return -value
	}
	return value
}

func ratio(numerator, denominator int64) Rational {
	first, second := abs64(numerator), denominator
	for second != 0 {
		first, second = second, first%second
	}
	return Rational{numerator / first, denominator / first}
}

func integer(value int64) Rational { return Rational{value, 1} }

func (value Rational) Compare(other Rational) int {
	left, right := value.P*other.Q, other.P*value.Q
	if left < right {
		return -1
	}
	if left > right {
		return 1
	}
	return 0
}

func decimal(value Rational, digits int) string {
	scale := int64(1)
	for range digits {
		scale *= 10
	}
	rounded := (2*scale*abs64(value.P) + value.Q) / (2 * value.Q)
	sign := ""
	if value.P < 0 && rounded > 0 {
		sign = "-"
	}
	return fmt.Sprintf("%s%d.%0*d", sign, rounded/scale, digits, rounded%scale)
}

func hullAreaText(doubled int64) string {
	fraction := 0
	if doubled%2 != 0 {
		fraction = 5
	}
	return fmt.Sprintf("%d.%d", doubled/2, fraction)
}

func writeFiles(directory string, files map[string][]string) {
	if err := os.MkdirAll(directory, 0755); err != nil {
		panic(err)
	}
	for name, lines := range files {
		if err := os.WriteFile(filepath.Join(directory, name), []byte(strings.Join(lines, "\n")+"\n"), 0644); err != nil {
			panic(err)
		}
	}
}
