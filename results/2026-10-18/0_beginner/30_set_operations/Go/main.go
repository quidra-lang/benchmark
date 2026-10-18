package main

import (
	"fmt"
)

func main() {
	a, b := [26]bool{}, [26]bool{}
	for _, n := range []int{12, 5, 8, 21, 5, 17, 3, 12, 9} {
		a[n] = true
	}
	for _, n := range []int{8, 14, 21, 6, 14, 3, 25, 6} {
		b[n] = true
	}
	for op, label := range []string{"union", "intersection", "difference", "symmetric difference"} {
		fmt.Printf("%s:", label)
		for n := 0; n < 26; n++ {
			keep := false
			switch op {
			case 0:
				keep = a[n] || b[n]
			case 1:
				keep = a[n] && b[n]
			case 2:
				keep = a[n] && ! b[n]
			case 3:
				keep = a[n] != b[n]
			}
			if keep {
				fmt.Printf(" %d", n)
			}
		}
		fmt.Println()
	}
}
