package main

import "sort"

type KDNode struct {
	Point       Object
	Axis        int
	Left, Right *KDNode
}

func keyLess(a, b Object, axis int) bool {
	first, second := 0, 1
	if axis == 1 {
		first, second = 1, 0
	}
	if a.Box[first] != b.Box[first] {
		return a.Box[first] < b.Box[first]
	}
	if a.Box[second] != b.Box[second] {
		return a.Box[second] < b.Box[second]
	}
	return a.ID < b.ID
}
func buildKD(points []Object, depth int) *KDNode {
	if len(points) == 0 {
		return nil
	}
	ordered := append([]Object{}, points...)
	axis := depth % 2
	sort.Slice(ordered, func(i, j int) bool { return keyLess(ordered[i], ordered[j], axis) })
	middle := len(ordered) / 2
	return &KDNode{ordered[middle], axis, buildKD(ordered[:middle], depth+1), buildKD(ordered[middle+1:], depth+1)}
}
func insertKD(root *KDNode, point Object) *KDNode {
	if root == nil {
		return &KDNode{Point: point}
	}
	node := root
	for {
		left := keyLess(point, node.Point, node.Axis)
		child := node.Right
		if left {
			child = node.Left
		}
		if child == nil {
			child = &KDNode{Point: point, Axis: 1 - node.Axis}
			if left {
				node.Left = child
			} else {
				node.Right = child
			}
			return root
		}
		node = child
	}
}
func minimumKD(node *KDNode, axis int) Object {
	if node.Axis == axis {
		if node.Left == nil {
			return node.Point
		}
		return minimumKD(node.Left, axis)
	}
	best := node.Point
	for _, child := range []*KDNode{node.Left, node.Right} {
		if child != nil {
			candidate := minimumKD(child, axis)
			if keyLess(candidate, best, axis) {
				best = candidate
			}
		}
	}
	return best
}
func deleteKD(node *KDNode, point Object) *KDNode {
	if node == nil {
		return nil
	}
	if node.Point.ID == point.ID {
		if node.Right != nil {
			replacement := minimumKD(node.Right, node.Axis)
			node.Point = replacement
			node.Right = deleteKD(node.Right, replacement)
		} else if node.Left != nil {
			replacement := minimumKD(node.Left, node.Axis)
			node.Point = replacement
			node.Right = deleteKD(node.Left, replacement)
			node.Left = nil
		} else {
			return nil
		}
	} else if keyLess(point, node.Point, node.Axis) {
		node.Left = deleteKD(node.Left, point)
	} else {
		node.Right = deleteKD(node.Right, point)
	}
	return node
}
