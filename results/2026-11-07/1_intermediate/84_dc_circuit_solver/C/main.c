#include <stdbool.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <setjmp.h>
#define MAX_ELEMENTS 40
#define MAX_NODES 21
#define MAX_UNKNOWNS 60
typedef struct {
    long long numerator, denominator;
} Rational;
typedef struct {
    Rational cells[MAX_UNKNOWNS][MAX_UNKNOWNS];
} Matrix;
static const Rational ZERO = {0, 1}, ONE = {1, 1};

static long long absolute(long long x) {
    return x < 0 ? -x : x;
}

static Rational rational(long long numerator, long long denominator) {
    if (denominator < 0) {
        numerator = -numerator;
        denominator = -denominator;
    }
    long long a = absolute(numerator), b = denominator;
    while (b) {
        long long next = a % b;
        a = b;
        b = next;
    }
    return (Rational){numerator / a, denominator / a};
}

static Rational add(Rational a, Rational b) {
    return rational(a.numerator * b.denominator + b.numerator * a.denominator, a.denominator * b.denominator);
}

static Rational negate(Rational a) {
    return (Rational){-a.numerator, a.denominator};
}

static Rational subtract(Rational a, Rational b) {
    return add(a, negate(b));
}

static Rational multiply(Rational a, Rational b) {
    return rational(a.numerator * b.numerator, a.denominator * b.denominator);
}

static Rational divide(Rational a, Rational b) {
    return rational(a.numerator * b.denominator, a.denominator * b.numerator);
}

static int compare(Rational a, Rational b) {
    long long x = a.numerator * b.denominator, y = b.numerator * a.denominator;
    return (x > y) - (x < y);
}

static void fraction(Rational q) {
    printf("%lld", q.numerator);
    if (q.denominator != 1) printf("/%lld", q.denominator);
}

static void value(Rational q) {
    fraction(q);
    long long scaled = absolute(q.numerator) * 1000000 / q.denominator;
    printf(" (%s%lld.%06lld)", q.numerator < 0 ? "-" : "", scaled / 1000000, scaled % 1000000);
}

static void output_value(const char *label, Rational q) {
    printf("%s = ", label);
    value(q);
    putchar('\n');
}
static jmp_buf line_error;
static int line_number;

static void fail(const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    printf("error: line %d: ", line_number);
    vprintf(pattern, args);
    putchar('\n');
    va_end(args);
    longjmp(line_error, 1);
}

static bool equal(const char *a, const char *b) {
    return strcmp(a, b) == 0;
}

static bool digits(const char *text) {
    if (!*text) return false;
    for (; *text; text++) if (*text < '0' || *text > '9') return false;
    return true;
}

static bool ends(const char *text, const char *suffix) {
    size_t length = strlen(text), count = strlen(suffix);
    return length >= count && !strcmp(text + length - count, suffix);
}

static Rational number(const char *original) {
    char text[101];
    strcpy(text, original);
    Rational multiplier = ONE;
    size_t length = strlen(text);
    if (ends(text, "meg")) {
        text[length - 3] = '\0';
        multiplier = rational(1000000, 1);
    } else if (ends(text, "k")) {
        text[length - 1] = '\0';
        multiplier = rational(1000, 1);
    } else if (ends(text, "m")) {
        text[length - 1] = '\0';
        multiplier = rational(1, 1000);
    } else if (ends(text, "u")) {
        text[length - 1] = '\0';
        multiplier = rational(1, 1000000);
    }
    char *mantissa = text;
    bool negative = *mantissa == '-';
    if (negative) mantissa++;
    Rational result = ZERO;
    bool valid = false;
    if (digits(mantissa)) {
        result = rational(strtoll(mantissa, NULL, 10), 1);
        valid = true;
    } else {
        char *separator = strpbrk(mantissa, "./");
        if (separator) {
            char kind = *separator;
            *separator = '\0';
            const char *tail = separator + 1;
            if (digits(mantissa) && digits(tail)) {
                long long left = strtoll(mantissa, NULL, 10), right = strtoll(tail, NULL, 10);
                if (kind == '/') {
                    if (right) {
                        result = rational(left, right);
                        valid = true;
                    }
                } else {
                    long long denominator = 1;
                    for (const char *p = tail; *p; p++) denominator *= 10;
                    result = rational(left * denominator + right, denominator);
                    valid = true;
                }
            }
        }
    }
    if (!valid) fail("invalid value %s", original);
    result = multiply(result, multiplier);
    return negative ? negate(result) : result;
}

