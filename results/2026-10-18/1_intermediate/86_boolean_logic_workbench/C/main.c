#include <stdbool.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <setjmp.h>

typedef struct Allocation {
    void *pointer;
    struct Allocation *next;
} Allocation;
static Allocation *permanent, *temporary;

static void *take(Allocation **arena, size_t size) {
    Allocation *a = malloc(sizeof *a);
    void *p = calloc(1, size ? size : 1);
    if (!a || !p) exit(EXIT_FAILURE);
    *a = (Allocation){p, *arena};
    *arena = a;
    return p;
}

static void *allocate(size_t size) {
    return take(&temporary, size);
}

static void *persist(size_t size) {
    return take(&permanent, size);
}

static void clear(Allocation **arena) {
    while (*arena) {
        Allocation *next = (*arena)->next;
        free((*arena)->pointer);
        free(*arena);
        *arena = next;
    }
}

static char *part(const char *text, size_t length) {
    char *s = allocate(length + 1);
    memcpy(s, text, length);
    return s;
}

static bool equal(const char *a, const char *b) {
    return strcmp(a, b) == 0;
}

static bool lower(char c) {
    return c >= 'a' && c <= 'z';
}

static bool upper(char c) {
    return c >= 'A' && c <= 'Z';
}

static bool digit(char c) {
    return c >= '0' && c <= '9';
}

static bool listed(const char *s, const char *list) {
    size_t length = strlen(s);
    for (const char *p = list; *p;) {
        const char *end = strchr(p, ' ');
        size_t n = end ? (size_t)(end - p) : strlen(p);
        if (length == n && !memcmp(p, s, n)) return true;
        if (!end) break;
        p = end + 1;
    }
    return false;
}

static bool valid_name(const char *s) {
    if (!lower(*s) || strlen(s) > 8) return false;
    for (s++; *s; s++) if (!lower(*s) && !digit(*s)) return false;
    return true;
}

static int bits(unsigned n) {
    int count = 0;
    while (n) {
        n &= n - 1;
        count++;
    }
    return count;
}
static jmp_buf command_error;
static int generation;

static void fail(const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    fputs("error: ", stdout);
    vprintf(pattern, args);
    putchar('\n');
    va_end(args);
    longjmp(command_error, 1);
}
typedef struct {
    char *text;
    size_t length, capacity;
} Buffer;

static void append(Buffer *b, const char *text) {
    size_t n = strlen(text);
    if (b->length + n + 1 > b->capacity) {
        size_t capacity = b->capacity ? b->capacity : 64;
        while (capacity < b->length + n + 1) capacity *= 2;
        char *p = realloc(b->text, capacity);
        if (!p) exit(EXIT_FAILURE);
        b->text = p;
        b->capacity = capacity;
    }
    memcpy(b->text + b->length, text, n + 1);
    b->length += n;
}

static void append_char(Buffer *b, char c) {
    char text[2] = {c, '\0'};
    append(b, text);
}

static void append_int(Buffer *b, int n) {
    char text[32];
    snprintf(text, sizeof text, "%d", n);
    append(b, text);
}

static char *finish(Buffer *b, bool lasting) {
    char *out = lasting ? persist(b->length + 1) : allocate(b->length + 1);
    if (b->length) memcpy(out, b->text, b->length);
    free(b->text);
    return out;
}
typedef struct {
    unsigned positive, negative;
} Clause;
typedef struct {
    Clause *items;
    int count, capacity;
} Clauses;
typedef struct Node Node;
struct Node {
    char op;
    Node *left, *right, *next;
    unsigned variables;
    int id, simplify_generation, clause_generation, evaluate_generation, evaluated;
    Node *normal[2], *dual, *simplified;
    const char *printed;
    Clauses clause_cache;
};
static Node *node_buckets[16381];
static int node_count, simplify_generation, evaluate_generation;

static Node *make(char op, Node *left, Node *right) {
    unsigned long hash = (unsigned char)op;
    hash = hash * 1000003 + (unsigned long)(left ? left->id + 1 : 0);
    hash = hash * 1000003 + (unsigned long)(right ? right->id + 1 : 0);
    size_t bucket = hash % 16381;
    for (Node *n = node_buckets[bucket]; n; n = n->next) if (n->op == op && n->left == left && n->right == right) return n;
    Node *n = persist(sizeof *n);
    n->op = op;
    n->left = left;
    n->right = right;
    n->id = node_count++;
    n->variables = upper(op) ? 1u << (op - 'A') : (left ? left->variables : 0) | (right ? right->variables : 0);
    n->next = node_buckets[bucket];
    node_buckets[bucket] = n;
    return n;
}

static Node *leaf(char c) {
    return make(c, NULL, NULL);
}

static Node *negate(Node *n) {
    return make('~', n, NULL);
}

static int precedence(char op) {
    return op == '=' ? 1 : op == '>' ? 2 : op == '|' ? 3 : op == '^' ? 4 : op == '&' ? 5 : 6;
}

static const char *operator_text(char op) {
    return op == '=' ? "<->" : op == '>' ? "->" : op == '|' ? "|" : op == '^' ? "^" : "&";
}

static const char *print(Node *n) {
    if (n->printed) return n->printed;
    Buffer b = {0};
    if (!n->left) append_char(&b, n->op);
    else if (!n->right) {
        append(&b, "~");
        if (n->left->right) append(&b, "(");
        append(&b, print(n->left));
        if (n->left->right) append(&b, ")");
    } else {
        int p = precedence(n->op);
        bool left = n->left->right && (precedence(n->left->op) < p || (n->op == '>' && n->left->op == '>'));
        bool right = n->right->right && (precedence(n->right->op) < p || (n->op == n->right->op && n->op != '>'));
        if (left) append(&b, "(");
        append(&b, print(n->left));
        if (left) append(&b, ")");
        append(&b, " ");
        append(&b, operator_text(n->op));
        append(&b, " ");
        if (right) append(&b, "(");
        append(&b, print(n->right));
        if (right) append(&b, ")");
    }
    n->printed = finish(&b, true);
    return n->printed;
}

