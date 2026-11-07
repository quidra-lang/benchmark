package main

import (
	"strconv"
	"strings"
)

type Domain struct {
	attribute string
	values    []Value
}
type Days [366]bool

func dayNotation(days Days) string {
	var runs []string
	for first := 1; first <= 365; {
		if !days[first] {
			first++
			continue
		}
		last := first
		for last < 365 && days[last+1] {
			last++
		}
		runs = append(runs,
			strconv.Itoa(first)+"-"+strconv.Itoa(last))
		first = last + 1
	}
	return strings.Join(runs, ",")
}
func unionDays(a, b Days) Days {
	for i := 1; i <= 365; i++ {
		a[i] = a[i] || b[i]
	}
	return a
}
func enumeratePoints(domains []Domain, visit func(map[string]Value)) {
	point := map[string]Value{}
	var walk func(int)
	walk = func(i int) {
		if i == len(domains) {
			visit(point)
			return
		}
		for _, value := range domains[i].values {
			point[domains[i].attribute] = value
			walk(i + 1)
		}
	}
	walk(0)
}
func conflictWinner(policy, a, b *Element) *Element {
	if policy.algorithm == "first-applicable" {
		return a
	}
	effect := "PERMIT"
	if policy.algorithm == "deny-overrides" || policy.algorithm == "permit-unless-deny" {
		effect = "DENY"
	}
	if a.effect == effect {
		return a
	}
	return b
}
func blocker(rule *Element, standalone map[*Element]string) *Element {
	for _, earlier := range rule.parent.children {
		if earlier == rule {
			break
		}
		if standalone[earlier] != na {
			return earlier
		}
	}
	return nil
}
