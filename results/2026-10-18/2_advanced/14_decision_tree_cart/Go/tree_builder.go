package main

import (
	"fmt"
	"sort"
)

type Split struct {
	attribute *Attribute
	point     int
}

func halfText(point int) string { return fmt.Sprintf("%d.%d", point/2, 5*(point%2)) }
func (s Split) goesLeft(value int) bool {
	if s.attribute.integer {
		return 2*value <= s.point
	}
	return value == s.point
}
func (s Split) condition(left bool) string {
	if s.attribute.integer {
		operator := ">"
		if left {
			operator = "<="
		}
		return s.attribute.name + " " + operator + " " + halfText(s.point)
	}
	operator := "!="
	if left {
		operator = "="
	}
	return s.attribute.name + " " + operator + " " + s.attribute.values[s.point]
}

type Surrogate struct {
	split Split
	left  bool
	score int
}
type Candidate struct {
	split       Split
	left, right []Row
	value       Fraction
}
type Node struct {
	number, depth int
	stats         Statistics
	split         *Split
	surrogates    []Surrogate
	defaultLeft   bool
	left, right   *Node
}
type TreeBuilder struct {
	attributes []*Attribute
	classes    int
	settings   Settings
}

func splitCandidates(rows []Row, attribute *Attribute) []Split {
	seen := map[int]bool{}
	for _, row := range rows {
		seen[row.values[attribute.index]] = true
	}
	if len(seen) < 2 {
		return nil
	}
	values := make([]int, 0, len(seen))
	for value := range seen {
		values = append(values, value)
	}
	sort.Ints(values)
	found := []Split{}
	if attribute.integer {
		for i := 1; i < len(values); i++ {
			found = append(found, Split{attribute, values[i-1] + values[i]})
		}
	} else {
		for _, value := range values {
			found = append(found, Split{attribute, value})
		}
	}
	return found
}
func partition(rows []Row, split Split) ([]Row, []Row) {
	left, right := []Row{}, []Row{}
	for _, row := range rows {
		if split.goesLeft(row.values[split.attribute.index]) {
			left = append(left, row)
		} else {
			right = append(right, row)
		}
	}
	return left, right
}
func (b *TreeBuilder) bestForAttribute(rows []Row, attribute *Attribute) *Candidate {
	var best *Candidate
	for _, split := range splitCandidates(rows, attribute) {
		left, right := partition(rows, split)
		if len(left) < b.settings.minLeaf || len(right) < b.settings.minLeaf {
			continue
		}
		value := quality(statistics(left, b.classes), statistics(right, b.classes))
		if best == nil || compareFractions(value, best.value) > 0 {
			best = &Candidate{split, left, right, value}
		}
	}
	return best
}
func (b *TreeBuilder) bestSplit(rows []Row) *Candidate {
	var best *Candidate
	for _, attribute := range b.attributes {
		candidate := b.bestForAttribute(rows, attribute)
		if candidate != nil && (best == nil || compareFractions(candidate.value, best.value) > 0) {
			best = candidate
		}
	}
	return best
}
func (b *TreeBuilder) findSurrogates(rows []Row, primary Split, leftCount, rightCount int) []Surrogate {
	retained := []Surrogate{}
	for _, attribute := range b.attributes {
		if attribute.index == primary.attribute.index {
			continue
		}
		var best *Surrogate
		for _, split := range splitCandidates(rows, attribute) {
			agreement := 0
			for _, row := range rows {
				if split.goesLeft(row.values[attribute.index]) == primary.goesLeft(row.values[primary.attribute.index]) {
					agreement++
				}
			}
			left := agreement >= len(rows)-agreement
			score := max(agreement, len(rows)-agreement)
			if best == nil || score > best.score {
				best = &Surrogate{split, left, score}
			}
		}
		if best != nil && best.score > max(leftCount, rightCount) {
			retained = append(retained, *best)
		}
	}
	sort.SliceStable(retained, func(i, j int) bool { return retained[i].score > retained[j].score })
	return retained[:min(b.settings.maxSurrogates, len(retained))]
}
func (b *TreeBuilder) grow(rows []Row) *Node { return b.growNode(rows, 1, 0) }
func (b *TreeBuilder) growNode(rows []Row, number, depth int) *Node {
	node := &Node{number: number, depth: depth, stats: statistics(rows, b.classes)}
	if node.stats.errors == 0 || depth == b.settings.maxDepth || len(rows) < b.settings.minSplit {
		return node
	}
	best := b.bestSplit(rows)
	if best == nil || !improves(best.value, node.stats) {
		return node
	}
	node.split = &best.split
	node.defaultLeft = len(best.left) >= len(best.right)
	node.surrogates = b.findSurrogates(rows, best.split, len(best.left), len(best.right))
	node.left = b.growNode(best.left, number*2, depth+1)
	node.right = b.growNode(best.right, number*2+1, depth+1)
	return node
}
