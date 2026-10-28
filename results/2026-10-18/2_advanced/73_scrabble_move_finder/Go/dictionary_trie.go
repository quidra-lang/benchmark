package main

type TrieNode struct {
	Children [26]int
	Terminal bool
}
type Trie struct {
	Nodes []TrieNode
	Words int
}

func newTrieNode() TrieNode {
	var n TrieNode
	for i := range n.Children {
		n.Children[i] = -1
	}
	return n
}
func newTrie() Trie { return Trie{Nodes: []TrieNode{newTrieNode()}} }
func (t *Trie) add(word string) bool {
	node := 0
	for i := range word {
		letter := int(word[i] - 'A')
		next := t.Nodes[node].Children[letter]
		if next < 0 {
			next = len(t.Nodes)
			t.Nodes = append(t.Nodes,
				newTrieNode())
			t.Nodes[node].Children[letter] = next
		}
		node = next
	}
	if t.Nodes[node].Terminal {
		return false
	}
	t.Nodes[node].Terminal = true
	t.Words++
	return true
}
func (t Trie) find(prefix string) int {
	node := 0
	for i := range prefix {
		c := upper(prefix[i])
		node = t.Nodes[node].Children[c-'A']
		if node < 0 {
			return -1
		}
	}
	return node
}
func (t Trie) contains(word string) bool {
	node := t.find(word)
	return node >= 0 && t.Nodes[node].Terminal
}
func (t Trie) anagrams(rack string) []string {
	counts := collectionCounts(rack)
	var words []string
	var visit func(int,
		string)
	visit = func(node int, prefix string) {
		if t.Nodes[node].Terminal {
			words = append(words, prefix)
		}
		for letter, next := range t.Nodes[node].Children {
			if next < 0 {
				continue
			}
			tile := letter
			if counts[tile] == 0 {
				tile = 26
			}
			if counts[tile] == 0 {
				continue
			}
			counts[tile]--
			visit(next,
				prefix+string(byte('A'+letter)))
			counts[tile]++
		}
	}
	visit(0, "")
	return words
}
