#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstdint>
#include <iostream>
#include <map>
#include <memory>
#include <optional>
#include <regex>
#include <set>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <utility>
#include <variant>
#include <vector>

using Value = std::variant<int, std::string>;

struct SyntaxError : std::exception {};

struct BasicError : std::runtime_error {
    explicit BasicError(const std::string& text) : std::runtime_error(text) {}
};

[[noreturn]] void syntax() {
    throw SyntaxError{};
}

[[noreturn]] void fault(const std::string& message) {
    throw BasicError(message);
}

bool variable(const std::string& name) {
    static const std::regex pattern(R"([A-Z][0-9]?\$?)");
    return std::regex_match(name, pattern);
}

char name_type(const std::string& name) {
    return name.back() == '$' ? 'S' : 'I';
}

char value_type(const Value& value) {
    return std::holds_alternative<std::string>(value) ? 'S' : 'I';
}

const std::map<std::string, std::vector<std::string>> signatures = {
    {"ABS", {"I"}}, {"SGN", {"I"}}, {"INT", {"I"}},
    {"SQR", {"I"}}, {"RND", {"I"}}, {"LEN", {"S"}},
    {"ASC", {"S"}}, {"VAL", {"S"}}, {"CHR$", {"I"}},
    {"STR$", {"I"}}, {"LEFT$", {"SI"}}, {"RIGHT$", {"SI"}},
    {"MID$", {"SI", "SII"}}, {"INSTR", {"SS"}}
};

const std::map<std::string, int> error_codes = {
    {"NEXT WITHOUT FOR", 1}, {"RETURN WITHOUT GOSUB", 3},
    {"OUT OF DATA", 4}, {"ILLEGAL FUNCTION CALL", 5},
    {"OVERFLOW", 6}, {"OUT OF MEMORY", 7},
    {"UNDEFINED LINE NUMBER", 8}, {"SUBSCRIPT OUT OF RANGE", 9},
    {"DUPLICATE DEFINITION", 10}, {"DIVISION BY ZERO", 11},
    {"TYPE MISMATCH", 13}, {"STRING TOO LONG", 15},
    {"RESUME WITHOUT ERROR", 20}, {"FOR WITHOUT NEXT", 26},
    {"WHILE WITHOUT WEND", 29}, {"WEND WITHOUT WHILE", 30},
    {"INPUT PAST END", 62}
};

struct Token {
    char kind;
    std::string text;
    Value value;
};

bool digit(char c) {
    return c >= '0' && c <= '9';
}

bool upper(char c) {
    return c >= 'A' && c <= 'Z';
}

std::vector<Token> tokenize(const std::string& source) {
    std::vector<Token> result;
    std::size_t pos = 0;
    while (pos < source.size()) {
        char c = source[pos];
        if (c == ' ') {
            ++pos;
        } else if (c == '"') {
            auto end = source.find('"', pos + 1);
            if (end == std::string::npos) syntax();
            result.push_back({'S', source.substr(pos, end - pos + 1),
                              source.substr(pos + 1, end - pos - 1)});
            pos = end + 1;
        } else if (digit(c)) {
            auto start = pos;
            while (pos < source.size() && digit(source[pos])) ++pos;
            std::string word = source.substr(start, pos - start);
            long long value = 0;
            for (char letter : word) {
                value = value * 10 + letter - '0';
                if (value > 32767) syntax();
            }
            result.push_back({'I', word, static_cast<int>(value)});
        } else if (upper(c)) {
            if (source.compare(pos, 3, "REM") == 0) {
                result.push_back({'W', "REM", std::string("REM")});
                break;
            }
            auto start = pos;
            while (pos < source.size() && (upper(source[pos]) || digit(source[pos]))) ++pos;
            if (pos < source.size() && source[pos] == '$') ++pos;
            std::string word = source.substr(start, pos - start);
            result.push_back({'W', word, word});
        } else {
            std::string word(1, c);
            if (pos + 1 < source.size()) {
                std::string pair = source.substr(pos, 2);
                if (pair == "<>" || pair == "<=" || pair == ">=") word = pair;
            }
            if (std::string("+-*/^=<>() ,;:").find(c) == std::string::npos) syntax();
            result.push_back({'P', word, word});
            pos += word.size();
        }
    }
    result.push_back({'E', "", std::string("")});
    return result;
}

