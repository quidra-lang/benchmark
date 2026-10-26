#include "cart.hpp"
#include <cmath>
#include <iomanip>

bool TreeView::isLeaf(const Node* node) const { return !node->split || cuts.count(node->number); }
std::vector<const Node*> TreeView::preorder(const Node* start) const {
    std::vector<const Node*> result, pending{start ? start : root};
    while (!pending.empty()) {
        const Node* node = pending.back();
        pending.pop_back();
        result.push_back(node);
        if (!isLeaf(node)) {
            pending.push_back(node->right.get());
            pending.push_back(node->left.get());
        }
    }
    return result;
}
std::vector<const Node*> TreeView::leaves(const Node* start) const {
    std::vector<const Node*> result;
    for (const Node* node : preorder(start)) if (isLeaf(node)) result.push_back(node);
    return result;
}
int TreeView::depth() const {
    int result = 0;
    for (const Node* node : leaves()) result = std::max(result, node->depth);
    return result;
}
Integer TreeView::trainingErrors() const {
    Integer result = 0;
    for (const Node* node : leaves()) result += node->stats.errors;
    return result;
}
Route TreeView::route(const Row& row, const std::vector<Attribute>& attributes) const {
    Route result{};
    const Node* node = root;
    for (;;) {
        result.path.push_back(node);
        if (isLeaf(node)) {
            result.leaf = node;
            return result;
        }
        bool left = node->defaultLeft;
        Method method = Method::fallback;
        if (row.values[node->split->attribute] >= 0) {
            left = goesLeft(*node->split, row, attributes);
            method = Method::primary;
        } else {
            for (const Surrogate& surrogate : node->surrogates) {
                if (row.values[surrogate.split.attribute] < 0) continue;
                left = goesLeft(surrogate.split, row, attributes) == surrogate.forward;
                method = Method::surrogate;
                break;
            }
        }
        result.steps.push_back({node, left, method});
        node = left ? node->left.get() : node->right.get();
    }
}
int TreeView::predict(const Row& row, const std::vector<Attribute>& attributes) const { return route(row, attributes).leaf->stats.prediction; }
Integer TreeView::correct(const Rows& rows, const std::vector<Attribute>& attributes) const {
    Integer result = 0;
    for (const Row* row : rows) if (predict(*row, attributes) == row->label) ++result;
    return result;
}
std::string realText(double value, int places) {
    std::ostringstream stream;
    stream << std::fixed << std::setprecision(places) << value;
    std::string result = stream.str();
    if (std::stod(result) == 0 && result.front() == '-') result.erase(result.begin());
    return result;
}
std::string ratio(Integer numerator, Integer denominator) {
    return denominator ? text(numerator, '/', denominator, ' ', realText(static_cast<double>(numerator) / denominator)) : "0/0 -";
}
std::string fraction(Fraction value, int places) {
    if (!value.denominator) return "- -";
    Integer divisor = std::gcd(value.numerator, value.denominator);
    return text(value.numerator / divisor, '/', value.denominator / divisor, ' ', realText(static_cast<double>(value.numerator) / value.denominator, places));
}
Lines classification(const std::string& title, const Rows& rows, const std::vector<int>& predictions, const Lines& classes) {
    std::vector<Counts> matrix(classes.size(), Counts(classes.size()));
    Integer correct = 0;
    for (std::size_t i = 0; i < rows.size(); ++i) {
        ++matrix[rows[i]->label][predictions[i]];
        if (rows[i]->label == predictions[i]) ++correct;
    }
    Lines lines;
    add(lines, "confusion ", title, " correct ", correct, '/', rows.size(), " accuracy ", fraction({correct, static_cast<Integer>(rows.size())}));
    add(lines, "actual\\predicted ", join(classes));
    for (std::size_t k = 0; k < classes.size(); ++k) add(lines, classes[k], ' ', join(matrix[k]));
    double macro = 0;
    int available = 0;
    for (std::size_t k = 0; k < classes.size(); ++k) {
        Integer hits = matrix[k][k], predicted = 0, support = 0;
        for (std::size_t j = 0; j < classes.size(); ++j) {
            predicted += matrix[j][k];
            support += matrix[k][j];
        }
        add(lines, "class ", classes[k], " precision ", fraction({hits, predicted}), " recall ", fraction({hits, support}), " f1 ", fraction({2 * hits, predicted + support}), " support ", support);
        if (predicted + support) {
            macro += static_cast<double>(2 * hits) / (predicted + support);
            ++available;
        }
    }
    add(lines, "macro_f1 ", available ? realText(macro / available) : "-");
    return lines;
}
