package main

import (
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

type Election struct {
	time, node, term, won int
	trigger               string
	votes                 map[int]bool
}
type Leader struct {
	node, elected, ended, appended, commit int
	reason                                 string
	votes                                  map[int]bool
}
type Simulator struct {
	settings Settings
	nodes    []*Node
	network  *Network
	random   Generator
	checker  *Checker
	controls []Control
	requests []*Request
	time     int
	trace,
	electionsText, timelines []string
	elections []*Election
	leaders   map[int]*Leader
	leaderTicks, multiTicks,
	gapStart int
	gaps        [][2]int
	maximumTerm int
	reference   map[string]int
	replays     map[int]map[string]int
	statusCounts,
	keyRequests, keyCommitted map[string]int
	latencies []int
}

func nodeSet(set map[int]bool) string {
	a := make([]int, 0, len(set))
	for i := range set {
		a = append(a, i)
	}
	sort.Ints(a)
	b := make([]string,
		len(a))
	for j, i := range a {
		b[j] = fmt.Sprintf("n%d", i)
	}
	if len(a) == 0 {
		return "-"
	}
	return strings.Join(b,
		",")
}
func copySet(a map[int]bool) map[int]bool {
	b := map[int]bool{}
	for i, v := range a {
		b[i] = v
	}
	return b
}
func copyStore(a map[string]int) map[string]int {
	b := map[string]int{}
	for k, v := range a {
		b[k] = v
	}
	return b
}
func keys(a map[string]int) []string {
	out := make([]string, 0, len(a))
	for k := range a {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}
func line(out *[]string, format string, a ...any) { *out = append(*out, fmt.Sprintf(format, a...)) }
func (s *Simulator) node(i int) *Node             { return s.nodes[i-1] }
func (s *Simulator) majority(n int) bool          { return 2*n > s.settings.n }
func (s *Simulator) traceLine(format string, a ...any) {
	s.trace = append(s.trace, strconv.Itoa(s.time)+" "+fmt.Sprintf(format, a...))
}
func (s *Simulator) timer(n *Node) {
	n.deadline = s.time + s.random.Between(s.settings.emin, s.settings.emax)
}
func (s *Simulator) send(n *Node, destination int, m Message) {
	m.source = n.id
	m.destination = destination
	m.term = n.term
	s.network.send(s.time, m)
}
func (s *Simulator) appendTo(n *Node, d int) {
	prev := n.next[d] - 1
	entries := append([]Entry(nil), n.log[prev:min(prev+s.settings.b,
		len(n.log))]...)
	s.send(n, d, Message{kind: "AE", previous: prev, previousTerm: n.termAt(prev), entries: entries,
		commit: n.commit})
}
func (s *Simulator) broadcast(n *Node) {
	for _, other := range s.nodes {
		if other.id != n.id {
			s.appendTo(n, other.id)
		}
	}
}
func (s *Simulator) endLeader(n *Node, reason string) {
	r := s.leaders[n.term]
	r.ended = s.time
	r.reason = reason
	r.commit = n.commit
	n.cancelTransfer()
}
func (s *Simulator) control(e Control) {
	switch e.kind {
	case "CRASH":
		n := s.node(number(e.args[0]))
		s.traceLine("CRASH n%d %s term %d",
			n.id, n.role, n.term)
		if n.role == "LEADER" {
			s.endLeader(n, "CRASH")
		}
		n.up = false
		n.reset(s.settings.n)
	case "RESTART":
		n := s.node(number(e.args[0]))
		n.up = true
		s.timer(n)
		s.traceLine("RESTART n%d term %d length %d deadline %d", n.id, n.term, len(n.log), n.deadline)
	case "HEAL":
		clear(s.network.groups)
		s.traceLine("HEAL")
	case "PARTITION":
		groups := parseGroups(e.args)
		names := make([]string, len(groups))
		for i, g := range groups {
			set := map[int]bool{}
			for _, id := range g {
				s.network.groups[id] = i
				set[id] = true
			}
			names[i] = nodeSet(set)
		}
		s.traceLine("PARTITION %s",
			strings.Join(names, " "))
	case "TRANSFER":
		s.transfer(s.node(number(e.args[0])), number(e.args[1]))
	}
}
func (s *Simulator) attempt(r *Request) {
	r.attempts++
	destination := r.destination
	redirected := 0
	reason := ""
	var n *Node
	for {
		n = s.node(destination)
		if !n.up {
			reason = "down"
			break
		}
		if n.role == "LEADER" {
			if n.target != 0 {
				reason = "transfer"
				break
			}
			n.log = append(n.log,
				Entry{n.term, r.command, r.number})
			s.leaders[n.term].appended++
			r.index = len(n.log)
			r.term = n.term
			r.scheduled = -1
			s.traceLine("ACCEPT r%d n%d index %d term %d",
				r.number, n.id, r.index, r.term)
			return
		}
		if n.known == 0 || redirected >= s.settings.n-1 {
			reason = "noleader"
			break
		}
		destination = n.known
		s.traceLine("REDIRECT r%d n%d n%d",
			r.number, n.id, destination)
		redirected++
		r.redirects++
	}
	if r.attempts < s.settings.attempts {
		r.destination = n.id%s.settings.n + 1
		r.scheduled = s.time + s.settings.retry
		s.traceLine("REJECT r%d n%d %s retry n%d at %d",
			r.number, n.id, reason, r.destination, r.scheduled)
	} else {
		r.abandoned = true
		r.scheduled = -1
		s.traceLine("REJECT r%d n%d %s giveup",
			r.number, n.id, reason)
	}
}
func (s *Simulator) election(n *Node, trigger string) {
	n.term++
	n.role = "CANDIDATE"
	n.voted = n.id
	n.votes = map[int]bool{n.id: true}
	n.known = 0
	s.timer(n)
	n.stats.elections++
	n.election = len(s.elections)
	s.elections = append(s.elections,
		&Election{time: s.time, node: n.id, term: n.term, won: -1, trigger: trigger, votes: n.votes})
	s.traceLine("ELECTION n%d term %d last %d/%d deadline %d",
		n.id, n.term, len(n.log), n.lastTerm(), n.deadline)
	for _, other := range s.nodes {
		if other.id != n.id {
			s.send(n,
				other.id, Message{kind: "RV", last: len(n.log), lastTerm: n.lastTerm()})
		}
	}
}
func (s *Simulator) becomeLeader(n *Node) {
	n.role = "LEADER"
	n.known = n.id
	for _, other := range s.nodes {
		if other.id != n.id {
			n.next[other.id] = len(n.log) + 1
			n.match[other.id] = 0
		}
	}
	n.log = append(n.log,
		Entry{n.term, "NOOP", 0})
	n.stats.leaderTerms++
	s.elections[n.election].won = s.time
	s.checker.leader(n)
	s.leaders[n.term] = &Leader{node: n.id,
		elected: s.time, ended: -1, appended: 1, votes: copySet(n.votes)}
	s.traceLine("LEADER n%d term %d votes %s noop %d",
		n.id, n.term, nodeSet(n.votes), len(n.log))
	s.broadcast(n)
	n.heartbeat = s.time + s.settings.h
	n.quorum = s.time + s.settings.q
	n.heard = map[int]bool{}
}
func (s *Simulator) advance(n *Node, index int) {
	for i := n.commit + 1; i <= index; i++ {
		s.checker.commit(i,
			n.termAt(i), s.time)
	}
	n.commit = index
	first := n.applied + 1
	for i := first; i <= index; i++ {
		e := n.log[i-1]
		result := applyCommand(n.store,
			e.command)
		n.stats.applies++
		s.checker.apply(i, e, result)
	}
	n.applied = index
	s.traceLine("APPLY n%d %d-%d",
		n.id, first, index)
}
func (s *Simulator) checkCommit(n *Node) {
	for i := len(n.log); i > n.commit; i-- {
		if n.termAt(i) != n.term {
			return
		}
		count := 1
		for _, other := range s.nodes {
			if other.id != n.id && n.match[other.id] >= i {
				count++
			}
		}
		if s.majority(count) {
			s.traceLine("COMMIT n%d %d-%d term %d",
				n.id, n.commit+1, i, n.term)
			s.advance(n, i)
			return
		}
	}
}
func (s *Simulator) truncate(n *Node, first int) {
	removed := n.log[first-1:]
	n.stats.truncated += len(removed)
	s.checker.truncate(first,
		removed)
	s.traceLine("TRUNCATE n%d from %d removed %d", n.id, first, len(removed))
	n.log = n.log[:first-1]
}
func (s *Simulator) receive(m Message) {
	n := s.node(m.destination)
	if m.term > n.term {
		role := n.role
		s.traceLine("TERM n%d %d->%d %s n%d %s",
			n.id, n.term, m.term, m.kind, m.source, role)
		if role == "LEADER" {
			s.endLeader(n, "STEPDOWN")
		}
		n.term = m.term
		n.voted = 0
		n.known = 0
		n.role = "FOLLOWER"
		if role == "LEADER" {
			s.timer(n)
		}
	}
	switch m.kind {
	case "RV":
		reason := ""
		if m.term < n.term {
			reason = "term"
		} else if n.voted != 0 && n.voted != m.source {
			reason = "voted"
		} else if !n.accepts(m.last,
			m.lastTerm) {
			reason = "log"
		}
		if reason == "" {
			n.voted = m.source
			n.stats.votesGranted++
			s.timer(n)
			s.traceLine("VOTE n%d n%d term %d deadline %d",
				n.id, m.source, n.term, n.deadline)
		} else {
			s.traceLine("DENY n%d n%d term %d %s", n.id, m.source, n.term,
				reason)
		}
		s.send(n, m.source, Message{kind: "RVR", success: reason == ""})
	case "RVR":
		if n.role == "CANDIDATE" && m.term == n.term && m.success {
			n.votes[m.source] = true
			if s.majority(len(n.votes)) {
				s.becomeLeader(n)
			}
		}
	case "AE":
		if m.term < n.term {
			s.send(n, m.source, Message{kind: "AER"})
			return
		}
		if n.role == "CANDIDATE" {
			n.role = "FOLLOWER"
			s.traceLine("YIELD n%d term %d n%d",
				n.id, n.term, m.source)
		}
		n.known = m.source
		s.timer(n)
		if m.previous > len(n.log) || n.termAt(m.previous) != m.previousTerm {
			n.stats.aeFail++
			hint := m.previous - 1
			if m.previous > len(n.log) {
				hint = len(n.log)
			}
			s.send(n,
				m.source, Message{kind: "AER", m: hint})
			return
		}
		n.stats.aeOK++
		for j, e := range m.entries {
			k := m.previous + j + 1
			if k <= len(n.log) && n.termAt(k) != e.term {
				s.truncate(n,
					k)
			}
			if k > len(n.log) {
				n.log = append(n.log, e)
				n.stats.appended++
			}
		}
		confirmed := m.previous + len(m.entries)
		if c := min(m.commit,
			confirmed); c > n.commit {
			s.advance(n, c)
		}
		s.send(n, m.source, Message{kind: "AER", success: true, m: confirmed})
	case "AER":
		if n.role != "LEADER" || m.term != n.term {
			return
		}
		j := m.source
		n.heard[j] = true
		if m.success {
			n.match[j] = max(n.match[j],
				m.m)
			n.next[j] = max(n.next[j], m.m+1)
			s.checkCommit(n)
			if j == n.target && !n.transferSent && n.match[j] == len(n.log) {
				s.timeoutNow(n)
			} else if n.next[j] <= len(n.log) {
				s.appendTo(n,
					j)
			}
		} else {
			n.next[j] = max(n.match[j]+1, min(n.next[j]-1, m.m+1))
			s.traceLine("BACKTRACK n%d n%d next %d",
				n.id, j, n.next[j])
			s.appendTo(n, j)
		}
	case "TN":
		if m.term != n.term || n.role != "FOLLOWER" {
			s.traceLine("IGNORE n%d TN n%d term %d", n.id, m.source, m.term)
		} else {
			s.election(n, "transfer")
		}
	}
}
func (s *Simulator) timeoutNow(n *Node) {
	s.traceLine("TIMEOUTNOW n%d n%d term %d index %d", n.id, n.target,
		n.term, len(n.log))
	n.transferSent = true
	s.send(n, n.target, Message{kind: "TN"})
}
func (s *Simulator) transfer(n *Node, d int) {
	if !n.up || n.role != "LEADER" || n.target != 0 || n.id == d {
		s.traceLine("TRANSFER n%d n%d ignored",
			n.id, d)
		return
	}
	s.traceLine("TRANSFER n%d n%d start match %d/%d", n.id, d, n.match[d], len(n.log))
	n.target = d
	n.transferSent = false
	n.transferDeadline = s.time + s.settings.emin
	if n.match[d] == len(n.log) {
		s.timeoutNow(n)
	} else {
		s.appendTo(n,
			d)
	}
}
func (s *Simulator) timers(n *Node) {
	if n.role == "LEADER" {
		if n.quorum == s.time {
			if !s.majority(1 + len(n.heard)) {
				s.traceLine("STEPDOWN n%d term %d heard %s",
					n.id, n.term, nodeSet(n.heard))
				s.endLeader(n, "QUORUM")
				n.role = "FOLLOWER"
				n.known = 0
				s.timer(n)
				return
			}
			n.heard = map[int]bool{}
			n.quorum = s.time + s.settings.q
		}
		if n.target != 0 && n.transferDeadline == s.time {
			s.traceLine("TRANSFER n%d n%d abort",
				n.id, n.target)
			n.cancelTransfer()
		}
		if n.heartbeat == s.time {
			s.broadcast(n)
			n.heartbeat = s.time + s.settings.h
		}
	} else if n.deadline == s.time {
		s.election(n,
			"timeout")
	}
}
func (s *Simulator) endTick() {
	s.checker.checkLogs(s.nodes)
	count := 0
	for _, n := range s.nodes {
		if n.up && n.role == "LEADER" {
			count++
			n.stats.leaderTicks++
		}
	}
	if count > 0 {
		s.leaderTicks++
		if count >= 2 {
			s.multiTicks++
		}
		if s.gapStart >= 0 {
			s.gaps = append(s.gaps,
				[2]int{s.gapStart, s.time - 1})
			s.gapStart = -1
		}
	} else if s.gapStart < 0 {
		s.gapStart = s.time
	}
	if s.time%s.settings.sample == 0 {
		fields := make([]string,
			len(s.nodes))
		for i, n := range s.nodes {
			role := n.role[:1]
			if !n.up {
				role = "D"
			}
			fields[i] = role + strconv.Itoa(n.term)
		}
		s.timelines = append(s.timelines,
			fmt.Sprintf("TIMELINE %d %s", s.time, strings.Join(fields, " ")))
	}
}
func (s *Simulator) run() {
	for _, n := range s.nodes {
		s.timer(n)
		s.traceLine("START n%d deadline %d", n.id,
			n.deadline)
	}
	control := 0
	for t := 0; t <= s.settings.end; t++ {
		s.time = t
		for control < len(s.controls) && s.controls[control].time == t {
			s.control(s.controls[control])
			control++
		}
		for _, r := range s.requests {
			if r.scheduled == t {
				s.attempt(r)
			}
		}
		for _, m := range s.network.arrivals(t) {
			if s.network.deliver(m,
				s.node(m.destination).up) {
				s.receive(m)
			}
		}
		for _, n := range s.nodes {
			if n.up {
				s.timers(n)
			}
		}
		s.endTick()
	}
	if s.gapStart >= 0 {
		s.gaps = append(s.gaps,
			[2]int{s.gapStart, s.settings.end})
	}
	s.finish()
}
func (s *Simulator) finish() {
	s.reference = map[string]int{}
	s.replays = map[int]map[string]int{0: {}}
	for i := 1; i <= len(s.checker.applied); i++ {
		applyCommand(s.reference,
			s.checker.applied[i].entry.command)
		s.replays[i] = copyStore(s.reference)
	}
	s.statusCounts = map[string]int{}
	s.keyRequests = map[string]int{}
	s.keyCommitted = map[string]int{}
	for _, n := range s.nodes {
		s.maximumTerm = max(s.maximumTerm, n.term)
	}
	for _, r := range s.requests {
		key := strings.Fields(r.command)[1]
		s.keyRequests[key]++
		if r.index != 0 {
			if c,
				ok := s.checker.committed[r.index]; ok && c.term == r.term {
				r.status = "COMMITTED"
				r.latency = c.time - r.time
				r.result = s.checker.applied[r.index].result
				s.latencies = append(s.latencies,
					r.latency)
				s.keyCommitted[key]++
			} else {
				r.status = "LOST"
				for _, n := range s.nodes {
					if len(n.log) >= r.index && n.termAt(r.index) == r.term {
						r.status = "UNCOMMITTED"
						break
					}
				}
			}
		} else if r.abandoned {
			r.status = "FAILED"
		} else {
			r.status = "WAITING"
		}
		s.statusCounts[r.status]++
	}
}
func (s *Simulator) leaderLines() []string {
	var out []string
	byTerm := map[int][]*Election{}
	for _, e := range s.elections {
		byTerm[e.term] = append(byTerm[e.term], e)
		outcome := "LOST"
		if e.won >= 0 {
			outcome = fmt.Sprintf("WON %d",
				e.won)
		}
		line(&out, "ELECTION %d n%d term %d trigger %s votes %d %s", e.time, e.node, e.term, e.trigger,
			len(e.votes), outcome)
	}
	for term := 1; term <= s.maximumTerm; term++ {
		candidates := map[int]bool{}
		for _, e := range byTerm[term] {
			candidates[e.node] = true
		}
		r, ok := s.leaders[term]
		if !ok {
			line(&out, "TERM %d NONE candidates %s",
				term, nodeSet(candidates))
			continue
		}
		ended, reason, commit := "-", "ACTIVE", s.node(r.node).commit
		if r.ended >= 0 {
			ended = strconv.Itoa(r.ended)
			reason = r.reason
			commit = r.commit
		}
		start := byTerm[term][0].time
		line(&out,
			"TERM %d LEADER n%d elected %d votes %s ended %s %s appended %d commit %d candidates %s started %d wait %d",
			term, r.node, r.elected, nodeSet(r.votes), ended, reason, r.appended, commit, nodeSet(candidates), start,
			r.elected-start)
	}
	for _, n := range s.nodes {
		a := n.stats
		line(&out, "NODE n%d elections %d leader_terms %d leader_ticks %d votes_granted %d",
			n.id, a.elections, a.leaderTerms, a.leaderTicks, a.votesGranted)
	}
	out = append(out, s.timelines...)
	longest := 0
	for _, g := range s.gaps {
		length := g[1] - g[0] + 1
		longest = max(longest, length)
		line(&out, "GAP %d-%d length %d",
			g[0], g[1], length)
	}
	line(&out, "SUMMARY terms %d leaders %d elections %d leader_ticks %d multi_ticks %d ticks %d gaps %d longest %d",
		s.maximumTerm, len(s.leaders), len(s.elections), s.leaderTicks, s.multiTicks, s.settings.end+1, len(s.gaps),
		longest)
	return out
}
func (s *Simulator) logLines() []string {
	var out []string
	prefix := len(s.nodes[0].log)
	for _, n := range s.nodes {
		status := n.role
		if !n.up {
			status = "DOWN"
		}
		voted := "-"
		if n.voted != 0 {
			voted = fmt.Sprintf("n%d",
				n.voted)
		}
		line(&out, "NODE n%d %s term %d voted %s commit %d applied %d length %d", n.id, status,
			n.term, voted, n.commit, n.applied, len(n.log))
		for j, e := range n.log {
			text := fmt.Sprintf("%d %d %s",
				j+1, e.term, e.command)
			if e.request != 0 {
				text += fmt.Sprintf(" r%d", e.request)
			}
			out = append(out, text)
		}
		prefix = min(prefix,
			len(n.log))
		for j := 0; j < prefix; j++ {
			if n.log[j] != s.nodes[0].log[j] {
				prefix = j
				break
			}
		}
	}
	c := len(s.checker.committed)
	line(&out,
		"AGREE prefix %d committed %d", prefix, c)
	for _, n := range s.nodes {
		common := 0
		for i := 1; i <= min(len(n.log),
			c); i++ {
			if n.termAt(i) != s.checker.committed[i].term {
				break
			}
			common = i
		}
		a := n.stats
		line(&out, "DIFF n%d common %d behind %d extra %d ae_ok %d ae_fail %d appended %d truncated %d applies %d",
			n.id, common, c-common, len(n.log)-common, a.aeOK, a.aeFail, a.appended, a.truncated, a.applies)
	}
	return out
}
func (s *Simulator) stateLines() []string {
	var out []string
	for _, n := range s.nodes {
		status := "UP"
		if !n.up {
			status = "DOWN"
		}
		replay := "match"
		ref := s.replays[n.applied]
		if len(ref) != len(n.store) {
			replay = "mismatch"
		}
		for key, value := range ref {
			if got, ok := n.store[key]; !ok || got != value {
				replay = "mismatch"
			}
		}
		line(&out, "NODE n%d %s applied %d keys %d replay %s",
			n.id, status, n.applied, len(n.store), replay)
		for _, key := range keys(n.store) {
			line(&out, "%s %d", key,
				n.store[key])
		}
	}
	for _, r := range s.requests {
		text := fmt.Sprintf("REQUEST r%d at %d n%d %s attempts %d redirects %d %s",
			r.number, r.time, r.initial, r.command, r.attempts, r.redirects, r.status)
		if r.index != 0 {
			text += fmt.Sprintf(" index %d term %d",
				r.index, r.term)
			if r.status == "COMMITTED" {
				text += fmt.Sprintf(" latency %d result %s", r.latency,
					r.result)
			}
		} else if r.status == "WAITING" {
			text += fmt.Sprintf(" next %d", r.scheduled)
		}
		out = append(out,
			text)
	}
	for _, key := range keys(s.keyRequests) {
		value := "missing"
		if v, ok := s.reference[key]; ok {
			value = strconv.Itoa(v)
		}
		line(&out,
			"KEY %s requests %d committed %d final %s", key, s.keyRequests[key], s.keyCommitted[key], value)
	}
	line(&out,
		"REQUESTS total %d committed %d uncommitted %d lost %d failed %d waiting %d", len(s.requests),
		s.statusCounts["COMMITTED"], s.statusCounts["UNCOMMITTED"], s.statusCounts["LOST"], s.statusCounts["FAILED"],
		s.statusCounts["WAITING"])
	sum, lo, hi := 0, 0, 0
	for i, v := range s.latencies {
		sum += v
		if i == 0 || v < lo {
			lo = v
		}
		hi = max(hi,
			v)
	}
	line(&out, "LATENCY count %d total %d min %d max %d", len(s.latencies), sum, lo, hi)
	return out
}
func (s *Simulator) safetyLines() []string {
	out := s.checker.lines(s.maximumTerm)
	line(&out, "MESSAGES %s",
		s.network.total.text())
	for _, kind := range messageTypes {
		line(&out, "TYPE %s %s", kind, s.network.byType[kind].text())
	}
	for a := 1; a <= s.settings.n; a++ {
		for b := 1; b <= s.settings.n; b++ {
			if a == b {
				continue
			}
			link := s.network.links[a][b]
			dropped := link.stats[3] + link.stats[4] + link.stats[5] + link.stats[6]
			line(&out,
				"LINK n%d->n%d delay %d loss %d sent %d delivered %d dropped %d", a, b, link.delay, link.loss, link.stats[0],
				link.stats[1], dropped)
		}
	}
	line(&out, "DRAWS %d", s.random.draws)
	result := "SAFE"
	for _, v := range s.checker.violations {
		if v != 0 {
			result = "UNSAFE"
		}
	}
	line(&out,
		"RESULT %s", result)
	return out
}
func main() {
	settings := readSettings()
	controls, requests := readScript()
	s := &Simulator{settings: settings,
		network: readNetwork(settings.n), random: Generator{state: int64(settings.seed)}, checker: newChecker(),
		controls: controls, requests: requests, leaders: map[int]*Leader{}, gapStart: -1}
	for i := 1; i <= settings.n; i++ {
		s.nodes = append(s.nodes,
			newNode(i, settings.n))
	}
	s.run()
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	reports := map[string][]string{"trace.txt": s.trace,
		"leaders.txt": s.leaderLines(), "logs.txt": s.logLines(), "state.txt": s.stateLines(), "safety.txt": s.safetyLines()}
	for name, lines := range reports {
		if err := os.WriteFile("output/"+name, []byte(strings.Join(lines, "\n")+"\n"),
			0644); err != nil {
			panic(err)
		}
	}
}