struct Expression;
using Expr = std::shared_ptr<Expression>;

struct Expression {
    std::string kind;
    char type;
    Value value;
    std::vector<Expr> args;
};

Expr expression_node(std::string kind, char type, Value value = std::string(""),
                     std::vector<Expr> args = {}) {
    return std::make_shared<Expression>(
        Expression{std::move(kind), type, std::move(value), std::move(args)});
}

struct Statement;
using Stmt = std::shared_ptr<Statement>;

struct PrintItem {
    std::string kind;
    Expr expr;
};

struct Clause {
    std::optional<int> line;
    std::vector<Stmt> body;
};

struct Statement {
    std::string kind;
    int line = 0;
    Statement* next = nullptr;
    Expr expr;
    Expr target;
    std::vector<Expr> targets;
    std::vector<Expr> expressions;
    std::vector<Value> values;
    std::vector<int> numbers;
    std::vector<Clause> clauses;
    std::vector<PrintItem> items;
    std::string name;
    std::string mode;
};

class Parser {
    std::vector<Token> tokens;
    std::size_t pos = 0;

    const Token& current() const {
        return tokens[pos];
    }

    bool at(const std::string& word) const {
        return (current().kind == 'P' || current().kind == 'W')
            && current().text == word;
    }

    bool take(const std::string& word) {
        if (!at(word)) return false;
        ++pos;
        return true;
    }

    void expect(const std::string& word) {
        if (!take(word)) syntax();
    }

    int number() {
        if (current().kind != 'I') syntax();
        return std::get<int>(tokens[pos++].value);
    }

    Expr integer(int level = 0) {
        Expr value = expression(level);
        if (value->type != 'I') syntax();
        return value;
    }

    Expr target() {
        const Token& token = current();
        if (token.kind != 'W' || !variable(token.text)) syntax();
        std::string name = token.text;
        ++pos;
        Expr result = expression_node("variable", name_type(name), name);
        if (take("(")) {
            result->kind = "array";
            result->args.push_back(integer());
            if (take(",")) result->args.push_back(integer());
            expect(")");
        }
        return result;
    }

    Expr primary() {
        const Token& token = current();
        if (token.kind == 'I' || token.kind == 'S') {
            ++pos;
            return expression_node("constant", token.kind, token.value);
        }
        if (take("(")) {
            Expr value = expression();
            expect(")");
            return value;
        }
        if (token.kind == 'W' && variable(token.text)) return target();
        if (take("ERR")) return expression_node("builtin", 'I', std::string("ERR"));
        if (take("ERL")) return expression_node("builtin", 'I', std::string("ERL"));
        if (token.kind == 'W' && signatures.contains(token.text)) {
            std::string name = token.text;
            ++pos;
            expect("(");
            std::vector<Expr> args{expression()};
            while (take(",")) args.push_back(expression());
            expect(")");
            std::string types;
            for (auto& e : args) types += e->type;
            auto& expected = signatures.at(name);
            if (std::find(expected.begin(), expected.end(), types) == expected.end()) syntax();
            return expression_node("call", name_type(name), name, std::move(args));
        }
        syntax();
    }

    Expr expression(int level = 0) {
        if (level == 2 && take("NOT"))
            return expression_node("unary", 'I', std::string("NOT"), {integer(2)});
        if (level == 6 && take("-"))
            return expression_node("unary", 'I', std::string("-"), {integer(6)});
        if (level == 8) return primary();
        Expr left = expression(level + 1);
        const std::vector<std::vector<std::string>> ops = {
            {"OR"}, {"AND"}, {}, {"=", "<>", "<", ">", "<=", ">="},
            {"+", "-"}, {"*", "/", "MOD"}, {}, {"^"}
        };
        while (std::find(ops[level].begin(), ops[level].end(), current().text) != ops[level].end()) {
            std::string op = tokens[pos++].text;
            Expr right = expression(level == 7 ? 6 : level + 1);
            if (left->type != right->type ||
                (left->type == 'S' && level != 3 && op != "+")) syntax();
            left = expression_node("binary", level == 3 ? 'I' : left->type,
                                   op, {left, right});
            if (level == 7) break;
        }
        return left;
    }

