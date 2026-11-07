package main

import "strings"

type Stop struct {
	kind                                                            string
	section                                                         *Section
	dwell, scheduledArrival, scheduledDeparture, arrival, departure int
}
type Train struct {
	name                                         string
	symbol                                       byte
	length, acceleration, deceleration, maxSpeed int
	entry                                        *Boundary
	scheduledEntry,
	entrySpeed, actualEntry int
	stops                     []*Stop
	exit                      *Boundary
	scheduledExit, actualExit int
	state, direction          string
	path                      []PathSection
	head,
	speed, nextStop int
	dwelling           bool
	awaitDeparture     *Stop
	emergency, crossed bool
	boundaryCoordinate int
	distance,
	recordedMax, standing, passes int
}
type PathSection struct {
	section *Section
	start   int
}
type TrainRequest struct {
	train *Train
	route *Route
	time  int
}

func readTrains(layout *Layout, interlocking *Interlocking) ([]*Train, []TrainRequest) {
	var trains []*Train
	var requests []TrainRequest
	byName := map[string]*Train{}
	for _, line := range readLines("input/trains.txt") {
		a := strings.Fields(line)
		if a[0] == "TRAIN" {
			t := &Train{name: a[1],
				symbol: byte('a' + len(trains)), length: number(a[2]), acceleration: number(a[3]), deceleration: number(a[4]),
				maxSpeed: number(a[5]), entry: layout.boundaryByName[a[6]], scheduledEntry: number(a[7]), entrySpeed: number(a[8]),
				actualEntry: -1, actualExit: -1, state: "WAITING"}
			trains = append(trains, t)
			byName[t.name] = t
			continue
		}
		train := byName[a[1]]
		switch a[0] {
		case "REQUEST":
			requests = append(requests,
				TrainRequest{train, interlocking.byName[a[2]], number(a[3])})
		case "STOP", "TURN":
			train.stops = append(train.stops,
				&Stop{kind: a[0], section: layout.sectionByName[a[2]], dwell: number(a[3]), scheduledArrival: number(a[4]),
					scheduledDeparture: number(a[5]), arrival: -1, departure: -1})
		case "EXIT":
			train.exit = layout.boundaryByName[a[2]]
			train.scheduledExit = number(a[3])
		}
	}
	return trains,
		requests
}
func brakingDistance(u, b int) int { n := u / b; return n*u - b*n*(n+1)/2 }
func selectSpeed(train *Train, distance int) int {
	lo := max(train.speed-train.deceleration, 0)
	if train.emergency {
		return lo
	}
	for u := min(train.speed+train.acceleration,
		train.maxSpeed); u >= lo; u-- {
		if distance < 0 || u+brakingDistance(u, train.deceleration) <= distance {
			return u
		}
	}
	return lo
}
func (t *Train) headSection() PathSection {
	out := t.path[0]
	for _, section := range t.path {
		if section.start < t.head {
			out = section
		}
	}
	return out
}
func (t *Train) occupiedSections() []PathSection {
	var out []PathSection
	for _, section := range t.path {
		if section.start < t.head && section.start+section.section.length > t.head-t.length {
			out = append(out,
				section)
		}
	}
	return out
}
func (t *Train) stop() *Stop {
	if t.nextStop >= len(t.stops) {
		return nil
	}
	return t.stops[t.nextStop]
}
