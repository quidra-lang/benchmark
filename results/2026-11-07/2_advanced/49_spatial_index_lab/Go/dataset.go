package main

import (
	"os"
	"strconv"
	"strings"
)

type Object struct {
	ID  int
	Box Box
}
type Params struct{ World, Bucket, Maximum, Minimum, CellSize int }
type Command struct {
	Name   string
	Values []int
}

func readLines(path string) []string {
	data, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
}
func integer(s string) int {
	n, e := strconv.Atoi(s)
	if e != nil {
		panic(e)
	}
	return n
}
func parseInts(fields []string) []int {
	values := make([]int, len(fields))
	for i, s := range fields {
		values[i] = integer(s)
	}
	return values
}
func readObjects(path string, points bool) []Object {
	objects := []Object{}
	for _, line := range readLines(path)[1:] {
		v := parseInts(strings.Split(line, ","))
		box := Box{v[1], v[2], v[1], v[2]}
		if !points {
			box = Box{v[1], v[2], v[3], v[4]}
		}
		objects = append(objects, Object{v[0], box})
	}
	return objects
}
func readDataset() ([]Object, []Object, Params, []Command) {
	points, rects := readObjects("input/points.csv", true), readObjects("input/rects.csv", false)
	lines := readLines("input/params.txt")
	values := [][]string{}
	for _, s := range lines {
		values = append(values, strings.Split(s, " "))
	}
	p := Params{integer(values[0][1]), integer(values[1][1]), integer(values[2][1]), integer(values[2][2]), integer(values[3][1])}
	commands := []Command{}
	for _, line := range readLines("input/queries.txt") {
		f := strings.Split(line, " ")
		commands = append(commands, Command{f[0], parseInts(f[1:])})
	}
	return points, rects, p, commands
}
