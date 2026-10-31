package main

import "strings"

type Point struct{ X, Y int }

func cellCenter(cell Point) Point { return Point{100 * cell.X, 100 * cell.Y} }

type GridMap struct {
	Width, Height int
	Rows          []string
	Exit          Point
	Spawns        []Point
}

func readMap() *GridMap {
	lines := readLines("map.txt")
	fields := strings.Fields(lines[0])
	grid := &GridMap{Width: integer(fields[0]), Height: integer(fields[1])}
	grid.Rows = lines[1 : grid.Height+1]
	found := map[int]Point{}
	for y, row := range grid.Rows {
		for x := 0; x < len(row); x++ {
			terrain := row[x]
			if terrain >= '1' && terrain <= '9' {
				found[int(terrain-'0')] = Point{x, y}
			} else if terrain == 'E' {
				grid.Exit = Point{x, y}
			}
		}
	}
	for number := 1; number <= len(found); number++ {
		grid.Spawns = append(grid.Spawns, found[number])
	}
	return grid
}
func (g *GridMap) Inside(cell Point) bool {
	return cell.X >= 0 && cell.X < g.Width && cell.Y >= 0 && cell.Y < g.Height
}
func (g *GridMap) Terrain(cell Point) byte   { return g.Rows[cell.Y][cell.X] }
func (g *GridMap) Rock(cell Point) bool      { return g.Terrain(cell) == '#' }
func (g *GridMap) Water(cell Point) bool     { return g.Terrain(cell) == '~' }
func (g *GridMap) Buildable(cell Point) bool { return g.Terrain(cell) == '.' }
