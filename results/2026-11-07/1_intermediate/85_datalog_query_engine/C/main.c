#include <stdbool.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <setjmp.h>

#define MAX_TERMS 201
#define MAX_PREDICATES 50
#define MAX_RULES 100
#define MAX_ARITY 8
typedef struct Allocation {
    void *pointer;
    struct Allocation *next;
} Allocation;
static Allocation *permanent, *temporary, *workspace;

static void *take(Allocation **arena, size_t size) {
    Allocation *a = malloc(sizeof *a);
    void *p = calloc(1, size ? size : 1);
    if (!a || !p) exit(EXIT_FAILURE);
    *a = (Allocation){p, *arena};
    *arena = a;
    return p;
}

static void *persist(size_t size) {
    return take(&permanent, size);
}

static void *allocate(size_t size) {
    return take(&temporary, size);
}

static void *work_allocate(size_t size) {
    return take(&workspace, size);
}

static void restore_workspace(Allocation *checkpoint) {
    while (workspace != checkpoint) {
        Allocation *next = workspace->next;
        free(workspace->pointer);
        free(workspace);
        workspace = next;
    }
}

static void clear(Allocation **arena) {
    while (*arena) {
        Allocation *next = (*arena)->next;
        free((*arena)->pointer);
        free(*arena);
        *arena = next;
    }
}

static void *grow(void *old, int count, int *capacity, size_t size, bool lasting) {
    int next = *capacity ? *capacity * 2 : 8;
    void *p = lasting ? persist((size_t)next * size) : allocate((size_t)next * size);
    if (count) memcpy(p, old, (size_t)count * size);
    *capacity = next;
    return p;
}

static bool equal(const char *a, const char *b) {
    return strcmp(a, b) == 0;
}

static bool lower(char c) {
    return c >= 'a' && c <= 'z';
}

static bool digit(char c) {
    return c >= '0' && c <= '9';
}

static bool word_char(char c) {
    return lower(c) || (c >= 'A' && c <= 'Z') || digit(c) || c == '_';
}

static bool listed(const char *name, const char *list) {
    size_t length = strlen(name);
    for (const char *p = list; *p;) {
        const char *end = strchr(p, ' ');
        size_t n = end ? (size_t)(end - p) : strlen(p);
        if (length == n && !memcmp(p, name, n)) return true;
        if (!end) break;
        p = end + 1;
    }
    return false;
}
static const char *RESERVED = "not mod count sum min max retract dump why forget listing strata stats check predicates undo halt";
typedef struct Name {
    struct Name *next;
    size_t length;
    char text[];
} Name;
static Name *names[4093];

static const char *intern_part(const char *s, size_t length) {
    unsigned long hash = 5381;
    for (size_t i = 0; i < length; i++) hash = hash * 33 + (unsigned char)s[i];
    int bucket = (int)(hash % 4093);
    for (Name *n = names[bucket]; n; n = n->next) if (n->length == length && !memcmp(n->text, s, length)) return n->text;
    Name *n = persist(sizeof *n + length + 1);
    n->length = length;
    memcpy(n->text, s, length);
    n->next = names[bucket];
    names[bucket] = n;
    return n->text;
}

static const char *intern(const char *s) {
    return intern_part(s, strlen(s));
}
static jmp_buf line_error;
static int line_number;

static void fail(const char *pattern, ...) {
    printf("ERROR line %d: ", line_number);
    va_list args;
    va_start(args, pattern);
    vprintf(pattern, args);
    va_end(args);
    putchar('\n');
    longjmp(line_error, 1);
}
typedef struct {
    long long number;
    const char *symbol;
} Value;

static Value integer(long long n) {
    return (Value){n, NULL};
}

static Value symbol(const char *s) {
    return (Value){0, s};
}

static int value_compare(Value a, Value b) {
    if (!!a.symbol != !!b.symbol) return a.symbol ? 1 : -1;
    return a.symbol ? strcmp(a.symbol, b.symbol) : (a.number > b.number) - (a.number < b.number);
}

static void value_text(Value value) {
    if (!value.symbol) {
        printf("%lld", value.number);
        return;
    }
    bool plain = lower(*value.symbol) && !listed(value.symbol, RESERVED);
    for (const char *p = value.symbol; *p; p++) plain = plain && word_char(*p);
    if (!plain) putchar('"');
    fputs(value.symbol, stdout);
    if (!plain) putchar('"');
}
typedef struct {
    Value values[MAX_ARITY];
    int count;
} Tuple;

static int tuple_compare(const Tuple *a, const Tuple *b) {
    for (int i = 0; i < a->count; i++) {
        int c = value_compare(a->values[i], b->values[i]);
        if (c) return c;
    }
    return 0;
}
typedef struct {
    int variable;
    bool anonymous;
    Value value;
} Term;
typedef struct Expr Expr;
struct Expr {
    const char *op;
    Term term;
    bool leaf;
    Expr *left, *right;
};
typedef struct {
    const char *name;
    Term *terms;
    int count;
} Atom;
typedef struct {
    Atom *atom;
    bool negative;
    Expr *left, *right;
    const char *op;
} Literal;
typedef struct {
    Literal *items;
    int count;
} Body;
typedef struct {
    int number;
    Atom *head;
    Body body;
    const char **variables;
    int variable_count;
} Rule;
typedef struct {
    const char *kind, *name, *aggregate;
    long long number;
    int aggregate_variable;
    Rule *rule;
} Statement;
typedef struct {
    const char *kind, *text;
} Token;
typedef struct {
    Token tokens[202];
    int count, at;
    const char **variables;
    int variable_count;
} Parser;

