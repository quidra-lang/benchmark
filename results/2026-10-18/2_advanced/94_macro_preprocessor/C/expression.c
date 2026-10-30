#include "preprocessor.h"
typedef struct {
    Tokens tokens;
    int index;
    jmp_buf jump;
    char *error;
} ExpressionParser;
static void expression_error(ExpressionParser *parser, const char *message) {
    parser->error = (char *)message;
    longjmp(parser->jump, 1);
}
static int digit_value(char c) {
    if (c >= '0' && c <= '9')
        return c - '0';
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    if (c >= 'A' && c <= 'F')
        return c - 'A' + 10;
    return -1;
}
static int64_t integer_constant(ExpressionParser *parser, const char *spelling) {
    char *text = ml_text(spelling, strlen(spelling));
    const char *suffixes[] = {"ll", "LL", "l", "L"};
    for (int i = 0; i < 4; ++i) {
        size_t n = strlen(text), s = strlen(suffixes[i]);
        if (n > s && equal(text + n - s, suffixes[i])) {
            text[n - s] = 0;
            break;
        }
    }
    int base = 10;
    size_t first = 0, n = strlen(text);
    bool valid = n > 0;
    if (n >= 2 && text[0] == '0' && (text[1] == 'x' || text[1] == 'X')) {
        base = 16;
        first = 2;
        if (first == n)
            valid = false;
    } else if (n && text[0] == '0')
        base = 8;
    else if (!n || text[0] < '1' || text[0] > '9')
        valid = false;
    for (size_t i = first; i < n; ++i) {
        int digit = digit_value(text[i]);
        if (digit < 0 || digit >= base)
            valid = false;
    }
    if (!valid)
        expression_error(parser, ml_format("invalid integer constant \"%s\"", spelling));
    int64_t value = 0;
    for (size_t i = first; i < n; ++i)
        value = value * base + digit_value(text[i]);
    return value;
}
static int64_t character_constant(ExpressionParser *parser, const char *spelling) {
    size_t length = strlen(spelling) - 2;
    const char *body = spelling + 1;
    if (length == 1 && body[0] != '\'' && body[0] != '\\')
        return (unsigned char)body[0];
    if (length == 2 && body[0] == '\\') {
        const char characters[] = {'n', 't', '\\', '\'', '"', '0'};
        const int values[] = {10, 9, 92, 39, 34, 0};
        for (int i = 0; i < 6; ++i)
            if (body[1] == characters[i])
                return values[i];
    }
    expression_error(parser, ml_format("invalid character constant %s", spelling));
    return 0;
}
static int precedence(const char *op) {
    if (equal(op, "||"))
        return 1;
    if (equal(op, "&&"))
        return 2;
    if (equal(op, "|"))
        return 3;
    if (equal(op, "^"))
        return 4;
    if (equal(op, "&"))
        return 5;
    if (equal(op, "==") || equal(op, "!="))
        return 6;
    if (word_in("< > <= >=", op))
        return 7;
    if (equal(op, "<<") || equal(op, ">>"))
        return 8;
    if (equal(op, "+") || equal(op, "-"))
        return 9;
    if (word_in("* / %", op))
        return 10;
    return 0;
}
static ConditionExpr *node(const char *kind) {
    ConditionExpr *result = ml_alloc(sizeof(*result));
    result->kind = kind;
    return result;
}
static const char *peek(ExpressionParser *parser) {
    return parser->index == parser->tokens.count ? ""
                                                 : parser->tokens.items[parser->index].spelling;
}
static ConditionExpr *expression(ExpressionParser *);
static ConditionExpr *primary(ExpressionParser *parser) {
    if (parser->index == parser->tokens.count)
        expression_error(parser, "expected value at end of expression");
    Token token = parser->tokens.items[parser->index++];
    if (equal(token.kind, "number") || equal(token.kind, "character")) {
        ConditionExpr *result = node("constant");
        result->value = equal(token.kind, "number") ? integer_constant(parser, token.spelling)
                                                    : character_constant(parser, token.spelling);
        return result;
    }
    if (equal(token.kind, "identifier")) {
        ConditionExpr *result = node("identifier");
        result->name = token.spelling;
        return result;
    }
    if (equal(token.spelling, "(")) {
        ConditionExpr *result = expression(parser);
        if (!equal(peek(parser), ")"))
            expression_error(parser, "missing ')' in expression");
        ++parser->index;
        return result;
    }
    expression_error(parser, ml_format("expected value before \"%s\"", token.spelling));
    return NULL;
}
static ConditionExpr *unary(ExpressionParser *parser) {
    if (word_in("+ - ! ~", peek(parser))) {
        const char *op = peek(parser);
        ++parser->index;
        ConditionExpr *result = node("unary");
        result->op = op;
        result->first = unary(parser);
        return result;
    }
    return primary(parser);
}
static ConditionExpr *binary(ExpressionParser *parser, int minimum) {
    ConditionExpr *left = unary(parser);
    while (true) {
        int level = precedence(peek(parser));
        if (!level || level < minimum)
            break;
        const char *op = peek(parser);
        ++parser->index;
        ConditionExpr *right = binary(parser, level + 1);
        ConditionExpr *result = node("binary");
        result->op = op;
        result->first = left;
        result->second = right;
        left = result;
    }
    return left;
}
static ConditionExpr *expression(ExpressionParser *parser) {
    ConditionExpr *first = binary(parser, 1);
    if (equal(peek(parser), "?")) {
        ++parser->index;
        ConditionExpr *second = expression(parser);
        if (!equal(peek(parser), ":"))
            expression_error(parser, "'?' without following ':'");
        ++parser->index;
        ConditionExpr *third = expression(parser);
        ConditionExpr *result = node("conditional");
        result->first = first;
        result->second = second;
        result->third = third;
        return result;
    }
    return first;
}
ConditionExpr *parse_condition(Tokens tokens, const char *directive, char **error) {
    ExpressionParser *parser = ml_alloc(sizeof(*parser));
    parser->tokens = tokens;
    if (setjmp(parser->jump)) {
        *error = parser->error;
        return NULL;
    }
    if (!tokens.count)
        expression_error(parser, ml_format("#%s with no expression", directive));
    ConditionExpr *result = expression(parser);
    if (parser->index < tokens.count)
        expression_error(parser, ml_format("missing binary operator before \"%s\"", peek(parser)));
    *error = NULL;
    return result;
}
bool evaluate_condition(Preprocessor *p, Position position, ConditionExpr *e, int64_t *value,
                        char **error) {
    if (equal(e->kind, "constant")) {
        *value = e->value;
        return true;
    }
    if (equal(e->kind, "identifier")) {
        diagnostic(p, position, "warning", ml_format("identifier \"%s\" evaluates to 0", e->name));
        *value = 0;
        return true;
    }
    int64_t a, b;
    if (!evaluate_condition(p, position, e->first, &a, error))
        return false;
    if (equal(e->kind, "unary")) {
        *value = equal(e->op, "+")   ? a
                 : equal(e->op, "-") ? -a
                 : equal(e->op, "!") ? (a == 0)
                                     : -a - 1;
        return true;
    }
    if (equal(e->kind, "conditional"))
        return evaluate_condition(p, position, a ? e->second : e->third, value, error);
    if (equal(e->op, "&&") && !a) {
        *value = 0;
        return true;
    }
    if (equal(e->op, "||") && a) {
        *value = 1;
        return true;
    }
    if (!evaluate_condition(p, position, e->second, &b, error))
        return false;
    if (equal(e->op, "+"))
        *value = a + b;
    else if (equal(e->op, "-"))
        *value = a - b;
    else if (equal(e->op, "*"))
        *value = a * b;
    else if (equal(e->op, "/") || equal(e->op, "%")) {
        if (!b) {
            *error = "division by zero in #if";
            return false;
        }
        int64_t q = a / b;
        *value = equal(e->op, "/") ? q : a - b * q;
    } else if (equal(e->op, "<<"))
        *value = a * (INT64_C(1) << b);
    else if (equal(e->op, ">>")) {
        int64_t divisor = INT64_C(1) << b, q = a / divisor;
        if (a < 0 && a % divisor)
            --q;
        *value = q;
    } else if (equal(e->op, "&") || equal(e->op, "|") || equal(e->op, "^")) {
        uint32_t left = (uint32_t)a, right = (uint32_t)b;
        uint32_t result = equal(e->op, "&")   ? left & right
                          : equal(e->op, "|") ? left | right
                                              : left ^ right;
        *value = result >= UINT32_C(0x80000000) ? (int64_t)result - INT64_C(4294967296) : result;
    } else if (equal(e->op, "=="))
        *value = a == b;
    else if (equal(e->op, "!="))
        *value = a != b;
    else if (equal(e->op, "<"))
        *value = a < b;
    else if (equal(e->op, ">"))
        *value = a > b;
    else if (equal(e->op, "<="))
        *value = a <= b;
    else if (equal(e->op, ">="))
        *value = a >= b;
    else
        *value = b != 0;
    return true;
}
