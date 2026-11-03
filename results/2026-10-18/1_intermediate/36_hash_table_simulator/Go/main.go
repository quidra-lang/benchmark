package main

import (
	"bufio"
	"fmt"
	"os"
	"slices"
	"strconv"
	"strings"
)

type Mode int

const (
	chain Mode = iota
	linear
	quadratic
	double
	robinHood
	cuckoo
)

var modeNames = [...]string{"CHAIN", "LINEAR", "QUADRATIC", "DOUBLE", "ROBINHOOD", "CUCKOO"}

func (mode Mode) String() string { return modeNames[mode] }

func parseMode(text string) (Mode, error) {
	for mode := chain; mode <= cuckoo; mode++ {
		if mode.String() == text {
			return mode, nil
		}
	}
	return chain, fmt.Errorf("BAD MODE %s", text)
}

type Item struct {
	key   string
	value int64
}

func (item Item) String() string { return fmt.Sprintf("%s=%d", item.key, item.value) }

type SlotState int

const (
	empty SlotState = iota
	live
	tombstone
)

type Slot struct {
	state SlotState
	item  Item
}

func (slot Slot) content() string {
	if slot.state == live {
		return slot.item.key
	}
	if slot.state == tombstone {
		return "D"
	}
	return "-"
}

type Counters struct {
	probes, rehashes, inserts, updates, hits, misses, deletes, absent int64
}

type Search struct {
	found                                   bool
	position, chainIndex, probes, available int
	path                                    []string
}

type Placement struct {
	success, reused     bool
	position, movements int
	pending             Item
	moves               []string
}

type Record struct {
	item           Item
	position, cost int
}

type Reporting int

const (
	reportSilent Reporting = iota
	reportRehashes
	reportFull
	reportTrace
)

func (report Reporting) trace() bool   { return report == reportTrace }
func (report Reporting) details() bool { return report >= reportFull }

func hash(key string, base, modulus int) int {
	value := 0
	for i := range len(key) {
		value = (value*base + int(key[i])) % modulus
	}
	return value
}

func prime(value int) bool {
	if value < 2 {
		return false
	}
	for divisor := 2; divisor <= value/divisor; divisor++ {
		if value%divisor == 0 {
			return false
		}
	}
	return true
}

func nextPrime(value int) int {
	value = max(value, 2)
	for !prime(value) {
		value++
	}
	return value
}

func decimal(numerator, denominator int64) string {
	value := int64(0)
	if denominator != 0 {
		value = 100 * numerator / denominator
	}
	return fmt.Sprintf("%d.%02d", value/100, value%100)
}

func gauge(value int) byte {
	if value >= 10 {
		return '+'
	}
	return byte('0' + value)
}

func histogram(values []int) []string {
	frequencies := make(map[int]int)
	for _, value := range values {
		frequencies[value]++
	}
	keys := make([]int, 0, len(frequencies))
	for value := range frequencies {
		keys = append(keys, value)
	}
	slices.Sort(keys)
	var lines []string
	for _, value := range keys {
		count := frequencies[value]
		bar := strings.Repeat("#", min(count, 50))
		if count > 50 {
			bar += "+"
		}
		lines = append(lines, fmt.Sprintf("%d %d %s", value, count, bar))
	}
	return lines
}

func generate(count, length int, seed int64) []string {
	keys := make([]string, count)
	for i := range keys {
		key := make([]byte, length)
		for j := range key {
			seed = 48271 * seed % 2147483647
			key[j] = byte('a' + seed%26)
		}
		keys[i] = string(key)
	}
	return keys
}

func checkCapacity(value int64) (int, error) {
	if value < 2 || value > 10000 {
		return 0, fmt.Errorf("BAD CAPACITY")
	}
	return int(value), nil
}

func checkGeneration(count, length, seed int64) error {
	if count < 1 || count > 500 || length < 1 || length > 10 || seed < 1 || seed > 2147483646 {
		return fmt.Errorf("BAD ARGUMENT")
	}
	return nil
}

