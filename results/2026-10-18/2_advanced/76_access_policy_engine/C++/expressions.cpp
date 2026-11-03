#include "policy.hpp"
class Parser {
    Names tokens;
    std::size_t position = 0;
    std::string peek() const { return position < tokens.size() ? tokens[position] : ""; }
    std::string take() { return tokens[position++]; }
    Expr node(std::string op, std::vector<Expr> arguments = {}) {
        return std::make_shared<Expression>(Expression{std::move(op), {}, std::move(arguments)});
    }
    Expr joined(Expr (Parser::*next)(), const Names &operations) {
        Expr result = (this->*next)();
        while (std::find(operations.begin(), operations.end(), peek()) != operations.end()) {
            std::string op = take();
            result = node(op, {result, (this->*next)()});
        }
        return result;
    }
    Expr disjunction() { return joined(&Parser::conjunction, {"or"}); }
    Expr conjunction() { return joined(&Parser::negation, {"and"}); }
    Expr negation() {
        if (peek() == "not") {
            take();
            return node("not", {negation()});
        }
        return comparison();
    }
    Expr comparison() {
        Expr result = sum();
        std::string op = peek();
        if (op == "==" || op == "!=" || op == "<" || op == "<=" || op == ">" || op == ">=" ||
            op == "in") {
            take();
            result = node(op, {result, sum()});
        }
        return result;
    }
    Expr sum() { return joined(&Parser::product, {"+", "-"}); }
    Expr product() { return joined(&Parser::unary, {"*"}); }
    Expr unary() {
        if (peek() == "-") {
            take();
            return node("-", {unary()});
        }
        return primary();
    }
    Expr primary() {
        std::string token = take();
        Expr out = node("literal");
        if (token[0] >= '0' && token[0] <= '9')
            out->literal = Value::number(std::stoi(token));
        else if (token[0] == '"')
            out->literal = Value::word(token.substr(1, token.size() - 2));
        else if (token == "true" || token == "false")
            out->literal = Value::truth(token == "true");
        else if (token == "it")
            return node("it");
        else if (token.find('.') != std::string::npos) {
            out->operation = "attribute";
            out->literal = Value::word(token);
        } else if (token == "(") {
            out = disjunction();
            take();
        } else if (token == "[") {
            Names values;
            while (peek() != "]") {
                std::string item = take();
                values.push_back(item.substr(1, item.size() - 2));
                if (peek() != "]")
                    take();
            }
            take();
            out->literal = Value::collection(values);
        } else {
            take();
            std::vector<Expr> arguments;
            while (peek() != ")") {
                arguments.push_back(disjunction());
                if (peek() != ")")
                    take();
            }
            take();
            return node(token, arguments);
        }
        return out;
    }

  public:
    explicit Parser(const std::string &source) {
        for (std::size_t i = 0; i < source.size();) {
            if (source[i] == ' ') {
                ++i;
                continue;
            }
            std::size_t start = i++;
            char first = source[start];
            if (first == '"') {
                while (source[i] != '"')
                    ++i;
                ++i;
            } else if ((first >= '0' && first <= '9') || (first >= 'A' && first <= 'Z') ||
                       (first >= 'a' && first <= 'z')) {
                bool word = !(first >= '0' && first <= '9');
                while (i < source.size() && ((source[i] >= '0' && source[i] <= '9') ||
                                             (word && ((source[i] >= 'A' && source[i] <= 'Z') ||
                                                       (source[i] >= 'a' && source[i] <= 'z') ||
                                                       source[i] == '_' || source[i] == '.'))))
                    ++i;
            } else if (i < source.size() && source[i] == '=' &&
                       (first == '=' || first == '!' || first == '<' || first == '>'))
                ++i;
            tokens.push_back(source.substr(start, i - start));
        }
    }
    Expr parse() { return disjunction(); }
};
Expr parse_expression(const std::string &source) { return Parser(source).parse(); }
