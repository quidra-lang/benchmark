#include "cart.hpp"
#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <stdexcept>

class Minstd {
    Integer state;
public:
    explicit Minstd(Integer seed) : state(seed) {}
    Integer draw() { state = 48271 * state % 2147483647; return state; }
};
static std::string halfText(Integer value) { return text(value / 2, '.', value % 2 ? '5' : '0'); }
static std::string splitText(Split split, bool left, const Dataset& data) {
    const Attribute& attribute = data.attributes[split.attribute];
    return attribute.integer ? text(attribute.name, left ? " <= " : " > ", halfText(split.point))
                             : text(attribute.name, left ? " = " : " != ", attribute.values[split.point]);
}
struct Condition {
    int attribute;
    std::optional<Integer> lower, upper, equal;
    std::set<Integer> excluded;
};
struct Rule {
    const Node* leaf;
    std::vector<Condition> conditions, generalized;
    std::vector<int> removed;
};
class Analysis {
    Dataset data;
    Rows train, validation, test;
    TreeBuilder builder;
    std::unique_ptr<Node> root;
    TreeView grown, pruned;
    std::vector<Decision> decisions;
    std::vector<Route> grownRoutes, prunedRoutes;
    std::vector<Rule> rules;
    std::map<std::string, std::vector<int>> predictions;
    std::vector<Counts> testVotes;
    Lines crossLines, depthLines, complexityLines, bagLines;
public:
    explicit Analysis(Dataset input)
        : data(std::move(input)), train(rowPointers(data.train)), validation(rowPointers(data.validation)), test(rowPointers(data.test)), builder(data), root(builder.grow(train)), grown{root.get(), {}}, pruned{root.get(), {}} {
        PruningResult result = reducedError(root.get(), validation, data.attributes);
        pruned = std::move(result.tree);
        decisions = std::move(result.decisions);
        for (const Row* row : test) {
            grownRoutes.push_back(grown.route(*row, data.attributes));
            prunedRoutes.push_back(pruned.route(*row, data.attributes));
        }
        predictions["grown"] = predict(grown);
        predictions["pruned"] = predict(pruned);
        crossValidation();
        complexitySelection();
        bagging();
        collectRules(pruned.root, {});
        for (Rule& rule : rules) generalize(rule);
    }
    std::vector<int> predict(const TreeView& tree) const {
        std::vector<int> result;
        for (const Row* row : test) result.push_back(tree.predict(*row, data.attributes));
        return result;
    }
    std::string accuracy(const TreeView& tree, const Rows& rows) const { return ratio(tree.correct(rows, data.attributes), static_cast<Integer>(rows.size())); }
    static TreeView atDepth(const Node* root, int depth) {
        TreeView tree{root, {}};
        for (const Node* node : tree.preorder()) if (node->split && node->depth == depth) tree.cuts.insert(node->number);
        return tree;
    }
    void crossValidation() {
        std::vector<std::unique_ptr<Node>> roots;
        std::vector<Rows> held;
        Integer total = 0;
        int size = static_cast<int>(train.size());
        add(crossLines, "cross_validation folds ", data.settings.folds);
        for (int fold = 0; fold < data.settings.folds; ++fold) {
            int first = fold * size / data.settings.folds;
            int end = (fold + 1) * size / data.settings.folds;
            Rows training(train.begin(), train.begin() + first);
            training.insert(training.end(), train.begin() + end, train.end());
            held.emplace_back(train.begin() + first, train.begin() + end);
            roots.push_back(builder.grow(training));
            TreeView tree{roots.back().get(), {}};
            Integer correct = tree.correct(held.back(), data.attributes);
            total += correct;
            add(crossLines, "fold ", fold + 1, " rows ", first + 1, '-', end, " leaves ", tree.leaves().size(), " correct ", ratio(correct, end - first));
        }
        add(crossLines, "cv accuracy ", ratio(total, size));
        depthLines.push_back("depth_selection");
        int selected = 0;
        Integer maximum = -1;
        for (int depth = 0; depth <= data.settings.maxDepth; ++depth) {
            Integer correct = 0;
            for (std::size_t f = 0; f < roots.size(); ++f) correct += atDepth(roots[f].get(), depth).correct(held[f], data.attributes);
            TreeView tree = atDepth(root.get(), depth);
            if (correct > maximum) {
                maximum = correct;
                selected = depth;
            }
            add(depthLines, "depth ", depth, " leaves ", tree.leaves().size(), " cv ", ratio(correct, size), " train ", accuracy(tree, train), " validation ", accuracy(tree, validation), " test ", accuracy(tree, test));
        }
        TreeView selectedTree = atDepth(root.get(), selected);
        add(depthLines, "selected depth ", selected, " leaves ", selectedTree.leaves().size(), " test ", accuracy(selectedTree, test));
        predictions["depth"] = predict(selectedTree);
    }
    void complexitySelection() {
        std::vector<SequenceEntry> sequence = costComplexity(root.get());
        std::size_t selected = 0;
        Integer minimum = static_cast<Integer>(validation.size()) + 1;
        complexityLines.push_back("cost_complexity");
        for (std::size_t i = 0; i < sequence.size(); ++i) {
            const SequenceEntry& entry = sequence[i];
            Integer errors = static_cast<Integer>(validation.size()) - entry.tree.correct(validation, data.attributes);
            if (errors <= minimum) {
                selected = i;
                minimum = errors;
            }
            add(complexityLines, "subtree ", i, " alpha ", fraction({entry.alpha.numerator, entry.alpha.denominator * static_cast<Integer>(train.size())}, 6), " leaves ", entry.tree.leaves().size(), " train_errors ", entry.tree.trainingErrors(), " validation_errors ", errors);
        }
        const TreeView& tree = sequence[selected].tree;
        add(complexityLines, "selected subtree ", selected, " leaves ", tree.leaves().size(), " test ", accuracy(tree, test));
        predictions["cost_complexity"] = predict(tree);
    }
    void bagging() {
        Minstd generator(data.settings.bagSeed);
        std::vector<Counts> oobVotes(train.size(), Counts(data.classes.size()));
        testVotes.assign(test.size(), Counts(data.classes.size()));
        add(bagLines, "bagging trees ", data.settings.bagTrees, " seed ", data.settings.bagSeed);
        for (int b = 0; b < data.settings.bagTrees; ++b) {
            Rows sample;
            std::set<std::size_t> sampled;
            for (std::size_t i = 0; i < train.size(); ++i) {
                std::size_t index = static_cast<std::size_t>(generator.draw() % static_cast<Integer>(train.size()));
                sampled.insert(index);
                sample.push_back(train[index]);
            }
            std::unique_ptr<Node> bagRoot = builder.grow(sample);
            TreeView tree{bagRoot.get(), {}};
            Integer correct = 0, count = 0;
            for (std::size_t i = 0; i < train.size(); ++i) if (!sampled.count(i)) {
                int prediction = tree.predict(*train[i], data.attributes);
                ++oobVotes[i][prediction];
                ++count;
                if (prediction == train[i]->label) ++correct;
            }
            for (std::size_t i = 0; i < test.size(); ++i) ++testVotes[i][tree.predict(*test[i], data.attributes)];
            add(bagLines, "bag ", b + 1, " distinct ", sampled.size(), " leaves ", tree.leaves().size(), " oob ", ratio(correct, count));
        }
        Integer voted = 0, correct = 0;
        for (std::size_t i = 0; i < train.size(); ++i) {
            if (!std::accumulate(oobVotes[i].begin(), oobVotes[i].end(), Integer{0})) continue;
            ++voted;
            if (majority(oobVotes[i]) == train[i]->label) ++correct;
        }
        add(bagLines, "oob accuracy ", ratio(correct, voted), " unvoted ", static_cast<Integer>(train.size()) - voted);
        for (const Counts& votes : testVotes) predictions["bagging"].push_back(majority(votes));
        Lines classificationLines = classification("bagging test", test, predictions["bagging"], data.classes);
        bagLines.insert(bagLines.end(), classificationLines.begin(), classificationLines.end());
    }
    void collectRules(const Node* node, const std::vector<std::pair<Split, bool>>& steps) {
        if (!pruned.isLeaf(node)) {
            std::vector<std::pair<Split, bool>> left = steps, right = steps;
            left.emplace_back(*node->split, true);
            right.emplace_back(*node->split, false);
            collectRules(node->left.get(), left);
            collectRules(node->right.get(), right);
            return;
        }
        Rule rule{node, {}, {}, {}};
        for (int a = 0; a < static_cast<int>(data.attributes.size()); ++a) {
            Condition condition{a, {}, {}, {}, {}};
            bool found = false;
            for (const std::pair<Split, bool>& step : steps) {
                if (step.first.attribute != a) continue;
                found = true;
                Integer point = step.first.point;
                if (data.attributes[a].integer) {
                    if (step.second) condition.upper = condition.upper ? std::min(*condition.upper, point) : point;
                    else condition.lower = condition.lower ? std::max(*condition.lower, point) : point;
                } else if (step.second) condition.equal = point;
                else condition.excluded.insert(point);
            }
            if (found) rule.conditions.push_back(std::move(condition));
        }
        rules.push_back(std::move(rule));
    }
    bool holds(const Condition& condition, const Row& row) const {
        Integer value = row.values[condition.attribute];
        if (value < 0) return false;
        if (data.attributes[condition.attribute].integer) return (!condition.lower || 2 * value > *condition.lower) && (!condition.upper || 2 * value <= *condition.upper);
        return condition.equal ? value == *condition.equal : !condition.excluded.count(value);
    }
    std::pair<Integer, Integer> coverage(const std::vector<Condition>& conditions, const Rows& rows, int label) const {
        Integer hits = 0, count = 0;
        for (const Row* row : rows) {
            if (!std::all_of(conditions.begin(), conditions.end(), [&](const Condition& condition) { return holds(condition, *row); })) continue;
            ++count;
            if (row->label == label) ++hits;
        }
        return {hits, count};
    }
    Fraction laplace(const std::vector<Condition>& conditions, int label) const {
        std::pair<Integer, Integer> counts = coverage(conditions, validation, label);
        return {counts.first + 1, counts.second + static_cast<Integer>(data.classes.size())};
    }
    void generalize(Rule& rule) const {
        rule.generalized = rule.conditions;
        while (!rule.generalized.empty()) {
            Fraction current = laplace(rule.generalized, rule.leaf->stats.prediction);
            std::optional<Fraction> best;
            std::size_t chosen = 0;
            for (std::size_t i = 0; i < rule.generalized.size(); ++i) {
                std::vector<Condition> trial = rule.generalized;
                trial.erase(trial.begin() + static_cast<std::ptrdiff_t>(i));
                Fraction estimate = laplace(trial, rule.leaf->stats.prediction);
                if (!best || compare(estimate, *best) > 0) {
                    best = estimate;
                    chosen = i;
                }
            }
            if (compare(*best, current) < 0) break;
            rule.removed.push_back(rule.generalized[chosen].attribute);
            rule.generalized.erase(rule.generalized.begin() + static_cast<std::ptrdiff_t>(chosen));
        }
    }
    std::string conditionText(const Condition& condition) const {
        const Attribute& attribute = data.attributes[condition.attribute];
        if (attribute.integer) {
            if (condition.lower && condition.upper) return text(halfText(*condition.lower), " < ", attribute.name, " <= ", halfText(*condition.upper));
            if (condition.lower) return text(attribute.name, " > ", halfText(*condition.lower));
            return text(attribute.name, " <= ", halfText(*condition.upper));
        }
        if (condition.equal) return text(attribute.name, " = ", attribute.values[*condition.equal]);
        Lines names;
        for (Integer value : condition.excluded) names.push_back(attribute.values[value]);
        return names.size() == 1 ? text(attribute.name, " != ", names.front()) : text(attribute.name, " not in {", join(names, ","), '}');
    }
    std::string conditionsText(const std::vector<Condition>& conditions) const {
        Lines parts;
        for (const Condition& condition : conditions) parts.push_back(conditionText(condition));
        return parts.empty() ? "true" : join(parts, " and ");
    }
    Lines treeLines(const TreeView& tree) const {
        Lines lines;
        std::function<void(const Node*, const std::string&)> visit = [&](const Node* node, const std::string& condition) {
            std::string line = text(std::string(2 * node->depth, ' '), node->number, ' ', condition, " n ", node->stats.size, " counts ", join(node->stats.counts));
            if (tree.isLeaf(node)) line += " leaf " + data.classes[node->stats.prediction];
            lines.push_back(line);
            if (!tree.isLeaf(node)) {
                visit(node->left.get(), splitText(*node->split, true, data));
                visit(node->right.get(), splitText(*node->split, false, data));
            }
        };
        visit(tree.root, "root");
        lines.push_back("");
        add(lines, "nodes ", tree.preorder().size(), " leaves ", tree.leaves().size(), " depth ", tree.depth(), " errors ", ratio(tree.trainingErrors(), static_cast<Integer>(train.size())));
        for (int level = 0; level <= tree.depth(); ++level) {
            Integer nodes = 0, leaves = 0, rows = 0, errors = 0;
            for (const Node* node : tree.preorder()) if (node->depth == level) {
                ++nodes;
                if (tree.isLeaf(node)) { ++leaves; rows += node->stats.size; errors += node->stats.errors; }
            }
            add(lines, "level ", level, " nodes ", nodes, " leaves ", leaves, " rows ", rows, " errors ", errors);
        }
        return lines;
    }
    std::vector<Lines> treeFile() const {
        std::vector<Candidate> found;
        for (int a = 0; a < static_cast<int>(data.attributes.size()); ++a) {
            std::optional<Candidate> candidate = builder.bestForAttribute(train, a);
            if (candidate) found.push_back(std::move(*candidate));
        }
        std::sort(found.begin(), found.end(), [](const Candidate& a, const Candidate& b) {
            int order = compare(a.value, b.value);
            return order ? order > 0 : a.split.attribute < b.split.attribute;
        });
        Lines candidates;
        add(candidates, "root candidates n ", train.size(), " counts ", join(root->stats.counts));
        for (std::size_t i = 0; i < found.size(); ++i) {
            const Candidate& candidate = found[i];
            double n = static_cast<double>(train.size());
            double gain = static_cast<double>(candidate.value.numerator) / candidate.value.denominator / n - root->stats.squares / (n * n);
            add(candidates, i + 1, ' ', splitText(candidate.split, true, data), " left ", candidate.left.size(), " right ", candidate.right.size(), " gain ", realText(gain, 6));
        }
        Lines surrogates{"surrogates"};
        for (const Node* node : grown.preorder()) if (!grown.isLeaf(node)) {
            Lines listed;
            for (const Surrogate& surrogate : node->surrogates) listed.push_back(text(splitText(surrogate.split, true, data), surrogate.forward ? " left " : " right ", surrogate.score, '/', node->stats.size));
            add(surrogates, "node ", node->number, " split ", splitText(*node->split, true, data), " default ", node->defaultLeft ? "left" : "right", " surrogates ", listed.empty() ? "none" : join(listed, " ; "));
        }
        return {candidates, treeLines(grown), surrogates};
    }
    std::vector<Lines> prunedFile() const {
        Lines lines;
        add(lines, "reduced_error_pruning validation ", validation.size());
        int count = 0;
        for (const Decision& decision : decisions) {
            if (decision.pruned) ++count;
            add(lines, "node ", decision.node->number, " depth ", decision.node->depth, " rows ", decision.rows, " leaf ", decision.leafError, " subtree ", decision.subtreeError, decision.pruned ? " pruned" : " kept");
        }
        add(lines, "examined ", decisions.size(), " pruned ", count, " kept ", static_cast<int>(decisions.size()) - count);
        return {lines, treeLines(pruned)};
    }
    Lines predictionLines() const {
        Lines lines{"id,predicted,actual,grown,leaf,path,missing"};
        for (std::size_t i = 0; i < test.size(); ++i) {
            const Route& route = prunedRoutes[i];
            std::vector<int> path;
            int missing = 0;
            for (const Node* node : route.path) path.push_back(node->number);
            for (const Step& step : route.steps) if (step.method != Method::primary) ++missing;
            add(lines, test[i]->id, ',', data.classes[route.leaf->stats.prediction], ',', data.classes[test[i]->label], ',', data.classes[grownRoutes[i].leaf->stats.prediction], ',', route.leaf->number, ',', join(path, "-"), ',', missing);
        }
        return lines;
    }
    std::vector<Lines> ruleFile() const {
        Lines original, generalized, mistakes;
        add(original, "rules ", rules.size());
        add(generalized, "generalized ", rules.size());
        std::map<int, int> numbers;
        for (std::size_t i = 0; i < rules.size(); ++i) {
            const Rule& rule = rules[i];
            int label = rule.leaf->stats.prediction;
            numbers[rule.leaf->number] = static_cast<int>(i) + 1;
            Integer count = 0, hits = 0;
            for (std::size_t j = 0; j < test.size(); ++j) if (prunedRoutes[j].leaf == rule.leaf) {
                ++count;
                if (test[j]->label == label) ++hits;
            }
            add(original, "rule ", i + 1, " node ", rule.leaf->number, " if ", conditionsText(rule.conditions), " then ", data.classes[label], " train ", ratio(rule.leaf->stats.counts[label], rule.leaf->stats.size), " test ", ratio(hits, count));
            std::pair<Integer, Integer> val = coverage(rule.generalized, validation, label);
            std::pair<Integer, Integer> tst = coverage(rule.generalized, test, label);
            Lines removed;
            for (int a : rule.removed) removed.push_back(data.attributes[a].name);
            add(generalized, "general ", i + 1, " if ", conditionsText(rule.generalized), " then ", data.classes[label], " removed ", removed.empty() ? "none" : join(removed, ","), " laplace ", fraction(laplace(rule.generalized, label)), " validation ", val.first, '/', val.second, " test ", tst.first, '/', tst.second);
        }
        for (std::size_t i = 0; i < test.size(); ++i) {
            const Route& route = prunedRoutes[i];
            if (route.leaf->stats.prediction == test[i]->label) continue;
            Lines explanation;
            for (const Step& step : route.steps) explanation.push_back(splitText(*step.node->split, step.left, data) + (step.method == Method::primary ? "" : step.method == Method::surrogate ? " [surrogate]" : " [default]"));
            add(mistakes, test[i]->id, " actual ", data.classes[test[i]->label], " predicted ", data.classes[route.leaf->stats.prediction], " rule ", numbers.at(route.leaf->number), " path ", explanation.empty() ? "root" : join(explanation, "; "));
        }
        mistakes.insert(mistakes.begin(), text("misclassified ", mistakes.size()));
        return {original, generalized, mistakes};
    }
    Lines dataLines() const {
        Lines lines;
        add(lines, "data train ", train.size(), " validation ", validation.size(), " test ", test.size(), " attributes ", data.attributes.size(), " classes ", data.classes.size(), " target ", data.target);
        Statistics a = statistics(train, static_cast<int>(data.classes.size()));
        Statistics b = statistics(validation, static_cast<int>(data.classes.size()));
        Statistics c = statistics(test, static_cast<int>(data.classes.size()));
        for (std::size_t k = 0; k < data.classes.size(); ++k) add(lines, "class ", data.classes[k], " train ", a.counts[k], " validation ", b.counts[k], " test ", c.counts[k]);
        Counts val(data.attributes.size()), tst(data.attributes.size());
        for (const Row* row : validation) for (std::size_t i = 0; i < val.size(); ++i) if (row->values[i] < 0) ++val[i];
        for (const Row* row : test) for (std::size_t i = 0; i < tst.size(); ++i) if (row->values[i] < 0) ++tst[i];
        add(lines, "missing validation ", std::accumulate(val.begin(), val.end(), Integer{0}), " test ", std::accumulate(tst.begin(), tst.end(), Integer{0}));
        for (std::size_t i = 0; i < val.size(); ++i) add(lines, "missing ", data.attributes[i].name, " validation ", val[i], " test ", tst[i]);
        return lines;
    }
    Lines summaryLines() const {
        Lines lines;
        for (const std::pair<std::string, TreeView>& item : std::vector<std::pair<std::string, TreeView>>{{"grown", grown}, {"pruned", pruned}}) {
            const TreeView& tree = item.second;
            add(lines, item.first, " nodes ", tree.preorder().size(), " leaves ", tree.leaves().size(), " depth ", tree.depth(), " train ", accuracy(tree, train), " validation ", accuracy(tree, validation), " test ", accuracy(tree, test));
        }
        return lines;
    }
    Lines routingLines() const {
        std::map<int, std::array<Integer, 3>> tallies;
        for (const Route& route : prunedRoutes) for (const Step& step : route.steps) ++tallies[step.node->number][static_cast<int>(step.method)];
        Lines lines{"routing pruned test"};
        for (const Node* node : pruned.preorder()) if (!pruned.isLeaf(node)) {
            const std::array<Integer, 3>& tally = tallies[node->number];
            add(lines, "node ", node->number, " rows ", tally[0] + tally[1] + tally[2], " primary ", tally[0], " surrogate ", tally[1], " default ", tally[2]);
        }
        for (int incomplete = 0; incomplete < 2; ++incomplete) {
            Rows rows;
            for (const Row* row : test) {
                bool missing = std::any_of(row->values.begin(), row->values.end(), [](Integer value) { return value < 0; });
                if (missing == static_cast<bool>(incomplete)) rows.push_back(row);
            }
            add(lines, incomplete ? "incomplete" : "complete", " rows ", rows.size(), " correct ", accuracy(pruned, rows));
        }
        return lines;
    }
    Lines mcnemarLines() const {
        Lines lines{"mcnemar pruned test"};
        for (const std::string& model : Lines{"grown", "depth", "cost_complexity", "bagging"}) {
            Integer b = 0, c = 0;
            for (std::size_t i = 0; i < test.size(); ++i) {
                bool first = predictions.at("pruned")[i] == test[i]->label;
                bool second = predictions.at(model)[i] == test[i]->label;
                if (first && !second) ++b;
                if (second && !first) ++c;
            }
            Integer difference = std::max<Integer>(0, std::abs(b - c) - 1);
            Integer numerator = difference * difference;
            add(lines, "versus ", model, " b ", b, " c ", c, " statistic ", fraction({numerator, b + c ? b + c : 1}), " significant ", 1000 * numerator > 3841 * (b + c) ? "yes" : "no");
        }
        return lines;
    }
    Lines aucLines() const {
        Lines lines;
        for (const std::string& model : Lines{"grown", "pruned", "bagging"}) {
            std::vector<Counts> scores;
            Counts denominators;
            for (std::size_t i = 0; i < test.size(); ++i) {
                if (model == "bagging") {
                    scores.push_back(testVotes[i]);
                    denominators.push_back(data.settings.bagTrees);
                } else {
                    const Node* leaf = (model == "grown" ? grownRoutes[i] : prunedRoutes[i]).leaf;
                    scores.push_back(leaf->stats.counts);
                    denominators.push_back(leaf->stats.size);
                }
            }
            std::string line = "auc " + model;
            double macro = 0;
            int available = 0;
            for (std::size_t k = 0; k < data.classes.size(); ++k) {
                Integer positives = 0, wins = 0;
                for (std::size_t p = 0; p < test.size(); ++p) if (test[p]->label == static_cast<int>(k)) {
                    ++positives;
                    for (std::size_t n = 0; n < test.size(); ++n) if (test[n]->label != static_cast<int>(k)) {
                        int order = compare({scores[p][k], denominators[p]}, {scores[n][k], denominators[n]});
                        if (order > 0) wins += 2;
                        else if (!order) ++wins;
                    }
                }
                Integer denominator = 2 * positives * (static_cast<Integer>(test.size()) - positives);
                line += text(' ', data.classes[k], ' ', fraction({wins, denominator}));
                if (denominator) {
                    macro += static_cast<double>(wins) / denominator;
                    ++available;
                }
            }
            line += " macro " + (available ? realText(macro / available) : "-");
            lines.push_back(line);
        }
        return lines;
    }
    Lines learningLines() const {
        Lines lines{"learning_curve"};
        for (int size : data.settings.curve) {
            Rows training(train.begin(), train.begin() + size);
            std::unique_ptr<Node> curveRoot = builder.grow(training);
            TreeView tree{curveRoot.get(), {}};
            PruningResult result = reducedError(curveRoot.get(), validation, data.attributes);
            add(lines, "size ", size, " grown leaves ", tree.leaves().size(), " test ", accuracy(tree, test), " pruned leaves ", result.tree.leaves().size(), " test ", accuracy(result.tree, test));
        }
        return lines;
    }
    Lines impurityLines(const std::string& title, const TreeView& tree) const {
        std::vector<double> importance(data.attributes.size()), shares(data.attributes.size());
        std::vector<int> splits(data.attributes.size()), order(data.attributes.size());
        for (const Node* node : tree.preorder()) if (!tree.isLeaf(node)) {
            int a = node->split->attribute;
            importance[a] += impurityDecrease(node->stats, node->left->stats, node->right->stats);
            ++splits[a];
        }
        double total = 0;
        for (double value : importance) total += value;
        Counts rounded(data.attributes.size());
        for (std::size_t a = 0; a < importance.size(); ++a) {
            shares[a] = total ? importance[a] / total : 0;
            rounded[a] = static_cast<Integer>(std::llround(shares[a] * 10000));
            order[a] = static_cast<int>(a);
        }
        std::sort(order.begin(), order.end(), [&](int a, int b) { return rounded[a] != rounded[b] ? rounded[a] > rounded[b] : a < b; });
        Lines lines{"impurity " + title};
        for (std::size_t i = 0; i < order.size(); ++i) {
            int a = order[i];
            add(lines, i + 1, ' ', data.attributes[a].name, " decrease ", realText(importance[a] / train.size()), " share ", realText(shares[a]), " splits ", splits[a]);
        }
        return lines;
    }
    Lines permutationLines() const {
        struct Permutation { int attribute; Counts correct; Integer drop; };
        Minstd generator(data.settings.permutationSeed);
        Integer base = pruned.correct(test, data.attributes);
        std::vector<Permutation> records;
        for (int a = 0; a < static_cast<int>(data.attributes.size()); ++a) {
            Counts counts;
            for (int repeat = 0; repeat < data.settings.repeats; ++repeat) {
                Counts values;
                for (const Row* row : test) values.push_back(row->values[a]);
                for (std::size_t i = values.size(); i > 1; --i) {
                    std::size_t j = static_cast<std::size_t>(generator.draw() % static_cast<Integer>(i));
                    std::swap(values[i - 1], values[j]);
                }
                Integer correct = 0;
                for (std::size_t i = 0; i < test.size(); ++i) {
                    Row changed = *test[i];
                    changed.values[a] = values[i];
                    if (pruned.predict(changed, data.attributes) == changed.label) ++correct;
                }
                counts.push_back(correct);
            }
            Integer drop = data.settings.repeats * base - std::accumulate(counts.begin(), counts.end(), Integer{0});
            records.push_back({a, counts, drop});
        }
        std::sort(records.begin(), records.end(), [](const Permutation& a, const Permutation& b) { return a.drop != b.drop ? a.drop > b.drop : a.attribute < b.attribute; });
        Lines lines;
        add(lines, "permutation pruned test repeats ", data.settings.repeats, " seed ", data.settings.permutationSeed, " base ", ratio(base, static_cast<Integer>(test.size())));
        for (std::size_t i = 0; i < records.size(); ++i) {
            const Permutation& record = records[i];
            add(lines, i + 1, ' ', data.attributes[record.attribute].name, " correct ", join(record.correct), " drop ", fraction({record.drop, data.settings.repeats * static_cast<Integer>(test.size())}));
        }
        return lines;
    }
    static void write(const std::string& name, const std::vector<Lines>& sections) {
        std::ofstream file("output/" + name, std::ios::binary);
        if (!file) throw std::runtime_error("cannot write " + name);
        for (std::size_t i = 0; i < sections.size(); ++i) {
            if (i) file << '\n';
            for (const std::string& line : sections[i]) file << line << '\n';
        }
        file.close();
        if (!file) throw std::runtime_error("cannot write " + name);
    }
    void writeFiles() const {
        std::filesystem::create_directories("output");
        write("tree.txt", treeFile());
        write("pruned_tree.txt", prunedFile());
        write("predictions.csv", {predictionLines()});
        write("rules.txt", ruleFile());
        write("evaluation.txt", {dataLines(), summaryLines(), classification("grown test", test, predictions.at("grown"), data.classes), classification("pruned test", test, predictions.at("pruned"), data.classes), routingLines(), crossLines, depthLines, complexityLines, bagLines, mcnemarLines(), aucLines(), learningLines()});
        write("importance.txt", {impurityLines("grown", grown), impurityLines("pruned", pruned), permutationLines()});
    }
};
int main() {
    Analysis analysis(loadDataset());
    analysis.writeFiles();
}
