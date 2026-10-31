package main

import (
	"os"
	"strconv"
	"strings"
)

type Variable struct {
	Name                  string
	States                []string
	Parents               []int
	Given, Learned, Theta [][]float64
	Counts                [][]int
	Source                string
}
type Settings struct {
	Alpha       float64
	Method      string
	Order       []int
	Enumeration int
	Seed        int64
}
type Network struct {
	Variables []Variable
	Samples   [][]int
	Queries   []string
	Settings  Settings
	Names     map[string]int
}

func must(e error) {
	if e != nil {
		panic(e)
	}
}
func readText(path string) string { b, e := os.ReadFile(path); must(e); return string(b) }
func integer(s string) int        { v, e := strconv.Atoi(s); must(e); return v }
func real(s string) float64       { v, e := strconv.ParseFloat(s, 64); must(e); return v }
func readInput() Network {
	n := Network{Names: map[string]int{}}
	var lines []string
	for _, line := range strings.Split(readText("input/network.txt"),
		"\n") {
		if line != "" && line[0] != '#' {
			lines = append(lines, line)
		}
	}
	for pos := 0; pos < len(lines); pos++ {
		a := strings.Fields(lines[pos])
		switch a[0] {
		case "VARIABLE":
			n.Names[a[1]] = len(n.Variables)
			n.Variables = append(n.Variables,
				Variable{Name: a[1], States: a[2:]})
		case "PARENTS":
			v := n.Names[a[1]]
			for _, name := range a[2:] {
				n.Variables[v].Parents = append(n.Variables[v].Parents,
					n.Names[name])
			}
		case "CPT":
			v := n.Names[a[1]]
			rows := assignmentCount(n.Variables[v].Parents, n)
			for r := 0; r < rows; r++ {
				pos++
				var values []float64
				for _, value := range strings.Fields(lines[pos]) {
					values = append(values, real(value))
				}
				n.Variables[v].Given = append(n.Variables[v].Given,
					values)
			}
		}
	}
	for _, line := range strings.Split(strings.TrimSpace(readText("input/params.txt")), "\n") {
		a := strings.Fields(line)
		switch a[0] {
		case "PSEUDOCOUNT":
			n.Settings.Alpha = real(a[1])
		case "ELIMINATION":
			n.Settings.Method = strings.ToLower(a[1])
		case "ORDER":
			for _, name := range a[1:] {
				n.Settings.Order = append(n.Settings.Order, n.Names[name])
			}
		case "ENUMERATION_LIMIT":
			n.Settings.Enumeration = integer(a[1])
		case "SEED":
			n.Settings.Seed = int64(integer(a[1]))
		case "SOURCE":
			n.Variables[n.Names[a[1]]].Source = a[2]
		}
	}
	sampleLines := strings.Split(strings.TrimSpace(readText("input/samples.csv")),
		"\n")
	header := strings.Split(sampleLines[0], ",")
	for _, line := range sampleLines[1:] {
		values := strings.Split(line,
			",")
		a := make([]int, len(n.Variables))
		for col, name := range header {
			v := n.Names[name]
			for state, s := range n.Variables[v].States {
				if s == values[col] {
					a[v] = state
					break
				}
			}
		}
		n.Samples = append(n.Samples,
			a)
	}
	n.Queries = strings.Split(strings.TrimSpace(readText("input/queries.txt")), "\n")
	return n
}
