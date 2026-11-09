#include <algorithm>
#include <cstdint>
#include <functional>
#include <iomanip>
#include <iostream>
#include <map>
#include <memory>
#include <optional>
#include <queue>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <tuple>
#include <utility>
#include <vector>
using namespace std;
using States = set<int>;
using Count = int64_t;
vector<string> split(const string& text, char separator) {
    vector<string> result;
    size_t start = 0;
    for (;;) {
        size_t end = text.find(separator, start);
        result.push_back(text.substr(start, end == string::npos ? end : end - start));
        if (end == string::npos) return result;
        start = end + 1;
    }
}
string join(const vector<string>& parts, const string& separator) {
    string result;
    for (const string& part : parts) {
        if (!result.empty()) result += separator;
        result += part;
    }
    return result;
}
string printedWord(const string& word) {
    return word.empty() ? "e" : word;
}
struct Automaton {
    bool dfa = false;
    string alphabet;
    vector<string> names;
    int start = 0;
    States accepting;
    vector<map<char, States>> transitions;
    int addState(string name) {
        int index = names.size();
        names.push_back(move(name));
        transitions.emplace_back();
        return index;
    }
    void series(int count, char prefix) {
        for (int i = 0; i < count; ++i) addState(string(1, prefix) + to_string(i));
    }
    void edge(int from, char symbol, int to) {
        transitions[from][symbol].insert(to);
    }
    const States& destinations(int state, char symbol) const {
        static const States empty;
        auto found = transitions[state].find(symbol);
        return found == transitions[state].end() ? empty : found->second;
    }
    int delta(int state, char symbol) const {
        return *destinations(state, symbol).begin();
    }
    States closure(States states) const {
        vector<int> pending(states.begin(), states.end());
        for (size_t i = 0; i < pending.size(); ++i) for (int q : destinations(pending[i], 'e')) {
            if (states.insert(q).second) pending.push_back(q);
        }
        return states;
    }
    States initial() const {
        return closure({start});
    }
    States moveOn(const States& states, char symbol) const {
        States result;
        for (int p : states) {
            const auto& qs = destinations(p, symbol);
            result.insert(qs.begin(), qs.end());
        }
        return closure(move(result));
    }
    bool accepts(const States& states) const {
        for (int p : states) if (accepting.count(p)) return true;
        return false;
    }
    string list(const States& states) const {
        vector<string> parts;
        for (int p : states) parts.push_back(names[p]);
        return parts.empty() ? "none" : join(parts, ",");
    }
    string setText(const States& states) const {
        return states.empty() ? "{}" : "{" + list(states) + "}";
    }
    int transitionCount(char only = 0) const {
        int result = 0;
        for (const auto& row : transitions) for (const auto& edge : row) if (!only || edge.first == only) result += edge.second.size();
        return result;
    }
    string summary(const string& name) const {
        return string(dfa ? "DFA " : "NFA ") + name + ": alphabet=" + alphabet + " states=" + to_string(names.size())
            + " accepting=" + to_string(accepting.size()) + " transitions=" + to_string(transitionCount());
    }
};
pair<Automaton, vector<States>> determinize(const Automaton& source) {
    Automaton result;
    result.dfa = true;
    result.alphabet = source.alphabet;
    vector<States> subsets{source.initial()};
    map<States, int> indices{{subsets[0], 0}};
    result.addState("D0");
    for (size_t i = 0; i < subsets.size(); ++i) {
        if (source.accepts(subsets[i])) result.accepting.insert(i);
        for (char c : source.alphabet) {
            States destination = source.moveOn(subsets[i], c);
            auto found = indices.find(destination);
            int index;
            if (found == indices.end()) {
                index = subsets.size();
                indices[destination] = index;
                subsets.push_back(destination);
                result.addState("D" + to_string(index));
            } else index = found->second;
            result.edge(i, c, index);
        }
    }
    return {move(result), move(subsets)};
}
States graphReach(const Automaton& a, bool backwards) {
    vector<States> adjacency(a.names.size());
    for (size_t p = 0; p < a.names.size(); ++p) for (const auto& edge : a.transitions[p]) for (int q : edge.second) {
        if (backwards) adjacency[q].insert(p);
        else adjacency[p].insert(q);
    }
    States result = backwards ? a.accepting : States{a.start};
    vector<int> pending(result.begin(), result.end());
    for (size_t i = 0; i < pending.size(); ++i) for (int q : adjacency[pending[i]]) {
        if (result.insert(q).second) pending.push_back(q);
    }
    return result;
}
pair<Automaton, vector<string>> minimize(const Automaton& a) {
    States reachable = graphReach(a, false), unreachable, yes, no;
    for (size_t p = 0; p < a.names.size(); ++p) {
        if (!reachable.count(p)) unreachable.insert(p);
        else (a.accepting.count(p) ? yes : no).insert(p);
    }
    vector<string> details{"  unreachable: " + a.list(unreachable)};
    vector<States> blocks;
    if (!yes.empty()) blocks.push_back(yes);
    if (!no.empty()) blocks.push_back(no);
    auto orderBlocks = [](vector<States>& bs) {
        sort(bs.begin(), bs.end(), [](const States& x, const States& y) {
            return *x.begin() < *y.begin();
        });
    };
    auto showBlocks = [&](const vector<States>& bs) {
        vector<string> parts;
        for (const States& block : bs) parts.push_back(a.setText(block));
        return join(parts, " ");
    };
    orderBlocks(blocks);
    details.push_back("  round 0: " + showBlocks(blocks));
    vector<int> membership(a.names.size());
    for (int round = 1;; ++round) {
        for (size_t i = 0; i < blocks.size(); ++i) for (int p : blocks[i]) membership[p] = i;
        vector<States> refined;
        for (const States& block : blocks) {
            map<vector<int>, States> groups;
            for (int p : block) {
                vector<int> signature;
                for (char c : a.alphabet) signature.push_back(membership[a.delta(p, c)]);
                groups[signature].insert(p);
            }
            for (const auto& group : groups) refined.push_back(group.second);
        }
        if (refined.size() == blocks.size()) break;
        orderBlocks(refined);
        blocks = move(refined);
        details.push_back("  round " + to_string(round) + ": " + showBlocks(blocks));
    }
    for (size_t i = 0; i < blocks.size(); ++i) for (int p : blocks[i]) membership[p] = i;
    Automaton result;
    result.dfa = true;
    result.alphabet = a.alphabet;
    vector<int> sequence{membership[a.start]};
    map<int, int> indices{{sequence[0], 0}};
    result.addState("M0");
    for (size_t i = 0; i < sequence.size(); ++i) {
        const States block = blocks[sequence[i]];
        int representative = *block.begin();
        if (a.accepting.count(representative)) result.accepting.insert(i);
        for (char c : a.alphabet) {
            int destination = membership[a.delta(representative, c)];
            auto found = indices.find(destination);
            int index;
            if (found == indices.end()) {
                index = sequence.size();
                indices[destination] = index;
                sequence.push_back(destination);
                result.addState("M" + to_string(index));
            } else index = found->second;
            result.edge(i, c, index);
        }
        details.push_back("  M" + to_string(i) + " = " + a.setText(block));
    }
    return {move(result), move(details)};
}
struct Language {
    bool infinite = false;
    Count count = 0;
    optional<string> smallest;
};
Language inspectLanguage(const Automaton& input, bool needCount = false) {
    Automaton a = determinize(input).first;
    Language result;
    vector<bool> seen(a.names.size());
    vector<pair<int, string>> pending{{0, ""}};
    seen[0] = true;
    for (size_t i = 0; i < pending.size(); ++i) {
        int p = pending[i].first;
        string w = pending[i].second;
        if (!result.smallest && a.accepting.count(p)) result.smallest = w;
        for (char c : a.alphabet) {
            int q = a.delta(p, c);
            if (!seen[q]) {
                seen[q] = true;
                pending.emplace_back(q, w + c);
            }
        }
    }
    if (!result.smallest) return result;
    States live = graphReach(a, true);
    vector<int> color(a.names.size());
    vector<Count> count(a.names.size());
    function<Count(int)> visit = [&](int p) -> Count {
        if (!live.count(p)) return 0;
        if (color[p] == 1) {
            result.infinite = true;
            return 0;
        }
        if (color[p] == 2) return count[p];
        color[p] = 1;
        Count total = needCount ? a.accepting.count(p) : 0;
        for (char c : a.alphabet) {
            Count suffixes = visit(a.delta(p, c));
            if (needCount && !result.infinite) total += suffixes;
        }
        color[p] = 2;
        return count[p] = total;
    };
    result.count = visit(0);
    return result;
}
struct RegexNode {
    char op;
    vector<shared_ptr<RegexNode>> children;
};
using Regex = shared_ptr<RegexNode>;
class RegexParser {
    const string& text;
    size_t index = 0;
    char next() const {
        return index < text.size() ? text[index] : '\0';
    }
    [[noreturn]] void error() const {
        throw runtime_error("syntax error at " + to_string(index + 1));
    }
    bool atomStart(char c) const {
        return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '(';
    }
    Regex atom() {
        char c = next();
        if (c == '(') {
            ++index;
            auto result = alternation();
            if (next() != ')') error();
            ++index;
            return result;
        }
        if (!atomStart(c)) error();
        ++index;
        return make_shared<RegexNode>(RegexNode{c, {}});
    }
    Regex factor() {
        auto result = atom();
        while (next() == '*' || next() == '+' || next() == '?') {
            char op = text[index++];
            result = make_shared<RegexNode>(RegexNode{op, {result}});
        }
        return result;
    }
    Regex concatenation() {
        vector<Regex> parts{factor()};
        while (atomStart(next())) parts.push_back(factor());
        return parts.size() == 1 ? parts[0] : make_shared<RegexNode>(RegexNode{'.', move(parts)});
    }
    Regex alternation() {
        vector<Regex> parts{concatenation()};
        while (next() == '|') {
            ++index;
            parts.push_back(concatenation());
        }
        return parts.size() == 1 ? parts[0] : make_shared<RegexNode>(RegexNode{'|', move(parts)});
    }
public:
    explicit RegexParser(const string& s) : text(s) {
    }
    Regex parse() {
        auto result = alternation();
        if (index != text.size()) error();
        return result;
    }
};
Automaton thompson(const Regex& root, const string& alphabet) {
    Automaton a;
    a.alphabet = alphabet;
    auto state = [&]() {
        return a.addState("N" + to_string(a.names.size()));
    };
    function<pair<int, int>(const Regex&)> build = [&](const Regex& r) -> pair<int, int> {
        if (r->children.empty()) {
            int s = state(), f = state();
            a.edge(s, r->op, f);
            return {s, f};
        }
        if (r->op == '.') {
            auto first = build(r->children[0]);
            int last = first.second;
            for (size_t i = 1; i < r->children.size(); ++i) {
                auto next = build(r->children[i]);
                a.edge(last, 'e', next.first);
                last = next.second;
            }
            return {first.first, last};
        }
        int s = state();
        vector<pair<int, int>> parts;
        for (const Regex& child : r->children) parts.push_back(build(child));
        int f = state();
        for (auto part : parts) {
            a.edge(s, 'e', part.first);
            a.edge(part.second, 'e', f);
        }
        if (r->op != '|') {
            if (r->op != '+') a.edge(s, 'e', f);
            if (r->op != '?') a.edge(parts[0].second, 'e', parts[0].first);
        }
        return {s, f};
    };
    auto ends = build(root);
    a.start = ends.first;
    a.accepting.insert(ends.second);
    return a;
}
class Toolkit {
    vector<pair<string, Automaton>> table;
    int indexOf(const string& name) const {
        for (size_t i = 0; i < table.size(); ++i) if (table[i].first == name) return i;
        return -1;
    }
    void add(const string& name, Automaton a, const vector<string>& details, ostream& out) {
        out << a.summary(name) << '\n';
        for (const string& detail : details) out << detail << '\n';
        table.emplace_back(name, move(a));
    }
    int stateIndex(const Automaton& a, const string& name) const {
        auto found = find(a.names.begin(), a.names.end(), name);
        if (found == a.names.end()) throw runtime_error("unknown state " + name);
        return found - a.names.begin();
    }
    void definition(const string& command, const vector<string>& args, ostream& out) {
        if (args.size() < 5) throw runtime_error("wrong number of arguments");
        if (indexOf(args[0]) >= 0) throw runtime_error(args[0] + " already exists");
        Automaton a;
        a.dfa = command == "DFA";
        a.alphabet = args[2];
        sort(a.alphabet.begin(), a.alphabet.end());
        for (const string& name : split(args[1], ',')) {
            if (find(a.names.begin(), a.names.end(), name) != a.names.end()) throw runtime_error("duplicate state " + name);
            a.addState(name);
        }
        a.start = stateIndex(a, args[3]);
        if (args[4] != "-") for (const string& name : split(args[4], ',')) {
            int index = stateIndex(a, name);
            if (!a.accepting.insert(index).second) throw runtime_error("duplicate state " + name);
        }
        for (size_t i = 5; i < args.size(); ++i) {
            auto parts = split(args[i], ':');
            int p = stateIndex(a, parts[0]);
            char c = parts[1][0];
            if (c == 'e' && a.dfa) throw runtime_error("epsilon transition in DFA");
            if (c != 'e' && a.alphabet.find(c) == string::npos) throw runtime_error("unknown symbol " + string(1, c));
            int q = stateIndex(a, parts[2]);
            const auto& previous = a.destinations(p, c);
            if (previous.count(q)) throw runtime_error("duplicate transition " + args[i]);
            if (a.dfa && !previous.empty()) throw runtime_error("conflicting transition " + args[i]);
            a.edge(p, c, q);
        }
        if (a.dfa) for (size_t p = 0; p < a.names.size(); ++p) for (char c : a.alphabet) {
            if (a.destinations(p, c).empty()) throw runtime_error("missing transition " + a.names[p] + ":" + c);
        }
        add(args[0], move(a), {}, out);
    }
public:
    void execute(const string& line, ostream& out) {
        if (line[0] == '#') return;
        auto tokens = split(line, ' ');
        string command = tokens[0];
        vector<string> args(tokens.begin() + 1, tokens.end());
        const map<string, vector<char>> roles = {
            {"ACCEPT", {'r','o'}}, {"CLOSURE", {'r','o'}}, {"ENUM", {'r','o'}}, {"COUNT", {'r','o'}},
            {"TODFA", {'r','n'}}, {"EPSFREE", {'r','n'}}, {"REVERSE", {'r','n'}}, {"STAR", {'r','n'}},
            {"MINIMIZE", {'d','n'}}, {"COMPLEMENT", {'d','n'}}, {"EQUIV", {'r','r'}},
            {"UNION", {'d','d','n'}}, {"INTERSECT", {'d','d','n'}}, {"DIFF", {'d','d','n'}}, {"CONCAT", {'r','r','n'}},
            {"EMPTY", {'r'}}, {"FINITE", {'r'}}, {"INFO", {'r'}}, {"TABLE", {'r'}}, {"SHOW", {'r'}},
            {"DELETE", {'r'}}, {"SYNC", {'d'}}, {"LIST", {}}
        };
        if (command == "DFA" || command == "NFA") {
            definition(command, args, out);
            return;
        }
        if (command == "REGEX") {
            if (args.size() != 3) throw runtime_error("wrong number of arguments");
            if (indexOf(args[0]) >= 0) throw runtime_error(args[0] + " already exists");
            string alphabet = args[1];
            sort(alphabet.begin(), alphabet.end());
            for (char c : args[2]) if (((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) && c != 'e' && alphabet.find(c) == string::npos) {
                throw runtime_error("unknown symbol " + string(1, c));
            }
            auto expression = RegexParser(args[2]).parse();
            add(args[0], thompson(expression, alphabet), {}, out);
            return;
        }
        auto found = roles.find(command);
        if (found == roles.end()) throw runtime_error("unknown command " + command);
        if (args.size() != found->second.size()) throw runtime_error("wrong number of arguments");
        const auto& rs = found->second;
        for (size_t i = 0; i < rs.size(); ++i) if ((rs[i] == 'r' || rs[i] == 'd') && indexOf(args[i]) < 0) {
            throw runtime_error("unknown automaton " + args[i]);
        }
        for (size_t i = 0; i < rs.size(); ++i) if (rs[i] == 'n' && indexOf(args[i]) >= 0) throw runtime_error(args[i] + " already exists");
        for (size_t i = 0; i < rs.size(); ++i) if (rs[i] == 'd' && !table[indexOf(args[i])].second.dfa) throw runtime_error(args[i] + " is not a DFA");
        if (command == "LIST") {
            if (table.empty()) out << "(none)\n";
            for (const auto& entry : table) out << entry.second.summary(entry.first) << '\n';
            return;
        }
        Automaton a = table[indexOf(args[0])].second;
        Automaton b;
        bool binary = command == "EQUIV" || command == "UNION" || command == "INTERSECT" || command == "DIFF" || command == "CONCAT";
        if (binary) {
            b = table[indexOf(args[1])].second;
            if (a.alphabet != b.alphabet) throw runtime_error("alphabets differ");
        }
        if (command == "ACCEPT") {
            string w = args[1] == "e" ? "" : args[1];
            for (char c : w) if (a.alphabet.find(c) == string::npos) throw runtime_error("unknown symbol " + string(1, c));
            States current = a.initial();
            auto text = [&](const States& s) {
                return a.dfa ? a.names[*s.begin()] : a.setText(s);
            };
            string trace = text(current);
            for (char c : w) {
                current = a.moveOn(current, c);
                trace += " -" + string(1, c) + "-> " + text(current);
            }
            out << (a.accepts(current) ? "ACCEPT " : "REJECT ") << trace << '\n';
        } else if (command == "CLOSURE") {
            States states;
            for (const string& name : split(args[1], ',')) states.insert(stateIndex(a, name));
            out << a.setText(a.closure(move(states))) << '\n';
        } else if (command == "TODFA") {
            auto converted = determinize(a);
            vector<string> details;
            for (size_t i = 0; i < converted.second.size(); ++i) details.push_back("  D" + to_string(i) + " = " + a.setText(converted.second[i]));
            add(args[1], move(converted.first), details, out);
        } else if (command == "MINIMIZE") {
            auto minimized = minimize(a);
            add(args[1], move(minimized.first), minimized.second, out);
        } else if (command == "EPSFREE") {
            Automaton result;
            result.alphabet = a.alphabet;
            for (const string& name : a.names) result.addState(name);
            result.start = a.start;
            for (size_t p = 0; p < a.names.size(); ++p) {
                auto closed = a.closure({static_cast<int>(p)});
                if (a.accepts(closed)) result.accepting.insert(p);
                for (char c : a.alphabet) for (int q : a.moveOn(closed, c)) result.edge(p, c, q);
            }
            add(args[1], move(result), {}, out);
        } else if (command == "COMPLEMENT") {
            States accepting;
            for (size_t p = 0; p < a.names.size(); ++p) if (!a.accepting.count(p)) accepting.insert(p);
            a.accepting = move(accepting);
            add(args[1], move(a), {}, out);
        } else if (command == "UNION" || command == "INTERSECT" || command == "DIFF") {
            Automaton result;
            result.dfa = true;
            result.alphabet = a.alphabet;
            vector<pair<int, int>> pairs{{a.start, b.start}};
            map<pair<int, int>, int> indices{{pairs[0], 0}};
            result.addState("P0");
            vector<string> details;
            for (size_t i = 0; i < pairs.size(); ++i) {
                auto [p, q] = pairs[i];
                bool ap = a.accepting.count(p), bq = b.accepting.count(q);
                if (command == "UNION" ? ap || bq : command == "INTERSECT" ? ap && bq : ap && !bq) result.accepting.insert(i);
                for (char c : a.alphabet) {
                    auto destination = make_pair(a.delta(p, c), b.delta(q, c));
                    auto present = indices.find(destination);
                    int index;
                    if (present == indices.end()) {
                        index = pairs.size();
                        indices[destination] = index;
                        pairs.push_back(destination);
                        result.addState("P" + to_string(index));
                    } else index = present->second;
                    result.edge(i, c, index);
                }
                details.push_back("  P" + to_string(i) + " = (" + a.names[p] + "," + b.names[q] + ")");
            }
            add(args[2], move(result), details, out);
        } else if (command == "EQUIV") {
            a = determinize(a).first;
            b = determinize(b).first;
            vector<tuple<int, int, string>> pending{{0, 0, ""}};
            set<pair<int, int>> seen{{0, 0}};
            bool equivalent = true;
            for (size_t i = 0; i < pending.size(); ++i) {
                auto [p, q, w] = pending[i];
                if (a.accepting.count(p) != b.accepting.count(q)) {
                    out << "NOT EQUIVALENT: " << printedWord(w) << " is accepted only by " << (a.accepting.count(p) ? args[0] : args[1]) << '\n';
                    equivalent = false;
                    break;
                }
                for (char c : a.alphabet) {
                    auto destination = make_pair(a.delta(p, c), b.delta(q, c));
                    if (seen.insert(destination).second) pending.emplace_back(destination.first, destination.second, w + c);
                }
            }
            if (equivalent) out << "EQUIVALENT\n";
        } else if (command == "REVERSE" || command == "CONCAT" || command == "STAR") {
            Automaton result;
            result.alphabet = a.alphabet;
            int offset = command == "CONCAT" ? 0 : 1;
            result.series(a.names.size() + (command == "CONCAT" ? b.names.size() : 1), 'N');
            for (size_t p = 0; p < a.names.size(); ++p) for (const auto& edge : a.transitions[p]) for (int q : edge.second) {
                if (command == "REVERSE") result.edge(q + 1, edge.first, p + 1);
                else result.edge(p + offset, edge.first, q + offset);
            }
            if (command == "REVERSE") {
                for (int p : a.accepting) result.edge(0, 'e', p + 1);
                result.accepting.insert(a.start + 1);
            } else if (command == "STAR") {
                result.edge(0, 'e', a.start + 1);
                result.accepting.insert(0);
                for (int p : a.accepting) {
                    result.edge(p + 1, 'e', a.start + 1);
                    result.accepting.insert(p + 1);
                }
            } else {
                int m = a.names.size();
                result.start = a.start;
                for (size_t p = 0; p < b.names.size(); ++p) for (const auto& edge : b.transitions[p]) for (int q : edge.second) result.edge(p + m, edge.first, q + m);
                for (int p : a.accepting) result.edge(p, 'e', b.start + m);
                for (int q : b.accepting) result.accepting.insert(q + m);
            }
            add(args.back(), move(result), {}, out);
        } else if (command == "ENUM" || command == "COUNT") {
            int length = stoi(args[1]);
            a = determinize(a).first;
            if (command == "COUNT") {
                vector<Count> counts(a.names.size());
                counts[0] = 1;
                for (int i = 0; i < length; ++i) {
                    vector<Count> next(a.names.size());
                    for (size_t p = 0; p < counts.size(); ++p) for (char c : a.alphabet) next[a.delta(p, c)] += counts[p];
                    counts = move(next);
                }
                Count total = 0;
                for (int p : a.accepting) total += counts[p];
                out << total << '\n';
            } else {
                vector<pair<int, string>> pending{{0, ""}};
                vector<string> first;
                Count total = 0;
                for (size_t i = 0; i < pending.size(); ++i) {
                    auto [p, w] = pending[i];
                    if (a.accepting.count(p)) {
                        ++total;
                        if (first.size() < 50) first.push_back(printedWord(w));
                    }
                    if (static_cast<int>(w.size()) < length) for (char c : a.alphabet) pending.emplace_back(a.delta(p, c), w + c);
                }
                out << total;
                for (const string& w : first) out << ' ' << w;
                if (total > 50) out << " ...";
                out << '\n';
            }
        } else if (command == "EMPTY" || command == "FINITE") {
            auto language = inspectLanguage(a, command == "FINITE");
            if (command == "EMPTY") out << (language.smallest ? "NOT EMPTY " + printedWord(*language.smallest) : "EMPTY") << '\n';
            else if (language.infinite) out << "INFINITE\n";
            else out << "FINITE " << language.count << '\n';
        } else if (command == "SYNC") {
            States all;
            for (size_t p = 0; p < a.names.size(); ++p) all.insert(p);
            vector<pair<States, string>> pending{{all, ""}};
            set<States> seen{all};
            bool foundWord = false;
            for (size_t i = 0; i < pending.size(); ++i) {
                auto [states, w] = pending[i];
                if (states.size() == 1) {
                    out << "SYNCHRONIZING " << printedWord(w) << " -> " << a.names[*states.begin()] << '\n';
                    foundWord = true;
                    break;
                }
                for (char c : a.alphabet) {
                    States destination;
                    for (int p : states) destination.insert(a.delta(p, c));
                    if (seen.insert(destination).second) pending.emplace_back(destination, w + c);
                }
            }
            if (!foundWord) out << "NOT SYNCHRONIZING\n";
        } else if (command == "INFO") {
            auto language = inspectLanguage(a);
            bool deterministic = !a.transitionCount('e'), complete = true;
            for (size_t p = 0; p < a.names.size(); ++p) for (char c : a.alphabet) {
                if (a.destinations(p, c).size() > 1) deterministic = false;
                if (a.destinations(p, c).empty()) complete = false;
            }
            auto dfa = determinize(a).first;
            auto minimal = minimize(dfa).first;
            out << a.summary(args[0]) << "\n  epsilon transitions: " << a.transitionCount('e')
                << "\n  reachable: " << a.list(graphReach(a, false)) << "\n  live: " << a.list(graphReach(a, true))
                << "\n  deterministic: " << (deterministic ? "yes" : "no") << "\n  complete: " << (complete ? "yes" : "no")
                << "\n  language: " << (!language.smallest ? "empty" : language.infinite ? "infinite" : "finite")
                << "\n  minimal DFA states: " << minimal.names.size() << '\n';
        } else if (command == "SHOW") {
            out << (a.dfa ? "DFA " : "NFA ") << args[0] << ' ' << join(a.names, ",") << ' ' << a.alphabet << ' ' << a.names[a.start] << ' '
                << (a.accepting.empty() ? "-" : a.list(a.accepting));
            string symbols = a.alphabet + 'e';
            for (size_t p = 0; p < a.names.size(); ++p) for (char c : symbols) for (int q : a.destinations(p, c)) {
                out << ' ' << a.names[p] << ':' << c << ':' << a.names[q];
            }
            out << '\n';
        } else if (command == "TABLE") {
            string symbols = a.alphabet;
            if (!a.dfa && a.transitionCount('e')) symbols += 'e';
            vector<vector<string>> rows(1, vector<string>{""});
            for (char c : symbols) rows[0].push_back(string(1, c));
            for (size_t p = 0; p < a.names.size(); ++p) {
                vector<string> row{string(static_cast<int>(p) == a.start ? "->" : "  ") + (a.accepting.count(p) ? "*" : " ") + a.names[p]};
                for (char c : symbols) {
                    const States& destinations = a.destinations(p, c);
                    row.push_back(a.dfa ? a.names[*destinations.begin()] : destinations.empty() ? "-" : a.setText(destinations));
                }
                rows.push_back(move(row));
            }
            vector<size_t> widths(symbols.size() + 1);
            for (const auto& row : rows) for (size_t i = 0; i < row.size(); ++i) widths[i] = max(widths[i], row[i].size());
            for (const auto& row : rows) {
                string text;
                for (size_t i = 0; i < row.size(); ++i) {
                    if (i) text += "  ";
                    text += row[i] + string(widths[i] - row[i].size(), ' ');
                }
                while (!text.empty() && text.back() == ' ') text.pop_back();
                out << text << '\n';
            }
        } else if (command == "DELETE") {
            table.erase(table.begin() + indexOf(args[0]));
            out << "deleted " << args[0] << '\n';
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
    Toolkit toolkit;
    while (count-- && getline(cin, line)) {
        try {
            ostringstream output;
            toolkit.execute(line, output);
            cout << output.str();
        } catch (const runtime_error& error) {
            cout << "error: " << error.what() << '\n';
        }
    }
}
