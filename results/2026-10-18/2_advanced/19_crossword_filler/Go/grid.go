package main

import "fmt"

type Grid struct {
	Width, Height int
	Cells         []byte
}

func newGrid(rows []string) *Grid {
	grid := &Grid{Width: len(rows[0]), Height: len(rows)}
	for _, row := range rows {
		grid.Cells = append(grid.Cells, []byte(row)...)
	}
	return grid
}

func (g *Grid) Cell(row, column int) int { return row*g.Width + column }
func (g *Grid) Location(cell int) string { return fmt.Sprintf("%d,%d", cell/g.Width+1, cell%g.Width+1) }
func (g *Grid) IsOpen(row, column int) bool {
	return row >= 0 && row < g.Height && column >= 0 && column < g.Width && g.Cells[g.Cell(row, column)] != '#'
}

func (g *Grid) WhiteCells() []int {
	var cells []int
	for cell, letter := range g.Cells {
		if letter != '#' {
			cells = append(cells, cell)
		}
	}
	return cells
}

func (g *Grid) AsymmetricCell(symmetry string) int {
	for row := range g.Height {
		for column := range g.Width {
			otherRow := row
			if symmetry == "rot180" {
				otherRow = g.Height - 1 - row
			}
			if g.IsOpen(row, column) != g.IsOpen(otherRow, g.Width-1-column) {
				return g.Cell(row, column)
			}
		}
	}
	return -1
}

func (g *Grid) ComponentCount() int {
	seen := make([]bool, len(g.Cells))
	count := 0
	for _, start := range g.WhiteCells() {
		if seen[start] {
			continue
		}
		count++
		seen[start] = true
		stack := []int{start}
		for len(stack) > 0 {
			cell := stack[len(stack)-1]
			stack = stack[:len(stack)-1]
			row, column := cell/g.Width, cell%g.Width
			for _, offset := range [][2]int{{-1, 0}, {1, 0}, {0, -1}, {0, 1}} {
				r, c := row+offset[0], column+offset[1]
				if g.IsOpen(r, c) {
					neighbor := g.Cell(r, c)
					if !seen[neighbor] {
						seen[neighbor] = true
						stack = append(stack, neighbor)
					}
				}
			}
		}
	}
	return count
}
