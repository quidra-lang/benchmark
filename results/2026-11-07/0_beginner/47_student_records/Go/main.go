package main

import (
	"fmt"
	"sort"
)

func main() {
	students := []struct {
		name   string
		scores [3]int
		total  int
	}{
		{name: "Tanaka", scores: [3]int{78, 85, 94}},
		{name: "Suzuki", scores: [3]int{88, 74, 82}},
		{name: "Yamada", scores: [3]int{65, 90, 71}},
		{name: "Ito", scores: [3]int{80, 79, 85}},
		{name: "Kato", scores: [3]int{92, 88, 95}},
		{name: "Mori", scores: [3]int{70, 62, 78}},
	}
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
		if i == 0 || s.total != students[i-1].total {
			rank = i + 1
		}
		fmt.Printf("%d. %s total=%d average=%.2f\n", rank, s.name, s.total, float64(s.total)/3.0)
	}
}
