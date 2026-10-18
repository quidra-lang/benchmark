package main

import "fmt"

func main() {
	deck := [52]int{}
	for i := range deck {
		deck[i] = i
	}
	x := int64(2026)
	for i := 51; i >= 1; i-- {
		x = x * 48271 % 2147483647
		j := int(x % int64(i + 1))
		deck[i], deck[j] = deck[j], deck[i]
	}
	ranks, suits := "A23456789TJQK", "SHDC"
	for i, card := range deck {
		if i % 13 > 0 {
			fmt.Print(" ")
		}
		fmt.Printf("%c%c", ranks[card % 13], suits[card / 13])
		if i % 13 == 12 {
			fmt.Println()
		}
	}
}
