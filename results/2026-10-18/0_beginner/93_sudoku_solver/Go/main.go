package main

import "fmt"

func solve(board *[9][9]int, placements *uint64) bool {
	row, col := -1, -1
	for r := 0; r < 9 && row < 0; r++ {
		for c := 0; c < 9; c++ {
			if board[r][c] == 0 {
				row, col = r, c
				break
			}
		}
	}
	if row < 0 {
		return true
	}
	for d := 1; d <= 9; d++ {
		safe := true
		for k := 0; k < 9; k++ {
			if board[row][k] == d || board[k][col] == d {
				safe = false
			}
		}
		for r := row / 3 * 3; r < row/3*3+3; r++ {
			for c := col / 3 * 3; c < col/3*3+3; c++ {
				if board[r][c] == d {
					safe = false
				}
			}
		}
		if safe {
			board[row][col] = d
			(*placements)++
			if solve(board, placements) {
				return true
			}
			board[row][col] = 0
		}
	}
	return false
}

func main() {
	rows := []string{"800025000", "070080005", "260400070", "000001900", "010000040", "600200000", "900010000",
		"700000004", "020000036"}
	board := [9][9]int{}
	for r, row := range rows {
		for c := range row {
			board[r][c] = int(row[c] - '0')
		}
	}
	placements := uint64(0)
	solve(&board, &placements)
	for _, row := range board {
		for c, d := range row {
			if c > 0 {
				fmt.Print(" ")
			}
			fmt.Print(d)
		}
		fmt.Println()
	}
	fmt.Printf("placements: %d\n", placements)
}
