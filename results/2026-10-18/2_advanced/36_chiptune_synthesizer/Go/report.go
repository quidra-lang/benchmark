package main

import (
	"fmt"
	"strings"
)

func hexLines(samples []int64) []string {
	lines := []string{}
	for start := 0; start < len(samples); start += 32 {
		var b strings.Builder
		for _, s := range samples[start:min(start+32, len(samples))] {
			fmt.Fprintf(&b, "%02X", s)
		}
		lines = append(lines, b.String())
	}
	return lines
}
func adler32Text(values []int64) string {
	a, b := int64(1), int64(0)
	for _, v := range values {
		a = (a + v) % 65521
		b = (b + a) % 65521
	}
	return fmt.Sprintf("%08X", b*65536+a)
}
func abs(v int64) int64 {
	if v < 0 {
		return -v
	}
	return v
}
func peak(values []int64, center int64) int64 {
	var p int64
	for _, v := range values {
		p = max(p, abs(v-center))
	}
	return p
}
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
func rootMeanSquare(values []int64, center int64) int64 {
	var total int64
	for _, v := range values {
		d := v - center
		total += d * d
	}
	return isqrt(total / int64(len(values)))
}
func zeroCrossings(samples []int64) int {
	count := 0
	for i := 1; i < len(samples); i++ {
		if (samples[i-1] < 128) != (samples[i] < 128) {
			count++
		}
	}
	return count
}