static Parser parser(const char *line) {
    Parser p = {0};
    p.variables = persist(MAX_TERMS * sizeof(char *));
    size_t length = strlen(line);
    for (size_t i = 0; i < length;) {
        char c = line[i];
        if (c == ' ') {
            i++;
            continue;
        }
        if (c == '%') break;
        size_t first = i;
        const char *kind;
        if (c == '"') {
            const char *end = strchr(line + i + 1, '"');
            if (!end) fail("unterminated string");
            i = (size_t)(end - line) + 1;
            kind = "string";
        } else if (i + 1 < length && listed(intern_part(line + i, 2), ":- ?- != <= >=")) {
            i += 2;
            kind = intern_part(line + first, 2);
        } else if (strchr("(),.:=<>+-*/", c)) {
            i++;
            kind = intern_part(line + first, 1);
        } else if (word_char(c)) {
            while (i < length && word_char(line[i])) i++;
            const char *s = intern_part(line + first, i - first);
            if (lower(c)) kind = listed(s, RESERVED) ? s : "name";
            else if (c >= 'A' && c <= 'Z') kind = "variable";
            else if (equal(s, "_")) kind = "anonymous";
            else {
                bool digits = true;
                for (const char *q = s; *q; q++) digits = digits && digit(*q);
                if (!digits) fail("bad token '%s'", s);
                if (strtoll(s, NULL, 10) > 1000000000LL) fail("integer out of range '%s'", s);
                kind = "integer";
            }
        } else {
            fail("bad character '%c'", c);
            kind = "";
        }
        p.tokens[p.count++] = (Token){kind, intern_part(line + first, i - first)};
    }
    p.tokens[p.count++] = (Token){"end", ""};
    return p;
}

static bool is(Parser *p, const char *kind) {
    return equal(p->tokens[p->at].kind, kind);
}

static void syntax(Parser *p) {
    if (is(p, "end")) fail("syntax error at end of line");
    else fail("syntax error at '%s'", p->tokens[p->at].text);
}

static Token expect(Parser *p, const char *kind) {
    if (!is(p, kind)) syntax(p);
    return p->tokens[p->at++];
}

static int variable_index(Parser *p, const char *name) {
    for (int i = 0; i < p->variable_count; i++) if (equal(p->variables[i], name)) return i;
    p->variables[p->variable_count] = name;
    return p->variable_count++;
}

static Term read_term(Parser *p) {
    Token t = p->tokens[p->at];
    Term out = {.variable = -1};
    if (is(p, "name") || is(p, "string")) {
        p->at++;
        out.value = symbol(t.text);
        if (equal(t.kind, "string")) out.value = symbol(intern_part(t.text + 1, strlen(t.text) - 2));
    } else if (is(p, "integer") || is(p, "-")) {
        bool minus = is(p, "-");
        if (minus) p->at++;
        long long n = strtoll(expect(p, "integer").text, NULL, 10);
        out.value = integer(minus ? -n : n);
    } else if (is(p, "variable")) {
        p->at++;
        out.variable = variable_index(p, t.text);
    } else if (is(p, "anonymous")) {
        p->at++;
        out.anonymous = true;
    } else syntax(p);
    return out;
}

static Atom *read_atom(Parser *p) {
    const char *name = expect(p, "name").text;
    Term terms[MAX_TERMS];
    int count = 0;
    if (is(p, "(")) {
        p->at++;
        terms[count++] = read_term(p);
        while (is(p, ",")) {
            p->at++;
            terms[count++] = read_term(p);
        }
        expect(p, ")");
    }
    Atom *a = persist(sizeof *a);
    a->name = name;
    a->count = count;
    a->terms = persist((size_t)count * sizeof(Term));
    if (count) memcpy(a->terms, terms, (size_t)count * sizeof(Term));
    return a;
}
static Expr *expression(Parser *p);

static Expr *node(const char *op, Expr *left, Expr *right) {
    Expr *e = persist(sizeof *e);
    e->op = op;
    e->left = left;
    e->right = right;
    return e;
}

static Expr *factor(Parser *p) {
    if (is(p, "(")) {
        p->at++;
        Expr *e = expression(p);
        expect(p, ")");
        return node("()", e, NULL);
    }
    Expr *e = persist(sizeof *e);
    e->leaf = true;
    e->term = read_term(p);
    return e;
}

static Expr *product(Parser *p) {
    Expr *out = factor(p);
    while (is(p, "*") || is(p, "/") || is(p, "mod")) {
        const char *op = p->tokens[p->at++].text;
        out = node(op, out, factor(p));
    }
    return out;
}

static Expr *expression(Parser *p) {
    Expr *out = product(p);
    while (is(p, "+") || is(p, "-")) {
        const char *op = p->tokens[p->at++].text;
        out = node(op, out, product(p));
    }
    return out;
}

static Literal literal(Parser *p) {
    Literal out = {0};
    if (is(p, "not")) {
        p->at++;
        out.negative = true;
        out.atom = read_atom(p);
    } else if (is(p, "name") && !listed(p->tokens[p->at + 1].kind, "= != < <= > >= + - * / mod")) out.atom = read_atom(p);
    else {
        out.left = expression(p);
        if (!listed(p->tokens[p->at].kind, "= != < <= > >=")) syntax(p);
        out.op = p->tokens[p->at++].text;
        out.right = expression(p);
    }
    return out;
}

static Body read_body(Parser *p) {
    Literal items[MAX_TERMS];
    int count = 0;
    items[count++] = literal(p);
    while (is(p, ",")) {
        p->at++;
        items[count++] = literal(p);
    }
    Body body = {persist((size_t)count * sizeof(Literal)), count};
    memcpy(body.items, items, (size_t)count * sizeof(Literal));
    return body;
}

