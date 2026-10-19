#include <inttypes.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { int64_t n, d; } Fraction;
typedef struct { int len; Fraction *c; } Polynomial;
typedef struct Allocation { struct Allocation *next; max_align_t data[]; } Allocation;
typedef struct { char *data; size_t len, capacity; } Text;
typedef struct { char name[9]; Polynomial value; } Named;

static const Fraction ZERO = {0, 1}, ONE = {1, 1};
static Allocation *temporary;
static Text output;
static Named names[3000];
static int name_count;
static jmp_buf failure;
static char error_message[128];

static void *allocate(size_t size) {
    Allocation *block = calloc(1, sizeof(*block) + size);
    if (!block) exit(EXIT_FAILURE);
    block->next = temporary;
    temporary = block;
    return block->data;
}

static void clear_temporary(void) {
    while (temporary) {
        Allocation *next = temporary->next;
        free(temporary);
        temporary = next;
    }
}

static void emit(const char *format, ...) {
    va_list args, measured;
    va_start(args, format);
    va_copy(measured, args);
    int count = vsnprintf(NULL, 0, format, measured);
    va_end(measured);
    size_t needed = output.len + (size_t)count + 1;
    if (needed > output.capacity) {
        size_t capacity = needed * 2;
        char *data = realloc(output.data, capacity);
        if (!data) exit(EXIT_FAILURE);
        output.data = data;
        output.capacity = capacity;
    }
    vsnprintf(output.data + output.len, output.capacity - output.len, format, args);
    va_end(args);
    output.len += (size_t)count;
}

_Noreturn static void fail(const char *format, ...) {
    va_list args;
    va_start(args, format);
    vsnprintf(error_message, sizeof(error_message), format, args);
    va_end(args);
    longjmp(failure, 1);
}

static int64_t absolute(int64_t n) { return n < 0 ? -n : n; }
static int64_t gcd_integer(int64_t a, int64_t b) {
    a = absolute(a);
    b = absolute(b);
    while (b) { int64_t r = a % b; a = b; b = r; }
    return a;
}
static Fraction fraction(int64_t n, int64_t d) {
    if (d < 0) { n = -n; d = -d; }
    int64_t g = gcd_integer(n, d);
    return (Fraction){n / g, d / g};
}
static Fraction integer(int64_t n) { return (Fraction){n, 1}; }
static Fraction negate(Fraction a) { return (Fraction){-a.n, a.d}; }
static Fraction add(Fraction a, Fraction b) { return fraction(a.n * b.d + b.n * a.d, a.d * b.d); }
static Fraction subtract(Fraction a, Fraction b) { return fraction(a.n * b.d - b.n * a.d, a.d * b.d); }
static Fraction multiply(Fraction a, Fraction b) { return fraction(a.n * b.n, a.d * b.d); }
static Fraction divide(Fraction a, Fraction b) { return fraction(a.n * b.d, a.d * b.n); }
static int compare(Fraction a, Fraction b) {
    int64_t left = a.n * b.d, right = b.n * a.d;
    return (left > right) - (left < right);
}
static int sign(Fraction a) { return (a.n > 0) - (a.n < 0); }
static Fraction fraction_power(Fraction a, int n) {
    Fraction result = ONE;
    for (int i = 0; i < n; ++i) result = multiply(result, a);
    return result;
}
static Fraction literal(const char *text) {
    char *end;
    int64_t n = strtoll(text, &end, 10), d = *end == '/' ? strtoll(end + 1, NULL, 10) : 1;
    if (!d) fail("ERROR ZERO DENOMINATOR");
    return fraction(n, d);
}

typedef struct { char data[64]; } FractionText;
static FractionText fraction_text(Fraction a) {
    FractionText text;
    if (a.d == 1) snprintf(text.data, sizeof(text.data), "%" PRId64, a.n);
    else snprintf(text.data, sizeof(text.data), "%" PRId64 "/%" PRId64, a.n, a.d);
    return text;
}

