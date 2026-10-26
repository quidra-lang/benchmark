package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

var policies = []string{"COST", "NEAREST", "ROUND", "ETA"}
var configKeys = []string{"FLOORS", "CARS", "CAPACITY", "DOOR", "START", "POLICY", "ZONES", "PARK", "PATIENCE", "BYPASS", "PERIOD", "LIMIT", "COMPARE"}
var argumentCounts = map[string]int{"CALL": 3, "CANCEL": 1, "OUT": 1, "IN": 1, "HOLD": 2, "FIRE": 1, "RESET": 0, "WHERE": 1, "STATUS": 0}

type Zone struct{ low, high int }
type Config struct {
	floors, cars, capacity, door int
	starts, homes                []int
	zones                        []Zone
	policy                       string
	park, patience, period       int
	bypass, limit                int
	compare                      []string
}
type InputLine struct {
	number int
	words  []string
}
type Event struct {
	time    int
	command string
	values  []int
}

func number(s string) int { n, _ := strconv.Atoi(s); return n }
func abs(n int) int {
	if n < 0 {
		return -n
	}
	return n
}
func sign(n int) int {
	if n < 0 {
		return -1
	}
	if n > 0 {
		return 1
	}
	return 0
}
func contains(items []string, value string) bool {
	for _, item := range items {
		if item == value {
			return true
		}
	}
	return false
}
func joined(items []string) string {
	if len(items) == 0 {
		return "-"
	}
	return strings.Join(items, ",")
}
func average(total, count int) string {
	if count == 0 {
		return "-"
	}
	hundredths := total * 100 / count
	return fmt.Sprintf("%d.%02d", hundredths/100, hundredths%100)
}
func remove(items []int, value int) []int {
	for i, item := range items {
		if item == value {
			return append(items[:i], items[i+1:]...)
		}
	}
	return items
}
func sortedKeys(items map[int]bool) []int {
	keys := make([]int, 0, len(items))
	for key := range items {
		keys = append(keys, key)
	}
	sort.Ints(keys)
	return keys
}
func integerList(items []int, prefix string) string {
	words := make([]string, len(items))
	for i, value := range items {
		words[i] = prefix + strconv.Itoa(value)
	}
	return joined(words)
}
func parseConfig(lines [][]string) (*Config, string) {
	entries := make(map[string][]string)
	for _, words := range lines {
		key := words[0]
		if !contains(configKeys, key) {
			return nil, "unknown key " + key
		}
		if _, exists := entries[key]; exists {
			return nil, "duplicate key " + key
		}
		entries[key] = words[1:]
	}
	for _, key := range configKeys[:5] {
		if _, exists := entries[key]; !exists {
			return nil, "missing key " + key
		}
	}
	c := &Config{policy: "COST", park: -1, patience: -1, period: -1, bypass: 100, limit: 1000}
	for _, key := range configKeys {
		words, exists := entries[key]
		if !exists {
			continue
		}
		count := 1
		if key == "START" || key == "ZONES" {
			count = c.cars
		}
		if key == "PARK" {
			count = c.cars + 1
		}
		if (key == "COMPARE" && (len(words) < 1 || len(words) > 4)) || (key != "COMPARE" && len(words) != count) {
			return nil, "wrong number of values for " + key
		}
		bad := false
		values := make([]int, len(words))
		if key != "POLICY" && key != "COMPARE" && key != "ZONES" {
			for i, word := range words {
				values[i] = number(word)
			}
		}
		within := func(n, low, high int) bool { return low <= n && n <= high }
		switch key {
		case "FLOORS":
			c.floors = values[0]
			bad = !within(c.floors, 2, 50)
		case "CARS":
			c.cars = values[0]
			bad = !within(c.cars, 1, 8)
		case "CAPACITY":
			c.capacity = values[0]
			bad = !within(c.capacity, 1, 20)
		case "DOOR":
			c.door = values[0]
			bad = !within(c.door, 1, 9)
		case "START":
			c.starts = values
			for _, floor := range values {
				if !within(floor, 1, c.floors) {
					bad = true
				}
			}
		case "POLICY":
			c.policy = words[0]
			bad = !contains(policies, c.policy)
		case "ZONES":
			for _, word := range words {
				ends := strings.Split(word, ":")
				low, high := number(ends[0]), number(ends[1])
				if !(1 <= low && low < high && high <= c.floors) {
					bad = true
				}
				c.zones = append(c.zones, Zone{low, high})
			}
		case "PARK":
			c.park, c.homes = values[0], values[1:]
			bad = !within(c.park, 0, 100)
			for _, floor := range c.homes {
				if !within(floor, 1, c.floors) {
					bad = true
				}
			}
		case "PATIENCE":
			c.patience = values[0]
			bad = !within(c.patience, 1, 1000)
		case "BYPASS":
			c.bypass = values[0]
			bad = !within(c.bypass, 50, 100)
		case "PERIOD":
			c.period = values[0]
			bad = !within(c.period, 1, 1000)
		case "LIMIT":
			c.limit = values[0]
			bad = !within(c.limit, 1, 5000)
		case "COMPARE":
			seen := make(map[string]bool)
			for _, policy := range words {
				if !contains(policies, policy) || seen[policy] {
					bad = true
				}
				seen[policy] = true
			}
			c.compare = words
		}
		if bad {
			return nil, "bad value for " + key
		}
	}
	if len(c.zones) == 0 {
		for i := 0; i < c.cars; i++ {
			c.zones = append(c.zones, Zone{1, c.floors})
		}
	}
	for i, zone := range c.zones {
		if c.starts[i] < zone.low || c.starts[i] > zone.high {
			return nil, fmt.Sprintf("car %d starts outside its zone", i+1)
		}
		if c.park >= 0 && (c.homes[i] < zone.low || c.homes[i] > zone.high) {
			return nil, fmt.Sprintf("car %d home outside its zone", i+1)
		}
	}
	return c, ""
}
func (c *Config) serves(a, b int) bool {
	for _, z := range c.zones {
		if z.low <= a && a <= z.high && z.low <= b && b <= z.high {
			return true
		}
	}
	return false
}
func optional(value int) string {
	if value < 0 {
		return "off"
	}
	return strconv.Itoa(value)
}
func (c *Config) header() []string {
	lines := []string{fmt.Sprintf("config: floors=%d cars=%d capacity=%d door=%d policy=%s park=%s patience=%s bypass=%d period=%s limit=%d compare=%s", c.floors, c.cars, c.capacity, c.door, c.policy, optional(c.park), optional(c.patience), c.bypass, optional(c.period), c.limit, joined(c.compare))}
	for i, zone := range c.zones {
		home := "-"
		if c.park >= 0 {
			home = strconv.Itoa(c.homes[i])
		}
		lines = append(lines, fmt.Sprintf("E%d: start=%d zone=%d-%d home=%s", i+1, c.starts[i], zone.low, zone.high, home))
	}
	return lines
}
func validateEvents(c *Config, lines []InputLine) ([]Event, []string) {
	var events []Event
	var errors []string
	last, groups := 0, 0
	fire := false
	out := make([]bool, c.cars+1)
	for _, line := range lines {
		w := line.words
		time, command := number(w[0]), w[1]
		args := w[2:]
		message := ""
		count, known := argumentCounts[command]
		values := make([]int, len(args))
		if !known {
			message = "unknown command " + command
		} else if len(args) != count {
			message = "wrong number of arguments for " + command
		} else if time < last {
			message = "time goes backwards"
		} else {
			for i, arg := range args {
				values[i] = number(arg)
			}
			switch command {
			case "CALL":
				a, b, n := values[0], values[1], values[2]
				if a < 1 || a > c.floors || b < 1 || b > c.floors {
					message = "bad floor"
				} else if a == b {
					message = "same floor"
				} else if n < 1 || n > 99 {
					message = "bad count"
				} else if !c.serves(a, b) {
					message = fmt.Sprintf("no car serves %d->%d", a, b)
				} else if fire {
					message = "fire service active"
				}
			case "CANCEL", "WHERE":
				if values[0] < 1 || values[0] > groups {
					message = "unknown group"
				}
			case "OUT", "IN":
				e := values[0]
				if e < 1 || e > c.cars {
					message = "bad car"
				} else if command == "OUT" && out[e] {
					message = fmt.Sprintf("car %d already out", e)
				} else if command == "IN" && !out[e] {
					message = fmt.Sprintf("car %d already in", e)
				}
			case "HOLD":
				if values[0] < 1 || values[0] > c.cars {
					message = "bad car"
				} else if values[1] < 1 || values[1] > 9 {
					message = "bad ticks"
				}
			case "FIRE":
				if values[0] < 1 || values[0] > c.floors {
					message = "bad floor"
				} else if fire {
					message = "fire already active"
				}
			case "RESET":
				if !fire {
					message = "fire not active"
				}
			}
		}
		if message != "" {
			errors = append(errors, fmt.Sprintf("line %d: %s", line.number, message))
			continue
		}
		last = time
		switch command {
		case "CALL":
			groups++
		case "OUT":
			out[values[0]] = true
		case "IN":
			out[values[0]] = false
		case "FIRE":
			fire = true
		case "RESET":
			fire = false
		}
		events = append(events, Event{time, command, values})
	}
	return events, errors
}

