package main

import "fmt"

type SearchNode struct {
	Lower, Upper  []*Fraction
	Depth, Parent int
	Branch        string
	ParentValue   Fraction
}
type ModelResult struct {
	Status      string
	Objective   Fraction
	HasSolution bool
	Solution    []Fraction
	Solves      []*LPResult
	Root        *LPResult
	Tree        []string
}

func better(m *Model, a, b Fraction) bool {
	if m.Direction == "maximize" {
		return a.cmp(b) > 0
	}
	return a.cmp(b) < 0
}
func branchBound(m *Model, limit int, solve func([]*Fraction, []*Fraction, int) *LPResult) ModelResult {
	stack := []SearchNode{{Lower: append([]*Fraction{}, m.Lower...), Upper: append([]*Fraction{}, m.Upper...), Branch: "root"}}
	r := ModelResult{}
	incumbents, pruned, infeasible := 0, 0, 0
	for len(stack) > 0 {
		if len(r.Solves) == limit {
			r.Status = "NODE_LIMIT"
			break
		}
		node := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		number := len(r.Solves) + 1
		lp := solve(node.Lower, node.Upper, number)
		r.Solves = append(r.Solves, lp)
		if number == 1 {
			r.Root = lp
		}
		outcome := ""
		switch {
		case lp.Status == "INFEASIBLE":
			outcome = "infeasible"
			infeasible++
		case lp.Status == "UNBOUNDED":
			outcome = "unbounded"
			r.Status = "UNBOUNDED"
		case r.HasSolution && !better(m, lp.Objective, r.Objective):
			outcome = "pruned"
			pruned++
		default:
			j := -1
			for k, required := range m.Integer {
				if required && !lp.Solution[k].whole() {
					j = k
					break
				}
			}
			if j < 0 {
				r.HasSolution = true
				r.Objective = lp.Objective
				r.Solution = append([]Fraction{}, lp.Solution...)
				outcome = "incumbent"
				incumbents++
			} else {
				value := lp.Solution[j]
				down, up := integer(value.floor()), integer(value.ceil())
				lower := append([]*Fraction{}, node.Lower...)
				lower[j] = finite(up)
				upper := append([]*Fraction{}, node.Upper...)
				upper[j] = finite(down)
				stack = append(stack, SearchNode{lower, append([]*Fraction{}, node.Upper...), node.Depth + 1, number, m.Variables[j] + ">=" + up.String(), lp.Objective}, SearchNode{append([]*Fraction{}, node.Lower...), upper, node.Depth + 1, number, m.Variables[j] + "<=" + down.String(), lp.Objective})
				outcome = "branch " + m.Variables[j] + " " + value.String()
			}
		}
		parent := "-"
		if node.Parent > 0 {
			parent = fmt.Sprint(node.Parent)
		}
		lpValue := lp.Objective.String()
		if lp.Status == "INFEASIBLE" {
			lpValue = "infeasible"
		}
		if lp.Status == "UNBOUNDED" {
			lpValue = "unbounded"
		}
		r.Tree = append(r.Tree, fmt.Sprintf("NODE %d depth %d parent %s branch %s lp %s pivots %d action %s", number, node.Depth, parent, node.Branch, lpValue, lp.pivots(), outcome))
		if r.Status == "UNBOUNDED" {
			break
		}
	}
	if r.Status == "" {
		r.Status = "INFEASIBLE"
		if r.HasSolution {
			r.Status = "OPTIMAL"
		}
	}
	var bound *Fraction
	if r.HasSolution {
		bound = finite(r.Objective)
	}
	if r.Status == "NODE_LIMIT" {
		for i := len(stack) - 1; i >= 0; i-- {
			node := stack[i]
			r.Tree = append(r.Tree, fmt.Sprintf("OPEN parent %d branch %s bound %s", node.Parent, node.Branch, node.ParentValue))
			if bound == nil || better(m, node.ParentValue, *bound) {
				bound = finite(node.ParentValue)
			}
		}
	}
	objective, boundValue := "-", "-"
	if r.HasSolution {
		objective = r.Objective.String()
	}
	if bound != nil {
		boundValue = bound.String()
	}
	r.Tree = append(r.Tree, fmt.Sprintf("RESULT %s objective %s nodes %d incumbents %d pruned %d infeasible %d open %d bound %s", r.Status, objective, len(r.Solves), incumbents, pruned, infeasible, len(stack), boundValue))
	return r
}
