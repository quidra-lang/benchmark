#include "columnar.hpp"
class Parser {
    Lines tokens;
    std::size_t position = 0;
    std::string peek() const { return position < tokens.size() ? tokens[position] : ""; }
    std::string take() { return tokens[position++]; }
    bool accept(const std::string &token) {
        if (peek() != token)
            return false;
        ++position;
        return true;
    }
    static bool letter(char c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
    Cond node(std::string operation, Cond left = {}, Cond right = {}) {
        auto out = std::make_shared<Condition>();
        out->operation = std::move(operation);
        out->left = std::move(left);
        out->right = std::move(right);
        return out;
    }
    Item item() {
        std::string name = take();
        if (name[0] >= 'a' && name[0] <= 'z')
            return {"COLUMN", name};
        take();
        std::string operation = accept("DISTINCT") ? "COUNT_DISTINCT" : name;
        std::string column = accept("*") ? "" : take();
        take();
        return {operation, column};
    }
    Literal literal() {
        std::string token = take();
        if (token[0] == '\'')
            return {Type::String, Value::word(token.substr(1, token.size() - 2))};
        if (token == "TRUE" || token == "FALSE")
            return {Type::Bool, Value::integer(token == "TRUE")};
        return {Type::Int, Value::integer(std::stoll(token))};
    }
    Cond condition() {
        Cond tree = conjunction();
        while (accept("OR"))
            tree = node("OR", tree, conjunction());
        return tree;
    }
    Cond conjunction() {
        Cond tree = negation();
        while (accept("AND"))
            tree = node("AND", tree, negation());
        return tree;
    }
    Cond negation() {
        if (accept("NOT"))
            return node("NOT", negation());
        if (accept("(")) {
            Cond tree = condition();
            take();
            return tree;
        }
        std::string name = take(), operation = take();
        Cond tree = node(operation);
        tree->name = name;
        if (operation == "IS") {
            tree->operation = accept("NOT") ? "IS_NOT_NULL" : "IS_NULL";
            take();
        } else if (operation == "BETWEEN") {
            tree->literals.push_back(literal());
            take();
            tree->literals.push_back(literal());
        } else if (operation == "IN") {
            take();
            tree->literals.push_back(literal());
            while (accept(","))
                tree->literals.push_back(literal());
            take();
        } else
            tree->literals.push_back(literal());
        return tree;
    }

  public:
    explicit Parser(const std::string &source) {
        for (std::size_t i = 0; i < source.size();) {
            if (source[i] == ' ') {
                ++i;
                continue;
            }
            std::size_t start = i++;
            char c = source[start];
            if (c == '\'') {
                while (source[i] != '\'')
                    ++i;
                ++i;
            } else if (letter(c) || c == '_')
                while (i < source.size() &&
                       (letter(source[i]) || (source[i] >= '0' && source[i] <= '9') ||
                        source[i] == '_'))
                    ++i;
            else if ((c >= '0' && c <= '9') || c == '-')
                while (i < source.size() && source[i] >= '0' && source[i] <= '9')
                    ++i;
            else if (i < source.size() && ((c == '<' && (source[i] == '=' || source[i] == '>')) ||
                                           (c == '>' && source[i] == '=')))
                ++i;
            tokens.push_back(source.substr(start, i - start));
        }
    }
    Query parse() {
        Query out;
        take();
        out.star = accept("*");
        if (!out.star) {
            out.items.push_back(item());
            while (accept(","))
                out.items.push_back(item());
        }
        if (accept("WHERE"))
            out.condition = condition();
        if (accept("GROUP")) {
            take();
            out.group_name = take();
        }
        if (accept("ORDER")) {
            take();
            out.order_name = take();
            out.descending = accept("DESC");
            if (!out.descending)
                accept("ASC");
        }
        if (accept("LIMIT"))
            out.limit = std::stoi(take());
        return out;
    }
};
Query parse_query(const std::string &source) { return Parser(source).parse(); }
