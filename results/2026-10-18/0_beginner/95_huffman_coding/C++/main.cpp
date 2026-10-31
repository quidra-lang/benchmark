#include <algorithm>
#include <array>
#include <iostream>
#include <string>
#include <vector>

struct Node {
    int weight, minimum, left, right, symbol;
};

int pop(std::vector<int> &roots, const std::vector<Node> &nodes) {
    auto best = std::min_element(roots.begin(), roots.end(), [&nodes](int x, int y) {
        const Node &a = nodes[x], &b = nodes[y];
        return a.weight < b.weight || (a.weight == b.weight && a.minimum < b.minimum);
    });
    int result = *best;
    roots.erase(best);
    return result;
}

void assign(const std::vector<Node> &nodes, int root, const std::string &prefix,
            std::array<std::string, 128> &codes) {
    if (nodes[root].symbol >= 0) {
        codes[nodes[root].symbol] = prefix;
        return;
    }
    assign(nodes, nodes[root].left, prefix + "0", codes);
    assign(nodes, nodes[root].right, prefix + "1", codes);
}

int main() {
    std::string text = "she sells sea shells by the sea shore";
    std::array<int, 128> freq{};
    for (unsigned char c : text)
        ++freq[c];
    std::vector<Node> nodes;
    std::vector<int> roots;
    for (int c = 0; c < 128; ++c) {
        if (freq[c]) {
            roots.push_back(static_cast<int>(nodes.size()));
            nodes.push_back({freq[c], c, -1, -1, c});
        }
    }
    while (roots.size() > 1) {
        int left = pop(roots, nodes);
        int right = pop(roots, nodes);
        roots.push_back(static_cast<int>(nodes.size()));
        nodes.push_back({nodes[left].weight + nodes[right].weight,
                         std::min(nodes[left].minimum, nodes[right].minimum), left, right, -1});
    }
    std::array<std::string, 128> codes;
    assign(nodes, roots[0], "", codes);
    int bits = 0;
    for (int c = 0; c < 128; ++c) {
        if (freq[c]) {
            std::cout << "'" << static_cast<char>(c) << "' freq=" << freq[c]
                      << " code=" << codes[c] << '\n';
            bits += freq[c] * static_cast<int>(codes[c].size());
        }
    }
    std::cout << "encoded bits: " << bits << "\nfixed 8-bit: " << text.size() * 8 << '\n';
}