static int size(Node *n) {
    return 1 + (n->left ? size(n->left) : 0) + (n->right ? size(n->right) : 0);
}

static int depth(Node *n) {
    int a = n->left ? depth(n->left) : 0, b = n->right ? depth(n->right) : 0;
    return 1 + (a > b ? a : b);
}

static int variable_list(unsigned mask, char vars[27]) {
    int n = 0;
    for (int i = 0; i < 26; i++) if (mask & 1u << i) vars[n++] = (char)('A' + i);
    vars[n] = '\0';
    return n;
}
typedef struct {
    char *name;
    Node *node;
} Definition;
static Definition *definitions;
static int definition_count, definition_capacity;

static int find(const char *name) {
    for (int i = 0; i < definition_count; i++) if (equal(definitions[i].name, name)) return i;
    return -1;
}

static int definition_compare(const void *a, const void *b) {
    return strcmp(((const Definition *)a)->name, ((const Definition *)b)->name);
}

static void define(const char *name, Node *n) {
    int index = find(name);
    printf("%s %s = %s\n", index >= 0 ? "redefined" : "defined", name, print(n));
    if (index < 0) {
        if (definition_count == definition_capacity) {
            int next = definition_capacity ? definition_capacity * 2 : 8;
            Definition *items = persist((size_t)next * sizeof(Definition));
            if (definition_count) memcpy(items, definitions, (size_t)definition_count * sizeof(Definition));
            definitions = items;
            definition_capacity = next;
        }
        index = definition_count++;
        size_t length = strlen(name);
        definitions[index].name = persist(length + 1);
        memcpy(definitions[index].name, name, length + 1);
    }
    definitions[index].node = n;
    qsort(definitions, (size_t)definition_count, sizeof(Definition), definition_compare);
}
typedef struct {
    char kind;
    const char *text;
    int position;
} Token;
typedef struct {
    Token tokens[202];
    int count, at, end;
} Parser;

static Parser parser(const char *text, int start) {
    Parser p = {.end = start + (int)strlen(text)};
    for (size_t i = 0; text[i];) {
        char c = text[i];
        if (c == ' ') {
            i++;
            continue;
        }
        size_t first = i;
        char kind;
        if (!strncmp(text + i, "<->", 3)) {
            i += 3;
            kind = '=';
        } else if (!strncmp(text + i, "->", 2)) {
            i += 2;
            kind = '>';
        } else if (lower(c)) {
            i++;
            while (lower(text[i]) || digit(text[i])) i++;
            kind = 'n';
        } else if (upper(c) || strchr("01~&^|()", c)) {
            i++;
            kind = c;
        } else {
            fail("invalid character '%c' at %d", c, start + (int)i);
            kind = 0;
        }
        p.tokens[p.count++] = (Token){kind, part(text + first, i - first), start + (int)first};
    }
    return p;
}

static char peek(Parser *p) {
    return p->at == p->count ? '\0' : p->tokens[p->at].kind;
}

static void unexpected(Parser *p) {
    if (p->at == p->count) fail("unexpected end of formula at %d", p->end);
    Token t = p->tokens[p->at];
    fail("unexpected '%s' at %d", t.text, t.position);
}
static Node *expression(Parser *p, int level);

static Node *unary(Parser *p) {
    char c = peek(p);
    if (c == '~') {
        p->at++;
        return negate(unary(p));
    }
    if (c == '(') {
        p->at++;
        Node *n = expression(p, 1);
        if (peek(p) != ')') unexpected(p);
        p->at++;
        return n;
    }
    if (upper(c) || c == '0' || c == '1') {
        p->at++;
        return leaf(c);
    }
    if (c == 'n') {
        Token t = p->tokens[p->at++];
        int index = find(t.text);
        if (index < 0) fail("undefined name '%s' at %d", t.text, t.position);
        return definitions[index].node;
    }
    unexpected(p);
    return NULL;
}

static Node *expression(Parser *p, int level) {
    if (level == 6) return unary(p);
    Node *left = expression(p, level + 1);
    const char operators[] = "=>|^&";
    char op = operators[level - 1];
    while (peek(p) == op) {
        p->at++;
        Node *right = expression(p, level == 2 ? level : level + 1);
        left = make(op, left, right);
    }
    return left;
}

static Node *parse(const char *text, int start) {
    Parser p = parser(text, start);
    Node *n = expression(&p, 1);
    if (p.at != p.count) unexpected(&p);
    return n;
}

static Node *nnf(Node *n, bool positive) {
    if (n->normal[positive]) return n->normal[positive];
    Node *out;
    if (!n->left) out = n->op == '0' || n->op == '1' ? leaf(positive ? n->op : n->op == '0' ? '1' : '0') : positive ? n : negate(n);
    else if (n->op == '~') out = nnf(n->left, !positive);
    else if (n->op == '&' || n->op == '|') out = make(positive ? n->op : n->op == '&' ? '|' : '&', nnf(n->left, positive), nnf(n->right, positive));
    else if (n->op == '>') out = make(positive ? '|' : '&', nnf(n->left, !positive), nnf(n->right, positive));
    else {
        bool same = (n->op == '=') == positive;
        Node *a = make('&', nnf(n->left, true), nnf(n->right, same));
        Node *b = make('&', nnf(n->left, false), nnf(n->right, !same));
        out = make('|', a, b);
    }
    n->normal[positive] = out;
    return out;
}

