package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

func name(i int) string          { return string(rune('A' + i)) }
func cell(g *Grid, c int) string { return fmt.Sprintf("%d,%d", c%g.W, c/g.W) }
func conflictText(g *Grid, c Conflict) string {
	if c.Edge {
		return fmt.Sprintf("edge t %d %s %s from %s to %s", c.Time, name(c.A), name(c.B), cell(g, c.U), cell(g, c.V))
	}
	return fmt.Sprintf("vertex t %d %s %s at %s", c.Time, name(c.A), name(c.B), cell(g, c.V))
}
func action(g *Grid, u, v int) byte {
	if u == v {
		return '.'
	}
	if v == u-g.W {
		return 'N'
	}
	if v == u+1 {
		return 'E'
	}
	if v == u+g.W {
		return 'S'
	}
	return 'W'
}
func actions(g *Grid, path []int) string {
	out := make([]byte, len(path)-1)
	for t := 1; t < len(path); t++ {
		out[t-1] = action(g, path[t-1], path[t])
	}
	return string(out)
}
func gcd(a, b int) int {
	for b != 0 {
		a, b = b, a%b
	}
	return a
}
func fraction(a, b int) string {
	d := gcd(a, b)
	return fmt.Sprintf("%d/%d", a/d, b/d)
}
func intTexts(a []int) []string {
	out := make([]string, len(a))
	for i, v := range a {
		out[i] = strconv.Itoa(v)
	}
	return out
}
func writeLines(path string, lines []string) {
	s := ""
	if len(lines) > 0 {
		s = strings.Join(lines, "\n") + "\n"
	}
	if e := os.WriteFile("output/"+path, []byte(s), 0644); e != nil {
		panic(e)
	}
}
