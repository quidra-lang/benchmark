#include <setjmp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define APPEND(a, n, v) do { (a) = resize((a), ((n) + 1) * sizeof(*(a))); (a)[(n)++] = (v); } while (0)
typedef struct {
    char *data;
    size_t length, capacity;
} Buffer;
typedef struct {
    int n;
    uint32_t adjacent[16];
} Graph;
typedef struct {
    char *name;
    Graph graph;
} NamedGraph;
typedef struct {
    int colors[16], rounds;
} Refined;
typedef struct {
    int values[17], length;
} Signature;
typedef struct {
    int values[16];
} Label;
typedef struct {
    uint64_t nodes, leaves;
    char text[121];
    bool has_best;
    Label labels, *maxima;
    size_t count;
} Canonical;
typedef struct {
    int u, v;
} Edge;
typedef struct {
    int degrees[16], edges, triangles, sizes[16], components, girth, diameter, radius;
    bool bipartite;
} Invariants;
typedef struct {
    Label map;
    bool induced;
} Embedding;
typedef struct {
    uint64_t count, induced;
    Embedding first[5];
    int first_count;
} Embeddings;
typedef struct {
    char **items;
    size_t count;
} Strings;
static NamedGraph *registry;
static size_t registry_count;
static jmp_buf failure;
static char *error_reason;

static void *allocate(size_t size) {
    void *p = calloc(1, size ? size : 1);
    if (!p) exit(EXIT_FAILURE);
    return p;
}

static void *resize(void *p, size_t size) {
    p = realloc(p, size ? size : 1);
    if (!p) exit(EXIT_FAILURE);
    return p;
}

static char *slice(const char *s, size_t length) {
    char *out = allocate(length + 1);
    memcpy(out, s, length);
    return out;
}

static char *copy(const char *s) {
    return slice(s, strlen(s));
}

static char *format(const char *pattern, ...) {
    va_list args, saved;
    va_start(args, pattern);
    va_copy(saved, args);
    int length = vsnprintf(NULL, 0, pattern, args);
    va_end(args);
    char *out = allocate((size_t)length + 1);
    vsnprintf(out, (size_t)length + 1, pattern, saved);
    va_end(saved);
    return out;
}

static void error(const char *pattern, ...) {
    va_list args, saved;
    va_start(args, pattern);
    va_copy(saved, args);
    int length = vsnprintf(NULL, 0, pattern, args);
    va_end(args);
    error_reason = allocate((size_t)length + 1);
    vsnprintf(error_reason, (size_t)length + 1, pattern, saved);
    va_end(saved);
    longjmp(failure, 1);
}

static void append(Buffer *b, const char *s) {
    size_t n = strlen(s);
    if (b->length + n + 1 > b->capacity) {
        b->capacity = (b->length + n + 1) * 2;
        b->data = resize(b->data, b->capacity);
    }
    memcpy(b->data + b->length, s, n);
    b->length += n;
    b->data[b->length] = 0;
}

static char *finish(Buffer *b) {
    return b->data ? b->data : copy("");
}

static bool one_of(const char *word, const char *set) {
    return *word && !strchr(word, ' ') && strstr(set, format(" %s ", word));
}

static bool valid_name(const char *word) {
    size_t n = strlen(word);
    if (!n || n > 8 || *word < 'a' || *word > 'z') return false;
    for (size_t i = 1; i < n; i++) if ((word[i] < 'a' || word[i] > 'z') && (word[i] < '0' || word[i] > '9')) return false;
    return true;
}

static bool number(const char *word) {
    size_t n = strlen(word);
    if (!n || n > 3 || (n > 1 && *word == '0')) return false;
    for (size_t i = 0; i < n; i++) if (word[i] < '0' || word[i] > '9') return false;
    return true;
}

static bool edge_word(const char *word) {
    const char *hyphen = strchr(word, '-');
    return hyphen && !strchr(hyphen + 1, '-') && number(slice(word, (size_t)(hyphen - word))) && number(hyphen + 1);
}

static int bit_count(uint32_t value) {
    int count = 0;
    while (value) {
        value &= value - 1;
        count++;
    }
    return count;
}

static Graph make_graph(int n) {
    Graph graph = {.n = n};
    return graph;
}

static bool edge(Graph graph, int u, int v) {
    return (graph.adjacent[u] & (1u << v)) != 0;
}

static void join(Graph *graph, int u, int v) {
    graph->adjacent[u] |= 1u << v;
    graph->adjacent[v] |= 1u << u;
}

static int degree(Graph graph, int vertex) {
    return bit_count(graph.adjacent[vertex]);
}

