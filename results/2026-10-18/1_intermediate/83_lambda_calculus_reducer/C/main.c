#include <stdbool.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <setjmp.h>
typedef struct Allocation {
    void *pointer;
    struct Allocation *next;
} Allocation;
static Allocation *temporary;

static void *allocate(size_t size) {
    void *p = calloc(1, size ? size : 1);
    Allocation *a = malloc(sizeof *a);
    if (!p || !a) exit(EXIT_FAILURE);
    *a = (Allocation){p, temporary};
    temporary = a;
    return p;
}

static void clear_temporary(void) {
    while (temporary) {
        Allocation *next = temporary->next;
        free(temporary->pointer);
        free(temporary);
        temporary = next;
    }
}
typedef struct Name {
    struct Name *next;
    size_t length;
    char text[];
} Name;
#define NAME_BUCKETS 4093
static Name *name_buckets[NAME_BUCKETS];

static const char *intern_part(const char *text, size_t length) {
    unsigned long hash = 5381;
    for (size_t i = 0; i < length; i++) hash = hash * 33 + (unsigned char)text[i];
    size_t bucket = hash % NAME_BUCKETS;
    for (Name *n = name_buckets[bucket]; n; n = n->next) if (n->length == length && !memcmp(n->text, text, length)) return n->text;
    Name *n = malloc(sizeof *n + length + 1);
    if (!n) exit(EXIT_FAILURE);
    n->length = length;
    memcpy(n->text, text, length);
    n->text[length] = '\0';
    n->next = name_buckets[bucket];
    name_buckets[bucket] = n;
    return n->text;
}

