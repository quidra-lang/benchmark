package main

import "sort"

type HuffNode struct {
	Weight, Minimum, Symbol int
	Left, Right             *HuffNode
}

func treeLengths(frequencies []int) []int {
	lengths := make([]int, len(frequencies))
	nodes := []*HuffNode{}
	for s, w := range frequencies {
		if w > 0 {
			nodes = append(nodes, &HuffNode{Weight: w, Minimum: s, Symbol: s})
		}
	}
	if len(nodes) == 0 {
		return lengths
	}
	if len(nodes) == 1 {
		lengths[nodes[0].Symbol] = 1
		return lengths
	}
	for len(nodes) > 1 {
		sort.Slice(nodes, func(i, j int) bool {
			if nodes[i].Weight != nodes[j].Weight {
				return nodes[i].Weight < nodes[j].Weight
			}
			return nodes[i].Minimum < nodes[j].Minimum
		})
		a, b := nodes[0], nodes[1]
		nodes = append(nodes[2:], &HuffNode{Weight: a.Weight + b.Weight, Minimum: min(a.Minimum, b.Minimum), Symbol: -1, Left: a, Right: b})
	}
	var visit func(*HuffNode, int)
	visit = func(n *HuffNode, depth int) {
		if n.Symbol >= 0 {
			lengths[n.Symbol] = depth
			return
		}
		visit(n.Left, depth+1)
		visit(n.Right, depth+1)
	}
	visit(nodes[0], 0)
	return lengths
}
func limitedLengths(frequencies []int, maximum int) ([]int, int) {
	weights := append([]int{}, frequencies...)
	halvings := 0
	for {
		lengths := treeLengths(weights)
		longest := 0
		for _, v := range lengths {
			longest = max(longest, v)
		}
		if longest <= maximum {
			return lengths, halvings
		}
		for i, v := range weights {
			weights[i] = (v + 1) / 2
		}
		halvings++
	}
}
func canonicalCodes(lengths []int) []int {
	order := []int{}
	for s, v := range lengths {
		if v > 0 {
			order = append(order, s)
		}
	}
	sort.Slice(order, func(i, j int) bool {
		a, b := order[i], order[j]
		if lengths[a] != lengths[b] {
			return lengths[a] < lengths[b]
		}
		return a < b
	})
	codes := make([]int, len(lengths))
	code, previous := 0, 0
	for i, s := range order {
		if i > 0 {
			code = (code + 1) << (lengths[s] - previous)
		}
		codes[s] = code
		previous = lengths[s]
	}
	return codes
}
