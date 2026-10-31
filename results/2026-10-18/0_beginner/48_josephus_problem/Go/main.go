package main

import (
	"fmt"
	"slices"
)

func main() {
	for _, c := range [][2]int{{7, 3}, {10, 2}, {41, 3}} {
		n, k := c[0], c[1]
		people := make([]int, n)
		for i := range people {
			people[i] = i + 1
		}
		index, last := 0, 0
		fmt.Printf("n=%d k=%d:", n, k)
		for len(people) > 0 {
			index = (index + k - 1) % len(people)
			last = people[index]
			fmt.Printf(" %d", last)
			people = slices.Delete(people, index, index+1)
		}
		fmt.Printf("\nsurvivor: %d\n", last)
	}
}