type Table struct {
	mode                 Mode
	capacity, size, tomb int
	buckets              [][]Item
	slots                []Slot
	counters             Counters
}

func newTable(mode Mode, capacity int) *Table {
	table := &Table{mode: mode, capacity: capacity}
	if mode == chain {
		table.buckets = make([][]Item, capacity)
	} else {
		table.slots = make([]Slot, table.slotCount())
	}
	return table
}

func (table *Table) slotCount() int {
	if table.mode == cuckoo {
		return 2 * table.capacity
	}
	return table.capacity
}

func (table *Table) position(index int) string {
	if table.mode == cuckoo {
		return fmt.Sprintf("T%d.%d", index/table.capacity+1, index%table.capacity)
	}
	return strconv.Itoa(index)
}

func (table *Table) distance(item Item, index int) int {
	return (index + table.capacity - hash(item.key, 31, table.capacity)) % table.capacity
}

func (table *Table) items() []Item {
	items := make([]Item, 0, table.size)
	if table.mode == chain {
		for _, bucket := range table.buckets {
			items = append(items, bucket...)
		}
	} else {
		for _, slot := range table.slots {
			if slot.state == live {
				items = append(items, slot.item)
			}
		}
	}
	return items
}

func (table *Table) search(key string, trace bool) Search {
	result := Search{position: -1, available: -1}
	observe := func(position int, content string) {
		result.probes++
		if trace {
			result.path = append(result.path, table.position(position)+":"+content)
		}
	}
	home := hash(key, 31, table.capacity)
	if table.mode == chain {
		for index, item := range table.buckets[home] {
			observe(home, item.key)
			if item.key == key {
				result.found, result.position, result.chainIndex = true, home, index
				break
			}
		}
		return result
	}
	step, limit := 1, table.capacity
	if table.mode == double {
		step += hash(key, 37, table.capacity-1)
	}
	if table.mode == cuckoo {
		limit = 2
	}
	for i := range limit {
		position := (home + i*step) % table.capacity
		if table.mode == quadratic {
			position = (home + i*i) % table.capacity
		} else if table.mode == cuckoo && i == 1 {
			position = table.capacity + hash(key, 37, table.capacity)
		}
		slot := table.slots[position]
		observe(position, slot.content())
		if slot.state == live && slot.item.key == key {
			result.found, result.position = true, position
			break
		}
		if table.mode == cuckoo {
			continue
		}
		if slot.state == empty {
			if result.available < 0 {
				result.available = position
			}
			break
		}
		if slot.state == tombstone && result.available < 0 {
			result.available = position
		}
		if table.mode == robinHood && table.distance(slot.item, position) < i {
			break
		}
	}
	return result
}

func (table *Table) foundItem(search Search) Item {
	if table.mode == chain {
		return table.buckets[search.position][search.chainIndex]
	}
	return table.slots[search.position].item
}

