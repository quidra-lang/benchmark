package main

import (
	"fmt"
	"os"
	"sort"
	"strings"
)

func line(parts ...any) string {
	fields := []string{}
	for _, p := range parts {
		fields = append(fields, fmt.Sprint(p))
	}
	return strings.Join(fields, " ")
}
func writeLines(name string, lines []string) {
	text := ""
	if len(lines) > 0 {
		text = strings.Join(lines, "\n") + "\n"
	}
	if e := os.WriteFile("output/"+name, []byte(text), 0644); e != nil {
		panic(e)
	}
}
func joinBlocks(blocks [][]string) []string {
	lines := []string{}
	for i, block := range blocks {
		if i > 0 {
			lines = append(lines, "")
		}
		lines = append(lines, block...)
	}
	return lines
}
func value(roots []*HeapObject, source int) *HeapObject {
	if source < 0 {
		return nil
	}
	return roots[source]
}
func reachableNumbers(roots []*HeapObject) map[int]bool {
	reached := map[int]bool{}
	stack := append([]*HeapObject(nil), roots...)
	for len(stack) > 0 {
		o := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		if o == nil || reached[o.Number] {
			continue
		}
		reached[o.Number] = true
		stack = append(stack, o.Fields...)
	}
	return reached
}
func pairOf(objects []*HeapObject) Pair {
	pair := Pair{}
	for _, o := range objects {
		pair.Add(o)
	}
	return pair
}
func fragmentation(blocks []FreeBlock) string {
	total := totalFree(blocks)
	return pct(total-largestFree(blocks), total)
}

type Checkpoint struct {
	Label                             string
	Line, Stack                       int
	Live, Allocated, Phase, Survivors Pair
	Reachable                         map[int]bool
}
type Script struct {
	LineCount                   int
	Commands                    []Command
	Errors                      []string
	Counts                      map[string]int
	Roots, Objects              []*HeapObject
	Births, Deaths, Lifetimes   []int
	Clock, PeakLine, PhaseStart int
	Alive                       map[int]bool
	Live, Peak                  Pair
	Checkpoints                 []Checkpoint
	Labels                      map[string]bool
}

