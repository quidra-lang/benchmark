package main

import "sort"

type Box [4]int

func area(b Box) int { return (b[2] - b[0]) * (b[3] - b[1]) }
func mbr(a, b Box) Box {
	return Box{min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3])}
}
func enlargement(a, b Box) int { return area(mbr(a, b)) - area(a) }
func contains(a, b Box) bool   { return a[0] <= b[0] && b[2] <= a[2] && a[1] <= b[1] && b[3] <= a[3] }
func intersects(a, b Box) bool { return a[0] <= b[2] && b[0] <= a[2] && a[1] <= b[3] && b[1] <= a[3] }
func overlap(a, b Box) int {
	w, h := min(a[2], b[2])-max(a[0], b[0]), min(a[3], b[3])-max(a[1], b[1])
	if w > 0 && h > 0 {
		return w * h
	}
	return 0
}

type Entry struct {
	Box    Box
	ID     int
	Child  *RNode
	Number int
}
type RNode struct {
	Level   int
	Entries []*Entry
	Parent  *RNode
}

func (n *RNode) box() Box {
	b := n.Entries[0].Box
	for _, e := range n.Entries[1:] {
		b = mbr(b, e.Box)
	}
	return b
}
func (n *RNode) adoptChildren() {
	if n.Level > 0 {
		for _, e := range n.Entries {
			e.Child.Parent = n
		}
	}
}
func newRNode(level int, entries []*Entry) *RNode {
	n := &RNode{Level: level, Entries: entries}
	n.adoptChildren()
	return n
}

type RTree struct {
	Maximum, Minimum int
	Root             *RNode
}

