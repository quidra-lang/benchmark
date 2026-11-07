#include "archive.hpp"
static std::vector<int> tree_lengths(const std::vector<int> &frequencies) {
    struct Node {
        int weight, minimum, left = -1, right = -1, symbol = -1;
    };
    std::vector<Node> nodes;
    std::vector<int> queue;
    std::vector<int> lengths(frequencies.size());
    for (std::size_t s = 0; s < frequencies.size(); ++s)
        if (frequencies[s] > 0) {
            queue.push_back(nodes.size());
            nodes.push_back({frequencies[s], int(s), -1, -1, int(s)});
        }
    if (queue.empty())
        return lengths;
    if (queue.size() == 1) {
        lengths[nodes[queue[0]].symbol] = 1;
        return lengths;
    }
    auto less = [&](int a, int b) {
        return std::tie(nodes[a].weight, nodes[a].minimum) < std::tie(nodes[b].weight, nodes[b].minimum);
    };
    while (queue.size() > 1) {
        std::sort(queue.begin(), queue.end(), less);
        const int a = queue[0], b = queue[1];
        queue.erase(queue.begin(), queue.begin() + 2);
        queue.push_back(nodes.size());
        nodes.push_back(
            {nodes[a].weight + nodes[b].weight, std::min(nodes[a].minimum, nodes[b].minimum), a, b, -1});
    }
    std::vector<std::pair<int, int>> stack = {{queue[0], 0}};
    while (!stack.empty()) {
        const auto entry = stack.back();
        stack.pop_back();
        const Node &node = nodes[entry.first];
        if (node.symbol >= 0)
            lengths[node.symbol] = entry.second;
        else {
            stack.push_back({node.right, entry.second + 1});
            stack.push_back({node.left, entry.second + 1});
        }
    }
    return lengths;
}
Huffman huffman_lengths(std::vector<int> frequencies, int maximum) {
    Huffman out;
    while (true) {
        out.lengths = tree_lengths(frequencies);
        if (*std::max_element(out.lengths.begin(), out.lengths.end()) <= maximum)
            return out;
        for (int &frequency : frequencies)
            frequency = (frequency + 1) / 2;
        ++out.halvings;
    }
}
std::vector<int> canonical_codes(const std::vector<int> &lengths) {
    std::vector<int> order, codes(lengths.size());
    for (std::size_t s = 0; s < lengths.size(); ++s)
        if (lengths[s] > 0)
            order.push_back(s);
    std::sort(order.begin(), order.end(),
              [&](int a, int b) { return std::make_pair(lengths[a], a) < std::make_pair(lengths[b], b); });
    int code = 0, previous = 0;
    for (int symbol : order) {
        if (previous)
            code = (code + 1) << (lengths[symbol] - previous);
        codes[symbol] = code;
        previous = lengths[symbol];
    }
    return codes;
}