func (s *Script) check(c Command) string {
	depth := len(s.Roots)
	if (c.Name == "ALLOC" || c.Name == "PUSH" || c.Name == "LOAD") && depth == 64 {
		return "stack"
	}
	if (c.Name == "LOAD" || c.Name == "SET" || c.Name == "OVERWRITE") && c.Slot >= depth {
		return "stack"
	}
	if (c.Name == "PUSH" || c.Name == "SET" || c.Name == "OVERWRITE") && c.Source >= depth {
		return "stack"
	}
	if c.Name == "POP" && c.Count > depth {
		return "stack"
	}
	if c.Name == "LOAD" || c.Name == "SET" {
		target := s.Roots[c.Slot]
		if target == nil {
			return "null"
		}
		if c.Field >= len(target.Fields) {
			return "field"
		}
	}
	if c.Name == "CHECKPOINT" && s.Labels[c.Label] {
		return "duplicate"
	}
	return ""
}
func analyzeScript() *Script {
	texts := readLines("input/mutator.txt")
	s := &Script{LineCount: len(texts), Counts: map[string]int{}, Alive: map[int]bool{}, Labels: map[string]bool{}}
	for i, text := range texts {
		parsed := parseLine(i+1, text)
		c, reason := parsed.Command, parsed.Reason
		if reason == "" {
			reason = s.check(c)
		}
		if reason != "" {
			s.Errors = append(s.Errors, line("error", "line", i+1, reason))
			continue
		}
		s.Commands = append(s.Commands, c)
		s.Counts[c.Name]++
		switch c.Name {
		case "ALLOC":
			o := newObject(len(s.Objects)+1, c.Pointers, c.Data)
			s.Objects = append(s.Objects, o)
			s.Births = append(s.Births, s.Clock)
			s.Deaths = append(s.Deaths, 0)
			s.Lifetimes = append(s.Lifetimes, -1)
			s.Clock += o.Size
			s.Roots = append(s.Roots, o)
		case "PUSH":
			s.Roots = append(s.Roots, value(s.Roots, c.Source))
		case "LOAD":
			s.Roots = append(s.Roots, s.Roots[c.Slot].Fields[c.Field])
		case "POP":
			s.Roots = s.Roots[:len(s.Roots)-c.Count]
		case "SET":
			s.Roots[c.Slot].Fields[c.Field] = value(s.Roots, c.Source)
		case "OVERWRITE":
			s.Roots[c.Slot] = value(s.Roots, c.Source)
		}
		reached := reachableNumbers(s.Roots)
		for number := range s.Alive {
			if !reached[number] {
				s.Deaths[number-1] = c.Line
				s.Lifetimes[number-1] = s.Clock - s.Births[number-1] - s.Objects[number-1].Size
			}
		}
		s.Alive = reached
		s.Live = Pair{}
		for number := range reached {
			s.Live.Add(s.Objects[number-1])
		}
		if s.PeakLine == 0 || s.Live.Words > s.Peak.Words {
			s.Peak, s.PeakLine = s.Live, c.Line
		}
		if c.Name == "CHECKPOINT" {
			phase, survivors := Pair{}, Pair{}
			for _, o := range s.Objects[s.PhaseStart:] {
				phase.Add(o)
				if reached[o.Number] {
					survivors.Add(o)
				}
			}
			s.Checkpoints = append(s.Checkpoints, Checkpoint{c.Label, c.Line, len(s.Roots), s.Live, pairOf(s.Objects), phase, survivors, reached})
			s.PhaseStart = len(s.Objects)
			s.Labels[c.Label] = true
		}
	}
	return s
}
func (s *Script) Report() []string {
	lines := []string{line("script", "lines", s.LineCount, "valid", len(s.Commands), "errors", len(s.Errors))}
	lines = append(lines, s.Errors...)
	parts := []any{"commands"}
	for _, name := range commandNames {
		parts = append(parts, name, s.Counts[name])
	}
	lines = append(lines, line(parts...))
	sizes := []int{}
	for _, o := range s.Objects {
		sizes = append(sizes, o.Size)
	}
	lines = append(lines, line("allocated", "objects", len(s.Objects), "words", s.Clock, "sizes", classTable(sizes)),
		line("peak_live", "objects", s.Peak.Count, "words", s.Peak.Words, "line", s.PeakLine), line("end_live",
			"objects", s.Live.Count, "words", s.Live.Words, "stack", len(s.Roots)))
	counts := [6]int{}
	for _, life := range s.Lifetimes {
		index := 5
		if life >= 0 {
			index = 4
			for i, limit := range []int{63, 255, 1023, 4095} {
				if life <= limit {
					index = i
					break
				}
			}
		}
		counts[index]++
	}
	lines = append(lines, line("lifetimes", "0-63", counts[0], "64-255", counts[1], "256-1023", counts[2],
		"1024-4095", counts[3], "4096+", counts[4], "live", counts[5]))
	for _, c := range s.Checkpoints {
		lines = append(lines, line("checkpoint", c.Label, "line", c.Line, "stack", c.Stack, "live", c.Live,
			"allocated", c.Allocated, "phase", c.Phase, "survivors", c.Survivors, "survival", pct(c.Survivors.Words,
				c.Phase.Words)))
	}
	return lines
}
func leakReport(title string, garbage []*HeapObject, deaths []int) []string {
	members := map[int]*HeapObject{}
	neighbors := map[int][]int{}
	ids := []int{}
	for _, o := range garbage {
		members[o.Number] = o
		ids = append(ids, o.Number)
	}
	sort.Ints(ids)
	for _, o := range garbage {
		for _, child := range o.Fields {
			if child != nil && members[child.Number] != nil {
				neighbors[o.Number] = append(neighbors[o.Number], child.Number)
				neighbors[child.Number] = append(neighbors[child.Number], o.Number)
			}
		}
	}
	groups := [][]*HeapObject{}
	grouped := map[int]bool{}
	for _, id := range ids {
		if grouped[id] {
			continue
		}
		grouped[id] = true
		stack := []int{id}
		group := []*HeapObject{}
		for len(stack) > 0 {
			n := stack[len(stack)-1]
			stack = stack[:len(stack)-1]
			group = append(group, members[n])
			for _, other := range neighbors[n] {
				if !grouped[other] {
					grouped[other] = true
					stack = append(stack, other)
				}
			}
		}
		sort.Slice(group, func(i, j int) bool { return group[i].Number < group[j].Number })
		groups = append(groups, group)
	}
	onCycle := func(o *HeapObject) bool {
		visited := map[int]bool{}
		stack := append([]*HeapObject(nil), o.Fields...)
		for len(stack) > 0 {
			current := stack[len(stack)-1]
			stack = stack[:len(stack)-1]
			if current == nil || members[current.Number] == nil {
				continue
			}
			if current == o {
				return true
			}
			if visited[current.Number] {
				continue
			}
			visited[current.Number] = true
			stack = append(stack, current.Fields...)
		}
		return false
	}
	lines := []string{line(title, "groups", len(groups), "objects", len(garbage), "words", usedWords(garbage))}
	for i, group := range groups {
		codes := []string{}
		cycles, died := 0, 0
		for _, o := range group {
			code := fmt.Sprint(o.Number)
			if onCycle(o) {
				cycles++
				code += "*"
			}
			codes = append(codes, code)
			died = max(died, deaths[o.Number-1])
		}
		lines = append(lines, line("group", i+1, "objects", len(group), "words", usedWords(group), "cycle", cycles, "died", died, "ids", strings.Join(codes, " ")))
	}
	return lines
}
func (h *Heap) Retain(o *HeapObject) {
	if o != nil {
		o.Count++
		h.Increments++
	}
}
func (h *Heap) Release(o *HeapObject) {
	if o == nil {
		return
	}
	h.Decrements++
	o.Count--
	if o.Count > 0 {
		return
	}
	pending := []*HeapObject{o}
	for len(pending) > 0 {
		current := pending[len(pending)-1]
		pending = pending[:len(pending)-1]
		for i, x := range h.Objects {
			if x == current {
				h.Objects = append(h.Objects[:i], h.Objects[i+1:]...)
				break
			}
		}
		h.Released = append(h.Released, current)
		for _, child := range current.Fields {
			if child != nil {
				h.Decrements++
				child.Count--
				if child.Count == 0 {
					pending = append(pending, child)
				}
			}
		}
	}
}
func (h *Heap) Backup(roots []*HeapObject, lineNumber, request int) {
	r := newRecord(len(h.Records)+1, lineNumber, request, "backup", h.FreeList())
	mark(r, roots, h.Objects)
	garbage := []*HeapObject{}
	for _, o := range h.Objects {
		if !o.Marked {
			garbage = append(garbage, o)
		}
	}
	h.Reports = append(h.Reports, leakReport(line("backup", r.Number, "line", lineNumber), garbage, h.Deaths))
	h.Objects = sweep(r, h.Objects)
	for _, o := range garbage {
		for _, child := range o.Fields {
			if child != nil && child.Marked {
				child.Count--
				h.Decrements++
			}
		}
	}
	r.Finish(h.FreeList())
	h.Records = append(h.Records, r)
}

