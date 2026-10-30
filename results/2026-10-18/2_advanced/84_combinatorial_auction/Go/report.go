package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

type Fraction struct{ N, D int64 }

func gcd(a, b int64) int64 {
	if a < 0 {
		a = -a
	}
	for b != 0 {
		a, b = b, a%b
	}
	return a
}
func fraction(n, d int64) Fraction {
	if d < 0 {
		n, d = -n, -d
	}
	g := gcd(n, d)
	return Fraction{n / g, d / g}
}
func whole(n int64) Fraction               { return Fraction{n, 1} }
func (a Fraction) Add(b Fraction) Fraction { return fraction(a.N*b.D+b.N*a.D, a.D*b.D) }
func (a Fraction) Sub(b Fraction) Fraction { return fraction(a.N*b.D-b.N*a.D, a.D*b.D) }
func (a Fraction) Mul(b Fraction) Fraction { return fraction(a.N*b.N, a.D*b.D) }
func (a Fraction) Div(b Fraction) Fraction { return fraction(a.N*b.D, a.D*b.N) }
func (a Fraction) Cmp(b Fraction) int {
	left, right := a.N*b.D, b.N*a.D
	if left < right {
		return -1
	}
	if left > right {
		return 1
	}
	return 0
}
func (a Fraction) String() string {
	if a.D == 1 {
		return strconv.FormatInt(a.N, 10)
	}
	return fmt.Sprintf("%d/%d", a.N, a.D)
}
func bundle(items []Item, mask int) string {
	names := []string{}
	for i, a := range items {
		if mask&(1<<i) != 0 {
			names = append(names, a.Name)
		}
	}
	if len(names) == 0 {
		return "-"
	}
	return strings.Join(names, "+")
}
func numberList(a []*Bid) string {
	if len(a) == 0 {
		return "-"
	}
	out := make([]string, len(a))
	for i, b := range a {
		out[i] = strconv.Itoa(b.Number)
	}
	return strings.Join(out, "+")
}
func writeLines(name string, a []string) {
	s := ""
	if len(a) > 0 {
		s = strings.Join(a, "\n") + "\n"
	}
	if e := os.WriteFile("output/"+name, []byte(s), 0644); e != nil {
		panic(e)
	}
}