static const char *intern(const char *text) {
    return intern_part(text, strlen(text));
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

static bool macro_name(const char *name) {
    if (!upper(*name)) return false;
    for (const char *p = name + 1; *p; p++) if (!upper(*p) && !digit(*p) && *p != '_') return false;
    return true;
}
static jmp_buf command_error;

static void fail(const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    fputs("error: ", stdout);
    vprintf(pattern, args);
    putchar('\n');
    va_end(args);
    longjmp(command_error, 1);
}
typedef struct Term Term;
struct Term {
    char kind;
    const char *name;
    int number;
    Term *left, *right;
    bool marked;
    Term *next;
};
static Term *terms;
static size_t term_count;

static Term *term(char kind, const char *name, int number, Term *left, Term *right) {
    Term *t = calloc(1, sizeof *t);
    if (!t) exit(EXIT_FAILURE);
    *t = (Term){kind, name, number, left, right, false, terms};
    terms = t;
    term_count++;
    return t;
}

static Term *variable(const char *name) {
    return term('v', name, 0, NULL, NULL);
}

static Term *constant(const char *name) {
    return term('c', name, 0, NULL, NULL);
}

static Term *abstraction(const char *name, Term *body) {
    return term('a', name, 0, body, NULL);
}

static Term *application(Term *function, Term *argument) {
    return term('p', "", 0, function, argument);
}
typedef struct {
    const char *name;
    Term *term;
} Macro;
static Macro macros[103];
static int macro_count;
static bool display, eta;
static int limit = 10000;

static int find_macro(const char *name) {
    for (int i = 0; i < macro_count; i++) if (equal(macros[i].name, name)) return i;
    return -1;
}

static int macro_compare(const void *a, const void *b) {
    return strcmp(((const Macro *)a)->name, ((const Macro *)b)->name);
}

static void mark(Term *t) {
    if (!t || t->marked) return;
    t->marked = true;
    mark(t->left);
    mark(t->right);
}

static void collect(Term *current, Term *keep) {
    for (int i = 0; i < macro_count; i++) mark(macros[i].term);
    mark(current);
    mark(keep);
    Term **link = &terms;
    while (*link) {
        Term *t = *link;
        if (t->marked) {
            t->marked = false;
            link = &t->next;
        } else {
            *link = t->next;
            free(t);
            term_count--;
        }
    }
}
typedef struct {
    const char *kind, *text;
    int column;
} Token;
typedef struct {
    Token *tokens;
    int count, at;
} Parser;

static bool token_is(Parser *p, const char *kind) {
    return equal(p->tokens[p->at].kind, kind);
}

static Parser parser(const char *line, size_t start) {
    size_t length = strlen(line);
    Parser p = {allocate((length + 1) * sizeof(Token)), 0, 0};
    for (size_t i = start; i < length;) {
        char c = line[i];
        if (c == ' ') {
            i++;
            continue;
        }
        size_t first = i;
        const char *kind;
        if (strchr("\\.()=;", c)) {
            kind = intern_part(line + i, 1);
            i++;
        } else if (lower(c)) {
            kind = "variable";
            while (i < length && (lower(line[i]) || digit(line[i]))) i++;
        } else if (upper(c)) {
            kind = "macro";
            while (i < length && (upper(line[i]) || digit(line[i]) || line[i] == '_')) i++;
        } else if (c == '#' && i + 1 < length && digit(line[i + 1])) {
            kind = "numeral";
            i++;
            while (i < length && digit(line[i])) i++;
        } else {
            fail("column %zu: unexpected character '%c'", i + 1, c);
            return p;
        }
        p.tokens[p.count++] = (Token){kind, intern_part(line + first, i - first), (int)first + 1};
    }
    p.tokens[p.count++] = (Token){"end", "", (int)length + 1};
    return p;
}

static Token expect(Parser *p, const char *kind) {
    Token t = p->tokens[p->at];
    if (!equal(t.kind, kind)) {
        if (equal(kind, "variable") || equal(kind, "macro")) fail("column %d: expected %s", t.column, equal(kind, "macro") ? "macro name" : "variable");
        else fail("column %d: expected '%s'", t.column, kind);
    }
    p->at++;
    return t;
}
static Term *read_term(Parser *p);

static Term *atom(Parser *p) {
    Token t = p->tokens[p->at++];
    if (equal(t.kind, "variable")) return variable(t.text);
    if (equal(t.kind, "macro")) return term('m', t.text, 0, NULL, NULL);
    if (equal(t.kind, "numeral")) return term('n', "", atoi(t.text + 1), NULL, NULL);
    Term *body = read_term(p);
    expect(p, ")");
    return body;
}

static Term *read_term(Parser *p) {
    Term *result = NULL;
    while (token_is(p, "variable") || token_is(p, "macro") || token_is(p, "numeral") || token_is(p, "(")) {
        Term *next = atom(p);
        result = result ? application(result, next) : next;
    }
    if (token_is(p, "\\")) {
        p->at++;
        const char **names = allocate((size_t)p->count * sizeof(char *));
        int count = 0;
        names[count++] = expect(p, "variable").text;
        while (token_is(p, "variable")) names[count++] = p->tokens[p->at++].text;
        expect(p, ".");
        Term *body = read_term(p);
        for (int i = count - 1; i >= 0; i--) body = abstraction(names[i], body);
        result = result ? application(result, body) : body;
    }
    if (!result) fail("column %d: expected term", p->tokens[p->at].column);
    return result;
}

static void parser_end(Parser *p) {
    if (!token_is(p, "end")) fail("column %d: unexpected '%s'", p->tokens[p->at].column, p->tokens[p->at].text);
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
        char *next = realloc(b->text, capacity);
        if (!next) exit(EXIT_FAILURE);
        b->text = next;
        b->capacity = capacity;
    }
    memcpy(b->text + b->length, text, n + 1);
    b->length += n;
}

static void append_number(Buffer *b, int value) {
    char text[32];
    snprintf(text, sizeof text, "%d", value);
    append(b, text);
}

static void print_term(Buffer *b, const Term *t, bool end) {
    if (t->kind == 'n') {
        append(b, "#");
        append_number(b, t->number);
        return;
    }
    if (t->kind == 'd') {
        append_number(b, t->number);
        return;
    }
    if (t->kind != 'a' && t->kind != 'p') {
        append(b, t->name);
        return;
    }
    if (t->kind == 'a') {
        if (!end) append(b, "(");
        bool debruijn = !*t->name;
        append(b, "\\");
        const Term *body = t;
        bool first = true;
        while (body->kind == 'a') {
            if (debruijn) {
                if (!first) append(b, "\\");
            } else {
                if (!first) append(b, " ");
                append(b, body->name);
            }
            first = false;
            body = body->left;
        }
        if (!debruijn) append(b, ". ");
        print_term(b, body, true);
        if (!end) append(b, ")");
        return;
    }
    if (t->left->kind == 'a') {
        append(b, "(");
        print_term(b, t->left, true);
        append(b, ")");
    } else print_term(b, t->left, false);
    append(b, " ");
    if (t->right->kind == 'p') {
        append(b, "(");
        print_term(b, t->right, true);
        append(b, ")");
    } else print_term(b, t->right, end);
}

static void output_term(Term *t) {
    Buffer b = {0};
    print_term(&b, t, true);
    puts(b.text);
    free(b.text);
}

