package main

import (
	"fmt"
	"sort"
	"strings"
)

type Interval struct {
	Start, End int
	Mark       string
}

func chartScale(makespan, width int) (int, int) {
	for magnitude := 1; ; magnitude *= 10 {
		for _, step := range []int{1, 2, 5} {
			scale := step * magnitude
			columns := (makespan + scale - 1) / scale
			if columns <= width {
				return scale, columns
			}
		}
	}
}
func timeRow(scale, columns int) string {
	row := "time"
	for c := 0; c < columns; c += 10 {
		row += strings.Repeat(" ", max(0, 6+c-len(row))) + fmt.Sprint(c*scale)
	}
	return row
}
func ruleRow(columns int) string {
	row := strings.Repeat(" ", 6)
	for c := 0; c < columns; c++ {
		if c%10 == 0 {
			row += "+"
		} else {
			row += "-"
		}
	}
	return row
}
func framed(label, marks string) string { return fmt.Sprintf("%-4s |%s|", label, marks) }
func chartRow(label string, intervals []Interval, scale, columns int) string {
	ordered := append([]Interval(nil), intervals...)
	sort.SliceStable(ordered, func(i, j int) bool { return ordered[i].Start < ordered[j].Start })
	marks := ""
	for c := 0; c < columns; c++ {
		best := 0
		mark := "."
		for _, v := range ordered {
			overlap := min(v.End, (c+1)*scale) - max(v.Start, c*scale)
			if overlap > best {
				best = overlap
				mark = v.Mark
			}
		}
		marks += mark
	}
	return framed(label, marks)
}
func busyRow(intervals [][]Interval, scale, columns int) string {
	marks := ""
	for c := 0; c < columns; c++ {
		count := 0
		for _, row := range intervals {
			for _, v := range row {
				if v.Start <= c*scale && c*scale < v.End {
					count++
					break
				}
			}
		}
		if count == 10 {
			marks += "X"
		} else {
			marks += fmt.Sprint(count)
		}
	}
	return framed("busy", marks)
}
