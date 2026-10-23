#include <limits.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define MAX_NODES 20
#define MAX_EDGES 60
#define WORK_NODES (2 * MAX_NODES + 2)
#define WORK_EDGES (MAX_EDGES + MAX_NODES)
typedef struct {
    int u, v, capacity, cost, lower, flow;
} Edge;
typedef struct {
    int n, m;
    char *names[WORK_NODES];
    Edge edges[WORK_EDGES];
} Graph;
typedef struct {
    int count, arcs[WORK_NODES];
} Path;
typedef struct {
    Path path;
    int amount, stage, unit_cost;
} Augmentation;
typedef struct {
    Augmentation *items;
    int count, capacity;
} Augmentations;
typedef struct {
    bool cycle;
    int start, amount;
    Path path;
} Piece;
typedef struct {
    Piece *items;
    int count, capacity;
} Pieces;
typedef struct {
    int level[WORK_NODES], parent[WORK_NODES];
} Search;
static Graph network;
static int demand[MAX_NODES], owner, source, target;
static jmp_buf command_error;

static void *allocate(size_t bytes) {
    void *p = malloc(bytes);
    if (!p) exit(EXIT_FAILURE);
    return p;
}

static char *copy_string(const char *s) {
    char *p = allocate(strlen(s) + 1);
    strcpy(p, s);
    return p;
}

static void fail(const char *format, ...) {
    va_list args;
    va_start(args, format);
    fputs("ERROR ", stdout);
    vprintf(format, args);
    putchar('\n');
    va_end(args);
    longjmp(command_error, 1);
}

static int minimum(int a, int b) {
    return a < b ? a : b;
}

static Edge *edge(Graph *g, int arc) {
    return &g->edges[abs(arc) - 1];
}

static int from(Graph *g, int arc) {
    Edge *e = edge(g, arc);
    return arc > 0 ? e->u : e->v;
}

static int to(Graph *g, int arc) {
    Edge *e = edge(g, arc);
    return arc > 0 ? e->v : e->u;
}

static int residual(Graph *g, int arc) {
    Edge *e = edge(g, arc);
    return arc > 0 ? e->capacity - e->flow : e->flow;
}

static int arc_cost(Graph *g, int arc) {
    return arc > 0 ? edge(g, arc)->cost : -edge(g, arc)->cost;
}

static void add_edge(Graph *g, int u, int v, int capacity, int cost) {
    g->edges[g->m++] = (Edge){u, v, capacity, cost, 0, 0};
}

static Graph zero_copy(Graph *g) {
    Graph result = *g;
    for (int i = 0; i < result.m; i++) result.edges[i].flow = 0;
    return result;
}

static int arcs(Graph *g, int u, int *result) {
    int count = 0;
    for (int i = 0; i < g->m; i++) if (g->edges[i].u == u) result[count++] = i + 1;
    for (int i = 0; i < g->m; i++) if (g->edges[i].v == u) result[count++] = -i - 1;
    return count;
}

static void balances(Graph *g, int *b) {
    memset(b, 0, (size_t)g->n * sizeof *b);
    for (int i = 0; i < g->m; i++) {
        Edge *e = &g->edges[i];
        b[e->u] += e->flow;
        b[e->v] -= e->flow;
    }
}

static int value(Graph *g, int s) {
    int b[WORK_NODES];
    balances(g, b);
    return b[s];
}

static int total_cost(Graph *g) {
    int result = 0;
    for (int i = 0; i < g->m; i++) result += g->edges[i].flow * g->edges[i].cost;
    return result;
}

static int bottleneck(Graph *g, Path *path) {
    int result = INT_MAX;
    for (int i = 0; i < path->count; i++) result = minimum(result, residual(g, path->arcs[i]));
    return result;
}

static void push(Graph *g, Path *path, int amount) {
    for (int i = 0; i < path->count; i++) {
        int a = path->arcs[i];
        edge(g, a)->flow += a > 0 ? amount : -amount;
    }
}

static void notation(Graph *g, int start, Path *path) {
    fputs(g->names[start], stdout);
    for (int i = 0; i < path->count; i++) {
        int a = path->arcs[i];
        printf(" %c%d %s", a > 0 ? '+' : '-', abs(a), g->names[to(g, a)]);
    }
}