type Pause struct {
	Line, Work, Freed int
	Collection        bool
	Count             int
}
type PauseStats struct {
	Count, Collections, Work, Freed, Maximum int
	P50, P90                                 string
}

func pauseStats(pauses []Pause) PauseStats {
	stats := PauseStats{Count: len(pauses), P50: "-", P90: "-"}
	works := []int{}
	for _, p := range pauses {
		works = append(works, p.Work)
		stats.Work += p.Work
		stats.Freed += p.Freed
		stats.Maximum = max(stats.Maximum, p.Work)
		if p.Collection {
			stats.Collections++
		}
	}
	if len(works) > 0 {
		sort.Ints(works)
		stats.P50 = fmt.Sprint(works[(50*len(works)+99)/100-1])
		stats.P90 = fmt.Sprint(works[(90*len(works)+99)/100-1])
	}
	return stats
}

type Segment struct {
	Start, Length, MutatorBefore int
	Mutator                      bool
}
type Timeline struct {
	Segments        []Segment
	Length, Mutator int
}

func (t *Timeline) Add(mutator bool, units int) {
	if units == 0 {
		return
	}
	if len(t.Segments) > 0 && t.Segments[len(t.Segments)-1].Mutator == mutator {
		t.Segments[len(t.Segments)-1].Length += units
	} else {
		t.Segments = append(t.Segments, Segment{t.Length, units, t.Mutator, mutator})
	}
	t.Length += units
	if mutator {
		t.Mutator += units
	}
}
func (t *Timeline) MutatorUntil(pos int) int {
	if len(t.Segments) == 0 {
		return 0
	}
	i := sort.Search(len(t.Segments), func(i int) bool { return t.Segments[i].Start > pos }) - 1
	s := t.Segments[i]
	if s.Mutator {
		return s.MutatorBefore + pos - s.Start
	}
	return s.MutatorBefore
}
func (t *Timeline) MMU(width int) string {
	if width > t.Length {
		return "-"
	}
	lowest := width
	for _, s := range t.Segments {
		for _, begin := range []int{s.Start, s.Start + s.Length - width} {
			if begin >= 0 && begin <= t.Length-width {
				lowest = min(lowest, t.MutatorUntil(begin+width)-t.MutatorUntil(begin))
			}
		}
	}
	return pct(lowest, width)
}

