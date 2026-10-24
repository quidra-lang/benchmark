package main

import "fmt"

func main() {
	rows := []string{"#############", "#S..#.......#", "#.#.#.###.#.#", "#.#...#...#.#", "#.###.#.###.#",
		"#...#...#...#", "###.#####.#.#", "#.......#..G#", "#############"}
	maze := make([][]byte, 9)
	parent, distance := [117]int{}, [117]int{}
	start, goal := 0, 0
	for r, row := range rows {
		maze[r] = []byte(row)
	}
	for i := 0; i < 117; i++ {
		parent[i] = -1
		if maze[i / 13][i % 13] == 'S' {
			start = i
		}
		if maze[i / 13][i % 13] == 'G' {
			goal = i
		}
	}
	queue := []int{start}
	parent[start] = start
	directions := [][2]int{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}
	for head := 0; head < len(queue); head++ {
		v := queue[head]
		r, c := v / 13, v % 13
		for _, d := range directions {
			rr, cc := r + d[0], c + d[1]
			if rr < 0 || rr >= 9 || cc < 0 || cc >= 13 || maze[rr][cc] == '#' {
				continue
			}
			w := rr * 13 + cc
			if parent[w] < 0 {
				parent[w] = v
				distance[w] = distance[v] + 1
				queue = append(queue, w)
			}
		}
	}
	for v := goal; v != start; v = parent[v] {
		if maze[v / 13][v % 13] == '.' {
			maze[v / 13][v % 13] = '*'
		}
	}
	fmt.Printf("steps: %d\n", distance[goal])
	for _, row := range maze {
		fmt.Println(string(row))
	}
}
