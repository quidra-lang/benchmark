package main

import (
	"os"
	"sort"
	"strconv"
	"strings"
)

type Subject struct {
	ID               int
	Group            string
	Time, Event, Age int
	Sex              string
	Stage            int
}
type Params struct {
	Groups                []string
	Times                 []int
	Tau, Width, Intervals int
	Strata                string
	Subgroups             []string
	Landmark              int
	Covariates            []string
	Residuals             int
	Plot                  [4]int
}

func readLines(path string) []string {
	v, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	return strings.Split(strings.TrimSuffix(string(v), "\n"), "\n")
}
func integer(s string) int {
	v, e := strconv.Atoi(s)
	if e != nil {
		panic(e)
	}
	return v
}
func readDataset() ([]Subject, Params) {
	subjects := []Subject{}
	for _, line := range readLines("input/subjects.csv")[1:] {
		f := strings.Split(line, ",")
		subjects = append(subjects, Subject{integer(f[0]), f[1], integer(f[2]), integer(f[3]), integer(f[4]), f[5], integer(f[6])})
	}
	sort.Slice(subjects, func(i, j int) bool { return subjects[i].ID < subjects[j].ID })
	v := map[string][]string{}
	for _, line := range readLines("input/params.txt") {
		f := strings.Split(line, " ")
		v[f[0]] = f[1:]
	}
	p := Params{Groups: v["GROUPS"], Tau: integer(v["TAU"][0]), Width: integer(v["LIFE_TABLE"][0]), Intervals: integer(v["LIFE_TABLE"][1]),
		Strata: v["STRATA"][0], Subgroups: v["SUBGROUPS"], Landmark: integer(v["LANDMARK"][0]), Covariates: v["COX"],
		Residuals: integer(v["RESIDUALS"][0])}
	for _, s := range v["REPORT_TIMES"] {
		p.Times = append(p.Times, integer(s))
	}
	for i, s := range v["PLOT"] {
		p.Plot[i] = integer(s)
	}
	return subjects, p
}
