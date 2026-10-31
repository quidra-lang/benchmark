package main

import (
	"fmt"
	"strconv"
)

func main() {
	for _, n := range []int64{0, 7, 999, 1000, -456789, 3141592, 9876543210} {
		if n < 0 {
			fmt.Print("-")
			n = -n
		}
		text := strconv.FormatInt(n, 10)
		for i, c := range text {
			if i > 0 && (len(text)-i)%3 == 0 {
				fmt.Print(",")
			}
			fmt.Printf("%c", c)
		}
		fmt.Println()
	}
}