func (table *Table) place(item Item, initial *Search, trace bool) Placement {
	result := Placement{position: -1}
	home := hash(item.key, 31, table.capacity)
	if table.mode == chain {
		table.buckets[home] = append(table.buckets[home], item)
		result.success, result.position = true, home
		return result
	}
	if table.mode == linear || table.mode == quadratic || table.mode == double {
		if initial == nil {
			search := table.search(item.key, false)
			initial = &search
		}
		position := initial.available
		if position < 0 {
			result.pending = item
			return result
		}
		result.reused = table.slots[position].state == tombstone
		if result.reused {
			table.tomb--
		}
		table.slots[position] = Slot{state: live, item: item}
		result.success, result.position = true, position
		return result
	}
	carried := item
	if table.mode == robinHood {
		position, traveled, from := home, 0, -1
		for {
			if table.slots[position].state == empty {
				if trace && from >= 0 {
					result.moves = append(result.moves, fmt.Sprintf("SHIFT %s %d -> %d", carried.key, from, position))
				}
				table.slots[position] = Slot{state: live, item: carried}
				if result.position < 0 {
					result.position = position
				}
				result.success = true
				return result
			}
			resident := table.slots[position].item
			distance := table.distance(resident, position)
			if distance < traveled {
				if trace && from >= 0 {
					result.moves = append(result.moves, fmt.Sprintf("SHIFT %s %d -> %d", carried.key, from, position))
				}
				table.slots[position].item, carried = carried, resident
				if result.position < 0 {
					result.position = position
				}
				from, traveled = position, distance
				result.movements++
			}
			position = (position + 1) % table.capacity
			traveled++
		}
	}
	part := 0
	for {
		base := 31
		if part == 1 {
			base = 37
		}
		position := part*table.capacity + hash(carried.key, base, table.capacity)
		if table.slots[position].state == empty {
			table.slots[position] = Slot{state: live, item: carried}
			result.success = true
			result.position = table.search(item.key, false).position
			return result
		}
		if result.movements == table.capacity {
			result.pending = carried
			return result
		}
		resident := table.slots[position].item
		if trace {
			result.moves = append(result.moves, fmt.Sprintf("KICK %s %s", resident.key, table.position(position)))
		}
		table.slots[position].item, carried = carried, resident
		result.movements++
		part = 1 - part
	}
}

func (table *Table) remove(search Search, trace bool) (int, []string) {
	shifted := 0
	var moves []string
	position := search.position
	if table.mode == chain {
		table.buckets[position] = slices.Delete(table.buckets[position], search.chainIndex, search.chainIndex+1)
	} else if table.mode == linear || table.mode == quadratic || table.mode == double {
		table.slots[position] = Slot{state: tombstone}
		table.tomb++
	} else {
		table.slots[position] = Slot{}
		if table.mode == robinHood {
			source := (position + 1) % table.capacity
			for table.slots[source].state == live && table.distance(table.slots[source].item, source) > 0 {
				destination := (source + table.capacity - 1) % table.capacity
				if trace {
					moves = append(moves, fmt.Sprintf("SHIFT %s %d -> %d", table.slots[source].item.key, source, destination))
				}
				table.slots[destination], table.slots[source] = table.slots[source], Slot{}
				shifted++
				source = (source + 1) % table.capacity
			}
		}
	}
	table.size--
	return shifted, moves
}

func rebuild(mode Mode, capacity int, items []Item) *Table {
	trial := newTable(mode, capacity)
	for _, item := range items {
		if !trial.place(item, nil, false).success {
			return nil
		}
		trial.size++
	}
	return trial
}

func (table *Table) adopt(replacement *Table) {
	counters := table.counters
	*table = *replacement
	table.counters = counters
}

func (table *Table) automatic(capacity int, reason string, pending *Item) string {
	old := table.capacity
	items := table.items()
	if pending != nil {
		items = append(items, *pending)
	}
	for {
		if trial := rebuild(table.mode, capacity, items); trial != nil {
			table.adopt(trial)
			table.counters.rehashes++
			return fmt.Sprintf("REHASH %s %d -> %d", reason, old, capacity)
		}
		capacity = nextPrime(2 * capacity)
	}
}

func (table *Table) loadCheck(maximum int) string {
	threshold := int64(maximum) * int64(table.slotCount())
	if int64(table.size+table.tomb)*100 <= threshold {
		return ""
	}
	if int64(table.size)*200 > threshold {
		return table.automatic(nextPrime(2*table.capacity), "load", nil)
	}
	return table.automatic(table.capacity, "tomb", nil)
}

func (table *Table) shrinkCheck(minimum, maximum int) string {
	capacity := nextPrime(table.capacity / 2)
	slots := capacity
	if table.mode == cuckoo {
		slots *= 2
	}
	if int64(table.size)*100 >= int64(minimum)*int64(table.slotCount()) || capacity >= table.capacity ||
		int64(table.size)*100 > int64(maximum)*int64(slots) {
		return ""
	}
	trial := rebuild(table.mode, capacity, table.items())
	if trial == nil {
		return ""
	}
	old := table.capacity
	table.adopt(trial)
	table.counters.rehashes++
	return fmt.Sprintf("REHASH shrink %d -> %d", old, capacity)
}