static Node *dual(Node *n) {
    if (n->dual) return n->dual;
    Node *out;
    if (!n->left) out = n->op == '0' ? leaf('1') : n->op == '1' ? leaf('0') : n;
    else if (n->op == '~') out = negate(dual(n->left));
    else {
        Node *a = dual(n->left), *b = dual(n->right);
        out = n->op == '&' ? make('|', a, b) : n->op == '|' ? make('&', a, b) : n->op == '^' ? make('=', a, b) : n->op == '=' ? make('^', a, b) : make('&', negate(a), b);
    }
    n->dual = out;
    return out;
}

static Node *reduce_not(Node *n) {
    return n->op == '0' ? leaf('1') : n->op == '1' ? leaf('0') : n->op == '~' ? n->left : negate(n);
}

static bool complementary(Node *a, Node *b) {
    return (a->op == '~' && a->left == b) || (b->op == '~' && b->left == a);
}

static Node *simplify_binary(char op, Node *a, Node *b) {
    bool a0 = a->op == '0', a1 = a->op == '1', b0 = b->op == '0', b1 = b->op == '1';
    switch (op) {
        case '&':
            if (a0 || b0) return leaf('0');
            if (a1) return b;
            if (b1 || a == b) return a;
            if (complementary(a, b)) return leaf('0');
            break;
        case '|':
            if (a1 || b1) return leaf('1');
            if (a0) return b;
            if (b0 || a == b) return a;
            if (complementary(a, b)) return leaf('1');
            break;
        case '^':
            if (a0) return b;
            if (b0) return a;
            if (a1) return reduce_not(b);
            if (b1) return reduce_not(a);
            if (a == b) return leaf('0');
            if (complementary(a, b)) return leaf('1');
            break;
        case '>':
            if (a0 || b1) return leaf('1');
            if (a1) return b;
            if (b0) return reduce_not(a);
            if (a == b) return leaf('1');
            if (complementary(a, b)) return b;
            break;
        case '=':
            if (a1) return b;
            if (b1) return a;
            if (a0) return reduce_not(b);
            if (b0) return reduce_not(a);
            if (a == b) return leaf('1');
            if (complementary(a, b)) return leaf('0');
            break;
    }
    return make(op, a, b);
}

static Node *simplify_walk(Node *n, const int *substitutions) {
    if (n->simplify_generation == simplify_generation) return n->simplified;
    Node *out;
    if (!n->left) out = upper(n->op) && substitutions[n->op - 'A'] >= 0 ? leaf((char)('0' + substitutions[n->op - 'A'])) : n;
    else if (n->op == '~') out = reduce_not(simplify_walk(n->left, substitutions));
    else {
        Node *a = simplify_walk(n->left, substitutions), *b = simplify_walk(n->right, substitutions);
        out = simplify_binary(n->op, a, b);
    }
    n->simplify_generation = simplify_generation;
    n->simplified = out;
    return out;
}

static Node *simplify(Node *n, const int *substitutions) {
    simplify_generation++;
    return simplify_walk(n, substitutions);
}

static int evaluate(Node *n, unsigned true_variables) {
    if (n->evaluate_generation == evaluate_generation) return n->evaluated;
    int out;
    if (!n->left) out = upper(n->op) ? !!(true_variables & 1u << (n->op - 'A')) : n->op - '0';
    else if (n->op == '~') out = 1 - evaluate(n->left, true_variables);
    else {
        int a = evaluate(n->left, true_variables), b = evaluate(n->right, true_variables);
        out = n->op == '&' ? a & b : n->op == '|' ? a | b : n->op == '^' ? a ^ b : n->op == '>' ? (1 - a) | b : 1 - (a ^ b);
    }
    n->evaluate_generation = evaluate_generation;
    n->evaluated = out;
    return out;
}

static int *truth(Node *f, const char *vars, int n) {
    int *table = allocate((size_t)(1 << n) * sizeof(int));
    for (int row = 0; row < 1 << n; row++) {
        unsigned mask = 0;
        for (int i = 0; i < n; i++) if (row & 1 << (n - 1 - i)) mask |= 1u << (vars[i] - 'A');
        evaluate_generation++;
        table[row] = evaluate(f, mask);
    }
    return table;
}

static char *binary(int row, int n) {
    char *s = allocate((size_t)n + 1);
    for (int i = 0; i < n; i++) s[i] = row & 1 << (n - 1 - i) ? '1' : '0';
    return s;
}

static char *opposite(const char *pattern) {
    char *out = part(pattern, strlen(pattern));
    for (char *p = out; *p; p++) if (*p != '-') *p = *p == '1' ? '0' : '1';
    return out;
}

static int pattern_compare(const char *a, const char *b) {
    while (*a) {
        int x = *a == '1' ? 0 : *a == '0' ? 1 : 2, y = *b == '1' ? 0 : *b == '0' ? 1 : 2;
        if (x != y) return x - y;
        a++;
        b++;
    }
    return 0;
}

static int pattern_pointer_compare(const void *a, const void *b) {
    return pattern_compare(*(const char *const *)a, *(const char *const *)b);
}

static int literals(const char *p) {
    int n = 0;
    for (; *p; p++) n += *p != '-';
    return n;
}

static char *term(const char *pattern, const char *vars, bool clause) {
    Buffer b = {0};
    bool first = true;
    for (int i = 0; vars[i]; i++) if (pattern[i] != '-') {
        if (!first) append(&b, clause ? " | " : " & ");
        if (pattern[i] == '0') append(&b, "~");
        append_char(&b, vars[i]);
        first = false;
    }
    if (first) append(&b, clause ? "0" : "1");
    return finish(&b, false);
}

static char *form(char **patterns, int count, const char *vars, bool clauses) {
    Buffer b = {0};
    if (!count) append(&b, clauses ? "1" : "0");
    for (int i = 0; i < count; i++) {
        if (i) append(&b, clauses ? " & " : " | ");
        bool parens = clauses && count >= 2 && literals(patterns[i]) >= 2;
        if (parens) append(&b, "(");
        append(&b, term(patterns[i], vars, clauses));
        if (parens) append(&b, ")");
    }
    return finish(&b, false);
}