static Statement statement(Parser *p) {
    Statement s = {.kind = p->tokens[p->at].kind, .aggregate = "", .aggregate_variable = -1};
    Rule *r = persist(sizeof *r);
    s.rule = r;
    if (is(p, "name") || is(p, ":-")) {
        if (is(p, "name")) r->head = read_atom(p);
        if (is(p, ":-")) {
            p->at++;
            r->body = read_body(p);
            s.kind = "rule";
        } else {
            if (!r->head) syntax(p);
            s.kind = "fact";
        }
    } else if (is(p, "?-")) {
        p->at++;
        s.kind = "query";
        if (is(p, "count")) {
            s.aggregate = "count";
            p->at++;
        } else if (is(p, "sum") || is(p, "min") || is(p, "max")) {
            s.aggregate = p->tokens[p->at++].text;
            s.aggregate_variable = variable_index(p, expect(p, "variable").text);
            expect(p, ":");
        }
        r->body = read_body(p);
    } else {
        if (!listed(s.kind, "retract why dump forget listing strata stats check predicates undo halt")) syntax(p);
        p->at++;
        if (listed(s.kind, "retract why")) r->head = read_atom(p);
        else if (equal(s.kind, "dump")) s.name = expect(p, "name").text;
        else if (equal(s.kind, "forget")) s.number = strtoll(expect(p, "integer").text, NULL, 10);
        else if (equal(s.kind, "listing") && is(p, "name")) s.name = p->tokens[p->at++].text;
    }
    expect(p, ".");
    if (!is(p, "end")) syntax(p);
    r->variables = p->variables;
    r->variable_count = p->variable_count;
    return s;
}
typedef struct {
    Tuple **items;
    int count, capacity;
} Facts;
typedef struct {
    const char *name;
    int arity;
    Facts facts;
} Predicate;
typedef struct {
    Predicate predicates[MAX_PREDICATES];
    int predicate_count;
    Rule *rules[MAX_RULES];
    int rule_count;
} State;
typedef struct History {
    State state;
    int line;
    struct History *previous;
} History;
static State state;
static History *history;
static int next_rule = 1;

static int predicate_index(const char *name) {
    for (int i = 0; i < state.predicate_count; i++) if (equal(state.predicates[i].name, name)) return i;
    return -1;
}

static void snapshot(void) {
    History *h = persist(sizeof *h);
    h->state = state;
    h->line = line_number;
    h->previous = history;
    for (int i = 0; i < state.predicate_count; i++) {
        Facts *f = &h->state.predicates[i].facts;
        f->items = persist((size_t)f->count * sizeof(Tuple *));
        if (f->count) memcpy(f->items, state.predicates[i].facts.items, (size_t)f->count * sizeof(Tuple *));
        f->capacity = f->count;
    }
    history = h;
}

static void add_fact(Facts *facts, Tuple tuple) {
    if (facts->count == facts->capacity) facts->items = grow(facts->items, facts->count, &facts->capacity, sizeof(Tuple *), true);
    Tuple *t = persist(sizeof *t);
    *t = tuple;
    facts->items[facts->count++] = t;
}
typedef struct {
    int ids[MAX_TERMS], count;
} Variables;

static void term_variables(Term t, Variables *vars, bool unique) {
    if (t.variable < 0) return;
    if (unique) for (int i = 0; i < vars->count; i++) if (vars->ids[i] == t.variable) return;
    vars->ids[vars->count++] = t.variable;
}

static void expr_variables(Expr *e, Variables *vars, bool unique) {
    if (e->leaf) term_variables(e->term, vars, unique);
    else {
        expr_variables(e->left, vars, unique);
        if (e->right) expr_variables(e->right, vars, unique);
    }
}

static void literal_variables(Literal l, Variables *vars, bool unique) {
    if (l.atom) for (int i = 0; i < l.atom->count; i++) term_variables(l.atom->terms[i], vars, unique);
    else {
        expr_variables(l.left, vars, unique);
        expr_variables(l.right, vars, unique);
    }
}

static Variables rule_variables(const Rule *r, bool include_head, bool unique) {
    Variables out = {0};
    if (include_head && r->head) for (int i = 0; i < r->head->count; i++) term_variables(r->head->terms[i], &out, unique);
    for (int i = 0; i < r->body.count; i++) literal_variables(r->body.items[i], &out, unique);
    return out;
}

static bool expr_anonymous(Expr *e) {
    return e->leaf ? e->term.anonymous : expr_anonymous(e->left) || (e->right && expr_anonymous(e->right));
}

static void safety(const Rule *r, int aggregate) {
    if (r->head) for (int i = 0; i < r->head->count; i++) if (r->head->terms[i].anonymous) fail("anonymous variable in head");
    for (int i = 0; i < r->body.count; i++) {
        Literal l = r->body.items[i];
        if (!l.atom && (expr_anonymous(l.left) || expr_anonymous(l.right))) fail("anonymous variable in comparison");
    }
    bool bound[MAX_TERMS] = {false};
    for (int i = 0; i < r->body.count; i++) {
        Literal l = r->body.items[i];
        if (l.atom && !l.negative) for (int j = 0; j < l.atom->count; j++) if (l.atom->terms[j].variable >= 0) bound[l.atom->terms[j].variable] = true;
    }
    Variables needed = {0};
    if (r->head) for (int i = 0; i < r->head->count; i++) term_variables(r->head->terms[i], &needed, true);
    if (aggregate >= 0) needed.ids[needed.count++] = aggregate;
    for (int i = 0; i < r->body.count; i++) {
        Literal l = r->body.items[i];
        if (!l.atom || l.negative) literal_variables(l, &needed, true);
    }
    for (int i = 0; i < needed.count; i++) if (!bound[needed.ids[i]]) fail("unsafe variable %s", r->variables[needed.ids[i]]);
}
typedef struct {
    const char *names[252];
    int arities[252], count;
} ArityTable;

static void check_atom(ArityTable *table, Atom *a, bool clause) {
    int found = -1;
    for (int i = 0; i < table->count; i++) if (equal(table->names[i], a->name)) {
        found = i;
        break;
    }
    if (found < 0) {
        if (!clause) fail("unknown predicate %s", a->name);
        table->names[table->count] = a->name;
        table->arities[table->count++] = a->count;
    } else if (table->arities[found] != a->count) fail("arity mismatch for %s: expected %d, got %d", a->name, table->arities[found], a->count);
}

static ArityTable predicate_check(const Rule *r, bool clause, bool head) {
    ArityTable table = {0};
    for (int i = 0; i < state.predicate_count; i++) {
        table.names[table.count] = state.predicates[i].name;
        table.arities[table.count++] = state.predicates[i].arity;
    }
    if (head && r->head) check_atom(&table, r->head, clause);
    for (int i = 0; i < r->body.count; i++) if (r->body.items[i].atom) check_atom(&table, r->body.items[i].atom, clause);
    return table;
}

static int table_index(const ArityTable *table, const char *name) {
    for (int i = 0; i < table->count; i++) if (equal(table->names[i], name)) return i;
    return -1;
}