    Clause clause() {
        if (current().kind == 'I') return {number(), {}};
        return {std::nullopt, list(true)};
    }

    std::vector<Stmt> list(bool in_clause = false) {
        std::vector<Stmt> result{statement(in_clause)};
        while (take(":")) result.push_back(statement(in_clause));
        return result;
    }

    Stmt statement(bool in_clause) {
        std::string word = current().text;
        if (in_clause && std::set<std::string>{"IF", "FOR", "NEXT", "WHILE", "WEND", "DATA"}.contains(word))
            syntax();
        Stmt s = std::make_shared<Statement>();
        s->kind = word;
        if (take("REM") || take("RETURN") || take("WEND") || take("END") || take("STOP"))
            return s;
        if (take("PRINT")) {
            bool value_last = false;
            while (current().kind != 'E' && !at(":") && !at("ELSE")) {
                if (take(";")) {
                    s->items.push_back({";", nullptr});
                    value_last = false;
                } else if (take(",")) {
                    s->items.push_back({",", nullptr});
                    value_last = false;
                } else {
                    std::string mode = at("TAB") ? "TAB" : at("SPC") ? "SPC" : "value";
                    if (mode == "value" && value_last) syntax();
                    Expr value;
                    if (mode == "value") {
                        value = expression();
                    } else {
                        ++pos;
                        expect("(");
                        value = integer();
                        expect(")");
                    }
                    s->items.push_back({mode, value});
                    value_last = mode == "value";
                }
            }
            return s;
        }
        if (take("INPUT") || take("READ") || take("DIM")) {
            do {
                Expr ref = target();
                if (word == "DIM" && ref->kind != "array") syntax();
                s->targets.push_back(ref);
            } while (take(","));
            return s;
        }
        if (take("DATA")) {
            do {
                bool negative = take("-");
                Token token = current();
                if (token.kind != 'I' && (token.kind != 'S' || negative)) syntax();
                ++pos;
                if (negative) s->values.push_back(-std::get<int>(token.value));
                else s->values.push_back(token.value);
            } while (take(","));
            return s;
        }
        if (take("IF")) {
            s->expr = integer();
            expect("THEN");
            s->clauses.push_back(clause());
            if (take("ELSE")) s->clauses.push_back(clause());
            if (current().kind != 'E') syntax();
            return s;
        }
        if (take("GOTO") || take("GOSUB")) {
            s->numbers.push_back(number());
            return s;
        }
        if (take("ON")) {
            if (take("ERROR")) {
                s->kind = "handler";
                expect("GOTO");
                s->numbers.push_back(number());
            } else {
                s->expr = integer();
                if (take("GOTO")) s->mode = "GOTO";
                else {
                    expect("GOSUB");
                    s->mode = "GOSUB";
                }
                do {
                    s->numbers.push_back(number());
                } while (take(","));
            }
            return s;
        }
        if (take("RESUME")) {
            if (take("NEXT")) s->mode = "NEXT";
            else if (current().kind == 'I') {
                s->mode = "line";
                s->numbers.push_back(number());
            }
            return s;
        }
        if (take("FOR")) {
            Token token = current();
            if (token.kind != 'W' || !variable(token.text) || name_type(token.text) != 'I')
                syntax();
            s->name = token.text;
            ++pos;
            expect("=");
            s->expressions.push_back(integer());
            expect("TO");
            s->expressions.push_back(integer());
            s->expressions.push_back(take("STEP") ? integer() :
                                     expression_node("constant", 'I', 1));
            return s;
        }
        if (take("NEXT")) {
            if (current().kind == 'W' && variable(current().text) &&
                name_type(current().text) == 'I')
                s->name = tokens[pos++].text;
            return s;
        }
        if (take("WHILE") || take("RANDOMIZE")) {
            s->expr = integer();
            return s;
        }
        if (take("RESTORE")) {
            if (current().kind == 'I') s->numbers.push_back(number());
            return s;
        }
        take("LET");
        s->kind = "assign";
        s->target = target();
        expect("=");
        s->expr = expression();
        if (s->expr->type != s->target->type) syntax();
        return s;
    }

public:
    explicit Parser(std::vector<Token> source) : tokens(std::move(source)) {}

