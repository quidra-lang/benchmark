package main

import (
	"strconv"
	"strings"
)

type Entry struct {
	term    int
	command string
	request int
}
type NodeStats struct{ elections, leaderTerms, votesGranted, leaderTicks, aeOK, aeFail, appended, truncated, applies int }
type Node struct {
	id, term, voted int
	log             []Entry
	up              bool
	stats           NodeStats
	role            string
	commit, applied,
	known, deadline, election int
	store        map[string]int
	votes, heard map[int]bool
	next, match  []int
	heartbeat,
	quorum, target, transferDeadline int
	transferSent bool
}

func newNode(id, n int) *Node { node := &Node{id: id, up: true}; node.reset(n); return node }
func (n *Node) reset(count int) {
	n.role = "FOLLOWER"
	n.commit = 0
	n.applied = 0
	n.known = 0
	n.deadline = -1
	n.election = -1
	n.store = map[string]int{}
	n.votes = map[int]bool{}
	n.heard = map[int]bool{}
	n.next = make([]int,
		count+1)
	n.match = make([]int, count+1)
	n.heartbeat = -1
	n.quorum = -1
	n.cancelTransfer()
}
func (n *Node) cancelTransfer() { n.target = 0; n.transferSent = false; n.transferDeadline = -1 }
func (n *Node) termAt(i int) int {
	if i == 0 {
		return 0
	}
	return n.log[i-1].term
}
func (n *Node) lastTerm() int { return n.termAt(len(n.log)) }
func (n *Node) accepts(i, t int) bool {
	return t > n.lastTerm() || t == n.lastTerm() && i >= len(n.log)
}
func applyCommand(store map[string]int, command string) string {
	a := strings.Fields(command)
	if a[0] == "NOOP" {
		return ""
	}
	key := a[1]
	switch a[0] {
	case "SET":
		store[key] = number(a[2])
		return "ok"
	case "ADD":
		store[key] += number(a[2])
		return strconv.Itoa(store[key])
	case "DEL":
		if _,
			ok := store[key]; ok {
			delete(store, key)
			return "deleted"
		}
		return "missing"
	default:
		if v, ok := store[key]; ok {
			return strconv.Itoa(v)
		}
		return "missing"
	}
}
