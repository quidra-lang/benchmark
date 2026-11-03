'use strict';

class Trie {
    constructor() {
        this.root = { children: new Map(), terminal: false };
        this.nodes = 1;
        this.words = 0;
    }

    add(word) {
        let node = this.root;
        for (const letter of word) {
            if (!node.children.has(letter)) {
                node.children.set(letter, { children: new Map(), terminal: false });
                this.nodes++;
            }
            node = node.children.get(letter);
        }
        if (node.terminal) return false;
        node.terminal = true;
        this.words++;
        return true;
    }

    find(prefix) {
        let node = this.root;
        for (const letter of prefix) {
            node = node.children.get(letter);
            if (!node) return null;
        }
        return node;
    }

    has(word) {
        const node = this.find(word);
        return node !== null && node.terminal;
    }

    anagrams(rack) {
        const counts = new Map();
        for (const tile of rack) counts.set(tile, (counts.get(tile) || 0) + 1);
        const result = [];
        function visit(node, word) {
            if (node.terminal) result.push(word);
            for (const [letter, child] of node.children) {
                const tile = (counts.get(letter) || 0) > 0 ? letter : '?';
                if ((counts.get(tile) || 0) === 0) continue;
                counts.set(tile, counts.get(tile) - 1);
                visit(child, word + letter);
                counts.set(tile, counts.get(tile) + 1);
            }
        }
        visit(this.root, '');
        return result;
    }
}

module.exports = { Trie };
