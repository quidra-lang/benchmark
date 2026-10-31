package main

import (
	"fmt"
	"math"
	"strings"
)

func fixed(v float64, k int) string {
	s := fmt.Sprintf("%.*f", k, v)
	if strings.HasPrefix(s, "-") {
		zero := true
		for _, c := range s[1:] {
			if c != '0' && c != '.' {
				zero = false
			}
		}
		if zero {
			s = s[1:]
		}
	}
	return s
}
func curvePlot(observed []int, fitted []float64) []string {
	t := len(observed)
	maximum := observed[0]
	for _, v := range observed {
		maximum = max(maximum, v)
	}
	w := len(fmt.Sprint(maximum))
	grid := make([][]byte, 20)
	for r := range grid {
		grid[r] = []byte(strings.Repeat(".", 70))
	}
	days := make([]int, 70)
	for x := 0; x < 70; x++ {
		day := 1 + x*(t-1)/69
		days[x] = day
		oy := min(19, 20*observed[day-1]/maximum)
		fy := min(19, int(math.Floor(20*fitted[day-1]/float64(maximum))))
		grid[oy][x] = 'o'
		grid[fy][x] = '*'
		if oy == fy {
			grid[oy][x] = '#'
		}
	}
	out := []string{fmt.Sprintf("plot observed o fitted * both # days 1 %d max %d", t, maximum)}
	for y := 19; y >= 0; y-- {
		out = append(out, fmt.Sprintf("%*d |%s", w, maximum*y/20, string(grid[y])))
	}
	axis := []byte(strings.Repeat("-", 70))
	labels := []byte(strings.Repeat(" ", 70))
	for x := 0; x < 70; x += 10 {
		axis[x] = '+'
		copy(labels[x:], []byte(fmt.Sprint(days[x])))
	}
	out = append(out, strings.Repeat(" ", w+1)+"+"+string(axis), strings.TrimRight(strings.Repeat(" ", w+2)+string(labels), " "))
	return out
}
