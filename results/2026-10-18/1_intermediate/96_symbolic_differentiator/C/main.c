#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <math.h>
#include <setjmp.h>
#include <stdarg.h>

#define MAX_CHILDREN 2048
#define MAX_TOKENS 256
#define MAX_TEXT 8192

enum { VARIABLE, SUM, PRODUCT, POWER, FUNCTION, NUMBER };

typedef struct Node Node;
struct Node {
    int kind;
    int length;
    long long p;
    long long q;
    char *name;
    Node **children;
};

typedef struct {
    long long p;
    long long q;
    int length;
    Node **parts;
} Term;

typedef struct {
    Node *base;
    Node *original;
    Node *exponent;
    int count;
} FactorGroup;

typedef struct {
    char name[202];
    Node *expression;
} Definition;

static Definition definitions[1000];
static int definitions_count;
static char tokens[MAX_TOKENS][202];
static int tokens_count, token_position;
static char failure[256];
static jmp_buf recovery;
static Node *zero, *one, *minus_one, *half;

static void errorf(const char *format, ...) {
    va_list args;
    va_start(args, format);
    vsnprintf(failure, sizeof(failure), format, args);
    va_end(args);
    longjmp(recovery, 1);
}

static long long gcd_ll(long long a, long long b) {
    a = llabs(a);
    b = llabs(b);
    while (b) {
        long long t = a % b;
        a = b;
        b = t;
    }
    return a ? a : 1;
}

static void fraction(long long *p, long long *q) {
    if (!*q) errorf("division by zero");
    if (*q < 0) *p = -*p, *q = -*q;
    long long g = gcd_ll(*p, *q);
    *p /= g;
    *q /= g;
}

static Node *make_node(int kind, int length, Node **children, const char *name) {
    Node *result = malloc(sizeof(*result));
    result->kind = kind;
    result->length = length;
    result->p = 0;
    result->q = 1;
    result->name = NULL;
    result->children = NULL;
    if (length) {
        result->children = malloc((size_t)length * sizeof(Node *));
        memcpy(result->children, children, (size_t)length * sizeof(Node *));
    }
    if (name) {
        result->name = malloc(strlen(name) + 1);
        strcpy(result->name, name);
    }
    return result;
}

static Node *number(long long p, long long q) {
    fraction(&p, &q);
    Node *result = make_node(NUMBER, 0, NULL, NULL);
    result->p = p;
    result->q = q;
    return result;
}

static Node *integer(long long p) {
    return number(p, 1);
}

static Node *variable(const char *name) {
    return make_node(VARIABLE, 0, NULL, name);
}

static Node *function_node(const char *name, Node *arg) {
    Node *children[] = {arg};
    return make_node(FUNCTION, 1, children, name);
}

static Node *power_node(Node *base, Node *exponent) {
    Node *children[] = {base, exponent};
    return make_node(POWER, 2, children, NULL);
}

static int compare(const Node *left, const Node *right) {
    if (left == right) return 0;
    if (left->kind != right->kind) return left->kind < right->kind ? -1 : 1;
    if (left->kind == NUMBER) {
        long long a = left->p * right->q, b = right->p * left->q;
        return (a > b) - (a < b);
    }
    if (left->kind == VARIABLE || left->kind == FUNCTION) {
        int c = strcmp(left->name, right->name);
        if (c) return (c > 0) - (c < 0);
    }
    int len = left->length < right->length ? left->length : right->length;
    for (int i = 0; i < len; ++i) {
        int c = compare(left->children[i], right->children[i]);
        if (c) return c;
    }
    return (left->length > right->length) - (left->length < right->length);
}

static int equal(const Node *a, const Node *b) {
    return compare(a, b) == 0;
}

static int is_integer(const Node *f) {
    return f->kind == NUMBER && f->q == 1;
}

static Node *base(Node *f) {
    return f->kind == POWER ? f->children[0] : f;
}

static Node *exponent(Node *f) {
    return f->kind == POWER ? f->children[1] : one;
}

static Term coefficient(Node *f) {
    Term t;
    t.p = 1;
    t.q = 1;
    t.length = 0;
    t.parts = NULL;
    if (f->kind == NUMBER) {
        t.p = f->p;
        t.q = f->q;
    } else if (f->kind == PRODUCT) {
        t.parts = f->children;
        t.length = f->length;
        if (f->children[0]->kind == NUMBER) {
            t.p = f->children[0]->p;
            t.q = f->children[0]->q;
            ++t.parts;
            --t.length;
        }
    } else {
        t.parts = malloc(sizeof(Node *));
        t.parts[0] = f;
        t.length = 1;
    }
    return t;
}

static Node *add(int count, Node **args);
static Node *multiply(int count, Node **args);
static Node *power(Node *a, Node *b);
static Node *function(const char *name, Node *arg);

static Node *add_two(Node *a, Node *b) {
    Node *args[] = {a, b};
    return add(2, args);
}

