package main

import (
	"fmt"
	"strings"
)

func main() {
	for _, s := range []string{"AAABBBCCCD", "WWWWWWWWWWWWBWWWWWWWWWWWWBBB", "ALGORITHM", "MISSISSIPPI",
		"XXXXXXXXXXYYYYYYYYYYYYYYYYYYYYYZ"} {
		encoded := "";
		for i := 0; i < len(s); {
			j := i + 1;
			for j < len(s) && s[j] == s[i] {
				j++
			};
			encoded += fmt.Sprintf("%d%c", j - i, s[i]);
			i = j
		};
		decoded := "";
		for i := 0; i < len(encoded); {
			count := 0;
			for encoded[i] >= '0' && encoded[i] <= '9' {
				count = count * 10 + int(encoded[i] - '0');
				i++
			};
			decoded += strings.Repeat(string(encoded[i]), count);
			i++
		};
		fmt.Printf("%s -> %s -> %s\n", s, encoded, decoded)
	}
}
