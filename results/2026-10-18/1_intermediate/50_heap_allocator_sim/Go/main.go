package main

import (
	"bufio"
	"fmt"
	"math/bits"
	"os"
	"sort"
	"strconv"
	"strings"
)

const (
	unit                   = 8
	header                 = 8
	minBlock               = 16
	minBuddy               = 32
	maxHeap                = 65536
	uninitialized          = -1
	randomMultiplier int64 = 48271
	randomModulus    int64 = 2147483647
)

var modes = []string{"FIRST", "NEXT", "BEST", "WORST", "SEGFIT", "BUDDY"}
var counterNames = []string{"allocs", "frees", "reallocs", "moves", "failures", "collected"}

func number(s string) int { n, _ := strconv.Atoi(s); return n }
func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}
func powerOfTwo(n int) bool       { return n > 0 && n&(n-1) == 0 }
func sizeClass(n int) int         { return bits.Len(uint(n)) - 1 }
func area(start, size int) string { return fmt.Sprintf("%d+%d", start, size) }
func fragment(free, largest int) int {
	if free == 0 {
		return 0
	}
	return (free - largest) * 100 / free
}

func nextRandom(state int64) int64 { return randomMultiplier * state % randomModulus }

// A block is shared by the address-ordered heap and the live-ID index.
type block struct {
	start, size int
	used        bool
	owner       string
	requested   int
	contents    []int
	stamp       int
}

func (b *block) end() int     { return b.start + b.size }
func (b *block) payload() int { return b.start + header }
func (b *block) area() string { return area(b.start, b.size) }
func (b *block) mapUnits() string {
	count := b.size/unit - 1
	if !b.used {
		return "F" + strings.Repeat(".", count)
	}
	var out strings.Builder
	out.WriteByte('H')
	for i := 0; i < count; i++ {
		if i*unit < b.requested {
			out.WriteByte('#')
		} else {
			out.WriteByte('-')
		}
	}
	return out.String()
}

type heap struct {
	mode                       string
	size, rover, registrations int
	blocks                     []*block
}