static bool valid_node(const char *name) {
    if (equal(name, "0")) return true;
    if (!*name || strlen(name) > 8 || *name < 'a' || *name > 'z') return false;
    for (const char *p = name; *p; p++) if (!(*p >= 'a' && *p <= 'z') && !(*p >= '0' && *p <= '9')) return false;
    return true;
}
typedef struct {
    char name[9], n1[9], n2[9], c1[9], c2[9], reference[9];
    char kind;
    Rational value;
} Element;
static Element elements[MAX_ELEMENTS];
static int element_count;

static bool voltage_type(const Element *e) {
    return e->kind == 'V' || e->kind == 'E' || e->kind == 'H';
}

static bool independent(const Element *e) {
    return e->kind == 'V' || e->kind == 'I';
}

static int find_element(const char *name) {
    for (int i = 0; i < element_count; i++) if (equal(elements[i].name, name)) return i;
    return -1;
}

static int get_element(const char *name) {
    int index = find_element(name);
    if (index < 0) fail("unknown element %s", name);
    return index;
}
typedef struct {
    char names[MAX_NODES][9];
    int count;
} Nodes;

static void add_node(Nodes *nodes, const char *name) {
    for (int i = 0; i < nodes->count; i++) if (equal(nodes->names[i], name)) return;
    strcpy(nodes->names[nodes->count++], name);
}

static int node_compare(const void *a, const void *b) {
    return strcmp(a, b);
}

static Nodes nodes(bool include_ground, bool force_ground) {
    Nodes result = {0};
    if (force_ground) add_node(&result, "0");
    for (int i = 0; i < element_count; i++) {
        Element *e = &elements[i];
        add_node(&result, e->n1);
        add_node(&result, e->n2);
        if (*e->c1) {
            add_node(&result, e->c1);
            add_node(&result, e->c2);
        }
    }
    if (!include_ground) for (int i = 0; i < result.count; i++) if (equal(result.names[i], "0")) {
        memmove(result.names + i, result.names + i + 1, (size_t)(result.count - i - 1) * sizeof result.names[0]);
        result.count--;
        break;
    }
    qsort(result.names, (size_t)result.count, sizeof result.names[0], node_compare);
    return result;
}

static int node_index(const Nodes *nodes, const char *name) {
    for (int i = 0; i < nodes->count; i++) if (equal(nodes->names[i], name)) return i;
    return -1;
}

static void check_node(const char *name) {
    if (equal(name, "0")) return;
    Nodes all = nodes(false, false);
    if (node_index(&all, name) < 0) fail("unknown node %s", name);
}

static int root(int *parents, int i) {
    while (parents[i] != i) {
        parents[i] = parents[parents[i]];
        i = parents[i];
    }
    return i;
}

static bool join(int *parents, int a, int b) {
    a = root(parents, a);
    b = root(parents, b);
    if (a == b) return false;
    if (a < b) parents[b] = a;
    else parents[a] = b;
    return true;
}

static void reached(bool graph[MAX_NODES][MAX_NODES], int count, int start, bool *result) {
    result[start] = true;
    bool changed;
    do {
        changed = false;
        for (int i = 0; i < count; i++) if (result[i]) for (int j = 0; j < count; j++) if (graph[i][j] && !result[j]) {
            result[j] = true;
            changed = true;
        }
    }
    while (changed);
}

static void floating(const Nodes *all, bool *result) {
    bool graph[MAX_NODES][MAX_NODES] = {
        {false}
    };
    for (int i = 0; i < element_count; i++) if (elements[i].kind == 'R' || voltage_type(&elements[i])) {
        int a = node_index(all, elements[i].n1), b = node_index(all, elements[i].n2);
        graph[a][b] = graph[b][a] = true;
    }
    reached(graph, all->count, node_index(all, "0"), result);
}

static int source_loops(const Nodes *all, int *result) {
    int parents[MAX_NODES], count = 0;
    for (int i = 0; i < all->count; i++) parents[i] = i;
    for (int i = 0; i < element_count; i++) if (voltage_type(&elements[i]) && !join(parents, node_index(all, elements[i].n1), node_index(all, elements[i].n2))) result[count++] = i;
    return count;
}

static void structure(void) {
    Nodes actual = nodes(false, false);
    if (!actual.count) fail("no nodes");
    Nodes all = nodes(true, true);
    bool connected[MAX_NODES] = {false};
    floating(&all, connected);
    for (int i = 0; i < all.count; i++) if (!connected[i] && !equal(all.names[i], "0")) fail("floating node %s", all.names[i]);
    int loops[MAX_ELEMENTS];
    if (source_loops(&all, loops)) fail("voltage source loop at %s", elements[loops[0]].name);
}

static void zero_column(Rational *column, int count) {
    for (int i = 0; i < count; i++) column[i] = ZERO;
}

