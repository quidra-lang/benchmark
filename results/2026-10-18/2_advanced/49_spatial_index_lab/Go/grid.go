package main

import "sort"

type Cell struct {
	Column, Row int
	Box         Box
	Points      []Object
}
type Grid struct {
	World, CellSize, Side int
	Cells                 []*Cell
}

func newGrid(world, size int, points []Object) *Grid {
	g := &Grid{World: world, CellSize: size, Side: world / size}
	for row := 0; row < g.Side; row++ {
		for column := 0; column < g.Side; column++ {
			x, y := column*size, row*size
			g.Cells = append(g.Cells, &Cell{Column: column, Row: row, Box: Box{x, y, x + size - 1, y + size - 1}})
		}
	}
	for _, p := range points {
		g.insert(p)
	}
	return g
}
func (g *Grid) position(p Object) (int, int) { return p.Box[0] / g.CellSize, p.Box[1] / g.CellSize }
func (g *Grid) cell(p Object) *Cell          { column, row := g.position(p); return g.Cells[row*g.Side+column] }
func (g *Grid) insert(p Object) {
	cell := g.cell(p)
	cell.Points = append(cell.Points, p)
	sort.Slice(cell.Points, func(i, j int) bool { return cell.Points[i].ID < cell.Points[j].ID })
}
func (g *Grid) delete(p Object) {
	cell := g.cell(p)
	for i, point := range cell.Points {
		if point.ID == p.ID {
			cell.Points = append(cell.Points[:i], cell.Points[i+1:]...)
			return
		}
	}
}
