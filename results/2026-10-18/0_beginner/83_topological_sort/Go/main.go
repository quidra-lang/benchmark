package main

import (
	"fmt"
	"sort"
	"strings"
)

func solve(names []string, edges [][2]string, showCycle bool) {
	n := len(names)
	graph := make([][]bool, n)
	indegree := make([]int, n)
	taken := make([]bool, n)
	index := map[string]int{}
	for i, name := range names {
		graph[i] = make([]bool, n)
		index[name] = i
	}
	for _, e := range edges {
		a, b := index[e[0]], index[e[1]]
		graph[a][b] = true
		indegree[b]++
	}
	order := []string{}
	for {
		best := -1
		for v := 0; v < n; v++ {
			if !taken[v] && indegree[v] == 0 && (best < 0 || names[v] < names[best]) {
				best = v
			}
		}
		if best < 0 {
			break
		}
		order = append(order, names[best])
		taken[best] = true
		for v := 0; v < n; v++ {
			if graph[best][v] {
				indegree[v]--
			}
		}
	}
	fmt.Printf("order: %s\n", strings.Join(order, " -> "))
	if showCycle {
		remaining := []string{}
		for i, name := range names {
			if !taken[i] {
				remaining = append(remaining, name)
			}
		}
		sort.Strings(remaining)
		fmt.Printf("cycle: %s\n", strings.Join(remaining, " "))
	}
}

func main() {
	names1 := []string{
		"physics", "algebra", "graphics", "programming", "statistics", "calculus", "databases",
		"algorithms",
	}
	edges1 := [][2]string{{"calculus", "physics"}, {"algebra", "calculus"}, {"programming", "algorithms"},
		{"algebra", "statistics"}, {"algorithms", "databases"}, {"statistics", "databases"},
		{"calculus", "graphics"}, {"algorithms", "graphics"}, {"physics", "graphics"}}
	names2 := []string{"music", "ecology", "art", "geology", "biology", "chemistry"}
	edges2 := [][2]string{{"music", "art"}, {"art", "ecology"}, {"biology", "chemistry"},
		{"chemistry", "ecology"}, {"ecology", "geology"}, {"geology", "chemistry"}}
	solve(names1, edges1, false)
	solve(names2, edges2, true)
}
