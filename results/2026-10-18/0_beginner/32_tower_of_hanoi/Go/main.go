package main

import (
	"fmt"
)

func hanoi(n int, source, target, auxiliary rune) int {
	if n == 0 {
		return 0
	}
	count := hanoi(n - 1, source, auxiliary, target)
	fmt.Printf("move disk %d from %c to %c\n", n, source, target)
	return count + 1 + hanoi(n - 1, auxiliary, target, source)
}

func main() {
	count := hanoi(4, 'A', 'C', 'B')
	fmt.Printf("total moves: %d\n", count)
}
