#include <inttypes.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { MAX_N = 2000, TREE_SIZE = 8005, LEVELS = 11, MAX_COMMANDS = 1000 };
typedef enum { SEG, LAZY, FEN, RFEN, SPARSE, SQRT, PERSIST, GRID } Kind;
typedef enum { SUM, MIN, MAX, GCD } Operation;
static const char *kind_names[] = {"SEG", "LAZY", "FEN", "RFEN", "SPARSE", "SQRT", "PERSIST", "GRID"};
static const char *op_names[] = {"SUM", "MIN", "MAX", "GCD"};
static const char *value_names[] = {"sum", "min", "max", "gcd"};

typedef struct { int left, right; bool present; } Bounds;
typedef struct { int64_t sum, min, max; } Aggregate;
typedef struct { int visited, covered, pushes; } Counts;
typedef struct { int64_t value; int visited; } Answer;
typedef struct { Operation op; int64_t values[TREE_SIZE]; } Segment;
typedef struct { Aggregate value; int64_t assign, add; bool assigned; } LazyNode;
typedef struct { LazyNode nodes[TREE_SIZE]; } Lazy;
typedef struct { int64_t values[MAX_N], tree[MAX_N + 1]; } Fenwick;
typedef struct { int64_t first[MAX_N + 1], second[MAX_N + 1]; } RangeFenwick;
typedef struct { int64_t values[MAX_N]; int min[LEVELS][MAX_N], max[LEVELS][MAX_N], levels, entries; } Sparse;
typedef struct { int block, blocks; int64_t values[MAX_N], tags[MAX_N], sums[MAX_N]; } Sqrt;
typedef struct { int left, right; int64_t value; } PersistentNode;
typedef struct { PersistentNode *nodes; int size, capacity; } Pool;
typedef struct {
    Pool position, value;
    int roots[MAX_COMMANDS + 1], prefixes[MAX_N + 1], versions, distinct;
    int64_t values[MAX_N];
} Persistent;
typedef struct { int height, width; int64_t tree[21][21]; } Grid;
typedef struct {
    int n, max_node;
    int64_t values[MAX_N], original[MAX_N];
    bool built[8];
    Bounds bounds[TREE_SIZE];
    Segment seg;
    Lazy lazy;
    Fenwick fen;
    RangeFenwick rfen;
    Sparse sparse;
    Sqrt sqrt;
    Persistent persist;
    Grid grid;
} Lab;
typedef struct { int min, max, level; } SparseAnswer;
typedef struct { int64_t sum; int whole, cells; } SqrtAnswer;
typedef struct { int number, left, right, block; } MoQuery;
typedef struct { Aggregate values; int64_t gcd; } Reference;