func pathLine(search Search) string {
	if len(search.path) == 0 {
		return "PATH none"
	}
	return "PATH " + strings.Join(search.path, " ")
}

func (table *Table) put(item Item, add bool, maximum int, reporting Reporting) (bool, []string) {
	search := table.search(item.key, reporting.trace())
	table.counters.probes += int64(search.probes)
	command := "PUT"
	if add {
		command = "ADD"
	}
	var lines []string
	if search.found {
		old := table.foundItem(search).value
		if add {
			item.value += old
		}
		if table.mode == chain {
			table.buckets[search.position][search.chainIndex] = item
		} else {
			table.slots[search.position].item = item
		}
		table.counters.updates++
		if reporting.details() {
			lines = append(lines, fmt.Sprintf("%s %s UPDATED old=%d at=%s probes=%d", command, item, old, table.position(search.position), search.probes))
		}
		if reporting.trace() {
			lines = append(lines, pathLine(search))
		}
		return false, lines
	}
	placed := table.place(item, &search, reporting.trace())
	table.counters.inserts++
	if reporting.details() {
		row := fmt.Sprintf("%s %s NEW", command, item)
		if placed.success {
			row += fmt.Sprintf(" at=%s probes=%d", table.position(placed.position), search.probes)
			if placed.reused {
				row += " reused"
			}
			if table.mode == robinHood {
				row += fmt.Sprintf(" shifted=%d", placed.movements)
			}
			if table.mode == cuckoo {
				row += fmt.Sprintf(" kicks=%d", placed.movements)
			}
		} else {
			row += fmt.Sprintf(" probes=%d", search.probes)
			if table.mode == quadratic {
				row += " full"
			} else {
				row += fmt.Sprintf(" kicks=%d failed", placed.movements)
			}
		}
		lines = append(lines, row)
	}
	if reporting.trace() {
		lines = append(lines, pathLine(search))
		lines = append(lines, placed.moves...)
	}
	if placed.success {
		table.size++
	} else {
		reason := "full"
		if table.mode == cuckoo {
			reason = "kicks"
		}
		rehash := table.automatic(nextPrime(2*table.capacity), reason, &placed.pending)
		if reporting != reportSilent {
			lines = append(lines, rehash)
		}
	}
	if rehash := table.loadCheck(maximum); rehash != "" && reporting != reportSilent {
		lines = append(lines, rehash)
	}
	return true, lines
}

func (table *Table) delete(key string, minimum, maximum int, reporting Reporting) (bool, []string) {
	search := table.search(key, reporting.trace())
	table.counters.probes += int64(search.probes)
	var lines, moves []string
	if search.found {
		shifted := 0
		shifted, moves = table.remove(search, reporting.trace())
		table.counters.deletes++
		if reporting.details() {
			row := fmt.Sprintf("DEL %s OK at=%s probes=%d", key, table.position(search.position), search.probes)
			if table.mode == robinHood {
				row += fmt.Sprintf(" shifted=%d", shifted)
			}
			lines = append(lines, row)
		}
	} else {
		table.counters.absent++
		if reporting.details() {
			lines = append(lines, fmt.Sprintf("DEL %s NOT FOUND probes=%d", key, search.probes))
		}
	}
	if reporting.trace() {
		lines = append(lines, pathLine(search))
		lines = append(lines, moves...)
	}
	if search.found {
		if rehash := table.shrinkCheck(minimum, maximum); rehash != "" && reporting != reportSilent {
			lines = append(lines, rehash)
		}
	}
	return search.found, lines
}

func (table *Table) get(key string, trace bool) []string {
	search := table.search(key, trace)
	table.counters.probes += int64(search.probes)
	var row string
	if search.found {
		table.counters.hits++
		row = fmt.Sprintf("GET %s at=%s probes=%d", table.foundItem(search), table.position(search.position), search.probes)
	} else {
		table.counters.misses++
		row = fmt.Sprintf("GET %s NOT FOUND probes=%d", key, search.probes)
	}
	lines := []string{row}
	if trace {
		lines = append(lines, pathLine(search))
	}
	return lines
}

