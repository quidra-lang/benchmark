package main

import "sort"

var marks = []string{"retransmission", "out_of_order", "lost_segment", "duplicate_ack"}

const sequenceModulus int64 = 1 << 32

type Endpoint struct{ Address, Port int64 }

func endpointLess(a, b Endpoint) bool {
	if a.Address != b.Address {
		return a.Address < b.Address
	}
	return a.Port < b.Port
}
func endpointPair(a, b Endpoint) [2]Endpoint {
	if endpointLess(b, a) {
		return [2]Endpoint{b, a}
	}
	return [2]Endpoint{a, b}
}

type PreviousAck struct {
	Ack, Window   int64
	Number, Count int
}
type Side struct {
	Name                                         string
	ISN, MSS, WScale, Base, Expected, AdvancedAt int64
	Intervals                                    map[[2]int64]bool
	PreviousAck                                  *PreviousAck
	Packets                                      int
	Payload                                      int64
	Marks                                        map[string]int
}

func newSide(name string) *Side {
	return &Side{Name: name, ISN: -1, MSS: -1, WScale: -1, Base: -1, Expected: -1, Intervals: map[[2]int64]bool{}, Marks: map[string]int{}}
}

type StateEntry struct {
	State  string
	Packet int
}
type StreamEvent struct {
	Packet      int
	Side, Mark  string
	Start, Size int64
}
type Stream struct {
	Number                    int
	Client, Server            Endpoint
	State                     string
	History                   []StateEntry
	Start, End                int64
	Packets, Bytes            int
	Syn, SynAck, HandshakeAck int
	Events                    []StreamEvent
	Closer                    *Side
	FinalAck                  int64
	ClientSide, ServerSide    *Side
}

func (s *Stream) ChangeState(state string, packet int) {
	s.State = state
	s.History = append(s.History, StateEntry{state, packet})
}
func (s *Stream) RecordSyn(side *Side, p *Packet) {
	side.ISN = p.Fields.Num("tcp.seq_raw")
	side.MSS, side.WScale = -1, -1
	if p.Fields.Exists("tcp.options.mss") {
		side.MSS = p.Fields.Num("tcp.options.mss")
	}
	if p.Fields.Exists("tcp.options.wscale") {
		side.WScale = p.Fields.Num("tcp.options.wscale")
	}
	if side == s.ClientSide {
		s.Syn = p.Number
	} else {
		s.SynAck = p.Number
	}
}

type StreamTracker struct {
	Streams       []*Stream
	Latest        map[[2]Endpoint]*Stream
	DuplicateAcks map[int][2]int
}

