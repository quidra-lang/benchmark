package main

import (
	"os"
	"strconv"
	"strings"
)

type Attribute struct {
	index   int
	name    string
	integer bool
	values  []string
}
type Row struct {
	id     string
	values []int
	label  int
}
type Settings struct {
	maxDepth, minSplit, minLeaf, maxSurrogates, folds int
	curve                                             []int
	bagTrees                                          int
	bagSeed                                           int64
	repeats                                           int
	permutationSeed                                   int64
}
type Dataset struct {
	attributes              []*Attribute
	target                  string
	classes                 []string
	train, validation, test []Row
	settings                Settings
}

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
func parseInt(text string) int {
	value, err := strconv.Atoi(text)
	if err != nil {
		panic(err)
	}
	return value
}
func position(values []string, value string) int {
	for i, item := range values {
		if item == value {
			return i
		}
	}
	return -1
}
func readRows(path string, attributes []*Attribute, classes []string) []Row {
	rows := []Row{}
	for _, line := range readLines(path)[1:] {
		fields := strings.Split(line, ",")
		values := make([]int, len(attributes))
		for i, attribute := range attributes {
			text := fields[i+1]
			if text == "?" {
				values[i] = -1
			} else if attribute.integer {
				values[i] = parseInt(text)
			} else {
				values[i] = position(attribute.values, text)
			}
		}
		rows = append(rows, Row{fields[0], values, position(classes, fields[len(fields)-1])})
	}
	return rows
}
func loadDataset() *Dataset {
	data := &Dataset{}
	for _, line := range readLines("input/schema.txt") {
		fields := strings.Split(line, " ")
		if fields[0] == "ATTRIBUTE" {
			data.attributes = append(data.attributes, &Attribute{len(data.attributes), fields[1], fields[2] == "INT", fields[3:]})
		} else {
			data.target = fields[1]
			data.classes = fields[2:]
		}
	}
	entries := map[string][]int{}
	for _, line := range readLines("input/params.txt") {
		fields := strings.Split(line, " ")
		for _, value := range fields[1:] {
			entries[fields[0]] = append(entries[fields[0]], parseInt(value))
		}
	}
	data.settings = Settings{entries["MAX_DEPTH"][0], entries["MIN_SAMPLES_SPLIT"][0], entries["MIN_SAMPLES_LEAF"][0], entries["MAX_SURROGATES"][0], entries["FOLDS"][0], entries["CURVE"], entries["BAG_TREES"][0], int64(entries["BAG_SEED"][0]), entries["PERMUTATION_REPEATS"][0], int64(entries["PERMUTATION_SEED"][0])}
	data.train = readRows("input/train.csv", data.attributes, data.classes)
	data.validation = readRows("input/validation.csv", data.attributes, data.classes)
	data.test = readRows("input/test.csv", data.attributes, data.classes)
	return data
}
func (r Row) missing() int {
	count := 0
	for _, value := range r.values {
		if value < 0 {
			count++
		}
	}
	return count
}
