package main

import (
	"fmt"
	"os"
	"slices"
	"sort"
	"strconv"
	"strings"
)

func lines(path string) []string {
	b, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	if len(b) == 0 {
		return nil
	}
	return strings.Split(strings.TrimSuffix(string(b), "\n"), "\n")
}
func integer(s string) int {
	v, e := strconv.Atoi(s)
	if e != nil {
		panic(e)
	}
	return v
}

type Pair struct {
	ASN    int
	Prefix Prefix
}
type BestChange struct {
	Time, ASN int
	Prefix    Prefix
	Text      string
}
type EventStats struct {
	Event          Event
	Status         string
	Convergence    int
	Updates        int
	Withdrawals    int
	Drops          int
	BestChanges    int
	RoutesChanged  int
	MaxExploration int
	First, Repeat  int
	Exploration    map[Pair]int
	Changes, Cycle []BestChange
}

type Hop struct {
	Node   *ASNode
	Prefix Prefix
	Link   *Link
}
type Forwarding struct {
	Result string
	Visits []int
	Hops   []Hop
	Count  int
}
type TraceRecord struct {
	Trace, Start, End int
	Result            string
	Visits            []int
}
type RingRecord struct {
	Prefix     Prefix
	Start, End int
	Path       []int
}

func mergePath(a []int) []int {
	out := []int{}
	for _, n := range a {
		if len(out) == 0 || out[len(out)-1] != n {
			out = append(out, n)
		}
	}
	return out
}
func valleyPosition(p string) int {
	i := 0
	for i < len(p) && p[i] == 'U' {
		i++
	}
	if i < len(p) && p[i] == 'P' {
		i++
	}
	for i < len(p) && p[i] == 'D' {
		i++
	}
	return i
}
func endText(n int) string {
	if n < 0 {
		return "END"
	}
	return strconv.Itoa(n)
}

type Simulator struct {
	Topology      *Topology
	Policies      *Policies
	Parameters    Parameters
	Events        []Event
	Messages      MessageQueue
	Time, End     int
	Updates       []string
	Stats         []*EventStats
	Current       *EventStats
	Changed       map[Prefix]bool
	TraceRecords  []*TraceRecord
	OngoingTraces []*TraceRecord
	RingRecords   []*RingRecord
	OngoingRings  map[Prefix]map[string]*RingRecord
}