static Search bfs(Graph *g, int s, int threshold) {
    Search search = {0};
    for (int u = 0; u < g->n; u++) search.level[u] = -1;
    int queue[WORK_NODES], head = 0, tail = 0;
    search.level[s] = 0;
    queue[tail++] = s;
    while (head < tail) {
        int u = queue[head++], list[2 * WORK_EDGES], count = arcs(g, u, list);
        for (int i = 0; i < count; i++) {
            int a = list[i], v = to(g, a);
            if (residual(g, a) >= threshold && search.level[v] < 0) {
                search.level[v] = search.level[u] + 1;
                search.parent[v] = a;
                queue[tail++] = v;
            }
        }
    }
    return search;
}

static Path parent_path(Graph *g, int s, int t, int *parent) {
    Path result = {0};
    for (int v = t; v != s; v = from(g, parent[v])) result.arcs[result.count++] = parent[v];
    for (int i = 0; i < result.count / 2; i++) {
        int a = result.arcs[i];
        result.arcs[i] = result.arcs[result.count - 1 - i];
        result.arcs[result.count - 1 - i] = a;
    }
    return result;
}

static void record_augmentation(Augmentations *list, Path path, int amount, int stage, int cost) {
    if (list->count == list->capacity) {
        list->capacity = list->capacity ? 2 * list->capacity : 8;
        Augmentation *p = realloc(list->items, (size_t)list->capacity * sizeof *p);
        if (!p) exit(EXIT_FAILURE);
        list->items = p;
    }
    list->items[list->count++] = (Augmentation){path, amount, stage, cost};
}

static Augmentations maximum(Graph *g, int s, int t, const char *method) {
    Augmentations result = {0};
    if (!strcmp(method, "DINIC")) {
        int phase = 0;
        for (;;) {
            Search search = bfs(g, s, 1);
            if (search.level[t] < 0) break;
            phase++;
            int lists[WORK_NODES][2 * WORK_EDGES], counts[WORK_NODES], pointer[WORK_NODES] = {0};
            for (int u = 0; u < g->n; u++) counts[u] = arcs(g, u, lists[u]);
            Path path = {0};
            int u = s;
            for (;;) {
                if (u == t) {
                    int amount = bottleneck(g, &path);
                    record_augmentation(&result, path, amount, phase, 0);
                    push(g, &path, amount);
                    path.count = 0;
                    u = s;
                } else if (pointer[u] == counts[u]) {
                    if (u == s) break;
                    u = from(g, path.arcs[--path.count]);
                    pointer[u]++;
                } else {
                    int a = lists[u][pointer[u]], v = to(g, a);
                    if (residual(g, a) > 0 && search.level[v] == search.level[u] + 1) {
                        path.arcs[path.count++] = a;
                        u = v;
                    } else pointer[u]++;
                }
            }
        }
        return result;
    }
    int threshold = 1;
    if (!strcmp(method, "SCALING")) {
        int largest = 0;
        for (int i = 0; i < g->m; i++) if (g->edges[i].capacity > largest) largest = g->edges[i].capacity;
        while (threshold <= largest / 2) threshold *= 2;
    }
    do {
        for (;;) {
            Search search = bfs(g, s, threshold);
            if (search.level[t] < 0) break;
            Path path = parent_path(g, s, t, search.parent);
            int amount = bottleneck(g, &path);
            push(g, &path, amount);
            record_augmentation(&result, path, amount, threshold, 0);
            if (!strcmp(method, "AUGMENT")) return result;
        }
        threshold /= 2;
    }
    while (threshold > 0);
    return result;
}

static void finish_maximum(Graph *g, int s, int t) {
    Augmentations paths = maximum(g, s, t, "MAXFLOW");
    free(paths.items);
}

static bool negative_cycle(Graph *g, bool subtract_lower) {
    int distance[WORK_NODES] = {0};
    for (int pass = 0; pass < g->n; pass++) {
        bool changed = false;
        for (int i = 0; i < g->m; i++) {
            Edge *e = &g->edges[i];
            if (e->capacity - (subtract_lower ? e->lower : 0) > 0 && distance[e->v] > distance[e->u] + e->cost) {
                distance[e->v] = distance[e->u] + e->cost;
                changed = true;
            }
        }
        if (!changed) return false;
    }
    return g->n != 0;
}

