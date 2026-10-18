package main

import (
	"fmt"
)

func main() {
	initial := []string{".#......", "..#.....", "###.....", "........", "........", "........", ".....###",
		"........"}
	board := [8][8]byte{}
	for r, row := range initial {
		copy(board[r][:], row)
	}
	for g := 0; g <= 4; g++ {
		fmt.Printf("generation %d\n", g)
		for _, row := range board {
			fmt.Println(string(row[:]))
		}
		if g == 4 {
			break
		}
		next := [8][8]byte{}
		for r := 0; r < 8; r++ {
			for c := 0; c < 8; c++ {
				neighbors := 0
				for dr := - 1; dr <= 1; dr++ {
					for dc := - 1; dc <= 1; dc++ {
						rr, cc := r + dr, c + dc
						if (dr != 0 || dc != 0) && rr >= 0 && rr < 8 && cc >= 0 && cc < 8 && board[rr][cc] == '#' {
							neighbors++
						}
					}
				}
				next[r][c] = '.'
				if neighbors == 3 || board[r][c] == '#' && neighbors == 2 {
					next[r][c] = '#'
				}
			}
		}
		board = next
	}
	alive := 0
	for _, row := range board {
		for _, c := range row {
			if c == '#' {
				alive++
			}
		}
	}
	fmt.Printf("alive: %d\n", alive)
}
