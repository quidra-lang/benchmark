#include "cart.h"

bool goes_left(const Dataset *data, Split split, const Row *row) {
    Integer value = row->values[split.attribute];
    return data->attributes[split.attribute].integer ? 2 * value <= split.point : value == split.point;
}
static int integer_compare(const void *first, const void *second) {
    Integer a = *(const Integer *)first, b = *(const Integer *)second;
    return a < b ? -1 : a > b ? 1 : 0;
}
int split_candidates(const Dataset *data, Rows rows, int attribute, Split *result) {
    Integer values[500];
    for (int i = 0; i < rows.count; ++i) values[i] = rows.items[i]->values[attribute];
    qsort(values, (size_t)rows.count, sizeof(Integer), integer_compare);
    int count = 0;
    for (int i = 0; i < rows.count; ++i) if (!i || values[i] != values[i - 1]) values[count++] = values[i];
    if (count < 2) return 0;
    int size = data->attributes[attribute].integer ? count - 1 : count;
    for (int i = 0; i < size; ++i) result[i] = (Split){attribute, data->attributes[attribute].integer ? values[i] + values[i + 1] : values[i]};
    return size;
}
bool best_for_attribute(const Dataset *data, Rows rows, int attribute, Candidate *result) {
    Split splits[500];
    int count = split_candidates(data, rows, attribute, splits);
    bool found = false;
    for (int i = 0; i < count; ++i) {
        Candidate candidate = { .split = splits[i] };
        for (int j = 0; j < rows.count; ++j) {
            Rows *target = goes_left(data, splits[i], rows.items[j]) ? &candidate.left : &candidate.right;
            target->items[target->count++] = rows.items[j];
        }
        if (candidate.left.count < data->settings.min_leaf || candidate.right.count < data->settings.min_leaf) continue;
        candidate.value = evaluation_value(statistics(candidate.left, data->class_count), statistics(candidate.right, data->class_count));
        if (!found || compare(candidate.value, result->value) > 0) {
            *result = candidate;
            found = true;
        }
    }
    return found;
}
static void find_surrogates(const Dataset *data, Rows rows, const Candidate *primary, Node *node) {
    Surrogate chosen[12];
    int count = 0;
    for (int a = 0; a < data->attribute_count; ++a) {
        if (a == primary->split.attribute) continue;
        Split splits[500];
        int size = split_candidates(data, rows, a, splits);
        Surrogate best = {0};
        bool found = false;
        for (int i = 0; i < size; ++i) {
            Integer agreement = 0;
            for (int j = 0; j < rows.count; ++j)
                if (goes_left(data, splits[i], rows.items[j]) == goes_left(data, primary->split, rows.items[j])) ++agreement;
            Integer reverse = rows.count - agreement;
            Surrogate current = {splits[i], agreement >= reverse, agreement > reverse ? agreement : reverse};
            if (!found || current.score > best.score) { best = current; found = true; }
        }
        int limit = primary->left.count > primary->right.count ? primary->left.count : primary->right.count;
        if (found && best.score > limit) {
            int i = count++;
            while (i > 0 && chosen[i - 1].score < best.score) { chosen[i] = chosen[i - 1]; --i; }
            chosen[i] = best;
        }
    }
    node->surrogate_count = count < data->settings.max_surrogates ? count : data->settings.max_surrogates;
    memcpy(node->surrogates, chosen, (size_t)node->surrogate_count * sizeof(Surrogate));
}
Node *grow_tree(const Dataset *data, Rows rows, int number, int depth) {
    Node *node = allocate(sizeof(*node));
    node->number = number;
    node->depth = depth;
    node->stats = statistics(rows, data->class_count);
    if (!node->stats.errors || depth == data->settings.max_depth || rows.count < data->settings.min_split) return node;
    Candidate best;
    bool found = false;
    for (int a = 0; a < data->attribute_count; ++a) {
        Candidate candidate;
        if (best_for_attribute(data, rows, a, &candidate) && (!found || compare(candidate.value, best.value) > 0)) {
            best = candidate;
            found = true;
        }
    }
    if (!found || !improves(best.value, node->stats)) return node;
    node->branch = true;
    node->split = best.split;
    node->default_left = best.left.count >= best.right.count;
    find_surrogates(data, rows, &best, node);
    node->left = grow_tree(data, best.left, 2 * number, depth + 1);
    node->right = grow_tree(data, best.right, 2 * number + 1, depth + 1);
    return node;
}