static bool free_contains(const Term *t, const char *name) {
    if (t->kind == 'v') return equal(t->name, name);
    if (t->kind == 'a') return !equal(t->name, name) && free_contains(t->left, name);
    if (t->kind == 'p') return free_contains(t->left, name) || free_contains(t->right, name);
    return false;
}
typedef struct {
    const char **items;
    int count;
} Names;

static bool names_contain(Names names, const char *name) {
    for (int i = 0; i < names.count; i++) if (equal(names.items[i], name)) return true;
    return false;
}

static void free_names_walk(Term *t, const char **bindings, int depth, Names *names) {
    if (t->kind == 'v') {
        for (int i = depth - 1; i >= 0; i--) if (equal(bindings[i], t->name)) return;
        if (!names_contain(*names, t->name)) names->items[names->count++] = t->name;
    } else if (t->kind == 'a') {
        bindings[depth] = t->name;
        free_names_walk(t->left, bindings, depth + 1, names);
    } else if (t->kind == 'p') {
        free_names_walk(t->left, bindings, depth, names);
        free_names_walk(t->right, bindings, depth, names);
    }
}

static int name_compare(const void *a, const void *b) {
    return strcmp(*(const char *const *)a, *(const char *const *)b);
}

static Names free_names(Term *t) {
    Names names = {allocate(10000 * sizeof(char *)), 0};
    const char *bindings[201];
    free_names_walk(t, bindings, 0, &names);
    if (names.count > 1) qsort(names.items, (size_t)names.count, sizeof(char *), name_compare);
    return names;
}

static Term *substitute(Term *t, const char *name, Term *value) {
    if (t->kind == 'v') return equal(t->name, name) ? value : t;
    if (t->kind == 'p') {
        Term *left = substitute(t->left, name, value);
        Term *right = substitute(t->right, name, value);
        return application(left, right);
    }
    const char *bound = t->name;
    if (equal(bound, name) || !free_contains(t->left, name)) return t;
    if (!free_contains(value, bound)) return abstraction(bound, substitute(t->left, name, value));
    size_t length = strlen(bound);
    while (length && digit(bound[length - 1])) length--;
    size_t capacity = length + 32;
    char *candidate = malloc(capacity);
    if (!candidate) exit(EXIT_FAILURE);
    int number = 1;
    do {
        snprintf(candidate, capacity, "%.*s%d", (int)length, bound, number++);
    }
    while (free_contains(t->left, candidate) || free_contains(value, candidate));
    const char *fresh = intern(candidate);
    free(candidate);
    Term *renamed = substitute(t->left, bound, variable(fresh));
    return abstraction(fresh, substitute(renamed, name, value));
}

static const char *sequence(int index) {
    char text[32];
    if (index < 26) {
        text[0] = (char)('a' + index);
        text[1] = '\0';
    } else snprintf(text, sizeof text, "%c%d", 'a' + index % 26, index / 26);
    return intern(text);
}
typedef struct {
    const char *old_name, *new_name;
} Binding;

static Term *rename(Term *t, Names free, int *next, Binding *bindings, int depth) {
    if (t->kind == 'v') {
        for (int i = depth - 1; i >= 0; i--) if (equal(bindings[i].old_name, t->name)) return variable(bindings[i].new_name);
        return t;
    }
    if (t->kind == 'p') {
        Term *left = rename(t->left, free, next, bindings, depth);
        Term *right = rename(t->right, free, next, bindings, depth);
        return application(left, right);
    }
    const char *name;
    do {
        name = sequence((*next)++);
    }
    while (names_contain(free, name));
    bindings[depth] = (Binding){t->name, name};
    return abstraction(name, rename(t->left, free, next, bindings, depth + 1));
}

static Term *canonical(Term *t) {
    int next = 0;
    Binding bindings[201];
    return rename(t, free_names(t), &next, bindings, 0);
}

static Term *debruijn_walk(Term *t, const char **bindings, int depth) {
    if (t->kind == 'v') {
        for (int i = depth - 1; i >= 0; i--) if (equal(bindings[i], t->name)) return term('d', "", depth - 1 - i, NULL, NULL);
        return t;
    }
    if (t->kind == 'p') {
        Term *left = debruijn_walk(t->left, bindings, depth);
        Term *right = debruijn_walk(t->right, bindings, depth);
        return application(left, right);
    }
    bindings[depth] = t->name;
    return abstraction("", debruijn_walk(t->left, bindings, depth + 1));
}

static Term *debruijn(Term *t) {
    const char *bindings[201];
    return debruijn_walk(t, bindings, 0);
}

