package main

import (
	"fmt"
	"sort"
)

func dfs(v int, graph *[9][9]bool, seen *[9]bool, order *[]int) {
	seen[v] = true
	*order = append(*order, v)
	for w := 0; w < 9; w++ {
		if graph[v][w] && !seen[w] {
			dfs(w, graph, seen, order)
		}
	}
}

func main() {
	graph := [9][9]bool{}
	for _, e := range [][2]int{{5, 0}, {3, 8}, {7, 2}, {1, 6}, {0, 2}, {5, 3}, {7, 5}, {6, 4}, {8, 7}} {
		graph[e[0]][e[1]], graph[e[1]][e[0]] = true, true
	}
	seen := [9]bool{}
	order := []int{}
	dfs(0, &graph, &seen, &order)
	fmt.Print("DFS:")
	for _, v := range order {
		fmt.Printf(" %d", v)
	}
	fmt.Println()
	seen = [9]bool{}
	queue := []int{0}
	seen[0] = true
	fmt.Print("BFS:")
	for head := 0; head < len(queue); head++ {
		v := queue[head]
		fmt.Printf(" %d", v)
		for w := 0; w < 9; w++ {
			if graph[v][w] && !seen[w] {
				seen[w] = true
				queue = append(queue, w)
			}
		}
	}
	fmt.Println()
	seen = [9]bool{}
	components := [][]int{}
	for v := 0; v < 9; v++ {
		if !seen[v] {
			component := []int{}
			dfs(v, &graph, &seen, &component)
			sort.Ints(component)
			components = append(components, component)
		}
	}
	fmt.Printf("components: %d\n", len(components))
	for i, component := range components {
		fmt.Printf("component %d:", i + 1)
		for _, v := range component {
			fmt.Printf(" %d", v)
		}
		fmt.Println()
	}
}
