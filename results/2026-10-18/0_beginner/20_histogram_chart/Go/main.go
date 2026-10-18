package main

import (
	"fmt"
	"strings"
)

func main() {
	days := []string{"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"};
	counts := []int{7, 12, 4, 15, 9, 18, 11}
	for i, n := range counts {
		fmt.Printf("%s | %s %d\n", days[i], strings.Repeat("*", n), n)
	}
}
