package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

type prefix struct {
	address uint32
	length  int
}

func decimal(s string) bool {
	if s == "" || len(s) > 1 && s[0] == '0' {
		return false
	}
	for _, c := range s {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

func number(s string) int {
	n, _ := strconv.Atoi(s)
	return n
}

func parseAddress(s string) (uint32, bool) {
	parts := strings.Split(s, ".")
	if len(parts) != 4 {
		return 0, false
	}
	var a uint32
	for _, p := range parts {
		if len(p) > 3 || !decimal(p) || number(p) > 255 {
			return 0, false
		}
		a = a*256 + uint32(number(p))
	}
	return a, true
}

func address(a uint32) string {
	return fmt.Sprintf("%d.%d.%d.%d", a>>24, (a>>16)&255, (a>>8)&255, a&255)
}

func parsePrefix(s string) (prefix, bool) {
	parts := strings.Split(s, "/")
	if len(parts) != 2 || len(parts[1]) > 2 || !decimal(parts[1]) || number(parts[1]) > 32 {
		return prefix{}, false
	}
	a, ok := parseAddress(parts[0])
	return prefix{a, number(parts[1])}, ok
}

func network(a uint32, length int) uint32 {
	if length == 0 {
		return 0
	}
	return a & (^uint32(0) << uint(32-length))
}

func (p prefix) contains(a uint32) bool {
	return network(a, p.length) == network(p.address, p.length)
}

func (p prefix) String() string {
	return fmt.Sprintf("%s/%d", address(p.address), p.length)
}

func checkedAddress(s string) (uint32, error) {
	a, ok := parseAddress(s)
	if !ok {
		return 0, fmt.Errorf("bad address %s", s)
	}
	return a, nil
}

func checkedPrefix(s string) (prefix, error) {
	p, ok := parsePrefix(s)
	if !ok {
		return p, fmt.Errorf("bad prefix %s", s)
	}
	if network(p.address, p.length) != p.address {
		return p, fmt.Errorf("host bits set in %s", s)
	}
	return p, nil
}

type portRange struct {
	lo, hi int
	any    bool
}

func parsePorts(s string) (portRange, error) {
	if s == "ANY" {
		return portRange{0, 65535, true}, nil
	}
	parts := strings.Split(s, "-")
	lo, hi := number(parts[0]), number(parts[len(parts)-1])
	if lo > 65535 || hi > 65535 || lo > hi {
		return portRange{}, fmt.Errorf("bad port range %s", s)
	}
	return portRange{lo, hi, false}, nil
}

func (p portRange) String() string {
	if p.any {
		return "any"
	}
	if p.lo == p.hi {
		return strconv.Itoa(p.lo)
	}
	return fmt.Sprintf("%d-%d", p.lo, p.hi)
}

type rule struct {
	seq            int
	action, proto  string
	src, dst       prefix
	sports, dports portRange
	established    bool
	hits           int
}

type pat struct {
	proto                 string
	inside                uint32
	inport, outport, last int
}

type iface struct {
	name         string
	p            prefix
	up, outside  bool
	pool         int
	rpf          string
	rx, tx, drop int
	rules        [2][]*rule
	defaults     [2]int
	mappings     []*pat
}

type route struct {
	kind         string
	p            prefix
	out          *iface
	hop          *uint32
	metric, hits int
}

func (r *route) String() string {
	via := ""
	if r.hop != nil {
		via = " via " + address(*r.hop)
	}
	return fmt.Sprintf("%s %s%s dev %s metric %d", r.kind, r.p, via, r.out.name, r.metric)
}

type staticNAT struct {
	inside, outside uint32
}

type forward struct {
	out    *iface
	proto  string
	port   int
	inside uint32
	inport int
}

type tuple struct {
	proto string
	src   uint32
	sport int
	dst   uint32
	dport int
}

type connection struct {
	number                      int
	orig, reply                 tuple
	in, out                     *iface
	state                       string
	origCount, replyCount, last int
	fin                         [2]bool
}

var reasons = []string{"down", "martian", "rpf", "invalid", "acl_in", "ttl", "noroute", "acl_out", "exhausted"}

type router struct {
	ifaces                                              []*iface
	byName                                              map[string]*iface
	routes                                              []*route
	statics                                             []staticNAT
	forwards                                            []*forward
	conns                                               []*connection
	timeouts                                            map[string]int
	clock, packet, connNumber, forwarded, local, errors int
	drops                                               map[string]int
}

func newRouter() *router {
	return &router{byName: map[string]*iface{}, timeouts: map[string]int{"TCP": 300, "UDP": 60, "ICMP": 30}, drops: map[string]int{}}
}

func (r *router) interfaceNamed(name string) (*iface, error) {
	i, ok := r.byName[name]
	if !ok {
		return nil, fmt.Errorf("no interface %s", name)
	}
	return i, nil
}

func (r *router) localAddress(a uint32) *iface {
	for _, i := range r.ifaces {
		if i.p.address == a {
			return i
		}
	}
	return nil
}

func (r *router) selectRoute(a uint32) *route {
	var best *route
	for _, v := range r.routes {
		if v.out.up && v.p.contains(a) && (best == nil || v.p.length > best.p.length || v.p.length == best.p.length && v.metric < best.metric) {
			best = v
		}
	}
	return best
}

func (r *router) sortedIfaces() []*iface {
	out := append([]*iface{}, r.ifaces...)
	sort.Slice(out, func(i, j int) bool {
		return out[i].name < out[j].name
	})
	return out
}

func direction(s string) int {
	if s == "IN" {
		return 0
	}
	return 1
}

func (r *router) acl(i *iface, d int, t tuple, existing bool) string {
	if len(i.rules[d]) == 0 {
		return ""
	}
	for _, a := range i.rules[d] {
		if a.proto != "ANY" && a.proto != t.proto || !a.src.contains(t.src) || !a.dst.contains(t.dst) || a.established && !existing {
			continue
		}
		if (a.proto == "TCP" || a.proto == "UDP") && (t.sport < a.sports.lo || t.sport > a.sports.hi || t.dport < a.dports.lo || t.dport > a.dports.hi) {
			continue
		}
		a.hits++
		if a.action == "PERMIT" {
			return ""
		}
		dir := []string{"in", "out"}[d]
		if a.action == "DENY" {
			return fmt.Sprintf("DROP acl %s %s %d", i.name, dir, a.seq)
		}
		reason := "icmp-prohibited"
		if t.proto == "TCP" {
			reason = "tcp-reset"
		}
		return fmt.Sprintf("REJECT acl %s %s %d %s", i.name, dir, a.seq, reason)
	}
	i.defaults[d]++
	return fmt.Sprintf("DROP acl %s %s default", i.name, []string{"in", "out"}[d])
}

func martian(a uint32) bool {
	return a>>24 == 0 || a>>24 == 127 || a>>29 == 7
}

func (r *router) packetVerdict(i *iface, t tuple, flags string, ttl int) (string, string) {
	drop := func(reason string) (string, string) {
		return "DROP " + reason, reason
	}
	if !i.up {
		return drop("down")
	}
	if martian(t.src) || martian(t.dst) || r.localAddress(t.src) != nil {
		return drop("martian")
	}
	if i.rpf != "off" {
		back := r.selectRoute(t.src)
		if back == nil || i.rpf == "strict" && back.out != i {
			return drop("rpf")
		}
	}
	pure := t.proto == "TCP" && flags == "S"
	var conn *connection
	way := "new"
	for n, c := range r.conns {
		if c.orig == t {
			conn = c
			way = "orig"
		} else if c.reply == t {
			conn = c
			way = "reply"
		}
		if conn != nil {
			if conn.state == "CLOSED" && pure {
				r.conns = append(r.conns[:n], r.conns[n+1:]...)
				conn = nil
				way = "new"
			}
			break
		}
	}
	if t.proto == "TCP" && conn == nil && !pure {
		return drop("invalid")
	}
	if verdict := r.acl(i, 0, t, conn != nil); verdict != "" {
		return verdict, "acl_in"
	}
	translated := t
	var used *pat
	if i.outside {
		matched := false
		for _, m := range r.statics {
			if m.outside == t.dst {
				translated.dst = m.inside
				matched = true
				break
			}
		}
		if !matched && t.dst == i.p.address {
			for _, f := range r.forwards {
				if f.out == i && f.proto == t.proto && f.port == t.dport {
					translated.dst = f.inside
					translated.dport = f.inport
					matched = true
					break
				}
			}
			if !matched {
				for _, m := range i.mappings {
					if m.proto == t.proto && m.outport == t.dport {
						translated.dst = m.inside
						translated.dport = m.inport
						used = m
						break
					}
				}
			}
		}
	}
	if local := r.localAddress(translated.dst); local != nil {
		return "LOCAL " + local.name, "local"
	}
	if ttl == 1 {
		return drop("ttl")
	}
	route := r.selectRoute(translated.dst)
	if route == nil {
		return drop("noroute")
	}
	o := route.out
	if verdict := r.acl(o, 1, translated, conn != nil); verdict != "" {
		return verdict, "acl_out"
	}
	if !i.outside && o.outside {
		matched := false
		for _, m := range r.statics {
			if m.inside == t.src {
				translated.src = m.outside
				matched = true
				break
			}
		}
		if !matched {
			for _, f := range r.forwards {
				if f.out == o && f.proto == t.proto && f.inside == t.src && f.inport == t.sport {
					translated.src = o.p.address
					translated.sport = f.port
					matched = true
					break
				}
			}
		}
		if !matched && o.pool > 0 {
			for _, m := range o.mappings {
				if m.proto == t.proto && m.inside == t.src && m.inport == t.sport {
					used = m
					break
				}
			}
			if used == nil {
				port := 20000
				for ; port < 20000+o.pool; port++ {
					busy := false
					for _, m := range o.mappings {
						if m.outport == port {
							busy = true
						}
					}
					for _, f := range r.forwards {
						if f.out == o && f.port == port {
							busy = true
						}
					}
					if !busy {
						break
					}
				}
				if port == 20000+o.pool {
					return drop("exhausted")
				}
				used = &pat{t.proto, t.src, t.sport, port, r.clock}
				o.mappings = append(o.mappings, used)
			}
			translated.src = o.p.address
			translated.sport = used.outport
		}
	}
	if used != nil {
		used.last = r.clock
	}
	if conn == nil {
		r.connNumber++
		state := "UNREPLIED"
		if t.proto == "TCP" {
			state = "SYN_SENT"
		}
		conn = &connection{number: r.connNumber, orig: t, reply: tuple{t.proto, translated.dst, translated.dport, translated.src, translated.sport}, in: i, out: o, state: state}
		r.conns = append(r.conns, conn)
		way = "new"
	}
	if way == "reply" {
		conn.replyCount++
	} else {
		conn.origCount++
	}
	conn.last = r.clock
	if t.proto != "TCP" {
		if way == "reply" {
			conn.state = "REPLIED"
		}
	} else if strings.Contains(flags, "R") {
		conn.state = "CLOSED"
	} else {
		if conn.state == "SYN_SENT" && way == "reply" && strings.Contains(flags, "S") && strings.Contains(flags, "A") {
			conn.state = "ESTABLISHED"
		}
		if strings.Contains(flags, "F") && (conn.state == "ESTABLISHED" || conn.state == "FIN_WAIT") {
			side := 0
			if way == "reply" {
				side = 1
			}
			conn.fin[side] = true
			if conn.fin[0] && conn.fin[1] {
				conn.state = "CLOSED"
			} else {
				conn.state = "FIN_WAIT"
			}
		}
	}
	o.tx++
	route.hits++
	via := "direct"
	if route.hop != nil {
		via = "via " + address(*route.hop)
	}
	v := fmt.Sprintf("FORWARD %s %s ttl=%d", o.name, via, ttl-1)
	if translated.dst != t.dst || translated.dport != t.dport {
		v += fmt.Sprintf(" dnat=%s:%d", address(translated.dst), translated.dport)
	}
	if translated.src != t.src || translated.sport != t.sport {
		v += fmt.Sprintf(" snat=%s:%d", address(translated.src), translated.sport)
	}
	v += fmt.Sprintf(" conn=%d %s", conn.number, way)
	return v, "forwarded"
}

func (r *router) expire() (int, int) {
	old := len(r.conns)
	kept := r.conns[:0]
	for _, c := range r.conns {
		timeout := r.timeouts[c.orig.proto]
		if c.orig.proto == "TCP" {
			if c.state == "SYN_SENT" || c.state == "FIN_WAIT" {
				timeout = 60
			} else if c.state == "CLOSED" {
				timeout = 10
			}
		}
		if r.clock-c.last < timeout {
			kept = append(kept, c)
		}
	}
	r.conns = kept
	removed := 0
	for _, i := range r.ifaces {
		ms := i.mappings[:0]
		for _, m := range i.mappings {
			if r.clock-m.last >= r.timeouts[m.proto] {
				removed++
			} else {
				ms = append(ms, m)
			}
		}
		i.mappings = ms
	}
	return old - len(kept), removed
}

func (r *router) show(what string) string {
	out := []string{}
	add := func(format string, args ...any) {
		out = append(out, fmt.Sprintf(format, args...))
	}
	is := r.sortedIfaces()
	switch what {
	case "IFACES":
		add("show ifaces count=%d", len(is))
		for _, i := range is {
			status, role := "down", "inside"
			if i.up {
				status = "up"
			}
			if i.outside {
				role = "outside"
			}
			s := fmt.Sprintf("%s %s %s %s rpf=%s", i.name, i.p, status, role, i.rpf)
			if i.pool > 0 {
				s += fmt.Sprintf(" pat=%d/%d", len(i.mappings), i.pool)
			}
			out = append(out, s)
		}
	case "ROUTES":
		rs := append([]*route{}, r.routes...)
		sort.SliceStable(rs, func(i, j int) bool {
			a, b := rs[i], rs[j]
			if a.p.address != b.p.address {
				return a.p.address < b.p.address
			}
			if a.p.length != b.p.length {
				return a.p.length < b.p.length
			}
			return a.metric < b.metric
		})
		add("show routes count=%d", len(rs))
		for _, v := range rs {
			s := fmt.Sprintf("%s hits=%d", v, v.hits)
			if !v.out.up {
				s += " inactive"
			}
			out = append(out, s)
		}
	case "ACL":
		count := 0
		for _, i := range is {
			count += len(i.rules[0]) + len(i.rules[1])
		}
		add("show acl count=%d", count)
		for _, i := range is {
			for d, rules := range i.rules {
				dir := []string{"in", "out"}[d]
				for _, a := range rules {
					src, dst := "any", "any"
					if a.src.length > 0 {
						src = a.src.String()
					}
					if a.dst.length > 0 {
						dst = a.dst.String()
					}
					est := ""
					if a.established {
						est = " established"
					}
					add("acl %s %s %d %s %s %s %s %s %s%s hits=%d", i.name, dir, a.seq, a.action, a.proto, src, a.sports, dst, a.dports, est, a.hits)
				}
				if len(rules) > 0 {
					add("acl %s %s default DENY hits=%d", i.name, dir, i.defaults[d])
				}
			}
		}
	case "NAT":
		count := 0
		for _, i := range is {
			count += len(i.mappings)
		}
		add("show nat static=%d forward=%d pat=%d", len(r.statics), len(r.forwards), count)
		ss := append([]staticNAT{}, r.statics...)
		sort.Slice(ss, func(i, j int) bool {
			return ss[i].inside < ss[j].inside
		})
		for _, s := range ss {
			add("static %s %s", address(s.inside), address(s.outside))
		}
		fs := append([]*forward{}, r.forwards...)
		sort.Slice(fs, func(i, j int) bool {
			a, b := fs[i], fs[j]
			if a.out.name != b.out.name {
				return a.out.name < b.out.name
			}
			if a.port != b.port {
				return a.port < b.port
			}
			return a.proto < b.proto
		})
		for _, f := range fs {
			add("forward %s %s %d %s:%d", f.out.name, f.proto, f.port, address(f.inside), f.inport)
		}
		for _, i := range is {
			ms := append([]*pat{}, i.mappings...)
			sort.Slice(ms, func(i, j int) bool {
				return ms[i].outport < ms[j].outport
			})
			for _, m := range ms {
				add("pat %s %d %s %s:%d idle=%d", i.name, m.outport, m.proto, address(m.inside), m.inport, r.clock-m.last)
			}
		}
	case "CONNS":
		add("show conns count=%d", len(r.conns))
		for _, c := range r.conns {
			a, b := c.orig, c.reply
			add("conn %d %s %s:%d > %s:%d reply %s:%d > %s:%d in=%s out=%s state=%s pkts=%d/%d idle=%d", c.number, a.proto, address(a.src), a.sport, address(a.dst), a.dport, address(b.src), b.sport, address(b.dst), b.dport, c.in.name, c.out.name, c.state, c.origCount, c.replyCount, r.clock-c.last)
		}
	case "COUNTERS":
		dropped := 0
		for _, n := range r.drops {
			dropped += n
		}
		add("show counters packets=%d forwarded=%d local=%d dropped=%d errors=%d", r.forwarded+r.local+dropped, r.forwarded, r.local, dropped, r.errors)
		s := "drops"
		for _, reason := range reasons {
			s += fmt.Sprintf(" %s=%d", reason, r.drops[reason])
		}
		out = append(out, s)
		for _, i := range is {
			add("iface %s rx=%d tx=%d drop=%d", i.name, i.rx, i.tx, i.drop)
		}
	}
	return strings.Join(out, "\n")
}

func (r *router) command(w []string) (string, error) {
	bad := func(format string, args ...any) (string, error) {
		return "", fmt.Errorf(format, args...)
	}
	cmd := w[0]
	switch cmd {
	case "IFACE":
		name := w[1]
		if r.byName[name] != nil {
			return bad("duplicate interface %s", name)
		}
		p, ok := parsePrefix(w[2])
		if !ok || p.length < 8 || p.length > 30 {
			return bad("bad prefix %s", w[2])
		}
		net := network(p.address, p.length)
		if p.address == net || p.address == net|(^uint32(0)>>uint(p.length)) {
			return bad("bad host address %s", w[2])
		}
		for _, i := range r.ifaces {
			k := p.length
			if i.p.length < k {
				k = i.p.length
			}
			if network(p.address, k) == network(i.p.address, k) {
				return bad("subnet overlaps %s", i.name)
			}
		}
		i := &iface{name: name, p: p, up: true, rpf: "off"}
		r.ifaces = append(r.ifaces, i)
		r.byName[name] = i
		r.routes = append(r.routes, &route{kind: "C", p: prefix{net, p.length}, out: i})
		return fmt.Sprintf("ok iface %s %s network %s/%d", name, w[2], address(net), p.length), nil
	case "UP", "DOWN":
		i, err := r.interfaceNamed(w[1])
		if err != nil {
			return "", err
		}
		status := strings.ToLower(cmd)
		if i.up == (cmd == "UP") {
			return bad("interface %s already %s", i.name, status)
		}
		i.up = cmd == "UP"
		return "ok " + status + " " + i.name, nil
	case "ROUTE":
		p, err := checkedPrefix(w[1])
		if err != nil {
			return "", err
		}
		var out *iface
		var hop *uint32
		if w[2] == "VIA" {
			a, e := checkedAddress(w[3])
			if e != nil {
				return "", e
			}
			hop = &a
		} else {
			out, err = r.interfaceNamed(w[3])
			if err != nil {
				return "", err
			}
		}
		metric := number(w[4])
		if metric < 1 || metric > 255 {
			return bad("bad metric %s", w[4])
		}
		if hop != nil {
			if r.localAddress(*hop) != nil {
				return bad("nexthop %s is local", w[3])
			}
			for _, i := range r.ifaces {
				if i.p.contains(*hop) {
					out = i
					break
				}
			}
			if out == nil {
				return bad("nexthop %s unreachable", w[3])
			}
		}
		for _, v := range r.routes {
			sameHop := v.hop == nil && hop == nil || v.hop != nil && hop != nil && *v.hop == *hop
			if v.kind == "S" && v.p == p && v.out == out && sameHop {
				return bad("duplicate route %s", w[1])
			}
		}
		v := &route{kind: "S", p: p, out: out, hop: hop, metric: metric}
		r.routes = append(r.routes, v)
		return "ok route " + v.String(), nil
	case "NOROUTE":
		p, err := checkedPrefix(w[1])
		if err != nil {
			return "", err
		}
		count := 0
		for _, v := range r.routes {
			if v.kind == "S" && v.p == p {
				count++
			}
		}
		if count == 0 {
			return bad("no static route %s", w[1])
		}
		kept := r.routes[:0]
		for _, v := range r.routes {
			if v.kind != "S" || v.p != p {
				kept = append(kept, v)
			}
		}
		r.routes = kept
		return fmt.Sprintf("ok noroute %s removed=%d", w[1], count), nil
	case "LOOKUP":
		a, err := checkedAddress(w[1])
		if err != nil {
			return "", err
		}
		v := r.selectRoute(a)
		s := "none"
		if v != nil {
			s = v.String()
		}
		return "lookup " + w[1] + " " + s, nil
	case "ACL":
		i, err := r.interfaceNamed(w[1])
		if err != nil {
			return "", err
		}
		seq := number(w[3])
		if seq < 1 || seq > 9999 {
			return bad("bad sequence %s", w[3])
		}
		read := func(s string) (prefix, error) {
			if s == "ANY" {
				return prefix{}, nil
			}
			return checkedPrefix(s)
		}
		src, err := read(w[6])
		if err != nil {
			return "", err
		}
		sports, err := parsePorts(w[7])
		if err != nil {
			return "", err
		}
		dst, err := read(w[8])
		if err != nil {
			return "", err
		}
		dports, err := parsePorts(w[9])
		if err != nil {
			return "", err
		}
		if (w[5] == "ICMP" || w[5] == "ANY") && (!sports.any || !dports.any) {
			return bad("ports not allowed for %s", w[5])
		}
		d := direction(w[2])
		for _, a := range i.rules[d] {
			if a.seq == seq {
				return bad("duplicate sequence %s", w[3])
			}
		}
		i.rules[d] = append(i.rules[d], &rule{seq: seq, action: w[4], proto: w[5], src: src, dst: dst, sports: sports, dports: dports, established: len(w) == 11})
		sort.Slice(i.rules[d], func(a, b int) bool {
			return i.rules[d][a].seq < i.rules[d][b].seq
		})
		return fmt.Sprintf("ok acl %s %s %s", i.name, strings.ToLower(w[2]), w[3]), nil
	case "NOACL":
		i, err := r.interfaceNamed(w[1])
		if err != nil {
			return "", err
		}
		d := direction(w[2])
		for n, a := range i.rules[d] {
			if a.seq == number(w[3]) {
				i.rules[d] = append(i.rules[d][:n], i.rules[d][n+1:]...)
				return fmt.Sprintf("ok noacl %s %s %s hits=%d", i.name, strings.ToLower(w[2]), w[3], a.hits), nil
			}
		}
		return bad("no rule %s on %s %s", w[3], i.name, strings.ToLower(w[2]))
	case "NAT":
		switch w[1] {
		case "STATIC":
			a, err := checkedAddress(w[2])
			if err != nil {
				return "", err
			}
			b, err := checkedAddress(w[3])
			if err != nil {
				return "", err
			}
			if r.localAddress(a) != nil {
				return bad("address %s is local", w[2])
			}
			if r.localAddress(b) != nil {
				return bad("address %s is local", w[3])
			}
			for _, m := range r.statics {
				if m.inside == a {
					return bad("duplicate static %s", w[2])
				}
			}
			for _, m := range r.statics {
				if m.outside == b {
					return bad("duplicate static %s", w[3])
				}
			}
			r.statics = append(r.statics, staticNAT{a, b})
			return "ok nat static " + w[2] + " " + w[3], nil
		case "OUTSIDE", "PAT", "FORWARD":
			i, err := r.interfaceNamed(w[2])
			if err != nil {
				return "", err
			}
			switch w[1] {
			case "OUTSIDE":
				if i.outside {
					return bad("interface %s already outside", i.name)
				}
				i.outside = true
				return "ok nat outside " + i.name, nil
			case "PAT":
				n := number(w[3])
				if n < 1 || n > 1000 {
					return bad("bad pool size %s", w[3])
				}
				if i.pool > 0 {
					return bad("pat already on %s", i.name)
				}
				i.pool = n
				i.outside = true
				return fmt.Sprintf("ok nat pat %s %s 20000-%d", i.name, address(i.p.address), 19999+n), nil
			case "FORWARD":
				port := number(w[4])
				if port < 1 || port > 65535 {
					return bad("bad port %s", w[4])
				}
				a, err := checkedAddress(w[5])
				if err != nil {
					return "", err
				}
				inport := number(w[6])
				if inport < 1 || inport > 65535 {
					return bad("bad port %s", w[6])
				}
				if !i.outside {
					return bad("interface %s not outside", i.name)
				}
				if r.localAddress(a) != nil {
					return bad("address %s is local", w[5])
				}
				for _, f := range r.forwards {
					if f.out == i && f.proto == w[3] && f.port == port {
						return bad("duplicate forward %s %s %s", i.name, w[3], w[4])
					}
				}
				r.forwards = append(r.forwards, &forward{i, w[3], port, a, inport})
				return fmt.Sprintf("ok nat forward %s %s %s %s:%s", i.name, w[3], w[4], w[5], w[6]), nil
			}
		}
	case "RPF":
		i, err := r.interfaceNamed(w[1])
		if err != nil {
			return "", err
		}
		i.rpf = strings.ToLower(w[2])
		return "ok rpf " + i.name + " " + i.rpf, nil
	case "TIMEOUT":
		n := number(w[2])
		if n < 1 || n > 86400 {
			return bad("bad timeout %s", w[2])
		}
		r.timeouts[w[1]] = n
		return "ok timeout " + w[1] + " " + w[2], nil
	case "TICK":
		n := number(w[1])
		if n < 1 || n > 86400 {
			return bad("bad tick %s", w[1])
		}
		r.clock += n
		c, m := r.expire()
		return fmt.Sprintf("ok tick time=%d expired conns=%d nat=%d", r.clock, c, m), nil
	case "PACKET":
		i, err := r.interfaceNamed(w[1])
		if err != nil {
			return "", err
		}
		proto, flags := w[2], w[3]
		if proto != "TCP" && flags != "-" {
			return bad("flags not allowed for %s", proto)
		}
		if proto == "TCP" && flags != "-" {
			seen := map[rune]bool{}
			for _, c := range flags {
				if !strings.ContainsRune("SAFR", c) || seen[c] {
					return bad("bad flags %s", flags)
				}
				seen[c] = true
			}
		}
		src, err := checkedAddress(w[4])
		if err != nil {
			return "", err
		}
		sp := number(w[5])
		if sp > 65535 {
			return bad("bad port %s", w[5])
		}
		dst, err := checkedAddress(w[6])
		if err != nil {
			return "", err
		}
		dp := number(w[7])
		if dp > 65535 {
			return bad("bad port %s", w[7])
		}
		ttl := number(w[8])
		if ttl < 1 || ttl > 255 {
			return bad("bad ttl %s", w[8])
		}
		r.packet++
		i.rx++
		v, reason := r.packetVerdict(i, tuple{proto, src, sp, dst, dp}, flags, ttl)
		switch reason {
		case "forwarded":
			r.forwarded++
		case "local":
			r.local++
		default:
			r.drops[reason]++
			i.drop++
		}
		return fmt.Sprintf("#%d %s %s %s:%s > %s:%s %s", r.packet, proto, flags, w[4], w[5], w[6], w[7], v), nil
	case "SHOW":
		return r.show(w[1]), nil
	case "CLEAR":
		if w[1] == "CONNS" {
			c, m := len(r.conns), 0
			r.conns = nil
			for _, i := range r.ifaces {
				m += len(i.mappings)
				i.mappings = nil
			}
			return fmt.Sprintf("ok clear conns=%d nat=%d", c, m), nil
		}
		r.forwarded = 0
		r.local = 0
		r.errors = 0
		r.drops = map[string]int{}
		for _, i := range r.ifaces {
			i.rx = 0
			i.tx = 0
			i.drop = 0
			i.defaults = [2]int{}
			for _, rs := range i.rules {
				for _, a := range rs {
					a.hits = 0
				}
			}
		}
		for _, v := range r.routes {
			v.hits = 0
		}
		return "ok clear counters", nil
	}
	return "", nil
}

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Scan()
	n := number(scanner.Text())
	r := newRouter()
	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()
	for k := 0; k < n && scanner.Scan(); k++ {
		line, err := r.command(strings.Split(scanner.Text(), " "))
		if err != nil {
			r.errors++
			fmt.Fprintln(out, "error: "+err.Error())
		} else {
			fmt.Fprintln(out, line)
		}
	}
}
