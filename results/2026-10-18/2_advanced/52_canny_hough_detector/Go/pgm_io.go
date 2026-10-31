package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

type Image [][]int
type Point struct{ X, Y int }
type Trig [180]Point
type Params map[string][]int64

func (p Params) integer(key string) int { return int(p[key][0]) }
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
func readInputs() (Image, Trig, Params) {
	lines := readLines("input/image.pgm")
	image := Image{}
	for _, line := range lines[3:] {
		row := []int{}
		for _, word := range strings.Split(line, " ") {
			row = append(row, parseInt(word))
		}
		image = append(image, row)
	}
	trig := Trig{}
	for _, line := range readLines("input/trig.txt") {
		f := strings.Split(line, " ")
		trig[parseInt(f[0])] = Point{parseInt(f[1]), parseInt(f[2])}
	}
	params := Params{}
	for _, line := range readLines("input/params.txt") {
		f := strings.Split(line, " ")
		for _, word := range f[1:] {
			v, e := strconv.ParseInt(word, 10, 64)
			if e != nil {
				panic(e)
			}
			params[f[0]] = append(params[f[0]], v)
		}
	}
	return image, trig, params
}
func writeLines(name string, lines []string) {
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	if e := os.WriteFile("output/"+name, []byte(strings.Join(lines, "\n")+"\n"), 0644); e != nil {
		panic(e)
	}
}
func writePGM(name string, image Image) {
	lines := []string{"P2", fmt.Sprintf("%d %d", len(image[0]), len(image)), "255"}
	for _, row := range image {
		fields := make([]string, len(row))
		for i, v := range row {
			fields[i] = strconv.Itoa(v)
		}
		lines = append(lines, strings.Join(fields, " "))
	}
	writeLines(name, lines)
}
