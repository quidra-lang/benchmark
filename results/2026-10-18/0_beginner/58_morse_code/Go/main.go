package main

import (
	"fmt"
	"strings"
)

func main() {
	symbols := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	codes := []string{".-", "-...", "-.-.", "-..", ".", "..-.", "--.", "....", "..", ".---", "-.-",
		".-..", "--", "-.", "---", ".--.", "--.-", ".-.", "...", "-", "..-", "...-", ".--", "-..-", "-.--",
		"--..", "-----", ".----", "..---", "...--", "....-", ".....", "-....", "--...", "---..", "----."}
	message := "MEET ME AT PIER 9 AT 1745"
	words := []string{}
	for _, w := range strings.Split(message, " ") {
		parts := []string{}
		for _, c := range w {
			parts = append(parts, codes[strings.IndexRune(symbols, c)])
		}
		words = append(words, strings.Join(parts, " "))
	}
	encoded := strings.Join(words, " / ")
	fmt.Println(encoded)
	decoded := []string{}
	for _, w := range strings.Split(encoded, " / ") {
		word := ""
		for _, token := range strings.Split(w, " ") {
			for i, code := range codes {
				if code == token {
					word += string(symbols[i])
					break
				}
			}
		}
		decoded = append(decoded, word)
	}
	fmt.Println(strings.Join(decoded, " "))
}
