package main

import (
	"os"
	"sort"
	"strconv"
	"strings"
)

type Row struct {
	ID     int
	Values []float64
	Label  string
	Class  int
}
type Subset struct {
	Name     string
	Features []int
}
type Params struct {
	Prior                               string
	Epsilon, Gamma, Outlier             float64
	Smoothing, GammaGrid, Edges, Reject []float64
	Curve                               []int
	Folds, Bootstrap                    int
	Seed                                int64
	MapSize, PlotSize                   [2]int
	Subsets                             []Subset
	Pairs                               [][2]int
}
type Dataset struct {
	Features, Classes []string
	Train, Test       []Row
	Costs             [][]float64
	Params            Params
}

func readLines(path string) []string {
	data, err := os.ReadFile(path)
	if err != nil {
		panic(err)
	}
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
}
func integer(s string) int {
	v, e := strconv.Atoi(s)
	if e != nil {
		panic(e)
	}
	return v
}
func decimal(s string) float64 {
	v, e := strconv.ParseFloat(s, 64)
	if e != nil {
		panic(e)
	}
	return v
}
func decimals(s []string) []float64 {
	out := make([]float64, len(s))
	for i, x := range s {
		out[i] = decimal(x)
	}
	return out
}
func integers(s []string) []int {
	out := make([]int, len(s))
	for i, x := range s {
		out[i] = integer(x)
	}
	return out
}
func readTable(path string) ([]string, []Row) {
	lines := readLines(path)
	head := strings.Split(lines[0], ",")
	rows := []Row{}
	for _, line := range lines[1:] {
		fields := strings.Split(line, ",")
		rows = append(rows, Row{ID: integer(fields[0]), Values: decimals(fields[1 : len(fields)-1]), Label: fields[len(fields)-1]})
	}
	return head[1 : len(head)-1], rows
}
func readInputs() Dataset {
	features, train := readTable("input/train.csv")
	_, test := readTable("input/test.csv")
	labels := map[string]bool{}
	for _, r := range train {
		labels[r.Label] = true
	}
	classes := []string{}
	for name := range labels {
		classes = append(classes, name)
	}
	sort.Strings(classes)
	indices := map[string]int{}
	for i, s := range classes {
		indices[s] = i
	}
	for i := range train {
		train[i].Class = indices[train[i].Label]
	}
	for i := range test {
		test[i].Class = indices[test[i].Label]
	}
	names := map[string]int{}
	for i, s := range features {
		names[s] = i
	}
	v := map[string][]string{}
	params := Params{}
	for _, line := range readLines("input/params.txt") {
		f := strings.Split(line, " ")
		switch f[0] {
		case "SUBSET":
			seq := []int{}
			for _, s := range f[2:] {
				seq = append(seq, names[s])
			}
			params.Subsets = append(params.Subsets, Subset{f[1], seq})
		case "PAIR":
			params.Pairs = append(params.Pairs, [2]int{names[f[1]], names[f[2]]})
		default:
			v[f[0]] = f[1:]
		}
	}
	params.Prior = v["PRIOR"][0]
	params.Epsilon = decimal(v["VAR_SMOOTHING"][0])
	params.Gamma = decimal(v["QDA_GAMMA"][0])
	params.Outlier = decimal(v["OUTLIER_THRESHOLD"][0])
	params.Smoothing = decimals(v["SMOOTHING_GRID"])
	params.GammaGrid = decimals(v["GAMMA_GRID"])
	params.Edges = decimals(v["CALIBRATION_EDGES"])
	params.Reject = decimals(v["REJECT_THRESHOLDS"])
	params.Curve = integers(v["CURVE"])
	params.Folds = integer(v["CV_FOLDS"][0])
	params.Bootstrap = integer(v["BOOTSTRAP"][0])
	params.Seed = int64(integer(v["BOOTSTRAP"][1]))
	params.MapSize = [2]int{integer(v["MAP_SIZE"][0]), integer(v["MAP_SIZE"][1])}
	params.PlotSize = [2]int{integer(v["PLOT_SIZE"][0]), integer(v["PLOT_SIZE"][1])}
	lines := readLines("input/costs.csv")
	columns := strings.Split(lines[0], ",")[1:]
	costs := zeros(len(classes))
	for _, line := range lines[1:] {
		f := strings.Split(line, ",")
		for j, s := range columns {
			costs[indices[f[0]]][indices[s]] = decimal(f[j+1])
		}
	}
	return Dataset{features, classes, train, test, costs, params}
}
