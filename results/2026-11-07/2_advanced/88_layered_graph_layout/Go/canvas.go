package main

import (
	"fmt"
	"strings"
)

type Cell struct{ Row, Column int }
type Canvas struct {
	M, N, Rows, Columns int
	Direction           string
	Lines               [][]byte
	Arrows, Boxes       [][]byte
	Highlighted         [][]bool
}

func newCanvas(m, n int, direction string) *Canvas {
	rows, columns := m, n
	if direction == "LR" || direction == "RL" {
		rows, columns = n, m
	}
	c := &Canvas{M: m, N: n, Rows: rows, Columns: columns, Direction: direction, Lines: make([][]byte, rows), Arrows: make([][]byte, rows), Boxes: make([][]byte, rows), Highlighted: make([][]bool, rows)}
	for r := 0; r < rows; r++ {
		c.Lines[r] = make([]byte, columns)
		c.Arrows[r] = make([]byte, columns)
		c.Boxes[r] = make([]byte, columns)
		c.Highlighted[r] = make([]bool, columns)
	}
	return c
}
func (c *Canvas) Map(main, secondary int) Cell {
	if c.Direction == "BT" || c.Direction == "RL" {
		main = c.M - 1 - main
	}
	if c.Direction == "TB" || c.Direction == "BT" {
		return Cell{main, secondary}
	}
	return Cell{secondary, main}
}
func (c *Canvas) Line(main, secondary int, kind byte) {
	p := c.Map(main, secondary)
	c.Lines[p.Row][p.Column] |= kind
}
func (c *Canvas) MainLine(main, secondary int) {
	kind := byte(1)
	if c.Direction == "LR" || c.Direction == "RL" {
		kind = 2
	}
	c.Line(main, secondary, kind)
}
func (c *Canvas) SecondaryLine(main, secondary int) {
	kind := byte(2)
	if c.Direction == "LR" || c.Direction == "RL" {
		kind = 1
	}
	c.Line(main, secondary, kind)
}
func (c *Canvas) Segment(g0, gap, upper, lower, offset int) {
	if upper == lower {
		for j := 0; j < gap; j++ {
			c.MainLine(g0+j, upper)
		}
		return
	}
	for j := 0; j < offset; j++ {
		c.MainLine(g0+j, upper)
	}
	c.Line(g0+offset, upper, 4)
	c.Line(g0+offset, lower, 4)
	for x := min(upper, lower) + 1; x < max(upper, lower); x++ {
		c.SecondaryLine(g0+offset, x)
	}
	for j := offset + 1; j < gap; j++ {
		c.MainLine(g0+j, lower)
	}
}
func (c *Canvas) Highlight(a, b Cell) {
	dr, dc := 0, 0
	if a.Row < b.Row {
		dr = 1
	} else if a.Row > b.Row {
		dr = -1
	}
	if a.Column < b.Column {
		dc = 1
	} else if a.Column > b.Column {
		dc = -1
	}
	for {
		c.Highlighted[a.Row][a.Column] = true
		if a == b {
			break
		}
		a.Row += dr
		a.Column += dc
	}
}
func (c *Canvas) CrossingCells() int {
	sum := 0
	for _, row := range c.Lines {
		for _, mask := range row {
			if mask&3 == 3 {
				sum++
			}
		}
	}
	return sum
}
func (c *Canvas) Character(r, column int) byte {
	if c.Boxes[r][column] != 0 {
		return c.Boxes[r][column]
	}
	if c.Arrows[r][column] != 0 {
		return c.Arrows[r][column]
	}
	if c.Highlighted[r][column] {
		return '#'
	}
	switch c.Lines[r][column] {
	case 0:
		return ' '
	case 1:
		return '|'
	case 2:
		return '-'
	default:
		return '+'
	}
}
func (c *Canvas) Drawing(name string) []string {
	ruler := "    "
	for column := 0; column < c.Columns; column++ {
		ruler += fmt.Sprintf("%d", column%10)
	}
	out := []string{fmt.Sprintf("graph %s %dx%d", name, c.Columns, c.Rows), ruler}
	for r := 0; r < c.Rows; r++ {
		row := make([]byte, c.Columns)
		for column := range row {
			row[column] = c.Character(r, column)
		}
		out = append(out, strings.TrimRight(fmt.Sprintf("%3d %s", r, row), " "))
	}
	return out
}