static bool same(const Term *a, const Term *b) {
    if (a->kind != b->kind) return false;
    if (a->kind == 'v' || a->kind == 'c' || a->kind == 'm') return equal(a->name, b->name);
    if (a->kind == 'd' || a->kind == 'n') return a->number == b->number;
    if (a->kind == 'a') return same(a->left, b->left);
    return same(a->left, b->left) && same(a->right, b->right);
}
typedef struct {
    Term *term;
    const char *kind;
} Step;

static bool eta_redex(Term *t) {
    return t->kind == 'a' && t->left->kind == 'p' && t->left->right->kind == 'v' && equal(t->left->right->name, t->name) && !free_contains(t->left->left, t->name);
}

static Step one_step(Term *t, const char *strategy, bool use_eta) {
    bool normal = equal(strategy, "NORMAL"), applicative = equal(strategy, "APPLICATIVE"), cbn = equal(strategy, "CBN");
    if (t->kind == 'v') return (Step){0};
    if (t->kind == 'a') {
        if (!normal && !applicative) return (Step){0};
        if (normal && use_eta && eta_redex(t)) return (Step){t->left->left, "eta"};
        Step body = one_step(t->left, strategy, use_eta);
        if (body.term) return (Step){abstraction(t->name, body.term), body.kind};
        return use_eta && eta_redex(t) ? (Step){t->left->left, "eta"} : (Step){0};
    }
    if ((normal || cbn) && t->left->kind == 'a') return (Step){substitute(t->left->left, t->left->name, t->right), "beta"};
    Step left = one_step(t->left, strategy, use_eta);
    if (left.term) return (Step){application(left.term, t->right), left.kind};
    if (cbn) return (Step){0};
    Step right = one_step(t->right, strategy, use_eta);
    if (right.term) return (Step){application(t->left, right.term), right.kind};
    if (t->left->kind == 'a' && (normal || applicative || t->right->kind == 'v' || t->right->kind == 'a')) return (Step){substitute(t->left->left, t->left->name, t->right), "beta"};
    return (Step){0};
}

static Term *expand(Term *t) {
    if (t->kind == 'v') return t;
    if (t->kind == 'm') {
        int index = find_macro(t->name);
        if (index < 0) fail("unbound macro %s", t->name);
        return expand(macros[index].term);
    }
    if (t->kind == 'n') {
        Term *body = variable("x");
        for (int i = 0; i < t->number; i++) body = application(variable("f"), body);
        return abstraction("f", abstraction("x", body));
    }
    if (t->kind == 'a') return abstraction(t->name, expand(t->left));
    Term *left = expand(t->left);
    Term *right = expand(t->right);
    return application(left, right);
}

static bool has_reference(Term *t, const char *name) {
    if (t->kind == 'm') return equal(t->name, name);
    return (t->left && has_reference(t->left, name)) || (t->right && has_reference(t->right, name));
}

static bool depends(Term *t, const char *name, bool *seen) {
    if (t->kind == 'm') {
        if (equal(t->name, name)) return true;
        int index = find_macro(t->name);
        if (index < 0 || seen[index]) return false;
        seen[index] = true;
        return depends(macros[index].term, name, seen);
    }
    return (t->left && depends(t->left, name, seen)) || (t->right && depends(t->right, name, seen));
}

static void check_references(Term *t, const char *name) {
    if (t->kind == 'm') {
        bool seen[103] = {false};
        if (depends(t, name, seen)) fail("recursive definition of %s", name);
        if (find_macro(t->name) < 0) fail("unbound macro %s", t->name);
    } else {
        if (t->left) check_references(t->left, name);
        if (t->right) check_references(t->right, name);
    }
}

static int size(Term *t) {
    return t->kind == 'v' ? 1 : t->kind == 'a' ? 1 + size(t->left) : 1 + size(t->left) + size(t->right);
}

static int depth(Term *t) {
    if (t->kind == 'v') return 1;
    int left = depth(t->left);
    if (t->kind == 'a') return 1 + left;
    int right = depth(t->right);
    return 1 + (left > right ? left : right);
}
typedef struct Type Type;
struct Type {
    int variable;
    Type *left, *right, *link;
};

static Type *type_variable(int *next) {
    Type *t = allocate(sizeof *t);
    t->variable = (*next)++;
    return t;
}

static Type *arrow(Type *left, Type *right) {
    Type *t = allocate(sizeof *t);
    t->variable = -1;
    t->left = left;
    t->right = right;
    return t;
}

