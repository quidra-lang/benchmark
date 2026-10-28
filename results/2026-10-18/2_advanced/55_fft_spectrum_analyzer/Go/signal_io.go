package main

import (
	"os"
	"strconv"
	"strings"
)

type Params struct {
	M                                               int
	MainWindow                                      string
	Threshold                                       float64
	PeakCount                                       int
	Fundamental                                     float64
	D, L                                            int
	WelchWindow                                     string
	F, H, B                                         int
	SpectrogramWindow                               string
	Onset                                           float64
	P1, P2, B1, B2, Notch, Width, E1, E2, Z1, Z2, J int
	FIR                                             []float64
	MaxLag                                          int
	Bands                                           []int
	T1, T2, Block                                   int
}

func readText(path string) string {
	b, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	return string(b)
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
func readInput() (int, []float64, []float64, Params) {
	lines := strings.Split(strings.TrimSuffix(readText("input/signal.csv"), "\n"), "\n")
	header := strings.Split(lines[0], ",")
	fs, n := integer(header[0]), integer(header[1])
	x, y := make([]float64, n), make([]float64, n)
	for i := 0; i < n; i++ {
		s := strings.Split(lines[i+1], ",")
		x[i], y[i] = number(s[0]), number(s[1])
	}
	a := [][]string{}
	for _, s := range strings.Split(strings.TrimSuffix(readText("input/params.txt"), "\n"), "\n") {
		a = append(a, strings.Fields(s)[1:])
	}
	p := Params{M: integer(a[0][0]), MainWindow: a[1][0], Threshold: number(a[2][0]), PeakCount: integer(a[3][0]),
		Fundamental: number(a[4][0]), D: integer(a[4][1]), L: integer(a[5][0]), WelchWindow: a[5][1],
		F: integer(a[6][0]), H: integer(a[6][1]), B: integer(a[6][2]), SpectrogramWindow: a[6][3],
		Onset: number(a[7][0]), P1: integer(a[8][0]), P2: integer(a[8][1]), B1: integer(a[9][0]),
		B2: integer(a[9][1]), Notch: integer(a[10][0]), Width: integer(a[10][1]), E1: integer(a[11][0]),
		E2: integer(a[11][1]), Z1: integer(a[12][0]), Z2: integer(a[12][1]), J: integer(a[12][2]),
		MaxLag: integer(a[14][0]), T1: integer(a[16][0]), T2: integer(a[16][1]), Block: integer(a[17][0])}
	for _, s := range a[13] {
		p.FIR = append(p.FIR, number(s))
	}
	for _, s := range a[15] {
		p.Bands = append(p.Bands, integer(s))
	}
	return fs, x, y, p
}