static Node *multiply_two(Node *a, Node *b) {
    Node *args[] = {a, b};
    return multiply(2, args);
}

static Node *multiply_three(Node *a, Node *b, Node *c) {
    Node *args[] = {a, b, c};
    return multiply(3, args);
}

static void mul_fraction(long long *p, long long *q, long long a, long long b) {
    *p *= a;
    *q *= b;
    fraction(p, q);
}

static void add_fraction(long long *p, long long *q, long long a, long long b) {
    *p = *p * b + a * *q;
    *q *= b;
    fraction(p, q);
}

static int monomial_equal(const Term *a, const Term *b) {
    if (a->length != b->length) return 0;
    for (int i = 0; i < a->length; ++i) if (!equal(a->parts[i], b->parts[i])) return 0;
    return 1;
}

static Node *build_product(long long p, long long q, int count, Node **args) {
    if (!p) return zero;
    if (!count) return number(p, q);
    if (p == q && count == 1) return args[0];
    Node *all[MAX_CHILDREN];
    int n = 0;
    if (p != q) all[n++] = number(p, q);
    for (int i = 0; i < count; ++i) all[n++] = args[i];
    return make_node(PRODUCT, n, all, NULL);
}

static void flatten_add(Node *f, Node **terms, int *count) {
    if (f->kind == SUM) {
        for (int i = 0; i < f->length; ++i) terms[(*count)++] = f->children[i];
    } else if (f->kind == PRODUCT && f->length == 2 && f->children[0]->kind == NUMBER && f->children[1]->kind == SUM) {
        for (int i = 0; i < f->children[1]->length; ++i) {
            terms[(*count)++] = multiply_two(f->children[0], f->children[1]->children[i]);
        }
    } else {
        terms[(*count)++] = f;
    }
}

static int exponent_compare(Node *a, Node *b) {
    if (a->kind == NUMBER && b->kind != NUMBER) return -1;
    if (a->kind != NUMBER && b->kind == NUMBER) return 1;
    return compare(a, b);
}

static int term_compare(const void *ap, const void *bp) {
    const Node *a = *(Node *const *)ap, *b = *(Node *const *)bp;
    Term at = coefficient((Node *)a), bt = coefficient((Node *)b);
    Node *bases[MAX_CHILDREN * 2];
    int count = 0;
    for (int i = 0; i < at.length; ++i) {
        Node *candidate = base(at.parts[i]);
        int found = 0;
        for (int j = 0; j < count; ++j) found |= equal(candidate, bases[j]);
        if (!found) bases[count++] = candidate;
    }
    for (int i = 0; i < bt.length; ++i) {
        Node *candidate = base(bt.parts[i]);
        int found = 0;
        for (int j = 0; j < count; ++j) found |= equal(candidate, bases[j]);
        if (!found) bases[count++] = candidate;
    }
    for (int i = 1; i < count; ++i) {
        Node *current = bases[i];
        int j = i;
        while (j > 0 && compare(bases[j - 1], current) > 0) bases[j] = bases[j - 1], --j;
        bases[j] = current;
    }
    for (int i = 0; i < count; ++i) {
        Node *ax = zero, *bx = zero;
        for (int j = 0; j < at.length; ++j) if (equal(base(at.parts[j]), bases[i])) ax = exponent(at.parts[j]);
        for (int j = 0; j < bt.length; ++j) if (equal(base(bt.parts[j]), bases[i])) bx = exponent(bt.parts[j]);
        int c = exponent_compare(bx, ax);
        if (c) return c;
    }
    return 0;
}

static Node *add(int count, Node **args) {
    Node *terms[MAX_CHILDREN];
    int term_count = 0;
    for (int i = 0; i < count; ++i) flatten_add(args[i], terms, &term_count);
    Term groups[MAX_CHILDREN];
    int group_count = 0;
    for (int i = 0; i < term_count; ++i) {
        Term next = coefficient(terms[i]);
        int index = -1;
        for (int j = 0; j < group_count; ++j) if (monomial_equal(&next, &groups[j])) {index = j; break;}
        if (index < 0) groups[group_count++] = next;
        else add_fraction(&groups[index].p, &groups[index].q, next.p, next.q);
    }
    Node *built[MAX_CHILDREN];
    int length = 0;
    for (int i = 0; i < group_count; ++i) {
        if (groups[i].p) built[length++] = build_product(groups[i].p, groups[i].q, groups[i].length, groups[i].parts);
    }
    qsort(built, (size_t)length, sizeof(Node *), term_compare);
    if (!length) return zero;
    if (length == 1) return built[0];
    return make_node(SUM, length, built, NULL);
}

static int compare_bases(const void *a, const void *b) {
    Node *aa = *(Node *const *)a, *bb = *(Node *const *)b;
    return compare(base(aa), base(bb));
}