static int64_t minimum(int64_t a, int64_t b) { return a < b ? a : b; }
static int64_t maximum(int64_t a, int64_t b) { return a > b ? a : b; }
static int64_t gcd_value(int64_t a, int64_t b) {
    if (a < 0) a = -a;
    if (b < 0) b = -b;
    while (b) { int64_t rest = a % b; a = b; b = rest; }
    return a;
}
static int isqrt_value(int n) {
    int result = 1;
    while ((result + 1) * (result + 1) <= n) result++;
    return result;
}
static int compare_values(const void *a, const void *b) {
    int64_t x = *(const int64_t *)a, y = *(const int64_t *)b;
    return (x > y) - (x < y);
}
static int unique_values(int64_t *values, int n) {
    qsort(values, n, sizeof(*values), compare_values);
    int size = 0;
    for (int i = 0; i < n; i++) if (!size || values[i] != values[size - 1]) values[size++] = values[i];
    return size;
}
static int rank_of(const int64_t *values, int n, int64_t target) {
    int left = 0, right = n;
    while (left < right) {
        int mid = (left + right) / 2;
        if (values[mid] < target) left = mid + 1; else right = mid;
    }
    return left;
}
static Aggregate combine(Aggregate a, Aggregate b) {
    return (Aggregate){a.sum + b.sum, minimum(a.min, b.min), maximum(a.max, b.max)};
}
static int64_t operate(Operation op, int64_t a, int64_t b) {
    switch (op) {
        case SUM: return a + b;
        case MIN: return minimum(a, b);
        case MAX: return maximum(a, b);
        case GCD: return gcd_value(a, b);
    }
    return 0;
}
static void shape(Lab *lab, int node, int left, int right) {
    lab->bounds[node] = (Bounds){left, right, true};
    if (node > lab->max_node) lab->max_node = node;
    if (left == right) return;
    int mid = (left + right) / 2;
    shape(lab, 2 * node, left, mid);
    shape(lab, 2 * node + 1, mid + 1, right);
}
static void reset_shape(Lab *lab) {
    memset(lab->bounds, 0, sizeof(lab->bounds));
    lab->max_node = 0;
    shape(lab, 1, 0, lab->n - 1);
}
static void segment_build(Lab *lab, int node) {
    Bounds b = lab->bounds[node];
    if (b.left == b.right) {
        int64_t value = lab->values[b.left];
        lab->seg.values[node] = lab->seg.op == GCD ? gcd_value(value, 0) : value;
    } else {
        segment_build(lab, 2 * node);
        segment_build(lab, 2 * node + 1);
        lab->seg.values[node] = operate(lab->seg.op, lab->seg.values[2 * node], lab->seg.values[2 * node + 1]);
    }
}
static int64_t segment_query(const Lab *lab, int node, int left, int right, int *visited) {
    (*visited)++;
    Bounds b = lab->bounds[node];
    if (left <= b.left && b.right <= right) return lab->seg.values[node];
    int mid = (b.left + b.right) / 2;
    if (right <= mid) return segment_query(lab, 2 * node, left, right, visited);
    if (left > mid) return segment_query(lab, 2 * node + 1, left, right, visited);
    int64_t a = segment_query(lab, 2 * node, left, right, visited);
    int64_t z = segment_query(lab, 2 * node + 1, left, right, visited);
    return operate(lab->seg.op, a, z);
}
static int segment_update(Lab *lab, int node, int index, int64_t value) {
    Bounds b = lab->bounds[node];
    if (b.left == b.right) {
        lab->seg.values[node] = lab->seg.op == GCD ? gcd_value(value, 0) : value;
        return 1;
    }
    int child = 2 * node + (index > (b.left + b.right) / 2);
    int visited = 1 + segment_update(lab, child, index, value);
    lab->seg.values[node] = operate(lab->seg.op, lab->seg.values[2 * node], lab->seg.values[2 * node + 1]);
    return visited;
}
static void lazy_build(Lab *lab, int node) {
    Bounds b = lab->bounds[node];
    LazyNode *current = &lab->lazy.nodes[node];
    *current = (LazyNode){0};
    if (b.left == b.right) {
        int64_t value = lab->values[b.left];
        current->value = (Aggregate){value, value, value};
    } else {
        lazy_build(lab, 2 * node);
        lazy_build(lab, 2 * node + 1);
        current->value = combine(lab->lazy.nodes[2 * node].value, lab->lazy.nodes[2 * node + 1].value);
    }
}
static void lazy_apply(Lab *lab, int node, int64_t value, bool assign) {
    Bounds b = lab->bounds[node];
    LazyNode *current = &lab->lazy.nodes[node];
    int length = b.right - b.left + 1;
    if (assign) current->value = (Aggregate){value * length, value, value};
    else {
        current->value.sum += value * length;
        current->value.min += value;
        current->value.max += value;
    }
    if (b.left == b.right) return;
    if (assign) { current->assigned = true; current->assign = value; current->add = 0; }
    else current->add += value;
}
static void lazy_push(Lab *lab, int node, Counts *counts) {
    LazyNode *current = &lab->lazy.nodes[node];
    if (!current->assigned && current->add == 0) return;
    counts->pushes++;
    for (int child = 2 * node; child <= 2 * node + 1; child++) {
        if (current->assigned) lazy_apply(lab, child, current->assign, true);
        if (current->add) lazy_apply(lab, child, current->add, false);
    }
    current->assigned = false;
    current->add = 0;
}
static void lazy_update(Lab *lab, int node, int left, int right, int64_t value, bool assign, Counts *counts) {
    counts->visited++;
    Bounds b = lab->bounds[node];
    if (left <= b.left && b.right <= right) {
        counts->covered++;
        lazy_apply(lab, node, value, assign);
        return;
    }
    lazy_push(lab, node, counts);
    int mid = (b.left + b.right) / 2;
    if (left <= mid) lazy_update(lab, 2 * node, left, right, value, assign, counts);
    if (right > mid) lazy_update(lab, 2 * node + 1, left, right, value, assign, counts);
    lab->lazy.nodes[node].value = combine(lab->lazy.nodes[2 * node].value, lab->lazy.nodes[2 * node + 1].value);
}
static Aggregate lazy_query(Lab *lab, int node, int left, int right, Counts *counts) {
    counts->visited++;
    Bounds b = lab->bounds[node];
    if (left <= b.left && b.right <= right) return lab->lazy.nodes[node].value;
    lazy_push(lab, node, counts);
    int mid = (b.left + b.right) / 2;
    if (right <= mid) return lazy_query(lab, 2 * node, left, right, counts);
    if (left > mid) return lazy_query(lab, 2 * node + 1, left, right, counts);
    Aggregate a = lazy_query(lab, 2 * node, left, right, counts);
    Aggregate z = lazy_query(lab, 2 * node + 1, left, right, counts);
    return combine(a, z);
}
static int fen_add(int64_t *tree, int n, int position, int64_t value) {
    int visited = 0;
    for (int p = position; p <= n; p += p & -p) { tree[p] += value; visited++; }
    return visited;
}
static Answer fen_prefix(const int64_t *tree, int position) {
    Answer answer = {0};
    for (int p = position; p > 0; p -= p & -p) { answer.value += tree[p]; answer.visited++; }
    return answer;
}
static Answer fen_range(const int64_t *tree, int left, int right) {
    Answer a = fen_prefix(tree, right + 1), b = fen_prefix(tree, left);
    return (Answer){a.value - b.value, a.visited + b.visited};
}
static Answer rfen_prefix(const RangeFenwick *tree, int position) {
    Answer a = fen_prefix(tree->first, position), b = fen_prefix(tree->second, position);
    return (Answer){position * a.value - b.value, a.visited + b.visited};
}
static Answer rfen_range(const RangeFenwick *tree, int left, int right) {
    Answer a = rfen_prefix(tree, right + 1), b = rfen_prefix(tree, left);
    return (Answer){a.value - b.value, a.visited + b.visited};
}
static void sparse_build(Lab *lab) {
    Sparse *s = &lab->sparse;
    memcpy(s->values, lab->values, lab->n * sizeof(int64_t));
    s->levels = s->entries = 0;
    for (int length = 1; length <= lab->n; length *= 2) {
        int level = s->levels++;
        for (int i = 0; i + length <= lab->n; i++) {
            if (!level) { s->min[level][i] = s->max[level][i] = i; }
            else {
                int a = s->min[level - 1][i], b = s->min[level - 1][i + length / 2];
                s->min[level][i] = s->values[a] <= s->values[b] ? a : b;
                a = s->max[level - 1][i]; b = s->max[level - 1][i + length / 2];
                s->max[level][i] = s->values[a] >= s->values[b] ? a : b;
            }
            s->entries++;
        }
    }
}
static SparseAnswer sparse_query(const Sparse *s, int left, int right) {
    int level = 0, length = 1;
    while (2 * length <= right - left + 1) { length *= 2; level++; }
    int end = right - length + 1;
    int a = s->min[level][left], b = s->min[level][end];
    int low = s->values[a] <= s->values[b] ? a : b;
    a = s->max[level][left]; b = s->max[level][end];
    return (SparseAnswer){low, s->values[a] >= s->values[b] ? a : b, level};
}
static SqrtAnswer sqrt_process(Sqrt *s, int left, int right, int64_t value, bool update) {
    SqrtAnswer answer = {0};
    int first = left / s->block, last = right / s->block;
    for (int i = left; i <= right; i++) {
        int block = i / s->block;
        if (block != first && block != last) continue;
        if (update) { s->values[i] += value; s->sums[block] += value; }
        else answer.sum += s->values[i] + s->tags[block];
        answer.cells++;
    }
    for (int block = first + 1; block < last; block++) {
        if (update) { s->tags[block] += value; s->sums[block] += value * s->block; }
        else answer.sum += s->sums[block];
        answer.whole++;
    }
    return answer;
}
static int pool_append(Pool *pool, PersistentNode node) {
    if (pool->size == pool->capacity) {
        int capacity = pool->capacity ? 2 * pool->capacity : 4096;
        PersistentNode *nodes = realloc(pool->nodes, (size_t)capacity * sizeof(*nodes));
        if (!nodes) exit(EXIT_FAILURE);
        pool->nodes = nodes;
        pool->capacity = capacity;
    }
    int index = pool->size++;
    pool->nodes[index] = node;
    return index;
}
static int persistent_build(Pool *pool, const int64_t *values, int left, int right) {
    int index = pool_append(pool, (PersistentNode){-1, -1, 0});
    if (left == right) pool->nodes[index].value = values ? values[left] : 0;
    else {
        int mid = (left + right) / 2;
        int a = persistent_build(pool, values, left, mid);
        int b = persistent_build(pool, values, mid + 1, right);
        pool->nodes[index] = (PersistentNode){a, b, pool->nodes[a].value + pool->nodes[b].value};
    }
    return index;
}
static int persistent_set(Pool *pool, int source, int left, int right, int target, int64_t value, bool increment) {
    PersistentNode node = pool->nodes[source];
    int index = pool_append(pool, node);
    if (left == right) pool->nodes[index].value = increment ? node.value + value : value;
    else {
        int mid = (left + right) / 2;
        if (target <= mid) node.left = persistent_set(pool, node.left, left, mid, target, value, increment);
        else node.right = persistent_set(pool, node.right, mid + 1, right, target, value, increment);
        node.value = pool->nodes[node.left].value + pool->nodes[node.right].value;
        pool->nodes[index] = node;
    }
    return index;
}
static int64_t persistent_query(const Pool *pool, int root, int nl, int nr, int left, int right, int *visited) {
    (*visited)++;
    PersistentNode node = pool->nodes[root];
    if (left <= nl && nr <= right) return node.value;
    int mid = (nl + nr) / 2;
    if (right <= mid) return persistent_query(pool, node.left, nl, mid, left, right, visited);
    if (left > mid) return persistent_query(pool, node.right, mid + 1, nr, left, right, visited);
    int64_t a = persistent_query(pool, node.left, nl, mid, left, right, visited);
    int64_t b = persistent_query(pool, node.right, mid + 1, nr, left, right, visited);
    return a + b;
}
static void persist_clear(Persistent *p) {
    free(p->position.nodes);
    free(p->value.nodes);
    *p = (Persistent){0};
}
static void persist_build(Lab *lab) {
    Persistent *p = &lab->persist;
    persist_clear(p);
    p->roots[0] = persistent_build(&p->position, lab->values, 0, lab->n - 1);
    p->versions = 1;
    memcpy(p->values, lab->values, lab->n * sizeof(int64_t));
    p->distinct = unique_values(p->values, lab->n);
    p->prefixes[0] = persistent_build(&p->value, NULL, 0, p->distinct - 1);
    for (int i = 0; i < lab->n; i++) {
        int rank = rank_of(p->values, p->distinct, lab->values[i]);
        p->prefixes[i + 1] = persistent_set(&p->value, p->prefixes[i], 0, p->distinct - 1, rank, 1, true);
    }
}
static Answer persist_kth(const Persistent *p, int left, int right, int k) {
    int u = p->prefixes[right + 1], w = p->prefixes[left];
    int low = 0, high = p->distinct - 1, visited = 1;
    while (low < high) {
        PersistentNode a = p->value.nodes[u], b = p->value.nodes[w];
        int64_t count = p->value.nodes[a.left].value - p->value.nodes[b.left].value;
        int mid = (low + high) / 2;
        if (k <= count) { u = a.left; w = b.left; high = mid; }
        else { k -= (int)count; u = a.right; w = b.right; low = mid + 1; }
        visited++;
    }
    return (Answer){p->values[low], visited};
}
static int grid_add(Grid *grid, int row, int col, int64_t value) {
    int visited = 0;
    for (int y = row + 1; y <= grid->height; y += y & -y) {
        for (int x = col + 1; x <= grid->width; x += x & -x) { grid->tree[y][x] += value; visited++; }
    }
    return visited;
}
static Answer grid_prefix(const Grid *grid, int row, int col) {
    Answer answer = {0};
    for (int y = row; y > 0; y -= y & -y) {
        for (int x = col; x > 0; x -= x & -x) { answer.value += grid->tree[y][x]; answer.visited++; }
    }
    return answer;
}

