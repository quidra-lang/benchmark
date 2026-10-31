package main

import (
	"fmt"
	"strings"
)

func drawCanvas(roots []Placement, width, height int) []string {
	grid := make([][]byte, height)
	for y := range grid {
		grid[y] = []byte(strings.Repeat(" ", width))
	}
	var draw func(*Box, int, int)
	draw = func(box *Box, x, y int) {
		for _, d := range box.Drawn {
			for i := 0; i < len(d.Text); i++ {
				if d.Text[i] != ' ' {
					grid[y+d.Y][x+d.X+i] = d.Text[i]
				}
			}
		}
		for _, child := range box.Children {
			draw(child.Box, x+child.X, y+child.Y)
		}
	}
	for _, root := range roots {
		draw(root.Box, root.X, root.Y)
	}
	out := make([]string, height)
	for y := range grid {
		out[y] = strings.TrimRight(string(grid[y]), " ")
	}
	return out
}
func describeBoxes(roots []Placement) ([]string, int, map[string]int) {
	out := []string{}
	depth := 0
	kinds := map[string]int{}
	var walk func(Placement, int, int, int)
	walk = func(p Placement, x, y, level int) {
		x += p.X
		y += p.Y
		b := p.Box
		out = append(out, fmt.Sprintf("%s%s%s x=%d y=%d w=%d h=%d b=%d", strings.Repeat(" ", 2*level), p.Role, b.Description, x, y, b.W, b.H, b.B))
		depth = max(depth, level+1)
		kind := strings.SplitN(b.Description, " ", 2)[0]
		kinds[kind]++
		for _, child := range b.Children {
			walk(child, x, y, level+1)
		}
	}
	for _, root := range roots {
		walk(root, 0, 0, 0)
	}
	return out, depth, kinds
}
