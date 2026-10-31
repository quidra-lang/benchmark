package main

import "sort"

var childNames = []string{"NW", "NE", "SW", "SE"}

type QuadNode struct {
	X, Y, Size int
	Points     []Object
	Children   []*QuadNode
}

func destination(node *QuadNode, point Object) int {
	index := 0
	half := node.Size / 2
	if point.Box[0] >= node.X+half {
		index++
	}
	if point.Box[1] >= node.Y+half {
		index += 2
	}
	return index
}
func insertQuad(node *QuadNode, point Object, capacity int) {
	if len(node.Children) > 0 {
		insertQuad(node.Children[destination(node, point)], point, capacity)
		return
	}
	node.Points = append(node.Points, point)
	sort.Slice(node.Points, func(i, j int) bool { return node.Points[i].ID < node.Points[j].ID })
	if len(node.Points) <= capacity {
		return
	}
	h := node.Size / 2
	node.Children = []*QuadNode{{X: node.X, Y: node.Y, Size: h}, {X: node.X + h, Y: node.Y, Size: h},
		{X: node.X, Y: node.Y + h, Size: h}, {X: node.X + h, Y: node.Y + h, Size: h}}
	previous := node.Points
	node.Points = nil
	for _, p := range previous {
		insertQuad(node, p, capacity)
	}
}
func deleteQuad(node *QuadNode, point Object, capacity int) {
	if len(node.Children) == 0 {
		for i, p := range node.Points {
			if p.ID == point.ID {
				node.Points = append(node.Points[:i], node.Points[i+1:]...)
				return
			}
		}
		return
	}
	deleteQuad(node.Children[destination(node, point)], point, capacity)
	points := []Object{}
	for _, child := range node.Children {
		if len(child.Children) > 0 {
			return
		}
		points = append(points, child.Points...)
	}
	if len(points) <= capacity {
		sort.Slice(points, func(i, j int) bool { return points[i].ID < points[j].ID })
		node.Points = points
		node.Children = nil
	}
}
func buildQuad(points []Object, world, capacity int) *QuadNode {
	root := &QuadNode{Size: world}
	for _, p := range points {
		insertQuad(root, p, capacity)
	}
	return root
}
