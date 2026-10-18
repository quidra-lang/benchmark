package main

import (
	"fmt"
)

func main() {
	a, b, sum := 1, 1, 0
	for i := 0; i < 30; i++ {
		if i > 0 {
			fmt.Print(" ")
		}
		fmt.Print(a)
		sum += a
		a, b = b, a + b
	}
	fmt.Printf("\nsum: %d\n", sum)
}
