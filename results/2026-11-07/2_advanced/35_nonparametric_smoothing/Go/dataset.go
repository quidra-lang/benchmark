package main

import (
	"os"
	"sort"
	"strconv"
	"strings"
)

type Point struct{ X, Y int }
type Series struct {
	Name   string
	Points []Point
}
type TestPoint struct {
	Name string
	X    int
}
type Settings struct {
	Windows, Kernels, Bandwidths, Degrees, Spans, Lambdas, Isotonic, BandMethods, PlotSeries, PlotMethods []string
	RobustIterations, Folds, GridPoints, Bootstrap, Trim, Width, Height                                   int
	BandZ, Threshold                                                                                      float64
	Seed                                                                                                  int64
}

func readLines(path string) []string {
	data, err := os.ReadFile(path)
	if err != nil {
		panic(err)
	}
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
}
func integer(text string) int {
	v, err := strconv.Atoi(text)
	if err != nil {
		panic(err)
	}
	return v
}
func decimal(text string) float64 {
	v, err := strconv.ParseFloat(text, 64)
	if err != nil {
		panic(err)
	}
	return v
}
func hundredths(text string) int { return integer(strings.ReplaceAll(text, ".", "")) }
func readDataset() ([]*Series, []TestPoint, *Settings) {
	series := []*Series{}
	table := map[string]*Series{}
	for _, line := range readLines("input/series.csv")[1:] {
		f := strings.Split(line, ",")
		s := table[f[0]]
		if s == nil {
			s = &Series{Name: f[0]}
			table[f[0]] = s
			series = append(series, s)
		}
		s.Points = append(s.Points, Point{hundredths(f[1]), hundredths(f[2])})
	}
	for _, s := range series {
		sort.Slice(s.Points, func(i, j int) bool { return s.Points[i].X < s.Points[j].X })
	}
	tests := []TestPoint{}
	for _, line := range readLines("input/test_points.csv")[1:] {
		f := strings.Split(line, ",")
		tests = append(tests, TestPoint{f[0], hundredths(f[1])})
	}
	f := map[string][]string{}
	for _, line := range readLines("input/params.txt") {
		words := strings.Split(line, " ")
		f[words[0]] = words[1:]
	}
	s := &Settings{Windows: f["WINDOWS"], Kernels: f["KERNELS"], Bandwidths: f["BANDWIDTHS"], Degrees: f["LOESS_DEGREES"],
		Spans: f["SPANS"], Lambdas: f["LAMBDAS"], Isotonic: f["ISOTONIC"], BandMethods: f["BAND_METHODS"],
		PlotSeries: f["PLOT_SERIES"], PlotMethods: f["PLOT_METHODS"], RobustIterations: integer(f["ROBUST_ITERATIONS"][0]),
		Folds: integer(f["CV_FOLDS"][0]), GridPoints: integer(f["GRID_POINTS"][0]), BandZ: decimal(f["BAND_Z"][0]),
		Threshold: float64(hundredths(f["OUTLIER_THRESHOLD"][0])) / 100, Bootstrap: integer(f["BOOTSTRAP"][0]),
		Trim: integer(f["BOOTSTRAP"][1]), Seed: int64(integer(f["BOOTSTRAP"][2])), Width: integer(f["PLOT_SIZE"][0]),
		Height: integer(f["PLOT_SIZE"][1])}
	return series, tests, s
}
func pointData(points []Point) ([]int, []float64) {
	positions := make([]int, len(points))
	values := make([]float64, len(points))
	for i, p := range points {
		positions[i] = p.X
		values[i] = float64(p.Y) / 100
	}
	return positions, values
}