static Augmentations cheapest(Graph *g, int s, int t, int wanted) {
    Augmentations result = {0};
    int pushed = 0;
    while (wanted < 0 || pushed < wanted) {
        /* The usable global arc sequence stays fixed throughout these passes. */
        int usable[2 * WORK_EDGES], count = 0;
        for (int i = 1; i <= g->m; i++) if (residual(g, i) > 0) usable[count++] = i;
        for (int i = 1; i <= g->m; i++) if (residual(g, -i) > 0) usable[count++] = -i;
        int distance[WORK_NODES] = {0}, parent[WORK_NODES] = {0};
        bool known[WORK_NODES] = {false}, changed;
        known[s] = true;
        do {
            changed = false;
            for (int i = 0; i < count; i++) {
                int a = usable[i], u = from(g, a), v = to(g, a);
                if (known[u] && (!known[v] || distance[u] + arc_cost(g, a) < distance[v])) {
                    distance[v] = distance[u] + arc_cost(g, a);
                    known[v] = true;
                    parent[v] = a;
                    changed = true;
                }
            }
        }
        while (changed);
        if (!known[t]) break;
        Path path = parent_path(g, s, t, parent);
        int amount = bottleneck(g, &path);
        if (wanted >= 0) amount = minimum(amount, wanted - pushed);
        push(g, &path, amount);
        pushed += amount;
        record_augmentation(&result, path, amount, 0, distance[t]);
    }
    return result;
}

static void record_piece(Pieces *list, bool cycle, int start, Path path, int amount) {
    if (list->count == list->capacity) {
        list->capacity = list->capacity ? 2 * list->capacity : 8;
        Piece *p = realloc(list->items, (size_t)list->capacity * sizeof *p);
        if (!p) exit(EXIT_FAILURE);
        list->items = p;
    }
    list->items[list->count++] = (Piece){cycle, start, amount, path};
}

static Pieces decompose(Graph *g) {
    int remaining[WORK_EDGES], balance[WORK_NODES];
    balances(g, balance);
    for (int i = 0; i < g->m; i++) remaining[i] = g->edges[i].flow;
    Pieces result = {0};
    for (;;) {
        int first = -1;
        for (int i = 0; i < g->m; i++) if (remaining[i] > 0) {
            first = i;
            break;
        }
        if (first < 0) break;
        int start = -1;
        for (int u = 0; u < g->n; u++) if (balance[u] > 0) {
            start = u;
            break;
        }
        if (start < 0) start = g->edges[first].u;
        int vertices[WORK_NODES], length = 1;
        vertices[0] = start;
        Path path = {0};
        for (;;) {
            int u = vertices[length - 1], i = 0;
            while (g->edges[i].u != u || remaining[i] == 0) i++;
            int v = g->edges[i].v;
            path.arcs[path.count++] = i + 1;
            int repeated = -1;
            for (int j = 0; j < length; j++) if (vertices[j] == v) {
                repeated = j;
                break;
            }
            if (repeated >= 0) {
                Path cycle = {0};
                int amount = INT_MAX;
                for (int j = repeated; j < path.count; j++) {
                    int a = path.arcs[j];
                    cycle.arcs[cycle.count++] = a;
                    amount = minimum(amount, remaining[a - 1]);
                }
                for (int j = 0; j < cycle.count; j++) remaining[cycle.arcs[j] - 1] -= amount;
                record_piece(&result, true, v, cycle, amount);
                break;
            }
            vertices[length++] = v;
            if (balance[v] < 0) {
                int amount = minimum(balance[start], -balance[v]);
                for (int j = 0; j < path.count; j++) amount = minimum(amount, remaining[path.arcs[j] - 1]);
                for (int j = 0; j < path.count; j++) remaining[path.arcs[j] - 1] -= amount;
                balance[start] -= amount;
                balance[v] += amount;
                record_piece(&result, false, start, path, amount);
                break;
            }
        }
    }
    return result;
}

static int node(const char *name) {
    for (int i = 0; i < network.n; i++) if (!strcmp(name, network.names[i])) return i;
    fail("UNKNOWN NODE %s", name);
    return -1;
}

static Edge *checked_edge(const char *text) {
    int number = atoi(text);
    if (number < 1 || number > network.m) fail("UNKNOWN EDGE %s", text);
    return &network.edges[number - 1];
}

static void endpoints(char *s, char *t, int *u, int *v) {
    *u = node(s);
    *v = node(t);
    if (*u == *v) fail("SAME NODE");
}

static int start_flow(int s, int t) {
    if (owner != 1 || source != s || target != t) for (int i = 0; i < network.m; i++) network.edges[i].flow = 0;
    owner = 1;
    source = s;
    target = t;
    return value(&network, s);
}

