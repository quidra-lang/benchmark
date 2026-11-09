package main

import (
	"fmt"
	"strings"
)

func main() {
	words := strings.Split("we planted beans and carrots in the garden behind our old house", " ")
	longest, shortest, total := words[0], words[0], 0
	for _, w := range words {
		total += len(w)
		if len(w) > len(longest) {
			longest = w
		}
		if len(w) < len(shortest) {
			shortest = w
		}
	}
	fmt.Printf("words: %d\nlongest: %s\nshortest: %s\naverage length: %.2f\n",
		len(words), longest, shortest, float64(total)/float64(len(words)))
}
