#include <algorithm>
#include <array>
#include <cctype>
#include <cstdlib>
#include <functional>
#include <iostream>
#include <memory>
#include <regex>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>
using namespace std;
struct Expr;
using P = shared_ptr<const Expr>;
struct Expr {
    char kind;
    long long n;
    int row = 0, flags = 0;
    string text;
    P a, b;
    vector<P> args;
    Expr(char k, long long v = 0, string s = "", P x = {}, P y = {}, vector<P> xs = {})
        : kind(k), n(v), text(move(s)), a(move(x)), b(move(y)), args(move(xs)) {
    }
};
P node(char k, long long n = 0, string s = "", P a = {}, P b = {}, vector<P> xs = {}) {
    return make_shared<Expr>(k, n, move(s), move(a), move(b), move(xs));
}
P number(long long n) {
    return node('N', n);
}
P text(string s) {
    return node('S', 0, move(s));
}
P error(string s) {
    return node('E', 0, move(s));
}
P reference(int c, int r, int f = 0) {
    auto p = make_shared<Expr>('R', c);
    p->row = r;
    p->flags = f;
    return p;
}
P invalid = node('X');
int indexOf(P p) {
    return p->row * 26 + int(p->n);
}
string addressOf(int i) {
    return string(1, char('A' + i % 26)) + to_string(i / 26 + 1);
}
bool inside(P p) {
    return p->n >= 0 && p->n < 26 && p->row >= 0 && p->row < 99;
}
P rangeOf(P a, P b) {
    int c = int(a->n), d = int(b->n), r = a->row, t = b->row, ac = a->flags & 1, bc = b->flags & 1,
        ar = a->flags & 2, br = b->flags & 2;
    if (c > d) {
        swap(c, d);
        swap(ac, bc);
    }
    if (r > t) {
        swap(r, t);
        swap(ar, br);
    }
    return node('G', 0, "", reference(c, r, ac | ar), reference(d, t, bc | br));
}
P address(string s) {
    if (!regex_match(s, regex("[A-Z][1-9][0-9]?")))
        throw runtime_error("bad address");
    return reference(s[0] - 'A', stoi(s.substr(1)) - 1);
}
P area(string s) {
    size_t p = s.find(':');
    if (p == string::npos) {
        P a = address(s);
        return rangeOf(a, a);
    }
    P a = address(s.substr(0, p)), b = address(s.substr(p + 1));
    return rangeOf(a, b);
}
vector<int> cells(P g) {
    vector<int> out;
    for (int r = g->a->row; r <= g->b->row; r++)
        for (int c = int(g->a->n); c <= g->b->n; c++)
            out.push_back(r * 26 + c);
    return out;
}
bool contains(P g, P r) {
    return r->n >= g->a->n && r->n <= g->b->n && r->row >= g->a->row && r->row <= g->b->row;
}
int precedence(string op) {
    if (op == "&")
        return 1;
    if (op == "+" || op == "-")
        return 2;
    if (op == "*" || op == "/")
        return 3;
    return 0;
}
struct Token {
    P value;
    int position;
};
class Parser {
    vector<Token> ts;
    size_t at = 0;
    [[noreturn]] void syntax(int p) {
        throw runtime_error("syntax error at " + to_string(p));
    }
    bool take(string s) {
        if (ts[at].value->kind == 'T' && ts[at].value->text == s) {
            at++;
            return true;
        }
        return false;
    }
    void expect(string s) {
        if (!take(s))
            syntax(ts[at].position);
    }
    P expr(int level = 0) {
        if (level == 4)
            return primary();
        P a = expr(level + 1);
        while (ts[at].value->kind == 'T' &&
               string("= <> < <= > >= & + - * /").find(ts[at].value->text) != string::npos &&
               precedence(ts[at].value->text) == level && ts[at].value->text != "(" &&
               ts[at].value->text != ")") {
            string op = ts[at++].value->text;
            a = node('B', 0, op, a, expr(level + 1));
        }
        return a;
    }
    P primary() {
        if (take("-"))
            return node('U', 0, "", primary());
        Token t = ts[at++];
        P x = t.value;
        if (x->kind == 'N' || x->kind == 'S' || x->kind == 'W')
            return x;
        if (x->kind == 'R') {
            if (!take(":"))
                return x;
            if (ts[at].value->kind != 'R')
                syntax(ts[at].position);
            return rangeOf(x, ts[at++].value);
        }
        if (x->kind == 'C') {
            expect("(");
            vector<P> args;
            if (!take(")")) {
                args.push_back(expr());
                while (take(","))
                    args.push_back(expr());
                expect(")");
            }
            return node('F', 0, x->text, {}, {}, move(args));
        }
        if (x->kind == 'T' && x->text == "(") {
            P a = expr();
            expect(")");
            return a;
        }
        syntax(t.position);
    }

