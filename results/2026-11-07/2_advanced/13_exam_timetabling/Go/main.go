package main

import (
	"fmt"
	"slices"
	"sort"
	"strings"
)

const (
	backToBack = iota
	sameDay
	overnight
	frontLoad
)

var relations = []string{"back_to_back", "same_day", "overnight"}
var exchangeVerdicts = []string{"fixed", "invalid", "worse", "applied"}
var swapVerdicts = []string{"fixed", "invalid", "rooms", "worse", "applied"}

func stringKeys[V any](values map[string]V) []string {
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}
func intKeys[V any](values map[int]V) []int {
	keys := make([]int, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Ints(keys)
	return keys
}
func copyAssignment(source map[string]int) map[string]int {
	result := make(map[string]int, len(source))
	for id, slot := range source {
		result[id] = slot
	}
	return result
}
func ceilDiv(numerator, denominator int) int { return (numerator + denominator - 1) / denominator }
func verdictCounts(tally map[string]int, verdicts []string) string {
	parts := make([]string, 0, len(verdicts))
	for _, verdict := range verdicts {
		parts = append(parts, fmt.Sprintf("%s %d", verdict, tally[verdict]))
	}
	return strings.Join(parts, " ")
}

type Order struct{ later, earlier string }
type Calendar struct {
	days, periods, limit, frontCount, deadline, ratio, slotCount int
	lengths, weights                                             []int
	closed                                                       map[int]bool
	unavailable                                                  map[string]map[int]bool
	fixed                                                        map[string]int
	orders                                                       []Order
	arrows                                                       map[string][]string
}

func newCalendar(lines []string) *Calendar {
	settings := make([][]int, 6)
	for i, line := range lines[:6] {
		for _, value := range strings.Fields(line)[1:] {
			settings[i] = append(settings[i], integer(value))
		}
	}
	calendar := &Calendar{
		days: settings[0][0], lengths: settings[1], periods: len(settings[1]),
		limit: settings[2][0], weights: settings[3], frontCount: settings[4][0],
		deadline: settings[4][1], ratio: settings[5][0],
		closed: map[int]bool{}, unavailable: map[string]map[int]bool{},
		fixed: map[string]int{}, arrows: map[string][]string{},
	}
	calendar.slotCount = calendar.days * calendar.periods
	return calendar
}
func (c *Calendar) slotAt(dayText, periodText string) int {
	day, period := integer(dayText), integer(periodText)
	if day < 1 || day > c.days || period < 1 || period > c.periods {
		return 0
	}
	return (day-1)*c.periods + period
}
func (c *Calendar) dayOf(slot int) int { return (slot-1)/c.periods + 1 }
func (c *Calendar) name(slot int) string {
	return fmt.Sprintf("D%dP%d", c.dayOf(slot), (slot-1)%c.periods+1)
}
func (c *Calendar) length(slot int) int { return c.lengths[(slot-1)%c.periods] }
func (c *Calendar) relation(first, second int) int {
	low, high := min(first, second), max(first, second)
	if c.dayOf(low) == c.dayOf(high) {
		if high-low == 1 {
			return backToBack
		}
		if high-low >= 2 {
			return sameDay
		}
	} else if high-low == 1 {
		return overnight
	}
	return -1
}

type Breakdown struct {
	counts      [3]int
	late, total int
}

func (b Breakdown) text() string {
	return fmt.Sprintf("back_to_back %d same_day %d overnight %d front_load %d penalty %d", b.counts[0], b.counts[1], b.counts[2], b.late, b.total)
}

type AttemptRecord struct {
	size, deadEnds int
	failed         string
}
type AssignmentStep struct {
	course           string
	slot, saturation int
}
type Insertion struct {
	course         string
	slot, increase int
}
type PenaltyPair struct {
	first, second    string
	relation, shared int
}
type StudentPair struct {
	relation, lowSlot int
	lowCourse         string
	highSlot          int
	highCourse        string
}
type RoomGroup struct {
	room       *Room
	placements []Placement
}
type StudentExam struct {
	slot   int
	course string
}
type StudentScore struct {
	student string
	counts  [3]int
	penalty int
}
type Scheduler struct {
	courses                                  map[string]*Course
	studentCourses                           map[string][]string
	rooms                                    []*Room
	calendar                                 *Calendar
	errors                                   []string
	largestRoom                              int
	empty, oversized, schedulable, frontLoad []string
	graph                                    *ConflictGraph
	edges                                    []Edge
	openSlots                                []int
	fixedSlots                               map[int]bool
	assignment                               map[string]int
	penalty                                  int
	attempts                                 []AttemptRecord
	assignmentOrder                          []AssignmentStep
	excluded                                 []string
	insertions                               []Insertion
	reasons                                  map[string][]string
	initial, exchanged                       Breakdown
	exchangeLog, swapLog                     []string
	placements                               map[string]Placement
	slotPlacements                           map[int][]Placement
}

func newScheduler(courses map[string]*Course, students map[string][]string, rooms []*Room, calendar *Calendar, errors []string) *Scheduler {
	s := &Scheduler{
		courses: courses, studentCourses: students, rooms: rooms,
		calendar: calendar, errors: errors, fixedSlots: map[int]bool{},
		assignment: map[string]int{}, reasons: map[string][]string{},
		placements: map[string]Placement{}, slotPlacements: map[int][]Placement{},
	}
	for _, room := range rooms {
		s.largestRoom = max(s.largestRoom, room.capacity)
	}
	vertices := []string{}
	for _, id := range stringKeys(courses) {
		size := courses[id].size()
		if size > 0 {
			vertices = append(vertices, id)
		}
		if size == 0 {
			s.empty = append(s.empty, id)
		} else if size > s.largestRoom {
			s.oversized = append(s.oversized, id)
		} else {
			s.schedulable = append(s.schedulable, id)
		}
	}
	s.graph = newConflictGraph(vertices, students)
	s.edges = s.graph.edges()
	ordered := s.bySize(s.schedulable)
	s.frontLoad = ordered[:min(calendar.frontCount, len(ordered))]
	return s
}
func (s *Scheduler) bySize(ids []string) []string {
	result := append([]string(nil), ids...)
	sort.Slice(result, func(i, j int) bool {
		a, b := result[i], result[j]
		if s.courses[a].size() != s.courses[b].size() {
			return s.courses[a].size() > s.courses[b].size()
		}
		return a < b
	})
	return result
}
func (s *Scheduler) byDegree(ids []string) []string {
	result := append([]string(nil), ids...)
	sort.Slice(result, func(i, j int) bool {
		a, b := result[i], result[j]
		if s.graph.degree(a) != s.graph.degree(b) {
			return s.graph.degree(a) > s.graph.degree(b)
		}
		return a < b
	})
	return result
}
func (s *Scheduler) blockedStudents(course *Course, slot int) []string {
	blocked := []string{}
	for _, student := range course.students {
		if s.calendar.unavailable[student][slot] {
			blocked = append(blocked, student)
		}
	}
	return blocked
}
func (s *Scheduler) suitable(course *Course, slot int) bool {
	return s.calendar.length(slot) >= course.duration && len(s.blockedStudents(course, slot)) == 0
}
func (s *Scheduler) packs(ids []string) bool {
	courses := make([]*Course, 0, len(ids))
	for _, id := range ids {
		courses = append(courses, s.courses[id])
	}
	_, ok := pack(s.rooms, courses)
	return ok
}
func outside(day, period string) string {
	return fmt.Sprintf("slot %s %s outside calendar", day, period)
}
func (s *Scheduler) validateCalendar(lines []string) {
	for index, line := range lines[6:] {
		fields := strings.Fields(line)
		message := ""
		switch fields[0] {
		case "closed":
			message = s.acceptClosed(fields[1:])
		case "unavailable":
			message = s.acceptUnavailable(fields[1:])
		case "fixed":
			message = s.acceptFixed(fields[1:])
		case "after":
			message = s.acceptAfter(fields[1:])
		}
		if message != "" {
			s.errors = append(s.errors, fmt.Sprintf("calendar.txt line %d: %s", index+7, message))
		}
	}
	for slot := 1; slot <= s.calendar.slotCount; slot++ {
		if !s.calendar.closed[slot] {
			s.openSlots = append(s.openSlots, slot)
		}
	}
	for _, slot := range s.calendar.fixed {
		s.fixedSlots[slot] = true
	}
}
func (s *Scheduler) acceptClosed(fields []string) string {
	slot := s.calendar.slotAt(fields[0], fields[1])
	if slot == 0 {
		return outside(fields[0], fields[1])
	}
	if s.calendar.closed[slot] {
		return "duplicate closed " + s.calendar.name(slot)
	}
	s.calendar.closed[slot] = true
	return ""
}
func (s *Scheduler) acceptUnavailable(fields []string) string {
	student := fields[0]
	if _, exists := s.studentCourses[student]; !exists {
		return "unknown student " + student
	}
	slot := s.calendar.slotAt(fields[1], fields[2])
	if slot == 0 {
		return outside(fields[1], fields[2])
	}
	blocked := s.calendar.unavailable[student]
	if blocked == nil {
		blocked = map[int]bool{}
		s.calendar.unavailable[student] = blocked
	}
	if blocked[slot] {
		return fmt.Sprintf("duplicate unavailable %s %s", student, s.calendar.name(slot))
	}
	blocked[slot] = true
	return ""
}
func (s *Scheduler) acceptFixed(fields []string) string {
	id := fields[0]
	course, exists := s.courses[id]
	if !exists {
		return "unknown course " + id
	}
	if !slices.Contains(s.schedulable, id) {
		return "course " + id + " not schedulable"
	}
	slot := s.calendar.slotAt(fields[1], fields[2])
	if slot == 0 {
		return outside(fields[1], fields[2])
	}
	name := s.calendar.name(slot)
	if s.calendar.closed[slot] {
		return "slot " + name + " closed"
	}
	if !s.suitable(course, slot) {
		return "slot " + name + " unsuitable for " + id
	}
	if _, fixed := s.calendar.fixed[id]; fixed {
		return "duplicate fixed " + id
	}
	group := s.coursesAt(s.calendar.fixed, slot)
	for _, other := range group {
		if _, adjacent := s.graph.neighbours(id)[other]; adjacent {
			return "conflict " + id + " " + other
		}
	}
	if !s.packs(append(group, id)) {
		return "rooms full " + name
	}
	s.calendar.fixed[id] = slot
	return ""
}
func (s *Scheduler) acceptAfter(fields []string) string {
	later, earlier := fields[0], fields[1]
	for _, id := range fields {
		if _, exists := s.courses[id]; !exists {
			return "unknown course " + id
		}
	}
	for _, id := range fields {
		if !slices.Contains(s.schedulable, id) {
			return "course " + id + " not schedulable"
		}
	}
	if later == earlier {
		return "bad order " + later + " " + earlier
	}
	order := Order{later, earlier}
	if slices.Contains(s.calendar.orders, order) {
		return "duplicate order " + later + " " + earlier
	}
	if reachable(s.calendar.arrows, earlier, later) {
		return "cycle " + later + " " + earlier
	}
	laterSlot, laterFixed := s.calendar.fixed[later]
	earlierSlot, earlierFixed := s.calendar.fixed[earlier]
	if laterFixed && earlierFixed && laterSlot <= earlierSlot {
		return "fixed order " + later + " " + earlier
	}
	s.calendar.orders = append(s.calendar.orders, order)
	s.calendar.arrows[later] = append(s.calendar.arrows[later], earlier)
	return ""
}
func (s *Scheduler) coursesAt(assignment map[string]int, slot int) []string {
	ids := []string{}
	for id, other := range assignment {
		if other == slot {
			ids = append(ids, id)
		}
	}
	sort.Strings(ids)
	return ids
}
func (s *Scheduler) orderConflicts(id string, slot int, assignment map[string]int) []string {
	conflicts := []string{}
	for _, order := range s.calendar.orders {
		if order.later == id {
			if other, assigned := assignment[order.earlier]; assigned && slot <= other {
				conflicts = append(conflicts, order.earlier)
			}
		} else if order.earlier == id {
			if other, assigned := assignment[order.later]; assigned && slot >= other {
				conflicts = append(conflicts, order.later)
			}
		}
	}
	return conflicts
}
func (s *Scheduler) ordersSatisfied(assignment map[string]int) bool {
	for _, order := range s.calendar.orders {
		later, hasLater := assignment[order.later]
		earlier, hasEarlier := assignment[order.earlier]
		if hasLater && hasEarlier && later <= earlier {
			return false
		}
	}
	return true
}
func (s *Scheduler) candidateSlots(id string, assignment map[string]int) []int {
	candidates := []int{}
	for _, slot := range s.openSlots {
		if !s.suitable(s.courses[id], slot) {
			continue
		}
		clash := false
		for other := range s.graph.neighbours(id) {
			if assignment[other] == slot {
				clash = true
				break
			}
		}
		if clash || len(s.orderConflicts(id, slot, assignment)) > 0 {
			continue
		}
		if s.packs(append(s.coursesAt(assignment, slot), id)) {
			candidates = append(candidates, slot)
		}
	}
	return candidates
}
func (s *Scheduler) buildTimetable() {
	for {
		pending := []string{}
		for _, id := range s.schedulable {
			if _, fixed := s.calendar.fixed[id]; !fixed && !slices.Contains(s.excluded, id) {
				pending = append(pending, id)
			}
		}
		assignment := copyAssignment(s.calendar.fixed)
		attempt := Attempt{courses: pending, graph: s.graph, limit: s.calendar.limit, candidateSlots: s.candidateSlots}
		success := attempt.search(assignment)
		failed := ""
		if !success {
			failed = attempt.deadEndCourse
		}
		s.attempts = append(s.attempts, AttemptRecord{len(pending), attempt.deadEnds, failed})
		if !success {
			s.excluded = append(s.excluded, failed)
			continue
		}
		s.assignment = assignment
		for _, choice := range attempt.chosen {
			s.assignmentOrder = append(s.assignmentOrder, AssignmentStep{choice.course, assignment[choice.course], choice.saturation})
		}
		return
	}
}
func (s *Scheduler) penaltyPairs(assignment map[string]int) []PenaltyPair {
	pairs := []PenaltyPair{}
	for _, edge := range s.edges {
		first, hasFirst := assignment[edge.first]
		second, hasSecond := assignment[edge.second]
		if hasFirst && hasSecond {
			relation := s.calendar.relation(first, second)
			if relation >= 0 {
				pairs = append(pairs, PenaltyPair{edge.first, edge.second, relation, edge.shared})
			}
		}
	}
	return pairs
}
func (s *Scheduler) lateCourses(assignment map[string]int) []string {
	late := []string{}
	for _, id := range s.frontLoad {
		if slot, assigned := assignment[id]; assigned && slot > s.calendar.deadline {
			late = append(late, id)
		}
	}
	return late
}
func (s *Scheduler) breakdown(assignment map[string]int) Breakdown {
	result := Breakdown{late: len(s.lateCourses(assignment))}
	for _, pair := range s.penaltyPairs(assignment) {
		result.counts[pair.relation] += pair.shared
	}
	result.total = s.calendar.weights[frontLoad] * result.late
	for relation, count := range result.counts {
		result.total += s.calendar.weights[relation] * count
	}
	return result
}
func (s *Scheduler) contributions() map[string]int {
	result := map[string]int{}
	for id := range s.assignment {
		result[id] = 0
	}
	for _, pair := range s.penaltyPairs(s.assignment) {
		value := s.calendar.weights[pair.relation] * pair.shared
		result[pair.first] += value
		result[pair.second] += value
	}
	for _, id := range s.lateCourses(s.assignment) {
		result[id] += s.calendar.weights[frontLoad]
	}
	return result
}
func (s *Scheduler) blockingReason(id string, slot int) string {
	course := s.courses[id]
	if s.calendar.closed[slot] {
		return "closed"
	}
	if s.calendar.length(slot) < course.duration {
		return "too_short"
	}
	if blocked := s.blockedStudents(course, slot); len(blocked) > 0 {
		return "unavailable " + blocked[0]
	}
	chosen := ""
	strongest := -1
	for other, shared := range s.graph.neighbours(id) {
		if s.assignment[other] == slot && (shared > strongest || shared == strongest && other < chosen) {
			chosen, strongest = other, shared
		}
	}
	if chosen != "" {
		return fmt.Sprintf("conflict %s shared %d", chosen, strongest)
	}
	if conflicts := s.orderConflicts(id, slot, s.assignment); len(conflicts) > 0 {
		sort.Strings(conflicts)
		return "order " + conflicts[0]
	}
	return "rooms"
}
func (s *Scheduler) insertExcluded() {
	excluded := append([]string(nil), s.excluded...)
	sort.Strings(excluded)
	for _, id := range excluded {
		slots := s.candidateSlots(id, s.assignment)
		if len(slots) == 0 {
			for slot := 1; slot <= s.calendar.slotCount; slot++ {
				s.reasons[id] = append(s.reasons[id], s.blockingReason(id, slot))
			}
			continue
		}
		before := s.breakdown(s.assignment).total
		best, bestTotal := 0, 0
		for _, slot := range slots {
			trial := copyAssignment(s.assignment)
			trial[id] = slot
			total := s.breakdown(trial).total
			if best == 0 || total < bestTotal {
				best, bestTotal = slot, total
			}
		}
		s.assignment[id] = best
		s.insertions = append(s.insertions, Insertion{id, best, bestTotal - before})
	}
	s.initial = s.breakdown(s.assignment)
	s.penalty = s.initial.total
}
func (s *Scheduler) unscheduled() []string {
	ids := append([]string(nil), s.oversized...)
	for _, id := range s.excluded {
		if _, assigned := s.assignment[id]; !assigned {
			ids = append(ids, id)
		}
	}
	sort.Strings(ids)
	return ids
}
func (s *Scheduler) validTrial(trial map[string]int, moved []string) bool {
	for _, id := range moved {
		if !s.suitable(s.courses[id], trial[id]) {
			return false
		}
	}
	return s.ordersSatisfied(trial)
}
func (s *Scheduler) movedCourses(trial map[string]int) []string {
	moved := []string{}
	for id, slot := range trial {
		if s.assignment[id] != slot {
			moved = append(moved, id)
		}
	}
	sort.Strings(moved)
	return moved
}
func (s *Scheduler) exchangeTrial(first, second int) (string, map[string]int, int) {
	if s.fixedSlots[first] || s.fixedSlots[second] {
		return "fixed", nil, 0
	}
	trial := copyAssignment(s.assignment)
	for id, slot := range s.assignment {
		if slot == first {
			trial[id] = second
		} else if slot == second {
			trial[id] = first
		}
	}
	if !s.validTrial(trial, s.movedCourses(trial)) {
		return "invalid", nil, 0
	}
	total := s.breakdown(trial).total
	if total >= s.penalty {
		return "worse", nil, 0
	}
	return "applied", trial, total
}
func (s *Scheduler) exchangeSlots() {
	serial := 0
	for round := 1; ; round++ {
		tally := map[string]int{}
		records := []string{}
		pairs := 0
		for index, first := range s.openSlots {
			for _, second := range s.openSlots[index+1:] {
				pairs++
				verdict, trial, total := s.exchangeTrial(first, second)
				tally[verdict]++
				if verdict == "applied" {
					serial++
					records = append(records, fmt.Sprintf("EXCHANGE %d %s %s penalty %d -> %d", serial, s.calendar.name(first), s.calendar.name(second), s.penalty, total))
					s.assignment = trial
					s.penalty = total
				}
			}
		}
		s.exchangeLog = append(s.exchangeLog, fmt.Sprintf("ROUND %d pairs %d %s", round, pairs, verdictCounts(tally, exchangeVerdicts)))
		s.exchangeLog = append(s.exchangeLog, records...)
		if tally["applied"] == 0 {
			break
		}
	}
	s.exchanged = s.breakdown(s.assignment)
}
func (s *Scheduler) swapTrial(id string, home, target int) (string, map[string]int, int) {
	chain := s.graph.kempeChain(s.assignment, id, home, target)
	for _, member := range chain {
		if _, fixed := s.calendar.fixed[member]; fixed {
			return "fixed", nil, 0
		}
	}
	trial := copyAssignment(s.assignment)
	for _, member := range chain {
		if s.assignment[member] == home {
			trial[member] = target
		} else {
			trial[member] = home
		}
	}
	if !s.validTrial(trial, chain) {
		return "invalid", nil, 0
	}
	if !s.packs(s.coursesAt(trial, home)) || !s.packs(s.coursesAt(trial, target)) {
		return "rooms", nil, 0
	}
	total := s.breakdown(trial).total
	if total >= s.penalty {
		return "worse", nil, 0
	}
	return "applied", trial, total
}
func (s *Scheduler) swapChains() {
	serial := 0
	for pass := 1; ; pass++ {
		tally := map[string]int{}
		records := []string{}
		candidates := 0
		movable := []string{}
		for _, id := range stringKeys(s.assignment) {
			if _, fixed := s.calendar.fixed[id]; !fixed {
				movable = append(movable, id)
			}
		}
		for _, id := range movable {
			home := s.assignment[id]
			for _, target := range s.openSlots {
				if target == home {
					continue
				}
				candidates++
				verdict, trial, total := s.swapTrial(id, home, target)
				tally[verdict]++
				if verdict != "applied" {
					continue
				}
				serial++
				chain := s.movedCourses(trial)
				records = append(records, fmt.Sprintf("SWAP %d %s %s %s chain %d penalty %d -> %d", serial, id, s.calendar.name(home), s.calendar.name(target), len(chain), s.penalty, total))
				for _, member := range chain {
					records = append(records, fmt.Sprintf("  MOVE %s %s -> %s", member, s.calendar.name(s.assignment[member]), s.calendar.name(trial[member])))
				}
				s.assignment = trial
				s.penalty = total
				break
			}
		}
		s.swapLog = append(s.swapLog, fmt.Sprintf("PASS %d candidates %d %s", pass, candidates, verdictCounts(tally, swapVerdicts)))
		s.swapLog = append(s.swapLog, records...)
		if tally["applied"] == 0 {
			break
		}
	}
}
func (s *Scheduler) assignRooms() {
	for _, slot := range s.openSlots {
		group := []*Course{}
		for _, id := range s.coursesAt(s.assignment, slot) {
			group = append(group, s.courses[id])
		}
		placed, ok := pack(s.rooms, group)
		if !ok {
			panic("final packing failed")
		}
		s.slotPlacements[slot] = placed
		for _, placement := range placed {
			s.placements[placement.course.id] = placement
		}
	}
}
func (s *Scheduler) roomGroups(slot int) []RoomGroup {
	groups := []RoomGroup{}
	for _, room := range s.rooms {
		placed := []Placement{}
		for _, placement := range s.slotPlacements[slot] {
			if placement.room == room {
				placed = append(placed, placement)
			}
		}
		if len(placed) > 0 {
			groups = append(groups, RoomGroup{room, placed})
		}
	}
	return groups
}
func (s *Scheduler) invigilators(slot int) int {
	total := 0
	for _, group := range s.roomGroups(slot) {
		students := 0
		for _, placement := range group.placements {
			students += placement.course.size()
		}
		total += ceilDiv(students, s.calendar.ratio)
	}
	return total
}
func (s *Scheduler) slotLoad(slot int) (int, int) {
	ids := s.coursesAt(s.assignment, slot)
	students := 0
	for _, id := range ids {
		students += s.courses[id].size()
	}
	return len(ids), students
}
func (s *Scheduler) studentExams(student string) []StudentExam {
	exams := []StudentExam{}
	for _, id := range s.studentCourses[student] {
		if slot, assigned := s.assignment[id]; assigned {
			exams = append(exams, StudentExam{slot, id})
		}
	}
	sort.Slice(exams, func(i, j int) bool {
		if exams[i].slot != exams[j].slot {
			return exams[i].slot < exams[j].slot
		}
		return exams[i].course < exams[j].course
	})
	return exams
}
func (s *Scheduler) studentPairs(student string) []StudentPair {
	exams := s.studentExams(student)
	pairs := []StudentPair{}
	for i, low := range exams {
		for _, high := range exams[i+1:] {
			relation := s.calendar.relation(low.slot, high.slot)
			if relation >= 0 {
				pairs = append(pairs, StudentPair{relation, low.slot, low.course, high.slot, high.course})
			}
		}
	}
	return pairs
}
func (s *Scheduler) studentPenalty(student string) ([3]int, int) {
	counts := [3]int{}
	for _, pair := range s.studentPairs(student) {
		counts[pair.relation]++
	}
	total := 0
	for relation, count := range counts {
		total += s.calendar.weights[relation] * count
	}
	return counts, total
}
func (s *Scheduler) timetableLines() []string {
	c := s.calendar
	lines := []string{fmt.Sprintf("TIMETABLE days %d periods %d open %d courses %d scheduled %d unscheduled %d empty %d", c.days, c.periods, len(s.openSlots), len(s.courses), len(s.assignment), len(s.unscheduled()), len(s.empty))}
	header := []string{}
	for period := 1; period <= c.periods; period++ {
		header = append(header, fmt.Sprintf("P%d", period))
	}
	header = append(header, "TOTAL")
	lines = append(lines, fixedWidthLine("DAY", header, 4, 10))
	for day := 1; day <= c.days; day++ {
		cells := []string{}
		dayExams, dayStudents := 0, 0
		for period := 1; period <= c.periods; period++ {
			slot := (day-1)*c.periods + period
			if c.closed[slot] {
				cells = append(cells, "closed")
				continue
			}
			exams, students := s.slotLoad(slot)
			cells = append(cells, fmt.Sprintf("%d/%d", exams, students))
			dayExams += exams
			dayStudents += students
		}
		cells = append(cells, fmt.Sprintf("%d/%d", dayExams, dayStudents))
		lines = append(lines, fixedWidthLine(fmt.Sprintf("D%d", day), cells, 4, 10))
	}
	for slot := 1; slot <= c.slotCount; slot++ {
		prefix := fmt.Sprintf("SLOT %d %s minutes %d", slot, c.name(slot), c.length(slot))
		if c.closed[slot] {
			lines = append(lines, prefix+" closed")
			continue
		}
		exams, students := s.slotLoad(slot)
		groups := s.roomGroups(slot)
		seats := 0
		for _, group := range groups {
			seats += group.room.capacity
		}
		lines = append(lines, fmt.Sprintf("%s exams %d students %d rooms %d seats %d invigilators %d", prefix, exams, students, len(groups), seats, s.invigilators(slot)))
		for _, placement := range s.slotPlacements[slot] {
			course := placement.course
			marker := ""
			if _, fixed := c.fixed[course.id]; fixed {
				marker = " fixed"
			}
			lines = append(lines, fmt.Sprintf("  %s %dmin students %d room %s seats %d-%d%s %s", course.id, course.duration, course.size(), placement.room.id, placement.firstSeat, placement.lastSeat, marker, course.name))
		}
	}
	for _, room := range s.rooms {
		used, exams, seated := 0, 0, 0
		for _, slot := range s.openSlots {
			for _, group := range s.roomGroups(slot) {
				if group.room == room {
					used++
					exams += len(group.placements)
					for _, placement := range group.placements {
						seated += placement.course.size()
					}
				}
			}
		}
		lines = append(lines, fmt.Sprintf("ROOM %s capacity %d slots %d exams %d seated %d utilization %d", room.id, room.capacity, used, exams, seated, roundedPercent(seated, room.capacity*len(s.openSlots))))
	}
	total := 0
	for _, slot := range s.openSlots {
		total += s.invigilators(slot)
	}
	lines = append(lines, fmt.Sprintf("INVIGILATORS total %d ratio %d", total, c.ratio))
	return lines
}
func (s *Scheduler) roomLines() []string {
	lines := []string{"slot,room,course,students,first_seat,last_seat"}
	for _, slot := range s.openSlots {
		for _, group := range s.roomGroups(slot) {
			for _, p := range group.placements {
				lines = append(lines, fmt.Sprintf("%s,%s,%s,%d,%d,%d", s.calendar.name(slot), group.room.id, p.course.id, p.course.size(), p.firstSeat, p.lastSeat))
			}
		}
	}
	return lines
}
func (s *Scheduler) penaltyLines() []string {
	c := s.calendar
	w := c.weights
	final := s.breakdown(s.assignment)
	lines := []string{fmt.Sprintf("WEIGHTS back_to_back %d same_day %d overnight %d front_load %d", w[0], w[1], w[2], w[3]), fmt.Sprintf("FRONT_LOAD courses %d last_slot %s", len(s.frontLoad), c.name(c.deadline)), "INITIAL " + s.initial.text()}
	lines = append(lines, s.exchangeLog...)
	lines = append(lines, "EXCHANGED "+s.exchanged.text())
	lines = append(lines, s.swapLog...)
	lines = append(lines, "FINAL "+final.text(), fmt.Sprintf("SAVED %d", s.initial.total-final.total))
	daily := make([][3]int, c.days+1)
	for _, pair := range s.penaltyPairs(s.assignment) {
		day := c.dayOf(min(s.assignment[pair.first], s.assignment[pair.second]))
		daily[day][pair.relation] += pair.shared
	}
	for day := 1; day <= c.days; day++ {
		counts := daily[day]
		lines = append(lines, fmt.Sprintf("DAY D%d back_to_back %d same_day %d overnight %d", day, counts[0], counts[1], counts[2]))
	}
	for _, id := range s.lateCourses(s.assignment) {
		lines = append(lines, fmt.Sprintf("LATE %s %s students %d", id, c.name(s.assignment[id]), s.courses[id].size()))
	}
	contributions := s.contributions()
	ranked := stringKeys(contributions)
	sort.Slice(ranked, func(i, j int) bool {
		a, b := ranked[i], ranked[j]
		if contributions[a] != contributions[b] {
			return contributions[a] > contributions[b]
		}
		return a < b
	})
	for _, id := range ranked[:min(10, len(ranked))] {
		if contributions[id] > 0 {
			lines = append(lines, fmt.Sprintf("COURSE %s %s penalty %d", id, c.name(s.assignment[id]), contributions[id]))
		}
	}
	return append(lines, s.studentStatistics()...)
}
func (s *Scheduler) studentStatistics() []string {
	histogram, gaps, dayLoads := map[int]int{}, map[int]int{}, map[int]int{}
	ranking := []StudentScore{}
	for _, student := range stringKeys(s.studentCourses) {
		counts, penalty := s.studentPenalty(student)
		histogram[penalty]++
		ranking = append(ranking, StudentScore{student, counts, penalty})
		exams := s.studentExams(student)
		for i := 1; i < len(exams); i++ {
			gaps[exams[i].slot-exams[i-1].slot]++
		}
		if len(exams) > 0 {
			perDay := map[int]int{}
			largest := 0
			for _, exam := range exams {
				day := s.calendar.dayOf(exam.slot)
				perDay[day]++
				largest = max(largest, perDay[day])
			}
			dayLoads[largest]++
		}
	}
	lines := []string{}
	for _, value := range intKeys(histogram) {
		lines = append(lines, fmt.Sprintf("HISTOGRAM %d %d", value, histogram[value]))
	}
	for _, value := range intKeys(gaps) {
		lines = append(lines, fmt.Sprintf("GAP %d %d", value, gaps[value]))
	}
	for _, value := range intKeys(dayLoads) {
		lines = append(lines, fmt.Sprintf("DAYLOAD %d %d", value, dayLoads[value]))
	}
	sort.Slice(ranking, func(i, j int) bool {
		if ranking[i].penalty != ranking[j].penalty {
			return ranking[i].penalty > ranking[j].penalty
		}
		return ranking[i].student < ranking[j].student
	})
	for _, score := range ranking[:min(5, len(ranking))] {
		if score.penalty > 0 {
			lines = append(lines, fmt.Sprintf("WORST %s penalty %d back_to_back %d same_day %d overnight %d", score.student, score.penalty, score.counts[0], score.counts[1], score.counts[2]))
		}
	}
	return lines
}
func (s *Scheduler) scheduleLines(queries []string) []string {
	lines := []string{}
	c := s.calendar
	for _, student := range queries {
		ids, exists := s.studentCourses[student]
		if !exists {
			lines = append(lines, "STUDENT "+student+" not found")
			continue
		}
		assigned := s.studentExams(student)
		_, penalty := s.studentPenalty(student)
		lines = append(lines, fmt.Sprintf("STUDENT %s exams %d scheduled %d penalty %d", student, len(ids), len(assigned), penalty))
		for _, exam := range assigned {
			placement := s.placements[exam.course]
			course := placement.course
			seat := placement.firstSeat + sort.SearchStrings(course.students, student)
			lines = append(lines, fmt.Sprintf("  %s %s room %s seat %d %s", c.name(exam.slot), exam.course, placement.room.id, seat, course.name))
		}
		for _, id := range ids {
			if _, assigned := s.assignment[id]; !assigned {
				lines = append(lines, "  UNSCHEDULED "+id+" "+s.courses[id].name)
			}
		}
		for _, pair := range s.studentPairs(student) {
			lines = append(lines, fmt.Sprintf("  %s %s %s %s %s", strings.ToUpper(relations[pair.relation]), c.name(pair.lowSlot), pair.lowCourse, c.name(pair.highSlot), pair.highCourse))
		}
		for _, slot := range intKeys(c.unavailable[student]) {
			lines = append(lines, "  UNAVAILABLE "+c.name(slot))
		}
	}
	return lines
}
func (s *Scheduler) statusLines() []string {
	contributions := s.contributions()
	lines := []string{"course,status,slot,students,minutes,degree,penalty"}
	for _, id := range stringKeys(s.courses) {
		course := s.courses[id]
		status := "no_slot"
		slot := "-"
		if _, fixed := s.calendar.fixed[id]; fixed {
			status = "fixed"
		} else if _, assigned := s.assignment[id]; assigned {
			status = "scheduled"
		} else if slices.Contains(s.oversized, id) {
			status = "too_large"
		} else if slices.Contains(s.empty, id) {
			status = "empty"
		}
		if value, assigned := s.assignment[id]; assigned {
			slot = s.calendar.name(value)
		}
		lines = append(lines, fmt.Sprintf("%s,%s,%s,%d,%d,%d,%d", id, status, slot, course.size(), course.duration, s.graph.degree(id), contributions[id]))
	}
	return lines
}
func (s *Scheduler) graphLines() []string {
	vertices, edges := len(s.graph.vertices), len(s.edges)
	shared := 0
	for _, edge := range s.edges {
		shared += edge.shared
	}
	density := 0
	if vertices >= 2 {
		density = 2000 * edges / (vertices * (vertices - 1))
	}
	lines := []string{fmt.Sprintf("GRAPH courses %d edges %d shared %d density %d", vertices, edges, shared, density)}
	ranked := s.byDegree(s.graph.vertices)
	for _, id := range ranked[:min(5, len(ranked))] {
		lines = append(lines, fmt.Sprintf("DEGREE %s neighbours %d shared %d students %d", id, s.graph.degree(id), s.graph.sharedTotal(id), s.courses[id].size()))
	}
	components := s.graph.components()
	lines = append(lines, fmt.Sprintf("COMPONENTS %d", len(components)))
	for index, component := range components {
		lines = append(lines, fmt.Sprintf("COMPONENT %d size %d first %s", index+1, len(component), component[0]))
	}
	clique := s.graph.greedyClique(s.schedulable)
	lines = append(lines, strings.Join(append([]string{"CLIQUE", "size", fmt.Sprint(len(clique))}, clique...), " "))
	return lines
}
func (s *Scheduler) capacityLines() []string {
	most, attaining := 0, 0
	for _, ids := range s.studentCourses {
		if len(ids) > most {
			most = len(ids)
			attaining = 1
		} else if len(ids) == most {
			attaining++
		}
	}
	demand, capacity := 0, 0
	for _, id := range s.schedulable {
		demand += s.courses[id].size()
	}
	for _, room := range s.rooms {
		capacity += room.capacity
	}
	lines := []string{fmt.Sprintf("LOAD max_exams %d students %d", most, attaining), fmt.Sprintf("SEATS demand %d capacity %d min_slots %d", demand, capacity, ceilDiv(demand, capacity)), fmt.Sprintf("HEURISTIC largest_degree slots %d", greedyNumbering(s.byDegree(s.schedulable), s.graph)), fmt.Sprintf("HEURISTIC largest_enrolment slots %d", greedyNumbering(s.bySize(s.schedulable), s.graph))}
	table := s.bySize(s.graph.vertices)
	table = table[:min(8, len(table))]
	lines = append(lines, fixedWidthLine("MATRIX", table, 9, 9))
	for _, row := range table {
		cells := []string{}
		for _, column := range table {
			cell := "-"
			if column != row {
				cell = fmt.Sprint(s.graph.neighbours(row)[column])
			}
			cells = append(cells, cell)
		}
		lines = append(lines, fixedWidthLine(row, cells, 9, 9))
	}
	return lines
}
func (s *Scheduler) reportLines() []string {
	c := s.calendar
	enrolments := 0
	for _, ids := range s.studentCourses {
		enrolments += len(ids)
	}
	lines := []string{fmt.Sprintf("INPUT courses %d enrolments %d rooms %d students %d errors %d", len(s.courses), enrolments, len(s.rooms), len(s.studentCourses), len(s.errors))}
	for _, message := range s.errors {
		lines = append(lines, "ERROR "+message)
	}
	lines = append(lines, s.graphLines()...)
	lines = append(lines, s.capacityLines()...)
	for _, id := range s.empty {
		lines = append(lines, "EMPTY "+id)
	}
	for _, id := range s.oversized {
		lines = append(lines, fmt.Sprintf("TOO_LARGE %s students %d largest_room %d", id, s.courses[id].size(), s.largestRoom))
	}
	for _, slot := range intKeys(c.closed) {
		lines = append(lines, "CLOSED "+c.name(slot))
	}
	for _, id := range stringKeys(c.fixed) {
		lines = append(lines, "FIXED "+id+" "+c.name(c.fixed[id]))
	}
	for _, order := range c.orders {
		lines = append(lines, "AFTER "+order.later+" "+order.earlier)
	}
	for index, attempt := range s.attempts {
		result := "success"
		if attempt.failed != "" {
			result = "failed " + attempt.failed
		}
		lines = append(lines, fmt.Sprintf("ATTEMPT %d courses %d backtracks %d %s", index+1, attempt.size, attempt.deadEnds, result))
	}
	for index, step := range s.assignmentOrder {
		lines = append(lines, fmt.Sprintf("ORDER %d %s %s saturation %d degree %d", index+1, step.course, c.name(step.slot), step.saturation, s.graph.degree(step.course)))
	}
	for _, insertion := range s.insertions {
		lines = append(lines, fmt.Sprintf("INSERTED %s %s penalty %d", insertion.course, c.name(insertion.slot), insertion.increase))
	}
	for _, id := range s.unscheduled() {
		reason := "no_slot"
		if slices.Contains(s.oversized, id) {
			reason = "too_large"
		}
		lines = append(lines, fmt.Sprintf("UNSCHEDULED %s reason %s students %d", id, reason, s.courses[id].size()))
		for index, message := range s.reasons[id] {
			lines = append(lines, "  "+c.name(index+1)+" "+message)
		}
	}
	used := map[int]bool{}
	for _, slot := range s.assignment {
		used[slot] = true
	}
	lines = append(lines, fmt.Sprintf("SUMMARY scheduled %d unscheduled %d slots_used %d penalty %d", len(s.assignment), len(s.unscheduled()), len(used), s.penalty))
	return lines
}
func main() {
	errors := []string{}
	courses := loadCourses("input/courses.csv", &errors)
	students := loadEnrolments("input/enrolments.csv", courses, &errors)
	rooms := loadRooms("input/rooms.csv", &errors)
	calendarLines := readLines("input/calendar.txt")
	scheduler := newScheduler(courses, students, rooms, newCalendar(calendarLines), errors)
	scheduler.validateCalendar(calendarLines)
	scheduler.buildTimetable()
	scheduler.insertExcluded()
	scheduler.exchangeSlots()
	scheduler.swapChains()
	scheduler.assignRooms()
	writeFiles("output", []OutputFile{
		{"timetable.txt", scheduler.timetableLines()},
		{"rooms.csv", scheduler.roomLines()},
		{"penalties.txt", scheduler.penaltyLines()},
		{"student_schedules.txt", scheduler.scheduleLines(readLines("input/queries.txt"))},
		{"course_status.csv", scheduler.statusLines()},
		{"report.txt", scheduler.reportLines()},
	})
}