static void flatten_multiply(Node *f, Node **items, int *count) {
    if (f->kind == PRODUCT) {
        for (int i = 0; i < f->length; ++i) items[(*count)++] = f->children[i];
    } else items[(*count)++] = f;
}

static Node *multiply(int count, Node **args) {
    Node *factors[MAX_CHILDREN];
    int factor_count = 0;
    for (int i = 0; i < count; ++i) flatten_multiply(args[i], factors, &factor_count);
    long long p = 1, q = 1;
    FactorGroup groups[MAX_CHILDREN];
    int group_count = 0;
    for (int i = 0; i < factor_count; ++i) {
        Node *f = factors[i];
        if (f->kind == NUMBER) {
            mul_fraction(&p, &q, f->p, f->q);
            continue;
        }
        Node *b = base(f);
        int index = -1;
        for (int j = 0; j < group_count; ++j) if (equal(groups[j].base, b)) {index = j; break;}
        if (index < 0) {
            groups[group_count].base = b;
            groups[group_count].original = f;
            groups[group_count].exponent = exponent(f);
            groups[group_count].count = 1;
            ++group_count;
        } else {
            groups[index].exponent = add_two(groups[index].exponent, exponent(f));
            ++groups[index].count;
        }
    }
    if (!p) return zero;
    Node *built[MAX_CHILDREN];
    for (int i = 0; i < group_count; ++i) {
        built[i] = groups[i].count == 1 ? groups[i].original : power(groups[i].base, groups[i].exponent);
    }
    int retry = 0;
    for (int i = 0; i < group_count; ++i) {
        if (built[i]->kind == NUMBER || built[i]->kind == PRODUCT) retry = 1;
        for (int j = 0; j < i; ++j) if (equal(base(built[i]), base(built[j]))) retry = 1;
    }
    if (retry) {
        Node *again[MAX_CHILDREN];
        again[0] = number(p, q);
        for (int i = 0; i < group_count; ++i) again[i + 1] = built[i];
        return multiply(group_count + 1, again);
    }
    qsort(built, (size_t)group_count, sizeof(Node *), compare_bases);
    return build_product(p, q, group_count, built);
}

static long long integer_root(long long value, long long degree) {
    if (value == 1) return 1;
    if (degree > 20) return -1;
    long long rounded = llround(pow((double)value, 1.0 / (double)degree));
    for (long long r = rounded > 0 ? rounded - 1 : 0; r <= rounded + 1; ++r) {
        long long total = 1;
        for (long long i = 0; i < degree; ++i) {
            if (r && total > value / r) {total = value + 1; break;}
            total *= r;
        }
        if (total == value) return r;
    }
    return -1;
}

static Node *rational_power(long long p, long long q, long long exp) {
    if (exp < 0) {
        long long t = p;
        p = q;
        q = t;
        exp = -exp;
    }
    long long a = 1, b = 1;
    while (exp) {
        if (exp % 2) mul_fraction(&a, &b, p, q);
        exp /= 2;
        if (exp) mul_fraction(&p, &q, p, q);
    }
    return number(a, b);
}

static Node *power(Node *b, Node *x) {
    if (equal(x, zero)) return one;
    if (equal(x, one)) return b;
    if (b->kind == NUMBER) {
        if (equal(b, one)) return one;
        if (x->kind != NUMBER) return power_node(b, x);
        if (!b->p) {
            if (x->p > 0) return zero;
            errorf("division by zero");
        }
        if (is_integer(x)) return rational_power(b->p, b->q, x->p);
        if (b->p > 0) {
            long long a = integer_root(b->p, x->q);
            long long c = integer_root(b->q, x->q);
            if (a >= 0 && c >= 0) return rational_power(a, c, x->p);
        }
    } else if (is_integer(x)) {
        if (b->kind == POWER) return power(b->children[0], multiply_two(b->children[1], x));
        if (b->kind == PRODUCT) {
            Node *parts[MAX_CHILDREN];
            for (int i = 0; i < b->length; ++i) parts[i] = power(b->children[i], x);
            return multiply(b->length, parts);
        }
    }
    return power_node(b, x);
}

static Node *function(const char *name, Node *arg) {
    if (!strcmp(name, "sqrt")) return power(arg, half);
    if (equal(arg, zero)) {
        if (!strcmp(name, "sin") || !strcmp(name, "tan")) return zero;
        if (!strcmp(name, "cos") || !strcmp(name, "exp")) return one;
    }
    if (!strcmp(name, "ln") && equal(arg, one)) return zero;
    if (!strcmp(name, "sin") || !strcmp(name, "cos") || !strcmp(name, "tan")) {
        Term c = coefficient(arg);
        if (c.p < 0) {
            Node *f = function(name, multiply_two(minus_one, arg));
            return !strcmp(name, "cos") ? f : multiply_two(minus_one, f);
        }
    }
    if (arg->kind == FUNCTION) {
        if ((!strcmp(name, "ln") && !strcmp(arg->name, "exp")) ||
            (!strcmp(name, "exp") && !strcmp(arg->name, "ln"))) return arg->children[0];
    }
    return function_node(name, arg);
}

