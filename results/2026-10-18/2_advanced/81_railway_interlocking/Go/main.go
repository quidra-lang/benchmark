package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

type Event struct {
	time int
	kind string
	args []string
}
type Request struct {
	number, time int
	route        *Route
	lastReason   string
}
type Simulator struct {
	layout        *Layout
	interlocking  *Interlocking
	trains        []*Train
	trainRequests []TrainRequest
	events        []Event
	queue         []*Request
	time,
	end, throwTime, overlapTime int
	snapshotsAt    map[int]bool
	log, snapshots []string
	safety         Safety
	requestCount,
	granted, dropped int
}

func number(s string) int { v, _ := strconv.Atoi(s); return v }
func readLines(path string) []string {
	data, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	if len(data) == 0 {
		return nil
	}
	return strings.Split(strings.TrimSuffix(string(data),
		"\n"), "\n")
}
func (s *Simulator) write(format string, a ...any) {
	s.log = append(s.log, strconv.Itoa(s.time)+" "+fmt.Sprintf(format, a...))
}
func (s *Simulator) throw(p *Point, target string) {
	p.moving = true
	p.target = target
	p.completion = s.time + s.throwTime
	s.write("MOVE %s %s until %d",
		p.name, target, p.completion)
}
func (s *Simulator) addRequest(route *Route, requester string) {
	s.requestCount++
	route.requests++
	s.queue = append(s.queue,
		&Request{number: s.requestCount, time: s.time, route: route})
	s.write("REQUEST q%d %s %s", s.requestCount,
		route.name, requester)
}
func (s *Simulator) cancel(route *Route) {
	var remaining []*Request
	found := false
	for _, request := range s.queue {
		if request.route == route {
			found = true
			s.dropped++
			s.write("DROP q%d %s",
				request.number, route.name)
		} else {
			remaining = append(remaining, request)
		}
	}
	if found {
		s.queue = remaining
		return
	}
	if route.state == "LOCKED" {
		route.cancels++
		if route.start.aspect != "RED" && route.start.section.occupied() {
			route.state = "APPROACH"
			route.releaseTime = s.time + route.approach
			s.write("CANCEL %s approach until %d",
				route.name, route.releaseTime)
		} else {
			s.interlocking.release(route)
			s.write("CANCEL %s released",
				route.name)
		}
	} else if route.state == "" {
		s.write("CANCEL %s none", route.name)
	} else {
		s.write("CANCEL %s refused",
			route.name)
	}
}
func (s *Simulator) event(e Event) {
	a := e.args
	switch e.kind {
	case "REQUEST":
		s.addRequest(s.interlocking.byName[a[0]],
			"OPERATOR")
	case "CANCEL":
		s.cancel(s.interlocking.byName[a[0]])
	case "THROW":
		p := s.layout.pointByName[a[0]]
		target := a[1]
		result := "start"
		switch {
		case len(p.locks) > 0:
			result = "locked"
		case p.failed:
			result = "failed"
		case p.moving:
			result = "moving"
		case p.common.occupied():
			result = "occupied"
		case p.position == target:
			result = "none"
		}
		s.write("THROW %s %s %s",
			p.name, target, result)
		if result == "start" {
			s.throw(p, target)
		}
	case "TCFAIL", "TCFIX":
		section := s.layout.sectionByName[a[0]]
		section.failed = e.kind == "TCFAIL"
		s.write("%s %s",
			e.kind, section.name)
	case "POINTFAIL":
		p := s.layout.pointByName[a[0]]
		p.failed = true
		if p.moving {
			p.completion = -1
		}
		s.write("POINTFAIL %s",
			p.name)
	case "POINTFIX":
		p := s.layout.pointByName[a[0]]
		p.failed = false
		s.write("POINTFIX %s", p.name)
		if p.moving {
			p.completion = s.time + s.throwTime
			s.write("MOVE %s %s until %d",
				p.name, p.target, p.completion)
		}
	}
}
func (s *Simulator) reason(route *Route) string {
	if route.state != "" {
		return "busy"
	}
	for _, other := range route.conflicts {
		if other.state == "LOCKED" || other.state == "APPROACH" {
			return "conflict " + other.name
		}
	}
	oppositeOverlap := func(section *Section) bool {
		for other := range section.overlaps {
			if other.direction != route.direction {
				return true
			}
		}
		return false
	}
	for _, section := range route.sections {
		if section.occupied() {
			return "occupied " + section.name
		}
		if section.route != nil || oppositeOverlap(section) {
			return "locked " + section.name
		}
	}
	for _, section := range route.overlap {
		if section.occupied() {
			return "occupied " + section.name
		}
		if section.route != nil && section.route.direction != route.direction || oppositeOverlap(section) {
			return "locked " + section.name
		}
	}
	for _, requirement := range route.requirements() {
		p, target := requirement.point, requirement.position
		for _, lock := range p.locks {
			if lock.position != target {
				return "point " + p.name + " locked"
			}
		}
		if !p.moving && p.position == target || p.moving && p.target == target {
			continue
		}
		switch {
		case p.failed:
			return "point " + p.name + " failed"
		case p.moving:
			return "point " + p.name + " moving"
		case p.common.occupied():
			return "point " + p.name + " occupied"
		}
	}
	return ""
}
func (s *Simulator) requests() {
	var remaining []*Request
	for _, request := range s.queue {
		route := request.route
		reason := s.reason(route)
		if reason != "" {
			if reason != request.lastReason {
				s.write("WAIT q%d %s %s",
					request.number, route.name, reason)
				request.lastReason = reason
			}
			remaining = append(remaining, request)
			continue
		}
		s.interlocking.lock(route)
		wait := s.time - request.time
		route.grants++
		route.wait += wait
		route.maxwait = max(route.maxwait,
			wait)
		s.granted++
		s.write("GRANT q%d %s wait %d", request.number, route.name, wait)
		for _, requirement := range route.requirements() {
			p := requirement.point
			if !p.moving && p.position != requirement.position {
				s.throw(p,
					requirement.position)
			}
		}
	}
	s.queue = remaining
}
func (s *Simulator) limit(train *Train) int {
	if train.crossed {
		return -1
	}
	head := train.headSection()
	section := head.section
	distance := head.start + section.length - train.head
	for {
		signal := s.layout.signalAt[section.name+":"+train.direction]
		if signal != nil && signal.aspect == "RED" {
			return distance
		}
		if stop := train.stop(); stop != nil && stop.section == section {
			return distance
		}
		next := s.layout.beyond(section,
			train.direction)
		switch next.kind {
		case "boundary":
			return -1
		case "buffer", "impassable":
			return distance
		case "section":
			section = next.section
			distance += section.length
		}
	}
}
func (s *Simulator) pass(train *Train, signal *Signal) {
	var route *Route
	for _, r := range s.interlocking.routes {
		if r.start == signal && (r.state == "LOCKED" || r.state == "APPROACH") {
			route = r
			break
		}
	}
	name := "-"
	if route != nil {
		name = route.name
	}
	s.write("PASS %s %s %s %s",
		train.name, signal.name, signal.aspect, name)
	signal.passes++
	train.passes++
	if route != nil {
		route.state = "USED"
		route.uses++
	}
	s.safety.signalPassing(s.time,
		train, signal)
	if signal.aspect == "RED" {
		s.write("SPAD %s %s", train.name, signal.name)
		train.emergency = true
	}
}
func (s *Simulator) runTrain(train *Train, entered map[*Boundary]bool) {
	if train.state == "EXITED" {
		return
	}
	if train.state == "WAITING" {
		if s.time < train.scheduledEntry || train.entry.section.occupied() || entered[train.entry] {
			return
		}
		entered[train.entry] = true
		train.state = "RUNNING"
		train.direction = "UP"
		if train.entry.end == "R" {
			train.direction = "DOWN"
		}
		train.path = []PathSection{{train.entry.section,
			0}}
		train.head = 0
		train.speed = train.entrySpeed
		train.actualEntry = s.time
		s.write("ENTER %s %s",
			train.name, train.entry.name)
	}
	if train.dwelling {
		stop := train.stop()
		if s.time < stop.arrival+stop.dwell || s.time < stop.scheduledDeparture {
			return
		}
		train.dwelling = false
		train.awaitDeparture = stop
		train.nextStop++
		if stop.kind == "TURN" {
			head := train.headSection()
			end := head.start + head.section.length
			occupied := train.occupiedSections()
			path := make([]PathSection,
				len(occupied))
			for i, section := range occupied {
				path[len(path)-1-i] = PathSection{section.section,
					end - (section.start + section.section.length)}
			}
			train.path = path
			train.head = end - (train.head - train.length)
			if train.direction == "UP" {
				train.direction = "DOWN"
			} else {
				train.direction = "UP"
			}
			s.write("REVERSE %s %s",
				train.name, stop.section.name)
		}
	}
	oldSpeed := train.speed
	speed := selectSpeed(train, s.limit(train))
	remaining := speed
	current := train.headSection()
	for remaining > 0 {
		if train.crossed {
			train.head += remaining
			break
		}
		end := current.start + current.section.length
		if train.head+remaining <= end {
			train.head += remaining
			break
		}
		remaining -= end - train.head
		train.head = end
		if signal := s.layout.signalAt[current.section.name+":"+train.direction]; signal != nil {
			s.pass(train,
				signal)
		}
		if stop := train.awaitDeparture; stop != nil && stop.section == current.section {
			stop.departure = s.time
			train.awaitDeparture = nil
			s.write("DEPART %s %s",
				train.name, stop.section.name)
		}
		next := s.layout.beyond(current.section, train.direction)
		if next.kind == "boundary" {
			train.crossed = true
			train.boundaryCoordinate = end
		} else if next.kind == "section" {
			current = PathSection{next.section,
				end}
			train.path = append(train.path, current)
		} else {
			panic("impassable movement")
		}
	}
	train.speed = speed
	train.distance += speed
	train.recordedMax = max(train.recordedMax,
		speed)
	if speed == 0 {
		train.emergency = false
	}
	arrived := false
	if stop := train.stop(); stop != nil && speed == 0 {
		head := train.headSection()
		if head.section == stop.section && train.head == head.start+head.section.length {
			train.dwelling = true
			stop.arrival = s.time
			arrived = true
			s.write("ARRIVE %s %s",
				train.name, stop.section.name)
		}
	}
	if speed == 0 && !arrived {
		train.standing++
		if oldSpeed > 0 {
			s.write("HOLD %s %s",
				train.name, train.headSection().section.name)
		}
	}
	if train.crossed && train.head-train.length >= train.boundaryCoordinate {
		train.state = "EXITED"
		train.actualExit = s.time
		s.write("EXIT %s %s",
			train.name, train.exit.name)
	}
}
func (s *Simulator) occupancy() {
	for _, section := range s.layout.sections {
		section.occupants = nil
	}
	for _, train := range s.trains {
		if train.state != "RUNNING" {
			continue
		}
		for _, part := range train.occupiedSections() {
			part.section.occupants = append(part.section.occupants,
				train)
		}
	}
}
func (s *Simulator) sectionalRelease() {
	for _, route := range s.interlocking.routes {
		if route.state != "USED" {
			continue
		}
		for _, section := range route.sections {
			if section.route == route && section.occupied() {
				route.passed[section] = true
			}
		}
		for _, section := range route.sections {
			if section.route != route {
				continue
			}
			if !route.passed[section] || section.occupied() {
				break
			}
			s.interlocking.unlockSection(route,
				section)
			s.write("RELEASE %s %s", route.name, section.name)
		}
		remaining := false
		for _, section := range route.sections {
			if section.route == route {
				remaining = true
				break
			}
		}
		if !remaining {
			s.interlocking.release(route)
			s.write("DONE %s",
				route.name)
		} else if len(route.overlap) > 0 && route.overlapLocked {
			if route.sections[len(route.sections)-1].occupied() {
				route.overlapCounter++
			} else {
				route.overlapCounter = 0
			}
			if route.overlapCounter >= s.overlapTime {
				s.interlocking.unlockOverlap(route)
				s.write("OVERLAP %s",
					route.name)
			}
		}
	}
}
func (s *Simulator) statistics() {
	for _, route := range s.interlocking.routes {
		if route.state != "" {
			route.lockedTicks++
		}
	}
	for _, point := range s.layout.points {
		if len(point.locks) > 0 {
			point.lockedTicks++
		}
		if point.moving {
			point.movingTicks++
		}
	}
	for _, section := range s.layout.sections {
		if section.occupied() {
			section.occupiedTicks++
		}
		if section.route != nil || len(section.overlaps) > 0 {
			section.lockedTicks++
		}
		for _, train := range section.occupants {
			section.trains[train] = true
		}
	}
	for _, signal := range s.layout.signals {
		switch signal.aspect {
		case "RED":
			signal.red++
		case "YELLOW":
			signal.yellow++
		case "GREEN":
			signal.green++
		}
	}
}
func (s *Simulator) snapshot() {
	l := s.layout
	grid := make([][]byte, l.height)
	for row := range grid {
		grid[row] = []byte(strings.Repeat(" ",
			l.width))
	}
	for _, label := range l.labels {
		copy(grid[label.row][label.col:], []byte(label.text))
	}
	for _, section := range l.sections {
		character := byte('-')
		if section.failed {
			character = '#'
		} else if section.route != nil {
			character = '='
		} else if len(section.overlaps) > 0 {
			character = '~'
		}
		for col := section.first; col <= section.last; col++ {
			grid[section.row][col] = character
		}
	}
	for _, train := range s.trains {
		if train.state != "RUNNING" {
			continue
		}
		for _, part := range train.occupiedSections() {
			section := part.section
			lo,
				hi := max(train.head-train.length, part.start), min(train.head, part.start+section.length)
			p, q := lo-part.start,
				hi-part.start
			if train.direction == "DOWN" {
				p, q = section.length-(hi-part.start), section.length-(lo-part.start)
			}
			width := section.last - section.first + 1
			for j := 0; j < width; j++ {
				if p*width < (j+1)*section.length && q*width > j*section.length {
					old := grid[section.row][section.first+j]
					character := train.symbol
					if old >= 'a' && old <= 'z' || old == '*' {
						character = '*'
					}
					grid[section.row][section.first+j] = character
				}
			}
		}
	}
	for _, buffer := range l.buffers {
		grid[buffer.row][buffer.col] = '|'
	}
	for _, point := range l.points {
		character := byte('?')
		if point.detected() {
			character = point.position[0]
		}
		grid[point.row][point.col] = character
	}
	for _, signal := range l.signals {
		character := byte('X')
		if signal.aspect == "YELLOW" {
			character = 'Y'
		} else if signal.aspect == "GREEN" {
			character = 'G'
		}
		grid[signal.row][signal.col] = character
	}
	s.snapshots = append(s.snapshots,
		fmt.Sprintf("SNAPSHOT %d", s.time))
	for _, row := range grid {
		s.snapshots = append(s.snapshots, strings.TrimRight(string(row),
			" "))
	}
	for _, train := range s.trains {
		if train.state != "RUNNING" {
			continue
		}
		var names []string
		for _, part := range train.occupiedSections() {
			names = append(names, part.section.name)
		}
		s.snapshots = append(s.snapshots,
			fmt.Sprintf("TRAIN %c %s %s %d %s", train.symbol, train.name, train.direction, train.speed, strings.Join(names,
				",")))
	}
	var routes []string
	for _, route := range s.interlocking.routes {
		if route.state != "" {
			routes = append(routes,
				route.name+"/"+route.state)
		}
	}
	if len(routes) == 0 {
		routes = append(routes, "-")
	}
	s.snapshots = append(s.snapshots,
		"ROUTES "+strings.Join(routes, " "))
}
func (s *Simulator) run() {
	event := 0
	for t := 0; t <= s.end; t++ {
		s.time = t
		for _, point := range s.layout.points {
			if point.moving && point.completion == t {
				point.position = point.target
				point.moving = false
				point.throws++
				s.write("POINT %s %s",
					point.name, point.position)
			}
		}
		for _, route := range s.interlocking.routes {
			if route.state == "APPROACH" && route.releaseTime == t {
				s.interlocking.release(route)
				s.write("TIMEOUT %s",
					route.name)
			}
		}
		for _, request := range s.trainRequests {
			if request.time == t {
				s.addRequest(request.route,
					request.train.name)
			}
		}
		for event < len(s.events) && s.events[event].time == t {
			s.event(s.events[event])
			event++
		}
		s.requests()
		aspects := signalAspects(s.layout,
			s.interlocking.routes)
		for _, signal := range s.layout.signals {
			if aspects[signal] != signal.aspect {
				signal.aspect = aspects[signal]
				s.write("SIGNAL %s %s",
					signal.name, signal.aspect)
			}
		}
		entered := map[*Boundary]bool{}
		for _, train := range s.trains {
			s.runTrain(train,
				entered)
		}
		s.occupancy()
		s.sectionalRelease()
		s.safety.check(t, s.layout, s.interlocking.routes)
		s.statistics()
		if s.snapshotsAt[t] {
			s.snapshot()
		}
	}
}
func (s *Simulator) reports() ([]string, []string) {
	csv := []string{"train,location,scheduled,actual,delay"}
	onTime,
		late, missing, totalDelay, maxDelay := 0, 0, 0, 0, 0
	add := func(name, location string, scheduled, actual int) {
		if actual < 0 {
			missing++
			csv = append(csv,
				fmt.Sprintf("%s,%s,%d,-,-", name, location, scheduled))
			return
		}
		delay := actual - scheduled
		if delay <= 0 {
			onTime++
		} else {
			late++
			totalDelay += delay
			maxDelay = max(maxDelay,
				delay)
		}
		csv = append(csv, fmt.Sprintf("%s,%s,%d,%d,%d", name, location, scheduled, actual, delay))
	}
	for _, train := range s.trains {
		add(train.name, "enter:"+train.entry.name, train.scheduledEntry, train.actualEntry)
		for _, stop := range train.stops {
			add(train.name, "arr:"+stop.section.name, stop.scheduledArrival, stop.arrival)
			add(train.name,
				"dep:"+stop.section.name, stop.scheduledDeparture, stop.departure)
		}
		add(train.name, "exit:"+train.exit.name,
			train.scheduledExit, train.actualExit)
	}
	var out []string
	for _, route := range s.interlocking.routes {
		out = append(out,
			fmt.Sprintf("ROUTE %s %s-%s requests %d grants %d uses %d cancels %d wait %d maxwait %d locked %d",
				route.name, route.start.name, route.finish, route.requests, route.grants, route.uses, route.cancels,
				route.wait, route.maxwait, route.lockedTicks))
	}
	for _, point := range s.layout.points {
		position := "?"
		if point.detected() {
			position = point.position
		}
		out = append(out,
			fmt.Sprintf("POINT %s throws %d locked %d moving %d final %s", point.name, point.throws, point.lockedTicks,
				point.movingTicks, position))
	}
	for _, section := range s.layout.sections {
		out = append(out, fmt.Sprintf("SECTION %s occupied %d locked %d trains %d",
			section.name, section.occupiedTicks, section.lockedTicks, len(section.trains)))
	}
	for _, signal := range s.layout.signals {
		out = append(out,
			fmt.Sprintf("SIGNAL %s red %d yellow %d green %d passes %d", signal.name, signal.red, signal.yellow,
				signal.green, signal.passes))
	}
	exited, running, waiting := 0, 0, 0
	for _, train := range s.trains {
		out = append(out,
			fmt.Sprintf("TRAIN %s %c %s distance %d maxspeed %d standing %d passes %d", train.name, train.symbol,
				train.state, train.distance, train.recordedMax, train.standing, train.passes))
		switch train.state {
		case "EXITED":
			exited++
		case "RUNNING":
			running++
		default:
			waiting++
		}
	}
	out = append(out,
		fmt.Sprintf("TRAINS total %d exited %d running %d waiting %d", len(s.trains), exited, running, waiting),
		fmt.Sprintf("PUNCTUALITY on_time %d late %d missing %d total_delay %d max_delay %d", onTime, late,
			missing, totalDelay, maxDelay), fmt.Sprintf("REQUESTS total %d granted %d dropped %d pending %d",
			s.requestCount, s.granted, s.dropped, len(s.queue)))
	return csv, out
}
func writeLines(name string, lines []string) {
	text := ""
	if len(lines) > 0 {
		text = strings.Join(lines, "\n") + "\n"
	}
	if err := os.WriteFile("output/"+name,
		[]byte(text), 0644); err != nil {
		panic(err)
	}
}
func main() {
	layout := readLayout()
	interlocking := readInterlocking(layout)
	trains, requests := readTrains(layout,
		interlocking)
	p := readLines("input/params.txt")
	s := &Simulator{layout: layout, interlocking: interlocking,
		trains: trains, trainRequests: requests, end: number(strings.Fields(p[0])[1]), throwTime: number(strings.Fields(p[1])[1]),
		overlapTime: number(strings.Fields(p[2])[1]), snapshotsAt: map[int]bool{}}
	for _, time := range strings.Fields(p[3])[1:] {
		s.snapshotsAt[number(time)] = true
	}
	for _, line := range readLines("input/events.txt") {
		a := strings.Fields(line)
		s.events = append(s.events, Event{number(a[0]),
			a[1], a[2:]})
	}
	s.run()
	csv, summary := s.reports()
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	writeLines("events.txt",
		s.log)
	writeLines("snapshots.txt", s.snapshots)
	writeLines("train_log.csv", csv)
	writeLines("safety.txt",
		s.safety.lines())
	writeLines("summary.txt", summary)
}
