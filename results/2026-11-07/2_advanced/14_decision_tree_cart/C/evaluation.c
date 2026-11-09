#include "cart.h"

bool is_leaf(const TreeView *tree, const Node *node) { return !node->branch || tree->cuts[node->number]; }
Nodes preorder(const TreeView *tree, const Node *start) {
    Nodes result = {0}, pending = { .items = {start ? start : tree->root}, .count = 1 };
    while (pending.count) {
        const Node *node = pending.items[--pending.count];
        result.items[result.count++] = node;
        if (!is_leaf(tree, node)) {
            pending.items[pending.count++] = node->right;
            pending.items[pending.count++] = node->left;
        }
    }
    return result;
}
Nodes leaves(const TreeView *tree, const Node *start) {
    Nodes nodes = preorder(tree, start), result = {0};
    for (int i = 0; i < nodes.count; ++i) if (is_leaf(tree, nodes.items[i])) result.items[result.count++] = nodes.items[i];
    return result;
}
int tree_depth(const TreeView *tree) {
    Nodes nodes = leaves(tree, NULL);
    int result = 0;
    for (int i = 0; i < nodes.count; ++i) if (nodes.items[i]->depth > result) result = nodes.items[i]->depth;
    return result;
}
Integer training_errors(const TreeView *tree) {
    Nodes nodes = leaves(tree, NULL);
    Integer result = 0;
    for (int i = 0; i < nodes.count; ++i) result += nodes.items[i]->stats.errors;
    return result;
}
Route route_row(const Dataset *data, const TreeView *tree, const Row *row) {
    Route result = {0};
    const Node *node = tree->root;
    for (;;) {
        result.path[result.count] = node;
        if (is_leaf(tree, node)) { result.leaf = node; return result; }
        bool left = node->default_left;
        Method method = DEFAULT;
        if (row->values[node->split.attribute] >= 0) {
            left = goes_left(data, node->split, row);
            method = PRIMARY;
        } else {
            for (int i = 0; i < node->surrogate_count; ++i) {
                Surrogate surrogate = node->surrogates[i];
                if (row->values[surrogate.split.attribute] < 0) continue;
                left = goes_left(data, surrogate.split, row) == surrogate.forward;
                method = SURROGATE;
                break;
            }
        }
        result.steps[result.count++] = (Step){node, left, method};
        node = left ? node->left : node->right;
    }
}
int predict(const Dataset *data, const TreeView *tree, const Row *row) { return route_row(data, tree, row).leaf->stats.prediction; }
Integer correct_count(const Dataset *data, const TreeView *tree, Rows rows) {
    Integer result = 0;
    for (int i = 0; i < rows.count; ++i) if (predict(data, tree, rows.items[i]) == rows.items[i]->label) ++result;
    return result;
}
char *real_text(double value, int places) {
    char *result = format("%.*f", places, value);
    return result[0] == '-' && strtod(result, NULL) == 0 ? result + 1 : result;
}
char *ratio(Integer numerator, Integer denominator) {
    return denominator ? format("%lld/%lld %s", numerator, denominator, real_text((double)numerator / denominator, 4)) : "0/0 -";
}
char *fraction(Fraction value, int places) {
    if (!value.denominator) return "- -";
    Integer a = value.numerator < 0 ? -value.numerator : value.numerator, b = value.denominator;
    while (b) { Integer remainder = a % b; a = b; b = remainder; }
    return format("%lld/%lld %s", value.numerator / a, value.denominator / a, real_text((double)value.numerator / value.denominator, places));
}
Lines classification(const Dataset *data, const char *title, Rows rows, const int *predictions) {
    Integer matrix[6][6] = {{0}}, correct = 0;
    for (int i = 0; i < rows.count; ++i) {
        ++matrix[rows.items[i]->label][predictions[i]];
        if (rows.items[i]->label == predictions[i]) ++correct;
    }
    Lines result = {0};
    add_line(&result, "confusion %s correct %lld/%d accuracy %s", title, correct, rows.count, fraction((Fraction){correct, rows.count}, 4));
    char *header = "actual\\predicted";
    for (int k = 0; k < data->class_count; ++k) header = format("%s %s", header, data->classes[k]);
    add_line(&result, "%s", header);
    for (int k = 0; k < data->class_count; ++k) add_line(&result, "%s %s", data->classes[k], counts_text(matrix[k], data->class_count));
    double macro = 0;
    int available = 0;
    for (int k = 0; k < data->class_count; ++k) {
        Integer hits = matrix[k][k], predicted = 0, support = 0;
        for (int j = 0; j < data->class_count; ++j) { predicted += matrix[j][k]; support += matrix[k][j]; }
        add_line(&result, "class %s precision %s recall %s f1 %s support %lld", data->classes[k], fraction((Fraction){hits, predicted}, 4), fraction((Fraction){hits, support}, 4), fraction((Fraction){2 * hits, predicted + support}, 4), support);
        if (predicted + support) { macro += (double)(2 * hits) / (predicted + support); ++available; }
    }
    add_line(&result, "macro_f1 %s", available ? real_text(macro / available, 4) : "-");
    return result;
}