static void zero_matrix(Matrix *matrix, int count) {
    for (int i = 0; i < count; i++) zero_column(matrix->cells[i], count);
}

static bool solve(const Matrix *matrix, const Rational *column, int count, Rational *solution) {
    Rational rows[MAX_UNKNOWNS][MAX_UNKNOWNS + 1];
    for (int i = 0; i < count; i++) {
        for (int j = 0; j < count; j++) rows[i][j] = matrix->cells[i][j];
        rows[i][count] = column[i];
    }
    for (int k = 0; k < count; k++) {
        int pivot = k;
        while (pivot < count && !rows[pivot][k].numerator) pivot++;
        if (pivot == count) return false;
        if (pivot != k) for (int j = 0; j <= count; j++) {
            Rational swap = rows[k][j];
            rows[k][j] = rows[pivot][j];
            rows[pivot][j] = swap;
        }
        Rational value = rows[k][k];
        for (int j = 0; j <= count; j++) rows[k][j] = divide(rows[k][j], value);
        for (int i = 0; i < count; i++) if (i != k && rows[i][k].numerator) {
            Rational factor = rows[i][k];
            for (int j = 0; j <= count; j++) rows[i][j] = subtract(rows[i][j], multiply(factor, rows[k][j]));
        }
    }
    for (int i = 0; i < count; i++) solution[i] = rows[i][count];
    return true;
}
typedef struct {
    Nodes nodes;
    int sources[MAX_ELEMENTS], source_count, count;
    Matrix a;
    Rational b[MAX_UNKNOWNS];
} Model;

static int model_index(const Model *m, const char *name) {
    int node = node_index(&m->nodes, name);
    if (node >= 0) return node;
    for (int i = 0; i < m->source_count; i++) if (equal(elements[m->sources[i]].name, name)) return m->nodes.count + i;
    return -1;
}

static void matrix_add(Model *m, const char *row, const char *column, Rational q) {
    int i = model_index(m, row), j = model_index(m, column);
    if (i >= 0 && j >= 0) m->a.cells[i][j] = add(m->a.cells[i][j], q);
}

static void column_add(const Model *m, Rational *column, const char *row, Rational q) {
    int i = model_index(m, row);
    if (i >= 0) column[i] = add(column[i], q);
}

static void build(Model *m, int changed, Rational replacement) {
    memset(m, 0, sizeof *m);
    m->nodes = nodes(false, false);
    for (int i = 0; i < element_count; i++) if (voltage_type(&elements[i])) m->sources[m->source_count++] = i;
    m->count = m->nodes.count + m->source_count;
    zero_matrix(&m->a, m->count);
    zero_column(m->b, m->count);
    for (int i = 0; i < element_count; i++) {
        Element *e = &elements[i];
        Rational w = i == changed ? replacement : e->value;
        switch (e->kind) {
            case 'R':
                {
                    Rational g = divide(ONE, w);
                    matrix_add(m, e->n1, e->n1, g);
                    matrix_add(m, e->n2, e->n2, g);
                    matrix_add(m, e->n1, e->n2, negate(g));
                    matrix_add(m, e->n2, e->n1, negate(g));
                    break;
                }
            case 'I':
                column_add(m, m->b, e->n1, negate(w));
                column_add(m, m->b, e->n2, w);
                break;
            case 'G':
                matrix_add(m, e->n1, e->c1, w);
                matrix_add(m, e->n2, e->c2, w);
                matrix_add(m, e->n1, e->c2, negate(w));
                matrix_add(m, e->n2, e->c1, negate(w));
                break;
            case 'F':
                matrix_add(m, e->n1, e->reference, w);
                matrix_add(m, e->n2, e->reference, negate(w));
                break;
            default:
                matrix_add(m, e->n1, e->name, ONE);
                matrix_add(m, e->name, e->n1, ONE);
                matrix_add(m, e->n2, e->name, negate(ONE));
                matrix_add(m, e->name, e->n2, negate(ONE));
                if (e->kind == 'V') column_add(m, m->b, e->name, w);
                else if (e->kind == 'E') {
                    matrix_add(m, e->name, e->c1, negate(w));
                    matrix_add(m, e->name, e->c2, w);
                } else matrix_add(m, e->name, e->reference, negate(w));
                break;
        }
    }
}

static Rational potential(const Model *m, const Rational *solution, const char *node) {
    return equal(node, "0") ? ZERO : solution[model_index(m, node)];
}

static Rational difference(const Model *m, const Rational *solution, const char *a, const char *b) {
    return subtract(potential(m, solution, a), potential(m, solution, b));
}

