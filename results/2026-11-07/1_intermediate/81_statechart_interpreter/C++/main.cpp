#include <algorithm>
#include <cctype>
#include <deque>
#include <iostream>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

using namespace std;
using Integer = long long;

vector<string> words(const string& text) {
    istringstream input(text);
    vector<string> result;
    string word;
    while (input >> word) result.push_back(word);
    return result;
}
string join(const vector<string>& values, const string& separator = ",") {
    string result;
    for (const auto& value : values) {
        if (!result.empty()) result += separator;
        result += value;
    }
    return result.empty() ? "-" : result;
}
struct Expression;
using Expr = shared_ptr<Expression>;
struct Expression {
    string kind, text;
    Integer value = 0;
    Expr left, right;
};
struct ParsedExpression {
    Expr tree;
    vector<pair<string, string>> references;
};

class ExpressionParser {
    vector<string> tokens;
    size_t position = 0;
    vector<pair<string, string>> references;
    static int precedence(const string& token) {
        if (token == "||") return 0;
        if (token == "&&") return 1;
        if (token == "==" || token == "!=" || token == "<" || token == "<=" || token == ">" || token == ">=") return 2;
        if (token == "+" || token == "-") return 3;
        if (token == "*" || token == "/" || token == "%") return 4;
        return -1;
    }
    Expr unary() {
        string token = tokens[position++];
        if (token == "!" || token == "-") return make_shared<Expression>(Expression{"unary", token, 0, unary(), nullptr});
        if (token == "(") {
            Expr result = binary(0);
            ++position;
            return result;
        }
        if (token == "in") {
            ++position;
            string name = tokens[position++];
            ++position;
            references.push_back({"state", name});
            return make_shared<Expression>(Expression{"state", name, 0, nullptr, nullptr});
        }
        if (isdigit(static_cast<unsigned char>(token[0])))
            return make_shared<Expression>(Expression{"number", "", stoll(token), nullptr, nullptr});
        if (token != "_data") references.push_back({"variable", token});
        return make_shared<Expression>(Expression{"variable", token, 0, nullptr, nullptr});
    }
    Expr binary(int minimum) {
        Expr left = unary();
        while (position < tokens.size() && precedence(tokens[position]) >= minimum) {
            string operation = tokens[position++];
            Expr right = binary(precedence(operation) + 1);
            left = make_shared<Expression>(Expression{"binary", operation, 0, left, right});
        }
        return left;
    }
public:
    explicit ExpressionParser(const string& text) {
        for (size_t i = 0; i < text.size();) {
            unsigned char ch = text[i];
            if (ch == ' ') {
                ++i;
                continue;
            }
            size_t start = i++;
            if (isalnum(ch) || ch == '_') {
                while (i < text.size() && (isalnum(static_cast<unsigned char>(text[i])) || text[i] == '_')) ++i;
            } else if (i < text.size()) {
                string pair = text.substr(start, 2);
                if (pair == "||" || pair == "&&" || pair == "==" || pair == "!=" || pair == "<=" || pair == ">=") ++i;
            }
            tokens.push_back(text.substr(start, i - start));
        }
    }
    ParsedExpression parse() {
        Expr tree = binary(0);
        return {tree, references};
    }
};
ParsedExpression expression(const string& text) {
    return ExpressionParser(text).parse();
}