static bool strata(const ArityTable *table, Rule *extra, int *levels) {
    for (int i = 0; i < table->count; i++) levels[i] = 0;
    for (int pass = 0; pass < table->count; pass++) {
        bool changed = false;
        for (int ri = 0; ri < state.rule_count + !!extra; ri++) {
            Rule *r = ri < state.rule_count ? state.rules[ri] : extra;
            if (!r->head) continue;
            int h = table_index(table, r->head->name);
            for (int j = 0; j < r->body.count; j++) {
                Literal l = r->body.items[j];
                if (l.atom) {
                    int value = levels[table_index(table, l.atom->name)] + l.negative;
                    if (levels[h] < value) {
                        levels[h] = value;
                        changed = true;
                    }
                }
            }
        }
        if (!changed) return true;
        if (pass + 1 == table->count) return false;
    }
    return true;
}
typedef struct {
    Value *values;
    bool *bound;
} Environment;

static Environment empty_environment(int count) {
    return (Environment){work_allocate((size_t)count * sizeof(Value)), work_allocate((size_t)count * sizeof(bool))};
}

static Environment clone_environment(Environment source, int count) {
    Environment out = empty_environment(count);
    if (count) {
        memcpy(out.values, source.values, (size_t)count * sizeof(Value));
        memcpy(out.bound, source.bound, (size_t)count * sizeof(bool));
    }
    return out;
}

static bool match(Atom *atom, const Tuple *tuple, Environment source, Environment result, int variable_count) {
    if (variable_count) {
        memcpy(result.values, source.values, (size_t)variable_count * sizeof(Value));
        memcpy(result.bound, source.bound, (size_t)variable_count * sizeof(bool));
    }
    for (int i = 0; i < atom->count; i++) {
        Term t = atom->terms[i];
        Value value = tuple->values[i];
        if (t.anonymous) continue;
        if (t.variable < 0) {
            if (value_compare(t.value, value)) return false;
        } else if (result.bound[t.variable]) {
            if (value_compare(result.values[t.variable], value)) return false;
        } else {
            result.bound[t.variable] = true;
            result.values[t.variable] = value;
        }
    }
    return true;
}

static Tuple atom_tuple(Atom *atom, Environment env) {
    Tuple t = {.count = atom->count};
    for (int i = 0; i < atom->count; i++) t.values[i] = atom->terms[i].variable >= 0 ? env.values[atom->terms[i].variable] : atom->terms[i].value;
    return t;
}

static long long floor_divide(long long a, long long b) {
    long long q = a / b, r = a % b;
    return r && ((r < 0) != (b < 0)) ? q - 1 : q;
}

static bool evaluate(Expr *e, Environment env, Value *out) {
    if (e->leaf) {
        *out = e->term.variable >= 0 ? env.values[e->term.variable] : e->term.value;
        return true;
    }
    Value a, b;
    if (!evaluate(e->left, env, &a)) return false;
    if (equal(e->op, "()")) {
        *out = a;
        return true;
    }
    if (!evaluate(e->right, env, &b) || a.symbol || b.symbol || ((equal(e->op, "/") || equal(e->op, "mod")) && !b.number)) return false;
    long long n;
    if (equal(e->op, "+")) n = a.number + b.number;
    else if (equal(e->op, "-")) n = a.number - b.number;
    else if (equal(e->op, "*")) n = a.number * b.number;
    else if (equal(e->op, "/")) n = floor_divide(a.number, b.number);
    else n = a.number - b.number * floor_divide(a.number, b.number);
    *out = integer(n);
    return true;
}

static bool comparison(Literal l, Environment env) {
    Value a, b;
    if (!evaluate(l.left, env, &a) || !evaluate(l.right, env, &b)) return false;
    int c = value_compare(a, b);
    if (equal(l.op, "=")) return !c;
    if (equal(l.op, "!=")) return c != 0;
    if (a.symbol || b.symbol) return false;
    return equal(l.op, "<") ? c < 0 : equal(l.op, "<=") ? c <= 0 : equal(l.op, ">") ? c > 0 : c >= 0;
}
typedef struct {
    char *text;
    size_t length, capacity;
} Buffer;

static void append(Buffer *b, const char *s) {
    size_t n = strlen(s);
    if (b->length + n + 1 > b->capacity) {
        size_t capacity = b->capacity ? b->capacity : 64;
        while (capacity < b->length + n + 1) capacity *= 2;
        char *text = realloc(b->text, capacity);
        if (!text) exit(EXIT_FAILURE);
        b->text = text;
        b->capacity = capacity;
    }
    memcpy(b->text + b->length, s, n + 1);
    b->length += n;
}

static void append_value(Buffer *b, Value value) {
    if (!value.symbol) {
        char text[32];
        snprintf(text, sizeof text, "%lld", value.number);
        append(b, text);
        return;
    }
    bool plain = lower(*value.symbol) && !listed(value.symbol, RESERVED);
    for (const char *p = value.symbol; *p; p++) plain = plain && word_char(*p);
    if (!plain) append(b, "\"");
    append(b, value.symbol);
    if (!plain) append(b, "\"");
}

static void append_term(Buffer *b, Term t, const Rule *r, const Environment *env) {
    if (t.anonymous) append(b, "_");
    else if (t.variable < 0) append_value(b, t.value);
    else if (env) append_value(b, env->values[t.variable]);
    else append(b, r->variables[t.variable]);
}

static void append_expr(Buffer *b, Expr *e, const Rule *r, const Environment *env) {
    if (e->leaf) {
        append_term(b, e->term, r, env);
        return;
    }
    if (equal(e->op, "()")) {
        append(b, "(");
        append_expr(b, e->left, r, env);
        append(b, ")");
        return;
    }
    append_expr(b, e->left, r, env);
    append(b, " ");
    append(b, e->op);
    append(b, " ");
    append_expr(b, e->right, r, env);
}

static void append_atom(Buffer *b, Atom *a, const Rule *r, const Environment *env) {
    append(b, a->name);
    if (a->count) {
        append(b, "(");
        for (int i = 0; i < a->count; i++) {
            if (i) append(b, ", ");
            append_term(b, a->terms[i], r, env);
        }
        append(b, ")");
    }
}

