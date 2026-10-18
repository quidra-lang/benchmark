package main

import (
	"fmt"
	"sort"
)

type Edge struct {
	a, b rune
	weight int
}

func find(parent * [8]int, v int) int {
	if parent[v] != v {
		parent[v] = find(parent, parent[v])
	}
	return parent[v]
}

func main() {
	edges := []Edge{{'A', 'B', 7}, {'C', 'A', 4}, {'B', 'C', 9}, {'B', 'D', 14}, {'D', 'C', 6}, {'C',
		'E', 3}, {'E', 'D', 5}, {'F', 'D', 11}, {'E', 'G', 16}, {'G', 'F', 8}, {'H', 'F', 12}, {'G', 'H',
		2}, {'H', 'E', 10}}
	sort.Slice(edges, func(i, j int) bool {
		return edges[i].weight < edges[j].weight
	})
	parent := [8]int{}
	for i := range parent {
		parent[i] = i
	}
	accepted, total, skipped := 0, 0, 0
	for _, e := range edges {
		if accepted == 7 {
			break
		}
		a, b := find(&parent, int(e.a - 'A')), find(&parent, int(e.b - 'A'))
		if a == b {
			skipped++
			continue
		}
		parent[a] = b
		accepted++
		total += e.weight
		fmt.Printf("%c-%c %d\n", min(e.a, e.b), max(e.a, e.b), e.weight)
	}
	fmt.Printf("total weight: %d\nskipped: %d\n", total, skipped)
}
