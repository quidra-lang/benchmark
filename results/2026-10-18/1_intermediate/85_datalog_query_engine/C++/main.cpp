#include <algorithm>
#include <cctype>
#include <cstdint>
#include <functional>
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
using Integer = int64_t;

const set<string> reserved = {"not", "mod", "count", "sum", "min", "max",
    "retract", "dump", "why", "forget", "listing", "strata", "stats", "check",
    "predicates", "undo", "halt"};
bool lower(char c) {
    return c >= 'a' && c <= 'z';
}
bool upper(char c) {
    return c >= 'A' && c <= 'Z';
}
bool digit(char c) {
    return c >= '0' && c <= '9';
}
bool word(char c) {
    return lower(c) || upper(c) || digit(c) || c == '_';
}

struct Value {
    bool symbol = false;
    Integer number = 0;
    string text;
    static Value integer(Integer n) {
        return {false, n, ""};
    }
    static Value atom(string s) {
        return {true, 0, move(s)};
    }
    bool operator<(const Value& b) const {
        if (symbol != b.symbol) return !symbol;
        return symbol ? text < b.text : number < b.number;
    }
    bool operator==(const Value& b) const {
        return symbol == b.symbol && (symbol ? text == b.text : number == b.number);
    }
    string notation() const {
        if (!symbol) return to_string(number);
        bool bare = !text.empty() && lower(text[0]) && !reserved.count(text);
        for (char c : text) bare = bare && word(c);
        return bare ? text : "\"" + text + "\"";
    }
};
using Tuple = vector<Value>;
using Binding = map<string, Value>;
struct Term {
    char kind = 'c';
    Value value;
    string variable;
    string notation(const Binding* binding = nullptr) const {
        if (kind == 'c') return value.notation();
        if (kind == 'a') return "_";
        return binding ? binding->at(variable).notation() : variable;
    }
    Value evaluate(const Binding& binding) const {
        return kind == 'c' ? value : binding.at(variable);
    }
};
struct Expression {
    string op;
    Term term;
    shared_ptr<Expression> left, right;
    string notation(const Binding* binding = nullptr) const {
        if (op.empty()) return term.notation(binding);
        if (op == "()") return "(" + left->notation(binding) + ")";
        return left->notation(binding) + " " + op + " " + right->notation(binding);
    }
    optional<Value> evaluate(const Binding& binding) const {
        if (op.empty()) return term.evaluate(binding);
        auto a = left->evaluate(binding);
        if (op == "()") return a;
        auto b = right->evaluate(binding);
        if (!a || !b || a->symbol || b->symbol) return nullopt;
        Integer x = a->number, y = b->number, n;
        if (op == "+") n = x + y;
        else if (op == "-") n = x - y;
        else if (op == "*") n = x * y;
        else {
            if (!y) return nullopt;
            Integer quotient = x / y;
            if (x % y && ((x < 0) != (y < 0))) --quotient;
            n = op == "/" ? quotient : x - y * quotient;
        }
        return Value::integer(n);
    }
    void terms(vector<Term>& result) const {
        if (op.empty()) result.push_back(term);
        else {
            left->terms(result);
            if (right) right->terms(result);
        }
    }
};
struct Atom {
    string name;
    vector<Term> terms;
    string notation(const Binding* binding = nullptr) const {
        string result = name;
        if (!terms.empty()) {
            result += '(';
            for (size_t i = 0; i < terms.size(); ++i) {
                if (i) result += ", ";
                result += terms[i].notation(binding);
            }
            result += ')';
        }
        return result;
    }
    Tuple tuple(const Binding& binding) const {
        Tuple result;
        for (const Term& t : terms) result.push_back(t.evaluate(binding));
        return result;
    }
    bool match(const Tuple& tuple, Binding& binding) const {
        for (size_t i = 0; i < terms.size(); ++i) {
            const Term& t = terms[i];
            if (t.kind == 'a') continue;
            if (t.kind == 'c') {
                if (!(t.value == tuple[i])) return false;
            } else {
                auto found = binding.find(t.variable);
                if (found == binding.end()) binding[t.variable] = tuple[i];
                else if (!(found->second == tuple[i])) return false;
            }
        }
        return true;
    }
};
struct Literal {
    char kind = 'p';
    Atom atom;
    string comparison;
    shared_ptr<Expression> left, right;
    vector<Term> terms() const {
        if (kind != 'c') return atom.terms;
        vector<Term> result;
        left->terms(result);
        right->terms(result);
        return result;
    }
    string notation(const Binding* binding = nullptr) const {
        if (kind != 'c') return (kind == 'n' ? "not " : "") + atom.notation(binding);
        return left->notation(binding) + " " + comparison + " " + right->notation(binding);
    }
    bool holds(const Binding& binding) const {
        auto a = left->evaluate(binding), b = right->evaluate(binding);
        if (!a || !b) return false;
        if (comparison == "=") return *a == *b;
        if (comparison == "!=") return !(*a == *b);
        if (a->symbol || b->symbol) return false;
        if (comparison == "<") return a->number < b->number;
        if (comparison == "<=") return a->number <= b->number;
        if (comparison == ">") return a->number > b->number;
        return a->number >= b->number;
    }
};
struct Rule {
    int number = 0;
    optional<Atom> head;
    vector<Literal> body;
    string notation() const {
        string result = head ? head->notation() + " :- " : ":- ";
        for (size_t i = 0; i < body.size(); ++i) {
            if (i) result += ", ";
            result += body[i].notation();
        }
        return result + '.';
    }
};
struct Token {
    string text, kind;
};
vector<Token> lex(const string& line) {
    vector<Token> tokens;
    for (size_t i = 0; i < line.size();) {
        char c = line[i];
        if (c == ' ') {
            ++i;
            continue;
        }
        if (c == '%') break;
        if (c == '"') {
            size_t end = line.find('"', i + 1);
            if (end == string::npos) throw runtime_error("unterminated string");
            tokens.push_back({line.substr(i, end - i + 1), "string"});
            i = end + 1;
            continue;
        }
        string pair = line.substr(i, 2);
        if (pair == ":-" || pair == "?-" || pair == "!=" || pair == "<=" || pair == ">=") {
            tokens.push_back({pair, pair});
            i += 2;
        } else if (string("(),.:=<>+-*/").find(c) != string::npos) {
            tokens.push_back({string(1, c), string(1, c)});
            ++i;
        } else if (word(c)) {
            size_t start = i++;
            while (i < line.size() && word(line[i])) ++i;
            string text = line.substr(start, i - start), kind;
            if (lower(c)) kind = reserved.count(text) ? text : "name";
            else if (upper(c)) kind = "variable";
            else if (text == "_") kind = "anonymous";
            else if (all_of(text.begin(), text.end(), digit)) {
                if (stoll(text) > 1000000000) throw runtime_error("integer out of range '" + text + "'");
                kind = "integer";
            } else throw runtime_error("bad token '" + text + "'");
            tokens.push_back({text, kind});
        } else throw runtime_error("bad character '" + string(1, c) + "'");
    }
    return tokens;
}
struct Statement {
    string kind, name, aggregate, aggregateVariable;
    Atom atom;
    Rule rule;
    Integer number = 0;
};
class Parser {
    const vector<Token>& tokens;
    size_t index = 0;
    string kind(size_t ahead = 0) const {
        return index + ahead < tokens.size() ? tokens[index + ahead].kind : "";
    }
    bool take(const string& s) {
        if (kind() != s) return false;
        ++index;
        return true;
    }
    [[noreturn]] void error() const {
        if (index == tokens.size()) throw runtime_error("syntax error at end of line");
        throw runtime_error("syntax error at '" + tokens[index].text + "'");
    }
    Token need(const string& s) {
        if (kind() != s) error();
        return tokens[index++];
    }
    bool compare(const string& s) const {
        return s == "=" || s == "!=" || s == "<" || s == "<=" || s == ">" || s == ">=";
    }
    Term term() {
        Term result;
        string k = kind();
        if (k == "name") result.value = Value::atom(tokens[index++].text);
        else if (k == "string") {
            string s = tokens[index++].text;
            result.value = Value::atom(s.substr(1, s.size() - 2));
        } else if (k == "integer" || k == "-") {
            bool negative = take("-");
            result.value = Value::integer(stoll(need("integer").text) * (negative ? -1 : 1));
        } else if (k == "variable") {
            result.kind = 'v';
            result.variable = tokens[index++].text;
        } else if (take("anonymous")) result.kind = 'a';
        else error();
        return result;
    }
    Atom atom() {
        Atom result;
        result.name = need("name").text;
        if (take("(")) {
            result.terms.push_back(term());
            while (take(",")) result.terms.push_back(term());
            need(")");
        }
        return result;
    }
    shared_ptr<Expression> factor() {
        auto result = make_shared<Expression>();
        if (take("(")) {
            result->op = "()";
            result->left = expression();
            need(")");
        } else result->term = term();
        return result;
    }
    shared_ptr<Expression> product() {
        auto result = factor();
        while (kind() == "*" || kind() == "/" || kind() == "mod") {
            string op = tokens[index++].text;
            auto right = factor();
            result = make_shared<Expression>(Expression{op, {}, result, right});
        }
        return result;
    }
    shared_ptr<Expression> expression() {
        auto result = product();
        while (kind() == "+" || kind() == "-") {
            string op = tokens[index++].text;
            auto right = product();
            result = make_shared<Expression>(Expression{op, {}, result, right});
        }
        return result;
    }
    Literal literal() {
        Literal result;
        if (take("not")) {
            result.kind = 'n';
            result.atom = atom();
        } else if (kind() == "name" && !compare(kind(1)) && kind(1) != "+" && kind(1) != "-"
                   && kind(1) != "*" && kind(1) != "/" && kind(1) != "mod") result.atom = atom();
        else {
            result.kind = 'c';
            result.left = expression();
            if (!compare(kind())) error();
            result.comparison = tokens[index++].text;
            result.right = expression();
        }
        return result;
    }
    vector<Literal> body() {
        vector<Literal> result{literal()};
        while (take(",")) result.push_back(literal());
        return result;
    }
public:
    explicit Parser(const vector<Token>& ts) : tokens(ts) {
    }
    Statement parse() {
        Statement result;
        if (take("?-")) {
            result.kind = "query";
            if (take("count")) result.aggregate = "count";
            else if (kind() == "sum" || kind() == "min" || kind() == "max") {
                result.aggregate = tokens[index++].text;
                result.aggregateVariable = need("variable").text;
                need(":");
            }
            result.rule.body = body();
        } else if (take(":-")) {
            result.kind = "rule";
            result.rule.body = body();
        } else if (kind() == "name") {
            result.atom = atom();
            if (take(":-")) {
                result.kind = "rule";
                result.rule.head = result.atom;
                result.rule.body = body();
            } else result.kind = "fact";
        } else {
            result.kind = kind();
            const set<string> commands = {"retract", "why", "dump", "forget", "listing", "strata",
                "stats", "check", "predicates", "undo", "halt"};
            if (!commands.count(result.kind)) error();
            ++index;
            if (result.kind == "retract" || result.kind == "why") result.atom = atom();
            else if (result.kind == "dump") result.name = need("name").text;
            else if (result.kind == "forget") result.number = stoll(need("integer").text);
            else if (result.kind == "listing" && kind() == "name") result.name = tokens[index++].text;
        }
        need(".");
        if (index != tokens.size()) error();
        return result;
    }
};
vector<Term> allTerms(const Rule& rule) {
    vector<Term> result;
    if (rule.head) result = rule.head->terms;
    for (const Literal& literal : rule.body) {
        auto ts = literal.terms();
        result.insert(result.end(), ts.begin(), ts.end());
    }
    return result;
}
vector<string> variables(const vector<Term>& terms) {
    vector<string> result;
    set<string> seen;
    for (const Term& t : terms) {
        if (t.kind == 'v' && seen.insert(t.variable).second) result.push_back(t.variable);
    }
    return result;
}
Tuple bindingTuple(const Binding& binding, const vector<string>& vars) {
    Tuple result;
    for (const string& v : vars) result.push_back(binding.at(v));
    return result;
}
string answerText(const Tuple& tuple, const vector<string>& vars) {
    string result;
    for (size_t i = 0; i < vars.size(); ++i) {
        if (i) result += ", ";
        result += vars[i] + " = " + tuple[i].notation();
    }
    return result;
}
struct State {
    map<string, int> arities;
    map<string, set<Tuple>> facts;
    vector<Rule> rules;
};
struct Derivation {
    int round = 0, rule = 0;
};
using Database = map<string, map<Tuple, Derivation>>;
struct Model {
    Database database;
    vector<int> rounds, added;
};
vector<Atom> atoms(const Rule& rule) {
    vector<Atom> result;
    if (rule.head) result.push_back(*rule.head);
    for (const Literal& l : rule.body) if (l.kind != 'c') result.push_back(l.atom);
    return result;
}
void predicates(const State& state, const Rule& rule, bool registering) {
    auto known = state.arities;
    for (const Atom& a : atoms(rule)) {
        auto found = known.find(a.name);
        if (found == known.end()) {
            if (!registering) throw runtime_error("unknown predicate " + a.name);
            known[a.name] = static_cast<int>(a.terms.size());
        } else if (found->second != static_cast<int>(a.terms.size())) {
            throw runtime_error("arity mismatch for " + a.name + ": expected " + to_string(found->second)
                + ", got " + to_string(a.terms.size()));
        }
    }
}
void safety(const Rule& rule, const string& aggregate = "") {
    if (rule.head) for (const Term& t : rule.head->terms) {
        if (t.kind == 'a') throw runtime_error("anonymous variable in head");
    }
    for (const Literal& l : rule.body) if (l.kind == 'c') for (const Term& t : l.terms()) {
        if (t.kind == 'a') throw runtime_error("anonymous variable in comparison");
    }
    set<string> bound;
    for (const Literal& l : rule.body) if (l.kind == 'p') for (const Term& t : l.atom.terms) {
        if (t.kind == 'v') bound.insert(t.variable);
    }
    vector<Term> checked;
    if (rule.head) checked = rule.head->terms;
    if (!aggregate.empty()) checked.push_back({'v', {}, aggregate});
    for (const Literal& l : rule.body) if (l.kind != 'p') {
        auto ts = l.terms();
        checked.insert(checked.end(), ts.begin(), ts.end());
    }
    for (const Term& t : checked) if (t.kind == 'v' && !bound.count(t.variable)) {
        throw runtime_error("unsafe variable " + t.variable);
    }
}
void registerPredicates(State& state, const Rule& rule) {
    for (const Atom& a : atoms(rule)) {
        state.arities[a.name] = static_cast<int>(a.terms.size());
        state.facts.try_emplace(a.name);
    }
}
map<string, int> strata(const State& state, const string& newHead = "") {
    map<string, int> result;
    for (const auto& p : state.arities) result[p.first] = 0;
    for (size_t pass = 0; pass < result.size(); ++pass) {
        bool changed = false;
        for (const Rule& r : state.rules) if (r.head) for (const Literal& l : r.body) if (l.kind != 'c') {
            int required = result.at(l.atom.name) + (l.kind == 'n');
            int& s = result.at(r.head->name);
            if (s < required) {
                s = required;
                changed = true;
            }
        }
        if (!changed) break;
        if (pass + 1 == result.size()) throw runtime_error("negative cycle through " + newHead);
    }
    return result;
}
set<Binding> solve(const vector<Literal>& body, const Database& db, int limit = -1) {
    vector<const Atom*> positive;
    vector<pair<const Literal*, vector<Term>>> filters;
    for (const Literal& literal : body) {
        if (literal.kind == 'p') positive.push_back(&literal.atom);
        else filters.emplace_back(&literal, literal.terms());
    }
    set<Binding> solutions;
    vector<bool> used(positive.size(), false);
    function<void(const Binding&, size_t)> visit = [&](const Binding& binding, size_t depth) {
        for (const auto& filter : filters) {
            bool bound = true;
            for (const Term& term : filter.second) {
                if (term.kind == 'v' && !binding.count(term.variable)) bound = false;
            }
            if (!bound) continue;
            const Literal& literal = *filter.first;
            if (literal.kind == 'c') {
                if (!literal.holds(binding)) return;
            } else {
                for (const auto& entry : db.at(literal.atom.name)) {
                    Binding candidate = binding;
                    if (literal.atom.match(entry.first, candidate)) return;
                }
            }
        }
        if (depth == positive.size()) {
            solutions.insert(binding);
            return;
        }
        size_t choice = 0, bestSize = 0;
        int bestBound = -1;
        for (size_t i = 0; i < positive.size(); ++i) if (!used[i]) {
            int bound = 0;
            for (const Term& term : positive[i]->terms) {
                if (term.kind == 'c' || (term.kind == 'v' && binding.count(term.variable))) ++bound;
            }
            size_t size = db.at(positive[i]->name).size();
            if (bound > bestBound || (bound == bestBound && size < bestSize)) {
                choice = i;
                bestBound = bound;
                bestSize = size;
            }
        }
        const Atom& atom = *positive[choice];
        used[choice] = true;
        set<Binding> seen;
        for (const auto& entry : db.at(atom.name)) {
            if (limit >= 0 && entry.second.round >= limit) continue;
            Binding candidate = binding;
            if (atom.match(entry.first, candidate) && seen.insert(candidate).second) visit(candidate, depth + 1);
        }
        used[choice] = false;
    };
    visit(Binding{}, 0);
    return solutions;
}
Model model(const State& state) {
    Model result;
    auto levels = strata(state);
    int maximum = -1;
    for (const auto& p : levels) {
        maximum = max(maximum, p.second);
        auto& rows = result.database[p.first];
        for (const Tuple& tuple : state.facts.at(p.first)) rows[tuple] = {};
    }
    result.rounds.resize(maximum + 1);
    result.added.resize(maximum + 1);
    int serial = 0;
    for (int level = 0; level <= maximum; ++level) for (;;) {
        map<pair<string, Tuple>, int> added;
        for (const Rule& r : state.rules) if (r.head && levels.at(r.head->name) == level) {
            for (const Binding& binding : solve(r.body, result.database)) {
                Tuple tuple = r.head->tuple(binding);
                if (result.database.at(r.head->name).count(tuple)) continue;
                auto key = make_pair(r.head->name, move(tuple));
                auto found = added.find(key);
                if (found == added.end() || r.number < found->second) added[key] = r.number;
            }
        }
        if (added.empty()) break;
        ++serial;
        ++result.rounds[level];
        result.added[level] += static_cast<int>(added.size());
        for (const auto& entry : added) result.database[entry.first.first][entry.first.second] = {serial, entry.second};
    }
    return result;
}
set<Tuple> answers(const Rule& rule, const Database& db, const vector<string>& vars) {
    set<Tuple> result;
    for (const Binding& binding : solve(rule.body, db)) result.insert(bindingTuple(binding, vars));
    return result;
}
string groundNotation(const string& name, const Tuple& tuple) {
    Atom atom;
    atom.name = name;
    for (const Value& value : tuple) atom.terms.push_back({'c', value, ""});
    return atom.notation();
}
void proof(ostream& out, const State& state, const Database& db, const string& name, const Tuple& tuple, int depth) {
    const Derivation& origin = db.at(name).at(tuple);
    string indent(depth * 2, ' '), text = groundNotation(name, tuple);
    if (!origin.round) {
        out << indent << text << " [fact]\n";
        return;
    }
    for (const Rule& r : state.rules) if (r.head && r.head->name == name) {
        optional<Binding> chosen;
        Tuple best;
        auto vars = variables(allTerms(r));
        for (const Binding& binding : solve(r.body, db, origin.round)) {
            if (r.head->tuple(binding) != tuple) continue;
            Tuple order = bindingTuple(binding, vars);
            if (!chosen || order < best) {
                chosen = binding;
                best = move(order);
            }
        }
        if (!chosen) continue;
        out << indent << text << " [rule " << r.number << "]\n";
        for (const Literal& l : r.body) {
            if (l.kind != 'p') out << indent << "  " << l.notation(&*chosen) << '\n';
            else for (const auto& entry : db.at(l.atom.name)) {
                if (entry.second.round >= origin.round) continue;
                Binding binding = *chosen;
                if (l.atom.match(entry.first, binding)) {
                    proof(out, state, db, l.atom.name, entry.first, depth + 1);
                    break;
                }
            }
        }
        return;
    }
}
class Engine {
    State state;
    int nextRule = 1;
    vector<pair<int, State>> history;
    void save(int line) {
        history.emplace_back(line, state);
    }
    void requirePredicate(const string& name) const {
        if (!state.arities.count(name)) throw runtime_error("unknown predicate " + name);
    }
public:
    bool execute(const Statement& statement, int line, ostream& out) {
        const string& command = statement.kind;
        if (command == "halt") return false;
        if (command == "fact" || command == "rule") {
            Rule r = statement.rule;
            if (command == "fact") r.head = statement.atom;
            predicates(state, r, true);
            safety(r);
            if (command == "fact") {
                Tuple tuple = r.head->tuple({});
                auto found = state.facts.find(r.head->name);
                if (found != state.facts.end() && found->second.count(tuple)) return true;
                save(line);
                registerPredicates(state, r);
                state.facts[r.head->name].insert(move(tuple));
            } else {
                for (const Rule& old : state.rules) if (old.notation() == r.notation()) {
                    throw runtime_error("duplicate of rule " + to_string(old.number));
                }
                State proposed = state;
                registerPredicates(proposed, r);
                proposed.rules.push_back(r);
                if (r.head) strata(proposed, r.head->name);
                save(line);
                r.number = nextRule++;
                registerPredicates(state, r);
                state.rules.push_back(r);
                auto ts = allTerms(r);
                map<string, int> count;
                for (const Term& t : ts) if (t.kind == 'v') ++count[t.variable];
                for (const string& v : variables(ts)) if (count[v] == 1) {
                    out << "WARNING line " << line << ": singleton variable " << v << '\n';
                }
            }
        } else if (command == "query") {
            const Rule& r = statement.rule;
            predicates(state, r, false);
            safety(r, statement.aggregateVariable);
            auto computed = model(state);
            auto vars = variables(allTerms(r));
            auto rows = answers(r, computed.database, vars);
            const string& aggregate = statement.aggregate;
            if (aggregate == "count") out << rows.size() << '\n';
            else if (!aggregate.empty()) {
                size_t position = find(vars.begin(), vars.end(), statement.aggregateVariable) - vars.begin();
                if (aggregate == "sum") {
                    Integer total = 0;
                    for (const Tuple& row : rows) {
                        if (row[position].symbol) throw runtime_error("non-integer value in sum");
                        total += row[position].number;
                    }
                    out << total << '\n';
                } else if (rows.empty()) out << "no answers\n";
                else {
                    optional<Value> best;
                    for (const Tuple& row : rows) {
                        const Value& value = row[position];
                        if (!best || (aggregate == "min" ? value < *best : *best < value)) best = value;
                    }
                    out << best->notation() << '\n';
                }
            } else if (vars.empty()) out << (rows.empty() ? "false.\n" : "true.\n");
            else {
                for (const Tuple& row : rows) out << answerText(row, vars) << '\n';
                out << rows.size() << (rows.size() == 1 ? " answer\n" : " answers\n");
            }
        } else if (command == "retract" || command == "why") {
            Rule check;
            check.head = statement.atom;
            predicates(state, check, false);
            const Atom& a = statement.atom;
            if (command == "retract") {
                vector<Tuple> removed;
                for (const Tuple& tuple : state.facts.at(a.name)) {
                    Binding binding;
                    if (a.match(tuple, binding)) removed.push_back(tuple);
                }
                if (removed.empty()) throw runtime_error("no matching facts");
                save(line);
                for (const Tuple& tuple : removed) state.facts[a.name].erase(tuple);
                out << removed.size() << (removed.size() == 1 ? " fact retracted\n" : " facts retracted\n");
            } else {
                for (const Term& t : a.terms) if (t.kind != 'c') throw runtime_error("why needs a ground atom");
                auto computed = model(state);
                Tuple tuple = a.tuple({});
                if (!computed.database.at(a.name).count(tuple)) out << "false.\n";
                else proof(out, state, computed.database, a.name, tuple, 0);
            }
        } else if (command == "forget") {
            auto found = find_if(state.rules.begin(), state.rules.end(), [&](const Rule& r) {
                return r.number == statement.number;
            });
            if (found == state.rules.end()) throw runtime_error("no rule " + to_string(statement.number));
            size_t index = found - state.rules.begin();
            save(line);
            state.rules.erase(state.rules.begin() + index);
        } else if (command == "undo") {
            if (history.empty()) throw runtime_error("nothing to undo");
            out << "undid line " << history.back().first << '\n';
            state = move(history.back().second);
            history.pop_back();
        } else if (command == "listing") {
            if (!statement.name.empty()) requirePredicate(statement.name);
            bool any = false;
            for (const Rule& r : state.rules) if (statement.name.empty() || (r.head && r.head->name == statement.name)) {
                out << r.number << ": " << r.notation() << '\n';
                any = true;
            }
            if (!any) out << "no rules\n";
        } else if (command == "strata") {
            auto levels = strata(state);
            if (levels.empty()) out << "no predicates\n";
            else {
                map<string, set<string>> reach;
                for (const Rule& r : state.rules) if (r.head) for (const Literal& l : r.body) {
                    if (l.kind != 'c') reach[r.head->name].insert(l.atom.name);
                }
                for (const auto& middle : state.arities) for (const auto& start : state.arities) {
                    if (reach[start.first].count(middle.first)) {
                        const auto destinations = reach[middle.first];
                        reach[start.first].insert(destinations.begin(), destinations.end());
                    }
                }
                int maximum = 0;
                for (const auto& p : levels) maximum = max(maximum, p.second);
                for (int k = 0; k <= maximum; ++k) {
                    out << "stratum " << k << ": ";
                    bool first = true;
                    for (const auto& p : levels) if (p.second == k) {
                        if (!first) out << ", ";
                        out << p.first << (reach[p.first].count(p.first) ? "*" : "");
                        first = false;
                    }
                    out << '\n';
                }
            }
        } else if (command == "dump") {
            requirePredicate(statement.name);
            auto computed = model(state);
            const auto& tuples = computed.database.at(statement.name);
            for (const auto& t : tuples) out << groundNotation(statement.name, t.first) << ".\n";
            out << tuples.size() << (tuples.size() == 1 ? " tuple\n" : " tuples\n");
        } else if (command == "stats" || command == "predicates") {
            auto computed = model(state);
            size_t facts = 0, tuples = 0, rules = 0;
            map<int, int> deriving;
            for (const auto& p : state.arities) {
                facts += state.facts.at(p.first).size();
                tuples += computed.database.at(p.first).size();
                for (const auto& row : computed.database.at(p.first)) if (row.second.rule) ++deriving[row.second.rule];
            }
            for (const Rule& r : state.rules) if (r.head) ++rules;
            if (command == "stats") {
                out << "facts " << facts << ", rules " << rules << ", constraints " << state.rules.size() - rules
                    << ", tuples " << tuples << '\n';
                for (size_t k = 0; k < computed.rounds.size(); ++k) {
                    out << "stratum " << k << ": rounds " << computed.rounds[k] << ", new " << computed.added[k] << '\n';
                }
                for (const Rule& r : state.rules) if (r.head) out << "rule " << r.number << ": new " << deriving[r.number] << '\n';
            } else {
                if (state.arities.empty()) out << "no predicates\n";
                for (const auto& p : state.arities) {
                    int count = 0;
                    for (const Rule& r : state.rules) if (r.head && r.head->name == p.first) ++count;
                    out << p.first << '/' << p.second << ": facts " << state.facts.at(p.first).size()
                        << ", rules " << count << ", tuples " << computed.database.at(p.first).size() << '\n';
                }
            }
        } else if (command == "check") {
            auto computed = model(state);
            bool any = false;
            for (const Rule& r : state.rules) if (!r.head) {
                any = true;
                auto vars = variables(allTerms(r));
                auto rows = answers(r, computed.database, vars);
                out << "constraint " << r.number << ": ";
                if (rows.empty()) out << "ok\n";
                else {
                    out << rows.size() << (rows.size() == 1 ? " violation\n" : " violations\n");
                    if (!vars.empty()) for (const Tuple& row : rows) out << "  " << answerText(row, vars) << '\n';
                }
            }
            if (!any) out << "no constraints\n";
        }
        return true;
    }
};
int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    Engine engine;
    string line;
    int number = 0;
    while (getline(cin, line)) {
        ++number;
        try {
            auto tokens = lex(line);
            if (tokens.empty()) continue;
            auto statement = Parser(tokens).parse();
            ostringstream output;
            if (!engine.execute(statement, number, output)) break;
            cout << output.str();
        } catch (const runtime_error& error) {
            cout << "ERROR line " << number << ": " << error.what() << '\n';
        }
    }
}
