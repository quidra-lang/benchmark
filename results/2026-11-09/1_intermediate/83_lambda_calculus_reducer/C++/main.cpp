#include <algorithm>
#include <iostream>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using namespace std;

struct Term;
using T = shared_ptr<const Term>;
struct Term {
    string kind, name;
    int number = 0;
    T left, right;
};
T leaf(const string& kind, const string& name = "", int number = 0) {
    return make_shared<Term>(Term{kind, name, number, nullptr, nullptr});
}
T abstraction(const string& name, T body) {
    return make_shared<Term>(Term{"abs", name, 0, body, nullptr});
}
T application(T function, T argument) {
    return make_shared<Term>(Term{"app", "", 0, function, argument});
}
set<string> free_variables(T term) {
    if (term->kind == "var") return {term->name};
    if (term->kind == "abs") {
        auto result = free_variables(term->left);
        result.erase(term->name);
        return result;
    }
    if (term->kind == "app") {
        auto result = free_variables(term->left), argument = free_variables(term->right);
        result.insert(argument.begin(), argument.end());
        return result;
    }
    return {};
}
string printed(T term, bool end = true, bool debruijn = false) {
    if (term->kind == "var" || term->kind == "macro" || term->kind == "constant") return term->name;
    if (term->kind == "numeral") return "#" + to_string(term->number);
    if (term->kind == "index") return to_string(term->number);
    if (term->kind == "abs") {
        string prefix = "\\";
        if (debruijn) {
            T body = term;
            prefix.clear();
            while (body->kind == "abs") {
                prefix += '\\';
                body = body->left;
            }
            prefix += printed(body, true, true);
        } else {
            T body = term;
            bool first = true;
            while (body->kind == "abs") {
                if (!first) prefix += ' ';
                prefix += body->name;
                body = body->left;
                first = false;
            }
            prefix += ". " + printed(body, true, false);
        }
        return end ? prefix : "(" + prefix + ")";
    }
    string left = term->left->kind == "abs" ? "(" + printed(term->left, true, debruijn) + ")" : printed(term->left, false, debruijn);
    string right = term->right->kind == "app" ? "(" + printed(term->right, true, debruijn) + ")" : printed(term->right, end, debruijn);
    return left + " " + right;
}
string sequence_name(size_t index) {
    return string(1, char('a' + index % 26)) + (index >= 26 ? to_string(index / 26) : "");
}
T canonical_term(T term) {
    auto free = free_variables(term);
    size_t next = 0;
    vector<pair<string, string>> bindings;
    auto rename = [&](auto&& self, T value) -> T {
        if (value->kind == "var") {
            for (auto it = bindings.rbegin(); it != bindings.rend(); ++it) if (it->first == value->name) return leaf("var", it->second);
            return value;
        }
        if (value->kind == "abs") {
            string name;
            do {
                name = sequence_name(next++);
            }
            while (free.count(name));
            bindings.push_back({value->name, name});
            T body = self(self, value->left);
            bindings.pop_back();
            return abstraction(name, body);
        }
        if (value->kind == "app") {
            T left = self(self, value->left);
            T right = self(self, value->right);
            return application(left, right);
        }
        return value;
    };
    return rename(rename, term);
}
string canonical(T term) {
    return printed(canonical_term(term));
}
T debruijn_term(T term, vector<string>& bindings) {
    if (term->kind == "var") {
        for (size_t i = bindings.size(); i > 0; --i) if (bindings[i - 1] == term->name) return leaf("index", "", bindings.size() - i);
        return term;
    }
    if (term->kind == "abs") {
        bindings.push_back(term->name);
        T body = debruijn_term(term->left, bindings);
        bindings.pop_back();
        return abstraction("", body);
    }
    T left = debruijn_term(term->left, bindings), right = debruijn_term(term->right, bindings);
    return application(left, right);
}
T debruijn_term(T term) {
    vector<string> bindings;
    return debruijn_term(term, bindings);
}
bool alpha_equal(T a, T b) {
    return printed(debruijn_term(a), true, true) == printed(debruijn_term(b), true, true);
}
T substitute(T term, const string& variable, T replacement) {
    if (term->kind == "var") return term->name == variable ? replacement : term;
    if (term->kind == "app") {
        T left = substitute(term->left, variable, replacement), right = substitute(term->right, variable, replacement);
        return application(left, right);
    }
    auto body_free = free_variables(term->left);
    if (term->name == variable || !body_free.count(variable)) return term;
    auto replacement_free = free_variables(replacement);
    if (!replacement_free.count(term->name)) return abstraction(term->name, substitute(term->left, variable, replacement));
    string base = term->name;
    while (!base.empty() && base.back() >= '0' && base.back() <= '9') base.pop_back();
    string fresh;
    for (size_t i = 1;; ++i) {
        fresh = base + to_string(i);
        if (!replacement_free.count(fresh) && !body_free.count(fresh)) break;
    }
    T renamed = substitute(term->left, term->name, leaf("var", fresh));
    return abstraction(fresh, substitute(renamed, variable, replacement));
}
struct Token {
    string kind, text;
    int column;
};
[[noreturn]] void failure(const string& message) {
    throw runtime_error(message);
}
vector<Token> lexical(const string& line, size_t start) {
    vector<Token> tokens;
    for (size_t i = start; i < line.size();) {
        char ch = line[i];
        if (ch == ' ') {
            ++i;
            continue;
        }
        size_t first = i++;
        string kind = "symbol";
        if (ch >= 'a' && ch <= 'z') {
            kind = "var";
            while (i < line.size() && ((line[i] >= 'a' && line[i] <= 'z') || (line[i] >= '0' && line[i] <= '9'))) ++i;
        } else if (ch >= 'A' && ch <= 'Z') {
            kind = "macro";
            while (i < line.size() && ((line[i] >= 'A' && line[i] <= 'Z') || (line[i] >= '0' && line[i] <= '9') || line[i] == '_')) ++i;
        } else if (ch == '#' && i < line.size() && line[i] >= '0' && line[i] <= '9') {
            kind = "numeral";
            while (i < line.size() && line[i] >= '0' && line[i] <= '9') ++i;
        } else if (string("\\.()=;").find(ch) == string::npos)
            failure("column " + to_string(first + 1) + ": unexpected character '" + string(1, ch) + "'");
        tokens.push_back({kind, line.substr(first, i - first), int(first + 1)});
    }
    tokens.push_back({"end", "", int(line.size() + 1)});
    return tokens;
}
class Parser {
    vector<Token> tokens;
    size_t position = 0;
public:
    explicit Parser(vector<Token> tokens) : tokens(move(tokens)) {
    }
    const Token& next() const {
        return tokens[position];
    }
    Token consume() {
        return tokens[position++];
    }
    string expect(const string& kind, const string& notation) {
        const auto& token = next();
        if ((kind == "var" || kind == "macro") ? token.kind != kind : token.text != kind)
            failure("column " + to_string(token.column) + ": expected " + notation);
        return consume().text;
    }
    T term() {
        vector<T> elements;
        while (next().kind == "var" || next().kind == "macro" || next().kind == "numeral" || next().text == "(") {
            Token token = consume();
            if (token.text == "(") {
                elements.push_back(term());
                expect(")", "')'");
            }
            else elements.push_back(leaf(token.kind, token.kind == "numeral" ? "" : token.text,
                                         token.kind == "numeral" ? stoi(token.text.substr(1)) : 0));
        }
        if (next().text == "\\") {
            consume();
            vector<string> bindings{expect("var", "variable")};
            while (next().kind == "var") bindings.push_back(consume().text);
            expect(".", "'.'");
            T body = term();
            for (auto it = bindings.rbegin(); it != bindings.rend(); ++it) body = abstraction(*it, body);
            elements.push_back(body);
        }
        if (elements.empty()) failure("column " + to_string(next().column) + ": expected term");
        T result = elements[0];
        for (size_t i = 1; i < elements.size(); ++i) result = application(result, elements[i]);
        return result;
    }
    void finish() const {
        if (next().kind != "end") failure("column " + to_string(next().column) + ": unexpected '" + next().text + "'");
    }
};
struct Step {
    T term;
    string kind;
};
optional<Step> one_step(T term, const string& strategy, bool eta) {
    bool normal = strategy == "NORMAL", applicative = strategy == "APPLICATIVE";
    if (term->kind == "var") return nullopt;
    if (term->kind == "abs") {
        if (!normal && !applicative) return nullopt;
        bool eta_redex = eta && term->left->kind == "app" && term->left->right->kind == "var" &&
                         term->left->right->name == term->name && !free_variables(term->left->left).count(term->name);
        if (normal && eta_redex) return Step{term->left->left, "eta"};
        if (auto step = one_step(term->left, strategy, eta)) return Step{abstraction(term->name, step->term), step->kind};
        if (applicative && eta_redex) return Step{term->left->left, "eta"};
        return nullopt;
    }
    T function = term->left, argument = term->right;
    if ((normal || strategy == "CBN") && function->kind == "abs")
        return Step{substitute(function->left, function->name, argument), "beta"};
    if (auto step = one_step(function, strategy, eta)) return Step{application(step->term, argument), step->kind};
    if (strategy != "CBN") if (auto step = one_step(argument, strategy, eta)) return Step{application(function, step->term), step->kind};
    if ((applicative || strategy == "CBV") && function->kind == "abs" &&
        (applicative || argument->kind == "var" || argument->kind == "abs"))
        return Step{substitute(function->left, function->name, argument), "beta"};
    return nullopt;
}
T abstract_ski(const string& variable, T term) {
    if (!free_variables(term).count(variable)) return application(leaf("constant", "K"), term);
    if (term->kind == "var") return leaf("constant", "I");
    if (term->right->kind == "var" && term->right->name == variable && !free_variables(term->left).count(variable)) return term->left;
    T left = abstract_ski(variable, term->left), right = abstract_ski(variable, term->right);
    return application(application(leaf("constant", "S"), left), right);
}
T to_ski(T term) {
    if (term->kind == "var") return term;
    if (term->kind == "abs") return abstract_ski(term->name, to_ski(term->left));
    T left = to_ski(term->left), right = to_ski(term->right);
    return application(left, right);
}
optional<Step> ski_step(T term) {
    vector<T> arguments;
    T head = term;
    while (head->kind == "app") {
        arguments.push_back(head->right);
        head = head->left;
    }
    reverse(arguments.begin(), arguments.end());
    T result;
    size_t used = 0;
    if (head->kind == "constant") {
        if (head->name == "I" && arguments.size() >= 1) {
            result = arguments[0];
            used = 1;
        }
        else if (head->name == "K" && arguments.size() >= 2) {
            result = arguments[0];
            used = 2;
        }
        else if (head->name == "S" && arguments.size() >= 3) {
            result = application(application(arguments[0], arguments[2]), application(arguments[1], arguments[2]));
            used = 3;
        }
    }
    if (result) {
        for (size_t i = used; i < arguments.size(); ++i) result = application(result, arguments[i]);
        return Step{result, head->name};
    }
    for (size_t i = 0; i < arguments.size(); ++i) if (auto step = ski_step(arguments[i])) {
        result = head;
        for (size_t j = 0; j < arguments.size(); ++j) result = application(result, j == i ? step->term : arguments[j]);
        return Step{result, step->kind};
    }
    return nullopt;
}
struct Type;
using TypePtr = shared_ptr<Type>;
struct Type {
    int id;
    TypePtr left, right, binding;
};
struct NotTypable {
};
class Inference {
    int counter = 0;
    map<string, TypePtr> free;
    vector<pair<string, TypePtr>> bindings;
    TypePtr variable() {
        return make_shared<Type>(Type{counter++, nullptr, nullptr, nullptr});
    }
    static TypePtr arrow(TypePtr a, TypePtr b) {
        return make_shared<Type>(Type{-1, a, b, nullptr});
    }
    static TypePtr prune(TypePtr type) {
        if (type->binding) type->binding = prune(type->binding);
        return type->binding ? type->binding : type;
    }
    static bool occurs(int id, TypePtr type) {
        type = prune(type);
        if (type->id >= 0) return type->id == id;
        return occurs(id, type->left) || occurs(id, type->right);
    }
    static void unify(TypePtr a, TypePtr b) {
        a = prune(a);
        b = prune(b);
        if (a == b) return;
        if (a->id >= 0) {
            if (occurs(a->id, b)) throw NotTypable{};
            a->binding = b;
        } else if (b->id >= 0) unify(b, a);
        else {
            unify(a->left, b->left);
            unify(a->right, b->right);
        }
    }
    TypePtr infer(T term) {
        if (term->kind == "var") {
            for (auto it = bindings.rbegin(); it != bindings.rend(); ++it) if (it->first == term->name) return it->second;
            if (!free.count(term->name)) free[term->name] = variable();
            return free.at(term->name);
        }
        if (term->kind == "abs") {
            TypePtr input = variable();
            bindings.push_back({term->name, input});
            TypePtr output = infer(term->left);
            bindings.pop_back();
            return arrow(input, output);
        }
        TypePtr function = infer(term->left), argument = infer(term->right), result = variable();
        unify(function, arrow(argument, result));
        return result;
    }
    static string show(TypePtr type, map<int, string>& names) {
        type = prune(type);
        if (type->id >= 0) {
            if (!names.count(type->id)) names[type->id] = sequence_name(names.size());
            return names.at(type->id);
        }
        string left = show(type->left, names);
        if (prune(type->left)->id < 0) left = "(" + left + ")";
        string right = show(type->right, names);
        return left + " -> " + right;
    }
public:
    string principal(T term) {
        try {
            TypePtr result = infer(term);
            map<int, string> names;
            return show(result, names);
        }
        catch (const NotTypable&) {
            return "not typable";
        }
    }
};
struct Closure;
using Environment = shared_ptr<const vector<Closure>>;
struct Closure {
    T code;
    Environment environment;
};
T reify(T code, Environment environment, int depth = 0) {
    while (code->kind == "index" && code->number >= depth) {
        Closure closure = (*environment)[code->number - depth];
        code = closure.code;
        environment = closure.environment;
        depth = 0;
    }
    if (code->kind == "index") return code;
    if (code->kind == "var") return code;
    if (code->kind == "abs") return abstraction("", reify(code->left, environment, depth + 1));
    T left = reify(code->left, environment, depth), right = reify(code->right, environment, depth);
    return application(left, right);
}
T named_from_debruijn(T term) {
    auto free = free_variables(term);
    size_t next = 0;
    vector<string> bindings;
    auto convert = [&](auto&& self, T code) -> T {
        if (code->kind == "var") return code;
        if (code->kind == "index") return leaf("var", bindings[bindings.size() - 1 - code->number]);
        if (code->kind == "abs") {
            string name;
            do {
                name = sequence_name(next++);
            }
            while (free.count(name));
            bindings.push_back(name);
            T body = self(self, code->left);
            bindings.pop_back();
            return abstraction(name, body);
        }
        T left = self(self, code->left), right = self(self, code->right);
        return application(left, right);
    };
    return convert(convert, term);
}

