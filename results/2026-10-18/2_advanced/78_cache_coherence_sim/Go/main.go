package main

import (
	"container/heap"
	"fmt"
	"math/bits"
	"os"
	"sort"
	"strconv"
	"strings"
)

type Event struct {
	number, line, cycle, core, address, block, word, distance int
	op                                                        string
}
type Rejection struct {
	line   int
	reason string
}
type Reuse struct {
	accesses, distinct, cold, opt int
	histogram                     [6]int
	lru                           [5]int
}
type Fenwick []int

func (f Fenwick) add(i, amount int) {
	for i < len(f) {
		f[i] += amount
		i += i & -i
	}
}
func (f Fenwick) sum(i int) int {
	value := 0
	for i > 0 {
		value += f[i]
		i -= i & -i
	}
	return value
}

type NextUse struct{ block, next int }
type OptQueue []NextUse

func (q OptQueue) Len() int { return len(q) }
func (q OptQueue) Less(i, j int) bool {
	if q[i].next != q[j].next {
		return q[i].next > q[j].next
	}
	return q[i].block < q[j].block
}
func (q OptQueue) Swap(i, j int) { q[i], q[j] = q[j], q[i] }
func (q *OptQueue) Push(v any)   { *q = append(*q, v.(NextUse)) }
func (q *OptQueue) Pop() any     { a := *q; v := a[len(a)-1]; *q = a[:len(a)-1]; return v }
func validate(c Config, lines []string) ([]*Event, []Rejection) {
	var events []*Event
	var rejects []Rejection
	last := 0
	for i, line := range lines {
		a := strings.Split(line, " ")
		reason := ""
		if len(a) != 3 && len(a) != 4 {
			reason = "fields"
		} else {
			for _, field := range a {
				if field == "" {
					reason = "fields"
					break
				}
			}
		}
		if reason == "" && (!decimal(a[0]) || len(a[0]) > 7) {
			reason = "cycle"
		}
		if reason == "" && (!decimal(a[1]) || number(a[1]) >= c.n) {
			reason = "core"
		}
		if reason == "" && (a[2] != "R" && a[2] != "W" && a[2] != "FENCE" || a[2] == "FENCE" && len(a) != 3 || a[2] != "FENCE" && len(a) != 4) {
			reason = "op"
		}
		addr := 0
		if reason == "" && a[2] != "FENCE" {
			if !hexDigits(a[3]) {
				reason = "address"
			} else {
				addr = hexNumber(a[3])
				if addr%4 != 0 || addr > 0x7fffffff {
					reason = "address"
				}
			}
		}
		if reason == "" && number(a[0]) < last {
			reason = "order"
		}
		if reason != "" {
			rejects = append(rejects,
				Rejection{i + 1, reason})
			continue
		}
		last = number(a[0])
		events = append(events, &Event{number: len(events) + 1,
			line: i + 1, cycle: last, core: number(a[1]), address: addr, block: addr / c.line, word: addr % c.line / 4, op: a[2]})
	}
	return events,
		rejects
}
func reuseAnalysis(c Config, events []*Event) []Reuse {
	out := make([]Reuse, c.n)
	capacity := c.l1Sets * c.l1Ways
	sizes := []int{capacity / 4,
		capacity / 2, capacity, 2 * capacity, 4 * capacity}
	for core := 0; core < c.n; core++ {
		var ordered []*Event
		for _, e := range events {
			if e.core == core && e.op != "FENCE" {
				ordered = append(ordered, e)
			}
		}
		r := &out[core]
		r.accesses = len(ordered)
		last := map[int]int{}
		fenwick := make(Fenwick,
			len(ordered)+1)
		for i, e := range ordered {
			position := i + 1
			previous := last[e.block]
			if previous == 0 {
				r.cold++
				e.distance = 0
			} else {
				e.distance = len(last) - fenwick.sum(previous) + 1
				fenwick.add(previous,
					-1)
				index := 5
				switch {
				case e.distance == 1:
					index = 0
				case e.distance <= 4:
					index = 1
				case e.distance <= 16:
					index = 2
				case e.distance <= 64:
					index = 3
				case e.distance <= 256:
					index = 4
				}
				r.histogram[index]++
			}
			for j, size := range sizes {
				if previous == 0 || e.distance > size {
					r.lru[j]++
				}
			}
			fenwick.add(position, 1)
			last[e.block] = position
		}
		r.distinct = len(last)
		next := make([]int,
			len(ordered))
		future := map[int]int{}
		for i := len(ordered) - 1; i >= 0; i-- {
			block := ordered[i].block
			next[i] = len(ordered) + 1
			if at,
				ok := future[block]; ok {
				next[i] = at
			}
			future[block] = i
		}
		resident := map[int]int{}
		queue := OptQueue{}
		for i, e := range ordered {
			if _, ok := resident[e.block]; !ok {
				r.opt++
				if len(resident) == capacity {
					for {
						victim := heap.Pop(&queue).(NextUse)
						if value,
							ok := resident[victim.block]; ok && value == victim.next {
							delete(resident, victim.block)
							break
						}
					}
				}
			}
			resident[e.block] = next[i]
			heap.Push(&queue,
				NextUse{e.block, next[i]})
		}
	}
	return out
}

