package main

import "fmt"

func main() {
	coins := []int{1, 5, 6, 9}
	minimum, ways := [41]int{}, [41]int{1}
	for amount := 1; amount <= 40; amount++ {
		minimum[amount] = 1000
		for _, coin := range coins {
			if coin <= amount {
				minimum[amount] = min(minimum[amount], minimum[amount - coin] + 1)
			}
		}
	}
	for _, coin := range coins {
		for amount := coin; amount <= 40; amount++ {
			ways[amount] += ways[amount - coin]
		}
	}
	for _, target := range []int{8, 11, 15, 22, 33, 40} {
		remaining, greedy := target, 0
		for i := 3; i >= 0; i-- {
			greedy += remaining / coins[i]
			remaining %= coins[i]
		}
		fmt.Printf("%d: min=%d greedy=%d ways=%d\n", target, minimum[target], greedy, ways[target])
	}
}
