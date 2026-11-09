package main

func squaredDistance(a, b Point) int64 { dx, dy := a.X-b.X, a.Y-b.Y; return dx*dx + dy*dy }

type Cell struct{ X, Y int64 }
type GridIndex struct {
	Points []Point
	EPS    int64
	Cells  map[Cell][]int
}

func newGrid(points []Point, eps int) *GridIndex {
	grid := &GridIndex{points, int64(eps), map[Cell][]int{}}
	for i, p := range points {
		cell := grid.CellOf(p)
		grid.Cells[cell] = append(grid.Cells[cell], i)
	}
	return grid
}
func (g *GridIndex) CellOf(p Point) Cell { return Cell{p.X / g.EPS, p.Y / g.EPS} }
func (g *GridIndex) Neighborhood(index int) ([]int, int) {
	p := g.Points[index]
	c := g.CellOf(p)
	neighbors := []int{}
	candidates := 0
	for y := c.Y - 1; y <= c.Y+1; y++ {
		for x := c.X - 1; x <= c.X+1; x++ {
			for _, j := range g.Cells[Cell{x, y}] {
				candidates++
				if squaredDistance(p, g.Points[j]) <= g.EPS*g.EPS {
					neighbors = append(neighbors, j)
				}
			}
		}
	}
	return neighbors, candidates
}
func (g *GridIndex) Busiest() (Cell, int) {
	best := Cell{}
	count := -1
	for cell, points := range g.Cells {
		if len(points) > count || len(points) == count && (cell.Y < best.Y || cell.Y == best.Y && cell.X < best.X) {
			best, count = cell, len(points)
		}
	}
	return best, count
}
func bruteForceCounts(points []Point, eps int) []int {
	counts := make([]int, len(points))
	limit := int64(eps) * int64(eps)
	for i, p := range points {
		for _, q := range points {
			if squaredDistance(p, q) <= limit {
				counts[i]++
			}
		}
	}
	return counts
}
