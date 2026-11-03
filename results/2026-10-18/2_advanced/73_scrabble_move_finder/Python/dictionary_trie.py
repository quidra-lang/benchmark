"""Word trie with duplicate detection and rack-constrained anagrams."""

from collections import Counter


class Node:
    def __init__(self):
        self.children = {}
        self.terminal = False


class Trie:
    def __init__(self):
        self.root = Node()
        self.nodes, self.words = 1, 0

    def add(self, word):
        node = self.root
        for letter in word:
            if letter not in node.children:
                node.children[letter] = Node()
                self.nodes += 1
            node = node.children[letter]
        if node.terminal:
            return False
        node.terminal = True
        self.words += 1
        return True

    def prefix(self, word):
        node = self.root
        for letter in word:
            node = node.children.get(letter)
            if node is None:
                break
        return node

    def __contains__(self, word):
        node = self.prefix(word)
        return node is not None and node.terminal

    def anagrams(self, rack):
        counts, result = Counter(rack), []

        def visit(node, word):
            if node.terminal:
                result.append(word)
            for letter in sorted(node.children):
                tile = letter if counts[letter] else "?"
                if counts[tile]:
                    counts[tile] -= 1
                    visit(node.children[letter], word + letter)
                    counts[tile] += 1

        visit(self.root, "")
        return result