    std::vector<Stmt> parse() {
        auto result = list();
        if (current().kind != 'E') syntax();
        return result;
    }
};

struct BasicArray {
    std::vector<int> bounds;
    std::vector<Value> values;
};

struct Address {
    std::string name;
    std::optional<std::size_t> index;
};

struct Frame {
    std::string kind;
    Statement* position;
    std::string name;
    int end = 0;
    int step = 0;
};

class Machine {
    std::vector<std::string> inputs;
    std::map<std::string, Value> variables;
    std::map<std::string, BasicArray> arrays;
    std::vector<Frame> stack;
    std::map<int, Statement*> entries;
    std::vector<Statement*> sequence;
    std::vector<std::pair<int, Value>> data;
    std::size_t data_position = 0;
    std::size_t input_position = 0;
    std::int64_t random_state = 1;
    int handler = 0;
    bool handling = false;
    Statement* remembered = nullptr;
    int err = 0;
    int erl = 0;
    std::string buffer;
    std::vector<std::string> output;

    void end_line() {
        while (!buffer.empty() && buffer.back() == ' ') buffer.pop_back();
        output.push_back(buffer);
        buffer.clear();
    }

    void message(const std::string& text) {
        if (!buffer.empty()) end_line();
        output.push_back(text);
    }

    int checked(std::int64_t value) {
        if (value < -32768 || value > 32767) fault("OVERFLOW");
        return static_cast<int>(value);
    }

    Value get(const std::string& name) {
        auto found = variables.find(name);
        if (found != variables.end()) return found->second;
        return name_type(name) == 'S' ? Value(std::string("")) : Value(0);
    }

    void declare(const std::string& name, const std::vector<int>& bounds) {
        std::size_t count = 1;
        for (int bound : bounds) count *= static_cast<std::size_t>(bound + 1);
        Value zero = name_type(name) == 'S' ? Value(std::string("")) : Value(0);
        arrays[name] = {bounds, std::vector<Value>(count, zero)};
    }

    Address address(const Expr& target) {
        std::string name = std::get<std::string>(target->value);
        if (target->kind == "variable") return {name, std::nullopt};
        std::vector<int> indices;
        for (auto& arg : target->args) indices.push_back(std::get<int>(evaluate(arg)));
        if (!arrays.contains(name)) declare(name, std::vector<int>(indices.size(), 10));
        BasicArray& array = arrays.at(name);
        if (indices.size() != array.bounds.size()) fault("SUBSCRIPT OUT OF RANGE");
        std::size_t index = 0;
        for (std::size_t i = 0; i < indices.size(); ++i) {
            int value = indices[i];
            if (value < 0 || value > array.bounds[i]) fault("SUBSCRIPT OUT OF RANGE");
            index = index * (array.bounds[i] + 1) + value;
        }
        return {name, index};
    }

    Value load(const Address& address) {
        return address.index ? arrays.at(address.name).values.at(*address.index) : get(address.name);
    }

    void store(const Address& address, const Value& value) {
        if (address.index) arrays.at(address.name).values.at(*address.index) = value;
        else variables[address.name] = value;
    }

    int integer_power(int base, int exponent) {
        if (exponent < 0) fault("ILLEGAL FUNCTION CALL");
        std::int64_t result = 1;
        std::int64_t current = base;
        while (exponent > 0) {
            if (exponent % 2) result = checked(result * current);
            exponent /= 2;
            if (exponent) current = checked(current * current);
        }
        return static_cast<int>(result);
    }

