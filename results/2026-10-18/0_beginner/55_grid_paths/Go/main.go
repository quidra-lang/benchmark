package main

import (
	"fmt"
)

func main() {
	grid := []string{".......", "..#....", "....#..", ".#.....", "...#.#.", "......."}
	for _, obstacles := range []bool{false, true} {
		dp := [6][7]int{}
		dp[0][0] = 1
		for r := 0; r < 6; r++ {
			for c := 0; c < 7; c++ {
				if obstacles && grid[r][c] == '#' {
					continue
				}
				if r > 0 {
					dp[r][c] += dp[r - 1][c]
				}
				if c > 0 {
					dp[r][c] += dp[r][c - 1]
				}
			}
		}
		label := "without"
		if obstacles {
			label = "with"
		}
		fmt.Printf("%s obstacles: %d\n", label, dp[5][6])
	}
}
