package main

import "fmt"

var busTypes = []string{"BusRd", "BusRdX", "BusUpgr", "BusWr", "WB"}

type Transaction struct {
	number, start, core, block        int
	kind, snoop, source, l2, eviction string
	invalidations, hits               int
}

func (t Transaction) text(lineSize int) string {
	out := fmt.Sprintf("%d %d c%d %s %s", t.number, t.start,
		t.core, t.kind, address(t.block*lineSize))
	if t.kind == "WB" {
		return out
	}
	out += " snoop " + t.snoop
	if t.kind == "BusRd" || t.kind == "BusRdX" {
		out += " data " + t.source
	}
	if t.kind != "BusUpgr" {
		out += " l2 " + t.l2 + t.eviction
	}
	return out
}

type Bus struct {
	free, wait, busy int
	transactions     []Transaction
}

func (b *Bus) assign(request, latency int, t Transaction) Transaction {
	t.start = max(request, b.free)
	b.wait += t.start - request
	b.free = t.start + latency
	b.busy += latency
	t.number = len(b.transactions) + 1
	return t
}