static Polynomial polynomial(int length) {
    Polynomial result = {length, length ? allocate((size_t)length * sizeof(Fraction)) : NULL};
    for (int i = 0; i < length; ++i) result.c[i] = ZERO;
    return result;
}
static Polynomial trim(Polynomial a) {
    while (a.len && !a.c[a.len - 1].n) --a.len;
    return a;
}
static Polynomial constant(Fraction c) {
    Polynomial result = polynomial(c.n != 0);
    if (result.len) result.c[0] = c;
    return result;
}
static Polynomial linear(Fraction c, Fraction slope) {
    Polynomial result = polynomial(2);
    result.c[0] = c;
    result.c[1] = slope;
    return trim(result);
}
static Fraction coefficient(Polynomial a, int i) { return i < a.len ? a.c[i] : ZERO; }
static Polynomial poly_add(Polynomial a, Polynomial b, bool minus) {
    Polynomial result = polynomial(a.len > b.len ? a.len : b.len);
    for (int i = 0; i < result.len; ++i)
        result.c[i] = minus ? subtract(coefficient(a, i), coefficient(b, i)) : add(coefficient(a, i), coefficient(b, i));
    return trim(result);
}
static Polynomial poly_negate(Polynomial a) {
    Polynomial result = polynomial(a.len);
    for (int i = 0; i < a.len; ++i) result.c[i] = negate(a.c[i]);
    return result;
}
static Polynomial scale(Polynomial a, Fraction c, bool division) {
    Polynomial result = polynomial(a.len);
    for (int i = 0; i < a.len; ++i) result.c[i] = division ? divide(a.c[i], c) : multiply(c, a.c[i]);
    return trim(result);
}
static Polynomial product(Polynomial a, Polynomial b) {
    if (!a.len || !b.len) return polynomial(0);
    Polynomial result = polynomial(a.len + b.len - 1);
    for (int i = 0; i < a.len; ++i)
        for (int j = 0; j < b.len; ++j)
            result.c[i + j] = add(result.c[i + j], multiply(a.c[i], b.c[j]));
    return trim(result);
}
static Polynomial power(Polynomial a, int n) {
    if (n && !a.len) return a;
    if (a.len == 1 && a.c[0].d == 1 && absolute(a.c[0].n) == 1)
        return constant(integer(a.c[0].n < 0 && n % 2 ? -1 : 1));
    Polynomial result = constant(ONE);
    for (int i = 0; i < n; ++i) result = product(result, a);
    return result;
}

typedef struct { Polynomial quotient, remainder; } Division;
static Division divmod(Polynomial a, Polynomial b) {
    Polynomial q = polynomial(a.len >= b.len ? a.len - b.len + 1 : 0);
    Polynomial r = polynomial(a.len);
    if (a.len) memcpy(r.c, a.c, (size_t)a.len * sizeof(Fraction));
    while (r.len && r.len >= b.len) {
        Fraction t = divide(r.c[r.len - 1], b.c[b.len - 1]);
        int offset = r.len - b.len;
        q.c[offset] = t;
        for (int j = 0; j < b.len; ++j) r.c[offset + j] = subtract(r.c[offset + j], multiply(t, b.c[j]));
        r = trim(r);
    }
    return (Division){trim(q), r};
}
static Polynomial monic(Polynomial a) { return a.len ? scale(a, a.c[a.len - 1], true) : a; }
static Polynomial derivative(Polynomial a) {
    Polynomial result = polynomial(a.len > 1 ? a.len - 1 : 0);
    for (int i = 1; i < a.len; ++i) result.c[i - 1] = multiply(integer(i), a.c[i]);
    return result;
}
static Polynomial differentiate(Polynomial a, int n) {
    for (int i = 0; i < n && a.len; ++i) a = derivative(a);
    return a;
}
static Polynomial integral(Polynomial a) {
    Polynomial result = polynomial(a.len + 1);
    for (int i = 0; i < a.len; ++i) result.c[i + 1] = divide(a.c[i], integer(i + 1));
    return trim(result);
}
static Fraction evaluate(Polynomial a, Fraction x) {
    Fraction result = ZERO;
    for (int i = a.len - 1; i >= 0; --i) result = add(multiply(result, x), a.c[i]);
    return result;
}
static Polynomial compose(Polynomial a, Polynomial b) {
    Polynomial result = polynomial(0);
    for (int i = a.len - 1; i >= 0; --i) result = poly_add(product(result, b), constant(a.c[i]), false);
    return result;
}
static Polynomial poly_gcd(Polynomial a, Polynomial b) {
    while (b.len) { Polynomial r = divmod(a, b).remainder; a = b; b = r; }
    return monic(a);
}

typedef struct { Polynomial g, s, t; } Bezout;
static Bezout extended_gcd(Polynomial a, Polynomial b) {
    Polynomial s0 = constant(ONE), s1 = polynomial(0), t0 = polynomial(0), t1 = constant(ONE);
    while (b.len) {
        Division d = divmod(a, b);
        Polynomial s = poly_add(s0, product(d.quotient, s1), true);
        Polynomial t = poly_add(t0, product(d.quotient, t1), true);
        a = b; b = d.remainder;
        s0 = s1; s1 = s;
        t0 = t1; t1 = t;
    }
    if (a.len) {
        Fraction lead = a.c[a.len - 1];
        a = scale(a, lead, true);
        s0 = scale(s0, lead, true);
        t0 = scale(t0, lead, true);
    }
    return (Bezout){a, s0, t0};
}
static bool is_one(Polynomial a) { return a.len == 1 && compare(a.c[0], ONE) == 0; }
static Fraction content(Polynomial a) {
    int64_t lcm = 1, gcd = 0;
    for (int i = 0; i < a.len; ++i) {
        lcm = lcm * a.c[i].d / gcd_integer(lcm, a.c[i].d);
        gcd = gcd_integer(gcd, a.c[i].n);
    }
    return fraction(a.c[a.len - 1].n < 0 ? -gcd : gcd, lcm);
}
static Polynomial primitive(Polynomial a) { return scale(a, content(a), true); }
static Polynomial square_free(Polynomial a) {
    return a.len > 1 ? divmod(a, poly_gcd(a, derivative(a))).quotient : a;
}