static void flow_list(void) {
    for (int i = 0; i < network.m; i++) {
        Edge *e = &network.edges[i];
        printf("FLOW %d %s %s %d/%d\n", i + 1, network.names[e->u], network.names[e->v], e->flow, e->capacity);
    }
}

static void copy_flows(Graph *g, bool lower) {
    for (int i = 0; i < network.m; i++) network.edges[i].flow = g->edges[i].flow + (lower ? network.edges[i].lower : 0);
}

static int split(char *s, char separator, char **parts) {
    int count = 0;
    parts[count++] = s;
    for (char *p = s; *p; p++) if (*p == separator) {
        *p = '\0';
        parts[count++] = p + 1;
    }
    return count;
}
typedef struct {
    int na, nb, np, pairs[60][2], a[12], b[12];
    char *left[12], *right[12];
} Matching;

static bool try_match(Matching *m, int u, bool *examined) {
    for (int i = 0; i < m->np; i++) if (m->pairs[i][0] == u) {
        int v = m->pairs[i][1];
        if (examined[v]) continue;
        examined[v] = true;
        if (m->b[v] < 0 || try_match(m, m->b[v], examined)) {
            m->a[u] = v;
            m->b[v] = u;
            return true;
        }
    }
    return false;
}

static void comma_names(char **names, int count, const bool *included) {
    bool first = true;
    for (int i = 0; i < count; i++) if (included[i]) {
        if (!first) putchar(',');
        fputs(names[i], stdout);
        first = false;
    }
    if (first) putchar('-');
}

static void matching(char **w) {
    Matching m = {0};
    m.na = split(w[1], ',', m.left);
    m.nb = split(w[2], ',', m.right);
    for (int i = 0; i < m.na; i++) for (int j = 0; j < i; j++) if (!strcmp(m.left[i], m.left[j])) fail("DUPLICATE VERTEX %s", m.left[i]);
    for (int i = 0; i < m.nb; i++) {
        for (int j = 0; j < i; j++) if (!strcmp(m.right[i], m.right[j])) fail("DUPLICATE VERTEX %s", m.right[i]);
        for (int j = 0; j < m.na; j++) if (!strcmp(m.right[i], m.left[j])) fail("DUPLICATE VERTEX %s", m.right[i]);
    }
    if (strcmp(w[3], "-")) {
        char *pairs[60];
        m.np = split(w[3], ',', pairs);
        for (int i = 0; i < m.np; i++) {
            char *p[2];
            split(pairs[i], '-', p);
            int u = -1, v = -1;
            for (int j = 0; j < m.na; j++) if (!strcmp(p[0], m.left[j])) u = j;
            for (int j = 0; j < m.nb; j++) if (!strcmp(p[1], m.right[j])) v = j;
            if (u < 0) fail("UNKNOWN VERTEX %s", p[0]);
            if (v < 0) fail("UNKNOWN VERTEX %s", p[1]);
            for (int j = 0; j < i; j++) if (m.pairs[j][0] == u && m.pairs[j][1] == v) fail("DUPLICATE PAIR %s-%s", p[0], p[1]);
            m.pairs[i][0] = u;
            m.pairs[i][1] = v;
        }
    }
    for (int i = 0; i < m.na; i++) m.a[i] = -1;
    for (int i = 0; i < m.nb; i++) m.b[i] = -1;
    for (int i = 0; i < m.na; i++) {
        bool examined[12] = {false};
        try_match(&m, i, examined);
    }
    bool za[12] = {false}, zb[12] = {false}, free_a[12] = {false}, free_b[12] = {false};
    int queue[12], head = 0, tail = 0, size = 0;
    for (int u = 0; u < m.na; u++) {
        if (m.a[u] < 0) {
            free_a[u] = za[u] = true;
            queue[tail++] = u;
        } else size++;
    }
    while (head < tail) {
        int u = queue[head++];
        for (int i = 0; i < m.np; i++) if (m.pairs[i][0] == u) {
            int v = m.pairs[i][1];
            if (m.a[u] == v || zb[v]) continue;
            zb[v] = true;
            if (m.b[v] >= 0 && !za[m.b[v]]) {
                za[m.b[v]] = true;
                queue[tail++] = m.b[v];
            }
        }
    }
    printf("MATCH size=%d left=%d right=%d\n", size, m.na, m.nb);
    for (int u = 0; u < m.na; u++) if (m.a[u] >= 0) printf("PAIR %s %s\n", m.left[u], m.right[m.a[u]]);
    for (int v = 0; v < m.nb; v++) free_b[v] = m.b[v] < 0;
    fputs("FREE ", stdout);
    comma_names(m.left, m.na, free_a);
    putchar(' ');
    comma_names(m.right, m.nb, free_b);
    putchar('\n');
    printf("COVER size=%d", size);
    for (int u = 0; u < m.na; u++) if (!za[u]) printf(" %s", m.left[u]);
    for (int v = 0; v < m.nb; v++) if (zb[v]) printf(" %s", m.right[v]);
    putchar('\n');
    if (size < m.na) {
        fputs("HALL ", stdout);
        comma_names(m.left, m.na, za);
        putchar(' ');
        comma_names(m.right, m.nb, zb);
        putchar('\n');
    }
}
typedef struct {
    int n, values[8][8], best, count, chosen[8], current[8];
    bool forbidden[8][8], minimize;
} Assignment;