static Rational current(const Model *m, const Rational *solution, const Element *e) {
    switch (e->kind) {
        case 'R':
            return divide(difference(m, solution, e->n1, e->n2), e->value);
        case 'I':
            return e->value;
        case 'G':
            return multiply(e->value, difference(m, solution, e->c1, e->c2));
        case 'F':
            return multiply(e->value, solution[model_index(m, e->reference)]);
        default:
            return solution[model_index(m, e->name)];
    }
}

static void injection(const Model *m, const char *a, const char *b, Rational *solution) {
    Rational rhs[MAX_UNKNOWNS];
    zero_column(rhs, m->count);
    column_add(m, rhs, a, ONE);
    column_add(m, rhs, b, negate(ONE));
    solve(&m->a, rhs, m->count, solution);
}

static void alone(const Model *m, const Element *source, bool unit, Rational *solution) {
    Rational rhs[MAX_UNKNOWNS];
    zero_column(rhs, m->count);
    Rational q = unit ? ONE : source->value;
    if (source->kind == 'V') column_add(m, rhs, source->name, q);
    else {
        column_add(m, rhs, source->n1, negate(q));
        column_add(m, rhs, source->n2, q);
    }
    solve(&m->a, rhs, m->count, solution);
}

static void add_element(char **w, int argc) {
    const char *name = w[0];
    char kind = *name;
    if (!strchr("RVIEGFH", kind)) fail("unknown element type %s", name);
    int count = kind == 'E' || kind == 'G' ? 6 : kind == 'F' || kind == 'H' ? 5 : 4;
    if (argc != count) fail("wrong field count for %s", name);
    if (find_element(name) >= 0) fail("duplicate element %s", name);
    for (int i = 1; i <= (count == 6 ? 4 : 2); i++) if (!valid_node(w[i])) fail("invalid node %s", w[i]);
    if (kind == 'F' || kind == 'H') {
        int source = find_element(w[3]);
        if (source < 0 || elements[source].kind != 'V') fail("unknown voltage source %s", w[3]);
    }
    Rational q = number(w[count - 1]);
    if (kind == 'R' && q.numerator <= 0) fail("nonpositive resistance %s", name);
    Element e = {0};
    strcpy(e.name, name);
    e.kind = kind;
    strcpy(e.n1, w[1]);
    strcpy(e.n2, w[2]);
    if (count == 6) {
        strcpy(e.c1, w[3]);
        strcpy(e.c2, w[4]);
    } else if (count == 5) strcpy(e.reference, w[3]);
    e.value = q;
    elements[element_count++] = e;
}
typedef struct {
    const char *name;
    int arity;
} Command;
static const Command commands[] = {
    {".OP", 0},
    {".CURRENT", 1},
    {".VOLTAGE", 2},
    {".POWER", 0},
    {".KCL", 1},
    {".THEVENIN", 2},
    {".NORTON", 2},
    {".MAXPOWER", 2},
    {".TF", 2},
    {".SENS", 1},
    {".ZPARAM", 4},
    {".SUPERPOSITION", 1},
    {".SWEEP", 5},
    {".MATRIX", 0},
    {".REQ", 2},
    {".REDUCE", 2},
    {".CHECK", 0},
    {".ALTER", 2},
    {".DELETE", 1},
    {".CLEAR", 0},
    {".NODES", 0},
    {".PRINT", 0}
};

static void resistance(const char *from, const char *to) {
    Nodes all = nodes(true, true);
    int parents[MAX_NODES];
    for (int i = 0; i < all.count; i++) parents[i] = i;
    for (int i = 0; i < element_count; i++) if (elements[i].kind == 'V') join(parents, node_index(&all, elements[i].n1), node_index(&all, elements[i].n2));
    int a = root(parents, node_index(&all, from)), b = root(parents, node_index(&all, to));
    if (a == b) {
        output_value("Req", ZERO);
        return;
    }
    bool graph[MAX_NODES][MAX_NODES] = {
        {false}
    }, connected[MAX_NODES] = {false};
    for (int i = 0; i < element_count; i++) if (elements[i].kind == 'R') {
        int p = root(parents, node_index(&all, elements[i].n1)), q = root(parents, node_index(&all, elements[i].n2));
        if (p != q) graph[p][q] = graph[q][p] = true;
    }
    reached(graph, all.count, a, connected);
    if (!connected[b]) {
        puts("Req = INFINITE");
        return;
    }
    int index[MAX_NODES], count = 0;
    for (int i = 0; i < all.count; i++) index[i] = connected[i] && i != b ? count++ : -1;
    Matrix g;
    Rational rhs[MAX_UNKNOWNS], solution[MAX_UNKNOWNS];
    zero_matrix(&g, count);
    zero_column(rhs, count);
    rhs[index[a]] = ONE;
    for (int i = 0; i < element_count; i++) if (elements[i].kind == 'R') {
        int p = root(parents, node_index(&all, elements[i].n1)), q = root(parents, node_index(&all, elements[i].n2));
        if (p == q || !connected[p]) continue;
        Rational value = divide(ONE, elements[i].value);
        p = index[p];
        q = index[q];
        if (p >= 0) g.cells[p][p] = add(g.cells[p][p], value);
        if (q >= 0) g.cells[q][q] = add(g.cells[q][q], value);
        if (p >= 0 && q >= 0) {
            g.cells[p][q] = subtract(g.cells[p][q], value);
            g.cells[q][p] = subtract(g.cells[q][p], value);
        }
    }
    solve(&g, rhs, count, solution);
    output_value("Req", solution[index[a]]);
}