static int edges(Graph graph, Edge *out) {
    int count = 0;
    for (int u = 0; u < graph.n; u++) for (int v = u + 1; v < graph.n; v++) if (edge(graph, u, v)) {
        if (out) out[count] = (Edge){u, v};
        count++;
    }
    return count;
}

static int cells(const int *colors, int n) {
    int count = 0;
    for (int i = 0; i < n; i++) if (colors[i] >= count) count = colors[i] + 1;
    return count;
}

static int compare_numbers(const int *a, int an, const int *b, int bn) {
    for (int i = 0; i < an && i < bn; i++) if (a[i] != b[i]) return a[i] < b[i] ? -1 : 1;
    return (an > bn) - (an < bn);
}

static void print_numbers(const int *values, int count) {
    for (int i = 0; i < count; i++) printf("%s%d", i ? " " : "", values[i]);
}

static Label degree_colors(Graph graph) {
    Label result = {0};
    for (int v = 0; v < graph.n; v++) {
        bool seen[17] = {0};
        int d = degree(graph, v);
        for (int w = 0; w < graph.n; w++) if (degree(graph, w) < d) seen[degree(graph, w)] = true;
        for (int i = 0; i < d; i++) if (seen[i]) result.values[v]++;
    }
    return result;
}

static Refined refine(Graph graph, const int *initial) {
    Refined result = {0};
    memcpy(result.colors, initial, (size_t)graph.n * sizeof(*initial));
    while (true) {
        Signature signatures[16] = {0};
        int order[16], next[16];
        for (int v = 0; v < graph.n; v++) {
            Signature *signature = signatures + v;
            signature->values[0] = result.colors[v];
            signature->length = 1;
            for (int w = 0; w < graph.n; w++) if (edge(graph, v, w)) signature->values[signature->length++] = result.colors[w];
            for (int i = 2; i < signature->length; i++) {
                int value = signature->values[i], j = i;
                while (j > 1 && signature->values[j - 1] > value) {
                    signature->values[j] = signature->values[j - 1];
                    j--;
                }
                signature->values[j] = value;
            }
            order[v] = v;
        }
        for (int i = 1; i < graph.n; i++) {
            int vertex = order[i], j = i;
            while (j > 0 && compare_numbers(signatures[order[j - 1]].values, signatures[order[j - 1]].length, signatures[vertex].values, signatures[vertex].length) > 0) {
                order[j] = order[j - 1];
                j--;
            }
            order[j] = vertex;
        }
        int color = 0;
        for (int i = 0; i < graph.n; i++) {
            if (i && compare_numbers(signatures[order[i - 1]].values, signatures[order[i - 1]].length, signatures[order[i]].values, signatures[order[i]].length)) color++;
            next[order[i]] = color;
        }
        if (cells(next, graph.n) == cells(result.colors, graph.n)) return result;
        memcpy(result.colors, next, (size_t)graph.n * sizeof(*next));
        result.rounds++;
    }
}

static Label individualize(const int *colors, int n, int vertex) {
    Label result = {0};
    for (int i = 0; i < n; i++) result.values[i] = colors[i] + (i != vertex && colors[i] >= colors[vertex]);
    return result;
}

static void leaf_string(Graph graph, const int *labels, char *out) {
    int inverse[16], at = 0;
    for (int i = 0; i < graph.n; i++) inverse[labels[i]] = i;
    for (int u = 0; u < graph.n; u++) for (int v = u + 1; v < graph.n; v++) out[at++] = edge(graph, inverse[u], inverse[v]) ? '1' : '0';
    out[at] = 0;
}

static void canonical_search(Graph graph, const int *colors, Canonical *result) {
    result->nodes++;
    if (cells(colors, graph.n) == graph.n) {
        result->leaves++;
        char text[121];
        leaf_string(graph, colors, text);
        int order = result->has_best ? strcmp(text, result->text) : 1;
        if (order > 0) {
            strcpy(result->text, text);
            memcpy(result->labels.values, colors, (size_t)graph.n * sizeof(*colors));
            result->has_best = true;
            result->count = 0;
        }
        if (order >= 0) {
            Label label = {0};
            memcpy(label.values, colors, (size_t)graph.n * sizeof(*colors));
            APPEND(result->maxima, result->count, label);
        }
        return;
    }
    int sizes[16] = {0}, chosen = -1, smallest = graph.n + 1;
    for (int i = 0; i < graph.n; i++) sizes[colors[i]]++;
    for (int color = 0; color < cells(colors, graph.n); color++) if (sizes[color] >= 2 && sizes[color] < smallest) {
        chosen = color;
        smallest = sizes[color];
    }
    for (int v = 0; v < graph.n; v++) if (colors[v] == chosen) {
        Label individualized = individualize(colors, graph.n, v);
        Refined child = refine(graph, individualized.values);
        canonical_search(graph, child.colors, result);
    }
}

