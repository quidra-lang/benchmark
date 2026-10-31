package main

import (
	"os"
	"strconv"
	"strings"
)

type Point [2]float64
type Example struct {
	ID    string
	Point Point
	Label int
}
type Params struct {
	Cs                     []float64
	Kernels                []Kernel
	Tolerance, Epsilon     float64
	MaxPasses, Folds       int
	Learning               []int
	Newton                 int
	Multiclass             string
	MulticlassC, Lambda    float64
	Iterations, Seed       int
	XMin, XMax, YMin, YMax float64
	W, H                   int
}

func lines(path string) []string {
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
func readExamples(path string) []Example {
	out := []Example{}
	for _, line := range lines(path)[1:] {
		a := strings.Split(line, ",")
		out = append(out, Example{a[0], Point{number(a[1]), number(a[2])}, integer(a[3])})
	}
	return out
}
func readMulticlass() ([]Example, []Example) {
	train, test := []Example{}, []Example{}
	for _, line := range lines("input/multiclass.csv")[1:] {
		a := strings.Split(line, ",")
		e := Example{a[0], Point{number(a[1]), number(a[2])}, integer(a[3])}
		if a[4] == "train" {
			train = append(train, e)
		} else {
			test = append(test, e)
		}
	}
	return train, test
}
func readParams() Params {
	p := Params{}
	for _, line := range lines("input/params.txt") {
		a := strings.Fields(line)
		switch a[0] {
		case "C_GRID":
			for _, s := range a[1:] {
				p.Cs = append(p.Cs, number(s))
			}
		case "KERNEL":
			k := Kernel{Name: a[1], Kind: a[2]}
			if k.Kind == "poly" {
				k.Degree, k.Gamma, k.Coef = integer(a[3]), number(a[4]), number(a[5])
			} else if k.Kind == "rbf" {
				k.Gamma = number(a[3])
			}
			p.Kernels = append(p.Kernels, k)
		case "TOLERANCE":
			p.Tolerance = number(a[1])
		case "EPS":
			p.Epsilon = number(a[1])
		case "MAX_PASSES":
			p.MaxPasses = integer(a[1])
		case "FOLDS":
			p.Folds = integer(a[1])
		case "LEARNING_CURVE":
			for _, s := range a[1:] {
				p.Learning = append(p.Learning, integer(s))
			}
		case "NEWTON_ITERATIONS":
			p.Newton = integer(a[1])
		case "MULTICLASS":
			p.Multiclass, p.MulticlassC = a[1], number(a[2])
		case "PEGASOS":
			p.Lambda, p.Iterations, p.Seed = number(a[1]), integer(a[2]), integer(a[3])
		case "PLOT_X":
			p.XMin, p.XMax = number(a[1]), number(a[2])
		case "PLOT_Y":
			p.YMin, p.YMax = number(a[1]), number(a[2])
		case "PLOT_SIZE":
			p.W, p.H = integer(a[1]), integer(a[2])
		}
	}
	return p
}
