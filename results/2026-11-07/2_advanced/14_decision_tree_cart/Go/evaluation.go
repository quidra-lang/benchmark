package main

import (
	"fmt"
	"strings"
)

type Tree struct {
	root *Node
	cuts map[int]bool
}
type RouteStep struct {
	node   *Node
	left   bool
	method string
}
type Route struct {
	leaf  *Node
	path  []*Node
	steps []RouteStep
}

func (t Tree) isLeaf(node *Node) bool { return node.split == nil || t.cuts[node.number] }
func (t Tree) preorder(start *Node) []*Node {
	if start == nil {
		start = t.root
	}
	nodes := []*Node{}
	pending := []*Node{start}
	for len(pending) > 0 {
		node := pending[len(pending)-1]
		pending = pending[:len(pending)-1]
		nodes = append(nodes, node)
		if !t.isLeaf(node) {
			pending = append(pending, node.right, node.left)
		}
	}
	return nodes
}
func (t Tree) leaves() []*Node {
	leaves := []*Node{}
	for _, node := range t.preorder(nil) {
		if t.isLeaf(node) {
			leaves = append(leaves, node)
		}
	}
	return leaves
}
func (t Tree) internal() []*Node {
	nodes := []*Node{}
	for _, node := range t.preorder(nil) {
		if !t.isLeaf(node) {
			nodes = append(nodes, node)
		}
	}
	return nodes
}
func (t Tree) depth() int {
	depth := 0
	for _, node := range t.leaves() {
		depth = max(depth, node.depth)
	}
	return depth
}
func (t Tree) trainingErrors() int64 {
	errors := int64(0)
	for _, node := range t.leaves() {
		errors += node.stats.errors
	}
	return errors
}
func (t Tree) route(row Row) Route {
	result := Route{}
	node := t.root
	for {
		result.path = append(result.path, node)
		if t.isLeaf(node) {
			result.leaf = node
			return result
		}
		left, method := node.defaultLeft, "default"
		value := row.values[node.split.attribute.index]
		if value >= 0 {
			left = node.split.goesLeft(value)
			method = "primary"
		} else {
			for _, surrogate := range node.surrogates {
				value = row.values[surrogate.split.attribute.index]
				if value >= 0 {
					left = surrogate.split.goesLeft(value) == surrogate.left
					method = "surrogate"
					break
				}
			}
		}
		result.steps = append(result.steps, RouteStep{node, left, method})
		if left {
			node = node.left
		} else {
			node = node.right
		}
	}
}
func (t Tree) predict(row Row) int { return t.route(row).leaf.stats.majority }
func (t Tree) correct(rows []Row) int64 {
	correct := int64(0)
	for _, row := range rows {
		if t.predict(row) == row.label {
			correct++
		}
	}
	return correct
}
func realText(value float64, places int) string {
	text := fmt.Sprintf("%.*f", places, value)
	if text == "-0."+strings.Repeat("0", places) {
		return text[1:]
	}
	return text
}
func ratioText(numerator, denominator int64) string {
	if denominator == 0 {
		return "0/0 -"
	}
	return fmt.Sprintf("%d/%d %s", numerator, denominator, realText(float64(numerator)/float64(denominator), 4))
}
func fractionText(numerator, denominator int64, places int) string {
	if denominator == 0 {
		return "- -"
	}
	a, b := numerator, denominator
	if a < 0 {
		a = -a
	}
	for b != 0 {
		a, b = b, a%b
	}
	return fmt.Sprintf("%d/%d %s", numerator/a, denominator/a, realText(float64(numerator)/float64(denominator), places))
}
func classificationLines(title string, classes []string, rows []Row, predicted []int) []string {
	matrix := make([][]int64, len(classes))
	for i := range matrix {
		matrix[i] = make([]int64, len(classes))
	}
	correct := int64(0)
	for i, row := range rows {
		matrix[row.label][predicted[i]]++
		if row.label == predicted[i] {
			correct++
		}
	}
	lines := []string{fmt.Sprintf("confusion %s correct %d/%d accuracy %s", title, correct, len(rows), fractionText(correct, int64(len(rows)), 4)), "actual\\predicted " + strings.Join(classes, " ")}
	for i, name := range classes {
		lines = append(lines, name+" "+countsText(matrix[i]))
	}
	macro := 0.0
	defined := 0
	for i, name := range classes {
		hits := matrix[i][i]
		predictedTotal := int64(0)
		for _, counts := range matrix {
			predictedTotal += counts[i]
		}
		support := sum(matrix[i])
		denominator := predictedTotal + support
		if denominator > 0 {
			macro += float64(2*hits) / float64(denominator)
			defined++
		}
		lines = append(lines, fmt.Sprintf("class %s precision %s recall %s f1 %s support %d", name, fractionText(hits, predictedTotal, 4), fractionText(hits, support, 4), fractionText(2*hits, denominator, 4), support))
	}
	average := "-"
	if defined > 0 {
		average = realText(macro/float64(defined), 4)
	}
	return append(lines, "macro_f1 "+average)
}
