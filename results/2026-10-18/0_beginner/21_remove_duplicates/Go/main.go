package main

import (
	"fmt"
)

func main() {
	values := []int{12, 5, 12, 8, 3, 5, 20, 8, 8, 15, 3, 7, 20, 12, 9}
	unique := []int{}
	seen := map[int]bool{}
	for _, n := range values {
		if ! seen[n] {
			seen[n] = true
			unique = append(unique, n)
		}
	}
	for i, n := range unique {
		if i > 0 {
			fmt.Print(" ")
		}
		fmt.Print(n)
	}
	fmt.Printf("\nremoved: %d\n", len(values) - len(unique))
}
