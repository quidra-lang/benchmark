package main

import (
	"fmt"
	"math"
	"strings"
)

func curveLines(collections [][]Subject, estimates [][]KMRow, width, height, limit int) []string {
	cells := make([][]uint8, height)
	for q := range cells {
		cells[q] = make([]uint8, width)
	}
	step := limit / width
	for g, rows := range collections {
		maximum := 0
		for _, s := range rows {
			maximum = max(maximum, s.Time)
		}
		previous := -1
		mask := uint8(1 << g)
		for column := 0; column < width; column++ {
			t := column * step
			if t > maximum {
				break
			}
			q := min(height-1, int(math.Floor(rowAt(estimates[g], t).Survival*float64(height))))
			cells[q][column] |= mask
			if previous >= 0 && previous-1 > q {
				for v := q + 1; v < previous; v++ {
					cells[v][column] |= mask
				}
			}
			previous = q
		}
	}
	border := "   +" + strings.Repeat("-", width) + "+"
	lines := []string{border}
	for q := height - 1; q >= 0; q-- {
		text := make([]byte, width)
		for c, mask := range cells[q] {
			text[c] = ' '
			if mask != 0 {
				if mask&(mask-1) != 0 {
					text[c] = '*'
				} else {
					for g := 0; g < len(collections); g++ {
						if mask == uint8(1<<g) {
							text[c] = byte('A' + g)
							break
						}
					}
				}
			}
		}
		lines = append(lines, fmt.Sprintf("%3d|%s|", 100*q/height, string(text)))
	}
	return append(lines, border)
}
