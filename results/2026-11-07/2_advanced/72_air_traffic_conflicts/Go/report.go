package main

import (
	"fmt"
	"os"
	"strings"
)

func format(x float64, digits int) string {
	s := fmt.Sprintf("%.*f", digits, x)
	if strings.HasPrefix(s, "-") && strings.Trim(s[1:], "0.") == "" {
		return s[1:]
	}
	return s
}
func f(x float64) string { return format(x, 3) }
func signed(x int) string {
	if x > 0 {
		return fmt.Sprintf("+%d", x)
	}
	return fmt.Sprint(x)
}
func line(s *strings.Builder, template string, a ...any) { fmt.Fprintf(s, template+"\n", a...) }
func chart(s *strings.Builder, grid [][]byte) {
	border := "+" + strings.Repeat("-", len(grid[0])) + "+"
	line(s,
		"%s", border)
	for _, row := range grid {
		line(s, "|%s|", string(row))
	}
	line(s, "%s", border)
}
func write(path string, s *strings.Builder) { must(os.WriteFile(path, []byte(s.String()), 0644)) }
