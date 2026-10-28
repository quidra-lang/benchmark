package main

import "fmt"

var propertyNames = []string{"ELECTION_SAFETY", "LEADER_COMPLETENESS", "LOG_MATCHING", "STATE_MACHINE_SAFETY", "COMMITTED_KEPT"}

type CommitRecord struct{ term, time int }
type ApplyRecord struct {
	entry  Entry
	result string
}
type Checker struct {
	violations [5]int
	leaders    map[int]int
	committed  map[int]CommitRecord
	applied    map[int]ApplyRecord
	elected,
	logChecks, pairChecks, applies, truncations, removed int
}

func newChecker() *Checker {
	return &Checker{leaders: map[int]int{}, committed: map[int]CommitRecord{}, applied: map[int]ApplyRecord{}}
}
func (c *Checker) leader(n *Node) {
	c.elected++
	if old, ok := c.leaders[n.term]; !ok {
		c.leaders[n.term] = n.id
	} else if old != n.id {
		c.violations[0]++
	}
	for i, r := range c.committed {
		if i > len(n.log) || n.termAt(i) != r.term {
			c.violations[1]++
			break
		}
	}
}
func (c *Checker) commit(i, term, t int) {
	if _, ok := c.committed[i]; !ok {
		c.committed[i] = CommitRecord{term, t}
	}
}
func (c *Checker) apply(i int, e Entry, result string) {
	c.applies++
	if old, ok := c.applied[i]; !ok {
		c.applied[i] = ApplyRecord{e,
			result}
	} else if old.entry != e {
		c.violations[3]++
	}
}
func (c *Checker) truncate(first int, entries []Entry) {
	c.truncations++
	c.removed += len(entries)
	for j, e := range entries {
		if r, ok := c.committed[first+j]; ok && r.term == e.term {
			c.violations[4]++
		}
	}
}
func (c *Checker) checkLogs(nodes []*Node) {
	c.logChecks++
	for a, x := range nodes {
		for _, y := range nodes[a+1:] {
			c.pairChecks++
			limit := min(len(x.log),
				len(y.log))
			g := 0
			for k := limit; k >= 1; k-- {
				if x.termAt(k) == y.termAt(k) {
					g = k
					break
				}
			}
			for k := 0; k < g; k++ {
				if x.log[k] != y.log[k] {
					c.violations[2]++
					break
				}
			}
		}
	}
}
func (c *Checker) lines(k int) []string {
	details := []string{fmt.Sprintf("terms %d leaders %d elected %d",
		k, len(c.leaders), c.elected), fmt.Sprintf("checks %d committed %d", c.elected, len(c.committed)),
		fmt.Sprintf("checks %d pairs %d", c.logChecks, c.pairChecks), fmt.Sprintf("applies %d indices %d",
			c.applies, len(c.applied)), fmt.Sprintf("truncations %d removed %d", c.truncations, c.removed)}
	var out []string
	for i, name := range propertyNames {
		verdict := "OK"
		if c.violations[i] > 0 {
			verdict = "FAIL"
		}
		out = append(out, fmt.Sprintf("%s %s violations %d %s",
			name, verdict, c.violations[i], details[i]))
	}
	return out
}