static char *assignment(int row, const char *vars, int n) {
    Buffer b = {0};
    append(&b, "{");
    for (int i = 0; i < n; i++) {
        if (i) append(&b, " ");
        append_char(&b, vars[i]);
        append(&b, "=");
        append_char(&b, row & 1 << (n - 1 - i) ? '1' : '0');
    }
    append(&b, "}");
    return finish(&b, false);
}

static int *coefficients(const int *table, int rows) {
    int *out = allocate((size_t)rows * sizeof(int));
    memcpy(out, table, (size_t)rows * sizeof(int));
    for (int bit = 1; bit < rows; bit <<= 1) for (int s = 0; s < rows; s++) if (s & bit) out[s] ^= out[s ^ bit];
    return out;
}
typedef struct {
    uint64_t words[4];
} Coverage;

static void cover_set(Coverage *c, int row) {
    c->words[row / 64] |= UINT64_C(1) << (row % 64);
}

static bool cover_has(Coverage c, int row) {
    return !!(c.words[row / 64] & (UINT64_C(1) << (row % 64)));
}

static bool cover_intersects(Coverage a, Coverage b) {
    for (int i = 0; i < 4; i++) if (a.words[i] & b.words[i]) return true;
    return false;
}

static bool cover_contains(Coverage a, Coverage b) {
    for (int i = 0; i < 4; i++) if (b.words[i] & ~a.words[i]) return false;
    return true;
}

static void cover_union(Coverage *a, Coverage b) {
    for (int i = 0; i < 4; i++) a->words[i] |= b.words[i];
}
typedef struct {
    char pattern[9];
    unsigned mask, values;
    Coverage coverage;
} Implicant;
typedef struct {
    Implicant *items;
    int count, capacity;
} Implicants;

static void all_implicants(int at, int n, unsigned mask, unsigned values, char pattern[9], const bool *allowed, Implicants *out) {
    if (at == n) {
        Coverage coverage = {
            {0}
        };
        for (int row = 0; row < 1 << n; row++) if ((((unsigned)row ^ values) & mask) == 0) {
            if (!allowed[row]) return;
            cover_set(&coverage, row);
        }
        if (out->count == out->capacity) {
            int next = out->capacity ? out->capacity * 2 : 8;
            Implicant *items = allocate((size_t)next * sizeof(Implicant));
            if (out->count) memcpy(items, out->items, (size_t)out->count * sizeof(Implicant));
            out->items = items;
            out->capacity = next;
        }
        Implicant p = {.mask = mask, .values = values, .coverage = coverage};
        pattern[n] = '\0';
        memcpy(p.pattern, pattern, (size_t)n + 1);
        out->items[out->count++] = p;
        return;
    }
    unsigned bit = 1u << (n - 1 - at);
    pattern[at] = '1';
    all_implicants(at + 1, n, mask | bit, values | bit, pattern, allowed, out);
    pattern[at] = '0';
    all_implicants(at + 1, n, mask | bit, values, pattern, allowed, out);
    pattern[at] = '-';
    all_implicants(at + 1, n, mask, values, pattern, allowed, out);
}
static bool product_of_sums;

static int implicant_compare(const void *a, const void *b) {
    const char *x = (*(Implicant *const *)a)->pattern, *y = (*(Implicant *const *)b)->pattern;
    if (!product_of_sums) return pattern_compare(x, y);
    for (; *x; x++, y++) {
        int p = *x == '0' ? 0 : *x == '1' ? 1 : 2, q = *y == '0' ? 0 : *y == '1' ? 1 : 2;
        if (p != q) return p - q;
    }
    return 0;
}

static char **cover_patterns(Implicant **cover, int count, bool pos) {
    char **patterns = allocate((size_t)count * sizeof(char *));
    for (int i = 0; i < count; i++) patterns[i] = pos ? opposite(cover[i]->pattern) : part(cover[i]->pattern, strlen(cover[i]->pattern));
    if (count > 1) qsort(patterns, (size_t)count, sizeof(char *), pattern_pointer_compare);
    return patterns;
}

static int cover_literals(Implicant **cover, int count) {
    int total = 0;
    for (int i = 0; i < count; i++) total += bits(cover[i]->mask);
    return total;
}

