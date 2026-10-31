package main

import "sort"

type SuffixArray struct{ SA, Classes []int }
type AdjacentCheck struct{ Ordered, LCPSum, MaxLCP, Star int }

func symbol(c byte) int {
	switch c {
	case '$':
		return 0
	case '#':
		return 1
	case 'A':
		return 2
	case 'C':
		return 3
	case 'G':
		return 4
	default:
		return 5
	}
}
func countingSort(a []int, keys []int, classes int) []int {
	counts := make([]int, classes)
	for _, i := range a {
		counts[keys[i]]++
	}
	position := 0
	for i, n := range counts {
		counts[i] = position
		position += n
	}
	b := make([]int, len(a))
	for _, i := range a {
		key := keys[i]
		b[counts[key]] = i
		counts[key]++
	}
	return b
}
func suffixArray(text string) SuffixArray {
	n := len(text)
	positions, keys := make([]int, n), make([]int,
		n)
	for i := 0; i < n; i++ {
		positions[i] = i
		keys[i] = symbol(text[i])
	}
	order := countingSort(positions, keys,
		6)
	rank := make([]int, n)
	classes := 0
	previous := -1
	for _, i := range order {
		if keys[i] != previous {
			classes++
			previous = keys[i]
		}
		rank[i] = classes - 1
	}
	counts := []int{classes}
	for h := 1; classes < n; h *= 2 {
		second := make([]int,
			n)
		for i := 0; i < n; i++ {
			if i+h < n {
				second[i] = rank[i+h] + 1
			}
		}
		order = countingSort(countingSort(positions,
			second, classes+1), rank, classes)
		next := make([]int, n)
		nextClasses := 0
		lastA, lastB := -1, -1
		for _, i := range order {
			if rank[i] != lastA || second[i] != lastB {
				nextClasses++
				lastA,
					lastB = rank[i], second[i]
			}
			next[i] = nextClasses - 1
		}
		rank, classes = next, nextClasses
		counts = append(counts,
			classes)
	}
	return SuffixArray{order, counts}
}
func directSort(text string) []int {
	a := make([]int, len(text))
	for i := range a {
		a[i] = i
	}
	sort.Slice(a, func(i, j int) bool { return text[a[i]:] < text[a[j]:] })
	return a
}
func adjacent(text string, sa []int) AdjacentCheck {
	a := AdjacentCheck{Star: 1}
	for i := 1; i < len(sa); i++ {
		x,
			y := sa[i-1], sa[i]
		l := 0
		for text[x+l] == text[y+l] {
			l++
		}
		if symbol(text[x+l]) < symbol(text[y+l]) {
			a.Ordered++
		}
		a.LCPSum += l
		if l > a.MaxLCP {
			a.MaxLCP,
				a.Star = l, i
		}
	}
	return a
}