func (s *Simulator) Log(format string, args ...any) {
	s.Updates = append(s.Updates, fmt.Sprintf("%d ", s.Time)+fmt.Sprintf(format, args...))
}
func (s *Simulator) Import(session *Session, p Prefix, a *Attribute) (*Route, *Rule) {
	rule := s.Policies.Applied("IMPORT", session, p, a)
	if rule != nil && rule.Deny {
		return nil, rule
	}
	lp := s.Parameters.Provider
	switch session.Link.Role(session.Owner) {
	case "customer":
		lp = s.Parameters.Customer
	case "peer":
		lp = s.Parameters.Peer
	}
	med, comm := a.MED, a.Communities
	if rule != nil {
		if rule.HasLP {
			lp = rule.LP
		}
		if rule.HasMED {
			med = rule.MED
		}
		comm = rule.Edit(comm)
	}
	return &Route{Attribute: &Attribute{a.Path, a.Origin, med, comm}, LP: lp, Link: session.Link}, rule
}
func (s *Simulator) Candidates(node *ASNode, p Prefix) []*Route {
	out := []*Route{}
	for _, session := range node.Sessions {
		if a := session.Incoming[p]; a != nil {
			r, _ := s.Import(session, p, a)
			if r != nil {
				out = append(out, r)
			}
		}
	}
	return out
}
func (s *Simulator) Redecide(node *ASNode, p Prefix) {
	var route *Route
	if a := node.Origins[p]; a != nil {
		route = &Route{Attribute: a, Local: true}
	} else {
		choices := s.Candidates(node, p)
		if len(choices) > 0 {
			route, _ = bestRoute(choices, s.Topology)
		}
	}
	if sameRoute(route, node.RIB[p]) {
		return
	}
	if route == nil {
		delete(node.RIB, p)
	} else {
		node.RIB[p] = route
	}
	text := routeText(route)
	s.Log("BEST %d %s %s", node.Number, p.Text(), text)
	node.Changes++
	s.Current.BestChanges++
	key := Pair{node.Number, p}
	s.Current.Exploration[key]++
	s.Current.MaxExploration = max(s.Current.MaxExploration, s.Current.Exploration[key])
	s.Current.Changes = append(s.Current.Changes, BestChange{s.Time, node.Number, p, text})
	s.Changed[p] = true
	for _, session := range node.Sessions {
		if !session.Link.Up {
			continue
		}
		session.Pending[p] = true
		if session.Timer < 0 {
			s.Pending(session)
		}
	}
}
func (s *Simulator) Advertised(session *Session, p Prefix) (*Attribute, *Rule) {
	r := session.Owner.RIB[p]
	if r == nil {
		return nil, nil
	}
	a := r.Attribute
	if !r.Local && a.Path[0] == session.Link.Other(session.Owner).Number {
		return nil, nil
	}
	if slices.Contains(a.Communities, noExport) {
		return nil, nil
	}
	rule := s.Policies.Applied("EXPORT", session, p, a)
	if rule != nil && rule.Deny {
		return nil, rule
	}
	allow := rule != nil && rule.Allow
	if !allow && !r.Local && r.Link.Role(session.Owner) != "customer" && session.Link.Role(session.Owner) != "customer" {
		return nil, rule
	}
	prepend, med, comm := 0, 0, a.Communities
	if rule != nil {
		prepend = rule.Prepend
		if rule.HasMED {
			med = rule.MED
		}
		comm = rule.Edit(comm)
	}
	path := make([]int, 1+prepend, 1+prepend+len(a.Path))
	for i := range path {
		path[i] = session.Owner.Number
	}
	path = append(path, a.Path...)
	return &Attribute{path, a.Origin, med, comm}, rule
}
func (s *Simulator) Pending(session *Session) {
	sent := 0
	for _, p := range orderedPrefixes(session.Pending) {
		a, rule := s.Advertised(session, p)
		if sameAttribute(a, session.Outgoing[p]) {
			continue
		}
		if a == nil {
			delete(session.Outgoing, p)
		} else {
			session.Outgoing[p] = a
		}
		m := s.Messages.Send(s.Time, session, p, a)
		sent++
		session.Sent++
		s.Current.Updates++
		base := fmt.Sprintf("SEND #%d %d->%d %s %s", m.Serial, m.Sender().Number, m.Receiver().Number, m.Link().Name, p.Text())
		if a == nil {
			s.Current.Withdrawals++
			s.Log("%s WITHDRAW", base)
		} else {
			s.Log("%s ANNOUNCE %s", base, attributeText(a))
		}
		if rule != nil {
			rule.Hits++
		}
	}
	clear(session.Pending)
	session.Timer = -1
	if sent > 0 && session.Link.MRAI > 0 {
		session.Timer = s.Time + session.Link.MRAI
	}
}
func (s *Simulator) Receive(m *Message) {
	session, a := m.Link().Session(m.Receiver()), m.Attribute
	result := "WITHDRAW"
	session.Received++
	if a == nil {
		delete(session.Incoming, m.Prefix)
	} else if slices.Contains(a.Path, m.Receiver().Number) {
		delete(session.Incoming, m.Prefix)
		result = "ANNOUNCE loop"
	} else {
		session.Incoming[m.Prefix] = a
		r, rule := s.Import(session, m.Prefix, a)
		result = "ANNOUNCE accept"
		if rule != nil {
			rule.Hits++
			if r == nil {
				result = "ANNOUNCE deny " + rule.Name
			} else {
				result += " " + rule.Name
			}
		}
	}
	s.Log("RECV #%d %d->%d %s %s %s", m.Serial, m.Sender().Number, m.Receiver().Number, m.Link().Name, m.Prefix.Text(), result)
	s.Redecide(m.Receiver(), m.Prefix)
}
func (s *Simulator) Execute(event Event) {
	s.Log("EVENT %d %s", event.Number, event.Text)
	a := event.Args
	switch event.Kind {
	case "INITIAL":
		for _, x := range s.Topology.Initial {
			x.Node.Origins[x.Prefix] = x.Attribute
			s.Redecide(x.Node, x.Prefix)
		}
	case "ANNOUNCE":
		n, p := s.Topology.ByNumber[integer(a[1])], prefix(a[2])
		n.Origins[p] = &Attribute{Origin: a[3], Communities: communities(a[4:])}
		s.Redecide(n, p)
	case "WITHDRAW":
		n, p := s.Topology.ByNumber[integer(a[1])], prefix(a[2])
		delete(n.Origins, p)
		s.Redecide(n, p)
	case "LINK_DOWN":
		l := s.Topology.ByName[a[2]]
		l.Up = false
		l.Downs++
		for _, m := range s.Messages.RemoveLink(l) {
			s.Current.Drops++
			s.Log("DROP #%d %d->%d %s %s", m.Serial, m.Sender().Number, m.Receiver().Number, l.Name, m.Prefix.Text())
		}
		endpoints := []*ASNode{l.A, l.B}
		sort.Slice(endpoints, func(i, j int) bool { return endpoints[i].Number < endpoints[j].Number })
		remembered := make([][]Prefix, 2)
		for i, n := range endpoints {
			session := l.Session(n)
			remembered[i] = orderedPrefixes(session.Incoming)
			clear(session.Incoming)
			clear(session.Outgoing)
			clear(session.Pending)
			session.Timer = -1
		}
		for i, n := range endpoints {
			for _, p := range remembered[i] {
				s.Redecide(n, p)
			}
		}
	case "LINK_UP":
		l := s.Topology.ByName[a[2]]
		l.Up = true
		endpoints := []*ASNode{l.A, l.B}
		sort.Slice(endpoints, func(i, j int) bool { return endpoints[i].Number < endpoints[j].Number })
		for _, n := range endpoints {
			session := l.Session(n)
			clear(session.Pending)
			for p := range n.RIB {
				session.Pending[p] = true
			}
			s.Pending(session)
		}
	case "POLICY_ON", "POLICY_OFF":
		rule := s.Policies.ByName[a[2]]
		rule.Active = event.Kind == "POLICY_ON"
		n := s.Topology.ByNumber[rule.Owner]
		if rule.Direction == "IMPORT" {
			prefixes := map[Prefix]bool{}
			for _, session := range n.Sessions {
				for p := range session.Incoming {
					prefixes[p] = true
				}
			}
			for _, p := range orderedPrefixes(prefixes) {
				s.Redecide(n, p)
			}
		} else {
			for _, session := range n.Sessions {
				if !session.Link.Up {
					continue
				}
				for p := range n.RIB {
					session.Pending[p] = true
				}
				for p := range session.Outgoing {
					session.Pending[p] = true
				}
				if session.Timer < 0 {
					s.Pending(session)
				}
			}
		}
	}
}
func (s *Simulator) Quiet() bool {
	if len(s.Messages.Heap) > 0 {
		return false
	}
	for _, session := range s.Topology.Sessions {
		if len(session.Pending) > 0 {
			return false
		}
	}
	return true
}
func (s *Simulator) State() string {
	var out strings.Builder
	table := func(tag string, a map[Prefix]*Attribute) {
		out.WriteString(tag + "{")
		for _, p := range orderedPrefixes(a) {
			fmt.Fprintf(&out, "%s=%s;", p.Text(), attributeText(a[p]))
		}
		out.WriteString("}")
	}
	for _, session := range s.Topology.Sessions {
		fmt.Fprintf(&out, "S%d:%d", session.Owner.Number, session.Link.Number)
		table("I", session.Incoming)
		table("O", session.Outgoing)
		out.WriteString("P{")
		for _, p := range orderedPrefixes(session.Pending) {
			out.WriteString(p.Text() + ";")
		}
		timer := -1
		if session.Timer >= 0 {
			timer = session.Timer - s.Time
		}
		fmt.Fprintf(&out, "}T%d;", timer)
	}
	out.WriteString("Q{")
	for _, m := range s.Messages.Ordered() {
		fmt.Fprintf(&out, "%d:%d:%d:%d:%s:", m.Time-s.Time, m.Receiver().Number, m.Sender().Number, m.Link().Number, m.Prefix.Text())
		if m.Attribute == nil {
			out.WriteString("W;")
		} else {
			out.WriteString("A" + attributeText(m.Attribute) + ";")
		}
	}
	out.WriteString("}")
	return out.String()
}
func (s *Simulator) Snapshot() map[Pair]*Route {
	out := map[Pair]*Route{}
	for _, n := range s.Topology.Nodes {
		for p, r := range n.RIB {
			out[Pair{n.Number, p}] = r
		}
	}
	return out
}
func (s *Simulator) Run() {
	for k, event := range s.Events {
		s.Current = &EventStats{Event: event, First: -1, Repeat: -1, Exploration: map[Pair]int{}}
		before, seen := s.Snapshot(), map[string]int{}
		deliveries := 0
		s.Time = event.Time
		clear(s.Changed)
		s.Execute(event)
		for t := event.Time; ; t++ {
			s.Time = t
			if t > event.Time {
				clear(s.Changed)
			}
			arrived := s.Messages.Arrivals(t)
			for _, m := range arrived {
				s.Receive(m)
			}
			if len(arrived) > 0 {
				s.Current.Convergence = t - event.Time
			}
			for _, session := range s.Topology.Sessions {
				if session.Timer == t {
					session.Timer = -1
					if len(session.Pending) > 0 {
						s.Pending(session)
					}
				}
			}
			if len(s.Changed) > 0 {
				s.ForwardingCheck()
			}
			if len(arrived) > 0 {
				deliveries++
				if s.Current.First < 0 && deliveries <= s.Parameters.Stepcap {
					key := s.State()
					if first, ok := seen[key]; ok {
						s.Current.First = first
						s.Current.Repeat = t
						for _, c := range s.Current.Changes {
							if c.Time > first && c.Time <= t {
								s.Current.Cycle = append(s.Current.Cycle, c)
							}
						}
					} else {
						seen[key] = t
					}
				}
			}
			last := k == len(s.Events)-1
			stop := last && (s.Quiet() || s.Current.First >= 0 || deliveries >= s.Parameters.Stepcap)
			if !last {
				stop = t == s.Events[k+1].Time-1
			}
			if stop {
				s.End = t
				break
			}
		}
		switch {
		case s.Current.First >= 0:
			s.Current.Status = "DIVERGENT"
		case s.Quiet():
			s.Current.Status = "CONVERGED"
		case k == len(s.Events)-1:
			s.Current.Status = "CAPPED"
		default:
			s.Current.Status = "UNSETTLED"
		}
		after := s.Snapshot()
		pairs := map[Pair]bool{}
		for p := range before {
			pairs[p] = true
		}
		for p := range after {
			pairs[p] = true
		}
		for p := range pairs {
			if !sameRoute(before[p], after[p]) {
				s.Current.RoutesChanged++
			}
		}
		s.Stats = append(s.Stats, s.Current)
	}
}
func (s *Simulator) Forward(source *ASNode, address uint64) Forwarding {
	out := Forwarding{Visits: []int{source.Number}}
	visited := map[int]bool{source.Number: true}
	node := source
	for {
		var route *Route
		var selected Prefix
		for p, r := range node.RIB {
			if p.Contains(address) && (route == nil || p.Length > selected.Length) {
				route = r
				selected = p
			}
		}
		if route == nil {
			out.Result = "UNREACHABLE"
			if len(out.Hops) > 0 {
				out.Result = "BLACKHOLE"
			}
			return out
		}
		if route.Local {
			out.Hops = append(out.Hops, Hop{node, selected, nil})
			out.Result = "DELIVERED"
			return out
		}
		l := route.Link
		out.Hops = append(out.Hops, Hop{node, selected, l})
		out.Count++
		node = l.Other(node)
		out.Visits = append(out.Visits, node.Number)
		if visited[node.Number] {
			out.Result = "LOOP"
			return out
		}
		visited[node.Number] = true
	}
}
func (s *Simulator) Pattern(path []int) string {
	var out strings.Builder
	for i := 0; i+1 < len(path); i++ {
		out.WriteString(symbol(s.Topology.Between(path[i], path[i+1]).Role(s.Topology.ByNumber[path[i]])))
	}
	return out.String()
}
func (s *Simulator) Loops(p Prefix) [][]int {
	done := map[int]bool{}
	out := [][]int{}
	for _, source := range s.Topology.Nodes {
		if done[source.Number] {
			continue
		}
		positions := map[int]int{}
		path := []int{}
		node := source
		for {
			if done[node.Number] {
				break
			}
			if at, ok := positions[node.Number]; ok {
				cycle := path[at:]
				first := 0
				for i, n := range cycle {
					if n < cycle[first] {
						first = i
					}
				}
				rotated := append(slices.Clone(cycle[first:]), cycle[:first]...)
				out = append(out, rotated)
				break
			}
			positions[node.Number] = len(path)
			path = append(path, node.Number)
			r := node.RIB[p]
			if r == nil || r.Local {
				break
			}
			node = r.Link.Other(node)
		}
		for _, n := range path {
			done[n] = true
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i][0] < out[j][0] })
	return out
}
func (s *Simulator) ForwardingCheck() {
	for _, p := range orderedPrefixes(s.Changed) {
		paths := s.Loops(p)
		found := map[string][]int{}
		for _, path := range paths {
			found[pathText(path)] = path
		}
		ongoing := s.OngoingRings[p]
		if ongoing == nil {
			ongoing = map[string]*RingRecord{}
			s.OngoingRings[p] = ongoing
		}
		for key, r := range ongoing {
			if _, ok := found[key]; !ok {
				r.End = s.Time
				delete(ongoing, key)
			}
		}
		for _, path := range paths {
			key := pathText(path)
			if ongoing[key] == nil {
				r := &RingRecord{p, s.Time, -1, slices.Clone(path)}
				ongoing[key] = r
				s.RingRecords = append(s.RingRecords, r)
			}
		}
	}
	for i, trace := range s.Parameters.Traces {
		path := s.Forward(trace.Source, trace.Address)
		status := ""
		if path.Result == "LOOP" || path.Result == "BLACKHOLE" {
			status = path.Result
		}
		old := s.OngoingTraces[i]
		if old != nil && (old.Result != status || !slices.Equal(old.Visits, path.Visits)) {
			old.End = s.Time
			s.OngoingTraces[i] = nil
		}
		if status != "" && s.OngoingTraces[i] == nil {
			r := &TraceRecord{i, s.Time, -1, status, slices.Clone(path.Visits)}
			s.OngoingTraces[i] = r
			s.TraceRecords = append(s.TraceRecords, r)
		}
	}
}
func (s *Simulator) ConvergenceLines() []string {
	out := []string{"event,time,kind,status,convergence_time,updates,withdrawals,drops,best_changes,routes_changed,max_exploration"}
	for _, r := range s.Stats {
		out = append(out, fmt.Sprintf("%d,%d,%s,%s,%d,%d,%d,%d,%d,%d,%d", r.Event.Number, r.Event.Time, r.Event.Kind, r.Status, r.Convergence, r.Updates, r.Withdrawals, r.Drops, r.BestChanges, r.RoutesChanged, r.MaxExploration))
	}
	return out
}
func (s *Simulator) RIBLines() []string {
	out := []string{}
	for _, n := range s.Topology.Nodes {
		sent, received, local := 0, 0, 0
		for _, session := range n.Sessions {
			sent += session.Sent
			received += session.Received
		}
		for _, r := range n.RIB {
			if r.Local {
				local++
			}
		}
		out = append(out, fmt.Sprintf("AS %d routes %d local %d sent %d received %d changes %d", n.Number, len(n.RIB), local, sent, received, n.Changes))
		for _, session := range n.Sessions {
			accepted := 0
			for p, a := range session.Incoming {
				r, _ := s.Import(session, p, a)
				if r != nil {
					accepted++
				}
			}
			state := "DOWN"
			if session.Link.Up {
				state = "UP"
			}
			out = append(out, fmt.Sprintf("SESSION %s %d %s %s in %d accepted %d out %d sent %d received %d flaps %d", session.Link.Name, session.Link.Other(n).Number, session.Link.Role(n), state, len(session.Incoming), accepted, len(session.Outgoing), session.Sent, session.Received, session.Link.Downs))
		}
		for _, p := range orderedPrefixes(n.RIB) {
			r := n.RIB[p]
			choices := s.Candidates(n, p)
			text := fmt.Sprintf("%s %s candidates %d", p.Text(), routeText(r), len(choices))
			if !r.Local {
				_, reason := bestRoute(choices, s.Topology)
				text += " reason " + reason
			}
			out = append(out, text)
			remaining := []*Route{}
			for _, c := range choices {
				if !sameRoute(c, r) {
					remaining = append(remaining, c)
				}
			}
			for len(remaining) > 0 {
				best, _ := bestRoute(remaining, s.Topology)
				out = append(out, "ALT "+routeText(best))
				for i, c := range remaining {
					if c == best {
						remaining = append(remaining[:i], remaining[i+1:]...)
						break
					}
				}
			}
		}
	}
	return out
}
func (s *Simulator) PathLines() []string {
	out := []string{}
	for _, trace := range s.Parameters.Traces {
		path := s.Forward(trace.Source, trace.Address)
		var directions strings.Builder
		out = append(out, fmt.Sprintf("TRACE %d %s %s hops %d", trace.Source.Number, trace.Text, path.Result, path.Count))
		for _, hop := range path.Hops {
			if hop.Link == nil {
				out = append(out, fmt.Sprintf("HOP %d %s LOCAL", hop.Node.Number, hop.Prefix.Text()))
			} else {
				out = append(out, fmt.Sprintf("HOP %d %s next %d link %s", hop.Node.Number, hop.Prefix.Text(), hop.Link.Other(hop.Node).Number, hop.Link.Name))
				directions.WriteString(symbol(hop.Link.Role(hop.Node)))
			}
		}
		last := path.Visits[len(path.Visits)-1]
		if path.Result == "LOOP" {
			out = append(out, fmt.Sprintf("HOP %d REVISIT", last))
		} else if path.Result == "BLACKHOLE" || path.Result == "UNREACHABLE" {
			out = append(out, fmt.Sprintf("HOP %d NOROUTE", last))
		}
		if len(path.Hops) == 0 {
			out = append(out, "CONTROL NONE")
		} else {
			r := trace.Source.RIB[path.Hops[0].Prefix]
			notation := pathText(r.Attribute.Path)
			if r.Local {
				notation = "LOCAL"
			}
			match := "MISMATCH"
			if path.Result == "DELIVERED" && slices.Equal(mergePath(r.Attribute.Path), path.Visits[1:]) {
				match = "MATCH"
			}
			out = append(out, "CONTROL "+notation+" "+match)
		}
		if path.Count > 0 {
			w := directions.String()
			judgment := "VALLEY"
			if valleyPosition(w) == len(w) {
				judgment = "VALLEYFREE"
			}
			out = append(out, "PATTERN "+w+" "+judgment)
		}
	}
	set := map[Prefix]bool{}
	for _, n := range s.Topology.Nodes {
		for p := range n.Origins {
			set[p] = true
		}
	}
	prefixes := orderedPrefixes(set)
	notations := make([]string, len(prefixes))
	for i, p := range prefixes {
		notations[i] = p.Text()
	}
	text := "PREFIXES"
	if len(prefixes) > 0 {
		text += " " + strings.Join(notations, ",")
	}
	out = append(out, text)
	for _, n := range s.Topology.Nodes {
		var symbols strings.Builder
		for _, p := range prefixes {
			path := s.Forward(n, p.Address)
			symbol := "U"
			switch path.Result {
			case "LOOP":
				symbol = "L"
			case "BLACKHOLE":
				symbol = "B"
			case "DELIVERED":
				symbol = "*"
				if path.Count > 0 {
					symbol = "X"
					arrival := path.Hops[len(path.Hops)-1].Node
					if arrival.Origins[p] != nil {
						symbol = "+"
					}
				}
			}
			symbols.WriteString(symbol)
		}
		text := fmt.Sprintf("REACH %d", n.Number)
		if symbols.Len() > 0 {
			text += " " + symbols.String()
		}
		out = append(out, text)
	}
	return out
}
func (s *Simulator) AuditLines() []string {
	out := []string{}
	loops, blackholes, valleys, learned, divergent := 0, 0, 0, 0, 0
	traces := slices.Clone(s.TraceRecords)
	sort.Slice(traces, func(i, j int) bool {
		if traces[i].Start != traces[j].Start {
			return traces[i].Start < traces[j].Start
		}
		return traces[i].Trace < traces[j].Trace
	})
	for _, r := range traces {
		t := s.Parameters.Traces[r.Trace]
		text := fmt.Sprintf("%s %d %s from %d to %s", r.Result, t.Source.Number, t.Text, r.Start, endText(r.End))
		if r.Result == "BLACKHOLE" {
			blackholes++
			text += fmt.Sprintf(" at %d", r.Visits[len(r.Visits)-1])
		} else {
			loops++
		}
		out = append(out, text+" path "+pathText(r.Visits))
	}
	rings := slices.Clone(s.RingRecords)
	sort.Slice(rings, func(i, j int) bool {
		a, b := rings[i], rings[j]
		if a.Start != b.Start {
			return a.Start < b.Start
		}
		if a.Prefix != b.Prefix {
			return prefixLess(a.Prefix, b.Prefix)
		}
		return a.Path[0] < b.Path[0]
	})
	for _, r := range rings {
		out = append(out, fmt.Sprintf("RING %s from %d to %s path %s", r.Prefix.Text(), r.Start, endText(r.End), pathText(r.Path)))
	}
	for _, n := range s.Topology.Nodes {
		for _, p := range orderedPrefixes(n.RIB) {
			r := n.RIB[p]
			if r.Local {
				continue
			}
			learned++
			h := mergePath(append([]int{n.Number}, r.Attribute.Path...))
			w := s.Pattern(h)
			g := valleyPosition(w)
			if g < len(w) {
				valleys++
				out = append(out, fmt.Sprintf("VALLEY %d %s path %s pattern %s leaker %d", n.Number, p.Text(), pathText(r.Attribute.Path), w, h[g]))
			}
		}
	}
	for _, r := range s.Policies.Rules {
		state := "OFF"
		if r.Active {
			state = "ON"
		}
		out = append(out, fmt.Sprintf("RULE %s %s %s hits %d", r.Name, r.Direction, state, r.Hits))
	}
	for _, r := range s.Stats {
		if r.First < 0 {
			continue
		}
		divergent++
		out = append(out, fmt.Sprintf("DIVERGENT event %d first %d repeat %d period %d", r.Event.Number, r.First, r.Repeat, r.Repeat-r.First))
		counts := map[Pair]int{}
		for _, c := range r.Cycle {
			out = append(out, fmt.Sprintf("CYCLE %d %d %s %s", c.Time, c.ASN, c.Prefix.Text(), c.Text))
			counts[Pair{c.ASN, c.Prefix}]++
		}
		pairs := make([]Pair, 0, len(counts))
		for p := range counts {
			pairs = append(pairs, p)
		}
		sort.Slice(pairs, func(i, j int) bool {
			if pairs[i].ASN != pairs[j].ASN {
				return pairs[i].ASN < pairs[j].ASN
			}
			return prefixLess(pairs[i].Prefix, pairs[j].Prefix)
		})
		for _, p := range pairs {
			out = append(out, fmt.Sprintf("OSCILLATE %d %s changes %d", p.ASN, p.Prefix.Text(), counts[p]))
		}
	}
	out = append(out, fmt.Sprintf("SUMMARY loops %d blackholes %d rings %d routes %d valleys %d divergent %d end %d", loops, blackholes, len(rings), learned, valleys, divergent, s.End))
	return out
}
func main() {
	t := readTopology()
	p := readParameters(t)
	s := &Simulator{Topology: t, Policies: readPolicies(), Parameters: p, Events: readEvents(), Changed: map[Prefix]bool{}, OngoingTraces: make([]*TraceRecord, len(p.Traces)), OngoingRings: map[Prefix]map[string]*RingRecord{}}
	s.Run()
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	writeLines("updates.txt", s.Updates)
	writeLines("convergence.csv", s.ConvergenceLines())
	writeLines("ribs.txt", s.RIBLines())
	writeLines("paths.txt", s.PathLines())
	writeLines("audit.txt", s.AuditLines())
}
