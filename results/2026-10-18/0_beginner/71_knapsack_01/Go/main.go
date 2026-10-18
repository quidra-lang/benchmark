package main

import (
	"fmt"
)

func main() {
	names := []string{"tent", "stove", "lantern", "rope", "camera", "blanket", "water"}
	weights, values := []int{10, 3, 2, 3, 5, 5, 6}, []int{120, 65, 45, 20, 90, 85, 100}
	dp := [8][21]int{}
	for i := 1; i <= 7; i++ {
		for w := 0; w <= 20; w++ {
			dp[i][w] = dp[i - 1][w]
			if weights[i - 1] <= w {
				dp[i][w] = max(dp[i][w], dp[i - 1][w - weights[i - 1]] + values[i - 1])
			}
		}
	}
	chosen := [7]bool{}
	capacity, totalWeight := 20, 0
	for i := 7; i >= 1; i-- {
		if dp[i][capacity] != dp[i - 1][capacity] {
			chosen[i - 1] = true
			capacity -= weights[i - 1]
			totalWeight += weights[i - 1]
		}
	}
	fmt.Printf("max value: %d\ntotal weight: %d\nitems:", dp[7][20], totalWeight)
	for i, name := range names {
		if chosen[i] {
			fmt.Printf(" %s", name)
		}
	}
	fmt.Println()
}