static void write_polynomial(Polynomial a, const char *variable) {
    bool first = true;
    for (int i = a.len - 1; i >= 0; --i) {
        Fraction c = a.c[i];
        if (!c.n) continue;
        if (first) { if (c.n < 0) emit("-"); }
        else emit(c.n < 0 ? " - " : " + ");
        c.n = absolute(c.n);
        if (i == 0 || c.n != c.d) emit("%s", fraction_text(c).data);
        if (i) { emit("%s", variable); if (i > 1) emit("^%d", i); }
        first = false;
    }
    if (first) emit("0");
}
static int find_name(const char *name) {
    for (int i = 0; i < name_count; ++i) if (!strcmp(names[i].name, name)) return i;
    return -1;
}
static Polynomial lookup(const char *name) {
    int index = find_name(name);
    if (index < 0) fail("ERROR UNKNOWN %s", name);
    return names[index].value;
}
static void print_named(const char *name, Polynomial value) {
    emit("%s = ", name);
    write_polynomial(value, "x");
    emit("\n");
}
static void store(const char *name, Polynomial value) {
    Fraction *saved = value.len ? malloc((size_t)value.len * sizeof(Fraction)) : NULL;
    if (value.len && !saved) exit(EXIT_FAILURE);
    if (value.len) memcpy(saved, value.c, (size_t)value.len * sizeof(Fraction));
    int index = find_name(name);
    if (index < 0) { index = name_count++; strcpy(names[index].name, name); }
    else free(names[index].value.c);
    names[index].value = (Polynomial){value.len, saved};
    print_named(name, names[index].value);
}
static int named_compare(const void *a, const void *b) { return strcmp((*(Named *const *)a)->name, (*(Named *const *)b)->name); }

// Build the syntax tree completely before any name lookup or arithmetic.
typedef enum { NUMBER, NAME, SYMBOL, END } TokenKind;
typedef struct { TokenKind kind; int position, number; char symbol, name[9]; } Token;
typedef enum { LITERAL, VARIABLE, REFERENCE, NEGATIVE, PLUS, MINUS, TIMES, OVER, POWER, COMPOSE } Operation;
typedef struct Node { Operation op; int number; char name[9]; struct Node *left, *right; } Node;
typedef struct { Token tokens[101]; int count, index; } Parser;

static bool is_digit(char c) { return c >= '0' && c <= '9'; }
static bool is_upper(char c) { return c >= 'A' && c <= 'Z'; }
static Parser tokenize(const char *text) {
    Parser parser = {0};
    int position = 0;
    while (text[position]) {
        if (text[position] == ' ') { ++position; continue; }
        Token token = {.position = position + 1};
        if (is_digit(text[position])) {
            token.kind = NUMBER;
            while (is_digit(text[position])) token.number = token.number * 10 + text[position++] - '0';
        } else if (is_upper(text[position])) {
            token.kind = NAME;
            int length = 0;
            while (is_upper(text[position]) || is_digit(text[position])) token.name[length++] = text[position++];
            token.name[length] = '\0';
        } else { token.kind = SYMBOL; token.symbol = text[position++]; }
        parser.tokens[parser.count++] = token;
    }
    parser.tokens[parser.count++] = (Token){.kind = END};
    return parser;
}
static Token *peek(Parser *parser) { return &parser->tokens[parser->index]; }
static bool accept(Parser *parser, char symbol) {
    if (peek(parser)->kind != SYMBOL || peek(parser)->symbol != symbol) return false;
    ++parser->index;
    return true;
}
static void syntax_error(Parser *parser) {
    if (peek(parser)->kind == END) fail("ERROR SYNTAX AT END");
    fail("ERROR SYNTAX AT %d", peek(parser)->position);
}
static Node *node(Operation op, Node *left, Node *right) {
    Node *result = allocate(sizeof(*result));
    result->op = op; result->left = left; result->right = right;
    return result;
}
static Node *parse_expression(Parser *parser);
static Node *parse_primary(Parser *parser) {
    Token token = *peek(parser);
    Node *result;
    if (token.kind == NUMBER) {
        ++parser->index;
        result = node(LITERAL, NULL, NULL);
        result->number = token.number;
    } else if (accept(parser, 'x')) result = node(VARIABLE, NULL, NULL);
    else if (token.kind == NAME) {
        ++parser->index;
        result = node(REFERENCE, NULL, NULL);
        strcpy(result->name, token.name);
        while (accept(parser, '\'')) ++result->number;
        if (accept(parser, '(')) {
            Node *argument = parse_expression(parser);
            if (!accept(parser, ')')) syntax_error(parser);
            result = node(COMPOSE, result, argument);
        }
    } else if (accept(parser, '(')) {
        result = parse_expression(parser);
        if (!accept(parser, ')')) syntax_error(parser);
    } else { syntax_error(parser); return NULL; }
    return result;
}
static Node *parse_factor(Parser *parser) {
    Node *result = parse_primary(parser);
    if (accept(parser, '^')) {
        if (peek(parser)->kind != NUMBER) syntax_error(parser);
        Node *powered = node(POWER, result, NULL);
        powered->number = peek(parser)->number;
        ++parser->index;
        result = powered;
    }
    return result;
}
static Node *parse_term(Parser *parser) {
    Node *result = parse_factor(parser);
    for (;;) {
        if (accept(parser, '*')) result = node(TIMES, result, parse_factor(parser));
        else if (accept(parser, '/')) result = node(OVER, result, parse_factor(parser));
        else if (peek(parser)->kind == NAME || (peek(parser)->kind == SYMBOL && (peek(parser)->symbol == 'x' || peek(parser)->symbol == '(')))
            result = node(TIMES, result, parse_factor(parser));
        else return result;
    }
}
static Node *parse_expression(Parser *parser) {
    bool negative = accept(parser, '-');
    Node *result = parse_term(parser);
    if (negative) result = node(NEGATIVE, result, NULL);
    for (;;) {
        if (accept(parser, '+')) result = node(PLUS, result, parse_term(parser));
        else if (accept(parser, '-')) result = node(MINUS, result, parse_term(parser));
        else return result;
    }
}
static void check_product(Polynomial a, Polynomial b) {
    if (a.len && b.len && a.len + b.len - 2 > 30) fail("ERROR DEGREE LIMIT");
}
static void check_power(Polynomial a, int n) {
    if (a.len && (int64_t)(a.len - 1) * n > 30) fail("ERROR DEGREE LIMIT");
}
static void check_composition(Polynomial a, Polynomial b) {
    if (a.len > 1 && b.len > 1 && (a.len - 1) * (b.len - 1) > 30) fail("ERROR DEGREE LIMIT");
}
static Polynomial evaluate_node(const Node *expression) {
    if (expression->op == LITERAL) return constant(integer(expression->number));
    if (expression->op == VARIABLE) return linear(ZERO, ONE);
    if (expression->op == REFERENCE) return differentiate(lookup(expression->name), expression->number);
    Polynomial left = evaluate_node(expression->left);
    if (expression->op == NEGATIVE) return poly_negate(left);
    if (expression->op == POWER) { check_power(left, expression->number); return power(left, expression->number); }
    Polynomial right = evaluate_node(expression->right);
    switch (expression->op) {
        case PLUS: return poly_add(left, right, false);
        case MINUS: return poly_add(left, right, true);
        case TIMES: check_product(left, right); return product(left, right);
        case OVER:
            if (!right.len) fail("ERROR DIVISION BY ZERO");
            if (right.len > 1) fail("ERROR NONCONSTANT DIVISOR");
            return scale(left, right.c[0], true);
        case COMPOSE: check_composition(left, right); return compose(left, right);
        default: abort();
    }
}