type Group struct {
	number, landing, destination, count, time, direction int
	waiting, car, boarded, delivered, lost               int
	lastBoard, lastAlight, waitTotal, travelTotal        int
	cars                                                 map[int]bool
}
type Passenger struct{ group, count, boarded int }
type Car struct {
	number, floor, low, high, home, direction, door, idleStart int
	inService                                                  bool
	passengers                                                 []Passenger
	calls                                                      []int
	distance, stops, boarded, busy, energy                     int
}
type Simulation struct {
	config                                                           *Config
	events                                                           []Event
	policy                                                           string
	cars                                                             []*Car
	groups                                                           []*Group
	pending                                                          []int
	fireFloor, lastRound, time                                       int
	status                                                           string
	log                                                              []string
	abandoned, evacuated, delivered, waitTotal, travelTotal, maxWait int
}

func newSimulation(c *Config, events []Event, policy string) *Simulation {
	s := &Simulation{config: c, events: events, policy: policy}
	for i, z := range c.zones {
		home := 0
		if c.park >= 0 {
			home = c.homes[i]
		}
		s.cars = append(s.cars, &Car{number: i + 1, floor: c.starts[i], low: z.low, high: z.high, home: home, inService: true})
	}
	return s
}
func (s *Simulation) emit(format string, args ...any) {
	s.log = append(s.log, strconv.Itoa(s.time)+" "+fmt.Sprintf(format, args...))
}
func (c *Car) load() int {
	total := 0
	for _, p := range c.passengers {
		total += p.count
	}
	return total
}
func (s *Simulation) targets(c *Car) map[int]bool {
	targets := make(map[int]bool)
	for _, p := range c.passengers {
		targets[s.groups[p.group-1].destination] = true
	}
	for _, id := range c.calls {
		targets[s.groups[id-1].landing] = true
	}
	return targets
}
func (s *Simulation) bypassing(c *Car) bool { return c.load()*100 >= s.config.capacity*s.config.bypass }
func (s *Simulation) cost(c *Car, g *Group) int {
	f, d, x := c.floor, c.direction, g.landing
	if s.policy == "NEAREST" || d == 0 {
		return abs(f - x)
	}
	targets := s.targets(c)
	distance, via := 0, 0
	if g.direction == d && (x-f)*d >= 0 {
		distance = abs(x - f)
		for y := range targets {
			if (y-f)*d > 0 && (x-y)*d > 0 {
				via++
			}
		}
	} else {
		turn := f
		for y := range targets {
			if (y-turn)*d > 0 {
				turn = y
			}
			if (y-f)*d > 0 {
				via++
			}
		}
		distance = abs(f-turn) + abs(turn-x)
	}
	if s.policy == "COST" {
		return distance
	}
	return distance + s.config.door*via + c.door
}
func (s *Simulation) assign(g *Group, excluded int) bool {
	var candidates []*Car
	for _, c := range s.cars {
		if c.inService && c.number != excluded && c.low <= g.landing && g.landing <= c.high && c.low <= g.destination && g.destination <= c.high {
			candidates = append(candidates, c)
		}
	}
	if len(candidates) == 0 {
		return false
	}
	chosen := candidates[0]
	if s.policy == "ROUND" {
		for _, c := range candidates {
			if c.number > s.lastRound {
				chosen = c
				break
			}
		}
		s.lastRound = chosen.number
		s.emit("E%d ASSIGN G%d", chosen.number, g.number)
	} else {
		best := s.cost(chosen, g)
		for _, c := range candidates[1:] {
			cost := s.cost(c, g)
			if cost < best {
				chosen, best = c, cost
			}
		}
		s.emit("E%d ASSIGN G%d cost=%d", chosen.number, g.number, best)
	}
	if g.car != 0 {
		old := s.cars[g.car-1]
		old.calls = remove(old.calls, g.number)
	}
	chosen.calls = append(chosen.calls, g.number)
	g.car = chosen.number
	return true
}
func (s *Simulation) dispatch(g *Group) {
	if !s.assign(g, 0) {
		s.pending = append(s.pending, g.number)
		s.emit("PENDING G%d", g.number)
	}
}
func (s *Simulation) walkAway(g *Group, word string) {
	if g.car != 0 {
		c := s.cars[g.car-1]
		c.calls = remove(c.calls, g.number)
		g.car = 0
	} else {
		s.pending = remove(s.pending, g.number)
	}
	s.emit("%s G%d x%d", word, g.number, g.waiting)
	g.lost += g.waiting
	s.abandoned += g.waiting
	g.waiting = 0
}
func (s *Simulation) execute(event Event) {
	v := event.values
	switch event.command {
	case "CALL":
		g := &Group{number: len(s.groups) + 1, landing: v[0], destination: v[1], count: v[2], time: s.time, direction: sign(v[1] - v[0]), waiting: v[2], cars: make(map[int]bool)}
		s.groups = append(s.groups, g)
		s.emit("CALL G%d %d->%d x%d", g.number, g.landing, g.destination, g.count)
		s.dispatch(g)
	case "CANCEL":
		g := s.groups[v[0]-1]
		if g.waiting > 0 {
			s.walkAway(g, "CANCEL")
		} else {
			s.emit("CANCEL G%d ignored", g.number)
		}
	case "OUT":
		c := s.cars[v[0]-1]
		c.inService = false
		s.emit("E%d OUT", c.number)
		calls := c.calls
		c.calls = nil
		for _, id := range calls {
			g := s.groups[id-1]
			g.car = 0
			s.dispatch(g)
		}
	case "IN":
		c := s.cars[v[0]-1]
		c.inService = true
		c.idleStart = s.time
		s.emit("E%d IN", c.number)
		pending := s.pending
		s.pending = nil
		for _, id := range pending {
			if !s.assign(s.groups[id-1], 0) {
				s.pending = append(s.pending, id)
			}
		}
	case "HOLD":
		c := s.cars[v[0]-1]
		if c.door > 0 {
			c.door += v[1]
			s.emit("E%d HOLD %d", c.number, c.door)
		} else {
			s.emit("E%d HOLD ignored", c.number)
		}
	case "FIRE":
		s.fireFloor = v[0]
		s.emit("FIRE %d", v[0])
		for _, g := range s.groups {
			if g.waiting > 0 {
				s.walkAway(g, "ABANDON")
			}
		}
	case "RESET":
		s.fireFloor = 0
		s.emit("RESET")
		for _, c := range s.cars {
			c.idleStart = s.time
		}
	case "WHERE":
		g := s.groups[v[0]-1]
		place := "-"
		if g.waiting > 0 {
			if g.car == 0 {
				place = "pending"
			} else {
				place = fmt.Sprintf("E%d", g.car)
			}
		}
		var riding []string
		for _, c := range s.cars {
			count := 0
			for _, p := range c.passengers {
				if p.group == g.number {
					count += p.count
				}
			}
			if count > 0 {
				riding = append(riding, fmt.Sprintf("E%dx%d", c.number, count))
			}
		}
		s.emit("WHERE G%d waiting=%d car=%s riding=%s delivered=%d lost=%d", g.number, g.waiting, place, joined(riding), g.delivered, g.lost)
	case "STATUS":
		for _, c := range s.cars {
			stops := make(map[int]bool)
			for _, p := range c.passengers {
				stops[s.groups[p.group-1].destination] = true
			}
			direction := "idle"
			if c.direction > 0 {
				direction = "up"
			} else if c.direction < 0 {
				direction = "down"
			}
			service := "out"
			if c.inService {
				service = "in"
			}
			s.emit("STATUS E%d floor=%d dir=%s door=%d load=%d stops=%s calls=%s service=%s", c.number, c.floor, direction, c.door, c.load(), integerList(sortedKeys(stops), ""), integerList(c.calls, "G"), service)
		}
		s.emit("STATUS pending=%s", integerList(s.pending, "G"))
	}
}
func (s *Simulation) chooseDirection(c *Car) int {
	f, d := c.floor, c.direction
	targets := s.targets(c)
	var here []*Group
	if !s.bypassing(c) {
		for _, id := range c.calls {
			g := s.groups[id-1]
			if g.landing == f {
				here = append(here, g)
			}
		}
	}
	if d != 0 {
		for y := range targets {
			if (y-f)*d > 0 {
				return d
			}
		}
		for _, g := range here {
			if g.direction == d {
				return d
			}
		}
	}
	if len(here) > 0 {
		return here[0].direction
	}
	if d != 0 {
		for y := range targets {
			if (y-f)*d < 0 {
				return -d
			}
		}
	}
	if d == 0 && len(c.calls) > 0 {
		return sign(s.groups[c.calls[0]-1].landing - f)
	}
	return 0
}
func (s *Simulation) deliver(p Passenger) {
	g := s.groups[p.group-1]
	wait, travel := p.boarded-g.time, s.time-g.time
	g.delivered += p.count
	g.lastAlight = s.time
	g.waitTotal += wait * p.count
	g.travelTotal += travel * p.count
	s.delivered += p.count
	s.waitTotal += wait * p.count
	s.travelTotal += travel * p.count
	if wait > s.maxWait {
		s.maxWait = wait
	}
}
func (s *Simulation) openDoors(c *Car) {
	s.emit("E%d OPEN %d", c.number, c.floor)
	c.door = s.config.door
	c.stops++
	c.energy += 2
	var riding []Passenger
	for _, p := range c.passengers {
		g := s.groups[p.group-1]
		if g.destination == c.floor {
			s.emit("E%d ALIGHT G%d x%d", c.number, g.number, p.count)
			s.deliver(p)
		} else if s.fireFloor != 0 {
			s.emit("E%d EVACUATE G%d x%d", c.number, g.number, p.count)
			g.lost += p.count
			s.evacuated += p.count
		} else {
			riding = append(riding, p)
		}
	}
	c.passengers = riding
	if s.fireFloor != 0 {
		return
	}
	heading := s.chooseDirection(c)
	if heading != 0 {
		c.direction = heading
	}
	var boarding []int
	for _, id := range c.calls {
		g := s.groups[id-1]
		if g.landing == c.floor && g.direction == heading {
			boarding = append(boarding, id)
		}
	}
	for _, id := range boarding {
		g := s.groups[id-1]
		count := s.config.capacity - c.load()
		if g.waiting < count {
			count = g.waiting
		}
		if count > 0 {
			c.passengers = append(c.passengers, Passenger{id, count, s.time})
			c.boarded += count
			g.waiting -= count
			g.boarded += count
			g.lastBoard = s.time
			g.cars[c.number] = true
			s.emit("E%d BOARD G%d x%d", c.number, id, count)
		}
		if g.waiting == 0 {
			c.calls = remove(c.calls, id)
			g.car = 0
		} else {
			s.emit("E%d LEFT G%d x%d", c.number, id, g.waiting)
			s.assign(g, c.number)
		}
	}
}
func (s *Simulation) move(c *Car, step int) {
	if step > 0 {
		c.energy += 3 + c.load()
	} else {
		c.energy++
	}
	c.distance++
	c.floor += step
}
func (s *Simulation) advance(c *Car) {
	previousFloor := c.floor
	if c.door > 0 {
		c.door--
	}
	if c.door == 0 {
		heading, stopping := 0, false
		if s.fireFloor != 0 {
			heading = sign(s.fireFloor - c.floor)
			stopping = heading == 0 && len(c.passengers) > 0
		} else {
			heading = s.chooseDirection(c)
			for _, p := range c.passengers {
				if s.groups[p.group-1].destination == c.floor {
					stopping = true
				}
			}
			if !s.bypassing(c) {
				for _, id := range c.calls {
					g := s.groups[id-1]
					if g.landing == c.floor && g.direction == heading {
						stopping = true
					}
				}
			}
		}
		if stopping {
			s.openDoors(c)
		} else if heading != 0 {
			c.direction = heading
			s.move(c, heading)
		} else {
			if c.direction != 0 {
				s.emit("E%d IDLE %d", c.number, c.floor)
				c.direction = 0
				c.idleStart = s.time
			}
			if s.fireFloor == 0 && c.inService && c.home != 0 && c.floor != c.home && s.time-c.idleStart >= s.config.park {
				s.move(c, sign(c.home-c.floor))
				if c.floor == c.home {
					s.emit("E%d PARK %d", c.number, c.home)
				}
			}
		}
	}
	if c.door > 0 || c.floor != previousFloor {
		c.busy++
	}
}
func (s *Simulation) settled(c *Car) bool {
	if c.door > 0 || len(c.passengers) > 0 || len(c.calls) > 0 {
		return false
	}
	if s.fireFloor != 0 {
		return c.floor == s.fireFloor
	}
	return !c.inService || c.home == 0 || c.floor == c.home
}
func (s *Simulation) run() {
	index := 0
	for {
		if s.config.patience >= 0 {
			for _, g := range s.groups {
				if g.waiting > 0 && s.time == g.time+s.config.patience {
					s.walkAway(g, "ABANDON")
				}
			}
		}
		for index < len(s.events) && s.events[index].time == s.time {
			s.execute(s.events[index])
			index++
		}
		for _, c := range s.cars {
			s.advance(c)
		}
		settled := true
		for _, c := range s.cars {
			if !s.settled(c) {
				settled = false
			}
		}
		if index == len(s.events) && settled {
			s.status = "end"
			s.emit("END")
			return
		}
		if s.time == s.config.limit {
			s.status = "abort"
			s.emit("ABORT")
			return
		}
		s.time++
	}
}
func (s *Simulation) averages() string {
	maximum := "-"
	if s.delivered > 0 {
		maximum = strconv.Itoa(s.maxWait)
	}
	return fmt.Sprintf("avg_wait=%s avg_travel=%s max_wait=%s", average(s.waitTotal, s.delivered), average(s.travelTotal, s.delivered), maximum)
}
func breakdown(label string, groups []*Group) string {
	passengers, delivered, wait := 0, 0, 0
	for _, g := range groups {
		passengers += g.count
		delivered += g.delivered
		wait += g.waitTotal
	}
	return fmt.Sprintf("%s: groups=%d passengers=%d delivered=%d avg_wait=%s", label, len(groups), passengers, delivered, average(wait, delivered))
}
func (s *Simulation) report() []string {
	var lines []string
	floors := make(map[int][]*Group)
	periods := make(map[int][]*Group)
	passengers := 0
	for _, g := range s.groups {
		wait, travel := "-", "-"
		if g.boarded == g.count {
			wait = strconv.Itoa(g.lastBoard - g.time)
		}
		if g.delivered == g.count {
			travel = strconv.Itoa(g.lastAlight - g.time)
		}
		lines = append(lines, fmt.Sprintf("G%d t=%d %d->%d n=%d delivered=%d lost=%d wait=%s travel=%s cars=%s", g.number, g.time, g.landing, g.destination, g.count, g.delivered, g.lost, wait, travel, integerList(sortedKeys(g.cars), "")))
		floors[g.landing] = append(floors[g.landing], g)
		passengers += g.count
		if s.config.period > 0 {
			k := g.time / s.config.period
			periods[k] = append(periods[k], g)
		}
	}
	for _, c := range s.cars {
		tenths := c.busy * 1000 / (s.time + 1)
		lines = append(lines, fmt.Sprintf("E%d distance=%d stops=%d boarded=%d busy=%d util=%d.%d%% energy=%d", c.number, c.distance, c.stops, c.boarded, c.busy, tenths/10, tenths%10, c.energy))
	}
	for f := 1; f <= s.config.floors; f++ {
		if groups := floors[f]; len(groups) > 0 {
			lines = append(lines, breakdown(fmt.Sprintf("F%d", f), groups))
		}
	}
	if s.config.period > 0 {
		keys := make([]int, 0, len(periods))
		for k := range periods {
			keys = append(keys, k)
		}
		sort.Ints(keys)
		for _, k := range keys {
			start := k * s.config.period
			lines = append(lines, breakdown(fmt.Sprintf("P%d %d-%d", k, start, start+s.config.period-1), periods[k]))
		}
	}
	lines = append(lines, fmt.Sprintf("summary: groups=%d passengers=%d delivered=%d abandoned=%d evacuated=%d %s end=%d", len(s.groups), passengers, s.delivered, s.abandoned, s.evacuated, s.averages(), s.time))
	return lines
}