func newTracker() *StreamTracker {
	return &StreamTracker{Latest: map[[2]Endpoint]*Stream{}, DuplicateAcks: map[int][2]int{}}
}
func (t *StreamTracker) Track(p *Packet) {
	f := p.Fields
	source, destination := Endpoint{f.Num("ip.src"), f.Num("tcp.srcport")}, Endpoint{f.Num("ip.dst"), f.Num("tcp.dstport")}
	seq, ack := f.Num("tcp.seq_raw"), f.Num("tcp.ack_raw")
	syn, fin, rst, hasAck := f.Num("tcp.flags.syn") == 1, f.Num("tcp.flags.fin") == 1, f.Num("tcp.flags.rst") == 1, f.Num("tcp.flags.ack") == 1
	key := endpointPair(source, destination)
	stream := t.Latest[key]
	if stream == nil || (stream.State == "CLOSED" || stream.State == "RESET") && syn && !hasAck {
		stream = &Stream{Number: len(t.Streams), Client: source, Server: destination, State: "ESTABLISHED",
			Start: p.Time, End: p.Time, ClientSide: newSide("client"), ServerSide: newSide("server")}
		if syn && hasAck {
			stream.Client, stream.Server = destination, source
			stream.State = "SYN_RECEIVED"
			stream.RecordSyn(stream.ServerSide, p)
		} else if syn {
			stream.State = "SYN_SENT"
			stream.RecordSyn(stream.ClientSide, p)
		}
		stream.History = []StateEntry{{stream.State, p.Number}}
		t.Streams = append(t.Streams, stream)
		t.Latest[key] = stream
	}
	f.N("tcp.stream", int64(stream.Number))
	side, other := stream.ClientSide, stream.ServerSide
	if source != stream.Client {
		side, other = other, side
	}
	if side.Base < 0 {
		side.Base = seq
	}
	if hasAck && other.Base < 0 {
		other.Base = ack
	}
	relative := (seq - side.Base + sequenceModulus) % sequenceModulus
	f.N("tcp.seq", relative)
	if hasAck {
		f.N("tcp.ack", (ack-other.Base+sequenceModulus)%sequenceModulus)
	}
	size := f.Num("tcp.len") + f.Num("tcp.flags.syn") + f.Num("tcp.flags.fin")
	mark := ""
	if size > 0 {
		if side.Expected >= 0 && relative != side.Expected {
			if relative > side.Expected {
				mark = "lost_segment"
			} else if side.Intervals[[2]int64{relative, size}] {
				mark = "retransmission"
			} else if p.Time-side.AdvancedAt < 3000 {
				mark = "out_of_order"
			} else {
				mark = "retransmission"
			}
		}
		side.Intervals[[2]int64{relative, size}] = true
		if side.Expected < 0 || relative+size > side.Expected {
			side.Expected, side.AdvancedAt = relative+size, p.Time
		}
	} else if hasAck && !rst {
		previous := side.PreviousAck
		if previous != nil && ack == previous.Ack && f.Num("tcp.window") == previous.Window {
			mark = "duplicate_ack"
			previous.Count++
			t.DuplicateAcks[p.Number] = [2]int{previous.Number, previous.Count}
		}
	}
	if hasAck && mark != "duplicate_ack" {
		side.PreviousAck = &PreviousAck{Ack: ack, Window: f.Num("tcp.window"), Number: p.Number}
	}
	if mark != "" {
		f.N("tcp.analysis."+mark, 1)
		side.Marks[mark]++
		stream.Events = append(stream.Events, StreamEvent{p.Number, side.Name, mark, relative, size})
	}
	window := f.Num("tcp.window")
	if stream.ClientSide.WScale >= 0 && stream.ServerSide.WScale >= 0 && !syn {
		window *= 1 << uint(side.WScale)
	}
	f.N("tcp.window.calc", window)
	state := stream.State
	if rst {
		if state != "CLOSED" && state != "RESET" {
			stream.ChangeState("RESET", p.Number)
		}
	} else if state == "SYN_SENT" && syn && hasAck && side == stream.ServerSide && ack == (stream.ClientSide.ISN+1)%sequenceModulus {
		stream.ChangeState("SYN_RECEIVED", p.Number)
		stream.RecordSyn(stream.ServerSide, p)
	} else if state == "SYN_RECEIVED" && side == stream.ClientSide && hasAck && !syn && ack == (stream.ServerSide.ISN+1)%sequenceModulus {
		stream.ChangeState("ESTABLISHED", p.Number)
		stream.HandshakeAck = p.Number
	} else if state == "ESTABLISHED" && fin {
		stream.ChangeState("FIN_WAIT", p.Number)
		stream.Closer = side
	} else if state == "FIN_WAIT" && fin && side != stream.Closer {
		stream.ChangeState("CLOSING", p.Number)
		stream.FinalAck = (seq + f.Num("tcp.len") + 1) % sequenceModulus
	} else if state == "CLOSING" && side == stream.Closer && hasAck && ack == stream.FinalAck {
		stream.ChangeState("CLOSED", p.Number)
	}
	side.Packets++
	side.Payload += f.Num("tcp.len")
	stream.Packets++
	stream.Bytes += p.Length
	stream.End = p.Time
}

type Conversation struct {
	Kind                                   int
	A, B                                   Endpoint
	FirstNumber                            int
	FirstTime, LastTime                    int64
	PacketsAB, BytesAB, PacketsBA, BytesBA int
}

