package main

type Mask [][]bool

func newMask(width, height int) Mask {
	out := make(Mask, height)
	for y := range out {
		out[y] = make([]bool, width)
	}
	return out
}
func inside(p Point, width, height int) bool {
	return p.X >= 0 && p.X < width && p.Y >= 0 && p.Y < height
}
func neighbors(p Point, width, height int) []Point {
	out := []Point{}
	for dy := -1; dy <= 1; dy++ {
		for dx := -1; dx <= 1; dx++ {
			q := Point{p.X + dx, p.Y + dy}
			if (dx != 0 || dy != 0) && inside(q, width, height) {
				out = append(out, q)
			}
		}
	}
	return out
}
func directions(gx, gy Image) Image {
	out := newImage(len(gx[0]), len(gx))
	for y, row := range gx {
		for x, v := range row {
			ax, ay := abs(v), abs(gy[y][x])
			direction := 135
			if 29*ay <= 12*ax {
				direction = 0
			} else if 29*ay >= 70*ax {
				direction = 90
			} else if v*gy[y][x] < 0 {
				direction = 45
			}
			out[y][x] = direction
		}
	}
	return out
}
func suppress(magnitude, direction Image) Image {
	width, height := len(magnitude[0]), len(magnitude)
	out := newImage(width, height)
	offsets := map[int]Point{0: {-1, 0}, 45: {1, -1}, 90: {0, -1}, 135: {-1, -1}}
	for y := 1; y < height-1; y++ {
		for x := 1; x < width-1; x++ {
			d := offsets[direction[y][x]]
			v := magnitude[y][x]
			if v > magnitude[y+d.Y][x+d.X] && v >= magnitude[y-d.Y][x-d.X] {
				out[y][x] = v
			}
		}
	}
	return out
}
func hysteresis(nms Image, low, high int) (Mask, int, int, int) {
	width, height := len(nms[0]), len(nms)
	edge := newMask(width, height)
	queue := []Point{}
	strong, weak := 0, 0
	for y, row := range nms {
		for x, v := range row {
			if v >= high {
				strong++
				edge[y][x] = true
				queue = append(queue, Point{x, y})
			} else if v >= low {
				weak++
			}
		}
	}
	for i := 0; i < len(queue); i++ {
		for _, q := range neighbors(queue[i], width, height) {
			if !edge[q.Y][q.X] && nms[q.Y][q.X] >= low {
				edge[q.Y][q.X] = true
				queue = append(queue, q)
			}
		}
	}
	return edge, strong, weak, len(queue) - strong
}
func components(edge Mask) [][]Point {
	width, height := len(edge[0]), len(edge)
	seen := newMask(width, height)
	groups := [][]Point{}
	for y, row := range edge {
		for x, present := range row {
			if !present || seen[y][x] {
				continue
			}
			seen[y][x] = true
			queue := []Point{{x, y}}
			for i := 0; i < len(queue); i++ {
				for _, q := range neighbors(queue[i], width, height) {
					if edge[q.Y][q.X] && !seen[q.Y][q.X] {
						seen[q.Y][q.X] = true
						queue = append(queue, q)
					}
				}
			}
			groups = append(groups, queue)
		}
	}
	return groups
}
