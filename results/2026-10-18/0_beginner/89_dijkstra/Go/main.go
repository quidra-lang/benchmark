package main

import (
	"fmt"
	"slices"
	"strings"
)

func main() {
	graph := [7][7]int{}
	for _, e := range [][3]int{{0, 1, 7}, {0, 2, 3}, {0, 3, 9}, {1, 2, 2}, {2, 4, 6}, {1, 3, 3}, {3,
		4, 4}, {3, 5, 5}, {4, 5, 3}, {4, 6, 8}, {5, 6, 4}} {
		graph[e[0]][e[1]], graph[e[1]][e[0]] = e[2], e[2]
	}
	distance, parent, done := [7]int{}, [7]int{}, [7]bool{}
	for i := 0; i < 7; i++ {
		distance[i] = 1000000
		parent[i] = -1
	}
	distance[0] = 0
	for step := 0; step < 7; step++ {
		u := -1
		for v := 0; v < 7; v++ {
			if !done[v] && (u < 0 || distance[v] < distance[u]) {
				u = v
			}
		}
		done[u] = true
		for v := 0; v < 7; v++ {
			if graph[u][v] > 0 && distance[u] + graph[u][v] < distance[v] {
				distance[v] = distance[u] + graph[u][v]
				parent[v] = u
			}
		}
	}
	for v := 0; v < 7; v++ {
		path := []string{}
		for u := v; u >= 0; u = parent[u] {
			path = append(path, string(rune('A' + u)))
		}
		slices.Reverse(path)
		fmt.Printf("%c: distance=%d path=%s\n", 'A' + v, distance[v], strings.Join(path, "-"))
	}
}