static void assign_visit(Assignment *a, int row, unsigned used, int sum) {
    if (row == a->n) {
        if (a->count == 0 || (a->minimize ? sum < a->best : sum > a->best)) {
            a->best = sum;
            a->count = 1;
            memcpy(a->chosen, a->current, sizeof a->chosen);
        } else if (sum == a->best) a->count++;
        return;
    }
    for (int col = 0; col < a->n; col++) if (!(used & (1u << col)) && !a->forbidden[row][col]) {
        a->current[row] = col;
        assign_visit(a, row + 1, used | (1u << col), sum + a->values[row][col]);
    }
}

static void assignment(char **w, int count) {
    int n = atoi(w[2]);
    if (n < 1 || n > 8) fail("BAD SIZE");
    if (count - 3 != n * n) fail("BAD LENGTH");
    Assignment a = {0};
    a.n = n;
    a.minimize = !strcmp(w[1], "MIN");
    for (int i = 0; i < n * n; i++) {
        a.forbidden[i / n][i % n] = !strcmp(w[i + 3], "x");
        if (!a.forbidden[i / n][i % n]) a.values[i / n][i % n] = atoi(w[i + 3]);
    }
    assign_visit(&a, 0, 0, 0);
    if (a.count == 0) printf("ASSIGN %s n=%d infeasible\n", w[1], n);
    else {
        printf("ASSIGN %s n=%d total=%d optimal=%d\n", w[1], n, a.best, a.count);
        for (int i = 0; i < n; i++) printf("MATE %d %d %d\n", i + 1, a.chosen[i] + 1, a.values[i][a.chosen[i]]);
    }
}

