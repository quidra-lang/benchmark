package main

var directions = []Point{{0, -1}, {1, 0}, {0, 1}, {-1, 0}}

func neighbor(cell Point, direction int) Point {
	delta := directions[direction]
	return Point{cell.X + delta.X, cell.Y + delta.Y}
}

type DistanceField struct {
	Grid *GridMap
	Exit Point
	Dist []int
}

func newDistanceField(grid *GridMap, towers map[Point]bool) *DistanceField {
	field := &DistanceField{Grid: grid, Exit: grid.Exit, Dist: make([]int, grid.Width*grid.Height)}
	for i := range field.Dist {
		field.Dist[i] = -1
	}
	field.Dist[grid.Exit.Y*grid.Width+grid.Exit.X] = 0
	queue := []Point{grid.Exit}
	for head := 0; head < len(queue); head++ {
		cell := queue[head]
		for direction := range directions {
			following := neighbor(cell, direction)
			if grid.Inside(following) && !grid.Rock(following) && !towers[following] && field.At(following) < 0 {
				field.Dist[following.Y*grid.Width+following.X] = field.At(cell) + 1
				queue = append(queue, following)
			}
		}
	}
	return field
}
func (f *DistanceField) At(cell Point) int { return f.Dist[cell.Y*f.Grid.Width+cell.X] }
func (f *DistanceField) Direction(cell Point) int {
	best, bestDist := -1, 0
	for direction := range directions {
		following := neighbor(cell, direction)
		if !f.Grid.Inside(following) {
			continue
		}
		distance := f.At(following)
		if distance >= 0 && (best < 0 || distance < bestDist) {
			best, bestDist = direction, distance
		}
	}
	return best
}
func (f *DistanceField) Next(cell Point) Point { return neighbor(cell, f.Direction(cell)) }
func (f *DistanceField) Path(start Point) []Point {
	path := []Point{start}
	for path[len(path)-1] != f.Exit {
		path = append(path, f.Next(path[len(path)-1]))
	}
	return path
}