static void append_literal(Buffer *b, Literal l, const Rule *r, const Environment *env) {
    if (l.atom) {
        if (l.negative) append(b, "not ");
        append_atom(b, l.atom, r, env);
    } else {
        append_expr(b, l.left, r, env);
        append(b, " ");
        append(b, l.op);
        append(b, " ");
        append_expr(b, l.right, r, env);
    }
}

static const char *rule_text(const Rule *r) {
    Buffer b = {0};
    if (r->head) {
        append_atom(&b, r->head, r, NULL);
        append(&b, " :- ");
    } else append(&b, ":- ");
    for (int i = 0; i < r->body.count; i++) {
        if (i) append(&b, ", ");
        append_literal(&b, r->body.items[i], r, NULL);
    }
    append(&b, ".");
    const char *out = intern(b.text);
    free(b.text);
    return out;
}

static void tuple_text(const char *predicate, const Tuple *tuple) {
    fputs(predicate, stdout);
    if (tuple->count) {
        putchar('(');
        for (int i = 0; i < tuple->count; i++) {
            if (i) fputs(", ", stdout);
            value_text(tuple->values[i]);
        }
        putchar(')');
    }
}
typedef struct {
    Tuple tuple;
    int round, rule;
} Row;
typedef struct {
    Row *items;
    int count, capacity;
} Rows;
typedef struct {
    Rows predicates[MAX_PREDICATES];
    int levels[MAX_PREDICATES], rounds[MAX_PREDICATES], added[MAX_PREDICATES], maximum;
} Model;

static int row_index(const Rows *rows, const Tuple *tuple) {
    int lo = 0, hi = rows->count;
    while (lo < hi) {
        int mid = lo + (hi - lo) / 2;
        if (tuple_compare(&rows->items[mid].tuple, tuple) < 0) lo = mid + 1;
        else hi = mid;
    }
    return lo;
}

static bool has_row(const Rows *rows, const Tuple *tuple) {
    int at = row_index(rows, tuple);
    return at < rows->count && !tuple_compare(&rows->items[at].tuple, tuple);
}

static void add_row(Rows *rows, Tuple tuple, int round, int rule) {
    int at = row_index(rows, &tuple);
    if (at < rows->count && !tuple_compare(&rows->items[at].tuple, &tuple)) {
        if (rule < rows->items[at].rule) rows->items[at].rule = rule;
        return;
    }
    if (rows->count == rows->capacity) rows->items = grow(rows->items, rows->count, &rows->capacity, sizeof(Row), false);
    memmove(rows->items + at + 1, rows->items + at, (size_t)(rows->count - at) * sizeof(Row));
    rows->items[at] = (Row){tuple, round, rule};
    rows->count++;
}

static bool filters(const Rule *r, const Model *model, Environment env, bool complete) {
    Value values[MAX_TERMS];
    bool bound[MAX_TERMS];
    Environment scratch = {values, bound};
    for (int i = 0; i < r->body.count; i++) {
        Literal l = r->body.items[i];
        if (l.atom && !l.negative) continue;
        if (!complete) {
            Variables needed = {0};
            literal_variables(l, &needed, true);
            bool ready = true;
            for (int j = 0; j < needed.count; j++) if (!env.bound[needed.ids[j]]) ready = false;
            if (!ready) continue;
        }
        if (!l.atom) {
            if (!comparison(l, env)) return false;
        } else {
            const Rows *rows = &model->predicates[predicate_index(l.atom->name)];
            for (int j = 0; j < rows->count; j++) if (match(l.atom, &rows->items[j].tuple, env, scratch, r->variable_count)) return false;
        }
    }
    return true;
}
typedef struct {
    Environment *items;
    int count, capacity;
} Environments;

static void add_environment(Environments *all, Environment env) {
    if (all->count == all->capacity) {
        int next = all->capacity ? all->capacity * 2 : 8;
        Environment *items = work_allocate((size_t)next * sizeof(Environment));
        if (all->count) memcpy(items, all->items, (size_t)all->count * sizeof(Environment));
        all->items = items;
        all->capacity = next;
    }
    all->items[all->count++] = env;
}
typedef struct EnvEntry {
    Environment env;
    struct EnvEntry *next;
} EnvEntry;

static unsigned long environment_hash(Environment env, int count) {
    unsigned long hash = 5381;
    for (int i = 0; i < count; i++) {
        hash = hash * 33 + env.bound[i];
        if (!env.bound[i]) continue;
        Value v = env.values[i];
        hash = hash * 33 + !!v.symbol;
        if (v.symbol) for (const char *p = v.symbol; *p; p++) hash = hash * 33 + (unsigned char)*p;
        else hash = hash * 33 + (unsigned long)v.number;
    }
    return hash;
}

static bool insert_environment(EnvEntry **buckets, Environment env, int count, Environments *out) {
    size_t bucket = environment_hash(env, count) % 4093;
    for (EnvEntry *e = buckets[bucket]; e; e = e->next) {
        bool same = true;
        for (int i = 0; i < count; i++) if (env.bound[i] != e->env.bound[i] || (env.bound[i] && value_compare(env.values[i], e->env.values[i]))) {
            same = false;
            break;
        }
        if (same) return false;
    }
    EnvEntry *e = work_allocate(sizeof *e);
    e->env = clone_environment(env, count);
    e->next = buckets[bucket];
    buckets[bucket] = e;
    add_environment(out, e->env);
    return true;
}
static Variables sort_variables;

static int environment_compare(const void *a, const void *b) {
    const Environment *x = a, *y = b;
    for (int i = 0; i < sort_variables.count; i++) {
        int v = sort_variables.ids[i], c = value_compare(x->values[v], y->values[v]);
        if (c) return c;
    }
    return 0;
}

typedef struct BindingEntry {
    Tuple key;
    struct BindingEntry *next;
} BindingEntry;