static int variable_name(const char *name) {
    if (!islower((unsigned char)*name)) return 0;
    for (const char *p = name + 1; *p; ++p) if (!islower((unsigned char)*p) && !isdigit((unsigned char)*p)) return 0;
    static const char *const banned[] = {"sin","cos","tan","exp","ln","sqrt"};
    for (int i = 0; i < 6; ++i) if (!strcmp(name, banned[i])) return 0;
    return 1;
}

static int definition_name(const char *name) {
    if (!isupper((unsigned char)*name)) return 0;
    for (const char *p = name + 1; *p; ++p) if (!isupper((unsigned char)*p) && !isdigit((unsigned char)*p)) return 0;
    return 1;
}

static Node *definition(const char *name) {
    for (int i = 0; i < definitions_count; ++i) if (!strcmp(definitions[i].name, name)) return definitions[i].expression;
    return NULL;
}

static void tokenize(const char *text) {
    tokens_count = token_position = 0;
    for (int i = 0; text[i];) {
        if (text[i] == ' ') {++i; continue;}
        int begin = i;
        if (isdigit((unsigned char)text[i])) while (isdigit((unsigned char)text[i])) ++i;
        else if (islower((unsigned char)text[i])) while (islower((unsigned char)text[i]) || isdigit((unsigned char)text[i])) ++i;
        else if (isupper((unsigned char)text[i])) while (isupper((unsigned char)text[i]) || isdigit((unsigned char)text[i])) ++i;
        else if (strchr("+-*/^()", text[i])) ++i;
        else errorf("invalid character '%c'", text[i]);
        int length = i - begin;
        memcpy(tokens[tokens_count], text + begin, (size_t)length);
        tokens[tokens_count][length] = '\0';
        ++tokens_count;
    }
}

static const char *peek(void) {
    return token_position == tokens_count ? "" : tokens[token_position];
}

static void unexpected(void) {
    if (token_position == tokens_count) errorf("unexpected end of expression");
    errorf("unexpected '%s'", peek());
}

static int accept(const char *text) {
    if (strcmp(peek(), text)) return 0;
    ++token_position;
    return 1;
}

static void expect(const char *text) {
    if (!accept(text)) unexpected();
}

static Node *parse_expression(void);
static Node *parse_unary(void);

static Node *parse_atom(void) {
    if (accept("(")) {
        Node *f = parse_expression();
        expect(")");
        return f;
    }
    const char *text = peek();
    if (!text[0] || !isalnum((unsigned char)text[0])) unexpected();
    ++token_position;
    if (isdigit((unsigned char)text[0])) return integer(atoll(text));
    if (isupper((unsigned char)text[0])) {
        Node *f = definition(text);
        if (!f) errorf("undefined name '%s'", text);
        return f;
    }
    if (variable_name(text)) return variable(text);
    expect("(");
    Node *inner = parse_expression();
    expect(")");
    return function(text, inner);
}

static Node *parse_unary(void) {
    if (accept("-")) return multiply_two(minus_one, parse_unary());
    Node *left = parse_atom();
    if (accept("^")) return power(left, parse_unary());
    return left;
}

static Node *parse_term(void) {
    Node *left = parse_unary();
    while (!strcmp(peek(), "*") || !strcmp(peek(), "/")) {
        int div = accept("/");
        if (!div) expect("*");
        Node *right = parse_unary();
        left = div ? multiply_two(left, power(right, minus_one)) : multiply_two(left, right);
    }
    return left;
}

static Node *parse_expression(void) {
    Node *left = parse_term();
    while (!strcmp(peek(), "+") || !strcmp(peek(), "-")) {
        int subtraction = accept("-");
        if (!subtraction) expect("+");
        Node *right = parse_term();
        left = add_two(left, subtraction ? multiply_two(minus_one, right) : right);
    }
    return left;
}

static Node *parse(const char *text) {
    tokenize(text);
    Node *result = parse_expression();
    if (token_position != tokens_count) unexpected();
    return result;
}

static void gather_variables(Node *f, char names[MAX_CHILDREN][202], int *count) {
    if (f->kind == VARIABLE) {
        for (int i = 0; i < *count; ++i) if (!strcmp(names[i], f->name)) return;
        strcpy(names[(*count)++], f->name);
    }
    for (int i = 0; i < f->length; ++i) gather_variables(f->children[i], names, count);
}

static int sort_names(const void *a, const void *b) {
    return strcmp((const char *)a, (const char *)b);
}

static int variables(Node *f, char names[MAX_CHILDREN][202]) {
    int count = 0;
    gather_variables(f, names, &count);
    qsort(names, (size_t)count, sizeof(names[0]), sort_names);
    return count;
}

