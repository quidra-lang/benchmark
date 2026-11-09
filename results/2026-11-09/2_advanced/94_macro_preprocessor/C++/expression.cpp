#include "preprocessor.hpp"
static int digit_value(char c) {
    if (c >= '0' && c <= '9')
        return c - '0';
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    if (c >= 'A' && c <= 'F')
        return c - 'A' + 10;
    return -1;
}
static int64_t integer_constant(const std::string &spelling) {
    std::string text = spelling;
    for (const std::string &suffix :
         {std::string("ll"), std::string("LL"), std::string("l"), std::string("L")})
        if (text.size() > suffix.size() &&
            text.compare(text.size() - suffix.size(), suffix.size(), suffix) == 0) {
            text.resize(text.size() - suffix.size());
            break;
        }
    int base = 10;
    size_t first = 0;
    bool valid = !text.empty();
    if (text.size() >= 2 && text[0] == '0' && (text[1] == 'x' || text[1] == 'X')) {
        base = 16;
        first = 2;
        if (first == text.size())
            valid = false;
    } else if (!text.empty() && text[0] == '0')
        base = 8;
    else if (text.empty() || text[0] < '1' || text[0] > '9')
        valid = false;
    for (size_t i = first; i < text.size(); ++i) {
        int digit = digit_value(text[i]);
        if (digit < 0 || digit >= base)
            valid = false;
    }
    if (!valid)
        throw PreprocessingError{"invalid integer constant \"" + spelling + "\""};
    int64_t value = 0;
    for (size_t i = first; i < text.size(); ++i)
        value = value * base + digit_value(text[i]);
    return value;
}
static int64_t character_constant(const std::string &spelling) {
    std::string body = spelling.substr(1, spelling.size() - 2);
    if (body.size() == 1 && body[0] != '\'' && body[0] != '\\')
        return static_cast<unsigned char>(body[0]);
    if (body.size() == 2 && body[0] == '\\') {
        const std::map<char, int> escapes = {{'n', 10},  {'t', 9},  {'\\', 92},
                                             {'\'', 39}, {'"', 34}, {'0', 0}};
        auto found = escapes.find(body[1]);
        if (found != escapes.end())
            return found->second;
    }
    throw PreprocessingError{"invalid character constant " + spelling};
}
static int precedence(const std::string &op) {
    if (op == "||")
        return 1;
    if (op == "&&")
        return 2;
    if (op == "|")
        return 3;
    if (op == "^")
        return 4;
    if (op == "&")
        return 5;
    if (op == "==" || op == "!=")
        return 6;
    if (word_in("< > <= >=", op))
        return 7;
    if (op == "<<" || op == ">>")
        return 8;
    if (op == "+" || op == "-")
        return 9;
    if (word_in("* / %", op))
        return 10;
    return 0;
}
static std::unique_ptr<ConditionExpr> node(const std::string &kind) {
    auto result = std::make_unique<ConditionExpr>();
    result->kind = kind;
    return result;
}
struct ExpressionParser {
    const Tokens &tokens;
    size_t index = 0;
    std::string peek() const { return index == tokens.size() ? "" : tokens[index].spelling; }
    std::unique_ptr<ConditionExpr> expression() {
        auto first = binary(1);
        if (peek() == "?") {
            ++index;
            auto second = expression();
            if (peek() != ":")
                throw PreprocessingError{"'?' without following ':'"};
            ++index;
            auto third = expression();
            auto result = node("conditional");
            result->children.push_back(std::move(first));
            result->children.push_back(std::move(second));
            result->children.push_back(std::move(third));
            return result;
        }
        return first;
    }
    std::unique_ptr<ConditionExpr> binary(int minimum) {
        auto left = unary();
        while (true) {
            int level = precedence(peek());
            if (!level || level < minimum)
                break;
            std::string op = peek();
            ++index;
            auto right = binary(level + 1);
            auto result = node("binary");
            result->op = op;
            result->children.push_back(std::move(left));
            result->children.push_back(std::move(right));
            left = std::move(result);
        }
        return left;
    }
    std::unique_ptr<ConditionExpr> unary() {
        if (word_in("+ - ! ~", peek())) {
            std::string op = peek();
            ++index;
            auto result = node("unary");
            result->op = op;
            result->children.push_back(unary());
            return result;
        }
        return primary();
    }
    std::unique_ptr<ConditionExpr> primary() {
        if (index == tokens.size())
            throw PreprocessingError{"expected value at end of expression"};
        const Token &token = tokens[index++];
        if (token.kind == "number" || token.kind == "character") {
            auto result = node("constant");
            result->value = token.kind == "number" ? integer_constant(token.spelling)
                                                   : character_constant(token.spelling);
            return result;
        }
        if (token.kind == "identifier") {
            auto result = node("identifier");
            result->name = token.spelling;
            return result;
        }
        if (token.spelling == "(") {
            auto result = expression();
            if (peek() != ")")
                throw PreprocessingError{"missing ')' in expression"};
            ++index;
            return result;
        }
        throw PreprocessingError{"expected value before \"" + token.spelling + "\""};
    }
};
std::unique_ptr<ConditionExpr> parse_condition(const Tokens &tokens, const std::string &directive) {
    if (tokens.empty())
        throw PreprocessingError{"#" + directive + " with no expression"};
    ExpressionParser parser{tokens};
    auto result = parser.expression();
    if (parser.index < tokens.size())
        throw PreprocessingError{"missing binary operator before \"" + parser.peek() + "\""};
    return result;
}
int64_t evaluate_condition(const ConditionExpr &e,
                           const std::function<void(const std::string &)> &warning) {
    if (e.kind == "constant")
        return e.value;
    if (e.kind == "identifier") {
        warning("identifier \"" + e.name + "\" evaluates to 0");
        return 0;
    }
    int64_t a = evaluate_condition(*e.children[0], warning);
    if (e.kind == "unary") {
        if (e.op == "+")
            return a;
        if (e.op == "-")
            return -a;
        if (e.op == "!")
            return a == 0;
        return -a - 1;
    }
    if (e.kind == "conditional")
        return evaluate_condition(*e.children[a ? 1 : 2], warning);
    if (e.op == "&&" && !a)
        return 0;
    if (e.op == "||" && a)
        return 1;
    int64_t b = evaluate_condition(*e.children[1], warning);
    if (e.op == "+")
        return a + b;
    if (e.op == "-")
        return a - b;
    if (e.op == "*")
        return a * b;
    if (e.op == "/" || e.op == "%") {
        if (!b)
            throw PreprocessingError{"division by zero in #if"};
        int64_t q = a / b;
        return e.op == "/" ? q : a - b * q;
    }
    if (e.op == "<<")
        return a * (int64_t(1) << b);
    if (e.op == ">>") {
        int64_t divisor = int64_t(1) << b, q = a / divisor;
        if (a < 0 && a % divisor)
            --q;
        return q;
    }
    if (e.op == "&" || e.op == "|" || e.op == "^") {
        uint32_t left = static_cast<uint32_t>(a), right = static_cast<uint32_t>(b);
        uint32_t value = e.op == "&" ? left & right : e.op == "|" ? left | right : left ^ right;
        return value >= 0x80000000u ? static_cast<int64_t>(value) - 4294967296LL : value;
    }
    if (e.op == "==")
        return a == b;
    if (e.op == "!=")
        return a != b;
    if (e.op == "<")
        return a < b;
    if (e.op == ">")
        return a > b;
    if (e.op == "<=")
        return a <= b;
    if (e.op == ">=")
        return a >= b;
    return b != 0;
}
