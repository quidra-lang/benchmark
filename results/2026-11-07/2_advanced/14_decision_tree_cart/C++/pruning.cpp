#include "cart.hpp"

PruningResult reducedError(const Node* root, const Rows& rows, const std::vector<Attribute>& attributes) {
    PruningResult result{{root, {}}, {}};
    std::map<int, Integer> visits, errors;
    TreeView grown{root, {}};
    for (const Row* row : rows) for (const Node* node : grown.route(*row, attributes).path) {
        ++visits[node->number];
        if (row->label != node->stats.prediction) ++errors[node->number];
    }
    std::function<Integer(const Node*)> decide = [&](const Node* node) {
        Integer leafError = errors[node->number];
        if (!node->split) return leafError;
        Integer left = decide(node->left.get());
        Integer right = decide(node->right.get());
        Integer subtree = left + right;
        bool pruned = leafError <= subtree;
        result.decisions.push_back({node, visits[node->number], leafError, subtree, pruned});
        if (pruned) result.tree.cuts.insert(node->number);
        return pruned ? leafError : subtree;
    };
    decide(root);
    return result;
}
std::vector<SequenceEntry> costComplexity(const Node* root) {
    TreeView tree{root, {}};
    std::vector<SequenceEntry> sequence{{tree, {0, 1}}};
    while (!tree.isLeaf(root)) {
        std::vector<std::pair<int, Fraction>> candidates;
        for (const Node* node : tree.preorder()) {
            if (tree.isLeaf(node)) continue;
            std::vector<const Node*> leaves = tree.leaves(node);
            Integer errors = 0;
            for (const Node* leaf : leaves) errors += leaf->stats.errors;
            candidates.push_back({node->number, {node->stats.errors - errors, static_cast<Integer>(leaves.size()) - 1}});
        }
        Fraction minimum = candidates.front().second;
        for (const std::pair<int, Fraction>& candidate : candidates) if (compare(candidate.second, minimum) < 0) minimum = candidate.second;
        for (const std::pair<int, Fraction>& candidate : candidates) if (compare(candidate.second, minimum) == 0) tree.cuts.insert(candidate.first);
        sequence.push_back({tree, minimum});
    }
    return sequence;
}
