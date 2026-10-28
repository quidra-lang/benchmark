package main

import (
	"os"
	"strconv"
	"strings"
)

type Mesh struct {
	W, H          int
	DX, Thickness float64
	Codes         []byte
	Neighbors     [][4]int
}

func readLines(path string) []string {
	b, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	return strings.Split(strings.TrimSuffix(string(b), "\n"), "\n")
}
func integer(s string) int {
	v, e := strconv.Atoi(s)
	if e != nil {
		panic(e)
	}
	return v
}
func number(s string) float64 {
	v, e := strconv.ParseFloat(s, 64)
	if e != nil {
		panic(e)
	}
	return v
}
func readMesh() Mesh {
	lines := readLines("input/plate.txt")
	a := strings.Fields(lines[0])
	m := Mesh{W: integer(a[0]), H: integer(a[1]), DX: number(a[2]), Thickness: number(a[3])}
	for _, line := range lines[1:] {
		m.Codes = append(m.Codes, []byte(line)...)
	}
	m.Neighbors = make([][4]int, m.W*m.H)
	for p := range m.Codes {
		r, c := p/m.W, p%m.W
		m.Neighbors[p] = [4]int{-1, -1, -1, -1}
		if c > 0 {
			m.Neighbors[p][0] = p - 1
		}
		if c+1 < m.W {
			m.Neighbors[p][1] = p + 1
		}
		if r > 0 {
			m.Neighbors[p][2] = p - m.W
		}
		if r+1 < m.H {
			m.Neighbors[p][3] = p + m.W
		}
	}
	return m
}
func (m Mesh) segmentCells(edge string, start, end int) ([]int, int) {
	cells := []int{}
	face := 0
	for i := start; i <= end; i++ {
		switch edge {
		case "left":
			face = 0
			cells = append(cells, i*m.W)
		case "right":
			face = 1
			cells = append(cells, i*m.W+m.W-1)
		case "top":
			face = 2
			cells = append(cells, i)
		case "bottom":
			face = 3
			cells = append(cells, (m.H-1)*m.W+i)
		}
	}
	return cells, face
}
func (m Mesh) sourceCells(r1, c1, r2, c2 int) []int {
	out := []int{}
	for r := r1; r <= r2; r++ {
		for c := c1; c <= c2; c++ {
			out = append(out, r*m.W+c)
		}
	}
	return out
}
