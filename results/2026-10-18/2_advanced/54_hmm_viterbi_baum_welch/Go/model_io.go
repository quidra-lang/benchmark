package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

type Model struct {
	Name                 string
	States, Symbols      []string
	Missing              string
	Initial              []float64
	Transition, Emission [][]float64
}
type RawRecord struct {
	Name, Role, Observation, Labels string
	Line                            int
}
type RawInputs struct {
	Initial            *Model
	Sequences, Labeled []RawRecord
	Params             map[string][]string
}

func sum(values []float64) float64 {
	out := 0.0
	for _, v := range values {
		out += v
	}
	return out
}
func normalize(values []float64) []float64 {
	total := sum(values)
	out := make([]float64, len(values))
	for i, v := range values {
		out[i] = v / total
	}
	return out
}
func matrix(rows, columns int) [][]float64 {
	out := make([][]float64, rows)
	for i := range out {
		out[i] = make([]float64, columns)
	}
	return out
}
func newModel(name string, template *Model, initial []float64, transition, emission [][]float64) *Model {
	out := &Model{Name: name, States: template.States, Symbols: template.Symbols, Missing: template.Missing, Initial: normalize(initial)}
	for _, row := range transition {
		out.Transition = append(out.Transition, normalize(row))
	}
	for _, row := range emission {
		out.Emission = append(out.Emission, normalize(row))
	}
	return out
}
func readLines(path string) []string {
	data, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
}
func parseReal(s string) float64 {
	v, e := strconv.ParseFloat(s, 64)
	if e != nil {
		panic(e)
	}
	return v
}
func parseInt(s string) int {
	v, e := strconv.Atoi(s)
	if e != nil {
		panic(e)
	}
	return v
}
func reals(values []string) []float64 {
	out := make([]float64, len(values))
	for i, s := range values {
		out[i] = parseReal(s)
	}
	return out
}
func readInputs() RawInputs {
	lines := readLines("input/model.txt")
	template := &Model{States: strings.Split(lines[0], " ")[1:], Symbols: strings.Split(lines[1], " ")[1:], Missing: strings.Split(lines[2], " ")[1]}
	k := len(template.States)
	initial := reals(strings.Split(lines[3], " ")[1:])
	transition, emission := [][]float64{}, [][]float64{}
	for i := 0; i < k; i++ {
		transition = append(transition, reals(strings.Split(lines[4+i], " ")[2:]))
		emission = append(emission, reals(strings.Split(lines[4+k+i], " ")[2:]))
	}
	out := RawInputs{Initial: newModel("INITIAL", template, initial, transition, emission), Params: map[string][]string{}}
	for i, line := range readLines("input/sequences.txt") {
		f := strings.Split(line, " ")
		out.Sequences = append(out.Sequences, RawRecord{Name: f[0], Observation: f[1], Line: i + 1})
	}
	lines = readLines("input/labeled.txt")
	for i := 0; i < len(lines); i += 2 {
		f := strings.Split(lines[i], " ")
		out.Labeled = append(out.Labeled, RawRecord{f[0], f[1], f[2], lines[i+1], i + 1})
	}
	for _, line := range readLines("input/params.txt") {
		f := strings.Split(line, " ")
		out.Params[f[0]] = f[1:]
	}
	return out
}
func numberDigits(value float64, digits int) string {
	text := fmt.Sprintf("%.*f", digits, value)
	if strings.HasPrefix(text, "-") {
		n, e := strconv.ParseFloat(text, 64)
		if e == nil && n == 0 {
			return text[1:]
		}
	}
	return text
}
func number(value float64) string { return numberDigits(value, 4) }
func numberList(values []float64) string {
	out := make([]string, len(values))
	for i, v := range values {
		out[i] = number(v)
	}
	return strings.Join(out, " ")
}
func modelLines(model *Model) []string {
	lines := []string{"MODEL " + model.Name, "STATES " + strings.Join(model.States, " "), "SYMBOLS " + strings.Join(model.Symbols,
		" "), "MISSING " + model.Missing, "INITIAL " + numberList(model.Initial)}
	for i, state := range model.States {
		lines = append(lines, "TRANSITION "+state+" "+numberList(model.Transition[i]))
	}
	for i, state := range model.States {
		lines = append(lines, "EMISSION "+state+" "+numberList(model.Emission[i]))
	}
	return lines
}
func writeLines(name string, lines []string) {
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	if e := os.WriteFile("output/"+name, []byte(strings.Join(lines, "\n")+"\n"), 0644); e != nil {
		panic(e)
	}
}
