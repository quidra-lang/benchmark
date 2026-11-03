package main

import (
	"fmt"
	"os"
	"strings"
)

func decimal(p, q int) string {
	n := (2*p*10000 + q) / (2 * q)
	return fmt.Sprintf("%d.%04d", n/10000, n%10000)
}
func percent(p, q int) string {
	if q == 0 {
		return "-"
	}
	n := (2*p*10000 + q) / (2 * q)
	return fmt.Sprintf("%d.%02d", n/100, n%100)
}
func fraction(p, q int) string {
	a, b := p, q
	for b != 0 {
		a, b = b, a%b
	}
	return fmt.Sprint(p/a, "/", q/a)
}
func hex(pc int) string { return fmt.Sprintf("%08x", pc) }
func registerText(r int) string {
	if r < 0 {
		return "-"
	}
	return fmt.Sprint("r", r)
}
func writeLines(name string, lines []string) {
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	if e := os.WriteFile("output/"+name, []byte(strings.Join(lines, "\n")+"\n"), 0644); e != nil {
		panic(e)
	}
}

type Span struct {
	First, Last int
	Character   byte
	Stage       int
}
type DiagramRow struct {
	Instruction, PC int
	Class           string
	Wrong           bool
	Spans           []Span
	Annotation      string
}

func (r DiagramRow) render(start, end int) (string, bool, int, int) {
	cells := []byte(strings.Repeat(".", end-start+1))
	visible := false
	for _, s := range r.Spans {
		for c := max(start, s.First); c <= min(end, s.Last); c++ {
			cells[c-start] = s.Character
			visible = true
		}
	}
	stars, flush := 0, 0
	for _, c := range cells {
		if c == '*' {
			stars++
		}
		if c == 'x' {
			flush++
		}
	}
	left := fmt.Sprintf("%6d %s %-6s ", r.Instruction+1, hex(r.PC), r.Class)
	if r.Wrong {
		left = fmt.Sprintf("     - %s FLUSH  ", hex(r.PC))
	}
	return left + string(cells) + r.Annotation, visible, stars, flush
}
func cycleDigits(start, end int) string {
	b := make([]byte, end-start+1)
	for c := start; c <= end; c++ {
		b[c-start] = byte('0' + c%10)
	}
	return string(b)
}
