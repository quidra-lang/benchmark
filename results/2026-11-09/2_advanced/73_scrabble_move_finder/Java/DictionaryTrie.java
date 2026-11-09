import java.util.*;
final class DictionaryTrie {
    static final class Node {
        Node[] children = new Node[26];
        boolean terminal;
    }
    final Node root = new Node();
    int nodes = 1, words;
    boolean add(String word) {
        Node node = root;
        for (char letter : word.toCharArray()) {
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
    Node prefix(String word) {
        Node node = root;
        for (char letter : word.toCharArray()) {
            node = node.children[letter - 'A'];
            if (node == null)
                return null;
        }
        return node;
    }
    boolean contains(String word) {
        Node node = prefix(word);
        return node != null && node.terminal;
    }
    void visit(Node node, String word, int[] counts, List<String> result) {
        if (node.terminal)
            result.add(word);
        for (int i = 0; i < 26; i++)
            if (node.children[i] != null) {
                char letter = (char)('A' + i);
                char tile = counts[letter] > 0 ? letter : '?';
                if (counts[tile] > 0) {
                    counts[tile]--;
                    visit(node.children[i], word + letter, counts, result);
                    counts[tile]++;
                }
            }
    }
    List<String> anagrams(String rack) {
        int[] counts = new int[128];
        for (char c : rack.toCharArray())
            counts[c]++;
        List<String> result = new ArrayList<>();
        visit(root, "", counts, result);
        return result;
    }
}