static void minimize(const char *vars, int n, const int *f, const int *dc, bool pos) {
    bool allowed[256] = {false};
    Coverage on = {
        {0}
    };
    for (int row = 0; row < 1 << n; row++) {
        bool selected = (pos ? 1 - f[row] : f[row]) == 1 && (!dc || dc[row] == 0);
        if (selected) cover_set(&on, row);
        allowed[row] = selected || (dc && dc[row] == 1);
    }
    Implicants all = {0};
    char pattern[9];
    all_implicants(0, n, 0, 0, pattern, allowed, &all);
    bool *keys = allocate(65536 * sizeof(bool));
    for (int i = 0; i < all.count; i++) keys[(all.items[i].mask << 8) | all.items[i].values] = true;
    Implicant **primes = allocate((size_t)all.count * sizeof(Implicant *));
    int prime_count = 0, stages[9] = {0}, prime_stages[9] = {0};
    for (int i = 0; i < all.count; i++) {
        Implicant *p = &all.items[i];
        int stage = n - bits(p->mask);
        stages[stage]++;
        bool prime = true;
        for (unsigned bit = 1; bit < 1u << n; bit <<= 1) if ((p->mask & bit) && keys[((p->mask ^ bit) << 8) | (p->values & ~bit)]) {
            prime = false;
            break;
        }
        if (prime) {
            prime_stages[stage]++;
            if (cover_intersects(p->coverage, on)) primes[prime_count++] = p;
        }
    }
    product_of_sums = false;
    if (prime_count > 1) qsort(primes, (size_t)prime_count, sizeof(Implicant *), implicant_compare);
    bool *essential_flags = allocate((size_t)prime_count * sizeof(bool));
    for (int row = 0; row < 1 << n; row++) if (cover_has(on, row)) {
        int only = -1, count = 0;
        for (int i = 0; i < prime_count; i++) if (cover_has(primes[i]->coverage, row)) {
            only = i;
            count++;
        }
        if (count == 1) essential_flags[only] = true;
    }
    Implicant **essential = allocate((size_t)prime_count * sizeof(Implicant *)), **optional = allocate((size_t)prime_count * sizeof(Implicant *));
    int essential_count = 0, optional_count = 0;
    for (int i = 0; i < prime_count; i++) if (essential_flags[i]) essential[essential_count++] = primes[i];
    else optional[optional_count++] = primes[i];
    Implicant **candidate = allocate((size_t)prime_count * sizeof(Implicant *)), **best = allocate((size_t)prime_count * sizeof(Implicant *));
    int best_count = -1, best_literals = 0;
    product_of_sums = pos;
    for (unsigned mask = 0; mask < 1u << optional_count; mask++) {
        int count = essential_count;
        if (count) memcpy(candidate, essential, (size_t)count * sizeof(Implicant *));
        for (int i = 0; i < optional_count; i++) if (mask & 1u << i) candidate[count++] = optional[i];
        if (best_count >= 0 && count > best_count) continue;
        Coverage covered = {
            {0}
        };
        for (int i = 0; i < count; i++) cover_union(&covered, candidate[i]->coverage);
        if (!cover_contains(covered, on)) continue;
        int total = cover_literals(candidate, count);
        if (count > 1) qsort(candidate, (size_t)count, sizeof(Implicant *), implicant_compare);
        bool better = best_count < 0 || count < best_count || (count == best_count && total < best_literals);
        if (!better && count == best_count && total == best_literals) for (int i = 0; i < count; i++) {
            int c = implicant_compare(&candidate[i], &best[i]);
            if (c) {
                better = c < 0;
                break;
            }
        }
        if (better) {
            best_count = count;
            best_literals = total;
            if (count) memcpy(best, candidate, (size_t)count * sizeof(Implicant *));
        }
    }
    if (!pos) {
        for (int stage = 0; stage <= n; stage++) {
            printf("stage %d: implicants %d primes %d\n", stage, stages[stage], prime_stages[stage]);
            if (stage == n || !stages[stage + 1]) break;
        }
        fputs("primes: ", stdout);
        if (!prime_count) fputs("none", stdout);
        else for (int i = 0; i < prime_count; i++) {
            if (i) fputs(", ", stdout);
            fputs(term(primes[i]->pattern, vars, false), stdout);
        }
        putchar('\n');
        fputs("essential: ", stdout);
        if (!essential_count) fputs("none", stdout);
        else for (int i = 0; i < essential_count; i++) {
            if (i) fputs(", ", stdout);
            fputs(term(essential[i]->pattern, vars, false), stdout);
        }
        putchar('\n');
    }
    printf("minimal: %s\n", form(cover_patterns(best, best_count, pos), best_count, vars, pos));
    printf("%s %d literals %d\n", pos ? "clauses" : "terms", best_count, best_literals);
}

static bool clause_subset(Clause a, Clause b) {
    return (a.positive & b.positive) == a.positive && (a.negative & b.negative) == a.negative;
}

static bool tautological(Clause c) {
    return (c.positive & c.negative) != 0;
}

static void add_clause(Clauses *set, Clause clause) {
    if (set->count == set->capacity) {
        int next = set->capacity ? set->capacity * 2 : 8;
        Clause *items = allocate((size_t)next * sizeof(Clause));
        if (set->count) memcpy(items, set->items, (size_t)set->count * sizeof(Clause));
        set->items = items;
        set->capacity = next;
    }
    set->items[set->count++] = clause;
}

static int clause_compare(const void *a, const void *b) {
    const Clause *x = a, *y = b;
    if (x->positive != y->positive) return x->positive < y->positive ? -1 : 1;
    return (x->negative > y->negative) - (x->negative < y->negative);
}

static int clause_length_compare(const void *a, const void *b) {
    const Clause *x = a, *y = b;
    int c = bits(x->positive | x->negative) - bits(y->positive | y->negative);
    return c ? c : clause_compare(a, b);
}

static Clauses unique_clauses(Clauses set) {
    if (set.count > 1) qsort(set.items, (size_t)set.count, sizeof(Clause), clause_compare);
    int count = 0;
    for (int i = 0; i < set.count; i++) if (!tautological(set.items[i]) && (!count || clause_compare(&set.items[i], &set.items[count - 1]))) set.items[count++] = set.items[i];
    set.count = count;
    return set;
}

static Clauses tidy(Clauses set) {
    if (set.count > 1) qsort(set.items, (size_t)set.count, sizeof(Clause), clause_length_compare);
    Clauses out = {0};
    for (int i = 0; i < set.count; i++) if (!tautological(set.items[i])) {
        bool contains = false;
        for (int j = 0; j < out.count; j++) if (clause_subset(out.items[j], set.items[i])) {
            contains = true;
            break;
        }
        if (!contains) add_clause(&out, set.items[i]);
    }
    return out;
}

