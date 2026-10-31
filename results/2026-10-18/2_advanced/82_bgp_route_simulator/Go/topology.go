package main

import (
	"fmt"
	"sort"
	"strconv"
	"strings"
)

type Prefix struct {
	Address uint64
	Length  int
}

func ip(s string) uint64 {
	var n uint64
	for _, a := range strings.Split(s, ".") {
		v, _ := strconv.ParseUint(a, 10, 64)
		n = n*256 + v
	}
	return n
}
func ipText(n uint64) string {
	return fmt.Sprintf("%d.%d.%d.%d", n>>24, (n>>16)&255, (n>>8)&255, n&255)
}
func prefix(s string) Prefix {
	a := strings.Split(s, "/")
	return Prefix{ip(a[0]), integer(a[1])}
}
func (p Prefix) Text() string { return fmt.Sprintf("%s/%d", ipText(p.Address), p.Length) }
func (p Prefix) Contains(address uint64) bool {
	return p.Address>>uint(32-p.Length) == address>>uint(32-p.Length)
}
func prefixLess(a, b Prefix) bool {
	if a.Address != b.Address {
		return a.Address < b.Address
	}
	return a.Length < b.Length
}
func orderedPrefixes[T any](a map[Prefix]T) []Prefix {
	out := make([]Prefix, 0, len(a))
	for p := range a {
		out = append(out, p)
	}
	sort.Slice(out, func(i, j int) bool { return prefixLess(out[i], out[j]) })
	return out
}

type ASNode struct {
	Number   int
	Router   uint64
	Origins  map[Prefix]*Attribute
	RIB      map[Prefix]*Route
	Sessions []*Session
	Changes  int
}
type Link struct {
	Name, Relationship         string
	A, B                       *ASNode
	Delay, MRAI, Number, Downs int
	Up                         bool
	Sessions                   []*Session
}

func (l *Link) Other(n *ASNode) *ASNode {
	if n == l.A {
		return l.B
	}
	return l.A
}
func (l *Link) Role(n *ASNode) string {
	if l.Relationship == "P2P" {
		return "peer"
	}
	if n == l.A {
		return "customer"
	}
	return "provider"
}
func (l *Link) Session(n *ASNode) *Session {
	if n == l.A {
		return l.Sessions[0]
	}
	return l.Sessions[1]
}
func symbol(role string) string {
	if role == "customer" {
		return "D"
	}
	if role == "provider" {
		return "U"
	}
	return "P"
}

type Initial struct {
	Node      *ASNode
	Prefix    Prefix
	Attribute *Attribute
}
type Topology struct {
	Nodes    []*ASNode
	ByNumber map[int]*ASNode
	Links    []*Link
	ByName   map[string]*Link
	Initial  []Initial
	Sessions []*Session
}

func (t *Topology) Between(a, b int) *Link {
	for _, s := range t.ByNumber[a].Sessions {
		if s.Link.Other(s.Owner).Number == b {
			return s.Link
		}
	}
	panic("missing link")
}
func readTopology() *Topology {
	t := &Topology{ByNumber: map[int]*ASNode{}, ByName: map[string]*Link{}}
	for _, line := range lines("input/topology.txt") {
		a := strings.Fields(line)
		switch a[0] {
		case "AS":
			n := &ASNode{Number: integer(a[1]), Router: ip(a[2]), Origins: map[Prefix]*Attribute{}, RIB: map[Prefix]*Route{}}
			t.Nodes = append(t.Nodes, n)
			t.ByNumber[n.Number] = n
		case "LINK":
			l := &Link{Name: a[1], A: t.ByNumber[integer(a[2])], B: t.ByNumber[integer(a[3])], Relationship: a[4], Delay: integer(a[5]), MRAI: integer(a[6]), Number: len(t.Links), Up: true}
			t.Links = append(t.Links, l)
			t.ByName[l.Name] = l
			for _, n := range []*ASNode{l.A, l.B} {
				s := &Session{Owner: n, Link: l, Incoming: map[Prefix]*Attribute{}, Outgoing: map[Prefix]*Attribute{}, Pending: map[Prefix]bool{}, Timer: -1}
				l.Sessions = append(l.Sessions, s)
				n.Sessions = append(n.Sessions, s)
			}
		case "PREFIX":
			t.Initial = append(t.Initial, Initial{t.ByNumber[integer(a[1])], prefix(a[2]), &Attribute{Origin: a[3], Communities: communities(a[4:])}})
		}
	}
	sort.Slice(t.Nodes, func(i, j int) bool { return t.Nodes[i].Number < t.Nodes[j].Number })
	for _, n := range t.Nodes {
		t.Sessions = append(t.Sessions, n.Sessions...)
	}
	return t
}
