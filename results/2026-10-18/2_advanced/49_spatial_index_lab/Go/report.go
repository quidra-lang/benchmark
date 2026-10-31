package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

func fraction(a, b int) string {
	x, y := a, b
	for y != 0 {
		x, y = y, x%y
	}
	return fmt.Sprintf("%d/%d", a/x, b/x)
}
func ids(values []int) string {
	if len(values) == 0 {
		return "-"
	}
	fields := make([]string, len(values))
	for i, v := range values {
		fields[i] = strconv.Itoa(v)
	}
	return strings.Join(fields, " ")
}
func boxWords(b Box) string { return fmt.Sprintf("%d %d %d %d", b[0], b[1], b[2], b[3]) }
func distances(values [][2]int) string {
	if len(values) == 0 {
		return "-"
	}
	fields := make([]string, len(values))
	for i, v := range values {
		fields[i] = fmt.Sprintf("%d:%d", v[0], v[1])
	}
	return strings.Join(fields, " ")
}
func writeLines(name string, lines []string) {
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	text := ""
	if len(lines) > 0 {
		text = strings.Join(lines, "\n") + "\n"
	}
	if e := os.WriteFile("output/"+name, []byte(text), 0644); e != nil {
		panic(e)
	}
}
