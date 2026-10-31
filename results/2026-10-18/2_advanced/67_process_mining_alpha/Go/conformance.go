package main

import "strings"

type Net struct {
	Places, Transitions  []string
	In, Out              map[string][]int
	Initial, Final, Arcs int
}
type PlaceReplay struct {
	Missing, Remaining, Deviating int
	Waits                         []int
	Routes                        map[string]int
}
type Replay struct {
	Missing, Remaining, Consumed, Produced, Skipped, Fitting int
	Places                                                   []PlaceReplay
}

func newNet(places, transitions []string, initial, final int) Net {
	n := Net{Places: places, Transitions: transitions,
		In: map[string][]int{}, Out: map[string][]int{}, Initial: initial, Final: final}
	for _, t := range transitions {
		n.In[t] = nil
		n.Out[t] = nil
	}
	return n
}
func readModel() Net {
	var places, transitions []string
	var arcs [][2]string
	initial, final := "", ""
	for _, line := range strings.Split(strings.TrimSpace(readText("input/model.txt")), "\n") {
		a := strings.Fields(line)
		switch a[0] {
		case "PLACE":
			places = append(places,
				a[1])
		case "TRANSITION":
			transitions = append(transitions, a[1])
		case "ARC":
			arcs = append(arcs, [2]string{a[1],
				a[2]})
		case "INITIAL":
			initial = a[1]
		case "FINAL":
			final = a[1]
		}
	}
	sortNames(transitions)
	index := map[string]int{}
	for i, p := range places {
		index[p] = i
	}
	n := newNet(places, transitions, index[initial], index[final])
	for _, a := range arcs {
		if p, ok := index[a[0]]; ok {
			n.In[a[1]] = append(n.In[a[1]], p)
		} else {
			n.Out[a[0]] = append(n.Out[a[0]],
				index[a[1]])
		}
		n.Arcs++
	}
	for _, t := range transitions {
		sortInts(n.In[t])
		sortInts(n.Out[t])
	}
	return n
}
func (n Net) enabled(mark []int, t string) bool {
	for _, p := range n.In[t] {
		if mark[p] == 0 {
			return false
		}
	}
	return true
}
func (n Net) fire(mark []int, t string) []int {
	a := append([]int(nil), mark...)
	for _, p := range n.In[t] {
		a[p]--
	}
	for _, p := range n.Out[t] {
		a[p]++
	}
	return a
}
func replayRecord(n Net) Replay {
	r := Replay{Places: make([]PlaceReplay, len(n.Places))}
	for i := range r.Places {
		r.Places[i].Routes = map[string]int{}
	}
	return r
}
func (r Replay) fitness() Ratio {
	c, p := int64(r.Consumed), int64(r.Produced)
	return newRatio(2*c*p-int64(r.Missing)*p-int64(r.Remaining)*c, 2*c*p)
}