static Type *resolved(Type *t) {
    Type *end = t;
    while (end->link) end = end->link;
    while (t->link) {
        Type *next = t->link;
        t->link = end;
        t = next;
    }
    return end;
}

static bool occurs(Type *variable, Type *within) {
    within = resolved(within);
    return within == variable || (within->variable < 0 && (occurs(variable, within->left) || occurs(variable, within->right)));
}

static bool unify(Type *a, Type *b) {
    a = resolved(a);
    b = resolved(b);
    if (a == b) return true;
    if (a->variable >= 0) {
        if (occurs(a, b)) return false;
        a->link = b;
        return true;
    }
    if (b->variable >= 0) return unify(b, a);
    return unify(a->left, b->left) && unify(a->right, b->right);
}
typedef struct {
    const char *name;
    Type *type;
} TypedBinding;
typedef struct {
    int next, free_count;
    TypedBinding free[10000], bindings[201];
} Inference;

static Type *infer(Term *t, Inference *inference, int depth) {
    if (t->kind == 'v') {
        for (int i = depth - 1; i >= 0; i--) if (equal(inference->bindings[i].name, t->name)) return inference->bindings[i].type;
        for (int i = 0; i < inference->free_count; i++) if (equal(inference->free[i].name, t->name)) return inference->free[i].type;
        Type *type = type_variable(&inference->next);
        inference->free[inference->free_count++] = (TypedBinding){t->name, type};
        return type;
    }
    if (t->kind == 'a') {
        Type *parameter = type_variable(&inference->next);
        inference->bindings[depth] = (TypedBinding){t->name, parameter};
        Type *body = infer(t->left, inference, depth + 1);
        return body ? arrow(parameter, body) : NULL;
    }
    Type *function = infer(t->left, inference, depth);
    if (!function) return NULL;
    Type *argument = infer(t->right, inference, depth);
    if (!argument) return NULL;
    Type *result = type_variable(&inference->next);
    return unify(function, arrow(argument, result)) ? result : NULL;
}

static void print_type(Buffer *buffer, Type *t, const char **names, int *next) {
    t = resolved(t);
    if (t->variable >= 0) {
        if (!names[t->variable]) names[t->variable] = sequence((*next)++);
        append(buffer, names[t->variable]);
        return;
    }
    Type *left = resolved(t->left);
    if (left->variable < 0) append(buffer, "(");
    print_type(buffer, left, names, next);
    if (left->variable < 0) append(buffer, ")");
    append(buffer, " -> ");
    print_type(buffer, t->right, names, next);
}

static void output_type(Term *t) {
    Inference *inference = allocate(sizeof *inference);
    Type *type = infer(t, inference, 0);
    if (!type) {
        puts("not typable");
        return;
    }
    const char **names = allocate((size_t)inference->next * sizeof(char *));
    int next = 0;
    Buffer buffer = {0};
    print_type(&buffer, type, names, &next);
    puts(buffer.text);
    free(buffer.text);
}

static void church(Buffer *buffer, Term *t) {
    if (t->kind == 'a' && t->left->kind == 'a') {
        const char *f = t->name, *x = t->left->name;
        Term *body = t->left->left;
        int count = 0;
        while (body->kind == 'p' && body->left->kind == 'v' && equal(body->left->name, f)) {
            count++;
            body = body->right;
        }
        if (body->kind == 'v' && equal(body->name, x)) {
            append_number(buffer, count);
            return;
        }
        if (t->left->left->kind == 'v' && equal(t->left->left->name, f)) {
            append(buffer, "true");
            return;
        }
    }
    if (t->kind == 'a' && t->left->kind == 'p' && t->left->left->kind == 'p' && t->left->left->left->kind == 'v' && equal(t->left->left->left->name, t->name)) {
        Term *p = t->left->left->right, *q = t->left->right;
        if (!free_contains(p, t->name) && !free_contains(q, t->name)) {
            append(buffer, "(");
            church(buffer, p);
            append(buffer, ", ");
            church(buffer, q);
            append(buffer, ")");
            return;
        }
    }
    print_term(buffer, canonical(t), true);
}

static Term *abstract_ski(const char *name, Term *t) {
    if (!free_contains(t, name)) return application(constant("K"), t);
    if (t->kind == 'v' && equal(t->name, name)) return constant("I");
    if (t->kind == 'p' && t->right->kind == 'v' && equal(t->right->name, name) && !free_contains(t->left, name)) return t->left;
    Term *left = abstract_ski(name, t->left);
    Term *right = abstract_ski(name, t->right);
    return application(application(constant("S"), left), right);
}

