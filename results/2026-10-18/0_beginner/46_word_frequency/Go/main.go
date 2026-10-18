package main

import (
	"fmt"
	"strings"
	"sort"
)

func main() {
	text := "The cat sat on the mat. The dog sat on the rug, and the cat watched the dog. A bird sang on the fence, and the Dog barked at the bird. The cat slept in the sun, the bird flew away, and the dog sat by the door.";
	words := strings.FieldsFunc(strings.ToLower(text), func(c rune) bool {
		return c < 'a' || c > 'z'
	});
	counts := map[string]int{};
	for _, w := range words {
		counts[w]++
	};
	entries := []string{};
	for w := range counts {
		entries = append(entries, w)
	};
	sort.Slice(entries, func(i, j int) bool {
		a, b := entries[i], entries[j];
		if counts[a] != counts[b] {
			return counts[a] > counts[b]
		};
		return a < b
	});
	for _, w := range entries[: 5] {
		fmt.Printf("%s: %d\n", w, counts[w])
	};
	fmt.Printf("distinct words: %d\n", len(entries))
}