static Canonical canonical(Graph graph) {
    Canonical result = {0};
    Label degrees = degree_colors(graph);
    Refined root = refine(graph, degrees.values);
    canonical_search(graph, root.colors, &result);
    return result;
}

static Invariants invariants(Graph graph) {
    Invariants result = {.edges = edges(graph, NULL), .girth = 0, .diameter = 0, .radius = graph.n, .bipartite = true};
    bool visited[16] = {0};
    for (int v = 0; v < graph.n; v++) result.degrees[v] = degree(graph, v);
    for (int i = 0; i < graph.n; i++) for (int j = i + 1; j < graph.n; j++) if (result.degrees[j] > result.degrees[i]) {
        int x = result.degrees[i];
        result.degrees[i] = result.degrees[j];
        result.degrees[j] = x;
    }
    for (int a = 0; a < graph.n; a++) for (int b = a + 1; b < graph.n; b++) for (int c = b + 1; c < graph.n; c++) if (edge(graph, a, b) && edge(graph, a, c) && edge(graph, b, c)) result.triangles++;
    for (int source = 0; source < graph.n; source++) {
        int distance[16], parent[16], queue[16], count = 1, at = 0;
        for (int i = 0; i < graph.n; i++) distance[i] = parent[i] = -1;
        distance[source] = 0;
        queue[0] = source;
        while (at < count) {
            int u = queue[at++];
            for (int v = 0; v < graph.n; v++) if (edge(graph, u, v)) {
                if (distance[v] < 0) {
                    distance[v] = distance[u] + 1;
                    parent[v] = u;
                    queue[count++] = v;
                } else if (parent[u] != v && parent[v] != u) {
                    int cycle = distance[u] + distance[v] + 1;
                    if (!result.girth || cycle < result.girth) result.girth = cycle;
                }
                if (distance[u] % 2 == distance[v] % 2) result.bipartite = false;
            }
        }
        if (!visited[source]) {
            result.sizes[result.components++] = count;
            for (int i = 0; i < graph.n; i++) if (distance[i] >= 0) visited[i] = true;
        }
        int eccentricity = 0;
        for (int i = 0; i < graph.n; i++) if (distance[i] > eccentricity) eccentricity = distance[i];
        if (eccentricity > result.diameter) result.diameter = eccentricity;
        if (eccentricity < result.radius) result.radius = eccentricity;
    }
    for (int i = 0; i < result.components; i++) for (int j = i + 1; j < result.components; j++) if (result.sizes[j] > result.sizes[i]) {
        int x = result.sizes[i];
        result.sizes[i] = result.sizes[j];
        result.sizes[j] = x;
    }
    if (result.components > 1) result.diameter = result.radius = -1;
    return result;
}

static char *girth_text(int girth) {
    return girth ? format("%d", girth) : "none";
}

static char *distance_text(int distance) {
    return distance < 0 ? "INF" : format("%d", distance);
}

static bool color_search(Graph graph, int count, int vertex, int largest, int *colors) {
    if (vertex == graph.n) return true;
    for (int color = 0; color < count && color <= largest + 1; color++) {
        bool good = true;
        for (int other = 0; other < vertex; other++) if (edge(graph, vertex, other) && colors[other] == color) good = false;
        if (good) {
            colors[vertex] = color;
            if (color_search(graph, count, vertex + 1, largest > color ? largest : color, colors)) return true;
        }
    }
    return false;
}