static void build_array(Lab *lab, Kind kind, int parameter, bool output) {
    lab->built[kind] = true;
    int64_t total = 0;
    if (kind == SEG) {
        lab->seg.op = (Operation)parameter;
        segment_build(lab, 1);
        if (output) printf("SEG BUILD %s nodes=%d maxnode=%d root=%" PRId64 "\n",
            op_names[parameter], 2 * lab->n - 1, lab->max_node, lab->seg.values[1]);
    } else if (kind == LAZY) {
        lazy_build(lab, 1);
        Aggregate root = lab->lazy.nodes[1].value;
        if (output) printf("LAZY BUILD nodes=%d sum=%" PRId64 " min=%" PRId64 " max=%" PRId64 "\n",
            2 * lab->n - 1, root.sum, root.min, root.max);
    } else if (kind == FEN) {
        memset(&lab->fen, 0, sizeof(lab->fen));
        memcpy(lab->fen.values, lab->values, lab->n * sizeof(int64_t));
        for (int i = 0; i < lab->n; i++) { fen_add(lab->fen.tree, lab->n, i + 1, lab->values[i]); total += lab->values[i]; }
        if (output) printf("FEN BUILD n=%d total=%" PRId64 "\n", lab->n, total);
    } else if (kind == RFEN) {
        memset(&lab->rfen, 0, sizeof(lab->rfen));
        for (int i = 0; i < lab->n; i++) {
            int64_t difference = lab->values[i] - (i ? lab->values[i - 1] : 0);
            fen_add(lab->rfen.first, lab->n, i + 1, difference);
            fen_add(lab->rfen.second, lab->n, i + 1, i * difference);
            total += lab->values[i];
        }
        if (output) printf("RFEN BUILD n=%d total=%" PRId64 "\n", lab->n, total);
    } else if (kind == SPARSE) {
        sparse_build(lab);
        if (output) printf("SPARSE BUILD levels=%d entries=%d\n", lab->sparse.levels, lab->sparse.entries);
    } else if (kind == SQRT) {
        Sqrt *s = &lab->sqrt;
        memset(s, 0, sizeof(*s));
        s->block = parameter;
        s->blocks = (lab->n + parameter - 1) / parameter;
        memcpy(s->values, lab->values, lab->n * sizeof(int64_t));
        for (int i = 0; i < lab->n; i++) s->sums[i / parameter] += lab->values[i];
        if (output) printf("SQRT BUILD block=%d blocks=%d\n", parameter, s->blocks);
    } else if (kind == PERSIST) {
        persist_build(lab);
        if (output) printf("PERSIST BUILD nodes=%d distinct=%d valuenodes=%d\n",
            lab->persist.position.size, lab->persist.distinct, lab->persist.value.size);
    }
}
static bool query_items(Lab *lab, Kind kind, int version, int left, int right, const Reference *expected, char *out) {
    if (kind == SEG) {
        int visited = 0;
        int64_t answer = segment_query(lab, 1, left, right, &visited);
        snprintf(out, 256, "%s=%" PRId64 " visited=%d", value_names[lab->seg.op], answer, visited);
        if (!expected) return true;
        int64_t values[] = {expected->values.sum, expected->values.min, expected->values.max, expected->gcd};
        return answer == values[lab->seg.op];
    }
    if (kind == LAZY) {
        Counts counts = {0};
        Aggregate answer = lazy_query(lab, 1, left, right, &counts);
        snprintf(out, 256, "sum=%" PRId64 " min=%" PRId64 " max=%" PRId64 " visited=%d pushes=%d",
            answer.sum, answer.min, answer.max, counts.visited, counts.pushes);
        return !expected || (answer.sum == expected->values.sum && answer.min == expected->values.min && answer.max == expected->values.max);
    }
    if (kind == SPARSE) {
        SparseAnswer answer = sparse_query(&lab->sparse, left, right);
        int64_t low = lab->sparse.values[answer.min], high = lab->sparse.values[answer.max];
        snprintf(out, 256, "min=%" PRId64 " minpos=%d max=%" PRId64 " maxpos=%d level=%d", low, answer.min, high, answer.max, answer.level);
        return !expected || (low == expected->values.min && high == expected->values.max);
    }
    if (kind == SQRT) {
        SqrtAnswer answer = sqrt_process(&lab->sqrt, left, right, 0, false);
        snprintf(out, 256, "sum=%" PRId64 " whole=%d cells=%d", answer.sum, answer.whole, answer.cells);
        return !expected || answer.sum == expected->values.sum;
    }
    Answer answer = {0};
    if (kind == FEN) answer = fen_range(lab->fen.tree, left, right);
    else if (kind == RFEN) answer = rfen_range(&lab->rfen, left, right);
    else answer.value = persistent_query(&lab->persist.position, lab->persist.roots[version], 0, lab->n - 1, left, right, &answer.visited);
    snprintf(out, 256, "sum=%" PRId64 " visited=%d", answer.value, answer.visited);
    return !expected || answer.value == expected->values.sum;
}
static bool check_index(const Lab *lab, int index) {
    if (index >= 0 && index < lab->n) return true;
    printf("ERROR BAD INDEX %d\n", index);
    return false;
}
static bool check_range(const Lab *lab, int left, int right) {
    if (!check_index(lab, left) || !check_index(lab, right)) return false;
    if (left <= right) return true;
    printf("ERROR BAD RANGE %d %d\n", left, right);
    return false;
}
static bool check_version(const Lab *lab, int version) {
    if (version >= 0 && version < lab->persist.versions) return true;
    printf("ERROR BAD VERSION %d\n", version);
    return false;
}
static bool check_cell(const Grid *grid, int row, int col) {
    if (row >= 0 && row < grid->height && col >= 0 && col < grid->width) return true;
    printf("ERROR BAD CELL %d %d\n", row, col);
    return false;
}
static void print_values(const char *label, const int64_t *values, int count) {
    fputs(label, stdout);
    for (int i = 0; i < count; i++) printf(" %" PRId64, values[i]);
    putchar('\n');
}
static void dump(const Lab *lab, Kind kind) {
    if (kind == SEG || kind == LAZY) {
        if (kind == SEG) printf("SEG DUMP %s nodes=%d\n", op_names[lab->seg.op], 2 * lab->n - 1);
        else printf("LAZY DUMP nodes=%d\n", 2 * lab->n - 1);
        for (int i = 1; i <= lab->max_node; i++) {
            Bounds b = lab->bounds[i];
            if (!b.present) continue;
            printf("NODE %d %d %d ", i, b.left, b.right);
            if (kind == SEG) printf("%" PRId64 "\n", lab->seg.values[i]);
            else {
                LazyNode node = lab->lazy.nodes[i];
                printf("sum=%" PRId64 " min=%" PRId64 " max=%" PRId64 " assign=", node.value.sum, node.value.min, node.value.max);
                if (b.left != b.right && node.assigned) printf("%" PRId64, node.assign); else putchar('-');
                printf(" add=%" PRId64 "\n", b.left == b.right ? INT64_C(0) : node.add);
            }
        }
    } else if (kind == FEN || kind == RFEN) {
        printf("%s DUMP n=%d\n", kind_names[kind], lab->n);
        if (kind == FEN) print_values("T", lab->fen.tree + 1, lab->n);
        else { print_values("B1", lab->rfen.first + 1, lab->n); print_values("B2", lab->rfen.second + 1, lab->n); }
    } else if (kind == SPARSE) {
        printf("SPARSE DUMP levels=%d\n", lab->sparse.levels);
        for (int level = 0; level < lab->sparse.levels; level++) {
            printf("MIN %d", level);
            for (int i = 0; i + (1 << level) <= lab->n; i++) printf(" %d", lab->sparse.min[level][i]);
            printf("\nMAX %d", level);
            for (int i = 0; i + (1 << level) <= lab->n; i++) printf(" %d", lab->sparse.max[level][i]);
            putchar('\n');
        }
    } else if (kind == SQRT) {
        const Sqrt *s = &lab->sqrt;
        printf("SQRT DUMP block=%d blocks=%d\n", s->block, s->blocks);
        for (int block = 0; block < s->blocks; block++) {
            int first = block * s->block, end = (block + 1) * s->block;
            if (end > lab->n) end = lab->n;
            printf("BLOCK %d %d %d add=%" PRId64 " sum=%" PRId64, block, first, end - 1, s->tags[block], s->sums[block]);
            for (int i = first; i < end; i++) printf(" %" PRId64, s->values[i]);
            putchar('\n');
        }
    } else if (kind == GRID) {
        printf("GRID DUMP rows=%d cols=%d\n", lab->grid.height, lab->grid.width);
        for (int row = 1; row <= lab->grid.height; row++) {
            printf("ROW %d", row);
            for (int col = 1; col <= lab->grid.width; col++) printf(" %" PRId64, lab->grid.tree[row][col]);
            putchar('\n');
        }
    }
}
static int compare_queries(const void *a, const void *b) {
    const MoQuery *x = a, *y = b;
    if (x->block != y->block) return x->block - y->block;
    if (x->right != y->right) return x->block % 2 ? y->right - x->right : x->right - y->right;
    return x->number - y->number;
}
static void mo(const Lab *lab, MoQuery *queries, int count) {
    int64_t sorted[MAX_N];
    int ranks[MAX_N], frequencies[MAX_N] = {0}, answers[100];
    MoQuery original[100];
    memcpy(original, queries, count * sizeof(*queries));
    memcpy(sorted, lab->values, lab->n * sizeof(int64_t));
    int distinct_values = unique_values(sorted, lab->n);
    for (int i = 0; i < lab->n; i++) ranks[i] = rank_of(sorted, distinct_values, lab->values[i]);
    qsort(queries, count, sizeof(*queries), compare_queries);
    int left = 0, right = -1, moves = 0, distinct = 0;
    for (int i = 0; i < count; i++) {
        MoQuery q = queries[i];
        moves += abs(q.left - left) + abs(q.right - right);
        while (left > q.left) if (frequencies[ranks[--left]]++ == 0) distinct++;
        while (right < q.right) if (frequencies[ranks[++right]]++ == 0) distinct++;
        while (left < q.left) if (--frequencies[ranks[left++]] == 0) distinct--;
        while (right > q.right) if (--frequencies[ranks[right--]] == 0) distinct--;
        answers[q.number - 1] = distinct;
    }
    printf("MO queries=%d block=%d moves=%d\nORDER", count, isqrt_value(lab->n), moves);
    for (int i = 0; i < count; i++) printf(" %d", queries[i].number);
    putchar('\n');
    for (int i = 0; i < count; i++) printf("ANSWER %d %d %d distinct=%d\n", i + 1, original[i].left, original[i].right, answers[i]);
}
static void check_all(Lab *lab, int left, int right) {
    Reference reference = {{0, lab->values[left], lab->values[left]}, 0};
    for (int i = left; i <= right; i++) {
        reference.values.sum += lab->values[i];
        reference.values.min = minimum(reference.values.min, lab->values[i]);
        reference.values.max = maximum(reference.values.max, lab->values[i]);
        reference.gcd = gcd_value(reference.gcd, lab->values[i]);
    }
    printf("CHECK %d %d sum=%" PRId64 " min=%" PRId64 " max=%" PRId64 " gcd=%" PRId64 "\n",
        left, right, reference.values.sum, reference.values.min, reference.values.max, reference.gcd);
    int ok = 0, diff = 0;
    for (Kind kind = SEG; kind < GRID; kind++) {
        if (!lab->built[kind]) continue;
        char out[256];
        int version = lab->persist.versions - 1;
        bool same = query_items(lab, kind, version, left, right, &reference, out);
        if (same) ok++; else diff++;
        printf("%s %s ", kind_names[kind], same ? "OK" : "DIFF");
        if (kind == PERSIST) printf("version=%d ", version);
        puts(out);
    }
    printf("RESULT ok=%d diff=%d\n", ok, diff);
}
static int64_t number(char **words, int index) { return strtoll(words[index], NULL, 10); }
static void execute(Lab *lab, char **words, int count) {
    const char *command = words[0];
    if (!strcmp(command, "LOAD")) {
        int removed = 0;
        for (Kind kind = SEG; kind < GRID; kind++) { removed += lab->built[kind]; lab->built[kind] = false; }
        persist_clear(&lab->persist);
        lab->n = count - 1;
        for (int i = 0; i < lab->n; i++) lab->values[i] = lab->original[i] = number(words, i + 1);
        reset_shape(lab);
        printf("LOAD n=%d removed=%d\n", lab->n, removed);
        return;
    }
    if (!strcmp(command, "RESET")) {
        memcpy(lab->values, lab->original, lab->n * sizeof(int64_t));
        int rebuilt = 0;
        for (Kind kind = SEG; kind < GRID; kind++) if (lab->built[kind]) {
            int parameter = kind == SEG ? (int)lab->seg.op : kind == SQRT ? lab->sqrt.block : 0;
            build_array(lab, kind, parameter, false);
            rebuilt++;
        }
        printf("RESET rebuilt=%d\n", rebuilt);
        return;
    }
    if (!strcmp(command, "ARRAY") || !strcmp(command, "CHECK")) {
        int left = (int)number(words, 1), right = (int)number(words, 2);
        if (!check_range(lab, left, right)) return;
        if (!strcmp(command, "CHECK")) check_all(lab, left, right);
        else {
            printf("ARRAY %d %d", left, right);
            for (int i = left; i <= right; i++) printf(" %" PRId64, lab->values[i]);
            putchar('\n');
        }
        return;
    }
    if (!strcmp(command, "MO")) {
        MoQuery queries[100];
        int total = (count - 1) / 2, block = isqrt_value(lab->n);
        for (int i = 0; i < total; i++) {
            int left = (int)number(words, 2 * i + 1), right = (int)number(words, 2 * i + 2);
            if (!check_range(lab, left, right)) return;
            queries[i] = (MoQuery){i + 1, left, right, left / block};
        }
        mo(lab, queries, total);
        return;
    }
    Kind kind = SEG;
    while (strcmp(command, kind_names[kind])) kind++;
    const char *action = words[1];
    if (!strcmp(action, "BUILD")) {
        int parameter = 0;
        if (kind == SEG) {
            while (parameter < 4 && strcmp(words[2], op_names[parameter])) parameter++;
            if (parameter == 4) { printf("ERROR BAD OP %s\n", words[2]); return; }
        } else if (kind == SQRT) {
            parameter = count == 3 ? (int)number(words, 2) : isqrt_value(lab->n);
            if (parameter > lab->n) { printf("ERROR BAD BLOCK %d\n", parameter); return; }
        } else if (kind == GRID) {
            int height = (int)number(words, 2), width = (int)number(words, 3);
            if (count - 4 != height * width) { printf("ERROR BAD COUNT %d %d\n", count - 4, height * width); return; }
            lab->grid = (Grid){.height = height, .width = width};
            int64_t total = 0;
            for (int i = 0; i < height * width; i++) {
                int64_t value = number(words, i + 4);
                grid_add(&lab->grid, i / width, i % width, value);
                total += value;
            }
            lab->built[GRID] = true;
            printf("GRID BUILD rows=%d cols=%d total=%" PRId64 "\n", height, width, total);
            return;
        }
        build_array(lab, kind, parameter, true);
        return;
    }
    if (!lab->built[kind]) { printf("ERROR NOT BUILT %s\n", command); return; }
    if (!strcmp(action, "DUMP")) { dump(lab, kind); return; }
    if (kind == GRID) {
        int row = (int)number(words, 2), col = (int)number(words, 3);
        if (!check_cell(&lab->grid, row, col)) return;
        if (!strcmp(action, "ADD")) {
            int64_t value = number(words, 4);
            int visited = grid_add(&lab->grid, row, col, value);
            printf("GRID ADD %d %d %" PRId64 " visited=%d\n", row, col, value, visited);
        } else {
            int bottom = (int)number(words, 4), right = (int)number(words, 5);
            if (!check_cell(&lab->grid, bottom, right)) return;
            if (row > bottom || col > right) { printf("ERROR BAD RECT %d %d %d %d\n", row, col, bottom, right); return; }
            Answer a = grid_prefix(&lab->grid, bottom + 1, right + 1), b = grid_prefix(&lab->grid, row, right + 1);
            Answer c = grid_prefix(&lab->grid, bottom + 1, col), d = grid_prefix(&lab->grid, row, col);
            printf("GRID SUM %d %d %d %d sum=%" PRId64 " visited=%d\n", row, col, bottom, right,
                a.value - b.value - c.value + d.value, a.visited + b.visited + c.visited + d.visited);
        }
        return;
    }
    if (kind == PERSIST) {
        Persistent *p = &lab->persist;
        if (!strcmp(action, "NODES")) {
            printf("PERSIST NODES versions=%d position=%d value=%d\n", p->versions, p->position.size, p->value.size);
            return;
        }
        if (!strcmp(action, "KTH")) {
            int left = (int)number(words, 2), right = (int)number(words, 3), k = (int)number(words, 4);
            if (!check_range(lab, left, right)) return;
            if (k < 1 || k > right - left + 1) { printf("ERROR BAD K %d\n", k); return; }
            Answer answer = persist_kth(p, left, right, k);
            printf("PERSIST KTH %d %d %d value=%" PRId64 " visited=%d\n", left, right, k, answer.value, answer.visited);
            return;
        }
        int version = (int)number(words, 2), left = (int)number(words, 3);
        if (!check_version(lab, version)) return;
        if (!strcmp(action, "SET")) {
            if (!check_index(lab, left)) return;
            int64_t value = number(words, 4);
            int old = p->position.size, next = p->versions;
            p->roots[next] = persistent_set(&p->position, p->roots[version], 0, lab->n - 1, left, value, false);
            p->versions++;
            printf("PERSIST SET %d %d %" PRId64 " version=%d created=%d\n", version, left, value, next, p->position.size - old);
        } else {
            int right = (int)number(words, 4);
            if (!check_range(lab, left, right)) return;
            char out[256];
            query_items(lab, PERSIST, version, left, right, NULL, out);
            printf("PERSIST QUERY %d %d %d %s\n", version, left, right, out);
        }
        return;
    }
    if (kind == FEN && !strcmp(action, "LOWER")) {
        for (int i = 0; i < lab->n; i++) if (lab->fen.values[i] < 0) { printf("ERROR NEGATIVE %d\n", i); return; }
        int64_t k = number(words, 2), rest = k;
        int step = 1, position = 0, visited = 0;
        while (2 * step <= lab->n) step *= 2;
        for (; step > 0; step /= 2) if (position + step <= lab->n) {
            visited++;
            if (lab->fen.tree[position + step] < rest) { rest -= lab->fen.tree[position + step]; position += step; }
        }
        printf("FEN LOWER %" PRId64 " index=", k);
        if (position == lab->n) fputs("none", stdout); else printf("%d", position);
        printf(" visited=%d\n", visited);
        return;
    }
    int left = (int)number(words, 2);
    if (kind == SEG && !strcmp(action, "UPDATE")) {
        if (!check_index(lab, left)) return;
        int64_t value = number(words, 3);
        lab->values[left] = value;
        int visited = segment_update(lab, 1, left, value);
        printf("SEG UPDATE %d %" PRId64 " root=%" PRId64 " visited=%d\n", left, value, lab->seg.values[1], visited);
        return;
    }
    if (kind == FEN && (!strcmp(action, "ADD") || !strcmp(action, "PREFIX"))) {
        if (!check_index(lab, left)) return;
        if (!strcmp(action, "ADD")) {
            int64_t value = number(words, 3);
            lab->values[left] += value;
            lab->fen.values[left] += value;
            int visited = fen_add(lab->fen.tree, lab->n, left + 1, value);
            printf("FEN ADD %d %" PRId64 " visited=%d\n", left, value, visited);
        } else {
            Answer answer = fen_prefix(lab->fen.tree, left + 1);
            printf("FEN PREFIX %d sum=%" PRId64 " visited=%d\n", left, answer.value, answer.visited);
        }
        return;
    }
    int right = (int)number(words, 3);
    if (!check_range(lab, left, right)) return;
    if (!strcmp(action, "ADD") || !strcmp(action, "ASSIGN")) {
        int64_t value = number(words, 4);
        bool assign = !strcmp(action, "ASSIGN");
        for (int i = left; i <= right; i++) lab->values[i] = assign ? value : lab->values[i] + value;
        if (kind == LAZY) {
            Counts counts = {0};
            lazy_update(lab, 1, left, right, value, assign, &counts);
            printf("LAZY %s %d %d %" PRId64 " visited=%d covered=%d pushes=%d\n", action, left, right, value, counts.visited, counts.covered, counts.pushes);
        } else if (kind == RFEN) {
            int visited = fen_add(lab->rfen.first, lab->n, left + 1, value);
            visited += fen_add(lab->rfen.first, lab->n, right + 2, -value);
            visited += fen_add(lab->rfen.second, lab->n, left + 1, value * left);
            visited += fen_add(lab->rfen.second, lab->n, right + 2, -value * (right + 1));
            printf("RFEN ADD %d %d %" PRId64 " visited=%d\n", left, right, value, visited);
        } else {
            SqrtAnswer answer = sqrt_process(&lab->sqrt, left, right, value, true);
            printf("SQRT ADD %d %d %" PRId64 " whole=%d cells=%d\n", left, right, value, answer.whole, answer.cells);
        }
    } else {
        char out[256];
        query_items(lab, kind, 0, left, right, NULL, out);
        printf("%s %s %d %d %s\n", command, action, left, right, out);
    }
}
static int tokenize(char *line, char **words) {
    int count = 0;
    for (char *word = strtok(line, " \r\n"); word; word = strtok(NULL, " \r\n")) words[count++] = word;
    return count;
}
int main(void) {
    static Lab lab;
    char line[30002], *words[MAX_N + 2];
    if (!fgets(line, sizeof(line), stdin)) return 0;
    lab.n = atoi(line);
    if (!fgets(line, sizeof(line), stdin)) return 0;
    tokenize(line, words);
    for (int i = 0; i < lab.n; i++) lab.values[i] = lab.original[i] = number(words, i);
    reset_shape(&lab);
    if (!fgets(line, sizeof(line), stdin)) return 0;
    int commands = atoi(line);
    for (int i = 0; i < commands; i++) {
        if (!fgets(line, sizeof(line), stdin)) break;
        int count = tokenize(line, words);
        execute(&lab, words, count);
    }
    persist_clear(&lab.persist);
    return 0;
}