static Clauses clauses(Node *n) {
    if (n->clause_generation == generation) return n->clause_cache;
    Clauses out = {0};
    if (n->op == '0') add_clause(&out, (Clause){0, 0});
    else if (n->op == '1') {
    } else if (!n->left) add_clause(&out, (Clause){1u << (n->op - 'A'), 0});
    else if (n->op == '~') add_clause(&out, (Clause){0, 1u << (n->left->op - 'A')});
    else {
        Clauses a = clauses(n->left), b = clauses(n->right);
        if (n->op == '&') {
            for (int i = 0; i < a.count; i++) add_clause(&out, a.items[i]);
            for (int i = 0; i < b.count; i++) add_clause(&out, b.items[i]);
        } else for (int i = 0; i < a.count; i++) for (int j = 0; j < b.count; j++) {
            Clause c = {a.items[i].positive | b.items[j].positive, a.items[i].negative | b.items[j].negative};
            if (!tautological(c)) add_clause(&out, c);
        }
        out = tidy(out);
    }
    n->clause_generation = generation;
    n->clause_cache = out;
    return out;
}

static bool empty_clause(Clauses set) {
    for (int i = 0; i < set.count; i++) if (!(set.items[i].positive | set.items[i].negative)) return true;
    return false;
}

static char **clause_patterns(Clauses set, const char *vars, int n) {
    char **patterns = allocate((size_t)set.count * sizeof(char *));
    for (int i = 0; i < set.count; i++) {
        char *p = allocate((size_t)n + 1);
        for (int j = 0; j < n; j++) {
            unsigned bit = 1u << (vars[j] - 'A');
            p[j] = set.items[i].positive & bit ? '1' : set.items[i].negative & bit ? '0' : '-';
        }
        patterns[i] = p;
    }
    if (set.count > 1) qsort(patterns, (size_t)set.count, sizeof(char *), pattern_pointer_compare);
    return patterns;
}
typedef struct {
    int variable, low, high;
} Decision;
typedef struct {
    Decision items[255];
    int count;
} Decisions;

static int bdd(const int *table, int from, int count, int variable, Decisions *nodes) {
    if (count == 1) return table[from];
    int low = bdd(table, from, count / 2, variable + 1, nodes), high = bdd(table, from + count / 2, count / 2, variable + 1, nodes);
    if (low == high) return low;
    for (int i = 0; i < nodes->count; i++) if (nodes->items[i].variable == variable && nodes->items[i].low == low && nodes->items[i].high == high) return i + 2;
    int id = nodes->count + 2;
    nodes->items[nodes->count++] = (Decision){variable, low, high};
    return id;
}
typedef struct {
    const char *items[201];
    int count;
} Words;

static Words words(const char *text) {
    Words out = {0};
    for (const char *p = text; *p;) {
        while (*p == ' ') p++;
        if (!*p) break;
        const char *first = p;
        while (*p && *p != ' ') p++;
        out.items[out.count++] = part(first, (size_t)(p - first));
    }
    return out;
}

static int anf_pattern_compare(const void *a, const void *b) {
    const char *x = *(const char *const *)a, *y = *(const char *const *)b;
    int c = literals(x) - literals(y);
    return c ? c : pattern_compare(x, y);
}