static void command(char *line) {
    char *w[1001];
    int count = split(line, ' ', w);
    char *c = w[0];
    if (!strcmp(c, "NODE")) {
        for (int i = 1; i < count; i++) {
            for (int j = 0; j < network.n; j++) if (!strcmp(w[i], network.names[j])) fail("DUPLICATE NODE %s", w[i]);
            for (int j = 1; j < i; j++) if (!strcmp(w[i], w[j])) fail("DUPLICATE NODE %s", w[i]);
        }
        if (network.n + count - 1 > MAX_NODES) fail("TOO MANY NODES");
        for (int i = 1; i < count; i++) {
            demand[network.n] = 0;
            network.names[network.n++] = copy_string(w[i]);
        }
        printf("NODE added=%d total=%d\n", count - 1, network.n);
    } else if (!strcmp(c, "EDGE")) {
        int u = node(w[1]), v = node(w[2]);
        if (u == v) fail("SELF LOOP");
        if (network.m == MAX_EDGES) fail("TOO MANY EDGES");
        int capacity = atoi(w[3]), cost = count == 5 ? atoi(w[4]) : 0;
        add_edge(&network, u, v, capacity, cost);
        printf("EDGE %d %s %s cap=%d cost=%d\n", network.m, w[1], w[2], capacity, cost);
    } else if (!strcmp(c, "LOWER") || !strcmp(c, "CAP") || !strcmp(c, "COST")) {
        Edge *e = checked_edge(w[1]);
        int number = atoi(w[1]), amount = atoi(w[2]);
        if (!strcmp(c, "LOWER")) {
            if (amount > e->capacity) fail("BAD BOUND");
            e->lower = amount;
            printf("LOWER %d low=%d cap=%d\n", number, amount, e->capacity);
        } else if (!strcmp(c, "CAP")) {
            if (amount < e->lower) fail("BAD BOUND");
            if (amount < e->flow) fail("BELOW FLOW");
            e->capacity = amount;
            printf("CAP %d low=%d cap=%d\n", number, e->lower, amount);
        } else {
            e->cost = amount;
            printf("COST %d cost=%d\n", number, amount);
        }
    } else if (!strcmp(c, "DEMAND")) {
        int u = node(w[1]), amount = atoi(w[2]), sum = 0;
        demand[u] = amount;
        for (int i = 0; i < network.n; i++) sum += demand[i];
        printf("DEMAND %s %d total=%d\n", w[1], amount, sum);
    } else if (!strcmp(c, "RESET")) {
        int changed = 0;
        for (int i = 0; i < network.m; i++) {
            if (network.edges[i].flow) changed++;
            network.edges[i].flow = 0;
        }
        owner = 0;
        printf("RESET edges=%d\n", changed);
    } else if (!strcmp(c, "CLEAR")) {
        printf("CLEAR nodes=%d edges=%d\n", network.n, network.m);
        for (int i = 0; i < network.n; i++) free(network.names[i]);
        memset(&network, 0, sizeof network);
        owner = 0;
    } else if (!strcmp(c, "SHOW")) {
        printf("NETWORK nodes=%d edges=%d\n", network.n, network.m);
        if (owner == 0) puts("STATE none");
        else if (owner == 2) printf("STATE circulation cost=%d\n", total_cost(&network));
        else printf("STATE flow %s %s value=%d cost=%d\n", network.names[source], network.names[target], value(&network, source), total_cost(&network));
        for (int u = 0; u < network.n; u++) {
            int sent = 0, received = 0;
            for (int i = 0; i < network.m; i++) {
                if (network.edges[i].u == u) sent += network.edges[i].flow;
                if (network.edges[i].v == u) received += network.edges[i].flow;
            }
            printf("NODE %s demand=%d out=%d in=%d\n", network.names[u], demand[u], sent, received);
        }
        for (int i = 0; i < network.m; i++) {
            Edge *e = &network.edges[i];
            printf("EDGE %d %s %s cap=%d cost=%d low=%d flow=%d\n", i + 1, network.names[e->u], network.names[e->v], e->capacity, e->cost, e->lower, e->flow);
        }
    } else if (!strcmp(c, "AUGMENT") || !strcmp(c, "MAXFLOW") || !strcmp(c, "DINIC") || !strcmp(c, "SCALING") || !strcmp(c, "MINCUT")) {
        int s, t;
        endpoints(w[1], w[2], &s, &t);
        int initial = start_flow(s, t);
        Augmentations paths = maximum(&network, s, t, c);
        printf("%s %s %s value=%d", c, w[1], w[2], value(&network, s));
        if (!strcmp(c, "AUGMENT")) {
            if (!paths.count) puts(" none");
            else {
                printf(" amount=%d ", paths.items[0].amount);
                notation(&network, s, &paths.items[0].path);
                putchar('\n');
            }
        } else if (!strcmp(c, "MINCUT")) {
            Search search = bfs(&network, s, 1);
            int cut = 0;
            for (int i = 0; i < network.m; i++) {
                Edge *e = &network.edges[i];
                if (search.level[e->u] >= 0 && search.level[e->v] < 0) cut++;
            }
            printf(" edges=%d\nSOURCE", cut);
            for (int u = 0; u < network.n; u++) if (search.level[u] >= 0) printf(" %s", network.names[u]);
            fputs("\nSINK", stdout);
            for (int u = 0; u < network.n; u++) if (search.level[u] < 0) printf(" %s", network.names[u]);
            putchar('\n');
            for (int i = 0; i < network.m; i++) {
                Edge *e = &network.edges[i];
                if (search.level[e->u] >= 0 && search.level[e->v] < 0) printf("CUT %d %s %s %d\n", i + 1, network.names[e->u], network.names[e->v], e->capacity);
            }
        } else {
            printf(" start=%d", initial);
            if (!strcmp(c, "DINIC")) printf(" phases=%d", paths.count ? paths.items[paths.count - 1].stage : 0);
            printf(" paths=%d\n", paths.count);
            for (int i = 0; i < paths.count; i++) {
                Augmentation *a = &paths.items[i];
                printf("AUG %d", i + 1);
                if (!strcmp(c, "DINIC")) printf(" phase=%d", a->stage);
                if (!strcmp(c, "SCALING")) printf(" delta=%d", a->stage);
                printf(" amount=%d ", a->amount);
                notation(&network, s, &a->path);
                putchar('\n');
            }
            flow_list();
        }
        free(paths.items);
    } else if (!strcmp(c, "SENSITIVITY")) {
        int s, t;
        endpoints(w[1], w[2], &s, &t);
        Graph g = zero_copy(&network);
        finish_maximum(&g, s, t);
        int amount = value(&g, s), up_count = 0, down_count = 0;
        bool up[MAX_EDGES], down[MAX_EDGES];
        for (int i = 0; i < network.m; i++) {
            g = zero_copy(&network);
            g.edges[i].capacity++;
            finish_maximum(&g, s, t);
            up[i] = value(&g, s) > amount;
            down[i] = false;
            if (network.edges[i].capacity > 0) {
                g = zero_copy(&network);
                g.edges[i].capacity--;
                finish_maximum(&g, s, t);
                down[i] = value(&g, s) < amount;
            }
            up_count += up[i];
            down_count += down[i];
        }
        printf("SENSITIVITY %s %s value=%d up=%d down=%d\n", w[1], w[2], amount, up_count, down_count);
        for (int i = 0; i < network.m; i++) if (up[i] || down[i]) {
            Edge *e = &network.edges[i];
            printf("CRITICAL %d %s %s up=%s down=%s\n", i + 1, network.names[e->u], network.names[e->v], up[i] ? "yes" : "no", down[i] ? "yes" : "no");
        }
    } else if (!strcmp(c, "MINCOST")) {
        int s, t;
        endpoints(w[1], w[2], &s, &t);
        if (negative_cycle(&network, false)) fail("NEGATIVE CYCLE");
        int wanted = !strcmp(w[3], "MAX") ? -1 : atoi(w[3]);
        Graph g = zero_copy(&network);
        Augmentations paths = cheapest(&g, s, t, wanted);
        int amount = value(&g, s);
        printf("MINCOST %s %s k=%s", w[1], w[2], w[3]);
        if (wanted >= 0 && amount < wanted) printf(" infeasible max=%d\n", amount);
        else {
            copy_flows(&g, false);
            owner = 1;
            source = s;
            target = t;
            printf(" flow=%d cost=%d\n", amount, total_cost(&g));
            for (int i = 0; i < paths.count; i++) {
                Augmentation *a = &paths.items[i];
                printf("AUG %d amount=%d cost=%d ", i + 1, a->amount, a->unit_cost);
                notation(&g, s, &a->path);
                putchar('\n');
            }
            flow_list();
        }
        free(paths.items);
    } else if (!strcmp(c, "DISJOINT")) {
        int s, t;
        endpoints(w[1], w[2], &s, &t);
        Graph g = {0};
        g.n = network.n;
        memcpy(g.names, network.names, (size_t)g.n * sizeof *g.names);
        int exits[MAX_NODES];
        for (int u = 0; u < network.n; u++) {
            exits[u] = u;
            if (!strcmp(w[3], "VERTEX") && u != s && u != t) {
                exits[u] = g.n;
                g.names[g.n++] = network.names[u];
            }
        }
        for (int i = 0; i < network.m; i++) {
            Edge *e = &network.edges[i];
            add_edge(&g, exits[e->u], e->v, e->capacity > 0, 0);
        }
        for (int u = 0; u < network.n; u++) if (exits[u] != u) add_edge(&g, u, exits[u], 1, 0);
        finish_maximum(&g, s, t);
        Pieces pieces = decompose(&g);
        int paths = 0;
        for (int i = 0; i < pieces.count; i++) if (!pieces.items[i].cycle) paths++;
        printf("DISJOINT %s %s %s count=%d\n", w[1], w[2], w[3], paths);
        int number = 0;
        for (int i = 0; i < pieces.count; i++) if (!pieces.items[i].cycle) {
            printf("PATH %d %s", ++number, w[1]);
            Path *path = &pieces.items[i].path;
            for (int j = 0; j < path->count; j++) {
                int a = path->arcs[j];
                if (a <= network.m) printf(" +%d %s", a, network.names[network.edges[a - 1].v]);
            }
            putchar('\n');
        }
        free(pieces.items);
    } else if (!strcmp(c, "DECOMPOSE")) {
        Pieces pieces = decompose(&network);
        int cycles = 0, path_number = 0, cycle_number = 0;
        for (int i = 0; i < pieces.count; i++) cycles += pieces.items[i].cycle;
        printf("DECOMPOSE paths=%d cycles=%d\n", pieces.count - cycles, cycles);
        for (int i = 0; i < pieces.count; i++) {
            Piece *p = &pieces.items[i];
            printf("%s %d amount=%d ", p->cycle ? "CYCLE" : "PATH", p->cycle ? ++cycle_number : ++path_number, p->amount);
            notation(&network, p->start, &p->path);
            putchar('\n');
        }
        free(pieces.items);
    } else if (!strcmp(c, "VERIFY")) {
        int violations = 0, balance[WORK_NODES];
        balances(&network, balance);
        for (int i = 0; i < network.m; i++) if (network.edges[i].flow < network.edges[i].lower) violations++;
        for (int u = 0; u < network.n; u++) if ((owner != 1 || (u != source && u != target)) && -balance[u] != (owner == 1 ? 0 : demand[u])) violations++;
        if (!violations) puts("VERIFY ok");
        else {
            printf("VERIFY violations=%d\n", violations);
            for (int i = 0; i < network.m; i++) {
                Edge *e = &network.edges[i];
                if (e->flow < e->lower) printf("LOW %d flow=%d low=%d\n", i + 1, e->flow, e->lower);
            }
            for (int u = 0; u < network.n; u++) if ((owner != 1 || (u != source && u != target)) && -balance[u] != (owner == 1 ? 0 : demand[u])) printf("BALANCE %s net=%d need=%d\n", network.names[u], -balance[u], owner == 1 ? 0 : demand[u]);
        }
    } else if (!strcmp(c, "CIRCULATION")) {
        bool mincost = !strcmp(w[1], "MINCOST");
        if (mincost && negative_cycle(&network, true)) fail("NEGATIVE CYCLE");
        int sum = 0;
        for (int u = 0; u < network.n; u++) sum += demand[u];
        if (sum) {
            printf("CIRCULATION infeasible unbalanced=%d\n", sum);
            return;
        }
        Graph g = zero_copy(&network);
        int n = g.n, remaining[MAX_NODES], required = 0;
        g.names[g.n++] = "source";
        g.names[g.n++] = "sink";
        memcpy(remaining, demand, (size_t)n * sizeof *remaining);
        for (int i = 0; i < g.m; i++) {
            Edge *e = &g.edges[i];
            remaining[e->u] += e->lower;
            remaining[e->v] -= e->lower;
            e->capacity -= e->lower;
        }
        for (int u = 0; u < n; u++) if (remaining[u] < 0) add_edge(&g, n, u, -remaining[u], 0);
        for (int u = 0; u < n; u++) if (remaining[u] > 0) {
            add_edge(&g, u, n + 1, remaining[u], 0);
            required += remaining[u];
        }
        if (mincost) {
            Augmentations paths = cheapest(&g, n, n + 1, -1);
            free(paths.items);
        } else finish_maximum(&g, n, n + 1);
        int achieved = -value(&g, n + 1);
        if (achieved < required) {
            printf("CIRCULATION infeasible required=%d achieved=%d\nCUT", required, achieved);
            Search search = bfs(&g, n, 1);
            for (int u = 0; u < n; u++) if (search.level[u] >= 0) printf(" %s", network.names[u]);
            putchar('\n');
        } else {
            copy_flows(&g, true);
            owner = 2;
            printf("CIRCULATION feasible required=%d cost=%d\n", required, total_cost(&network));
            flow_list();
        }
    } else if (!strcmp(c, "MATCH")) matching(w);
    else if (!strcmp(c, "ASSIGN")) assignment(w, count);
}

static char *read_line(void) {
    size_t length = 0, capacity = 128;
    char *line = allocate(capacity);
    int ch;
    while ((ch = getchar()) != EOF && ch != '\n') {
        if (length + 1 == capacity) {
            capacity *= 2;
            char *p = realloc(line, capacity);
            if (!p) exit(EXIT_FAILURE);
            line = p;
        }
        line[length++] = (char)ch;
    }
    line[length] = '\0';
    return line;
}
int main(void) {
    char *first = read_line();
    int n = atoi(first);
    free(first);
    for (int i = 0; i < n; i++) {
        char *line = read_line();
        if (setjmp(command_error) == 0) command(line);
        free(line);
    }
    for (int i = 0; i < network.n; i++) free(network.names[i]);
    return 0;
}
