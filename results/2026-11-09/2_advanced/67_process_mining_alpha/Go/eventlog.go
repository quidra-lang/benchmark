package main

import (
	"os"
	"sort"
	"strconv"
	"strings"
)

type Event struct {
	Case, Activity, Timestamp, Resource string
	Time, Line                          int
}
type Case struct {
	ID                string
	Events            []Event
	Trace             []string
	Duration, Variant int
}

func must(e error) {
	if e != nil {
		panic(e)
	}
}
func readText(path string) string { b, e := os.ReadFile(path); must(e); return string(b) }
func integer(s string) int        { v, e := strconv.Atoi(s); must(e); return v }
func inputRows() ([]string, map[string]string) {
	lines := strings.Split(strings.TrimSpace(readText("input/eventlog.csv")),
		"\n")
	params := map[string]string{}
	for _, line := range strings.Split(strings.TrimSpace(readText("input/params.txt")),
		"\n") {
		a := strings.Fields(line)
		params[a[0]] = a[1]
	}
	return lines[1:], params
}
func timestamp(s string) (int, bool) {
	month, day, hour, minute := integer(s[5:7]), integer(s[8:10]), integer(s[11:13]),
		integer(s[14:16])
	days := []int{31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
	if month < 1 || month > 12 || day < 1 || day > days[month-1] || hour > 23 || minute > 59 {
		return 0,
			false
	}
	d := day - 1
	for m := 0; m < month-1; m++ {
		d += days[m]
	}
	return (d*24+hour)*60 + minute, true
}
func groupCases(events []Event) []*Case {
	m := map[string]*Case{}
	for _, e := range events {
		if m[e.Case] == nil {
			m[e.Case] = &Case{ID: e.Case}
		}
		m[e.Case].Events = append(m[e.Case].Events,
			e)
	}
	var cases []*Case
	for _, c := range m {
		sort.Slice(c.Events, func(i, j int) bool {
			a, b := c.Events[i],
				c.Events[j]
			return a.Time < b.Time || a.Time == b.Time && a.Line < b.Line
		})
		for _, e := range c.Events {
			c.Trace = append(c.Trace,
				e.Activity)
		}
		c.Duration = c.Events[len(c.Events)-1].Time - c.Events[0].Time
		cases = append(cases, c)
	}
	sort.Slice(cases,
		func(i, j int) bool { return cases[i].ID < cases[j].ID })
	return cases
}
func median(a []int) Ratio {
	a = append([]int(nil), a...)
	sort.Ints(a)
	n := len(a)
	if n%2 == 1 {
		return ratio(a[n/2], 1)
	}
	return ratio(a[n/2-1]+a[n/2], 2)
}
