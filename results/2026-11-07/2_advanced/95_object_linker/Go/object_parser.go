package main

import (
	"bufio"
	"encoding/hex"
	"os"
	"strconv"
	"strings"
)

type Object struct {
	Name         string
	Rank         int
	Sections     []*Section
	Symbols      []*Symbol
	Groups       []COMDATGroup
	SectionNames map[string]*Section
	SymbolNames  map[string]*Symbol
}
type Section struct {
	Name                     string
	Alignment, Size, Address int64
	Data                     []byte
	Object                   *Object
	Relocations              []*Relocation
	Reason                   string
	Output                   *OutputSection
	Live                     bool
	Merged                   *Component
	StringOffsets            map[int64]int64
}
type Symbol struct {
	Name, Binding, Location string
	Section                 *Section
	Offset, Size, Alignment int64
	Object                  *Object
}
type Relocation struct {
	Section        *Section
	Offset, Addend int64
	Type           string
	Symbol         *Symbol
}
type COMDATGroup struct {
	Signature string
	Sections  []*Section
}

func belongs(name, base string) bool   { return name == base || strings.HasPrefix(name, base+".") }
func (s *Section) nobits() bool        { return belongs(s.Name, ".bss") }
func (s *Section) stringSection() bool { return belongs(s.Name, ".rodata.str") }
func readLines(path string) []string {
	file, err := os.Open(path)
	if err != nil {
		panic(err)
	}
	defer file.Close()
	out := []string{}
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 4096), 1024*1024)
	for scanner.Scan() {
		out = append(out, scanner.Text())
	}
	if err = scanner.Err(); err != nil {
		panic(err)
	}
	return out
}
func number(text string) int64 {
	base := 10
	if strings.HasPrefix(text, "0x") {
		base = 16
		text = text[2:]
	}
	n, err := strconv.ParseInt(text, base, 64)
	if err != nil {
		panic(err)
	}
	return n
}
func parseObject(lines []string, name string) *Object {
	o := &Object{Name: name, SectionNames: map[string]*Section{}, SymbolNames: map[string]*Symbol{}}
	var current *Section
	for _, line := range lines {
		a := strings.Split(line, " ")
		switch a[0] {
		case "section":
			current = &Section{Name: a[1], Alignment: number(a[2]), Size: number(a[3]), Object: o}
			o.Sections = append(o.Sections, current)
			o.SectionNames[current.Name] = current
		case "data":
			bytes, err := hex.DecodeString(a[1])
			if err != nil {
				panic(err)
			}
			current.Data = append(current.Data, bytes...)
		case "comdat":
			g := COMDATGroup{Signature: a[1]}
			for _, name := range a[2:] {
				g.Sections = append(g.Sections, o.SectionNames[name])
			}
			o.Groups = append(o.Groups, g)
		case "symbol":
			s := &Symbol{Name: a[1], Binding: a[2], Location: a[3], Object: o}
			if a[3] == "common" {
				s.Size = number(a[4])
				s.Alignment = number(a[5])
			} else if a[3] != "undef" {
				s.Location = "section"
				s.Section = o.SectionNames[a[3]]
				s.Offset = number(a[4])
			}
			o.Symbols = append(o.Symbols, s)
			o.SymbolNames[s.Name] = s
		case "reloc":
			r := &Relocation{Section: o.SectionNames[a[1]], Offset: number(a[2]), Type: a[3], Symbol: o.SymbolNames[a[4]], Addend: number(a[5])}
			r.Section.Relocations = append(r.Section.Relocations, r)
		}
	}
	return o
}
