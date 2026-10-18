package main

import (
	"fmt"
	"strings"
)

func main() {
	sentence := "every program starts with a single line"
	characters := []byte(sentence)
	for i, j := 0, len(characters)-1; i < j; i, j = i+1, j-1 {
		characters[i], characters[j] = characters[j], characters[i]
	}
	fmt.Println(string(characters))
	words := strings.Split(sentence, " ")
	for i, j := 0, len(words)-1; i < j; i, j = i+1, j-1 {
		words[i], words[j] = words[j], words[i]
	}
	fmt.Println(strings.Join(words, " "))
}
