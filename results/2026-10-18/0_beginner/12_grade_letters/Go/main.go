package main

import (
	"fmt"
)

func main() {
	counts := [5]int{}
	grades := "ABCDF"
	for _, s := range []int{78, 90, 100, 59, 80, 85, 89, 70, 45, 93} {
		g := 4
		if s >= 90 {
			g = 0
		} else if s >= 80 {
			g = 1
		} else if s >= 70 {
			g = 2
		} else if s >= 60 {
			g = 3
		}
		counts[g]++
		fmt.Printf("%d: %c\n", s, grades[g])
	}
	for i, c := range counts {
		fmt.Printf("%c: %d\n", grades[i], c)
	}
}
