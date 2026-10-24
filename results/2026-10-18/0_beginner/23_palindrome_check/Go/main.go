package main

import "fmt"

func main() {
	for _, phrase := range []string{"Never odd or even", "Race a car", "Was it a car or a cat I saw?",
		"Hello, World!", "Step on no pets.", "No lemon, no melon"} {
		clean := []rune{}
		for _, c := range phrase {
			if c >= 'A' && c <= 'Z' {
				c = c - 'A' + 'a'
			}
			if c >= 'a' && c <= 'z' {
				clean = append(clean, c)
			}
		}
		yes := true
		for i := 0; i < len(clean) / 2; i++ {
			if clean[i] != clean[len(clean) - 1 - i] {
				yes = false
			}
		}
		result := "no"
		if yes {
			result = "yes"
		}
		fmt.Printf("%s -> %s\n", phrase, result)
	}
}
