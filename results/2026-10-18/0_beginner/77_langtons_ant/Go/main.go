package main

import "fmt"

func main() {
	black := [11][11]bool{}
	dr, dc := []int{-1, 0, 1, 0}, []int{0, 1, 0, -1}
	r, c, d := 5, 5, 0
	for step := 0; step < 300; step++ {
		if black[r][c] {
			d = (d + 3) % 4
		} else {
			d = (d + 1) % 4
		}
		black[r][c] = !black[r][c]
		r, c = (r + dr[d] + 11) % 11, (c + dc[d] + 11) % 11
	}
	count := 0
	for i, row := range black {
		for j, b := range row {
			if b {
				count++
			}
			ch := '.'
			if i == r && j == c {
				ch = 'A'
			} else if b {
				ch = '#'
			}
			fmt.Printf("%c", ch)
		}
		fmt.Println()
	}
	fmt.Printf("black: %d\n", count)
}
