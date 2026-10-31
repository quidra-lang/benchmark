package main

import (
	"os"
	"strconv"
	"strings"
)

type Group struct {
	Name       string
	Population int
	Fatality   float64
}
type Intervention struct {
	Day        int
	Multiplier float64
}
type Scenario struct {
	Name       string
	Multiplier float64
}
type ContactChange struct {
	Name, Group string
	Factor      float64
}
type Params struct {
	Sigma, Gamma, E0, I0, BetaMin, BetaMax, RhoMin, RhoMax float64
	BetaCount, RhoCount, Golden, Rounds                    int
	DeltaBeta, DeltaGamma, Alpha, Chi, Psi, Omega          float64
	Nelder, Holdout                                        int
	EffectWidth, Outlier                                   float64
	DeathLag                                               int
	Milestones                                             []int
	Generation, Horizon                                    int
	Threshold                                              float64
	Scenarios                                              []Scenario
	Changes                                                []ContactChange
}
type Data struct {
	Cases, Deaths []int
	Groups        []Group
	Contacts      [][]float64
	Interventions []Intervention
	Params        Params
	Population    int
	Fatality      float64
}

func lines(path string) []string {
	b, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	return strings.Split(strings.TrimSuffix(string(b), "\n"), "\n")
}
func integer(s string) int {
	v, e := strconv.Atoi(s)
	if e != nil {
		panic(e)
	}
	return v
}
func number(s string) float64 {
	v, e := strconv.ParseFloat(s, 64)
	if e != nil {
		panic(e)
	}
	return v
}
func readData() Data {
	d := Data{}
	for _, line := range lines("input/cases.csv")[1:] {
		a := strings.Split(line, ",")
		d.Cases = append(d.Cases, integer(a[1]))
		d.Deaths = append(d.Deaths, integer(a[2]))
	}
	for _, line := range lines("input/population.txt") {
		a := strings.Fields(line)
		if a[0] == "group" {
			g := Group{a[1], integer(a[2]), number(a[3])}
			d.Groups = append(d.Groups, g)
			d.Population += g.Population
			d.Fatality += float64(g.Population) * g.Fatality
		} else {
			row := []float64{}
			for _, s := range a[1:] {
				row = append(row, number(s))
			}
			d.Contacts = append(d.Contacts, row)
		}
	}
	d.Fatality /= float64(d.Population)
	for _, line := range lines("input/interventions.txt") {
		a := strings.Fields(line)
		d.Interventions = append(d.Interventions, Intervention{integer(a[0]), number(a[1])})
	}
	p := &d.Params
	for _, line := range lines("input/params.txt") {
		a := strings.Fields(line)
		switch a[0] {
		case "sigma":
			p.Sigma = number(a[1])
		case "gamma":
			p.Gamma = number(a[1])
		case "initial":
			p.E0, p.I0 = number(a[1]), number(a[2])
		case "beta_grid":
			p.BetaMin, p.BetaMax, p.BetaCount = number(a[1]), number(a[2]), integer(a[3])
		case "rho_grid":
			p.RhoMin, p.RhoMax, p.RhoCount = number(a[1]), number(a[2]), integer(a[3])
		case "golden":
			p.Golden, p.Rounds = integer(a[1]), integer(a[2])
		case "simplex":
			p.DeltaBeta, p.DeltaGamma = number(a[1]), number(a[2])
		case "nelder_mead":
			p.Alpha, p.Chi, p.Psi, p.Omega, p.Nelder = number(a[1]), number(a[2]), number(a[3]), number(a[4]), integer(a[5])
		case "holdout":
			p.Holdout = integer(a[1])
		case "effect_width":
			p.EffectWidth = number(a[1])
		case "outlier":
			p.Outlier = number(a[1])
		case "death_lag":
			p.DeathLag = integer(a[1])
		case "milestones":
			for _, s := range a[1:] {
				p.Milestones = append(p.Milestones, integer(s))
			}
		case "generation":
			p.Generation = integer(a[1])
		case "horizon":
			p.Horizon = integer(a[1])
		case "threshold":
			p.Threshold = number(a[1])
		case "scenario":
			p.Scenarios = append(p.Scenarios, Scenario{a[1], number(a[2])})
		case "contact_change":
			p.Changes = append(p.Changes, ContactChange{a[1], a[2], number(a[3])})
		}
	}
	return d
}
func writeLines(name string, a []string) {
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	if e := os.WriteFile("output/"+name, []byte(strings.Join(a, "\n")+"\n"), 0644); e != nil {
		panic(e)
	}
}
