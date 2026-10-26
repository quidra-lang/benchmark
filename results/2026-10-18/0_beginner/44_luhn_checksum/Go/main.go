package main

import "fmt"

func main() {
	for _, s := range []string{"688126340316", "0128469655154", "92181914514156", "177332430060552",
		"7982377590420309", "9884593615513906"} {
		sum := 0
		for i := 0; i < len(s); i++ {
			d := int(s[len(s)-1-i] - '0')
			if i%2 == 1 {
				d *= 2
				if d > 9 {
					d -= 9
				}
			}
			sum += d
		}
		if sum%10 == 0 {
			fmt.Printf("%s: valid\n", s)
		} else {
			expected := (10 - (sum-int(s[len(s)-1]-'0'))%10) % 10
			fmt.Printf("%s: invalid (expected check digit %d)\n", s, expected)
		}
	}
}