static int contains_variable(Node *f, const char *name) {
    if (f->kind == VARIABLE && !strcmp(f->name, name)) return 1;
    for (int i = 0; i < f->length; ++i) if (contains_variable(f->children[i], name)) return 1;
    return 0;
}

static Node *derivative(Node *f, const char *name) {
    if (f->kind == NUMBER) return zero;
    if (f->kind == VARIABLE) return !strcmp(f->name, name) ? one : zero;
    if (f->kind == SUM) {
        Node *terms[MAX_CHILDREN];
        for (int i = 0; i < f->length; ++i) terms[i] = derivative(f->children[i], name);
        return add(f->length, terms);
    }
    if (f->kind == PRODUCT) {
        Node *terms[MAX_CHILDREN];
        for (int i = 0; i < f->length; ++i) {
            Node *factors[MAX_CHILDREN];
            for (int j = 0; j < f->length; ++j) {
                factors[j] = i == j ? derivative(f->children[j], name) : f->children[j];
            }
            terms[i] = multiply(f->length, factors);
        }
        return add(f->length, terms);
    }
    if (f->kind == POWER) {
        Node *b = f->children[0], *x = f->children[1];
        if (!contains_variable(x, name)) {
            return multiply_three(x, power(b, add_two(x, minus_one)), derivative(b, name));
        }
        if (!contains_variable(b, name)) {
            return multiply_three(f, function("ln", b), derivative(x, name));
        }
        Node *first = multiply_two(derivative(x, name), function("ln", b));
        Node *second = multiply_three(x, derivative(b, name), power(b, minus_one));
        return multiply_two(f, add_two(first, second));
    }
    Node *a = f->children[0], *h;
    if (!strcmp(f->name, "sin")) h = function("cos", a);
    else if (!strcmp(f->name, "cos")) h = multiply_two(minus_one, function("sin", a));
    else if (!strcmp(f->name, "tan")) h = power(function("cos", a), integer(-2));
    else if (!strcmp(f->name, "exp")) h = f;
    else h = power(a, minus_one);
    return multiply_two(h, derivative(a, name));
}

static Node *substitute(Node *f, int count, const char **names, Node **values) {
    if (f->kind == VARIABLE) {
        for (int i = 0; i < count; ++i) if (!strcmp(f->name, names[i])) return values[i];
        return f;
    }
    if (f->kind == NUMBER) return f;
    Node *children[MAX_CHILDREN];
    for (int i = 0; i < f->length; ++i) children[i] = substitute(f->children[i], count, names, values);
    if (f->kind == SUM) return add(f->length, children);
    if (f->kind == PRODUCT) return multiply(f->length, children);
    if (f->kind == POWER) return power(children[0], children[1]);
    return function(f->name, children[0]);
}

static Node *replace(Node *f, const char *name, Node *value) {
    const char *names[] = {name};
    Node *values[] = {value};
    return substitute(f, 1, names, values);
}

static Node *distribute(Node *a, Node *b) {
    Node *left = a->kind == SUM ? a : NULL, *right = b->kind == SUM ? b : NULL;
    int n = left ? left->length : 1, m = right ? right->length : 1;
    Node *terms[MAX_CHILDREN];
    int count = 0;
    for (int i = 0; i < n; ++i) {
        for (int j = 0; j < m; ++j) {
            terms[count++] = multiply_two(left ? left->children[i] : a, right ? right->children[j] : b);
        }
    }
    return add(count, terms);
}

static Node *expand(Node *f) {
    if (f->kind == NUMBER || f->kind == VARIABLE) return f;
    Node *children[MAX_CHILDREN];
    for (int i = 0; i < f->length; ++i) children[i] = expand(f->children[i]);
    if (f->kind == SUM) return add(f->length, children);
    if (f->kind == PRODUCT) {
        Node *result = children[0];
        for (int i = 1; i < f->length; ++i) result = distribute(result, children[i]);
        return result;
    }
    if (f->kind == FUNCTION) return function(f->name, children[0]);
    if (children[0]->kind == SUM && is_integer(children[1]) && children[1]->p > 0) {
        Node *result = children[0];
        for (long long i = 1; i < children[1]->p; ++i) result = distribute(result, children[0]);
        return result;
    }
    return power(children[0], children[1]);
}

static double numerical_value(Node *f) {
    if (f->kind == NUMBER) return (double)f->p / (double)f->q;
    if (f->kind == SUM) {
        double result = 0.0;
        for (int i = 0; i < f->length; ++i) result += numerical_value(f->children[i]);
        return result;
    }
    if (f->kind == PRODUCT) {
        double result = 1.0;
        for (int i = 0; i < f->length; ++i) result *= numerical_value(f->children[i]);
        return result;
    }
    if (f->kind == POWER) {
        double a = numerical_value(f->children[0]);
        double b = numerical_value(f->children[1]);
        int integral = f->children[1]->kind == NUMBER ? is_integer(f->children[1]) : floor(b) == b;
        if (a < 0.0 && !integral) errorf("domain error");
        return equal(f->children[1], half) ? sqrt(a) : pow(a, b);
    }
    double a = numerical_value(f->children[0]);
    if (!strcmp(f->name, "ln")) {
        if (a <= 0.0) errorf("domain error");
        return log(a);
    }
    if (!strcmp(f->name, "sin")) return sin(a);
    if (!strcmp(f->name, "cos")) return cos(a);
    if (!strcmp(f->name, "tan")) return tan(a);
    return exp(a);
}