type Access struct {
	event                         *Event
	issue, latency, miss, sharing int
	hit                           bool
	service                       string
}
type DynamicWord struct{ writer, readers int }
type Simulator struct {
	config   Config
	scenario Scenario
	l1       []*Cache
	l2       *Cache
	bus      Bus
	cores    []CoreStats
	ready,
	writes []int
	invalid  []map[int]uint64
	accesses []Access
	watch    []string
	lookups, l2Hits, l2Misses,
	flushes, writebacks, evictions, dirtyEvictions, snoopHits, readLatency, writeLatency int
	fanout, histogram []int
	handoffs,
	lastWriter map[int]int
	communication [][]int
	words         map[[2]int]*DynamicWord
}

func newSimulator(c Config, scenario Scenario) *Simulator {
	s := &Simulator{config: c, scenario: scenario,
		l2: newCache(c.l2Sets, c.l2Ways, scenario.l2), cores: make([]CoreStats, c.n), ready: make([]int, c.n),
		writes: make([]int, c.n), invalid: make([]map[int]uint64, c.n), fanout: make([]int, c.n), histogram: make([]int,
			6), handoffs: map[int]int{}, lastWriter: map[int]int{}, communication: make([][]int, c.n), words: map[[2]int]*DynamicWord{}}
	for k := 0; k < c.n; k++ {
		s.l1 = append(s.l1,
			newCache(c.l1Sets, c.l1Ways, scenario.l1))
		s.invalid[k] = map[int]uint64{}
		s.communication[k] = make([]int,
			c.n)
	}
	return s
}
func indexOf(a []string, value string) int {
	for i, v := range a {
		if v == value {
			return i
		}
	}
	return -1
}
func (s *Simulator) tuple(block int) string {
	var fields []string
	for core, cache := range s.l1 {
		fields = append(fields,
			fmt.Sprintf("c%d:%s", core, cache.state(block)))
	}
	return strings.Join(fields, " ") + " L2:" + s.l2.state(block)
}
func (s *Simulator) transact(core, block, word int, kind string, request int) (int, string) {
	c := s.config
	t := s.bus.assign(request,
		c.tb, Transaction{core: core, block: block, kind: kind})
	s.cores[core].bus[indexOf(busTypes, kind)]++
	if kind == "WB" {
		s.writebacks++
		s.l2.hit(block)
		s.l2.change(block,
			"D")
		s.bus.transactions = append(s.bus.transactions, t)
		return t.start + c.tb, ""
	}
	supplier := -1
	flushed := false
	var snoops []string
	for k, cache := range s.l1 {
		if k == core {
			continue
		}
		state := cache.state(block)
		if state == "I" {
			continue
		}
		next,
			supply, flush := snoopTransition(s.scenario.protocol, state, kind)
		t.hits++
		snoops = append(snoops, fmt.Sprintf("c%d:%s>%s",
			k, state, next))
		if next == "I" {
			cache.remove(block)
			t.invalidations++
			s.cores[core].invalidationsSent++
			s.cores[k].invalidationsReceived++
			s.invalid[k][block] = uint64(1) << word
		} else {
			cache.change(block,
				next)
		}
		if supply {
			supplier = k
			s.cores[k].supplied++
		}
		if flush {
			flushed = true
		}
	}
	t.snoop = strings.Join(snoops,
		" ")
	if t.snoop == "" {
		t.snoop = "none"
	}
	s.snoopHits += t.hits
	if kind == "BusRdX" || kind == "BusUpgr" || kind == "BusWr" {
		s.fanout[t.invalidations]++
	}
	end := t.start + c.tb
	service := "upgrade"
	if kind != "BusUpgr" {
		s.lookups++
		hit := s.l2.state(block) != "I"
		if hit {
			s.l2Hits++
			s.l2.hit(block)
			t.l2 = "hit"
		} else {
			s.l2Misses++
			t.l2 = "miss"
			evicted := s.l2.fill(block,
				"C")
			if evicted.state != "" {
				s.evictions++
				isDirty := evicted.state == "D"
				var backs []string
				for k, cache := range s.l1 {
					state := cache.state(evicted.block)
					if state == "I" {
						continue
					}
					backs = append(backs,
						fmt.Sprintf("c%d:%s", k, state))
					if dirty(state) {
						isDirty = true
					}
					cache.remove(evicted.block)
					s.cores[k].backInvalidations++
				}
				backText := strings.Join(backs,
					" ")
				if backText == "" {
					backText = "none"
				}
				dirtyText := "clean"
				if isDirty {
					s.dirtyEvictions++
					dirtyText = "dirty"
				}
				t.eviction = fmt.Sprintf(" evict %s %s %s",
					address(evicted.block*c.line), backText, dirtyText)
			}
		}
		if flushed || kind == "BusWr" {
			s.l2.change(block,
				"D")
		}
		if flushed {
			s.flushes++
		}
		if kind == "BusWr" {
			service = "through"
			end += c.t2
			if !hit {
				end += c.tm
			}
		} else if supplier >= 0 {
			service = "cache"
			t.source = fmt.Sprintf("c%d",
				supplier)
		} else if hit {
			service = "l2"
			t.source = "L2"
			end += c.t2
		} else {
			service = "memory"
			t.source = "mem"
			end += c.t2 + c.tm
		}
	}
	s.bus.transactions = append(s.bus.transactions,
		t)
	return end, service
}
func (s *Simulator) access(e *Event, issue int) {
	c := s.config
	core, block, word := e.core, e.block, e.word
	stats := &s.cores[core]
	stats.accesses++
	if e.op == "R" {
		stats.reads++
	} else {
		stats.writes++
	}
	state := s.l1[core].state(block)
	hit := state != "I"
	kind,
		next := requestTransition(s.scenario.protocol, state, e.op)
	miss, sharing := -1, -1
	if hit {
		stats.hits++
		s.l1[core].hit(block)
	} else {
		stats.misses++
		switch {
		case e.distance == 0:
			miss = 0
		case s.invalid[core][block] != 0:
			miss = 3
			if s.invalid[core][block]&(uint64(1)<<word) != 0 {
				sharing = 0
				stats.trueSharing++
			} else {
				sharing = 1
				stats.falseSharing++
			}
		case e.distance > c.l1Sets*c.l1Ways:
			miss = 1
		default:
			miss = 2
		}
		stats.miss[miss]++
	}
	var before []string
	if s.scenario.name == c.primary {
		for _, watched := range c.watch {
			before = append(before, s.tuple(watched))
		}
		key := [2]int{block, word}
		if e.op == "W" {
			if previous,
				ok := s.lastWriter[block]; ok && previous != core {
				s.handoffs[block]++
			}
			s.lastWriter[block] = core
			s.words[key] = &DynamicWord{writer: core}
		} else if previous := s.words[key]; previous != nil && previous.writer != core && previous.readers>>core&1 == 0 {
			s.communication[previous.writer][core]++
			previous.readers |= 1 << core
		}
	}
	if e.op == "W" {
		for k := 0; k < c.n; k++ {
			if k == core {
				continue
			}
			if mask,
				ok := s.invalid[k][block]; ok {
				s.invalid[k][block] = mask | (uint64(1) << word)
			}
		}
	}
	end, service := issue+c.t1,
		"l1"
	if kind != "" {
		if next == "E/S" {
			next = "E"
			for k, cache := range s.l1 {
				if k != core && cache.state(block) != "I" {
					next = "S"
					break
				}
			}
		}
		end,
			service = s.transact(core, block, word, kind, issue+c.t1)
	}
	if state != "I" {
		s.l1[core].change(block, next)
	} else if next != "I" {
		evicted := s.l1[core].fill(block,
			next)
		delete(s.invalid[core], block)
		if evicted.state != "" && dirty(evicted.state) {
			s.transact(core,
				evicted.block, 0, "WB", s.bus.free)
		}
	}
	latency := end - issue
	stats.latency += latency
	stats.service[indexOf(serviceNames,
		service)]++
	stats.finish = max(stats.finish, end)
	if e.op == "R" {
		s.ready[core] = end
		s.readLatency += latency
	} else {
		s.ready[core] = issue + c.t1
		s.writes[core] = max(s.writes[core],
			end)
		s.writeLatency += latency
	}
	bin := 5
	switch {
	case latency == 1:
		bin = 0
	case latency <= 9:
		bin = 1
	case latency <= 29:
		bin = 2
	case latency <= 99:
		bin = 3
	case latency <= 299:
		bin = 4
	}
	s.histogram[bin]++
	s.accesses = append(s.accesses,
		Access{e, issue, latency, miss, sharing, hit, service})
	if s.scenario.name == c.primary {
		for j, watched := range c.watch {
			after := s.tuple(watched)
			if block == watched || after != before[j] {
				s.watch = append(s.watch,
					fmt.Sprintf("%d %d c%d %s %s line %s %s", e.number, issue, core, e.op, address(e.address), address(watched*c.line),
						after))
			}
		}
	}
}
func (s *Simulator) run(events []*Event) {
	ordered := make([][]*Event, s.config.n)
	for _, e := range events {
		ordered[e.core] = append(ordered[e.core],
			e)
	}
	at := make([]int, s.config.n)
	for {
		chosen, issue := -1, 0
		for core, queue := range ordered {
			if at[core] == len(queue) {
				continue
			}
			next := max(queue[at[core]].cycle,
				s.ready[core])
			if chosen < 0 || next < issue {
				chosen = core
				issue = next
			}
		}
		if chosen < 0 {
			break
		}
		e := ordered[chosen][at[chosen]]
		at[chosen]++
		if e.op == "FENCE" {
			end := max(issue,
				s.writes[chosen])
			stats := &s.cores[chosen]
			stats.fences++
			stats.fenceStall += end - issue
			stats.finish = max(stats.finish,
				end)
			s.ready[chosen] = end
		} else {
			s.access(e, issue)
		}
	}
}
func (s *Simulator) total() CoreStats {
	out := CoreStats{}
	for _, core := range s.cores {
		out.add(core)
	}
	return out
}
func (s *Simulator) statsLines() []string {
	c := s.config
	out := []string{fmt.Sprintf("scenario %s %s %s %s",
		s.scenario.name, s.scenario.protocol, s.scenario.l1, s.scenario.l2)}
	for k, core := range s.cores {
		out = append(out,
			core.lines(fmt.Sprintf("c%d", k))...)
	}
	total := s.total()
	out = append(out, total.lines("total")...)
	transactions := len(s.bus.transactions)
	out = append(out,
		fmt.Sprintf("l2 lookups %d hits %d misses %d flushes %d writebacks %d evictions %d dirty_evictions %d",
			s.lookups, s.l2Hits, s.l2Misses, s.flushes, s.writebacks, s.evictions, s.dirtyEvictions), fmt.Sprintf("bus transactions %d busy %d wait %d utilization %s",
			transactions, s.bus.busy, s.bus.wait, decimalRatio(100*s.bus.busy, total.finish)), fmt.Sprintf("traffic command_bytes %d data_bytes %d memory_bytes %d",
			8*transactions, c.line*(total.bus[0]+total.bus[1]+total.bus[4])+4*total.bus[3], c.line*(s.l2Misses+s.dirtyEvictions)))
	names := make([]string,
		c.n)
	for i := range names {
		names[i] = strconv.Itoa(i)
	}
	out = append(out, fmt.Sprintf("snoops probes %d hits %d fanout %s",
		(c.n-1)*(transactions-total.bus[4]), s.snoopHits, rangeCounts(names, s.fanout)), fmt.Sprintf("latencies reads %d writes %d histogram %s",
		s.readLatency, s.writeLatency, rangeCounts([]string{"1", "2-9", "10-29", "30-99", "100-299", "300+"},
			s.histogram)))
	return out
}