static Term *ski(Term *t) {
    if (t->kind == 'v') return t;
    if (t->kind == 'a') return abstract_ski(t->name, ski(t->left));
    Term *left = ski(t->left);
    Term *right = ski(t->right);
    return application(left, right);
}

static Term *apply(Term *head, Term **args, int count, int from) {
    for (int i = from; i < count; i++) head = application(head, args[i]);
    return head;
}

static Step ski_step(Term *t) {
    Term *args[201], *head = t;
    int count = 0;
    while (head->kind == 'p') {
        args[count++] = head->right;
        head = head->left;
    }
    for (int i = 0; i < count / 2; i++) {
        Term *swap = args[i];
        args[i] = args[count - i - 1];
        args[count - i - 1] = swap;
    }
    if (head->kind == 'c') {
        if (equal(head->name, "I") && count >= 1) return (Step){apply(args[0], args, count, 1), "I"};
        if (equal(head->name, "K") && count >= 2) return (Step){apply(args[0], args, count, 2), "K"};
        if (equal(head->name, "S") && count >= 3) return (Step){apply(application(application(args[0], args[2]), application(args[1], args[2])), args, count, 3), "S"};
    }
    for (int i = 0; i < count; i++) {
        Step next = ski_step(args[i]);
        if (next.term) {
            args[i] = next.term;
            return (Step){apply(head, args, count, 0), next.kind};
        }
    }
    return (Step){0};
}
typedef struct {
    Term *term;
    int count;
    bool success;
} Reduced;

static Reduced reduce(Term *t, const char *strategy, bool use_eta, bool show, bool use_ski, Term *keep) {
    int count = 0;
    while (true) {
        Step next = use_ski ? ski_step(t) : one_step(t, strategy, use_eta);
        if (!next.term) return (Reduced){t, count, true};
        if (count == limit) return (Reduced){t, count, false};
        t = next.term;
        count++;
        if (show) {
            printf("step %d (%s): ", count, next.kind);
            output_term(t);
        }
        if (term_count > 100000) collect(t, keep);
    }
}

static void output_failure(void) {
    printf("no normal form within %d steps\n", limit);
}
typedef struct Environment Environment;
typedef struct {
    Term *term;
    Environment *environment;
} Closure;
struct Environment {
    Closure closure;
    Environment *next;
    int count;
};

static Closure environment_at(Environment *environment, int index) {
    while (index--) environment = environment->next;
    return environment->closure;
}

static Term *realize(Term *code, Environment *environment, int depth) {
    while (code->kind == 'd' && code->number >= depth) {
        Closure closure = environment_at(environment, code->number - depth);
        code = closure.term;
        environment = closure.environment;
        depth = 0;
    }
    if (code->kind == 'v' || code->kind == 'd') return code;
    if (code->kind == 'a') return abstraction("", realize(code->left, environment, depth + 1));
    Term *left = realize(code->left, environment, depth);
    Term *right = realize(code->right, environment, depth);
    return application(left, right);
}

static Term *from_debruijn(Term *t, Names free, const char **bindings, int depth, int *next) {
    if (t->kind == 'v') return t;
    if (t->kind == 'd') return variable(bindings[depth - 1 - t->number]);
    if (t->kind == 'p') {
        Term *left = from_debruijn(t->left, free, bindings, depth, next);
        Term *right = from_debruijn(t->right, free, bindings, depth, next);
        return application(left, right);
    }
    const char *name;
    do {
        name = sequence((*next)++);
    }
    while (names_contain(free, name));
    bindings[depth] = name;
    return abstraction(name, from_debruijn(t->left, free, bindings, depth + 1, next));
}

