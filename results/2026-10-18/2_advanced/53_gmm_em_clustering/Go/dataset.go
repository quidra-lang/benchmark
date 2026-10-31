package main

import (
	"os"
	"strconv"
	"strings"
)

type Point struct{ X, Y float64 }
type DataPoint struct {
	ID    string
	Point Point
}
type Covariance struct{ A, B, C float64 }
type Component struct {
	Weight float64
	Mean   Point
	Cov    Covariance
}
type Model []Component
type Params struct {
	K                      []int
	Iterations             int
	Types                  []string
	Epsilon, Tolerance     float64
	KMeansMax, Folds       int
	Uncertain, LowDensity  float64
	GOFEdges               []float64
	XMin, XMax, YMin, YMax float64
	Width, Height          int
}

func readLines(path string) []string {
	data, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
}
func parseReal(s string) float64 {
	v, e := strconv.ParseFloat(s, 64)
	if e != nil {
		panic(e)
	}
	return v
}
func parseInt(s string) int {
	v, e := strconv.Atoi(s)
	if e != nil {
		panic(e)
	}
	return v
}
func readDataset() ([]DataPoint, map[int]Model, Params) {
	points := []DataPoint{}
	for _, line := range readLines("input/points.csv")[1:] {
		f := strings.Split(line, ",")
		points = append(points, DataPoint{f[0], Point{parseReal(f[1]), parseReal(f[2])}})
	}
	values := map[string][]string{}
	for _, line := range readLines("input/params.txt") {
		f := strings.Split(line, " ")
		values[f[0]] = f[1:]
	}
	p := Params{Iterations: parseInt(values["ITERATIONS"][0]), Types: values["TYPES"], Epsilon: parseReal(values["REGULARIZATION"][0]),
		Tolerance: parseReal(values["SETTLE_TOLERANCE"][0]), KMeansMax: parseInt(values["KMEANS_MAX_ITERATIONS"][0]),
		Folds: parseInt(values["CV_FOLDS"][0]), Uncertain: parseReal(values["UNCERTAIN_THRESHOLD"][0]),
		LowDensity: parseReal(values["LOW_DENSITY_THRESHOLD"][0]), XMin: parseReal(values["MAP_X"][0]),
		XMax: parseReal(values["MAP_X"][1]), YMin: parseReal(values["MAP_Y"][0]), YMax: parseReal(values["MAP_Y"][1]),
		Width: parseInt(values["MAP_SIZE"][0]), Height: parseInt(values["MAP_SIZE"][1])}
	for _, s := range values["K"] {
		p.K = append(p.K, parseInt(s))
	}
	for _, s := range values["GOF_EDGES"] {
		p.GOFEdges = append(p.GOFEdges, parseReal(s))
	}
	initial := map[int]Model{}
	lines := readLines("input/init.txt")
	for cursor := 0; cursor < len(lines); {
		if lines[cursor] == "" {
			cursor++
			continue
		}
		k := parseInt(strings.Split(lines[cursor], " ")[1])
		weights := strings.Split(lines[cursor+1], " ")[1:]
		model := make(Model, k)
		for j := 0; j < k; j++ {
			f := strings.Split(lines[cursor+2+j], " ")
			model[j] = Component{parseReal(weights[j]), Point{parseReal(f[2]), parseReal(f[3])}, Covariance{parseReal(f[4]), parseReal(f[5]), parseReal(f[6])}}
		}
		initial[k] = model
		cursor += k + 2
	}
	return points, initial, p
}
