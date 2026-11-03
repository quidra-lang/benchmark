package main

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

type Fraction struct{ N, D int64 }

func fraction(n, d int64) Fraction {
	if n == 0 {
		return Fraction{0, 1}
	}
	if d < 0 {
		n = -n
		d = -d
	}
	a, b := n, d
	if a < 0 {
		a = -a
	}
	for b != 0 {
		a, b = b, a%b
	}
	return Fraction{n / a, d / a}
}
func integer(n int64) Fraction { return Fraction{n, 1} }
func (a Fraction) denominator() int64 {
	if a.D == 0 {
		return 1
	}
	return a.D
}
func (a Fraction) add(b Fraction) Fraction {
	return fraction(a.N*b.denominator()+b.N*a.denominator(), a.denominator()*b.denominator())
}
func (a Fraction) sub(b Fraction) Fraction { return a.add(b.neg()) }
func (a Fraction) mul(b Fraction) Fraction { return fraction(a.N*b.N, a.denominator()*b.denominator()) }
func (a Fraction) div(b Fraction) Fraction { return fraction(a.N*b.denominator(), a.denominator()*b.N) }
func (a Fraction) neg() Fraction           { return fraction(-a.N, a.denominator()) }
func (a Fraction) abs() Fraction {
	if a.N < 0 {
		return a.neg()
	}
	return a
}
func (a Fraction) cmp(b Fraction) int {
	left, right := a.N*b.denominator(), b.N*a.denominator()
	if left < right {
		return -1
	}
	if left > right {
		return 1
	}
	return 0
}
func (a Fraction) floor() int64 {
	d := a.denominator()
	q := a.N / d
	if a.N < 0 && a.N%d != 0 {
		q--
	}
	return q
}
func (a Fraction) ceil() int64 { return -a.neg().floor() }
func (a Fraction) whole() bool { return a.denominator() == 1 }
func (a Fraction) String() string {
	if a.denominator() == 1 {
		return strconv.FormatInt(a.N, 10)
	}
	return fmt.Sprintf("%d/%d", a.N, a.denominator())
}
func (a Fraction) approx() string {
	n := a.N
	if n < 0 {
		n = -n
	}
	d := a.denominator()
	t := (2*n*1000000 + d) / (2 * d)
	sign := ""
	if a.N < 0 && t > 0 {
		sign = "-"
	}
	return fmt.Sprintf("%s%d.%06d", sign, t/1000000, t%1000000)
}

var numberPattern = regexp.MustCompile(`^[0-9]+(?:\.[0-9]+|/[0-9]+)?$`)

func readNumber(word string, signed bool) (Fraction, bool) {
	sign := int64(1)
	if signed && strings.HasPrefix(word, "-") {
		sign = -1
		word = word[1:]
	}
	if !numberPattern.MatchString(word) {
		return Fraction{}, false
	}
	if strings.Contains(word, "/") {
		a := strings.Split(word, "/")
		n, _ := strconv.ParseInt(a[0], 10, 64)
		d, _ := strconv.ParseInt(a[1], 10, 64)
		if d == 0 {
			return Fraction{}, false
		}
		return fraction(sign*n, d), true
	}
	if strings.Contains(word, ".") {
		a := strings.Split(word, ".")
		n, _ := strconv.ParseInt(a[0]+a[1], 10, 64)
		d := int64(1)
		for range a[1] {
			d *= 10
		}
		return fraction(sign*n, d), true
	}
	n, _ := strconv.ParseInt(word, 10, 64)
	return integer(sign * n), true
}
func finite(value Fraction) *Fraction {
	copy := value
	return &copy
}
func boundText(value *Fraction, lower bool) string {
	if value != nil {
		return value.String()
	}
	if lower {
		return "-inf"
	}
	return "inf"
}
