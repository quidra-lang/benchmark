package main

type Decision struct {
	node                    *Node
	rows                    int
	leafError, subtreeError int64
	pruned                  bool
}
type SequenceTree struct {
	alpha Fraction
	tree  Tree
}

func reducedErrorPruning(root *Node, rows []Row) (Tree, []Decision) {
	reached := map[int][]Row{}
	original := Tree{root, nil}
	for _, row := range rows {
		for _, node := range original.route(row).path {
			reached[node.number] = append(reached[node.number], row)
		}
	}
	cuts := map[int]bool{}
	decisions := []Decision{}
	var decide func(*Node) int64
	decide = func(node *Node) int64 {
		leafError := int64(0)
		for _, row := range reached[node.number] {
			if row.label != node.stats.majority {
				leafError++
			}
		}
		if node.split == nil {
			return leafError
		}
		subtreeError := decide(node.left) + decide(node.right)
		pruned := leafError <= subtreeError
		decisions = append(decisions, Decision{node, len(reached[node.number]), leafError, subtreeError, pruned})
		if pruned {
			cuts[node.number] = true
			return leafError
		}
		return subtreeError
	}
	decide(root)
	return Tree{root, cuts}, decisions
}
func costComplexitySequence(root *Node) []SequenceTree {
	tree := Tree{root, map[int]bool{}}
	sequence := []SequenceTree{{Fraction{0, 1}, tree}}
	for !tree.isLeaf(root) {
		alpha := Fraction{0, 0}
		weakest := []int{}
		for _, node := range tree.internal() {
			leaves := int64(0)
			errors := int64(0)
			for _, descendant := range tree.preorder(node) {
				if tree.isLeaf(descendant) {
					leaves++
					errors += descendant.stats.errors
				}
			}
			strength := Fraction{node.stats.errors - errors, leaves - 1}
			comparison := -1
			if alpha.denominator != 0 {
				comparison = compareFractions(strength, alpha)
			}
			if comparison < 0 {
				alpha = strength
				weakest = []int{node.number}
			} else if comparison == 0 {
				weakest = append(weakest, node.number)
			}
		}
		cuts := map[int]bool{}
		for number := range tree.cuts {
			cuts[number] = true
		}
		for _, number := range weakest {
			cuts[number] = true
		}
		tree = Tree{root, cuts}
		sequence = append(sequence, SequenceTree{alpha, tree})
	}
	return sequence
}
