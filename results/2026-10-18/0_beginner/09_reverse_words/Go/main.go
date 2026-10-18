package main

import (
    "fmt"
    "slices"
    "strings"
)

func main() {
    sentence := "every program starts with a single line"
    characters := []byte(sentence)
    slices.Reverse(characters)
    fmt.Println(string(characters))
    words := strings.Split(sentence, " ")
    slices.Reverse(words)
    fmt.Println(strings.Join(words, " "))
}