type Scenario struct {
	name       string
	config     *Config
	simulation *Simulation
}

func (s *Scenario) outcome() string {
	if s.simulation == nil {
		return "invalid"
	}
	if s.simulation.status == "abort" {
		return "aborted"
	}
	if s.simulation.delivered == 0 {
		return "empty"
	}
	return "ranked"
}
func main() {
	scanner := bufio.NewScanner(os.Stdin)
	var lines []string
	for scanner.Scan() {
		lines = append(lines, scanner.Text())
	}
	output := bufio.NewWriter(os.Stdout)
	defer output.Flush()
	index := 1
	scenarios := make([]*Scenario, 0)
	for q := 0; q < number(lines[0]); q++ {
		name := strings.Split(lines[index], " ")[1]
		index++
		var settings [][]string
		var eventLines []InputLine
		for lines[index] != "END" {
			words := strings.Split(lines[index], " ")
			if words[0][0] >= '0' && words[0][0] <= '9' {
				eventLines = append(eventLines, InputLine{index + 1, words})
			} else {
				settings = append(settings, words)
			}
			index++
		}
		index++
		scenario := &Scenario{name: name}
		scenarios = append(scenarios, scenario)
		fmt.Fprintf(output, "== %s ==\n", name)
		config, problem := parseConfig(settings)
		if problem != "" {
			fmt.Fprintln(output, "error: "+problem)
			continue
		}
		scenario.config = config
		for _, line := range config.header() {
			fmt.Fprintln(output, line)
		}
		events, errors := validateEvents(config, eventLines)
		for _, line := range errors {
			fmt.Fprintln(output, line)
		}
		simulation := newSimulation(config, events, config.policy)
		simulation.run()
		scenario.simulation = simulation
		for _, line := range simulation.log {
			fmt.Fprintln(output, line)
		}
		for _, line := range simulation.report() {
			fmt.Fprintln(output, line)
		}
		for _, policy := range config.compare {
			rerun := newSimulation(config, events, policy)
			rerun.run()
			fmt.Fprintf(output, "compare %s: delivered=%d %s end=%d status=%s\n", policy, rerun.delivered, rerun.averages(), rerun.time, rerun.status)
		}
	}
	fmt.Fprintln(output, "== ranking ==")
	var ranked []*Scenario
	for _, scenario := range scenarios {
		if scenario.outcome() == "ranked" {
			ranked = append(ranked, scenario)
		}
	}
	sort.SliceStable(ranked, func(i, j int) bool {
		a, b := ranked[i].simulation, ranked[j].simulation
		left, right := int64(a.waitTotal)*int64(b.delivered), int64(b.waitTotal)*int64(a.delivered)
		if left != right {
			return left < right
		}
		return int64(a.travelTotal)*int64(b.delivered) < int64(b.travelTotal)*int64(a.delivered)
	})
	for i, scenario := range ranked {
		fmt.Fprintf(output, "%d. %s policy=%s %s\n", i+1, scenario.name, scenario.config.policy, scenario.simulation.averages())
	}
	for _, scenario := range scenarios {
		if outcome := scenario.outcome(); outcome != "ranked" {
			fmt.Fprintf(output, "- %s %s\n", scenario.name, outcome)
		}
	}
	fmt.Fprintln(output, "== policies ==")
	for _, policy := range policies {
		runs, count, wait, travel := 0, 0, 0, 0
		for _, scenario := range ranked {
			if scenario.config.policy == policy {
				s := scenario.simulation
				runs++
				count += s.delivered
				wait += s.waitTotal
				travel += s.travelTotal
			}
		}
		if runs > 0 {
			fmt.Fprintf(output, "%s: runs=%d avg_wait=%s avg_travel=%s\n", policy, runs, average(wait, count), average(travel, count))
		}
	}
}