func newHeap(mode string, size int) *heap {
	h := &heap{mode: mode, size: size}
	h.blocks = []*block{h.register(&block{size: size})}
	return h
}
func (h *heap) register(b *block) *block { h.registrations++; b.stamp = h.registrations; return b }
func (h *heap) buddy() bool              { return h.mode == "BUDDY" }
func (h *heap) requiredLength(n int) int {
	length := ((n+unit-1)/unit)*unit + header
	if !h.buddy() {
		return length
	}
	result := minBuddy
	for result < length {
		result *= 2
	}
	return result
}
func (h *heap) locate(address int) int {
	for i, b := range h.blocks {
		if address < b.end() {
			return i
		}
	}
	return len(h.blocks)
}
func (h *heap) indexOf(needle *block) int {
	for i, b := range h.blocks {
		if b == needle {
			return i
		}
	}
	return -1
}
func (h *heap) usedBlocks() []*block {
	out := make([]*block, 0)
	for _, b := range h.blocks {
		if b.used {
			out = append(out, b)
		}
	}
	return out
}
func (h *heap) freeBlocks() []*block {
	out := make([]*block, 0)
	for _, b := range h.blocks {
		if !b.used {
			out = append(out, b)
		}
	}
	return out
}
func (h *heap) usedTotal() int {
	total := 0
	for _, b := range h.blocks {
		if b.used {
			total += b.size
		}
	}
	return total
}
func (h *heap) fragmentation() int {
	total, largest := 0, 0
	for _, b := range h.blocks {
		if !b.used {
			total += b.size
			largest = max(largest, b.size)
		}
	}
	return fragment(total, largest)
}
func (h *heap) placement(b *block, align int) int {
	p := ((b.start+header+align-1)/align)*align - header
	if p > b.start && p-b.start < minBlock {
		p += align
	}
	return p
}
func (h *heap) choose(length, align int) (int, int, bool) {
	roverIndex := h.locate(h.rover)
	selectedIndex, selectedPlace := -1, 0
	var bestA, bestB int
	for i, b := range h.blocks {
		if b.used {
			continue
		}
		place := h.placement(b, align)
		if place+length > b.end() {
			continue
		}
		a, c := 0, 0
		switch h.mode {
		case "NEXT":
			a = (i - roverIndex + len(h.blocks)) % len(h.blocks)
		case "BEST", "BUDDY":
			a, c = b.size, b.start
		case "WORST":
			a, c = -b.size, b.start
		case "SEGFIT":
			a, c = sizeClass(b.size), -b.stamp
		default:
			a = b.start
		}
		if selectedIndex < 0 || a < bestA || (a == bestA && c < bestB) {
			selectedIndex, selectedPlace = i, place
			bestA, bestB = a, c
		}
	}
	return selectedIndex, selectedPlace, selectedIndex >= 0
}
func (h *heap) carve(index, place, length int) *block {
	old := h.blocks[index]
	parts := make([]*block, 0, 3)
	if place > old.start {
		parts = append(parts, h.register(&block{start: old.start, size: place - old.start}))
	}
	chosen := &block{start: place, size: old.end() - place}
	parts = append(parts, chosen)
	if chosen.size-length >= minBlock {
		parts = append(parts, h.register(&block{start: place + length, size: chosen.size - length}))
		chosen.size = length
	}
	h.blocks = append(append(append([]*block{}, h.blocks[:index]...), parts...), h.blocks[index+1:]...)
	return chosen
}
func (h *heap) halve(index, length int) *block {
	b := h.blocks[index]
	for b.size > length {
		b.size /= 2
		sibling := h.register(&block{start: b.end(), size: b.size})
		h.blocks = append(h.blocks, nil)
		copy(h.blocks[index+2:], h.blocks[index+1:])
		h.blocks[index+1] = sibling
	}
	return b
}
func (h *heap) allocate(length, align int) *block {
	index, place, found := h.choose(length, align)
	if !found {
		return nil
	}
	var b *block
	if h.buddy() {
		b = h.halve(index, length)
	} else {
		b = h.carve(index, place, length)
	}
	b.used = true
	if h.mode == "NEXT" {
		h.rover = b.end()
		if h.rover == h.size {
			h.rover = 0
		}
	}
	return b
}
func (h *heap) mergeNext(index int) {
	h.blocks[index].size += h.blocks[index+1].size
	h.blocks = append(h.blocks[:index+1], h.blocks[index+2:]...)
}
func (h *heap) coalesce(index int) (*block, int) {
	merges := 0
	if h.buddy() {
		for h.blocks[index].size < h.size {
			b := h.blocks[index]
			buddyIndex := index - 1
			if b.start%(2*b.size) == 0 {
				buddyIndex = index + 1
			}
			if buddyIndex < 0 || buddyIndex >= len(h.blocks) {
				break
			}
			other := h.blocks[buddyIndex]
			if other.used || other.size != b.size {
				break
			}
			index = min(index, buddyIndex)
			h.mergeNext(index)
			merges++
		}
	} else {
		if index+1 < len(h.blocks) && !h.blocks[index+1].used {
			h.mergeNext(index)
			merges++
		}
		if index > 0 && !h.blocks[index-1].used {
			index--
			h.mergeNext(index)
			merges++
		}
	}
	return h.register(h.blocks[index]), merges
}
func (h *heap) release(b *block) (*block, int) {
	b.used = false
	b.owner = ""
	b.requested = 0
	b.contents = nil
	return h.coalesce(h.indexOf(b))
}
func (h *heap) shrink(index, length int) string {
	b := h.blocks[index]
	if h.buddy() {
		if length == b.size {
			return "kept"
		}
		h.halve(index, length)
		return "shrunk"
	}
	if b.size-length < minBlock {
		return "kept"
	}
	extra := &block{start: b.start + length, size: b.size - length}
	b.size = length
	h.blocks = append(h.blocks, nil)
	copy(h.blocks[index+2:], h.blocks[index+1:])
	h.blocks[index+1] = extra
	h.coalesce(index + 1)
	return "shrunk"
}
func (h *heap) growIntoNext(index, length int) string {
	if index+1 >= len(h.blocks) || h.blocks[index+1].used {
		return ""
	}
	b := h.blocks[index]
	total := b.size + h.blocks[index+1].size
	if total < length {
		return ""
	}
	h.blocks = append(h.blocks[:index+1], h.blocks[index+2:]...)
	if total-length >= minBlock {
		b.size = length
		extra := h.register(&block{start: b.end(), size: total - length})
		h.blocks = append(h.blocks, nil)
		copy(h.blocks[index+2:], h.blocks[index+1:])
		h.blocks[index+1] = extra
	} else {
		b.size = total
	}
	return "grown"
}
func (h *heap) growBuddy(index, length int) string {
	b := h.blocks[index]
	size, last := b.size, index
	for size < length {
		last++
		if b.start%(2*size) != 0 || last >= len(h.blocks) {
			return ""
		}
		partner := h.blocks[last]
		if partner.used || partner.size != size {
			return ""
		}
		size *= 2
	}
	h.blocks = append(h.blocks[:index+1], h.blocks[last+1:]...)
	b.size = length
	return "grown"
}
func (h *heap) resize(b *block, length int) string {
	index := h.indexOf(b)
	if length <= b.size {
		return h.shrink(index, length)
	}
	if h.buddy() {
		return h.growBuddy(index, length)
	}
	return h.growIntoNext(index, length)
}
func (h *heap) extend(amount int) *block {
	h.blocks = append(h.blocks, &block{start: h.size, size: amount})
	h.size += amount
	b, _ := h.coalesce(len(h.blocks) - 1)
	return b
}
func (h *heap) trim() int {
	released := 0
	if h.buddy() {
		for len(h.blocks) > 0 && !h.blocks[len(h.blocks)-1].used && 2*h.blocks[len(h.blocks)-1].size == h.size {
			released += h.blocks[len(h.blocks)-1].size
			h.blocks = h.blocks[:len(h.blocks)-1]
			h.size /= 2
		}
	} else if len(h.blocks) >= 2 && !h.blocks[len(h.blocks)-1].used {
		b := h.blocks[len(h.blocks)-1]
		released = b.size
		h.size = b.start
		h.blocks = h.blocks[:len(h.blocks)-1]
	}
	if h.rover >= h.size {
		h.rover = 0
	}
	return released
}
func (h *heap) compact() ([]string, int) {
	moves := []string{}
	packed := h.usedBlocks()
	address := 0
	for _, b := range packed {
		if b.start != address {
			previous := b.payload()
			b.start = address
			moves = append(moves, fmt.Sprintf("MOVE %s %d -> %d", b.owner, previous, b.payload()))
		}
		address += b.size
	}
	if address < h.size {
		packed = append(packed, h.register(&block{start: address, size: h.size - address}))
	}
	h.blocks = packed
	h.rover = 0
	return moves, address
}

