package main

import (
	"math"
	"os"
	"strconv"
	"strings"
)

type Table struct {
	Names, IDs []string
	Rows       [][]float64
}
type Settings struct {
	Missing, Scaling, Components                                                                  string
	Target                                                                                        float64
	Parallel                                                                                      int
	Seed                                                                                          int64
	T2Limit, SPELimit                                                                             float64
	Cycles, Top, ScreeWidth, BiplotWidth, BiplotHeight, Radius, DiagnosticWidth, DiagnosticHeight int
}
type Dataset struct {
	Data, Supplementary Table
	Settings            Settings
}

func readLines(path string) []string {
	v, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	return strings.Split(strings.TrimSuffix(string(v), "\n"), "\n")
}
func decimal(s string) float64 {
	v, e := strconv.ParseFloat(s, 64)
	if e != nil {
		panic(e)
	}
	return v
}
func integer(s string) int {
	v, e := strconv.Atoi(s)
	if e != nil {
		panic(e)
	}
	return v
}
func readTable(path string) Table {
	lines := readLines(path)
	t := Table{Names: strings.Split(lines[0], ",")[1:]}
	for _, line := range lines[1:] {
		f := strings.Split(line, ",")
		t.IDs = append(t.IDs, f[0])
		row := make([]float64, len(f)-1)
		for j, v := range f[1:] {
			if v == "NA" {
				row[j] = math.NaN()
			} else {
				row[j] = decimal(v)
			}
		}
		t.Rows = append(t.Rows, row)
	}
	return t
}
func readSettings() Settings {
	v := map[string][]string{}
	for _, line := range readLines("input/params.txt") {
		f := strings.Split(line, " ")
		v[f[0]] = f[1:]
	}
	return Settings{v["MISSING"][0], v["SCALING"][0], v["COMPONENTS"][0], decimal(v["CUMULATIVE_TARGET"][0]),
		integer(v["PARALLEL"][0]), int64(integer(v["PARALLEL"][1])), decimal(v["T2_LIMIT"][0]), decimal(v["SPE_LIMIT"][0]),
		integer(v["VARIMAX_CYCLES"][0]), integer(v["TOP_ROWS"][0]), integer(v["SCREE_WIDTH"][0]),
		integer(v["BIPLOT_SIZE"][0]), integer(v["BIPLOT_SIZE"][1]), integer(v["CIRCLE_RADIUS"][0]),
		integer(v["DIAGNOSTIC_SIZE"][0]), integer(v["DIAGNOSTIC_SIZE"][1])}
}
func readDataset() Dataset {
	return Dataset{readTable("input/data.csv"), readTable("input/supplementary.csv"), readSettings()}
}
