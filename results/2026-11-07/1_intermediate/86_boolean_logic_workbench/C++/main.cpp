#include <algorithm>
#include <functional>
#include <iostream>
#include <iterator>
#include <map>
#include <memory>
#include <numeric>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <tuple>
#include <utility>
#include <vector>
using namespace std;

struct Node;
using Formula = shared_ptr<const Node>;
struct Node {
    string op;
    Formula left, right;
};
Formula leaf(string value) {
    return make_shared<Node>(Node{move(value), {}, {}});
}
Formula make(string op, Formula left, Formula right = {}) {
    return make_shared<Node>(Node{move(op), move(left), move(right)});
}
bool variable(char c) {
    return c >= 'A' && c <= 'Z';
}
bool lower(char c) {
    return c >= 'a' && c <= 'z';
}
bool digit(char c) {
    return c >= '0' && c <= '9';
}
bool validName(const string& name) {
    return !name.empty() && name.size() <= 8 && lower(name[0])
        && all_of(name.begin(), name.end(), [](char c) {
            return lower(c) || digit(c);
        });
}
vector<string> words(const string& text) {
    istringstream input(text);
    vector<string> result;
    string s;
    while (input >> s) result.push_back(s);
    return result;
}
string join(const vector<string>& parts, const string& separator) {
    string result;
    for (const string& s : parts) {
        if (!result.empty()) result += separator;
        result += s;
    }
    return result;
}
int precedence(const string& op) {
    if (op == "<->") return 1;
    if (op == "->") return 2;
    if (op == "|") return 3;
    if (op == "^") return 4;
    if (op == "&") return 5;
    return op == "~" ? 6 : 7;
}
string notation(const Formula& f) {
    if (!f->left) return f->op;
    if (f->op == "~") {
        string child = notation(f->left);
        return "~" + (f->left->right ? "(" + child + ")" : child);
    }
    string a = notation(f->left), b = notation(f->right);
    if (f->left->right && (precedence(f->left->op) < precedence(f->op)
            || (f->left->op == "->" && f->op == "->"))) a = "(" + a + ")";
    if (f->right->right && (precedence(f->right->op) < precedence(f->op)
            || (f->right->op == f->op && f->op != "->"))) b = "(" + b + ")";
    return a + " " + f->op + " " + b;
}
bool equalTree(const Formula& a, const Formula& b) {
    if (a == b) return true;
    if (!a || !b || a->op != b->op) return false;
    return equalTree(a->left, b->left) && equalTree(a->right, b->right);
}
Formula negate(const Formula& f) {
    if (f->op == "0") return leaf("1");
    if (f->op == "1") return leaf("0");
    if (f->op == "~") return f->left;
    return make("~", f);
}
Formula binary(const string& op, const Formula& a, const Formula& b) {
    bool same = equalTree(a, b);
    bool complement = (a->op == "~" && equalTree(a->left, b)) || (b->op == "~" && equalTree(b->left, a));
    if (op == "&") {
        if (a->op == "0" || b->op == "0") return leaf("0");
        if (a->op == "1") return b;
        if (b->op == "1" || same) return a;
        if (complement) return leaf("0");
    } else if (op == "|") {
        if (a->op == "1" || b->op == "1") return leaf("1");
        if (a->op == "0") return b;
        if (b->op == "0" || same) return a;
        if (complement) return leaf("1");
    } else if (op == "^") {
        if (a->op == "0") return b;
        if (b->op == "0") return a;
        if (a->op == "1") return negate(b);
        if (b->op == "1") return negate(a);
        if (same) return leaf("0");
        if (complement) return leaf("1");
    } else if (op == "->") {
        if (a->op == "0" || b->op == "1") return leaf("1");
        if (a->op == "1") return b;
        if (b->op == "0") return negate(a);
        if (same) return leaf("1");
        if (complement) return b;
    } else if (op == "<->") {
        if (a->op == "1") return b;
        if (b->op == "1") return a;
        if (a->op == "0") return negate(b);
        if (b->op == "0") return negate(a);
        if (same) return leaf("1");
        if (complement) return leaf("0");
    }
    return make(op, a, b);
}
Formula simplify(const Formula& f, const map<char, int>& assignment = {}) {
    if (!f->left) {
        auto it = assignment.find(f->op[0]);
        return it == assignment.end() ? f : leaf(to_string(it->second));
    }
    auto a = simplify(f->left, assignment);
    if (f->op == "~") return negate(a);
    auto b = simplify(f->right, assignment);
    return binary(f->op, a, b);
}
Formula nnf(const Formula& f, bool positive, map<pair<Formula, bool>, Formula>& memo) {
    pair<Formula, bool> key{f, positive};
    auto cached = memo.find(key);
    if (cached != memo.end()) return cached->second;
    const string& op = f->op;
    Formula result;
    if (!f->left) {
        result = op == "0" || op == "1"
            ? leaf(to_string((op == "1") == positive)) : positive ? f : make("~", f);
    } else if (op == "~") {
        result = nnf(f->left, !positive, memo);
    } else if (op == "&" || op == "|") {
        auto a = nnf(f->left, positive, memo), b = nnf(f->right, positive, memo);
        result = make(positive ? op : (op == "&" ? "|" : "&"), a, b);
    } else if (op == "->") {
        auto a = nnf(f->left, !positive, memo), b = nnf(f->right, positive, memo);
        result = make(positive ? "|" : "&", a, b);
    } else {
        bool agreement = positive == (op == "<->");
        auto ap = nnf(f->left, true, memo), an = nnf(f->left, false, memo);
        auto bp = nnf(f->right, true, memo), bn = nnf(f->right, false, memo);
        result = make("|", make("&", ap, agreement ? bp : bn), make("&", an, agreement ? bn : bp));
    }
    memo.emplace(key, result);
    return result;
}
Formula nnf(const Formula& f) {
    map<pair<Formula, bool>, Formula> memo;
    return nnf(f, true, memo);
}
Formula dual(const Formula& f) {
    if (!f->left) return f->op == "0" ? leaf("1") : f->op == "1" ? leaf("0") : f;
    auto a = dual(f->left);
    if (f->op == "~") return make("~", a);
    auto b = dual(f->right);
    if (f->op == "->") return make("&", make("~", a), b);
    string op = f->op == "&" ? "|" : f->op == "|" ? "&" : f->op == "^" ? "<->" : "^";
    return make(op, a, b);
}
void collect(const Formula& f, set<char>& vars) {
    if (!f->left) {
        if (variable(f->op[0])) vars.insert(f->op[0]);
    } else {
        collect(f->left, vars);
        if (f->right) collect(f->right, vars);
    }
}
pair<int, int> dimensions(const Formula& f) {
    if (!f->left) return {1, 1};
    auto a = dimensions(f->left);
    if (!f->right) return {a.first + 1, a.second + 1};
    auto b = dimensions(f->right);
    return {a.first + b.first + 1, max(a.second, b.second) + 1};
}
int evaluate(const Formula& f, const map<char, int>& assignment) {
    if (!f->left) return variable(f->op[0]) ? assignment.at(f->op[0]) : f->op == "1";
    int a = evaluate(f->left, assignment);
    if (f->op == "~") return !a;
    int b = evaluate(f->right, assignment);
    if (f->op == "&") return a & b;
    if (f->op == "^") return a ^ b;
    if (f->op == "|") return a | b;
    if (f->op == "->") return !a || b;
    return a == b;
}
struct Token {
    string text;
    int position;
};
class Parser {
    vector<Token> tokens;
    size_t index = 0;
    int endPosition;
    const map<string, Formula>& names;
    [[noreturn]] void error() const {
        if (index == tokens.size()) throw runtime_error("unexpected end of formula at " + to_string(endPosition));
        throw runtime_error("unexpected '" + tokens[index].text + "' at " + to_string(tokens[index].position));
    }
    Formula unary() {
        if (index == tokens.size()) error();
        Token token = tokens[index];
        if (token.text == "~") {
            ++index;
            return make("~", unary());
        }
        if (token.text == "(") {
            ++index;
            auto result = expression(1);
            if (index == tokens.size() || tokens[index].text != ")") error();
            ++index;
            return result;
        }
        if (variable(token.text[0]) || token.text == "0" || token.text == "1") {
            ++index;
            return leaf(token.text);
        }
        if (lower(token.text[0])) {
            auto found = names.find(token.text);
            if (found == names.end()) throw runtime_error("undefined name '" + token.text + "' at " + to_string(token.position));
            ++index;
            return found->second;
        }
        error();
    }
    Formula expression(int level) {
        if (level == 6) return unary();
        auto result = expression(level + 1);
        while (index < tokens.size() && precedence(tokens[index].text) == level) {
            string op = tokens[index++].text;
            auto right = expression(op == "->" ? level : level + 1);
            result = make(op, result, right);
        }
        return result;
    }
public:
    Parser(const string& text, int start, const map<string, Formula>& definitions)
        : endPosition(start + static_cast<int>(text.size())), names(definitions) {
        for (size_t i = 0; i < text.size();) {
            if (text[i] == ' ') {
                ++i;
                continue;
            }
            size_t begin = i;
            if (text.compare(i, 3, "<->") == 0) i += 3;
            else if (text.compare(i, 2, "->") == 0) i += 2;
            else if (lower(text[i])) {
                ++i;
                while (i < text.size() && (lower(text[i]) || digit(text[i]))) ++i;
            } else if (variable(text[i]) || string("01~&^|()").find(text[i]) != string::npos) ++i;
            else throw runtime_error("invalid character '" + string(1, text[i]) + "' at " + to_string(start + i));
            tokens.push_back({text.substr(begin, i - begin), start + static_cast<int>(begin)});
        }
    }
    Formula parse() {
        auto result = expression(1);
        if (index != tokens.size()) error();
        return result;
    }
};
string pattern(int row, int n) {
    string result(n, '0');
    for (int i = n - 1; i >= 0; --i) {
        result[i] += row & 1;
        row >>= 1;
    }
    return result;
}
int literals(const string& p) {
    return count_if(p.begin(), p.end(), [](char c) {
        return c != '-';
    });
}
int rankPattern(char c) {
    return c == '1' ? 0 : c == '0' ? 1 : 2;
}
struct PatternLess {
    bool operator()(const string& a, const string& b) const {
        return lexicographical_compare(a.begin(), a.end(), b.begin(), b.end(), [](char x, char y) {
            return rankPattern(x) < rankPattern(y);
        });
    }
};
using Patterns = set<string, PatternLess>;
bool contains(const string& p, const string& row) {
    for (size_t i = 0; i < p.size(); ++i) if (p[i] != '-' && p[i] != row[i]) return false;
    return true;
}
string swapBits(string p) {
    for (char& c : p) if (c != '-') c = c == '0' ? '1' : '0';
    return p;
}
string term(const string& p, const string& vars, bool clause = false) {
    vector<string> parts;
    for (size_t i = 0; i < p.size(); ++i) if (p[i] != '-') parts.push_back((p[i] == '0' ? "~" : "") + string(1, vars[i]));
    return parts.empty() ? (clause ? "0" : "1") : join(parts, clause ? " | " : " & ");
}
string coverNotation(const vector<string>& ps, const string& vars, bool clauses = false) {
    vector<string> parts;
    for (const string& p : ps) {
        string text = term(p, vars, clauses);
        if (clauses && ps.size() >= 2 && literals(p) >= 2) text = "(" + text + ")";
        parts.push_back(text);
    }
    return parts.empty() ? (clauses ? "1" : "0") : join(parts, clauses ? " & " : " | ");
}
string listTerms(const Patterns& ps, const string& vars) {
    vector<string> parts;
    for (const string& p : ps) parts.push_back(term(p, vars));
    return parts.empty() ? "none" : join(parts, ", ");
}
void minimize(ostream& out, const vector<int>& f, const vector<int>& dc, const string& vars, bool pos) {
    Patterns stage, primes;
    vector<string> on;
    for (size_t r = 0; r < f.size(); ++r) {
        bool care = dc.empty() || !dc[r];
        if ((pos ? !f[r] : f[r]) && care) on.push_back(pattern(r, vars.size()));
        if ((pos ? !f[r] : f[r]) || !care) stage.insert(pattern(r, vars.size()));
    }
    for (int k = 0;; ++k) {
        Patterns next, combined;
        for (auto a = stage.begin(); a != stage.end(); ++a) for (auto b = std::next(a); b != stage.end(); ++b) {
            int differences = 0, position = -1;
            for (size_t i = 0; i < a->size(); ++i) if ((*a)[i] != (*b)[i]) {
                if ((*a)[i] == '-' || (*b)[i] == '-') {
                    differences = 2;
                    break;
                }
                ++differences;
                position = i;
            }
            if (differences == 1) {
                string merged = *a;
                merged[position] = '-';
                next.insert(move(merged));
                combined.insert(*a);
                combined.insert(*b);
            }
        }
        int primeCount = 0;
        for (const string& p : stage) if (!combined.count(p)) {
            primes.insert(p);
            ++primeCount;
        }
        if (!pos) out << "stage " << k << ": implicants " << stage.size() << " primes " << primeCount << '\n';
        if (next.empty()) break;
        stage = move(next);
    }
    Patterns target, essential;
    for (const string& p : primes) for (const string& row : on) if (contains(p, row)) {
        target.insert(p);
        break;
    }
    for (const string& row : on) {
        vector<string> covering;
        for (const string& p : target) if (contains(p, row)) covering.push_back(p);
        if (covering.size() == 1) essential.insert(covering[0]);
    }
    vector<string> candidates;
    for (const string& p : target) if (!essential.count(p)) candidates.push_back(p);
    vector<string> best;
    int bestCount = 1000000, bestLiterals = 1000000;
    PatternLess less;
    for (int mask = 0; mask < (1 << candidates.size()); ++mask) {
        vector<string> cover(essential.begin(), essential.end());
        for (size_t i = 0; i < candidates.size(); ++i) if (mask & (1 << i)) cover.push_back(candidates[i]);
        if (static_cast<int>(cover.size()) > bestCount) continue;
        bool complete = true;
        for (const string& row : on) {
            bool covered = false;
            for (const string& p : cover) if (contains(p, row)) {
                covered = true;
                break;
            }
            if (!covered) {
                complete = false;
                break;
            }
        }
        if (!complete) continue;
        int count = cover.size(), literalCount = 0;
        for (string& p : cover) {
            literalCount += literals(p);
            if (pos) p = swapBits(p);
        }
        sort(cover.begin(), cover.end(), less);
        if (count < bestCount || (count == bestCount && (literalCount < bestLiterals
                || (literalCount == bestLiterals && lexicographical_compare(cover.begin(), cover.end(), best.begin(), best.end(), less))))) {
            bestCount = count;
            bestLiterals = literalCount;
            best = move(cover);
        }
    }
    if (!pos) {
        out << "primes: " << listTerms(target, vars) << '\n';
        out << "essential: " << listTerms(essential, vars) << '\n';
    }
    out << "minimal: " << coverNotation(best, vars, pos) << '\n';
    out << (pos ? "clauses " : "terms ") << bestCount << " literals " << bestLiterals << '\n';
}
Patterns tidy(const Patterns& input) {
    Patterns result;
    for (const string& p : input) {
        bool absorbed = false;
        for (const string& q : input) if (p != q && literals(q) < literals(p)) {
            bool subset = true;
            for (size_t i = 0; i < p.size(); ++i) if (q[i] != '-' && q[i] != p[i]) {
                subset = false;
                break;
            }
            if (subset) {
                absorbed = true;
                break;
            }
        }
        if (!absorbed) result.insert(p);
    }
    return result;
}
optional<string> mergeClause(const string& a, const string& b) {
    string result = a;
    for (size_t i = 0; i < a.size(); ++i) if (b[i] != '-') {
        if (result[i] != '-' && result[i] != b[i]) return nullopt;
        result[i] = b[i];
    }
    return result;
}
Patterns clauses(const Formula& f, const string& vars, map<Formula, Patterns>& memo) {
    auto cached = memo.find(f);
    if (cached != memo.end()) return cached->second;
    Patterns result;
    if (f->op == "0") {
        result.insert(string(vars.size(), '-'));
    } else if (f->op != "1" && (!f->left || f->op == "~")) {
        string p(vars.size(), '-');
        p[vars.find(f->op == "~" ? f->left->op[0] : f->op[0])] = f->op == "~" ? '0' : '1';
        result.insert(p);
    } else if (f->op != "1") {
        auto a = clauses(f->left, vars, memo), b = clauses(f->right, vars, memo);
        if (f->op == "&") {
            result = move(a);
            result.insert(b.begin(), b.end());
        } else for (const string& p : a) for (const string& q : b) {
            auto merged = mergeClause(p, q);
            if (merged) result.insert(*merged);
        }
        result = tidy(result);
    }
    memo.emplace(f, result);
    return result;
}
Patterns clauses(const Formula& f, const string& vars) {
    map<Formula, Patterns> memo;
    return clauses(f, vars, memo);
}
vector<int> coefficients(vector<int> f) {
    for (size_t bit = 1; bit < f.size(); bit <<= 1) {
        for (size_t row = 0; row < f.size(); ++row) if (row & bit) f[row] ^= f[row ^ bit];
    }
    return f;
}
string assignment(int row, const string& vars) {
    string result = "{";
    string bits = pattern(row, vars.size());
    for (size_t i = 0; i < vars.size(); ++i) {
        if (i) result += ' ';
        result += string(1, vars[i]) + "=" + bits[i];
    }
    return result + '}';
}
class Workbench {
    map<string, Formula> names;
    void define(const string& name, Formula f, ostream& out) {
        out << (names.count(name) ? "redefined " : "defined ") << name << " = " << notation(f) << '\n';
        names[name] = move(f);
    }
public:
    void execute(const string& line, ostream& out) {
        size_t space = line.find(' ');
        string command = line.substr(0, space);
        bool hasArgument = space != string::npos;
        string argument = hasArgument ? line.substr(space + 1) : "";
        const set<string> commands = {"DEF", "DEFSUM", "DEL", "LIST", "PRINT", "TABLE", "MINTERMS", "MAXTERMS",
            "DNF", "CNF", "NNF", "DUAL", "ANF", "SIMPLIFY", "RESTRICT", "COFACTOR", "MINIMIZE", "MINDC",
            "MINPOS", "KMAP", "SAT", "TAUT", "COUNT", "EQUIV", "IMPLIES", "PROPS", "BDD", "CLAUSES", "DP"};
        if (!commands.count(command)) throw runtime_error("unknown command " + command);
        if (command == "LIST" && hasArgument) throw runtime_error("unexpected argument");
        if (command != "LIST" && !hasArgument) throw runtime_error("missing argument");
        if (command == "LIST") {
            out << "names: " << names.size() << '\n';
            for (const auto& entry : names) out << entry.first << " = " << notation(entry.second) << '\n';
            return;
        }
        if (command == "DEL") {
            if (!validName(argument)) throw runtime_error("invalid name '" + argument + "'");
            if (!names.count(argument)) throw runtime_error("undefined name '" + argument + "'");
            names.erase(argument);
            out << "deleted " << argument << '\n';
            return;
        }
        if (command == "DEF") {
            size_t split = argument.find(' ');
            if (split == string::npos) throw runtime_error("missing argument");
            string name = argument.substr(0, split);
            if (!validName(name)) throw runtime_error("invalid name '" + name + "'");
            auto f = Parser(argument.substr(split + 1), name.size() + 6, names).parse();
            define(name, f, out);
            return;
        }
        if (command == "DEFSUM") {
            size_t split = argument.find(';');
            if (split == string::npos) throw runtime_error("missing ';'");
            auto front = words(argument.substr(0, split)), back = words(argument.substr(split + 1));
            if (front.empty()) throw runtime_error("missing argument");
            if (!validName(front[0])) throw runtime_error("invalid name '" + front[0] + "'");
            bool valid = front.size() >= 2;
            for (size_t i = 1; i < front.size(); ++i) {
                valid = valid && front[i].size() == 1 && variable(front[i][0]) && (i == 1 || front[i - 1] < front[i]);
            }
            if (!valid) throw runtime_error("bad variable list");
            int n = front.size() - 1;
            if (n >= 9) throw runtime_error("too many variables: " + to_string(n));
            Formula f;
            int previous = -1;
            for (const string& m : back) {
                bool validM = m == "0" || (!m.empty() && m[0] != '0' && all_of(m.begin(), m.end(), digit));
                long long value = validM ? stoll(m) : -1;
                if (!validM || value >= (1 << n) || value <= previous) throw runtime_error("bad minterm '" + m + "'");
                previous = value;
                string bits = pattern(value, n);
                Formula product;
                for (int i = 0; i < n; ++i) {
                    auto literal = leaf(front[i + 1]);
                    if (bits[i] == '0') literal = make("~", literal);
                    product = product ? make("&", product, literal) : literal;
                }
                f = f ? make("|", f, product) : product;
            }
            define(front[0], f ? f : leaf("0"), out);
            return;
        }
        const set<string> splitCommands = {"RESTRICT", "COFACTOR", "MINDC", "EQUIV", "IMPLIES"};
        string first = argument, second;
        int firstStart = command.size() + 2, secondStart = 0;
        if (splitCommands.count(command)) {
            size_t split = argument.find(';');
            if (split == string::npos) throw runtime_error("missing ';'");
            first = argument.substr(0, split);
            second = argument.substr(split + 1);
            secondStart = firstStart + split + 1;
        }
        auto f = Parser(first, firstStart, names).parse();
        Formula g;
        if (command == "MINDC" || command == "EQUIV" || command == "IMPLIES") g = Parser(second, secondStart, names).parse();
        map<char, int> substitutions;
        char cofactor = 0;
        if (command == "RESTRICT") {
            auto assignments = words(second);
            if (assignments.empty()) throw runtime_error("missing assignment");
            for (const string& a : assignments) {
                if (a.size() != 3 || !variable(a[0]) || a[1] != '=' || (a[2] != '0' && a[2] != '1')) throw runtime_error("bad assignment '" + a + "'");
                if (substitutions.count(a[0])) throw runtime_error("duplicate variable " + string(1, a[0]));
                substitutions[a[0]] = a[2] - '0';
            }
        } else if (command == "COFACTOR") {
            auto vs = words(second);
            if (vs.size() != 1 || vs[0].size() != 1 || !variable(vs[0][0])) throw runtime_error("bad variable");
            cofactor = vs[0][0];
        }
        set<char> variables;
        collect(f, variables);
        if (g) collect(g, variables);
        string vars(variables.begin(), variables.end());
        int n = vars.size();
        const set<string> tableCommands = {"TABLE", "MINTERMS", "MAXTERMS", "DNF", "CNF", "ANF", "SAT", "TAUT", "COUNT",
            "EQUIV", "IMPLIES", "PROPS", "KMAP", "BDD", "MINIMIZE", "MINDC", "MINPOS"};
        if (tableCommands.count(command) && n >= 9) throw runtime_error("too many variables: " + to_string(n));
        if (command == "PRINT") {
            vector<string> letters;
            for (char v : vars) letters.push_back(string(1, v));
            auto size = dimensions(f);
            out << "formula: " << notation(f) << "\nvariables: " << (vars.empty() ? "none" : join(letters, " "))
                << "\nsize " << size.first << " depth " << size.second << '\n';
        } else if (command == "NNF") out << "nnf: " << notation(nnf(f)) << '\n';
        else if (command == "DUAL") out << "dual: " << notation(dual(f)) << '\n';
        else if (command == "SIMPLIFY") out << "simplified: " << notation(simplify(f)) << '\n';
        else if (command == "RESTRICT") out << "restricted: " << notation(simplify(f, substitutions)) << '\n';
        else if (command == "COFACTOR") {
            auto one = simplify(f, {{cofactor, 1}}), zero = simplify(f, {{cofactor, 0}});
            out << "cofactor " << cofactor << "=1: " << notation(one) << "\ncofactor " << cofactor << "=0: " << notation(zero)
                << "\ndifference: " << notation(binary("^", one, zero)) << '\n';
        } else if (command == "CLAUSES" || command == "DP") {
            auto current = clauses(nnf(f), vars);
            if (command == "CLAUSES") out << "clauses: " << coverNotation(vector<string>(current.begin(), current.end()), vars, true) << '\n';
            else {
                string empty(vars.size(), '-');
                out << "start: clauses " << current.size() << '\n';
                for (size_t i = 0; i < vars.size() && !current.empty() && !current.count(empty); ++i) {
                    Patterns positive, negative, retained, resolvents;
                    for (const string& p : current) {
                        if (p[i] == '1') positive.insert(p);
                        else if (p[i] == '0') negative.insert(p);
                        else retained.insert(p);
                    }
                    for (string p : positive) for (string q : negative) {
                        p[i] = q[i] = '-';
                        auto merged = mergeClause(p, q);
                        if (merged) resolvents.insert(*merged);
                    }
                    retained.insert(resolvents.begin(), resolvents.end());
                    current = tidy(retained);
                    out << "eliminate " << vars[i] << ": resolvents " << resolvents.size() << " clauses " << current.size() << '\n';
                }
                out << "result: " << (current.count(empty) ? "unsatisfiable" : "satisfiable") << '\n';
            }
        } else {
            vector<int> values(1 << n), other(g ? 1 << n : 0);
            for (int row = 0; row < (1 << n); ++row) {
                map<char, int> assignment;
                for (int i = 0; i < n; ++i) assignment[vars[i]] = (row >> (n - 1 - i)) & 1;
                values[row] = evaluate(f, assignment);
                if (g) other[row] = evaluate(g, assignment);
            }
            if (command == "TABLE") {
                for (char v : vars) out << v << ' ';
                out << "| F\n";
                for (int r = 0; r < (1 << n); ++r) {
                    for (char bit : pattern(r, n)) out << bit << ' ';
                    out << "| " << values[r] << '\n';
                }
            } else if (command == "MINTERMS" || command == "MAXTERMS") {
                vector<string> rows;
                for (int r = 0; r < (1 << n); ++r) if (values[r] == (command == "MINTERMS")) rows.push_back(to_string(r));
                out << (command == "MINTERMS" ? "minterms: " : "maxterms: ") << (rows.empty() ? "none" : join(rows, " ")) << '\n';
            } else if (command == "DNF" || command == "CNF") {
                vector<string> ps;
                bool cnf = command == "CNF";
                for (int r = 0; r < (1 << n); ++r) if (values[r] != cnf) ps.push_back(cnf ? swapBits(pattern(r, n)) : pattern(r, n));
                out << (cnf ? "cnf: " : "dnf: ") << coverNotation(ps, vars, cnf) << '\n';
            } else if (command == "ANF") {
                auto cs = coefficients(values);
                vector<string> ps, terms;
                for (int r = 0; r < (1 << n); ++r) if (cs[r]) {
                    string p = pattern(r, n);
                    replace(p.begin(), p.end(), '0', '-');
                    ps.push_back(p);
                }
                sort(ps.begin(), ps.end(), [](const string& a, const string& b) {
                    return literals(a) != literals(b) ? literals(a) < literals(b) : PatternLess{}(a, b);
                });
                for (const string& p : ps) terms.push_back(term(p, vars));
                out << "anf: " << (terms.empty() ? "0" : join(terms, " ^ ")) << '\n';
            } else if (command == "SAT" || command == "TAUT") {
                int wanted = command == "SAT";
                auto found = find(values.begin(), values.end(), wanted);
                if (command == "SAT") out << (found == values.end() ? "unsatisfiable" : "satisfiable: " + assignment(found - values.begin(), vars)) << '\n';
                else out << (found == values.end() ? "tautology" : "not a tautology: " + assignment(found - values.begin(), vars)) << '\n';
            } else if (command == "COUNT") out << "models: " << count(values.begin(), values.end(), 1) << " of " << values.size() << '\n';
            else if (command == "EQUIV" || command == "IMPLIES") {
                int witness = -1;
                for (int r = 0; r < (1 << n); ++r) if (command == "EQUIV" ? values[r] != other[r] : values[r] && !other[r]) {
                    witness = r;
                    break;
                }
                if (command == "EQUIV") {
                    if (witness < 0) out << "equivalent\n";
                    else out << "not equivalent: " << assignment(witness, vars) << " f=" << values[witness] << " g=" << other[witness] << '\n';
                } else out << (witness < 0 ? "implies" : "does not imply: " + assignment(witness, vars)) << '\n';
            } else if (command == "PROPS") {
                vector<string> depends;
                bool selfDual = true, monotone = true, linear = true, symmetric = true;
                for (int i = 0; i < n; ++i) {
                    bool dependent = false;
                    int bit = 1 << (n - 1 - i);
                    for (int r = 0; r < (1 << n); ++r) {
                        if (values[r] != values[r ^ bit]) dependent = true;
                        if (!(r & bit) && values[r] > values[r | bit]) monotone = false;
                    }
                    if (dependent) depends.push_back(string(1, vars[i]));
                }
                auto cs = coefficients(values);
                map<int, int> weights;
                for (int r = 0; r < (1 << n); ++r) {
                    if (values[r] == values[(1 << n) - 1 - r]) selfDual = false;
                    string bits = pattern(r, n);
                    int weight = count(bits.begin(), bits.end(), '1');
                    if (cs[r] && weight > 1) linear = false;
                    if (weights.count(weight) && weights[weight] != values[r]) symmetric = false;
                    weights[weight] = values[r];
                }
                auto yes = [](bool b) {
                    return b ? "yes" : "no";
                };
                out << "depends: " << (depends.empty() ? "none" : join(depends, " ")) << "\nzero-preserving: " << yes(!values.front())
                    << "\none-preserving: " << yes(values.back()) << "\nself-dual: " << yes(selfDual) << "\nmonotone: " << yes(monotone)
                    << "\nlinear: " << yes(linear) << "\nsymmetric: " << yes(symmetric) << '\n';
            } else if (command == "KMAP") {
                if (n < 2 || n > 4) throw runtime_error("kmap needs 2 to 4 variables");
                int p = n / 2, q = n - p;
                string label = vars.substr(0, p) + "\\" + vars.substr(p);
                out << label;
                for (int i = 0; i < (1 << q); ++i) out << ' ' << pattern(i ^ (i / 2), q);
                out << '\n';
                for (int i = 0; i < (1 << p); ++i) {
                    int r = i ^ (i / 2);
                    out << pattern(r, p) << string(q + 1, ' ');
                    for (int j = 0; j < (1 << q); ++j) out << string(q, ' ') << values[(r << q) | (j ^ (j / 2))];
                    out << '\n';
                }
            } else if (command == "BDD") {
                vector<tuple<int, int, int>> nodes;
                map<tuple<int, int, int>, int> unique;
                function<int(int, int, int)> build = [&](int level, int begin, int length) {
                    if (level == n) return values[begin];
                    int lo = build(level + 1, begin, length / 2);
                    int hi = build(level + 1, begin + length / 2, length / 2);
                    if (lo == hi) return lo;
                    auto key = make_tuple(level, lo, hi);
                    auto found = unique.find(key);
                    if (found != unique.end()) return found->second;
                    int id = nodes.size() + 2;
                    unique[key] = id;
                    nodes.push_back(key);
                    return id;
                };
                int root = build(0, 0, values.size());
                vector<int> paths{0, 1};
                out << "nodes: " << nodes.size() << '\n';
                for (size_t i = 0; i < nodes.size(); ++i) {
                    auto [level, lo, hi] = nodes[i];
                    out << i + 2 << " = ite(" << vars[level] << ", " << hi << ", " << lo << ")\n";
                    paths.push_back(paths[lo] + paths[hi]);
                }
                out << "root: " << root << "\npaths: " << paths[root] << '\n';
            } else minimize(out, values, command == "MINDC" ? other : vector<int>{}, vars, command == "MINPOS");
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
    Workbench workbench;
    while (count-- && getline(cin, line)) {
        try {
            ostringstream output;
            workbench.execute(line, output);
            cout << output.str();
        } catch (const runtime_error& error) {
            cout << "error: " << error.what() << '\n';
        }
    }
}
