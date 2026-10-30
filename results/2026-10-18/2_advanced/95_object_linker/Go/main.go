package main

import (
	"fmt"
	"os"
	"sort"
	"strings"
)

type ScriptDefinition struct{ Name, Expression string }
type Input struct {
	Kind  string
	Names []string
}
type Script struct {
	Entry                           string
	GC                              bool
	Segments                        []*Segment
	Outputs                         []*OutputSection
	SegmentNames                    map[string]*Segment
	OutputNames                     map[string]*OutputSection
	Loads                           [][2]string
	Keep, Sort, Wrap, ScriptNames   map[string]bool
	Definitions                     []ScriptDefinition
	ChecksumSegment, ChecksumSymbol string
	Inputs                          []Input
}

func readScript() *Script {
	s := &Script{SegmentNames: map[string]*Segment{}, OutputNames: map[string]*OutputSection{}, Keep: map[string]bool{}, Sort: map[string]bool{}, Wrap: map[string]bool{}, ScriptNames: map[string]bool{}}
	for _, line := range readLines("input/link.txt") {
		a := strings.Split(line, " ")
		switch a[0] {
		case "entry":
			s.Entry = a[1]
		case "gc":
			s.GC = a[1] == "on"
		case "segment":
			segment := &Segment{Name: a[1], Base: number(a[2]), Length: number(a[3]), Fill: number(a[4])}
			s.Segments = append(s.Segments, segment)
			s.SegmentNames[segment.Name] = segment
			for _, name := range a[5:] {
				o := &OutputSection{Name: name, Segment: segment}
				segment.Sections = append(segment.Sections, o)
				s.Outputs = append(s.Outputs, o)
				s.OutputNames[name] = o
			}
		case "load":
			s.Loads = append(s.Loads, [2]string{a[1], a[2]})
		case "keep":
			s.Keep[a[1]] = true
		case "sort":
			s.Sort[a[1]] = true
		case "wrap":
			s.Wrap[a[1]] = true
		case "define":
			parts := strings.SplitN(line, " = ", 2)
			s.Definitions = append(s.Definitions, ScriptDefinition{a[1], parts[1]})
			s.ScriptNames[a[1]] = true
		case "checksum":
			s.ChecksumSegment = a[1]
			s.ChecksumSymbol = a[2]
		default:
			s.Inputs = append(s.Inputs, Input{a[0], a[1:]})
		}
	}
	return s
}

type COMDATRecord struct {
	Keeper     *Object
	Discarders []string
}
type Linker struct {
	Script                                 *Script
	Objects                                []*Object
	Entries                                map[string][]*Symbol
	Archives                               map[string]*Archive
	Extractions                            []Extraction
	COMDAT                                 map[string]*COMDATRecord
	COMDATOrder                            []string
	Names                                  map[string]*Resolution
	OrderedNames                           []string
	Orphans                                map[string]int
	Veneers                                map[VeneerPair]bool
	VeneerComponents                       map[VeneerPair]*Component
	ScriptValues                           map[string]int64
	RelocationLines, RelocationDiagnostics []string
	RelocationCounts                       map[string]map[string]int
}

