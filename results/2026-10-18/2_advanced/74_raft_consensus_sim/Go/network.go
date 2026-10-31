package main

import (
	"container/heap"
	"fmt"
	"strings"
)

var messageTypes = []string{"RV", "RVR", "AE", "AER", "TN"}
var statFields = []string{"sent", "delivered", "inflight", "partition", "rule", "loss", "down"}

type Counts [7]int

func (c Counts) text() string {
	a := make([]string, 7)
	for i, name := range statFields {
		a[i] = fmt.Sprintf("%s %d", name, c[i])
	}
	return strings.Join(a, " ")
}

type Drop struct {
	kind       string
	start, end int
}
type Link struct {
	delay, loss, passed int
	drops               []Drop
	stats               Counts
}
type Message struct {
	kind                                                                         string
	source, destination, term, last, lastTerm, previous, previousTerm, commit, m int
	success                                                                      bool
	entries                                                                      []Entry
	arrival, serial                                                              int
}
type MessageQueue []Message

func (q MessageQueue) Len() int { return len(q) }
func (q MessageQueue) Less(i, j int) bool {
	a, b := q[i], q[j]
	if a.arrival != b.arrival {
		return a.arrival < b.arrival
	}
	if a.source != b.source {
		return a.source < b.source
	}
	return a.serial < b.serial
}
func (q MessageQueue) Swap(i, j int) { q[i], q[j] = q[j], q[i] }
func (q *MessageQueue) Push(v any)   { *q = append(*q, v.(Message)) }
func (q *MessageQueue) Pop() any     { a := *q; v := a[len(a)-1]; *q = a[:len(a)-1]; return v }

type Network struct {
	links  [][]*Link
	groups []int
	total  Counts
	byType map[string]*Counts
	queue  MessageQueue
	serial int
}

func readNetwork(n int) *Network {
	lines := readLines("input/network.txt")
	d := number(strings.Fields(lines[0])[1])
	w := &Network{links: make([][]*Link,
		n+1), groups: make([]int, n+1), byType: map[string]*Counts{}}
	for _, kind := range messageTypes {
		w.byType[kind] = &Counts{}
	}
	for a := 1; a <= n; a++ {
		w.links[a] = make([]*Link,
			n+1)
		for b := 1; b <= n; b++ {
			if a != b {
				w.links[a][b] = &Link{delay: d}
			}
		}
	}
	for _, line := range lines[1:] {
		v := strings.Fields(line)
		for a := 1; a <= n; a++ {
			for b := 1; b <= n; b++ {
				if a == b || (v[1] != "*" && number(v[1]) != a) || (v[2] != "*" && number(v[2]) != b) {
					continue
				}
				link := w.links[a][b]
				switch v[0] {
				case "DELAY":
					link.delay = number(v[3])
				case "LOSS":
					link.loss = number(v[3])
				case "DROP":
					link.drops = append(link.drops,
						Drop{v[3], number(v[4]), number(v[5])})
				}
			}
		}
	}
	return w
}
func (w *Network) count(m Message, field, amount int) {
	w.total[field] += amount
	w.byType[m.kind][field] += amount
	w.links[m.source][m.destination].stats[field] += amount
}
func (w *Network) separated(a, b int) bool { return w.groups[a] != w.groups[b] }
func (w *Network) send(t int, m Message) {
	w.serial++
	m.serial = w.serial
	w.count(m, 0, 1)
	link := w.links[m.source][m.destination]
	if w.separated(m.source,
		m.destination) {
		w.count(m, 3, 1)
		return
	}
	for _, d := range link.drops {
		if (d.kind == m.kind || d.kind == "ALL") && d.start <= t && t <= d.end {
			w.count(m,
				4, 1)
			return
		}
	}
	link.passed++
	if link.loss > 0 && link.passed%link.loss == 0 {
		w.count(m, 5, 1)
		return
	}
	m.arrival = t + link.delay
	w.count(m,
		2, 1)
	heap.Push(&w.queue, m)
}
func (w *Network) arrivals(t int) []Message {
	var out []Message
	for len(w.queue) > 0 && w.queue[0].arrival == t {
		m := heap.Pop(&w.queue).(Message)
		w.count(m,
			2, -1)
		out = append(out, m)
	}
	return out
}
func (w *Network) deliver(m Message, up bool) bool {
	if !up {
		w.count(m, 6, 1)
		return false
	}
	if w.separated(m.source,
		m.destination) {
		w.count(m, 3, 1)
		return false
	}
	w.count(m, 1, 1)
	return true
}