  public:
    P parse(string s) {
        for (size_t i = 1; i < s.size();) {
            int p = int(i) + 1;
            char c = s[i];
            if (c == ' ') {
                i++;
                continue;
            }
            if (c >= '0' && c <= '9') {
                size_t j = i;
                while (j < s.size() && isdigit(static_cast<unsigned char>(s[j])))
                    j++;
                if (j - i >= 10)
                    syntax(p);
                ts.push_back({number(stoll(s.substr(i, j - i))), p});
                i = j;
            } else if (c == '"') {
                size_t j = s.find('"', i + 1);
                if (j == string::npos)
                    syntax(p);
                ts.push_back({text(s.substr(i + 1, j - i - 1)), p});
                i = j + 1;
            } else if (isalpha(static_cast<unsigned char>(c)) || c == '$') {
                size_t j = i;
                while (j < s.size() && (isalnum(static_cast<unsigned char>(s[j])) || s[j] == '$'))
                    j++;
                string w = s.substr(i, j - i);
                for (char &ch : w)
                    ch = char(toupper(static_cast<unsigned char>(ch)));
                smatch m;
                P x;
                if (regex_match(w, m, regex("(\\$?)([A-Z])(\\$?)([1-9][0-9]?)")))
                    x = reference(m[2].str()[0] - 'A', stoi(m[4].str()) - 1,
                                  (!m[1].str().empty() ? 1 : 0) | (!m[3].str().empty() ? 2 : 0));
                else if (regex_match(w, regex("[A-Z][A-Z0-9]*"))) {
                    size_t k = s.find_first_not_of(' ', j);
                    x = node(k != string::npos && s[k] == '(' ? 'C' : 'W', 0, w);
                } else
                    syntax(p);
                ts.push_back({x, p});
                i = j;
            } else {
                string op = s.substr(i, 2);
                if (op != "<>" && op != "<=" && op != ">=")
                    op = string(1, c);
                if (string("+-*/&(),:=<>").find(c) == string::npos)
                    syntax(p);
                ts.push_back({node('T', 0, op), p});
                i += op.size();
            }
        }
        ts.push_back({node('Z'), int(s.size()) + 1});
        P tree = expr();
        if (ts[at].value->kind != 'Z')
            syntax(ts[at].position);
        return tree;
    }
};
string canonical(P x) {
    switch (x->kind) {
    case 'N':
        return to_string(x->n);
    case 'S':
        return "\"" + x->text + "\"";
    case 'W':
        return x->text;
    case 'X':
        return "#REF!";
    case 'R':
        return string(x->flags & 1 ? "$" : "") + char('A' + x->n) + (x->flags & 2 ? "$" : "") +
               to_string(x->row + 1);
    case 'G':
        return canonical(x->a) + ":" + canonical(x->b);
    case 'F': {
        string s = x->text + "(";
        for (size_t i = 0; i < x->args.size(); i++) {
            if (i)
                s += ",";
            s += canonical(x->args[i]);
        }
        return s + ")";
    }
    case 'U':
        return "-" + (x->a->kind == 'B' ? "(" + canonical(x->a) + ")" : canonical(x->a));
    case 'B': {
        string a = canonical(x->a), b = canonical(x->b);
        if (x->a->kind == 'B' && precedence(x->a->text) < precedence(x->text))
            a = "(" + a + ")";
        if (x->b->kind == 'B' && precedence(x->b->text) <= precedence(x->text))
            b = "(" + b + ")";
        return a + x->text + b;
    }
    default:
        return "";
    }
}
string display(P x) {
    return !x ? "" : x->kind == 'N' ? to_string(x->n) : x->text;
}
string notation(P x) {
    return !x               ? "(empty)"
           : x->kind == '=' ? "=" + canonical(x->a)
           : x->kind == 'S' ? "\"" + x->text + "\""
                            : display(x);
}
P toNumber(P x) {
    return !x ? number(0) : (x->kind == 'S' || x->kind == 'G') ? error("#VALUE!") : x;
}
P toText(P x) {
    return !x               ? text("")
           : x->kind == 'N' ? text(to_string(x->n))
           : x->kind == 'G' ? error("#VALUE!")
                            : x;
}
void dependencies(P x, set<int> &out) {
    if (!x)
        return;
    if (x->kind == 'R')
        out.insert(indexOf(x));
    else if (x->kind == 'G') {
        for (int i : cells(x))
            out.insert(i);
    } else {
        dependencies(x->a, out);
        dependencies(x->b, out);
        for (P a : x->args)
            dependencies(a, out);
    }
}
P rewrite(P x, const function<P(P)> &transform) {
    if (!x)
        return {};
    if (x->kind == 'R' || x->kind == 'G')
        return transform(x);
    P a = rewrite(x->a, transform), b = rewrite(x->b, transform);
    vector<P> args;
    bool changed = a != x->a || b != x->b;
    for (P old : x->args) {
        P v = rewrite(old, transform);
        changed |= v != old;
        args.push_back(v);
    }
    return changed ? node(x->kind, x->n, x->text, a, b, move(args)) : x;
}
using Grid = array<P, 2574>;
class Sheet {
    Grid contents{}, values{};
    array<set<int>, 2574> deps;
    vector<pair<string, Grid>> history;
    P evaluate(P x) {
        if (x->kind == 'N' || x->kind == 'S' || x->kind == 'G')
            return x;
        if (x->kind == 'R')
            return values[indexOf(x)];
        if (x->kind == 'W')
            return error("#NAME?");
        if (x->kind == 'X')
            return error("#REF!");
        if (x->kind == 'U') {
            P a = toNumber(evaluate(x->a));
            return a->kind == 'E' ? a : number(-a->n);
        }
        if (x->kind == 'B') {
            P a = evaluate(x->a), b = evaluate(x->b);
            if (a && a->kind == 'E')
                return a;
            if (b && b->kind == 'E')
                return b;
            string op = x->text;
            if (precedence(op) == 0) {
                if ((a && a->kind == 'G') || (b && b->kind == 'G'))
                    return error("#VALUE!");
                bool strings = (a && a->kind == 'S') || (b && b->kind == 'S');
                if (!a)
                    a = strings ? text("") : number(0);
                if (!b)
                    b = strings ? text("") : number(0);
                int c = a->kind != b->kind ? (a->kind == 'N' ? -1 : 1)
                        : a->kind == 'N'   ? (a->n > b->n) - (a->n < b->n)
                                           : a->text.compare(b->text);
                return number(op == "="    ? c == 0
                              : op == "<>" ? c != 0
                              : op == "<"  ? c < 0
                              : op == "<=" ? c <= 0
                              : op == ">"  ? c > 0
                                           : c >= 0);
            }
            a = op == "&" ? toText(a) : toNumber(a);
            b = op == "&" ? toText(b) : toNumber(b);
            if (a->kind == 'E')
                return a;
            if (b->kind == 'E')
                return b;
            if (op == "&")
                return text(a->text + b->text);
            if (op == "+")
                return number(a->n + b->n);
            if (op == "-")
                return number(a->n - b->n);
            if (op == "*")
                return number(a->n * b->n);
            return b->n ? number(a->n / b->n) : error("#DIV/0!");
        }
        string name = x->text;
        const vector<P> &args = x->args;
        static const set<string> aggregates = {"SUM",     "MIN", "MAX", "COUNT",
                                               "AVERAGE", "AND", "OR",  "CONCAT"};
        if (aggregates.count(name)) {
            if (args.empty())
                return error("#VALUE!");
            vector<P> items;
            vector<long long> ns;
            for (P arg : args) {
                P v = evaluate(arg);
                if (v && v->kind == 'G') {
                    for (int i : cells(v))
                        items.push_back(values[i]);
                } else
                    items.push_back(v);
            }
            for (P v : items)
                if (v && v->kind == 'N')
                    ns.push_back(v->n);
            if (name == "COUNT")
                return number(ns.size());
            for (P v : items)
                if (v && v->kind == 'E')
                    return v;
            if (name == "CONCAT") {
                string s;
                for (P v : items)
                    s += toText(v)->text;
                return text(s);
            }
            long long sum = 0;
            for (long long n : ns)
                sum += n;
            if (name == "SUM")
                return number(sum);
            if (name == "MIN")
                return number(ns.empty() ? 0 : *min_element(ns.begin(), ns.end()));
            if (name == "MAX")
                return number(ns.empty() ? 0 : *max_element(ns.begin(), ns.end()));
            if (ns.empty())
                return error(name == "AVERAGE" ? "#DIV/0!" : "#VALUE!");
            if (name == "AVERAGE")
                return number(sum / static_cast<long long>(ns.size()));
            bool nonzero = name == "AND";
            for (long long n : ns)
                nonzero = name == "AND" ? (nonzero && n != 0) : (nonzero || n != 0);
            return number(nonzero);
        }
        if (name == "IF") {
            if (args.size() != 2 && args.size() != 3)
                return error("#VALUE!");
            P c = toNumber(evaluate(args[0]));
            if (c->kind == 'E')
                return c;
            return c->n ? evaluate(args[1]) : args.size() == 3 ? evaluate(args[2]) : number(0);
        }
        if (name != "ABS" && name != "NOT" && name != "LEN")
            return error("#NAME?");
        if (args.size() != 1)
            return error("#VALUE!");
        P v = evaluate(args[0]);
        v = name == "LEN" ? toText(v) : toNumber(v);
        return v->kind == 'E' ? v
                              : number(name == "LEN"   ? static_cast<long long>(v->text.size())
                                       : name == "ABS" ? llabs(v->n)
                                                       : v->n == 0);
    }
    void recalculate() {
        array<int, 2574> indices, low{};
        indices.fill(-1);
        array<bool, 2574> on{}, cyclic{}, done{};
        vector<int> stack;
        int serial = 0;
        for (int i = 0; i < 2574; i++) {
            deps[i].clear();
            if (contents[i] && contents[i]->kind == '=') {
                dependencies(contents[i]->a, deps[i]);
                values[i] = {};
            } else
                values[i] = contents[i];
        }
        function<void(int)> visit = [&](int i) {
            indices[i] = low[i] = serial++;
            stack.push_back(i);
            on[i] = true;
            for (int j : deps[i])
                if (contents[j] && contents[j]->kind == '=') {
                    if (indices[j] < 0) {
                        visit(j);
                        low[i] = min(low[i], low[j]);
                    } else if (on[j])
                        low[i] = min(low[i], indices[j]);
                }
            if (low[i] == indices[i]) {
                vector<int> part;
                int j;
                do {
                    j = stack.back();
                    stack.pop_back();
                    on[j] = false;
                    part.push_back(j);
                } while (j != i);
                if (part.size() > 1 || deps[i].count(i))
                    for (int j : part)
                        cyclic[j] = true;
            }
        };
        for (int i = 0; i < 2574; i++)
            if (contents[i] && contents[i]->kind == '=' && indices[i] < 0)
                visit(i);
        function<void(int)> calculate = [&](int i) {
            if (!contents[i] || contents[i]->kind != '=' || done[i])
                return;
            done[i] = true;
            if (cyclic[i]) {
                values[i] = error("#CYCLE!");
                return;
            }
            for (int j : deps[i])
                calculate(j);
            P v = evaluate(contents[i]->a);
            values[i] = !v ? number(0) : v->kind == 'G' ? error("#VALUE!") : v;
        };
        for (int i = 0; i < 2574; i++)
            calculate(i);
    }
    int replace(Grid next) {
        Grid old = values;
        contents = move(next);
        recalculate();
        int changed = 0;
        for (int i = 0; i < 2574; i++)
            changed += notation(old[i]) != notation(values[i]);
        return changed;
    }
    string describe(int i) {
        return addressOf(i) + ": " + notation(contents[i]) + " -> " + notation(values[i]);
    }
    string formatted(const set<int> &xs) {
        string s;
        for (int i : xs) {
            if (!s.empty())
                s += ",";
            s += addressOf(i);
        }
        return s.empty() ? "none" : s;
    }

