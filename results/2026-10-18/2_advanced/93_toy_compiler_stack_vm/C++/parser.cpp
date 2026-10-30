#include "compiler.hpp"
static std::vector<std::unique_ptr<Expr>> expressions;
static std::vector<std::unique_ptr<Statement>> statements;
static std::vector<std::unique_ptr<Declaration>> declarations;
Expr *new_expr(const std::string &kind, Token token, std::vector<Expr *> children) {
    expressions.push_back(std::make_unique<Expr>());
    Expr *result = expressions.back().get();
    result->kind = kind;
    result->token = std::move(token);
    result->children = std::move(children);
    return result;
}
Statement *new_statement(const std::string &kind, Token token) {
    statements.push_back(std::make_unique<Statement>());
    Statement *result = statements.back().get();
    result->kind = kind;
    result->token = std::move(token);
    return result;
}
const Token &Parser::peek() const { return tokens[index]; }
void Parser::fail() const {
    const Token &token = peek();
    throw CompileError{"syntax",
                       token.kind == "END" ? "unexpected end of program"
                                           : "unexpected '" + token.spelling + "'",
                       token.position};
}
Token Parser::take(const std::string &kind) {
    if (peek().kind != kind)
        fail();
    return tokens[index++];
}
bool Parser::accept(const std::string &kind) {
    if (peek().kind != kind)
        return false;
    ++index;
    return true;
}
Declaration *Parser::declaration_start() {
    if (!word_in("int bool void", peek().kind))
        fail();
    std::string type = tokens[index++].kind;
    Token name = take("identifier");
    declarations.push_back(std::make_unique<Declaration>());
    Declaration *result = declarations.back().get();
    result->type = type;
    result->name = name;
    return result;
}
Program Parser::program() {
    Program result;
    while (peek().kind != "END") {
        Declaration *d = declaration_start();
        if (accept("(")) {
            d->function = true;
            if (!accept(")")) {
                d->parameters.push_back(declaration_start());
                while (accept(","))
                    d->parameters.push_back(declaration_start());
                take(")");
            }
            d->body = block();
            result.functions.push_back(d);
        } else {
            if (accept("[")) {
                d->array = true;
                d->size = take("integer");
                take("]");
            } else if (accept("="))
                d->initializer = expression();
            take(";");
            result.globals.push_back(d);
        }
        result.declarations.push_back(d);
    }
    result.end = peek();
    return result;
}
Statement *Parser::block() {
    Statement *result = new_statement("block", take("{"));
    while (peek().kind != "}") {
        if (peek().kind == "END")
            fail();
        if (word_in("int bool void", peek().kind)) {
            Token start = peek();
            Declaration *d = declaration_start();
            if (accept("="))
                d->initializer = expression();
            take(";");
            Statement *statement = new_statement("declaration", start);
            statement->declaration = d;
            result->statements.push_back(statement);
        } else
            result->statements.push_back(statement());
    }
    result->close = take("}");
    return result;
}
Statement *Parser::statement() {
    Token token = peek();
    if (token.kind == "{")
        return block();
    ++index;
    Statement *result = new_statement(token.kind, token);
    if (token.kind == "if") {
        take("(");
        result->condition = expression();
        take(")");
        result->yes = statement();
        if (accept("else"))
            result->no = statement();
    } else if (token.kind == "while") {
        take("(");
        result->condition = expression();
        take(")");
        result->body = statement();
    } else if (token.kind == "for") {
        take("(");
        if (word_in("int bool void", peek().kind)) {
            Token start = peek();
            Declaration *d = declaration_start();
            take("=");
            d->initializer = expression();
            result->init = new_statement("declaration", start);
            result->init->declaration = d;
        } else if (peek().kind != ";")
            result->init = simple();
        take(";");
        if (peek().kind != ";")
            result->condition = expression();
        take(";");
        if (peek().kind != ")")
            result->update = simple();
        take(")");
        result->body = statement();
    } else if (token.kind == "break" || token.kind == "continue")
        take(";");
    else if (token.kind == "return") {
        if (peek().kind != ";")
            result->expr = expression();
        take(";");
    } else if (token.kind == "print") {
        take("(");
        result->expressions.push_back(expression());
        while (accept(","))
            result->expressions.push_back(expression());
        take(")");
        take(";");
    } else if (token.kind == "identifier" || token.kind == "read") {
        --index;
        result = simple();
        take(";");
    } else {
        --index;
        fail();
    }
    return result;
}
Expr *Parser::call(Token token) {
    take("(");
    std::vector<Expr *> args;
    if (!accept(")")) {
        args.push_back(expression());
        while (accept(","))
            args.push_back(expression());
        take(")");
    }
    return new_expr("call", token, std::move(args));
}
Statement *Parser::simple() {
    Token token = peek();
    if (accept("read")) {
        take("(");
        take(")");
        Statement *result = new_statement("call", token);
        result->expr = new_expr("read", token);
        return result;
    }
    token = take("identifier");
    if (peek().kind == "(") {
        Statement *result = new_statement("call", token);
        result->expr = call(token);
        return result;
    }
    Statement *result = new_statement("assignment", token);
    if (accept("[")) {
        result->index = expression();
        take("]");
    }
    take("=");
    result->expr = expression();
    return result;
}
static int precedence(const std::string &op) {
    if (op == "||")
        return 1;
    if (op == "&&")
        return 2;
    if (op == "==" || op == "!=")
        return 3;
    if (word_in("< <= > >=", op))
        return 4;
    if (op == "+" || op == "-")
        return 5;
    if (word_in("* / %", op))
        return 6;
    return 0;
}
Expr *Parser::expression(int minimum) {
    Expr *left = unary();
    while (true) {
        int level = precedence(peek().kind);
        if (!level || level < minimum)
            break;
        Token op = tokens[index++];
        Expr *right = expression(level + 1);
        left = new_expr("binary", op, {left, right});
    }
    return left;
}
Expr *Parser::unary() {
    if (peek().kind == "-" || peek().kind == "!") {
        Token op = tokens[index++];
        Expr *child = unary();
        return new_expr("unary", op, {child});
    }
    return primary();
}
Expr *Parser::primary() {
    Token token = peek();
    if (accept("integer")) {
        Expr *result = new_expr("integer", token);
        result->value = token.integer;
        return result;
    }
    if (token.kind == "true" || token.kind == "false") {
        ++index;
        Expr *result = new_expr("boolean", token);
        result->value = token.kind == "true";
        return result;
    }
    if (accept("read")) {
        take("(");
        take(")");
        return new_expr("read", token);
    }
    if (accept("(")) {
        Expr *result = expression();
        take(")");
        return result;
    }
    if (accept("identifier")) {
        if (peek().kind == "(")
            return call(token);
        if (accept("[")) {
            Expr *index = expression();
            take("]");
            return new_expr("array", token, {index});
        }
        return new_expr("variable", token);
    }
    fail();
    return nullptr;
}
