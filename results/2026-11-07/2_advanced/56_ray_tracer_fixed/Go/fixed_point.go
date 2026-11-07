package main

const S int64 = 4096

func floorDiv(a, b int64) int64 {
	q, r := a/b, a%b
	if r != 0 && ((r < 0) != (b < 0)) {
		q--
	}
	return q
}
func mul(a, b int64) int64 { return floorDiv(a*b, S) }
func isqrt(n int64) int64 {
	if n < 2 {
		return n
	}
	lo, hi := int64(1), n
	for lo <= hi {
		m := (lo + hi) / 2
		if m <= n/m {
			lo = m + 1
		} else {
			hi = m - 1
		}
	}
	return hi
}
func absolute(a int64) int64 {
	if a < 0 {
		return -a
	}
	return a
}
