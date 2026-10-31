package main

import "sort"

type StringSet map[string]bool

func terminalOrder(set StringSet) []string {
	out := []string{}
	for s := range set {
		if s != "$" {
			out = append(out, s)
		}
	}
	sort.Strings(out)
	if set["$"] {
		out = append(out, "$")
	}
	return out
}
func terminalsOf(g Grammar) StringSet {
	out := StringSet{}
	for _, lhs := range g.Order {
		for _, rhs := range g.Rules[lhs] {
			for _, s := range rhs {
				if !isNonterminal(s) {
					out[s] = true
				}
			}
		}
	}
	return out
}
func mergeSet(target, source StringSet) bool {
	changed := false
	for s := range source {
		if !target[s] {
			target[s] = true
			changed = true
		}
	}
	return changed
}
func firstSequence(rhs []string, nullable map[string]bool, first map[string]StringSet) (StringSet, bool) {
	out := StringSet{}
	for _, s := range rhs {
		if !isNonterminal(s) {
			out[s] = true
			return out, false
		}
		mergeSet(out, first[s])
		if !nullable[s] {
			return out, false
		}
	}
	return out, true
}

type Sets struct {
	Nullable                                  map[string]bool
	First, Follow                             map[string]StringSet
	NullablePasses, FirstPasses, FollowPasses int
	Terminals                                 []string
}

func analyzeSets(g Grammar) Sets {
	out := Sets{Nullable: map[string]bool{}, First: map[string]StringSet{}, Follow: map[string]StringSet{}, Terminals: terminalOrder(terminalsOf(g))}
	for _, lhs := range g.Order {
		out.First[lhs] = StringSet{}
		out.Follow[lhs] = StringSet{}
	}
	out.Follow[g.Start]["$"] = true
	for {
		out.NullablePasses++
		changed := false
		for _, lhs := range g.Order {
			if out.Nullable[lhs] {
				continue
			}
			for _, rhs := range g.Rules[lhs] {
				empty := true
				for _, s := range rhs {
					if !isNonterminal(s) || !out.Nullable[s] {
						empty = false
						break
					}
				}
				if empty {
					out.Nullable[lhs] = true
					changed = true
					break
				}
			}
		}
		if !changed {
			break
		}
	}
	for {
		out.FirstPasses++
		changed := false
		for _, lhs := range g.Order {
			for _, rhs := range g.Rules[lhs] {
				more, _ := firstSequence(rhs, out.Nullable, out.First)
				if mergeSet(out.First[lhs], more) {
					changed = true
				}
			}
		}
		if !changed {
			break
		}
	}
	for {
		out.FollowPasses++
		changed := false
		for _, lhs := range g.Order {
			for _, rhs := range g.Rules[lhs] {
				for i, s := range rhs {
					if !isNonterminal(s) {
						continue
					}
					more, empty := firstSequence(rhs[i+1:], out.Nullable, out.First)
					if empty {
						mergeSet(more, out.Follow[lhs])
					}
					if mergeSet(out.Follow[s], more) {
						changed = true
					}
				}
			}
		}
		if !changed {
			break
		}
	}
	return out
}