    Value evaluate(const Expr& expression) {
        const Value& op = expression->value;
        if (expression->kind == "constant") return op;
        if (expression->kind == "variable" || expression->kind == "array")
            return load(address(expression));
        if (expression->kind == "builtin")
            return std::get<std::string>(op) == "ERR" ? err : erl;
        if (expression->kind == "unary") {
            int number = std::get<int>(evaluate(expression->args[0]));
            return std::get<std::string>(op) == "NOT" ? ~number : checked(-static_cast<std::int64_t>(number));
        }
        std::vector<Value> args;
        for (auto& part : expression->args) args.push_back(evaluate(part));
        if (expression->kind == "call") return call(std::get<std::string>(op), args);
        const std::string& operation = std::get<std::string>(op);
        const Value& a = args[0];
        const Value& b = args[1];
        if (std::set<std::string>{"=", "<>", "<", ">", "<=", ">="}.contains(operation)) {
            int order = 0;
            if (std::holds_alternative<std::string>(a))
                order = std::get<std::string>(a).compare(std::get<std::string>(b));
            else {
                int left = std::get<int>(a), right = std::get<int>(b);
                order = (left > right) - (left < right);
            }
            bool yes = operation == "=" ? order == 0 :
                       operation == "<>" ? order != 0 :
                       operation == "<" ? order < 0 :
                       operation == ">" ? order > 0 :
                       operation == "<=" ? order <= 0 : order >= 0;
            return yes ? -1 : 0;
        }
        if (expression->type == 'S') {
            std::string value = std::get<std::string>(a) + std::get<std::string>(b);
            if (value.size() > 255) fault("STRING TOO LONG");
            return value;
        }
        int x = std::get<int>(a), y = std::get<int>(b);
        if (operation == "+") return checked(static_cast<std::int64_t>(x) + y);
        if (operation == "-") return checked(static_cast<std::int64_t>(x) - y);
        if (operation == "*") return checked(static_cast<std::int64_t>(x) * y);
        if (operation == "/") {
            if (y == 0) fault("DIVISION BY ZERO");
            return checked(static_cast<std::int64_t>(x) / y);
        }
        if (operation == "MOD") {
            if (y == 0) fault("DIVISION BY ZERO");
            return x % y;
        }
        if (operation == "^") return integer_power(x, y);
        if (operation == "AND") return x & y;
        if (operation == "OR") return x | y;
        syntax();
    }

    Value call(const std::string& name, const std::vector<Value>& args) {
        int n = std::holds_alternative<int>(args[0]) ? std::get<int>(args[0]) : 0;
        std::string s = std::holds_alternative<std::string>(args[0]) ?
                        std::get<std::string>(args[0]) : "";
        int k = args.size() > 1 && std::holds_alternative<int>(args[1]) ?
                std::get<int>(args[1]) : 0;
        if (name == "ABS") return checked(std::llabs(static_cast<std::int64_t>(n)));
        if (name == "SGN") return (n > 0) - (n < 0);
        if (name == "INT") return n;
        if (name == "SQR") {
            if (n < 0) fault("ILLEGAL FUNCTION CALL");
            return static_cast<int>(std::sqrt(n));
        }
        if (name == "RND") {
            if (n < 1) fault("ILLEGAL FUNCTION CALL");
            random_state = (48271 * random_state) % 2147483647;
            return static_cast<int>(random_state % n) + 1;
        }
        if (name == "LEN") return static_cast<int>(s.size());
        if (name == "ASC") {
            if (s.empty()) fault("ILLEGAL FUNCTION CALL");
            return static_cast<int>(static_cast<unsigned char>(s[0]));
        }
        if (name == "VAL") {
            std::smatch match;
            static const std::regex pattern(R"(^ *([+-]?[0-9]+))");
            if (!std::regex_search(s, match, pattern)) return 0;
            std::int64_t result = 0;
            try {
                result = std::stoll(match[1].str());
            } catch (const std::out_of_range&) {
                fault("OVERFLOW");
            }
            return checked(result);
        }
        if (name == "CHR$") {
            if (n < 32 || n > 126) fault("ILLEGAL FUNCTION CALL");
            return std::string(1, static_cast<char>(n));
        }
        if (name == "STR$") return std::to_string(n);
        if (name == "LEFT$") {
            if (k < 0) fault("ILLEGAL FUNCTION CALL");
            return s.substr(0, static_cast<std::size_t>(k));
        }
        if (name == "RIGHT$") {
            if (k < 0) fault("ILLEGAL FUNCTION CALL");
            return s.substr(s.size() - std::min(s.size(), static_cast<std::size_t>(k)));
        }
        if (name == "MID$") {
            if (k < 1) fault("ILLEGAL FUNCTION CALL");
            int length = args.size() == 3 ? std::get<int>(args[2]) :
                         static_cast<int>(s.size());
            if (length < 0) fault("ILLEGAL FUNCTION CALL");
            if (static_cast<std::size_t>(k) > s.size()) return std::string("");
            return s.substr(k - 1, length);
        }
        if (name == "INSTR") {
            auto pos = s.find(std::get<std::string>(args[1]));
            return pos == std::string::npos ? 0 : static_cast<int>(pos + 1);
        }
        syntax();
    }

