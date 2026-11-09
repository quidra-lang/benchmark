#include "cart.h"

static Integer decide(const Node *node, const Integer *visits, const Integer *errors, PruningResult *result) {
    Integer leaf_error = errors[node->number];
    if (!node->branch) return leaf_error;
    Integer left = decide(node->left, visits, errors, result);
    Integer right = decide(node->right, visits, errors, result);
    Integer subtree = left + right;
    bool pruned = leaf_error <= subtree;
    result->decisions[result->count++] = (Decision){node, visits[node->number], leaf_error, subtree, pruned};
    if (pruned) result->tree.cuts[node->number] = true;
    return pruned ? leaf_error : subtree;
}
void reduced_error(const Dataset *data, const Node *root, Rows rows, PruningResult *result) {
    *result = (PruningResult){ .tree = {.root = root} };
    TreeView grown = {.root = root};
    Integer visits[2048] = {0}, errors[2048] = {0};
    for (int i = 0; i < rows.count; ++i) {
        Route path = route_row(data, &grown, rows.items[i]);
        for (int j = 0; j <= path.count; ++j) {
            const Node *node = path.path[j];
            ++visits[node->number];
            if (rows.items[i]->label != node->stats.prediction) ++errors[node->number];
        }
    }
    decide(root, visits, errors, result);
}
Sequence cost_complexity(const Node *root) {
    Sequence sequence = { .items = allocate(1000 * sizeof(SequenceEntry)), .count = 1 };
    TreeView tree = {.root = root};
    sequence.items[0] = (SequenceEntry){tree, {0, 1}};
    while (!is_leaf(&tree, root)) {
        Nodes nodes = preorder(&tree, NULL);
        Fraction strengths[1000], minimum = {0, 1};
        bool found = false;
        for (int i = 0; i < nodes.count; ++i) {
            const Node *node = nodes.items[i];
            if (is_leaf(&tree, node)) continue;
            Nodes descendants = leaves(&tree, node);
            Integer errors = 0;
            for (int j = 0; j < descendants.count; ++j) errors += descendants.items[j]->stats.errors;
            strengths[i] = (Fraction){node->stats.errors - errors, descendants.count - 1};
            if (!found || compare(strengths[i], minimum) < 0) { minimum = strengths[i]; found = true; }
        }
        bool weakest[2048] = {false};
        for (int i = 0; i < nodes.count; ++i)
            if (!is_leaf(&tree, nodes.items[i]) && !compare(strengths[i], minimum)) weakest[nodes.items[i]->number] = true;
        for (int i = 0; i < 2048; ++i) if (weakest[i]) tree.cuts[i] = true;
        sequence.items[sequence.count++] = (SequenceEntry){tree, minimum};
    }
    return sequence;
}
