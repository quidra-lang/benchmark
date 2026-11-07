#include "awk.hpp"
namespace awk {
    NodePtr node(const std::string& kind, const Position& position) {
        NodePtr value = std::make_shared < Node >();
        value->kind = kind;
        value->position = position;
        return value;
    }
    std::vector<NodePtr> children(const NodePtr& value) {
        std::vector<NodePtr> result;
        for (const NodePtr& child : {value->a, value->b, value->c, value->d}) if (child) result.push_back(child);
        result.insert(result.end(), value->nodes.begin(), value->nodes.end());
        return result;
    }
    bool is_lvalue(const NodePtr& value) {
        return value->kind == "name" || value->kind == "array" || value->kind == "field";
    }
    const Token& Parser::peek() const {return tokens[index];
    } Token Parser::take() {
        return tokens[index++];
    }
    bool Parser::accept(const std::string& spelling) {
        if (peek().text != spelling) return false;
        take();
        return true;
    }
    Token Parser::expect(const std::string& spelling) {
        if (peek().text != spelling) fail();
        return take();
    }
    [[noreturn]]void Parser::fail() const {throw Issue {peek().position, "", 0};
    } void Parser::newlines() {
        while (accept("\n")) {
        }
    }
    NodePtr Parser::name() {
        if (peek().kind != "name") fail();
        Token token = take();
        NodePtr result = node("name", token.position);
        result->text = token.text;
        return result;
    }
    std::vector<NodePtr> Parser::parse() {
        std::vector<NodePtr> items;
        while (peek().kind != "end") {
            if (accept("\n") || accept(";")) continue;
            Token start = peek();
            if (accept("function")) {
                if (peek().kind != "name" && peek().kind != "function_name") fail();
                Token token = take();
                NodePtr item = node("function", start.position);
                item->text = token.text;
                item->name_position = token.position;
                expect("(");
                if (peek().text != ")") do {
                    NodePtr parameter = name();
                    parameter->kind = "parameter";
                    item->nodes.push_back(parameter);
                    if (peek().text != ",") break;
                    take();
                    newlines();
                } while (true);
                expect(")");
                newlines();
                in_function = true;
                item->a = block();
                in_function = false;
                items.push_back(item);
                continue;
            }
            NodePtr item = node("rule", start.position);
            if (start.text == "BEGIN" || start.text == "END") item->flavor = take().text;
            else if (start.text == "{") item->flavor = "all";
            else {
                item->nodes.push_back(expression());
                if (accept(",")) {
                    newlines();
                    item->nodes.push_back(expression());
                }
                item->flavor = item->nodes.size() == 2 ? "range" : "pattern";
            }
            phase = item->flavor;
            if (phase == "BEGIN" || phase == "END" || phase == "all" || peek().text == "{") item->a = block();
            else if (peek().text != "\n" && peek().text != ";" && peek().kind != "end") fail();
            phase.clear();
            items.push_back(item);
        }
        return items;
    }
    NodePtr Parser::block() {
        Token t = expect("{");
        NodePtr result = node("block", t.position);
        while (peek().text != "}") {
            if (accept("\n") || accept(";")) continue;
            result->nodes.push_back(statement());
        }
        expect("}");
        return result;
    }
    NodePtr Parser::condition() {
        expect("(");
        NodePtr result = expression();
        expect(")");
        return result;
    }
    NodePtr Parser::loop_body() {
        newlines();
        ++loop_depth;
        NodePtr result = statement();
        --loop_depth;
        return result;
    }
    void Parser::terminator() {
        if (accept(";") || accept("\n")) return;
        if (peek().text != "}") fail();
    }
    NodePtr Parser::statement() {
        Token token = peek();
        const std::string spelling = token.text;
        if (spelling == "{") return block();
        if (accept(";")) return node("empty", token.position);
        NodePtr result = node(spelling, token.position);
        if (accept("if")) {
            result->a = condition();
            newlines();
            result->b = statement();
            newlines();
            if (accept("else")) {
                newlines();
                result->c = statement();
            }
            return result;
        }
        if (accept("while")) {
            result->a = condition();
            result->b = loop_body();
            return result;
        }
        if (accept("do")) {
            result->b = loop_body();
            newlines();
            expect("while");
            result->a = condition();
            terminator();
            return result;
        }
        if (accept("for")) {
            expect("(");
            if (index + 3 < tokens.size() && tokens[index].kind == "name" && tokens[index + 1].text == "in" && tokens[index + 2].kind == "name" && tokens[index + 3].text == ")") {
                result->kind = "for_in";
                result->a = name();
                expect("in");
                result->b = name();
                expect(")");
                result->c = loop_body();
                return result;
            }
            if (peek().text != ";") result->a = expression();
            expect(";");
            newlines();
            if (peek().text != ";") result->b = expression();
            expect(";");
            newlines();
            if (peek().text != ")") result->c = expression();
            expect(")");
            result->d = loop_body();
            return result;
        }
        if (spelling == "print" || spelling == "printf") {
            take();
            result = output(token);
        } else if (accept("delete")) {
            result->a = name();
            result->flag = accept("[");
            if (result->flag) {
                result->nodes = expression_list();
                expect("]");
            }
        } else if (spelling == "next" || spelling == "break" || spelling == "continue" || spelling == "exit" || spelling == "return") {
            take();
            if ((spelling == "next" && !in_function &&(phase == "BEGIN" || phase == "END")) ||(spelling == "return" && !in_function) ||((spelling == "break" || spelling == "continue") && loop_depth == 0)) throw Issue {token.position, "", 0};
            if ((spelling == "exit" || spelling == "return") && peek().text != ";" && peek().text != "\n" && peek().text != "}") result->a = expression();
        } else {
            result->kind = "expression_statement";
            result->a = expression();
        }
        terminator();
        return result;
    }
    bool Parser::parenthesized_output() const {if (peek().text != "(") return false;
    int depth = 0;
    for (std::size_t i = index;i < tokens.size();++i) {
        if (tokens[i].text == "(")++depth;
        else if (tokens[i].text == ")" && --depth == 0) {
            const Token& t = tokens[i + 1];
            return t.text == ";" || t.text == "\n" || t.text == "}" || t.text == ">" || t.text == ">>" || t.kind == "end";
        }
    }
    return false;
    } NodePtr Parser::output(Token token) {
        NodePtr result = node(token.text, token.position);
        if (parenthesized_output()) {
            expect("(");
            result->nodes = expression_list();
            expect(")");
        } else if (peek().text != ";" && peek().text != "\n" && peek().text != "}" && peek().text != ">" && peek().text != ">>") result->nodes = expression_list(false);
        if (token.text == "printf" && result->nodes.empty()) fail();
        if (peek().text == ">" || peek().text == ">>") {
            Token redirect = take();
            result->redirect = redirect.text;
            result->redirect_position = redirect.position;
            result->a = concatenation();
        }
        return result;
    }
    std::vector<NodePtr> Parser::expression_list(bool greater) {
        std::vector<NodePtr> result = {expression(greater)};
        while (accept(",")) {
            newlines();
            result.push_back(expression(greater));
        }
        return result;
    }
    NodePtr Parser::expression(bool greater) {
        NodePtr left = conditional(greater);
        const std::set<std::string> assignments = {"=", "+=", "-=", "*=", "/=", "%=", "^="};
        if (is_lvalue(left) && assignments.count(peek().text)) {
            Token op = take();
            NodePtr result = node("assignment", op.position);
            result->text = op.text;
            result->a = left;
            result->b = expression(greater);
            return result;
        }
        return left;
    }
    NodePtr Parser::conditional(bool greater) {
        NodePtr left = logical(0, greater);
        if (!accept("?")) return left;
        NodePtr result = node("conditional", tokens[index - 1].position);
        result->a = left;
        result->b = conditional(greater);
        expect(":");
        result->c = conditional(greater);
        return result;
    }
    NodePtr Parser::binary(Token op, NodePtr a, NodePtr b) {
        NodePtr result = node("binary", op.position);
        result->text = op.text;
        result->a = std::move(a);
        result->b = std::move(b);
        return result;
    }
    NodePtr Parser::logical(int level, bool greater) {
        if (level == 2) return membership(greater);
        NodePtr left = logical(level + 1, greater);
        std::string op = level == 0 ? "||" : "&&";
        while (peek().text == op) {
            Token token = take();
            newlines();
            NodePtr right = logical(level + 1, greater);
            left = binary(token, left, right);
        }
        return left;
    }
    NodePtr Parser::membership(bool greater) {
        NodePtr left = comparison(greater);
        while (peek().text == "in") {
            Token token = take();
            NodePtr result = node("membership", token.position);
            result->nodes = {left};
            result->a = name();
            left = result;
        }
        return left;
    }
    NodePtr Parser::comparison(bool greater) {
        NodePtr left = concatenation();
        const std::set<std::string> ops = {"<", "<=", "==", "!=", ">=", ">"};
        while (ops.count(peek().text) &&(greater || peek().text != ">")) {
            Token op = take();
            NodePtr right = concatenation();
            left = binary(op, left, right);
        }
        return left;
    }
    NodePtr Parser::concatenation() {
        NodePtr left = additive();
        while (peek().kind == "number" || peek().kind == "string" || peek().kind == "name" || peek().kind == "function_name" || peek().kind == "builtin" || peek().text == "$" || peek().text == "(" || peek().text == "++" || peek().text == "--") {
            Token op = peek();
            op.text = "concat";
            NodePtr right = additive();
            left = binary(op, left, right);
        }
        return left;
    }
    NodePtr Parser::additive() {
        NodePtr left = multiplicative();
        while (peek().text == "+" || peek().text == "-") {
            Token op = take();
            NodePtr right = multiplicative();
            left = binary(op, left, right);
        }
        return left;
    }
    NodePtr Parser::multiplicative() {
        NodePtr left = unary();
        while (peek().text == "*" || peek().text == "/" || peek().text == "%") {
            Token op = take();
            NodePtr right = unary();
            left = binary(op, left, right);
        }
        return left;
    }
    NodePtr Parser::unary() {
        if (peek().text == "!" || peek().text == "-" || peek().text == "+") {
            Token op = take();
            NodePtr result = node("unary", op.position);
            result->text = op.text;
            result->a = unary();
            return result;
        }
        NodePtr left = postfix();
        if (peek().text == "^") {
            Token op = take();
            NodePtr right = unary();
            left = binary(op, left, right);
        }
        return left;
    }
    NodePtr Parser::prefix() {
        Token op = take();
        NodePtr result = node("increment", op.position);
        result->number = op.text == "++" ? 1 : -1;
        result->flag = true;
        result->a = lvalue();
        return result;
    }
    NodePtr Parser::postfix() {
        if (peek().text == "++" || peek().text == "--") return prefix();
        NodePtr left = atom();
        if (is_lvalue(left) &&(peek().text == "++" || peek().text == "--")) {
            Token op = take();
            NodePtr result = node("increment", op.position);
            result->number = op.text == "++" ? 1 : -1;
            result->a = left;
            return result;
        }
        return left;
    }
    NodePtr Parser::lvalue() {
        if (peek().kind == "name") {
            NodePtr result = name();
            if (accept("[")) {
                result->kind = "array";
                result->nodes = expression_list();
                expect("]");
            }
            return result;
        }
        if (peek().text == "$") {
            Token dollar = take();
            NodePtr result = node("field", dollar.position);
            result->a =(peek().text == "++" || peek().text == "--") ? prefix() : atom();
            return result;
        }
        fail();
    }
    NodePtr Parser::atom() {
        Token token = peek();
        if (token.kind == "number" || token.kind == "string") {
            take();
            NodePtr result = node(token.kind, token.position);
            if (token.kind == "number") result->number = std::stoll(token.value);
            else result->text = token.value;
            return result;
        }
        if (token.kind == "name" || token.text == "$") return lvalue();
        if (accept("(")) {
            std::vector<NodePtr> values = expression_list();
            expect(")");
            if (values.size() == 1) {
                NodePtr result = node("paren", token.position);
                result->a = values[0];
                return result;
            }
            expect("in");
            NodePtr result = node("membership", token.position);
            result->nodes = values;
            result->a = name();
            return result;
        }
        if (token.kind == "function_name" || token.kind == "builtin") {
            take();
            NodePtr result = node(token.kind == "builtin" ? "builtin" : "call", token.position);
            result->text = token.text;
            if (accept("(")) {
                if (peek().text != ")") result->nodes = expression_list();
                expect(")");
            } else if (token.kind == "function_name" || token.text != "length") fail();
            if (result->kind == "builtin") {
                std::size_t n = result->nodes.size();
                bool valid = token.text == "length" ? n <= 1 : token.text == "substr" || token.text == "split" ? n == 2 || n == 3 : token.text == "index" ? n == 2 : token.text == "sprintf" ? n >= 1 : n == 1;
                if (!valid ||(token.text == "split" && result->nodes[1]->kind != "name")) throw Issue {token.position, "", 0};
            }
            return result;
        }
        if (accept("getline")) {
            NodePtr result = node("getline", token.position);
            if (peek().kind == "name" || peek().text == "$") result->a = lvalue();
            if (accept("<")) result->b = atom();
            return result;
        }
        fail();
    }
}