static void render(Node *f, char *buffer);

static int atomic(Node *f) {
    return f->kind == VARIABLE || f->kind == FUNCTION ||
           (is_integer(f) && f->p >= 0) ||
           (f->kind == POWER && equal(f->children[1], half));
}

static void render_atomic(Node *f, char *buffer) {
    if (!atomic(f)) strcat(buffer, "(");
    render(f, buffer);
    if (!atomic(f)) strcat(buffer, ")");
}

static void render_power(Node *b, Node *x, char *buffer) {
    if (equal(x, half)) {
        strcat(buffer, "sqrt(");
        render(b, buffer);
        strcat(buffer, ")");
    } else {
        render_atomic(b, buffer);
        strcat(buffer, "^");
        render_atomic(x, buffer);
    }
}

static void render_factor(Node *f, char *buffer) {
    if (f->kind == SUM) {
        strcat(buffer, "(");
        render(f, buffer);
        strcat(buffer, ")");
    } else if (f->kind == POWER) render_power(f->children[0], f->children[1], buffer);
    else render(f, buffer);
}

static void push_factor(char *list, int *count, Node *f, int negative_power) {
    if (*count) strcat(list, "*");
    if (negative_power && f->kind == POWER) {
        Node *positive = number(-f->children[1]->p, f->children[1]->q);
        if (equal(positive, one)) render_factor(f->children[0], list);
        else render_power(f->children[0], positive, list);
    } else render_factor(f, list);
    ++*count;
}

static void render_quotient(long long p, long long q, int count, Node **factors, char *output) {
    char numerator[MAX_TEXT] = "", denominator[MAX_TEXT] = "";
    int numerators = 0, denominators = 0;
    if (llabs(p) != 1) {
        sprintf(numerator, "%lld", llabs(p));
        ++numerators;
    }
    if (q != 1) {
        sprintf(denominator, "%lld", q);
        ++denominators;
    }
    for (int i = 0; i < count; ++i) {
        Node *f = factors[i];
        if (f->kind == POWER && f->children[1]->kind == NUMBER && f->children[1]->p < 0) {
            push_factor(denominator, &denominators, f, 1);
        } else push_factor(numerator, &numerators, f, 0);
    }
    if (p < 0) strcat(output, "-");
    strcat(output, numerators ? numerator : "1");
    if (denominators) {
        strcat(output, denominators == 1 ? "/" : "/(");
        strcat(output, denominator);
        if (denominators != 1) strcat(output, ")");
    }
}

static void render(Node *f, char *buffer) {
    if (f->kind == NUMBER) {
        char digits[64];
        if (f->q == 1) sprintf(digits, "%lld", f->p);
        else sprintf(digits, "%lld/%lld", f->p, f->q);
        strcat(buffer, digits);
        return;
    }
    if (f->kind == VARIABLE) {
        strcat(buffer, f->name);
        return;
    }
    if (f->kind == FUNCTION) {
        strcat(buffer, f->name);
        strcat(buffer, "(");
        render(f->children[0], buffer);
        strcat(buffer, ")");
        return;
    }
    if (f->kind == POWER) {
        if (f->children[1]->kind == NUMBER && f->children[1]->p < 0) {
            Node *items[] = {f};
            render_quotient(1, 1, 1, items, buffer);
        } else render_power(f->children[0], f->children[1], buffer);
        return;
    }
    if (f->kind == PRODUCT) {
        Term t = coefficient(f);
        render_quotient(t.p, t.q, t.length, t.parts, buffer);
        return;
    }
    for (int i = 0; i < f->length; ++i) {
        char term[MAX_TEXT] = "";
        render(f->children[i], term);
        if (i) {
            if (term[0] == '-') {
                strcat(buffer, " - ");
                strcat(buffer, term + 1);
            } else {
                strcat(buffer, " + ");
                strcat(buffer, term);
            }
        } else strcat(buffer, term);
    }
}

static char *notation(Node *f) {
    char *buffer = calloc(MAX_TEXT, 1);
    render(f, buffer);
    return buffer;
}

static char *trim(char *text) {
    while (*text == ' ') ++text;
    size_t length = strlen(text);
    while (length && text[length - 1] == ' ') text[--length] = '\0';
    return text;
}

