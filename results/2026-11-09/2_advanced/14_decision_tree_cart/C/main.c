#include "cart.h"

enum { GROWN, PRUNED, DEPTH, COMPLEXITY, BAGGING };
static const char *model_names[] = {"grown", "pruned", "depth", "cost_complexity", "bagging"};
typedef struct { int attribute; Integer lower, upper, equal; unsigned excluded; } Condition;
typedef struct { Condition items[12]; int count; } Conditions;
typedef struct { const Node *leaf; Conditions conditions, general; int removed[12], removed_count; } Rule;
typedef struct {
    Dataset data;
    Rows train, validation, test;
    Node *root;
    TreeView grown, pruned;
    Decision decisions[500]; int decision_count;
    Route grown_routes[300], pruned_routes[300];
    Rule rules[500]; int rule_count;
    int predictions[5][300]; Integer test_votes[300][6];
    Lines cross_lines, depth_lines, complexity_lines, bag_lines;
} Analysis;
static Integer draw(Integer *state) { *state = 48271 * *state % 2147483647; return *state; }
static char *half_text(Integer value) { return format("%lld.%d", value / 2, value % 2 ? 5 : 0); }
static char *split_text(const Dataset *data, Split split, bool left) {
    const Attribute *attribute = &data->attributes[split.attribute];
    return attribute->integer ? format("%s %s %s", attribute->name, left ? "<=" : ">", half_text(split.point))
                              : format("%s %s %s", attribute->name, left ? "=" : "!=", attribute->values[split.point]);
}
static char *accuracy(const Analysis *a, const TreeView *tree, Rows rows) { return ratio(correct_count(&a->data, tree, rows), rows.count); }
static TreeView at_depth(const Node *root, int depth) {
    TreeView tree = {.root = root};
    Nodes nodes = preorder(&tree, NULL);
    for (int i = 0; i < nodes.count; ++i) if (nodes.items[i]->branch && nodes.items[i]->depth == depth) tree.cuts[nodes.items[i]->number] = true;
    return tree;
}
static void model_predictions(Analysis *a, int model, const TreeView *tree) {
    for (int i = 0; i < a->test.count; ++i) a->predictions[model][i] = predict(&a->data, tree, a->test.items[i]);
}
static void cross_validation(Analysis *a) {
    Node *roots[500];
    int first[500], end[500];
    int n = a->train.count, folds = a->data.settings.folds;
    Integer total = 0;
    add_line(&a->cross_lines, "cross_validation folds %d", folds);
    for (int f = 0; f < folds; ++f) {
        first[f] = f * n / folds;
        end[f] = (f + 1) * n / folds;
        Rows training = {0}, held = {0};
        for (int i = 0; i < n; ++i) {
            Rows *target = i >= first[f] && i < end[f] ? &held : &training;
            target->items[target->count++] = a->train.items[i];
        }
        roots[f] = grow_tree(&a->data, training, 1, 0);
        TreeView tree = {.root = roots[f]};
        Integer correct = correct_count(&a->data, &tree, held);
        total += correct;
        add_line(&a->cross_lines, "fold %d rows %d-%d leaves %d correct %s", f + 1, first[f] + 1, end[f], leaves(&tree, NULL).count, ratio(correct, held.count));
    }
    add_line(&a->cross_lines, "cv accuracy %s", ratio(total, n));
    add_line(&a->depth_lines, "depth_selection");
    int selected = 0;
    Integer maximum = -1;
    for (int depth = 0; depth <= a->data.settings.max_depth; ++depth) {
        Integer correct = 0;
        for (int f = 0; f < folds; ++f) {
            TreeView tree = at_depth(roots[f], depth);
            Rows held = {0};
            for (int i = first[f]; i < end[f]; ++i) held.items[held.count++] = a->train.items[i];
            correct += correct_count(&a->data, &tree, held);
        }
        TreeView tree = at_depth(a->root, depth);
        if (correct > maximum) { maximum = correct; selected = depth; }
        add_line(&a->depth_lines, "depth %d leaves %d cv %s train %s validation %s test %s", depth, leaves(&tree, NULL).count, ratio(correct, n), accuracy(a, &tree, a->train), accuracy(a, &tree, a->validation), accuracy(a, &tree, a->test));
    }
    TreeView selected_tree = at_depth(a->root, selected);
    add_line(&a->depth_lines, "selected depth %d leaves %d test %s", selected, leaves(&selected_tree, NULL).count, accuracy(a, &selected_tree, a->test));
    model_predictions(a, DEPTH, &selected_tree);
}
static void complexity_selection(Analysis *a) {
    Sequence sequence = cost_complexity(a->root);
    int selected = 0;
    Integer minimum = a->validation.count + 1;
    add_line(&a->complexity_lines, "cost_complexity");
    for (int i = 0; i < sequence.count; ++i) {
        const SequenceEntry *entry = &sequence.items[i];
        Integer errors = a->validation.count - correct_count(&a->data, &entry->tree, a->validation);
        if (errors <= minimum) { selected = i; minimum = errors; }
        Fraction alpha = {entry->alpha.numerator, entry->alpha.denominator * a->train.count};
        add_line(&a->complexity_lines, "subtree %d alpha %s leaves %d train_errors %lld validation_errors %lld", i, fraction(alpha, 6), leaves(&entry->tree, NULL).count, training_errors(&entry->tree), errors);
    }
    const TreeView *tree = &sequence.items[selected].tree;
    add_line(&a->complexity_lines, "selected subtree %d leaves %d test %s", selected, leaves(tree, NULL).count, accuracy(a, tree, a->test));
    model_predictions(a, COMPLEXITY, tree);
}
static void bagging(Analysis *a) {
    Integer state = a->data.settings.bag_seed;
    Integer votes[500][6] = {{0}};
    add_line(&a->bag_lines, "bagging trees %d seed %lld", a->data.settings.bag_trees, state);
    for (int b = 0; b < a->data.settings.bag_trees; ++b) {
        Rows sample = {0};
        bool sampled[500] = {false};
        int distinct = 0;
        for (int i = 0; i < a->train.count; ++i) {
            int index = (int)(draw(&state) % a->train.count);
            sample.items[sample.count++] = a->train.items[index];
            if (!sampled[index]) { sampled[index] = true; ++distinct; }
        }
        Node *root = grow_tree(&a->data, sample, 1, 0);
        TreeView tree = {.root = root};
        Integer count = 0, correct = 0;
        for (int i = 0; i < a->train.count; ++i) if (!sampled[i]) {
            int prediction = predict(&a->data, &tree, a->train.items[i]);
            ++votes[i][prediction];
            ++count;
            if (prediction == a->train.items[i]->label) ++correct;
        }
        for (int i = 0; i < a->test.count; ++i) ++a->test_votes[i][predict(&a->data, &tree, a->test.items[i])];
        add_line(&a->bag_lines, "bag %d distinct %d leaves %d oob %s", b + 1, distinct, leaves(&tree, NULL).count, ratio(correct, count));
    }
    Integer voted = 0, correct = 0;
    for (int i = 0; i < a->train.count; ++i) {
        Integer total = 0;
        for (int k = 0; k < a->data.class_count; ++k) total += votes[i][k];
        if (!total) continue;
        ++voted;
        if (majority(votes[i], a->data.class_count) == a->train.items[i]->label) ++correct;
    }
    add_line(&a->bag_lines, "oob accuracy %s unvoted %lld", ratio(correct, voted), a->train.count - voted);
    for (int i = 0; i < a->test.count; ++i) a->predictions[BAGGING][i] = majority(a->test_votes[i], a->data.class_count);
    Lines evaluated = classification(&a->data, "bagging test", a->test, a->predictions[BAGGING]);
    for (int i = 0; i < evaluated.count; ++i) add_line(&a->bag_lines, "%s", evaluated.items[i]);
}
static void collect_rules(Analysis *a, const Node *node, Split *splits, bool *directions, int depth) {
    if (!is_leaf(&a->pruned, node)) {
        splits[depth] = node->split;
        directions[depth] = true;
        collect_rules(a, node->left, splits, directions, depth + 1);
        directions[depth] = false;
        collect_rules(a, node->right, splits, directions, depth + 1);
        return;
    }
    Rule *rule = &a->rules[a->rule_count++];
    rule->leaf = node;
    for (int attribute = 0; attribute < a->data.attribute_count; ++attribute) {
        Condition condition = {attribute, -1, -1, -1, 0};
        bool found = false;
        for (int i = 0; i < depth; ++i) if (splits[i].attribute == attribute) {
            found = true;
            Integer point = splits[i].point;
            if (a->data.attributes[attribute].integer) {
                if (directions[i]) { if (condition.upper < 0 || point < condition.upper) condition.upper = point; }
                else if (condition.lower < 0 || point > condition.lower) condition.lower = point;
            } else if (directions[i]) condition.equal = point;
            else condition.excluded |= 1u << (unsigned)point;
        }
        if (found) rule->conditions.items[rule->conditions.count++] = condition;
    }
}
static bool holds(const Analysis *a, Condition condition, const Row *row) {
    Integer value = row->values[condition.attribute];
    if (value < 0) return false;
    if (a->data.attributes[condition.attribute].integer) return (condition.lower < 0 || 2 * value > condition.lower) && (condition.upper < 0 || 2 * value <= condition.upper);
    return condition.equal >= 0 ? value == condition.equal : !(condition.excluded & (1u << (unsigned)value));
}
static Fraction coverage(const Analysis *a, Conditions conditions, Rows rows, int label) {
    Fraction result = {0};
    for (int i = 0; i < rows.count; ++i) {
        bool covered = true;
        for (int j = 0; j < conditions.count; ++j) if (!holds(a, conditions.items[j], rows.items[i])) covered = false;
        if (!covered) continue;
        ++result.denominator;
        if (rows.items[i]->label == label) ++result.numerator;
    }
    return result;
}
static Fraction laplace(const Analysis *a, Conditions conditions, int label) {
    Fraction result = coverage(a, conditions, a->validation, label);
    ++result.numerator;
    result.denominator += a->data.class_count;
    return result;
}
static Conditions remove_condition(Conditions conditions, int index) {
    --conditions.count;
    memmove(&conditions.items[index], &conditions.items[index + 1], (size_t)(conditions.count - index) * sizeof(Condition));
    return conditions;
}
static void generalize(const Analysis *a, Rule *rule) {
    rule->general = rule->conditions;
    while (rule->general.count) {
        Fraction current = laplace(a, rule->general, rule->leaf->stats.prediction), best = {0, 1};
        int chosen = -1;
        for (int i = 0; i < rule->general.count; ++i) {
            Fraction trial = laplace(a, remove_condition(rule->general, i), rule->leaf->stats.prediction);
            if (chosen < 0 || compare(trial, best) > 0) { best = trial; chosen = i; }
        }
        if (compare(best, current) < 0) break;
        rule->removed[rule->removed_count++] = rule->general.items[chosen].attribute;
        rule->general = remove_condition(rule->general, chosen);
    }
}
static char *condition_text(const Analysis *a, Condition condition) {
    const Attribute *attribute = &a->data.attributes[condition.attribute];
    if (attribute->integer) {
        if (condition.lower >= 0 && condition.upper >= 0) return format("%s < %s <= %s", half_text(condition.lower), attribute->name, half_text(condition.upper));
        if (condition.lower >= 0) return format("%s > %s", attribute->name, half_text(condition.lower));
        return format("%s <= %s", attribute->name, half_text(condition.upper));
    }
    if (condition.equal >= 0) return format("%s = %s", attribute->name, attribute->values[condition.equal]);
    char *names = "";
    int count = 0;
    for (int v = 0; v < attribute->value_count; ++v) if (condition.excluded & (1u << v)) {
        names = format("%s%s%s", names, count ? "," : "", attribute->values[v]);
        ++count;
    }
    return count == 1 ? format("%s != %s", attribute->name, names) : format("%s not in {%s}", attribute->name, names);
}
static char *conditions_text(const Analysis *a, Conditions conditions) {
    char *result = "";
    for (int i = 0; i < conditions.count; ++i) result = format("%s%s%s", result, i ? " and " : "", condition_text(a, conditions.items[i]));
    return conditions.count ? result : "true";
}
static void node_lines(const Analysis *a, const TreeView *tree, const Node *node, const char *condition, Lines *lines) {
    char *line = format("%*s%d %s n %lld counts %s", 2 * node->depth, "", node->number, condition, node->stats.size, counts_text(node->stats.counts, a->data.class_count));
    if (is_leaf(tree, node)) { add_line(lines, "%s leaf %s", line, a->data.classes[node->stats.prediction]); return; }
    add_line(lines, "%s", line);
    node_lines(a, tree, node->left, split_text(&a->data, node->split, true), lines);
    node_lines(a, tree, node->right, split_text(&a->data, node->split, false), lines);
}
static Lines tree_lines(const Analysis *a, const TreeView *tree) {
    Lines result = {0};
    node_lines(a, tree, tree->root, "root", &result);
    add_line(&result, "");
    Nodes nodes = preorder(tree, NULL), leaf_nodes = leaves(tree, NULL);
    int depth = tree_depth(tree);
    add_line(&result, "nodes %d leaves %d depth %d errors %s", nodes.count, leaf_nodes.count, depth, ratio(training_errors(tree), a->train.count));
    for (int level = 0; level <= depth; ++level) {
        Integer count = 0, leaf_count = 0, rows = 0, errors = 0;
        for (int i = 0; i < nodes.count; ++i) {
            const Node *node = nodes.items[i];
            if (node->depth != level) continue;
            ++count;
            if (is_leaf(tree, node)) { ++leaf_count; rows += node->stats.size; errors += node->stats.errors; }
        }
        add_line(&result, "level %d nodes %lld leaves %lld rows %lld errors %lld", level, count, leaf_count, rows, errors);
    }
    return result;
}
static Lines root_lines(const Analysis *a) {
    Candidate found[12];
    int count = 0;
    for (int attribute = 0; attribute < a->data.attribute_count; ++attribute) {
        Candidate candidate;
        if (!best_for_attribute(&a->data, a->train, attribute, &candidate)) continue;
        int i = count++;
        while (i > 0 && compare(candidate.value, found[i - 1].value) > 0) { found[i] = found[i - 1]; --i; }
        found[i] = candidate;
    }
    Lines result = {0};
    add_line(&result, "root candidates n %d counts %s", a->train.count, counts_text(a->root->stats.counts, a->data.class_count));
    for (int i = 0; i < count; ++i) {
        Candidate *candidate = &found[i];
        double size = a->train.count;
        double gain = (double)candidate->value.numerator / candidate->value.denominator / size - a->root->stats.squares / (size * size);
        add_line(&result, "%d %s left %d right %d gain %s", i + 1, split_text(&a->data, candidate->split, true), candidate->left.count, candidate->right.count, real_text(gain, 6));
    }
    return result;
}
static Lines surrogate_lines(const Analysis *a) {
    Lines result = {0};
    add_line(&result, "surrogates");
    Nodes nodes = preorder(&a->grown, NULL);
    for (int i = 0; i < nodes.count; ++i) {
        const Node *node = nodes.items[i];
        if (!node->branch) continue;
        char *listed = "";
        for (int j = 0; j < node->surrogate_count; ++j) {
            Surrogate surrogate = node->surrogates[j];
            listed = format("%s%s%s %s %lld/%lld", listed, j ? " ; " : "", split_text(&a->data, surrogate.split, true), surrogate.forward ? "left" : "right", surrogate.score, node->stats.size);
        }
        add_line(&result, "node %d split %s default %s surrogates %s", node->number, split_text(&a->data, node->split, true), node->default_left ? "left" : "right", node->surrogate_count ? listed : "none");
    }
    return result;
}
static Lines pruning_lines(const Analysis *a) {
    Lines result = {0};
    int count = 0;
    add_line(&result, "reduced_error_pruning validation %d", a->validation.count);
    for (int i = 0; i < a->decision_count; ++i) {
        Decision decision = a->decisions[i];
        if (decision.pruned) ++count;
        add_line(&result, "node %d depth %d rows %lld leaf %lld subtree %lld %s", decision.node->number, decision.node->depth, decision.rows, decision.leaf_error, decision.subtree_error, decision.pruned ? "pruned" : "kept");
    }
    add_line(&result, "examined %d pruned %d kept %d", a->decision_count, count, a->decision_count - count);
    return result;
}
static Lines prediction_lines(const Analysis *a) {
    Lines result = {0};
    add_line(&result, "id,predicted,actual,grown,leaf,path,missing");
    for (int i = 0; i < a->test.count; ++i) {
        const Route *route = &a->pruned_routes[i];
        char *path = "";
        int missing = 0;
        for (int j = 0; j <= route->count; ++j) path = format("%s%s%d", path, j ? "-" : "", route->path[j]->number);
        for (int j = 0; j < route->count; ++j) if (route->steps[j].method != PRIMARY) ++missing;
        add_line(&result, "%s,%s,%s,%s,%d,%s,%d", a->test.items[i]->id, a->data.classes[route->leaf->stats.prediction], a->data.classes[a->test.items[i]->label], a->data.classes[a->grown_routes[i].leaf->stats.prediction], route->leaf->number, path, missing);
    }
    return result;
}
static void rule_sections(const Analysis *a, Lines *original, Lines *generalized, Lines *mistakes) {
    add_line(original, "rules %d", a->rule_count);
    add_line(generalized, "generalized %d", a->rule_count);
    int numbers[2048] = {0};
    for (int i = 0; i < a->rule_count; ++i) {
        const Rule *rule = &a->rules[i];
        int label = rule->leaf->stats.prediction;
        numbers[rule->leaf->number] = i + 1;
        Integer hits = 0, count = 0;
        for (int j = 0; j < a->test.count; ++j) if (a->pruned_routes[j].leaf == rule->leaf) {
            ++count;
            if (a->test.items[j]->label == label) ++hits;
        }
        add_line(original, "rule %d node %d if %s then %s train %s test %s", i + 1, rule->leaf->number, conditions_text(a, rule->conditions), a->data.classes[label], ratio(rule->leaf->stats.counts[label], rule->leaf->stats.size), ratio(hits, count));
        Fraction val = coverage(a, rule->general, a->validation, label);
        Fraction tst = coverage(a, rule->general, a->test, label);
        char *removed = "";
        for (int j = 0; j < rule->removed_count; ++j) removed = format("%s%s%s", removed, j ? "," : "", a->data.attributes[rule->removed[j]].name);
        add_line(generalized, "general %d if %s then %s removed %s laplace %s validation %lld/%lld test %lld/%lld", i + 1, conditions_text(a, rule->general), a->data.classes[label], rule->removed_count ? removed : "none", fraction(laplace(a, rule->general, label), 4), val.numerator, val.denominator, tst.numerator, tst.denominator);
    }
    Lines wrong = {0};
    for (int i = 0; i < a->test.count; ++i) {
        const Route *route = &a->pruned_routes[i];
        if (route->leaf->stats.prediction == a->test.items[i]->label) continue;
        char *explanation = "";
        for (int j = 0; j < route->count; ++j) {
            Step step = route->steps[j];
            const char *mark = step.method == PRIMARY ? "" : step.method == SURROGATE ? " [surrogate]" : " [default]";
            explanation = format("%s%s%s%s", explanation, j ? "; " : "", split_text(&a->data, step.node->split, step.left), mark);
        }
        add_line(&wrong, "%s actual %s predicted %s rule %d path %s", a->test.items[i]->id, a->data.classes[a->test.items[i]->label], a->data.classes[route->leaf->stats.prediction], numbers[route->leaf->number], route->count ? explanation : "root");
    }
    add_line(mistakes, "misclassified %d", wrong.count);
    for (int i = 0; i < wrong.count; ++i) add_line(mistakes, "%s", wrong.items[i]);
}
static Lines data_lines(const Analysis *a) {
    Lines result = {0};
    add_line(&result, "data train %d validation %d test %d attributes %d classes %d target %s", a->train.count, a->validation.count, a->test.count, a->data.attribute_count, a->data.class_count, a->data.target);
    Statistics train = statistics(a->train, a->data.class_count), val = statistics(a->validation, a->data.class_count), test = statistics(a->test, a->data.class_count);
    for (int k = 0; k < a->data.class_count; ++k) add_line(&result, "class %s train %lld validation %lld test %lld", a->data.classes[k], train.counts[k], val.counts[k], test.counts[k]);
    Integer val_missing[12] = {0}, test_missing[12] = {0}, vm = 0, tm = 0;
    for (int i = 0; i < a->validation.count; ++i) for (int j = 0; j < a->data.attribute_count; ++j)
        if (a->validation.items[i]->values[j] < 0) { ++val_missing[j]; ++vm; }
    for (int i = 0; i < a->test.count; ++i) for (int j = 0; j < a->data.attribute_count; ++j)
        if (a->test.items[i]->values[j] < 0) { ++test_missing[j]; ++tm; }
    add_line(&result, "missing validation %lld test %lld", vm, tm);
    for (int j = 0; j < a->data.attribute_count; ++j) add_line(&result, "missing %s validation %lld test %lld", a->data.attributes[j].name, val_missing[j], test_missing[j]);
    return result;
}
static Lines summary_lines(const Analysis *a) {
    Lines result = {0};
    const TreeView *trees[] = {&a->grown, &a->pruned};
    for (int i = 0; i < 2; ++i) {
        const TreeView *tree = trees[i];
        add_line(&result, "%s nodes %d leaves %d depth %d train %s validation %s test %s", model_names[i], preorder(tree, NULL).count, leaves(tree, NULL).count, tree_depth(tree), accuracy(a, tree, a->train), accuracy(a, tree, a->validation), accuracy(a, tree, a->test));
    }
    return result;
}
static Lines routing_lines(const Analysis *a) {
    Integer tallies[2048][3] = {{0}};
    for (int i = 0; i < a->test.count; ++i) for (int j = 0; j < a->pruned_routes[i].count; ++j) {
        Step step = a->pruned_routes[i].steps[j];
        ++tallies[step.node->number][step.method];
    }
    Lines result = {0};
    add_line(&result, "routing pruned test");
    Nodes nodes = preorder(&a->pruned, NULL);
    for (int i = 0; i < nodes.count; ++i) if (!is_leaf(&a->pruned, nodes.items[i])) {
        const Integer *tally = tallies[nodes.items[i]->number];
        add_line(&result, "node %d rows %lld primary %lld surrogate %lld default %lld", nodes.items[i]->number, tally[0] + tally[1] + tally[2], tally[0], tally[1], tally[2]);
    }
    for (int incomplete = 0; incomplete < 2; ++incomplete) {
        Rows rows = {0};
        for (int i = 0; i < a->test.count; ++i) {
            bool missing = false;
            for (int j = 0; j < a->data.attribute_count; ++j) if (a->test.items[i]->values[j] < 0) missing = true;
            if (missing == (bool)incomplete) rows.items[rows.count++] = a->test.items[i];
        }
        add_line(&result, "%s rows %d correct %s", incomplete ? "incomplete" : "complete", rows.count, accuracy(a, &a->pruned, rows));
    }
    return result;
}
static Lines mcnemar_lines(const Analysis *a) {
    Lines result = {0};
    add_line(&result, "mcnemar pruned test");
    const int compared[] = {GROWN, DEPTH, COMPLEXITY, BAGGING};
    for (int m = 0; m < 4; ++m) {
        int model = compared[m];
        Integer b = 0, c = 0;
        for (int i = 0; i < a->test.count; ++i) {
            bool first = a->predictions[PRUNED][i] == a->test.items[i]->label;
            bool second = a->predictions[model][i] == a->test.items[i]->label;
            if (first && !second) ++b;
            if (second && !first) ++c;
        }
        Integer difference = b > c ? b - c : c - b;
        difference = difference ? difference - 1 : 0;
        Integer numerator = difference * difference;
        add_line(&result, "versus %s b %lld c %lld statistic %s significant %s", model_names[model], b, c, fraction((Fraction){numerator, b + c ? b + c : 1}, 4), 1000 * numerator > 3841 * (b + c) ? "yes" : "no");
    }
    return result;
}
static Lines auc_lines(const Analysis *a) {
    Lines result = {0};
    const int models[] = {GROWN, PRUNED, BAGGING};
    for (int m = 0; m < 3; ++m) {
        int model = models[m];
        Integer scores[300][6], denominators[300];
        for (int i = 0; i < a->test.count; ++i) {
            const Node *leaf = model == GROWN ? a->grown_routes[i].leaf : a->pruned_routes[i].leaf;
            denominators[i] = model == BAGGING ? a->data.settings.bag_trees : leaf->stats.size;
            for (int k = 0; k < a->data.class_count; ++k) scores[i][k] = model == BAGGING ? a->test_votes[i][k] : leaf->stats.counts[k];
        }
        char *line = format("auc %s", model_names[model]);
        double macro = 0;
        int available = 0;
        for (int k = 0; k < a->data.class_count; ++k) {
            Integer positives = 0, wins = 0;
            for (int p = 0; p < a->test.count; ++p) if (a->test.items[p]->label == k) {
                ++positives;
                for (int n = 0; n < a->test.count; ++n) if (a->test.items[n]->label != k) {
                    int order = compare((Fraction){scores[p][k], denominators[p]}, (Fraction){scores[n][k], denominators[n]});
                    if (order > 0) wins += 2;
                    else if (!order) ++wins;
                }
            }
            Integer denominator = 2 * positives * (a->test.count - positives);
            line = format("%s %s %s", line, a->data.classes[k], fraction((Fraction){wins, denominator}, 4));
            if (denominator) { macro += (double)wins / denominator; ++available; }
        }
        add_line(&result, "%s macro %s", line, available ? real_text(macro / available, 4) : "-");
    }
    return result;
}
static Lines learning_lines(const Analysis *a) {
    Lines result = {0};
    add_line(&result, "learning_curve");
    for (int i = 0; i < a->data.settings.curve_count; ++i) {
        int size = a->data.settings.curve[i];
        Rows training = a->train;
        training.count = size;
        Node *root = grow_tree(&a->data, training, 1, 0);
        TreeView tree = {.root = root};
        PruningResult pruning;
        reduced_error(&a->data, root, a->validation, &pruning);
        add_line(&result, "size %d grown leaves %d test %s pruned leaves %d test %s", size, leaves(&tree, NULL).count, accuracy(a, &tree, a->test), leaves(&pruning.tree, NULL).count, accuracy(a, &pruning.tree, a->test));
    }
    return result;
}
static Lines impurity_lines(const Analysis *a, const char *title, const TreeView *tree) {
    double importance[12] = {0}, shares[12], total = 0;
    Integer rounded[12];
    int splits[12] = {0}, order[12];
    Nodes nodes = preorder(tree, NULL);
    for (int i = 0; i < nodes.count; ++i) if (!is_leaf(tree, nodes.items[i])) {
        const Node *node = nodes.items[i];
        importance[node->split.attribute] += impurity_decrease(node->stats, node->left->stats, node->right->stats);
        ++splits[node->split.attribute];
    }
    for (int i = 0; i < a->data.attribute_count; ++i) total += importance[i];
    for (int i = 0; i < a->data.attribute_count; ++i) {
        shares[i] = total ? importance[i] / total : 0;
        rounded[i] = llround(shares[i] * 10000);
        int j = i;
        while (j > 0 && rounded[order[j - 1]] < rounded[i]) { order[j] = order[j - 1]; --j; }
        order[j] = i;
    }
    Lines result = {0};
    add_line(&result, "impurity %s", title);
    for (int i = 0; i < a->data.attribute_count; ++i) {
        int attribute = order[i];
        add_line(&result, "%d %s decrease %s share %s splits %d", i + 1, a->data.attributes[attribute].name, real_text(importance[attribute] / a->train.count, 4), real_text(shares[attribute], 4), splits[attribute]);
    }
    return result;
}
static Lines permutation_lines(const Analysis *a) {
    Integer state = a->data.settings.permutation_seed;
    Integer base = correct_count(&a->data, &a->pruned, a->test);
    Integer counts[12][10] = {{0}}, drops[12];
    int order[12], repeats = a->data.settings.repeats;
    for (int attribute = 0; attribute < a->data.attribute_count; ++attribute) {
        Integer total = 0;
        for (int repeat = 0; repeat < repeats; ++repeat) {
            Integer values[300];
            for (int i = 0; i < a->test.count; ++i) values[i] = a->test.items[i]->values[attribute];
            for (int i = a->test.count; i > 1; --i) {
                int j = (int)(draw(&state) % i);
                Integer saved = values[i - 1]; values[i - 1] = values[j]; values[j] = saved;
            }
            Integer correct = 0;
            for (int i = 0; i < a->test.count; ++i) {
                Row changed = *a->test.items[i];
                changed.values[attribute] = values[i];
                if (predict(&a->data, &a->pruned, &changed) == changed.label) ++correct;
            }
            counts[attribute][repeat] = correct;
            total += correct;
        }
        drops[attribute] = repeats * base - total;
        int j = attribute;
        while (j > 0 && drops[order[j - 1]] < drops[attribute]) { order[j] = order[j - 1]; --j; }
        order[j] = attribute;
    }
    Lines result = {0};
    add_line(&result, "permutation pruned test repeats %d seed %lld base %s", repeats, a->data.settings.permutation_seed, ratio(base, a->test.count));
    for (int i = 0; i < a->data.attribute_count; ++i) {
        int attribute = order[i];
        add_line(&result, "%d %s correct %s drop %s", i + 1, a->data.attributes[attribute].name, counts_text(counts[attribute], repeats), fraction((Fraction){drops[attribute], (Integer)repeats * a->test.count}, 4));
    }
    return result;
}
static void write_sections(const char *name, const Lines *sections, int count) {
    FILE *file = fopen(format("output/%s", name), "wb");
    if (!file) exit(EXIT_FAILURE);
    for (int i = 0; i < count; ++i) {
        if (i && fputc('\n', file) == EOF) exit(EXIT_FAILURE);
        for (int j = 0; j < sections[i].count; ++j) if (fprintf(file, "%s\n", sections[i].items[j]) < 0) exit(EXIT_FAILURE);
    }
    if (fclose(file)) exit(EXIT_FAILURE);
}
int main(void) {
    static Analysis analysis;
    Analysis *a = &analysis;
    load_dataset(&a->data);
    a->train = row_sequence(a->data.train, a->data.train_count);
    a->validation = row_sequence(a->data.validation, a->data.validation_count);
    a->test = row_sequence(a->data.test, a->data.test_count);
    a->root = grow_tree(&a->data, a->train, 1, 0);
    a->grown = (TreeView){.root = a->root};
    PruningResult result;
    reduced_error(&a->data, a->root, a->validation, &result);
    a->pruned = result.tree;
    a->decision_count = result.count;
    memcpy(a->decisions, result.decisions, (size_t)result.count * sizeof(Decision));
    for (int i = 0; i < a->test.count; ++i) {
        a->grown_routes[i] = route_row(&a->data, &a->grown, a->test.items[i]);
        a->pruned_routes[i] = route_row(&a->data, &a->pruned, a->test.items[i]);
    }
    model_predictions(a, GROWN, &a->grown);
    model_predictions(a, PRUNED, &a->pruned);
    cross_validation(a);
    complexity_selection(a);
    bagging(a);
    Split splits[10]; bool directions[10];
    collect_rules(a, a->root, splits, directions, 0);
    for (int i = 0; i < a->rule_count; ++i) generalize(a, &a->rules[i]);
    if (mkdir("output", 0777) && errno != EEXIST) exit(EXIT_FAILURE);
    Lines tree[] = {root_lines(a), tree_lines(a, &a->grown), surrogate_lines(a)};
    Lines pruned[] = {pruning_lines(a), tree_lines(a, &a->pruned)};
    Lines predictions[] = {prediction_lines(a)};
    Lines rules[3] = {{0}};
    rule_sections(a, &rules[0], &rules[1], &rules[2]);
    Lines evaluation[] = {data_lines(a), summary_lines(a), classification(&a->data, "grown test", a->test, a->predictions[GROWN]), classification(&a->data, "pruned test", a->test, a->predictions[PRUNED]), routing_lines(a), a->cross_lines, a->depth_lines, a->complexity_lines, a->bag_lines, mcnemar_lines(a), auc_lines(a), learning_lines(a)};
    Lines importance[] = {impurity_lines(a, "grown", &a->grown), impurity_lines(a, "pruned", &a->pruned), permutation_lines(a)};
    write_sections("tree.txt", tree, 3);
    write_sections("pruned_tree.txt", pruned, 2);
    write_sections("predictions.csv", predictions, 1);
    write_sections("rules.txt", rules, 3);
    write_sections("evaluation.txt", evaluation, 12);
    write_sections("importance.txt", importance, 3);
    return 0;
}