struct Action {
    string kind, name, prefix;
    int delay = 0;
    bool has_string = false;
    ParsedExpression argument;
};
vector<Action> parse_actions(const string& text) {
    vector<Action> result;
    for (size_t start = 0; start < text.size();) {
        size_t end = text.find("; ", start);
        string part = text.substr(start, end == string::npos ? end : end - start);
        Action action;
        size_t assignment = part.find(" = ");
        if (assignment != string::npos && part.rfind("log ", 0) != 0) {
            action.kind = "assign";
            action.name = part.substr(0, assignment);
            action.argument = expression(part.substr(assignment + 3));
        } else if (part.rfind("log ", 0) == 0) {
            action.kind = "log";
            string rest = part.substr(4);
            if (rest[0] == '"') {
                size_t quote = rest.find('"', 1);
                action.has_string = true;
                action.prefix = rest.substr(1, quote - 1);
                if (quote + 1 < rest.size()) action.argument = expression(rest.substr(quote + 2));
            } else action.argument = expression(rest);
        } else {
            size_t first = part.find(' ');
            action.kind = part.substr(0, first);
            size_t second = part.find(' ', first + 1);
            action.name = part.substr(first + 1, second == string::npos ? second : second - first - 1);
            if (action.kind == "raise") {
                if (second != string::npos) action.argument = expression(part.substr(second + 1));
            } else if (action.kind == "send") {
                size_t third = part.find(' ', second + 1);
                action.delay = stoi(part.substr(second + 1, third == string::npos ? third : third - second - 1));
                if (third != string::npos) action.argument = expression(part.substr(third + 1));
            }
        }
        result.push_back(move(action));
        if (end == string::npos) break;
        start = end + 2;
    }
    return result;
}
struct Transition {
    string source_name, target_name, kind, trigger;
    vector<string> descriptors;
    int source = -1, target = -1, delay = 0;
    ParsedExpression guard;
    vector<Action> actions;
};
Transition parse_transition(const string& text) {
    Transition result;
    size_t position = 3, end = text.find(' ', position);
    result.source_name = text.substr(position, end - position);
    position = end + 1;
    end = text.find(' ', position);
    string trigger = text.substr(position, end == string::npos ? end : end - position);
    position = end == string::npos ? text.size() : end;
    if (trigger == "after") {
        result.trigger = "timer";
        ++position;
        end = text.find(' ', position);
        result.delay = stoi(text.substr(position, end == string::npos ? end : end - position));
        position = end == string::npos ? text.size() : end;
    } else if (trigger == "always") result.trigger = "always";
    else {
        result.trigger = "event";
        for (size_t start = 0;;) {
            size_t separator = trigger.find('|', start);
            result.descriptors.push_back(trigger.substr(start, separator == string::npos ? separator : separator - start));
            if (separator == string::npos) break;
            start = separator + 1;
        }
    }
    if (text.compare(position, 2, " [") == 0) {
        end = text.find(']', position + 2);
        result.guard = expression(text.substr(position + 2, end - position - 2));
        position = end + 1;
    }
    result.kind = "internal";
    if (text.compare(position, 4, " -> ") == 0 || text.compare(position, 4, " ~> ") == 0) {
        result.kind = text[position + 1] == '-' ? "external" : "local";
        position += 4;
        end = text.find(' ', position);
        result.target_name = text.substr(position, end == string::npos ? end : end - position);
        position = end == string::npos ? text.size() : end;
    }
    if (position < text.size()) result.actions = parse_actions(text.substr(position + 3));
    return result;
}
struct Definition {
    int line = 0, state = -1;
    string kind, name, parent, initial, history_kind, default_name;
    Integer value = 0;
    vector<Action> actions;
    Transition transition;
    string error;
};
Definition parse_definition(const string& text, int line) {
    auto items = words(text);
    Definition result;
    result.line = line;
    result.kind = items[0];
    result.name = items[1];
    if (result.kind == "var") result.value = stoll(items[2]);
    else if (result.kind == "entry" || result.kind == "exit") result.actions = parse_actions(text.substr(text.find(" / ") + 3));
    else if (result.kind == "on") result.transition = parse_transition(text);
    else if (result.kind == "state") {
        size_t position = 2;
        if (position < items.size() && items[position] != "initial") result.parent = items[position++];
        if (position < items.size()) result.initial = items[position + 1];
    } else {
        if (items.size() >= 3) result.parent = items[2];
        if (result.kind == "history") {
            result.history_kind = items[3];
            if (items.size() == 5) result.default_name = items[4];
        }
    }
    return result;
}
struct State {
    string name, kind, initial_name, history_kind, default_name;
    int parent = -1, depth = 0, initial = -1, default_target = -1;
    vector<int> children, child_states, transitions;
    vector<vector<Action>> entry, exit;
    Integer entered = 0, taken = 0, dwell = 0, entry_time = 0;
};
struct Event {
    string name;
    Integer value = 0;
};
struct Reservation {
    Integer due, sequence;
    int transition = -1;
    Event event;
};
struct Trigger {
    string kind;
    Event event;
    int transition = -1;
};
struct Selected {
    int transition, scope;
    vector<bool> exits;
};
struct EvaluationError {
};

