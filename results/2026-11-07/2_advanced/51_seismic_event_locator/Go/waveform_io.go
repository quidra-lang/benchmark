package main

import (
	"os"
	"strconv"
	"strings"
)

type Params map[string][]string

func (p Params) integer(key string, index int) int {
	v, e := strconv.Atoi(p[key][index])
	if e != nil {
		panic(e)
	}
	return v
}
func (p Params) real(key string, index int) float64 {
	v, e := strconv.ParseFloat(p[key][index], 64)
	if e != nil {
		panic(e)
	}
	return v
}

type Station struct {
	Code                                         string
	X, Y, Elevation                              int
	Order, Start                                 int
	Samples                                      []int64
	Mean, Peak                                   int64
	Noise                                        float64
	ClippedSamples, Triggers, ShortTriggers      int
	Picks                                        []*Pick
	TimeCorrection, MagCorrection                float64
	FirstResiduals, FinalResiduals, MagResiduals []float64
}

func readLines(path string) []string {
	data, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
}
func parseInt(s string) int {
	v, e := strconv.Atoi(s)
	if e != nil {
		panic(e)
	}
	return v
}
func loadInputs() ([]*Station, Params) {
	stations := []*Station{}
	for i, line := range readLines("input/stations.csv")[1:] {
		f := strings.Split(line, ",")
		stations = append(stations, &Station{Code: f[0], X: parseInt(f[1]), Y: parseInt(f[2]), Elevation: parseInt(f[3]), Order: i})
	}
	lines := readLines("input/waveforms.txt")
	cursor := 0
	for _, s := range stations {
		f := strings.Split(lines[cursor], " ")
		s.Start = parseInt(f[2])
		count := parseInt(f[3])
		cursor++
		for len(s.Samples) < count {
			for _, word := range strings.Split(lines[cursor], " ") {
				s.Samples = append(s.Samples, int64(parseInt(word)))
			}
			cursor++
		}
	}
	params := Params{}
	for _, line := range readLines("input/params.txt") {
		f := strings.Split(line, " ")
		params[f[0]] = f[1:]
	}
	return stations, params
}