func (table *Table) records() []Record {
	records := make([]Record, 0, table.size)
	if table.mode == chain {
		for position, bucket := range table.buckets {
			for index, item := range bucket {
				records = append(records, Record{item, position, index + 1})
			}
		}
	} else {
		for position, slot := range table.slots {
			if slot.state != live {
				continue
			}
			cost := 0
			switch table.mode {
			case cuckoo:
				cost = position/table.capacity + 1
			case linear, robinHood:
				cost = table.distance(slot.item, position) + 1
			default:
				cost = table.search(slot.item.key, false).probes
			}
			records = append(records, Record{slot.item, position, cost})
		}
	}
	return records
}

func (table *Table) metrics() (int, string) {
	longest, total := 0, int64(0)
	for _, record := range table.records() {
		longest = max(longest, record.cost)
		total += int64(record.cost)
	}
	return longest, decimal(total, int64(table.size))
}

func (table *Table) dump() []string {
	lines := []string{fmt.Sprintf("DUMP %s cap=%d size=%d tomb=%d", table.mode, table.capacity, table.size, table.tomb)}
	if table.mode == chain {
		for position, bucket := range table.buckets {
			row := strconv.Itoa(position)
			if len(bucket) == 0 {
				row += " -"
			}
			for _, item := range bucket {
				row += " " + item.String()
			}
			lines = append(lines, row)
		}
	} else {
		for position, slot := range table.slots {
			prefix := strconv.Itoa(position)
			if table.mode == cuckoo {
				prefix = fmt.Sprintf("T%d %d", position/table.capacity+1, position%table.capacity)
			}
			content := slot.content()
			if slot.state == live {
				content = slot.item.String()
				if table.mode == robinHood {
					content += fmt.Sprintf(" d=%d", table.distance(slot.item, position))
				}
			}
			lines = append(lines, prefix+" "+content)
		}
	}
	return lines
}

func (table *Table) mapReport() []string {
	lines := []string{fmt.Sprintf("MAP %s cap=%d", table.mode, table.capacity)}
	costs := make([]int, table.slotCount())
	if table.mode != chain {
		for _, record := range table.records() {
			costs[record.position] = record.cost
		}
	}
	parts := 1
	if table.mode == cuckoo {
		parts = 2
	}
	for part := range parts {
		for start := 0; start < table.capacity; start += 40 {
			text := make([]byte, min(40, table.capacity-start))
			for j := range text {
				index := start + j
				if table.mode == chain {
					text[j] = '.'
					if len(table.buckets[index]) > 0 {
						text[j] = gauge(len(table.buckets[index]))
					}
				} else {
					position := part*table.capacity + index
					switch table.slots[position].state {
					case empty:
						text[j] = '.'
					case tombstone:
						text[j] = 'D'
					case live:
						text[j] = '#'
						if table.mode != cuckoo {
							text[j] = gauge(costs[position] - 1)
						}
					}
				}
			}
			prefix := ""
			if table.mode == cuckoo {
				prefix = fmt.Sprintf("T%d ", part+1)
			}
			lines = append(lines, fmt.Sprintf("%s%05d %s", prefix, start, text))
		}
	}
	return lines
}

func (table *Table) statistics() []string {
	longest, average := table.metrics()
	c := table.counters
	return []string{
		fmt.Sprintf("STATS %s size=%d cap=%d slots=%d tomb=%d load=%s%% longest=%d avg=%s probes=%d rehashes=%d",
			table.mode, table.size, table.capacity, table.slotCount(), table.tomb, decimal(100*int64(table.size), int64(table.slotCount())), longest, average, c.probes, c.rehashes),
		fmt.Sprintf("OPS inserts=%d updates=%d hits=%d misses=%d deletes=%d absent=%d", c.inserts, c.updates, c.hits, c.misses, c.deletes, c.absent),
	}
}

