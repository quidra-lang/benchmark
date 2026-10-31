package main

import "strings"

type Section struct {
	name                     string
	length, row, first, last int
	failed                   bool
	occupants                []*Train
	route                    *Route
	overlaps                 map[*Route]bool
	occupiedTicks,
	lockedTicks int
	trains map[*Train]bool
}

func (s *Section) occupied() bool { return s.failed || len(s.occupants) > 0 }

type PointLock struct {
	route    *Route
	position string
}
type Point struct {
	name, side              string
	common, normal, reverse *Section
	row, col                int
	position, target        string
	moving,
	failed bool
	completion, throws, lockedTicks, movingTicks int
	locks                                        []PointLock
}

func (p *Point) detected() bool { return !p.moving && !p.failed }

type Signal struct {
	name, direction            string
	section                    *Section
	row, col                   int
	aspect                     string
	red, yellow, green, passes int
}
type Buffer struct {
	name, end string
	section   *Section
	row, col  int
}
type Boundary struct {
	name, end string
	section   *Section
}
type Label struct {
	row, col int
	text     string
}
type Endpoint struct {
	kind, name, branch string
	section            *Section
	point              *Point
}
type Layout struct {
	sections       []*Section
	points         []*Point
	signals        []*Signal
	buffers        []*Buffer
	boundaries     []*Boundary
	labels         []Label
	sectionByName  map[string]*Section
	pointByName    map[string]*Point
	signalByName   map[string]*Signal
	bufferByName   map[string]*Buffer
	boundaryByName map[string]*Boundary
	ends           map[string]Endpoint
	signalAt       map[string]*Signal
	height,
	width int
}

func endKey(section *Section, end string) string { return section.name + ":" + end }
func readLayout() *Layout {
	l := &Layout{sectionByName: map[string]*Section{}, pointByName: map[string]*Point{},
		signalByName: map[string]*Signal{}, bufferByName: map[string]*Buffer{}, boundaryByName: map[string]*Boundary{},
		ends: map[string]Endpoint{}, signalAt: map[string]*Signal{}}
	position := func(row, col int) {
		l.height = max(l.height,
			row+1)
		l.width = max(l.width, col+1)
	}
	for _, line := range readLines("input/layout.txt") {
		a := strings.Fields(line)
		switch a[0] {
		case "SECTION":
			s := &Section{name: a[1],
				length: number(a[2]), row: number(a[3]), first: number(a[4]), last: number(a[5]), overlaps: map[*Route]bool{},
				trains: map[*Train]bool{}}
			l.sections = append(l.sections, s)
			l.sectionByName[s.name] = s
			position(s.row,
				s.last)
		case "JOINT":
			x, y := l.sectionByName[a[1]], l.sectionByName[a[2]]
			l.ends[endKey(x, "R")] = Endpoint{kind: "section",
				section: y}
			l.ends[endKey(y, "L")] = Endpoint{kind: "section", section: x}
		case "POINT":
			p := &Point{name: a[1], side: a[2], common: l.sectionByName[a[3]], normal: l.sectionByName[a[4]],
				reverse: l.sectionByName[a[5]], row: number(a[6]), col: number(a[7]), position: "N", completion: -1}
			l.points = append(l.points,
				p)
			l.pointByName[p.name] = p
			position(p.row, p.col)
			branchEnd := "L"
			if p.side == "L" {
				branchEnd = "R"
			}
			l.ends[endKey(p.common,
				p.side)] = Endpoint{kind: "point", point: p, branch: "common"}
			l.ends[endKey(p.normal, branchEnd)] = Endpoint{kind: "point",
				point: p, branch: "normal"}
			l.ends[endKey(p.reverse, branchEnd)] = Endpoint{kind: "point", point: p, branch: "reverse"}
		case "SIGNAL":
			g := &Signal{name: a[1], section: l.sectionByName[a[2]], direction: a[3], row: number(a[4]),
				col: number(a[5]), aspect: "RED"}
			l.signals = append(l.signals, g)
			l.signalByName[g.name] = g
			l.signalAt[g.section.name+":"+g.direction] = g
			position(g.row,
				g.col)
		case "BUFFER":
			b := &Buffer{name: a[1], section: l.sectionByName[a[2]], end: a[3], row: number(a[4]), col: number(a[5])}
			l.buffers = append(l.buffers,
				b)
			l.bufferByName[b.name] = b
			l.ends[endKey(b.section, b.end)] = Endpoint{kind: "buffer", name: b.name}
			position(b.row,
				b.col)
		case "BOUNDARY":
			b := &Boundary{name: a[1], section: l.sectionByName[a[2]], end: a[3]}
			l.boundaries = append(l.boundaries,
				b)
			l.boundaryByName[b.name] = b
			l.ends[endKey(b.section, b.end)] = Endpoint{kind: "boundary", name: b.name}
		case "LABEL":
			label := Label{number(a[1]), number(a[2]), a[3]}
			l.labels = append(l.labels, label)
			position(label.row, label.col+len(label.text)-1)
		}
	}
	return l
}
func (l *Layout) beyond(section *Section, direction string) Endpoint {
	end := "R"
	if direction == "DOWN" {
		end = "L"
	}
	e := l.ends[endKey(section,
		end)]
	if e.kind != "point" {
		return e
	}
	p := e.point
	if p.moving {
		return Endpoint{kind: "impassable"}
	}
	selected := p.normal
	if p.position == "R" {
		selected = p.reverse
	}
	if e.branch == "common" {
		return Endpoint{kind: "section",
			section: selected}
	}
	if selected != section {
		return Endpoint{kind: "impassable"}
	}
	return Endpoint{kind: "section",
		section: p.common}
}
