package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type OutputFile struct {
	name  string
	lines []string
}

func fixedWidthLine(label string, cells []string, labelWidth, cellWidth int) string {
	var line strings.Builder
	fmt.Fprintf(&line, "%-*s", labelWidth, label)
	for _, cell := range cells {
		fmt.Fprintf(&line, "%*s", cellWidth, cell)
	}
	return line.String()
}
func roundedPercent(part, whole int) int { return (200*part + whole) / (2 * whole) }
func writeFiles(directory string, files []OutputFile) {
	if err := os.MkdirAll(directory, 0755); err != nil {
		panic(err)
	}
	for _, file := range files {
		if err := os.WriteFile(filepath.Join(directory, file.name), []byte(strings.Join(file.lines, "\n")+"\n"), 0644); err != nil {
			panic(err)
		}
	}
}