  public:
    void execute(string line) {
        size_t p = line.find(' ');
        string name = line.substr(0, p), rest = p == string::npos ? "" : line.substr(p + 1);
        if (name == "SHOW") {
            cout << describe(indexOf(address(rest))) << '\n';
            return;
        }
        if (name == "LIST") {
            bool any = false;
            for (int i = 0; i < 2574; i++)
                if (contents[i]) {
                    cout << describe(i) << '\n';
                    any = true;
                }
            if (!any)
                cout << "(no cells)\n";
            return;
        }
        if (name == "DEPS") {
            int i = indexOf(address(rest));
            set<int> ds;
            for (int j = 0; j < 2574; j++)
                if (deps[j].count(i))
                    ds.insert(j);
            cout << rest << ": precedents=" << formatted(deps[i]) << " dependents=" << formatted(ds)
                 << '\n';
            return;
        }
        if (name == "PRINT") {
            P g = area(rest);
            int rw = int(to_string(g->b->row + 1).size());
            vector<size_t> widths;
            string sep = "+" + string(rw, '-') + "+", header = "|" + string(rw, ' ') + "|";
            for (int c = int(g->a->n); c <= g->b->n; c++) {
                size_t w = 1;
                for (int r = g->a->row; r <= g->b->row; r++)
                    w = max(w, display(values[r * 26 + c]).size());
                widths.push_back(w);
                sep += string(w, '-') + "+";
                header += string(1, char('A' + c)) + string(w - 1, ' ') + "|";
            }
            cout << sep << '\n' << header << '\n' << sep << '\n';
            for (int r = g->a->row; r <= g->b->row; r++) {
                string s = to_string(r + 1);
                cout << '|' << string(rw - s.size(), ' ') << s << '|';
                for (size_t j = 0; j < widths.size(); j++) {
                    P v = values[r * 26 + int(g->a->n) + int(j)];
                    s = display(v);
                    string pad(widths[j] - s.size(), ' ');
                    cout << (v && v->kind == 'N' ? pad + s : s + pad) << '|';
                }
                cout << '\n';
            }
            cout << sep << '\n';
            return;
        }
        if (name == "UNDO") {
            if (history.empty())
                throw runtime_error("nothing to undo");
            auto entry = move(history.back());
            history.pop_back();
            int changed = replace(move(entry.second));
            cout << "UNDO " << entry.first << " changed=" << changed << '\n';
            return;
        }
        Grid next = contents;
        int target = -1;
        if (name == "SET") {
            p = rest.find(' ');
            target = indexOf(address(rest.substr(0, p)));
            string s = rest.substr(p + 1);
            if (s[0] == '=')
                next[target] = node('=', 0, "", Parser().parse(s));
            else if (regex_match(s, regex("\"[^\"]*\"")))
                next[target] = text(s.substr(1, s.size() - 2));
            else if (regex_match(s, regex("0|-?[1-9][0-9]{0,8}")))
                next[target] = number(stoll(s));
            else
                throw runtime_error("bad value");
        } else if (name == "CLEAR") {
            for (int i : cells(area(rest)))
                next[i] = {};
        } else if (name == "COPY" || name == "MOVE") {
            p = rest.find(' ');
            P source = area(rest.substr(0, p)), dest = address(rest.substr(p + 1));
            int dc = int(dest->n - source->a->n), dr = dest->row - source->a->row;
            auto shift = [&](P r, bool relative) {
                return reference(int(r->n) + (relative && (r->flags & 1) ? 0 : dc),
                                 r->row + (relative && (r->flags & 2) ? 0 : dr), r->flags);
            };
            P destination = rangeOf(shift(source->a, false), shift(source->b, false));
            if (!inside(destination->a) || !inside(destination->b))
                throw runtime_error("out of grid");
            function<P(P)> transform = [&](P x) {
                if (x->kind == 'R') {
                    if (name == "COPY") {
                        P a = shift(x, true);
                        return inside(a) ? a : invalid;
                    }
                    return contains(source, x)        ? shift(x, false)
                           : contains(destination, x) ? invalid
                                                      : x;
                }
                if (name == "MOVE" && !(contains(source, x->a) && contains(source, x->b)))
                    return x;
                P a = shift(x->a, name == "COPY"), b = shift(x->b, name == "COPY");
                return inside(a) && inside(b) ? rangeOf(a, b) : invalid;
            };
            if (name == "MOVE")
                for (P &x : next)
                    x = rewrite(x, transform);
            vector<pair<int, P>> moving;
            for (int i : cells(source))
                moving.emplace_back(i, name == "COPY" ? rewrite(contents[i], transform) : next[i]);
            if (name == "MOVE")
                for (auto &entry : moving)
                    next[entry.first] = {};
            for (auto &entry : moving)
                next[entry.first + dr * 26 + dc] = entry.second;
        } else if (name == "INSERTROW" || name == "DELETEROW" || name == "INSERTCOL" ||
                   name == "DELETECOL") {
            bool row = name.substr(name.size() - 3) == "ROW", insert = name.rfind("INSERT", 0) == 0;
            if (!regex_match(rest, regex(row ? "[1-9][0-9]?" : "[A-Z]")))
                throw runtime_error("bad address");
            int at = row ? stoi(rest) - 1 : rest[0] - 'A', limit = row ? 99 : 26;
            auto axis = [&](P x) { return row ? x->row : int(x->n); };
            auto change = [&](P x, int v) {
                return reference(row ? int(x->n) : v, row ? v : x->row, x->flags);
            };
            if (insert)
                for (int i = 0; i < 2574; i++)
                    if (contents[i] && (row ? i / 26 : i % 26) == limit - 1)
                        throw runtime_error(string("last ") + (row ? "row" : "column") +
                                            " not empty");
            function<P(P)> transform = [&](P x) {
                if (x->kind == 'R') {
                    int v = axis(x);
                    if (!insert && v == at)
                        return invalid;
                    int n = v + (insert ? (v >= at) : -(v > at));
                    return n >= limit ? invalid : change(x, n);
                }
                int a = axis(x->a), b = axis(x->b);
                if (!insert && a == at && b == at)
                    return invalid;
                int u = a + (insert ? (a >= at) : -(a > at)),
                    v = b + (insert ? (b >= at) : -(b >= at));
                return v >= limit ? invalid : rangeOf(change(x->a, u), change(x->b, v));
            };
            next = {};
            for (int i = 0; i < 2574; i++)
                if (contents[i]) {
                    P r = reference(i % 26, i / 26);
                    int v = axis(r);
                    if (!insert && v == at)
                        continue;
                    P t = change(r, v + (insert ? (v >= at) : -(v > at)));
                    next[indexOf(t)] = rewrite(contents[i], transform);
                }
        } else
            throw runtime_error("unknown command");
        history.emplace_back(name, contents);
        int changed = replace(move(next));
        cout << name;
        if (name == "SET")
            cout << ' ' << addressOf(target) << '=' << notation(values[target]);
        cout << " changed=" << changed << '\n';
    }
};
int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    string line;
    getline(cin, line);
    Sheet sheet;
    while (n-- && getline(cin, line)) {
        try {
            sheet.execute(line);
        } catch (const runtime_error &e) {
            cout << "ERROR " << e.what() << '\n';
        }
    }
}
