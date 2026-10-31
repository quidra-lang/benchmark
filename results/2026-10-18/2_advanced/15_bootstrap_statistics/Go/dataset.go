package main

import (
	"os"
	"strconv"
	"strings"
)

type Group struct {
	number int
	name   string
	values []int64
}
type PairedSample struct{ before, after, differences []int64 }
type Settings struct {
	seed                                                                    int64
	bootstrap, permutations, confidence, pilot, powerSims, powerPerms, bins int
}
type Dataset struct {
	groups   []*Group
	paired   PairedSample
	pairs    [][2]*Group
	settings Settings
}

func readLines(path string) []string {
	data, err := os.ReadFile(path)
	if err != nil {
		panic(err)
	}
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
}
func integer(text string) int64 {
	value, err := strconv.ParseInt(text, 10, 64)
	if err != nil {
		panic(err)
	}
	return value
}
func hundredths(text string) int64 {
	parts := strings.SplitN(text, ".", 2)
	fraction := "00"
	if len(parts) > 1 {
		fraction = (parts[1] + "00")[:2]
	}
	return integer(parts[0])*100 + integer(fraction)
}
func loadDataset() *Dataset {
	data := &Dataset{}
	byName := map[string]*Group{}
	for _, line := range readLines("input/samples.csv")[1:] {
		fields := strings.Split(line, ",")
		group := byName[fields[0]]
		if group == nil {
			group = &Group{number: len(data.groups) + 1, name: fields[0]}
			byName[group.name] = group
			data.groups = append(data.groups, group)
		}
		group.values = append(group.values, hundredths(fields[1]))
	}
	for _, line := range readLines("input/paired.csv")[1:] {
		fields := strings.Split(line, ",")
		before, after := hundredths(fields[1]), hundredths(fields[2])
		data.paired.before = append(data.paired.before, before)
		data.paired.after = append(data.paired.after, after)
		data.paired.differences = append(data.paired.differences, after-before)
	}
	entries := map[string][]int{}
	for _, line := range readLines("input/params.txt") {
		fields := strings.Split(line, " ")
		if fields[0] == "compare" {
			data.pairs = append(data.pairs, [2]*Group{byName[fields[1]], byName[fields[2]]})
		} else {
			for _, value := range fields[1:] {
				entries[fields[0]] = append(entries[fields[0]], int(integer(value)))
			}
		}
	}
	data.settings = Settings{int64(entries["seed"][0]), entries["bootstrap"][0], entries["permutations"][0], entries["confidence"][0], entries["pilot"][0], entries["power"][0], entries["power"][1], entries["bins"][0]}
	return data
}
