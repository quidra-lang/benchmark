package main

import (
	"sort"
	"strings"
)

func isLetter(c byte) bool { return c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' }

type SplitPoint struct {
	Position     int
	AppendHyphen bool
}
type Hyphenation struct {
	Words             map[string][]int
	LeftMin, RightMin int
}

func newHyphenation(lines, additions []string, left, right int) *Hyphenation {
	h := &Hyphenation{map[string][]int{}, left, right}
	for _, s := range append(append([]string(nil), lines...), additions...) {
		h.Register(s)
	}
	return h
}
func (h *Hyphenation) Register(spelling string) {
	parts := strings.Split(spelling, "-")
	position := 0
	points := []int{}
	for _, part := range parts[:len(parts)-1] {
		position += len(part)
		points = append(points, position)
	}
	h.Words[strings.Join(parts, "")] = points
}
func (h *Hyphenation) SplitPoints(word string) []SplitPoint {
	points := map[int]bool{}
	first, last := 0, len(word)
	for first < len(word) && !isLetter(word[first]) {
		first++
	}
	for last > first && !isLetter(word[last-1]) {
		last--
	}
	core := word[first:last]
	letters := len(core) > 0
	for i := range core {
		if !isLetter(core[i]) {
			letters = false
		}
	}
	if letters {
		for _, p := range h.Words[strings.ToLower(core)] {
			if p >= h.LeftMin && len(core)-p >= h.RightMin {
				points[first+p] = true
			}
		}
	}
	for p := 1; p < len(word)-1; p++ {
		if word[p] == '-' && isLetter(word[p-1]) && isLetter(word[p+1]) {
			points[p+1] = false
		}
	}
	positions := []int{}
	for p := range points {
		positions = append(positions, p)
	}
	sort.Ints(positions)
	result := []SplitPoint{}
	for _, p := range positions {
		result = append(result, SplitPoint{p, points[p]})
	}
	return result
}