static int parse_literal(const char *text, Node **result) {
    const char *p = text;
    int negative = 0;
    if (*p == '-') {negative = 1; ++p;}
    if (!isdigit((unsigned char)*p)) return 0;
    long long numerator = 0, denominator = 1;
    while (isdigit((unsigned char)*p)) numerator = numerator * 10 + *p++ - '0';
    if (*p == '/') {
        ++p;
        if (!isdigit((unsigned char)*p)) return 0;
        denominator = 0;
        while (isdigit((unsigned char)*p)) denominator = denominator * 10 + *p++ - '0';
    }
    if (*p) return 0;
    *result = number(negative ? -numerator : numerator, denominator);
    return 1;
}

static Node *literal(const char *text) {
    Node *result;
    if (!parse_literal(text, &result)) errorf("invalid number '%s'", text);
    return result;
}

static void assignment(const char *text, char name[202], Node **value) {
    const char *equal_sign = strchr(text, '=');
    if (!equal_sign || equal_sign - text >= 201) errorf("invalid assignment '%s'", text);
    size_t length = (size_t)(equal_sign - text);
    memcpy(name, text, length);
    name[length] = '\0';
    if (!variable_name(name)) errorf("invalid assignment '%s'", text);
    Node *parsed;
    if (!parse_literal(equal_sign + 1, &parsed)) errorf("invalid assignment '%s'", text);
    *value = parsed;
}

