package main

import (
	"os"
	"strconv"
	"strings"
)

func readLines(path string) []string {
	data, err := os.ReadFile(path)
	if err != nil {
		panic(err)
	}
	if len(data) == 0 {
		return nil
	}
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
}
func integer(text string) int64 {
	v, err := strconv.ParseInt(text, 10, 64)
	if err != nil {
		panic(err)
	}
	return v
}
func readECG() []int64 {
	samples := []int64{}
	for _, line := range readLines("input/ecg.csv")[1:] {
		fields := strings.Split(line, ",")
		samples = append(samples, integer(fields[1]))
	}
	return samples
}

type Annotation struct {
	Sample int
	Label  string
	Beat   *Beat
}

func readAnnotations() []*Annotation {
	refs := []*Annotation{}
	for _, line := range readLines("input/annotations.csv")[1:] {
		fields := strings.Split(line, ",")
		refs = append(refs, &Annotation{Sample: int(integer(fields[0])), Label: fields[1]})
	}
	return refs
}
func readParams() map[string]int64 {
	params := map[string]int64{}
	for _, line := range readLines("input/params.txt") {
		fields := strings.Split(line, " ")
		params[fields[0]] = integer(fields[1])
	}
	return params
}
func writeLines(name string, lines []string) {
	if err := os.WriteFile("output/"+name, []byte(strings.Join(lines, "\n")+"\n"), 0644); err != nil {
		panic(err)
	}
}
