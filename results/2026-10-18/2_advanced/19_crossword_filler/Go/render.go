package main

import (
	"fmt"
	"strings"
)

func decimal(numerator, denominator, places int) string {
	scale := 1
	for range places {
		scale *= 10
	}
	rounded := (2*numerator*scale + denominator) / (2 * denominator)
	return fmt.Sprintf("%d.%0*d", rounded/scale, places, rounded%scale)
}

func gridLines(grid *Grid, letters []byte) []string {
	lines := make([]string, grid.Height)
	for row := range grid.Height {
		lines[row] = string(letters[row*grid.Width : (row+1)*grid.Width])
	}
	return lines
}

func numberLines(layout *Layout) []string {
	grid := layout.Grid
	var lines []string
	for row := range grid.Height {
		var marks []string
		for column := range grid.Width {
			cell := grid.Cell(row, column)
			mark := " ."
			if grid.Cells[cell] == '#' {
				mark = "##"
			} else if layout.Numbers[cell] > 0 {
				mark = fmt.Sprintf("%2d", layout.Numbers[cell])
			}
			marks = append(marks, mark)
		}
		lines = append(lines, strings.Join(marks, " "))
	}
	return lines
}

func listLine(slot Slot, clue, entry, score string, theme bool) string {
	line := fmt.Sprintf("%d. %s (%d) %s %s", slot.Number, clue, slot.Length(), entry, score)
	if theme {
		line += " theme"
	}
	return line
}
