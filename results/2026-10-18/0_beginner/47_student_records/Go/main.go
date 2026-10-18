package main

import (
	"fmt"
	"sort"
)

func main() {
	students := []struct {
		name string
		scores [3]int
		total int
	}{{"Tanaka", [3]int{78, 85, 94}, 0}, {"Suzuki", [3]int{88, 74, 82}, 0}, {"Yamada", [3]int{65, 90,
		71}, 0}, {"Ito", [3]int{80, 79, 85}, 0}, {"Kato", [3]int{92, 88, 95}, 0}, {"Mori", [3]int{70, 62,
		78}, 0}}
	for i := range students {
		for _, s := range students[i].scores {
			students[i].total += s
		}
	}
	sort.Slice(students, func(i, j int) bool {
		a, b := students[i], students[j]
		if a.total != b.total {
			return a.total > b.total
		}
		return a.name < b.name
	})
	rank := 0
	for i, s := range students {
		if i == 0 || s.total != students[i - 1].total {
			rank = i + 1
		}
		fmt.Printf("%d. %s total=%d average=%.2f\n", rank, s.name, s.total, float64(s.total)/3.0)
	}
}
