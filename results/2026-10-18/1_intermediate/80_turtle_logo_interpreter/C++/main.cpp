#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <iostream>
#include <initializer_list>
#include <map>
#include <memory>
#include <optional>
#include <queue>
#include <set>
#include <string>
#include <utility>
#include <vector>

using namespace std;
using Integer = long long;

struct LogoError {
    int line;
    string reason;
};
struct Token {
    string text, kind;
    int line = 0;
    bool sign = false;
};
[[noreturn]] void fail(const Token& token, const string& reason) {
    throw LogoError{token.line, reason};
}
bool name_word(const string& text) {
    if (text.empty() || text[0] < 'A' || text[0] > 'Z') return false;
    for (char ch : text) if (!(ch >= 'A' && ch <= 'Z') && !(ch >= '0' && ch <= '9') && ch != '_') return false;
    return true;
}
vector<Token> lex(string text, int line) {
    size_t comment = text.find(';');
    if (comment != string::npos) text.resize(comment);
    for (char& ch : text) if (ch >= 'a' && ch <= 'z') ch -= 'a' - 'A';
    vector<Token> result;
    const string delimiters = " []()+-*/=<>";
    for (size_t i = 0; i < text.size();) {
        if (text[i] == ' ') {
            ++i;
            continue;
        }
        size_t start = i;
        Token token{"", "symbol", line, false};
        if (delimiters.find(text[i]) != string::npos) {
            char ch = text[i++];
            if ((ch == '<' && i < text.size() && (text[i] == '=' || text[i] == '>')) ||
                (ch == '>' && i < text.size() && text[i] == '=')) ++i;
            token.text = text.substr(start, i - start);
            if (ch == '-') token.sign = (start == 0 || text[start - 1] == ' ' || text[start - 1] == '[' || text[start - 1] == '(') &&
                                           i < text.size() && text[i] != ' ';
        } else {
            while (i < text.size() && delimiters.find(text[i]) == string::npos) ++i;
            token.text = text.substr(start, i - start);
            bool digits = all_of(token.text.begin(), token.text.end(), [](char ch) {
                return ch >= '0' && ch <= '9';
            });
            if (digits) token.kind = "number";
            else if (token.text[0] == ':' && name_word(token.text.substr(1))) token.kind = "variable";
            else if (token.text[0] == '"' && name_word(token.text.substr(1))) token.kind = "quoted";
            else if (name_word(token.text)) token.kind = "word";
            else fail(token, "bad token '" + token.text + "'");
        }
        result.push_back(token);
    }
    return result;
}

struct Primitive {
    string canonical, signature;
    bool function;
};
map<string, Primitive> primitives() {
    map<string, Primitive> result;
    auto add = [&](const string& canonical, const string& signature, bool function, initializer_list<string> aliases = {}) {
        result[canonical] = {canonical, signature, function};
        for (const auto& alias : aliases) result[alias] = {canonical, signature, function};
    };
    add("FD", "E", false, {"FORWARD"});
    add("BK", "E", false, {"BACK"});
    add("RT", "E", false, {"RIGHT"});
    add("LT", "E", false, {"LEFT"});
    add("SETH", "E", false, {"SETHEADING"});
    add("PU", "", false, {"PENUP"});
    add("PD", "", false, {"PENDOWN"});
    add("PE", "", false, {"PENERASE"});
    add("SETPEN", "E", false);
    add("SETXY", "EE", false);
    add("SETX", "E", false);
    add("SETY", "E", false);
    add("HOME", "", false);
    add("CS", "", false, {"CLEARSCREEN"});
    add("CLEAN", "", false);
    add("FILL", "", false);
    add("LABEL", "P", false);
    add("SNAPSHOT", "", false);
    add("REPEAT", "EL", false);
    add("FOR", "QEEL", false);
    add("WHILE", "EL", false);
    add("IF", "EL", false);
    add("IFELSE", "ELL", false);
    add("TEST", "E", false);
    add("IFTRUE", "L", false, {"IFT"});
    add("IFFALSE", "L", false, {"IFF"});
    add("STOP", "", false);
    add("OUTPUT", "E", false, {"OP"});
    add("MAKE", "QE", false);
    add("LOCAL", "Q", false);
    add("LOCALMAKE", "QE", false);
    add("TRACE", "Q", false);
    add("UNTRACE", "Q", false);
    add("SEED", "E", false);
    add("PRINT", "P", false, {"PR"});
    for (const string& word : {"XCOR", "YCOR", "HEADING", "REPCOUNT"}) add(word, "", true);
    for (const string& word : {"RANDOM", "ABS", "NOT"}) add(word, "E", true);
    for (const string& word : {"AND", "OR", "MAX", "MIN"}) add(word, "EE", true);
    return result;
}