static void print_invariants(const char *name, Graph graph) {
    Invariants data = invariants(graph);
    printf("invariants %s\ndegrees ", name);
    print_numbers(data.degrees, graph.n);
    printf("\nedges %d triangles %d\ncomponents %d sizes ", data.edges, data.triangles, data.components);
    print_numbers(data.sizes, data.components);
    printf("\ngirth %s diameter %s radius %s\nbipartite %s\n", girth_text(data.girth), distance_text(data.diameter), distance_text(data.radius), data.bipartite ? "yes" : "no");
    if (graph.n >= 13) {
        puts("clique -\nchromatic -");
        return;
    }
    int best[16] = {0}, best_count = 0;
    for (uint32_t mask = 1; mask < (1u << graph.n); mask++) {
        if (bit_count(mask) < best_count) continue;
        int candidate[16], count = 0;
        bool good = true;
        for (int u = 0; u < graph.n; u++) if (mask & (1u << u)) {
            candidate[count++] = u;
            for (int v = u + 1; v < graph.n; v++) if ((mask & (1u << v)) && !edge(graph, u, v)) good = false;
        }
        if (good && (count > best_count || compare_numbers(candidate, count, best, best_count) < 0)) {
            memcpy(best, candidate, (size_t)count * sizeof(*best));
            best_count = count;
        }
    }
    printf("clique %d ", best_count);
    print_numbers(best, best_count);
    int colors[16], count = 1;
    while (!color_search(graph, count, 0, -1, colors)) count++;
    printf("\nchromatic %d ", count);
    print_numbers(colors, graph.n);
    putchar('\n');
}

static int find(int *parent, int vertex) {
    return parent[vertex] == vertex ? vertex : (parent[vertex] = find(parent, parent[vertex]));
}

static void unite(int *parent, int a, int b) {
    a = find(parent, a);
    b = find(parent, b);
    if (a != b) parent[a > b ? a : b] = a < b ? a : b;
}

static void automorphisms(const char *name, Graph graph) {
    Canonical data = canonical(graph);
    Edge list[120];
    int m = edges(graph, list), vertices[16], edge_sets[120], inverse[16], edge_index[16][16] = {0};
    for (int i = 0; i < graph.n; i++) {
        vertices[i] = i;
        inverse[data.labels.values[i]] = i;
    }
    for (int i = 0; i < m; i++) {
        edge_sets[i] = i;
        edge_index[list[i].u][list[i].v] = edge_index[list[i].v][list[i].u] = i;
    }
    for (size_t l = 0; l < data.count; l++) {
        int permutation[16];
        for (int i = 0; i < graph.n; i++) {
            permutation[i] = inverse[data.maxima[l].values[i]];
            unite(vertices, i, permutation[i]);
        }
        for (int i = 0; i < m; i++) unite(edge_sets, i, edge_index[permutation[list[i].u]][permutation[list[i].v]]);
    }
    int vertex_count = 0, edge_count = 0;
    for (int i = 0; i < graph.n; i++) if (find(vertices, i) == i) vertex_count++;
    for (int i = 0; i < m; i++) if (find(edge_sets, i) == i) edge_count++;
    printf("aut %s order %zu\nvertex orbits %d\n", name, data.count, vertex_count);
    for (int i = 0; i < graph.n; i++) if (find(vertices, i) == i) {
        printf("orbit");
        for (int j = 0; j < graph.n; j++) if (find(vertices, j) == i) printf(" %d", j);
        putchar('\n');
    }
    printf("edge orbits %d\n", edge_count);
    for (int i = 0; i < m; i++) if (find(edge_sets, i) == i) {
        printf("orbit");
        for (int j = 0; j < m; j++) if (find(edge_sets, j) == i) printf(" %d-%d", list[j].u, list[j].v);
        putchar('\n');
    }
    printf("transitive vertex %s edge %s\n", vertex_count == 1 ? "yes" : "no", edge_count == 1 ? "yes" : "no");
    free(data.maxima);
}

static void embedding_search(Graph pattern, Graph target, int vertex, uint32_t used, Label map, bool induced, Embeddings *result) {
    if (vertex == pattern.n) {
        result->count++;
        if (induced) result->induced++;
        if (result->first_count < 5) result->first[result->first_count++] = (Embedding){map, induced};
        return;
    }
    for (int candidate = 0; candidate < target.n; candidate++) if (!(used & (1u << candidate))) {
        bool good = true, still_induced = induced;
        for (int before = 0; before < vertex; before++) {
            bool a = edge(pattern, vertex, before), b = edge(target, candidate, map.values[before]);
            if (a && !b) good = false;
            if (a != b) still_induced = false;
        }
        if (good) {
            map.values[vertex] = candidate;
            embedding_search(pattern, target, vertex + 1, used | (1u << candidate), map, still_induced, result);
        }
    }
}

