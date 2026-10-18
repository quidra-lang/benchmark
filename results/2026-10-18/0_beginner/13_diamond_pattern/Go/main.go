package main

import (
	"fmt"
	"strings"
)

func main() {
	n := 5
	for row := 1; row < 2 * n; row++ {
		i := min(row, 2*n-row)
		fmt.Println(strings.Repeat(" ", n - i) + strings.Repeat("*", 2 * i - 1))
	}
}
