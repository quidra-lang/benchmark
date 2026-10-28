package main

import (
	"sort"
	"strconv"
	"strings"
)

type CacheLine struct {
	block int
	state string
	stamp int
}
type CacheSet struct {
	ways             []CacheLine
	bits             []int
	fills, evictions int
}
type Cache struct {
	sets   []CacheSet
	policy string
	clock  int
}

func newCache(sets, ways int, policy string) *Cache {
	c := &Cache{sets: make([]CacheSet, sets), policy: policy}
	for i := range c.sets {
		c.sets[i].ways = make([]CacheLine,
			ways)
		c.sets[i].bits = make([]int, ways)
	}
	return c
}
func (c *Cache) find(b int) (int, int) {
	set := b % len(c.sets)
	for i, line := range c.sets[set].ways {
		if line.state != "" && line.block == b {
			return set, i
		}
	}
	return set, -1
}
func (c *Cache) state(b int) string {
	set, way := c.find(b)
	if way < 0 {
		return "I"
	}
	return c.sets[set].ways[way].state
}
func (c *Cache) change(b int, state string) {
	set, way := c.find(b)
	if way >= 0 {
		c.sets[set].ways[way].state = state
	}
}
func (c *Cache) remove(b int) {
	set, way := c.find(b)
	if way >= 0 {
		c.sets[set].ways[way].state = ""
	}
}
func (c *Cache) touch(set, way int, fill bool) {
	if c.policy == "FIFO" && !fill {
		return
	}
	c.clock++
	c.sets[set].ways[way].stamp = c.clock
	if c.policy == "PLRU" {
		node,
			lo, hi := 1, 0, len(c.sets[set].ways)
		for hi-lo > 1 {
			mid := (lo + hi) / 2
			if way < mid {
				c.sets[set].bits[node] = 1
				node *= 2
				hi = mid
			} else {
				c.sets[set].bits[node] = 0
				node = node*2 + 1
				lo = mid
			}
		}
	}
}
func (c *Cache) hit(b int) { set, way := c.find(b); c.touch(set, way, false) }
func (c *Cache) victim(set int) int {
	a := &c.sets[set]
	for i, line := range a.ways {
		if line.state == "" {
			return i
		}
	}
	if c.policy == "PLRU" {
		node,
			lo, hi := 1, 0, len(a.ways)
		for hi-lo > 1 {
			mid := (lo + hi) / 2
			if a.bits[node] == 0 {
				node *= 2
				hi = mid
			} else {
				node = node*2 + 1
				lo = mid
			}
		}
		return lo
	}
	way := 0
	for i := 1; i < len(a.ways); i++ {
		if a.ways[i].stamp < a.ways[way].stamp {
			way = i
		}
	}
	return way
}
func (c *Cache) fill(b int, state string) CacheLine {
	set := b % len(c.sets)
	way := c.victim(set)
	a := &c.sets[set]
	old := a.ways[way]
	a.fills++
	if old.state != "" {
		a.evictions++
	}
	a.ways[way] = CacheLine{block: b,
		state: state}
	c.touch(set, way, true)
	return old
}
func (c *Cache) replacement(set int) string {
	a := c.sets[set]
	var out []string
	if c.policy == "PLRU" {
		for _, bit := range a.bits[1:] {
			out = append(out, strconv.Itoa(bit))
		}
		if len(out) == 0 {
			return "-"
		}
		return strings.Join(out,
			"")
	}
	var ways []int
	for i, line := range a.ways {
		if line.state != "" {
			ways = append(ways, i)
		}
	}
	sort.Slice(ways,
		func(i, j int) bool { return a.ways[ways[i]].stamp > a.ways[ways[j]].stamp })
	for _, way := range ways {
		out = append(out,
			strconv.Itoa(way))
	}
	if len(out) == 0 {
		return "-"
	}
	return strings.Join(out, " ")
}
