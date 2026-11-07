package main

import (
	"fmt"
	"slices"
	"sort"
	"strconv"
	"strings"
)

const noExport uint64 = 0xffffff01

func community(s string) uint64 {
	if s == "NO_EXPORT" {
		return noExport
	}
	a := strings.Split(s, ":")
	return uint64(integer(a[0]))*65536 + uint64(integer(a[1]))
}
func communityText(c uint64) string {
	if c == noExport {
		return "NO_EXPORT"
	}
	return fmt.Sprintf("%d:%d", c>>16, c&65535)
}
func communities(a []string) []uint64 {
	set := map[uint64]bool{}
	for _, s := range a {
		set[community(s)] = true
	}
	out := []uint64{}
	for c := range set {
		out = append(out, c)
	}
	slices.Sort(out)
	return out
}
func communitiesText(a []uint64) string {
	if len(a) == 0 {
		return "-"
	}
	out := make([]string, len(a))
	for i, c := range a {
		out[i] = communityText(c)
	}
	return strings.Join(out, ",")
}

type PrefixEntry struct {
	Permit    bool
	Prefix    Prefix
	Low, High int
}
type Condition struct{ Kind, Value string }
type Edit struct {
	Add       bool
	Community uint64
}
type Rule struct {
	Name, Direction, Target            string
	Owner                              int
	Active, Deny, Allow, HasLP, HasMED bool
	LP, MED, Prepend, Hits             int
	Conditions                         []Condition
	Edits                              []Edit
}

func (r *Rule) Edit(a []uint64) []uint64 {
	set := map[uint64]bool{}
	for _, c := range a {
		set[c] = true
	}
	for _, e := range r.Edits {
		if e.Add {
			set[e.Community] = true
		} else {
			delete(set, e.Community)
		}
	}
	out := []uint64{}
	for c := range set {
		out = append(out, c)
	}
	sort.Slice(out, func(i, j int) bool { return out[i] < out[j] })
	return out
}

type Policies struct {
	Lists  map[string][]PrefixEntry
	Rules  []*Rule
	ByName map[string]*Rule
}

func (p *Policies) Permitted(name string, q Prefix) bool {
	for _, e := range p.Lists[name] {
		if e.Low <= q.Length && q.Length <= e.High && e.Prefix.Contains(q.Address) {
			return e.Permit
		}
	}
	return false
}
func (p *Policies) Applied(direction string, s *Session, q Prefix, a *Attribute) *Rule {
	for _, r := range p.Rules {
		if !r.Active || r.Owner != s.Owner.Number || r.Direction != direction {
			continue
		}
		if r.Target != "*" && r.Target != strconv.Itoa(s.Link.Other(s.Owner).Number) && r.Target != s.Link.Name {
			continue
		}
		match := true
		for _, c := range r.Conditions {
			switch c.Kind {
			case "PREFIX":
				match = p.Permitted(c.Value, q)
			case "CONTAINS":
				match = slices.Contains(a.Path, integer(c.Value))
			case "ORIGINAS":
				n := s.Owner.Number
				if len(a.Path) > 0 {
					n = a.Path[len(a.Path)-1]
				}
				match = n == integer(c.Value)
			case "LENGTH":
				v := strings.Split(c.Value, "-")
				match = integer(v[0]) <= len(a.Path) && len(a.Path) <= integer(v[1])
			case "COMMUNITY":
				match = slices.Contains(a.Communities, community(c.Value))
			}
			if !match {
				break
			}
		}
		if match {
			return r
		}
	}
	return nil
}
func readPolicies() *Policies {
	p := &Policies{Lists: map[string][]PrefixEntry{}, ByName: map[string]*Rule{}}
	for _, line := range lines("input/policies.txt") {
		a := strings.Fields(line)
		if a[0] == "PLIST" {
			q := prefix(a[3])
			low, high, ge, le := q.Length, q.Length, false, false
			for i := 4; i < len(a); i += 2 {
				if a[i] == "GE" {
					low = integer(a[i+1])
					ge = true
				} else {
					high = integer(a[i+1])
					le = true
				}
			}
			if ge && !le {
				high = 32
			}
			p.Lists[a[1]] = append(p.Lists[a[1]], PrefixEntry{a[2] == "PERMIT", q, low, high})
			continue
		}
		r := &Rule{Name: a[1], Active: a[2] == "ON", Owner: integer(a[3]), Direction: a[4], Target: a[5]}
		i := 6
		for a[i] != "THEN" {
			r.Conditions = append(r.Conditions, Condition{a[i], a[i+1]})
			i += 2
		}
		i++
		for i < len(a) {
			kind := a[i]
			i++
			switch kind {
			case "DENY":
				r.Deny = true
			case "ALLOW":
				r.Allow = true
			case "LOCALPREF":
				r.LP = integer(a[i])
				r.HasLP = true
				i++
			case "MED":
				r.MED = integer(a[i])
				r.HasMED = true
				i++
			case "PREPEND":
				r.Prepend = integer(a[i])
				i++
			case "ADD", "REMOVE":
				r.Edits = append(r.Edits, Edit{kind == "ADD", community(a[i])})
				i++
			}
		}
		p.Rules = append(p.Rules, r)
		p.ByName[r.Name] = r
	}
	return p
}