func (t *RTree) chooseSubtree(box Box, level int) *RNode {
	node := t.Root
	for node.Level > level {
		best := node.Entries[0]
		for _, e := range node.Entries[1:] {
			a, b := enlargement(e.Box, box), enlargement(best.Box, box)
			if a < b || a == b && area(e.Box) < area(best.Box) {
				best = e
			}
		}
		node = best.Child
	}
	return node
}
func (t *RTree) split(node *RNode) *RNode {
	entries := node.Entries
	first, second, bestWaste := 0, 1, 0
	initialized := false
	for i := 0; i < len(entries)-1; i++ {
		for j := i + 1; j < len(entries); j++ {
			a, b := entries[i].Box, entries[j].Box
			waste := area(mbr(a, b)) - area(a) - area(b)
			if !initialized || waste > bestWaste {
				first, second, bestWaste, initialized = i, j, waste, true
			}
		}
	}
	group1, group2 := []*Entry{entries[first]}, []*Entry{entries[second]}
	box1, box2 := entries[first].Box, entries[second].Box
	rest := []*Entry{}
	for i, e := range entries {
		if i != first && i != second {
			rest = append(rest, e)
		}
	}
	for len(rest) > 0 {
		if len(group1)+len(rest) == t.Minimum {
			group1 = append(group1, rest...)
			break
		}
		if len(group2)+len(rest) == t.Minimum {
			group2 = append(group2, rest...)
			break
		}
		selected, greatest, d1, d2 := 0, -1, 0, 0
		for i, e := range rest {
			a, b := enlargement(box1, e.Box), enlargement(box2, e.Box)
			difference := a - b
			if difference < 0 {
				difference = -difference
			}
			if difference > greatest {
				selected, greatest, d1, d2 = i, difference, a, b
			}
		}
		e := rest[selected]
		rest = append(rest[:selected], rest[selected+1:]...)
		choice1 := d1 < d2 || d1 == d2 && (area(box1) < area(box2) || area(box1) == area(box2) && len(group1) <= len(group2))
		if choice1 {
			group1 = append(group1, e)
			box1 = mbr(box1, e.Box)
		} else {
			group2 = append(group2, e)
			box2 = mbr(box2, e.Box)
		}
	}
	node.Entries = group1
	node.adoptChildren()
	sibling := newRNode(node.Level, group2)
	sibling.Parent = node.Parent
	return sibling
}
func (t *RTree) insert(entry *Entry, level int) {
	node := t.chooseSubtree(entry.Box, level)
	node.Entries = append(node.Entries, entry)
	if level > 0 {
		entry.Child.Parent = node
	}
	for {
		var sibling *RNode
		if len(node.Entries) > t.Maximum {
			sibling = t.split(node)
		}
		parent := node.Parent
		if parent == nil {
			if sibling != nil {
				t.Root = newRNode(node.Level+1, []*Entry{{Box: node.box(), Child: node}, {Box: sibling.box(), Child: sibling}})
			}
			return
		}
		for _, e := range parent.Entries {
			if e.Child == node {
				e.Box = node.box()
				break
			}
		}
		if sibling != nil {
			parent.Entries = append(parent.Entries, &Entry{Box: sibling.box(), Child: sibling})
			sibling.Parent = parent
		}
		node = parent
	}
}
func findLeaf(node *RNode, point Object) (*RNode, int) {
	if node.Level == 0 {
		for i, e := range node.Entries {
			if e.ID == point.ID {
				return node, i
			}
		}
	} else {
		for _, e := range node.Entries {
			if contains(e.Box, point.Box) {
				if leaf, i := findLeaf(e.Child, point); leaf != nil {
					return leaf, i
				}
			}
		}
	}
	return nil, 0
}
func (t *RTree) delete(point Object) {
	node, index := findLeaf(t.Root, point)
	node.Entries = append(node.Entries[:index], node.Entries[index+1:]...)
	removed := []*RNode{}
	for node != t.Root {
		parent := node.Parent
		for i, e := range parent.Entries {
			if e.Child == node {
				if len(node.Entries) < t.Minimum {
					parent.Entries = append(parent.Entries[:i], parent.Entries[i+1:]...)
					removed = append(removed, node)
					node.Parent = nil
				} else {
					e.Box = node.box()
				}
				break
			}
		}
		node = parent
	}
	for _, n := range removed {
		for _, e := range n.Entries {
			t.insert(e, n.Level)
		}
	}
	for t.Root.Level > 0 && len(t.Root.Entries) == 1 {
		t.Root = t.Root.Entries[0].Child
		t.Root.Parent = nil
	}
}
func strRoot(entries []*Entry, maximum int) *RNode {
	level := 0
	for {
		pages := (len(entries) + maximum - 1) / maximum
		slabs := 1
		for slabs*slabs < pages {
			slabs++
		}
		sort.Slice(entries, func(i, j int) bool {
			a, b := entries[i], entries[j]
			x, y := a.Box[0]+a.Box[2], b.Box[0]+b.Box[2]
			if x != y {
				return x < y
			}
			x, y = a.Box[1]+a.Box[3], b.Box[1]+b.Box[3]
			return x < y || x == y && a.Number < b.Number
		})
		nodes := []*RNode{}
		slabSize := slabs * maximum
		for start := 0; start < len(entries); start += slabSize {
			slab := append([]*Entry{}, entries[start:min(start+slabSize, len(entries))]...)
			sort.Slice(slab, func(i, j int) bool {
				a, b := slab[i], slab[j]
				x, y := a.Box[1]+a.Box[3], b.Box[1]+b.Box[3]
				if x != y {
					return x < y
				}
				x, y = a.Box[0]+a.Box[2], b.Box[0]+b.Box[2]
				return x < y || x == y && a.Number < b.Number
			})
			for offset := 0; offset < len(slab); offset += maximum {
				nodes = append(nodes, newRNode(level, append([]*Entry{}, slab[offset:min(offset+maximum, len(slab))]...)))
			}
		}
		if len(nodes) == 1 {
			return nodes[0]
		}
		entries = []*Entry{}
		for i, node := range nodes {
			entries = append(entries, &Entry{Box: node.box(), Child: node, Number: i})
		}
		level++
	}
}
func buildRTree(objects []Object, maximum, minimum int, bulk bool) *RTree {
	tree := &RTree{maximum, minimum, newRNode(0, nil)}
	entries := []*Entry{}
	for _, o := range objects {
		entries = append(entries, &Entry{Box: o.Box, ID: o.ID, Number: o.ID})
	}
	if bulk {
		tree.Root = strRoot(entries, maximum)
	} else {
		for _, e := range entries {
			tree.insert(e, 0)
		}
	}
	return tree
}
