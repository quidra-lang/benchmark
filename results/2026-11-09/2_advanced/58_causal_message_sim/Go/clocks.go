package main

import (
	"fmt"
	"strings"
)

func tick(p *Process, sent *Event) {
	if sent == nil {
		p.L++
	} else {
		p.L = max(p.L, sent.L) + 1
		for i, x := range sent.V {
			p.V[i] = max(p.V[i], x)
		}
	}
	p.V[p.Index]++
}
func lessEqual(a, b []int) bool {
	for i, v := range a {
		if v > b[i] {
			return false
		}
	}
	return true
}
func relation(a, b []int) string {
	less, greater := false, false
	for i, v := range a {
		if v < b[i] {
			less = true
		}
		if v > b[i] {
			greater = true
		}
	}
	if less && !greater {
		return "->"
	}
	if greater && !less {
		return "<-"
	}
	return "||"
}
func deliverable(c *Copy, b []int) bool {
	s, source := c.Message.Stamp, c.Source
	for k, v := range s {
		if k == source {
			if v != b[k]+1 {
				return false
			}
		} else if v > b[k] {
			return false
		}
	}
	return true
}
func missing(c *Copy, b []int) []int {
	out := []int{}
	for k, v := range c.Message.Stamp {
		limit := b[k]
		if k == c.Source {
			limit++
		}
		if v > limit {
			out = append(out, k)
		}
	}
	return out
}
func vectorText(v []int) string {
	a := make([]string, len(v))
	for i, x := range v {
		a[i] = fmt.Sprint(x)
	}
	return strings.Join(a, ",")
}
