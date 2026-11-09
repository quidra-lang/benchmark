package main

import "fmt"

func floorDiv(a, b int64) int64 {
	q := a / b
	if a%b < 0 {
		q--
	}
	return q
}
func abs(v int64) int64 {
	if v < 0 {
		return -v
	}
	return v
}
func rdiv(a, b int64) int64 { return floorDiv(2*a+b, 2*b) }
func isqrt(n int64) int64 {
	lo, hi := int64(0), n
	for lo < hi {
		mid := lo + (hi-lo)/2 + 1
		if mid <= n/mid {
			lo = mid
		} else {
			hi = mid - 1
		}
	}
	return lo
}
func root(p, q int64) int64 { return (isqrt(40000*p/q) + 1) / 2 }
func two(v int64) string {
	sign := ""
	if v < 0 {
		sign = "-"
		v = -v
	}
	return fmt.Sprintf("%s%d.%02d", sign, v/100, v%100)
}
func four(v int64) string { return fmt.Sprintf("%d.%04d", v/10000, v%10000) }
func fraction(a, b int64) string {
	x, y := a, b
	for y != 0 {
		x, y = y, x%y
	}
	return fmt.Sprintf("%d/%d", a/x, b/x)
}
func ratio(a, b int64) string {
	if b == 0 {
		return fmt.Sprintf("%d/0 none", a)
	}
	return fmt.Sprintf("%d/%d reduced=%s percent=%s", a, b, fraction(a, b), two(rdiv(10000*a, b)))
}
func maybeTwo(v *int64) string {
	if v == nil {
		return "none"
	}
	return two(*v)
}
func optional(v int64) string {
	if v == 0 {
		return "-"
	}
	return fmt.Sprint(v)
}
