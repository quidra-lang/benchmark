package main

import (
	"fmt"
	"strings"
)

func symbolLines(a [][]int) []string {
	out := make([]string, len(a))
	for y, row := range a {
		b := make([]byte,
			len(row))
		for x, v := range row {
			b[x] = '.'
			if v == 1 {
				b[x] = '#'
			}
		}
		out[y] = string(b)
	}
	return out
}
func pbm(a [][]int, quiet, scale int) string {
	n := len(a)
	width := (n + 2*quiet) * scale
	var out strings.Builder
	fmt.Fprintf(&out,
		"P1\n%d %d\n", width, width)
	for py := 0; py < width; py++ {
		for px := 0; px < width; px++ {
			x, y := px/scale-quiet,
				py/scale-quiet
			bit := byte('0')
			if x >= 0 && y >= 0 && x < n && y < n && a[y][x] == 1 {
				bit = '1'
			}
			out.WriteByte(bit)
		}
		out.WriteByte('\n')
	}
	return out.String()
}
