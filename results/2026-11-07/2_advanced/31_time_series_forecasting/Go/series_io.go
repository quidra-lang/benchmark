package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

type Series struct {
	Name    string
	Periods []string
	Raw     []*float64
	Events  map[string]string
	Policy  Policy
}
type Policy struct {
	OnHand, Lead, Review int
	Service              float64
}
type Settings map[string][]string

func integer(text string) int {
	value, e := strconv.Atoi(text)
	if e != nil {
		panic(e)
	}
	return value
}
func number(text string) float64 {
	value, e := strconv.ParseFloat(text, 64)
	if e != nil {
		panic(e)
	}
	return value
}
func (s Settings) Int(key string) int      { return integer(s[key][0]) }
func (s Settings) Real(key string) float64 { return number(s[key][0]) }
func (s Settings) Reals(key string) []float64 {
	values := []float64{}
	for _, v := range s[key] {
		values = append(values, number(v))
	}
	return values
}
func readLines(path string) []string {
	content, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	return strings.Split(strings.TrimSuffix(string(content), "\n"), "\n")
}
func readInputs() ([]*Series, Settings) {
	series := []*Series{}
	named := map[string]*Series{}
	for _, line := range readLines("input/series.csv")[1:] {
		f := strings.Split(line, ",")
		record := named[f[0]]
		if record == nil {
			record = &Series{Name: f[0], Events: map[string]string{}}
			named[f[0]] = record
			series = append(series, record)
		}
		record.Periods = append(record.Periods, f[1])
		var value *float64
		if f[2] != "NA" {
			n := number(f[2])
			value = &n
		}
		record.Raw = append(record.Raw, value)
	}
	for _, line := range readLines("input/events.csv")[1:] {
		f := strings.Split(line, ",")
		named[f[0]].Events[f[1]] = f[2]
	}
	for _, line := range readLines("input/inventory.csv")[1:] {
		f := strings.Split(line, ",")
		named[f[0]].Policy = Policy{integer(f[1]), integer(f[2]), integer(f[3]), number(f[4])}
	}
	settings := Settings{}
	for _, line := range readLines("input/params.txt") {
		f := strings.Fields(line)
		settings[f[0]] = f[1:]
	}
	return series, settings
}
func nextMonth(period string) string {
	year, month := integer(period[:4]), integer(period[5:])
	year += month / 12
	month = month%12 + 1
	return fmt.Sprintf("%04d-%02d", year, month)
}
func real(value float64) string {
	text := fmt.Sprintf("%.4f", value)
	if text == "-0.0000" {
		return "0.0000"
	}
	return text
}
func optional(value *float64) string {
	if value == nil {
		return "NA"
	}
	return real(*value)
}
func writeLines(name string, lines []string) {
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	if e := os.WriteFile("output/"+name, []byte(strings.Join(lines, "\n")+"\n"), 0644); e != nil {
		panic(e)
	}
}