static void command(const char *line) {
    const char *space = strchr(line, ' '), *arg = space ? space + 1 : line + strlen(line);
    const char *c = part(line, space ? (size_t)(space - line) : strlen(line));
    const char *single = "PRINT TABLE MINTERMS MAXTERMS DNF CNF NNF DUAL ANF SIMPLIFY MINIMIZE MINPOS KMAP SAT TAUT COUNT PROPS BDD CLAUSES DP";
    const char *split = "RESTRICT COFACTOR MINDC EQUIV IMPLIES";
    if (!listed(c, single) && !listed(c, split) && !listed(c, "DEF DEFSUM DEL LIST")) fail("unknown command %s", c);
    if (equal(c, "LIST") && space) fail("unexpected argument");
    if (!equal(c, "LIST") && !space) fail("missing argument");
    const char *semicolon = strchr(arg, ';');
    if (listed(c, split) && !semicolon) fail("missing ';'");
    if (equal(c, "LIST")) {
        printf("names: %d\n", definition_count);
        for (int i = 0; i < definition_count; i++) printf("%s = %s\n", definitions[i].name, print(definitions[i].node));
        return;
    }
    if (equal(c, "DEL")) {
        if (!valid_name(arg)) fail("invalid name '%s'", arg);
        int at = find(arg);
        if (at < 0) fail("undefined name '%s'", arg);
        memmove(definitions + at, definitions + at + 1, (size_t)(definition_count - at - 1) * sizeof(Definition));
        definition_count--;
        printf("deleted %s\n", arg);
        return;
    }
    if (equal(c, "DEF")) {
        const char *end = strchr(arg, ' ');
        if (!end) fail("missing argument");
        const char *name = part(arg, (size_t)(end - arg));
        if (!valid_name(name)) fail("invalid name '%s'", name);
        Node *f = parse(end + 1, (int)strlen(name) + 6);
        define(name, f);
        return;
    }
    if (equal(c, "DEFSUM")) {
        if (!semicolon) fail("missing ';'");
        Words front = words(part(arg, (size_t)(semicolon - arg))), back = words(semicolon + 1);
        if (!front.count) fail("missing argument");
        if (!valid_name(front.items[0])) fail("invalid name '%s'", front.items[0]);
        if (front.count == 1) fail("bad variable list");
        for (int i = 1; i < front.count; i++) if (strlen(front.items[i]) != 1 || !upper(*front.items[i]) || (i > 1 && strcmp(front.items[i - 1], front.items[i]) >= 0)) fail("bad variable list");
        int n = front.count - 1;
        if (n >= 9) fail("too many variables: %d", n);
        int previous = -1;
        Node *result = NULL;
        for (int i = 0; i < back.count; i++) {
            const char *word = back.items[i];
            bool valid = *word && !(*word == '0' && word[1]);
            for (const char *p = word; *p; p++) valid = valid && digit(*p);
            if (!valid) fail("bad minterm '%s'", word);
            long row = strtol(word, NULL, 10);
            if (row >= 1 << n || row <= previous) fail("bad minterm '%s'", word);
            previous = (int)row;
            Node *term_node = NULL;
            for (int j = 0; j < n; j++) {
                Node *literal = leaf(*front.items[j + 1]);
                if (!(row & 1 << (n - 1 - j))) literal = negate(literal);
                term_node = term_node ? make('&', term_node, literal) : literal;
            }
            result = result ? make('|', result, term_node) : term_node;
        }
        define(front.items[0], result ? result : leaf('0'));
        return;
    }
    int start = (int)strlen(c) + 2;
    const char *first = listed(c, split) ? part(arg, (size_t)(semicolon - arg)) : arg, *second = listed(c, split) ? semicolon + 1 : "";
    Node *f = parse(first, start), *g = NULL;
    if (listed(c, "MINDC EQUIV IMPLIES")) g = parse(second, start + (int)(semicolon - arg) + 1);
    int substitutions[26];
    for (int i = 0; i < 26; i++) substitutions[i] = -1;
    if (equal(c, "RESTRICT")) {
        Words assignments = words(second);
        if (!assignments.count) fail("missing assignment");
        for (int i = 0; i < assignments.count; i++) {
            const char *a = assignments.items[i];
            if (strlen(a) != 3 || !upper(a[0]) || a[1] != '=' || (a[2] != '0' && a[2] != '1')) fail("bad assignment '%s'", a);
            int v = a[0] - 'A';
            if (substitutions[v] >= 0) fail("duplicate variable %c", a[0]);
            substitutions[v] = a[2] - '0';
        }
        printf("restricted: %s\n", print(simplify(f, substitutions)));
        return;
    }
    if (equal(c, "COFACTOR")) {
        Words x = words(second);
        if (x.count != 1 || strlen(x.items[0]) != 1 || !upper(*x.items[0])) fail("bad variable");
        char v = *x.items[0];
        substitutions[v - 'A'] = 1;
        Node *f1 = simplify(f, substitutions);
        substitutions[v - 'A'] = 0;
        Node *f0 = simplify(f, substitutions);
        printf("cofactor %c=1: %s\n", v, print(f1));
        printf("cofactor %c=0: %s\n", v, print(f0));
        printf("difference: %s\n", print(simplify_binary('^', f1, f0)));
        return;
    }
    char vars[27];
    int n = variable_list(f->variables | (g ? g->variables : 0), vars);
    if (equal(c, "PRINT")) {
        printf("formula: %s\nvariables: ", print(f));
        if (!n) fputs("none", stdout);
        for (int i = 0; i < n; i++) {
            if (i) putchar(' ');
            putchar(vars[i]);
        }
        printf("\nsize %d depth %d\n", size(f), depth(f));
        return;
    }
    if (equal(c, "NNF")) {
        printf("nnf: %s\n", print(nnf(f, true)));
        return;
    }
    if (equal(c, "DUAL")) {
        printf("dual: %s\n", print(dual(f)));
        return;
    }
    if (equal(c, "SIMPLIFY")) {
        printf("simplified: %s\n", print(simplify(f, substitutions)));
        return;
    }
    if (equal(c, "CLAUSES") || equal(c, "DP")) {
        Clauses set = clauses(nnf(f, true));
        if (equal(c, "CLAUSES")) {
            printf("clauses: %s\n", form(clause_patterns(set, vars, n), set.count, vars, true));
            return;
        }
        printf("start: clauses %d\n", set.count);
        for (int i = 0; i < n; i++) {
            if (!set.count || empty_clause(set)) break;
            unsigned bit = 1u << (vars[i] - 'A');
            Clauses resolvents = {0}, next = {0};
            for (int p = 0; p < set.count; p++) if (set.items[p].positive & bit) for (int q = 0; q < set.count; q++) if (set.items[q].negative & bit) {
                Clause r = {(set.items[p].positive | set.items[q].positive) & ~bit, (set.items[p].negative | set.items[q].negative) & ~bit};
                if (!tautological(r)) add_clause(&resolvents, r);
            }
            resolvents = unique_clauses(resolvents);
            for (int j = 0; j < set.count; j++) if (!((set.items[j].positive | set.items[j].negative) & bit)) add_clause(&next, set.items[j]);
            for (int j = 0; j < resolvents.count; j++) add_clause(&next, resolvents.items[j]);
            set = tidy(next);
            printf("eliminate %c: resolvents %d clauses %d\n", vars[i], resolvents.count, set.count);
        }
        printf("result: %s\n", empty_clause(set) ? "unsatisfiable" : "satisfiable");
        return;
    }
    if (n >= 9) fail("too many variables: %d", n);
    int *table = truth(f, vars, n), *other = g ? truth(g, vars, n) : NULL, rows = 1 << n;
    if (listed(c, "MINIMIZE MINDC MINPOS")) {
        minimize(vars, n, table, other, equal(c, "MINPOS"));
        return;
    }
    if (equal(c, "TABLE")) {
        for (int i = 0; i < n; i++) printf("%c ", vars[i]);
        puts("| F");
        for (int r = 0; r < rows; r++) {
            for (int i = 0; i < n; i++) printf("%d ", !!(r & 1 << (n - 1 - i)));
            printf("| %d\n", table[r]);
        }
    } else if (listed(c, "MINTERMS MAXTERMS DNF CNF")) {
        bool positive = listed(c, "MINTERMS DNF");
        char **patterns = allocate((size_t)rows * sizeof(char *));
        int count = 0;
        Buffer numbers = {0};
        for (int r = 0; r < rows; r++) if (table[r] == positive) {
            if (count) append(&numbers, " ");
            append_int(&numbers, r);
            patterns[count++] = positive ? binary(r, n) : opposite(binary(r, n));
        }
        if (equal(c, "DNF") || equal(c, "CNF")) printf("%s: %s\n", positive ? "dnf" : "cnf", form(patterns, count, vars, !positive));
        else printf("%s: %s\n", positive ? "minterms" : "maxterms", count ? numbers.text : "none");
        free(numbers.text);
    } else if (equal(c, "ANF")) {
        int *coeff = coefficients(table, rows);
        char **patterns = allocate((size_t)rows * sizeof(char *));
        int count = 0;
        for (int r = 0; r < rows; r++) if (coeff[r]) {
            char *p = binary(r, n);
            for (int i = 0; i < n; i++) if (p[i] == '0') p[i] = '-';
            patterns[count++] = p;
        }
        if (count > 1) qsort(patterns, (size_t)count, sizeof(char *), anf_pattern_compare);
        fputs("anf: ", stdout);
        if (!count) fputs("0", stdout);
        for (int i = 0; i < count; i++) {
            if (i) fputs(" ^ ", stdout);
            fputs(term(patterns[i], vars, false), stdout);
        }
        putchar('\n');
    } else if (equal(c, "SAT") || equal(c, "TAUT")) {
        bool sat = equal(c, "SAT");
        int first_row = -1;
        for (int r = 0; r < rows; r++) if (table[r] == sat) {
            first_row = r;
            break;
        }
        if (first_row < 0) puts(sat ? "unsatisfiable" : "tautology");
        else printf("%s: %s\n", sat ? "satisfiable" : "not a tautology", assignment(first_row, vars, n));
    } else if (equal(c, "COUNT")) {
        int count = 0;
        for (int r = 0; r < rows; r++) count += table[r];
        printf("models: %d of %d\n", count, rows);
    } else if (equal(c, "EQUIV") || equal(c, "IMPLIES")) {
        bool equivalent = equal(c, "EQUIV");
        int first_row = -1;
        for (int r = 0; r < rows; r++) if (equivalent ? table[r] != other[r] : table[r] == 1 && other[r] == 0) {
            first_row = r;
            break;
        }
        if (first_row < 0) puts(equivalent ? "equivalent" : "implies");
        else if (equivalent) printf("not equivalent: %s f=%d g=%d\n", assignment(first_row, vars, n), table[first_row], other[first_row]);
        else printf("does not imply: %s\n", assignment(first_row, vars, n));
    } else if (equal(c, "PROPS")) {
        bool self_dual = true, monotone = true, linear = true, symmetric = true;
        int *coeff = coefficients(table, rows), weights[9];
        for (int i = 0; i <= n; i++) weights[i] = -1;
        fputs("depends: ", stdout);
        bool first_dependency = true;
        for (int i = 0; i < n; i++) {
            int bit = 1 << (n - 1 - i);
            bool depends = false;
            for (int r = 0; r < rows; r++) if (table[r] != table[r ^ bit]) {
                depends = true;
                break;
            }
            if (depends) {
                if (!first_dependency) putchar(' ');
                putchar(vars[i]);
                first_dependency = false;
            }
        }
        if (first_dependency) fputs("none", stdout);
        putchar('\n');
        for (int r = 0; r < rows; r++) {
            self_dual = self_dual && table[r] != table[rows - 1 - r];
            if (coeff[r] && bits((unsigned)r) > 1) linear = false;
            int weight = bits((unsigned)r);
            if (weights[weight] >= 0 && weights[weight] != table[r]) symmetric = false;
            weights[weight] = table[r];
            for (int bit = 1; bit < rows; bit <<= 1) if (!(r & bit) && table[r] > table[r | bit]) monotone = false;
        }
        const char *labels[] = {"zero-preserving", "one-preserving", "self-dual", "monotone", "linear", "symmetric"};
        bool values[] = {table[0] == 0, table[rows - 1] == 1, self_dual, monotone, linear, symmetric};
        for (int i = 0; i < 6; i++) printf("%s: %s\n", labels[i], values[i] ? "yes" : "no");
    } else if (equal(c, "KMAP")) {
        if (n < 2 || n > 4) fail("kmap needs 2 to 4 variables");
        int p = n / 2, q = n - p;
        for (int i = 0; i < p; i++) putchar(vars[i]);
        putchar('\\');
        for (int i = p; i < n; i++) putchar(vars[i]);
        for (int j = 0; j < 1 << q; j++) printf(" %s", binary(j ^ j / 2, q));
        putchar('\n');
        for (int i = 0; i < 1 << p; i++) {
            int row = i ^ i / 2;
            fputs(binary(row, p), stdout);
            for (int j = 0; j <= q; j++) putchar(' ');
            for (int j = 0; j < 1 << q; j++) {
                for (int k = 0; k < q; k++) putchar(' ');
                printf("%d", table[(row << q) | (j ^ j / 2)]);
            }
            putchar('\n');
        }
    } else if (equal(c, "BDD")) {
        Decisions nodes = {0};
        int root = bdd(table, 0, rows, 0, &nodes), paths[257] = {0};
        paths[1] = 1;
        printf("nodes: %d\n", nodes.count);
        for (int i = 0; i < nodes.count; i++) {
            Decision d = nodes.items[i];
            paths[i + 2] = paths[d.low] + paths[d.high];
            printf("%d = ite(%c, %d, %d)\n", i + 2, vars[d.variable], d.high, d.low);
        }
        printf("root: %d\npaths: %d\n", root, paths[root]);
    }
}

int main(void) {
    char line[202];
    if (!fgets(line, sizeof line, stdin)) return 0;
    int count = atoi(line);
    for (int i = 0; i < count; i++) {
        if (!fgets(line, sizeof line, stdin)) break;
        size_t length = strlen(line);
        if (length && line[length - 1] == '\n') line[--length] = '\0';
        if (length && line[length - 1] == '\r') line[--length] = '\0';
        generation++;
        if (setjmp(command_error) == 0) command(line);
        clear(&temporary);
    }
    clear(&permanent);
    return 0;
}
