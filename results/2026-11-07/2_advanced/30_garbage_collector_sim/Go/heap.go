package main

import (
	"fmt"
	"sort"
	"strings"
)

type HeapObject struct {
	Number, Size, Address, Moves, Age, Count int
	Fields                                   []*HeapObject
	Marked                                   bool
}

func newObject(number, p, d int) *HeapObject {
	return &HeapObject{Number: number, Size: 1 + p + d, Fields: make([]*HeapObject, p)}
}

type Pair struct{ Count, Words int }

func (p *Pair) Add(o *HeapObject) { p.Count++; p.Words += o.Size }
func (p *Pair) AddPair(q Pair)    { p.Count += q.Count; p.Words += q.Words }
func (p Pair) String() string     { return fmt.Sprintf("%d %d", p.Count, p.Words) }

type FreeBlock struct{ Address, Length int }
type CollectionRecord struct {
	Number, Line, Request        int
	Kind                         string
	Live, Freed, Moved, Promoted Pair
	Stack, Work                  int
	Before, After                [2]int
}

func newRecord(number, line, request int, kind string, blocks []FreeBlock) *CollectionRecord {
	return &CollectionRecord{Number: number, Line: line, Request: request, Kind: kind, Before: [2]int{totalFree(blocks), largestFree(blocks)}}
}
func (r *CollectionRecord) Finish(blocks []FreeBlock) {
	r.After = [2]int{totalFree(blocks), largestFree(blocks)}
}
func byAddress(objects []*HeapObject) []*HeapObject {
	result := append([]*HeapObject(nil), objects...)
	sort.Slice(result, func(i, j int) bool { return result[i].Address < result[j].Address })
	return result
}
func freeBlocks(objects []*HeapObject, start, end int) []FreeBlock {
	blocks := []FreeBlock{}
	position := start
	for _, o := range byAddress(objects) {
		if o.Address < start || o.Address >= end {
			continue
		}
		if o.Address > position {
			blocks = append(blocks, FreeBlock{position, o.Address - position})
		}
		position = o.Address + o.Size
	}
	if position < end {
		blocks = append(blocks, FreeBlock{position, end - position})
	}
	return blocks
}
func firstFit(blocks []FreeBlock, size int) (int, bool) {
	for _, b := range blocks {
		if b.Length >= size {
			return b.Address, true
		}
	}
	return 0, false
}
func totalFree(blocks []FreeBlock) int {
	total := 0
	for _, b := range blocks {
		total += b.Length
	}
	return total
}
func largestFree(blocks []FreeBlock) int {
	largest := 0
	for _, b := range blocks {
		largest = max(largest, b.Length)
	}
	return largest
}
func dec2(a, b int) string {
	q := (200*int64(a) + int64(b)) / (2 * int64(b))
	return fmt.Sprintf("%d.%02d", q/100, q%100)
}
func pct(a, b int) string {
	if b == 0 {
		return "-"
	}
	return dec2(100*a, b)
}
func classTable(values []int) string {
	counts := [5]int{}
	for _, v := range values {
		index := 4
		for i, limit := range []int{1, 3, 7, 15} {
			if v <= limit {
				index = i
				break
			}
		}
		counts[index]++
	}
	return fmt.Sprintf("1:%d 2-3:%d 4-7:%d 8-15:%d 16+:%d", counts[0], counts[1], counts[2], counts[3], counts[4])
}
func heapMap(size int, objects []*HeapObject, reachable map[int]bool, inactive [2]int) string {
	cells := []byte(strings.Repeat(".", size))
	for a := inactive[0]; a < inactive[1]; a++ {
		cells[a] = '-'
	}
	for _, o := range objects {
		header, body := byte('#'), byte('=')
		if reachable[o.Number] {
			header = byte('A' + (o.Number-1)%26)
			body = header + 32
		}
		cells[o.Address] = header
		for a := o.Address + 1; a < o.Address+o.Size; a++ {
			cells[a] = body
		}
	}
	return string(cells)
}

type Heap struct {
	Size, Young, PromotionAge, Base, Top, Target, Barriers, Remembers int
	Type                                                              string
	Objects                                                           []*HeapObject
	Records                                                           []*CollectionRecord
	Remembered                                                        map[*HeapObject]bool
	Increments, Decrements                                            int
	Released                                                          []*HeapObject
	Reports                                                           [][]string
	Deaths                                                            []int
}

func (h *Heap) FreeList() []FreeBlock {
	switch h.Type {
	case "MARK_COMPACT":
		if h.Top < h.Size {
			return []FreeBlock{{h.Top, h.Size - h.Top}}
		}
		return nil
	case "COPYING", "GENERATIONAL":
		half := h.Size / 2
		if h.Type == "GENERATIONAL" {
			half = h.Young / 2
		}
		blocks := []FreeBlock{}
		if h.Top < h.Base+half {
			blocks = append(blocks, FreeBlock{h.Top, h.Base + half - h.Top})
		}
		if h.Type == "GENERATIONAL" {
			blocks = append(blocks, h.OldBlocks()...)
		}
		return blocks
	default:
		return freeBlocks(h.Objects, 0, h.Size)
	}
}
func (h *Heap) Inactive() [2]int {
	switch h.Type {
	case "COPYING":
		start := h.Size/2 - h.Base
		return [2]int{start, start + h.Size/2}
	case "GENERATIONAL":
		start := h.Young/2 - h.Base
		return [2]int{start, start + h.Young/2}
	default:
		return [2]int{}
	}
}
func usedWords(objects []*HeapObject) int {
	words := 0
	for _, o := range objects {
		words += o.Size
	}
	return words
}
