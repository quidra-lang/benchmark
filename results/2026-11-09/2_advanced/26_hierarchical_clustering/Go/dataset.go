package main

import (
	"os"
	"strconv"
	"strings"
)

type Observation struct {
	Ident, Label string
	Values       []float64
}

func readLines(path string) []string {
	data, err := os.ReadFile(path)
	if err != nil {
		panic(err)
	}
	if len(data) == 0 {
		return []string{}
	}
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
}
func integer(text string) int    { value, _ := strconv.Atoi(text); return value }
func number(text string) float64 { value, _ := strconv.ParseFloat(text, 64); return value }
func readObservations() ([]string, []Observation) {
	lines := readLines("input/data.csv")
	names := strings.Split(lines[0], ",")[2:]
	observations := []Observation{}
	for _, line := range lines[1:] {
		fields := strings.Split(line, ",")
		values := []float64{}
		for _, field := range fields[2:] {
			values = append(values, number(field))
		}
		observations = append(observations, Observation{fields[0], fields[1], values})
	}
	return names, observations
}
func readSettings() map[string][]string {
	entries := map[string][]string{}
	for _, line := range readLines("input/params.txt") {
		fields := strings.Split(line, " ")
		entries[fields[0]] = fields[1:]
	}
	return entries
}
func writeLines(name string, lines []string) {
	text := ""
	if len(lines) > 0 {
		text = strings.Join(lines, "\n") + "\n"
	}
	if err := os.WriteFile("output/"+name, []byte(text), 0644); err != nil {
		panic(err)
	}
}
