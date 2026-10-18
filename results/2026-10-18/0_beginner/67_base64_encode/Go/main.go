package main

import (
	"fmt"
)

func main() {
	alphabet := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	for _, s := range []string{"Man", "Hello, World!", "", "<b>bold</b>", "a+b=c?"} {
		encoded := []byte{}
		for i := 0; i < len(s); i += 3 {
			remain := len(s) - i
			bits := uint32(s[i]) << 16
			if remain > 1 {
				bits |= uint32(s[i + 1]) << 8
			}
			if remain > 2 {
				bits |= uint32(s[i + 2])
			}
			encoded = append(encoded, alphabet[(bits >> 18) &63], alphabet[(bits >> 12) &63])
			if remain > 1 {
				encoded = append(encoded, alphabet[(bits >> 6) &63])
			} else {
				encoded = append(encoded, '=')
			}
			if remain > 2 {
				encoded = append(encoded, alphabet[bits &63])
			} else {
				encoded = append(encoded, '=')
			}
		}
		fmt.Printf("\"%s\" -> \"%s\"\n", s, encoded)
	}
}