static void kam(Term *t) {
    Term *code = debruijn(t);
    Environment *environment = NULL;
    Closure *stack = allocate((size_t)limit * sizeof(Closure));
    int count = 0, stack_count = 0;
    while (true) {
        const char *kind = code->kind == 'p' ? "push" : code->kind == 'a' && stack_count ? "grab" : code->kind == 'd' ? "access" : "";
        if (!*kind) break;
        if (count == limit) {
            printf("no result within %d transitions\n", limit);
            return;
        }
        if (equal(kind, "push")) {
            stack[stack_count++] = (Closure){code->right, environment};
            code = code->left;
        } else if (equal(kind, "grab")) {
            Environment *next = allocate(sizeof *next);
            *next = (Environment){stack[--stack_count], environment, environment ? environment->count + 1 : 1};
            environment = next;
            code = code->left;
        } else {
            Closure closure = environment_at(environment, code->number);
            code = closure.term;
            environment = closure.environment;
        }
        count++;
        if (display) {
            printf("step %d (%s): ", count, kind);
            Buffer buffer = {0};
            print_term(&buffer, code, true);
            printf("%s [env %d, stack %d]\n", buffer.text, environment ? environment->count : 0, stack_count);
            free(buffer.text);
        }
    }
    Term *result = realize(code, environment, 0);
    for (int i = stack_count - 1; i >= 0; i--) result = application(result, realize(stack[i].term, stack[i].environment, 0));
    const char *bindings[201];
    int next = 0;
    result = from_debruijn(result, free_names(result), bindings, 0, &next);
    fputs("result: ", stdout);
    Buffer buffer = {0};
    print_term(&buffer, result, true);
    printf("%s (transitions: %d)\n", buffer.text, count);
    free(buffer.text);
}

static bool listed(const char *name, const char *list) {
    size_t length = strlen(name);
    const char *at = list;
    while (*at) {
        const char *end = strchr(at, ' ');
        size_t n = end ? (size_t)(end - at) : strlen(at);
        if (length == n && !memcmp(at, name, n)) return true;
        if (!end) break;
        at = end + 1;
    }
    return false;
}

static bool reserved(const char *name) {
    return listed(name, "S K I NORMAL APPLICATIVE CBN CBV");
}

static void command(const char *line) {
    const char *space = strchr(line, ' '), *argument = space ? space + 1 : line + strlen(line);
    const char *name = intern_part(line, space ? (size_t)(space - line) : strlen(line));
    if (!listed(name, "let unlet macros steps eta limit expand subst reduce equal alpha debruijn fv size depth type church ski skireduce kam")) fail("unknown command %s", name);
    if (listed(name, "unlet macros steps eta limit")) {
        const char **words = allocate((strlen(argument) + 1) * sizeof(char *));
        int count = 0;
        const char *p = argument;
        while (*p) {
            while (*p == ' ') p++;
            if (!*p) break;
            const char *first = p;
            while (*p && *p != ' ') p++;
            words[count++] = intern_part(first, (size_t)(p - first));
        }
        if (equal(name, "steps") || equal(name, "eta")) {
            if (count != 1 || (!equal(words[0], "on") && !equal(words[0], "off"))) fail("bad argument");
            if (equal(name, "steps")) display = equal(words[0], "on");
            else eta = equal(words[0], "on");
        } else if (equal(name, "limit")) {
            if (count != 1 || !*words[0] || strlen(words[0]) > 5) fail("bad argument");
            for (const char *c = words[0]; *c; c++) if (!digit(*c)) fail("bad argument");
            int value = atoi(words[0]);
            if (value < 1 || value > 10000) fail("bad argument");
            limit = value;
        } else if (equal(name, "macros")) {
            if (count) fail("bad argument");
            bool any = false;
            for (int i = 0; i < macro_count; i++) if (!listed(macros[i].name, "S K I")) {
                printf("%s = ", macros[i].name);
                output_term(macros[i].term);
                any = true;
            }
            if (!any) puts("(none)");
        } else {
            if (count != 1 || !macro_name(words[0])) fail("bad argument");
            const char *macro = words[0];
            if (reserved(macro)) fail("reserved name %s", macro);
            int index = find_macro(macro);
            if (index < 0) fail("unbound macro %s", macro);
            for (int i = 0; i < macro_count; i++) if (has_reference(macros[i].term, macro)) fail("%s is used by %s", macro, macros[i].name);
            memmove(macros + index, macros + index + 1, (size_t)(macro_count - index - 1) * sizeof(Macro));
            macro_count--;
            printf("removed %s\n", macro);
        }
        return;
    }
    Parser p = parser(line, (size_t)(argument - line));
    const char *identifier = NULL, *strategy = "NORMAL";
    Term *first, *second = NULL;
    if (equal(name, "let")) {
        identifier = expect(&p, "macro").text;
        expect(&p, "=");
        first = read_term(&p);
    } else if (equal(name, "subst")) {
        identifier = expect(&p, "variable").text;
        expect(&p, "=");
        first = read_term(&p);
        expect(&p, ";");
        second = read_term(&p);
    } else {
        if (equal(name, "reduce") && token_is(&p, "macro") && listed(p.tokens[p.at].text, "NORMAL APPLICATIVE CBN CBV")) strategy = p.tokens[p.at++].text;
        first = read_term(&p);
        if (equal(name, "equal") || equal(name, "alpha")) {
            expect(&p, ";");
            second = read_term(&p);
        }
    }
    parser_end(&p);
    if (equal(name, "let")) {
        if (reserved(identifier)) fail("reserved name %s", identifier);
        check_references(first, identifier);
        Names free = free_names(first);
        if (free.count) fail("free variable %s in definition of %s", free.items[0], identifier);
        int index = find_macro(identifier);
        printf("%s %s\n", index >= 0 ? "redefined" : "defined", identifier);
        if (index < 0) index = macro_count++;
        macros[index] = (Macro){identifier, first};
        qsort(macros, (size_t)macro_count, sizeof(Macro), macro_compare);
        return;
    }
    first = expand(first);
    if (second) second = expand(second);
    if (equal(name, "expand")) output_term(first);
    else if (equal(name, "subst")) output_term(substitute(second, identifier, first));
    else if (equal(name, "debruijn")) output_term(debruijn(first));
    else if (equal(name, "fv")) {
        Names free = free_names(first);
        if (!free.count) puts("(none)");
        else {
            for (int i = 0; i < free.count; i++) printf("%s%s", i ? " " : "", free.items[i]);
            putchar('\n');
        }
    } else if (equal(name, "size")) printf("%d\n", size(first));
    else if (equal(name, "depth")) printf("%d\n", depth(first));
    else if (equal(name, "alpha")) {
        Term *a = debruijn(first);
        Term *b = debruijn(second);
        puts(same(a, b) ? "yes" : "no");
    } else if (equal(name, "equal")) {
        Reduced a = reduce(first, "NORMAL", eta, false, false, second);
        Reduced b = reduce(second, "NORMAL", eta, false, false, a.term);
        if (!a.success || !b.success) puts("unknown");
        else {
            Term *left = debruijn(a.term);
            Term *right = debruijn(b.term);
            puts(same(left, right) ? "yes" : "no");
        }
    } else if (equal(name, "type")) output_type(first);
    else if (equal(name, "church")) {
        Reduced result = reduce(first, "NORMAL", false, false, false, NULL);
        if (!result.success) output_failure();
        else {
            Buffer buffer = {0};
            church(&buffer, canonical(result.term));
            puts(buffer.text);
            free(buffer.text);
        }
    } else if (equal(name, "ski")) output_term(ski(first));
    else if (equal(name, "kam")) kam(first);
    else {
        bool use_ski = equal(name, "skireduce");
        Reduced result = reduce(use_ski ? ski(first) : first, strategy, eta, display, use_ski, NULL);
        if (!result.success) output_failure();
        else {
            fputs("result: ", stdout);
            Buffer buffer = {0};
            print_term(&buffer, use_ski ? result.term : canonical(result.term), true);
            printf("%s (steps: %d)\n", buffer.text, result.count);
            free(buffer.text);
        }
    }
}