static void remove_resistor(Element *list, int *count, int index) {
    memmove(list + index, list + index + 1, (size_t)(*count - index - 1) * sizeof(Element));
    (*count)--;
}

static void reduce(const char *from, const char *to) {
    if (equal(from, to)) {
        output_value("Req", ZERO);
        return;
    }
    Nodes all = nodes(true, true);
    bool graph[MAX_NODES][MAX_NODES] = {
        {false}
    }, connected[MAX_NODES] = {false};
    for (int i = 0; i < element_count; i++) if (elements[i].kind == 'R') {
        int a = node_index(&all, elements[i].n1), b = node_index(&all, elements[i].n2);
        graph[a][b] = graph[b][a] = true;
    }
    reached(graph, all.count, node_index(&all, from), connected);
    if (!connected[node_index(&all, to)]) {
        puts("Req = INFINITE");
        return;
    }
    Element list[MAX_ELEMENTS];
    int count = 0, sequence = 0;
    for (int i = 0; i < element_count; i++) if (elements[i].kind == 'R' && connected[node_index(&all, elements[i].n1)]) list[count++] = elements[i];
    while (true) {
        int removed = -1;
        for (int i = 0; i < count; i++) if (equal(list[i].n1, list[i].n2)) {
            removed = i;
            break;
        }
        if (removed >= 0) {
            printf("remove %s\n", list[removed].name);
            remove_resistor(list, &count, removed);
            continue;
        }
        int degrees[MAX_NODES] = {0};
        for (int i = 0; i < count; i++) {
            degrees[node_index(&all, list[i].n1)]++;
            degrees[node_index(&all, list[i].n2)]++;
        }
        int leaf = -1;
        for (int i = 0; i < all.count; i++) if (!equal(all.names[i], from) && !equal(all.names[i], to) && degrees[i] == 1) {
            leaf = i;
            break;
        }
        if (leaf >= 0) {
            for (int i = 0; i < count; i++) if (equal(list[i].n1, all.names[leaf]) || equal(list[i].n2, all.names[leaf])) {
                printf("remove %s\n", list[i].name);
                remove_resistor(list, &count, i);
                break;
            }
            continue;
        }
        int x = -1, y = -1;
        bool parallel = false;
        for (int i = 0; i < count && x < 0; i++) for (int j = i + 1; j < count; j++) if ((equal(list[i].n1, list[j].n1) && equal(list[i].n2, list[j].n2)) || (equal(list[i].n1, list[j].n2) && equal(list[i].n2, list[j].n1))) {
            x = i;
            y = j;
            parallel = true;
            break;
        }
        int middle = -1;
        if (x < 0) {
            for (int i = 0; i < all.count; i++) if (!equal(all.names[i], from) && !equal(all.names[i], to) && degrees[i] == 2) {
                middle = i;
                break;
            }
            if (middle < 0) break;
            for (int i = 0; i < count; i++) if (equal(list[i].n1, all.names[middle]) || equal(list[i].n2, all.names[middle])) {
                if (x < 0) x = i;
                else y = i;
            }
        }
        Element a = list[x], b = list[y], next = {0};
        snprintf(next.name, sizeof next.name, "#%d", ++sequence);
        next.kind = 'R';
        next.value = parallel ? divide(multiply(a.value, b.value), add(a.value, b.value)) : add(a.value, b.value);
        strcpy(next.n1, parallel ? a.n1 : equal(a.n1, all.names[middle]) ? a.n2 : a.n1);
        strcpy(next.n2, parallel ? a.n2 : equal(b.n1, all.names[middle]) ? b.n2 : b.n1);
        remove_resistor(list, &count, y);
        remove_resistor(list, &count, x);
        list[count++] = next;
        printf("%s = %s %s %s = ", next.name, a.name, parallel ? "||" : "+", b.name);
        value(next.value);
        putchar('\n');
    }
    if (count == 1) output_value("Req", list[0].value);
    else printf("not series-parallel: %d resistors remain\n", count);
}

