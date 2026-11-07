package main

import "strings"

type Canvas struct {
	Width, Height int
	Rows          [][]byte
}

func newCanvas(width, height int) *Canvas {
	c := &Canvas{width, height, make([][]byte, height)}
	for r := range c.Rows {
		c.Rows[r] = []byte(strings.Repeat(" ", width))
	}
	return c
}
func (c *Canvas) position(x, y, d int64) (int, int) {
	return int((2*x*int64(c.Width-1) + 1000*d) / (2000 * d)), c.Height - 1 - int((2*y*int64(c.Height-1)+1000*d)/(2000*d))
}
func (c *Canvas) mark(x, y, d int64, ch byte) {
	column, row := c.position(x, y, d)
	c.Rows[row][column] = ch
}
func (c *Canvas) line(a, b Point, ch byte) {
	x, y := c.position(a.X, a.Y, 1)
	endX, endY := c.position(b.X, b.Y, 1)
	dx, dy := int(abs64(int64(endX-x))), -int(abs64(int64(endY-y)))
	sx, sy := -1, -1
	if x < endX {
		sx = 1
	}
	if y < endY {
		sy = 1
	}
	error := dx + dy
	for {
		c.Rows[y][x] = ch
		if x == endX && y == endY {
			return
		}
		twice := 2 * error
		if twice >= dy {
			error += dy
			x += sx
		}
		if twice <= dx {
			error += dx
			y += sy
		}
	}
}
func (c *Canvas) drawVoronoi(points []Point) {
	horizontal, vertical := int64(c.Width-1), int64(c.Height-1)
	owners := make([][]int, c.Height)
	for r := 0; r < c.Height; r++ {
		owners[r] = make([]int, c.Width)
		for column := 0; column < c.Width; column++ {
			best := int64(-1)
			for site, p := range points[1:] {
				dx := (int64(column)*1000 - p.X*horizontal) * vertical
				dy := ((vertical-int64(r))*1000 - p.Y*vertical) * horizontal
				distance := dx*dx + dy*dy
				if best < 0 || distance < best {
					best = distance
					owners[r][column] = site + 1
				}
			}
		}
	}
	for r := 0; r < c.Height; r++ {
		for column := 0; column < c.Width; column++ {
			owner := owners[r][column]
			if column < c.Width-1 && owner != owners[r][column+1] || r < c.Height-1 && owner != owners[r+1][column] {
				c.Rows[r][column] = '#'
			}
		}
	}
	for _, p := range points[1:] {
		c.mark(p.X, p.Y, 1, 'o')
	}
}
func (c *Canvas) framed() []string {
	border := "+" + strings.Repeat("-", c.Width) + "+"
	out := []string{border}
	for _, row := range c.Rows {
		out = append(out, "|"+string(row)+"|")
	}
	return append(out, border)
}