func (c *Conversation) Packets() int { return c.PacketsAB + c.PacketsBA }
func (c *Conversation) Bytes() int   { return c.BytesAB + c.BytesBA }

type ConversationKey struct {
	Kind, Stream int
	Pair         [2]Endpoint
}

func buildConversations(packets []*Packet) []*Conversation {
	conversations := []*Conversation{}
	table := map[ConversationKey]*Conversation{}
	for _, p := range packets {
		f := p.Fields
		if !f.Exists("ip.src") {
			continue
		}
		type View struct {
			Key                 ConversationKey
			Source, Destination Endpoint
		}
		source, destination := Endpoint{f.Num("ip.src"), -1}, Endpoint{f.Num("ip.dst"), -1}
		views := []View{{ConversationKey{Kind: 0, Pair: endpointPair(source, destination)}, source, destination}}
		if f.Exists("tcp.stream") {
			src, dst := Endpoint{source.Address, f.Num("tcp.srcport")}, Endpoint{destination.Address, f.Num("tcp.dstport")}
			views = append(views, View{ConversationKey{Kind: 1, Stream: int(f.Num("tcp.stream"))}, src, dst})
		}
		if f.Exists("udp.srcport") {
			src, dst := Endpoint{source.Address, f.Num("udp.srcport")}, Endpoint{destination.Address, f.Num("udp.dstport")}
			views = append(views, View{ConversationKey{Kind: 2, Pair: endpointPair(src, dst)}, src, dst})
		}
		for _, v := range views {
			c := table[v.Key]
			if c == nil {
				c = &Conversation{Kind: v.Key.Kind, A: v.Source, B: v.Destination, FirstNumber: p.Number, FirstTime: p.Time}
				table[v.Key] = c
				conversations = append(conversations, c)
			}
			if v.Source == c.A {
				c.PacketsAB++
				c.BytesAB += p.Length
			} else {
				c.PacketsBA++
				c.BytesBA += p.Length
			}
			c.LastTime = p.Time
		}
	}
	sort.Slice(conversations, func(i, j int) bool {
		a, b := conversations[i], conversations[j]
		if a.Bytes() != b.Bytes() {
			return a.Bytes() > b.Bytes()
		}
		if a.Packets() != b.Packets() {
			return a.Packets() > b.Packets()
		}
		if a.Kind != b.Kind {
			return a.Kind < b.Kind
		}
		return a.FirstNumber < b.FirstNumber
	})
	return conversations
}

type EndpointTotals struct {
	Address                                int64
	TxPackets, TxBytes, RxPackets, RxBytes int
}

func (e *EndpointTotals) Packets() int { return e.TxPackets + e.RxPackets }
func (e *EndpointTotals) Bytes() int   { return e.TxBytes + e.RxBytes }
func buildEndpoints(packets []*Packet) []*EndpointTotals {
	table := map[int64]*EndpointTotals{}
	for _, p := range packets {
		if !p.Fields.Exists("ip.src") {
			continue
		}
		source, destination := p.Fields.Num("ip.src"), p.Fields.Num("ip.dst")
		for _, address := range []int64{source, destination} {
			if table[address] == nil {
				table[address] = &EndpointTotals{Address: address}
			}
		}
		sender, receiver := table[source], table[destination]
		sender.TxPackets++
		sender.TxBytes += p.Length
		receiver.RxPackets++
		receiver.RxBytes += p.Length
	}
	endpoints := []*EndpointTotals{}
	for _, e := range table {
		endpoints = append(endpoints, e)
	}
	sort.Slice(endpoints, func(i, j int) bool {
		a, b := endpoints[i], endpoints[j]
		if a.Bytes() != b.Bytes() {
			return a.Bytes() > b.Bytes()
		}
		if a.Packets() != b.Packets() {
			return a.Packets() > b.Packets()
		}
		return a.Address < b.Address
	})
	return endpoints
}
