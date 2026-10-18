package main

import (
	"fmt"
)

func cipher(s string, shift byte) string {
	out := []byte(s)
	for i, c := range out {
		if c >= 'a' && c <= 'z' {
			out[i] = 'a' + (c - 'a' + shift) % 26
		} else if c >= 'A' && c <= 'Z' {
			out[i] = 'A' + (c - 'A' + shift) % 26
		}
	}
	return string(out)
}

func main() {
	message := "Zoe, meet Max by the Old Bridge at six!"
	encrypted := cipher(message, 3)
	fmt.Println(encrypted)
	fmt.Println(cipher(encrypted, 23))
}
