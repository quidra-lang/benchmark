#include <algorithm>
#include <cstdlib>
#include <iostream>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <string>
#include <utility>
#include <vector>

using namespace std;
using Integer = long long;

string upper(string text) {
    for (char& ch : text) if (ch >= 'a' && ch <= 'z') ch -= 'a' - 'A';
    return text;
}
struct ForthError {
    string word, reason;
    optional<Integer> code;
};
[[noreturn]] void error(const string& word, const string& reason, optional<Integer> code = nullopt) {
    throw ForthError{word, reason, code};
}
struct Word;
struct Definition;
using WordPtr = shared_ptr<Word>;
struct Action {
    string kind, spelling, text;
    Integer value = 0;
    size_t target = 0;
    WordPtr word;
    vector<size_t> locals;
};
struct Definition {
    vector<Action> body;
    size_t local_count = 0;
};
struct Word {
    string name, kind;
    Integer here = 8, address = 0, value = 0, xt = 0, deferred = 0;
    shared_ptr<Definition> definition, does_definition;
    size_t does_start = 0;
};
struct Control {
    string kind;
    size_t start, begin;
    vector<size_t> patches;
};

class Forth {
    vector<Integer> stack, returns, memory{10};
    map<string, WordPtr> builtins;
    vector<WordPtr> dictionary, tokens;
    WordPtr compiling;
    string definition_display;
    map<string, size_t> locals;
    vector<Control> controls;
    string line, pending;
    size_t position = 0;
    int depth = 0;
    const set<string> compile_only = {
        "IF", "ELSE", "THEN", "DO", "?DO", "LOOP", "+LOOP", "LEAVE", "UNLOOP", "I", "J",
        "BEGIN", "UNTIL", "WHILE", "REPEAT", "AGAIN", "CASE", "OF", "ENDOF", "ENDCASE", "EXIT",
        "RECURSE", "DOES>", ";", ">R", "R>", "R@", "ABORT\"", "[']", "{:"
    };
    const set<string> interpret_only = {":", ":NONAME", "FORGET"};
    const set<string> both = {".\"", "(", "\\", "TO", "IS"};
    Integer here() const {
        return Integer(memory.size()) * 8;
    }
    optional<string> read_word() {
        while (position < line.size() && line[position] == ' ') ++position;
        if (position == line.size()) return nullopt;
        size_t start = position;
        while (position < line.size() && line[position] != ' ') ++position;
        return line.substr(start, position - start);
    }
    string read_name(const string& owner) {
        auto name = read_word();
        if (!name) error(owner, "missing name", -16);
        return *name;
    }
    static optional<Integer> digits(string text, int base) {
        bool negative = !text.empty() && text[0] == '-';
        if (negative) text.erase(0, 1);
        if (text.empty()) return nullopt;
        text = upper(text);
        for (char ch : text) {
            int digit = ch >= '0' && ch <= '9' ? ch - '0' : ch >= 'A' && ch <= 'Z' ? ch - 'A' + 10 : 36;
            if (digit >= base) return nullopt;
        }
        Integer result = 0;
        for (char ch : text) {
            int digit = ch >= '0' && ch <= '9' ? ch - '0' : ch >= 'A' && ch <= 'Z' ? ch - 'A' + 10 : 36;
            result = result * base + digit;
        }
        return negative ? -result : result;
    }
    optional<Integer> number(const string& text, const string& owner, optional<int> fixed_base = nullopt) const {
        if (text.size() == 3 && text[0] == '\'' && text[2] == '\'') return Integer(static_cast<unsigned char>(text[1]));
        if (!text.empty() && (text[0] == '$' || text[0] == '#' || text[0] == '%'))
            return digits(text.substr(1), text[0] == '$' ? 16 : text[0] == '#' ? 10 : 2);
        Integer base = fixed_base ? *fixed_base : memory[0];
        if (base < 2 || base > 36) error(owner, "invalid base", -40);
        return digits(text, int(base));
    }
    void check_name(const string& name) const {
        string canonical = upper(name);
        if (compile_only.count(canonical) || interpret_only.count(canonical) || both.count(canonical) || number(name, name, 10))
            error(name, "invalid name", -19);
    }
    WordPtr find(const string& name) const {
        string canonical = upper(name);
        for (auto it = dictionary.rbegin(); it != dictionary.rend(); ++it) if ((*it)->name == canonical) return *it;
        auto found = builtins.find(canonical);
        return found == builtins.end() ? nullptr : found->second;
    }
    WordPtr existing(const string& name) const {
        auto word = find(name);
        if (!word) error(name, "undefined word", -13);
        return word;
    }
    void push(Integer value, const string& owner) {
        stack.push_back(value);
        if (stack.size() > 1000) error(owner, "stack overflow", -3);
    }
    vector<Integer> take(size_t count, const string& owner) {
        if (stack.size() < count) error(owner, "stack underflow", -4);
        vector<Integer> result(stack.end() - count, stack.end());
        stack.resize(stack.size() - count);
        return result;
    }
    Integer pop(const string& owner) {
        return take(1, owner)[0];
    }
    void return_need(size_t count, const string& owner) const {
        if (returns.size() < count) error(owner, "return stack underflow", -6);
    }
    void return_push(Integer value, const string& owner) {
        returns.push_back(value);
        if (returns.size() > 1000) error(owner, "return stack overflow", -5);
    }
    size_t cell(Integer address, const string& owner) const {
        if (address < 0 || address % 8 || address >= here()) error(owner, "invalid address", -9);
        return size_t(address / 8);
    }
    WordPtr xt_word(Integer xt, const string& owner) const {
        if (xt < 1 || xt > Integer(tokens.size())) error(owner, "invalid argument", -24);
        return tokens[size_t(xt - 1)];
    }
    Integer xt_of(const WordPtr& word) {
        if (!word->xt) {
            tokens.push_back(word);
            word->xt = tokens.size();
        }
        return word->xt;
    }
    string format(Integer value, const string& owner) const {
        Integer base = memory[0];
        if (base < 2 || base > 36) error(owner, "invalid base", -40);
        bool negative = value < 0;
        if (negative) value = -value;
        string result;
        do {
            result += "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"[value % base];
            value /= base;
        }
        while (value);
        if (negative) result += '-';
        reverse(result.begin(), result.end());
        return result;
    }
    void flush() {
        while (!pending.empty() && pending.back() == ' ') pending.pop_back();
        cout << pending << '\n';
        pending.clear();
    }
    string read_string(const string& owner) {
        size_t end = position < line.size() ? line.find('"', position + 1) : string::npos;
        if (end == string::npos) error(owner, "unterminated string");
        string result = line.substr(position + 1, end - position - 1);
        position = end + 1;
        return result;
    }
    static pair<Integer, Integer> divide(Integer a, Integer b, const string& owner) {
        if (!b) error(owner, "division by zero", -10);
        Integer quotient = a / b, remainder = a % b;
        if (remainder && ((remainder < 0) != (b < 0))) {
            --quotient;
            remainder += b;
        }
        return {quotient, remainder};
    }
    void add_defined(const string& kind, const string& owner) {
        string name = read_name(owner);
        check_name(name);
        Integer value = kind == "constant" || kind == "value" ? pop(owner) : 0;
        auto word = make_shared<Word>();
        word->name = upper(name);
        word->kind = kind;
        word->here = here();
        word->address = here();
        word->value = value;
        dictionary.push_back(word);
        if (kind == "variable" || kind == "value") memory.push_back(value);
    }
    void builtin(const string& operation, const string& owner) {
        if (operation == "CREATE" || operation == "VARIABLE" || operation == "CONSTANT" || operation == "VALUE" || operation == "DEFER") {
            add_defined(operation == "CREATE" ? "create" : operation == "VARIABLE" ? "variable" : operation == "CONSTANT" ? "constant" : operation == "VALUE" ? "value" : "defer", owner);
        } else if (operation == "'") {
            auto word = existing(read_name(owner));
            push(xt_of(word), owner);
        } else if (operation == "EXECUTE") {
            auto word = xt_word(pop(owner), owner);
            execute(word, word->name);
        } else if (operation == "CATCH") {
            auto word = xt_word(pop(owner), owner);
            auto saved = stack;
            size_t return_depth = returns.size();
            int saved_depth = depth;
            try {
                execute(word, word->name);
            }
            catch (const ForthError& caught) {
                if (!caught.code) throw;
                stack = move(saved);
                if (returns.size() > return_depth) returns.resize(return_depth);
                depth = saved_depth;
                push(*caught.code, owner);
                return;
            }
            push(0, owner);
        } else if (operation == "THROW") {
            Integer value = pop(owner);
            if (value) error(owner, "exception " + to_string(value), value);
        } else if (operation == "ABORT") error(owner, "aborted", -1);
        else if (operation == "WORDS") {
            for (auto it = dictionary.rbegin(); it != dictionary.rend(); ++it) pending += (*it)->name + " ";
        } else if (operation == "CR") flush();
        else if (operation == "SPACE") pending += ' ';
        else if (operation == "SPACES") {
            Integer count = pop(owner);
            if (count > 0) pending.append(size_t(count), ' ');
        }
        else if (operation == "EMIT") {
            Integer value = pop(owner);
            if (value < 32 || value > 126) error(owner, "invalid argument", -24);
            pending += char(value);
        } else if (operation == ".") pending += format(pop(owner), owner) + " ";
        else if (operation == ".R") {
            auto a = take(2, owner);
            string text = format(a[0], owner);
            if (a[1] > Integer(text.size())) pending.append(size_t(a[1] - text.size()), ' ');
            pending += text;
        } else if (operation == ".S") {
            string text = "<" + format(stack.size(), owner) + "> ";
            for (Integer value : stack) text += format(value, owner) + " ";
            pending += text;
        } else if (operation == "?") {
            size_t at = cell(pop(owner), owner);
            pending += format(memory[at], owner) + " ";
        }
        else if (operation == "!" || operation == "+!") {
            auto a = take(2, owner);
            size_t at = cell(a[1], owner);
            if (operation == "!") memory[at] = a[0];
            else memory[at] += a[0];
        } else if (operation == "@") {
            size_t at = cell(pop(owner), owner);
            push(memory[at], owner);
        }
        else if (operation == ",") memory.push_back(pop(owner));
        else if (operation == "ALLOT") {
            Integer count = pop(owner);
            if (count < 0 || count % 8) error(owner, "invalid argument", -24);
            memory.resize(memory.size() + size_t(count / 8));
        } else if (operation == "HEX" || operation == "DECIMAL") memory[0] = operation == "HEX" ? 16 : 10;
        else if (operation == "HERE") push(here(), owner);
        else if (operation == "BASE") push(0, owner);
        else if (operation == "BL") push(32, owner);
        else if (operation == "TRUE" || operation == "FALSE") push(operation == "TRUE" ? -1 : 0, owner);
        else if (operation == "DEPTH") push(stack.size(), owner);
        else if (operation == "PICK" || operation == "ROLL") {
            Integer index = pop(owner);
            if (index < 0) error(owner, "invalid argument", -24);
            if (index >= Integer(stack.size())) error(owner, "stack underflow", -4);
            size_t at = stack.size() - 1 - size_t(index);
            Integer value = stack[at];
            if (operation == "ROLL") stack.erase(stack.begin() + at);
            push(value, owner);
        } else if (operation == ">R") return_push(pop(owner), owner);
        else if (operation == "R>" || operation == "R@" || operation == "I" || operation == "J" || operation == "UNLOOP") {
            size_t count = operation == "J" ? 3 : operation == "UNLOOP" ? 2 : 1;
            return_need(count, owner);
            if (operation == "UNLOOP") returns.resize(returns.size() - 2);
            else {
                Integer value = returns[returns.size() - count];
                if (operation == "R>") returns.pop_back();
                push(value, owner);
            }
        } else {
            static const map<string, size_t> arities = {
                {"+",2},{"-",2},{"*",2},{"/",2},{"MOD",2},{"/MOD",2},{"*/",3},{"*/MOD",3},
                {"NEGATE",1},{"ABS",1},{"MIN",2},{"MAX",2},{"1+",1},{"1-",1},{"2*",1},{"2/",1},
                {"=",2},{"<>",2},{"<",2},{">",2},{"0=",1},{"0<>",1},{"0<",1},{"0>",1},{"WITHIN",3},
                {"AND",2},{"OR",2},{"XOR",2},{"INVERT",1},{"CELLS",1},{"CELL+",1},
                {"DUP",1},{"?DUP",1},{"DROP",1},{"SWAP",2},{"OVER",2},{"ROT",3},{"-ROT",3},
                {"NIP",2},{"TUCK",2},{"2DUP",2},{"2DROP",2},{"2SWAP",4},{"2OVER",4}
            };
            auto a = take(arities.at(operation), owner);
            vector<Integer> result;
            if (operation == "+") result = {a[0] + a[1]};
            else if (operation == "-") result = {a[0] - a[1]};
            else if (operation == "*") result = {a[0] * a[1]};
            else if (operation == "/" || operation == "MOD" || operation == "/MOD" || operation == "*/" || operation == "*/MOD") {
                bool product = operation == "*/" || operation == "*/MOD";
                auto [q, r] = divide(product ? a[0] * a[1] : a[0], product ? a[2] : a[1], owner);
                if (operation == "MOD") result = {r};
                else if (operation == "/MOD" || operation == "*/MOD") result = {r, q};
                else result = {q};
            } else if (operation == "NEGATE") result = {-a[0]};
            else if (operation == "ABS") result = {abs(a[0])};
            else if (operation == "MIN") result = {min(a[0], a[1])};
            else if (operation == "MAX") result = {max(a[0], a[1])};
            else if (operation == "1+") result = {a[0] + 1};
            else if (operation == "1-") result = {a[0] - 1};
            else if (operation == "2*") result = {2 * a[0]};
            else if (operation == "2/") result = {divide(a[0], 2, owner).first};
            else if (operation == "CELLS") result = {8 * a[0]};
            else if (operation == "CELL+") result = {a[0] + 8};
            else if (operation == "AND") result = {a[0] & a[1]};
            else if (operation == "OR") result = {a[0] | a[1]};
            else if (operation == "XOR") result = {a[0] ^ a[1]};
            else if (operation == "INVERT") result = {-a[0] - 1};
            else if (operation == "DUP") result = {a[0], a[0]};
            else if (operation == "?DUP") result = a[0] ? vector<Integer>{a[0], a[0]} : a;
            else if (operation == "DROP" || operation == "2DROP") result = {};
            else if (operation == "SWAP") result = {a[1], a[0]};
            else if (operation == "OVER") result = {a[0], a[1], a[0]};
            else if (operation == "ROT") result = {a[1], a[2], a[0]};
            else if (operation == "-ROT") result = {a[2], a[0], a[1]};
            else if (operation == "NIP") result = {a[1]};
            else if (operation == "TUCK") result = {a[1], a[0], a[1]};
            else if (operation == "2DUP") result = {a[0], a[1], a[0], a[1]};
            else if (operation == "2SWAP") result = {a[2], a[3], a[0], a[1]};
            else if (operation == "2OVER") result = {a[0], a[1], a[2], a[3], a[0], a[1]};
            else {
                bool flag = operation == "=" ? a[0] == a[1] : operation == "<>" ? a[0] != a[1] :
                            operation == "<" ? a[0] < a[1] : operation == ">" ? a[0] > a[1] :
                            operation == "0=" ? a[0] == 0 : operation == "0<>" ? a[0] != 0 :
                            operation == "0<" ? a[0] < 0 : operation == "0>" ? a[0] > 0 : a[1] <= a[0] && a[0] < a[2];
                result = {flag ? -1 : 0};
            }
            for (Integer value : result) push(value, owner);
        }
    }
    void execute(WordPtr word, string owner) {
        while (word->kind == "defer") {
            if (!word->deferred) error(owner, "deferred word not set", -21);
            word = xt_word(word->deferred, owner);
            owner = word->name;
        }
        if (word->kind == "builtin") builtin(word->name, owner);
        else if (word->kind == "colon") run_definition(word->definition, 0, owner);
        else if (word->kind == "create" || word->kind == "variable") {
            push(word->address, owner);
            if (word->does_definition) run_definition(word->does_definition, word->does_start, owner);
        } else if (word->kind == "constant") push(word->value, owner);
        else if (word->kind == "value") push(memory[size_t(word->address / 8)], owner);
    }
    void run_definition(const shared_ptr<Definition>& definition, size_t start, const string& owner) {
        if (depth == 100) error(owner, "nesting too deep", -7);
        ++depth;
        size_t return_depth = returns.size();
        vector<Integer> frame(definition->local_count);
        size_t ip = start;
        while (ip < definition->body.size()) {
            const Action& action = definition->body[ip++];
            const string& token = action.spelling;
            if (action.kind == "push") push(action.value, token);
            else if (action.kind == "call") execute(action.word, token);
            else if (action.kind == "primitive") builtin(action.text, token);
            else if (action.kind == "string") pending += action.text;
            else if (action.kind == "abort") {
                if (pop(token)) error(token, action.text, -2);
            }
            else if (action.kind == "getlocal") push(frame[action.target], token);
            else if (action.kind == "setlocal") frame[action.target] = pop(token);
            else if (action.kind == "locals") {
                auto values = take(action.locals.size(), token);
                for (size_t i = 0; i < values.size(); ++i) frame[action.locals[i]] = values[i];
            } else if (action.kind == "setvalue") memory[size_t(action.word->address / 8)] = pop(token);
            else if (action.kind == "setdefer") {
                Integer value = pop(token);
                xt_word(value, token);
                action.word->deferred = value;
            } else if (action.kind == "jump") ip = action.target;
            else if (action.kind == "if") {
                if (!pop(token)) ip = action.target;
            }
            else if (action.kind == "do" || action.kind == "?do") {
                auto values = take(2, token);
                if (action.kind == "?do" && values[0] == values[1]) ip = action.target;
                else {
                    return_push(values[0], token);
                    return_push(values[1], token);
                }
            } else if (action.kind == "loop" || action.kind == "+loop") {
                Integer step = action.kind == "loop" ? 1 : pop(token);
                return_need(2, token);
                Integer index = returns.back(), limit = returns[returns.size() - 2];
                bool before = index - limit < 0, after = index + step - limit < 0;
                if (before != after) returns.resize(returns.size() - 2);
                else {
                    returns.back() = index + step;
                    ip = action.target;
                }
            } else if (action.kind == "leave") {
                return_need(2, token);
                returns.resize(returns.size() - 2);
                ip = action.target;
            }
            else if (action.kind == "of") {
                auto values = take(2, token);
                if (values[0] != values[1]) {
                    push(values[0], token);
                    ip = action.target;
                }
            } else if (action.kind == "drop") pop(token);
            else if (action.kind == "exit") break;
            else if (action.kind == "does") {
                if (dictionary.empty() || dictionary.back()->kind != "create") error(token, "no CREATE word", -31);
                dictionary.back()->does_definition = definition;
                dictionary.back()->does_start = ip;
                break;
            }
        }
        if (returns.size() > return_depth) returns.resize(return_depth);
        --depth;
    }
    size_t emit(Action action) {
        compiling->definition->body.push_back(move(action));
        return compiling->definition->body.size() - 1;
    }
    void control_top(const set<string>& kinds, const string& owner) const {
        if (controls.empty() || !kinds.count(controls.back().kind)) error(owner, "control structure mismatch");
    }
    void compile(const string& token, const string& operation) {
        auto& body = compiling->definition->body;
        Action action;
        action.spelling = token;
        if (operation == ";") {
            if (!controls.empty()) {
                string kind = controls.back().kind;
                if (kind == "ELSE") kind = "IF";
                if (kind == "WHILE") kind = "BEGIN";
                error(token, "unclosed " + kind);
            }
            WordPtr finished = compiling;
            compiling.reset();
            if (finished->name == ":NONAME") push(xt_of(finished), token);
            else dictionary.push_back(finished);
            return;
        }
        if (operation == "IF") {
            action.kind = "if";
            size_t at = emit(action);
            controls.push_back({"IF", at, at, {}});
        } else if (operation == "ELSE") {
            control_top({"IF"}, token);
            action.kind = "jump";
            size_t at = emit(action);
            body[controls.back().start].target = at + 1;
            controls.back() = {"ELSE", at, at, {}};
        } else if (operation == "THEN") {
            control_top({"IF", "ELSE"}, token);
            action.kind = "nop";
            size_t at = emit(action);
            body[controls.back().start].target = at + 1;
            controls.pop_back();
        } else if (operation == "BEGIN") {
            action.kind = "nop";
            size_t at = emit(action);
            controls.push_back({"BEGIN", at, at, {}});
        } else if (operation == "UNTIL" || operation == "AGAIN") {
            control_top({"BEGIN"}, token);
            action.kind = operation == "UNTIL" ? "if" : "jump";
            action.target = controls.back().begin + 1;
            emit(action);
            controls.pop_back();
        } else if (operation == "WHILE") {
            control_top({"BEGIN"}, token);
            action.kind = "if";
            size_t at = emit(action);
            controls.back().kind = "WHILE";
            controls.back().start = at;
        } else if (operation == "REPEAT") {
            control_top({"WHILE"}, token);
            action.kind = "jump";
            action.target = controls.back().begin + 1;
            size_t at = emit(action);
            body[controls.back().start].target = at + 1;
            controls.pop_back();
        } else if (operation == "DO" || operation == "?DO") {
            action.kind = operation == "DO" ? "do" : "?do";
            size_t at = emit(action);
            controls.push_back({operation, at, at, {}});
        } else if (operation == "LOOP" || operation == "+LOOP") {
            control_top({"DO", "?DO"}, token);
            action.kind = operation == "LOOP" ? "loop" : "+loop";
            action.target = controls.back().start + 1;
            size_t at = emit(action);
            body[controls.back().start].target = at + 1;
            for (size_t patch : controls.back().patches) body[patch].target = at + 1;
            controls.pop_back();
        } else if (operation == "LEAVE") {
            size_t found = controls.size();
            while (found > 0) {
                --found;
                if (controls[found].kind == "DO" || controls[found].kind == "?DO") break;
            }
            if (controls.empty() || (controls[found].kind != "DO" && controls[found].kind != "?DO")) error(token, "control structure mismatch");
            action.kind = "leave";
            size_t at = emit(action);
            controls[found].patches.push_back(at);
        } else if (operation == "CASE") {
            action.kind = "nop";
            size_t at = emit(action);
            controls.push_back({"CASE", at, at, {}});
        } else if (operation == "OF") {
            control_top({"CASE"}, token);
            action.kind = "of";
            size_t at = emit(action);
            controls.push_back({"OF", at, at, {}});
        } else if (operation == "ENDOF") {
            control_top({"OF"}, token);
            action.kind = "jump";
            size_t at = emit(action);
            body[controls.back().start].target = at + 1;
            controls.pop_back();
            controls.back().patches.push_back(at);
        } else if (operation == "ENDCASE") {
            control_top({"CASE"}, token);
            action.kind = "drop";
            size_t at = emit(action);
            for (size_t patch : controls.back().patches) body[patch].target = at + 1;
            controls.pop_back();
        } else if (operation == "DOES>") {
            if (!controls.empty()) error(token, "control structure mismatch");
            action.kind = "does";
            emit(action);
        } else if (operation == "EXIT") {
            action.kind = "exit";
            emit(action);
        }
        else if (operation == "RECURSE") {
            action.kind = "call";
            action.word = compiling;
            emit(action);
        }
        else if (operation == "[']") {
            action.kind = "push";
            action.value = xt_of(existing(read_name(token)));
            emit(action);
        } else if (operation == "{:") {
            vector<string> names;
            bool closed = false, ignored = false;
            while (auto name = read_word()) {
                if (*name == ":}") {
                    closed = true;
                    break;
                }
                if (*name == "--") ignored = true;
                if (!ignored) names.push_back(*name);
            }
            if (!closed) error(token, "unterminated locals");
            for (const auto& name : names) check_name(name);
            action.kind = "locals";
            for (const auto& name : names) {
                size_t at = compiling->definition->local_count++;
                locals[upper(name)] = at;
                action.locals.push_back(at);
            }
            emit(action);
        } else if (operation == ">R" || operation == "R>" || operation == "R@" || operation == "I" || operation == "J" || operation == "UNLOOP") {
            action.kind = "primitive";
            action.text = operation;
            emit(action);
        } else if (locals.count(operation)) {
            action.kind = "getlocal";
            action.target = locals.at(operation);
            emit(action);
        } else if (auto word = find(operation)) {
            action.kind = "call";
            action.word = word;
            emit(action);
        }
        else {
            auto value = number(token, token);
            if (!value) error(token, "undefined word", -13);
            action.kind = "push";
            action.value = *value;
            emit(action);
        }
    }
    void process(const string& token) {
        string operation = upper(token);
        if (operation == "\\") {
            position = line.size();
            return;
        }
        if (operation == "(") {
            size_t end = line.find(')', position);
            if (end == string::npos) error(token, "unterminated comment");
            position = end + 1;
            return;
        }
        if (!compiling && compile_only.count(operation)) error(token, "compile only");
        if (compiling && interpret_only.count(operation)) error(token, "interpret only");
        if (operation == ".\"" || operation == "ABORT\"") {
            string text = read_string(token);
            if (compiling) {
                Action action;
                action.kind = operation == ".\"" ? "string" : "abort";
                action.spelling = token;
                action.text = text;
                emit(action);
            } else pending += text;
        } else if (operation == "TO" || operation == "IS") {
            string name = read_name(token), canonical = upper(name);
            Action action;
            action.spelling = token;
            if (operation == "TO" && compiling && locals.count(canonical)) {
                action.kind = "setlocal";
                action.target = locals.at(canonical);
                emit(action);
                return;
            }
            auto word = existing(name);
            if (operation == "TO" && word->kind != "value") error(name, "not a value");
            if (operation == "IS" && word->kind != "defer") error(name, "not deferred");
            if (compiling) {
                action.kind = operation == "TO" ? "setvalue" : "setdefer";
                action.word = word;
                emit(action);
            }
            else {
                Integer value = pop(token);
                if (operation == "TO") memory[size_t(word->address / 8)] = value;
                else {
                    xt_word(value, token);
                    word->deferred = value;
                }
            }
        } else if (operation == ":" || operation == ":NONAME") {
            string name = operation == ":" ? read_name(token) : ":NONAME";
            if (operation == ":") check_name(name);
            compiling = make_shared<Word>();
            compiling->name = upper(name);
            compiling->kind = "colon";
            compiling->here = here();
            compiling->definition = make_shared<Definition>();
            definition_display = operation == ":" ? name : token;
            locals.clear();
            controls.clear();
        } else if (operation == "FORGET") {
            string name = read_name(token), canonical = upper(name);
            size_t found = dictionary.size();
            for (size_t i = dictionary.size(); i > 0; --i) if (dictionary[i - 1]->name == canonical) {
                found = i - 1;
                break;
            }
            if (found == dictionary.size()) error(name, "undefined word", -13);
            memory.resize(size_t(dictionary[found]->here / 8));
            dictionary.resize(found);
        } else if (compiling) compile(token, operation);
        else if (auto word = find(operation)) execute(word, token);
        else {
            auto value = number(token, token);
            if (!value) error(token, "undefined word", -13);
            push(*value, token);
        }
    }
public:
    Forth() {
        const string names = "+ - * / MOD /MOD */ */MOD NEGATE ABS MIN MAX 1+ 1- 2* 2/ = <> < > 0= 0<> 0< 0> WITHIN TRUE FALSE AND OR XOR INVERT DUP ?DUP DROP SWAP OVER ROT -ROT NIP TUCK 2DUP 2DROP 2SWAP 2OVER DEPTH PICK ROLL . .R .S ? CR EMIT SPACE SPACES BL ! @ +! , ALLOT HERE CELLS CELL+ BASE HEX DECIMAL CREATE VARIABLE CONSTANT VALUE DEFER ' EXECUTE CATCH THROW ABORT WORDS";
        size_t start = 0;
        while (start < names.size()) {
            size_t end = names.find(' ', start);
            string name = names.substr(start, end == string::npos ? end : end - start);
            auto word = make_shared<Word>();
            word->name = name;
            word->kind = "builtin";
            builtins[name] = word;
            if (end == string::npos) break;
            start = end + 1;
        }
    }
    void process_line(const string& input) {
        line = input;
        position = 0;
        try {
            while (auto token = read_word()) process(*token);
        }
        catch (const ForthError& issue) {
            if (!pending.empty()) flush();
            cout << "ERROR " << issue.word << ": " << issue.reason << '\n';
            stack.clear();
            returns.clear();
            depth = 0;
            compiling.reset();
            locals.clear();
            controls.clear();
        }
        if (!pending.empty()) flush();
    }
    void finish() const {
        if (compiling) cout << "ERROR " << definition_display << ": unterminated definition\n";
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    Forth forth;
    string line;
    while (getline(cin, line) && line != "BYE") forth.process_line(line);
    forth.finish();
}
