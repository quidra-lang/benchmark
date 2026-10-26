package main

import (
	"sort"
	"strconv"
	"strings"
)

func validWord(text string) bool {
	if len(text) < 3 || len(text) > 15 {
		return false
	}
	for i := range text {
		if text[i] < 'A' || text[i] > 'Z' {
			return false
		}
	}
	return true
}

func validInteger(text string, low, high int) bool {
	if text == "" || text[0] == '0' || len(text) > len(strconv.Itoa(high)) {
		return false
	}
	for i := range text {
		if text[i] < '0' || text[i] > '9' {
			return false
		}
	}
	value, err := strconv.Atoi(text)
	return err == nil && value >= low && value <= high
}

func wordLineError(line string) string {
	if strings.Count(line, " ") != 1 {
		return "bad format"
	}
	word, score, _ := strings.Cut(line, " ")
	if !validWord(word) {
		return "bad word"
	}
	if !validInteger(score, 1, 100) {
		return "bad score"
	}
	return ""
}

func clueLineError(line string) string {
	if strings.Count(line, "|") != 1 {
		return "bad format"
	}
	word, clue, _ := strings.Cut(line, "|")
	if !validWord(word) {
		return "bad word"
	}
	if len(clue) < 1 || len(clue) > 60 || clue[0] == ' ' || clue[len(clue)-1] == ' ' {
		return "bad clue"
	}
	return ""
}

func matches(word, pattern []byte) bool {
	for position, mark := range pattern {
		if mark != '.' && word[position] != mark {
			return false
		}
	}
	return true
}

type Word struct {
	Text    string
	Letters []byte
	Score   int
}
type LetterKey struct {
	Length, Position int
	Letter           byte
}
type WordIndex struct {
	Words    []Word
	Lookup   map[string]int
	ByLength map[int][]int
	ByLetter map[LetterKey][]int
}

func newWordIndex(scores map[string]int) *WordIndex {
	names := make([]string, 0, len(scores))
	for word := range scores {
		names = append(names, word)
	}
	sort.Slice(names, func(i, j int) bool {
		if scores[names[i]] == scores[names[j]] {
			return names[i] < names[j]
		}
		return scores[names[i]] > scores[names[j]]
	})
	index := &WordIndex{Lookup: make(map[string]int), ByLength: make(map[int][]int), ByLetter: make(map[LetterKey][]int)}
	for id, text := range names {
		letters := []byte(text)
		index.Words = append(index.Words, Word{text, letters, scores[text]})
		index.Lookup[text] = id
		index.ByLength[len(letters)] = append(index.ByLength[len(letters)], id)
		for position, letter := range letters {
			key := LetterKey{len(letters), position, letter}
			index.ByLetter[key] = append(index.ByLetter[key], id)
		}
	}
	return index
}

func (index *WordIndex) Candidates(pattern []byte, minimum int, used []bool) []int {
	pool := index.ByLength[len(pattern)]
	for position, mark := range pattern {
		if mark == '.' {
			continue
		}
		bucket := index.ByLetter[LetterKey{len(pattern), position, mark}]
		if len(bucket) < len(pool) {
			pool = bucket
		}
	}
	var result []int
	for _, id := range pool {
		if index.Words[id].Score < minimum {
			break
		}
		if !used[id] && matches(index.Words[id].Letters, pattern) {
			result = append(result, id)
		}
	}
	return result
}