static void isomorphism(Graph left, Graph right) {
    if (left.n != right.n) {
        printf("not isomorphic vertices %d %d\n", left.n, right.n);
        return;
    }
    Invariants a = invariants(left), b = invariants(right);
    char *reason = NULL;
    if (a.edges != b.edges) reason = format("edges %d %d", a.edges, b.edges);
    else if (compare_numbers(a.degrees, left.n, b.degrees, right.n)) reason = "degrees";
    else if (a.triangles != b.triangles) reason = format("triangles %d %d", a.triangles, b.triangles);
    else if (a.components != b.components) reason = format("components %d %d", a.components, b.components);
    else if (a.girth != b.girth) reason = format("girth %s %s", girth_text(a.girth), girth_text(b.girth));
    else if (a.diameter != b.diameter) reason = format("diameter %s %s", distance_text(a.diameter), distance_text(b.diameter));
    else if (a.bipartite != b.bipartite) reason = format("bipartite %s %s", a.bipartite ? "yes" : "no", b.bipartite ? "yes" : "no");
    if (reason) {
        printf("not isomorphic %s\n", reason);
        return;
    }
    Label dx = degree_colors(left), dy = degree_colors(right);
    Refined x = refine(left, dx.values), y = refine(right, dy.values);
    int xs[16] = {0}, ys[16] = {0};
    for (int i = 0; i < left.n; i++) {
        xs[x.colors[i]]++;
        ys[y.colors[i]]++;
    }
    if (x.rounds != y.rounds || cells(x.colors, left.n) != cells(y.colors, right.n) || compare_numbers(xs, cells(x.colors, left.n), ys, cells(y.colors, right.n))) {
        puts("not isomorphic refinement");
        return;
    }
    Canonical c = canonical(left), d = canonical(right);
    if (strcmp(c.text, d.text)) puts("not isomorphic canonical");
    else {
        int inverse[16], mapping[16];
        for (int i = 0; i < right.n; i++) inverse[d.labels.values[i]] = i;
        for (int i = 0; i < left.n; i++) mapping[i] = inverse[c.labels.values[i]];
        printf("isomorphic\nmapping ");
        print_numbers(mapping, left.n);
        putchar('\n');
    }
    free(c.maxima);
    free(d.maxima);
}

static Graph from_string(int n, const char *text) {
    Graph graph = make_graph(n);
    int at = 0;
    for (int u = 0; u < n; u++) for (int v = u + 1; v < n; v++) if (text[at++] == '1') join(&graph, u, v);
    return graph;
}

static void string_add(Strings *set, const char *text) {
    for (size_t i = 0; i < set->count; i++) if (!strcmp(set->items[i], text)) return;
    APPEND(set->items, set->count, copy(text));
}

static int string_compare(const void *a, const void *b) {
    return strcmp(*(char *const *)a, *(char *const *)b);
}

static void classify(int n) {
    if (!n) error("bad value");
    if (n > 5) error("too large");
    int limit = n * (n - 1) / 2;
    Strings *classes = allocate((size_t)(limit + 1) * sizeof(*classes));
    Canonical empty = canonical(make_graph(n));
    string_add(classes, empty.text);
    free(empty.maxima);
    size_t total = 0;
    for (int m = 0; m <= limit; m++) {
        qsort(classes[m].items, classes[m].count, sizeof(*classes[m].items), string_compare);
        total += classes[m].count;
        if (m == limit) break;
        for (size_t i = 0; i < classes[m].count; i++) {
            Graph graph = from_string(n, classes[m].items[i]);
            for (int u = 0; u < n; u++) for (int v = u + 1; v < n; v++) if (!edge(graph, u, v)) {
                Graph added = graph;
                join(&added, u, v);
                Canonical result = canonical(added);
                string_add(classes + m + 1, result.text);
                free(result.maxima);
            }
        }
    }
    printf("classify %d total %zu\n", n, total);
    for (int m = 0; m <= limit; m++) {
        printf("edges %d count %zu", m, classes[m].count);
        for (size_t i = 0; i < classes[m].count; i++) printf(" %s", *classes[m].items[i] ? classes[m].items[i] : "-");
        putchar('\n');
    }
}

static int named_compare(const void *a, const void *b) {
    return strcmp(((const NamedGraph *)a)->name, ((const NamedGraph *)b)->name);
}

static Graph *get_graph(const char *name) {
    for (size_t i = 0; i < registry_count; i++) if (!strcmp(registry[i].name, name)) return &registry[i].graph;
    return NULL;
}

static void define(char *name, Graph graph) {
    Graph *existing = get_graph(name);
    bool replaced = existing != NULL;
    if (existing) *existing = graph;
    else {
        APPEND(registry, registry_count, ((NamedGraph){name, graph}));
        qsort(registry, registry_count, sizeof(*registry), named_compare);
    }
    printf("%s %s n %d m %d\n", replaced ? "redefined" : "defined", name, graph.n, edges(graph, NULL));
}