static char *read_line(void) {
    size_t length = 0, capacity = 128;
    char *line = malloc(capacity);
    if (!line) exit(EXIT_FAILURE);
    int c;
    while ((c = getchar()) != EOF && c != '\n') {
        if (length + 1 == capacity) {
            capacity *= 2;
            char *next = realloc(line, capacity);
            if (!next) exit(EXIT_FAILURE);
            line = next;
        }
        line[length++] = (char)c;
    }
    if (c == EOF && !length) {
        free(line);
        return NULL;
    }
    line[length] = '\0';
    return line;
}
int main(void) {
    Term *x = variable("x"), *y = variable("y"), *z = variable("z");
    macros[macro_count++] = (Macro){"I", abstraction("x", x)};
    macros[macro_count++] = (Macro){"K", abstraction("x", abstraction("y", x))};
    macros[macro_count++] = (Macro){"S", abstraction("x", abstraction("y", abstraction("z", application(application(x, z), application(y, z)))))};
    char *line;
    while ((line = read_line())) {
        if (equal(line, "quit")) {
            free(line);
            break;
        }
        if (*line && strncmp(line, "--", 2) != 0) {
            if (setjmp(command_error) == 0) command(line);
            clear_temporary();
            collect(NULL, NULL);
        }
        free(line);
    }
    macro_count = 0;
    collect(NULL, NULL);
    for (int i = 0; i < NAME_BUCKETS; i++) while (name_buckets[i]) {
        Name *next = name_buckets[i]->next;
        free(name_buckets[i]);
        name_buckets[i] = next;
    }
    return 0;
}
