package main

import (
	"fmt"
)

func main() {
	row := [12]int{1}
	for n := 0; n < 12; n++ {
		for k := n; k > 0; k-- {
			row[k] += row[k - 1]
		}
		for k := 0; k <= n; k++ {
			if k > 0 {
				fmt.Print(" ")
			}
			fmt.Print(row[k])
		}
		fmt.Println()
	}
}