typedef struct { Fraction value; int multiplicity; } Root;
typedef struct { Fraction content; Root roots[30]; int count; Polynomial remaining; } Roots;
static int fraction_compare(const void *a, const void *b) { return compare(*(const Fraction *)a, *(const Fraction *)b); }
static int root_compare(const void *a, const void *b) { return compare(((const Root *)a)->value, ((const Root *)b)->value); }
static Roots rational_roots(Polynomial a) {
    Roots result = {.content = content(a)};
    Polynomial p = scale(a, result.content, true);
    int zeros = 0;
    while (!p.c[0].n) { ++zeros; --p.len; ++p.c; }
    int64_t first = absolute(p.c[0].n), last = p.c[p.len - 1].n;
    int *numerators = allocate((size_t)first * sizeof(int));
    int *denominators = allocate((size_t)last * sizeof(int));
    int ns = 0, nt = 0;
    for (int s = 1; s <= first; ++s) if (first % s == 0) numerators[ns++] = s;
    for (int t = 1; t <= last; ++t) if (last % t == 0) denominators[nt++] = t;
    Fraction *candidates = allocate((size_t)(2 * ns * nt) * sizeof(Fraction));
    int count = 0;
    for (int i = 0; i < ns; ++i) for (int j = 0; j < nt; ++j) {
        int64_t s = numerators[i], t = denominators[j];
        if (gcd_integer(s, t) != 1) continue;
        candidates[count++] = (Fraction){s, t};
        candidates[count++] = (Fraction){-s, t};
    }
    qsort(candidates, (size_t)count, sizeof(Fraction), fraction_compare);
    for (int i = 0; i < count; ++i) {
        Fraction r = candidates[i];
        int multiplicity = 0;
        while (p.len > 1 && !evaluate(p, r).n) {
            p = divmod(p, linear(integer(-r.n), integer(r.d))).quotient;
            ++multiplicity;
        }
        if (multiplicity) result.roots[result.count++] = (Root){r, multiplicity};
    }
    if (zeros) result.roots[result.count++] = (Root){ZERO, zeros};
    qsort(result.roots, (size_t)result.count, sizeof(Root), root_compare);
    result.remaining = p;
    return result;
}