struct Expr;
using Expression = shared_ptr<Expr>;
struct Expr {
    Token token;
    string kind, operation;
    vector<Expression> children;
};
struct Item {
    bool quoted = false;
    string word;
    Expression expression;
};
struct Command {
    Token token;
    string operation;
    bool procedure = false;
    vector<Item> items;
    vector<vector<Command>> lists;
};
struct Procedure {
    Token definition;
    vector<string> parameters;
    vector<Token> tokens;
    vector<Command> body;
};

class Parser {
    const vector<Token>& tokens;
    const map<string, Primitive>& builtins;
    const map<string, Procedure>& procedures;
    bool top_level;
    size_t position = 0;
    bool at(const string& text) const {
        return position < tokens.size() && tokens[position].text == text;
    }
    bool unknown(const Token& token) const {
        return token.kind == "word" && !builtins.count(token.text) && !procedures.count(token.text) &&
               token.text != "TO" && token.text != "END" && token.text != "MOD";
    }
    void available(const Token& owner) const {
        if (position == tokens.size() || at("]") || at(")")) fail(owner, "not enough inputs to " + owner.text);
        if (unknown(tokens[position])) fail(tokens[position], "I don't know how to " + tokens[position].text);
    }
    [[noreturn]] void reject(const Token& owner, const Token& value) const {
        fail(value, owner.text + " doesn't like " + value.text + " as input");
    }
    Expression term(const Token& owner) {
        available(owner);
        Token token = tokens[position++];
        auto result = make_shared<Expr>();
        result->token = token;
        if (token.kind == "number") result->kind = "number";
        else if (token.kind == "variable") result->kind = "variable";
        else if (token.text == "-") {
            result->kind = "unary";
            result->children.push_back(term(token));
        } else if (token.text == "(") {
            auto value = expression(token);
            if (!at(")")) fail(token, "missing )");
            ++position;
            return value;
        } else if (procedures.count(token.text)) {
            result->kind = "procedure";
            result->operation = token.text;
            for (size_t i = 0; i < procedures.at(token.text).parameters.size(); ++i)
                result->children.push_back(expression(token));
        } else if (builtins.count(token.text) && builtins.at(token.text).function) {
            const auto& primitive = builtins.at(token.text);
            result->kind = "function";
            result->operation = primitive.canonical;
            for (size_t i = 0; i < primitive.signature.size(); ++i) result->children.push_back(expression(token));
        } else reject(owner, token);
        return result;
    }
    Expression binary(const Token& owner, int level) {
        auto left = level == 2 ? term(owner) : binary(owner, level + 1);
        while (position < tokens.size()) {
            const Token& next = tokens[position];
            bool matches = level == 0 ? next.text == "=" || next.text == "<>" || next.text == "<" || next.text == ">" || next.text == "<=" || next.text == ">=" :
                           level == 1 ? next.text == "+" || (next.text == "-" && !next.sign) :
                                        next.text == "*" || next.text == "/" || next.text == "MOD";
            if (!matches) break;
            Token operation = tokens[position++];
            auto right = level == 2 ? term(operation) : binary(operation, level + 1);
            left = make_shared<Expr>(Expr{operation, "binary", operation.text, {left, right}});
        }
        return left;
    }
    Expression expression(const Token& owner) {
        return binary(owner, 0);
    }
    Item item(const Token& owner, char kind) {
        available(owner);
        if ((kind == 'Q' || kind == 'P') && tokens[position].kind == "quoted") {
            string word = tokens[position++].text.substr(1);
            return {true, word, nullptr};
        }
        if (kind == 'Q') reject(owner, tokens[position]);
        return {false, "", expression(owner)};
    }
    vector<Command> list(const Token& owner) {
        available(owner);
        if (!at("[")) reject(owner, tokens[position]);
        Token opening = tokens[position++];
        vector<Command> result;
        while (position < tokens.size() && !at("]")) result.push_back(command());
        if (position == tokens.size()) fail(opening, "missing ]");
        ++position;
        return result;
    }
    Command command() {
        Token token = tokens[position++];
        if (token.text == "]") fail(token, "unexpected ]");
        Command result;
        result.token = token;
        if (token.text == "(" && position < tokens.size() &&
            (tokens[position].text == "PRINT" || tokens[position].text == "PR")) {
            Token word = tokens[position++];
            result.operation = "PRINT";
            while (!at(")")) {
                if (position == tokens.size() || at("]")) fail(token, "missing )");
                result.items.push_back(item(word, 'P'));
            }
            ++position;
            return result;
        }
        if (token.text == "TO" || token.text == "END") fail(token, "misplaced " + token.text);
        auto primitive = builtins.find(token.text);
        if (primitive != builtins.end() && !primitive->second.function) {
            result.operation = primitive->second.canonical;
            if (top_level && (result.operation == "STOP" || result.operation == "OUTPUT" || result.operation == "LOCAL" || result.operation == "LOCALMAKE"))
                fail(token, "can only use " + token.text + " inside a procedure");
            for (char kind : primitive->second.signature) {
                if (kind == 'L') result.lists.push_back(list(token));
                else result.items.push_back(item(token, kind));
            }
            if ((result.operation == "TRACE" || result.operation == "UNTRACE") && !procedures.count(result.items[0].word)) {
                // The quote token is immediately after TRACE/UNTRACE.
                const Token& quote = tokens[position - 1];
                fail(quote, "I don't know how to " + result.items[0].word);
            }
            return result;
        }
        if (procedures.count(token.text)) {
            result.operation = token.text;
            result.procedure = true;
            for (size_t i = 0; i < procedures.at(token.text).parameters.size(); ++i) result.items.push_back(item(token, 'E'));
            return result;
        }
        if (unknown(token)) fail(token, "I don't know how to " + token.text);
        fail(token, "you don't say what to do with " + token.text);
    }
public:
    Parser(const vector<Token>& tokens, const map<string, Primitive>& builtins,
           const map<string, Procedure>& procedures, bool top)
        : tokens(tokens), builtins(builtins), procedures(procedures), top_level(top) {
        }
    vector<Command> parse() {
        vector<Command> result;
        while (position < tokens.size()) result.push_back(command());
        return result;
    }
};

