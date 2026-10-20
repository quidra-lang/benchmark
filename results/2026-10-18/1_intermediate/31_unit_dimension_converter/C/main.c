#include <inttypes.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { int64_t n, d; } Rational;
typedef struct { int64_t power[7]; } Dimension;
typedef struct { Rational value; Dimension dim; } Quantity;
typedef struct Allocation { void *value; struct Allocation *next; } Allocation;
static Allocation *temporary;
static jmp_buf failure;
static const Rational ONE = {1, 1};
static const char *base_names[] = {"kg", "m", "s", "A", "K", "mol", "cd"};

static void *allocate(size_t size) {
    void *value = calloc(1, size);
    Allocation *item = malloc(sizeof *item);
    if (!value || !item) exit(EXIT_FAILURE);
    *item = (Allocation){value, temporary}; temporary = item;
    return value;
}
static void release_temporary(void) {
    while (temporary) {
        Allocation *next = temporary->next;
        free(temporary->value); free(temporary); temporary = next;
    }
}
static char *slice(const char *text, size_t start, size_t end) {
    char *result = allocate(end - start + 1);
    memcpy(result, text + start, end - start); return result;
}
static char *format(const char *pattern, ...) {
    va_list args, copy;
    va_start(args, pattern); va_copy(copy, args);
    int length = vsnprintf(NULL, 0, pattern, copy); va_end(copy);
    char *result = allocate((size_t)length + 1);
    vsnprintf(result, (size_t)length + 1, pattern, args); va_end(args); return result;
}
static void fail(const char *pattern, ...) {
    va_list args; va_start(args, pattern);
    fputs("ERROR ", stdout); vprintf(pattern, args); putchar('\n'); va_end(args);
    longjmp(failure, 1);
}
static bool equal(const char *a, const char *b) { return strcmp(a, b) == 0; }
static bool letter(char c) { return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'); }
static bool digit(char c) { return c >= '0' && c <= '9'; }
static int64_t gcd(int64_t a, int64_t b) {
    if (a < 0) a = -a;
    while (b) { int64_t remainder = a % b; a = b; b = remainder; }
    return a;
}
static Rational rational(int64_t n, int64_t d) {
    if (d < 0) { n = -n; d = -d; }
    int64_t common = gcd(n, d); return (Rational){n / common, d / common};
}
static Rational integer(int64_t n) { return (Rational){n, 1}; }
static Rational add(Rational a, Rational b) { return rational(a.n * b.d + b.n * a.d, a.d * b.d); }
static Rational subtract(Rational a, Rational b) { return rational(a.n * b.d - b.n * a.d, a.d * b.d); }
static Rational multiply(Rational a, Rational b) { return rational(a.n * b.n, a.d * b.d); }
static Rational divide(Rational a, Rational b) { return rational(a.n * b.d, a.d * b.n); }
static Rational negate(Rational a) { a.n = -a.n; return a; }
static Rational power(Rational a, int exponent) {
    if (exponent < 0) { a = rational(a.d, a.n); exponent = -exponent; }
    Rational result = ONE;
    for (int i = 0; i < exponent; i++) result = multiply(result, a);
    return result;
}
static int compare(Rational a, Rational b) {
    int64_t left = a.n * b.d, right = b.n * a.d;
    return (left > right) - (left < right);
}
static char *fraction(Rational value) {
    return value.d == 1 ? format("%" PRId64, value.n) : format("%" PRId64 "/%" PRId64, value.n, value.d);
}
static char *decimal(Rational value) {
    int64_t magnitude = value.n < 0 ? -value.n : value.n;
    return format("%s%" PRId64 ".%06" PRId64, value.n < 0 ? "-" : "", magnitude / value.d, (magnitude % value.d) * 1000000 / value.d);
}
static char *notation(Rational value, const char *unit) { return format("%s %s (%s)", fraction(value), unit, decimal(value)); }
static Dimension dimension_add(Dimension a, Dimension b, int sign) {
    for (int i = 0; i < 7; i++) a.power[i] += sign * b.power[i];
    return a;
}
static Dimension dimension_scale(Dimension dim, int64_t factor) {
    for (int i = 0; i < 7; i++) dim.power[i] *= factor;
    return dim;
}
static bool same_dimension(Dimension a, Dimension b) {
    for (int i = 0; i < 7; i++) if (a.power[i] != b.power[i]) return false;
    return true;
}
static bool dimensionless(Dimension dim) { return same_dimension(dim, (Dimension){{0}}); }
static char *dimension_text(Dimension dim) {
    char *result = "";
    for (int i = 0; i < 7; i++) if (dim.power[i]) {
        const char *term = dim.power[i] == 1 ? base_names[i] : format("%s^%" PRId64, base_names[i], dim.power[i]);
        result = format("%s%s%s", result, *result ? " " : "", term);
    }
    return *result ? result : "1";
}
static void match_dimensions(Dimension a, Dimension b) {
    if (!same_dimension(a, b)) fail("DIMENSION MISMATCH %s vs %s", dimension_text(a), dimension_text(b));
}
static Rational number(const char *text) {
    size_t i = text[0] == '-' ? 1 : 0;
    bool negative = i != 0;
    if (!digit(text[i])) fail("BAD NUMBER %s", text);
    int64_t whole = 0;
    while (digit(text[i])) whole = whole * 10 + text[i++] - '0';
    int64_t denominator = 1, numerator = whole;
    if (text[i] == '.' || text[i] == '/') {
        char operation = text[i++];
        if (!digit(text[i])) fail("BAD NUMBER %s", text);
        int64_t tail = 0, scale = 1;
        while (digit(text[i])) { tail = tail * 10 + text[i++] - '0'; scale *= 10; }
        if (operation == '.') { numerator = whole * scale + tail; denominator = scale; }
        else { denominator = tail; if (!denominator) fail("BAD NUMBER %s", text); }
    }
    if (text[i]) fail("BAD NUMBER %s", text);
    return rational(negative ? -numerator : numerator, denominator);
}
static int exponent_value(const char *text) {
    int64_t value = strtoll(text, NULL, 10);
    if (!value || value < -3 || value > 3) fail("BAD EXPONENT %s", text);
    return (int)value;
}
static void check_name(const char *name, bool variable) {
    size_t length = strlen(name);
    bool valid = length > 0 && length <= 12;
    for (size_t i = 0; i < length; i++) if (!letter(name[i])) valid = false;
    if (variable && (equal(name, "abs") || equal(name, "sqrt") || equal(name, "min") || equal(name, "max"))) valid = false;
    if (!valid) fail("BAD NAME %s", name);
}

typedef struct { const char *name; Dimension dim; } Kind;
static const Kind kinds[] = {
    {"dimensionless", {{0}}}, {"length", {{0,1}}}, {"mass", {{1}}}, {"time", {{0,0,1}}},
    {"current", {{0,0,0,1}}}, {"temperature", {{0,0,0,0,1}}}, {"amount", {{0,0,0,0,0,1}}},
    {"luminous_intensity", {{0,0,0,0,0,0,1}}}, {"area", {{0,2}}}, {"volume", {{0,3}}},
    {"speed", {{0,1,-1}}}, {"acceleration", {{0,1,-2}}}, {"density", {{1,-3}}},
    {"momentum", {{1,1,-1}}}, {"force", {{1,1,-2}}}, {"energy", {{1,2,-2}}}, {"power", {{1,2,-3}}},
    {"pressure", {{1,-1,-2}}}, {"frequency", {{0,0,-1}}}, {"charge", {{0,0,1,1}}},
    {"voltage", {{1,2,-3,-1}}}, {"resistance", {{1,2,-3,-2}}}, {"conductance", {{-1,-2,3,2}}},
    {"capacitance", {{-1,-2,4,2}}}, {"magnetic_flux", {{1,2,-2,-1}}}, {"flux_density", {{1,0,-2,-1}}},
    {"inductance", {{1,2,-2,-2}}}, {"illuminance", {{0,-2,0,0,0,0,1}}}, {"catalytic_activity", {{0,0,-1,0,0,1}}}
};
static const Kind *find_kind(const char *name) {
    for (size_t i = 0; i < sizeof kinds / sizeof *kinds; i++) if (equal(name, kinds[i].name)) return &kinds[i];
    return NULL;
}
static const char *kind_name(Dimension dim) {
    for (size_t i = 0; i < sizeof kinds / sizeof *kinds; i++) if (same_dimension(dim, kinds[i].dim)) return kinds[i].name;
    return "-";
}
typedef struct {
    char symbol[13]; Quantity quantity; bool prefix, builtin;
    Rational definition_value; char definition_unit[201];
} Unit;
static Unit units[72];
static size_t unit_count;
static void builtin(const char *symbol, int64_t n, int64_t d, const char *kind, bool prefix) {
    Unit *unit = &units[unit_count++];
    strcpy(unit->symbol, symbol); unit->quantity = (Quantity){rational(n, d), find_kind(kind)->dim};
    unit->prefix = prefix; unit->builtin = true;
}
static void initialize_units(void) {
    builtin("m",1,1,"length",true); builtin("g",1,1000,"mass",true); builtin("s",1,1,"time",true);
    builtin("A",1,1,"current",true); builtin("K",1,1,"temperature",true); builtin("mol",1,1,"amount",true);
    builtin("cd",1,1,"luminous_intensity",true); builtin("N",1,1,"force",true); builtin("J",1,1,"energy",true);
    builtin("W",1,1,"power",true); builtin("Pa",1,1,"pressure",true); builtin("Hz",1,1,"frequency",true);
    builtin("C",1,1,"charge",true); builtin("V",1,1,"voltage",true); builtin("ohm",1,1,"resistance",true);
    builtin("S",1,1,"conductance",true); builtin("F",1,1,"capacitance",true); builtin("Wb",1,1,"magnetic_flux",true);
    builtin("T",1,1,"flux_density",true); builtin("H",1,1,"inductance",true); builtin("lx",1,1,"illuminance",true);
    builtin("kat",1,1,"catalytic_activity",true); builtin("L",1,1000,"volume",true); builtin("t",1000,1,"mass",false);
    builtin("min",60,1,"time",false); builtin("h",3600,1,"time",false); builtin("day",86400,1,"time",false);
    builtin("in",127,5000,"length",false); builtin("ft",381,1250,"length",false); builtin("yd",1143,1250,"length",false);
    builtin("mi",201168,125,"length",false); builtin("nmi",1852,1,"length",false); builtin("ha",10000,1,"area",false);
    builtin("kn",463,900,"speed",false); builtin("bar",100000,1,"pressure",true); builtin("atm",101325,1,"pressure",false);
    builtin("Torr",20265,152,"pressure",false); builtin("cal",523,125,"energy",true); builtin("Wh",3600,1,"energy",true);
    builtin("Ah",3600,1,"charge",true); builtin("dC",1,1,"temperature",false); builtin("dF",5,9,"temperature",false);
}
static bool resolve(const char *name, Quantity *result) {
    for (size_t i = 0; i < unit_count; i++) if (equal(name, units[i].symbol)) { *result = units[i].quantity; return true; }
    static const char *prefixes[] = {"G", "M", "k", "h", "da", "d", "c", "m", "u", "n"};
    static const Rational factors[] = {{1000000000,1}, {1000000,1}, {1000,1}, {100,1}, {10,1}, {1,10}, {1,100}, {1,1000}, {1,1000000}, {1,1000000000}};
    for (size_t p = 0; p < 10; p++) {
        size_t length = strlen(prefixes[p]);
        if (strncmp(name, prefixes[p], length) != 0) continue;
        for (size_t i = 0; i < 42; i++) if (units[i].prefix && equal(name + length, units[i].symbol)) {
            *result = units[i].quantity; result->value = multiply(factors[p], result->value); return true;
        }
    }
    return false;
}
static const char *simplified(Dimension dim) {
    for (size_t i = 0; i < unit_count; i++) if (units[i].quantity.value.n == 1 && units[i].quantity.value.d == 1 && same_dimension(dim, units[i].quantity.dim)) return units[i].symbol;
    return dimension_text(dim);
}
typedef struct { char name[13]; Quantity quantity; } Variable;
static Variable variables[50];
static size_t variable_count;
static Variable *find_variable(const char *name) {
    for (size_t i = 0; i < variable_count; i++) if (equal(name, variables[i].name)) return &variables[i];
    return NULL;
}

enum { TOKEN_END = 256, TOKEN_ID, TOKEN_NUMBER, TOKEN_UNIT, TOKEN_INVALID };
typedef struct { int kind; size_t start, end; char *text; } Token;
typedef struct { const char *source; Token tokens[201]; size_t count, position; } Parser;
typedef enum { LITERAL, UNIT_NAME, UNIT_VALUE, VARIABLE, BINARY, NEGATIVE, POWER, CALL } NodeKind;
typedef struct Node {
    NodeKind kind; char operation; char *text, *unit, *exponent;
    struct Node *left, *right, *args, *next;
    size_t argument_count; int exponent_number; Quantity resolved;
} Node;
static Node *node(NodeKind kind) { Node *result = allocate(sizeof *result); result->kind = kind; return result; }
static Node *binary_node(char operation, Node *left, Node *right) {
    Node *result = node(BINARY); result->operation = operation; result->left = left; result->right = right; return result;
}
static void tokenize(Parser *parser, const char *text, bool quantity) {
    *parser = (Parser){.source = text};
    size_t length = strlen(text), i = 0;
    while (i < length) {
        size_t start = i;
        int kind;
        if (letter(text[i])) { kind = TOKEN_ID; while (letter(text[i])) i++; }
        else if (digit(text[i])) {
            kind = TOKEN_NUMBER; while (digit(text[i])) i++;
            if (quantity && text[i] == '.' && digit(text[i + 1])) { i++; while (digit(text[i])) i++; }
        } else if (quantity && text[i] == '[' && text[i + 1] && text[i + 1] != ']' && strchr(text + i + 1, ']')) {
            kind = TOKEN_UNIT; i = (size_t)(strchr(text + i + 1, ']') - text) + 1;
        } else {
            kind = strchr(quantity ? "+-*/^()," : "*/^()-", text[i]) ? (unsigned char)text[i] : TOKEN_INVALID; i++;
        }
        parser->tokens[parser->count++] = (Token){kind, start, i, slice(text, start, i)};
    }
    parser->tokens[parser->count++] = (Token){TOKEN_END, length, length, ""};
}
static Token *current(Parser *parser) { return &parser->tokens[parser->position]; }
static void syntax(Parser *parser) {
    Token *token = current(parser);
    fail("SYNTAX %s AT %s", parser->source, token->kind == TOKEN_END ? "END" : format("%zu", token->start + 1));
}
static bool accept(Parser *parser, int kind) {
    if (current(parser)->kind != kind) return false;
    parser->position++; return true;
}
static void expect(Parser *parser, int kind) { if (!accept(parser, kind)) syntax(parser); }
static char *parse_exponent(Parser *parser) {
    size_t start = current(parser)->start;
    accept(parser, '-');
    Token *token = current(parser);
    if (token->kind != TOKEN_NUMBER || strchr(token->text, '.')) syntax(parser);
    parser->position++; return slice(parser->source, start, token->end);
}
static Node *unit_expression(Parser *parser);
static Node *unit_term(Parser *parser) {
    Token *token = current(parser);
    Node *result;
    if (accept(parser, TOKEN_ID)) { result = node(UNIT_NAME); result->text = token->text; }
    else if (token->kind == TOKEN_NUMBER && token->text[0] != '0') {
        parser->position++; result = node(LITERAL); result->text = token->text;
    } else if (accept(parser, '(')) { result = unit_expression(parser); expect(parser, ')'); }
    else { syntax(parser); return NULL; }
    if (accept(parser, '^')) {
        Node *power_node = node(POWER); power_node->left = result; power_node->exponent = parse_exponent(parser); result = power_node;
    }
    return result;
}
static Node *unit_expression(Parser *parser) {
    Node *one = node(LITERAL); one->text = "1";
    Node *result = binary_node('*', one, unit_term(parser));
    while (current(parser)->kind == '*' || current(parser)->kind == '/') {
        char operation = (char)current(parser)->kind; parser->position++;
        Node *right = unit_term(parser); result = binary_node(operation, result, right);
    }
    return result;
}
static void validate_units(Node *expression) {
    if (expression->kind == UNIT_NAME) {
        if (!resolve(expression->text, &expression->resolved)) fail("UNKNOWN UNIT %s", expression->text);
    } else if (expression->kind == POWER) {
        validate_units(expression->left); expression->exponent_number = exponent_value(expression->exponent);
    } else if (expression->kind == BINARY) {
        validate_units(expression->left); validate_units(expression->right);
    }
}
static Quantity evaluate_unit(Node *expression) {
    if (expression->kind == LITERAL) return (Quantity){number(expression->text), {{0}}};
    if (expression->kind == UNIT_NAME) return expression->resolved;
    Quantity left = evaluate_unit(expression->left);
    if (expression->kind == POWER) return (Quantity){power(left.value, expression->exponent_number), dimension_scale(left.dim, expression->exponent_number)};
    Quantity right = evaluate_unit(expression->right);
    return (Quantity){expression->operation == '*' ? multiply(left.value, right.value) : divide(left.value, right.value), dimension_add(left.dim, right.dim, expression->operation == '*' ? 1 : -1)};
}
static Node *parse_unit(const char *text) {
    Parser parser; tokenize(&parser, text, false);
    Node *expression = unit_expression(&parser);
    if (current(&parser)->kind != TOKEN_END) syntax(&parser);
    validate_units(expression); return expression;
}
static Quantity unit_value(const char *text) { return evaluate_unit(parse_unit(text)); }

typedef struct { Rational coefficient; int64_t exponents[201]; } Reduced;
typedef struct { const char *names[201]; size_t count; } NameOrder;
static Reduced reduce_node(Node *expression, NameOrder *order) {
    Reduced result = {.coefficient = ONE};
    if (expression->kind == LITERAL) { result.coefficient = number(expression->text); return result; }
    if (expression->kind == UNIT_NAME) {
        size_t index = 0;
        while (index < order->count && !equal(order->names[index], expression->text)) index++;
        if (index == order->count) order->names[order->count++] = expression->text;
        result.exponents[index] = 1; return result;
    }
    result = reduce_node(expression->left, order);
    if (expression->kind == POWER) {
        result.coefficient = power(result.coefficient, expression->exponent_number);
        for (size_t i = 0; i < order->count; i++) result.exponents[i] *= expression->exponent_number;
        return result;
    }
    Reduced right = reduce_node(expression->right, order);
    int sign = expression->operation == '*' ? 1 : -1;
    result.coefficient = sign == 1 ? multiply(result.coefficient, right.coefficient) : divide(result.coefficient, right.coefficient);
    for (size_t i = 0; i < order->count; i++) result.exponents[i] += sign * right.exponents[i];
    return result;
}
static char *reduced_text(Node *expression) {
    NameOrder order = {0}; Reduced reduced = reduce_node(expression, &order);
    char *result = reduced.coefficient.n == 1 && reduced.coefficient.d == 1 ? "" : fraction(reduced.coefficient);
    for (size_t i = 0; i < order.count; i++) if (reduced.exponents[i]) {
        const char *term = reduced.exponents[i] == 1 ? order.names[i] : format("%s^%" PRId64, order.names[i], reduced.exponents[i]);
        result = format("%s%s%s", result, *result ? " " : "", term);
    }
    return *result ? result : "1";
}

static Node *quantity_expression(Parser *parser);
static Node *quantity_primary(Parser *parser) {
    Token *token = current(parser);
    Node *result;
    if (accept(parser, TOKEN_NUMBER)) {
        result = node(LITERAL); result->text = token->text;
        if (current(parser)->kind == TOKEN_UNIT) {
            token = current(parser); parser->position++;
            result->kind = UNIT_VALUE; result->unit = slice(token->text, 1, strlen(token->text) - 1);
        }
    } else if (accept(parser, TOKEN_UNIT)) {
        result = node(UNIT_VALUE); result->text = "1"; result->unit = slice(token->text, 1, strlen(token->text) - 1);
    } else if (accept(parser, TOKEN_ID)) {
        result = node(VARIABLE); result->text = token->text;
        if (accept(parser, '(')) {
            result->kind = CALL;
            Node **next = &result->args;
            do {
                *next = quantity_expression(parser); next = &(*next)->next; result->argument_count++;
            } while (accept(parser, ','));
            expect(parser, ')');
        }
    } else if (accept(parser, '(')) { result = quantity_expression(parser); expect(parser, ')'); }
    else { syntax(parser); return NULL; }
    if (accept(parser, '^')) {
        Node *power_node = node(POWER); power_node->left = result; power_node->exponent = parse_exponent(parser); result = power_node;
    }
    return result;
}
static Node *quantity_unary(Parser *parser) {
    if (!accept(parser, '-')) return quantity_primary(parser);
    Node *result = node(NEGATIVE); result->left = quantity_unary(parser); return result;
}
static Node *quantity_product(Parser *parser) {
    Node *result = quantity_unary(parser);
    while (current(parser)->kind == '*' || current(parser)->kind == '/') {
        char operation = (char)current(parser)->kind; parser->position++;
        Node *right = quantity_unary(parser); result = binary_node(operation, result, right);
    }
    return result;
}
static Node *quantity_expression(Parser *parser) {
    Node *result = quantity_product(parser);
    while (current(parser)->kind == '+' || current(parser)->kind == '-') {
        char operation = (char)current(parser)->kind; parser->position++;
        Node *right = quantity_product(parser); result = binary_node(operation, result, right);
    }
    return result;
}
static int64_t integer_sqrt(int64_t n) {
    if (n < 2) return n;
    int64_t x = n, next = (n + 1) / 2;
    while (next < x) { x = next; next = (x + n / x) / 2; }
    return x;
}
static Quantity evaluate_quantity(Node *expression) {
    if (expression->kind == LITERAL) return (Quantity){number(expression->text), {{0}}};
    if (expression->kind == UNIT_VALUE) {
        Quantity result = unit_value(expression->unit);
        result.value = multiply(number(expression->text), result.value); return result;
    }
    if (expression->kind == VARIABLE) {
        Variable *variable = find_variable(expression->text);
        if (!variable) fail("UNKNOWN VARIABLE %s", expression->text);
        return variable->quantity;
    }
    if (expression->kind == CALL) {
        bool absolute = equal(expression->text, "abs"), root = equal(expression->text, "sqrt");
        bool minimum = equal(expression->text, "min"), maximum = equal(expression->text, "max");
        if (!absolute && !root && !minimum && !maximum) fail("UNKNOWN FUNCTION %s", expression->text);
        if (expression->argument_count != (absolute || root ? 1u : 2u)) fail("BAD ARGUMENTS %s", expression->text);
        Quantity left = evaluate_quantity(expression->args);
        if (absolute) { if (left.value.n < 0) left.value = negate(left.value); return left; }
        if (root) {
            if (left.value.n < 0) fail("NEGATIVE ROOT");
            for (int i = 0; i < 7; i++) if (left.dim.power[i] % 2) fail("ODD DIMENSION %s", dimension_text(left.dim));
            int64_t n = integer_sqrt(left.value.n), d = integer_sqrt(left.value.d);
            if (n * n != left.value.n || d * d != left.value.d) fail("NOT EXACT");
            left.value = rational(n, d);
            for (int i = 0; i < 7; i++) left.dim.power[i] /= 2;
            return left;
        }
        Quantity right = evaluate_quantity(expression->args->next);
        match_dimensions(left.dim, right.dim);
        int order = compare(left.value, right.value);
        return (minimum ? order <= 0 : order >= 0) ? left : right;
    }
    Quantity left = evaluate_quantity(expression->left);
    if (expression->kind == NEGATIVE) { left.value = negate(left.value); return left; }
    if (expression->kind == POWER) {
        int exponent = exponent_value(expression->exponent);
        if (!left.value.n && exponent < 0) fail("DIVISION BY ZERO");
        return (Quantity){power(left.value, exponent), dimension_scale(left.dim, exponent)};
    }
    Quantity right = evaluate_quantity(expression->right);
    if (expression->operation == '+' || expression->operation == '-') {
        match_dimensions(left.dim, right.dim);
        left.value = expression->operation == '+' ? add(left.value, right.value) : subtract(left.value, right.value);
        return left;
    }
    if (expression->operation == '/' && !right.value.n) fail("DIVISION BY ZERO");
    return (Quantity){expression->operation == '*' ? multiply(left.value, right.value) : divide(left.value, right.value), dimension_add(left.dim, right.dim, expression->operation == '*' ? 1 : -1)};
}
static Quantity quantity_value(const char *text) {
    Parser parser; tokenize(&parser, text, true);
    Node *expression = quantity_expression(&parser);
    if (current(&parser)->kind != TOKEN_END) syntax(&parser);
    return evaluate_quantity(expression);
}

static int unit_order(const void *left, const void *right) {
    const Unit *a = *(Unit *const *)left, *b = *(Unit *const *)right;
    int order = compare(a->quantity.value, b->quantity.value);
    return order ? order : strcmp(a->symbol, b->symbol);
}
static size_t select_units(Dimension dim, Unit **selected) {
    size_t count = 0;
    for (size_t i = 0; i < unit_count; i++) if (same_dimension(dim, units[i].quantity.dim)) selected[count++] = &units[i];
    qsort(selected, count, sizeof *selected, unit_order); return count;
}
static int variable_order(const void *left, const void *right) {
    const Variable *a = *(Variable *const *)left, *b = *(Variable *const *)right;
    return strcmp(a->name, b->name);
}
static void command(char **words, size_t count) {
    const char *name = words[0];
    if (equal(name, "DEFINE")) {
        check_name(words[1], false);
        Rational value = number(words[3]); Quantity unit = unit_value(words[4]), existing;
        if (find_kind(words[1]) || resolve(words[1], &existing)) fail("NAME TAKEN %s", words[1]);
        if (value.n <= 0) fail("NOT POSITIVE %s", words[3]);
        Rational factor = multiply(value, unit.value);
        Unit *created = &units[unit_count++]; *created = (Unit){0};
        strcpy(created->symbol, words[1]); created->quantity = (Quantity){factor, unit.dim};
        created->definition_value = value; strcpy(created->definition_unit, words[4]);
        printf("DEFINE %s factor=%s dim=%s kind=%s\n", words[1], fraction(factor), dimension_text(unit.dim), kind_name(unit.dim));
    } else if (equal(name, "UNDEF")) {
        size_t index = 0;
        while (index < unit_count && !equal(units[index].symbol, words[1])) index++;
        if (index < 42) fail("BUILTIN UNIT %s", words[1]);
        if (index == unit_count) fail("NOT DEFINED %s", words[1]);
        memmove(&units[index], &units[index + 1], (unit_count - index - 1) * sizeof *units);
        unit_count--; printf("UNDEF %s\n", words[1]);
    } else if (equal(name, "DEFS")) {
        printf("DEFS count=%zu\n", unit_count - 42);
        for (size_t i = 42; i < unit_count; i++) {
            Unit *unit = &units[i];
            printf("DEF %s = %s %s factor=%s dim=%s\n", unit->symbol, fraction(unit->definition_value), unit->definition_unit, fraction(unit->quantity.value), dimension_text(unit->quantity.dim));
        }
    } else if (equal(name, "CONVERT") || equal(name, "INVERT")) {
        Rational value = number(words[1]); Quantity from = unit_value(words[2]); Quantity to = unit_value(words[4]);
        bool inverse = equal(name, "INVERT");
        if (inverse) {
            if (dimensionless(from.dim) || !dimensionless(dimension_add(from.dim, to.dim, 1))) fail("NOT RECIPROCAL %s vs %s", dimension_text(from.dim), dimension_text(to.dim));
            if (!value.n) fail("DIVISION BY ZERO");
        } else match_dimensions(from.dim, to.dim);
        Rational result = multiply(value, from.value);
        if (inverse) result = divide(ONE, result);
        result = divide(result, to.value);
        printf("%s %s %s = %s\n", name, fraction(value), words[2], notation(result, words[4]));
    } else if (equal(name, "DIM") || equal(name, "REDUCE") || equal(name, "SIMPLIFY")) {
        Node *expression = parse_unit(words[1]); Quantity unit = evaluate_unit(expression);
        if (equal(name, "DIM")) printf("DIM %s = %s factor=%s kind=%s\n", words[1], dimension_text(unit.dim), fraction(unit.value), kind_name(unit.dim));
        else if (equal(name, "REDUCE")) printf("REDUCE %s = %s\n", words[1], reduced_text(expression));
        else printf("SIMPLIFY %s = %s\n", words[1], notation(unit.value, simplified(unit.dim)));
    } else if (equal(name, "ADD") || equal(name, "SUB") || equal(name, "MUL") || equal(name, "DIV") || equal(name, "COMPARE")) {
        Rational a = number(words[1]); Quantity first = unit_value(words[2]);
        Rational b = number(words[3]); Quantity second = unit_value(words[4]);
        bool target = count == 7;
        Quantity destination = target ? unit_value(words[6]) : first;
        if (equal(name, "ADD") || equal(name, "SUB") || equal(name, "COMPARE")) {
            match_dimensions(first.dim, second.dim);
            if (target) match_dimensions(first.dim, destination.dim);
            Rational left = multiply(a, first.value); Rational right = multiply(b, second.value);
            if (equal(name, "COMPARE")) {
                int relation = compare(left, right);
                const char *ratio = right.n ? fraction(divide(left, right)) : "undefined";
                printf("COMPARE %s %s %c %s %s ratio=%s\n", fraction(a), words[2], relation < 0 ? '<' : relation > 0 ? '>' : '=', fraction(b), words[4], ratio);
            } else {
                bool addition = equal(name, "ADD");
                Rational sum = addition ? add(left, right) : subtract(left, right);
                Rational result = divide(sum, destination.value);
                printf("%s %s %s %c %s %s = %s\n", name, fraction(a), words[2], addition ? '+' : '-', fraction(b), words[4], notation(result, target ? words[6] : words[2]));
            }
        } else {
            bool product = equal(name, "MUL");
            Dimension dim = dimension_add(first.dim, second.dim, product ? 1 : -1);
            if (!product && !b.n) fail("DIVISION BY ZERO");
            if (target) match_dimensions(dim, destination.dim);
            Rational raw = product ? multiply(a, b) : divide(a, b);
            Rational left = multiply(a, first.value); Rational right = multiply(b, second.value);
            Rational coherent = product ? multiply(left, right) : divide(left, right);
            printf("%s %s %s %c %s %s = ", name, fraction(a), words[2], product ? '*' : '/', fraction(b), words[4]);
            if (target) puts(notation(divide(coherent, destination.value), words[6]));
            else {
                const char *right_unit = !product && (strchr(words[4], '*') || strchr(words[4], '/')) ? format("(%s)", words[4]) : words[4];
                printf("%s %s%c%s = %s\n", fraction(raw), words[2], product ? '*' : '/', right_unit, notation(coherent, simplified(dim)));
            }
        }
    } else if (equal(name, "TEMP")) {
        Rational value = number(words[1]);
        if (strlen(words[2]) != 1 || !strchr("CFKR", words[2][0])) fail("UNKNOWN SCALE %s", words[2]);
        if (strlen(words[4]) != 1 || !strchr("CFKR", words[4][0])) fail("UNKNOWN SCALE %s", words[4]);
        Rational kelvin = value;
        if (equal(words[2], "C")) kelvin = add(value, rational(5463,20));
        else if (equal(words[2], "F")) { kelvin = add(value, rational(45967,100)); kelvin = multiply(kelvin, rational(5,9)); }
        else if (equal(words[2], "R")) kelvin = multiply(value, rational(5,9));
        if (kelvin.n < 0) fail("BELOW ABSOLUTE ZERO");
        Rational result = kelvin;
        if (equal(words[4], "C")) result = subtract(kelvin, rational(5463,20));
        else if (equal(words[4], "F")) { result = multiply(kelvin, rational(9,5)); result = subtract(result, rational(45967,100)); }
        else if (equal(words[4], "R")) result = multiply(kelvin, rational(9,5));
        printf("TEMP %s %s = %s\n", fraction(value), words[2], notation(result, words[4]));
    } else if (equal(name, "LIST") || equal(name, "TABLE")) {
        bool table = equal(name, "TABLE");
        Rational value = ONE; Quantity unit = {ONE, {{0}}}; Dimension dim;
        if (table) { value = number(words[1]); unit = unit_value(words[2]); dim = unit.dim; }
        else {
            const Kind *kind = find_kind(words[1]);
            dim = kind ? kind->dim : unit_value(words[1]).dim;
        }
        Unit *selected[72]; size_t length = select_units(dim, selected);
        if (table) printf("TABLE %s %s dim=%s count=%zu\n", fraction(value), words[2], dimension_text(dim), length);
        else printf("LIST %s dim=%s kind=%s count=%zu\n", words[1], dimension_text(dim), kind_name(dim), length);
        for (size_t i = 0; i < length; i++) {
            Unit *item = selected[i];
            if (table) {
                Rational coherent = multiply(value, unit.value); Rational result = divide(coherent, item->quantity.value);
                printf("ROW %s\n", notation(result, item->symbol));
            } else printf("UNIT %s factor=%s origin=%s prefix=%s\n", item->symbol, fraction(item->quantity.value), item->builtin ? "builtin" : "user", item->prefix ? "yes" : "no");
        }
    } else if (equal(name, "AUTO")) {
        Rational value = number(words[1]); Quantity unit = unit_value(words[2]);
        size_t index = 0;
        while (index < 42 && (!units[index].prefix || !same_dimension(unit.dim, units[index].quantity.dim))) index++;
        if (index == 42) fail("NO PREFIXABLE UNIT %s", dimension_text(unit.dim));
        Rational coherent = multiply(value, unit.value); Rational scaled = divide(coherent, units[index].quantity.value);
        Rational magnitude = scaled.n < 0 ? negate(scaled) : scaled;
        int exponent = 0;
        if (magnitude.n) {
            if (compare(magnitude, ONE) >= 0) {
                while (exponent < 9 && compare(magnitude, power(integer(10), exponent + 3)) >= 0) exponent += 3;
            } else {
                while (exponent > -9 && compare(magnitude, power(integer(10), exponent)) < 0) exponent -= 3;
            }
        }
        static const char *prefixes[] = {"n", "u", "m", "", "k", "M", "G"};
        const char *symbol = format("%s%s", prefixes[(exponent + 9) / 3], units[index].symbol);
        Rational result = divide(scaled, power(integer(10), exponent));
        printf("AUTO %s %s = %s\n", fraction(value), words[2], notation(result, symbol));
    } else if (equal(name, "SPLIT")) {
        Rational value = number(words[1]); Quantity unit = unit_value(words[2]);
        char *list = slice(words[4], 0, strlen(words[4])), *parts[5];
        size_t length = 1; parts[0] = list;
        for (char *p = list; *p; p++) if (*p == ',') { *p = '\0'; parts[length++] = p + 1; }
        Quantity destinations[5];
        for (size_t i = 0; i < length; i++) destinations[i] = unit_value(parts[i]);
        if (value.n < 0) fail("NEGATIVE VALUE");
        for (size_t i = 0; i < length; i++) match_dimensions(unit.dim, destinations[i].dim);
        for (size_t i = 0; i + 1 < length; i++) if (compare(destinations[i].value, destinations[i + 1].value) <= 0) fail("UNIT ORDER");
        Rational remaining = multiply(value, unit.value);
        printf("SPLIT %s %s = ", fraction(value), words[2]);
        for (size_t i = 0; i + 1 < length; i++) {
            Rational quotient = divide(remaining, destinations[i].value); int64_t count_unit = quotient.n / quotient.d;
            remaining = subtract(remaining, multiply(integer(count_unit), destinations[i].value));
            printf("%" PRId64 " %s ", count_unit, parts[i]);
        }
        puts(notation(divide(remaining, destinations[length - 1].value), parts[length - 1]));
    } else if (equal(name, "LET")) {
        check_name(words[1], true); Quantity quantity = quantity_value(words[3]);
        Variable *variable = find_variable(words[1]);
        if (!variable) { variable = &variables[variable_count++]; strcpy(variable->name, words[1]); }
        variable->quantity = quantity;
        printf("LET %s = %s\n", words[1], notation(quantity.value, simplified(quantity.dim)));
    } else if (equal(name, "EVAL")) {
        Quantity quantity = quantity_value(words[1]);
        if (count == 4) {
            Quantity unit = unit_value(words[3]); match_dimensions(quantity.dim, unit.dim);
            printf("EVAL %s = %s\n", words[1], notation(divide(quantity.value, unit.value), words[3]));
        } else printf("EVAL %s = %s\n", words[1], notation(quantity.value, simplified(quantity.dim)));
    } else if (equal(name, "VARS")) {
        Variable *ordered[50];
        for (size_t i = 0; i < variable_count; i++) ordered[i] = &variables[i];
        qsort(ordered, variable_count, sizeof *ordered, variable_order);
        printf("VARS count=%zu\n", variable_count);
        for (size_t i = 0; i < variable_count; i++) printf("VAR %s = %s\n", ordered[i]->name, notation(ordered[i]->quantity.value, simplified(ordered[i]->quantity.dim)));
    } else fail("UNKNOWN COMMAND %s", name);
}

int main(void) {
    initialize_units();
    char line[256];
    if (!fgets(line, sizeof line, stdin)) return 0;
    int count = atoi(line);
    for (int i = 0; i < count; i++) {
        if (!fgets(line, sizeof line, stdin)) break;
        line[strcspn(line, "\r\n")] = '\0';
        char *words[201]; size_t word_count = 0;
        for (char *word = strtok(line, " "); word; word = strtok(NULL, " ")) words[word_count++] = word;
        if (!setjmp(failure)) command(words, word_count);
        release_temporary();
    }
    return 0;
}
