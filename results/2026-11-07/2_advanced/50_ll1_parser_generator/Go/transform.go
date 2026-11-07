package main

import (
	"slices"
	"strings"
)

func cloneGrammar(g Grammar) Grammar {
	out := Grammar{Order: append([]string{}, g.Order...), Rules: map[string][][]string{}, Start: g.Start}
	for _, lhs := range g.Order {
		for _, rhs := range g.Rules[lhs] {
			out.Rules[lhs] = append(out.Rules[lhs], append([]string{}, rhs...))
		}
	}
	return out
}
func concatenate(parts ...[]string) []string {
	out := []string{}
	for _, part := range parts {
		out = append(out, part...)
	}
	return out
}
func freshName(lhs string, rules map[string][][]string) string {
	proposed := strings.TrimSuffix(lhs, ">") + "'>"
	for {
		if _, ok := rules[proposed]; !ok {
			return proposed
		}
		proposed = strings.TrimSuffix(proposed, ">") + "'>"
	}
}
func leadingReaches(rules map[string][][]string, source, target string) bool {
	queue := []string{source}
	seen := map[string]bool{source: true}
	for i := 0; i < len(queue); i++ {
		for _, rhs := range rules[queue[i]] {
			if len(rhs) == 0 || !isNonterminal(rhs[0]) {
				continue
			}
			next := rhs[0]
			if next == target {
				return true
			}
			if !seen[next] {
				seen[next] = true
				queue = append(queue, next)
			}
		}
	}
	return false
}
func deduplicate(alternatives [][]string) [][]string {
	out := [][]string{}
	for _, rhs := range alternatives {
		duplicate := false
		for _, old := range out {
			if slices.Equal(old, rhs) {
				duplicate = true
				break
			}
		}
		if !duplicate {
			out = append(out, rhs)
		}
	}
	return out
}
func eliminateLeftRecursion(grammar Grammar) (Grammar, []string) {
	g := cloneGrammar(grammar)
	initial := append([]string{}, g.Order...)
	log := []string{}
	for i, lhs := range initial {
		for _, earlier := range initial[:i] {
			has := false
			for _, rhs := range g.Rules[lhs] {
				if len(rhs) > 0 && rhs[0] == earlier {
					has = true
					break
				}
			}
			if !has || !leadingReaches(g.Rules, earlier, lhs) {
				continue
			}
			replacements := [][]string{}
			for _, rhs := range g.Rules[lhs] {
				if len(rhs) > 0 && rhs[0] == earlier {
					for _, source := range g.Rules[earlier] {
						replacements = append(replacements, concatenate(source, rhs[1:]))
					}
				} else {
					replacements = append(replacements, rhs)
				}
			}
			g.Rules[lhs] = deduplicate(replacements)
			log = append(log, "substitute "+earlier+" into "+lhs)
		}
		recursive, nonrecursive := [][]string{}, [][]string{}
		for _, rhs := range g.Rules[lhs] {
			if len(rhs) == 1 && rhs[0] == lhs {
				log = append(log, "remove cycle "+productionNotation(lhs, rhs))
				continue
			}
			if len(rhs) > 0 && rhs[0] == lhs {
				recursive = append(recursive, rhs[1:])
			} else {
				nonrecursive = append(nonrecursive, rhs)
			}
		}
		g.Rules[lhs] = nonrecursive
		if len(recursive) == 0 {
			continue
		}
		created := freshName(lhs, g.Rules)
		g.Rules[lhs] = [][]string{}
		for _, rhs := range nonrecursive {
			g.Rules[lhs] = append(g.Rules[lhs], concatenate(rhs, []string{created}))
		}
		g.Rules[created] = [][]string{}
		for _, rhs := range recursive {
			g.Rules[created] = append(g.Rules[created], concatenate(rhs, []string{created}))
		}
		g.Rules[created] = append(g.Rules[created], []string{})
		position := slices.Index(g.Order, lhs) + 1
		g.Order = append(append(append([]string{}, g.Order[:position]...), created), g.Order[position:]...)
		log = append(log, "eliminate left recursion in "+lhs+" with "+created)
	}
	return g, log
}
func leftFactor(grammar Grammar) (Grammar, []string) {
	g := cloneGrammar(grammar)
	log := []string{}
	for position := 0; position < len(g.Order); position++ {
		lhs := g.Order[position]
		current := g.Rules[lhs]
		kept := [][]string{}
		createdNames := []string{}
		handled := map[string]bool{}
		for _, rhs := range current {
			if len(rhs) == 0 {
				kept = append(kept, rhs)
				continue
			}
			first := rhs[0]
			if handled[first] {
				continue
			}
			handled[first] = true
			group := [][]string{}
			for _, other := range current {
				if len(other) > 0 && other[0] == first {
					group = append(group, other)
				}
			}
			if len(group) == 1 {
				kept = append(kept, rhs)
				continue
			}
			length := len(group[0])
			for _, other := range group[1:] {
				length = min(length, len(other))
				for k := 0; k < length; k++ {
					if other[k] != group[0][k] {
						length = k
						break
					}
				}
			}
			prefix := group[0][:length]
			created := freshName(lhs, g.Rules)
			g.Rules[created] = [][]string{}
			for _, other := range group {
				g.Rules[created] = append(g.Rules[created], append([]string{}, other[length:]...))
			}
			kept = append(kept, concatenate(prefix, []string{created}))
			createdNames = append(createdNames, created)
			log = append(log, "left factor "+lhs+" on "+notation(prefix)+" with "+created)
		}
		g.Rules[lhs] = kept
		g.Order = append(concatenate(g.Order[:position+1], createdNames), g.Order[position+1:]...)
	}
	return g, log
}
