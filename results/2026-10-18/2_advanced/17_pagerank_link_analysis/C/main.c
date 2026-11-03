#include "analysis.h"

static const char *regions[] = {"CORE", "IN", "OUT", "TUBE", "IN_TENDRIL", "OUT_TENDRIL", "OTHER"};
static const char *quantities[] = {"in_degree", "pagerank", "cheirank", "authority", "hub", "trustrank", "harmonic"};
typedef struct {
    Input input;
    Graph graph, undirected, inter, host_graph;
    Components components, host_components;
    int index[10000], host_of[500], host_count, core, kcore[500], region[500], trust_distance[500];
    char *host_names[500];
    int ignored_counts[3], incoming[500], outgoing[500], condensation_edges, condensation_depth;
    int weak_count, weak_largest, undirected_edges, closed, possible, eligible, degeneracy;
    int reachable_pairs, distance_sum, diameter, diameter_source, diameter_target, histogram[500];
    double average_clustering, harmonic[500], trust_ratio[500];
    PageRank pagerank, cheirank, trustrank, sweep[5], demoted, personalized[20], host_rank;
    Hits global_hits;
    int order[500], rank[500], chei_rank[500], demoted_rank[500], host_positions[500];
    bool suspects[500], suspect_hosts[500];
    int suspect_count, removed;
    Lines ignored, queries;
} Analysis;
static void rank_order(const double *values, int count, int *order) {
    Integer keys[500];
    for (int i = 0; i < count; ++i) {
        keys[i] = scaled(values[i], 6);
        int j = i;
        while (j && keys[order[j - 1]] < keys[i]) { order[j] = order[j - 1]; --j; }
        order[j] = i;
    }
}
static void positions(const int *order, int count, int *ranks) { for (int i = 0; i < count; ++i) ranks[order[i]] = i + 1; }
static int top_list(const double *values, int count, int limit, int *top) {
    int order[500], size = 0;
    rank_order(values, count, order);
    for (int i = 0; i < count && size < limit; ++i) if (scaled(values[order[i]], 6) > 0) top[size++] = order[i];
    return size;
}
static char *page_ids(const Analysis *analysis, const int *nodes, int count) {
    char *result = "";
    for (int i = 0; i < count; ++i) result = format("%s%s%d", result, i ? " " : "", analysis->input.pages[nodes[i]].id);
    return result;
}
static int collect(const bool *members, int count, int *result) { int size = 0; for (int i = 0; i < count; ++i) if (members[i]) result[size++] = i; return size; }
static double total(const double *values, const bool *members, int count) { double result = 0; for (int i = 0; i < count; ++i) if (!members || members[i]) result += values[i]; return result; }
static int representative(const Analysis *analysis, const bool *members) {
    int best = -1;
    for (int i = 0; i < analysis->input.count; ++i) if (members[i] && (best < 0 || analysis->rank[i] < analysis->rank[best])) best = i;
    return best;
}
static void rank_lines(const Analysis *analysis, Lines *lines, const int *nodes, int count, const double *values) {
    for (int i = 0; i < count; ++i) {
        const Page *page = &analysis->input.pages[nodes[i]];
        add_line(lines, "%d %d %s %s %s", i + 1, page->id, fixed(values[nodes[i]], 6), page->host, page->title);
    }
}
static void score_block(const Analysis *analysis, Lines *lines, const char *name, const double *values) {
    int top[500], count = top_list(values, analysis->input.count, analysis->input.settings.top_k, top);
    add_line(lines, "%s top %d", name, analysis->input.settings.top_k);
    rank_lines(analysis, lines, top, count, values);
}
static char *kendall(const Integer *first, const Integer *second, int count) {
    Integer concordant = 0, discordant = 0;
    for (int i = 0; i < count; ++i) for (int j = i + 1; j < count; ++j) {
        Integer dx = first[i] - first[j], dy = second[i] - second[j];
        if (!dx || !dy) continue;
        if ((dx > 0) == (dy > 0)) ++concordant; else ++discordant;
    }
    return fraction(concordant - discordant, (Integer)count * (count - 1) / 2);
}
static int compare_strings(const void *first, const void *second) { return strcmp(*(char *const *)first, *(char *const *)second); }
static void build_graphs(Analysis *analysis) {
    int n = analysis->input.count;
    for (int id = 0; id < 10000; ++id) analysis->index[id] = -1;
    for (int i = 0; i < n; ++i) {
        analysis->index[analysis->input.pages[i].id] = i;
        char *host = analysis->input.pages[i].host;
        bool found = false;
        for (int h = 0; h < analysis->host_count; ++h) if (!strcmp(analysis->host_names[h], host)) found = true;
        if (!found) analysis->host_names[analysis->host_count++] = host;
    }
    qsort(analysis->host_names, (size_t)analysis->host_count, sizeof(char *), compare_strings);
    for (int i = 0; i < n; ++i) {
        int h = 0;
        while (strcmp(analysis->host_names[h], analysis->input.pages[i].host)) ++h;
        analysis->host_of[i] = h;
    }
    int *weights = allocate((size_t)n * n * sizeof(int));
    const char *reasons[] = {"unknown", "self", "duplicate"};
    for (int r = 0; r < analysis->input.record_count; ++r) {
        Record record = analysis->input.records[r];
        int u = analysis->index[record.source], v = analysis->index[record.target], reason = -1;
        if (u < 0 || v < 0) reason = 0;
        else if (u == v) reason = 1;
        else if (weights[u * n + v]) reason = 2;
        if (reason >= 0) {
            ++analysis->ignored_counts[reason];
            add_line(&analysis->ignored, "ignored line %d %d,%d %s", record.line, record.source, record.target, reasons[reason]);
        } else weights[u * n + v] = 1;
    }
    analysis->graph = graph_from_weights(n, weights);
    int *undirected = allocate((size_t)n * n * sizeof(int)), *inter = allocate((size_t)n * n * sizeof(int));
    int h = analysis->host_count;
    int *host_weights = allocate((size_t)h * h * sizeof(int));
    for (int u = 0; u < n; ++u) for (int v = 0; v < n; ++v) if (weights[u * n + v]) {
        undirected[u * n + v] = undirected[v * n + u] = 1;
        if (analysis->host_of[u] != analysis->host_of[v]) {
            inter[u * n + v] = 1;
            ++host_weights[analysis->host_of[u] * h + analysis->host_of[v]];
        }
    }
    analysis->undirected = graph_from_weights(n, undirected);
    analysis->inter = graph_from_weights(n, inter);
    analysis->host_graph = graph_from_weights(h, host_weights);
    analysis->host_components = strong_components(&analysis->host_graph);
}
static void graph_statistics(Analysis *analysis) {
    int n = analysis->input.count;
    Graph *graph = &analysis->graph, *undirected = &analysis->undirected;
    int remaining[500], weak_labels[500], weak_sizes[500] = {0};
    bool removed[500] = {0};
    double local_sum = 0;
    for (int v = 0; v < n; ++v) {
        Nodes neighbors = undirected->out[v];
        int degree = neighbors.count;
        analysis->undirected_edges += degree;
        remaining[v] = degree;
        if (degree < 2) continue;
        int closed = 0, possible = degree * (degree - 1) / 2;
        for (int i = 0; i < degree; ++i) for (int j = i + 1; j < degree; ++j) if (undirected->weights[neighbors.values[i] * n + neighbors.values[j]]) ++closed;
        analysis->closed += closed; analysis->possible += possible; ++analysis->eligible;
        local_sum += (double)closed / possible;
    }
    analysis->undirected_edges /= 2;
    analysis->average_clustering = local_sum / analysis->eligible;
    int level = 0, left = n;
    while (left) {
        int chosen = -1;
        for (int v = 0; v < n; ++v) if (!removed[v] && remaining[v] <= level) { chosen = v; break; }
        if (chosen < 0) { ++level; continue; }
        removed[chosen] = true; analysis->kcore[chosen] = level; --left;
        for (int j = 0; j < undirected->out[chosen].count; ++j) if (!removed[undirected->out[chosen].values[j]]) --remaining[undirected->out[chosen].values[j]];
    }
    analysis->degeneracy = level;
    analysis->weak_count = weak_components(graph, weak_labels);
    for (int v = 0; v < n; ++v) ++weak_sizes[weak_labels[v]];
    for (int c = 0; c < analysis->weak_count; ++c) if (weak_sizes[c] > analysis->weak_largest) analysis->weak_largest = weak_sizes[c];
    analysis->components = strong_components(graph);
    Components *components = &analysis->components;
    int c = components->count;
    int *condensation = allocate((size_t)c * c * sizeof(int));
    int pending[500] = {0}, depth[500] = {0};
    for (int u = 0; u < n; ++u) for (int j = 0; j < graph->out[u].count; ++j) {
        int v = graph->out[u].values[j], first = components->labels[u], second = components->labels[v];
        if (first == second) continue;
        ++analysis->outgoing[first]; ++analysis->incoming[second];
        if (!condensation[first * c + second]) { condensation[first * c + second] = 1; ++pending[second]; ++analysis->condensation_edges; }
    }
    int ready[500], count = 0;
    for (int i = 0; i < c; ++i) {
        if (components->sizes[i] > components->sizes[analysis->core]) analysis->core = i;
        if (!pending[i]) ready[count++] = i;
    }
    while (count) {
        int u = ready[--count];
        for (int v = 0; v < c; ++v) if (condensation[u * c + v]) {
            if (depth[u] + 1 > depth[v]) depth[v] = depth[u] + 1;
            if (depth[v] > analysis->condensation_depth) analysis->condensation_depth = depth[v];
            if (!--pending[v]) ready[count++] = v;
        }
    }
    bool starts[500] = {0}, forward[500], backward[500], from_in[500], to_out[500];
    for (int v = 0; v < n; ++v) starts[v] = components->labels[v] == analysis->core;
    reachable(graph, starts, false, forward); reachable(graph, starts, true, backward);
    for (int v = 0; v < n; ++v) analysis->region[v] = starts[v] ? 0 : backward[v] ? 1 : forward[v] ? 2 : 6;
    for (int v = 0; v < n; ++v) starts[v] = analysis->region[v] == 1;
    reachable(graph, starts, false, from_in);
    for (int v = 0; v < n; ++v) starts[v] = analysis->region[v] == 2;
    reachable(graph, starts, true, to_out);
    for (int v = 0; v < n; ++v) if (analysis->region[v] == 6) analysis->region[v] = from_in[v] && to_out[v] ? 3 : from_in[v] ? 4 : to_out[v] ? 5 : 6;
    for (int source = 0; source < n; ++source) {
        memset(starts, 0, sizeof starts); starts[source] = true;
        int distances[500]; bfs_distances(graph, starts, distances);
        for (int target = 0; target < n; ++target) {
            int steps = distances[target];
            if (source == target || steps < 0) continue;
            ++analysis->reachable_pairs; analysis->distance_sum += steps; ++analysis->histogram[steps];
            analysis->harmonic[target] += 1.0 / steps;
            if (steps > analysis->diameter) { analysis->diameter = steps; analysis->diameter_source = source; analysis->diameter_target = target; }
        }
    }
}
static void compute_scores(Analysis *analysis) {
    int n = analysis->input.count;
    Settings settings = analysis->input.settings;
    bool everyone[500], trusted[500] = {0};
    for (int v = 0; v < n; ++v) everyone[v] = true;
    for (int i = 0; i < settings.trusted_count; ++i) trusted[analysis->index[settings.trusted[i]]] = true;
    int *reverse = allocate((size_t)n * n * sizeof(int));
    for (int u = 0; u < n; ++u) for (int v = 0; v < n; ++v) reverse[v * n + u] = analysis->graph.weights[u * n + v];
    Graph reversed = graph_from_weights(n, reverse);
    analysis->pagerank = power_iteration(&analysis->graph, everyone, settings.damping, settings.iterations, settings.tolerance);
    analysis->cheirank = power_iteration(&reversed, everyone, settings.damping, settings.iterations, settings.tolerance);
    analysis->trustrank = power_iteration(&analysis->graph, trusted, settings.damping, settings.iterations, settings.tolerance);
    analysis->global_hits = hits(&analysis->inter, everyone, settings.hits_iterations);
    rank_order(analysis->pagerank.values, n, analysis->order); positions(analysis->order, n, analysis->rank);
    int order[500]; rank_order(analysis->cheirank.values, n, order); positions(order, n, analysis->chei_rank);
    bfs_distances(&analysis->graph, trusted, analysis->trust_distance);
    for (int v = 0; v < n; ++v) analysis->trust_ratio[v] = analysis->trustrank.values[v] / analysis->pagerank.values[v];
    for (int s = 0; s < settings.sweep_count; ++s) analysis->sweep[s] = power_iteration(&analysis->graph, everyone, settings.sweep[s], settings.iterations, settings.tolerance);
    for (int r = 0; r < settings.spam_top; ++r) {
        int v = analysis->order[r];
        if ((double)scaled(analysis->trust_ratio[v], 4) / 10000 < settings.spam_threshold) { analysis->suspects[v] = true; ++analysis->suspect_count; analysis->suspect_hosts[analysis->host_of[v]] = true; }
    }
    if (analysis->suspect_count) {
        int *kept = allocate((size_t)n * n * sizeof(int));
        for (int u = 0; u < n; ++u) for (int v = 0; v < n; ++v) if (analysis->graph.weights[u * n + v]) {
            if (analysis->host_of[u] == analysis->host_of[v] && analysis->suspect_hosts[analysis->host_of[u]]) ++analysis->removed;
            else kept[u * n + v] = 1;
        }
        Graph graph = graph_from_weights(n, kept);
        analysis->demoted = power_iteration(&graph, everyone, settings.damping, settings.iterations, settings.tolerance);
        rank_order(analysis->demoted.values, n, order); positions(order, n, analysis->demoted_rank);
    }
    for (int h = 0; h < analysis->host_count; ++h) everyone[h] = true;
    analysis->host_rank = power_iteration(&analysis->host_graph, everyone, settings.damping, settings.iterations, settings.tolerance);
    rank_order(analysis->host_rank.values, analysis->host_count, order); positions(order, analysis->host_count, analysis->host_positions);
}
static void salsa_scores(const Graph *graph, double *values) {
    int n = graph->count;
    int *adjacent = allocate((size_t)n * n * sizeof(int));
    for (int u = 0; u < n; ++u) {
        Nodes targets = graph->out[u];
        for (int j = 1; j < targets.count; ++j) {
            int first = targets.values[j - 1], second = targets.values[j];
            adjacent[first * n + second] = adjacent[second * n + first] = 1;
        }
    }
    Graph connections = graph_from_weights(n, adjacent);
    int labels[500], sizes[500] = {0}, mass[500] = {0}, side = 0;
    weak_components(&connections, labels);
    for (int v = 0; v < n; ++v) if (graph->in[v].count) { ++side; ++sizes[labels[v]]; mass[labels[v]] += graph->in[v].count; }
    for (int v = 0; v < n; ++v) values[v] = graph->in[v].count ? (double)(sizes[labels[v]] * graph->in[v].count) / (side * mass[labels[v]]) : 0;
}
static bool matches(const Page *page, const Query *query) {
    for (int i = 0; i < query->word_count; ++i) {
        const char *word = query->words[i];
        bool exclude = word[0] == '-', found = false;
        if (exclude) ++word;
        for (int w = 0; w < page->word_count; ++w) if (!strcmp(word, page->words[w])) found = true;
        if (exclude ? found : !found) return false;
    }
    return true;
}
static int overlap(const int *first, int first_count, const int *second, int second_count) {
    int result = 0;
    for (int i = 0; i < first_count; ++i) for (int j = 0; j < second_count; ++j) if (first[i] == second[j]) { ++result; break; }
    return result;
}
static int ranked_counts(const int *counts, int n, int limit, int *result) {
    int size = 0;
    for (int v = 0; v < n; ++v) {
        if (!counts[v]) continue;
        int j = size++;
        while (j && counts[result[j - 1]] < counts[v]) { result[j] = result[j - 1]; --j; }
        result[j] = v;
    }
    return size < limit ? size : limit;
}
static void query_scores(Analysis *analysis) {
    int n = analysis->input.count;
    Settings settings = analysis->input.settings;
    Graph *graph = &analysis->graph;
    for (int q = 0; q < analysis->input.query_count; ++q) {
        Query *query = &analysis->input.queries[q];
        if (q) add_line(&analysis->queries, "");
        char *heading = format("query %d words", q + 1);
        for (int w = 0; w < query->word_count; ++w) heading = format("%s %s", heading, query->words[w]);
        heading = format("%s seeds", heading);
        for (int s = 0; s < query->seed_count; ++s) heading = format("%s %d", heading, query->seeds[s]);
        add_line(&analysis->queries, "%s", heading);
        int matched[500], match_count = 0;
        for (int r = 0; r < n; ++r) if (matches(&analysis->input.pages[analysis->order[r]], query)) matched[match_count++] = analysis->order[r];
        int root_count = match_count < settings.root_limit ? match_count : settings.root_limit;
        bool base[500] = {0};
        for (int r = 0; r < root_count; ++r) {
            int v = matched[r]; base[v] = true;
            for (int j = 0; j < graph->out[v].count && j < settings.neighbor_limit; ++j) base[graph->out[v].values[j]] = true;
            for (int j = 0; j < graph->in[v].count && j < settings.neighbor_limit; ++j) base[graph->in[v].values[j]] = true;
        }
        int base_count = 0, dropped = 0, link_count = 0;
        int *weights = allocate((size_t)n * n * sizeof(int)), *reverse = allocate((size_t)n * n * sizeof(int));
        for (int u = 0; u < n; ++u) {
            if (base[u]) ++base_count;
            for (int j = 0; j < graph->out[u].count; ++j) {
                int v = graph->out[u].values[j];
                if (!base[u] || !base[v]) continue;
                if (analysis->host_of[u] == analysis->host_of[v]) ++dropped;
                else { weights[u * n + v] = reverse[v * n + u] = 1; ++link_count; }
            }
        }
        add_line(&analysis->queries, "matched %d root %d base %d links %d dropped_intra_host %d", match_count, root_count, base_count, link_count, dropped);
        add_line(&analysis->queries, "results");
        rank_lines(analysis, &analysis->queries, matched, match_count < settings.top_k ? match_count : settings.top_k, analysis->pagerank.values);
        bool seeds[500] = {0}, reached[500];
        for (int s = 0; s < query->seed_count; ++s) seeds[analysis->index[query->seeds[s]]] = true;
        analysis->personalized[q] = power_iteration(graph, seeds, settings.damping, settings.iterations, settings.tolerance);
        reachable(graph, seeds, false, reached);
        int reach = 0;
        for (int v = 0; v < n; ++v) if (reached[v]) ++reach;
        add_line(&analysis->queries, "personalized reach %d seed_mass %s", reach, fixed(total(analysis->personalized[q].values, seeds, n), 6));
        int top[500], count = top_list(analysis->personalized[q].values, n, settings.top_k, top), global_overlap = 0;
        rank_lines(analysis, &analysis->queries, top, count, analysis->personalized[q].values);
        for (int i = 0; i < count; ++i) if (analysis->rank[top[i]] <= settings.top_k) ++global_overlap;
        add_line(&analysis->queries, "overlap_with_global %d", global_overlap);
        if (!link_count) { add_line(&analysis->queries, "hits none"); continue; }
        Graph subgraph = graph_from_weights(n, weights), reversed = graph_from_weights(n, reverse);
        Hits scores = hits(&subgraph, base, settings.hits_iterations);
        double salsa_authority[500], salsa_hub[500];
        salsa_scores(&subgraph, salsa_authority); salsa_scores(&reversed, salsa_hub);
        int authority_top[500], hub_top[500], salsa_a_top[500], salsa_h_top[500];
        int a_count = top_list(scores.authority, n, settings.top_k, authority_top), h_count = top_list(scores.hub, n, settings.top_k, hub_top);
        int sa_count = top_list(salsa_authority, n, settings.top_k, salsa_a_top), sh_count = top_list(salsa_hub, n, settings.top_k, salsa_h_top);
        add_line(&analysis->queries, "hits authorities"); rank_lines(analysis, &analysis->queries, authority_top, a_count, scores.authority);
        add_line(&analysis->queries, "hits hubs"); rank_lines(analysis, &analysis->queries, hub_top, h_count, scores.hub);
        add_line(&analysis->queries, "salsa authorities"); rank_lines(analysis, &analysis->queries, salsa_a_top, sa_count, salsa_authority);
        add_line(&analysis->queries, "salsa hubs"); rank_lines(analysis, &analysis->queries, salsa_h_top, sh_count, salsa_hub);
        bool hosts[500] = {0}; int host_count = 0;
        for (int i = 0; i < a_count; ++i) if (!hosts[analysis->host_of[authority_top[i]]]) { hosts[analysis->host_of[authority_top[i]]] = true; ++host_count; }
        add_line(&analysis->queries, "hits_salsa_overlap authorities %d hubs %d authority_hosts %d", overlap(authority_top, a_count, salsa_a_top, sa_count), overlap(hub_top, h_count, salsa_h_top, sh_count), host_count);
        int cited = authority_top[0], citing = hub_top[0], cocitation[500] = {0}, coupling[500] = {0};
        for (int i = 0; i < graph->in[cited].count; ++i) {
            int u = graph->in[cited].values[i];
            for (int j = 0; j < graph->out[u].count; ++j) { int v = graph->out[u].values[j]; if (v != cited) ++cocitation[v]; }
        }
        for (int i = 0; i < graph->out[citing].count; ++i) {
            int v = graph->out[citing].values[i];
            for (int j = 0; j < graph->in[v].count; ++j) { int u = graph->in[v].values[j]; if (u != citing) ++coupling[u]; }
        }
        add_line(&analysis->queries, "related_to %d citing %d", analysis->input.pages[cited].id, graph->in[cited].count);
        count = ranked_counts(cocitation, n, settings.top_k, top);
        for (int i = 0; i < count; ++i) { Page page = analysis->input.pages[top[i]]; add_line(&analysis->queries, "%d %d %d %s %s", i + 1, page.id, cocitation[top[i]], page.host, page.title); }
        add_line(&analysis->queries, "coupled_to %d cited %d", analysis->input.pages[citing].id, graph->out[citing].count);
        count = ranked_counts(coupling, n, settings.top_k, top);
        for (int i = 0; i < count; ++i) { Page page = analysis->input.pages[top[i]]; add_line(&analysis->queries, "%d %d %d %s %s", i + 1, page.id, coupling[top[i]], page.host, page.title); }
    }
}
static Lines graph_stats_lines(const Analysis *analysis) {
    Lines lines = {0};
    const Graph *graph = &analysis->graph;
    int n = graph->count, links = 0, intra = 0, reciprocal = 0, max_in = 0, max_out = 0;
    int in_distribution[500] = {0}, out_distribution[500] = {0}, core_distribution[500] = {0};
    bool dangling[500], no_in[500], most_in[500], most_out[500];
    for (int u = 0; u < n; ++u) {
        links += graph->out[u].count;
        if (graph->in[u].count > max_in) max_in = graph->in[u].count;
        if (graph->out[u].count > max_out) max_out = graph->out[u].count;
        ++in_distribution[graph->in[u].count]; ++out_distribution[graph->out[u].count]; ++core_distribution[analysis->kcore[u]];
        dangling[u] = !graph->out[u].count; no_in[u] = !graph->in[u].count;
        for (int j = 0; j < graph->out[u].count; ++j) {
            int v = graph->out[u].values[j];
            if (analysis->host_of[u] == analysis->host_of[v]) ++intra;
            if (graph->weights[v * n + u]) ++reciprocal;
        }
    }
    for (int u = 0; u < n; ++u) { most_in[u] = graph->in[u].count == max_in; most_out[u] = graph->out[u].count == max_out; }
    add_line(&lines, "pages %d", n); add_line(&lines, "hosts %d", analysis->host_count);
    add_line(&lines, "link_rows %d", analysis->input.record_count); add_line(&lines, "links %d", links);
    add_line(&lines, "ignored_unknown %d", analysis->ignored_counts[0]); add_line(&lines, "ignored_self %d", analysis->ignored_counts[1]); add_line(&lines, "ignored_duplicate %d", analysis->ignored_counts[2]);
    extend(&lines, analysis->ignored);
    add_line(&lines, "intra_host_links %d", intra); add_line(&lines, "inter_host_links %d", links - intra);
    add_line(&lines, "mean_degree %s", fixed((double)links / n, 4)); add_line(&lines, "reciprocity %s", fraction(reciprocal, links));
    int nodes[500], count = collect(dangling, n, nodes);
    add_line(&lines, "dangling %d%s%s", count, count ? " " : "", page_ids(analysis, nodes, count));
    count = collect(no_in, n, nodes);
    add_line(&lines, "no_in_links %d%s%s", count, count ? " " : "", page_ids(analysis, nodes, count));
    count = collect(most_in, n, nodes); add_line(&lines, "max_in_degree %d pages %s", max_in, page_ids(analysis, nodes, count));
    count = collect(most_out, n, nodes); add_line(&lines, "max_out_degree %d pages %s", max_out, page_ids(analysis, nodes, count));
    add_line(&lines, ""); add_line(&lines, "in_degree_distribution");
    for (int degree = 0; degree < n; ++degree) if (in_distribution[degree]) add_line(&lines, "%d %d", degree, in_distribution[degree]);
    add_line(&lines, ""); add_line(&lines, "out_degree_distribution");
    for (int degree = 0; degree < n; ++degree) if (out_distribution[degree]) add_line(&lines, "%d %d", degree, out_distribution[degree]);
    add_line(&lines, ""); add_line(&lines, "undirected_links %d", analysis->undirected_edges);
    add_line(&lines, "transitivity %s", fraction(analysis->closed, analysis->possible));
    add_line(&lines, "average_clustering %s pages %d", fixed(analysis->average_clustering, 4), analysis->eligible);
    add_line(&lines, "degeneracy %d pages %d", analysis->degeneracy, core_distribution[analysis->degeneracy]); add_line(&lines, "core_distribution");
    for (int core = 0; core < n; ++core) if (core_distribution[core]) add_line(&lines, "%d %d", core, core_distribution[core]);
    const Components *components = &analysis->components;
    int singletons = 0;
    for (int c = 0; c < components->count; ++c) if (components->sizes[c] == 1) ++singletons;
    add_line(&lines, ""); add_line(&lines, "strong_components %d largest %d singletons %d condensation_links %d", components->count, components->sizes[analysis->core], singletons, analysis->condensation_edges);
    add_line(&lines, "weak_components %d largest %d", analysis->weak_count, analysis->weak_largest);
    add_line(&lines, "condensation_depth %d", analysis->condensation_depth);
    for (int c = 0; c < components->count; ++c) {
        if (components->sizes[c] < 2) continue;
        bool members[500];
        for (int v = 0; v < n; ++v) members[v] = components->labels[v] == c;
        add_line(&lines, "scc %d size %d min %d incoming %d outgoing %d pagerank %s%s", c + 1, components->sizes[c], analysis->input.pages[components->minimum[c]].id, analysis->incoming[c], analysis->outgoing[c], fixed(total(analysis->pagerank.values, members, n), 6), analysis->outgoing[c] ? "" : " sink");
    }
    add_line(&lines, ""); add_line(&lines, "bowtie core_scc %d", analysis->core + 1);
    for (int region = 0; region < 7; ++region) {
        bool members[500];
        for (int v = 0; v < n; ++v) members[v] = analysis->region[v] == region;
        count = collect(members, n, nodes);
        char *line = format("%s %d pagerank %s", regions[region], count, fixed(total(analysis->pagerank.values, members, n), 6));
        if (count) line = format("%s top %d", line, analysis->input.pages[representative(analysis, members)].id);
        if (count && count <= 10) line = format("%s pages %s", line, page_ids(analysis, nodes, count));
        add_line(&lines, "%s", line);
    }
    int region_links[7][7] = {{0}};
    for (int u = 0; u < n; ++u) for (int j = 0; j < graph->out[u].count; ++j) ++region_links[analysis->region[u]][analysis->region[graph->out[u].values[j]]];
    add_line(&lines, "region_links");
    for (int a = 0; a < 7; ++a) for (int b = 0; b < 7; ++b) if (region_links[a][b]) add_line(&lines, "%s %s %d", regions[a], regions[b], region_links[a][b]);
    add_line(&lines, ""); add_line(&lines, "distances");
    add_line(&lines, "reachable_pairs %d", analysis->reachable_pairs); add_line(&lines, "average %s", fraction(analysis->distance_sum, analysis->reachable_pairs));
    add_line(&lines, "diameter %d from %d to %d", analysis->diameter, analysis->input.pages[analysis->diameter_source].id, analysis->input.pages[analysis->diameter_target].id);
    int cumulative = 0, effective = analysis->diameter;
    for (int d = 1; d <= analysis->diameter; ++d) { cumulative += analysis->histogram[d]; if (10 * cumulative >= 9 * analysis->reachable_pairs) { effective = d; break; } }
    add_line(&lines, "effective_diameter %d", effective);
    for (int d = 1; d <= analysis->diameter; ++d) add_line(&lines, "%d %d", d, analysis->histogram[d]);
    return lines;
}
static Lines pagerank_lines(const Analysis *analysis) {
    Lines lines = {0};
    add_line(&lines, "id,in_degree,out_degree,scc,region,kcore,harmonic,pagerank,pagerank_rank,cheirank,cheirank_rank,authority,hub,trustrank,trust_ratio,trust_distance");
    for (int v = 0; v < analysis->input.count; ++v) add_line(&lines, "%d,%d,%d,%d,%s,%d,%s,%s,%d,%s,%d,%s,%s,%s,%s,%d", analysis->input.pages[v].id, analysis->graph.in[v].count, analysis->graph.out[v].count, analysis->components.labels[v] + 1, regions[analysis->region[v]], analysis->kcore[v], fixed(analysis->harmonic[v], 6), fixed(analysis->pagerank.values[v], 6), analysis->rank[v], fixed(analysis->cheirank.values[v], 6), analysis->chei_rank[v], fixed(analysis->global_hits.authority[v], 6), fixed(analysis->global_hits.hub[v], 6), fixed(analysis->trustrank.values[v], 6), fixed(analysis->trust_ratio[v], 4), analysis->trust_distance[v]);
    return lines;
}
static Lines host_lines(const Analysis *analysis) {
    Lines lines = {0};
    add_line(&lines, "host,pages,core_pages,internal_links,internal_density,outgoing_links,incoming_links,dangling_pages,page_score_sum,top_page,score,rank");
    for (int host = 0; host < analysis->host_count; ++host) {
        bool members[500]; int count = 0, core = 0, internal = 0, outgoing = 0, incoming = 0, dangling = 0;
        for (int v = 0; v < analysis->input.count; ++v) {
            members[v] = analysis->host_of[v] == host;
            if (!members[v]) continue;
            ++count;
            if (analysis->region[v] == 0) ++core;
            if (!analysis->graph.out[v].count) ++dangling;
            for (int j = 0; j < analysis->graph.out[v].count; ++j) { if (analysis->host_of[analysis->graph.out[v].values[j]] == host) ++internal; else ++outgoing; }
            for (int j = 0; j < analysis->graph.in[v].count; ++j) if (analysis->host_of[analysis->graph.in[v].values[j]] != host) ++incoming;
        }
        double density = count >= 2 ? (double)internal / (count * (count - 1)) : 0;
        add_line(&lines, "%s,%d,%d,%d,%s,%d,%d,%d,%s,%d,%s,%d", analysis->host_names[host], count, core, internal, fixed(density, 4), outgoing, incoming, dangling, fixed(total(analysis->pagerank.values, members, analysis->input.count), 6), analysis->input.pages[representative(analysis, members)].id, fixed(analysis->host_rank.values[host], 6), analysis->host_positions[host]);
    }
    return lines;
}
static Lines ranking_lines(const Analysis *analysis) {
    Lines lines = {0};
    int n = analysis->input.count, limit = analysis->input.settings.top_k;
    score_block(analysis, &lines, "pagerank", analysis->pagerank.values);
    bool dangling[500];
    for (int v = 0; v < n; ++v) dangling[v] = !analysis->graph.out[v].count;
    add_line(&lines, "dangling_mass %s", fixed(total(analysis->pagerank.values, dangling, n), 6));
    int top[500], count = top_list(analysis->pagerank.values, n, limit, top);
    for (int i = 0; i < count; ++i) {
        int v = top[i], order[500], size = 0;
        double contributions[500];
        for (int j = 0; j < analysis->graph.in[v].count; ++j) {
            int u = analysis->graph.in[v].values[j];
            contributions[u] = (analysis->input.settings.damping * analysis->pagerank.values[u]) / analysis->graph.out[u].count;
            int p = size++;
            while (p && scaled(contributions[order[p - 1]], 6) < scaled(contributions[u], 6)) { order[p] = order[p - 1]; --p; }
            order[p] = u;
        }
        char *line = format("contributors %d", analysis->input.pages[v].id);
        for (int j = 0; j < size && j < 3; ++j) line = format("%s %d %s", line, analysis->input.pages[order[j]].id, fixed(contributions[order[j]], 6));
        add_line(&lines, "%s", line);
    }
    const double *scores[] = {analysis->cheirank.values, analysis->global_hits.authority, analysis->global_hits.hub, analysis->trustrank.values, analysis->harmonic};
    const char *names[] = {"cheirank", "authority", "hub", "trustrank", "harmonic"};
    for (int s = 0; s < 5; ++s) { add_line(&lines, ""); score_block(analysis, &lines, names[s], scores[s]); }
    Integer series[7][500];
    for (int v = 0; v < n; ++v) {
        series[0][v] = analysis->graph.in[v].count;
        series[1][v] = scaled(analysis->pagerank.values[v], 6);
        for (int s = 0; s < 5; ++s) series[s + 2][v] = scaled(scores[s][v], 6);
    }
    add_line(&lines, ""); add_line(&lines, "correlation");
    for (int a = 0; a < 7; ++a) for (int b = a + 1; b < 7; ++b) add_line(&lines, "%s %s %s", quantities[a], quantities[b], kendall(series[a], series[b], n));
    add_line(&lines, ""); add_line(&lines, "damping_sweep");
    for (int s = 0; s < analysis->input.settings.sweep_count; ++s) {
        const PageRank *run = &analysis->sweep[s];
        int order[500], ranks[500], shared = 0, footrule = 0, shift = 0;
        Integer keys[500];
        rank_order(run->values, n, order); positions(order, n, ranks);
        for (int v = 0; v < n; ++v) {
            if (ranks[v] <= limit && analysis->rank[v] <= limit) ++shared;
            footrule += abs(ranks[v] - analysis->rank[v]);
            if (abs(ranks[v] - analysis->rank[v]) > abs(ranks[shift] - analysis->rank[shift])) shift = v;
            keys[v] = scaled(run->values[v], 6);
        }
        add_line(&lines, "damping %s overlap %d footrule %d kendall %s largest_shift %d %d %d", fixed(analysis->input.settings.sweep[s], 4), shared, footrule, kendall(series[1], keys, n), analysis->input.pages[shift].id, analysis->rank[shift], ranks[shift]);
        add_line(&lines, "top %s", page_ids(analysis, order, n < limit ? n : limit));
    }
    add_line(&lines, ""); add_line(&lines, "spam top %d threshold %s", analysis->input.settings.spam_top, fixed(analysis->input.settings.spam_threshold, 4));
    for (int r = 0; r < n; ++r) {
        int v = analysis->order[r];
        if (!analysis->suspects[v]) continue;
        add_line(&lines, "suspect %d rank %d pagerank %s trustrank %s trust_ratio %s trust_distance %d kcore %d %s", analysis->input.pages[v].id, analysis->rank[v], fixed(analysis->pagerank.values[v], 6), fixed(analysis->trustrank.values[v], 6), fixed(analysis->trust_ratio[v], 4), analysis->trust_distance[v], analysis->kcore[v], analysis->input.pages[v].host);
    }
    add_line(&lines, "count %d", analysis->suspect_count); add_line(&lines, "trust_by_distance");
    for (int d = 0; d <= n; ++d) {
        int distance = d == n ? -1 : d;
        bool members[500]; int size = 0;
        for (int v = 0; v < n; ++v) { members[v] = analysis->trust_distance[v] == distance; if (members[v]) ++size; }
        if (size) add_line(&lines, "%s pages %d trustrank %s pagerank %s", distance < 0 ? "unreachable" : format("%d", distance), size, fixed(total(analysis->trustrank.values, members, n), 6), fixed(total(analysis->pagerank.values, members, n), 6));
    }
    add_line(&lines, "");
    if (!analysis->suspect_count) add_line(&lines, "demotion none");
    else {
        char *line = "demotion hosts";
        for (int h = 0; h < analysis->host_count; ++h) if (analysis->suspect_hosts[h]) line = format("%s %s", line, analysis->host_names[h]);
        add_line(&lines, "%s removed_links %d", line, analysis->removed);
        count = top_list(analysis->demoted.values, n, limit, top);
        for (int i = 0; i < count; ++i) {
            int v = top[i]; Page page = analysis->input.pages[v];
            add_line(&lines, "%d %d %s was %d %s %s", i + 1, page.id, fixed(analysis->demoted.values[v], 6), analysis->rank[v], page.host, page.title);
        }
        for (int r = 0; r < n; ++r) { int v = analysis->order[r]; if (analysis->suspects[v]) add_line(&lines, "suspect %d before %d after %d", analysis->input.pages[v].id, analysis->rank[v], analysis->demoted_rank[v]); }
    }
    int host_count = analysis->host_count, edges = 0, reciprocal = 0, largest = 0;
    typedef struct { int source, target, weight; } Edge;
    Edge heavy[6000];
    for (int u = 0; u < host_count; ++u) for (int v = 0; v < host_count; ++v) {
        int weight = analysis->host_graph.weights[u * host_count + v];
        if (!weight) continue;
        if (analysis->host_graph.weights[v * host_count + u]) ++reciprocal;
        int i = edges++;
        while (i && heavy[i - 1].weight < weight) { heavy[i] = heavy[i - 1]; --i; }
        heavy[i] = (Edge){u, v, weight};
    }
    for (int c = 0; c < analysis->host_components.count; ++c) if (analysis->host_components.sizes[c] > largest) largest = analysis->host_components.sizes[c];
    add_line(&lines, ""); add_line(&lines, "host_graph hosts %d links %d reciprocal %d strong_components %d largest %d", host_count, edges, reciprocal, analysis->host_components.count, largest);
    add_line(&lines, "host_links top %d", limit);
    for (int e = 0; e < edges && e < limit; ++e) add_line(&lines, "%s %s %d", analysis->host_names[heavy[e].source], analysis->host_names[heavy[e].target], heavy[e].weight);
    return lines;
}
static void convergence_block(Lines *lines, const char *heading, const PageRank *run) {
    add_line(lines, ""); add_line(lines, "%s", heading);
    for (int t = 10; t <= run->iterations; t += 10) add_line(lines, "iteration %d l1 %s", t, fixed(run->changes[t - 1], 10));
    add_line(lines, "converged_at %s", run->converged_at ? format("%d", run->converged_at) : "none");
}
static Lines convergence_lines(const Analysis *analysis) {
    Lines lines = {0};
    Settings settings = analysis->input.settings;
    char *damping = fixed(settings.damping, 4);
    add_line(&lines, "iterations %d tolerance %s", settings.iterations, fixed(settings.tolerance, 10));
    convergence_block(&lines, format("pagerank damping %s", damping), &analysis->pagerank);
    convergence_block(&lines, format("cheirank damping %s", damping), &analysis->cheirank);
    convergence_block(&lines, format("trustrank damping %s seeds %d", damping, settings.trusted_count), &analysis->trustrank);
    for (int s = 0; s < settings.sweep_count; ++s) convergence_block(&lines, format("sweep damping %s", fixed(settings.sweep[s], 4)), &analysis->sweep[s]);
    if (analysis->suspect_count) convergence_block(&lines, format("demoted damping %s", damping), &analysis->demoted);
    for (int q = 0; q < analysis->input.query_count; ++q) convergence_block(&lines, format("personalized query %d damping %s", q + 1, damping), &analysis->personalized[q]);
    convergence_block(&lines, format("host_pagerank damping %s hosts %d", damping, analysis->host_count), &analysis->host_rank);
    return lines;
}
int main(void) {
    Analysis *analysis = allocate(sizeof(*analysis));
    read_input(&analysis->input);
    build_graphs(analysis);
    graph_statistics(analysis);
    compute_scores(analysis);
    query_scores(analysis);
    write_lines("graph_stats.txt", graph_stats_lines(analysis));
    write_lines("pagerank.csv", pagerank_lines(analysis));
    write_lines("rankings.txt", ranking_lines(analysis));
    write_lines("convergence.txt", convergence_lines(analysis));
    write_lines("queries.txt", analysis->queries);
    write_lines("hosts.csv", host_lines(analysis));
    return 0;
}
