#include "cart.hpp"

bool goesLeft(Split split, const Row& row, const std::vector<Attribute>& attributes) {
    Integer value = row.values[split.attribute];
    return attributes[split.attribute].integer ? 2 * value <= split.point : value == split.point;
}
std::vector<Split> candidates(const Rows& rows, const std::vector<Attribute>& attributes, int attribute) {
    std::set<Integer> distinct;
    for (const Row* row : rows) distinct.insert(row->values[attribute]);
    std::vector<Split> result;
    if (distinct.size() < 2) return result;
    Counts values(distinct.begin(), distinct.end());
    if (attributes[attribute].integer) {
        for (std::size_t i = 1; i < values.size(); ++i) result.push_back({attribute, values[i - 1] + values[i]});
    } else {
        for (Integer value : values) result.push_back({attribute, value});
    }
    return result;
}
std::optional<Candidate> TreeBuilder::bestForAttribute(const Rows& rows, int attribute) const {
    std::optional<Candidate> best;
    for (Split split : candidates(rows, data.attributes, attribute)) {
        Rows left, right;
        for (const Row* row : rows) (goesLeft(split, *row, data.attributes) ? left : right).push_back(row);
        if (left.size() < static_cast<std::size_t>(data.settings.minLeaf) || right.size() < static_cast<std::size_t>(data.settings.minLeaf)) continue;
        Fraction value = evaluationValue(statistics(left, static_cast<int>(data.classes.size())), statistics(right, static_cast<int>(data.classes.size())));
        if (!best || compare(value, best->value) > 0) best = Candidate{split, std::move(left), std::move(right), value};
    }
    return best;
}
std::vector<Surrogate> TreeBuilder::surrogates(const Rows& rows, const Candidate& primary) const {
    std::vector<Surrogate> result;
    for (int a = 0; a < static_cast<int>(data.attributes.size()); ++a) {
        if (a == primary.split.attribute) continue;
        std::optional<Surrogate> best;
        for (Split split : candidates(rows, data.attributes, a)) {
            Integer agreement = 0;
            for (const Row* row : rows) if (goesLeft(split, *row, data.attributes) == goesLeft(primary.split, *row, data.attributes)) ++agreement;
            Integer reversed = static_cast<Integer>(rows.size()) - agreement;
            Surrogate surrogate{split, agreement >= reversed, std::max(agreement, reversed)};
            if (!best || surrogate.score > best->score) best = surrogate;
        }
        if (best && best->score > static_cast<Integer>(std::max(primary.left.size(), primary.right.size()))) result.push_back(*best);
    }
    std::sort(result.begin(), result.end(), [](const Surrogate& a, const Surrogate& b) {
        return a.score != b.score ? a.score > b.score : a.split.attribute < b.split.attribute;
    });
    result.resize(std::min(result.size(), static_cast<std::size_t>(data.settings.maxSurrogates)));
    return result;
}
std::unique_ptr<Node> TreeBuilder::grow(const Rows& rows, int number, int depth) const {
    std::unique_ptr<Node> node = std::make_unique<Node>();
    node->number = number;
    node->depth = depth;
    node->stats = statistics(rows, static_cast<int>(data.classes.size()));
    if (!node->stats.errors || depth == data.settings.maxDepth || rows.size() < static_cast<std::size_t>(data.settings.minSplit)) return node;
    std::optional<Candidate> best;
    for (int a = 0; a < static_cast<int>(data.attributes.size()); ++a) {
        std::optional<Candidate> candidate = bestForAttribute(rows, a);
        if (candidate && (!best || compare(candidate->value, best->value) > 0)) best = std::move(candidate);
    }
    if (!best || !improves(best->value, node->stats)) return node;
    node->split = best->split;
    node->defaultLeft = best->left.size() >= best->right.size();
    node->surrogates = surrogates(rows, *best);
    node->left = grow(best->left, 2 * number, depth + 1);
    node->right = grow(best->right, 2 * number + 1, depth + 1);
    return node;
}