type WordSharing struct{ readers, writers int }
type LineSharing struct {
	cores, writers, reads, writes int
	words                         map[int]*WordSharing
}

func staticSharing(events []*Event) map[int]*LineSharing {
	out := map[int]*LineSharing{}
	for _, e := range events {
		if e.op == "FENCE" {
			continue
		}
		line := out[e.block]
		if line == nil {
			line = &LineSharing{words: map[int]*WordSharing{}}
			out[e.block] = line
		}
		line.cores |= 1 << e.core
		word := line.words[e.word]
		if word == nil {
			word = &WordSharing{}
			line.words[e.word] = word
		}
		if e.op == "W" {
			line.writes++
			line.writers |= 1 << e.core
			word.writers |= 1 << e.core
		} else {
			line.reads++
			word.readers |= 1 << e.core
		}
	}
	return out
}
func sortedIntKeys[V any](a map[int]V) []int {
	var keys []int
	for key := range a {
		keys = append(keys, key)
	}
	sort.Ints(keys)
	return keys
}
func (s *Simulator) sharingLines(events []*Event) []string {
	lines := staticSharing(events)
	trueMiss, falseMiss := map[int]int{},
		map[int]int{}
	for _, a := range s.accesses {
		if a.sharing == 0 {
			trueMiss[a.event.block]++
		} else if a.sharing == 1 {
			falseMiss[a.event.block]++
		}
	}
	var out []string
	count,
		trueLines, falseLines, totalTrue, totalFalse := 0, 0, 0, 0, 0
	for _, block := range sortedIntKeys(lines) {
		line := lines[block]
		if bits.OnesCount(uint(line.cores)) < 2 || line.writers == 0 {
			continue
		}
		count++
		isTrue := false
		var words []string
		for _, word := range sortedIntKeys(line.words) {
			v := line.words[word]
			if v.writers != 0 && bits.OnesCount(uint(v.readers|v.writers)) >= 2 {
				isTrue = true
			}
			words = append(words,
				fmt.Sprintf("w%d=%s/%s", word, coreString(v.readers), coreString(v.writers)))
		}
		kind := "false"
		if isTrue {
			kind = "true"
			trueLines++
		} else {
			falseLines++
		}
		t,
			f := trueMiss[block], falseMiss[block]
		totalTrue += t
		totalFalse += f
		out = append(out, fmt.Sprintf("%s %s cores %s writers %s reads %d writes %d handoffs %d coherence %d true %d false %d words %s",
			address(block*s.config.line), kind, coreString(line.cores), coreString(line.writers), line.reads,
			line.writes, s.handoffs[block], t+f, t, f, strings.Join(words, " ")))
	}
	out = append(out, fmt.Sprintf("lines %d true_lines %d false_lines %d coherence %d true %d false %d",
		count, trueLines, falseLines, totalTrue+totalFalse, totalTrue, totalFalse), "communication")
	for core, row := range s.communication {
		var values []string
		for _, v := range row {
			values = append(values, strconv.Itoa(v))
		}
		out = append(out,
			fmt.Sprintf("c%d %s", core, strings.Join(values, " ")))
	}
	return out
}
func (s *Simulator) finalLines() []string {
	var out []string
	cacheRows := func(name string, cache *Cache) {
		for set, a := range cache.sets {
			var ways []string
			for _, way := range a.ways {
				text := "-"
				if way.state != "" {
					text = address(way.block*s.config.line) + ":" + way.state
				}
				ways = append(ways,
					text)
			}
			out = append(out, fmt.Sprintf("%s %d %s %s %s fills %d evictions %d", name, set, strings.Join(ways,
				" "), strings.ToLower(cache.policy), cache.replacement(set), a.fills, a.evictions))
		}
	}
	for core, cache := range s.l1 {
		name := fmt.Sprintf("c%d",
			core)
		cacheRows(name, cache)
		counts := map[string]int{}
		total := 0
		for _, set := range cache.sets {
			for _, way := range set.ways {
				if way.state != "" {
					total++
					counts[way.state]++
				}
			}
		}
		out = append(out, fmt.Sprintf("%s lines %d M %d O %d E %d S %d V %d",
			name, total, counts["M"], counts["O"], counts["E"], counts["S"], counts["V"]))
	}
	cacheRows("L2", s.l2)
	dirtyCount,
		clean, inL1 := 0, 0, 0
	for _, set := range s.l2.sets {
		for _, way := range set.ways {
			if way.state == "" {
				continue
			}
			if way.state == "D" {
				dirtyCount++
			} else {
				clean++
			}
			for _, cache := range s.l1 {
				if cache.state(way.block) != "I" {
					inL1++
					break
				}
			}
		}
	}
	out = append(out, fmt.Sprintf("L2 lines %d dirty %d clean %d in_l1 %d",
		dirtyCount+clean, dirtyCount, clean, inL1))
	return out
}

