package main

import (
	"fmt"
	"math"
	"os"
	"strconv"
	"strings"
)

type Fraction struct{ P, Q int64 }

func gcd(a, b int64) int64 {
	if a < 0 {
		a = -a
	}
	for b != 0 {
		a, b = b, a%b
	}
	return a
}
func fraction(p, q int64) Fraction {
	if q < 0 {
		p, q = -p, -q
	}
	divisor := gcd(p, q)
	return Fraction{p / divisor, q / divisor}
}
func (a Fraction) Add(b Fraction) Fraction {
	common := gcd(a.Q, b.Q)
	return fraction(a.P*(b.Q/common)+b.P*(a.Q/common), (a.Q/common)*b.Q)
}
func (a Fraction) Mul(b Fraction) Fraction {
	x, y := gcd(a.P, b.Q), gcd(b.P, a.Q)
	return fraction((a.P/x)*(b.P/y), (a.Q/y)*(b.Q/x))
}
func (a Fraction) Div(value int64) Fraction { return a.Mul(fraction(1, value)) }
func (a Fraction) Cmp(b Fraction) int {
	left, right := a.P*b.Q, b.P*a.Q
	if left > right {
		return 1
	}
	if left < right {
		return -1
	}
	return 0
}
func (a Fraction) Real() float64         { return float64(a.P) / float64(a.Q) }
func fractionText(value Fraction) string { return fmt.Sprintf("%d/%d", value.P, value.Q) }
func fixed(value float64, places int) string {
	text := strconv.FormatFloat(value, 'f', places, 64)
	parsed, _ := strconv.ParseFloat(text, 64)
	if parsed == 0 {
		return strings.TrimPrefix(text, "-")
	}
	return text
}
func fixedFraction(value Fraction, places int) string {
	numerator := value.P
	sign := ""
	if numerator < 0 {
		numerator = -numerator
		sign = "-"
	}
	whole, remainder := numerator/value.Q, numerator%value.Q
	digits, scale := int64(0), int64(1)
	for i := 0; i < places; i++ {
		remainder *= 10
		digits = digits*10 + remainder/value.Q
		remainder %= value.Q
		scale *= 10
	}
	last := digits
	if places == 0 {
		last = whole
	}
	if 2*remainder > value.Q || 2*remainder == value.Q && last%2 != 0 {
		digits++
		if digits == scale {
			whole++
			digits = 0
		}
	}
	if whole == 0 && digits == 0 {
		sign = ""
	}
	if places == 0 {
		return sign + strconv.FormatInt(whole, 10)
	}
	return fmt.Sprintf("%s%d.%0*d", sign, whole, places, digits)
}
func fractionWithReal(value Fraction) string {
	return fractionText(value) + " " + fixedFraction(value, 4)
}
func decimalValue(value float64, places int) int64 {
	scale := 1.0
	for i := 0; i < places; i++ {
		scale *= 10
	}
	return int64(math.RoundToEven(value * scale))
}
func writeLines(name string, lines []string) {
	if err := os.WriteFile("output/"+name, []byte(strings.Join(lines, "\n")+"\n"), 0644); err != nil {
		panic(err)
	}
}