func experiment(mode string, size int, seed int64, operations, maxRequest int) string {
	h := newHeap(mode, size)
	state := seed
	live := []*block{}
	used, peak, successes, failures := 0, 0, 0, 0
	for i := 0; i < operations; i++ {
		state = nextRandom(state)
		allocating := len(live) == 0 || state%3 != 0
		state = nextRandom(state)
		if allocating {
			request := 1 + int(state%int64(maxRequest))
			b := h.allocate(h.requiredLength(request), unit)
			if b == nil {
				failures++
			} else {
				successes++
				live = append(live, b)
				used += b.size
			}
		} else {
			index := int(state % int64(len(live)))
			b := live[index]
			live = append(live[:index], live[index+1:]...)
			used -= b.size
			h.release(b)
		}
		peak = max(peak, used)
	}
	return fmt.Sprintf("BENCH %s ok=%d fail=%d peak=%d used=%d frag=%d blocks=%d", mode, successes, failures, peak, used, h.fragmentation(), len(h.blocks))
}

// A separate index tracks live objects, while the heap tracks their physical blocks.
type allocator struct {
	heap         *heap
	live         map[string]*block
	freed, roots map[string]bool
	references   map[string]map[string]bool
	histories    map[string][]string
	counters     map[string]int
	peak         int
	output       []string
}

