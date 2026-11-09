package main

import (
	"os"
	"sort"
	"strconv"
	"strings"
)

type Point struct {
	ID   int
	X, Y int64
}
type Params struct {
	EPS, Extract                                                                                 []int
	MinPts, MaxEPS, XiU, XiV, XiMinSize, MapWidth, MapHeight, KdistWidth, KdistHeight, PlotWidth int
	XiText                                                                                       string
}

func integer(s string) int {
	n, e := strconv.Atoi(s)
	if e != nil {
		panic(e)
	}
	return n
}
func readLines(path string) []string {
	b, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	return strings.Split(strings.TrimSuffix(string(b), "\n"), "\n")
}
func readPoints() []Point {
	points := []Point{}
	for _, line := range readLines("input/points.csv")[1:] {
		f := strings.Split(line, ",")
		points = append(points, Point{integer(f[0]), int64(integer(f[1])), int64(integer(f[2]))})
	}
	sort.Slice(points, func(i, j int) bool { return points[i].ID < points[j].ID })
	return points
}
func readParams() Params {
	f := map[string][]string{}
	for _, line := range readLines("input/params.txt") {
		p := strings.Fields(line)
		f[p[0]] = p[1:]
	}
	ints := func(key string) []int {
		values := []int{}
		for _, v := range f[key] {
			values = append(values, integer(v))
		}
		return values
	}
	xi := strings.Split(f["XI"][0], "/")
	return Params{EPS: ints("EPS"), Extract: ints("EXTRACT_EPS"), MinPts: integer(f["MIN_PTS"][0]), MaxEPS: integer(f["OPTICS_MAX_EPS"][0]),
		XiText: f["XI"][0], XiU: integer(xi[0]), XiV: integer(xi[1]), XiMinSize: integer(f["XI_MIN_SIZE"][0]),
		MapWidth: integer(f["MAP_SIZE"][0]), MapHeight: integer(f["MAP_SIZE"][1]), KdistWidth: integer(f["KDIST_PLOT"][0]),
		KdistHeight: integer(f["KDIST_PLOT"][1]), PlotWidth: integer(f["PLOT_WIDTH"][0])}
}