    Statement* line(int number) {
        auto found = entries.find(number);
        if (found == entries.end()) fault("UNDEFINED LINE NUMBER");
        return found->second;
    }

    void push(const Frame& frame) {
        if (stack.size() == 100) fault("OUT OF MEMORY");
        stack.push_back(frame);
    }

    int search(const std::string& kind, const std::string& name = "") {
        for (int i = static_cast<int>(stack.size()) - 1; i >= 0; --i) {
            const Frame& frame = stack[i];
            if (frame.kind == "GOSUB") break;
            if (frame.kind == kind && (name.empty() || frame.name == name)) return i;
        }
        return -1;
    }

    Statement* matching(Statement* s, const std::string& open, const std::string& close) {
        auto found = std::find(sequence.begin(), sequence.end(), s);
        int depth = 0;
        for (auto it = found + 1; it != sequence.end(); ++it) {
            Statement* current = *it;
            if (current->kind == open) ++depth;
            else if (current->kind == close) {
                if (depth == 0) return current->next;
                --depth;
            }
        }
        fault(open + " WITHOUT " + close);
    }

    Statement* subroutine(int number, Statement* after) {
        Statement* destination = line(number);
        push({"GOSUB", after});
        return destination;
    }

    Statement* execute(Statement* s) {
        Statement* next = s->next;
        if (s->kind == "REM" || s->kind == "DATA") return next;
        if (s->kind == "assign") {
            Address place = address(s->target);
            store(place, evaluate(s->expr));
        } else if (s->kind == "PRINT") {
            for (auto& item : s->items) {
                if (item.kind == ",") {
                    buffer.append(10 - buffer.size() % 10, ' ');
                } else if (item.kind != ";") {
                    Value v = evaluate(item.expr);
                    if (item.kind == "value") {
                        buffer += std::holds_alternative<std::string>(v) ?
                                  std::get<std::string>(v) :
                                  std::to_string(std::get<int>(v));
                    } else {
                        int n = std::get<int>(v);
                        if (n < 0) fault("ILLEGAL FUNCTION CALL");
                        std::size_t count = item.kind == "SPC" ? n :
                            std::max<std::int64_t>(0, static_cast<std::int64_t>(n) - static_cast<std::int64_t>(buffer.size()));
                        buffer.append(count, ' ');
                    }
                }
            }
            if (s->items.empty() ||
                (s->items.back().kind != ";" && s->items.back().kind != ","))
                end_line();
        } else if (s->kind == "INPUT" || s->kind == "READ") {
            for (auto& target : s->targets) {
                Address place = address(target);
                Value value;
                if (s->kind == "READ") {
                    if (data_position == data.size()) fault("OUT OF DATA");
                    value = data[data_position++].second;
                    if (value_type(value) != target->type) fault("TYPE MISMATCH");
                } else {
                    for (;;) {
                        if (input_position == inputs.size()) fault("INPUT PAST END");
                        std::string text = inputs[input_position++];
                        if (target->type == 'S') {
                            value = text;
                            break;
                        }
                        static const std::regex pattern(R"(-?[0-9]+)");
                        if (std::regex_match(text, pattern)) {
                            try {
                                auto n = std::stoll(text);
                                if (n >= -32768 && n <= 32767) {
                                    value = static_cast<int>(n);
                                    break;
                                }
                            } catch (const std::out_of_range&) {}
                        }
                        message("?REDO FROM START");
                    }
                }
                store(place, value);
            }
        } else if (s->kind == "RESTORE") {
            if (s->numbers.empty()) data_position = 0;
            else {
                int target = s->numbers[0];
                line(target);
                auto it = std::find_if(data.begin(), data.end(),
                                       [target](const auto& item) { return item.first >= target; });
                data_position = static_cast<std::size_t>(it - data.begin());
            }
        } else if (s->kind == "IF") {
            auto index = std::get<int>(evaluate(s->expr)) != 0 ? 0u : 1u;
            if (index < s->clauses.size()) {
                Clause& clause = s->clauses[index];
                next = clause.line ? line(*clause.line) : clause.body.front().get();
            }
        } else if (s->kind == "GOTO") {
            next = line(s->numbers[0]);
        } else if (s->kind == "GOSUB") {
            next = subroutine(s->numbers[0], next);
        } else if (s->kind == "ON") {
            int index = std::get<int>(evaluate(s->expr));
            if (index < 0) fault("ILLEGAL FUNCTION CALL");
            if (index > 0 && static_cast<std::size_t>(index) <= s->numbers.size()) {
                int destination = s->numbers[index - 1];
                next = s->mode == "GOTO" ? line(destination) : subroutine(destination, next);
            }
        } else if (s->kind == "RETURN") {
            int found = static_cast<int>(stack.size()) - 1;
            while (found >= 0 && stack[found].kind != "GOSUB") --found;
            if (found < 0) fault("RETURN WITHOUT GOSUB");
            next = stack[found].position;
            stack.resize(found);
        } else if (s->kind == "FOR") {
            int start = std::get<int>(evaluate(s->expressions[0]));
            int last = std::get<int>(evaluate(s->expressions[1]));
            int step = std::get<int>(evaluate(s->expressions[2]));
            if (step == 0) fault("ILLEGAL FUNCTION CALL");
            int found = search("FOR", s->name);
            if (found >= 0) stack.resize(found);
            variables[s->name] = start;
            if (step > 0 ? start > last : start < last)
                next = matching(s, "FOR", "NEXT");
            else push({"FOR", next, s->name, last, step});
        } else if (s->kind == "NEXT") {
            int found = search("FOR", s->name);
            if (found < 0) fault("NEXT WITHOUT FOR");
            stack.resize(found + 1);
            Frame frame = stack[found];
            int value = checked(static_cast<std::int64_t>(std::get<int>(get(frame.name))) + frame.step);
            variables[frame.name] = value;
            if (frame.step > 0 ? value > frame.end : value < frame.end)
                stack.pop_back();
            else next = frame.position;
        } else if (s->kind == "WHILE") {
            if (std::get<int>(evaluate(s->expr)) != 0) push({"WHILE", s});
            else next = matching(s, "WHILE", "WEND");
        } else if (s->kind == "WEND") {
            int found = search("WHILE");
            if (found < 0) fault("WEND WITHOUT WHILE");
            next = stack[found].position;
            stack.resize(found);
        } else if (s->kind == "DIM") {
            for (auto& target : s->targets) {
                std::string name = std::get<std::string>(target->value);
                std::vector<int> bounds;
                for (auto& arg : target->args) bounds.push_back(std::get<int>(evaluate(arg)));
                if (arrays.contains(name)) fault("DUPLICATE DEFINITION");
                std::int64_t elements = 1;
                for (int bound : bounds) {
                    if (bound < 0) fault("ILLEGAL FUNCTION CALL");
                    elements *= bound + 1;
                }
                if (elements > 10000) fault("OUT OF MEMORY");
                declare(name, bounds);
            }
        } else if (s->kind == "RANDOMIZE") {
            int n = std::get<int>(evaluate(s->expr));
            if (n < 1) fault("ILLEGAL FUNCTION CALL");
            random_state = n;
        } else if (s->kind == "handler") {
            if (s->numbers[0] != 0) line(s->numbers[0]);
            handler = s->numbers[0];
        } else if (s->kind == "RESUME") {
            if (!handling) fault("RESUME WITHOUT ERROR");
            next = s->mode == "line" ? line(s->numbers[0]) :
                   s->mode == "NEXT" ? remembered->next : remembered;
            handling = false;
        } else if (s->kind == "STOP") {
            message("BREAK IN LINE " + std::to_string(s->line));
            return nullptr;
        } else if (s->kind == "END") {
            return nullptr;
        }
        return next;
    }