static unsigned long binding_hash(const Tuple *key) {
    unsigned long hash = 5381;
    for (int i = 0; i < key->count; i++) {
        Value v = key->values[i];
        hash = hash * 33 + !!v.symbol;
        if (v.symbol) for (const char *p = v.symbol; *p; p++) hash = hash * 33 + (unsigned char)*p;
        else hash = hash * 33 + (unsigned long)v.number;
    }
    return hash;
}

static void visit_solutions(const Rule *r, const Model *model, int before,
                            const int *positives, int count, int at, Environment env,
                            EnvEntry **answers, Environments *out) {
    if (!filters(r, model, env, at == count)) return;
    if (at == count) {
        insert_environment(answers, env, r->variable_count, out);
        return;
    }
    Atom *atom = r->body.items[positives[at]].atom;
    const Rows *rows = &model->predicates[predicate_index(atom->name)];
    size_t bucket_count = (size_t)rows->count * 2 + 1;
    Allocation *frame = NULL;
    BindingEntry **seen = take(&frame, bucket_count * sizeof(BindingEntry *));
    Value values[MAX_TERMS];
    bool bound[MAX_TERMS];
    Environment candidate = {values, bound};
    for (int i = 0; i < rows->count; i++) {
        if (before >= 0 && rows->items[i].round >= before) continue;
        if (!match(atom, &rows->items[i].tuple, env, candidate, r->variable_count)) continue;
        Tuple key = {0};
        for (int j = 0; j < atom->count; j++) {
            int variable = atom->terms[j].variable;
            if (variable >= 0) key.values[key.count++] = candidate.values[variable];
        }
        size_t bucket = binding_hash(&key) % bucket_count;
        bool duplicate = false;
        for (BindingEntry *entry = seen[bucket]; entry; entry = entry->next) {
            if (!tuple_compare(&entry->key, &key)) {
                duplicate = true;
                break;
            }
        }
        if (duplicate) continue;
        BindingEntry *entry = take(&frame, sizeof *entry);
        *entry = (BindingEntry){key, seen[bucket]};
        seen[bucket] = entry;
        visit_solutions(r, model, before, positives, count, at + 1, candidate, answers, out);
    }
    clear(&frame);
}

static Environments solutions(const Rule *r, const Model *model, int before) {
    int positives[MAX_TERMS], count = 0;
    for (int i = 0; i < r->body.count; i++) if (r->body.items[i].atom && !r->body.items[i].negative) positives[count++] = i;
    for (int i = 1; i < count; i++) {
        int v = positives[i], j = i;
        while (j && model->predicates[predicate_index(r->body.items[positives[j - 1]].atom->name)].count > model->predicates[predicate_index(r->body.items[v].atom->name)].count) {
            positives[j] = positives[j - 1];
            j--;
        }
        positives[j] = v;
    }
    Environments out = {0};
    EnvEntry **answers = work_allocate(4093 * sizeof(EnvEntry *));
    visit_solutions(r, model, before, positives, count, 0,
                    empty_environment(r->variable_count), answers, &out);
    sort_variables = rule_variables(r, false, true);
    if (out.count > 1) qsort(out.items, (size_t)out.count, sizeof(Environment), environment_compare);
    return out;
}

static Model *build_model(void) {
    Model *model = allocate(sizeof *model);
    Rule empty = {0};
    ArityTable table = predicate_check(&empty, true, false);
    strata(&table, NULL, model->levels);
    model->maximum = -1;
    for (int p = 0; p < state.predicate_count; p++) {
        if (model->levels[p] > model->maximum) model->maximum = model->levels[p];
        Facts facts = state.predicates[p].facts;
        for (int i = 0; i < facts.count; i++) add_row(&model->predicates[p], *facts.items[i], 0, 0);
    }
    int serial = 0;
    for (int level = 0; level <= model->maximum; level++) while (true) {
        Rows staged[MAX_PREDICATES] = {0};
        int added = 0;
        for (int i = 0; i < state.rule_count; i++) {
            Rule *r = state.rules[i];
            if (!r->head) continue;
            int p = predicate_index(r->head->name);
            if (model->levels[p] != level) continue;
            Allocation *checkpoint = workspace;
            Environments answers = solutions(r, model, -1);
            for (int j = 0; j < answers.count; j++) {
                Tuple tuple = atom_tuple(r->head, answers.items[j]);
                if (!has_row(&model->predicates[p], &tuple)) add_row(&staged[p], tuple, 0, r->number);
            }
            restore_workspace(checkpoint);
        }
        for (int p = 0; p < state.predicate_count; p++) added += staged[p].count;
        if (!added) break;
        serial++;
        model->rounds[level]++;
        model->added[level] += added;
        for (int p = 0; p < state.predicate_count; p++) for (int i = 0; i < staged[p].count; i++) add_row(&model->predicates[p], staged[p].items[i].tuple, serial, staged[p].items[i].rule);
    }
    return model;
}

static void indent(int depth) {
    for (int i = 0; i < depth * 2; i++) putchar(' ');
}

static void answers_text(const Rule *r, Environments answers, int depth) {
    Variables vars = rule_variables(r, false, true);
    for (int i = 0; i < answers.count; i++) {
        indent(depth);
        for (int j = 0; j < vars.count; j++) {
            int v = vars.ids[j];
            if (j) fputs(", ", stdout);
            printf("%s = ", r->variables[v]);
            value_text(answers.items[i].values[v]);
        }
        putchar('\n');
    }
}

