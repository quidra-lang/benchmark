package main

import (
	"fmt"
)

type Node struct {
	weight, minimum, left, right, symbol int
}

func pop(roots * []int, nodes[]Node) int {
	best := 0
	for i := 1; i < len(*roots); i++ {
		a, b := nodes[(*roots)[i]], nodes[(*roots)[best]]
		if a.weight < b.weight || a.weight == b.weight && a.minimum < b.minimum {
			best = i
		}
	}
	result := (*roots)[best]
	(*roots)[best] = (*roots)[len(*roots) - 1]
	* roots = (*roots)[: len(*roots) - 1]
	return result
}

func assign(nodes[]Node, root int, prefix string, codes * [128]string) {
	if nodes[root].symbol >= 0 {
		codes[nodes[root].symbol] = prefix
		return
	}
	assign(nodes, nodes[root].left, prefix + "0", codes)
	assign(nodes, nodes[root].right, prefix + "1", codes)
}

func main() {
	text := "she sells sea shells by the sea shore"
	freq := [128]int{}
	for i := range text {
		freq[text[i]]++
	}
	nodes := []Node{}
	roots := []int{}
	for c, f := range freq {
		if f > 0 {
			roots = append(roots, len(nodes))
			nodes = append(nodes, Node{f, c, -1, -1, c})
		}
	}
	for len(roots) > 1 {
		left, right := pop(&roots, nodes), pop(&roots, nodes)
		roots = append(roots, len(nodes))
		nodes = append(nodes, Node{nodes[left].weight + nodes[right].weight, min(nodes[left].minimum, nodes[right].minimum),
			left, right, -1})
	}
	codes := [128]string{}
	assign(nodes, roots[0], "", &codes)
	bits := 0
	for c, f := range freq {
		if f > 0 {
			fmt.Printf("'%c' freq=%d code=%s\n", c, f, codes[c])
			bits += f * len(codes[c])
		}
	}
	fmt.Printf("encoded bits: %d\nfixed 8-bit: %d\n", bits, len(text) * 8)
}
