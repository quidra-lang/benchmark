package main

import "fmt"

func search(n, row int, positions *[8]int, count *int, first *[8]int) {
	if row == n {
		if n == 8 && *count == 0 {
			*first = *positions
		}
		(*count)++
		return
	}
	for col := 0; col < n; col++ {
		safe := true
		for r := 0; r < row; r++ {
			difference := positions[r] - col
			if difference < 0 {
				difference = -difference
			}
			if positions[r] == col || difference == row - r {
				safe = false
				break
			}
		}
		if safe {
			positions[row] = col
			search(n, row + 1, positions, count, first)
		}
	}
}

func main() {
	first := [8]int{}
	for n := 4; n <= 8; n++ {
		positions := [8]int{}
		count := 0
		search(n, 0, &positions, &count, &first)
		fmt.Printf("N=%d: %d solutions\n", n, count)
	}
	for r := 0; r < 8; r++ {
		for c := 0; c < 8; c++ {
			ch := '.'
			if first[r] == c {
				ch = 'Q'
			}
			fmt.Printf("%c", ch)
		}
		fmt.Println()
	}
}