static void command(char **w, int argc) {
    const char *c = w[0];
    int arity = -1;
    for (size_t i = 0; i < sizeof commands / sizeof commands[0]; i++) if (equal(c, commands[i].name)) arity = commands[i].arity;
    if (arity < 0) fail("unknown command %s", c);
    if (argc - 1 != arity) fail("wrong argument count for %s", c);
    if (equal(c, ".ALTER")) {
        int index = get_element(w[1]);
        Rational next = number(w[2]);
        Element *e = &elements[index];
        if (e->kind == 'R' && next.numerator <= 0) fail("nonpositive resistance %s", e->name);
        printf("altered %s: ", e->name);
        fraction(e->value);
        fputs(" -> ", stdout);
        fraction(next);
        putchar('\n');
        e->value = next;
        return;
    }
    if (equal(c, ".DELETE")) {
        int index = get_element(w[1]);
        for (int i = 0; i < element_count; i++) if (equal(elements[i].reference, w[1])) fail("%s is referenced by %s", w[1], elements[i].name);
        printf("deleted %s\n", elements[index].name);
        memmove(elements + index, elements + index + 1, (size_t)(element_count - index - 1) * sizeof(Element));
        element_count--;
        return;
    }
    if (equal(c, ".CLEAR")) {
        printf("cleared %d elements\n", element_count);
        element_count = 0;
        return;
    }
    if (equal(c, ".PRINT")) {
        if (!element_count) puts("empty netlist");
        for (int i = 0; i < element_count; i++) {
            Element *e = &elements[i];
            printf("%s %s %s", e->name, e->n1, e->n2);
            if (*e->c1) printf(" %s %s", e->c1, e->c2);
            else if (*e->reference) printf(" %s", e->reference);
            putchar(' ');
            fraction(e->value);
            putchar('\n');
        }
        return;
    }
    if (equal(c, ".NODES")) {
        Nodes all = nodes(true, false);
        if (!all.count) puts("no nodes");
        for (int n = 0; n < all.count; n++) {
            printf("%s:", all.names[n]);
            for (int i = 0; i < element_count; i++) {
                Element *e = &elements[i];
                if (equal(e->n1, all.names[n]) || equal(e->n2, all.names[n]) || equal(e->c1, all.names[n]) || equal(e->c2, all.names[n])) printf(" %s", e->name);
            }
            putchar('\n');
        }
        return;
    }
    if (equal(c, ".REQ") || equal(c, ".REDUCE")) {
        check_node(w[1]);
        check_node(w[2]);
        if (equal(c, ".REQ")) resistance(w[1], w[2]);
        else reduce(w[1], w[2]);
        return;
    }
    Model model;
    if (equal(c, ".CHECK")) {
        Nodes actual = nodes(false, false);
        if (!actual.count) {
            puts("no nodes");
            return;
        }
        bool any = false;
        for (int n = 0; n < actual.count; n++) {
            int degree = 0;
            for (int i = 0; i < element_count; i++) {
                degree += equal(elements[i].n1, actual.names[n]);
                degree += equal(elements[i].n2, actual.names[n]);
            }
            if (degree < 2) {
                printf("dangling node %s\n", actual.names[n]);
                any = true;
            }
        }
        Nodes all = nodes(true, true);
        bool connected[MAX_NODES] = {false};
        floating(&all, connected);
        for (int i = 0; i < all.count; i++) if (!connected[i] && !equal(all.names[i], "0")) {
            printf("floating node %s\n", all.names[i]);
            any = true;
        }
        int loops[MAX_ELEMENTS], count = source_loops(&all, loops);
        for (int i = 0; i < count; i++) {
            printf("voltage source loop at %s\n", elements[loops[i]].name);
            any = true;
        }
        if (!any) {
            Rational solution[MAX_UNKNOWNS];
            build(&model, -1, ZERO);
            if (!solve(&model.a, model.b, model.count, solution)) puts("singular matrix");
            else puts("ok");
        }
        return;
    }
    if (equal(c, ".SWEEP")) {
        int index = get_element(w[1]);
        Rational from = number(w[2]);
        Rational to = number(w[3]);
        Rational step = number(w[4]);
        check_node(w[5]);
        if (step.numerator <= 0) fail("invalid sweep step");
        if (compare(from, to) > 0) fail("invalid sweep range");
        Rational span = divide(subtract(to, from), step);
        long long count = span.numerator / span.denominator + 1;
        if (count > 20) fail("too many sweep points");
        if (elements[index].kind == 'R' && from.numerator <= 0) fail("nonpositive resistance %s", elements[index].name);
        structure();
        for (int k = 0; k < count; k++) {
            Rational q = add(from, multiply(step, rational(k, 1))), solution[MAX_UNKNOWNS];
            build(&model, index, q);
            bool valid = solve(&model.a, model.b, model.count, solution);
            printf("%s = ", elements[index].name);
            fraction(q);
            if (!valid) puts(": singular matrix");
            else {
                printf(": V(%s) = ", w[5]);
                value(potential(&model, solution, w[5]));
                putchar('\n');
            }
        }
        return;
    }
    int selected = -1;
    if (equal(c, ".CURRENT")) selected = get_element(w[1]);
    else if (equal(c, ".VOLTAGE") || equal(c, ".THEVENIN") || equal(c, ".NORTON") || equal(c, ".MAXPOWER")) {
        check_node(w[1]);
        check_node(w[2]);
    } else if (equal(c, ".KCL") || equal(c, ".SENS") || equal(c, ".SUPERPOSITION")) check_node(w[1]);
    else if (equal(c, ".ZPARAM")) for (int i = 1; i <= 4; i++) check_node(w[i]);
    else if (equal(c, ".TF")) {
        check_node(w[1]);
        selected = get_element(w[2]);
        if (!independent(&elements[selected])) fail("not an independent source %s", elements[selected].name);
    }
    structure();
    build(&model, -1, ZERO);
    if (equal(c, ".MATRIX")) {
        fputs("unknowns:", stdout);
        for (int i = 0; i < model.nodes.count; i++) printf(" V(%s)", model.nodes.names[i]);
        for (int i = 0; i < model.source_count; i++) printf(" I(%s)", elements[model.sources[i]].name);
        putchar('\n');
        for (int i = 0; i < model.count; i++) {
            printf("%s:", i < model.nodes.count ? model.nodes.names[i] : elements[model.sources[i - model.nodes.count]].name);
            for (int j = 0; j < model.count; j++) {
                putchar(' ');
                fraction(model.a.cells[i][j]);
            }
            fputs(" | ", stdout);
            fraction(model.b[i]);
            putchar('\n');
        }
        return;
    }
    Rational point[MAX_UNKNOWNS];
    if (!solve(&model.a, model.b, model.count, point)) fail("singular matrix");
    if (equal(c, ".OP")) {
        for (int i = 0; i < model.nodes.count; i++) {
            printf("V(%s) = ", model.nodes.names[i]);
            value(point[i]);
            putchar('\n');
        }
        for (int i = 0; i < model.source_count; i++) {
            printf("I(%s) = ", elements[model.sources[i]].name);
            value(point[model.nodes.count + i]);
            putchar('\n');
        }
    } else if (equal(c, ".CURRENT")) {
        printf("I(%s) = ", elements[selected].name);
        value(current(&model, point, &elements[selected]));
        putchar('\n');
    } else if (equal(c, ".VOLTAGE")) {
        printf("V(%s,%s) = ", w[1], w[2]);
        value(difference(&model, point, w[1], w[2]));
        putchar('\n');
    } else if (equal(c, ".POWER")) {
        Rational absorbed = ZERO, delivered = ZERO, total = ZERO;
        for (int i = 0; i < element_count; i++) {
            Element *e = &elements[i];
            Rational power = multiply(difference(&model, point, e->n1, e->n2), current(&model, point, e));
            printf("P(%s) = ", e->name);
            value(power);
            putchar('\n');
            if (power.numerator > 0) absorbed = add(absorbed, power);
            if (power.numerator < 0) delivered = subtract(delivered, power);
            total = add(total, power);
        }
        output_value("absorbed", absorbed);
        output_value("delivered", delivered);
        output_value("total", total);
    } else if (equal(c, ".KCL")) {
        Rational sum = ZERO;
        for (int i = 0; i < element_count; i++) {
            Element *e = &elements[i];
            if (equal(e->n1, w[1]) || equal(e->n2, w[1])) {
                Rational q = equal(e->n1, e->n2) ? ZERO : equal(e->n1, w[1]) ? current(&model, point, e) : negate(current(&model, point, e));
                printf("I(%s) leaving %s = ", e->name, w[1]);
                value(q);
                putchar('\n');
                sum = add(sum, q);
            }
        }
        output_value("sum", sum);
    } else if (equal(c, ".THEVENIN") || equal(c, ".NORTON") || equal(c, ".MAXPOWER")) {
        Rational voltage = difference(&model, point, w[1], w[2]), auxiliary[MAX_UNKNOWNS];
        injection(&model, w[1], w[2], auxiliary);
        Rational resistance = difference(&model, auxiliary, w[1], w[2]);
        if (equal(c, ".NORTON") && !resistance.numerator) fail("zero thevenin resistance");
        if (equal(c, ".MAXPOWER") && resistance.numerator <= 0) fail("nonpositive thevenin resistance");
        if (equal(c, ".THEVENIN")) {
            output_value("Vth", voltage);
            output_value("Rth", resistance);
        } else if (equal(c, ".NORTON")) {
            output_value("In", divide(voltage, resistance));
            output_value("Rn", resistance);
        } else {
            output_value("RL", resistance);
            output_value("Pmax", divide(multiply(voltage, voltage), multiply(rational(4, 1), resistance)));
        }
    } else if (equal(c, ".TF")) {
        Element *e = &elements[selected];
        Rational unit[MAX_UNKNOWNS], auxiliary[MAX_UNKNOWNS];
        alone(&model, e, true, unit);
        output_value("gain", potential(&model, unit, w[1]));
        if (e->kind == 'V') {
            Rational q = unit[model_index(&model, e->name)];
            if (!q.numerator) puts("input resistance = INFINITE");
            else output_value("input resistance", divide(negate(ONE), q));
        } else output_value("input resistance", difference(&model, unit, e->n2, e->n1));
        injection(&model, w[1], "0", auxiliary);
        output_value("output resistance", potential(&model, auxiliary, w[1]));
    } else if (equal(c, ".SENS")) {
        for (int i = 0; i < element_count; i++) {
            Element *e = &elements[i];
            Rational rhs[MAX_UNKNOWNS], auxiliary[MAX_UNKNOWNS];
            zero_column(rhs, model.count);
            switch (e->kind) {
                case 'R':
                    {
                        Rational q = divide(current(&model, point, e), e->value);
                        column_add(&model, rhs, e->n1, q);
                        column_add(&model, rhs, e->n2, negate(q));
                        break;
                    }
                case 'I':
                    column_add(&model, rhs, e->n1, negate(ONE));
                    column_add(&model, rhs, e->n2, ONE);
                    break;
                case 'G':
                case 'F':
                    {
                        Rational q = e->kind == 'G' ? difference(&model, point, e->c1, e->c2) : point[model_index(&model, e->reference)];
                        column_add(&model, rhs, e->n1, negate(q));
                        column_add(&model, rhs, e->n2, q);
                        break;
                    }
                case 'V':
                    column_add(&model, rhs, e->name, ONE);
                    break;
                case 'E':
                    column_add(&model, rhs, e->name, difference(&model, point, e->c1, e->c2));
                    break;
                case 'H':
                    column_add(&model, rhs, e->name, point[model_index(&model, e->reference)]);
                    break;
            }
            solve(&model.a, rhs, model.count, auxiliary);
            printf("dV(%s)/d%s = ", w[1], e->name);
            value(potential(&model, auxiliary, w[1]));
            putchar('\n');
        }
    } else if (equal(c, ".ZPARAM")) {
        Rational first[MAX_UNKNOWNS], second[MAX_UNKNOWNS];
        injection(&model, w[1], w[2], first);
        injection(&model, w[3], w[4], second);
        output_value("z11", difference(&model, first, w[1], w[2]));
        output_value("z12", difference(&model, second, w[1], w[2]));
        output_value("z21", difference(&model, first, w[3], w[4]));
        output_value("z22", difference(&model, second, w[3], w[4]));
    } else if (equal(c, ".SUPERPOSITION")) {
        Rational sum = ZERO;
        for (int i = 0; i < element_count; i++) if (independent(&elements[i])) {
            Rational auxiliary[MAX_UNKNOWNS];
            alone(&model, &elements[i], false, auxiliary);
            Rational q = potential(&model, auxiliary, w[1]);
            printf("%s: V(%s) = ", elements[i].name, w[1]);
            value(q);
            putchar('\n');
            sum = add(sum, q);
        }
        printf("total: V(%s) = ", w[1]);
        value(sum);
        putchar('\n');
    }
}
int main(void) {
    char line[102];
    while (fgets(line, sizeof line, stdin)) {
        line_number++;
        size_t length = strlen(line);
        if (length && line[length - 1] == '\n') line[--length] = '\0';
        if (length && line[length - 1] == '\r') line[--length] = '\0';
        if (equal(line, ".END")) break;
        if (*line == '*') continue;
        char *words[101];
        int count = 0;
        for (char *p = strtok(line, " "); p; p = strtok(NULL, " ")) words[count++] = p;
        if (setjmp(line_error) == 0) {
            if (*words[0] == '.') command(words, count);
            else add_element(words, count);
        }
    }
    return 0;
}
