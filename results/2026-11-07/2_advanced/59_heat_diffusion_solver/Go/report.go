package main

import (
	"fmt"
	"os"
	"strings"
)

func fixed(v float64, digits int) string {
	s := fmt.Sprintf("%.*f", digits, v)
	if strings.HasPrefix(s, "-") {
		zero := true
		for _, c := range s[1:] {
			if c != '0' && c != '.' {
				zero = false
			}
		}
		if zero {
			s = s[1:]
		}
	}
	return s
}
func timeText(t int) string        { return fmt.Sprintf("%d.%03d", t/1000, t%1000) }
func cell(mesh Mesh, p int) string { return fmt.Sprint(p/mesh.W, " ", p%mesh.W) }
func fieldLines(mesh Mesh, x []float64) []string {
	out := []string{}
	for r := 0; r < mesh.H; r++ {
		row := []string{}
		for c := 0; c < mesh.W; c++ {
			row = append(row, fixed(x[r*mesh.W+c], 2))
		}
		out = append(out, strings.Join(row, " "))
	}
	return out
}
func isotherm(mesh Mesh, x, bands []float64) ([]string, []int) {
	hot := hottest(x)
	counts := make([]int, len(bands)+1)
	out := []string{}
	for r := 0; r < mesh.H; r++ {
		row := make([]byte, mesh.W)
		for c := 0; c < mesh.W; c++ {
			p := r*mesh.W + c
			level := 0
			for _, v := range bands {
				if v <= x[p] {
					level++
				}
			}
			counts[level]++
			row[c] = byte('0' + level)
			if p == hot {
				row[c] = '*'
			}
		}
		out = append(out, string(row))
	}
	return out, counts
}
func writeLines(name string, lines []string) {
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	if e := os.WriteFile("output/"+name, []byte(strings.Join(lines, "\n")+"\n"), 0644); e != nil {
		panic(e)
	}
}
