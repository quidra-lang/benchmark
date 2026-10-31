package main

import (
	"fmt"
	"os"
	"strings"
)

func fixedText(value int64) string {
	sign := ""
	if value < 0 {
		sign = "-"
		value = -value
	}
	return fmt.Sprintf("%s%d.%04d", sign, value/10000, value%10000)
}
func averageText(total int64, count int) string {
	return fixedText(floorDiv(10000*total, int64(count)))
}
func cellText(w *World, cell int) string { return fmt.Sprintf("%d,%d", cell/w.Cols, cell%w.Cols) }
func cellsText(w *World, cells []int) string {
	parts := make([]string, len(cells))
	for i, c := range cells {
		parts[i] = cellText(w, c)
	}
	return strings.Join(parts, " ")
}
func gridLines(w *World, fields []string, separator string) []string {
	lines := []string{}
	for r := range w.Rows {
		parts := []string{}
		for c := range w.Cols {
			cell := r*w.Cols + c
			state := w.StateIndex[cell]
			text := string(w.Kinds[cell])
			if state >= 0 {
				text = fields[state]
			}
			parts = append(parts, text)
		}
		lines = append(lines, strings.Join(parts, separator))
	}
	return lines
}
func valueGrid(w *World, values []int64) []string {
	fields := make([]string, len(values))
	for s, v := range values {
		fields[s] = fixedText(v)
	}
	return gridLines(w, fields, " ")
}
func policyGrid(w *World, policy []int) []string {
	fields := make([]string, len(policy))
	for s, a := range policy {
		fields[s] = string("^>v<"[a])
	}
	return gridLines(w, fields, "")
}
func qTableRows(w *World, name string, q [][4]int64, visits [][4]int64) []string {
	lines := []string{}
	for s, cell := range w.States {
		for a := range 4 {
			count := "-"
			if visits != nil {
				count = fmt.Sprint(visits[s][a])
			}
			lines = append(lines, fmt.Sprintf("%s,%d,%d,%c,%s,%s", name, cell/w.Cols, cell%w.Cols, actionLetters[a], fixedText(q[s][a]), count))
		}
	}
	return lines
}
func joinParts(parts [][]string) []string {
	lines := []string{}
	for i, part := range parts {
		if i > 0 {
			lines = append(lines, "")
		}
		lines = append(lines, part...)
	}
	return lines
}
func writeLines(name string, lines []string) {
	if err := os.WriteFile("output/"+name, []byte(strings.Join(lines, "\n")+"\n"), 0644); err != nil {
		panic(err)
	}
}
