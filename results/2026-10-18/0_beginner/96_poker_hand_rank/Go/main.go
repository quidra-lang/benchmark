package main

import (
	"fmt"
	"strings"
	"sort"
)

type Hand struct {
	text string
	category int
	key []int
}

func evaluate(text string) Hand {
	ranks := "23456789TJQKA"
	counts := [15]int{}
	flush := true
	for i := 0; i < 5; i++ {
		rank := strings.IndexByte(ranks, text[i * 3]) + 2
		counts[rank]++
		if text[i * 3 + 1] != text[1] {
			flush = false
		}
	}
	key := []int{}
	maximum, pairs := 0, 0
	for r := 14; r >= 2; r-- {
		if counts[r] > 0 {
			key = append(key, r)
			maximum = max(maximum, counts[r])
			if counts[r] == 2 {
				pairs++
			}
		}
	}
	wheel := len(key) == 5 && counts[14] > 0 && counts[2] > 0 && counts[3] > 0 && counts[4] > 0 && counts[5] > 0
	straight := len(key) == 5 && (key[0] - key[4] == 4 || wheel)
	category := 0
	switch {
	case straight && flush:
		category = 8
	case maximum == 4:
		category = 7
	case maximum == 3 && pairs == 1:
		category = 6
	case flush:
		category = 5
	case straight:
		category = 4
	case maximum == 3:
		category = 3
	case pairs == 2:
		category = 2
	case pairs == 1:
		category = 1
	}
	sort.Slice(key, func(i, j int) bool {
		a, b := key[i], key[j]
		if counts[a] != counts[b] {
			return counts[a] > counts[b]
		}
		return a > b
	})
	if wheel && straight {
		for i := range key {
			key[i] = 5 - i
		}
	}
	return Hand{text, category, key}
}

func main() {
	hands := []Hand{}
	for _, text := range []string{"9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD",
		"3H 6C 4S 2D 5C", "JD TC 4H 8C AS", "QC 6D QS 3S 6H", "9H KH 9S 8H 3D"} {
		hands = append(hands, evaluate(text))
	}
	sort.Slice(hands, func(i, j int) bool {
		a, b := hands[i], hands[j]
		if a.category != b.category {
			return a.category > b.category
		}
		for k := range a.key {
			if a.key[k] != b.key[k] {
				return a.key[k] > b.key[k]
			}
		}
		return false
	})
	categories := []string{"high card", "one pair", "two pair", "three of a kind", "straight", "flush",
		"full house", "four of a kind", "straight flush"}
	for i, h := range hands {
		fmt.Printf("%d. %s: %s\n", i + 1, h.text, categories[h.category])
	}
}
