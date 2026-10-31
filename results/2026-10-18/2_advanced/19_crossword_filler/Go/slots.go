package main

import (
	"fmt"
	"sort"
)

func startsRun(grid *Grid, row, column, dr, dc int) bool {
	return grid.IsOpen(row, column) && !grid.IsOpen(row-dr, column-dc)
}
func runLength(grid *Grid, row, column, dr, dc int) int {
	length := 0
	for grid.IsOpen(row+length*dr, column+length*dc) {
		length++
	}
	return length
}

func shortRunError(grid *Grid) string {
	for row := range grid.Height {
		for column := range grid.Width {
			for _, across := range []bool{true, false} {
				dr, dc, direction := 1, 0, "down"
				if across {
					dr, dc, direction = 0, 1, "across"
				}
				if startsRun(grid, row, column, dr, dc) && runLength(grid, row, column, dr, dc) == 2 {
					return fmt.Sprintf("short slot at %s %s", grid.Location(grid.Cell(row, column)), direction)
				}
			}
		}
	}
	return ""
}

type Slot struct {
	Index, Number int
	Across        bool
	Cells         []int
	Label         string
	Crossings     []int
}

func (slot Slot) Length() int { return len(slot.Cells) }

type Layout struct {
	Grid                          *Grid
	Numbers, AcrossSlot, DownSlot []int
	Slots                         []Slot
}

func newLayout(grid *Grid) *Layout {
	layout := &Layout{Grid: grid, Numbers: make([]int, len(grid.Cells)), AcrossSlot: make([]int, len(grid.Cells)), DownSlot: make([]int, len(grid.Cells))}
	for cell := range grid.Cells {
		layout.AcrossSlot[cell] = -1
		layout.DownSlot[cell] = -1
	}
	nextNumber := 0
	for row := range grid.Height {
		for column := range grid.Width {
			for _, across := range []bool{true, false} {
				dr, dc := 1, 0
				if across {
					dr, dc = 0, 1
				}
				if !startsRun(grid, row, column, dr, dc) {
					continue
				}
				length := runLength(grid, row, column, dr, dc)
				if length < 3 {
					continue
				}
				start := grid.Cell(row, column)
				if layout.Numbers[start] == 0 {
					nextNumber++
					layout.Numbers[start] = nextNumber
				}
				number, index := layout.Numbers[start], len(layout.Slots)
				cells := make([]int, length)
				owners := layout.DownSlot
				direction := "D"
				if across {
					owners = layout.AcrossSlot
					direction = "A"
				}
				for position := range length {
					cells[position] = grid.Cell(row+position*dr, column+position*dc)
					owners[cells[position]] = index
				}
				layout.Slots = append(layout.Slots, Slot{Index: index, Number: number, Across: across, Cells: cells, Label: fmt.Sprintf("%d%s", number, direction)})
			}
		}
	}
	for index := range layout.Slots {
		slot := &layout.Slots[index]
		owners := layout.AcrossSlot
		if slot.Across {
			owners = layout.DownSlot
		}
		for _, cell := range slot.Cells {
			if owners[cell] >= 0 {
				slot.Crossings = append(slot.Crossings, owners[cell])
			}
		}
		sort.Ints(slot.Crossings)
	}
	return layout
}

func (layout *Layout) OwnerCount(cell int) int {
	count := 0
	if layout.AcrossSlot[cell] >= 0 {
		count++
	}
	if layout.DownSlot[cell] >= 0 {
		count++
	}
	return count
}

func (layout *Layout) OrphanCell() int {
	for _, cell := range layout.Grid.WhiteCells() {
		if layout.OwnerCount(cell) == 0 {
			return cell
		}
	}
	return -1
}