static Strings split(const char *line) {
    Strings out = {0};
    size_t start = 0;
    for (size_t i = 0;; i++) if (!line[i] || line[i] == ' ') {
        APPEND(out.items, out.count, slice(line + start, i - start));
        start = i + 1;
        if (!line[i]) break;
    }
    return out;
}

static void command(const char *line) {
    Strings words = split(line);
    char *cmd = words.items[0], **a = words.items + 1;
    size_t argc = words.count - 1;
    bool definition = one_of(cmd, " GRAPH  CYCLE  PATH  COMPLETE  BIPARTITE  STAR  WHEEL  PETERSEN  HYPERCUBE  CIRCULANT  GRID  COMPLEMENT  LINE  PRODUCT  UNION  RELABEL  INDUCED  CANONIZE ");
    if (!definition && !one_of(cmd, " DELETE  LIST  SHOW  INVARIANTS  REFINE  CANON  ISO  AUT  SUBISO  CLASSIFY ")) error("unknown command %s", cmd);
    size_t minimum = 0, maximum = 0, names = 0;
    if (!strcmp(cmd, "CLASSIFY")) minimum = maximum = 1;
    else if (one_of(cmd, " PETERSEN  DELETE  SHOW  INVARIANTS  CANON  AUT ")) minimum = maximum = names = 1;
    else if (one_of(cmd, " CYCLE  PATH  COMPLETE  STAR  WHEEL  HYPERCUBE ")) {
        minimum = maximum = 2;
        names = 1;
    } else if (one_of(cmd, " BIPARTITE  GRID ")) {
        minimum = maximum = 3;
        names = 1;
    } else if (one_of(cmd, " COMPLEMENT  LINE  CANONIZE  ISO  SUBISO ")) minimum = maximum = names = 2;
    else if (one_of(cmd, " PRODUCT  UNION ")) minimum = maximum = names = 3;
    else if (!strcmp(cmd, "GRAPH")) {
        minimum = 2;
        maximum = SIZE_MAX;
        names = 1;
    } else if (!strcmp(cmd, "CIRCULANT")) {
        minimum = 3;
        maximum = SIZE_MAX;
        names = 1;
    } else if (!strcmp(cmd, "RELABEL")) {
        minimum = names = 2;
        maximum = SIZE_MAX;
    } else if (!strcmp(cmd, "INDUCED")) {
        minimum = 3;
        names = 2;
        maximum = SIZE_MAX;
    } else if (!strcmp(cmd, "REFINE")) {
        minimum = names = 1;
        maximum = SIZE_MAX;
    }
    if (argc < minimum || argc > maximum) error("bad arguments");
    for (size_t i = 0; i < names; i++) if (!valid_name(a[i])) error("bad arguments");
    for (size_t i = names; i < argc; i++) if (!(!strcmp(cmd, "GRAPH") && i >= 2 ? edge_word(a[i]) : number(a[i]))) error("bad arguments");
    size_t first_ref = definition ? (one_of(cmd, " COMPLEMENT  LINE  PRODUCT  UNION  RELABEL  INDUCED  CANONIZE ") ? 1 : names) : 0;
    if (strcmp(cmd, "LIST") && strcmp(cmd, "CLASSIFY")) for (size_t i = first_ref; i < names; i++) if (!get_graph(a[i])) error("no graph %s", a[i]);
    char *name = argc ? a[0] : "";
    int n = argc > names ? atoi(a[names]) : 0;
    Graph graph = {0};
    if (definition) {
        if (one_of(cmd, " GRAPH  CYCLE  PATH  COMPLETE  CIRCULANT ")) {
            if (n < (one_of(cmd, " CYCLE  CIRCULANT ") ? 3 : 1)) error("bad value");
            if (n > 16) error("too large");
            graph = make_graph(n);
            if (!strcmp(cmd, "GRAPH")) for (size_t i = 2; i < argc; i++) {
                int u = atoi(a[i]), v = atoi(strchr(a[i], '-') + 1);
                if (u >= n || v >= n || u == v) error("bad edge %s", a[i]);
                if (edge(graph, u, v)) error("duplicate edge %s", a[i]);
                join(&graph, u, v);
            }
            if (one_of(cmd, " PATH  CYCLE ")) {
                for (int i = 1; i < n; i++) join(&graph, i - 1, i);
                if (!strcmp(cmd, "CYCLE")) join(&graph, n - 1, 0);
            }
            if (!strcmp(cmd, "COMPLETE")) for (int u = 0; u < n; u++) for (int v = u + 1; v < n; v++) join(&graph, u, v);
            if (!strcmp(cmd, "CIRCULANT")) {
                int previous = 0;
                for (size_t i = 2; i < argc; i++) {
                    int jump = atoi(a[i]);
                    if (jump <= previous || jump * 2 > n) error("bad value");
                    previous = jump;
                    for (int v = 0; v < n; v++) join(&graph, v, (v + jump) % n);
                }
            }
        } else if (one_of(cmd, " STAR  WHEEL ")) {
            if (n < (!strcmp(cmd, "WHEEL") ? 3 : 1)) error("bad value");
            if (n >= 16) error("too large");
            graph = make_graph(n + 1);
            for (int i = 1; i <= n; i++) join(&graph, 0, i);
            if (!strcmp(cmd, "WHEEL")) for (int i = 1; i <= n; i++) join(&graph, i, i == n ? 1 : i + 1);
        } else if (one_of(cmd, " BIPARTITE  GRID ")) {
            int b = atoi(a[2]);
            if (!n || !b) error("bad value");
            int size = !strcmp(cmd, "GRID") ? n * b : n + b;
            if (size > 16) error("too large");
            graph = make_graph(size);
            if (!strcmp(cmd, "BIPARTITE")) for (int u = 0; u < n; u++) for (int v = 0; v < b; v++) join(&graph, u, n + v);
            else for (int x = 0; x < n; x++) for (int y = 0; y < b; y++) {
                if (x + 1 < n) join(&graph, x * b + y, (x + 1) * b + y);
                if (y + 1 < b) join(&graph, x * b + y, x * b + y + 1);
            }
        } else if (!strcmp(cmd, "PETERSEN")) {
            graph = make_graph(10);
            for (int i = 0; i < 5; i++) {
                join(&graph, i, (i + 1) % 5);
                join(&graph, i, i + 5);
                join(&graph, i + 5, 5 + (i + 2) % 5);
            }
        } else if (!strcmp(cmd, "HYPERCUBE")) {
            if (!n) error("bad value");
            if (n > 4) error("too large");
            graph = make_graph(1 << n);
            for (int u = 0; u < graph.n; u++) for (int bit = 0; bit < n; bit++) join(&graph, u, u ^ (1 << bit));
        } else if (!strcmp(cmd, "COMPLEMENT")) {
            Graph source = *get_graph(a[1]);
            graph = make_graph(source.n);
            for (int u = 0; u < source.n; u++) for (int v = u + 1; v < source.n; v++) if (!edge(source, u, v)) join(&graph, u, v);
        } else if (!strcmp(cmd, "LINE")) {
            Edge list[120];
            int count = edges(*get_graph(a[1]), list);
            if (!count) error("no edges");
            if (count > 16) error("too large");
            graph = make_graph(count);
            for (int i = 0; i < count; i++) for (int j = i + 1; j < count; j++) if (list[i].u == list[j].u || list[i].u == list[j].v || list[i].v == list[j].u || list[i].v == list[j].v) join(&graph, i, j);
        } else if (one_of(cmd, " PRODUCT  UNION ")) {
            Graph x = *get_graph(a[1]), y = *get_graph(a[2]);
            bool product = !strcmp(cmd, "PRODUCT");
            int size = product ? x.n * y.n : x.n + y.n;
            if (size > 16) error("too large");
            graph = make_graph(size);
            Edge xe[120], ye[120];
            int xm = edges(x, xe), ym = edges(y, ye);
            if (product) {
                for (int u = 0; u < x.n; u++) for (int i = 0; i < ym; i++) join(&graph, u * y.n + ye[i].u, u * y.n + ye[i].v);
                for (int v = 0; v < y.n; v++) for (int i = 0; i < xm; i++) join(&graph, xe[i].u * y.n + v, xe[i].v * y.n + v);
            } else {
                for (int i = 0; i < xm; i++) join(&graph, xe[i].u, xe[i].v);
                for (int i = 0; i < ym; i++) join(&graph, x.n + ye[i].u, x.n + ye[i].v);
            }
        } else {
            Graph source = *get_graph(a[1]);
            Label selected = {0};
            int count = (int)argc - 2;
            bool induced = !strcmp(cmd, "INDUCED");
            if (!strcmp(cmd, "CANONIZE")) {
                Canonical data = canonical(source);
                selected = data.labels;
                count = source.n;
                free(data.maxima);
            } else {
                bool seen[16] = {0};
                if (!induced && count != source.n) error("bad permutation");
                for (int i = 0; i < count; i++) {
                    int vertex = atoi(a[i + 2]);
                    if (vertex >= source.n || seen[vertex]) error(induced ? "bad vertices" : "bad permutation");
                    seen[vertex] = true;
                    selected.values[i] = vertex;
                }
            }
            graph = make_graph(induced ? count : source.n);
            if (induced) {
                for (int u = 0; u < count; u++) for (int v = u + 1; v < count; v++) if (edge(source, selected.values[u], selected.values[v])) join(&graph, u, v);
            } else {
                Edge list[120];
                int m = edges(source, list);
                for (int i = 0; i < m; i++) join(&graph, selected.values[list[i].u], selected.values[list[i].v]);
            }
        }
        define(name, graph);
        return;
    }
    Graph *found = get_graph(name);
    if (found) graph = *found;
    if (!strcmp(cmd, "DELETE")) {
        size_t next = 0;
        for (size_t i = 0; i < registry_count; i++) if (strcmp(registry[i].name, name)) registry[next++] = registry[i];
        registry_count = next;
        printf("deleted %s\n", name);
    } else if (!strcmp(cmd, "LIST")) {
        printf("graphs %zu\n", registry_count);
        for (size_t i = 0; i < registry_count; i++) printf("%s n %d m %d\n", registry[i].name, registry[i].graph.n, edges(registry[i].graph, NULL));
    } else if (!strcmp(cmd, "SHOW")) {
        printf("graph %s n %d m %d\n", name, graph.n, edges(graph, NULL));
        for (int v = 0; v < graph.n; v++) {
            printf("%d:", v);
            for (int w = 0; w < graph.n; w++) if (edge(graph, v, w)) printf(" %d", w);
            putchar('\n');
        }
    } else if (!strcmp(cmd, "INVARIANTS")) print_invariants(name, graph);
    else if (!strcmp(cmd, "REFINE")) {
        for (size_t i = 1; i < argc; i++) if (atoi(a[i]) >= graph.n) error("bad vertices");
        Label degrees = degree_colors(graph);
        Refined result = refine(graph, degrees.values);
        for (size_t i = 1; i < argc; i++) {
            int vertex = atoi(a[i]), count = 0;
            for (int v = 0; v < graph.n; v++) if (result.colors[v] == result.colors[vertex]) count++;
            if (count == 1) error("singleton %d", vertex);
            Label individualized = individualize(result.colors, graph.n, vertex);
            Refined next = refine(graph, individualized.values);
            next.rounds += result.rounds;
            result = next;
        }
        int count = cells(result.colors, graph.n);
        printf("refine %s rounds %d cells %d\n", name, result.rounds, count);
        for (int color = 0; color < count; color++) {
            printf("%d:", color);
            for (int v = 0; v < graph.n; v++) if (result.colors[v] == color) printf(" %d", v);
            putchar('\n');
        }
    } else if (!strcmp(cmd, "CANON")) {
        Canonical data = canonical(graph);
        printf("canon %s nodes %llu leaves %llu\nlabels ", name, (unsigned long long)data.nodes, (unsigned long long)data.leaves);
        print_numbers(data.labels.values, graph.n);
        printf("\nstring %s\n", *data.text ? data.text : "-");
        free(data.maxima);
    } else if (!strcmp(cmd, "AUT")) automorphisms(name, graph);
    else if (!strcmp(cmd, "ISO")) isomorphism(graph, *get_graph(a[1]));
    else if (!strcmp(cmd, "SUBISO")) {
        Graph destination = *get_graph(a[1]);
        Embeddings result = {0};
        if (graph.n <= destination.n) embedding_search(graph, destination, 0, 0, (Label){0}, true, &result);
        Canonical data = canonical(graph);
        printf("subiso %s %s embeddings %llu induced %llu\ncopies %llu induced %llu\n", name, a[1], (unsigned long long)result.count, (unsigned long long)result.induced, (unsigned long long)(result.count / data.count), (unsigned long long)(result.induced / data.count));
        for (int i = 0; i < result.first_count; i++) {
            printf("embedding ");
            print_numbers(result.first[i].map.values, graph.n);
            puts(result.first[i].induced ? " induced" : "");
        }
        free(data.maxima);
    } else if (!strcmp(cmd, "CLASSIFY")) classify(atoi(name));
}

static char *read_line(void) {
    Buffer b = {0};
    int c;
    while ((c = getchar()) != EOF && c != '\n') append(&b, (char[]){(char)c, 0});
    if (c == EOF && !b.length) return NULL;
    return finish(&b);
}
int main(void) {
    int count = atoi(read_line());
    for (int i = 0; i < count; i++) {
        char *line = read_line();
        if (setjmp(failure)) printf("error: %s\n", error_reason);
        else command(line);
    }
    return 0;
}