func newAllocator() *allocator { a := &allocator{}; a.reset(nil); return a }
func (a *allocator) reset(h *heap) {
	a.heap = h
	a.live = make(map[string]*block)
	a.freed = make(map[string]bool)
	a.roots = make(map[string]bool)
	a.references = make(map[string]map[string]bool)
	a.histories = make(map[string][]string)
	a.counters = make(map[string]int)
	a.peak = 0
}
func (a *allocator) emit(format string, args ...any) {
	a.output = append(a.output, fmt.Sprintf(format, args...))
}
func (a *allocator) record(id, line string) {
	a.output = append(a.output, line)
	a.histories[id] = append(a.histories[id], line)
}
func (a *allocator) outOfMemory(id string) error {
	a.counters["failures"]++
	return fmt.Errorf("OUT OF MEMORY %s", id)
}
func (a *allocator) needLive(id string) (*block, error) {
	if b, ok := a.live[id]; ok {
		return b, nil
	}
	if a.freed[id] {
		return nil, fmt.Errorf("USE AFTER FREE %s", id)
	}
	return nil, fmt.Errorf("UNKNOWN ID %s", id)
}
func (a *allocator) needRange(id string, offset, length int) (*block, error) {
	b, err := a.needLive(id)
	if err != nil {
		return nil, err
	}
	if offset+length > b.requested {
		return nil, fmt.Errorf("OUT OF BOUNDS %s", id)
	}
	return b, nil
}
func (a *allocator) freeListOnly() error {
	if a.heap.buddy() {
		return fmt.Errorf("UNSUPPORTED IN BUDDY MODE")
	}
	return nil
}
func (a *allocator) reachable() map[string]bool {
	found := make(map[string]bool, len(a.roots))
	pending := make([]string, 0, len(a.roots))
	for id := range a.roots {
		found[id] = true
		pending = append(pending, id)
	}
	for len(pending) > 0 {
		id := pending[len(pending)-1]
		pending = pending[:len(pending)-1]
		for target := range a.references[id] {
			if !found[target] {
				found[target] = true
				pending = append(pending, target)
			}
		}
	}
	return found
}
func (a *allocator) allocateID(word, id string, request, alignment, fill int) error {
	if request == 0 {
		return fmt.Errorf("BAD SIZE")
	}
	if _, found := a.live[id]; found {
		return fmt.Errorf("DUPLICATE ID %s", id)
	}
	b := a.heap.allocate(a.heap.requiredLength(request), alignment)
	if b == nil {
		return a.outOfMemory(id)
	}
	b.owner = id
	b.requested = request
	b.contents = make([]int, request)
	for i := range b.contents {
		b.contents[i] = fill
	}
	a.live[id] = b
	delete(a.freed, id)
	a.counters["allocs"]++
	a.record(id, fmt.Sprintf("%s %s addr=%d block=%d", word, id, b.payload(), b.size))
	return nil
}
func (a *allocator) releaseID(id string) string {
	b := a.live[id]
	size := b.size
	delete(a.live, id)
	a.freed[id] = true
	delete(a.roots, id)
	delete(a.references, id)
	for _, targets := range a.references {
		delete(targets, id)
	}
	free, merges := a.heap.release(b)
	return fmt.Sprintf("block=%d merges=%d free=%s", size, merges, free.area())
}
func (a *allocator) freeID(id string) error {
	if a.freed[id] {
		return fmt.Errorf("DOUBLE FREE %s", id)
	}
	if _, found := a.live[id]; !found {
		return fmt.Errorf("UNKNOWN ID %s", id)
	}
	details := a.releaseID(id)
	a.counters["frees"]++
	a.record(id, fmt.Sprintf("FREE %s %s", id, details))
	return nil
}
func (a *allocator) realloc(id string, request int) error {
	if request == 0 {
		return a.freeID(id)
	}
	if a.freed[id] {
		return fmt.Errorf("USE AFTER FREE %s", id)
	}
	b, exists := a.live[id]
	if !exists {
		return a.allocateID("MALLOC", id, request, unit, uninitialized)
	}
	length := a.heap.requiredLength(request)
	contents := make([]int, request)
	for i := range contents {
		if i < len(b.contents) {
			contents[i] = b.contents[i]
		} else {
			contents[i] = uninitialized
		}
	}
	previous := b.payload()
	kind := a.heap.resize(b, length)
	if kind == "" {
		moved := a.heap.allocate(length, unit)
		if moved == nil {
			return a.outOfMemory(id)
		}
		moved.owner = id
		a.live[id] = moved
		a.heap.release(b)
		a.counters["moves"]++
		b = moved
		kind = fmt.Sprintf("moved from=%d", previous)
	}
	b.requested = request
	b.contents = contents
	a.counters["reallocs"]++
	a.record(id, fmt.Sprintf("REALLOC %s addr=%d block=%d %s", id, b.payload(), b.size, kind))
	return nil
}

