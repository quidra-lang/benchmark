package main

import (
	"os"
	"strconv"
	"strings"
)

type Row struct {
	ID     string
	Values []float64
	Label  int
}
type Params struct {
	Rounds                             int
	Variants                           []string
	Bins                               int
	Smoothing, Convergence, Clip       float64
	Folds                              int
	Margins                            []float64
	Classes, SammeRounds, Permutations int
	PermutationSeed, NoiseSeed         int64
	Noise, Sizes                       []int
	Shrinkage                          []float64
	Bootstrap                          int
	BootstrapSeed                      int64
}
type Inputs struct {
	Features              []string
	Train, Test           []Row
	MultiFeatures         []string
	MultiTrain, MultiTest []Row
	Params                Params
}

func readLines(path string) []string {
	v, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	return strings.Split(strings.TrimSuffix(string(v), "\n"), "\n")
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
func decimals(v []string) []float64 {
	out := make([]float64, len(v))
	for i, s := range v {
		out[i] = decimal(s)
	}
	return out
}
func integers(v []string) []int {
	out := make([]int, len(v))
	for i, s := range v {
		out[i] = integer(s)
	}
	return out
}
func readBinary(path string) ([]string, []Row) {
	lines := readLines(path)
	head := strings.Split(lines[0], ",")
	rows := []Row{}
	for _, line := range lines[1:] {
		f := strings.Split(line, ",")
		rows = append(rows, Row{f[0], decimals(f[1 : len(f)-1]), integer(f[len(f)-1])})
	}
	return head[1 : len(head)-1], rows
}
func readParams() Params {
	v := map[string][]string{}
	for _, line := range readLines("input/params.txt") {
		f := strings.Split(line, " ")
		v[f[0]] = f[1:]
	}
	return Params{integer(v["ROUNDS"][0]), v["VARIANTS"], integer(v["BINS"][0]), decimal(v["SMOOTHING"][0]),
		decimal(v["CONVERGENCE"][0]), decimal(v["CLIP"][0]), integer(v["FOLDS"][0]), decimals(v["MARGINS"]),
		integer(v["CLASSES"][0]), integer(v["SAMME_ROUNDS"][0]), integer(v["PERMUTATION"][0]), int64(integer(v["PERMUTATION"][1])),
		int64(integer(v["NOISE"][0])), integers(v["NOISE"][1:]), integers(v["SIZES"]), decimals(v["SHRINKAGE"]),
		integer(v["BOOTSTRAP"][0]), int64(integer(v["BOOTSTRAP"][1]))}
}
func readInputs() Inputs {
	features, train := readBinary("input/train.csv")
	_, test := readBinary("input/test.csv")
	lines := readLines("input/multiclass.csv")
	head := strings.Split(lines[0], ",")
	mt, mv := []Row{}, []Row{}
	for _, line := range lines[1:] {
		f := strings.Split(line, ",")
		row := Row{f[0], decimals(f[1 : len(f)-2]), integer(f[len(f)-2])}
		if f[len(f)-1] == "train" {
			mt = append(mt, row)
		} else {
			mv = append(mv, row)
		}
	}
	return Inputs{features, train, test, head[1 : len(head)-2], mt, mv, readParams()}
}
