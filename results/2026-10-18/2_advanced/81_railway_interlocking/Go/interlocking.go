package main

import "strings"

type Requirement struct {
	point    *Point
	position string
}
type Route struct {
	name, finish, direction, state string
	start                          *Signal
	points, flank                  []Requirement
	sections,
	overlap []*Section
	conflictNames                         []string
	conflicts                             []*Route
	approach, releaseTime, overlapCounter int
	overlapLocked                         bool
	passed                                map[*Section]bool
	requests,
	grants, uses, cancels, wait, maxwait, lockedTicks int
}
type Interlocking struct {
	layout *Layout
	routes []*Route
	byName map[string]*Route
}

func list(s string) []string {
	if s == "-" {
		return nil
	}
	return strings.Split(s, ",")
}
func readInterlocking(layout *Layout) *Interlocking {
	i := &Interlocking{layout: layout, byName: map[string]*Route{}}
	requirements := func(text string) []Requirement {
		var out []Requirement
		for _, s := range list(text) {
			a := strings.Split(s, ":")
			out = append(out, Requirement{layout.pointByName[a[0]],
				a[1]})
		}
		return out
	}
	for _, line := range readLines("input/routes.txt") {
		a := strings.Fields(line)
		r := &Route{name: a[1],
			start: layout.signalByName[a[2]], finish: a[3], points: requirements(a[4]), flank: requirements(a[7]),
			conflictNames: list(a[8]), approach: number(a[9]), releaseTime: -1, passed: map[*Section]bool{}}
		r.direction = r.start.direction
		for _, s := range list(a[5]) {
			r.sections = append(r.sections, layout.sectionByName[s])
		}
		for _, s := range list(a[6]) {
			r.overlap = append(r.overlap,
				layout.sectionByName[s])
		}
		i.routes = append(i.routes, r)
		i.byName[r.name] = r
	}
	for _, r := range i.routes {
		for _, name := range r.conflictNames {
			r.conflicts = append(r.conflicts, i.byName[name])
		}
	}
	return i
}
func (r *Route) requirements() []Requirement {
	return append(append([]Requirement(nil), r.points...), r.flank...)
}
func removePointLocks(point *Point, route *Route) {
	out := point.locks[:0]
	for _, lock := range point.locks {
		if lock.route != route {
			out = append(out, lock)
		}
	}
	point.locks = out
}
func (i *Interlocking) lock(r *Route) {
	r.state = "LOCKED"
	r.passed = map[*Section]bool{}
	for _, s := range r.sections {
		s.route = r
	}
	for _, s := range r.overlap {
		s.overlaps[r] = true
	}
	for _, requirement := range r.requirements() {
		requirement.point.locks = append(requirement.point.locks,
			PointLock{r, requirement.position})
	}
	r.overlapLocked = true
	r.overlapCounter = 0
	r.releaseTime = -1
}
func (i *Interlocking) unlockSection(r *Route, s *Section) {
	if s.route == r {
		s.route = nil
	}
	for _, point := range i.layout.points {
		if point.common == s {
			removePointLocks(point,
				r)
		}
	}
}
func (i *Interlocking) unlockOverlap(r *Route) {
	for _, s := range r.overlap {
		delete(s.overlaps, r)
		for _, point := range i.layout.points {
			if point.common == s {
				removePointLocks(point, r)
			}
		}
	}
	r.overlapLocked = false
}
func (i *Interlocking) release(r *Route) {
	for _, s := range r.sections {
		if s.route == r {
			s.route = nil
		}
	}
	if r.overlapLocked {
		i.unlockOverlap(r)
	}
	for _, point := range i.layout.points {
		removePointLocks(point, r)
	}
	r.state = ""
}
