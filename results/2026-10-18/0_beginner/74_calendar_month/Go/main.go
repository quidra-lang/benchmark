package main

import (
	"fmt"
	"strings"
)

func main() {
	names := []string{"January", "February", "March", "April", "May", "June", "July", "August", "September",
		"October", "November", "December"}
	lengths := []int{31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
	for k, p := range [][2]int{{2024, 2}, {2026, 8}, {2026, 11}} {
		y, m := p[0], p[1]
		yy, mm := y, m
		if mm < 3 {
			mm += 12
			yy--
		}
		h := (1 + 13 * (mm + 1) / 5 + yy % 100 + (yy % 100) / 4 + (yy / 100) / 4 + 5 * (yy / 100)) % 7
		start := (h + 6) % 7
		days := lengths[m - 1]
		if m == 2 && (y % 400 == 0 || y % 4 == 0 && y % 100 != 0) {
			days++
		}
		if k > 0 {
			fmt.Println()
		}
		fmt.Printf("%s %d\nSu Mo Tu We Th Fr Sa\n%s", names[m - 1], y, strings.Repeat(" ", start * 3))
		for d := 1; d <= days; d++ {
			col := (start + d - 1) % 7
			if d > 1 && col > 0 {
				fmt.Print(" ")
			}
			fmt.Printf("%2d", d)
			if col == 6 || d == days {
				fmt.Println()
			}
		}
	}
}
