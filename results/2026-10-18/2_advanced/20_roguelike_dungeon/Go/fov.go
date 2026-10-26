package main

var directionNames = []string{"N", "NE", "E", "SE", "S", "SW", "W", "NW"}
var directions = []Point{{0, -1}, {1, -1}, {1, 0}, {1, 1}, {0, 1}, {-1, 1}, {-1, 0}, {-1, -1}}

func abs(value int) int {
	if value < 0 {
		return -value
	}
	return value
}
func passable(level *Level, x, y int) bool {
	switch level.Terrain[y][x] {
	case '.', '#', '+', '<', '>':
		return true
	}
	return false
}
func canMove(level *Level, x, y, dx, dy int) bool {
	if !passable(level, x+dx, y+dy) {
		return false
	}
	return dx == 0 || dy == 0 || (level.Terrain[y][x] != '+' && level.Terrain[y+dy][x+dx] != '+')
}
func line(x0, y0, x1, y1 int) []Point {
	dx, dy := abs(x1-x0), abs(y1-y0)
	sx, sy := -1, -1
	if x1 > x0 {
		sx = 1
	}
	if y1 > y0 {
		sy = 1
	}
	err, x, y := dx-dy, x0, y0
	var cells []Point
	for x != x1 || y != y1 {
		e2 := 2 * err
		if e2 > -dy {
			err -= dy
			x += sx
		}
		if e2 < dx {
			err += dx
			y += sy
		}
		cells = append(cells, Point{x, y})
	}
	return cells
}
func fieldOfView(level *Level, px, py, radius int) [][]bool {
	visible := make([][]bool, level.Height)
	for y := range visible {
		visible[y] = make([]bool, level.Width)
	}
	for y := max(0, py-radius); y < min(level.Height, py+radius+1); y++ {
		for x := max(0, px-radius); x < min(level.Width, px+radius+1); x++ {
			if (x-px)*(x-px)+(y-py)*(y-py) > radius*radius {
				continue
			}
			cells := line(px, py, x, y)
			clear := true
			for i := 0; i < len(cells)-1; i++ {
				if !passable(level, cells[i].X, cells[i].Y) {
					clear = false
					break
				}
			}
			visible[y][x] = clear
		}
	}
	return visible
}
func distances(level *Level, px, py int) [][]int {
	dist := make([][]int, level.Height)
	for y := range dist {
		dist[y] = make([]int, level.Width)
		for x := range dist[y] {
			dist[y][x] = -1
		}
	}
	dist[py][px] = 0
	queue := []Point{{px, py}}
	for head := 0; head < len(queue); head++ {
		point := queue[head]
		for _, step := range directions {
			nx, ny := point.X+step.X, point.Y+step.Y
			if canMove(level, point.X, point.Y, step.X, step.Y) && dist[ny][nx] < 0 {
				dist[ny][nx] = dist[point.Y][point.X] + 1
				queue = append(queue, Point{nx, ny})
			}
		}
	}
	return dist
}