func newLinker(script *Script) *Linker {
	return &Linker{Script: script, Entries: map[string][]*Symbol{}, Archives: map[string]*Archive{}, COMDAT: map[string]*COMDATRecord{}, Names: map[string]*Resolution{}, Orphans: map[string]int{}, Veneers: map[VeneerPair]bool{}, ScriptValues: map[string]int64{}, RelocationCounts: map[string]map[string]int{}}
}
func (l *Linker) load(o *Object) {
	o.Rank = len(l.Objects)
	for _, group := range o.Groups {
		if previous := l.COMDAT[group.Signature]; previous != nil {
			for _, section := range group.Sections {
				section.Reason = "comdat"
			}
			previous.Discarders = append(previous.Discarders, o.Name)
		} else {
			l.COMDAT[group.Signature] = &COMDATRecord{Keeper: o}
			l.COMDATOrder = append(l.COMDATOrder, group.Signature)
		}
	}
	for _, s := range o.Symbols {
		if s.Binding == "local" {
			continue
		}
		if s.Location == "section" && s.Section.Reason == "comdat" {
			s.Location = "undef"
			s.Section = nil
		}
		if s.Location == "undef" {
			if l.Script.Wrap[s.Name] {
				s.Name = "__wrap_" + s.Name
			} else if strings.HasPrefix(s.Name, "__real_") && l.Script.Wrap[strings.TrimPrefix(s.Name, "__real_")] {
				s.Name = strings.TrimPrefix(s.Name, "__real_")
			}
		}
		l.Entries[s.Name] = append(l.Entries[s.Name], s)
	}
	l.Objects = append(l.Objects, o)
}
func (l *Linker) defined(name string) bool {
	if l.Script.ScriptNames[name] {
		return true
	}
	for _, entry := range l.Entries[name] {
		if entry.Location != "undef" {
			return true
		}
	}
	return false
}
func (l *Linker) undefined(name string) bool {
	if l.defined(name) {
		return false
	}
	if name == l.Script.Entry {
		return true
	}
	for _, entry := range l.Entries[name] {
		if entry.Binding == "global" && entry.Location == "undef" {
			return true
		}
	}
	return false
}
func (l *Linker) referrer(name string) string {
	for _, entry := range l.Entries[name] {
		if entry.Location == "undef" && entry.Binding == "global" {
			return entry.Object.Name
		}
	}
	return "*entry*"
}
func (l *Linker) scan(name string) int {
	archive := l.Archives[name]
	if archive == nil {
		archive = readArchive(name)
		l.Archives[name] = archive
	}
	return scanArchive(archive, l.undefined, l.referrer, l.load, func(record Extraction) { l.Extractions = append(l.Extractions, record) })
}
func (l *Linker) loadInputs() {
	for _, input := range l.Script.Inputs {
		switch input.Kind {
		case "object":
			name := input.Names[0]
			l.load(parseObject(readLines("input/"+name), name))
		case "library":
			l.scan(input.Names[0])
		case "group":
			for {
				count := 0
				for _, name := range input.Names {
					count += l.scan(name)
				}
				if count == 0 {
					break
				}
			}
		}
	}
}
func sortedKeys[V any](m map[string]V) []string {
	keys := []string{}
	for key := range m {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}
func (l *Linker) resolve() {
	names := map[string]bool{}
	for name := range l.Entries {
		names[name] = true
	}
	for name := range l.Script.ScriptNames {
		names[name] = true
	}
	l.OrderedNames = sortedKeys(names)
	for _, name := range l.OrderedNames {
		l.Names[name] = resolveName(name, l.Entries[name], l.Script.ScriptNames[name])
	}
}
func (l *Linker) collect() {
	for _, o := range l.Objects {
		for _, s := range o.Sections {
			if s.Reason == "comdat" {
				continue
			}
			s.Output = outputFor(s, l.Script.Outputs)
			if s.Output == nil {
				s.Reason = "orphan"
				l.Orphans[s.Name]++
			} else if !l.Script.GC {
				s.Live = true
			}
		}
	}
	if !l.Script.GC {
		for _, r := range l.Names {
			if r.Kind == "common" {
				r.Live = true
			}
		}
		return
	}
	queue := []*Section{}
	mark := func(s *Section) {
		if s != nil && s.Reason == "" && s.Output != nil && !s.Live {
			s.Live = true
			queue = append(queue, s)
		}
	}
	for _, o := range l.Objects {
		for _, s := range o.Sections {
			if s.Output != nil && l.Script.Keep[s.Output.Name] {
				mark(s)
			}
		}
	}
	if entry := l.Names[l.Script.Entry]; entry != nil {
		if entry.Kind == "global" || entry.Kind == "weak" {
			mark(entry.Definition.Section)
		} else if entry.Kind == "common" {
			entry.Live = true
		}
	}
	for head := 0; head < len(queue); head++ {
		for _, relocation := range queue[head].Relocations {
			symbol := relocation.Symbol
			if symbol.Binding == "local" {
				mark(symbol.Section)
			} else {
				r := l.Names[symbol.Name]
				if r.Kind == "global" || r.Kind == "weak" {
					mark(r.Definition.Section)
				} else if r.Kind == "common" {
					r.Live = true
				}
			}
		}
	}
	for _, o := range l.Objects {
		for _, s := range o.Sections {
			if s.Output != nil && s.Reason == "" && !s.Live {
				s.Reason = "gc"
			}
		}
	}
}
func priority(s *Section, o *OutputSection) int64 {
	if s.Name == o.Name {
		return 65536
	}
	return number(strings.TrimPrefix(s.Name, o.Name+"."))
}
func (l *Linker) components(o *OutputSection) []*Component {
	sections := []*Section{}
	for _, object := range l.Objects {
		for _, section := range object.Sections {
			if section.Live && section.Output == o {
				sections = append(sections, section)
			}
		}
	}
	if l.Script.Sort[o.Name] {
		sort.SliceStable(sections, func(i, j int) bool { return priority(sections[i], o) < priority(sections[j], o) })
	}
	stringsSections := []*Section{}
	for _, s := range sections {
		if s.stringSection() {
			stringsSections = append(stringsSections, s)
		}
	}
	var merged *Component
	if len(stringsSections) > 0 {
		merged = &Component{Kind: "merged", Alignment: 1, StringSections: len(stringsSections)}
		seen := map[string]int64{}
		for _, s := range stringsSections {
			s.Merged = merged
			s.StringOffsets = map[int64]int64{}
			merged.OriginalSize += s.Size
			for start := 0; start < len(s.Data); {
				end := start
				for s.Data[end] != 0 {
					end++
				}
				end++
				value := string(s.Data[start:end])
				offset, found := seen[value]
				if !found {
					offset = int64(len(merged.Data))
					seen[value] = offset
					merged.Data = append(merged.Data, s.Data[start:end]...)
					merged.Unique++
				}
				s.StringOffsets[int64(start)] = offset
				merged.Strings++
				start = end
			}
		}
		merged.Size = int64(len(merged.Data))
	}
	out := []*Component{}
	inserted := false
	for _, s := range sections {
		if s.stringSection() {
			if !inserted {
				out = append(out, merged)
				inserted = true
			}
		} else {
			out = append(out, &Component{Kind: "section", Size: s.Size, Alignment: s.Alignment, Section: s})
		}
	}
	if o.Name == ".bss" {
		common := []*Resolution{}
		for _, name := range l.OrderedNames {
			r := l.Names[name]
			if r.Kind == "common" && r.Live {
				common = append(common, r)
			}
		}
		sort.Slice(common, func(i, j int) bool {
			if common[i].Alignment != common[j].Alignment {
				return common[i].Alignment > common[j].Alignment
			}
			return common[i].Name < common[j].Name
		})
		for _, r := range common {
			out = append(out, &Component{Kind: "common", Size: r.Size, Alignment: r.Alignment, Common: r})
		}
	}
	targets := []string{}
	for pair := range l.Veneers {
		if pair.Output == o {
			targets = append(targets, pair.Target)
		}
	}
	sort.Strings(targets)
	for _, target := range targets {
		out = append(out, &Component{Kind: "veneer", Size: 8, Alignment: 4, Target: target})
	}
	return out
}
func sectionValue(section *Section, offset int64) int64 {
	if section.stringSection() {
		return section.Merged.Address + section.StringOffsets[offset]
	}
	return section.Address + offset
}
func (l *Linker) nameValue(name string) (int64, bool) {
	r := l.Names[name]
	switch r.Kind {
	case "global", "weak":
		return sectionValue(r.Definition.Section, r.Definition.Offset), true
	case "common":
		return r.Address, true
	case "script":
		return l.ScriptValues[name], true
	case "weakundef":
		return 0, true
	}
	return 0, false
}
func (l *Linker) symbolValue(s *Symbol) (int64, bool) {
	if s.Binding == "local" {
		return sectionValue(s.Section, s.Offset), true
	}
	return l.nameValue(s.Name)
}
func (l *Linker) farCall(r *Relocation) bool {
	if r.Type != "CALL24" || r.Symbol.Binding == "local" {
		return false
	}
	name := l.Names[r.Symbol.Name]
	if name.Kind != "global" && name.Kind != "weak" {
		return false
	}
	s, _ := l.nameValue(r.Symbol.Name)
	v := s + r.Addend - (r.Section.Address + r.Offset)
	return v < -(1<<25) || v >= 1<<25
}
func (l *Linker) layout() {
	for {
		l.VeneerComponents = map[VeneerPair]*Component{}
		for _, segment := range l.Script.Segments {
			for _, o := range segment.Sections {
				o.Components = l.components(o)
			}
			placeSegment(segment)
			for _, o := range segment.Sections {
				for _, c := range o.Components {
					if c.Kind == "veneer" {
						l.VeneerComponents[VeneerPair{o, c.Target}] = c
					}
				}
			}
		}
		changed := false
		for _, object := range l.Objects {
			for _, section := range object.Sections {
				if !section.Live {
					continue
				}
				for _, r := range section.Relocations {
					if l.farCall(r) {
						pair := VeneerPair{section.Output, r.Symbol.Name}
						if !l.Veneers[pair] {
							l.Veneers[pair] = true
							changed = true
						}
					}
				}
			}
		}
		if !changed {
			return
		}
	}
}
func (l *Linker) loadAddresses() {
	positions := map[string]int64{}
	for _, segment := range l.Script.Segments {
		segment.Physical = segment.Base
		positions[segment.Name] = segment.Base + segment.MemorySize
	}
	for _, load := range l.Script.Loads {
		a, b := l.Script.SegmentNames[load[0]], l.Script.SegmentNames[load[1]]
		a.Physical = aligned(positions[b.Name], 4)
		positions[b.Name] = a.Physical + a.FileSize
	}
	for _, segment := range l.Script.Segments {
		segment.Used = positions[segment.Name] - segment.Base
	}
}

type ScriptExpression struct {
	Tokens []string
	Index  int
	Linker *Linker
}

func expressionTokens(source string) []string {
	out := []string{}
	for i := 0; i < len(source); {
		if source[i] == ' ' {
			i++
			continue
		}
		if strings.ContainsRune("(),+-", rune(source[i])) {
			out = append(out, source[i:i+1])
			i++
			continue
		}
		start := i
		for i < len(source) && source[i] != ' ' && !strings.ContainsRune("(),+-", rune(source[i])) {
			i++
		}
		out = append(out, source[start:i])
	}
	return out
}
func (e *ScriptExpression) peek() string {
	if e.Index == len(e.Tokens) {
		return ""
	}
	return e.Tokens[e.Index]
}
func (e *ScriptExpression) expression() int64 {
	value := e.term()
	for e.peek() == "+" || e.peek() == "-" {
		op := e.peek()
		e.Index++
		right := e.term()
		if op == "+" {
			value += right
		} else {
			value -= right
		}
	}
	return value
}
func (e *ScriptExpression) term() int64 {
	token := e.Tokens[e.Index]
	e.Index++
	if token == "(" {
		value := e.expression()
		e.Index++
		return value
	}
	if token[0] >= '0' && token[0] <= '9' {
		return number(token)
	}
	if e.peek() == "(" && wordIn("start end size loadaddr align", token) {
		e.Index++
		if token == "align" {
			x := e.expression()
			e.Index++
			n := e.expression()
			e.Index++
			return aligned(x, n)
		}
		output := e.Linker.Script.OutputNames[e.Tokens[e.Index]]
		e.Index += 2
		switch token {
		case "start":
			return output.Address
		case "end":
			return output.Address + output.Size
		case "size":
			return output.Size
		case "loadaddr":
			return output.Segment.Physical + output.Address - output.Segment.Base
		}
	}
	return e.Linker.ScriptValues[token]
}
func wordIn(words, value string) bool {
	for _, word := range strings.Fields(words) {
		if word == value {
			return true
		}
	}
	return false
}
func (l *Linker) defineScriptSymbols() {
	for _, definition := range l.Script.Definitions {
		reader := ScriptExpression{Tokens: expressionTokens(definition.Expression), Linker: l}
		l.ScriptValues[definition.Name] = reader.expression()
	}
}
func relocationLocation(r *Relocation) string {
	return fmt.Sprintf("%s %s+%d", r.Section.Object.Name, r.Section.Name, r.Offset)
}
func (l *Linker) relocate() {
	for _, kind := range relocationTypes {
		l.RelocationCounts[kind] = map[string]int{}
	}
	for _, segment := range l.Script.Segments {
		for _, output := range segment.Sections {
			for _, component := range output.Components {
				if component.Kind != "section" {
					continue
				}
				section := component.Section
				for i, r := range section.Relocations {
					if unpaired(section.Relocations, i) {
						l.RelocationDiagnostics = append(l.RelocationDiagnostics, "error: unpaired HI16 at "+relocationLocation(r)+" against "+r.Symbol.Name)
					}
					p := section.Address + r.Offset
					s, defined := l.symbolValue(r.Symbol)
					status := "undefined"
					value, field := "-", "-"
					shownSymbol := "-"
					if defined {
						status = "ok"
						if l.farCall(r) {
							s = l.VeneerComponents[VeneerPair{output, r.Symbol.Name}].Address
							status = "veneer"
						}
						v, f, valid := relocationField(r.Type, s, r.Addend, p, l.ScriptValues["_gp"])
						if !valid {
							status = "overflow"
							l.RelocationDiagnostics = append(l.RelocationDiagnostics, fmt.Sprintf("error: relocation overflow at %s: %s value %d against %s", relocationLocation(r), r.Type, v, r.Symbol.Name))
						}
						littleEndian(section.Data, int(r.Offset), f, width(r.Type))
						shownSymbol = fmt.Sprintf("%08x", s)
						value = fmt.Sprint(v)
						field = fmt.Sprintf("%0*x", 2*width(r.Type), f)
					}
					l.RelocationCounts[r.Type][status]++
					l.RelocationCounts[r.Type]["total"]++
					l.RelocationLines = append(l.RelocationLines, fmt.Sprintf("%08x %s %s+%d %s %s %d %s %s %s %s", p, section.Object.Name, section.Name, r.Offset, r.Type, r.Symbol.Name, r.Addend, shownSymbol, value, field, status))
				}
			}
		}
	}
	for _, kind := range relocationTypes {
		c := l.RelocationCounts[kind]
		l.RelocationLines = append(l.RelocationLines, fmt.Sprintf("summary %s total %d ok %d veneer %d overflow %d undefined %d", kind, c["total"], c["ok"], c["veneer"], c["overflow"], c["undefined"]))
	}
}
func (l *Linker) buildImages() {
	for _, segment := range l.Script.Segments {
		segment.Image = make([]byte, int(segment.FileSize))
		for i := range segment.Image {
			segment.Image[i] = byte(segment.Fill)
		}
		for _, output := range segment.Sections {
			if belongs(output.Name, ".bss") {
				continue
			}
			for _, component := range output.Components {
				var data []byte
				switch component.Kind {
				case "section":
					data = component.Section.Data
				case "merged":
					data = component.Data
				case "veneer":
					target, _ := l.nameValue(component.Target)
					data = []byte{4, 240, 31, 229, 0, 0, 0, 0}
					littleEndian(data, 4, target, 4)
				}
				offset := int(component.Address - segment.Base)
				copy(segment.Image[offset:offset+len(data)], data)
			}
		}
	}
	if l.Script.ChecksumSegment != "" {
		segment := l.Script.SegmentNames[l.Script.ChecksumSegment]
		target := l.Names[l.Script.ChecksumSymbol].Definition
		offset := int(sectionValue(target.Section, target.Offset) - segment.Base)
		littleEndian(segment.Image, offset, 0, 4)
		sum := int64(0)
		for i := 0; i < len(segment.Image); i += 4 {
			word := int64(0)
			for j := 0; j < 4 && i+j < len(segment.Image); j++ {
				word += int64(segment.Image[i+j]) << uint(8*j)
			}
			sum += word
		}
		littleEndian(segment.Image, offset, modulo(-sum, 1<<32), 4)
	}
}
func (l *Linker) entryAddress() int64 {
	entry := l.Names[l.Script.Entry]
	if entry != nil && (entry.Kind == "global" || entry.Kind == "weak" || entry.Kind == "common") {
		value, _ := l.nameValue(l.Script.Entry)
		return value
	}
	return 0
}
func (l *Linker) imageHex() []string {
	out := []string{fmt.Sprintf("entry %08x %s", l.entryAddress(), l.Script.Entry)}
	for _, segment := range l.Script.Segments {
		out = append(out, fmt.Sprintf("segment %s vaddr %08x paddr %08x filesz %d memsz %d", segment.Name, segment.Base, segment.Physical, segment.FileSize, segment.MemorySize))
		for i := 0; i < len(segment.Image); i += 16 {
			parts := []string{fmt.Sprintf("%08x", segment.Base+int64(i))}
			for _, value := range segment.Image[i:min(i+16, len(segment.Image))] {
				parts = append(parts, fmt.Sprintf("%02x", value))
			}
			out = append(out, strings.Join(parts, " "))
		}
	}
	return out
}
func hexRecord(address int64, kind byte, data []byte) string {
	record := []byte{byte(len(data)), byte(address >> 8), byte(address), kind}
	record = append(record, data...)
	sum := 0
	for _, value := range record {
		sum += int(value)
	}
	record = append(record, byte((256-sum%256)%256))
	out := ":"
	for _, value := range record {
		out += fmt.Sprintf("%02X", value)
	}
	return out
}
func (l *Linker) intelHex() []string {
	segments := []*Segment{}
	for _, segment := range l.Script.Segments {
		if segment.FileSize > 0 {
			segments = append(segments, segment)
		}
	}
	sort.SliceStable(segments, func(i, j int) bool { return segments[i].Physical < segments[j].Physical })
	upper := int64(0)
	out := []string{}
	for _, segment := range segments {
		for k := int64(0); k < segment.FileSize; {
			address := segment.Physical + k
			n := min(int64(16), segment.FileSize-k, 65536-address%65536)
			if address/65536 != upper {
				upper = address / 65536
				out = append(out, hexRecord(0, 4, []byte{byte(upper / 256), byte(upper % 256)}))
			}
			out = append(out, hexRecord(address%65536, 0, segment.Image[int(k):int(k+n)]))
			k += n
		}
	}
	entry := l.entryAddress()
	out = append(out, hexRecord(0, 5, []byte{byte(entry >> 24), byte(entry >> 16), byte(entry >> 8), byte(entry)}), hexRecord(0, 1, nil))
	return out
}
func (l *Linker) status(r *Resolution) string {
	switch r.Kind {
	case "global", "weak":
		if r.Definition.Section.Live {
			return "kept"
		}
		return "discarded"
	case "common":
		if r.Live {
			return "kept"
		}
		return "discarded"
	case "script":
		return "kept"
	}
	return "-"
}
func (l *Linker) crossReferences() []string {
	out := []string{}
	for _, name := range l.OrderedNames {
		r := l.Names[name]
		referrers := "-"
		if len(r.Referrers) > 0 {
			referrers = strings.Join(r.Referrers, ",")
		}
		out = append(out, fmt.Sprintf("%s %s %s %s %s", name, r.Kind, l.status(r), r.Definer, referrers))
	}
	return out
}

type MapSymbol struct {
	Address             int64
	Name, Kind, Definer string
}

func (l *Linker) linkMap() []string {
	out := []string{}
	for _, extraction := range l.Extractions {
		out = append(out, "member "+extraction.Object+" "+extraction.Referrer+" "+extraction.Reason)
	}
	for _, signature := range l.COMDATOrder {
		c := l.COMDAT[signature]
		discarders := "-"
		if len(c.Discarders) > 0 {
			discarders = strings.Join(c.Discarders, ",")
		}
		out = append(out, "comdat "+signature+" "+c.Keeper.Name+" "+discarders)
	}
	veneerSymbols := []MapSymbol{}
	for _, segment := range l.Script.Segments {
		out = append(out, fmt.Sprintf("segment %s vaddr %08x paddr %08x filesz %d memsz %d used %d length %d %d%%", segment.Name, segment.Base, segment.Physical, segment.FileSize, segment.MemorySize, segment.Used, segment.Length, 100*segment.Used/segment.Length))
		for _, o := range segment.Sections {
			out = append(out, fmt.Sprintf("section %s %08x %d %d", o.Name, o.Address, o.Size, o.Alignment))
			for _, c := range o.Components {
				switch c.Kind {
				case "section":
					out = append(out, fmt.Sprintf("input %08x %d %d %s %s", c.Address, c.Size, c.Alignment, c.Section.Object.Name, c.Section.Name))
				case "merged":
					out = append(out, fmt.Sprintf("merged %08x %d sections %d strings %d unique %d saved %d", c.Address, c.Size, c.StringSections, c.Strings, c.Unique, c.OriginalSize-c.Size))
				case "common":
					out = append(out, fmt.Sprintf("common %08x %d %d %s %s", c.Address, c.Size, c.Alignment, c.Common.Definer, c.Common.Name))
				case "veneer":
					out = append(out, fmt.Sprintf("veneer %08x 8 %s", c.Address, c.Target))
					veneerSymbols = append(veneerSymbols, MapSymbol{c.Address, "__veneer_" + c.Target, "veneer", "*linker*"})
				}
			}
		}
	}
	for _, object := range l.Objects {
		for _, section := range object.Sections {
			if section.Reason != "" {
				out = append(out, fmt.Sprintf("discard %s %s %d %s", object.Name, section.Name, section.Size, section.Reason))
			}
		}
	}
	symbols := []MapSymbol{}
	for _, name := range l.OrderedNames {
		r := l.Names[name]
		if r.Kind == "common" && !r.Live {
			out = append(out, fmt.Sprintf("discard %s COMMON(%s) %d gc", r.Definer, name, r.Size))
		}
		if l.status(r) == "kept" {
			value, _ := l.nameValue(name)
			symbols = append(symbols, MapSymbol{value, name, r.Kind, r.Definer})
		}
	}
	symbols = append(symbols, veneerSymbols...)
	sort.SliceStable(symbols, func(i, j int) bool {
		if symbols[i].Address != symbols[j].Address {
			return symbols[i].Address < symbols[j].Address
		}
		return symbols[i].Name < symbols[j].Name
	})
	for _, s := range symbols {
		out = append(out, fmt.Sprintf("symbol %08x %s %s %s", s.Address, s.Name, s.Kind, s.Definer))
	}
	return out
}
func (l *Linker) unresolvedReferrers(name string) []string {
	out := []string{}
	for _, object := range l.Objects {
		found := false
		for _, section := range object.Sections {
			if !section.Live {
				continue
			}
			for _, r := range section.Relocations {
				if r.Symbol.Binding != "local" && r.Symbol.Name == name {
					found = true
					break
				}
			}
			if found {
				break
			}
		}
		if found {
			out = append(out, object.Name)
		}
	}
	return out
}
func (l *Linker) diagnostics() []string {
	out := []string{}
	for _, name := range sortedKeys(l.Orphans) {
		out = append(out, fmt.Sprintf("warning: orphan section %s discarded from %d object(s)", name, l.Orphans[name]))
	}
	for _, name := range l.OrderedNames {
		r := l.Names[name]
		definers := r.strongDefiners(l.Script.ScriptNames[name])
		if len(definers) >= 2 {
			out = append(out, "error: multiple definition of "+name+": "+strings.Join(definers, " "))
		}
		if len(r.Common) > 0 && (r.Kind == "global" || r.Kind == "script") {
			out = append(out, "warning: common symbol "+name+" overridden by "+r.Definer)
		}
		if r.Kind == "common" {
			pairs := map[[2]int64]bool{}
			for _, s := range r.Common {
				pairs[[2]int64{s.Size, s.Alignment}] = true
			}
			if len(pairs) > 1 {
				out = append(out, fmt.Sprintf("warning: common symbol %s merged to size %d align %d", name, r.Size, r.Alignment))
			}
		}
	}
	entry := l.Names[l.Script.Entry]
	if entry == nil || entry.Kind == "undefined" || entry.Kind == "weakundef" {
		out = append(out, "error: entry symbol "+l.Script.Entry+" is undefined")
	}
	for _, name := range l.OrderedNames {
		if l.Names[name].Kind == "undefined" {
			referrers := l.unresolvedReferrers(name)
			if len(referrers) > 0 {
				out = append(out, "error: undefined symbol "+name+" referenced by "+strings.Join(referrers, " "))
			}
		}
	}
	for _, segment := range l.Script.Segments {
		if segment.Used > segment.Length {
			out = append(out, fmt.Sprintf("error: segment %s overflows its length by %d bytes", segment.Name, segment.Used-segment.Length))
		}
	}
	for i, a := range l.Script.Segments {
		for _, b := range l.Script.Segments[i+1:] {
			if a.MemorySize > 0 && b.MemorySize > 0 && a.Base < b.Base+b.MemorySize && b.Base < a.Base+a.MemorySize {
				out = append(out, "error: segments "+a.Name+" and "+b.Name+" overlap")
			}
		}
	}
	out = append(out, l.RelocationDiagnostics...)
	errors, warnings := 0, 0
	for _, line := range out {
		if strings.HasPrefix(line, "error:") {
			errors++
		} else if strings.HasPrefix(line, "warning:") {
			warnings++
		}
	}
	return append(out, fmt.Sprintf("errors %d warnings %d", errors, warnings))
}
func writeLines(name string, lines []string) {
	value := ""
	if len(lines) > 0 {
		value = strings.Join(lines, "\n") + "\n"
	}
	if err := os.WriteFile("output/"+name, []byte(value), 0644); err != nil {
		panic(err)
	}
}
func main() {
	l := newLinker(readScript())
	l.loadInputs()
	l.resolve()
	l.collect()
	l.layout()
	l.loadAddresses()
	l.defineScriptSymbols()
	l.relocate()
	l.buildImages()
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	writeLines("image.hex", l.imageHex())
	writeLines("flash.ihex", l.intelHex())
	writeLines("link.map", l.linkMap())
	writeLines("xref.txt", l.crossReferences())
	writeLines("relocations.txt", l.RelocationLines)
	writeLines("diagnostics.txt", l.diagnostics())
}
