#include "ml.h"
static Expr *expression(Parser *);
static Expr *pattern(Parser *);
static Expr *type_expression(Parser *);
static Group *group(Parser *);
static Expr *node(const char *kind, Position position) {
    Expr *result = ml_alloc(sizeof(*result));
    result->kind = kind;
    result->position = position;
    return result;
}
static Expr *one(const char *kind, Position pos, Expr *child) {
    Expr *result = node(kind, pos);
    PUSH(result->children, child);
    return result;
}
static Expr *two(const char *kind, Position pos, Expr *first, Expr *second) {
    Expr *result = one(kind, pos, first);
    PUSH(result->children, second);
    return result;
}
Token parser_peek(Parser *parser) { return parser->tokens.items[parser->index]; }
static void syntax_error(Parser *parser) {
    parser->error = parser_peek(parser);
    longjmp(parser->jump, 1);
}
static bool accept(Parser *parser, const char *kind) {
    if (!equal(parser_peek(parser).kind, kind))
        return false;
    ++parser->index;
    return true;
}
static Token take(Parser *parser, const char *kind) {
    Token token = parser_peek(parser);
    if (!accept(parser, kind))
        syntax_error(parser);
    return token;
}
static Token name(Parser *parser) {
    if (!token_name(parser_peek(parser)))
        syntax_error(parser);
    return take(parser, "identifier");
}
void parser_recover(Parser *parser) {
    while (!equal(parser_peek(parser).kind, ";;") && !equal(parser_peek(parser).kind, "EOF"))
        ++parser->index;
    accept(parser, ";;");
}
Item *parser_item(Parser *parser) {
    Item *result = ml_alloc(sizeof(*result));
    if (accept(parser, "val")) {
        result->kind = "signature";
        result->name = name(parser);
        take(parser, ":");
        result->declared = type_expression(parser);
        take(parser, ";;");
        return result;
    }
    Token opening = parser_peek(parser);
    if (accept(parser, "let")) {
        Group *bindings = group(parser);
        if (accept(parser, "in")) {
            Expr *body = expression(parser);
            result->kind = "expression";
            result->expr = one("let", opening.position, body);
            result->expr->group = bindings;
        } else {
            result->kind = "declaration";
            result->group = bindings;
        }
    } else {
        result->kind = "expression";
        result->expr = expression(parser);
    }
    take(parser, ";;");
    return result;
}
static Binding *binding(Parser *parser) {
    Token identifier = name(parser);
    TokenList params = {0};
    while (equal(parser_peek(parser).kind, "identifier")) {
        Token param = take(parser, "identifier");
        PUSH(params, param);
    }
    take(parser, "=");
    Expr *value = expression(parser);
    for (int i = params.count - 1; i >= 0; --i) {
        value = one("fun", params.items[i].position, value);
        value->token = params.items[i];
    }
    Binding *result = ml_alloc(sizeof(*result));
    result->name = identifier;
    result->expr = value;
    return result;
}
static Group *group(Parser *parser) {
    Group *result = ml_alloc(sizeof(*result));
    Token rec = parser_peek(parser);
    if (accept(parser, "rec")) {
        result->recursive = true;
        result->rec = rec.position;
    }
    Binding *first = binding(parser);
    PUSH(result->bindings, first);
    while (accept(parser, "and")) {
        Binding *next = binding(parser);
        PUSH(result->bindings, next);
    }
    return result;
}
int operator_precedence(const char *op, bool *right) {
    *right = false;
    if (equal(op, "||")) {
        *right = true;
        return 1;
    }
    if (equal(op, "&&")) {
        *right = true;
        return 2;
    }
    if (word_in("= <> < > <= >=", op))
        return 3;
    if (equal(op, "::") || equal(op, "^")) {
        *right = true;
        return 4;
    }
    if (equal(op, "+") || equal(op, "-"))
        return 5;
    if (word_in("* / mod", op))
        return 6;
    return 0;
}
static Expr *atom(Parser *parser) {
    Token token = parser_peek(parser);
    Expr *result;
    if (equal(token.kind, "integer") || equal(token.kind, "string")) {
        ++parser->index;
        result = node(token.kind, token.position);
        result->value = token.value;
        result->integer = token.integer;
        return result;
    }
    if (equal(token.kind, "true") || equal(token.kind, "false")) {
        ++parser->index;
        result = node("boolean", token.position);
        result->value = (char *)token.kind;
        return result;
    }
    if (token_name(token)) {
        ++parser->index;
        result = node("name", token.position);
        result->value = token.spelling;
        return result;
    }
    if (accept(parser, "(")) {
        Expr *first = expression(parser);
        if (accept(parser, ",")) {
            Expr *second = expression(parser);
            take(parser, ")");
            return two("pair", token.position, first, second);
        }
        take(parser, ")");
        return first;
    }
    if (accept(parser, "[")) {
        result = node("list", token.position);
        if (!accept(parser, "]")) {
            Expr *first = expression(parser);
            PUSH(result->children, first);
            while (accept(parser, ";")) {
                Expr *next = expression(parser);
                PUSH(result->children, next);
            }
            take(parser, "]");
        }
        return result;
    }
    syntax_error(parser);
    return NULL;
}
static Expr *unary(Parser *parser) {
    Token token = parser_peek(parser);
    if (accept(parser, "-")) {
        Expr *child = unary(parser);
        Expr *result = one("negate", token.position, child);
        result->token = token;
        return result;
    }
    Expr *result = atom(parser);
    while (word_in("integer string true false ( [", parser_peek(parser).kind) ||
           token_name(parser_peek(parser))) {
        Expr *argument = atom(parser);
        result = two("apply", result->position, result, argument);
    }
    return result;
}
static Expr *binary(Parser *parser, int minimum) {
    Expr *left = unary(parser);
    while (true) {
        bool right;
        int precedence = operator_precedence(parser_peek(parser).kind, &right);
        if (!precedence || precedence < minimum)
            break;
        Token op = parser->tokens.items[parser->index++];
        Expr *second = binary(parser, precedence + (right ? 0 : 1));
        left = two("binary", left->position, left, second);
        left->token = op;
    }
    return left;
}
static Arm arm(Parser *parser) {
    Expr *pat = pattern(parser);
    take(parser, "->");
    Expr *body = expression(parser);
    return (Arm){pat, body};
}
static Expr *expression(Parser *parser) {
    Token opening = parser_peek(parser);
    if (accept(parser, "let")) {
        Group *bindings = group(parser);
        take(parser, "in");
        Expr *body = expression(parser);
        Expr *result = one("let", opening.position, body);
        result->group = bindings;
        return result;
    }
    if (accept(parser, "fun")) {
        TokenList parameters = {0};
        Token first = take(parser, "identifier");
        PUSH(parameters, first);
        while (equal(parser_peek(parser).kind, "identifier")) {
            Token next = take(parser, "identifier");
            PUSH(parameters, next);
        }
        take(parser, "->");
        Expr *result = expression(parser);
        for (int i = parameters.count - 1; i >= 0; --i) {
            result = one("fun", parameters.items[i].position, result);
            result->token = parameters.items[i];
        }
        result->position = opening.position;
        return result;
    }
    if (accept(parser, "if")) {
        Expr *condition = expression(parser);
        take(parser, "then");
        Expr *yes = expression(parser);
        take(parser, "else");
        Expr *no = expression(parser);
        Expr *result = two("if", opening.position, condition, yes);
        PUSH(result->children, no);
        return result;
    }
    if (accept(parser, "match")) {
        Expr *matched = expression(parser);
        take(parser, "with");
        accept(parser, "|");
        Expr *result = one("match", opening.position, matched);
        Arm first = arm(parser);
        PUSH(result->arms, first);
        while (accept(parser, "|")) {
            Arm next = arm(parser);
            PUSH(result->arms, next);
        }
        return result;
    }
    return binary(parser, 1);
}
static Expr *pattern_atom(Parser *parser) {
    Token token = parser_peek(parser);
    if (accept(parser, "identifier")) {
        Expr *result = node(equal(token.spelling, "_") ? "wildcard" : "name", token.position);
        result->value = token.spelling;
        return result;
    }
    if (accept(parser, "-")) {
        Token number = take(parser, "integer");
        Expr *result = node("integer", token.position);
        result->integer = -number.integer;
        return result;
    }
    if (word_in("integer string true false", token.kind))
        return atom(parser);
    if (accept(parser, "(")) {
        Expr *first = pattern(parser);
        if (accept(parser, ",")) {
            Expr *second = pattern(parser);
            take(parser, ")");
            return two("pair", token.position, first, second);
        }
        take(parser, ")");
        return first;
    }
    if (accept(parser, "[")) {
        Expr *result = node("list", token.position);
        if (!accept(parser, "]")) {
            Expr *first = pattern(parser);
            PUSH(result->children, first);
            while (accept(parser, ";")) {
                Expr *next = pattern(parser);
                PUSH(result->children, next);
            }
            take(parser, "]");
        }
        return result;
    }
    syntax_error(parser);
    return NULL;
}
static Expr *pattern(Parser *parser) {
    Expr *first = pattern_atom(parser);
    if (accept(parser, "::")) {
        Expr *rest = pattern(parser);
        return two("cons", first->position, first, rest);
    }
    return first;
}
static Expr *type_atom(Parser *parser) {
    Token token = parser_peek(parser);
    if (equal(token.kind, "identifier") && word_in("int bool string", token.spelling)) {
        ++parser->index;
        return node(token.spelling, token.position);
    }
    if (accept(parser, "type_variable")) {
        Expr *result = node("type_variable", token.position);
        result->value = token.spelling;
        return result;
    }
    if (accept(parser, "(")) {
        Expr *result = type_expression(parser);
        take(parser, ")");
        return result;
    }
    syntax_error(parser);
    return NULL;
}
static Expr *list_type(Parser *parser) {
    Expr *result = type_atom(parser);
    while (equal(parser_peek(parser).kind, "identifier") &&
           equal(parser_peek(parser).spelling, "list")) {
        ++parser->index;
        result = one("list", result->position, result);
    }
    return result;
}
static Expr *type_expression(Parser *parser) {
    Expr *result = list_type(parser);
    if (accept(parser, "*")) {
        Expr *second = list_type(parser);
        result = two("pair", result->position, result, second);
    }
    if (accept(parser, "->")) {
        Expr *second = type_expression(parser);
        result = two("function", result->position, result, second);
    }
    return result;
}
