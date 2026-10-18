package main

import (
	"fmt"
)

func main() {
	boards := [][3]string{{"XXX", "OO.", "O.X"}, {"X.O", ".X.", "O.."}, {"XO.", ".OX", "XO."}, {"XOX",
		"XOO", "OXX"}, {"X.O", "XO.", "O.X"}, {"XOX", "OXO", "OXX"}}
	lines := [][3]int{{0, 1, 2}, {3, 4, 5}, {6, 7, 8}, {0, 3, 6}, {1, 4, 7}, {2, 5, 8}, {0, 4, 8}, {2,
		4, 6}}
	for k, b := range boards {
		cells := b[0] + b[1] + b[2]
		winner := byte(0)
		for _, line := range lines {
			a, c, d := cells[line[0]], cells[line[1]], cells[line[2]]
			if a != '.' && a == c && c == d {
				winner = a
			}
		}
		result := "draw"
		if winner != 0 {
			result = fmt.Sprintf("%c wins", winner)
		} else {
			for i := range cells {
				if cells[i] == '.' {
					result = "in progress"
					break
				}
			}
		}
		fmt.Printf("board %d: %s\n", k + 1, result)
	}
}