    void connect(const std::vector<Stmt>& body, Statement* after, int number) {
        Statement* next = after;
        for (auto it = body.rbegin(); it != body.rend(); ++it) {
            Statement* s = it->get();
            s->line = number;
            s->next = next;
            for (auto& clause : s->clauses) connect(clause.body, next, number);
            next = s;
        }
    }

    std::vector<std::string> finish() {
        if (!buffer.empty()) end_line();
        output.push_back("READY");
        return output;
    }

public:
    explicit Machine(std::vector<std::string> input) : inputs(std::move(input)) {}

    std::vector<std::string> run(const std::map<int, std::string>& source) {
        std::vector<std::pair<int, std::vector<Stmt>>> parsed;
        for (auto& [number, text] : source) {
            try {
                parsed.push_back({number, Parser(tokenize(text)).parse()});
            } catch (const SyntaxError&) {
                message("ERROR IN LINE " + std::to_string(number) + ": SYNTAX ERROR");
                return finish();
            }
        }
        Statement* after = nullptr;
        for (auto it = parsed.rbegin(); it != parsed.rend(); ++it) {
            connect(it->second, after, it->first);
            entries[it->first] = it->second.front().get();
            after = it->second.front().get();
        }
        for (auto& [number, body] : parsed) {
            for (auto& statement : body) {
                sequence.push_back(statement.get());
                if (statement->kind == "DATA")
                    for (auto& value : statement->values) data.emplace_back(number, value);
            }
        }
        Statement* position = after;
        while (position != nullptr) {
            Statement* statement = position;
            try {
                position = execute(statement);
            } catch (const BasicError& error) {
                if (handler != 0 && !handling) {
                    err = error_codes.at(error.what());
                    erl = statement->line;
                    remembered = statement;
                    handling = true;
                    position = line(handler);
                } else {
                    message("ERROR IN LINE " + std::to_string(statement->line) +
                            ": " + error.what());
                    position = nullptr;
                }
            }
        }
        return finish();
    }
};

int main() {
    std::ios::sync_with_stdio(false);
    std::cin.tie(nullptr);
    int sessions;
    if (!(std::cin >> sessions)) return 0;
    std::string line;
    std::getline(std::cin, line);
    static const std::regex entry(R"(([0-9]+)(?: +(.*))?)");
    for (int session = 0; session < sessions; ++session) {
        std::map<int, std::string> source;
        while (std::getline(std::cin, line) && line != "RUN") {
            std::smatch match;
            if (!std::regex_match(line, match, entry)) continue;
            int number = std::stoi(match[1].str());
            if (match[2].matched) source[number] = match[2].str();
            else source.erase(number);
        }
        std::vector<std::string> input;
        while (std::getline(std::cin, line) && line != "END") input.push_back(line);
        for (auto& output : Machine(std::move(input)).run(source))
            std::cout << output << '\n';
    }
}
