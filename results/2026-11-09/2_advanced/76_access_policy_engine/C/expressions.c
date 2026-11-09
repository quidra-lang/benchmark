#include "policy.h"
typedef struct {
    Names tokens;
    size_t position;
} Parser;
static char *peek(Parser *p) {
    return p->position < p->tokens.count ? p->tokens.items[p->position] : "";
}
static char *take(Parser *p) { return p->tokens.items[p->position++]; }
static Expression *node(char *op) {
    Expression *e = allocate(sizeof(*e));
    e->operation = op;
    return e;
}
static Expression *unary_node(char *op, Expression *a) {
    Expression *e = node(op);
    Expressions_add(&e->arguments, a);
    return e;
}
static Expression *binary_node(char *op, Expression *a, Expression *b) {
    Expression *e = unary_node(op, a);
    Expressions_add(&e->arguments, b);
    return e;
}
static Expression *disjunction(Parser *p), *primary(Parser *p);
static Expression *unary(Parser *p) {
    if (!strcmp(peek(p), "-")) {
        take(p);
        return unary_node("-", unary(p));
    }
    return primary(p);
}
static Expression *joined(Parser *p, Expression *(*next)(Parser *), const char *first,
                          const char *second) {
    Expression *e = next(p);
    while (!strcmp(peek(p), first) || (second && !strcmp(peek(p), second))) {
        char *op = take(p);
        e = binary_node(op, e, next(p));
    }
    return e;
}
static Expression *product(Parser *p) { return joined(p, unary, "*", NULL); }
static Expression *sum(Parser *p) { return joined(p, product, "+", "-"); }
static Expression *comparison(Parser *p) {
    Expression *e = sum(p);
    char *op = peek(p);
    if (!strcmp(op, "==") || !strcmp(op, "!=") || !strcmp(op, "<") || !strcmp(op, "<=") ||
        !strcmp(op, ">") || !strcmp(op, ">=") || !strcmp(op, "in")) {
        take(p);
        e = binary_node(op, e, sum(p));
    }
    return e;
}
static Expression *negation(Parser *p) {
    if (!strcmp(peek(p), "not")) {
        take(p);
        return unary_node("not", negation(p));
    }
    return comparison(p);
}
static Expression *conjunction(Parser *p) { return joined(p, negation, "and", NULL); }
static Expression *disjunction(Parser *p) { return joined(p, conjunction, "or", NULL); }
static Expression *primary(Parser *p) {
    char *token = take(p);
    Expression *out = node("literal");
    if (token[0] >= '0' && token[0] <= '9')
        out->literal = number_value(atoi(token));
    else if (token[0] == '"')
        out->literal = word_value(substring(token + 1, strlen(token) - 2));
    else if (!strcmp(token, "true") || !strcmp(token, "false"))
        out->literal = bool_value(!strcmp(token, "true"));
    else if (!strcmp(token, "it"))
        out->operation = "it";
    else if (strchr(token, '.')) {
        out->operation = "attribute";
        out->literal = word_value(token);
    } else if (!strcmp(token, "(")) {
        out = disjunction(p);
        take(p);
    } else if (!strcmp(token, "[")) {
        Names values = {0};
        while (strcmp(peek(p), "]")) {
            char *item = take(p);
            Names_add(&values, substring(item + 1, strlen(item) - 2));
            if (strcmp(peek(p), "]"))
                take(p);
        }
        take(p);
        out->literal = bag_value(values);
    } else {
        out->operation = token;
        take(p);
        while (strcmp(peek(p), ")")) {
            Expressions_add(&out->arguments, disjunction(p));
            if (strcmp(peek(p), ")"))
                take(p);
        }
        take(p);
    }
    return out;
}
static bool letter(char c) { return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'); }
Expression *parse_expression(const char *source) {
    Parser p = {0};
    size_t length = strlen(source);
    for (size_t i = 0; i < length;) {
        if (source[i] == ' ') {
            ++i;
            continue;
        }
        size_t start = i++;
        char c = source[start];
        if (c == '"') {
            while (source[i] != '"')
                ++i;
            ++i;
        } else if (letter(c) || (c >= '0' && c <= '9')) {
            bool word = letter(c);
            while (i < length &&
                   ((source[i] >= '0' && source[i] <= '9') ||
                    (word && (letter(source[i]) || source[i] == '_' || source[i] == '.'))))
                ++i;
        } else if (i < length && source[i] == '=' && (c == '=' || c == '!' || c == '<' || c == '>'))
            ++i;
        Names_add(&p.tokens, substring(source + start, i - start));
    }
    return disjunction(&p);
}
