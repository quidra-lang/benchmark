package main

import (
	"os"
	"strconv"
	"strings"
)

type Value struct {
	Number  float64
	Label   string
	Present bool
}
type Record map[string]Value
type DataFrame struct {
	Columns     []string
	Categorical map[string]bool
	Rows        []Record
}
type Params struct {
	Tolerance, Alpha, Confidence, Leverage, Studentized, Cook, DFFITS, VIF, DW, BP, Normal float64
	Best, Width, Height                                                                    int
	Limit                                                                                  float64
}

func readLines(path string) []string {
	data, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
}
func decimal(s string) float64 {
	v, e := strconv.ParseFloat(s, 64)
	if e != nil {
		panic(e)
	}
	return v
}
func readCSV(path string, kinds map[string]bool) DataFrame {
	lines := readLines(path)
	columns := strings.Split(lines[0], ",")
	records := [][]string{}
	for _, line := range lines[1:] {
		records = append(records, strings.Split(line, ","))
	}
	categories := map[string]bool{}
	for j, c := range columns {
		if kinds != nil {
			categories[c] = kinds[c]
		} else {
			for _, r := range records {
				v := r[j]
				if v != "NA" && v[0] >= 'A' && v[0] <= 'Z' {
					categories[c] = true
					break
				}
			}
		}
	}
	rows := []Record{}
	for _, r := range records {
		row := Record{}
		for j, c := range columns {
			v := r[j]
			item := Value{}
			if v != "NA" {
				item.Present = true
				if categories[c] {
					item.Label = v
				} else {
					item.Number = decimal(v)
				}
			}
			row[c] = item
		}
		rows = append(rows, row)
	}
	return DataFrame{columns, categories, rows}
}
func readParams() Params {
	v := map[string][]string{}
	for _, line := range readLines("input/params.txt") {
		f := strings.Split(line, " ")
		v[f[0]] = f[1:]
	}
	get := func(s string) float64 { return decimal(v[s][0]) }
	return Params{get("RANK_TOL"), get("ALPHA_REMOVE"), get("CONFIDENCE"), get("LEVERAGE"), get("STUDENTIZED"),
		get("COOK"), get("DFFITS"), get("VIF"), get("DURBIN_WATSON"), get("BREUSCH_PAGAN"), get("NORMALITY"),
		int(get("BEST_SUBSETS")), int(decimal(v["PLOT"][0])), int(decimal(v["PLOT"][1])), decimal(v["PLOT"][2])}
}
