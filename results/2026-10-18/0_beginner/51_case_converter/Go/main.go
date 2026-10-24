package main

import (
	"fmt"
	"strings"
)

func main() {
	for _, id := range []string{"user_name", "maxRetryCount", "ShoppingCartItem", "background-color",
		"get_last_login_time", "isEmailAddressValid"} {
		words := []string{}
		word := ""
		for _, c := range id {
			if c == '_' || c == '-' || (c >= 'A' && c <= 'Z') {
				if word != "" {
					words = append(words, word)
					word = ""
				}
				if c == '_' || c == '-' {
					continue
				}
			}
			if c >= 'A' && c <= 'Z' {
				c = c - 'A' + 'a'
			}
			word += string(c)
		}
		if word != "" {
			words = append(words, word)
		}
		caps := make([]string, len(words))
		for i, w := range words {
			caps[i] = strings.ToUpper(w[:1]) + w[1:]
		}
		camel := words[0] + strings.Join(caps[1:], "")
		fmt.Printf("%s: snake=%s, camel=%s, pascal=%s, kebab=%s\n", id, strings.Join(words, "_"), camel,
			strings.Join(caps, ""), strings.Join(words, "-"))
	}
}