class Chart {
    vector<State> states{State{}};
    map<string, int> identifiers;
    map<string, Integer> variables;
    vector<Transition> transitions;
    vector<int> document;
    vector<bool> active;
    vector<optional<vector<int>>> history;
    deque<Event> internal;
    vector<Reservation> reservations;
    Integer current_value = 0, clock = 0, creation = 0, macrosteps = 0, microsteps = 0;
    bool tracing = false, halted = false;
    bool descendant(int state, int ancestor) const {
        for (int p = states[state].parent; p >= 0; p = states[p].parent) if (p == ancestor) return true;
        return false;
    }
    bool compound(int state) const {
        return state == 0 || (states[state].kind == "state" && !states[state].child_states.empty());
    }
    bool parallel(int state) const {
        return states[state].kind == "parallel" && !states[state].child_states.empty();
    }
    bool atomic(int state) const {
        return state != 0 && states[state].kind != "history" && states[state].child_states.empty();
    }
    void visit(int state) {
        document.push_back(state);
        for (int child : states[state].children) visit(child);
    }
    string bad_reference(const vector<pair<string, string>>& references) const {
        for (const auto& [kind, name] : references) {
            if (kind == "state" && !identifiers.count(name)) return "unknown state " + name;
            if (kind == "variable" && !variables.count(name)) return "unknown variable " + name;
        }
        return "";
    }
    string bad_actions(const vector<Action>& actions) const {
        for (const auto& action : actions) {
            if (action.kind == "assign" && !variables.count(action.name)) return "unknown variable " + action.name;
            string error = bad_reference(action.argument.references);
            if (!error.empty()) return error;
        }
        return "";
    }
    Integer evaluate(const Expr& expression) const {
        if (expression->kind == "number") return expression->value;
        if (expression->kind == "variable") return expression->text == "_data" ? current_value : variables.at(expression->text);
        if (expression->kind == "state") return active[identifiers.at(expression->text)];
        Integer a = evaluate(expression->left);
        string op = expression->text;
        if (expression->kind == "unary") return op == "!" ? a == 0 : -a;
        if (op == "&&" && a == 0) return 0;
        if (op == "||" && a != 0) return 1;
        Integer b = evaluate(expression->right);
        if ((op == "/" || op == "%") && b == 0) throw EvaluationError{};
        if (op == "+") return a + b;
        if (op == "-") return a - b;
        if (op == "*") return a * b;
        if (op == "/") return a / b;
        if (op == "%") return a % b;
        if (op == "==") return a == b;
        if (op == "!=") return a != b;
        if (op == "<") return a < b;
        if (op == "<=") return a <= b;
        if (op == ">") return a > b;
        if (op == ">=") return a >= b;
        return b != 0;
    }
    void execute(const vector<Action>& actions) {
        for (const auto& action : actions) {
            Integer value = 0;
            try {
                if (action.argument.tree) value = evaluate(action.argument.tree);
            }
            catch (const EvaluationError&) {
                internal.push_back({"error.execution", 0});
                break;
            }
            if (action.kind == "assign") variables[action.name] = value;
            else if (action.kind == "raise") internal.push_back({action.name, value});
            else if (action.kind == "send") reservations.push_back({clock + action.delay, ++creation, -1, {action.name, value}});
            else if (action.kind == "cancel") reservations.erase(remove_if(reservations.begin(), reservations.end(), [&](const Reservation& r) {
                return r.transition < 0 && r.event.name == action.name;
            }), reservations.end());
            else if (action.kind == "log") {
                if (action.has_string) cout << action.prefix;
                if (action.argument.tree) cout << value;
                cout << '\n';
            }
        }
    }
    vector<int> effective(const Transition& transition) const {
        if (states[transition.target].kind != "history") return {transition.target};
        if (history[transition.target]) return *history[transition.target];
        return {states[transition.target].default_target};
    }
    Selected selection(int id) const {
        const auto& transition = transitions[id];
        Selected result{id, -1, vector<bool>(states.size())};
        if (transition.kind == "internal") return result;
        auto targets = effective(transition);
        auto contains_all = [&](int parent) {
            return all_of(targets.begin(), targets.end(), [&](int target) {
                return descendant(target, parent);
            });
        };
        if (transition.kind == "local" && compound(transition.source) && contains_all(transition.source)) result.scope = transition.source;
        else for (int p = states[transition.source].parent; p >= 0; p = states[p].parent)
            if (compound(p) && contains_all(p)) {
                result.scope = p;
                break;
            }
        for (int state : document) result.exits[state] = active[state] && descendant(state, result.scope);
        return result;
    }
    bool matches(const Transition& transition, int id, const Trigger& trigger) const {
        if (trigger.kind == "always") return transition.trigger == "always";
        if (trigger.kind == "timer") return transition.trigger == "timer" && id == trigger.transition;
        if (transition.trigger != "event") return false;
        for (const auto& descriptor : transition.descriptors)
            if (descriptor == "*" || descriptor == trigger.event.name || trigger.event.name.rfind(descriptor + ".", 0) == 0) return true;
        return false;
    }
    vector<Selected> select(const Trigger& trigger) {
        vector<int> candidates;
        set<int> seen;
        for (int leaf : document) if (active[leaf] && atomic(leaf)) {
            int chosen = -1;
            for (int source = leaf; source > 0 && chosen < 0; source = states[source].parent) {
                for (int id : states[source].transitions) {
                    const auto& transition = transitions[id];
                    if (!matches(transition, id, trigger)) continue;
                    bool enabled = true;
                    try {
                        if (transition.guard.tree) enabled = evaluate(transition.guard.tree) != 0;
                    }
                    catch (const EvaluationError&) {
                        internal.push_back({"error.execution", 0});
                        enabled = false;
                    }
                    if (enabled) {
                        chosen = id;
                        break;
                    }
                }
            }
            if (chosen >= 0 && seen.insert(chosen).second) candidates.push_back(chosen);
        }
        vector<Selected> result;
        vector<bool> exiting(states.size());
        for (int candidate : candidates) {
            Selected current = selection(candidate);
            bool conflict = false;
            for (int state : document) if (current.exits[state] && exiting[state]) {
                conflict = true;
                break;
            }
            if (!conflict) {
                for (int state : document) exiting[state] = exiting[state] || current.exits[state];
                result.push_back(move(current));
            }
        }
        return result;
    }
    void expand(vector<bool>& entries) const {
        bool changed = true;
        while (changed) {
            changed = false;
            for (int state : document) if (entries[state]) {
                if (parallel(state)) {
                    for (int child : states[state].child_states) if (!entries[child]) {
                        entries[child] = true;
                        changed = true;
                    }
                } else if (compound(state)) {
                    bool has_child = false;
                    for (int child : states[state].child_states) has_child = has_child || entries[child];
                    if (!has_child) {
                        entries[states[state].initial] = true;
                        changed = true;
                    }
                }
            }
        }
    }
    bool complete(int state) const {
        if (compound(state)) {
            for (int child : states[state].child_states) if (states[child].kind == "final" && active[child]) return true;
            return false;
        }
        if (parallel(state)) {
            for (int child : states[state].child_states) if (!complete(child)) return false;
            return true;
        }
        return false;
    }
    void enter(const vector<bool>& entries) {
        for (int id : document) if (entries[id]) {
            State& state = states[id];
            active[id] = true;
            ++state.entered;
            state.entry_time = clock;
            for (int transition : state.transitions) if (transitions[transition].trigger == "timer")
                reservations.push_back({clock + transitions[transition].delay, ++creation, transition, {}});
            for (const auto& actions : state.entry) execute(actions);
            if (state.kind == "final") {
                int parent = state.parent;
                internal.push_back({"done.state." + states[parent].name, 0});
                int grandparent = states[parent].parent;
                if (grandparent > 0 && parallel(grandparent) && complete(grandparent))
                    internal.push_back({"done.state." + states[grandparent].name, 0});
            }
        }
    }
    string listed(const vector<bool>& selected, bool reverse = false) const {
        vector<string> names;
        for (int state : document) if (selected[state]) names.push_back(states[state].name);
        if (reverse) std::reverse(names.begin(), names.end());
        return join(names);
    }
    string trigger_name(const Trigger& trigger) const {
        if (trigger.kind == "always") return "always";
        if (trigger.kind == "timer") {
            const auto& transition = transitions[trigger.transition];
            return "after(" + to_string(transition.delay) + ")@" + states[transition.source].name;
        }
        return trigger.event.name + (trigger.event.value ? "=" + to_string(trigger.event.value) : "");
    }
    void microstep(const vector<Selected>& selected, const Trigger& trigger) {
        vector<bool> exits(states.size()), entries(states.size());
        for (const auto& item : selected) for (int state : document) exits[state] = exits[state] || item.exits[state];
        for (int state : document) if (exits[state]) {
            for (int child : states[state].children) if (states[child].kind == "history") {
                vector<int> saved;
                for (int candidate : document) if (active[candidate]) {
                    bool record = states[child].history_kind == "deep" ? atomic(candidate) && descendant(candidate, state) :
                                                                                      states[candidate].parent == state;
                    if (record) saved.push_back(candidate);
                }
                history[child] = move(saved);
            }
        }
        for (const auto& item : selected) {
            const auto& transition = transitions[item.transition];
            if (transition.kind == "internal") continue;
            for (int target : effective(transition))
                for (int state = target; state != item.scope && state > 0; state = states[state].parent) entries[state] = true;
        }
        expand(entries);
        if (tracing) {
            vector<string> sources;
            for (const auto& item : selected) sources.push_back(states[transitions[item.transition].source].name);
            cout << "[t=" << clock << "] " << trigger_name(trigger) << " (" << join(sources) << "): exit " << listed(exits, true)
                 << "; enter " << listed(entries) << '\n';
        }
        for (auto it = document.rbegin(); it != document.rend(); ++it) if (exits[*it]) {
            int id = *it;
            State& state = states[id];
            for (const auto& actions : state.exit) execute(actions);
            active[id] = false;
            state.dwell += clock - state.entry_time;
            reservations.erase(remove_if(reservations.begin(), reservations.end(), [&](const Reservation& reservation) {
                return reservation.transition >= 0 && transitions[reservation.transition].source == id;
            }), reservations.end());
        }
        for (const auto& item : selected) {
            const auto& transition = transitions[item.transition];
            execute(transition.actions);
            ++states[transition.source].taken;
        }
        enter(entries);
    }
    void macrostep(const Trigger& initial) {
        ++macrosteps;
        int count = 0;
        auto perform = [&](const vector<Selected>& selected, const Trigger& trigger) {
            if (count == 1000) {
                cout << "LIVELOCK t=" << clock << '\n';
                halted = true;
                return;
            }
            ++count;
            ++microsteps;
            microstep(selected, trigger);
        };
        if (initial.kind == "start") {
            current_value = 0;
            vector<bool> entries(states.size());
            entries[states[0].initial] = true;
            expand(entries);
            enter(entries);
        } else {
            current_value = initial.kind == "timer" ? 0 : initial.event.value;
            auto selected = select(initial);
            if (!selected.empty()) perform(selected, initial);
        }
        while (!halted) {
            current_value = 0;
            Trigger eventless{"always", {}, -1};
            auto selected = select(eventless);
            if (!selected.empty()) {
                perform(selected, eventless);
                continue;
            }
            if (internal.empty()) break;
            Event event = internal.front();
            internal.pop_front();
            current_value = event.value;
            Trigger trigger{"event", event, -1};
            selected = select(trigger);
            if (!selected.empty()) perform(selected, trigger);
        }
    }
    void warnings() const {
        vector<bool> reachable(states.size());
        reachable[states[0].initial] = true;
        bool changed = true;
        while (changed) {
            changed = false;
            auto add = [&](int state) {
                if (state > 0 && !reachable[state]) {
                    reachable[state] = true;
                    changed = true;
                }
            };
            for (int state : document) if (reachable[state]) {
                add(states[state].parent);
                if (compound(state)) add(states[state].initial);
                if (parallel(state)) for (int child : states[state].child_states) add(child);
                for (int id : states[state].transitions) if (transitions[id].target >= 0) {
                    int target = transitions[id].target;
                    add(states[target].kind == "history" ? states[target].default_target : target);
                }
            }
        }
        for (int state : document) if (states[state].kind != "history" && !reachable[state])
            cout << "warning: unreachable state " << states[state].name << '\n';
    }
    void dump() const {
        cout << "dump t=" << clock << '\n';
        for (int state : document) if (active[state]) cout << string(2 * states[state].depth, ' ') << states[state].name << '\n';
        for (const auto& [name, value] : variables) cout << "  var " << name << " = " << value << '\n';
        for (int state : document) if (states[state].kind == "history" && history[state]) {
            vector<string> names;
            for (int saved : *history[state]) names.push_back(states[saved].name);
            cout << "  history " << states[state].name << " = " << join(names) << '\n';
        }
        auto ordered = reservations;
        sort(ordered.begin(), ordered.end(), [](const Reservation& a, const Reservation& b) {
            return tie(a.due, a.sequence) < tie(b.due, b.sequence);
        });
        for (const auto& reservation : ordered) {
            if (reservation.transition < 0) cout << "  send " << reservation.due << ' ' << reservation.event.name << ' ' << reservation.event.value << '\n';
            else {
                const auto& transition = transitions[reservation.transition];
                cout << "  timer " << reservation.due << " after(" << transition.delay << ")@" << states[transition.source].name << '\n';
            }
        }
    }
public:
    bool define(vector<Definition>& definitions) {
        states[0].kind = "state";
        for (auto& definition : definitions) {
            const string& kind = definition.kind;
            if (kind == "var") {
                if (variables.count(definition.name)) definition.error = "duplicate variable " + definition.name;
                else variables[definition.name] = definition.value;
            } else if (kind == "state" || kind == "parallel" || kind == "final" || kind == "history") {
                if (identifiers.count(definition.name)) definition.error = "duplicate state " + definition.name;
                else if (!definition.parent.empty() && !identifiers.count(definition.parent)) definition.error = "unknown state " + definition.parent;
                else {
                    int parent = definition.parent.empty() ? 0 : identifiers.at(definition.parent);
                    if (states[parent].kind == "final" || states[parent].kind == "history") definition.error = definition.parent + " cannot have children";
                    else {
                        int id = states.size();
                        State state;
                        state.name = definition.name;
                        state.kind = kind;
                        state.parent = parent;
                        state.depth = states[parent].depth + 1;
                        state.initial_name = definition.initial;
                        state.history_kind = definition.history_kind;
                        state.default_name = definition.default_name;
                        states.push_back(move(state));
                        states[parent].children.push_back(id);
                        if (kind != "history") states[parent].child_states.push_back(id);
                        identifiers[definition.name] = id;
                        definition.state = id;
                    }
                }
            }
        }
        for (size_t id = 0; id < states.size(); ++id) if (compound(id)) {
            if (states[id].initial_name.empty()) {
                if (!states[id].child_states.empty()) states[id].initial = states[id].child_states[0];
            } else if (identifiers.count(states[id].initial_name)) states[id].initial = identifiers.at(states[id].initial_name);
        }
        for (auto& definition : definitions) if (definition.error.empty()) {
            const auto& kind = definition.kind;
            if (kind == "state" && !definition.initial.empty()) {
                if (!identifiers.count(definition.initial)) definition.error = "unknown state " + definition.initial;
                else {
                    int child = identifiers.at(definition.initial);
                    if (states[child].parent != definition.state || states[child].kind == "history")
                        definition.error = definition.initial + " is not a child of " + definition.name;
                }
            } else if (kind == "final" || kind == "history") {
                int id = definition.state, parent = states[id].parent;
                if (states[parent].kind != "state" || !compound(parent)) definition.error = definition.name + " needs a compound parent";
                else if (kind == "history" && !definition.default_name.empty()) {
                    if (!identifiers.count(definition.default_name)) definition.error = "unknown state " + definition.default_name;
                    else {
                        int target = identifiers.at(definition.default_name);
                        if (!descendant(target, parent) || states[target].kind == "history")
                            definition.error = definition.default_name + " is not a descendant of " + definition.parent;
                    }
                }
            } else if (kind == "entry" || kind == "exit" || kind == "on") {
                if (!identifiers.count(definition.name)) definition.error = "unknown state " + definition.name;
                else {
                    int source = identifiers.at(definition.name);
                    if (kind != "on" && states[source].kind == "history") definition.error = definition.name + " cannot have actions";
                    else if (kind == "on" && (states[source].kind == "history" || states[source].kind == "final")) definition.error = definition.name + " cannot have transitions";
                    else {
                        if (kind == "on") {
                            auto& transition = definition.transition;
                            definition.error = bad_reference(transition.guard.references);
                            if (definition.error.empty() && !transition.target_name.empty() && !identifiers.count(transition.target_name))
                                definition.error = "unknown state " + transition.target_name;
                            if (definition.error.empty()) definition.error = bad_actions(transition.actions);
                            if (definition.error.empty()) {
                                transition.source = source;
                                if (!transition.target_name.empty()) transition.target = identifiers.at(transition.target_name);
                                states[source].transitions.push_back(transitions.size());
                                transitions.push_back(transition);
                            }
                        } else {
                            definition.error = bad_actions(definition.actions);
                            if (definition.error.empty()) (kind == "entry" ? states[source].entry : states[source].exit).push_back(definition.actions);
                        }
                    }
                }
            }
        }
        bool valid = true;
        for (const auto& definition : definitions) if (!definition.error.empty()) {
            valid = false;
            cout << "error line " << definition.line << ": " << definition.error << '\n';
        }
        if (!valid) return false;
        for (size_t id = 1; id < states.size(); ++id) if (states[id].kind == "history")
            states[id].default_target = states[id].default_name.empty() ? states[states[id].parent].initial : identifiers.at(states[id].default_name);
        for (int child : states[0].children) visit(child);
        active.resize(states.size());
        history.resize(states.size());
        warnings();
        macrostep({"start", {}, -1});
        return true;
    }
    void script(const string& text) {
        if (halted) return;
        auto items = words(text);
        if (items[0] == "event") macrostep({"event", {items[1], items.size() == 3 ? stoll(items[2]) : 0}, -1});
        else if (items[0] == "tick") {
            Integer finish = clock + stoll(items[1]);
            while (!halted) {
                auto first = min_element(reservations.begin(), reservations.end(), [](const Reservation& a, const Reservation& b) {
                    return tie(a.due, a.sequence) < tie(b.due, b.sequence);
                });
                if (first == reservations.end() || first->due > finish) break;
                Reservation next = *first;
                reservations.erase(first);
                clock = next.due;
                if (next.transition >= 0) macrostep({"timer", {}, next.transition});
                else macrostep({"event", next.event, -1});
            }
            if (!halted) clock = finish;
        } else if (items[0] == "set") {
            if (!variables.count(items[1])) cout << "error: unknown variable " << items[1] << '\n';
            else variables[items[1]] = stoll(items[2]);
        } else if (items[0] == "trace") tracing = items[1] == "on";
        else if (items[0] == "eval") {
            string original = text.substr(5);
            auto parsed = expression(original);
            string error = bad_reference(parsed.references);
            if (!error.empty()) cout << "error: " << error << '\n';
            else {
                current_value = 0;
                try {
                    Integer value = evaluate(parsed.tree);
                    cout << original << " -> " << value << '\n';
                }
                catch (const EvaluationError&) {
                    cout << "error: division by zero\n";
                }
            }
        } else if (items[0] == "dump") dump();
    }
    void finish() const {
        cout << "end t=" << clock << " macrosteps=" << macrosteps << " microsteps=" << microsteps << '\n';
        for (int id : document) if (states[id].kind != "history") {
            const State& state = states[id];
            cout << "  " << state.name << " entered=" << state.entered << " taken=" << state.taken << " time="
                 << state.dwell + (active[id] ? clock - state.entry_time : 0) << '\n';
        }
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int count;
    cin >> count;
    string line;
    getline(cin, line);
    int line_number = 1;
    while (count--) {
        getline(cin, line);
        ++line_number;
        cout << "chart " << line.substr(6) << '\n';
        vector<Definition> definitions;
        while (getline(cin, line)) {
            ++line_number;
            if (line == "RUN") break;
            definitions.push_back(parse_definition(line, line_number));
        }
        Chart chart;
        bool valid = chart.define(definitions);
        while (getline(cin, line)) {
            ++line_number;
            if (line == "END") break;
            if (valid) chart.script(line);
        }
        if (valid) chart.finish();
    }
}
