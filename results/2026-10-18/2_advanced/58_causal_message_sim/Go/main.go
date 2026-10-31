package main

import (
	"container/heap"
	"fmt"
	"os"
	"sort"
	"strings"
)

type Params struct {
	Seed, End, CutTime int
	Compares           [][2]string
	Cuts               [][]int
	Predicates         []int
}

func readParams() Params {
	p := Params{}
	for _, line := range readLines("input/params.txt") {
		a := strings.Fields(line)
		switch a[0] {
		case "SEED":
			p.Seed = integer(a[1])
		case "END":
			p.End = integer(a[1])
		case "CUTCOUNT":
			p.CutTime = integer(a[1])
		case "COMPARE":
			p.Compares = append(p.Compares, [2]string{a[1], a[2]})
		case "CUT":
			v := []int{}
			for _, s := range a[1:] {
				v = append(v, integer(s))
			}
			p.Cuts = append(p.Cuts, v)
		case "PREDICATE":
			p.Predicates = append(p.Predicates, integer(a[1]))
		}
	}
	return p
}

type Event struct {
	Number, Process, Local, Time, L, Balance int
	V                                        []int
	Kind, Details                            string
	Message                                  *Message
	Copy                                     *Copy
}
type Message struct {
	ID, Source, Destination, Amount int
	Kind, Tag                       string
	Stamp                           []int
	Event                           *Event
	Copies                          []*Copy
}
type Copy struct {
	Message                                *Message
	Source, Destination, Arrival, Delivery int
	FIFO, Causal                           bool
	Missing                                []int
	Received                               *Event
}
type Packet struct {
	Source, Destination, Sequence, Arrival int
	Copy                                   *Copy
	Snapshot                               *Snapshot
}
type Item struct {
	Time, Process, Creation int
	Action                  *Action
	Packet                  *Packet
}
type Queue []*Item

func (q Queue) Len() int { return len(q) }
func (q Queue) Less(i, j int) bool {
	a, b := q[i], q[j]
	if a.Time != b.Time {
		return a.Time < b.Time
	}
	if a.Process != b.Process {
		return a.Process < b.Process
	}
	return a.Creation < b.Creation
}
func (q Queue) Swap(i, j int) { q[i], q[j] = q[j], q[i] }
func (q *Queue) Push(v any)   { *q = append(*q, v.(*Item)) }
func (q *Queue) Pop() any     { a := *q; v := a[len(a)-1]; *q = a[:len(a)-1]; return v }

type Display struct {
	Event    *Event
	Record   *SnapshotRecord
	Snapshot string
}
type Simulation struct {
	Network                 Network
	Processes               []*Process
	Events                  []*Event
	Messages                []*Message
	Copies                  []*Copy
	Snapshots               []*Snapshot
	SnapshotIndex           map[string]*Snapshot
	Display                 []Display
	Queue                   Queue
	Creation, Time, Initial int
	Raw                     bool
}

