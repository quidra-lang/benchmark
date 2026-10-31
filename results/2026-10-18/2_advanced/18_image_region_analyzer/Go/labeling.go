package main

type Labeling struct {
	Labels             [][]int
	Count, Provisional int
}

func findRoot(parents []int, label int) int {
	for parents[label] != label {
		parents[label] = parents[parents[label]]
		label = parents[label]
	}
	return label
}

func unionRoots(parents []int, first, second int) {
	a, b := findRoot(parents, first), findRoot(parents, second)
	if a != b {
		parents[max(a, b)] = min(a, b)
	}
}

func labelComponents(mask Mask, connectivity int) Labeling {
	height, width := len(mask), len(mask[0])
	previous := []Point{{-1, 0}, {0, -1}}
	if connectivity == 8 {
		previous = []Point{{-1, 0}, {-1, -1}, {0, -1}, {1, -1}}
	}
	provisional := make([][]int, height)
	for y := range provisional {
		provisional[y] = make([]int, width)
	}
	parents := []int{0}
	for y, row := range mask {
		for x, foreground := range row {
			if !foreground {
				continue
			}
			var neighbors []int
			for _, offset := range previous {
				nx, ny := x+offset.X, y+offset.Y
				if occupied(mask, nx, ny) {
					neighbors = append(neighbors, provisional[ny][nx])
				}
			}
			if len(neighbors) == 0 {
				provisional[y][x] = len(parents)
				parents = append(parents, len(parents))
			} else {
				provisional[y][x] = neighbors[0]
				for _, other := range neighbors[1:] {
					unionRoots(parents, neighbors[0], other)
				}
			}
		}
	}
	numbers := make([]int, len(parents))
	labels := make([][]int, height)
	count := 0
	for y := range labels {
		labels[y] = make([]int, width)
		for x, value := range provisional[y] {
			if value == 0 {
				continue
			}
			root := findRoot(parents, value)
			if numbers[root] == 0 {
				count++
				numbers[root] = count
			}
			labels[y][x] = numbers[root]
		}
	}
	return Labeling{labels, count, len(parents) - 1}
}

func bitQuadEuler(mask Mask, connectivity int) int {
	singles, triples, diagonals := 0, 0, 0
	for y := -1; y < len(mask); y++ {
		for x := -1; x < len(mask[0]); x++ {
			tl, tr := occupied(mask, x, y), occupied(mask, x+1, y)
			bl, br := occupied(mask, x, y+1), occupied(mask, x+1, y+1)
			count := 0
			for _, value := range []bool{tl, tr, bl, br} {
				if value {
					count++
				}
			}
			if count == 1 {
				singles++
			} else if count == 3 {
				triples++
			} else if count == 2 && ((tl && br) || (tr && bl)) {
				diagonals++
			}
		}
	}
	sign := 2
	if connectivity == 8 {
		sign = -2
	}
	return (singles - triples + sign*diagonals) / 4
}