class Workbench {
    map<string, T> macros;
    bool display = false, eta = false;
    int limit = 10000;
    const set<string> reserved = {"S", "K", "I", "NORMAL", "APPLICATIVE", "CBN", "CBV"};
    static vector<string> references(T term) {
        if (term->kind == "macro") return {term->name};
        if (term->kind == "abs") return references(term->left);
        if (term->kind == "app") {
            auto result = references(term->left), right = references(term->right);
            result.insert(result.end(), right.begin(), right.end());
            return result;
        }
        return {};
    }
    bool depends(const string& macro, const string& target, set<string>& visited) const {
        if (!macros.count(macro) || reserved.count(macro) || !visited.insert(macro).second) return false;
        for (const auto& name : references(macros.at(macro))) if (name == target || depends(name, target, visited)) return true;
        return false;
    }
    T expand(T term) const {
        if (term->kind == "macro") {
            auto found = macros.find(term->name);
            if (found == macros.end()) failure("unbound macro " + term->name);
            return expand(found->second);
        }
        if (term->kind == "numeral") {
            T body = leaf("var", "x");
            for (int i = 0; i < term->number; ++i) body = application(leaf("var", "f"), body);
            return abstraction("f", abstraction("x", body));
        }
        if (term->kind == "var") return term;
        if (term->kind == "abs") return abstraction(term->name, expand(term->left));
        T left = expand(term->left), right = expand(term->right);
        return application(left, right);
    }
    struct Reduction {
        T term;
        int count;
        bool success;
    };
    Reduction reduce(T term, const string& strategy, bool use_eta, bool show, bool ski = false) const {
        for (int count = 0;; ++count) {
            auto next = ski ? ski_step(term) : one_step(term, strategy, use_eta);
            if (!next) return {term, count, true};
            if (count == limit) return {term, count, false};
            term = next->term;
            if (show) cout << "step " << count + 1 << " (" << next->kind << "): " << printed(term) << '\n';
        }
    }
    string church_value(T term) const {
        if (term->kind == "abs" && term->left->kind == "abs") {
            T body = term->left->left;
            int number = 0;
            while (body->kind == "app" && body->left->kind == "var" && body->left->name == term->name) {
                ++number;
                body = body->right;
            }
            if (body->kind == "var" && body->name == term->left->name) return to_string(number);
            if (term->left->left->kind == "var" && term->left->left->name == term->name) return "true";
        }
        if (term->kind == "abs" && term->left->kind == "app" && term->left->left->kind == "app") {
            T head = term->left->left->left, first = term->left->left->right, second = term->left->right;
            if (head->kind == "var" && head->name == term->name && !free_variables(first).count(term->name) && !free_variables(second).count(term->name)) {
                string left = church_value(first), right = church_value(second);
                return "(" + left + ", " + right + ")";
            }
        }
        return canonical(term);
    }
    void kam(T term) const {
        T code = debruijn_term(term);
        Environment environment = make_shared<vector<Closure>>();
        vector<Closure> stack;
        int count = 0;
        while (code->kind == "app" || code->kind == "index" || (code->kind == "abs" && !stack.empty())) {
            if (count == limit) {
                cout << "no result within " << limit << " transitions\n";
                return;
            }
            string kind;
            if (code->kind == "app") {
                kind = "push";
                stack.push_back({code->right, environment});
                code = code->left;
            }
            else if (code->kind == "abs") {
                kind = "grab";
                auto extended = make_shared<vector<Closure>>(*environment);
                extended->insert(extended->begin(), stack.back());
                stack.pop_back();
                environment = extended;
                code = code->left;
            } else {
                kind = "access";
                Closure closure = (*environment)[code->number];
                code = closure.code;
                environment = closure.environment;
            }
            ++count;
            if (display) cout << "step " << count << " (" << kind << "): " << printed(code, true, true)
                              << " [env " << environment->size() << ", stack " << stack.size() << "]\n";
        }
        T result = reify(code, environment);
        for (auto it = stack.rbegin(); it != stack.rend(); ++it) result = application(result, reify(it->code, it->environment));
        cout << "result: " << canonical(named_from_debruijn(result)) << " (transitions: " << count << ")\n";
    }
public:
    Workbench() {
        for (const auto& [name, body] : vector<pair<string, string>>{{"S", "\\x y z. x z (y z)"}, {"K", "\\x y. x"}, {"I", "\\x. x"}})
            macros[name] = Parser(lexical(body, 0)).term();
    }
    void command(const string& line) {
        size_t space = line.find(' ');
        string command = line.substr(0, space);
        const set<string> commands = {"let", "unlet", "macros", "steps", "eta", "limit", "expand", "subst", "reduce", "equal", "alpha", "debruijn", "fv", "size", "depth", "type", "church", "ski", "skireduce", "kam"};
        if (!commands.count(command)) failure("unknown command " + command);
        string argument = space == string::npos ? "" : line.substr(space + 1);
        if (command == "unlet" || command == "macros" || command == "steps" || command == "eta" || command == "limit") {
            istringstream input(argument);
            vector<string> args;
            string word;
            while (input >> word) args.push_back(word);
            if (command == "macros") {
                if (!args.empty()) failure("bad argument");
                bool any = false;
                for (const auto& [name, body] : macros) if (!reserved.count(name)) {
                    cout << name << " = " << printed(body) << '\n';
                    any = true;
                }
                if (!any) cout << "(none)\n";
            } else if (command == "steps" || command == "eta") {
                if (args.size() != 1 || (args[0] != "on" && args[0] != "off")) failure("bad argument");
                (command == "steps" ? display : eta) = args[0] == "on";
            } else if (command == "limit") {
                if (args.size() != 1 || args[0].empty() || args[0].size() > 5 || !all_of(args[0].begin(), args[0].end(), [](char c) {
                    return c >= '0' && c <= '9';
                })) failure("bad argument");
                int value = stoi(args[0]);
                if (value < 1 || value > 10000) failure("bad argument");
                limit = value;
            } else {
                if (args.size() != 1 || args[0].empty() || args[0][0] < 'A' || args[0][0] > 'Z' ||
                    !all_of(args[0].begin(), args[0].end(), [](char c) {
                        return (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
                    })) failure("bad argument");
                string name = args[0];
                if (reserved.count(name)) failure("reserved name " + name);
                if (!macros.count(name)) failure("unbound macro " + name);
                for (const auto& [user, body] : macros) if (!reserved.count(user)) {
                    auto refs = references(body);
                    if (find(refs.begin(), refs.end(), name) != refs.end()) failure(name + " is used by " + user);
                }
                macros.erase(name);
                cout << "removed " << name << '\n';
            }
            return;
        }
        Parser parser(lexical(line, space == string::npos ? line.size() : space + 1));
        string name, strategy = "NORMAL";
        vector<T> terms;
        if (command == "let") {
            name = parser.expect("macro", "macro name");
            parser.expect("=", "'='");
            terms.push_back(parser.term());
        }
        else if (command == "subst") {
            name = parser.expect("var", "variable");
            parser.expect("=", "'='");
            terms.push_back(parser.term());
            parser.expect(";", "';'");
            terms.push_back(parser.term());
        } else if (command == "equal" || command == "alpha") {
            terms.push_back(parser.term());
            parser.expect(";", "';'");
            terms.push_back(parser.term());
        } else {
            if (command == "reduce" && parser.next().kind == "macro" &&
                (parser.next().text == "NORMAL" || parser.next().text == "APPLICATIVE" || parser.next().text == "CBN" || parser.next().text == "CBV")) strategy = parser.consume().text;
            terms.push_back(parser.term());
        }
        parser.finish();
        if (command == "let") {
            if (reserved.count(name)) failure("reserved name " + name);
            for (const auto& reference : references(terms[0])) {
                set<string> visited;
                if (reference == name || depends(reference, name, visited)) failure("recursive definition of " + name);
                if (!macros.count(reference)) failure("unbound macro " + reference);
            }
            auto free = free_variables(terms[0]);
            if (!free.empty()) failure("free variable " + *free.begin() + " in definition of " + name);
            bool existed = macros.count(name);
            macros[name] = terms[0];
            cout << (existed ? "redefined " : "defined ") << name << '\n';
            return;
        }
        for (T& term : terms) term = expand(term);
        T term = terms[0];
        if (command == "expand") cout << printed(term) << '\n';
        else if (command == "subst") cout << printed(substitute(terms[1], name, term)) << '\n';
        else if (command == "alpha") cout << (alpha_equal(term, terms[1]) ? "yes" : "no") << '\n';
        else if (command == "equal") {
            auto first = reduce(term, "NORMAL", eta, false), second = reduce(terms[1], "NORMAL", eta, false);
            cout << (!first.success || !second.success ? "unknown" : alpha_equal(first.term, second.term) ? "yes" : "no") << '\n';
        } else if (command == "debruijn") cout << printed(debruijn_term(term), true, true) << '\n';
        else if (command == "fv") {
            auto free = free_variables(term);
            bool first = true;
            for (const auto& variable : free) {
                cout << (first ? "" : " ") << variable;
                first = false;
            }
            if (free.empty()) cout << "(none)";
            cout << '\n';
        } else if (command == "size" || command == "depth") {
            auto measure = [&](auto&& self, T value) -> int {
                if (value->kind == "var") return 1;
                int left = self(self, value->left);
                if (value->kind == "abs") return 1 + left;
                int right = self(self, value->right);
                return 1 + (command == "size" ? left + right : max(left, right));
            };
            cout << measure(measure, term) << '\n';
        } else if (command == "type") cout << Inference().principal(term) << '\n';
        else if (command == "ski") cout << printed(to_ski(term)) << '\n';
        else if (command == "kam") kam(term);
        else {
            bool ski = command == "skireduce";
            if (ski) term = to_ski(term);
            auto result = reduce(term, strategy, command == "church" ? false : eta, display && command != "church", ski);
            if (!result.success) cout << "no normal form within " << limit << " steps\n";
            else if (command == "church") cout << church_value(canonical_term(result.term)) << '\n';
            else cout << "result: " << (ski ? printed(result.term) : canonical(result.term)) << " (steps: " << result.count << ")\n";
        }
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    Workbench workbench;
    string line;
    while (getline(cin, line) && line != "quit") {
        if (line.empty() || line.rfind("--", 0) == 0) continue;
        try {
            workbench.command(line);
        }
        catch (const runtime_error& error) {
            cout << "error: " << error.what() << '\n';
        }
    }
}
