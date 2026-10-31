part of 'main.dart';

class TrieNode {
  final List<int> children = List.filled(26, -1);
  bool terminal = false;
}

class Trie {
  final List<TrieNode> nodes = [TrieNode()];
  int words = 0;
  bool add(String word) {
    var node = 0;
    for (final code in word.codeUnits) {
      final letter = code - 65;
      var next = nodes[node].children[letter];
      if (next < 0) {
        next = nodes.length;
        nodes.add(TrieNode());
        nodes[node].children[letter] = next;
      }
      node = next;
    }
    if (nodes[node].terminal) return false;
    nodes[node].terminal = true;
    words++;
    return true;
  }

  int find(String prefix) {
    var node = 0;
    for (final code in prefix.toUpperCase().codeUnits) {
      node = nodes[node].children[code - 65];
      if (node < 0) return -1;
    }
    return node;
  }

  bool contains(String word) {
    final node = find(word);
    return node >= 0 && nodes[node].terminal;
  }

  List<String> anagrams(String rack) {
    final counts = collectionCounts(rack), result = <String>[];
    void visit(int node, String prefix) {
      if (nodes[node].terminal) result.add(prefix);
      for (var letter = 0; letter < 26; letter++) {
        final next = nodes[node].children[letter];
        if (next < 0) continue;
        final tile = counts[letter] > 0 ? letter : 26;
        if (counts[tile] == 0) continue;
        counts[tile]--;
        visit(next, prefix + String.fromCharCode(65 + letter));
        counts[tile]++;
      }
    }

    visit(0, '');
    return result;
  }
}