type Hot struct {
	bus                                     [5]int
	misses, coherence, invalidations, cores int
}

func (s *Simulator) detailLines() [][]string {
	c := s.config
	hot := map[int]*Hot{}
	for _, t := range s.bus.transactions {
		v := hot[t.block]
		if v == nil {
			v = &Hot{}
			hot[t.block] = v
		}
		v.bus[indexOf(busTypes,
			t.kind)]++
		v.invalidations += t.invalidations
		v.cores |= 1 << t.core
	}
	for _, a := range s.accesses {
		if v := hot[a.event.block]; v != nil {
			if !a.hit {
				v.misses++
			}
			if a.miss == 3 {
				v.coherence++
			}
		}
	}
	blocks := sortedIntKeys(hot)
	transactions := func(a *Hot) int {
		total := 0
		for _, n := range a.bus {
			total += n
		}
		return total
	}
	sort.Slice(blocks, func(i, j int) bool {
		a, b := transactions(hot[blocks[i]]),
			transactions(hot[blocks[j]])
		if a != b {
			return a > b
		}
		return blocks[i] < blocks[j]
	})
	hotLines := []string{"hot " + c.primary}
	for rank, block := range blocks[:min(c.top, len(blocks))] {
		v := hot[block]
		hotLines = append(hotLines, fmt.Sprintf("%d %s transactions %d %s misses %d coherence %d invalidations %d cores %s",
			rank+1, address(block*c.line), transactions(v), namedCounts(busTypes, v.bus[:]), v.misses, v.coherence,
			v.invalidations, coreString(v.cores)))
	}
	type Interval struct {
		accesses []int
		misses, transactions,
		busy int
	}
	count := s.total().finish/c.interval + 1
	intervals := make([]Interval, count)
	for i := range intervals {
		intervals[i].accesses = make([]int,
			c.n)
	}
	for _, a := range s.accesses {
		v := &intervals[a.issue/c.interval]
		v.accesses[a.event.core]++
		if !a.hit {
			v.misses++
		}
	}
	for _, t := range s.bus.transactions {
		if index := t.start / c.interval; index < count {
			intervals[index].transactions++
		}
		for i := t.start / c.interval; i < count && i <= (t.start+c.tb-1)/c.interval; i++ {
			first,
				last := max(t.start, i*c.interval), min(t.start+c.tb, (i+1)*c.interval)
			intervals[i].busy += last - first
		}
	}
	intervalLines := []string{fmt.Sprintf("intervals %s %d",
		c.primary, c.interval)}
	for i, v := range intervals {
		var counts []string
		for _, n := range v.accesses {
			counts = append(counts,
				strconv.Itoa(n))
		}
		intervalLines = append(intervalLines, fmt.Sprintf("%d %d-%d accesses %s misses %d transactions %d busy %d utilization %s",
			i, i*c.interval, (i+1)*c.interval-1, strings.Join(counts, " "), v.misses, v.transactions, v.busy, decimalRatio(100*v.busy,
				c.interval)))
	}
	ordered := append([]Access(nil), s.accesses...)
	sort.Slice(ordered, func(i, j int) bool {
		if ordered[i].latency != ordered[j].latency {
			return ordered[i].latency > ordered[j].latency
		}
		return ordered[i].event.number < ordered[j].event.number
	})
	slow := []string{"slowest " + c.primary}
	for i, a := range ordered[:min(c.top, len(ordered))] {
		e := a.event
		slow = append(slow, fmt.Sprintf("%d event %d cycle %d c%d %s %s latency %d service %s",
			i+1, e.number, a.issue, e.core, e.op, address(e.address), a.latency, a.service))
	}
	type RegionStats struct {
		accesses,
		reads, writes, hits, transactions, latency int
		miss [4]int
	}
	regionCounts := make([]RegionStats, len(c.regions)+1)
	regionIndex := func(address int) int {
		for i, r := range c.regions {
			if r.first <= address && address <= r.last {
				return i
			}
		}
		return len(c.regions)
	}
	for _, a := range s.accesses {
		v := &regionCounts[regionIndex(a.event.address)]
		v.accesses++
		if a.event.op == "R" {
			v.reads++
		} else {
			v.writes++
		}
		if a.hit {
			v.hits++
		} else {
			v.miss[a.miss]++
		}
		v.latency += a.latency
	}
	for _, t := range s.bus.transactions {
		regionCounts[regionIndex(t.block*c.line)].transactions++
	}
	regions := []string{"regions " + c.primary}
	for i, v := range regionCounts {
		name := "other"
		if i < len(c.regions) {
			name = c.regions[i].name
		}
		amat := "-"
		if v.accesses > 0 {
			amat = fraction(v.latency,
				v.accesses) + " " + decimalRatio(v.latency, v.accesses)
		}
		regions = append(regions, fmt.Sprintf("%s accesses %d reads %d writes %d hits %d %s transactions %d latency %d amat %s",
			name, v.accesses, v.reads, v.writes, v.hits, namedCounts(missNames, v.miss[:]), v.transactions, v.latency,
			amat))
	}
	return [][]string{hotLines, intervalLines, slow, regions}
}
func main() {
	c := readConfig()
	raw := readLines("input/trace.txt")
	events, rejects := validate(c, raw)
	reuse := reuseAnalysis(c,
		events)
	first := []string{fmt.Sprintf("trace lines %d accepted %d rejected %d", len(raw), len(events),
		len(rejects))}
	for _, r := range rejects {
		first = append(first, fmt.Sprintf("reject line %d %s", r.line,
			r.reason))
	}
	first = append(first, fmt.Sprintf("geometry cores %d line %d l1 %d %d sets %d l2 %d %d sets %d",
		c.n, c.line, c.l1Size, c.l1Ways, c.l1Sets, c.l2Size, c.l2Ways, c.l2Sets), fmt.Sprintf("latency l1 %d l2 %d memory %d bus %d",
		c.t1, c.t2, c.tm, c.tb))
	var reuseLines []string
	cap := c.l1Sets * c.l1Ways
	sizes := []int{cap / 4, cap / 2,
		cap, 2 * cap, 4 * cap}
	for core, r := range reuse {
		reuseLines = append(reuseLines, fmt.Sprintf("reuse c%d accesses %d lines %d distance %s cold %d",
			core, r.accesses, r.distinct, rangeCounts([]string{"1", "2-4", "5-16", "17-64", "65-256", "257+"}, r.histogram[:]),
			r.cold))
		var counts []string
		for j, size := range sizes {
			counts = append(counts, fmt.Sprintf("%d:%d",
				size, r.lru[j]))
		}
		reuseLines = append(reuseLines, fmt.Sprintf("mrc c%d lru %s opt %d:%d", core, strings.Join(counts,
			" "), cap, r.opt))
	}
	sections := [][]string{first, reuseLines}
	var simulations []*Simulator
	var primary *Simulator
	for _, scenario := range c.scenarios {
		s := newSimulator(c, scenario)
		s.run(events)
		simulations = append(simulations,
			s)
		sections = append(sections, s.statsLines())
		if scenario.name == c.primary {
			primary = s
		}
	}
	ranking := append([]*Simulator(nil),
		simulations...)
	sort.Slice(ranking, func(i, j int) bool {
		a, b := ranking[i], ranking[j]
		if a.total().finish != b.total().finish {
			return a.total().finish < b.total().finish
		}
		if len(a.bus.transactions) != len(b.bus.transactions) {
			return len(a.bus.transactions) < len(b.bus.transactions)
		}
		return a.scenario.order < b.scenario.order
	})
	rankLines := []string{"ranking"}
	for i, s := range ranking {
		t := s.total()
		rankLines = append(rankLines, fmt.Sprintf("%d %s finish %d transactions %d amat %s %s",
			i+1, s.scenario.name, t.finish, len(s.bus.transactions), fraction(t.latency, t.accesses), decimalRatio(t.latency,
				t.accesses)))
	}
	sections = append(sections, rankLines)
	sections = append(sections, primary.detailLines()...)
	var stats []string
	for i, section := range sections {
		if i > 0 {
			stats = append(stats, "")
		}
		stats = append(stats, section...)
	}
	if e := os.MkdirAll("output",
		0755); e != nil {
		panic(e)
	}
	var busLines []string
	for _, t := range primary.bus.transactions {
		busLines = append(busLines,
			t.text(c.line))
	}
	writeLines("stats.txt", stats)
	writeLines("bus_log.txt", busLines)
	writeLines("watch.txt",
		primary.watch)
	writeLines("sharing.txt", primary.sharingLines(events))
	writeLines("final_state.txt",
		primary.finalLines())
}
