package main

import (
	"fmt"
	"strings"
)

var properties = []string{"OCCUPANCY", "POINT_MOTION", "CONFLICT", "SIGNAL_PASSING"}

type Safety struct {
	checks, violations [4]int
	records            []string
}

func (s *Safety) violation(time, property int, details string) {
	s.violations[property]++
	s.records = append(s.records,
		fmt.Sprintf("VIOLATION %d %s %s", time, properties[property], details))
}
func (s *Safety) signalPassing(time int, train *Train, signal *Signal) {
	s.checks[3]++
	if signal.aspect == "RED" {
		s.violation(time, 3, train.name+" "+signal.name)
	}
}
func (s *Safety) check(time int, layout *Layout, routes []*Route) {
	for _, section := range layout.sections {
		s.checks[0]++
		if len(section.occupants) >= 2 {
			var names []string
			for _, train := range section.occupants {
				names = append(names, train.name)
			}
			s.violation(time, 0, section.name+" "+strings.Join(names,
				","))
		}
	}
	for _, point := range layout.points {
		if !point.moving {
			continue
		}
		s.checks[1]++
		if len(point.common.occupants) > 0 {
			s.violation(time,
				1, point.name+" occupied")
		} else {
			for _, lock := range point.locks {
				if lock.route.state == "USED" || lock.route.state == "APPROACH" {
					s.violation(time,
						1, point.name+" locked")
					break
				}
			}
		}
	}
	active := func(r *Route) bool { return r.state == "LOCKED" || r.state == "APPROACH" }
	for i, a := range routes {
		if !active(a) {
			continue
		}
		for _, b := range routes[i+1:] {
			if !active(b) {
				continue
			}
			s.checks[2]++
			conflict := false
			for _, r := range a.conflicts {
				if r == b {
					conflict = true
				}
			}
			for _, r := range b.conflicts {
				if r == a {
					conflict = true
				}
			}
			if conflict {
				s.violation(time,
					2, a.name+" "+b.name)
			}
		}
	}
}
func (s *Safety) lines() []string {
	var out []string
	safe := true
	for i, name := range properties {
		verdict := "OK"
		if s.violations[i] > 0 {
			verdict = "FAIL"
			safe = false
		}
		out = append(out,
			fmt.Sprintf("%s %s checks %d violations %d", name, verdict, s.checks[i], s.violations[i]))
	}
	out = append(out,
		s.records...)
	if safe {
		out = append(out, "RESULT SAFE")
	} else {
		out = append(out, "RESULT UNSAFE")
	}
	return out
}