struct Return {
    optional<Integer> value;
};
struct Environment {
    map<string, Integer> variables;
    optional<bool> test;
};

class Machine {
    const map<string, Procedure>& procedures;
    int x = 0, y = 0, heading = 0;
    string pen = "DOWN";
    char character = '*';
    map<pair<int, int>, char> canvas;
    vector<Environment> environments{Environment{}};
    vector<Integer> repetitions;
    set<string> traced;
    Integer random_state = 1;
    pair<int, int> direction() const {
        static const pair<int, int> directions[] = {{0, 1}, {1, 1}, {1, 0}, {1, -1}, {0, -1}, {-1, -1}, {-1, 0}, {-1, 1}};
        return directions[heading / 45];
    }
    void apply(int px, int py) {
        if (pen == "DOWN") canvas[{px, py}] = character;
        else if (pen == "ERASE") canvas.erase({px, py});
    }
    static Integer floor_div(Integer numerator, Integer denominator) {
        return numerator >= 0 ? numerator / denominator : -((-numerator + denominator - 1) / denominator);
    }
    void move_to(int nx, int ny) {
        Integer dx = nx - x, dy = ny - y, steps = max(abs(dx), abs(dy));
        if (!steps) apply(x, y);
        else for (Integer i = 0; i <= steps; ++i)
            apply(x + floor_div(2 * i * dx + steps, 2 * steps), y + floor_div(2 * i * dy + steps, 2 * steps));
        x = nx;
        y = ny;
    }
    void make_variable(const string& name, Integer value) {
        for (size_t i = environments.size() - 1; i > 0; --i) if (environments[i].variables.count(name)) {
            environments[i].variables[name] = value;
            return;
        }
        environments[0].variables[name] = value;
    }
    optional<Integer> invoke(const Token& token, const vector<Integer>& values) {
        if (active.size() == 100) fail(token, "recursion too deep");
        const auto& procedure = procedures.at(token.text);
        bool tracing = traced.count(token.text);
        string indent(2 * active.size(), ' ');
        if (tracing) {
            cout << indent << "( " << token.text;
            for (Integer value : values) cout << ' ' << value;
            cout << " )\n";
        }
        Environment environment;
        for (size_t i = 0; i < values.size(); ++i) environment.variables[procedure.parameters[i]] = values[i];
        environments.push_back(move(environment));
        active.push_back(token.text);
        optional<Integer> result;
        try {
            execute(procedure.body);
        }
        catch (const Return& stopped) {
            result = stopped.value;
        }
        environments.pop_back();
        active.pop_back();
        if (tracing) {
            cout << indent << token.text;
            if (result) cout << " outputs " << *result << '\n';
            else cout << " stops\n";
        }
        return result;
    }
    Integer evaluate(const Expression& expression) {
        const Token& token = expression->token;
        if (expression->kind == "number") return stoll(token.text);
        if (expression->kind == "variable") {
            string name = token.text.substr(1);
            for (auto i = environments.rbegin(); i != environments.rend(); ++i) {
                auto found = i->variables.find(name);
                if (found != i->variables.end()) return found->second;
            }
            fail(token, name + " has no value");
        }
        if (expression->kind == "unary") return -evaluate(expression->children[0]);
        vector<Integer> values;
        for (const auto& child : expression->children) values.push_back(evaluate(child));
        if (expression->kind == "procedure") {
            auto result = invoke(token, values);
            if (!result) fail(token, token.text + " did not output");
            return *result;
        }
        string op = expression->operation;
        if (expression->kind == "binary") {
            Integer a = values[0], b = values[1];
            if ((op == "/" || op == "MOD") && b == 0) fail(token, op + " doesn't like 0 as input");
            if (op == "+") return a + b;
            if (op == "-") return a - b;
            if (op == "*") return a * b;
            if (op == "/") return a / b;
            if (op == "MOD") return a % b;
            if (op == "=") return a == b;
            if (op == "<>") return a != b;
            if (op == "<") return a < b;
            if (op == ">") return a > b;
            if (op == "<=") return a <= b;
            return a >= b;
        }
        if (op == "XCOR") return x;
        if (op == "YCOR") return y;
        if (op == "HEADING") return heading;
        if (op == "REPCOUNT") {
            if (repetitions.empty()) fail(token, "REPCOUNT outside REPEAT");
            return repetitions.back();
        }
        if (op == "RANDOM") {
            if (values[0] < 1) fail(token, token.text + " doesn't like " + to_string(values[0]) + " as input");
            random_state = 48271 * random_state % 2147483647;
            return random_state % values[0];
        }
        if (op == "ABS") return abs(values[0]);
        if (op == "NOT") return values[0] == 0;
        if (op == "AND") return values[0] != 0 && values[1] != 0;
        if (op == "OR") return values[0] != 0 || values[1] != 0;
        if (op == "MAX") return max(values[0], values[1]);
        return min(values[0], values[1]);
    }
    void fill() {
        if (canvas.empty() || canvas.count({x, y})) return;
        int x1 = x, x2 = x, y1 = y, y2 = y;
        bool first = true;
        for (const auto& [position, mark] : canvas) {
            auto [px, py] = position;
            if (first) {
                x1 = x2 = px;
                y1 = y2 = py;
                first = false;
            }
            x1 = min(x1, px);
            x2 = max(x2, px);
            y1 = min(y1, py);
            y2 = max(y2, py);
        }
        if (x < x1 || x > x2 || y < y1 || y > y2) return;
        queue<pair<int, int>> pending;
        pending.push({x, y});
        canvas[{x, y}] = character;
        const int dx[] = {1, -1, 0, 0}, dy[] = {0, 0, 1, -1};
        while (!pending.empty()) {
            auto [px, py] = pending.front();
            pending.pop();
            for (int d = 0; d < 4; ++d) {
                int nx = px + dx[d], ny = py + dy[d];
                if (nx >= x1 && nx <= x2 && ny >= y1 && ny <= y2 && !canvas.count({nx, ny})) {
                    canvas[{nx, ny}] = character;
                    pending.push({nx, ny});
                }
            }
        }
    }
    void run(const Command& command) {
        const auto& op = command.operation;
        const auto& token = command.token;
        if (op == "WHILE" && !command.procedure) {
            while (evaluate(command.items[0].expression) != 0) execute(command.lists[0]);
            return;
        }
        vector<Integer> values;
        vector<string> strings;
        for (const auto& item : command.items) {
            Integer value = item.quoted ? 0 : evaluate(item.expression);
            values.push_back(value);
            strings.push_back(item.quoted ? item.word : to_string(value));
        }
        if (command.procedure) {
            auto result = invoke(token, values);
            if (result) fail(token, "you don't say what to do with " + to_string(*result));
            return;
        }
        if (op == "PRINT") {
            for (size_t i = 0; i < strings.size(); ++i) cout << (i ? " " : "") << strings[i];
            cout << '\n';
        } else if (op == "FD" || op == "BK") {
            auto [dx, dy] = direction();
            Integer count = values[0] * (op == "BK" ? -1 : 1);
            if (count < 0) {
                count = -count;
                dx = -dx;
                dy = -dy;
            }
            apply(x, y);
            for (Integer i = 0; i < count; ++i) {
                x += dx;
                y += dy;
                apply(x, y);
            }
        } else if (op == "RT" || op == "LT" || op == "SETH") {
            Integer a = values[0];
            if (a % 45) fail(token, token.text + " doesn't like " + to_string(a) + " as input");
            Integer next = op == "SETH" ? a : heading + (op == "LT" ? -a : a);
            heading = (next % 360 + 360) % 360;
        } else if (op == "PU" || op == "PD" || op == "PE") pen = op == "PU" ? "UP" : op == "PD" ? "DOWN" : "ERASE";
        else if (op == "SETPEN") {
            if (values[0] < 33 || values[0] > 126) fail(token, "SETPEN doesn't like " + to_string(values[0]) + " as input");
            character = char(values[0]);
        } else if (op == "SETXY") move_to(values[0], values[1]);
        else if (op == "SETX") move_to(values[0], y);
        else if (op == "SETY") move_to(x, values[0]);
        else if (op == "HOME") {
            move_to(0, 0);
            heading = 0;
        }
        else if (op == "CS") {
            canvas.clear();
            x = y = heading = 0;
        }
        else if (op == "CLEAN") canvas.clear();
        else if (op == "FILL") fill();
        else if (op == "LABEL") {
            auto [dx, dy] = direction();
            for (size_t i = 0; i < strings[0].size(); ++i) canvas[{x + int(i) * dx, y + int(i) * dy}] = strings[0][i];
        } else if (op == "SNAPSHOT") picture();
        else if (op == "MAKE") make_variable(command.items[0].word, values[1]);
        else if (op == "LOCAL" || op == "LOCALMAKE") environments.back().variables[command.items[0].word] = op == "LOCAL" ? 0 : values[1];
        else if (op == "TRACE") traced.insert(command.items[0].word);
        else if (op == "UNTRACE") traced.erase(command.items[0].word);
        else if (op == "STOP") throw Return{nullopt};
        else if (op == "OUTPUT") throw Return{values[0]};
        else if (op == "TEST") environments.back().test = values[0] != 0;
        else if (op == "IFTRUE" || op == "IFFALSE") {
            if (!environments.back().test) fail(token, token.text + " without TEST");
            if (*environments.back().test == (op == "IFTRUE")) execute(command.lists[0]);
        } else if (op == "IF" || op == "IFELSE") {
            if (values[0] != 0) execute(command.lists[0]);
            else if (op == "IFELSE") execute(command.lists[1]);
        } else if (op == "REPEAT") {
            if (command.lists[0].empty()) return;
            for (Integer k = 1; k <= values[0]; ++k) {
                repetitions.push_back(k);
                try {
                    execute(command.lists[0]);
                }
                catch (const Return&) {
                    repetitions.pop_back();
                    throw;
                }
                repetitions.pop_back();
            }
        } else if (op == "FOR") {
            Integer first = values[1], last = values[2], step = first <= last ? 1 : -1;
            if (command.lists[0].empty()) {
                make_variable(command.items[0].word, last);
                return;
            }
            for (Integer value = first;; value += step) {
                make_variable(command.items[0].word, value);
                execute(command.lists[0]);
                if (value == last) break;
            }
        } else if (op == "SEED") {
            if (values[0] < 1) fail(token, "SEED doesn't like " + to_string(values[0]) + " as input");
            random_state = values[0];
        }
    }
public:
    vector<string> active;
    explicit Machine(const map<string, Procedure>& procedures) : procedures(procedures) {
    }
    void execute(const vector<Command>& commands) {
        for (const auto& command : commands) run(command);
    }
    void picture() const {
        if (canvas.empty()) {
            cout << "CANVAS 0 0 0\n";
            return;
        }
        int x1 = canvas.begin()->first.first, x2 = x1;
        int y1 = canvas.begin()->first.second, y2 = y1;
        for (const auto& [position, mark] : canvas) {
            x1 = min(x1, position.first);
            x2 = max(x2, position.first);
            y1 = min(y1, position.second);
            y2 = max(y2, position.second);
        }
        cout << "CANVAS " << x2 - x1 + 1 << ' ' << y2 - y1 + 1 << ' ' << canvas.size() << '\n';
        for (int py = y2; py >= y1; --py) {
            string row;
            for (int px = x1; px <= x2; ++px) {
                auto found = canvas.find({px, py});
                row += found == canvas.end() ? ' ' : found->second;
            }
            while (!row.empty() && row.back() == ' ') row.pop_back();
            cout << row << '\n';
        }
    }
    void finish() const {
        cout << "TURTLE " << x << ' ' << y << ' ' << heading << ' ' << pen << ' ' << character << '\n';
        picture();
    }
};

