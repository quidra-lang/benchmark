package main

import (
	"bufio"
	"fmt"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

var weekdays = []string{"MO", "TU", "WE", "TH", "FR", "SA", "SU"}
var points = map[string]int{"A": 4, "B": 3, "C": 2, "D": 1, "F": 0}
var wordPattern = regexp.MustCompile("[A-Z0-9]+|[&|()]")
var validWord = regexp.MustCompile("^(?:[A-Z]{2,4}[0-9]{3}|Y[1-9])$")

func integer(s string) int { v, _ := strconv.Atoi(s); return v }
func clock(m int) string { return fmt.Sprintf("%02d:%02d", m/60, m%60) }
func rate(n, max int) string {
	if max == 0 { return "n/a" }
	return fmt.Sprintf("%d%%", n*100/max)
}
func dayIndex(day string) int {
	for i, d := range weekdays { if d == day { return i } }
	return -1
}

type Slot struct { day string; start, end int; raw string }
func (s Slot) overlaps(t Slot) bool {
	return s.day == t.day && s.start < t.end && t.start < s.end
}
func readSlots(text string) ([]Slot, error) {
	if text == "-" { return nil, nil }
	var slots []Slot
	for _, raw := range strings.Split(text, ",") {
		sh, sm := integer(raw[2:4]), integer(raw[4:6])
		eh, em := integer(raw[7:9]), integer(raw[9:11])
		start, end := sh*60+sm, eh*60+em
		day := raw[:2]
		if dayIndex(day) < 0 || sh > 23 || sm > 59 || eh > 23 || em > 59 || start >= end {
			return nil, fmt.Errorf("invalid slot %s", raw)
		}
		slots = append(slots, Slot{day, start, end, raw})
	}
	for i, a := range slots {
		for j := i+1; j < len(slots); j++ {
			if a.overlaps(slots[j]) {
				return nil, fmt.Errorf("overlapping slots %s %s", a.raw, slots[j].raw)
			}
		}
	}
	return slots, nil
}

type Expr struct { kind, word string; children []*Expr }
func combine(kind string, nodes []*Expr) *Expr {
	var children []*Expr
	for _, node := range nodes {
		if node.kind == kind { children = append(children, node.children...) } else {
			children = append(children, node)
		}
	}
	if len(children) == 1 { return children[0] }
	return &Expr{kind: kind, children: children}
}
func canonical(node *Expr) string {
	if node == nil { return "-" }
	if node.kind == "word" { return node.word }
	var parts []string
	for _, child := range node.children {
		s := canonical(child)
		if node.kind == "and" && child.kind == "or" { s = "("+s+")" }
		parts = append(parts, s)
	}
	if node.kind == "and" { return strings.Join(parts, "&") }
	return strings.Join(parts, "|")
}
func refersTo(node *Expr, code string) bool {
	if node == nil { return false }
	if node.kind == "word" { return node.word == code }
	for _, child := range node.children { if refersTo(child, code) { return true } }
	return false
}

type Parser struct { tokens []string; pos int; bad bool }
func (p *Parser) peek() string {
	if p.pos >= len(p.tokens) { return "" }
	return p.tokens[p.pos]
}
func (p *Parser) factor() *Expr {
	token := p.peek()
	if token == "" { p.bad = true; return nil }
	p.pos++
	if token == "(" {
		node := p.expression()
		if p.peek() != ")" { p.bad = true; return nil }
		p.pos++
		return node
	}
	if token == "&" || token == "|" || token == ")" { p.bad = true; return nil }
	return &Expr{kind: "word", word: token}
}
func (p *Parser) term() *Expr {
	first := p.factor()
	if first == nil { return nil }
	nodes := []*Expr{first}
	for p.peek() == "&" {
		p.pos++
		next := p.factor()
		if next == nil { return nil }
		nodes = append(nodes, next)
	}
	return combine("and", nodes)
}
func (p *Parser) expression() *Expr {
	first := p.term()
	if first == nil { return nil }
	nodes := []*Expr{first}
	for p.peek() == "|" {
		p.pos++
		next := p.term()
		if next == nil { return nil }
		nodes = append(nodes, next)
	}
	return combine("or", nodes)
}
func parsePrereq(code, text string) (*Expr, error) {
	if text == "-" { return nil, nil }
	tokens := wordPattern.FindAllString(text, -1)
	invalid := fmt.Errorf("invalid prereq %s", code)
	if strings.Join(tokens, "") != text { return nil, invalid }
	for _, t := range tokens {
		if t != "&" && t != "|" && t != "(" && t != ")" && !validWord.MatchString(t) {
			return nil, invalid
		}
	}
	p := &Parser{tokens: tokens}
	tree := p.expression()
	if p.bad || tree == nil || p.pos != len(tokens) { return nil, invalid }
	if refersTo(tree, code) { return nil, fmt.Errorf("self prereq %s", code) }
	return tree, nil
}

type Grade struct { code, grade string; credits int }
type Course struct {
	code string
	credits, capacity int
	slots []Slot
	prereq *Expr
	open bool
	enrolled map[string]bool
	waiting []string
}
func (c *Course) weekly() int {
	n := 0
	for _, s := range c.slots { n += s.end-s.start }
	return n
}
func (c *Course) status() string {
	if c.open { return "open" }
	return "closed"
}
func (c *Course) department() string { return c.code[:len(c.code)-3] }

type History struct { command int; event string }
type Student struct {
	id string
	year, limit int
	grades []Grade
	taking map[string]bool
	history []History
}
func (s *Student) passed(code string) string {
	for _, grade := range s.grades {
		if grade.code == code && (grade.grade == "A" || grade.grade == "B" || grade.grade == "C") {
			return grade.grade
		}
	}
	return ""
}
func (s *Student) earned() int {
	n := 0
	for _, g := range s.grades { if g.grade != "F" { n += g.credits } }
	return n
}
func (s *Student) gpa() string {
	if len(s.grades) == 0 { return "n/a" }
	p, c := 0, 0
	for _, g := range s.grades { p += points[g.grade]*g.credits; c += g.credits }
	h := (200*p+c)/(2*c)
	return fmt.Sprintf("%d.%02d", h/100, h%100)
}
func satisfied(e *Expr, s *Student) bool {
	if e == nil { return true }
	if e.kind == "word" {
		if len(e.word) == 2 && e.word[0] == 'Y' { return s.year >= int(e.word[1]-'0') }
		return s.passed(e.word) != ""
	}
	if e.kind == "and" {
		for _, child := range e.children { if !satisfied(child, s) { return false } }
		return true
	}
	for _, child := range e.children { if satisfied(child, s) { return true } }
	return false
}

type Decision struct { word string; extra []string }
type Registrar struct {
	courses map[string]*Course
	students map[string]*Student
	commandNumber int
	output []string
}
func newRegistrar() *Registrar {
	return &Registrar{courses: make(map[string]*Course), students: make(map[string]*Student)}
}
func (r *Registrar) emit(indent int, parts ...any) {
	text := make([]string, len(parts))
	for i, x := range parts { text[i] = fmt.Sprint(x) }
	r.output = append(r.output, strings.Repeat(" ", indent)+strings.Join(text, " "))
}
func (r *Registrar) student(id string) (*Student, error) {
	if s := r.students[id]; s != nil { return s, nil }
	return nil, fmt.Errorf("unknown student %s", id)
}
func (r *Registrar) course(code string) (*Course, error) {
	if c := r.courses[code]; c != nil { return c, nil }
	return nil, fmt.Errorf("unknown course %s", code)
}
func (r *Registrar) sortedCourses() []*Course {
	var keys []string
	for id := range r.courses { keys = append(keys, id) }
	sort.Strings(keys)
	var result []*Course
	for _, id := range keys { result = append(result, r.courses[id]) }
	return result
}
func (r *Registrar) taking(s *Student, exclude string) []*Course {
	var codes []string
	for code := range s.taking { if code != exclude { codes = append(codes, code) } }
	sort.Strings(codes)
	var courses []*Course
	for _, code := range codes { courses = append(courses, r.courses[code]) }
	return courses
}
func (r *Registrar) credits(s *Student, exclude string) int {
	total := 0
	for _, c := range r.taking(s, exclude) { total += c.credits }
	return total
}
func indexOf(values []string, needle string) int {
	for i, value := range values { if value == needle { return i } }
	return -1
}
func (r *Registrar) waitlists(s *Student) []*Course {
	var result []*Course
	for _, c := range r.sortedCourses() {
		if indexOf(c.waiting, s.id) != -1 { result = append(result, c) }
	}
	return result
}
func (r *Registrar) conflict(s *Student, target *Course, exclude string) *Course {
	for _, c := range r.taking(s, exclude) {
		for _, first := range c.slots {
			for _, second := range target.slots {
				if first.overlaps(second) { return c }
			}
		}
	}
	return nil
}
func (r *Registrar) eligible(s *Student, c *Course, exclude string) Decision {
	if !c.open { return Decision{word: "course closed"} }
	if c.enrolled[s.id] { return Decision{word: "already enrolled"} }
	if indexOf(c.waiting, s.id) >= 0 { return Decision{word: "already waitlisted"} }
	if grade := s.passed(c.code); grade != "" {
		return Decision{"already completed", []string{grade}}
	}
	if !satisfied(c.prereq, s) { return Decision{word: "prereq not met"} }
	if other := r.conflict(s, c, exclude); other != nil {
		return Decision{"time conflict", []string{other.code}}
	}
	credits := r.credits(s, exclude)+c.credits
	if credits > s.limit {
		return Decision{"credit limit", []string{strconv.Itoa(credits), strconv.Itoa(s.limit)}}
	}
	return Decision{word: "OK"}
}
func (r *Registrar) waitPosition(s *Student, c *Course) int {
	n := 1
	for _, id := range c.waiting { if r.students[id].year >= s.year { n++ } }
	return n
}
func (r *Registrar) judgment(s *Student, c *Course) Decision {
	d := r.eligible(s, c, "")
	if d.word != "OK" { return d }
	if len(c.enrolled) < c.capacity { return Decision{word: "enroll"} }
	if len(r.waitlists(s)) >= 3 { return Decision{word: "waitlist limit"} }
	return Decision{"waitlist", []string{strconv.Itoa(r.waitPosition(s, c))}}
}
func (r *Registrar) reject(s *Student, c *Course, d Decision) error {
	return fmt.Errorf("%s", strings.Join(append([]string{d.word, s.id, c.code}, d.extra...), " "))
}
func (r *Registrar) record(s *Student, event string) {
	s.history = append(s.history, History{r.commandNumber, event})
}
func (r *Registrar) enroll(s *Student, c *Course) {
	c.enrolled[s.id] = true; s.taking[c.code] = true
}
func (r *Registrar) withdraw(s *Student, c *Course) {
	delete(c.enrolled, s.id); delete(s.taking, c.code)
}
func (r *Registrar) enrollmentLine(label string, s *Student, c *Course, indent int) {
	r.emit(indent, label, s.id, c.code, "enrolled",
		fmt.Sprintf("%d/%d", len(c.enrolled), c.capacity),
		"credits", fmt.Sprintf("%d/%d", r.credits(s, ""), s.limit))
}
func (r *Registrar) promote() {
	for _, c := range r.sortedCourses() {
		if !c.open { continue }
		for len(c.enrolled) < c.capacity {
			selected := -1
			for i, id := range c.waiting {
				s := r.students[id]
				if r.conflict(s, c, "") == nil && r.credits(s, "")+c.credits <= s.limit {
					selected = i; break
				}
			}
			if selected < 0 { break }
			id := c.waiting[selected]
			c.waiting = append(c.waiting[:selected], c.waiting[selected+1:]...)
			s := r.students[id]
			r.enroll(s, c)
			r.record(s, "promote "+c.code)
			r.enrollmentLine("PROMOTE", s, c, 2)
		}
	}
}
func (r *Registrar) schedule(s *Student) {
	courses := r.taking(s, "")
	weekly := 0
	for _, c := range courses { weekly += c.weekly() }
	r.emit(0, "SCHEDULE", s.id, "courses", len(courses), "credits",
		r.credits(s, ""), "weekly", clock(weekly))
	type Meeting struct { code string; slot Slot }
	for _, day := range weekdays {
		var meetings []Meeting
		for _, c := range courses {
			for _, slot := range c.slots {
				if slot.day == day { meetings = append(meetings, Meeting{c.code, slot}) }
			}
		}
		sort.Slice(meetings, func(i, j int) bool { return meetings[i].slot.start < meetings[j].slot.start })
		if len(meetings) > 0 {
			parts := []any{day}
			for _, m := range meetings {
				parts = append(parts, clock(m.slot.start)+"-"+clock(m.slot.end), m.code)
			}
			r.emit(2, parts...)
		}
	}
	parts := []any{"TBA"}
	for _, c := range courses { if len(c.slots) == 0 { parts = append(parts, c.code) } }
	if len(parts) > 1 { r.emit(2, parts...) }
}
func (r *Registrar) handle(cmd string, a []string) error {
	switch cmd {
	case "COURSE":
		if r.courses[a[0]] != nil { return fmt.Errorf("duplicate course %s", a[0]) }
		slots, err := readSlots(a[3]); if err != nil { return err }
		tree, err := parsePrereq(a[0], a[4]); if err != nil { return err }
		c := &Course{code: a[0], credits: integer(a[1]), capacity: integer(a[2]),
			slots: slots, prereq: tree, open: true, enrolled: make(map[string]bool)}
		r.courses[c.code] = c
		r.emit(0, "COURSE", c.code, "credits", c.credits, "capacity", c.capacity,
			"meetings", len(slots), "weekly", clock(c.weekly()), "prereq", canonical(tree))
	case "STUDENT":
		if r.students[a[0]] != nil { return fmt.Errorf("duplicate student %s", a[0]) }
		var grades []Grade
		seen := make(map[string]bool)
		if a[3] != "-" {
			for _, token := range strings.Split(a[3], ",") {
				parts := strings.Split(token, ":")
				code, grade := parts[0], parts[1]
				if _, ok := points[grade]; !ok {
					return fmt.Errorf("invalid grade %s %s %s", a[0], code, grade)
				}
				if seen[code] { return fmt.Errorf("duplicate record %s %s", a[0], code) }
				seen[code] = true
				grades = append(grades, Grade{code, grade, integer(parts[2])})
			}
		}
		s := &Student{id: a[0], year: integer(a[1]), limit: integer(a[2]),
			grades: grades, taking: make(map[string]bool)}
		r.students[s.id] = s
		r.emit(0, "STUDENT", s.id, "year", s.year, "limit", s.limit,
			"records", len(grades), "earned", s.earned(), "gpa", s.gpa())
	case "ENROLL", "CHECK":
		s, err := r.student(a[0]); if err != nil { return err }
		c, err := r.course(a[1]); if err != nil { return err }
		d := r.judgment(s, c)
		if cmd == "CHECK" {
			parts := []any{"CHECK", s.id, c.code, d.word}
			for _, value := range d.extra { parts = append(parts, value) }
			r.emit(0, parts...)
		} else if d.word == "enroll" {
			r.enroll(s, c); r.record(s, "enroll "+c.code)
			r.enrollmentLine("ENROLL", s, c, 0)
		} else if d.word == "waitlist" {
			pos := integer(d.extra[0])
			c.waiting = append(c.waiting, "")
			copy(c.waiting[pos:], c.waiting[pos-1:])
			c.waiting[pos-1] = s.id
			r.record(s, fmt.Sprintf("waitlist %s %d", c.code, pos))
			r.emit(0, "ENROLL", s.id, c.code, "waitlist", pos)
		} else { return r.reject(s, c, d) }
	case "OPTIONS":
		s, err := r.student(a[0]); if err != nil { return err }
		r.emit(0, "OPTIONS", s.id, "courses", len(r.courses))
		for _, c := range r.sortedCourses() {
			d := r.judgment(s, c)
			parts := []any{c.code, d.word}
			for _, value := range d.extra { parts = append(parts, value) }
			r.emit(2, parts...)
		}
	case "DROP":
		s, err := r.student(a[0]); if err != nil { return err }
		c, err := r.course(a[1]); if err != nil { return err }
		pos := indexOf(c.waiting, s.id)
		if c.enrolled[s.id] {
			r.withdraw(s, c); r.record(s, "drop "+c.code)
			r.enrollmentLine("DROP", s, c, 0)
		} else if pos >= 0 {
			c.waiting = append(c.waiting[:pos], c.waiting[pos+1:]...)
			r.record(s, "drop "+c.code+" waitlist")
			r.emit(0, "DROP", s.id, c.code, "waitlist", "removed")
		} else { return fmt.Errorf("not registered %s %s", s.id, c.code) }
		r.promote()
	case "SWAP":
		s, err := r.student(a[0]); if err != nil { return err }
		old, err := r.course(a[1]); if err != nil { return err }
		next, err := r.course(a[2]); if err != nil { return err }
		if !old.enrolled[s.id] { return fmt.Errorf("not enrolled %s %s", s.id, old.code) }
		if old == next { return fmt.Errorf("same course %s", old.code) }
		d := r.eligible(s, next, old.code)
		if d.word != "OK" { return r.reject(s, next, d) }
		if len(next.enrolled) >= next.capacity { return fmt.Errorf("course full %s", next.code) }
		r.withdraw(s, old); r.enroll(s, next)
		r.record(s, "swap "+old.code+" "+next.code)
		r.emit(0, "SWAP", s.id, old.code, "->", next.code, "credits",
			fmt.Sprintf("%d/%d", r.credits(s, ""), s.limit))
		r.promote()
	case "CLOSE", "OPEN":
		c, err := r.course(a[0]); if err != nil { return err }
		if c.open == (cmd == "OPEN") {
			status := "closed"
			if cmd == "OPEN" { status = "open" }
			return fmt.Errorf("already %s %s", status, c.code)
		}
		c.open = cmd == "OPEN"
		r.emit(0, cmd, c.code, "enrolled",
			fmt.Sprintf("%d/%d", len(c.enrolled), c.capacity), "waitlist", len(c.waiting))
		if cmd == "OPEN" { r.promote() }
	case "CAPACITY":
		c, err := r.course(a[0]); if err != nil { return err }
		capacity := integer(a[1])
		if capacity < len(c.enrolled) {
			return fmt.Errorf("capacity below enrollment %s %d", c.code, len(c.enrolled))
		}
		old := c.capacity; c.capacity = capacity
		r.emit(0, "CAPACITY", c.code, old, "->", capacity)
		r.promote()
	case "LIMIT":
		s, err := r.student(a[0]); if err != nil { return err }
		limit := integer(a[1]); credits := r.credits(s, "")
		if limit < credits { return fmt.Errorf("limit below enrolled %s %d", s.id, credits) }
		old := s.limit; s.limit = limit
		r.emit(0, "LIMIT", s.id, old, "->", limit)
		r.promote()
	case "PREREQ":
		c, err := r.course(a[0]); if err != nil { return err }
		tree, err := parsePrereq(c.code, a[1]); if err != nil { return err }
		c.prereq = tree; r.emit(0, "PREREQ", c.code, canonical(tree))
		var remaining []string
		for _, id := range c.waiting {
			s := r.students[id]
			if satisfied(tree, s) { remaining = append(remaining, id) } else {
				r.record(s, "unlist "+c.code); r.emit(2, "UNLIST", s.id, c.code)
			}
		}
		c.waiting = remaining
	case "CANCEL":
		c, err := r.course(a[0]); if err != nil { return err }
		r.emit(0, "CANCEL", c.code, "enrolled", len(c.enrolled), "waitlist", len(c.waiting))
		for id := range c.enrolled {
			s := r.students[id]; delete(s.taking, c.code); r.record(s, "cancel "+c.code)
		}
		for _, id := range c.waiting { r.record(r.students[id], "cancel "+c.code+" waitlist") }
		delete(r.courses, c.code); r.promote()
	case "ROSTER":
		c, err := r.course(a[0]); if err != nil { return err }
		r.emit(0, "ROSTER", c.code, c.status(), "enrolled",
			fmt.Sprintf("%d/%d", len(c.enrolled), c.capacity), "waitlist", len(c.waiting))
		ids := make([]string, 0, len(c.enrolled))
		for id := range c.enrolled { ids = append(ids, id) }
		sort.Strings(ids)
		for _, id := range ids { r.emit(2, "enrolled", id, "year", r.students[id].year) }
		for i, id := range c.waiting { r.emit(2, "waitlist", i+1, id, "year", r.students[id].year) }
	case "SCHEDULE":
		s, err := r.student(a[0]); if err != nil { return err }
		r.schedule(s)
	case "FREE":
		s, err := r.student(a[0]); if err != nil { return err }
		day := a[1]
		if dayIndex(day) < 0 { return fmt.Errorf("invalid day %s", day) }
		var meetings []Slot
		for _, c := range r.taking(s, "") {
			for _, slot := range c.slots {
				if slot.day == day && slot.start < 1320 && slot.end > 480 {
					meetings = append(meetings, slot)
				}
			}
		}
		sort.Slice(meetings, func(i,j int) bool { return meetings[i].start < meetings[j].start })
		type Interval struct { start, end int }
		var ranges []Interval
		cursor := 480
		for _, slot := range meetings {
			start := slot.start
			if start < 480 { start = 480 }
			if start > cursor { ranges = append(ranges, Interval{cursor, start}) }
			end := slot.end
			if end > 1320 { end = 1320 }
			if end > cursor { cursor = end }
		}
		if cursor < 1320 { ranges = append(ranges, Interval{cursor, 1320}) }
		total := 0
		for _, rg := range ranges { total += rg.end-rg.start }
		parts := []any{"FREE", s.id, day, "total", clock(total)}
		for _, rg := range ranges { parts = append(parts, clock(rg.start)+"-"+clock(rg.end)) }
		r.emit(0, parts...)
	case "INFO":
		c, err := r.course(a[0]); if err != nil { return err }
		r.emit(0, "INFO", c.code, c.status(), "credits", c.credits,
			"capacity", c.capacity, "prereq", canonical(c.prereq))
		slots := append([]Slot(nil), c.slots...)
		sort.Slice(slots, func(i,j int) bool {
			if slots[i].day != slots[j].day { return dayIndex(slots[i].day) < dayIndex(slots[j].day) }
			return slots[i].start < slots[j].start
		})
		if len(slots) == 0 { r.emit(2, "meet", "TBA") } else {
			for _, slot := range slots {
				r.emit(2, "meet", slot.day, clock(slot.start)+"-"+clock(slot.end))
			}
		}
		parts := []any{"required", "by"}
		for _, other := range r.sortedCourses() {
			if refersTo(other.prereq, c.code) { parts = append(parts, other.code) }
		}
		if len(parts) == 2 { parts = append(parts, "none") }
		r.emit(2, parts...)
	case "AUDIT":
		s, err := r.student(a[0]); if err != nil { return err }
		r.emit(0, "AUDIT", s.id, "year", s.year, "limit", s.limit)
		grades := append([]Grade(nil), s.grades...)
		sort.Slice(grades, func(i,j int) bool { return grades[i].code < grades[j].code })
		for _, grade := range grades { r.emit(2, "record", grade.code, grade.grade, grade.credits) }
		r.emit(2, "earned", s.earned(), "gpa", s.gpa())
		for _, c := range r.taking(s, "") { r.emit(2, "enrolled", c.code, c.credits) }
		credits := r.credits(s, "")
		r.emit(2, "credits", credits, "remaining", s.limit-credits)
		for _, c := range r.waitlists(s) {
			r.emit(2, "waitlist", c.code, indexOf(c.waiting, s.id)+1)
		}
	case "HISTORY":
		s, err := r.student(a[0]); if err != nil { return err }
		r.emit(0, "HISTORY", s.id, "events", len(s.history))
		for _, history := range s.history { r.emit(2, history.command, history.event) }
	case "STUDENTS":
		var ids []string
		for id := range r.students { ids = append(ids, id) }
		sort.Strings(ids)
		r.emit(0, "STUDENTS", len(r.students))
		for _, id := range ids {
			s := r.students[id]
			r.emit(2, s.id, "year", s.year, "credits",
				fmt.Sprintf("%d/%d", r.credits(s, ""), s.limit), "courses",
				len(s.taking), "waitlists", len(r.waitlists(s)))
		}
	case "REPORT":
		courses := r.sortedCourses()
		enrolled, capacity, waiting := 0, 0, 0
		departments := make(map[string][]*Course)
		for _, c := range courses {
			enrolled += len(c.enrolled); capacity += c.capacity; waiting += len(c.waiting)
			departments[c.department()] = append(departments[c.department()], c)
		}
		r.emit(0, "REPORT", "courses", len(courses), "enrolled",
			fmt.Sprintf("%d/%d", enrolled, capacity), "rate", rate(enrolled, capacity),
			"waitlisted", waiting)
		for _, c := range courses {
			r.emit(2, c.code, c.status(), fmt.Sprintf("%d/%d", len(c.enrolled), c.capacity),
				rate(len(c.enrolled), c.capacity), "waitlist", len(c.waiting))
		}
		var names []string
		for name := range departments { names = append(names, name) }
		sort.Strings(names)
		for _, name := range names {
			group := departments[name]
			k, m, q := 0, 0, 0
			for _, c := range group { k += len(c.enrolled); m += c.capacity; q += len(c.waiting) }
			r.emit(2, "dept", name, "courses", len(group), "enrolled",
				fmt.Sprintf("%d/%d", k, m), "rate", rate(k, m), "waitlisted", q)
		}
	}
	return nil
}
func (r *Registrar) execute(line string) {
	r.commandNumber++
	parts := strings.Fields(line)
	if err := r.handle(parts[0], parts[1:]); err != nil { r.emit(0, "ERROR", err.Error()) }
}
func main() {
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Scan()
	count := integer(scanner.Text())
	r := newRegistrar()
	for i := 0; i < count && scanner.Scan(); i++ { r.execute(scanner.Text()) }
	writer := bufio.NewWriter(os.Stdout)
	defer writer.Flush()
	for _, line := range r.output { fmt.Fprintln(writer, line) }
}