static void command(char *line) {
    char *space = strchr(line, ' '), *arguments = "";
    if (space) *space = '\0', arguments = space + 1;
    const char *cmd = line;
    static const char *const commands[] = {
        "LET","SIMPLIFY","EXPAND","DIFF","DIFFN","GRAD","HESSIAN","IMPLICIT",
        "SUBST","EVAL","TANGENT","LIMIT","TAYLOR"
    };
    int kind = -1;
    for (int i = 0; i < 13; ++i) if (!strcmp(cmd, commands[i])) kind = i;
    if (kind < 0) errorf("unknown command %s", cmd);
    if (kind == 0) {
        char *equal_sign = strchr(arguments, '=');
        if (!equal_sign) errorf("wrong number of arguments");
        *equal_sign = '\0';
        char *name = trim(arguments), *expression = trim(equal_sign + 1);
        if (!definition_name(name)) errorf("invalid name '%s'", name);
        Node *result = parse(expression);
        int index = -1;
        for (int i = 0; i < definitions_count; ++i) if (!strcmp(definitions[i].name, name)) index = i;
        if (index < 0) index = definitions_count++;
        strcpy(definitions[index].name, name);
        definitions[index].expression = result;
        printf("%s = %s\n", name, notation(result));
        return;
    }
    char *fields[5];
    int count = 0;
    if (space) {
        fields[count++] = arguments;
        for (char *p = arguments; *p; ++p) {
            if (*p == ';') {
                *p = '\0';
                fields[count++] = p + 1;
                if (count > 4) errorf("wrong number of arguments");
            }
        }
        for (int i = 0; i < count; ++i) fields[i] = trim(fields[i]);
    }
    int expected = kind == 1 || kind == 2 || kind == 5 || kind == 6 ? 1 :
                   kind == 3 ? 2 : kind == 12 ? 4 : 3;
    if (kind == 9) {
        if (count != 1 && count != 2) errorf("wrong number of arguments");
    } else if (count != expected) errorf("wrong number of arguments");
    Node *f = parse(fields[0]);
    if (kind == 1) {printf("simplified: %s\n", notation(f)); return;}
    if (kind == 2) {printf("expanded: %s\n", notation(expand(f))); return;}
    if (kind == 5 || kind == 6) {
        char names[MAX_CHILDREN][202];
        int n = variables(f, names);
        if (!n) {puts("no variables"); return;}
        for (int i = 0; i < n; ++i) {
            Node *d = derivative(f, names[i]);
            if (kind == 5) printf("d/d%s = %s\n", names[i], notation(d));
            else for (int j = i; j < n; ++j) {
                printf("d2/d%sd%s = %s\n", names[i], names[j], notation(derivative(d, names[j])));
            }
        }
        return;
    }
    if (kind == 9) {
        char assignments_buffer[256];
        strcpy(assignments_buffer, count == 2 ? fields[1] : "");
        const char *names[MAX_TOKENS];
        Node *values[MAX_TOKENS];
        char identifiers[MAX_TOKENS][202];
        int n = 0;
        for (char *word = strtok(assignments_buffer, " "); word; word = strtok(NULL, " ")) {
            assignment(word, identifiers[n], &values[n]);
            for (int i = 0; i < n; ++i) if (!strcmp(identifiers[i], identifiers[n])) errorf("duplicate variable %s", identifiers[n]);
            names[n] = identifiers[n];
            ++n;
        }
        char required[MAX_CHILDREN][202];
        int vars = variables(f, required);
        for (int j = 0; j < vars; ++j) {
            int assigned = 0;
            for (int i = 0; i < n; ++i) if (!strcmp(required[j], names[i])) assigned = 1;
            if (!assigned) errorf("no value for %s", required[j]);
        }
        Node *result = substitute(f, n, names, values);
        if (result->kind == NUMBER) printf("exact: %s\n", notation(result));
        else printf("approx: %.6f\n", numerical_value(result));
        return;
    }
    if (!variable_name(fields[1])) errorf("invalid variable '%s'", fields[1]);
    const char *v = fields[1];
    if (kind == 3) {
        printf("d/d%s = %s\n", v, notation(derivative(f, v)));
        return;
    }
    if (kind == 4) {
        if (strlen(fields[2]) != 1 || fields[2][0] < '1' || fields[2][0] > '8') errorf("invalid order '%s'", fields[2]);
        int order = fields[2][0] - '0';
        for (int k = 1; k <= order; ++k) {
            f = derivative(f, v);
            printf("d^%d/d%s^%d = %s\n", k, v, k, notation(f));
        }
        return;
    }
    if (kind == 7) {
        if (!variable_name(fields[2])) errorf("invalid variable '%s'", fields[2]);
        const char *w = fields[2];
        if (!strcmp(v, w)) errorf("same variable");
        Node *result = multiply_three(minus_one, derivative(f, v), power(derivative(f, w), minus_one));
        printf("d%s/d%s = %s\n", w, v, notation(result));
        return;
    }
    if (kind == 8) {
        Node *replacement = parse(fields[2]);
        printf("substituted: %s\n", notation(replace(f, v, replacement)));
        return;
    }
    Node *point = literal(fields[2]);
    if (kind == 10) {
        Node *slope = replace(derivative(f, v), v, point);
        Node *intercept = replace(f, v, point);
        Node *symbol = variable(v);
        Node *tangent = add(3, (Node *[]){multiply_two(slope, symbol), intercept,
                         multiply_two(number(-point->p, point->q), slope)});
        printf("tangent: y = %s\n", notation(tangent));
        if (equal(slope, zero)) printf("normal: %s = %s\n", v, notation(point));
        else {
            Node *inverse = power(slope, minus_one);
            Node *normal = add(3, (Node *[]){multiply_three(minus_one, inverse, symbol), intercept,
                               multiply_two(point, inverse)});
            printf("normal: y = %s\n", notation(normal));
        }
        return;
    }
    if (kind == 11) {
        Node *tops[MAX_CHILDREN], *bottoms[MAX_CHILDREN];
        int top_count = 0, bottom_count = 0;
        int n = f->kind == PRODUCT ? f->length : 1;
        for (int i = 0; i < n; ++i) {
            Node *part = f->kind == PRODUCT ? f->children[i] : f;
            if (part->kind == POWER && part->children[1]->kind == NUMBER && part->children[1]->p < 0) {
                Node *exp = number(-part->children[1]->p, part->children[1]->q);
                bottoms[bottom_count++] = power(part->children[0], exp);
            } else tops[top_count++] = part;
        }
        Node *numerator = multiply(top_count, tops), *denominator = multiply(bottom_count, bottoms);
        for (int k = 0; k <= 5; ++k) {
            Node *a = replace(numerator, v, point);
            Node *b = replace(denominator, v, point);
            if (!equal(b, zero)) {
                printf("limit: %s\n", notation(multiply_two(a, power(b, minus_one))));
                return;
            }
            if (!equal(a, zero)) {puts("limit: unbounded"); return;}
            if (k < 5) {
                numerator = derivative(numerator, v);
                denominator = derivative(denominator, v);
            }
        }
        puts("limit: unknown");
        return;
    }
    if (strlen(fields[3]) != 1 || fields[3][0] < '1' || fields[3][0] > '8') errorf("invalid order '%s'", fields[3]);
    int order = fields[3][0] - '0';
    Node *current = f, *terms[MAX_CHILDREN];
    long long factorial = 1;
    for (int k = 0; k <= order; ++k) {
        if (k) factorial *= k;
        Node *c = multiply_two(replace(current, v, point), number(1, factorial));
        Node *difference = add_two(variable(v), number(-point->p, point->q));
        terms[k] = multiply_two(c, power(difference, integer(k)));
        if (k != order) current = derivative(current, v);
    }
    printf("taylor: %s\n", notation(expand(add(order + 1, terms))));
}

int main(void) {
    zero = integer(0);
    one = integer(1);
    minus_one = integer(-1);
    half = number(1, 2);
    char line[256];
    if (!fgets(line, sizeof(line), stdin)) return 0;
    int count = atoi(line);
    for (int i = 0; i < count && fgets(line, sizeof(line), stdin); ++i) {
        size_t n = strlen(line);
        while (n && (line[n - 1] == '\n' || line[n - 1] == '\r')) line[--n] = '\0';
        if (!setjmp(recovery)) command(line);
        else printf("error: %s\n", failure);
    }
    return 0;
}
