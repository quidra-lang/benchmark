package main

import (
	"math"
	"strings"
)

type Cell struct{ Row, Column int }

func newGrid(rows, columns int) [][]byte {
	g := make([][]byte, rows)
	for r := range g {
		g[r] = []byte(strings.Repeat(" ", columns))
	}
	return g
}
func framed(g [][]byte) []string {
	border := "+" + strings.Repeat("-", len(g[0])) + "+"
	out := []string{border}
	for _, row := range g {
		out = append(out, "|"+string(row)+"|")
	}
	return append(out, border)
}
func gridIndex(fraction float64, size int) int {
	return min(int(math.Floor(fraction*float64(size))), size-1)
}
func roundedPosition(fraction, size float64) int { return int(math.Floor(fraction*size + 0.5)) }
func biplotCell(x, y, xLimit, yLimit float64, w, h int) Cell {
	return Cell{gridIndex((yLimit-y)/(2*yLimit), h), gridIndex((x+xLimit)/(2*xLimit), w)}
}
func circleCell(first, second float64, radius int) Cell {
	return Cell{radius/2 + 1 - roundedPosition(second, float64(radius)/2), radius + 1 + roundedPosition(first, float64(radius))}
}
func diagnosticCell(t2, spe, t2Max, speMax float64, w, h int) Cell {
	return Cell{h - 1 - gridIndex(spe/speMax, h), gridIndex(t2/t2Max, w)}
}
func sign(v int) int {
	if v < 0 {
		return -1
	}
	if v > 0 {
		return 1
	}
	return 0
}
func abs(v int) int {
	if v < 0 {
		return -v
	}
	return v
}
func shaftCells(origin, tip Cell) []Cell {
	dr, dc := tip.Row-origin.Row, tip.Column-origin.Column
	steps := max(abs(dr), abs(dc))
	out := []Cell{}
	for s := 1; s < steps; s++ {
		out = append(out, Cell{origin.Row + sign(dr)*((2*s*abs(dr)+steps)/(2*steps)), origin.Column + sign(dc)*((2*s*abs(dc)+steps)/(2*steps))})
	}
	return out
}
func shaftCharacter(origin, tip Cell) byte {
	dr, dc := tip.Row-origin.Row, tip.Column-origin.Column
	if 2*abs(dr) <= abs(dc) {
		return '-'
	}
	if 2*abs(dc) <= abs(dr) {
		return '|'
	}
	if dc*dr < 0 {
		return '/'
	}
	return '\\'
}
func screeLine(length, kaiser, broken, width int) string {
	out := make([]byte, width)
	for p := 1; p <= width; p++ {
		v := byte(' ')
		if p == broken {
			v = 'o'
		} else if p == kaiser {
			v = ':'
		} else if p <= length {
			v = '#'
		}
		out[p-1] = v
	}
	return "|" + string(out) + "|"
}
