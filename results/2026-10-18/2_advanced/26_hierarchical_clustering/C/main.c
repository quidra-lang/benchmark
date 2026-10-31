#include "clustering.h"
#include <inttypes.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

typedef struct {
    int partition[MAX_OBSERVATIONS], sizes[MAX_OBSERVATIONS], groups;
    double silhouette, dunn, wss, ch;
    Fraction ari;
} Evaluation;
typedef struct {
    const char *method;
    Tree *tree;
    double cophenetic[MAX_PAIRS], coefficient;
    Evaluation *height_cuts, *count_cuts;
    int label_partition[MAX_OBSERVATIONS];
} LinkageResult;
typedef struct {
    Dataset *data;
    int n, p, class_count;
    char *classes[10];
    int targets[MAX_OBSERVATIONS], neighbors[MAX_OBSERVATIONS];
    Vectors vectors;
    Matrix delta;
    double means[MAX_FEATURES], deviations[MAX_FEATURES], distance_pairs[MAX_PAIRS], distance_max;
    LinkageResult results[7];
    int chosen, position, kappa, selected[MAX_OBSERVATIONS];
    int member_counts[MAX_OBSERVATIONS], members[MAX_OBSERVATIONS][MAX_OBSERVATIONS];
    int table[MAX_OBSERVATIONS][10], majority[MAX_OBSERVATIONS];
    double silhouettes[MAX_OBSERVATIONS];
} Study;

