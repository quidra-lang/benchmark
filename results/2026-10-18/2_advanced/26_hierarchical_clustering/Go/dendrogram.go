package main

import (
	"fmt"
	"math"
	"strings"
)

func orderedChildren(merges []Merge, count int) [][2]int {
	minimum := make([]int, count)
	for i := range minimum {
		minimum[i] = i
	}
	children := [][2]int{}
	for _, merge := range merges {
		upper, lower := merge.A, merge.B
		if minimum[upper] > minimum[lower] {
			upper, lower = lower, upper
		}
		children = append(children, [2]int{upper, lower})
		minimum = append(minimum, min(minimum[merge.A], minimum[merge.B]))
	}
	return children
}
func leafOrder(children [][2]int, count int) []int {
	order := []int{}
	pending := []int{count + len(children) - 1}
	for len(pending) > 0 {
		last := len(pending) - 1
		node := pending[last]
		pending = pending[:last]
		if node < count {
			order = append(order, node)
		} else {
			pair := children[node-count]
			pending = append(pending, pair[1], pair[0])
		}
	}
	return order
}
func column(height, maximum float64, width int) int {
	position := math.Floor(height / maximum * float64(width))
	if position > float64(width) {
		return width + 1
	}
	return int(position)
}
func dendrogramRows(merges []Merge, children [][2]int, order []int, idents, labels []string, maximum float64, cutColumns []int, width int) []string {
	count := len(order)
	grid := make([][]int, count)
	for i := range grid {
		grid[i] = make([]int, width+1)
	}
	mark := func(row, x, level int) { grid[row][x] = max(grid[row][x], level) }
	anchor := make([]int, 2*count-1)
	for row, leaf := range order {
		anchor[leaf] = row
	}
	for _, x := range cutColumns {
		if x <= width {
			for row := 0; row < count; row++ {
				mark(row, x, 1)
			}
		}
	}
	columns := []int{}
	for _, merge := range merges {
		columns = append(columns, column(merge.Height, maximum, width))
	}
	for step, pair := range children {
		upper, lower := pair[0], pair[1]
		x := columns[step]
		mark(anchor[upper], x, 4)
		mark(anchor[lower], x, 4)
		for row := anchor[upper] + 1; row < anchor[lower]; row++ {
			mark(row, x, 3)
		}
		for _, child := range pair {
			start := 0
			if child >= count {
				start = columns[child-count] + 1
			}
			for position := start; position < x; position++ {
				mark(anchor[child], position, 2)
			}
		}
		anchor[count+step] = (anchor[upper] + anchor[lower]) / 2
	}
	idWidth, labelWidth := 0, 0
	for i, ident := range idents {
		idWidth = max(idWidth, len(ident))
		labelWidth = max(labelWidth, len(labels[i]))
	}
	rows := []string{}
	for row, leaf := range order {
		cells := make([]byte, width+1)
		for x, level := range grid[row] {
			cells[x] = " :-|+"[level]
		}
		rows = append(rows, strings.TrimRight(fmt.Sprintf("%-*s %-*s %s", idWidth, idents[leaf], labelWidth, labels[leaf], string(cells)), " "))
	}
	scale := make([]byte, width+1)
	for x := range scale {
		scale[x] = '-'
		if x%10 == 0 {
			scale[x] = '+'
		}
	}
	return append(rows, strings.Repeat(" ", idWidth+labelWidth+2)+string(scale))
}
