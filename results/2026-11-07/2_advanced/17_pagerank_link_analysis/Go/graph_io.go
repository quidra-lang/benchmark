package main

import (
	"os"
	"strconv"
	"strings"
)

type Page struct {
	id          int
	host, title string
	words       []string
}
type LinkRecord struct{ line, source, target int }
type Query struct {
	number int
	words  []string
	seeds  []int
}
type Settings struct {
	damping, tolerance, spamThreshold                                   float64
	iterations, spamTop, hitsIterations, topK, rootLimit, neighborLimit int
	sweep                                                               []float64
	trusted                                                             []int
}
type Input struct {
	pages    []Page
	records  []LinkRecord
	queries  []Query
	settings Settings
}

func readLines(path string) []string {
	data, err := os.ReadFile(path)
	if err != nil {
		panic(err)
	}
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
}
func parseInteger(text string) int {
	value, err := strconv.Atoi(text)
	if err != nil {
		panic(err)
	}
	return value
}
func parseReal(text string) float64 {
	value, err := strconv.ParseFloat(text, 64)
	if err != nil {
		panic(err)
	}
	return value
}
func readInput() Input {
	data := Input{}
	for _, line := range readLines("input/pages.csv")[1:] {
		fields := strings.Split(line, ",")
		data.pages = append(data.pages, Page{parseInteger(fields[0]), fields[1], fields[2], strings.Split(fields[2], " ")})
	}
	for i, line := range readLines("input/links.csv")[1:] {
		fields := strings.Split(line, ",")
		data.records = append(data.records, LinkRecord{i + 2, parseInteger(fields[0]), parseInteger(fields[1])})
	}
	for i, line := range readLines("input/queries.txt") {
		parts := strings.Split(line, " | ")
		query := Query{number: i + 1, words: strings.Split(parts[0], " ")}
		for _, seed := range strings.Split(parts[1], " ") {
			query.seeds = append(query.seeds, parseInteger(seed))
		}
		data.queries = append(data.queries, query)
	}
	entries := map[string][]string{}
	for _, line := range readLines("input/params.txt") {
		fields := strings.Split(line, " ")
		entries[fields[0]] = fields[1:]
	}
	number := func(key string) int { return parseInteger(entries[key][0]) }
	s := Settings{damping: parseReal(entries["DAMPING"][0]), iterations: number("PAGERANK_ITERATIONS"), tolerance: parseReal(entries["TOLERANCE"][0]), spamTop: number("SPAM_TOP"), spamThreshold: parseReal(entries["SPAM_THRESHOLD"][0]), hitsIterations: number("HITS_ITERATIONS"), topK: number("TOP_K"), rootLimit: number("ROOT_LIMIT"), neighborLimit: number("NEIGHBOR_LIMIT")}
	for _, value := range entries["DAMPING_SWEEP"] {
		s.sweep = append(s.sweep, parseReal(value))
	}
	for _, value := range entries["TRUSTED"] {
		s.trusted = append(s.trusted, parseInteger(value))
	}
	data.settings = s
	return data
}
