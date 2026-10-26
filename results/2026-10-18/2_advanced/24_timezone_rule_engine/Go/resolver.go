package main

import "sort"

type Period struct {
	Start, Offset int64
	DST           bool
	Abbreviation  string
}

func (p Period) SameState(other Period) bool {
	return p.Offset == other.Offset && p.DST == other.DST && p.Abbreviation == other.Abbreviation
}

type Timeline struct{ Periods []Period }

func (t Timeline) IndexAt(time int64) int {
	return sort.Search(len(t.Periods), func(i int) bool { return t.Periods[i].Start > time }) - 1
}
func (t Timeline) PeriodAt(time int64) Period { return t.Periods[t.IndexAt(time)] }
func (t Timeline) EndOf(index int) int64 {
	if index+1 < len(t.Periods) {
		return t.Periods[index+1].Start
	}
	return posInfinity
}
func (t Timeline) Nearby(first, last int64) []int {
	low, high := t.IndexAt(first-57600), t.IndexAt(last+57600)
	ids := []int{}
	for i := low; i <= high; i++ {
		ids = append(ids, i)
	}
	return ids
}
func (t Timeline) Candidates(local int64) []int {
	found := []int{}
	for _, index := range t.Nearby(local, local) {
		time := local - t.Periods[index].Offset
		if t.Periods[index].Start <= time && time < t.EndOf(index) {
			found = append(found, index)
		}
	}
	return found
}
func (t Timeline) SkippingTransition(local int64) int {
	for _, index := range t.Nearby(local, local) {
		if index > 0 {
			start := t.Periods[index].Start
			if start+t.Periods[index-1].Offset <= local && local < start+t.Periods[index].Offset {
				return index
			}
		}
	}
	return -1
}
