package main

import (
	"math"
	"os"
	"strconv"
	"strings"
)

type Example struct {
	Ident  string
	Values []float64
	Label  int
}
type Settings map[string][]string

func (s Settings) Int(key string, i int) int {
	value, err := strconv.Atoi(s[key][i])
	if err != nil {
		panic(err)
	}
	return value
}
func (s Settings) Real(key string, i int) float64 {
	value, err := strconv.ParseFloat(s[key][i], 64)
	if err != nil {
		panic(err)
	}
	return value
}
func readLines(path string) []string {
	content, err := os.ReadFile(path)
	if err != nil {
		panic(err)
	}
	return strings.Split(strings.TrimSuffix(string(content), "\n"), "\n")
}
func readExamples(path string) ([]string, []Example) {
	lines := readLines(path)
	header := strings.Split(lines[0], ",")
	examples := []Example{}
	for _, line := range lines[1:] {
		f := strings.Split(line, ",")
		values := []float64{}
		for _, s := range f[1 : len(f)-1] {
			v, e := strconv.ParseFloat(s, 64)
			if e != nil {
				panic(e)
			}
			values = append(values, v)
		}
		label, e := strconv.Atoi(f[len(f)-1])
		if e != nil {
			panic(e)
		}
		examples = append(examples, Example{f[0], values, label})
	}
	return header[1 : len(header)-1], examples
}
func readSettings() Settings {
	settings := Settings{}
	for _, line := range readLines("input/params.txt") {
		fields := strings.Fields(line)
		settings[fields[0]] = fields[1:]
	}
	return settings
}
func expansionTuples(count, degree int) [][]int {
	tuples := [][]int{}
	var visit func([]int, int, int)
	visit = func(prefix []int, start, remaining int) {
		if remaining == 0 {
			tuples = append(tuples, append([]int(nil), prefix...))
			return
		}
		for j := start; j < count; j++ {
			visit(append(prefix, j), j, remaining-1)
		}
	}
	for length := 1; length <= degree; length++ {
		visit(nil, 0, length)
	}
	return tuples
}
func expandedNames(names []string, tuples [][]int) []string {
	result := []string{}
	for _, indices := range tuples {
		fields := []string{}
		for _, j := range indices {
			fields = append(fields, names[j])
		}
		result = append(result, strings.Join(fields, "*"))
	}
	return result
}
func expandedValues(tuples [][]int, values []float64) []float64 {
	result := []float64{}
	for _, indices := range tuples {
		product := values[indices[0]]
		for _, j := range indices[1:] {
			product *= values[j]
		}
		result = append(result, product)
	}
	return result
}

type Statistics struct{ Means, Deviations []float64 }

func computeStatistics(rows [][]float64, count int) Statistics {
	result := Statistics{}
	for j := 0; j < count; j++ {
		total := 0.0
		for _, row := range rows {
			total += row[j]
		}
		mean := total / float64(len(rows))
		squares := 0.0
		for _, row := range rows {
			d := row[j] - mean
			squares += d * d
		}
		result.Means = append(result.Means, mean)
		result.Deviations = append(result.Deviations, math.Sqrt(squares/float64(len(rows)-1)))
	}
	return result
}
func standardize(values []float64, s Statistics, count int) []float64 {
	vector := []float64{1}
	for j := 0; j < count; j++ {
		vector = append(vector, (values[j]-s.Means[j])/s.Deviations[j])
	}
	return vector
}
func standardizedRows(rows [][]float64, s Statistics, count int) [][]float64 {
	result := [][]float64{}
	for _, row := range rows {
		result = append(result, standardize(row, s, count))
	}
	return result
}
