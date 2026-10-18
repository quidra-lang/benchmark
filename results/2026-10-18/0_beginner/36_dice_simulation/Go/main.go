package main

import (
	"fmt"
)

func main() {
	counts := [13]int{}
	x := int64(12345)
	for i := 0; i < 1000; i++ {
		x = x * 48271 % 2147483647
		a := x % 6 + 1
		x = x * 48271 % 2147483647
		b := x % 6 + 1
		counts[a + b]++
	}
	best := 2
	for s := 2; s <= 12; s++ {
		fmt.Printf("%d: %d\n", s, counts[s])
		if counts[s] > counts[best] {
			best = s
		}
	}
	fmt.Printf("most frequent: %d\n", best)
}
