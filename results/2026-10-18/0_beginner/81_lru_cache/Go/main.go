package main

import (
	"fmt"
	"slices"
)

func main() {
	cache := []rune{}
	hits, misses := 0, 0
	for _, key := range "BACBDABEADDCAEB" {
		position := slices.Index(cache, key)
		hit := position >= 0
		evicted := rune(0)
		if hit {
			hits++
			cache = slices.Delete(cache, position, position+1)
		} else {
			misses++
			if len(cache) == 3 {
				evicted = cache[2]
				cache = cache[:2]
			}
		}
		cache = append([]rune{key}, cache...)
		result := "miss"
		if hit {
			result = "hit"
		}
		fmt.Printf("%c: %s", key, result)
		if evicted != 0 {
			fmt.Printf(", evict %c", evicted)
		}
		fmt.Print(" [")
		for i, c := range cache {
			if i > 0 {
				fmt.Print(" ")
			}
			fmt.Printf("%c", c)
		}
		fmt.Println("]")
	}
	fmt.Printf("hits: %d misses: %d\n", hits, misses)
}
