package main

import (
	"fmt"
	"strconv"
	"strings"
)

var missNames = []string{"compulsory", "capacity", "conflict", "coherence"}
var serviceNames = []string{"l1", "upgrade", "through", "cache", "l2", "memory"}

type CoreStats struct {
	accesses, reads, writes, hits, misses, fences, trueSharing, falseSharing, invalidationsSent,
	invalidationsReceived, supplied, backInvalidations, latency, fenceStall, finish int
	miss    [4]int
	service [6]int
	bus     [5]int
}

func (c *CoreStats) add(a CoreStats) {
	c.accesses += a.accesses
	c.reads += a.reads
	c.writes += a.writes
	c.hits += a.hits
	c.misses += a.misses
	c.fences += a.fences
	c.trueSharing += a.trueSharing
	c.falseSharing += a.falseSharing
	c.invalidationsSent += a.invalidationsSent
	c.invalidationsReceived += a.invalidationsReceived
	c.supplied += a.supplied
	c.backInvalidations += a.backInvalidations
	c.latency += a.latency
	c.fenceStall += a.fenceStall
	c.finish = max(c.finish,
		a.finish)
	for i, v := range a.miss {
		c.miss[i] += v
	}
	for i, v := range a.service {
		c.service[i] += v
	}
	for i, v := range a.bus {
		c.bus[i] += v
	}
}
func gcd(a, b int) int {
	for b != 0 {
		a, b = b, a%b
	}
	return a
}
func fraction(p, q int) string { g := gcd(p, q); return fmt.Sprintf("%d/%d", p/g, q/g) }
func decimalRatio(p, q int) string {
	u := (2*p*100 + q) / (2 * q)
	return fmt.Sprintf("%d.%02d", u/100, u%100)
}
func coreString(mask int) string {
	out := ""
	for k := 0; k < 8; k++ {
		if mask>>k&1 == 1 {
			out += strconv.Itoa(k)
		}
	}
	if out == "" {
		return "-"
	}
	return out
}
func namedCounts(names []string, counts []int) string {
	var out []string
	for i, name := range names {
		out = append(out,
			fmt.Sprintf("%s %d", name, counts[i]))
	}
	return strings.Join(out, " ")
}
func rangeCounts(names []string, counts []int) string {
	var out []string
	for i, name := range names {
		out = append(out,
			fmt.Sprintf("%s:%d", name, counts[i]))
	}
	return strings.Join(out, " ")
}
func (c CoreStats) lines(name string) []string {
	return []string{fmt.Sprintf("%s accesses %d reads %d writes %d hits %d misses %d fences %d",
		name, c.accesses, c.reads, c.writes, c.hits, c.misses, c.fences), fmt.Sprintf("%s misses %s true_sharing %d false_sharing %d",
		name, namedCounts(missNames, c.miss[:]), c.trueSharing, c.falseSharing), name + " service " + namedCounts(serviceNames,
		c.service[:]), name + " bus " + namedCounts(busTypes, c.bus[:]), fmt.Sprintf("%s snoop invalidations_sent %d invalidations_received %d supplied %d back_invalidations %d",
		name, c.invalidationsSent, c.invalidationsReceived, c.supplied, c.backInvalidations), fmt.Sprintf("%s time latency %d amat %s %s fence_stall %d finish %d",
		name, c.latency, fraction(c.latency, c.accesses), decimalRatio(c.latency, c.accesses), c.fenceStall,
		c.finish)}
}
