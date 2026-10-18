package main

import "fmt"

func main() {
	sentence := "Peter Piper picked a peck of pickled peppers!"
	counts := [26]int{}
	for _, c := range sentence {
		if c >= 'A' && c <= 'Z' {
			c = c - 'A' + 'a'
		}
		if c >= 'a' && c <= 'z' {
			counts[c - 'a']++
		}
	}
	for i, n := range counts {
		if n > 0 {
			fmt.Printf("%c: %d\n", 'a' + i, n)
		}
	}
}
