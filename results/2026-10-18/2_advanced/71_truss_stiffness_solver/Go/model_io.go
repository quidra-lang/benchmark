package main

import (
	"os"
	"strconv"
	"strings"
)

type Node struct{ ID, X, Y int }
type Member struct {
	ID, I, J, Section, Material, Group int
	Length, C, S                       float64
	DOFs                               [4]int
}
type Section struct {
	Name          string
	Area, Inertia float64
}
type Material struct {
	Name              string
	E, FY, Rho, Alpha float64
}
type Support struct {
	Node       int
	Fixed      [2]bool
	Prescribed [2]float64
}
type LoadLine struct {
	Kind string
	Item int
	X, Y float64
}
type LoadCase struct {
	Name  string
	Lines []LoadLine
}
type Term struct {
	Case   int
	Factor float64
}
type Combination struct {
	Name  string
	Terms []Term
}
type Axle struct {
	Offset int
	Force  float64
}
type Drawing struct{ Result, Scale, WC, HC int }
type Settings struct {
	Deck, Influence []int
	Step            int
	Axles           []Axle
	Rating          int
	GammaD, GammaL, Compression,
	Tension float64
	Deflection, Ratio, Vibration, Modes, Iterations, Removal int
	Drawings                                                 []Drawing
	MapWC,
	MapHC int
}
type Model struct {
	Nodes        []Node
	Members      []Member
	Sections     []Section
	Materials    []Material
	Supports     []Support
	Cases        []LoadCase
	Combinations []Combination
	Groups       []string
	Settings     Settings
	Order,
	Number, Free, Restrained, DOFNode []int
	Prescribed []float64
}

func must(e error) {
	if e != nil {
		panic(e)
	}
}
func text(path string) string { b, e := os.ReadFile(path); must(e); return string(b) }
func integer(s string) int    { n, e := strconv.Atoi(s); must(e); return n }
func real(s string) float64   { v, e := strconv.ParseFloat(s, 64); must(e); return v }
func csvRows(name string) [][]string {
	lines := strings.Split(strings.TrimSpace(text("input/"+name+".csv")),
		"\n")
	a := make([][]string, 0, len(lines)-1)
	for _, s := range lines[1:] {
		a = append(a, strings.Split(s,
			","))
	}
	return a
}
func readModel() Model {
	var m Model
	nodes, members, sections, materials, groups := map[int]int{}, map[int]int{},
		map[string]int{}, map[string]int{}, map[string]int{}
	for _, a := range csvRows("nodes") {
		nodes[integer(a[0])] = len(m.Nodes)
		m.Nodes = append(m.Nodes,
			Node{integer(a[0]), integer(a[1]), integer(a[2])})
	}
	for _, a := range csvRows("sections") {
		sections[a[0]] = len(m.Sections)
		m.Sections = append(m.Sections,
			Section{a[0], real(a[1]), real(a[2])})
	}
	for _, a := range csvRows("materials") {
		materials[a[0]] = len(m.Materials)
		m.Materials = append(m.Materials,
			Material{a[0], real(a[1]), real(a[2]), real(a[3]), real(a[4])})
	}
	for _, a := range csvRows("members") {
		group,
			exists := groups[a[5]]
		if !exists {
			group = len(m.Groups)
			groups[a[5]] = group
			m.Groups = append(m.Groups,
				a[5])
		}
		members[integer(a[0])] = len(m.Members)
		m.Members = append(m.Members, Member{ID: integer(a[0]),
			I: nodes[integer(a[1])], J: nodes[integer(a[2])], Section: sections[a[3]], Material: materials[a[4]],
			Group: group})
	}
	for _, a := range csvRows("supports") {
		m.Supports = append(m.Supports, Support{nodes[integer(a[0])],
			[2]bool{a[1] == "1", a[2] == "1"}, [2]float64{real(a[3]), real(a[4])}})
	}
	caseIndex, resultIndex := map[string]int{},
		map[string]int{}
	for _, line := range strings.Split(strings.TrimSpace(text("input/loads.txt")), "\n") {
		a := strings.Fields(line)
		switch a[0] {
		case "LOADCASE":
			caseIndex[a[1]] = len(m.Cases)
			resultIndex[a[1]] = len(m.Cases)
			m.Cases = append(m.Cases,
				LoadCase{Name: a[1]})
		case "END":
		case "COMBINATION":
			combo := Combination{Name: a[1]}
			for i := 2; i < len(a); i += 2 {
				combo.Terms = append(combo.Terms,
					Term{caseIndex[a[i]], real(a[i+1])})
			}
			resultIndex[a[1]] = len(m.Cases) + len(m.Combinations)
			m.Combinations = append(m.Combinations,
				combo)
		default:
			l := LoadLine{Kind: a[0]}
			if a[0] == "FORCE" {
				l.Item, l.X, l.Y = nodes[integer(a[1])], real(a[2]),
					real(a[3])
			}
			if a[0] == "TEMPERATURE" {
				l.Item, l.X = members[integer(a[1])], real(a[2])
			}
			last := len(m.Cases) - 1
			m.Cases[last].Lines = append(m.Cases[last].Lines,
				l)
		}
	}
	p := &m.Settings
	for _, line := range strings.Split(strings.TrimSpace(text("input/params.txt")),
		"\n") {
		a := strings.Fields(line)
		switch a[0] {
		case "deck":
			for _, name := range a[1:] {
				p.Deck = append(p.Deck,
					nodes[integer(name)])
			}
		case "influence":
			p.Influence = append(p.Influence, members[integer(a[1])])
		case "vehicle":
			p.Step = integer(a[1])
			for i := 2; i < len(a); i += 2 {
				p.Axles = append(p.Axles,
					Axle{integer(a[i]), real(a[i+1])})
			}
		case "rating":
			p.Rating, p.GammaD, p.GammaL = resultIndex[a[1]],
				real(a[2]), real(a[3])
		case "slenderness":
			p.Compression, p.Tension = real(a[1]), real(a[2])
		case "deflection":
			p.Deflection,
				p.Ratio = resultIndex[a[1]], integer(a[2])
		case "vibration":
			p.Vibration, p.Modes, p.Iterations = caseIndex[a[1]],
				integer(a[2]), integer(a[3])
		case "removal":
			p.Removal = resultIndex[a[1]]
		case "drawing":
			p.Drawings = append(p.Drawings,
				Drawing{resultIndex[a[1]], integer(a[2]), integer(a[3]), integer(a[4])})
		case "utilization_map":
			p.MapWC,
				p.MapHC = integer(a[1]), integer(a[2])
		}
	}
	return m
}
