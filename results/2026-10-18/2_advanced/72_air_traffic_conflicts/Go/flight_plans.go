package main

import (
	"os"
	"sort"
	"strconv"
	"strings"
)

type AircraftType struct {
	Name                     string
	Climb, Descent, MinSpeed int
}
type Waypoint struct {
	X, Y, Level int
	HasLevel    bool
}
type Plan struct {
	Callsign                                                    string
	Type, Departure, Level, OriginalSpeed, Speed, Delay, Offset int
	Waypoints                                                   []Waypoint
}
type Sector struct {
	Name                                   string
	X1, Y1, X2, Y2, Lower, Upper, Capacity int
}
type Settings struct {
	DH, DV, Lookahead, MaxDelay, MinLevel, MaxLevel, Ta, Tb int
	Radar                                                   [6]int
	Snapshots                                               []int
	Leader, Alert                                           int
}
type Input struct {
	Plans    []Plan
	Types    []AircraftType
	Sectors  []Sector
	Settings Settings
}

func must(e error) {
	if e != nil {
		panic(e)
	}
}
func text(path string) string { b, e := os.ReadFile(path); must(e); return string(b) }
func integer(s string) int    { n, e := strconv.Atoi(s); must(e); return n }
func readInput() Input {
	var in Input
	types := map[string]int{}
	for _, line := range strings.Split(strings.TrimSpace(text("input/aircraft.txt")),
		"\n") {
		a := strings.Fields(line)
		types[a[0]] = len(in.Types)
		in.Types = append(in.Types, AircraftType{a[0],
			integer(a[1]), integer(a[2]), integer(a[3])})
	}
	for _, line := range strings.Split(strings.TrimSpace(text("input/flights.csv")),
		"\n")[1:] {
		a := strings.Split(line, ",")
		p := Plan{Callsign: a[0], Type: types[a[1]], Departure: integer(a[2]),
			Level: integer(a[3]), OriginalSpeed: integer(a[4]), Speed: integer(a[4])}
		for _, wp := range strings.Fields(a[5]) {
			b := strings.Split(wp,
				":")
			w := Waypoint{X: integer(b[0]), Y: integer(b[1])}
			if len(b) == 3 {
				w.Level, w.HasLevel = integer(b[2]),
					true
			}
			p.Waypoints = append(p.Waypoints, w)
		}
		in.Plans = append(in.Plans, p)
	}
	sort.Slice(in.Plans, func(i,
		j int) bool {
		return in.Plans[i].Callsign < in.Plans[j].Callsign
	})
	for _, line := range strings.Split(strings.TrimSpace(text("input/sectors.txt")),
		"\n") {
		a := strings.Fields(line)
		in.Sectors = append(in.Sectors, Sector{a[0], integer(a[1]), integer(a[2]),
			integer(a[3]), integer(a[4]), integer(a[5]), integer(a[6]), integer(a[7])})
	}
	p := &in.Settings
	for _, line := range strings.Split(strings.TrimSpace(text("input/params.txt")), "\n") {
		a := strings.Fields(line)
		switch a[0] {
		case "separation":
			p.DH,
				p.DV = integer(a[1]), integer(a[2])
		case "lookahead":
			p.Lookahead = integer(a[1])
		case "max_delay":
			p.MaxDelay = integer(a[1])
		case "levels":
			p.MinLevel,
				p.MaxLevel = integer(a[1]), integer(a[2])
		case "sampling":
			p.Ta, p.Tb = integer(a[1]), integer(a[2])
		case "radar":
			for i := range p.Radar {
				p.Radar[i] = integer(a[i+1])
			}
		case "snapshots":
			for _, s := range a[1:] {
				p.Snapshots = append(p.Snapshots, integer(s))
			}
		case "leader":
			p.Leader = integer(a[1])
		case "alert":
			p.Alert = integer(a[1])
		}
	}
	return in
}
func flightLevels(p Plan) []int {
	a := []int{p.Level + p.Offset}
	for _, w := range p.Waypoints {
		if w.HasLevel {
			a = append(a, w.Level+p.Offset)
		}
	}
	return a
}