static int maximum(const int *values, int count) {
    int result = values[0];
    for (int i = 1; i < count; ++i) if (values[i] > result) result = values[i];
    return result;
}
static char *real(double value) {
    if (isnan(value)) return "-";
    char *result = format("%.4f", value);
    return !strcmp(result, "-0.0000") ? "0.0000" : result;
}
static char *exact_real(Fraction value) {
    Integer magnitude = value.numerator < 0 ? -value.numerator : value.numerator;
    Integer rounded = (2 * magnitude * 10000 + value.denominator) / (2 * value.denominator);
    return format("%s%" PRId64 ".%04" PRId64, value.numerator < 0 && rounded ? "-" : "", rounded / 10000, rounded % 10000);
}
static char *ari_text(Fraction value) { return format("%" PRId64 "/%" PRId64 " %s", value.numerator, value.denominator, exact_real(value)); }
static double four_digit(double value) { return fabs(value) >= 1e12 ? value : round(value * 10000) / 10000; }
static char *integers(const int *values, int count, const char *separator) {
    Text text = {0};
    for (int i = 0; i < count; ++i) text_add(&text, "%s%d", i ? separator : "", values[i]);
    return text.data ? text.data : "";
}
static char *reals(const double *values, int count) {
    Text text = {0};
    for (int i = 0; i < count; ++i) text_add(&text, "%s%s", i ? " " : "", real(values[i]));
    return text.data ? text.data : "";
}
static char *names(char *const *values, int count) {
    Text text = {0};
    for (int i = 0; i < count; ++i) text_add(&text, "%s%s", i ? " " : "", values[i]);
    return text.data ? text.data : "";
}
static void sort_indices(int *order, const double *values, int count, bool decreasing, bool rounded) {
    for (int i = 0; i < count; ++i) {
        int position = i;
        double value = rounded ? four_digit(values[i]) : values[i];
        while (position > 0) {
            double previous = rounded ? four_digit(values[order[position - 1]]) : values[order[position - 1]];
            if (decreasing ? value <= previous : value >= previous) break;
            order[position] = order[position - 1];
            --position;
        }
        order[position] = i;
    }
}
static int compare_doubles(const void *first, const void *second) {
    double a = *(const double *)first, b = *(const double *)second;
    return (a > b) - (a < b);
}
static int compare_ints(const void *first, const void *second) {
    int a = *(const int *)first, b = *(const int *)second;
    return (a > b) - (a < b);
}
static int compare_names(const void *first, const void *second) { return strcmp(*(char *const *)first, *(char *const *)second); }
static int pair_values(const Matrix matrix, int count, double *values) {
    int position = 0;
    for (int i = 0; i < count; ++i) for (int j = i + 1; j < count; ++j) values[position++] = matrix[i][j];
    return position;
}
static int histogram_bin(double value, double maximum_value) {
    double bin = floor(10 * value / maximum_value);
    return bin >= 9 ? 9 : (int)bin;
}
static double node_height(const Tree *tree, int node) { return node < tree->count ? 0 : tree->heights[node - tree->count]; }
static double subtree_height(const Tree *tree, int node) { return node < tree->count ? 0 : tree->subtree_heights[node - tree->count]; }
static Tree *build_tree(const Matrix delta, int count, const char *method) {
    Tree *tree = allocate(sizeof *tree);
    tree->count = count;
    agglomerate(delta, count, method, tree->merges);
    ordered_children(tree);
    leaf_order(tree);
    for (int i = 0; i < count; ++i) { tree->sizes[i] = 1; tree->members[i][0] = i; }
    for (int step = 0; step < count - 1; ++step) {
        Merge merge = tree->merges[step];
        int node = count + step;
        tree->heights[step] = merge.height;
        tree->sizes[node] = merge.size;
        memcpy(tree->members[node], tree->members[merge.a], (size_t)tree->sizes[merge.a] * sizeof(int));
        memcpy(tree->members[node] + tree->sizes[merge.a], tree->members[merge.b], (size_t)tree->sizes[merge.b] * sizeof(int));
        tree->depths[node] = 1 + (tree->depths[merge.a] > tree->depths[merge.b] ? tree->depths[merge.a] : tree->depths[merge.b]);
        tree->subtree_heights[step] = fmax(merge.height, fmax(subtree_height(tree, merge.a), subtree_height(tree, merge.b)));
    }
    return tree;
}
static void tree_partition(const Tree *tree, const bool *chosen, int *partition) {
    int owner[MAX_OBSERVATIONS], numbers[MAX_NODES] = {0}, groups = 0;
    for (int i = 0; i < tree->count; ++i) owner[i] = i;
    for (int step = 0; step < tree->count - 1; ++step) if (chosen[step]) {
        int node = tree->count + step;
        for (int i = 0; i < tree->sizes[node]; ++i) owner[tree->members[node][i]] = node;
    }
    for (int row = 0; row < tree->count; ++row) {
        int node = owner[tree->order[row]];
        if (!numbers[node]) numbers[node] = ++groups;
    }
    for (int i = 0; i < tree->count; ++i) partition[i] = numbers[owner[i]];
}
static void cut_into(const Tree *tree, int groups, int *partition) {
    bool chosen[MAX_OBSERVATIONS] = {0};
    for (int step = 0; step < tree->count - groups; ++step) chosen[step] = true;
    tree_partition(tree, chosen, partition);
}
static void cut_at(const Tree *tree, double height, int *partition) {
    bool chosen[MAX_OBSERVATIONS] = {0};
    for (int step = 0; step < tree->count - 1; ++step) chosen[step] = tree->subtree_heights[step] <= height;
    tree_partition(tree, chosen, partition);
}
static void cophenetic(const Tree *tree, double *values) {
    Matrix matrix = {{0}};
    for (int step = 0; step < tree->count - 1; ++step) {
        Merge merge = tree->merges[step];
        for (int a = 0; a < tree->sizes[merge.a]; ++a) for (int b = 0; b < tree->sizes[merge.b]; ++b) {
            int i = tree->members[merge.a][a], j = tree->members[merge.b][b];
            matrix[i][j] = matrix[j][i] = merge.height;
        }
    }
    pair_values(matrix, tree->count, values);
}
static void height_sequence(const Tree *tree, int step, int depth, double *heights, int *count) {
    if (!depth) return;
    Merge merge = tree->merges[step];
    heights[(*count)++] = merge.height;
    if (merge.a >= tree->count) height_sequence(tree, merge.a - tree->count, depth - 1, heights, count);
    if (merge.b >= tree->count) height_sequence(tree, merge.b - tree->count, depth - 1, heights, count);
}
static char *newick(const Tree *tree, int node, char *const *ids) {
    if (node < tree->count) return ids[node];
    int upper = tree->children[node - tree->count][0], lower = tree->children[node - tree->count][1];
    double height = node_height(tree, node);
    char *first = newick(tree, upper, ids), *second = newick(tree, lower, ids);
    return format("(%s:%s,%s:%s)", first, real(height - node_height(tree, upper)), second, real(height - node_height(tree, lower)));
}
static Fraction label_ari(const Study *study, const int *partition) {
    return adjusted_rand(partition, study->targets, study->n, maximum(partition, study->n), study->class_count);
}
static Fraction partition_ari(const int *first, const int *second, int count) {
    return adjusted_rand(first, second, count, maximum(first, count), maximum(second, count));
}
static void class_table(const Study *study, const int *partition, int table[MAX_OBSERVATIONS][10]) {
    memset(table, 0, MAX_OBSERVATIONS * 10 * sizeof(int));
    for (int i = 0; i < study->n; ++i) ++table[partition[i] - 1][study->targets[i] - 1];
}
static int match_count(const Study *study, const int *partition) {
    int table[MAX_OBSERVATIONS][10], total = 0;
    class_table(study, partition, table);
    for (int group = 0; group < maximum(partition, study->n); ++group) total += maximum(table[group], study->class_count);
    return total;
}
static void centroids(const Study *study, const int *partition, int groups, Vectors centers, int *sizes) {
    memset(centers, 0, sizeof(Vectors));
    memset(sizes, 0, MAX_OBSERVATIONS * sizeof(int));
    for (int i = 0; i < study->n; ++i) ++sizes[partition[i] - 1];
    for (int group = 0; group < groups; ++group) for (int feature = 0; feature < study->p; ++feature) {
        for (int i = 0; i < study->n; ++i) if (partition[i] == group + 1) centers[group][feature] += study->vectors[i][feature];
        if (sizes[group]) centers[group][feature] /= sizes[group];
    }
}
static double within_sum(const Study *study, const int *partition) {
    Vectors centers;
    int sizes[MAX_OBSERVATIONS];
    centroids(study, partition, maximum(partition, study->n), centers, sizes);
    double total = 0;
    for (int i = 0; i < study->n; ++i) total += squared_distance(study->vectors[i], centers[partition[i] - 1], study->p);
    return total;
}
static double mean_silhouette(const int *partition, int count, const Matrix delta) {
    int groups = maximum(partition, count);
    if (groups < 2) return NAN;
    double values[MAX_OBSERVATIONS];
    silhouette_values(partition, count, groups, delta, values);
    return sequential_sum(values, count) / count;
}
static Evaluation evaluate(const Study *study, const int *partition) {
    Evaluation result = {0};
    memcpy(result.partition, partition, (size_t)study->n * sizeof(int));
    result.groups = maximum(partition, study->n);
    Vectors centers;
    centroids(study, partition, result.groups, centers, result.sizes);
    result.wss = within_sum(study, partition);
    result.silhouette = mean_silhouette(partition, study->n, study->delta);
    result.dunn = result.ch = NAN;
    double diameter = 0, separation = 0;
    bool found = false;
    for (int i = 0; i < study->n; ++i) for (int j = i + 1; j < study->n; ++j) {
        if (partition[i] == partition[j]) diameter = fmax(diameter, study->delta[i][j]);
        else if (!found || study->delta[i][j] < separation) { found = true; separation = study->delta[i][j]; }
    }
    if (result.groups >= 2 && diameter > 0) result.dunn = separation / diameter;
    if (result.groups >= 2 && result.groups < study->n) {
        double overall[MAX_FEATURES] = {0}, bss = 0;
        for (int feature = 0; feature < study->p; ++feature) {
            for (int i = 0; i < study->n; ++i) overall[feature] += study->vectors[i][feature];
            overall[feature] /= study->n;
        }
        for (int group = 0; group < result.groups; ++group) bss += result.sizes[group] * squared_distance(centers[group], overall, study->p);
        result.ch = (bss / (result.groups - 1)) / (result.wss / (study->n - result.groups));
    }
    result.ari = label_ari(study, partition);
    return result;
}
static char *evaluation_text(const Evaluation *value) {
    return format("sizes %s silhouette %s dunn %s wss %s ch %s ari %s", integers(value->sizes, value->groups, " "), real(value->silhouette), real(value->dunn), real(value->wss), real(value->ch), ari_text(value->ari));
}
static char *pair_text(const Study *study, int first, int second) { return format("%s %s %s", real(study->delta[first][second]), study->data->ids[first], study->data->ids[second]); }
static Lines data_part(const Study *study) {
    Lines lines = {0};
    const Dataset *data = study->data;
    add_line(&lines, "data n %d features %d classes %d distance %s standardize %s", study->n, study->p, study->class_count, data->settings.distance, data->settings.standardize);
    for (int f = 0; f < study->p; ++f) add_line(&lines, "feature %s mean %s sd %s", data->feature_names[f], real(study->means[f]), real(study->deviations[f]));
    int low_a = 0, low_b = 1, high_a = 0, high_b = 1;
    for (int i = 0; i < study->n; ++i) for (int j = i + 1; j < study->n; ++j) {
        if (study->delta[i][j] < study->delta[low_a][low_b]) { low_a = i; low_b = j; }
        if (study->delta[i][j] > study->delta[high_a][high_b]) { high_a = i; high_b = j; }
    }
    int pairs = study->n * (study->n - 1) / 2;
    add_line(&lines, "distances pairs %d min %s max %s mean %s", pairs, pair_text(study, low_a, low_b), pair_text(study, high_a, high_b), real(sequential_sum(study->distance_pairs, pairs) / pairs));
    double total = 0;
    int reciprocal = 0;
    for (int i = 0; i < study->n; ++i) { total += study->delta[i][study->neighbors[i]]; if (i < study->neighbors[i] && study->neighbors[study->neighbors[i]] == i) ++reciprocal; }
    add_line(&lines, "nearest_neighbors mean %s reciprocal_pairs %d", real(total / study->n), reciprocal);
    Evaluation labels = evaluate(study, study->targets);
    add_line(&lines, "labels %s", evaluation_text(&labels));
    return lines;
}
static Lines correlation_part(const Study *study) {
    Lines lines = {0};
    add_line(&lines, "correlation %s", names(study->data->feature_names, study->p));
    for (int feature = 0; feature < study->p; ++feature) {
        double values[MAX_FEATURES], first[MAX_OBSERVATIONS], second[MAX_OBSERVATIONS];
        for (int i = 0; i < study->n; ++i) first[i] = study->data->raw[i][feature];
        for (int other = 0; other < study->p; ++other) {
            for (int i = 0; i < study->n; ++i) second[i] = study->data->raw[i][other];
            values[other] = correlation(first, second, study->n);
        }
        add_line(&lines, "%s %s", study->data->feature_names[feature], reals(values, study->p));
    }
    return lines;
}
static Lines histogram_part(const Study *study) {
    int counts[10] = {0};
    for (int i = 0; i < study->n * (study->n - 1) / 2; ++i) ++counts[histogram_bin(study->distance_pairs[i], study->distance_max)];
    int highest = maximum(counts, 10);
    Lines lines = {0};
    add_line(&lines, "histogram");
    for (int bin = 0; bin < 10; ++bin) {
        int length = counts[bin] * 50 / highest;
        char bar[51];
        memset(bar, '#', (size_t)length);
        bar[length] = '\0';
        add_line(&lines, "%s %s %d%s%s", real(bin * study->distance_max / 10), real((bin + 1) * study->distance_max / 10), counts[bin], length ? " " : "", bar);
    }
    return lines;
}
static Lines linkage_part(const Study *study, const LinkageResult *result) {
    const Tree *tree = result->tree;
    const Settings *settings = &study->data->settings;
    double path = 0, minimum_height = tree->heights[0], maximum_height = minimum_height;
    int inversions = 0;
    for (int row = 0; row < study->n - 1; ++row) path += study->delta[tree->order[row]][tree->order[row + 1]];
    for (int step = 0; step < study->n - 1; ++step) {
        minimum_height = fmin(minimum_height, tree->heights[step]);
        maximum_height = fmax(maximum_height, tree->heights[step]);
        if (step && tree->heights[step] < tree->heights[step - 1]) ++inversions;
    }
    Lines lines = {0};
    add_line(&lines, "linkage %s", result->method);
    add_line(&lines, "cophenetic %s leaf_path %s", real(result->coefficient), real(path));
    add_line(&lines, "heights min %s max %s inversions %d", real(minimum_height), real(maximum_height), inversions);
    for (int step = 1; step < study->n - 1; ++step) if (tree->heights[step] < tree->heights[step - 1]) add_line(&lines, "inversion step %d height %s previous %s", step + 1, real(tree->heights[step]), real(tree->heights[step - 1]));
    double ordered[MAX_OBSERVATIONS], gaps[MAX_OBSERVATIONS];
    memcpy(ordered, tree->subtree_heights, (size_t)(study->n - 1) * sizeof(double));
    qsort(ordered, (size_t)study->n - 1, sizeof(double), compare_doubles);
    for (int k = 2; k <= settings->gap_max_k; ++k) gaps[k - 2] = ordered[study->n - k] - ordered[study->n - k - 1];
    int suggested = 2;
    for (int k = 3; k <= settings->gap_max_k; ++k) if (four_digit(gaps[k - 2]) > four_digit(gaps[suggested - 2])) suggested = k;
    add_line(&lines, "gaps %s", reals(gaps, settings->gap_max_k - 1));
    add_line(&lines, "suggested_k %d", suggested);
    double joining[MAX_OBSERVATIONS] = {0};
    int late[MAX_OBSERVATIONS], kinds[3] = {0};
    for (int step = 0; step < study->n - 1; ++step) {
        Merge merge = tree->merges[step];
        if (merge.a < study->n) joining[merge.a] = merge.height;
        if (merge.b < study->n) joining[merge.b] = merge.height;
        ++kinds[2 - (merge.a < study->n) - (merge.b < study->n)];
    }
    sort_indices(late, joining, study->n, true, false);
    Text late_text = {0};
    for (int i = 0; i < settings->list_size; ++i) text_add(&late_text, "%s%s:%s", i ? " " : "", study->data->ids[late[i]], real(joining[late[i]]));
    add_line(&lines, "late_joiners %s", late_text.data);
    add_line(&lines, "merges leaf_leaf %d leaf_cluster %d cluster_cluster %d depth %d", kinds[0], kinds[1], kinds[2], tree->depths[2 * study->n - 2]);
    int matches = match_count(study, result->label_partition);
    add_line(&lines, "label_cut k %d purity %d/%d %s", study->class_count, matches, study->n, real((double)matches / study->n));
    add_line(&lines, "inconsistency depth %s", settings->depth_text);
    for (int step = study->n - settings->inconsistency_count - 1; step < study->n - 1; ++step) {
        double heights[MAX_OBSERVATIONS], deviation = 0, coefficient = 0;
        int count = 0;
        height_sequence(tree, step, settings->depth, heights, &count);
        double mean = sequential_sum(heights, count) / count;
        if (count >= 2) {
            double squares = 0;
            for (int i = 0; i < count; ++i) { double difference = heights[i] - mean; squares += difference * difference; }
            deviation = sqrt(squares / (count - 1));
            coefficient = (tree->heights[step] - mean) / deviation;
        }
        add_line(&lines, "step %d height %s mean %s sd %s count %d coefficient %s", step + 1, real(tree->heights[step]), real(mean), real(deviation), count, real(coefficient));
    }
    for (size_t i = 0; i < settings->height_count; ++i) add_line(&lines, "cut height %s clusters %d %s", real(settings->cut_heights[i]), result->height_cuts[i].groups, evaluation_text(&result->height_cuts[i]));
    for (int i = 0; i < settings->cut_count; ++i) add_line(&lines, "cut k %d %s", settings->cut_counts[i], evaluation_text(&result->count_cuts[i]));
    return lines;
}
static Lines mst_part(const Study *study, const LinkageResult *single) {
    Edge edges[MAX_OBSERVATIONS];
    minimum_spanning_tree(study->delta, study->n, edges);
    double weights[MAX_OBSERVATIONS], total = 0;
    bool linked[MAX_OBSERVATIONS][MAX_OBSERVATIONS] = {{0}}, heights_match = true;
    for (int step = 0; step < study->n - 1; ++step) {
        Edge edge = edges[step];
        weights[step] = edge.weight;
        total += edge.weight;
        linked[edge.parent][edge.child] = linked[edge.child][edge.parent] = true;
    }
    double ordered[MAX_OBSERVATIONS];
    memcpy(ordered, weights, (size_t)(study->n - 1) * sizeof(double));
    qsort(ordered, (size_t)study->n - 1, sizeof(double), compare_doubles);
    int nearest_edges = 0, order[MAX_OBSERVATIONS];
    for (int step = 0; step < study->n - 1; ++step) if (fabs(ordered[step] - single->tree->heights[step]) > 0.000000001) heights_match = false;
    for (int i = 0; i < study->n; ++i) nearest_edges += linked[i][study->neighbors[i]];
    sort_indices(order, weights, study->n - 1, false, false);
    Lines lines = {0};
    add_line(&lines, "mst total %s heights %s nn_edges %d/%d", real(total), heights_match ? "match" : "mismatch", nearest_edges, study->n);
    for (int position = 0; position < study->data->settings.cut_count; ++position) {
        int k = study->data->settings.cut_counts[position], components[MAX_OBSERVATIONS];
        for (int i = 0; i < study->n; ++i) components[i] = i;
        for (int i = 0; i < study->n - k; ++i) {
            Edge edge = edges[order[i]];
            int old = components[edge.child], current = components[edge.parent];
            for (int j = 0; j < study->n; ++j) if (components[j] == old) components[j] = current;
        }
        bool agrees = true;
        for (int i = 0; i < study->n; ++i) for (int j = i + 1; j < study->n; ++j) {
            if ((components[i] == components[j]) != (single->count_cuts[position].partition[i] == single->count_cuts[position].partition[j])) agrees = false;
        }
        add_line(&lines, "mst partition k %d %s", k, agrees ? "match" : "mismatch");
    }
    return lines;
}
static Lines compare_part(const Study *study) {
    Lines lines = {0};
    const char *kinds[] = {"euclidean", "manhattan", "correlation"};
    add_line(&lines, "compare linkage %s k %d", study->data->settings.compare_linkage, study->class_count);
    for (int kind = 0; kind < 3; ++kind) {
        Matrix distances;
        distance_matrix(study->vectors, study->n, study->p, kinds[kind], distances);
        Tree *tree = build_tree(distances, study->n, study->data->settings.compare_linkage);
        int partition[MAX_OBSERVATIONS];
        double pairs[MAX_PAIRS], cophen[MAX_PAIRS];
        cut_into(tree, study->class_count, partition);
        int count = pair_values(distances, study->n, pairs);
        cophenetic(tree, cophen);
        add_line(&lines, "metric %s cophenetic %s silhouette %s ari %s", kinds[kind], real(correlation(pairs, cophen, count)), real(mean_silhouette(partition, study->n, distances)), ari_text(label_ari(study, partition)));
    }
    return lines;
}
static Lines summary_part(const Study *study) {
    const Settings *settings = &study->data->settings;
    int ranking[7];
    double coefficients[7];
    for (int method = 0; method < settings->linkage_count; ++method) coefficients[method] = study->results[method].coefficient;
    sort_indices(ranking, coefficients, settings->linkage_count, true, true);
    Text ordered = {0};
    for (int i = 0; i < settings->linkage_count; ++i) text_add(&ordered, "%s%s", i ? " " : "", study->results[ranking[i]].method);
    Lines lines = {0};
    add_line(&lines, "summary");
    add_line(&lines, "cophenetic_ranking %s", ordered.data);
    for (int i = 0; i < settings->cut_count; ++i) {
        int best = 0;
        for (int method = 1; method < settings->linkage_count; ++method) if (fraction_greater(study->results[method].count_cuts[i].ari, study->results[best].count_cuts[i].ari)) best = method;
        add_line(&lines, "best_ari k %d %s %s", settings->cut_counts[i], study->results[best].method, ari_text(study->results[best].count_cuts[i].ari));
    }
    for (int method = 0; method < settings->linkage_count; ++method) {
        const LinkageResult *result = &study->results[method];
        int best = 0;
        for (int i = 1; i < settings->cut_count; ++i) if (four_digit(result->count_cuts[i].silhouette) > four_digit(result->count_cuts[best].silhouette)) best = i;
        add_line(&lines, "best_silhouette %s k %d %s", result->method, settings->cut_counts[best], real(result->count_cuts[best].silhouette));
    }
    add_line(&lines, "selected %s k %d", study->results[study->chosen].method, study->kappa);
    return lines;
}
static Lines selection_part(const Study *study) {
    const Evaluation *cut = &study->results[study->chosen].count_cuts[study->position];
    Lines lines = {0};
    add_line(&lines, "selected linkage %s k %d ari %s silhouette %s", study->results[study->chosen].method, study->kappa, ari_text(cut->ari), real(cut->silhouette));
    for (int group = 0; group < study->kappa; ++group) {
        int size = study->member_counts[group], medoid = -1, first = -1, second = -1, nearest = -1;
        double silhouette = 0, raw_means[MAX_FEATURES] = {0}, medoid_sum = 0, separation = 0;
        for (int a = 0; a < size; ++a) silhouette += study->silhouettes[study->members[group][a]];
        silhouette /= size;
        for (int feature = 0; feature < study->p; ++feature) {
            for (int a = 0; a < size; ++a) raw_means[feature] += study->data->raw[study->members[group][a]][feature];
            raw_means[feature] /= size;
        }
        for (int a = 0; a < size; ++a) {
            int i = study->members[group][a];
            double total = 0;
            for (int b = 0; b < size; ++b) total += study->delta[i][study->members[group][b]];
            if (medoid < 0 || total < medoid_sum) { medoid = i; medoid_sum = total; }
            for (int b = a + 1; b < size; ++b) {
                int j = study->members[group][b];
                if (first < 0 || study->delta[i][j] > study->delta[first][second]) { first = i; second = j; }
            }
        }
        for (int other = 0; other < study->kappa; ++other) if (other != group) {
            double closest = study->delta[study->members[group][0]][study->members[other][0]];
            for (int a = 0; a < size; ++a) for (int b = 0; b < study->member_counts[other]; ++b) closest = fmin(closest, study->delta[study->members[group][a]][study->members[other][b]]);
            if (nearest < 0 || closest < separation) { nearest = other; separation = closest; }
        }
        int count = study->table[group][study->majority[group]];
        add_line(&lines, "cluster %d size %d silhouette %s majority %s purity %d/%d %s", group + 1, size, real(silhouette), study->classes[study->majority[group]], count, size, real((double)count / size));
        add_line(&lines, "  mean %s", reals(raw_means, study->p));
        add_line(&lines, "  medoid %s diameter %s nearest %d separation %s", study->data->ids[medoid], first < 0 ? "0.0000 - -" : pair_text(study, first, second), nearest + 1, real(separation));
    }
    return lines;
}
static Lines centroid_part(const Study *study) {
    Vectors centers;
    int sizes[MAX_OBSERVATIONS];
    centroids(study, study->selected, study->kappa, centers, sizes);
    Lines lines = {0};
    add_line(&lines, "centroid_distances");
    for (int group = 0; group < study->kappa; ++group) {
        double values[MAX_OBSERVATIONS];
        for (int other = 0; other < study->kappa; ++other) values[other] = sqrt(squared_distance(centers[group], centers[other], study->p));
        add_line(&lines, "%d %s", group + 1, reals(values, study->kappa));
    }
    return lines;
}
static Lines profile_part(const Study *study) {
    int width = 0;
    for (int feature = 0; feature < study->p; ++feature) if ((int)strlen(study->data->feature_names[feature]) > width) width = (int)strlen(study->data->feature_names[feature]);
    Lines lines = {0};
    add_line(&lines, "profile_bars");
    for (int group = 0; group < study->kappa; ++group) {
        add_line(&lines, "cluster %d", group + 1);
        for (int feature = 0; feature < study->p; ++feature) {
            double zeta = 0;
            for (int a = 0; a < study->member_counts[group]; ++a) zeta += (study->data->raw[study->members[group][a]][feature] - study->means[feature]) / study->deviations[feature];
            zeta /= study->member_counts[group];
            double raw_length = floor(fabs(zeta) * 4);
            int length = raw_length >= 10 ? 10 : (int)raw_length;
            char left[11] = "          ", right[11] = "          ";
            if (zeta < 0) memset(left + 10 - length, '#', (size_t)length);
            else memset(right, '#', (size_t)length);
            add_line(&lines, "%-*s %s|%s %s", width, study->data->feature_names[feature], left, right, real(zeta));
        }
    }
    return lines;
}
static Lines contingency_part(const Study *study) {
    int totals[10] = {0};
    Lines lines = {0};
    add_line(&lines, "contingency");
    add_line(&lines, "cluster %s total", names(study->classes, study->class_count));
    for (int group = 0; group < study->kappa; ++group) {
        for (int label = 0; label < study->class_count; ++label) totals[label] += study->table[group][label];
        add_line(&lines, "%d %s %d", group + 1, integers(study->table[group], study->class_count, " "), study->member_counts[group]);
    }
    add_line(&lines, "total %s %d", integers(totals, study->class_count, " "), study->n);
    int matches = match_count(study, study->selected);
    add_line(&lines, "purity %d/%d %s", matches, study->n, real((double)matches / study->n));
    return lines;
}
static Lines misplaced_part(const Study *study) {
    int count = 0;
    Lines lines = {0};
    add_line(&lines, "misplaced");
    for (int i = 0; i < study->n; ++i) if (study->targets[i] - 1 != study->majority[study->selected[i] - 1]) {
        ++count;
        add_line(&lines, "%s label %s cluster %d majority %s", study->data->ids[i], study->data->labels[i], study->selected[i], study->classes[study->majority[study->selected[i] - 1]]);
    }
    add_line(&lines, "count %d", count);
    return lines;
}
static Lines weakest_part(const Study *study) {
    int order[MAX_OBSERVATIONS];
    sort_indices(order, study->silhouettes, study->n, false, false);
    Lines lines = {0};
    add_line(&lines, "weakest");
    for (int position = 0; position < study->data->settings.list_size; ++position) {
        int i = order[position];
        add_line(&lines, "%s label %s cluster %d silhouette %s", study->data->ids[i], study->data->labels[i], study->selected[i], real(study->silhouettes[i]));
    }
    return lines;
}
static Lines feature_part(const Study *study) {
    double ratios[MAX_FEATURES];
    for (int feature = 0; feature < study->p; ++feature) {
        double overall = 0, centers[MAX_OBSERVATIONS] = {0}, between = 0, within = 0;
        for (int i = 0; i < study->n; ++i) overall += study->vectors[i][feature];
        overall /= study->n;
        for (int group = 0; group < study->kappa; ++group) {
            for (int a = 0; a < study->member_counts[group]; ++a) centers[group] += study->vectors[study->members[group][a]][feature];
            centers[group] /= study->member_counts[group];
            double difference = centers[group] - overall;
            between += study->member_counts[group] * difference * difference;
        }
        for (int i = 0; i < study->n; ++i) { double difference = study->vectors[i][feature] - centers[study->selected[i] - 1]; within += difference * difference; }
        ratios[feature] = (between / (study->kappa - 1)) / (within / (study->n - study->kappa));
    }
    int order[MAX_FEATURES];
    sort_indices(order, ratios, study->p, true, true);
    Lines lines = {0};
    add_line(&lines, "features");
    for (int i = 0; i < study->p; ++i) add_line(&lines, "%d %s f_ratio %s", i + 1, study->data->feature_names[order[i]], real(ratios[order[i]]));
    return lines;
}
static char *class_counts(const Study *study, const Tree *tree, int node) {
    int counts[10] = {0};
    for (int i = 0; i < tree->sizes[node]; ++i) ++counts[study->targets[tree->members[node][i]] - 1];
    return integers(counts, study->class_count, "/");
}
static Lines top_merges_part(const Study *study) {
    const Tree *tree = study->results[study->chosen].tree;
    Lines lines = {0};
    add_line(&lines, "top_merges");
    for (int step = study->n - study->data->settings.inconsistency_count - 1; step < study->n - 1; ++step) {
        Merge merge = tree->merges[step];
        add_line(&lines, "step %d height %s a %d %d %s b %d %d %s", step + 1, real(merge.height), merge.a, tree->sizes[merge.a], class_counts(study, tree, merge.a), merge.b, tree->sizes[merge.b], class_counts(study, tree, merge.b));
    }
    return lines;
}
static Lines drop_feature_part(const Study *study) {
    Lines lines = {0};
    add_line(&lines, "drop_feature");
    for (int feature = 0; feature < study->p; ++feature) {
        Vectors vectors;
        for (int i = 0; i < study->n; ++i) {
            int position = 0;
            for (int f = 0; f < study->p; ++f) if (f != feature) vectors[i][position++] = study->vectors[i][f];
        }
        Matrix delta;
        distance_matrix(vectors, study->n, study->p - 1, study->data->settings.distance, delta);
        Tree *tree = build_tree(delta, study->n, study->results[study->chosen].method);
        int partition[MAX_OBSERVATIONS];
        cut_into(tree, study->kappa, partition);
        add_line(&lines, "%s ari_selected %s ari_labels %s", study->data->feature_names[feature], ari_text(partition_ari(partition, study->selected, study->n)), ari_text(label_ari(study, partition)));
    }
    return lines;
}
static Lines refinement_part(const Study *study) {
    Vectors centers;
    int sizes[MAX_OBSERVATIONS], previous[MAX_OBSERVATIONS];
    centroids(study, study->selected, study->kappa, centers, sizes);
    memcpy(previous, study->selected, (size_t)study->n * sizeof(int));
    int iterations = study->data->settings.refine_iterations;
    for (int iteration = 1; iteration <= study->data->settings.refine_iterations; ++iteration) {
        int assignment[MAX_OBSERVATIONS];
        bool same = true;
        for (int i = 0; i < study->n; ++i) {
            int best = 0;
            double best_value = squared_distance(study->vectors[i], centers[0], study->p);
            for (int group = 1; group < study->kappa; ++group) {
                double value = squared_distance(study->vectors[i], centers[group], study->p);
                if (value < best_value) { best = group; best_value = value; }
            }
            assignment[i] = best + 1;
            if (assignment[i] != previous[i]) same = false;
        }
        if (same) { iterations = iteration; break; }
        Vectors updated;
        centroids(study, assignment, study->kappa, updated, sizes);
        for (int group = 0; group < study->kappa; ++group) if (sizes[group]) memcpy(centers[group], updated[group], (size_t)study->p * sizeof(double));
        memcpy(previous, assignment, (size_t)study->n * sizeof(int));
    }
    int changed = 0;
    memset(sizes, 0, sizeof sizes);
    for (int i = 0; i < study->n; ++i) { changed += previous[i] != study->selected[i]; ++sizes[previous[i] - 1]; }
    Lines lines = {0};
    add_line(&lines, "refinement max_iterations %d", study->data->settings.refine_iterations);
    add_line(&lines, "iterations %d changed %d wss %s -> %s", iterations, changed, real(within_sum(study, study->selected)), real(within_sum(study, previous)));
    add_line(&lines, "sizes %s silhouette %s", integers(sizes, study->kappa, " "), real(mean_silhouette(previous, study->n, study->delta)));
    add_line(&lines, "ari_selected %s ari_labels %s", ari_text(partition_ari(previous, study->selected, study->n)), ari_text(label_ari(study, previous)));
    return lines;
}
static void jaccard_values(const Study *study, const int *partition, const int *restricted, int count, double *values) {
    int table[MAX_OBSERVATIONS][MAX_OBSERVATIONS] = {{0}}, columns[MAX_OBSERVATIONS] = {0}, groups = maximum(partition, count);
    for (int i = 0; i < count; ++i) { ++table[restricted[i] - 1][partition[i] - 1]; ++columns[partition[i] - 1]; }
    for (int group = 0; group < study->kappa; ++group) {
        int size = 0;
        for (int other = 0; other < groups; ++other) size += table[group][other];
        Fraction best = fraction(0, 1);
        if (size) for (int other = 0; other < groups; ++other) {
            Fraction candidate = fraction(table[group][other], size + columns[other] - table[group][other]);
            if (fraction_greater(candidate, best)) best = candidate;
        }
        values[group] = fraction_value(best);
    }
}
static Lines stability_part(const Study *study) {
    const Settings *settings = &study->data->settings;
    Integer state = settings->seed;
    int size = study->n * settings->percent / 100;
    double total_ari = 0, totals[MAX_OBSERVATIONS] = {0};
    Lines lines = {0};
    add_line(&lines, "stability replicates %d percent %d seed %" PRId64, settings->replicates, settings->percent, settings->seed);
    for (int replicate = 1; replicate <= settings->replicates; ++replicate) {
        int sample[MAX_OBSERVATIONS], restricted[MAX_OBSERVATIONS], partition[MAX_OBSERVATIONS];
        for (int i = 0; i < study->n; ++i) sample[i] = i;
        for (int i = 0; i < size; ++i) {
            state = 48271 * state % 2147483647;
            int other = i + (int)(state % (study->n - i)), temporary = sample[i];
            sample[i] = sample[other];
            sample[other] = temporary;
        }
        qsort(sample, (size_t)size, sizeof(int), compare_ints);
        Matrix delta;
        for (int i = 0; i < size; ++i) {
            restricted[i] = study->selected[sample[i]];
            for (int j = 0; j < size; ++j) delta[i][j] = study->delta[sample[i]][sample[j]];
        }
        Tree *tree = build_tree(delta, size, study->results[study->chosen].method);
        cut_into(tree, study->kappa, partition);
        Fraction ari = partition_ari(partition, restricted, size);
        double values[MAX_OBSERVATIONS];
        jaccard_values(study, partition, restricted, size, values);
        total_ari += fraction_value(ari);
        for (int group = 0; group < study->kappa; ++group) totals[group] += values[group];
        add_line(&lines, "replicate %d size %d ari %s jaccard %s", replicate, size, ari_text(ari), reals(values, study->kappa));
    }
    for (int group = 0; group < study->kappa; ++group) totals[group] /= settings->replicates;
    add_line(&lines, "mean_ari %s", real(total_ari / settings->replicates));
    add_line(&lines, "mean_jaccard %s", reals(totals, study->kappa));
    return lines;
}
static Lines distance_map_part(const Study *study) {
    const Tree *tree = study->results[study->chosen].tree;
    Lines lines = {0};
    char border[MAX_OBSERVATIONS + 3];
    border[0] = '+';
    memset(border + 1, '-', (size_t)study->n);
    border[study->n + 1] = '+';
    border[study->n + 2] = '\0';
    add_line(&lines, "distance_map %s", study->results[study->chosen].method);
    add_line(&lines, "%s", border);
    for (int row = 0; row < study->n; ++row) {
        char line[MAX_OBSERVATIONS + 3];
        line[0] = '|';
        for (int column = 0; column < study->n; ++column) line[column + 1] = "@%#*+=-:. "[histogram_bin(study->delta[tree->order[row]][tree->order[column]], study->distance_max)];
        line[study->n + 1] = '|';
        line[study->n + 2] = '\0';
        add_line(&lines, "%s", line);
    }
    add_line(&lines, "%s", border);
    return lines;
}
static Study *create_study(Dataset *data) {
    Study *study = allocate(sizeof *study);
    study->data = data;
    study->n = data->count;
    study->p = data->features;
    for (int i = 0; i < study->n; ++i) {
        bool found = false;
        for (int label = 0; label < study->class_count; ++label) if (!strcmp(data->labels[i], study->classes[label])) found = true;
        if (!found) study->classes[study->class_count++] = data->labels[i];
    }
    qsort(study->classes, (size_t)study->class_count, sizeof(char *), compare_names);
    for (int i = 0; i < study->n; ++i) for (int label = 0; label < study->class_count; ++label) if (!strcmp(data->labels[i], study->classes[label])) study->targets[i] = label + 1;
    feature_statistics(data, study->means, study->deviations);
    analysis_vectors(data, study->means, study->deviations, study->vectors);
    distance_matrix(study->vectors, study->n, study->p, data->settings.distance, study->delta);
    int pair_count = pair_values(study->delta, study->n, study->distance_pairs);
    for (int i = 0; i < pair_count; ++i) study->distance_max = fmax(study->distance_max, study->distance_pairs[i]);
    for (int i = 0; i < study->n; ++i) {
        int best = -1;
        for (int j = 0; j < study->n; ++j) if (j != i && (best < 0 || study->delta[i][j] < study->delta[i][best])) best = j;
        study->neighbors[i] = best;
    }
    for (int method = 0; method < data->settings.linkage_count; ++method) {
        LinkageResult *result = &study->results[method];
        result->method = data->settings.linkages[method];
        result->tree = build_tree(study->delta, study->n, result->method);
        cophenetic(result->tree, result->cophenetic);
        result->coefficient = correlation(study->distance_pairs, result->cophenetic, pair_count);
        result->height_cuts = allocate(data->settings.height_count * sizeof(Evaluation));
        result->count_cuts = allocate((size_t)data->settings.cut_count * sizeof(Evaluation));
        int partition[MAX_OBSERVATIONS];
        for (size_t cut = 0; cut < data->settings.height_count; ++cut) {
            cut_at(result->tree, data->settings.cut_heights[cut], partition);
            result->height_cuts[cut] = evaluate(study, partition);
        }
        for (int cut = 0; cut < data->settings.cut_count; ++cut) {
            cut_into(result->tree, data->settings.cut_counts[cut], partition);
            result->count_cuts[cut] = evaluate(study, partition);
        }
        cut_into(result->tree, study->class_count, result->label_partition);
    }
    for (int method = 0; method < data->settings.linkage_count; ++method) for (int cut = 0; cut < data->settings.cut_count; ++cut) {
        if (fraction_greater(study->results[method].count_cuts[cut].ari, study->results[study->chosen].count_cuts[study->position].ari)) { study->chosen = method; study->position = cut; }
    }
    study->kappa = data->settings.cut_counts[study->position];
    memcpy(study->selected, study->results[study->chosen].count_cuts[study->position].partition, (size_t)study->n * sizeof(int));
    for (int i = 0; i < study->n; ++i) {
        int group = study->selected[i] - 1;
        study->members[group][study->member_counts[group]++] = i;
    }
    silhouette_values(study->selected, study->n, study->kappa, study->delta, study->silhouettes);
    class_table(study, study->selected, study->table);
    for (int group = 0; group < study->kappa; ++group) for (int label = 1; label < study->class_count; ++label) {
        if (study->table[group][label] > study->table[group][study->majority[group]]) study->majority[group] = label;
    }
    return study;
}
static Lines linkage_table(const Study *study) {
    Lines lines = {0};
    add_line(&lines, "method,step,a,b,height,size");
    for (int method = 0; method < study->data->settings.linkage_count; ++method) for (int step = 0; step < study->n - 1; ++step) {
        Merge merge = study->results[method].tree->merges[step];
        add_line(&lines, "%s,%d,%d,%d,%s,%d", study->results[method].method, step + 1, merge.a, merge.b, real(merge.height), merge.size);
    }
    return lines;
}
static Lines clusters_table(const Study *study) {
    const Settings *settings = &study->data->settings;
    Text header = {0};
    text_add(&header, "id,label");
    for (int method = 0; method < settings->linkage_count; ++method) {
        for (size_t cut = 0; cut < settings->height_count; ++cut) text_add(&header, ",%s_h%zu", settings->linkages[method], cut + 1);
        for (int cut = 0; cut < settings->cut_count; ++cut) text_add(&header, ",%s_k%d", settings->linkages[method], settings->cut_counts[cut]);
    }
    Lines lines = {0};
    add_line(&lines, "%s", header.data);
    for (int i = 0; i < study->n; ++i) {
        Text row = {0};
        text_add(&row, "%s,%s", study->data->ids[i], study->data->labels[i]);
        for (int method = 0; method < settings->linkage_count; ++method) {
            for (size_t cut = 0; cut < settings->height_count; ++cut) text_add(&row, ",%d", study->results[method].height_cuts[cut].partition[i]);
            for (int cut = 0; cut < settings->cut_count; ++cut) text_add(&row, ",%d", study->results[method].count_cuts[cut].partition[i]);
        }
        add_line(&lines, "%s", row.data);
    }
    return lines;
}
static Lines dendrogram_report(const Study *study) {
    Lines lines = {0};
    const Settings *settings = &study->data->settings;
    for (int method = 0; method < settings->linkage_count; ++method) {
        const LinkageResult *result = &study->results[method];
        double maximum_height = result->tree->heights[0];
        for (int step = 1; step < study->n - 1; ++step) maximum_height = fmax(maximum_height, result->tree->heights[step]);
        int *columns = allocate(settings->height_count * sizeof(int));
        for (size_t cut = 0; cut < settings->height_count; ++cut) columns[cut] = column_position(settings->cut_heights[cut], maximum_height, settings->width);
        Lines part = {0};
        add_line(&part, "dendrogram %s height_max %s width %d", result->method, real(maximum_height), settings->width);
        append_lines(&part, dendrogram_rows(result->tree, study->data, maximum_height, columns, settings->height_count, settings->width));
        for (size_t cut = 0; cut < settings->height_count; ++cut) add_line(&part, "cut %s column %s", real(settings->cut_heights[cut]), columns[cut] <= settings->width ? format("%d", columns[cut]) : "-");
        paragraph(&lines, part);
    }
    return lines;
}
static Lines trees_report(const Study *study) {
    Lines lines = {0};
    for (int method = 0; method < study->data->settings.linkage_count; ++method) {
        const LinkageResult *result = &study->results[method];
        add_line(&lines, "%s %s;", result->method, newick(result->tree, 2 * study->n - 2, study->data->ids));
    }
    return lines;
}
static Lines validation_report(const Study *study) {
    const Settings *settings = &study->data->settings;
    Lines lines = {0};
    paragraph(&lines, data_part(study));
    paragraph(&lines, correlation_part(study));
    paragraph(&lines, histogram_part(study));
    const LinkageResult *single = NULL;
    for (int method = 0; method < settings->linkage_count; ++method) {
        paragraph(&lines, linkage_part(study, &study->results[method]));
        if (!strcmp(study->results[method].method, "single")) single = &study->results[method];
    }
    if (single) paragraph(&lines, mst_part(study, single));
    paragraph(&lines, compare_part(study));
    Lines part = {0};
    add_line(&part, "cophenetic_matrix");
    add_line(&part, "linkage %s", names(settings->linkages, settings->linkage_count));
    int pairs = study->n * (study->n - 1) / 2;
    for (int method = 0; method < settings->linkage_count; ++method) {
        double values[7];
        for (int other = 0; other < settings->linkage_count; ++other) values[other] = correlation(study->results[method].cophenetic, study->results[other].cophenetic, pairs);
        add_line(&part, "%s %s", study->results[method].method, reals(values, settings->linkage_count));
    }
    paragraph(&lines, part);
    part = (Lines){0};
    add_line(&part, "agreement k %d", study->class_count);
    add_line(&part, "linkage %s", names(settings->linkages, settings->linkage_count));
    for (int method = 0; method < settings->linkage_count; ++method) {
        double values[7];
        for (int other = 0; other < settings->linkage_count; ++other) values[other] = fraction_value(partition_ari(study->results[method].label_partition, study->results[other].label_partition, study->n));
        add_line(&part, "%s %s", study->results[method].method, reals(values, settings->linkage_count));
    }
    paragraph(&lines, part);
    paragraph(&lines, summary_part(study));
    return lines;
}
static Lines profiles_report(const Study *study) {
    Lines lines = {0};
    paragraph(&lines, selection_part(study));
    paragraph(&lines, centroid_part(study));
    paragraph(&lines, profile_part(study));
    paragraph(&lines, contingency_part(study));
    paragraph(&lines, misplaced_part(study));
    paragraph(&lines, weakest_part(study));
    paragraph(&lines, feature_part(study));
    paragraph(&lines, top_merges_part(study));
    paragraph(&lines, drop_feature_part(study));
    paragraph(&lines, refinement_part(study));
    paragraph(&lines, stability_part(study));
    paragraph(&lines, distance_map_part(study));
    return lines;
}
int main(void) {
    Study *study = create_study(read_dataset());
    mkdir("output", 0777);
    write_lines("linkage.csv", linkage_table(study));
    write_lines("clusters.csv", clusters_table(study));
    write_lines("dendrogram.txt", dendrogram_report(study));
    write_lines("trees.txt", trees_report(study));
    write_lines("validation.txt", validation_report(study));
    write_lines("profiles.txt", profiles_report(study));
    return 0;
}
