package main

import (
	"fmt"
)

func days(y, m int) int {
	lengths := []int{31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
	n := lengths[m - 1]
	if m == 2 && (y % 400 == 0 || (y % 4 == 0 && y % 100 != 0)) {
		n++
	}
	return n
}

func main() {
	for _, p := range [][4]int{{1999, 12, 25, 10}, {2000, 2, 27, 3}, {2021, 2, 20, 14}, {2023, 11, 15,
		120}, {2026, 10, 17, 1500}} {
		y, m, d, n := p[0], p[1], p[2], p[3]
		for i := 0; i < n; i++ {
			d++
			if d > days(y, m) {
				d = 1
				m++
				if m > 12 {
					m = 1
					y++
				}
			}
		}
		fmt.Printf("%04d-%02d-%02d + %d days = %04d-%02d-%02d\n", p[0], p[1], p[2], n, y, m, d)
	}
}