func (s *Simulation) schedule(item *Item) {
	s.Creation++
	item.Creation = s.Creation
	heap.Push(&s.Queue, item)
}
func (s *Simulation) dispatch(source, destination int, c *Copy, snapshot *Snapshot) {
	sequence, arrival := s.Network.dispatch(source, destination, s.Time, c)
	p := &Packet{source, destination, sequence, arrival, c, snapshot}
	if c != nil {
		c.Arrival = arrival
	}
	s.schedule(&Item{Time: arrival, Process: destination, Packet: p})
}
func (s *Simulation) event(p *Process, kind, details string, m *Message, c *Copy) *Event {
	var sent *Event
	if c != nil {
		sent = c.Message.Event
	}
	tick(p, sent)
	e := &Event{Number: len(s.Events) + 1, Process: p.Index, Local: len(p.Events) + 1, Time: s.Time,
		L: p.L, Balance: p.Balance, V: append([]int(nil), p.V...), Kind: kind, Details: details,
		Message: m, Copy: c}
	s.Events = append(s.Events, e)
	p.Events = append(p.Events, e)
	p.Counts[kind]++
	p.Minimum = min(p.Minimum, p.Balance)
	s.Display = append(s.Display, Display{Event: e})
	return e
}
func (s *Simulation) action(p *Process, a Action, sender int) {
	switch a.Kind {
	case "LOCAL":
		s.event(p, "LOCAL", a.Argument, nil, nil)
	case "SNAPSHOT":
		snapshot := s.SnapshotIndex[a.Argument]
		if snapshot == nil {
			snapshot = &Snapshot{Name: a.Argument, Start: s.Time, Completed: -1, Records: make([]*SnapshotRecord,
				len(s.Processes)), Channels: map[ChannelKey]*SnapshotChannel{}}
			for _, key := range s.Network.Order {
				snapshot.Channels[key] = &SnapshotChannel{Dispatched: -1, Accepted: -1}
			}
			s.SnapshotIndex[a.Argument] = snapshot
			s.Snapshots = append(s.Snapshots, snapshot)
		}
		if snapshot.Records[p.Index] != nil {
			snapshot.Ignored = append(snapshot.Ignored, [2]int{p.Index, s.Time})
		} else {
			s.record(snapshot, p, "initiate")
		}
	default:
		destination := -1
		amount := 0
		kind, tag := "P2P", a.Value
		if a.Kind == "BROADCAST" {
			kind, tag = "BCAST", a.Argument
			p.B[p.Index]++
		} else {
			if a.Argument == "SENDER" {
				destination = sender
			} else {
				destination = s.Network.Index[a.Argument]
			}
			if a.Kind == "TRANSFER" {
				amount = integer(a.Value)
				tag = "transfer"
				if amount > p.Balance {
					p.Refused++
					s.event(p, "NOFUNDS", fmt.Sprintf("to %s amount %d balance %d", s.Network.Names[destination], amount, p.Balance), nil, nil)
					return
				}
				p.Balance -= amount
				p.Out += amount
			}
		}
		m := &Message{ID: len(s.Messages) + 1, Source: p.Index, Destination: destination, Amount: amount, Kind: kind, Tag: tag}
		if kind == "BCAST" {
			m.Stamp = append([]int(nil), p.B...)
		}
		s.Messages = append(s.Messages, m)
		eventKind, details := "SEND", fmt.Sprintf("m%d to %s tag %s", m.ID, processName(s.Network, destination), tag)
		if kind == "BCAST" {
			eventKind, details = "BCAST", fmt.Sprintf("m%d tag %s", m.ID, tag)
		} else if tag == "transfer" {
			details += fmt.Sprintf(" amount %d balance %d", amount, p.Balance)
		}
		m.Event = s.event(p, eventKind, details, m, nil)
		for q := range s.Processes {
			if q == p.Index || (kind == "P2P" && q != destination) {
				continue
			}
			c := &Copy{Message: m, Source: p.Index, Destination: q, Delivery: -1}
			m.Copies = append(m.Copies, c)
			s.Copies = append(s.Copies, c)
			s.dispatch(p.Index, q, c, nil)
		}
	}
}
func processName(n Network, index int) string {
	if index < 0 {
		return ""
	}
	return n.Names[index]
}
func (s *Simulation) record(snapshot *Snapshot, p *Process, reason string) {
	record := &SnapshotRecord{p.Index, s.Time, p.Balance, p.L, reason, append([]int(nil), p.V...), append([]*Copy(nil), p.Hold...)}
	snapshot.Records[p.Index] = record
	s.Display = append(s.Display, Display{Record: record, Snapshot: snapshot.Name})
	for q := range s.Processes {
		if q == p.Index {
			continue
		}
		channel := snapshot.Channels[ChannelKey{p.Index, q}]
		channel.Dispatched = s.Time
		s.dispatch(p.Index, q, nil, snapshot)
	}
}
func (s *Simulation) marker(packet *Packet) {
	snapshot := packet.Snapshot
	p := s.Processes[packet.Destination]
	if snapshot.Records[p.Index] == nil {
		s.record(snapshot, p, "marker "+s.Network.Names[packet.Source])
	}
	snapshot.Channels[ChannelKey{packet.Source, packet.Destination}].Accepted = s.Time
	snapshot.Markers++
	if snapshot.Markers == len(s.Network.Order) {
		snapshot.Completed = s.Time
	}
}
func (s *Simulation) deliver(c *Copy) {
	p := s.Processes[c.Destination]
	if c.Message.Kind == "BCAST" {
		p.B[c.Source]++
	}
	p.Balance += c.Message.Amount
	p.In += c.Message.Amount
	details := fmt.Sprintf("m%d from %s tag %s", c.Message.ID, s.Network.Names[c.Source], c.Message.Tag)
	if c.Message.Tag == "transfer" {
		details += fmt.Sprintf(" amount %d balance %d", c.Message.Amount, p.Balance)
	}
	c.Delivery = s.Time
	c.Received = s.event(p, "RECV", details, c.Message, c)
	p.Delivered = append(p.Delivered, c)
	for _, rule := range p.Rules {
		if rule.Tag == c.Message.Tag {
			s.action(p, rule.Action, c.Source)
		}
	}
}
func (s *Simulation) accept(packet *Packet) {
	p := s.Processes[packet.Destination]
	p.Next[packet.Source]++
	if packet.Copy == nil {
		s.marker(packet)
		return
	}
	c := packet.Copy
	for _, snapshot := range s.Snapshots {
		channel := snapshot.Channels[ChannelKey{c.Source, c.Destination}]
		if snapshot.Records[c.Destination] != nil && channel.Accepted < 0 {
			channel.State = append(channel.State, c)
		}
	}
	if s.Raw || c.Message.Kind == "P2P" {
		s.deliver(c)
		return
	}
	if !deliverable(c, p.B) {
		c.Causal = true
		c.Missing = missing(c, p.B)
		p.Hold = append(p.Hold, c)
		return
	}
	s.deliver(c)
	for {
		chosen := -1
		for i, c := range p.Hold {
			if deliverable(c, p.B) {
				chosen = i
				break
			}
		}
		if chosen < 0 {
			break
		}
		c := p.Hold[chosen]
		p.Hold = append(p.Hold[:chosen], p.Hold[chosen+1:]...)
		s.deliver(c)
	}
}
func (s *Simulation) arrival(packet *Packet) {
	p := s.Processes[packet.Destination]
	if s.Raw {
		s.accept(packet)
	} else if packet.Sequence != p.Next[packet.Source] {
		p.Buffers[packet.Source][packet.Sequence] = packet
		s.Network.Channels[ChannelKey{packet.Source, packet.Destination}].Buffered++
		if packet.Copy != nil {
			packet.Copy.FIFO = true
		}
	} else {
		s.accept(packet)
		for {
			next := p.Next[packet.Source]
			buffered := p.Buffers[packet.Source][next]
			if buffered == nil {
				break
			}
			delete(p.Buffers[packet.Source], next)
			s.accept(buffered)
		}
	}
	held := len(p.Hold)
	for _, buffer := range p.Buffers {
		held += len(buffer)
	}
	p.MaxHeld = max(p.MaxHeld, held)
}
func simulate(params Params, raw bool) *Simulation {
	network := readNetwork(params.Seed)
	programs := readPrograms(network)
	s := &Simulation{Network: network, SnapshotIndex: map[string]*Snapshot{}, Raw: raw}
	for i, program := range programs {
		s.Processes = append(s.Processes, newProcess(i, program, len(programs)))
		s.Initial += program.Initial
	}
	for p, program := range programs {
		for _, line := range program.Scheduled {
			for time := line.Time; time <= params.End; time += line.Period {
				action := line.Action
				s.schedule(&Item{Time: time, Process: p, Action: &action})
				if line.Period == 0 {
					break
				}
			}
		}
	}
	for s.Queue.Len() > 0 {
		item := heap.Pop(&s.Queue).(*Item)
		if item.Time > params.End {
			break
		}
		s.Time = item.Time
		if item.Action != nil {
			s.action(s.Processes[item.Process], *item.Action, -1)
		} else {
			s.arrival(item.Packet)
		}
	}
	return s
}
func eventName(s *Simulation, e *Event) string {
	return fmt.Sprintf("%s.%d", s.Network.Names[e.Process], e.Local)
}
func copyName(s *Simulation, c *Copy) string {
	return fmt.Sprintf("m%d->%s", c.Message.ID, s.Network.Names[c.Destination])
}
func names(s *Simulation, indices []int) string {
	a := []string{}
	for _, p := range indices {
		a = append(a, s.Network.Names[p])
	}
	return strings.Join(a, ",")
}
func yes(b bool) string {
	if b {
		return "yes"
	}
	return "no"
}
func ids(copies []*Copy, amount bool, empty string) string {
	if len(copies) == 0 {
		return empty
	}
	out := []string{}
	for _, c := range copies {
		v := fmt.Sprint("m", c.Message.ID)
		if amount && c.Message.Amount != 0 {
			v += fmt.Sprint(":", c.Message.Amount)
		}
		out = append(out, v)
	}
	return strings.Join(out, " ")
}
func writeLines(name string, lines []string) {
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	text := ""
	if len(lines) > 0 {
		text = strings.Join(lines, "\n") + "\n"
	}
	if e := os.WriteFile("output/"+name, []byte(text), 0644); e != nil {
		panic(e)
	}
}
func traceOutput(s *Simulation) {
	out := []string{}
	delivered := 0
	for _, c := range s.Copies {
		if c.Received != nil {
			delivered++
		}
	}
	for _, e := range s.Events {
		out = append(out, fmt.Sprintf("%d t=%d %s %s %s L=%d V=%s", e.Number, e.Time, eventName(s, e), e.Kind, e.Details, e.L, vectorText(e.V)))
	}
	out = append(out, fmt.Sprintf("SUMMARY events %d messages %d copies %d delivered %d undelivered %d draws %d",
		len(s.Events), len(s.Messages), len(s.Copies), delivered, len(s.Copies)-delivered, s.Network.Draws))
	for p, state := range s.Processes {
		out = append(out, fmt.Sprintf("FINAL %s events %d L=%d V=%s B=%s balance %d in %d out %d refused %d min %d",
			s.Network.Names[p], len(state.Events), state.L, vectorText(state.V), vectorText(state.B),
			state.Balance, state.In, state.Out, state.Refused, state.Minimum))
	}
	for p, state := range s.Processes {
		out = append(out, fmt.Sprintf("COUNTS %s local %d nofunds %d send %d bcast %d recv %d", s.Network.Names[p],
			state.Counts["LOCAL"], state.Counts["NOFUNDS"], state.Counts["SEND"], state.Counts["BCAST"],
			state.Counts["RECV"]))
	}
	writeLines("trace.txt", out)
}
func deliveryOutput(s *Simulation, end int) {
	out := []string{}
	broadcastLists := make([][]int, len(s.Processes))
	for p, state := range s.Processes {
		out = append(out, "PROCESS "+s.Network.Names[p])
		counts := [4]int{}
		totalWait, maxWait := 0, 0
		for rank, c := range state.Delivered {
			mode, index := "direct", 0
			if c.FIFO && c.Causal {
				mode, index = "fifo+causal "+names(s, c.Missing), 3
			} else if c.FIFO {
				mode, index = "fifo", 1
			} else if c.Causal {
				mode, index = "causal "+names(s, c.Missing), 2
			}
			counts[index]++
			wait := c.Delivery - c.Arrival
			totalWait += wait
			maxWait = max(maxWait, wait)
			out = append(out, fmt.Sprintf("%d m%d from %s %s tag %s sent %d arrived %d delivered %d wait %d %s",
				rank+1, c.Message.ID, s.Network.Names[c.Source], c.Message.Kind, c.Message.Tag, c.Message.Event.Time,
				c.Arrival, c.Delivery, wait, mode))
		}
		for _, c := range s.Copies {
			if c.Destination != p || c.Received != nil || c.Arrival > end {
				continue
			}
			place := "fifo"
			if c.Causal {
				place = "causal " + names(s, c.Missing)
			}
			out = append(out, fmt.Sprintf("HELD m%d from %s %s tag %s sent %d arrived %d %s", c.Message.ID,
				s.Network.Names[c.Source], c.Message.Kind, c.Message.Tag, c.Message.Event.Time, c.Arrival,
				place))
		}
		for _, c := range s.Copies {
			if c.Destination == p && c.Arrival > end {
				out = append(out, fmt.Sprintf("TRANSIT m%d from %s %s tag %s sent %d arrival %d", c.Message.ID,
					s.Network.Names[c.Source], c.Message.Kind, c.Message.Tag, c.Message.Event.Time,
					c.Arrival))
			}
		}
		out = append(out, fmt.Sprintf("TOTAL delivered %d direct %d fifo %d causal %d both %d wait %d max_wait %d max_held %d",
			len(state.Delivered), counts[0], counts[1], counts[2], counts[3], totalWait, maxWait,
			state.MaxHeld))
		bl := []string{}
		for _, e := range state.Events {
			if e.Message != nil && e.Message.Kind == "BCAST" {
				broadcastLists[p] = append(broadcastLists[p], e.Message.ID)
				bl = append(bl, fmt.Sprint("m", e.Message.ID))
			}
		}
		if len(bl) == 0 {
			bl = append(bl, "none")
		}
		out = append(out, "BCASTS "+strings.Join(bl, " "))
	}
	for _, key := range s.Network.Order {
		c := s.Network.Channels[key]
		delay := fmt.Sprint(c.A)
		if c.A != c.B {
			delay += fmt.Sprint("-", c.B)
		}
		out = append(out, fmt.Sprintf("CHANNEL %s->%s %s %s messages %d markers %d buffered %d max_delay %d entries %d",
			s.Network.Names[key.Source], s.Network.Names[key.Destination], c.Kind, delay, c.Copies,
			c.Markers, c.Buffered, c.MaxDelay, c.Entries))
	}
	tags := map[string][4]int{}
	for _, c := range s.Copies {
		v := tags[c.Message.Tag]
		v[0]++
		if c.Received != nil {
			latency := c.Delivery - c.Message.Event.Time
			v[1]++
			v[2] += latency
			v[3] = max(v[3], latency)
		}
		tags[c.Message.Tag] = v
	}
	ordered := []string{}
	for tag := range tags {
		ordered = append(ordered, tag)
	}
	sort.Strings(ordered)
	for _, tag := range ordered {
		v := tags[tag]
		out = append(out, fmt.Sprintf("TAG %s copies %d delivered %d latency %d max %d", tag, v[0], v[1], v[2], v[3]))
	}
	broadcasts := []*Message{}
	for _, m := range s.Messages {
		if m.Kind != "BCAST" {
			continue
		}
		broadcasts = append(broadcasts, m)
		stable := "none"
		time, all := 0, true
		for _, c := range m.Copies {
			if c.Received == nil {
				all = false
			}
			time = max(time, c.Delivery)
		}
		if all {
			stable = fmt.Sprint(time)
		}
		out = append(out, fmt.Sprintf("STABLE m%d %s tag %s sent %d stable %s", m.ID, s.Network.Names[m.Source], m.Tag, m.Event.Time, stable))
	}
	disagreements := 0
	for i, b1 := range broadcasts {
		for _, b2 := range broadcasts[i+1:] {
			early, late := []int{}, []int{}
			for p, list := range broadcastLists {
				a, b := -1, -1
				for j, id := range list {
					if id == b1.ID {
						a = j
					}
					if id == b2.ID {
						b = j
					}
				}
				if a >= 0 && b >= 0 {
					if a < b {
						early = append(early, p)
					} else {
						late = append(late, p)
					}
				}
			}
			if len(early) > 0 && len(late) > 0 {
				disagreements++
				out = append(out, fmt.Sprintf("DISAGREE m%d m%d %s %s", b1.ID, b2.ID, names(s, early), names(s, late)))
			}
		}
	}
	out = append(out, fmt.Sprint("DISAGREEMENTS ", disagreements))
	writeLines("deliveries.txt", out)
}
func verdict(s *Simulation, cut CutResult) string {
	if len(cut.Orphans) == 0 {
		return "yes"
	}
	a := []string{"no"}
	for _, c := range cut.Orphans {
		a = append(a, copyName(s, c))
	}
	return strings.Join(a, " ")
}
func snapshotMoney(snapshot *Snapshot) (int, int) {
	balances, channels := 0, 0
	for _, r := range snapshot.Records {
		balances += r.Balance
	}
	for _, c := range snapshot.Channels {
		for _, copy := range c.State {
			channels += copy.Message.Amount
		}
	}
	return balances, channels
}
func snapshotOutput(s, raw *Simulation) {
	out := []string{}
	for _, snapshot := range s.Snapshots {
		out = append(out, fmt.Sprintf("SNAPSHOT %s started %d completed %d", snapshot.Name, snapshot.Start, snapshot.Completed))
		pendingCount, channelCount := 0, 0
		collection := map[*Copy]int{}
		for p, r := range snapshot.Records {
			out = append(out, fmt.Sprintf("RECORD %s t=%d %s balance %d L=%d V=%s pending %s", s.Network.Names[p],
				r.Time, r.Reason, r.Balance, r.L, vectorText(r.V), ids(r.Pending, false, "none")))
			pendingCount += len(r.Pending)
			for _, c := range r.Pending {
				collection[c]++
			}
		}
		for _, key := range s.Network.Order {
			channel := snapshot.Channels[key]
			channelCount += len(channel.State)
			for _, c := range channel.State {
				collection[c]++
			}
			out = append(out, fmt.Sprintf("CHANNEL %s->%s marker %d %d state %s", s.Network.Names[key.Source],
				s.Network.Names[key.Destination], channel.Dispatched, channel.Accepted, ids(channel.State,
					true, "empty")))
		}
		for _, v := range snapshot.Ignored {
			out = append(out, fmt.Sprintf("IGNORED %s t=%d", s.Network.Names[v[0]], v[1]))
		}
		cut := snapshotCut(snapshot)
		result := analyzeCut(s, cut)
		out = append(out, fmt.Sprintf("CUT %s consistent %s vector %s", vectorText(cut), verdict(s, result), yes(result.Vector)))
		match := channelCount+pendingCount == len(result.Transit)
		for _, c := range result.Transit {
			collection[c]--
		}
		for _, count := range collection {
			if count != 0 {
				match = false
			}
		}
		out = append(out, fmt.Sprintf("TRANSIT channels %d pending %d cut %d match %s", channelCount, pendingCount, len(result.Transit), yes(match)))
		balances, channels := snapshotMoney(snapshot)
		out = append(out, fmt.Sprintf("MONEY balances %d channels %d total %d initial %d conserved %s",
			balances, channels, balances+channels, s.Initial, yes(balances+channels == s.Initial)))
	}
	for _, snapshot := range raw.Snapshots {
		cut := snapshotCut(snapshot)
		result := analyzeCut(raw, cut)
		balances, channels := snapshotMoney(snapshot)
		money := balances + channels
		out = append(out, fmt.Sprintf("RAW %s completed %d cut %s consistent %s money %d conserved %s",
			snapshot.Name, snapshot.Completed, vectorText(cut), verdict(raw, result), money, yes(money == raw.Initial)))
	}
	writeLines("snapshots.txt", out)
}
func rangeText(s *Simulation, events []*Event) string {
	out := []string{}
	for i := 0; i < len(events); {
		j := i + 1
		for j < len(events) && events[j].Process == events[i].Process {
			j++
		}
		text := eventName(s, events[i])
		if j-i > 1 {
			text += fmt.Sprint("-", events[j-1].Local)
		}
		out = append(out, text)
		i = j
	}
	return strings.Join(out, " ")
}
func longestChain(s *Simulation) []*Event {
	if len(s.Events) == 0 {
		return nil
	}
	e := s.Events[0]
	for _, f := range s.Events[1:] {
		if f.L > e.L {
			e = f
		}
	}
	out := []*Event{e}
	for e.L > 1 {
		if e.Copy != nil && e.Copy.Message.Event.L == e.L-1 {
			e = e.Copy.Message.Event
		} else {
			e = s.Processes[e.Process].Events[e.Local-2]
		}
		out = append(out, e)
	}
	for i, j := 0, len(out)-1; i < j; i, j = i+1, j-1 {
		out[i], out[j] = out[j], out[i]
	}
	return out
}
func analysisOutput(s, raw *Simulation, params Params) {
	out := []string{}
	byName := map[string]*Event{}
	for _, e := range s.Events {
		byName[eventName(s, e)] = e
	}
	edges := graph(s)
	for _, pair := range params.Compares {
		a, b := byName[pair[0]], byName[pair[1]]
		rel := relation(a.V, b.V)
		gr := "||"
		route := path(edges, a.Number-1, b.Number-1)
		if route != nil {
			gr = "->"
		} else {
			route = path(edges, b.Number-1, a.Number-1)
			if route != nil {
				gr = "<-"
			}
		}
		out = append(out, fmt.Sprintf("COMPARE %s %s %s L=%d,%d graph %s agree %s", pair[0], rel, pair[1], a.L, b.L, gr, yes(rel == gr)))
		if route != nil {
			events := make([]*Event, len(route))
			messages := 0
			for i, index := range route {
				events[i] = s.Events[index]
				if i > 0 && events[i].Process != events[i-1].Process {
					messages++
				}
			}
			out = append(out, fmt.Sprintf("PATH length %d messages %d %s", len(route), messages, rangeText(s, events)))
		}
		for _, e := range []*Event{a, b} {
			future := make([]int, len(s.Processes))
			for p, state := range s.Processes {
				for _, f := range state.Events {
					if f.V[e.Process] < e.Local {
						future[p]++
					}
				}
			}
			out = append(out, fmt.Sprintf("WINDOW %s past %s future %s", eventName(s, e), vectorText(e.V), vectorText(future)))
		}
	}
	c := concurrency(s.Events)
	out = append(out, fmt.Sprintf("CONCURRENCY events %d pairs %d ordered %d concurrent %d same_lamport %d inversions %d",
		len(s.Events), c.Pairs, c.Ordered, c.Concurrent, c.SameLamport, c.Inversions))
	for p := range s.Processes {
		for q := p + 1; q < len(s.Processes); q++ {
			out = append(out, fmt.Sprintf("PAIR %s %s %d", s.Network.Names[p], s.Network.Names[q], c.Processes[[2]int{p, q}]))
		}
	}
	chain := longestChain(s)
	out = append(out, fmt.Sprintf("CHAIN length %d %s", len(chain), rangeText(s, chain)))
	raceCount := 0
	for p, state := range s.Processes {
		for _, pair := range races(state) {
			raceCount++
			a, b := pair[0], pair[1]
			out = append(out, fmt.Sprintf("RACE %s m%d %s m%d %s", s.Network.Names[p], a.Message.ID, s.Network.Names[a.Source], b.Message.ID, s.Network.Names[b.Source]))
		}
	}
	out = append(out, fmt.Sprint("RACES ", raceCount))
	violations, fifo := violations(s)
	for _, v := range violations {
		p := v[0]
		a, b := s.Processes[p].Delivered[v[1]], s.Processes[p].Delivered[v[2]]
		out = append(out, fmt.Sprintf("VIOLATION %s m%d %s overtook m%d %s", s.Network.Names[p], a.Message.ID,
			s.Network.Names[a.Source], b.Message.ID, s.Network.Names[b.Source]))
	}
	out = append(out, fmt.Sprintf("VIOLATIONS causal %d fifo %d", len(violations), fifo))
	rawViolations, rawFIFO := violationSummary(raw)
	rawDelivered := 0
	for _, p := range raw.Processes {
		rawDelivered += len(p.Delivered)
	}
	out = append(out, fmt.Sprintf("RAW events %d delivered %d causal %d fifo %d", len(raw.Events), rawDelivered, rawViolations, rawFIFO))
	for _, cut := range params.Cuts {
		result := analyzeCut(s, cut)
		status := "consistent"
		if len(result.Orphans) > 0 {
			orphans := []string{}
			for _, copy := range result.Orphans {
				orphans = append(orphans, copyName(s, copy))
			}
			status = "inconsistent orphans " + strings.Join(orphans, " ")
		}
		out = append(out, fmt.Sprintf("CUT %s %s transit %d money %d initial %d", vectorText(cut), status, len(result.Transit), result.Money, s.Initial))
	}
	enumerated := enumerate(s, params.CutTime)
	out = append(out, fmt.Sprintf("CUTCOUNT t=%d events %s product %d consistent %d", params.CutTime,
		vectorText(enumerated.Limits), enumerated.Product, enumerated.Consistent))
	levels := []string{"LEVELS"}
	for _, count := range enumerated.Levels {
		levels = append(levels, fmt.Sprint(count))
	}
	out = append(out, strings.Join(levels, " "))
	for _, threshold := range params.Predicates {
		count, definitely := enumerated.predicate(threshold)
		out = append(out, fmt.Sprintf("PREDICATE transit>=%d cuts %d possibly %s definitely %s", threshold, count, yes(count > 0), yes(definitely)))
	}
	writeLines("analysis.txt", out)
}
func violationSummary(s *Simulation) (int, int) { v, f := violations(s); return len(v), f }
func put(canvas *[]byte, position int, text string) {
	for len(*canvas) < position+len(text) {
		*canvas = append(*canvas, ' ')
	}
	copy((*canvas)[position:], []byte(text))
}
func diagramHeader(s *Simulation, kind string) string {
	canvas := []byte(strings.Repeat(" ", 6))
	put(&canvas, 4, kind)
	for p, name := range s.Network.Names {
		put(&canvas, 6+8*p, name)
	}
	return strings.TrimRight(string(canvas), " ")
}
func diagramLine(s *Simulation, display Display, lamport bool) string {
	n := len(s.Processes)
	canvas := []byte(strings.Repeat(" ", 6+8*(n-1)+1))
	for p := 0; p < n; p++ {
		canvas[6+8*p] = '|'
	}
	process, time := 0, 0
	if display.Event != nil {
		e := display.Event
		process, time = e.Process, e.Time
		if lamport {
			time = e.L
		}
		column := 6 + 8*process
		symbol := byte('*')
		switch e.Kind {
		case "NOFUNDS":
			symbol = 'x'
		case "SEND":
			symbol = 'S'
		case "BCAST":
			symbol = 'B'
		case "RECV":
			symbol = 'R'
		}
		canvas[column] = symbol
		if e.Kind == "SEND" || e.Kind == "BCAST" {
			put(&canvas, column+1, fmt.Sprint("m", e.Message.ID))
		}
		if e.Kind == "RECV" {
			source := 6 + 8*e.Copy.Source
			a, z := min(source, column), max(source, column)
			for pos := a + 1; pos < z; pos++ {
				if (pos-6)%8 == 0 {
					canvas[pos] = '+'
				} else {
					canvas[pos] = '-'
				}
			}
			if source < column {
				canvas[z-1] = '>'
			} else {
				canvas[a+1] = '<'
			}
			put(&canvas, a+2, fmt.Sprint("m", e.Message.ID))
		}
	} else {
		process, time = display.Record.Process, display.Record.Time
		column := 6 + 8*process
		canvas[column] = '#'
		put(&canvas, column+1, display.Snapshot)
	}
	put(&canvas, 0, fmt.Sprintf("%5d", time))
	return strings.TrimRight(string(canvas), " ")
}
func diagramOutput(s *Simulation) {
	out := []string{diagramHeader(s, "t")}
	for _, d := range s.Display {
		out = append(out, diagramLine(s, d, false))
	}
	out = append(out, diagramHeader(s, "L"))
	events := append([]*Event(nil), s.Events...)
	sort.Slice(events, func(i, j int) bool {
		if events[i].L != events[j].L {
			return events[i].L < events[j].L
		}
		return events[i].Process < events[j].Process
	})
	for _, e := range events {
		out = append(out, diagramLine(s, Display{Event: e}, true))
	}
	writeLines("diagram.txt", out)
}
func main() {
	params := readParams()
	mainRun, raw := simulate(params, false), simulate(params, true)
	traceOutput(mainRun)
	deliveryOutput(mainRun, params.End)
	snapshotOutput(mainRun, raw)
	analysisOutput(mainRun, raw, params)
	diagramOutput(mainRun)
}
