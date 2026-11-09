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
		index := 0
		removed := []int{}
		for len(people) > 0 {
			index = (index + k - 1) % len(people)
			removed = append(removed, people[index])
			people = slices.Delete(people, index, index+1)
		}
		fmt.Printf("n=%d k=%d:", n, k)
		for _, person := range removed {
			fmt.Printf(" %d", person)
		}
		fmt.Printf("\nsurvivor: %d\n", removed[len(removed)-1])
	}
}
