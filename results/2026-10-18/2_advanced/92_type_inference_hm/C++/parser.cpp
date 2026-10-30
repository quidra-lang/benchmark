#include "ml.hpp"
static std::vector<std::unique_ptr<Expr>> expressions;
static std::vector<std::unique_ptr<Group>> groups;
static std::vector<std::unique_ptr<Binding>> bindings;
static Expr *node(const std::string &kind, const Position &position,
                  std::vector<Expr *> children = {}) {
    expressions.push_back(std::make_unique<Expr>());
    Expr *result = expressions.back().get();
    result->kind = kind;
    result->position = position;
    result->children = std::move(children);
    return result;
}
const Token &Parser::peek() const { return tokens[index]; }
bool Parser::accept(const std::string &kind) {
    if (peek().kind != kind)
        return false;
    ++index;
    return true;
}
Token Parser::take(const std::string &kind) {
    Token token = peek();
    if (!accept(kind))
        throw SyntaxError{token};
    return token;
}
Token Parser::name() {
    if (!peek().name())
        throw SyntaxError{peek()};
    return take("identifier");
}
void Parser::recover_item() {
    while (peek().kind != ";;" && peek().kind != "EOF")
        ++index;
    accept(";;");
}
Item Parser::item() {
    Item result;
    if (accept("val")) {
        result.kind = "signature";
        result.name = name();
        take(":");
        result.declared = type_expression();
        take(";;");
        return result;
    }
    Token opening = peek();
    if (accept("let")) {
        result.group = group();
        if (accept("in")) {
            result.kind = "expression";
            result.expr = node("let", opening.position, {expression()});
            result.expr->group = result.group;
            result.group = nullptr;
        } else
            result.kind = "declaration";
    } else {
        result.kind = "expression";
        result.expr = expression();
    }
    take(";;");
    return result;
}
Group *Parser::group() {
    groups.push_back(std::make_unique<Group>());
    Group *result = groups.back().get();
    Token rec = peek();
    if (accept("rec"))
        result->rec = rec.position;
    result->bindings.push_back(binding());
    while (accept("and"))
        result->bindings.push_back(binding());
    return result;
}
Binding *Parser::binding() {
    Token identifier = name();
    std::vector<Token> parameters;
    while (peek().kind == "identifier")
        parameters.push_back(take("identifier"));
    take("=");
    Expr *value = expression();
    for (auto it = parameters.rbegin(); it != parameters.rend(); ++it) {
        Expr *fun = node("fun", it->position, {value});
        fun->token = *it;
        value = fun;
    }
    bindings.push_back(std::make_unique<Binding>());
    Binding *result = bindings.back().get();
    result->name = identifier;
    result->expr = value;
    return result;
}
std::pair<int, bool> operator_info(const std::string &op) {
    if (op == "||")
        return {1, true};
    if (op == "&&")
        return {2, true};
    if (word_in("= <> < > <= >=", op))
        return {3, false};
    if (op == "::" || op == "^")
        return {4, true};
    if (op == "+" || op == "-")
        return {5, false};
    if (word_in("* / mod", op))
        return {6, false};
    return {0, false};
}
Expr *Parser::expression() {
    Token opening = peek();
    if (accept("let")) {
        Group *bindings = group();
        take("in");
        Expr *result = node("let", opening.position, {expression()});
        result->group = bindings;
        return result;
    }
    if (accept("fun")) {
        std::vector<Token> parameters = {take("identifier")};
        while (peek().kind == "identifier")
            parameters.push_back(take("identifier"));
        take("->");
        Expr *result = expression();
        for (auto it = parameters.rbegin(); it != parameters.rend(); ++it) {
            Expr *fun = node("fun", it->position, {result});
            fun->token = *it;
            result = fun;
        }
        result->position = opening.position;
        return result;
    }
    if (accept("if")) {
        Expr *condition = expression();
        take("then");
        Expr *yes = expression();
        take("else");
        Expr *no = expression();
        return node("if", opening.position, {condition, yes, no});
    }
    if (accept("match")) {
        Expr *matched = expression();
        take("with");
        accept("|");
        std::vector<Arm> arms = {arm()};
        while (accept("|"))
            arms.push_back(arm());
        Expr *result = node("match", opening.position, {matched});
        result->arms = std::move(arms);
        return result;
    }
    return binary(1);
}
Arm Parser::arm() {
    Expr *p = pattern();
    take("->");
    Expr *body = expression();
    return {p, body};
}
Expr *Parser::binary(int minimum) {
    Expr *left = unary();
    while (true) {
        std::pair<int, bool> info = operator_info(peek().kind);
        if (info.first == 0 || info.first < minimum)
            break;
        Token op = tokens[index++];
        Expr *right = binary(info.first + (info.second ? 0 : 1));
        Expr *result = node("binary", left->position, {left, right});
        result->token = op;
        left = result;
    }
    return left;
}
Expr *Parser::unary() {
    Token op = peek();
    if (accept("-")) {
        Expr *result = node("negate", op.position, {unary()});
        result->token = op;
        return result;
    }
    Expr *result = atom();
    while (word_in("integer string true false ( [", peek().kind) || peek().name()) {
        Expr *arg = atom();
        result = node("apply", result->position, {result, arg});
    }
    return result;
}
Expr *Parser::atom() {
    Token token = peek();
    Expr *result = nullptr;
    if (token.kind == "integer" || token.kind == "string") {
        ++index;
        result = node(token.kind, token.position);
        result->value = token.value;
        result->integer = token.integer;
        return result;
    }
    if (token.kind == "true" || token.kind == "false") {
        ++index;
        result = node("boolean", token.position);
        result->value = token.kind;
        return result;
    }
    if (token.name()) {
        ++index;
        result = node("name", token.position);
        result->value = token.spelling;
        return result;
    }
    if (accept("(")) {
        Expr *first = expression();
        if (accept(",")) {
            Expr *second = expression();
            take(")");
            return node("pair", token.position, {first, second});
        }
        take(")");
        return first;
    }
    if (accept("[")) {
        std::vector<Expr *> elements;
        if (!accept("]")) {
            elements.push_back(expression());
            while (accept(";"))
                elements.push_back(expression());
            take("]");
        }
        return node("list", token.position, std::move(elements));
    }
    throw SyntaxError{token};
}
Expr *Parser::pattern() {
    Expr *first = pattern_atom();
    if (accept("::")) {
        Expr *rest = pattern();
        return node("cons", first->position, {first, rest});
    }
    return first;
}
Expr *Parser::pattern_atom() {
    Token token = peek();
    if (accept("identifier")) {
        Expr *result = node(token.spelling == "_" ? "wildcard" : "name", token.position);
        result->value = token.spelling;
        return result;
    }
    if (accept("-")) {
        Token number = take("integer");
        Expr *result = node("integer", token.position);
        result->integer = -number.integer;
        return result;
    }
    if (word_in("integer string true false", token.kind))
        return atom();
    if (accept("(")) {
        Expr *first = pattern();
        if (accept(",")) {
            Expr *second = pattern();
            take(")");
            return node("pair", token.position, {first, second});
        }
        take(")");
        return first;
    }
    if (accept("[")) {
        std::vector<Expr *> elements;
        if (!accept("]")) {
            elements.push_back(pattern());
            while (accept(";"))
                elements.push_back(pattern());
            take("]");
        }
        return node("list", token.position, std::move(elements));
    }
    throw SyntaxError{token};
}
Expr *Parser::type_expression() {
    Expr *result = list_type();
    if (accept("*")) {
        Expr *second = list_type();
        result = node("pair", result->position, {result, second});
    }
    if (accept("->")) {
        Expr *second = type_expression();
        result = node("function", result->position, {result, second});
    }
    return result;
}
Expr *Parser::list_type() {
    Expr *result = type_atom();
    while (peek().kind == "identifier" && peek().spelling == "list") {
        ++index;
        result = node("list", result->position, {result});
    }
    return result;
}
Expr *Parser::type_atom() {
    Token token = peek();
    if (token.kind == "identifier" && word_in("int bool string", token.spelling)) {
        ++index;
        return node(token.spelling, token.position);
    }
    if (accept("type_variable")) {
        Expr *result = node("type_variable", token.position);
        result->value = token.spelling;
        return result;
    }
    if (accept("(")) {
        Expr *result = type_expression();
        take(")");
        return result;
    }
    throw SyntaxError{token};
}
