#include "formula.hpp"
NodePtr emptyRow() { return std::make_shared<Node>(); }
static NodePtr collapse(Nodes nodes) {
    if (nodes.size() == 1)
        return nodes[0];
    NodePtr out = emptyRow();
    out->items = std::move(nodes);
    return out;
}
std::optional<Issue> checkBraces(const std::vector<Token> &tokens) {
    std::vector<int> stack;
    for (const Token &token : tokens) {
        if (token.kind == Kind::OpenBrace)
            stack.push_back(token.column);
        else if (token.kind == Kind::CloseBrace) {
            if (stack.empty())
                return Issue{token.column, "unmatched }"};
            stack.pop_back();
        }
    }
    if (!stack.empty())
        return Issue{stack.back(), "unclosed {"};
    return std::nullopt;
}
Token Parser::peek() const {
    return position < tokens.size() ? tokens[position] : Token{Kind::Eof, "", end};
}
Token Parser::read() {
    Token token = peek();
    if (position < tokens.size())
        ++position;
    return token;
}
void Parser::unexpected(Token token) const {
    std::string message;
    if (token.kind == Kind::Right)
        message = "unexpected \\right";
    else if (token.kind == Kind::End)
        message = "unexpected \\end";
    else if (token.kind == Kind::Amp)
        message = "misplaced &";
    else
        message = "misplaced \\\\";
    throw Issue{token.column, message};
}
static bool terminator(Kind kind) {
    return kind == Kind::CloseBrace || kind == Kind::Amp || kind == Kind::Newline ||
           kind == Kind::Right || kind == Kind::End || kind == Kind::Eof;
}
Nodes Parser::elements(bool top, bool index) {
    Nodes out;
    for (;;) {
        Token token = peek();
        if (terminator(token.kind) || (index && token.kind == Kind::Symbol && token.value == "]"))
            return out;
        if (token.kind == Kind::Tag || token.kind == Kind::Label) {
            std::string name = token.kind == Kind::Tag ? "tag" : "label";
            if (!top)
                throw Issue{token.column, "misplaced \\" + name};
            std::optional<Token> &target = token.kind == Kind::Tag ? tag : label;
            if (target)
                throw Issue{token.column, "duplicate \\" + name};
            target = read();
            continue;
        }
        out.push_back(element());
    }
}
NodePtr Parser::element() {
    NodePtr base = (peek().kind == Kind::Sup || peek().kind == Kind::Sub) ? emptyRow() : nucleus();
    NodePtr sub, sup;
    while (peek().kind == Kind::Sup || peek().kind == Kind::Sub) {
        Token token = read();
        if (token.kind == Kind::Sup) {
            if (sup)
                throw Issue{token.column, "double superscript"};
            sup = argument("^");
        } else {
            if (sub)
                throw Issue{token.column, "double subscript"};
            sub = argument("_");
        }
    }
    if (!sub && !sup)
        return base;
    NodePtr out = emptyRow();
    out->kind = Kind::Script;
    out->base = base;
    out->sub = sub;
    out->sup = sup;
    return out;
}
NodePtr Parser::argument(const std::string &name) {
    Kind kind = peek().kind;
    if (kind == Kind::Identifier || kind == Kind::Number || kind == Kind::Symbol ||
        kind == Kind::Command || kind == Kind::Text || kind == Kind::Eqref ||
        kind == Kind::OpenBrace || kind == Kind::Fraction || kind == Kind::Binomial ||
        kind == Kind::Overset || kind == Kind::Underset || kind == Kind::SquareRoot ||
        kind == Kind::Accent)
        return nucleus();
    throw Issue{peek().column, "missing argument for " + name};
}
std::string Parser::delimiter() {
    Token token = read();
    if ((token.kind == Kind::Symbol && containsWord("( ) [ ] | .", token.value)) ||
        (token.kind == Kind::Command && (token.value == "\\{" || token.value == "\\}")))
        return token.value;
    throw Issue{token.column, "invalid delimiter"};
}
NodePtr Parser::nucleus() {
    Token token = read();
    NodePtr out = emptyRow();
    out->kind = token.kind;
    out->value = token.value;
    out->column = token.column;
    switch (token.kind) {
    case Kind::Identifier:
    case Kind::Number:
    case Kind::Symbol:
    case Kind::Command:
    case Kind::Text:
        return out;
    case Kind::Eqref:
        out->kind = Kind::Reference;
        return out;
    case Kind::OpenBrace: {
        Nodes nodes = elements();
        if (peek().kind != Kind::CloseBrace)
            unexpected(peek());
        read();
        return collapse(std::move(nodes));
    }
    case Kind::Fraction:
    case Kind::Binomial:
    case Kind::Overset:
    case Kind::Underset: {
        std::string name = token.kind == Kind::Fraction   ? "frac"
                           : token.kind == Kind::Binomial ? "binom"
                           : token.kind == Kind::Overset  ? "overset"
                                                          : "underset";
        out->items.push_back(argument("\\" + name));
        out->items.push_back(argument("\\" + name));
        return out;
    }
    case Kind::SquareRoot: {
        if (peek().kind == Kind::Symbol && peek().value == "[") {
            Token open = read();
            Nodes index = elements(false, true);
            if (peek().kind != Kind::Symbol || peek().value != "]")
                throw Issue{open.column, "missing ]"};
            read();
            out->kind = Kind::Root;
            out->items.push_back(collapse(std::move(index)));
        }
        out->items.push_back(argument("\\sqrt"));
        return out;
    }
    case Kind::Accent:
        out->items.push_back(argument("\\" + token.value));
        return out;
    case Kind::Left: {
        out->kind = Kind::Delimited;
        out->left = delimiter();
        Nodes nodes = elements();
        if (peek().kind != Kind::Right)
            throw Issue{token.column, "missing \\right"};
        out->rightColumn = read().column;
        out->right = delimiter();
        out->items.push_back(collapse(std::move(nodes)));
        return out;
    }
    case Kind::Begin: {
        out->kind = Kind::Matrix;
        out->rows.push_back({});
        for (;;) {
            out->rows.back().push_back(collapse(elements()));
            Token endToken = read();
            if (endToken.kind == Kind::Amp)
                continue;
            if (endToken.kind == Kind::Newline) {
                out->rows.push_back({});
                continue;
            }
            if (endToken.kind == Kind::End) {
                if (endToken.value != token.value)
                    throw Issue{endToken.column, "mismatched \\end"};
                break;
            }
            throw Issue{token.column, "missing \\end"};
        }
        if (out->rows.size() > 1 && out->rows.back().size() == 1 &&
            out->rows.back()[0]->kind == Kind::Row && out->rows.back()[0]->items.empty())
            out->rows.pop_back();
        std::size_t width = 0;
        for (const Nodes &row : out->rows)
            width = std::max(width, row.size());
        for (Nodes &row : out->rows)
            while (row.size() < width)
                row.push_back(emptyRow());
        return out;
    }
    default:
        throw std::logic_error("unexpected nucleus");
    }
}
