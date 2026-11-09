#include "compiler.h"
Expr *new_expr(const char *kind, Token token) {
    Expr *result = ml_alloc(sizeof(*result));
    result->kind = kind;
    result->token = token;
    return result;
}
Statement *new_statement(const char *kind, Token token) {
    Statement *result = ml_alloc(sizeof(*result));
    result->kind = kind;
    result->token = token;
    return result;
}
static Token peek(Parser *p) { return p->tokens.items[p->index]; }
static void fail(Parser *p) {
    Token token = peek(p);
    compile_fail(p->context, "syntax", token.position,
                 equal(token.kind, "END") ? "unexpected end of program"
                                          : ml_format("unexpected '%s'", token.spelling));
}
static Token take(Parser *p, const char *kind) {
    if (!equal(peek(p).kind, kind))
        fail(p);
    return p->tokens.items[p->index++];
}
static bool accept(Parser *p, const char *kind) {
    if (!equal(peek(p).kind, kind))
        return false;
    ++p->index;
    return true;
}
static Expr *expression(Parser *, int);
static Statement *block(Parser *);
static Statement *statement(Parser *);
static Statement *simple(Parser *);
static Declaration *declaration_start(Parser *p) {
    if (!word_in("int bool void", peek(p).kind))
        fail(p);
    Token type = p->tokens.items[p->index++];
    Declaration *result = ml_alloc(sizeof(*result));
    result->type = equal(type.kind, "int")    ? TOY_INT
                   : equal(type.kind, "bool") ? TOY_BOOL
                                              : TOY_VOID;
    result->name = take(p, "identifier");
    return result;
}
Program *parse(Parser *p) {
    Program *result = ml_alloc(sizeof(*result));
    while (!equal(peek(p).kind, "END")) {
        Declaration *d = declaration_start(p);
        if (accept(p, "(")) {
            d->function = true;
            if (!accept(p, ")")) {
                Declaration *parameter = declaration_start(p);
                PUSH(d->parameters, parameter);
                while (accept(p, ",")) {
                    parameter = declaration_start(p);
                    PUSH(d->parameters, parameter);
                }
                take(p, ")");
            }
            d->body = block(p);
            PUSH(result->functions, d);
        } else {
            if (accept(p, "[")) {
                d->array = true;
                d->size = take(p, "integer");
                take(p, "]");
            } else if (accept(p, "="))
                d->initializer = expression(p, 1);
            take(p, ";");
            PUSH(result->globals, d);
        }
        PUSH(result->declarations, d);
    }
    result->end = peek(p);
    return result;
}
static Statement *block(Parser *p) {
    Statement *result = new_statement("block", take(p, "{"));
    while (!equal(peek(p).kind, "}")) {
        if (equal(peek(p).kind, "END"))
            fail(p);
        Statement *child;
        if (word_in("int bool void", peek(p).kind)) {
            Token start = peek(p);
            Declaration *d = declaration_start(p);
            if (accept(p, "="))
                d->initializer = expression(p, 1);
            take(p, ";");
            child = new_statement("declaration", start);
            child->declaration = d;
        } else
            child = statement(p);
        PUSH(result->statements, child);
    }
    result->close = take(p, "}");
    return result;
}
static Statement *statement(Parser *p) {
    Token token = peek(p);
    if (equal(token.kind, "{"))
        return block(p);
    ++p->index;
    Statement *result = new_statement(token.kind, token);
    if (equal(token.kind, "if")) {
        take(p, "(");
        result->condition = expression(p, 1);
        take(p, ")");
        result->yes = statement(p);
        if (accept(p, "else"))
            result->no = statement(p);
    } else if (equal(token.kind, "while")) {
        take(p, "(");
        result->condition = expression(p, 1);
        take(p, ")");
        result->body = statement(p);
    } else if (equal(token.kind, "for")) {
        take(p, "(");
        if (word_in("int bool void", peek(p).kind)) {
            Token start = peek(p);
            Declaration *d = declaration_start(p);
            take(p, "=");
            d->initializer = expression(p, 1);
            result->init = new_statement("declaration", start);
            result->init->declaration = d;
        } else if (!equal(peek(p).kind, ";"))
            result->init = simple(p);
        take(p, ";");
        if (!equal(peek(p).kind, ";"))
            result->condition = expression(p, 1);
        take(p, ";");
        if (!equal(peek(p).kind, ")"))
            result->update = simple(p);
        take(p, ")");
        result->body = statement(p);
    } else if (equal(token.kind, "break") || equal(token.kind, "continue"))
        take(p, ";");
    else if (equal(token.kind, "return")) {
        if (!equal(peek(p).kind, ";"))
            result->expr = expression(p, 1);
        take(p, ";");
    } else if (equal(token.kind, "print")) {
        take(p, "(");
        Expr *first = expression(p, 1);
        PUSH(result->expressions, first);
        while (accept(p, ",")) {
            Expr *next = expression(p, 1);
            PUSH(result->expressions, next);
        }
        take(p, ")");
        take(p, ";");
    } else if (equal(token.kind, "identifier") || equal(token.kind, "read")) {
        --p->index;
        result = simple(p);
        take(p, ";");
    } else {
        --p->index;
        fail(p);
    }
    return result;
}
static Expr *call(Parser *p, Token token) {
    take(p, "(");
    Expr *result = new_expr("call", token);
    if (!accept(p, ")")) {
        Expr *first = expression(p, 1);
        PUSH(result->children, first);
        while (accept(p, ",")) {
            Expr *next = expression(p, 1);
            PUSH(result->children, next);
        }
        take(p, ")");
    }
    return result;
}
static Statement *simple(Parser *p) {
    Token token = peek(p);
    if (accept(p, "read")) {
        take(p, "(");
        take(p, ")");
        Statement *result = new_statement("call", token);
        result->expr = new_expr("read", token);
        return result;
    }
    token = take(p, "identifier");
    if (equal(peek(p).kind, "(")) {
        Statement *result = new_statement("call", token);
        result->expr = call(p, token);
        return result;
    }
    Statement *result = new_statement("assignment", token);
    if (accept(p, "[")) {
        result->index = expression(p, 1);
        take(p, "]");
    }
    take(p, "=");
    result->expr = expression(p, 1);
    return result;
}
static int precedence(const char *op) {
    if (equal(op, "||"))
        return 1;
    if (equal(op, "&&"))
        return 2;
    if (equal(op, "==") || equal(op, "!="))
        return 3;
    if (word_in("< <= > >=", op))
        return 4;
    if (equal(op, "+") || equal(op, "-"))
        return 5;
    if (word_in("* / %", op))
        return 6;
    return 0;
}
static Expr *primary(Parser *p) {
    Token token = peek(p);
    if (accept(p, "integer")) {
        Expr *result = new_expr("integer", token);
        result->value = token.integer;
        return result;
    }
    if (equal(token.kind, "true") || equal(token.kind, "false")) {
        ++p->index;
        Expr *result = new_expr("boolean", token);
        result->value = equal(token.kind, "true");
        return result;
    }
    if (accept(p, "read")) {
        take(p, "(");
        take(p, ")");
        return new_expr("read", token);
    }
    if (accept(p, "(")) {
        Expr *result = expression(p, 1);
        take(p, ")");
        return result;
    }
    if (accept(p, "identifier")) {
        if (equal(peek(p).kind, "("))
            return call(p, token);
        if (accept(p, "[")) {
            Expr *index = expression(p, 1);
            take(p, "]");
            Expr *result = new_expr("array", token);
            PUSH(result->children, index);
            return result;
        }
        return new_expr("variable", token);
    }
    fail(p);
    return NULL;
}
static Expr *unary(Parser *p) {
    if (equal(peek(p).kind, "-") || equal(peek(p).kind, "!")) {
        Token token = p->tokens.items[p->index++];
        Expr *child = unary(p);
        Expr *result = new_expr("unary", token);
        PUSH(result->children, child);
        return result;
    }
    return primary(p);
}
static Expr *expression(Parser *p, int minimum) {
    Expr *left = unary(p);
    while (true) {
        int level = precedence(peek(p).kind);
        if (!level || level < minimum)
            break;
        Token op = p->tokens.items[p->index++];
        Expr *right = expression(p, level + 1);
        Expr *result = new_expr("binary", op);
        PUSH(result->children, left);
        PUSH(result->children, right);
        left = result;
    }
    return left;
}
