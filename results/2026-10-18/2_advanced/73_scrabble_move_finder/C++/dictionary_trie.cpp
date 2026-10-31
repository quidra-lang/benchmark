#include "scrabble.hpp"
bool Trie::add(const std::string &word) {
    int node = 0;
    for (char letter : word) {
        int index = letter - 'A';
        if (nodes[node].children[index] < 0) {
            int child = int(nodes.size());
            nodes[node].children[index] = child;
            nodes.emplace_back();
        }
        node = nodes[node].children[index];
    }
    if (nodes[node].terminal)
        return false;
    nodes[node].terminal = true;
    ++words;
    return true;
}
int Trie::prefix(const std::string &word) const {
    int node = 0;
    for (char letter : word) {
        node = nodes[node].children[letter - 'A'];
        if (node < 0)
            break;
    }
    return node;
}
bool Trie::contains(const std::string &word) const {
    int node = prefix(word);
    return node >= 0 && nodes[node].terminal;
}
Names Trie::anagrams(const std::string &rack) const {
    Counts counts{};
    for (char tile : rack)
        ++counts[tile_index(tile)];
    Names out;
    std::function<void(int, std::string)> visit = [&](int node, std::string word) {
        if (nodes[node].terminal)
            out.push_back(word);
        for (int letter = 0; letter < 26; ++letter) {
            int child = nodes[node].children[letter];
            if (child < 0)
                continue;
            int tile = counts[letter] ? letter : 26;
            if (counts[tile]) {
                --counts[tile];
                visit(child, word + char('A' + letter));
                ++counts[tile];
            }
        }
    };
    visit(0, "");
    return out;
}