type Run struct {
	Entry                            CollectorEntry
	Config                           Config
	Script                           *Script
	Heap                             *Heap
	Roots, Placed                    []*HeapObject
	Cascades                         []Pause
	Timeline                         Timeline
	Observations                     [][]string
	PeakUsed, FailedLine, FailedSize int
}

func simulate(entry CollectorEntry, c Config, s *Script) *Run {
	r := &Run{Entry: entry, Config: c, Script: s, Heap: &Heap{Size: c.HeapSize, Young: entry.Young, PromotionAge: entry.Age,
		Type: entry.Type, Remembered: map[*HeapObject]bool{}, Deaths: s.Deaths}}
	for _, command := range s.Commands {
		if !r.step(command) {
			return r
		}
	}
	if entry.Type == "REFCOUNT" {
		garbage := []*HeapObject{}
		for _, o := range r.Heap.Objects {
			if !s.Alive[o.Number] {
				garbage = append(garbage, o)
			}
		}
		r.Heap.Reports = append(r.Heap.Reports, leakReport("end", garbage, s.Deaths))
	}
	return r
}
func (r *Run) retain(o *HeapObject) {
	if r.Entry.Type == "REFCOUNT" {
		r.Heap.Retain(o)
	}
}
func (r *Run) release(o *HeapObject) {
	if r.Entry.Type == "REFCOUNT" {
		r.Heap.Release(o)
	}
}
func (r *Run) push(o *HeapObject) { r.retain(o); r.Roots = append(r.Roots, o) }
func (r *Run) step(c Command) bool {
	h := r.Heap
	collections := len(h.Records)
	units := 1
	placed := true
	switch c.Name {
	case "ALLOC":
		o := newObject(len(r.Placed)+1, c.Pointers, c.Data)
		units = o.Size
		switch h.Type {
		case "COPYING":
			placed = h.AllocateCopy(o, r.Roots, c.Line)
		case "GENERATIONAL":
			placed = h.AllocateGeneration(o, r.Roots, c.Line)
		default:
			placed = h.AllocateMark(o, r.Roots, c.Line)
		}
		if placed {
			r.Placed = append(r.Placed, o)
			r.push(o)
			r.PeakUsed = max(r.PeakUsed, usedWords(h.Objects))
		}
	case "PUSH":
		r.push(value(r.Roots, c.Source))
	case "LOAD":
		r.push(r.Roots[c.Slot].Fields[c.Field])
	case "POP":
		for i := 0; i < c.Count; i++ {
			o := r.Roots[len(r.Roots)-1]
			r.Roots = r.Roots[:len(r.Roots)-1]
			r.release(o)
		}
	case "SET":
		target, v := r.Roots[c.Slot], value(r.Roots, c.Source)
		if h.Type == "GENERATIONAL" {
			h.WriteBarrier(target, v)
		}
		r.retain(v)
		previous := target.Fields[c.Field]
		target.Fields[c.Field] = v
		r.release(previous)
	case "OVERWRITE":
		v := value(r.Roots, c.Source)
		r.retain(v)
		previous := r.Roots[c.Slot]
		r.Roots[c.Slot] = v
		r.release(previous)
	case "CHECKPOINT":
		cp := r.Script.Checkpoints[len(r.Observations)]
		r.Observations = append(r.Observations, r.observe(cp))
	}
	for _, record := range h.Records[collections:] {
		r.Timeline.Add(false, record.Work)
	}
	if !placed {
		r.FailedLine, r.FailedSize = c.Line, units
		return false
	}
	r.Timeline.Add(true, units)
	if h.Type == "REFCOUNT" && len(h.Released) > 0 {
		cascade := Pause{Line: c.Line}
		for _, o := range h.Released {
			cascade.Count++
			cascade.Freed += o.Size
			cascade.Work += 1 + len(o.Fields)
		}
		h.Released = nil
		r.Cascades = append(r.Cascades, cascade)
		r.Timeline.Add(false, cascade.Work)
	}
	return true
}
func (r *Run) observe(cp Checkpoint) []string {
	h := r.Heap
	live, garbage := Pair{}, Pair{}
	for _, o := range h.Objects {
		if cp.Reachable[o.Number] {
			live.Add(o)
		} else {
			garbage.Add(o)
		}
	}
	blocks := h.FreeList()
	sizes := []int{}
	for _, b := range blocks {
		sizes = append(sizes, b.Length)
	}
	pointers, forward, backward, distance := 0, 0, 0, 0
	for _, o := range h.Objects {
		if !cp.Reachable[o.Number] {
			continue
		}
		for _, child := range o.Fields {
			if child == nil {
				continue
			}
			pointers++
			if child.Address > o.Address {
				forward++
			} else if child.Address < o.Address {
				backward++
			}
			d := child.Address - o.Address
			if d < 0 {
				d = -d
			}
			distance += d
		}
	}
	mean := "-"
	if pointers > 0 {
		mean = dec2(distance, pointers)
	}
	lines := []string{line("heap", "objects", pairOf(h.Objects), "reachable", live, "garbage", garbage),
		line("free", "total", totalFree(blocks), "largest", largestFree(blocks), "blocks", len(blocks),
			"sizes", classTable(sizes), "fragmentation", fragmentation(blocks)), line("locality", "pointers",
			pointers, "forward", forward, "backward", backward, "mean_distance", mean)}
	if h.Type == "GENERATIONAL" {
		young, old := Pair{}, Pair{}
		ages := [4]int{}
		for _, o := range h.Objects {
			if h.IsYoung(o) {
				young.Add(o)
				ages[min(o.Age, 3)]++
			} else {
				old.Add(o)
			}
		}
		lines = append(lines, line("generations", "young", young, "old", old, "remembered", len(h.Remembered),
			"ages", fmt.Sprintf("0:%d 1:%d 2:%d 3+:%d", ages[0], ages[1], ages[2], ages[3])))
	}
	if r.Config.Maps[cp.Label] {
		text := heapMap(h.Size, h.Objects, cp.Reachable, h.Inactive())
		for start := 0; start < len(text); start += r.Config.Width {
			lines = append(lines, fmt.Sprintf("%04d %s", start, text[start:start+r.Config.Width]))
		}
	}
	return lines
}
func (r *Run) pauses() []Pause {
	pauses := []Pause{}
	for _, c := range r.Heap.Records {
		pauses = append(pauses, Pause{Line: c.Line, Work: c.Work, Freed: c.Freed.Words, Collection: true})
	}
	return append(pauses, r.Cascades...)
}
func recordLine(c *CollectionRecord) string {
	return line(c.Number, "line", c.Line, "size", c.Request, "kind", c.Kind, "live", c.Live, "freed",
		c.Freed, "moved", c.Moved, "promoted", c.Promoted, "stack", c.Stack, "work", c.Work, "before",
		c.Before[0], c.Before[1], "after", c.After[0], c.After[1])
}
func (r *Run) collectionBlock() []string {
	h := r.Heap
	lines := []string{line("collector", r.Entry.Name, r.Entry.Type)}
	for _, c := range h.Records {
		lines = append(lines, recordLine(c))
	}
	pauses := r.pauses()
	stats := pauseStats(pauses)
	lines = append(lines, line("totals", "collections", stats.Collections, "pauses", stats.Count, "work",
		stats.Work, "freed", stats.Freed, "pause", "p50", stats.P50, "p90", stats.P90, "max", stats.Maximum))
	windows := []string{}
	for _, w := range r.Config.Windows {
		windows = append(windows, fmt.Sprintf("%d:%s", w, r.Timeline.MMU(w)))
	}
	lines = append(lines, line("utilization", pct(r.Timeline.Mutator, r.Timeline.Length), "mmu", strings.Join(windows, " ")))
	if h.Type == "GENERATIONAL" {
		parts := []any{"generational"}
		promoted := Pair{}
		for _, kind := range []string{"minor", "major", "tenure", "full"} {
			count, work := 0, 0
			for _, c := range h.Records {
				if c.Kind == kind {
					count++
					work += c.Work
				}
			}
			parts = append(parts, kind, count, work)
		}
		for _, c := range h.Records {
			promoted.AddPair(c.Promoted)
		}
		parts = append(parts, "promoted", promoted, "barrier", h.Barriers, "remembered", h.Remembers)
		lines = append(lines, line(parts...))
	}
	if h.Type == "REFCOUNT" {
		freed := Pair{}
		var largest *Pause
		for i := range r.Cascades {
			c := &r.Cascades[i]
			freed.Count += c.Count
			freed.Words += c.Freed
			if largest == nil || c.Work > largest.Work {
				largest = c
			}
		}
		maximum := "max_cascade 0 0 line -"
		if largest != nil {
			maximum = line("max_cascade", largest.Count, largest.Work, "line", largest.Line)
		}
		lines = append(lines, line("refcount", "increments", h.Increments, "decrements", h.Decrements, "cascades", len(r.Cascades), "freed", freed, maximum))
	}
	previous := 0
	for _, cp := range r.Script.Checkpoints {
		if r.FailedLine > 0 && r.FailedLine < cp.Line {
			lines = append(lines, line("phase", cp.Label, "out_of_memory"))
		} else {
			phase := []Pause{}
			for _, p := range pauses {
				if p.Line > previous && p.Line <= cp.Line {
					phase = append(phase, p)
				}
			}
			stats := pauseStats(phase)
			lines = append(lines, line("phase", cp.Label, "collections", stats.Collections, "pauses", stats.Count,
				"work", stats.Work, "freed", stats.Freed, "max_pause", stats.Maximum))
		}
		previous = cp.Line
	}
	if r.FailedLine == 0 {
		lines = append(lines, "status completed")
	} else {
		lines = append(lines, line("status", "out_of_memory", "line", r.FailedLine, "size", r.FailedSize))
	}
	return lines
}
func (r *Run) summaryRow() string {
	h := r.Heap
	stats := pauseStats(r.pauses())
	live, moved, movedObjects, maxMoves := 0, 0, 0, 0
	for _, c := range h.Records {
		live += c.Live.Count
		moved += c.Moved.Count
	}
	for _, o := range r.Placed {
		if o.Moves > 0 {
			movedObjects++
			maxMoves = max(maxMoves, o.Moves)
		}
	}
	status := "completed"
	end := []any{"-", "-", "-", "-"}
	if r.FailedLine > 0 {
		status = "out_of_memory"
	} else {
		blocks := h.FreeList()
		end = []any{usedWords(h.Objects), totalFree(blocks), largestFree(blocks), fragmentation(blocks)}
	}
	values := []any{r.Entry.Name, r.Entry.Type, status, len(h.Records), stats.Count, live, moved, movedObjects,
		maxMoves, stats.Freed, stats.Work, stats.P50, stats.P90, stats.Maximum, r.PeakUsed}
	values = append(values, end...)
	fields := []string{}
	for _, v := range values {
		fields = append(fields, fmt.Sprint(v))
	}
	return strings.Join(fields, ",")
}
func main() {
	config := readConfig()
	script := analyzeScript()
	runs := []*Run{}
	for _, entry := range config.Collectors {
		runs = append(runs, simulate(entry, config, script))
	}
	maps, collections, leaks := [][]string{}, [][]string{}, [][]string{}
	summary := []string{"collector,type,status,collections,pauses,live,moved,moved_objects,max_moves,freed,total_work,p50_pause,p90_pause,max_pause,peak_used,end_used,end_free,largest_free,fragmentation"}
	for i, cp := range script.Checkpoints {
		for _, r := range runs {
			block := []string{line("checkpoint", cp.Label, "line", cp.Line, "collector", r.Entry.Name)}
			if i < len(r.Observations) {
				block = append(block, r.Observations[i]...)
			} else {
				block = append(block, "out_of_memory")
			}
			maps = append(maps, block)
		}
	}
	for _, r := range runs {
		collections = append(collections, r.collectionBlock())
		summary = append(summary, r.summaryRow())
		if r.Entry.Type == "REFCOUNT" {
			block := []string{line("collector", r.Entry.Name)}
			for _, report := range r.Heap.Reports {
				block = append(block, report...)
			}
			if r.FailedLine > 0 {
				block = append(block, "status out_of_memory")
			}
			leaks = append(leaks, block)
		}
	}
	leakLines := joinBlocks(leaks)
	if len(leaks) == 0 {
		leakLines = []string{"none"}
	}
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	writeLines("mutator.txt", script.Report())
	writeLines("heap_maps.txt", joinBlocks(maps))
	writeLines("collections.txt", joinBlocks(collections))
	writeLines("summary.csv", summary)
	writeLines("leaks.txt", leakLines)
}
