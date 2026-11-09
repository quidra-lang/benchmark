package main

import (
	"container/heap"
	"slices"
	"strings"
)

type Session struct {
	Owner                 *ASNode
	Link                  *Link
	Incoming, Outgoing    map[Prefix]*Attribute
	Pending               map[Prefix]bool
	Timer, Sent, Received int
}
type Message struct {
	Serial, Time int
	Source       *Session
	Prefix       Prefix
	Attribute    *Attribute
}

func (m *Message) Sender() *ASNode   { return m.Source.Owner }
func (m *Message) Receiver() *ASNode { return m.Source.Link.Other(m.Source.Owner) }
func (m *Message) Link() *Link       { return m.Source.Link }
func messageLess(a, b *Message) bool {
	if a.Time != b.Time {
		return a.Time < b.Time
	}
	if a.Receiver().Number != b.Receiver().Number {
		return a.Receiver().Number < b.Receiver().Number
	}
	if a.Sender().Number != b.Sender().Number {
		return a.Sender().Number < b.Sender().Number
	}
	return a.Serial < b.Serial
}

type MessageHeap []*Message

func (h MessageHeap) Len() int           { return len(h) }
func (h MessageHeap) Less(i, j int) bool { return messageLess(h[i], h[j]) }
func (h MessageHeap) Swap(i, j int)      { h[i], h[j] = h[j], h[i] }
func (h *MessageHeap) Push(v any)        { *h = append(*h, v.(*Message)) }
func (h *MessageHeap) Pop() any {
	a := *h
	v := a[len(a)-1]
	*h = a[:len(a)-1]
	return v
}

type MessageQueue struct {
	Heap   MessageHeap
	Serial int
}

func (q *MessageQueue) Send(time int, s *Session, p Prefix, a *Attribute) *Message {
	q.Serial++
	m := &Message{q.Serial, time + s.Link.Delay, s, p, a}
	heap.Push(&q.Heap, m)
	return m
}
func (q *MessageQueue) Arrivals(time int) []*Message {
	out := []*Message{}
	for len(q.Heap) > 0 && q.Heap[0].Time == time {
		out = append(out, heap.Pop(&q.Heap).(*Message))
	}
	return out
}
func (q *MessageQueue) Ordered() []*Message {
	out := slices.Clone(q.Heap)
	slices.SortFunc(out, func(a, b *Message) int {
		if messageLess(a, b) {
			return -1
		}
		if messageLess(b, a) {
			return 1
		}
		return 0
	})
	return out
}
func (q *MessageQueue) RemoveLink(l *Link) []*Message {
	out := []*Message{}
	keep := MessageHeap{}
	for _, m := range q.Ordered() {
		if m.Link() == l {
			out = append(out, m)
		} else {
			keep = append(keep, m)
		}
	}
	q.Heap = keep
	heap.Init(&q.Heap)
	return out
}

type Event struct {
	Number, Time int
	Kind, Text   string
	Args         []string
}
type Trace struct {
	Source  *ASNode
	Address uint64
	Text    string
}
type Parameters struct {
	Customer, Peer, Provider, Stepcap int
	Traces                            []Trace
}

func readEvents() []Event {
	out := []Event{{0, 0, "INITIAL", "INITIAL", nil}}
	for _, line := range lines("input/events.txt") {
		a := strings.Fields(line)
		kind := a[1]
		if kind == "LINK" || kind == "POLICY" {
			kind += "_" + a[2]
		}
		out = append(out, Event{len(out), integer(a[0]), kind, strings.Join(a[1:], " "), a[1:]})
	}
	return out
}
func readParameters(t *Topology) Parameters {
	a := lines("input/params.txt")
	v := strings.Fields(a[0])
	p := Parameters{Customer: integer(v[1]), Peer: integer(v[2]), Provider: integer(v[3]), Stepcap: integer(strings.Fields(a[1])[1])}
	for _, line := range a[2:] {
		v := strings.Fields(line)
		p.Traces = append(p.Traces, Trace{t.ByNumber[integer(v[1])], ip(v[2]), v[2]})
	}
	return p
}
