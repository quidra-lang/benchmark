package main

import (
	"os"
	"strconv"
	"strings"
)

type Agent struct{ Start, Goal int }
type Grid struct {
	W, H   int
	Rows   []string
	Agents []Agent
	Dist   [][]int
}

func lines(path string) []string {
	b, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	return strings.Split(strings.TrimSuffix(string(b), "\n"), "\n")
}
func integer(s string) int {
	n, e := strconv.Atoi(s)
	if e != nil {
		panic(e)
	}
	return n
}
func (g *Grid) Free(c int) bool { return c >= 0 && c < g.W*g.H && g.Rows[c/g.W][c%g.W] == '.' }
func (g *Grid) Destinations(c int) []int {
	out := []int{c}
	x, y := c%g.W, c/g.W
	for _, d := range [][2]int{{0, -1}, {1, 0}, {0, 1}, {-1, 0}} {
		nx, ny := x+d[0], y+d[1]
		if nx >= 0 && nx < g.W && ny >= 0 && ny < g.H {
			q := ny*g.W + nx
			if g.Free(q) {
				out = append(out, q)
			}
		}
	}
	return out
}
func (g *Grid) Distances(goal int) []int {
	d := make([]int, g.W*g.H)
	for i := range d {
		d[i] = -1
	}
	d[goal] = 0
	q := []int{goal}
	for h := 0; h < len(q); h++ {
		c := q[h]
		for _, v := range g.Destinations(c)[1:] {
			if d[v] < 0 {
				d[v] = d[c] + 1
				q = append(q, v)
			}
		}
	}
	return d
}
func readGrid() *Grid {
	a := lines("input/map.txt")
	wh := strings.Fields(a[0])
	g := &Grid{W: integer(wh[0]), H: integer(wh[1]), Rows: a[1:]}
	for _, line := range lines("input/agents.csv")[1:] {
		v := strings.Split(line, ",")
		g.Agents = append(g.Agents, Agent{integer(v[2])*g.W + integer(v[1]), integer(v[4])*g.W + integer(v[3])})
	}
	for _, a := range g.Agents {
		g.Dist = append(g.Dist, g.Distances(a.Goal))
	}
	return g
}