func (table *Table) scan(cursor, limit int) string {
	var keys []string
	for cursor < table.slotCount() && len(keys) < limit {
		if table.mode == chain {
			for _, item := range table.buckets[cursor] {
				keys = append(keys, item.key)
			}
		} else if table.slots[cursor].state == live {
			keys = append(keys, table.slots[cursor].item.key)
		}
		cursor++
	}
	if cursor == table.slotCount() {
		cursor = 0
	}
	row := fmt.Sprintf("SCAN next=%d", cursor)
	if len(keys) > 0 {
		row += " " + strings.Join(keys, " ")
	}
	return row
}

func (table *Table) clusters() []string {
	var runs []int
	if table.mode == chain {
		for _, bucket := range table.buckets {
			if len(bucket) > 0 {
				runs = append(runs, len(bucket))
			}
		}
	} else {
		for base := 0; base < len(table.slots); base += table.capacity {
			firstEmpty := -1
			for i := range table.capacity {
				if table.slots[base+i].state == empty {
					firstEmpty = i
					break
				}
			}
			if firstEmpty < 0 {
				runs = append(runs, table.capacity)
				continue
			}
			length := 0
			for offset := 1; offset <= table.capacity; offset++ {
				if table.slots[base+(firstEmpty+offset)%table.capacity].state != empty {
					length++
				} else if length > 0 {
					runs = append(runs, length)
					length = 0
				}
			}
		}
	}
	longest := 0
	for _, length := range runs {
		longest = max(longest, length)
	}
	return append([]string{fmt.Sprintf("CLUSTERS runs=%d longest=%d", len(runs), longest)}, histogram(runs)...)
}

func (table *Table) distribution() []string {
	var values []int
	longest := 0
	for _, record := range table.records() {
		values = append(values, record.cost)
		longest = max(longest, record.cost)
	}
	return append([]string{fmt.Sprintf("DIST keys=%d longest=%d", table.size, longest)}, histogram(values)...)
}

func compareModes(table *Table, capacity, maximum int) []string {
	items := table.items()
	slices.SortFunc(items, func(a, b Item) int { return strings.Compare(a.key, b.key) })
	lines := []string{fmt.Sprintf("COMPARE keys=%d cap=%d", len(items), capacity)}
	for mode := chain; mode <= cuckoo; mode++ {
		trial := newTable(mode, capacity)
		for _, item := range items {
			trial.put(item, false, maximum, reportSilent)
		}
		longest, average := trial.metrics()
		lines = append(lines, fmt.Sprintf("%s cap=%d longest=%d avg=%s probes=%d rehashes=%d", mode, trial.capacity, longest, average, trial.counters.probes, trial.counters.rehashes))
	}
	return lines
}

func benchmark(capacity, count, length int, seed int64, maximum int) []string {
	keys := generate(2*count, length, seed)
	lines := []string{fmt.Sprintf("BENCH cap=%d count=%d len=%d seed=%d", capacity, count, length, seed)}
	for mode := chain; mode <= cuckoo; mode++ {
		trial := newTable(mode, capacity)
		for i, key := range keys[:count] {
			trial.put(Item{key, int64(i + 1)}, false, maximum, reportSilent)
		}
		misses, probes := int64(0), int64(0)
		for _, key := range keys[count:] {
			search := trial.search(key, false)
			if !search.found {
				misses++
				probes += int64(search.probes)
			}
		}
		_, average := trial.metrics()
		lines = append(lines, fmt.Sprintf("%s cap=%d keys=%d hit=%s misses=%d miss=%s rehashes=%d", mode, trial.capacity, trial.size, average, misses, decimal(probes, misses), trial.counters.rehashes))
	}
	return lines
}

type Simulator struct {
	table            *Table
	maximum, minimum int
	trace            bool
}

