#include "formatter.hpp"
Nodes nodeChildren(const Node &node) {
    Nodes out;
    for (const NodePtr &child : {node.expr, node.left, node.right, node.thenPart, node.elsePart,
                                 node.body, node.init, node.condition, node.update})
        if (child)
            out.push_back(child);
    out.insert(out.end(), node.elements.begin(), node.elements.end());
    out.insert(out.end(), node.dimensions.begin(), node.dimensions.end());
    return out;
}
bool typeName(const Token *token) { return wordIn("int float bool string void", token->value); }
int precedence(const std::string &op) {
    if (op == "||")
        return 1;
    if (op == "&&")
        return 2;
    if (op == "==" || op == "!=")
        return 3;
    if (wordIn("< <= > >=", op))
        return 4;
    if (op == "+" || op == "-")
        return 5;
    if (wordIn("* / %", op))
        return 6;
    return 0;
}
int expressionLevel(const NodePtr &node) {
    if (node->kind == NodeKind::Conditional)
        return 0;
    if (node->kind == NodeKind::Binary)
        return precedence(node->op->value);
    if (node->kind == NodeKind::Unary)
        return 7;
    return 8;
}
static NodePtr makeNode(NodeKind kind) {
    NodePtr out = std::make_shared<Node>();
    out->kind = kind;
    return out;
}
Token *Parser::peek() const {
    return tokens[std::min(position, static_cast<int>(tokens.size()) - 1)].get();
}
Token *Parser::read() {
    Token *token = peek();
    if (position < static_cast<int>(tokens.size()) - 1)
        ++position;
    return token;
}
void Parser::fail(const std::string &expected) const {
    Token *token = peek();
    throw FileError{token->position,
                    "expected " + expected + ", found " +
                        (token->kind == TokenKind::End ? "end of file" : "'" + token->value + "'")};
}
Token *Parser::take(const std::string &value) {
    if (peek()->value != value)
        fail("'" + value + "'");
    return read();
}
Token *Parser::takeType() {
    if (!typeName(peek()))
        fail("type");
    return read();
}
Token *Parser::identifier() {
    if (peek()->kind != TokenKind::Identifier)
        fail("identifier");
    return read();
}
NodePtr Parser::mark(NodePtr node, int start) const {
    node->first = start;
    node->last = std::max(start, position - 1);
    return node;
}
NodePtr Parser::program() {
    NodePtr out = makeNode(NodeKind::Program);
    while (peek()->kind != TokenKind::End) {
        int start = position;
        Token *type = takeType();
        Token *name = identifier();
        if (peek()->value == "(") {
            NodePtr node = makeNode(NodeKind::Function);
            node->token = type;
            node->name = name;
            node->init = list("parameters", "(", ")", false);
            node->body = block();
            out->elements.push_back(mark(node, start));
        } else
            out->elements.push_back(declaration(type, name, start, true));
    }
    return out;
}
NodePtr Parser::list(const std::string &kind, const std::string &open, const std::string &close,
                     bool trailing) {
    int start = position;
    NodePtr out = makeNode(NodeKind::List);
    out->value = kind;
    out->open = take(open);
    if (peek()->value != close)
        for (;;) {
            out->elements.push_back(kind == "parameters"    ? parameter()
                                    : kind == "initializer" ? initializer()
                                                            : expression());
            if (peek()->value != ",")
                break;
            Token *comma = read();
            if (trailing && peek()->value == close) {
                out->trailing = comma;
                break;
            }
            out->commas.push_back(comma);
        }
    out->close = take(close);
    return mark(out, start);
}
NodePtr Parser::parameter() {
    int start = position;
    NodePtr out = makeNode(NodeKind::Parameter);
    out->token = takeType();
    out->name = identifier();
    while (peek()->value == "[") {
        int begin = position;
        NodePtr dimension = makeNode(NodeKind::Dimension);
        dimension->open = read();
        dimension->close = take("]");
        out->dimensions.push_back(mark(dimension, begin));
    }
    return mark(out, start);
}
NodePtr Parser::declaration(Token *type, Token *name, int start, bool semi) {
    NodePtr out = makeNode(NodeKind::Declaration);
    out->token = type;
    out->name = name;
    while (peek()->value == "[") {
        int begin = position;
        NodePtr dimension = makeNode(NodeKind::Dimension);
        dimension->open = read();
        if (peek()->value != "]")
            dimension->expr = expression();
        dimension->close = take("]");
        out->dimensions.push_back(mark(dimension, begin));
    }
    if (peek()->value == "=") {
        out->op = read();
        out->init = initializer();
    }
    if (semi)
        out->semi = take(";");
    return mark(out, start);
}
NodePtr Parser::initializer() {
    return peek()->value == "{" ? list("initializer", "{", "}", true) : expression();
}
NodePtr Parser::block() {
    int start = position;
    NodePtr out = makeNode(NodeKind::Block);
    out->open = take("{");
    while (peek()->value != "}" && peek()->kind != TokenKind::End)
        out->elements.push_back(statement());
    out->close = take("}");
    return mark(out, start);
}
NodePtr Parser::statement() {
    int start = position;
    Token *token = peek();
    if (token->value == "{")
        return block();
    if (typeName(token)) {
        Token *type = read();
        Token *name = identifier();
        return declaration(type, name, start, true);
    }
    NodePtr out = makeNode(NodeKind::Simple);
    if (token->value == "if" || token->value == "while") {
        out->kind = token->value == "if" ? NodeKind::If : NodeKind::While;
        out->token = read();
        out->open = take("(");
        out->expr = expression();
        out->close = take(")");
        out->body = statement();
        if (out->kind == NodeKind::If && peek()->value == "else") {
            out->elseToken = read();
            out->elsePart = statement();
        }
    } else if (token->value == "for") {
        out->kind = NodeKind::For;
        out->token = read();
        out->open = take("(");
        if (peek()->value != ";") {
            if (typeName(peek())) {
                int begin = position;
                Token *type = read();
                Token *name = identifier();
                out->init = declaration(type, name, begin, false);
            } else
                out->init = simple();
        }
        out->semi = take(";");
        if (peek()->value != ";")
            out->condition = expression();
        out->semi2 = take(";");
        if (peek()->value != ")")
            out->update = simple();
        out->close = take(")");
        out->body = statement();
    } else if (token->value == "switch") {
        out->kind = NodeKind::Switch;
        out->token = read();
        out->open = take("(");
        out->expr = expression();
        out->close = take(")");
        int begin = position;
        NodePtr body = makeNode(NodeKind::SwitchBody);
        body->open = take("{");
        while (peek()->value == "case" || peek()->value == "default") {
            int clauseStart = position;
            NodePtr clause = makeNode(NodeKind::Clause);
            clause->token = read();
            if (clause->token->value == "case")
                clause->expr = expression();
            clause->colon = take(":");
            while (!wordIn("case default }", peek()->value) && peek()->kind != TokenKind::End)
                clause->elements.push_back(statement());
            body->elements.push_back(mark(clause, clauseStart));
        }
        body->close = take("}");
        out->body = mark(body, begin);
    } else if (token->value == "return") {
        out->kind = NodeKind::Return;
        out->token = read();
        if (peek()->value != ";")
            out->expr = expression();
        out->semi = take(";");
    } else if (token->value == "break" || token->value == "continue") {
        out->kind = token->value == "break" ? NodeKind::Break : NodeKind::Continue;
        out->token = read();
        out->semi = take(";");
    } else {
        out = simple();
        out->semi = take(";");
    }
    return mark(out, start);
}
NodePtr Parser::simple() {
    int start = position;
    NodePtr left = expression(), out = makeNode(NodeKind::Simple);
    out->expr = left;
    if (wordIn("= += -= *= /= %=", peek()->value)) {
        out = makeNode(NodeKind::Assignment);
        out->left = left;
        out->op = read();
        out->right = expression();
    }
    return mark(out, start);
}
NodePtr Parser::expression() {
    int start = position;
    NodePtr out = binary(1);
    if (peek()->value == "?") {
        NodePtr node = makeNode(NodeKind::Conditional);
        node->expr = out;
        node->op = read();
        node->thenPart = expression();
        node->colon = take(":");
        node->elsePart = expression();
        out = mark(node, start);
    }
    return out;
}
NodePtr Parser::binary(int level) {
    if (level == 7)
        return unary();
    NodePtr left = binary(level + 1);
    while (precedence(peek()->value) == level) {
        NodePtr out = makeNode(NodeKind::Binary);
        out->left = left;
        out->op = read();
        out->right = binary(level + 1);
        out->first = left->first;
        out->last = out->right->last;
        left = out;
    }
    return left;
}
NodePtr Parser::unary() {
    int start = position;
    if (peek()->value == "-" || peek()->value == "!") {
        NodePtr out = makeNode(NodeKind::Unary);
        out->op = read();
        out->expr = unary();
        return mark(out, start);
    }
    Token *token = peek();
    NodePtr out;
    if (token->kind == TokenKind::Identifier || token->kind == TokenKind::Number ||
        token->kind == TokenKind::String || token->value == "true" || token->value == "false") {
        out = makeNode(NodeKind::Atom);
        out->token = read();
        mark(out, start);
    } else if (token->value == "(") {
        out = makeNode(NodeKind::Parenthesized);
        out->open = read();
        out->expr = expression();
        out->close = take(")");
        mark(out, start);
    } else
        fail("expression");
    for (;;) {
        if (peek()->value == "(") {
            NodePtr node = makeNode(NodeKind::Call);
            node->left = out;
            node->init = list("arguments", "(", ")", false);
            out = mark(node, start);
        } else if (peek()->value == "[") {
            NodePtr node = makeNode(NodeKind::Index);
            node->left = out;
            node->open = read();
            node->expr = expression();
            node->close = take("]");
            out = mark(node, start);
        } else if (peek()->value == ".") {
            NodePtr node = makeNode(NodeKind::Member);
            node->left = out;
            node->op = read();
            node->name = identifier();
            out = mark(node, start);
        } else
            return out;
    }
}
