package main

import "fmt"

func main() {
	a := []int{27, 64, 13, 88, 41, 5, 72, 36}
	total := 0
	for p := 1; p <= 7; p++ {
		swaps := 0
		for j := 0; j <= 7-p; j++ {
			if a[j] > a[j+1] {
				a[j], a[j+1] = a[j+1], a[j]
				swaps++
			}
		}
		total += swaps
		fmt.Printf("pass %d:", p)
		for _, n := range a {
			fmt.Printf(" %d", n)
		}
		fmt.Println()
		if swaps == 0 {
			break
		}
	}
	fmt.Printf("swaps: %d\n", total)
}