static void write_factor(Polynomial p, int multiplicity, bool simple_x) {
    emit(" * ");
    if (simple_x) emit("x");
    else { emit("("); write_polynomial(p, "x"); emit(")"); }
    if (multiplicity > 1) emit("^%d", multiplicity);
}
static void write_square_free(const char *name, Polynomial a) {
    emit("sqfree(%s) = %s", name, fraction_text(content(a)).data);
    if (a.len > 1) {
        Polynomial w0 = monic(a), c = poly_gcd(w0, derivative(w0));
        Polynomial w = divmod(w0, c).quotient;
        for (int multiplicity = 1; w.len > 1; ++multiplicity) {
            Polynomial y = poly_gcd(w, c), f = divmod(w, y).quotient;
            if (f.len > 1) {
                Polynomial h = primitive(f);
                write_factor(h, multiplicity, h.len == 2 && !h.c[0].n && compare(h.c[1], ONE) == 0);
            }
            c = divmod(c, y).quotient;
            w = y;
        }
    }
    emit("\n");
}

// Infinity is separate from finite fractions, so all finite operations stay exact.
typedef struct { int infinity; Fraction value; } Bound;
typedef struct { Polynomial items[31]; int count; } Sturm;
typedef struct { Fraction low, high; } Interval;
typedef struct { Interval items[30]; int count; } Intervals;
static Bound finite(Fraction value) { return (Bound){0, value}; }
static Bound bound_literal(const char *text) {
    if (!strcmp(text, "-inf")) return (Bound){-1, ZERO};
    if (!strcmp(text, "inf")) return (Bound){1, ZERO};
    return finite(literal(text));
}
static int bound_compare(Bound a, Bound b) {
    if (a.infinity || b.infinity) return (a.infinity > b.infinity) - (a.infinity < b.infinity);
    return compare(a.value, b.value);
}
static FractionText bound_text(Bound a) {
    if (!a.infinity) return fraction_text(a.value);
    FractionText text;
    strcpy(text.data, a.infinity < 0 ? "-inf" : "inf");
    return text;
}
static Sturm sturm_sequence(Polynomial a) {
    Sturm result = {0};
    Polynomial p = square_free(a), q = derivative(p);
    result.items[result.count++] = p;
    while (q.len) {
        result.items[result.count++] = q;
        Polynomial r = poly_negate(divmod(p, q).remainder);
        p = q; q = r;
    }
    return result;
}
static int variations(const Sturm *sequence, Bound point) {
    int previous = 0, count = 0;
    for (int i = 0; i < sequence->count; ++i) {
        Polynomial p = sequence->items[i];
        int s = point.infinity ? sign(p.c[p.len - 1]) : sign(evaluate(p, point.value));
        if (point.infinity < 0 && (p.len - 1) % 2) s = -s;
        if (s) { if (previous && previous != s) ++count; previous = s; }
    }
    return count;
}
static int root_count(const Sturm *sequence, Bound low, Bound high) {
    int left = variations(sequence, low), right = variations(sequence, high);
    return left - right;
}
static void examine(const Sturm *sequence, Fraction low, Fraction high, Fraction width, Intervals *result) {
    int count = root_count(sequence, finite(low), finite(high));
    if (count >= 2) {
        Fraction middle = divide(add(low, high), integer(2));
        examine(sequence, low, middle, width, result);
        examine(sequence, middle, high, width, result);
    } else if (count == 1) {
        while (compare(subtract(high, low), width) > 0) {
            Fraction middle = divide(add(low, high), integer(2));
            if (root_count(sequence, finite(low), finite(middle)) >= 1) high = middle;
            else low = middle;
        }
        result->items[result->count++] = (Interval){low, high};
    }
}
static Intervals isolate(Polynomial a, int n) {
    Sturm sequence = sturm_sequence(a);
    Polynomial first = sequence.items[0];
    Fraction maximum = ZERO;
    for (int i = 0; i < first.len - 1; ++i) {
        Fraction ratio = divide(first.c[i], first.c[first.len - 1]);
        ratio.n = absolute(ratio.n);
        if (compare(ratio, maximum) > 0) maximum = ratio;
    }
    Fraction beta = add(ONE, maximum), width = fraction(1, INT64_C(1) << n);
    Intervals result = {0};
    examine(&sequence, negate(beta), beta, width, &result);
    return result;
}
static Fraction resultant(Polynomial p, Polynomial q) {
    Fraction r = ONE;
    while (q.len > 1) {
        Polynomial t = divmod(p, q).remainder;
        if (!t.len) return ZERO;
        r = multiply(r, fraction_power(q.c[q.len - 1], p.len - t.len));
        if ((p.len - 1) * (q.len - 1) % 2) r = negate(r);
        p = q; q = t;
    }
    return multiply(r, fraction_power(q.c[0], p.len - 1));
}
static Polynomial interpolate(const Fraction *values, int count) {
    int m = count / 2;
    Fraction *x = allocate((size_t)m * sizeof(Fraction));
    Fraction *d = allocate((size_t)m * sizeof(Fraction));
    for (int i = 0; i < m; ++i) { x[i] = values[2 * i]; d[i] = values[2 * i + 1]; }
    for (int j = 1; j < m; ++j)
        for (int i = 0; i < j; ++i)
            if (compare(x[j], x[i]) == 0) fail("ERROR DUPLICATE X %s", fraction_text(x[j]).data);
    for (int j = 1; j < m; ++j) for (int i = m - 1; i >= j; --i) {
        Fraction numerator = subtract(d[i], d[i - 1]);
        Fraction denominator = subtract(x[i], x[i - j]);
        d[i] = divide(numerator, denominator);
    }
    Polynomial result = polynomial(0);
    for (int i = m - 1; i >= 0; --i)
        result = poly_add(product(result, linear(negate(x[i]), ONE)), constant(d[i]), false);
    return result;
}
static Polynomial special(const char *kind, int n) {
    int family = !strcmp(kind, "chebyshev") ? 0 : !strcmp(kind, "chebyshev2") ? 1 :
        !strcmp(kind, "legendre") ? 2 : !strcmp(kind, "hermite") ? 3 : !strcmp(kind, "laguerre") ? 4 : -1;
    if (family < 0) fail("ERROR UNKNOWN KIND %s", kind);
    if (n > 30) fail("ERROR DEGREE LIMIT");
    Polynomial a = constant(ONE);
    Polynomial b = family == 4 ? linear(ONE, integer(-1)) : linear(ZERO, integer(family == 1 || family == 3 ? 2 : 1));
    if (!n) return a;
    for (int j = 1; j < n; ++j) {
        Polynomial factor = family == 4 ? linear(integer(2 * j + 1), integer(-1)) :
            linear(ZERO, integer(family == 2 ? 2 * j + 1 : 2));
        Fraction multiplier = integer(family == 2 || family == 4 ? j : family == 3 ? 2 * j : 1);
        Polynomial next = poly_add(product(factor, b), scale(a, multiplier, false), true);
        if (family == 2 || family == 4) next = scale(next, fraction(1, j + 1), false);
        a = b; b = next;
    }
    return b;
}

