#include <stdbool.h>
#include <ctype.h>
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct Node Node;
struct Node {
    char kind;
    int n, row, flags;
    char *text;
    Node *a, *b;
    Node **args;
    int argc;
};
typedef struct {
    Node *value;
    int position;
} Token;
typedef struct {
    Token tokens[205];
    int size, at;
} Parser;
typedef struct {
    char name[16];
    Node **contents;
} History;
typedef struct {
    Node *contents[2574], *values[2574];
    int *deps[2574], counts[2574];
    History history[1000];
    int history_size;
    int indices[2574], low[2574], stack[2574], stack_size, serial;
    bool on[2574], cyclic[2574], done[2574];
} Sheet;
static jmp_buf command_jump;
static char problem[80];
static Node invalid_node = {.kind = 'X'};
static Node *invalid = &invalid_node;
static void fail(const char *s) {
    snprintf(problem, sizeof problem, "%s", s);
    longjmp(command_jump, 1);
}
static void syntax(int p) {
    char s[80];
    snprintf(s, sizeof s, "syntax error at %d", p);
    fail(s);
}
typedef struct Allocation Allocation;
struct Allocation {
    void *pointer;
    Allocation *next;
};
static Allocation *value_allocations;
static bool evaluating;
static void *allocate(size_t n) {
    void *p = calloc(n ? n : 1, 1);
    if (!p)
        exit(1);
    if (evaluating) {
        Allocation *entry = malloc(sizeof *entry);
        if (!entry)
            exit(1);
        entry->pointer = p;
        entry->next = value_allocations;
        value_allocations = entry;
    }
    return p;
}
static void release_values(Allocation *entries) {
    while (entries) {
        Allocation *next = entries->next;
        free(entries->pointer);
        free(entries);
        entries = next;
    }
}
static char *copy_text(const char *s, size_t n) {
    char *p = allocate(n + 1);
    memcpy(p, s, n);
    return p;
}
static Node *node(char kind, int n, const char *s, Node *a, Node *b) {
    Node *x = allocate(sizeof *x);
    x->kind = kind;
    x->n = n;
    x->text = copy_text(s, strlen(s));
    x->a = a;
    x->b = b;
    return x;
}
static Node *num(int n) {
    return node('N', n, "", NULL, NULL);
}
static Node *text(const char *s) {
    return node('S', 0, s, NULL, NULL);
}
static Node *error_value(const char *s) {
    return node('E', 0, s, NULL, NULL);
}
static Node *reference(int c, int r, int f) {
    Node *x = node('R', c, "", NULL, NULL);
    x->row = r;
    x->flags = f;
    return x;
}
static int id(Node *r) {
    return r->row * 26 + r->n;
}
static void label(int i, char *s) {
    sprintf(s, "%c%d", 'A' + i % 26, i / 26 + 1);
}
static bool inside(Node *r) {
    return r->n >= 0 && r->n < 26 && r->row >= 0 && r->row < 99;
}
static Node *range(Node *a, Node *b) {
    int c = a->n, d = b->n, r = a->row, t = b->row, ac = a->flags & 1, bc = b->flags & 1,
        ar = a->flags & 2, br = b->flags & 2, z;
    if (c > d) {
        z = c;
        c = d;
        d = z;
        z = ac;
        ac = bc;
        bc = z;
    }
    if (r > t) {
        z = r;
        r = t;
        t = z;
        z = ar;
        ar = br;
        br = z;
    }
    return node('G', 0, "", reference(c, r, ac | ar), reference(d, t, bc | br));
}
static bool row_number(const char *s) {
    size_t n = strlen(s);
    return (n == 1 || n == 2) && s[0] >= '1' && s[0] <= '9' &&
           (n == 1 || (s[1] >= '0' && s[1] <= '9'));
}
static Node *address(const char *s) {
    if (strlen(s) < 2 || s[0] < 'A' || s[0] > 'Z' || !row_number(s + 1))
        fail("bad address");
    return reference(s[0] - 'A', atoi(s + 1) - 1, 0);
}
static Node *area(const char *s) {
    const char *p = strchr(s, ':');
    if (!p) {
        Node *a = address(s);
        return range(a, a);
    }
    char *first = copy_text(s, (size_t)(p - s));
    Node *a = address(first), *b = address(p + 1);
    free(first);
    return range(a, b);
}
static bool contains(Node *g, Node *r) {
    return r->n >= g->a->n && r->n <= g->b->n && r->row >= g->a->row && r->row <= g->b->row;
}
static int precedence(const char *s) {
    if (!strcmp(s, "&"))
        return 1;
    if (!strcmp(s, "+") || !strcmp(s, "-"))
        return 2;
    if (!strcmp(s, "*") || !strcmp(s, "/"))
        return 3;
    if (!strcmp(s, "=") || !strcmp(s, "<>") || !strcmp(s, "<") || !strcmp(s, "<=") ||
        !strcmp(s, ">") || !strcmp(s, ">="))
        return 0;
    return -1;
}
static Node *word_reference(const char *w) {
    int i = 0, f = 0;
    if (w[i] == '$') {
        f |= 1;
        i++;
    }
    if (w[i] < 'A' || w[i] > 'Z')
        return NULL;
    int c = w[i++] - 'A';
    if (w[i] == '$') {
        f |= 2;
        i++;
    }
    if (!row_number(w + i))
        return NULL;
    return reference(c, atoi(w + i) - 1, f);
}
static bool letter(char c) {
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
}
static void tokenize(Parser *p, const char *s) {
    size_t n = strlen(s);
    for (size_t i = 1; i < n;) {
        int pos = (int)i + 1;
        char ch = s[i];
        if (ch == ' ') {
            i++;
            continue;
        }
        Node *x;
        if (isdigit((unsigned char)ch)) {
            size_t j = i;
            while (j < n && isdigit((unsigned char)s[j]))
                j++;
            if (j - i >= 10)
                syntax(pos);
            char *w = copy_text(s + i, j - i);
            x = num(atoi(w));
            free(w);
            i = j;
        } else if (ch == '"') {
            const char *end = strchr(s + i + 1, '"');
            if (!end)
                syntax(pos);
            char *w = copy_text(s + i + 1, (size_t)(end - s - i - 1));
            x = text(w);
            free(w);
            i = (size_t)(end - s) + 1;
        } else if (letter(ch) || ch == '$') {
            size_t j = i;
            while (j < n && (letter(s[j]) || isdigit((unsigned char)s[j]) || s[j] == '$'))
                j++;
            char *w = copy_text(s + i, j - i);
            for (char *q = w; *q; q++)
                *q = (char)toupper((unsigned char)*q);
            i = j;
            x = word_reference(w);
            if (!x) {
                bool valid = w[0] >= 'A' && w[0] <= 'Z';
                for (char *q = w; *q; q++)
                    if (!(*q >= 'A' && *q <= 'Z') && !isdigit((unsigned char)*q))
                        valid = false;
                if (!valid)
                    syntax(pos);
                while (j < n && s[j] == ' ')
                    j++;
                x = node(j < n && s[j] == '(' ? 'C' : 'W', 0, w, NULL, NULL);
            }
            free(w);
        } else {
            char op[3] = {ch, 0, 0};
            if ((ch == '<' && (s[i + 1] == '>' || s[i + 1] == '=')) ||
                (ch == '>' && s[i + 1] == '='))
                op[1] = s[i + 1];
            if (!strchr("+-*/&(),:=<>", ch))
                syntax(pos);
            x = node('T', 0, op, NULL, NULL);
            i += strlen(op);
        }
        p->tokens[p->size++] = (Token){x, pos};
    }
    p->tokens[p->size++] = (Token){node('Z', 0, "", NULL, NULL), (int)n + 1};
}
static bool take(Parser *p, const char *op) {
    Node *x = p->tokens[p->at].value;
    if (x->kind == 'T' && !strcmp(x->text, op)) {
        p->at++;
        return true;
    }
    return false;
}
static void expect(Parser *p, const char *op) {
    if (!take(p, op))
        syntax(p->tokens[p->at].position);
}
static Node *expression(Parser *p, int level);
static Node *primary(Parser *p) {
    if (take(p, "-"))
        return node('U', 0, "", primary(p), NULL);
    Token t = p->tokens[p->at++];
    Node *x = t.value;
    if (x->kind == 'N' || x->kind == 'S' || x->kind == 'W')
        return x;
    if (x->kind == 'R') {
        if (!take(p, ":"))
            return x;
        if (p->tokens[p->at].value->kind != 'R')
            syntax(p->tokens[p->at].position);
        return range(x, p->tokens[p->at++].value);
    }
    if (x->kind == 'C') {
        expect(p, "(");
        Node *call = node('F', 0, x->text, NULL, NULL);
        Node *args[101];
        int count = 0;
        if (!take(p, ")")) {
            args[count++] = expression(p, 0);
            while (take(p, ","))
                args[count++] = expression(p, 0);
            expect(p, ")");
        }
        call->argc = count;
        call->args = allocate((size_t)count * sizeof *call->args);
        memcpy(call->args, args, (size_t)count * sizeof *args);
        return call;
    }
    if (x->kind == 'T' && !strcmp(x->text, "(")) {
        Node *a = expression(p, 0);
        expect(p, ")");
        return a;
    }
    syntax(t.position);
    return NULL;
}
static Node *expression(Parser *p, int level) {
    if (level == 4)
        return primary(p);
    Node *a = expression(p, level + 1);
    while (p->tokens[p->at].value->kind == 'T' &&
           precedence(p->tokens[p->at].value->text) == level) {
        char *op = p->tokens[p->at++].value->text;
        Node *b = expression(p, level + 1);
        a = node('B', 0, op, a, b);
    }
    return a;
}
static Node *parse_formula(const char *s) {
    Parser p = {0};
    tokenize(&p, s);
    Node *x = expression(&p, 0);
    if (p.tokens[p.at].value->kind != 'Z')
        syntax(p.tokens[p.at].position);
    return x;
}
static void canonical(Node *x, char *out) {
    char s[40];
    switch (x->kind) {
    case 'N':
        sprintf(s, "%d", x->n);
        strcat(out, s);
        break;
    case 'S':
        strcat(out, "\"");
        strcat(out, x->text);
        strcat(out, "\"");
        break;
    case 'W':
        strcat(out, x->text);
        break;
    case 'X':
        strcat(out, "#REF!");
        break;
    case 'R':
        sprintf(s, "%s%c%s%d", x->flags & 1 ? "$" : "", 'A' + x->n, x->flags & 2 ? "$" : "",
                x->row + 1);
        strcat(out, s);
        break;
    case 'G':
        canonical(x->a, out);
        strcat(out, ":");
        canonical(x->b, out);
        break;
    case 'F':
        strcat(out, x->text);
        strcat(out, "(");
        for (int i = 0; i < x->argc; i++) {
            if (i)
                strcat(out, ",");
            canonical(x->args[i], out);
        }
        strcat(out, ")");
        break;
    case 'U':
        strcat(out, "-");
        if (x->a->kind == 'B')
            strcat(out, "(");
        canonical(x->a, out);
        if (x->a->kind == 'B')
            strcat(out, ")");
        break;
    case 'B': {
        bool a = x->a->kind == 'B' && precedence(x->a->text) < precedence(x->text),
             b = x->b->kind == 'B' && precedence(x->b->text) <= precedence(x->text);
        if (a)
            strcat(out, "(");
        canonical(x->a, out);
        if (a)
            strcat(out, ")");
        strcat(out, x->text);
        if (b)
            strcat(out, "(");
        canonical(x->b, out);
        if (b)
            strcat(out, ")");
        break;
    }
    }
}
static void display(Node *x, char *s) {
    if (!x)
        s[0] = 0;
    else if (x->kind == 'N')
        sprintf(s, "%d", x->n);
    else
        strcpy(s, x->text);
}
static void notation(Node *x, char *s) {
    s[0] = 0;
    if (!x)
        strcpy(s, "(empty)");
    else if (x->kind == '=') {
        strcpy(s, "=");
        canonical(x->a, s);
    } else if (x->kind == 'S')
        sprintf(s, "\"%s\"", x->text);
    else
        display(x, s);
}
static Node *to_number(Node *x) {
    return !x ? num(0) : (x->kind == 'S' || x->kind == 'G') ? error_value("#VALUE!") : x;
}
static Node *to_string(Node *x) {
    if (!x)
        return text("");
    if (x->kind == 'N') {
        char s[40];
        sprintf(s, "%d", x->n);
        return text(s);
    }
    return x->kind == 'G' ? error_value("#VALUE!") : x;
}
typedef Node *(*Transform)(Node *, void *);
static Node *rewrite(Node *x, Transform f, void *context) {
    if (!x)
        return NULL;
    if (x->kind == 'R' || x->kind == 'G')
        return f(x, context);
    Node *a = rewrite(x->a, f, context), *b = rewrite(x->b, f, context);
    bool changed = a != x->a || b != x->b;
    Node **args = allocate((size_t)x->argc * sizeof *args);
    for (int i = 0; i < x->argc; i++) {
        args[i] = rewrite(x->args[i], f, context);
        changed |= args[i] != x->args[i];
    }
    if (!changed) {
        free(args);
        return x;
    }
    Node *v = node(x->kind, x->n, x->text, a, b);
    v->args = args;
    v->argc = x->argc;
    return v;
}
static void dependencies(Node *x, bool *out) {
    if (!x)
        return;
    if (x->kind == 'R')
        out[id(x)] = true;
    else if (x->kind == 'G') {
        for (int r = x->a->row; r <= x->b->row; r++)
            for (int c = x->a->n; c <= x->b->n; c++)
                out[r * 26 + c] = true;
    } else {
        dependencies(x->a, out);
        dependencies(x->b, out);
        for (int i = 0; i < x->argc; i++)
            dependencies(x->args[i], out);
    }
}
static Node *evaluate(Sheet *s, Node *x);
static Node *aggregate(Sheet *s, Node *x) {
    if (!x->argc)
        return error_value("#VALUE!");
    int count = 0, lo = 0, hi = 0;
    long long sum = 0;
    bool all = true, any = false;
    char joined[101] = "";
    for (int a = 0; a < x->argc; a++) {
        Node *v = evaluate(s, x->args[a]);
        int r1 = 0, r2 = 0, c1 = 0, c2 = 0;
        if (v && v->kind == 'G') {
            r1 = v->a->row;
            r2 = v->b->row;
            c1 = v->a->n;
            c2 = v->b->n;
        }
        for (int r = r1; r <= r2; r++)
            for (int c = c1; c <= c2; c++) {
                Node *item = v && v->kind == 'G' ? s->values[r * 26 + c] : v;
                if (item && item->kind == 'E') {
                    if (strcmp(x->text, "COUNT"))
                        return item;
                    continue;
                }
                if (item && item->kind == 'N') {
                    int n = item->n;
                    if (!count || n < lo)
                        lo = n;
                    if (!count || n > hi)
                        hi = n;
                    count++;
                    sum += n;
                    all = all && n != 0;
                    any = any || n != 0;
                }
                if (!strcmp(x->text, "CONCAT")) {
                    Node *t = to_string(item);
                    strcat(joined, t->text);
                }
            }
    }
    const char *name = x->text;
    if (!strcmp(name, "COUNT"))
        return num(count);
    if (!strcmp(name, "CONCAT"))
        return text(joined);
    if (!strcmp(name, "SUM"))
        return num((int)sum);
    if (!strcmp(name, "MIN"))
        return num(lo);
    if (!strcmp(name, "MAX"))
        return num(hi);
    if (!count)
        return error_value(!strcmp(name, "AVERAGE") ? "#DIV/0!" : "#VALUE!");
    if (!strcmp(name, "AVERAGE"))
        return num((int)(sum / count));
    return num(!strcmp(name, "AND") ? all : any);
}
static Node *evaluate(Sheet *s, Node *x) {
    if (x->kind == 'N' || x->kind == 'S' || x->kind == 'G')
        return x;
    if (x->kind == 'R')
        return s->values[id(x)];
    if (x->kind == 'W')
        return error_value("#NAME?");
    if (x->kind == 'X')
        return error_value("#REF!");
    if (x->kind == 'U') {
        Node *a = to_number(evaluate(s, x->a));
        return a->kind == 'E' ? a : num(-a->n);
    }
    if (x->kind == 'B') {
        Node *a = evaluate(s, x->a);
        Node *b = evaluate(s, x->b);
        const char *op = x->text;
        if (a && a->kind == 'E')
            return a;
        if (b && b->kind == 'E')
            return b;
        if (precedence(op) == 0) {
            if ((a && a->kind == 'G') || (b && b->kind == 'G'))
                return error_value("#VALUE!");
            bool strings = (a && a->kind == 'S') || (b && b->kind == 'S');
            if (!a)
                a = strings ? text("") : num(0);
            if (!b)
                b = strings ? text("") : num(0);
            int c = a->kind != b->kind ? (a->kind == 'N' ? -1 : 1)
                    : a->kind == 'N'   ? (a->n > b->n) - (a->n < b->n)
                                       : strcmp(a->text, b->text);
            return num(!strcmp(op, "=")    ? c == 0
                       : !strcmp(op, "<>") ? c != 0
                       : !strcmp(op, "<")  ? c < 0
                       : !strcmp(op, "<=") ? c <= 0
                       : !strcmp(op, ">")  ? c > 0
                                           : c >= 0);
        }
        a = !strcmp(op, "&") ? to_string(a) : to_number(a);
        b = !strcmp(op, "&") ? to_string(b) : to_number(b);
        if (a->kind == 'E')
            return a;
        if (b->kind == 'E')
            return b;
        if (!strcmp(op, "&")) {
            char joined[101];
            strcpy(joined, a->text);
            strcat(joined, b->text);
            return text(joined);
        }
        if (!strcmp(op, "+"))
            return num(a->n + b->n);
        if (!strcmp(op, "-"))
            return num(a->n - b->n);
        if (!strcmp(op, "*"))
            return num(a->n * b->n);
        return b->n ? num(a->n / b->n) : error_value("#DIV/0!");
    }
    const char *name = x->text;
    const char *names[] = {"SUM", "MIN", "MAX", "COUNT", "AVERAGE", "AND", "OR", "CONCAT"};
    for (int i = 0; i < 8; i++)
        if (!strcmp(name, names[i]))
            return aggregate(s, x);
    if (!strcmp(name, "IF")) {
        if (x->argc != 2 && x->argc != 3)
            return error_value("#VALUE!");
        Node *c = to_number(evaluate(s, x->args[0]));
        if (c->kind == 'E')
            return c;
        return c->n ? evaluate(s, x->args[1]) : x->argc == 3 ? evaluate(s, x->args[2]) : num(0);
    }
    if (strcmp(name, "ABS") && strcmp(name, "NOT") && strcmp(name, "LEN"))
        return error_value("#NAME?");
    if (x->argc != 1)
        return error_value("#VALUE!");
    Node *v = evaluate(s, x->args[0]);
    v = !strcmp(name, "LEN") ? to_string(v) : to_number(v);
    return v->kind == 'E' ? v
                          : num(!strcmp(name, "LEN")   ? (int)strlen(v->text)
                                : !strcmp(name, "ABS") ? abs(v->n)
                                                       : v->n == 0);
}
static void visit(Sheet *s, int i) {
    s->indices[i] = s->low[i] = s->serial++;
    s->stack[s->stack_size++] = i;
    s->on[i] = true;
    for (int k = 0; k < s->counts[i]; k++) {
        int j = s->deps[i][k];
        if (s->contents[j] && s->contents[j]->kind == '=') {
            if (s->indices[j] < 0) {
                visit(s, j);
                if (s->low[j] < s->low[i])
                    s->low[i] = s->low[j];
            } else if (s->on[j] && s->indices[j] < s->low[i])
                s->low[i] = s->indices[j];
        }
    }
    if (s->low[i] == s->indices[i]) {
        int part[200], count = 0, j;
        do {
            j = s->stack[--s->stack_size];
            s->on[j] = false;
            part[count++] = j;
        } while (j != i);
        bool self = false;
        for (int k = 0; k < s->counts[i]; k++)
            self |= s->deps[i][k] == i;
        if (count > 1 || self)
            for (int k = 0; k < count; k++)
                s->cyclic[part[k]] = true;
    }
}
static void calculate(Sheet *s, int i) {
    if (!s->contents[i] || s->contents[i]->kind != '=' || s->done[i])
        return;
    s->done[i] = true;
    if (s->cyclic[i]) {
        s->values[i] = error_value("#CYCLE!");
        return;
    }
    for (int k = 0; k < s->counts[i]; k++)
        calculate(s, s->deps[i][k]);
    Node *v = evaluate(s, s->contents[i]->a);
    s->values[i] = !v ? num(0) : v->kind == 'G' ? error_value("#VALUE!") : v;
}
static int replace(Sheet *s, Node **next) {
    Allocation *old_allocations = value_allocations;
    value_allocations = NULL;
    Node *old[2574];
    memcpy(old, s->values, sizeof old);
    memcpy(s->contents, next, sizeof s->contents);
    s->serial = s->stack_size = 0;
    memset(s->on, 0, sizeof s->on);
    memset(s->cyclic, 0, sizeof s->cyclic);
    memset(s->done, 0, sizeof s->done);
    for (int i = 0; i < 2574; i++) {
        free(s->deps[i]);
        s->deps[i] = NULL;
        s->counts[i] = 0;
        s->indices[i] = -1;
        Node *x = s->contents[i];
        if (x && x->kind == '=') {
            bool found[2574] = {0};
            dependencies(x->a, found);
            for (int j = 0; j < 2574; j++)
                if (found[j])
                    s->counts[i]++;
            s->deps[i] = allocate((size_t)s->counts[i] * sizeof(int));
            int k = 0;
            for (int j = 0; j < 2574; j++)
                if (found[j])
                    s->deps[i][k++] = j;
            s->values[i] = NULL;
        } else
            s->values[i] = x;
    }
    for (int i = 0; i < 2574; i++)
        if (s->contents[i] && s->contents[i]->kind == '=' && s->indices[i] < 0)
            visit(s, i);
    evaluating = true;
    for (int i = 0; i < 2574; i++)
        calculate(s, i);
    evaluating = false;
    int changed = 0;
    for (int i = 0; i < 2574; i++) {
        Node *a = old[i], *b = s->values[i];
        if (!a || !b) {
            changed += a != b;
            continue;
        }
        changed +=
            a->kind != b->kind || (a->kind == 'N' ? a->n != b->n : strcmp(a->text, b->text) != 0);
    }
    release_values(old_allocations);
    return changed;
}
static void describe(Sheet *s, int i) {
    char a[8], c[4096], v[104];
    label(i, a);
    notation(s->contents[i], c);
    notation(s->values[i], v);
    printf("%s: %s -> %s\n", a, c, v);
}
static void print_ids(bool *found) {
    bool any = false;
    for (int i = 0; i < 2574; i++)
        if (found[i]) {
            char a[8];
            label(i, a);
            printf("%s%s", any ? "," : "", a);
            any = true;
        }
    if (!any)
        printf("none");
}
typedef struct {
    bool copy;
    Node *source, *destination;
    int dc, dr;
} Transfer;
static Node *shift(Node *r, Transfer *t, bool relative) {
    return reference(r->n + (relative && (r->flags & 1) ? 0 : t->dc),
                     r->row + (relative && (r->flags & 2) ? 0 : t->dr), r->flags);
}
static Node *transfer_ref(Node *x, void *context) {
    Transfer *t = context;
    if (x->kind == 'R') {
        if (t->copy) {
            Node *r = shift(x, t, true);
            return inside(r) ? r : invalid;
        }
        return contains(t->source, x)        ? shift(x, t, false)
               : contains(t->destination, x) ? invalid
                                             : x;
    }
    if (!t->copy && !(contains(t->source, x->a) && contains(t->source, x->b)))
        return x;
    Node *a = shift(x->a, t, t->copy), *b = shift(x->b, t, t->copy);
    return inside(a) && inside(b) ? range(a, b) : invalid;
}
typedef struct {
    bool row, insert;
    int at, limit;
} Lines;
static int axis(Node *x, Lines *t) {
    return t->row ? x->row : x->n;
}
static Node *change(Node *x, int v, Lines *t) {
    return reference(t->row ? x->n : v, t->row ? v : x->row, x->flags);
}
static Node *line_ref(Node *x, void *context) {
    Lines *t = context;
    if (x->kind == 'R') {
        int v = axis(x, t);
        if (!t->insert && v == t->at)
            return invalid;
        int n = v + (t->insert ? (v >= t->at) : -(v > t->at));
        return n >= t->limit ? invalid : change(x, n, t);
    }
    int a = axis(x->a, t), b = axis(x->b, t);
    if (!t->insert && a == t->at && b == t->at)
        return invalid;
    int u = a + (t->insert ? (a >= t->at) : -(a > t->at)),
        v = b + (t->insert ? (b >= t->at) : -(b >= t->at));
    return v >= t->limit ? invalid : range(change(x->a, u, t), change(x->b, v, t));
}
static bool valid_integer(const char *s) {
    if (!strcmp(s, "0"))
        return true;
    size_t i = s[0] == '-' ? 1 : 0, n = strlen(s);
    if (n <= i || n - i > 9 || s[i] < '1' || s[i] > '9')
        return false;
    for (i++; i < n; i++)
        if (!isdigit((unsigned char)s[i]))
            return false;
    return true;
}
static void execute(Sheet *s, char *line) {
    char *rest = strchr(line, ' ');
    if (rest)
        *rest++ = 0;
    else
        rest = line + strlen(line);
    char *name = line;
    if (!strcmp(name, "SHOW")) {
        describe(s, id(address(rest)));
        return;
    }
    if (!strcmp(name, "LIST")) {
        bool any = false;
        for (int i = 0; i < 2574; i++)
            if (s->contents[i]) {
                describe(s, i);
                any = true;
            }
        if (!any)
            puts("(no cells)");
        return;
    }
    if (!strcmp(name, "DEPS")) {
        int i = id(address(rest));
        bool ps[2574] = {0}, ds[2574] = {0};
        for (int k = 0; k < s->counts[i]; k++)
            ps[s->deps[i][k]] = true;
        for (int j = 0; j < 2574; j++)
            for (int k = 0; k < s->counts[j]; k++)
                if (s->deps[j][k] == i)
                    ds[j] = true;
        printf("%s: precedents=", rest);
        print_ids(ps);
        printf(" dependents=");
        print_ids(ds);
        putchar('\n');
        return;
    }
    if (!strcmp(name, "PRINT")) {
        Node *g = area(rest);
        int rw = g->b->row + 1 >= 10 ? 2 : 1, widths[26], cols = g->b->n - g->a->n + 1;
        char sep[4096] = "+", head[4096] = "|", value[104];
        for (int j = 0; j < rw; j++) {
            strcat(sep, "-");
            strcat(head, " ");
        }
        strcat(sep, "+");
        strcat(head, "|");
        for (int j = 0; j < cols; j++) {
            int c = g->a->n + j, w = 1;
            for (int r = g->a->row; r <= g->b->row; r++) {
                display(s->values[r * 26 + c], value);
                if ((int)strlen(value) > w)
                    w = (int)strlen(value);
            }
            widths[j] = w;
            for (int k = 0; k < w; k++)
                strcat(sep, "-");
            strcat(sep, "+");
            size_t len = strlen(head);
            head[len] = (char)('A' + c);
            head[len + 1] = 0;
            for (int k = 1; k < w; k++)
                strcat(head, " ");
            strcat(head, "|");
        }
        puts(sep);
        puts(head);
        puts(sep);
        for (int r = g->a->row; r <= g->b->row; r++) {
            printf("|%*d|", rw, r + 1);
            for (int j = 0; j < cols; j++) {
                Node *v = s->values[r * 26 + g->a->n + j];
                display(v, value);
                if (v && v->kind == 'N')
                    printf("%*s|", widths[j], value);
                else
                    printf("%-*s|", widths[j], value);
            }
            putchar('\n');
        }
        puts(sep);
        return;
    }
    if (!strcmp(name, "UNDO")) {
        if (!s->history_size)
            fail("nothing to undo");
        History h = s->history[--s->history_size];
        int count = replace(s, h.contents);
        free(h.contents);
        printf("UNDO %s changed=%d\n", h.name, count);
        return;
    }
    Node *next[2574];
    memcpy(next, s->contents, sizeof next);
    int target = -1;
    if (!strcmp(name, "SET")) {
        char *v = strchr(rest, ' ');
        *v++ = 0;
        target = id(address(rest));
        size_t n = strlen(v);
        if (v[0] == '=')
            next[target] = node('=', 0, "", parse_formula(v), NULL);
        else if (n >= 2 && v[0] == '"' && v[n - 1] == '"' && !memchr(v + 1, '"', n - 2)) {
            char *w = copy_text(v + 1, n - 2);
            next[target] = text(w);
            free(w);
        } else if (valid_integer(v))
            next[target] = num(atoi(v));
        else
            fail("bad value");
    } else if (!strcmp(name, "CLEAR")) {
        Node *g = area(rest);
        for (int r = g->a->row; r <= g->b->row; r++)
            for (int c = g->a->n; c <= g->b->n; c++)
                next[r * 26 + c] = NULL;
    } else if (!strcmp(name, "COPY") || !strcmp(name, "MOVE")) {
        char *b = strchr(rest, ' ');
        *b++ = 0;
        Node *source = area(rest), *dest = address(b);
        Transfer t = {!strcmp(name, "COPY"), source, NULL, dest->n - source->a->n,
                      dest->row - source->a->row};
        t.destination = range(shift(source->a, &t, false), shift(source->b, &t, false));
        if (!inside(t.destination->a) || !inside(t.destination->b))
            fail("out of grid");
        if (!t.copy)
            for (int i = 0; i < 2574; i++)
                next[i] = rewrite(next[i], transfer_ref, &t);
        Node *moving[2574];
        memcpy(moving, next, sizeof moving);
        if (!t.copy)
            for (int r = source->a->row; r <= source->b->row; r++)
                for (int c = source->a->n; c <= source->b->n; c++)
                    next[r * 26 + c] = NULL;
        for (int r = source->a->row; r <= source->b->row; r++)
            for (int c = source->a->n; c <= source->b->n; c++) {
                int i = r * 26 + c;
                next[i + t.dr * 26 + t.dc] =
                    t.copy ? rewrite(s->contents[i], transfer_ref, &t) : moving[i];
            }
    } else if (!strcmp(name, "INSERTROW") || !strcmp(name, "DELETEROW") ||
               !strcmp(name, "INSERTCOL") || !strcmp(name, "DELETECOL")) {
        bool row = strstr(name, "ROW") != NULL, insert = !strncmp(name, "INSERT", 6);
        if (row ? !row_number(rest) : !(strlen(rest) == 1 && rest[0] >= 'A' && rest[0] <= 'Z'))
            fail("bad address");
        Lines t = {row, insert, row ? atoi(rest) - 1 : rest[0] - 'A', row ? 99 : 26};
        if (insert)
            for (int i = 0; i < 2574; i++)
                if (s->contents[i] && (row ? i / 26 : i % 26) == t.limit - 1)
                    fail(row ? "last row not empty" : "last column not empty");
        memset(next, 0, sizeof next);
        for (int i = 0; i < 2574; i++)
            if (s->contents[i]) {
                Node *r = reference(i % 26, i / 26, 0);
                int v = axis(r, &t);
                if (!insert && v == t.at)
                    continue;
                Node *u = change(r, v + (insert ? (v >= t.at) : -(v > t.at)), &t);
                next[id(u)] = rewrite(s->contents[i], line_ref, &t);
            }
    } else
        fail("unknown command");
    History *h = &s->history[s->history_size++];
    strcpy(h->name, name);
    h->contents = allocate(sizeof s->contents);
    memcpy(h->contents, s->contents, sizeof s->contents);
    int count = replace(s, next);
    printf("%s", name);
    if (target >= 0) {
        char a[8], v[104];
        label(target, a);
        notation(s->values[target], v);
        printf(" %s=%s", a, v);
    }
    printf(" changed=%d\n", count);
}
int main(void) {
    char line[512];
    if (!fgets(line, sizeof line, stdin))
        return 0;
    int n = atoi(line);
    Sheet *sheet = allocate(sizeof *sheet);
    for (int i = 0; i < n && fgets(line, sizeof line, stdin); i++) {
        line[strcspn(line, "\r\n")] = 0;
        if (!setjmp(command_jump))
            execute(sheet, line);
        else
            printf("ERROR %s\n", problem);
    }
    return 0;
}