static void proof(int predicate, const Tuple *tuple, const Model *model, int depth) {
    const Rows *rows = &model->predicates[predicate];
    Row row = rows->items[row_index(rows, tuple)];
    if (!row.round) {
        indent(depth);
        tuple_text(state.predicates[predicate].name, tuple);
        puts(" [fact]");
        return;
    }
    for (int ri = 0; ri < state.rule_count; ri++) {
        Rule *r = state.rules[ri];
        if (!r->head || !equal(r->head->name, state.predicates[predicate].name)) continue;
        Allocation *checkpoint = workspace;
        Environments choices = solutions(r, model, row.round);
        sort_variables = rule_variables(r, true, true);
        if (choices.count > 1) qsort(choices.items, (size_t)choices.count, sizeof(Environment), environment_compare);
        for (int i = 0; i < choices.count; i++) {
            Environment env = choices.items[i];
            Tuple head = atom_tuple(r->head, env);
            if (tuple_compare(&head, tuple)) continue;
            indent(depth);
            tuple_text(state.predicates[predicate].name, tuple);
            printf(" [rule %d]\n", r->number);
            for (int li = 0; li < r->body.count; li++) {
                Literal l = r->body.items[li];
                if (l.atom && !l.negative) {
                    int p = predicate_index(l.atom->name);
                    const Rows *premises = &model->predicates[p];
                    Value values[MAX_TERMS];
                    bool bound[MAX_TERMS];
                    Environment scratch = {values, bound};
                    for (int j = 0; j < premises->count; j++) if (premises->items[j].round < row.round && match(l.atom, &premises->items[j].tuple, env, scratch, r->variable_count)) {
                        proof(p, &premises->items[j].tuple, model, depth + 1);
                        break;
                    }
                } else {
                    Buffer b = {0};
                    append_literal(&b, l, r, &env);
                    indent(depth + 1);
                    puts(b.text);
                    free(b.text);
                }
            }
            restore_workspace(checkpoint);
            return;
        }
        restore_workspace(checkpoint);
    }
}
static int predicate_order[MAX_PREDICATES];

static int predicate_name_compare(const void *a, const void *b) {
    return strcmp(state.predicates[*(const int *)a].name, state.predicates[*(const int *)b].name);
}

static void order_predicates(void) {
    for (int i = 0; i < state.predicate_count; i++) predicate_order[i] = i;
    qsort(predicate_order, (size_t)state.predicate_count, sizeof(int), predicate_name_compare);
}

