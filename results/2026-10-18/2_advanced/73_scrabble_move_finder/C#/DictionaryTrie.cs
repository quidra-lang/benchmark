using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
public sealed class DictionaryTrie {
    public sealed class Node {
        public Node[] children = new Node[26];
        public bool terminal;
    }
    public readonly Node root = new Node();
    public int nodes = 1, words;
    public bool Add(string word) {
        Node node = root;
        foreach (char letter in word.ToCharArray()) {
            int i = letter - 'A';
            if (node.children[i] == null) {
                node.children[i] = new Node();
                nodes++;
            }
            node = node.children[i];
        }
        if (node.terminal)
            return false;
        node.terminal = true;
        words++;
        return true;
    }
    public Node Prefix(string word) {
        Node node = root;
        foreach (char letter in word.ToCharArray()) {
            node = node.children[letter - 'A'];
            if (node == null)
                return null;
        }
        return node;
    }
    public bool Contains(string word) {
        Node node = Prefix(word);
        return node != null && node.terminal;
    }
    public void Visit(Node node, string word, int[] counts, List<string> result) {
        if (node.terminal)
            result.Add(word);
        for (int i = 0; i < 26; i++)
            if (node.children[i] != null) {
                char letter = (char)('A' + i);
                char tile = counts[letter] > 0 ? letter : '?';
                if (counts[tile] > 0) {
                    counts[tile]--;
                    Visit(node.children[i], word + letter, counts, result);
                    counts[tile]++;
                }
            }
    }
    public List<string> Anagrams(string rack) {
        int[] counts = new int[128];
        foreach (char c in rack.ToCharArray())
            counts[c]++;
        List<string> result = new();
        Visit(root, "", counts, result);
        return result;
    }
}