void program(const string& name, const vector<pair<int, string>>& lines) {
    cout << "PROGRAM " << name << '\n';
    auto builtins = primitives();
    map<string, Procedure> procedures;
    vector<string> order;
    vector<Token> top_tokens;
    string defining;
    try {
        for (const auto& [number, line] : lines) {
            auto tokens = lex(line, number);
            if (tokens.empty()) continue;
            if (tokens[0].kind == "word" && tokens[0].text == "TO") {
                if (!defining.empty()) fail(tokens[0], "TO inside definition of " + defining);
                if (tokens.size() < 2 || tokens[1].kind != "word") fail(tokens[0], "bad procedure header");
                string p = tokens[1].text;
                if (builtins.count(p) || p == "TO" || p == "END" || p == "MOD") fail(tokens[0], p + " is a primitive");
                if (procedures.count(p)) fail(tokens[0], p + " is already defined");
                vector<string> parameters;
                for (size_t i = 2; i < tokens.size(); ++i) {
                    if (tokens[i].kind != "variable") fail(tokens[0], "bad procedure header");
                    string parameter = tokens[i].text.substr(1);
                    if (find(parameters.begin(), parameters.end(), parameter) != parameters.end()) fail(tokens[0], "duplicate input " + tokens[i].text);
                    parameters.push_back(parameter);
                }
                procedures[p] = {tokens[0], parameters, {}, {}};
                order.push_back(p);
                defining = p;
            } else if (tokens.size() == 1 && tokens[0].kind == "word" && tokens[0].text == "END") {
                if (defining.empty()) fail(tokens[0], "END without TO");
                defining.clear();
            } else {
                auto& destination = defining.empty() ? top_tokens : procedures.at(defining).tokens;
                destination.insert(destination.end(), tokens.begin(), tokens.end());
            }
        }
        if (!defining.empty()) fail(procedures.at(defining).definition, "missing END for " + defining);
        for (const auto& p : order) procedures.at(p).body = Parser(procedures.at(p).tokens, builtins, procedures, false).parse();
        auto top = Parser(top_tokens, builtins, procedures, true).parse();
        Machine machine(procedures);
        try {
            machine.execute(top);
            machine.finish();
        }
        catch (const LogoError& error) {
            cout << "ERROR line " << error.line << ": " << error.reason << '\n';
            for (size_t end = machine.active.size(); end > 0;) {
                size_t start = end - 1;
                while (start > 0 && machine.active[start - 1] == machine.active[end - 1]) --start;
                cout << "  in " << machine.active[end - 1];
                if (end - start > 1) cout << " x" << end - start;
                cout << '\n';
                end = start;
            }
        }
    } catch (const LogoError& error) {
        cout << "ERROR line " << error.line << ": " << error.reason << '\n';
    }
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    string line, name;
    vector<pair<int, string>> lines;
    int number = 0;
    while (getline(cin, line)) {
        ++number;
        if (line == "#EOF" || line.rfind("#PROGRAM ", 0) == 0) {
            if (!name.empty()) program(name, lines);
            if (line == "#EOF") break;
            name = line.substr(9);
            lines.clear();
        } else lines.push_back({number, line});
    }
}