static void process(Statement s) {
    Rule *r = s.rule;
    if (equal(s.kind, "fact") || equal(s.kind, "rule")) {
        ArityTable arities = predicate_check(r, true, true);
        safety(r, -1);
        if (equal(s.kind, "rule")) {
            const char *notation = rule_text(r);
            for (int i = 0; i < state.rule_count; i++) if (equal(notation, rule_text(state.rules[i]))) fail("duplicate of rule %d", state.rules[i]->number);
            int levels[252];
            if (r->head && !strata(&arities, r, levels)) fail("negative cycle through %s", r->head->name);
        } else {
            int p = predicate_index(r->head->name);
            Tuple tuple = atom_tuple(r->head, (Environment){0});
            if (p >= 0) for (int i = 0; i < state.predicates[p].facts.count; i++) if (!tuple_compare(state.predicates[p].facts.items[i], &tuple)) return;
        }
        snapshot();
        for (int i = state.predicate_count; i < arities.count; i++) state.predicates[state.predicate_count++] = (Predicate){.name = arities.names[i], .arity = arities.arities[i]};
        if (equal(s.kind, "fact")) add_fact(&state.predicates[predicate_index(r->head->name)].facts, atom_tuple(r->head, (Environment){0}));
        else {
            r->number = next_rule++;
            state.rules[state.rule_count++] = r;
            Variables occurrences = rule_variables(r, true, false), ordered = rule_variables(r, true, true);
            for (int i = 0; i < ordered.count; i++) {
                int v = ordered.ids[i], count = 0;
                for (int j = 0; j < occurrences.count; j++) count += occurrences.ids[j] == v;
                if (count == 1) printf("WARNING line %d: singleton variable %s\n", line_number, r->variables[v]);
            }
        }
        return;
    }
    if (equal(s.kind, "undo")) {
        if (!history) fail("nothing to undo");
        State previous = history->state;
        int line = history->line;
        history = history->previous;
        state = previous;
        printf("undid line %d\n", line);
        return;
    }
    if (equal(s.kind, "forget")) {
        int at = -1;
        for (int i = 0; i < state.rule_count; i++) if (state.rules[i]->number == s.number) at = i;
        if (at < 0) fail("no rule %lld", s.number);
        snapshot();
        memmove(state.rules + at, state.rules + at + 1, (size_t)(state.rule_count - at - 1) * sizeof(Rule *));
        state.rule_count--;
        return;
    }
    if (listed(s.kind, "retract why")) predicate_check(r, false, true);
    if (equal(s.kind, "retract")) {
        int p = predicate_index(r->head->name);
        Facts *facts = &state.predicates[p].facts;
        int removed = 0;
        bool *remove = allocate((size_t)facts->count * sizeof(bool));
        Environment empty = empty_environment(r->variable_count);
        Value values[MAX_TERMS];
        bool bound[MAX_TERMS];
        Environment scratch = {values, bound};
        for (int i = 0; i < facts->count; i++) {
            remove[i] = match(r->head, facts->items[i], empty, scratch, r->variable_count);
            removed += remove[i];
        }
        if (!removed) fail("no matching facts");
        snapshot();
        int count = 0;
        for (int i = 0; i < facts->count; i++) if (!remove[i]) facts->items[count++] = facts->items[i];
        facts->count = count;
        printf("%d %s retracted\n", removed, removed == 1 ? "fact" : "facts");
        return;
    }
    if (listed(s.kind, "listing dump")) {
        if (s.name && predicate_index(s.name) < 0) fail("unknown predicate %s", s.name);
        if (equal(s.kind, "listing")) {
            bool any = false;
            for (int i = 0; i < state.rule_count; i++) if (!s.name || (state.rules[i]->head && equal(state.rules[i]->head->name, s.name))) {
                printf("%d: %s\n", state.rules[i]->number, rule_text(state.rules[i]));
                any = true;
            }
            if (!any) puts("no rules");
            return;
        }
    }
    if (equal(s.kind, "query")) {
        predicate_check(r, false, false);
        safety(r, s.aggregate_variable);
    }
    if (equal(s.kind, "why")) for (int i = 0; i < r->head->count; i++) if (r->head->terms[i].variable >= 0 || r->head->terms[i].anonymous) fail("why needs a ground atom");
    if (equal(s.kind, "strata")) {
        if (!state.predicate_count) {
            puts("no predicates");
            return;
        }
        Rule empty = {0};
        ArityTable table = predicate_check(&empty, true, false);
        int levels[MAX_PREDICATES];
        strata(&table, NULL, levels);
        bool reach[MAX_PREDICATES][MAX_PREDICATES] = {
            {false}
        };
        for (int i = 0; i < state.rule_count; i++) if (state.rules[i]->head) for (int j = 0; j < state.rules[i]->body.count; j++) {
            Literal l = state.rules[i]->body.items[j];
            if (l.atom) reach[predicate_index(state.rules[i]->head->name)][predicate_index(l.atom->name)] = true;
        }
        for (int k = 0; k < state.predicate_count; k++) for (int i = 0; i < state.predicate_count; i++) for (int j = 0; j < state.predicate_count; j++) reach[i][j] |= reach[i][k] && reach[k][j];
        int maximum = 0;
        for (int i = 0; i < state.predicate_count; i++) if (levels[i] > maximum) maximum = levels[i];
        order_predicates();
        for (int k = 0; k <= maximum; k++) {
            printf("stratum %d: ", k);
            bool first = true;
            for (int i = 0; i < state.predicate_count; i++) {
                int p = predicate_order[i];
                if (levels[p] == k) {
                    if (!first) fputs(", ", stdout);
                    printf("%s%s", state.predicates[p].name, reach[p][p] ? "*" : "");
                    first = false;
                }
            }
            putchar('\n');
        }
        return;
    }
    Model *model = build_model();
    if (equal(s.kind, "query")) {
        Environments answers = solutions(r, model, -1);
        Variables vars = rule_variables(r, false, true);
        if (equal(s.aggregate, "count")) printf("%d\n", answers.count);
        else if (equal(s.aggregate, "sum")) {
            long long total = 0;
            for (int i = 0; i < answers.count; i++) {
                Value v = answers.items[i].values[s.aggregate_variable];
                if (v.symbol) fail("non-integer value in sum");
                total += v.number;
            }
            printf("%lld\n", total);
        } else if (equal(s.aggregate, "min") || equal(s.aggregate, "max")) {
            if (!answers.count) puts("no answers");
            else {
                Value best = answers.items[0].values[s.aggregate_variable];
                for (int i = 1; i < answers.count; i++) {
                    Value v = answers.items[i].values[s.aggregate_variable];
                    int c = value_compare(v, best);
                    if (equal(s.aggregate, "min") ? c < 0 : c > 0) best = v;
                }
                value_text(best);
                putchar('\n');
            }
        } else if (!vars.count) puts(answers.count ? "true." : "false.");
        else {
            answers_text(r, answers, 0);
            printf("%d %s\n", answers.count, answers.count == 1 ? "answer" : "answers");
        }
    } else if (equal(s.kind, "dump")) {
        Rows rows = model->predicates[predicate_index(s.name)];
        for (int i = 0; i < rows.count; i++) {
            tuple_text(s.name, &rows.items[i].tuple);
            puts(".");
        }
        printf("%d %s\n", rows.count, rows.count == 1 ? "tuple" : "tuples");
    } else if (equal(s.kind, "why")) {
        int p = predicate_index(r->head->name);
        Tuple tuple = atom_tuple(r->head, (Environment){0});
        if (!has_row(&model->predicates[p], &tuple)) puts("false.");
        else proof(p, &tuple, model, 0);
    } else if (equal(s.kind, "check")) {
        bool any = false;
        for (int i = 0; i < state.rule_count; i++) if (!state.rules[i]->head) {
            Allocation *checkpoint = workspace;
            Rule *constraint = state.rules[i];
            Environments answers = solutions(constraint, model, -1);
            Variables vars = rule_variables(constraint, false, true);
            any = true;
            printf("constraint %d: ", constraint->number);
            if (!answers.count) puts("ok");
            else printf("%d %s\n", answers.count, answers.count == 1 ? "violation" : "violations");
            if (vars.count) answers_text(constraint, answers, 1);
            restore_workspace(checkpoint);
        }
        if (!any) puts("no constraints");
    } else if (equal(s.kind, "predicates")) {
        if (!state.predicate_count) puts("no predicates");
        order_predicates();
        for (int i = 0; i < state.predicate_count; i++) {
            int p = predicate_order[i], rules = 0;
            for (int j = 0; j < state.rule_count; j++) if (state.rules[j]->head && equal(state.rules[j]->head->name, state.predicates[p].name)) rules++;
            printf("%s/%d: facts %d, rules %d, tuples %d\n", state.predicates[p].name, state.predicates[p].arity, state.predicates[p].facts.count, rules, model->predicates[p].count);
        }
    } else if (equal(s.kind, "stats")) {
        int facts = 0, tuples = 0, rules = 0;
        for (int i = 0; i < state.predicate_count; i++) {
            facts += state.predicates[i].facts.count;
            tuples += model->predicates[i].count;
        }
        for (int i = 0; i < state.rule_count; i++) rules += state.rules[i]->head != NULL;
        printf("facts %d, rules %d, constraints %d, tuples %d\n", facts, rules, state.rule_count - rules, tuples);
        for (int k = 0; k <= model->maximum; k++) printf("stratum %d: rounds %d, new %d\n", k, model->rounds[k], model->added[k]);
        for (int i = 0; i < state.rule_count; i++) if (state.rules[i]->head) {
            int p = predicate_index(state.rules[i]->head->name), count = 0;
            for (int j = 0; j < model->predicates[p].count; j++) count += model->predicates[p].items[j].rule == state.rules[i]->number;
            printf("rule %d: new %d\n", state.rules[i]->number, count);
        }
    }
}

int main(void) {
    char line[202];
    while (fgets(line, sizeof line, stdin)) {
        line_number++;
        size_t length = strlen(line);
        if (length && line[length - 1] == '\n') line[--length] = '\0';
        if (length && line[length - 1] == '\r') line[--length] = '\0';
        if (setjmp(line_error) == 0) {
            Parser p = parser(line);
            if (!is(&p, "end")) {
                Statement s = statement(&p);
                if (equal(s.kind, "halt")) {
                    clear(&workspace);
                    clear(&temporary);
                    break;
                }
                process(s);
            }
        }
        clear(&workspace);
        clear(&temporary);
    }
    clear(&permanent);
    return 0;
}
