package main

import "fmt"

type Node struct {
	key, left, right int
}

func insert(nodes *[]Node, root, key int) int {
	if root < 0 {
		*nodes = append(*nodes, Node{key, -1, -1})
		return len(*nodes) -1
	}
	if key < (*nodes)[root].key {
		child := insert(nodes, (*nodes)[root].left, key)
		(*nodes)[root].left = child
	} else {
		child := insert(nodes, (*nodes)[root].right, key)
		(*nodes)[root].right = child
	}
	return root
}

func traverse(nodes []Node, root, mode int) {
	if root < 0 {
		return
	}
	if mode == 1 {
		fmt.Printf(" %d", nodes[root].key)
	}
	traverse(nodes, nodes[root].left, mode)
	if mode == 0 {
		fmt.Printf(" %d", nodes[root].key)
	}
	traverse(nodes, nodes[root].right, mode)
	if mode == 2 {
		fmt.Printf(" %d", nodes[root].key)
	}
}

func height(nodes []Node, root int) int {
	if root < 0 {
		return 0
	}
	return 1 + max(height(nodes, nodes[root].left), height(nodes, nodes[root].right))
}

func erase(nodes []Node, root, key int) int {
	if root < 0 {
		return root
	}
	if key < nodes[root].key {
		nodes[root].left = erase(nodes, nodes[root].left, key)
	} else if key > nodes[root].key {
		nodes[root].right = erase(nodes, nodes[root].right, key)
	} else {
		if nodes[root].left < 0 {
			return nodes[root].right
		}
		if nodes[root].right < 0 {
			return nodes[root].left
		}
		successor := nodes[root].right
		for nodes[successor].left >= 0 {
			successor = nodes[successor].left
		}
		nodes[root].key = nodes[successor].key
		nodes[root].right = erase(nodes, nodes[root].right, nodes[successor].key)
	}
	return root
}

func main() {
	nodes := []Node{}
	root := -1
	for _, key := range []int{50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34} {
		root = insert(&nodes, root, key)
	}
	for mode, label := range []string{"inorder", "preorder", "postorder"} {
		fmt.Printf("%s:", label)
		traverse(nodes, root, mode)
		fmt.Println()
	}
	queue := []int{root}
	fmt.Print("levelorder:")
	for head := 0; head < len(queue); head++ {
		v := queue[head]
		fmt.Printf(" %d", nodes[v].key)
		if nodes[v].left >= 0 {
			queue = append(queue, nodes[v].left)
		}
		if nodes[v].right >= 0 {
			queue = append(queue, nodes[v].right)
		}
	}
	fmt.Printf("\nheight: %d\n", height(nodes, root))
	root = erase(nodes, root, 6)
	root = erase(nodes, root, 27)
	fmt.Print("preorder after deletions:")
	traverse(nodes, root, 1)
	fmt.Printf("\nheight after deletions: %d\n", height(nodes, root))
}