func (sim *Simulator) execute(line string) ([]string, error) {
	words := strings.Split(line, " ")
	command := words[0]
	number := func(index int) int64 {
		value, _ := strconv.ParseInt(words[index], 10, 64)
		return value
	}
	switch command {
	case "CREATE", "MAXLOAD", "MINLOAD", "TRACE", "HASH", "PUT", "ADD", "GET", "DEL", "PROBE", "GEN", "GENDEL",
		"RESIZE", "CONVERT", "CLEAR", "DUMP", "MAP", "STATS", "KEYS", "TOP", "SCAN", "CLUSTERS", "DIST", "COMPARE", "BENCH":
	default:
		return nil, fmt.Errorf("UNKNOWN COMMAND %s", command)
	}
	switch command {
	case "CREATE":
		mode, err := parseMode(words[1])
		if err != nil {
			return nil, err
		}
		capacity, err := checkCapacity(number(2))
		if err != nil {
			return nil, err
		}
		sim.table = newTable(mode, nextPrime(capacity))
		return []string{fmt.Sprintf("CREATE %s cap=%d", mode, sim.table.capacity)}, nil
	case "MAXLOAD", "MINLOAD":
		value := number(1)
		if command == "MAXLOAD" && (value < 10 || value > 95) || command == "MINLOAD" && value > 40 {
			return nil, fmt.Errorf("BAD LOAD")
		}
		if command == "MAXLOAD" {
			sim.maximum = int(value)
		} else {
			sim.minimum = int(value)
		}
		return []string{fmt.Sprintf("%s %d", command, value)}, nil
	case "TRACE":
		if words[1] != "ON" && words[1] != "OFF" {
			return nil, fmt.Errorf("BAD ARGUMENT")
		}
		sim.trace = words[1] == "ON"
		return []string{"TRACE " + words[1]}, nil
	case "HASH":
		capacity, err := checkCapacity(number(2))
		if err != nil {
			return nil, err
		}
		key := words[1]
		return []string{fmt.Sprintf("HASH %s m=%d h31=%d h37=%d step=%d", key, capacity, hash(key, 31, capacity), hash(key, 37, capacity), 1+hash(key, 37, capacity-1))}, nil
	case "BENCH":
		capacity, err := checkCapacity(number(1))
		if err != nil {
			return nil, err
		}
		count, length, seed := number(2), number(3), number(4)
		if err := checkGeneration(count, length, seed); err != nil {
			return nil, err
		}
		return benchmark(nextPrime(capacity), int(count), int(length), seed, sim.maximum), nil
	}
	table := sim.table
	if table == nil {
		return nil, fmt.Errorf("NO TABLE")
	}
	reporting := reportFull
	if sim.trace {
		reporting = reportTrace
	}
	switch command {
	case "PUT", "ADD":
		_, lines := table.put(Item{words[1], number(2)}, command == "ADD", sim.maximum, reporting)
		return lines, nil
	case "GET":
		return table.get(words[1], sim.trace), nil
	case "DEL":
		_, lines := table.delete(words[1], sim.minimum, sim.maximum, reporting)
		return lines, nil
	case "PROBE":
		search := table.search(words[1], true)
		row := "PROBE " + words[1]
		if len(search.path) > 0 {
			row += " " + strings.Join(search.path, " ")
		}
		outcome := "MISS"
		if search.found {
			outcome = "FOUND"
		}
		return []string{fmt.Sprintf("%s %s probes=%d", row, outcome, search.probes)}, nil
	case "GEN", "GENDEL":
		count, length, seed := number(1), number(2), number(3)
		if err := checkGeneration(count, length, seed); err != nil {
			return nil, err
		}
		var lines []string
		changed := int64(0)
		for i, key := range generate(int(count), int(length), seed) {
			var didChange bool
			var output []string
			if command == "GEN" {
				didChange, output = table.put(Item{key, int64(i + 1)}, false, sim.maximum, reportRehashes)
			} else {
				didChange, output = table.delete(key, sim.minimum, sim.maximum, reportRehashes)
			}
			if didChange {
				changed++
			}
			lines = append(lines, output...)
		}
		if command == "GEN" {
			lines = append(lines, fmt.Sprintf("GEN %d new=%d updated=%d", count, changed, count-changed))
		} else {
			lines = append(lines, fmt.Sprintf("GENDEL %d deleted=%d missing=%d", count, changed, count-changed))
		}
		return lines, nil
	case "RESIZE", "CONVERT":
		capacity, mode := table.capacity, table.mode
		var err error
		if command == "RESIZE" {
			capacity, err = checkCapacity(number(1))
			if err == nil {
				capacity = nextPrime(capacity)
			}
		} else {
			mode, err = parseMode(words[1])
		}
		if err != nil {
			return nil, err
		}
		slots := capacity
		if mode == cuckoo {
			slots *= 2
		}
		if int64(table.size)*100 > int64(sim.maximum)*int64(slots) {
			return nil, fmt.Errorf("TOO SMALL")
		}
		trial := rebuild(mode, capacity, table.items())
		if trial == nil {
			return nil, fmt.Errorf("REBUILD FAILED")
		}
		row := fmt.Sprintf("RESIZE %d -> %d", table.capacity, capacity)
		if command == "CONVERT" {
			row = fmt.Sprintf("CONVERT %s -> %s cap=%d", table.mode, mode, capacity)
		}
		table.adopt(trial)
		return []string{row}, nil
	case "CLEAR":
		size := table.size
		table.adopt(newTable(table.mode, table.capacity))
		return []string{fmt.Sprintf("CLEAR %d", size)}, nil
	case "DUMP":
		return table.dump(), nil
	case "MAP":
		return table.mapReport(), nil
	case "STATS":
		return table.statistics(), nil
	case "KEYS":
		keys := make([]string, 0, table.size)
		for _, item := range table.items() {
			keys = append(keys, item.key)
		}
		slices.Sort(keys)
		row := fmt.Sprintf("KEYS %d", len(keys))
		if len(keys) > 0 {
			row += " " + strings.Join(keys, " ")
		}
		return []string{row}, nil
	case "TOP":
		limit := number(1)
		if limit < 1 || limit > 100 {
			return nil, fmt.Errorf("BAD ARGUMENT")
		}
		records := table.records()
		slices.SortFunc(records, func(a, b Record) int {
			if a.cost != b.cost {
				return b.cost - a.cost
			}
			return strings.Compare(a.item.key, b.item.key)
		})
		records = records[:min(len(records), int(limit))]
		lines := []string{fmt.Sprintf("TOP %d", len(records))}
		for _, record := range records {
			lines = append(lines, fmt.Sprintf("%s cost=%d at=%s", record.item.key, record.cost, table.position(record.position)))
		}
		return lines, nil
	case "SCAN":
		cursor, limit := number(1), number(2)
		if limit < 1 || limit > 100 {
			return nil, fmt.Errorf("BAD ARGUMENT")
		}
		if cursor >= int64(table.slotCount()) {
			return nil, fmt.Errorf("BAD CURSOR")
		}
		return []string{table.scan(int(cursor), int(limit))}, nil
	case "CLUSTERS":
		return table.clusters(), nil
	case "DIST":
		return table.distribution(), nil
	case "COMPARE":
		capacity, err := checkCapacity(number(1))
		if err != nil {
			return nil, err
		}
		return compareModes(table, nextPrime(capacity), sim.maximum), nil
	}
	panic("unreachable command")
}

func readLine(input *bufio.Reader) string {
	line, _ := input.ReadString('\n')
	return strings.TrimSuffix(strings.TrimSuffix(line, "\n"), "\r")
}

func main() {
	input := bufio.NewReader(os.Stdin)
	output := bufio.NewWriter(os.Stdout)
	defer output.Flush()
	count, _ := strconv.Atoi(readLine(input))
	sim := Simulator{maximum: 75}
	for range count {
		lines, err := sim.execute(readLine(input))
		if err != nil {
			fmt.Fprintln(output, "ERROR", err)
		} else {
			for _, line := range lines {
				fmt.Fprintln(output, line)
			}
		}
	}
}
