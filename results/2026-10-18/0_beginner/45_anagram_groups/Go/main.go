package main

import (
	"fmt"
	"slices"
	"strings"
)

func main() {
	words := []string{"listen", "stone", "night", "silent", "notes", "apple", "thing", "enlist", "earth",
		"onset", "heart", "tones"}
	keys := make([]string, len(words))
	for i, w := range words {
		b := []byte(w)
		slices.Sort(b)
		keys[i] = string(b)
	}
	used := make([]bool, len(words))
	for i := range words {
		if !used[i] {
			group := []string{}
			for j := i; j < len(words); j++ {
				if !used[j] && keys[j] == keys[i] {
					used[j] = true
					group = append(group, words[j])
				}
			}
			fmt.Println(strings.Join(group, " "))
		}
	}
}