typedef enum {
    PRINT, DELETE, LIST, DEGREE, ADD, SUB, MUL, POW, DIV, GCD, XGCD, LCM, INVMOD, CRT,
    MODPOW, DERIV, INTEG, AREA, TANGENT, TAYLOR, COMPOSITION, EVAL, ROOTS, FACTOR, SQFREE,
    DESCARTES, STURM, ISOLATE, RESULTANT, DISCRIM, POWERSUM, INTERP, SPECIAL
} CommandKind;
static const char *const command_names[] = {
    "PRINT", "DELETE", "LIST", "DEGREE", "ADD", "SUB", "MUL", "POW", "DIV", "GCD", "XGCD", "LCM", "INVMOD", "CRT",
    "MODPOW", "DERIV", "INTEG", "AREA", "TANGENT", "TAYLOR", "COMPOSE", "EVAL", "ROOTS", "FACTOR", "SQFREE",
    "DESCARTES", "STURM", "ISOLATE", "RESULTANT", "DISCRIM", "POWERSUM", "INTERP", "SPECIAL"
};

static void process(char *line) {
    if (!strncmp(line, "DEF ", 4)) {
        char *name = line + 4, *expression = strchr(name, ' ');
        *expression++ = '\0';
        Parser parser = tokenize(expression);
        Node *tree = parse_expression(&parser);
        if (peek(&parser)->kind != END) syntax_error(&parser);
        Polynomial value = evaluate_node(tree);
        store(name, value);
        return;
    }
    char *words[64];
    int word_count = 0;
    for (char *word = strtok(line, " "); word; word = strtok(NULL, " ")) words[word_count++] = word;
    CommandKind kind = PRINT;
    while (strcmp(words[0], command_names[kind])) ++kind;
    if ((kind == DIV && !strcmp(words[1], words[2])) ||
        (kind == XGCD && (!strcmp(words[1], words[2]) || !strcmp(words[1], words[3]) || !strcmp(words[2], words[3]))))
        fail("ERROR SAME NAME");
    int positions[4], source_count = 0;
    switch (kind) {
        case ADD: case SUB: case MUL: case GCD: case LCM: case INVMOD: case COMPOSITION:
            positions[source_count++] = 2; positions[source_count++] = 3; break;
        case POW: case DERIV: case INTEG: case TANGENT: positions[source_count++] = 2; break;
        case MODPOW: positions[source_count++] = 2; positions[source_count++] = 4; break;
        case DIV: positions[source_count++] = 3; positions[source_count++] = 4; break;
        case XGCD: positions[source_count++] = 4; positions[source_count++] = 5; break;
        case CRT: for (int i = 2; i <= 5; ++i) positions[source_count++] = i; break;
        case RESULTANT: positions[source_count++] = 1; positions[source_count++] = 2; break;
        case LIST: case INTERP: case SPECIAL: break;
        default: positions[source_count++] = 1; break;
    }
    Polynomial p[4] = {0};
    for (int i = 0; i < source_count; ++i) p[i] = lookup(words[positions[i]]);
    Fraction values[62];
    int value_count = 0, start = -1;
    if (kind == AREA || kind == TAYLOR || kind == EVAL || kind == INTERP) start = 2;
    else if (kind == TANGENT) start = 3;
    if (start >= 0) for (int i = start; i < word_count; ++i) values[value_count++] = literal(words[i]);
    Bound bounds[2];
    if (kind == STURM) { bounds[0] = bound_literal(words[2]); bounds[1] = bound_literal(words[3]); }
    Polynomial a = p[0], b = p[1], result = polynomial(0);
    bool save = false;
    switch (kind) {
        case PRINT: print_named(words[1], a); break;
        case DELETE: {
            int index = find_name(words[1]);
            free(names[index].value.c);
            memmove(&names[index], &names[index + 1], (size_t)(name_count - index - 1) * sizeof(Named));
            --name_count;
            emit("deleted %s\n", words[1]);
            break;
        }
        case LIST: {
            if (!name_count) { emit("no polynomials\n"); break; }
            Named **ordered = allocate((size_t)name_count * sizeof(Named *));
            for (int i = 0; i < name_count; ++i) ordered[i] = &names[i];
            qsort(ordered, (size_t)name_count, sizeof(Named *), named_compare);
            for (int i = 0; i < name_count; ++i) print_named(ordered[i]->name, ordered[i]->value);
            break;
        }
        case DEGREE:
            if (a.len) emit("deg(%s) = %d\n", words[1], a.len - 1);
            else emit("deg(%s) = -inf\n", words[1]);
            break;
        case ADD: case SUB: result = poly_add(a, b, kind == SUB); save = true; break;
        case MUL: check_product(a, b); result = product(a, b); save = true; break;
        case POW: {
            int n = atoi(words[3]);
            check_power(a, n); result = power(a, n); save = true; break;
        }
        case DIV: {
            if (!b.len) fail("ERROR DIVISION BY ZERO");
            Division d = divmod(a, b);
            store(words[1], d.quotient); store(words[2], d.remainder); break;
        }
        case GCD: result = poly_gcd(a, b); save = true; break;
        case XGCD: {
            Bezout e = extended_gcd(a, b);
            store(words[1], e.g); store(words[2], e.s); store(words[3], e.t); break;
        }
        case LCM:
            if (a.len && b.len) {
                Polynomial g = poly_gcd(a, b);
                if (a.len + b.len - g.len - 1 > 30) fail("ERROR DEGREE LIMIT");
                result = monic(product(divmod(a, g).quotient, b));
            }
            save = true; break;
        case INVMOD: {
            if (!b.len) fail("ERROR DIVISION BY ZERO");
            if (b.len == 1) fail("ERROR DEGREE TOO LOW");
            Bezout e = extended_gcd(a, b);
            if (!is_one(e.g)) fail("ERROR NOT COPRIME");
            result = divmod(e.s, b).remainder; save = true; break;
        }
        case CRT: {
            Polynomial m1 = p[1], a2 = p[2], m2 = p[3];
            if (!m1.len || !m2.len) fail("ERROR DIVISION BY ZERO");
            if (m1.len + m2.len - 2 > 30) fail("ERROR DEGREE LIMIT");
            Bezout e = extended_gcd(m1, m2);
            if (!is_one(e.g)) fail("ERROR NOT COPRIME");
            Polynomial r1 = divmod(a, m1).remainder, r2 = divmod(a2, m2).remainder;
            Polynomial u = divmod(product(poly_add(r2, r1, true), e.s), m2).remainder;
            result = poly_add(r1, product(m1, u), false); save = true; break;
        }
        case MODPOW: {
            if (!b.len) fail("ERROR DIVISION BY ZERO");
            if (2 * (b.len - 1) - 2 > 30) fail("ERROR DEGREE LIMIT");
            Polynomial x = divmod(constant(ONE), b).remainder, y = divmod(a, b).remainder;
            int exponent = atoi(words[3]);
            while (exponent) {
                if (exponent % 2) x = divmod(product(x, y), b).remainder;
                exponent /= 2;
                if (exponent) y = divmod(product(y, y), b).remainder;
            }
            result = x; save = true; break;
        }
        case DERIV: result = differentiate(a, atoi(words[3])); save = true; break;
        case INTEG:
            if (a.len > 30) fail("ERROR DEGREE LIMIT");
            result = integral(a); save = true; break;
        case AREA: {
            Polynomial antiderivative = integral(a);
            Fraction high = evaluate(antiderivative, values[1]), low = evaluate(antiderivative, values[0]);
            emit("integral(%s, %s, %s) = %s\n", words[1], fraction_text(values[0]).data,
                fraction_text(values[1]).data, fraction_text(subtract(high, low)).data);
            break;
        }
        case TANGENT: {
            Fraction y = evaluate(a, values[0]), slope = evaluate(derivative(a), values[0]);
            result = linear(subtract(y, multiply(slope, values[0])), slope); save = true; break;
        }
        case TAYLOR: {
            Fraction center = values[0];
            Polynomial shifted = compose(a, linear(center, ONE));
            char variable[96];
            if (!center.n) strcpy(variable, "x");
            else snprintf(variable, sizeof(variable), "(x %c %s)", center.n > 0 ? '-' : '+',
                fraction_text(center.n < 0 ? negate(center) : center).data);
            emit("taylor(%s, %s) = ", words[1], fraction_text(center).data);
            write_polynomial(shifted, variable); emit("\n"); break;
        }
        case COMPOSITION: check_composition(a, b); result = compose(a, b); save = true; break;
        case EVAL:
            for (int i = 0; i < value_count; ++i)
                emit("%s(%s) = %s\n", words[1], fraction_text(values[i]).data, fraction_text(evaluate(a, values[i])).data);
            break;
        case ROOTS: case FACTOR: {
            if (!a.len) fail("ERROR ZERO POLYNOMIAL");
            Roots roots = rational_roots(a);
            if (kind == ROOTS) {
                emit("roots(%s) = ", words[1]);
                if (!roots.count) emit("none");
                for (int i = 0; i < roots.count; ++i)
                    emit("%s%s (%d)", i ? ", " : "", fraction_text(roots.roots[i].value).data, roots.roots[i].multiplicity);
            } else {
                emit("factor(%s) = %s", words[1], fraction_text(roots.content).data);
                for (int i = 0; i < roots.count; ++i) {
                    Root r = roots.roots[i];
                    write_factor(linear(integer(-r.value.n), integer(r.value.d)), r.multiplicity, !r.value.n);
                }
                if (roots.remaining.len > 1) write_factor(roots.remaining, 1, false);
            }
            emit("\n"); break;
        }
        case SQFREE:
            if (!a.len) fail("ERROR ZERO POLYNOMIAL");
            write_square_free(words[1], a); break;
        case DESCARTES: {
            if (!a.len) fail("ERROR ZERO POLYNOMIAL");
            int counts[2] = {0};
            for (int negative = 0; negative < 2; ++negative) {
                int previous = 0;
                for (int i = a.len - 1; i >= 0; --i) {
                    int s = sign(a.c[i]);
                    if (negative && i % 2) s = -s;
                    if (s) { if (previous && previous != s) ++counts[negative]; previous = s; }
                }
            }
            emit("descartes(%s) = positive %d, negative %d\n", words[1], counts[0], counts[1]); break;
        }
        case STURM: {
            if (!a.len) fail("ERROR ZERO POLYNOMIAL");
            if (bound_compare(bounds[0], bounds[1]) >= 0) fail("ERROR BAD INTERVAL");
            Sturm sequence = sturm_sequence(a);
            int count = root_count(&sequence, bounds[0], bounds[1]);
            emit("sturm(%s, %s, %s) = %d\n", words[1], bound_text(bounds[0]).data, bound_text(bounds[1]).data, count); break;
        }
        case ISOLATE: {
            if (!a.len) fail("ERROR ZERO POLYNOMIAL");
            int n = atoi(words[2]);
            Intervals intervals = isolate(a, n);
            emit("isolate(%s, %d) = ", words[1], n);
            if (!intervals.count) emit("none");
            for (int i = 0; i < intervals.count; ++i)
                emit("%s(%s, %s]", i ? ", " : "", fraction_text(intervals.items[i].low).data, fraction_text(intervals.items[i].high).data);
            emit("\n"); break;
        }
        case RESULTANT:
            if (!a.len || !b.len) fail("ERROR ZERO POLYNOMIAL");
            emit("res(%s, %s) = %s\n", words[1], words[2], fraction_text(resultant(a, b)).data); break;
        case DISCRIM: case POWERSUM: {
            if (!a.len) fail("ERROR ZERO POLYNOMIAL");
            if (a.len == 1) fail("ERROR DEGREE TOO LOW");
            int degree = a.len - 1;
            if (kind == DISCRIM) {
                Fraction d = divide(resultant(a, derivative(a)), a.c[degree]);
                if ((degree * (degree - 1) / 2) % 2) d = negate(d);
                emit("disc(%s) = %s\n", words[1], fraction_text(d).data);
            } else {
                int n = atoi(words[2]);
                Polynomial c = monic(a);
                Fraction sums[31];
                emit("powersum(%s) = ", words[1]);
                for (int j = 1; j <= n; ++j) {
                    Fraction w = j <= degree ? multiply(integer(j), c.c[degree - j]) : ZERO;
                    for (int i = 1; i <= degree && i < j; ++i) w = add(w, multiply(c.c[degree - i], sums[j - i]));
                    sums[j] = negate(w);
                    emit("%s%s", j == 1 ? "" : ", ", fraction_text(sums[j]).data);
                }
                emit("\n");
            }
            break;
        }
        case INTERP: result = interpolate(values, value_count); save = true; break;
        case SPECIAL: result = special(words[2], atoi(words[3])); save = true; break;
    }
    if (save) store(words[1], result);
}

int main(void) {
    char input[2048];
    if (!fgets(input, sizeof(input), stdin)) return 0;
    int commands = atoi(input);
    for (int i = 0; i < commands; ++i) {
        if (!fgets(input, sizeof(input), stdin)) break;
        input[strcspn(input, "\r\n")] = '\0';
        output.len = 0;
        if (setjmp(failure) == 0) { process(input); fputs(output.data, stdout); }
        else printf("%s\n", error_message);
        clear_temporary();
    }
    for (int i = 0; i < name_count; ++i) free(names[i].value.c);
    free(output.data);
    return 0;
}