func (a *allocator) treeNode(leaves map[int]*block, start, size, depth int) {
	label := strings.Repeat(" ", 2*depth) + area(start, size)
	if b := leaves[start]; b != nil && b.size == size {
		if b.used {
			a.emit("%s USED %s", label, b.owner)
		} else {
			a.emit("%s FREE", label)
		}
		return
	}
	a.emit("%s split", label)
	a.treeNode(leaves, start, size/2, depth+1)
	a.treeNode(leaves, start+size/2, size/2, depth+1)
}

func (a *allocator) run(cmd string, v []string) error {
	h := a.heap
	switch cmd {
	case "HEAP":
		size, mode := number(v[0]), v[1]
		if size < 32 || size > maxHeap || size%unit != 0 || (mode == "BUDDY" && !powerOfTwo(size)) {
			return fmt.Errorf("BAD HEAP SIZE")
		}
		a.reset(newHeap(mode, size))
		a.emit("HEAP size=%d mode=%s", size, mode)
	case "MALLOC":
		return a.allocateID("MALLOC", v[0], number(v[1]), unit, uninitialized)
	case "CALLOC":
		return a.allocateID("CALLOC", v[0], number(v[1])*number(v[2]), unit, 0)
	case "MEMALIGN":
		if err := a.freeListOnly(); err != nil {
			return err
		}
		align := number(v[1])
		if !powerOfTwo(align) || align < unit || align > 4096 {
			return fmt.Errorf("BAD ALIGNMENT")
		}
		return a.allocateID("MEMALIGN", v[0], number(v[2]), align, uninitialized)
	case "REALLOC":
		return a.realloc(v[0], number(v[1]))
	case "FREE":
		return a.freeID(v[0])
	case "FILL":
		id, offset, length, value := v[0], number(v[1]), number(v[2]), number(v[3])
		b, err := a.needRange(id, offset, length)
		if err != nil {
			return err
		}
		for i := offset; i < offset+length; i++ {
			b.contents[i] = value
		}
		a.emit("FILL %s %d+%d = %d", id, offset, length, value)
	case "COPY":
		dest, dstart, source, sstart, length := v[0], number(v[1]), v[2], number(v[3]), number(v[4])
		dst, err := a.needRange(dest, dstart, length)
		if err != nil {
			return err
		}
		src, err := a.needRange(source, sstart, length)
		if err != nil {
			return err
		}
		saved := append([]int(nil), src.contents[sstart:sstart+length]...)
		copy(dst.contents[dstart:dstart+length], saved)
		a.emit("COPY %s %d+%d from %s %d", dest, dstart, length, source, sstart)
	case "READ":
		id, start, length := v[0], number(v[1]), number(v[2])
		b, err := a.needRange(id, start, length)
		if err != nil {
			return err
		}
		values := make([]string, length)
		for i := 0; i < length; i++ {
			if b.contents[start+i] == uninitialized {
				values[i] = "?"
			} else {
				values[i] = strconv.Itoa(b.contents[start+i])
			}
		}
		a.emit("READ %s %d+%d = %s", id, start, length, strings.Join(values, " "))
	case "ROOT":
		if _, err := a.needLive(v[0]); err != nil {
			return err
		}
		a.roots[v[0]] = true
		a.emit("ROOT %s", v[0])
	case "UNROOT":
		if _, err := a.needLive(v[0]); err != nil {
			return err
		}
		if !a.roots[v[0]] {
			return fmt.Errorf("NOT ROOT %s", v[0])
		}
		delete(a.roots, v[0])
		a.emit("UNROOT %s", v[0])
	case "LINK":
		src, dst := v[0], v[1]
		if _, err := a.needLive(src); err != nil {
			return err
		}
		if _, err := a.needLive(dst); err != nil {
			return err
		}
		if a.references[src] == nil {
			a.references[src] = make(map[string]bool)
		}
		a.references[src][dst] = true
		a.emit("LINK %s %s", src, dst)
	case "UNLINK":
		src, dst := v[0], v[1]
		if _, err := a.needLive(src); err != nil {
			return err
		}
		if _, err := a.needLive(dst); err != nil {
			return err
		}
		if !a.references[src][dst] {
			return fmt.Errorf("NO LINK %s %s", src, dst)
		}
		delete(a.references[src], dst)
		a.emit("UNLINK %s %s", src, dst)
	case "GC":
		found := a.reachable()
		garbage := make([]*block, 0)
		total := 0
		for id, b := range a.live {
			if !found[id] {
				garbage = append(garbage, b)
				total += b.size
			}
		}
		sort.Slice(garbage, func(i, j int) bool { return garbage[i].start < garbage[j].start })
		a.emit("GC collected=%d bytes=%d", len(garbage), total)
		for _, b := range garbage {
			id := b.owner
			a.record(id, fmt.Sprintf("COLLECT %s %s", id, a.releaseID(id)))
		}
		a.counters["collected"] += len(garbage)
	case "SBRK":
		amount := number(v[0])
		good := false
		if h.buddy() {
			good = amount == h.size && 2*h.size <= maxHeap
		} else {
			good = amount%unit == 0 && amount >= minBlock && h.size+amount <= maxHeap
		}
		if !good {
			return fmt.Errorf("BAD SBRK SIZE")
		}
		b := h.extend(amount)
		a.emit("SBRK heap=%d free=%s", h.size, b.area())
	case "TRIM":
		amount := h.trim()
		a.emit("TRIM heap=%d released=%d", h.size, amount)
	case "COMPACT":
		if err := a.freeListOnly(); err != nil {
			return err
		}
		moves, used := h.compact()
		a.counters["moves"] += len(moves)
		free := "none"
		if used < h.size {
			free = area(used, h.size-used)
		}
		a.emit("COMPACT moved=%d free=%s", len(moves), free)
		for _, line := range moves {
			fields := strings.Fields(line)
			a.record(fields[1], line)
		}
	case "WHO":
		address := number(v[0])
		if address >= h.size {
			a.emit("WHO %d outside", address)
			break
		}
		b := h.blocks[h.locate(address)]
		if !b.used {
			a.emit("WHO %d free %s", address, b.area())
			break
		}
		if address < b.payload() {
			a.emit("WHO %d header %s", address, b.owner)
			break
		}
		offset := address - b.payload()
		where := "slack"
		if offset < b.requested {
			where = "data"
		}
		a.emit("WHO %d %s %s+%d", address, where, b.owner, offset)
	case "DUMP":
		extra := ""
		if h.mode == "NEXT" {
			extra = fmt.Sprintf(" rover=%d", h.rover)
		}
		a.emit("DUMP mode=%s heap=%d blocks=%d%s", h.mode, h.size, len(h.blocks), extra)
		for _, b := range h.blocks {
			if b.used {
				a.emit("%d %d USED %s req=%d", b.start, b.size, b.owner, b.requested)
			} else {
				a.emit("%d %d FREE", b.start, b.size)
			}
		}
	case "MAP":
		a.emit("MAP heap=%d", h.size)
		var builder strings.Builder
		for _, b := range h.blocks {
			builder.WriteString(b.mapUnits())
		}
		chars := builder.String()
		for first := 0; first < len(chars); first += 64 {
			end := min(first+64, len(chars))
			a.emit("%05d %s", first*unit, chars[first:end])
		}
	case "FREELIST":
		free := h.freeBlocks()
		if h.mode == "SEGFIT" {
			sort.Slice(free, func(i, j int) bool { return free[i].stamp > free[j].stamp })
		}
		a.emit("FREELIST count=%d", len(free))
		groups := map[int][]string{}
		for _, b := range free {
			k := sizeClass(b.size)
			groups[k] = append(groups[k], b.area())
		}
		classes := make([]int, 0, len(groups))
		for k := range groups {
			classes = append(classes, k)
		}
		sort.Ints(classes)
		for _, k := range classes {
			a.emit("%d-%d: %s", 1<<k, (1<<(k+1))-1, strings.Join(groups[k], " "))
		}
	case "TREE":
		if !h.buddy() {
			return fmt.Errorf("REQUIRES BUDDY MODE")
		}
		leaves := make(map[int]*block)
		for _, b := range h.blocks {
			leaves[b.start] = b
		}
		a.emit("TREE heap=%d", h.size)
		a.treeNode(leaves, 0, h.size, 0)
	case "STATS":
		used, free := h.usedBlocks(), h.freeBlocks()
		usedTotal, requested, freeTotal, largest := 0, 0, 0, 0
		for _, b := range used {
			usedTotal += b.size
			requested += b.requested
		}
		for _, b := range free {
			freeTotal += b.size
			largest = max(largest, b.size)
		}
		a.emit("STATS used=%d used_blocks=%d free=%d free_blocks=%d largest=%d frag=%d requested=%d peak=%d", usedTotal, len(used), freeTotal, len(free), largest, fragment(freeTotal, largest), requested, a.peak)
		counters := make([]string, len(counterNames))
		for i, id := range counterNames {
			counters[i] = fmt.Sprintf("%s=%d", id, a.counters[id])
		}
		a.emit("OPS %s", strings.Join(counters, " "))
	case "LEAKS":
		found := a.reachable()
		keys := make([]string, 0, len(a.live))
		lost, requested := 0, 0
		for id, b := range a.live {
			keys = append(keys, id)
			requested += b.requested
			if !found[id] {
				lost++
			}
		}
		sort.Strings(keys)
		a.emit("LEAKS count=%d requested=%d lost=%d", len(keys), requested, lost)
		for _, id := range keys {
			b := a.live[id]
			state := "lost"
			if found[id] {
				state = "reachable"
			}
			a.emit("LEAK %s addr=%d block=%d req=%d %s", id, b.payload(), b.size, b.requested, state)
		}
	case "HISTORY":
		lines := a.histories[v[0]]
		a.emit("HISTORY %s events=%d", v[0], len(lines))
		a.output = append(a.output, lines...)
	case "BENCH":
		size, seed, ops, maxReq := number(v[0]), int64(number(v[1])), number(v[2]), number(v[3])
		if !powerOfTwo(size) || size < 32 || size > maxHeap {
			return fmt.Errorf("BAD HEAP SIZE")
		}
		a.emit("BENCH heap=%d seed=%d ops=%d maxreq=%d", size, seed, ops, maxReq)
		for _, mode := range modes {
			a.emit("%s", experiment(mode, size, seed, ops, maxReq))
		}
	}
	return nil
}
func (a *allocator) execute(line string) {
	fields := strings.Fields(line)
	name := fields[0]
	if a.heap == nil && name != "HEAP" && name != "BENCH" {
		a.emit("ERROR NO HEAP")
		return
	}
	err := a.run(name, fields[1:])
	if err != nil {
		a.emit("ERROR %s", err.Error())
	}
	if a.heap != nil {
		a.peak = max(a.peak, a.heap.usedTotal())
	}
}
func main() {
	in := bufio.NewScanner(os.Stdin)
	in.Buffer(make([]byte, 4096), 1<<22)
	if !in.Scan() {
		return
	}
	n := number(strings.TrimSpace(in.Text()))
	a := newAllocator()
	for i := 0; i < n && in.Scan(); i++ {
		a.execute(in.Text())
	}
	out := bufio.NewWriter(os.Stdout)
	for _, line := range a.output {
		fmt.Fprintln(out, line)
	}
	out.Flush()
}
