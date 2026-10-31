#include <algorithm>
#include <cstdlib>
#include <iostream>
#include <map>
#include <numeric>
#include <optional>
#include <queue>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using namespace std;
using Integer = long long;

struct Rational {
    Integer numerator, denominator;
    Rational(Integer p = 0, Integer q = 1) {
        if (q < 0) {
            p = -p;
            q = -q;
        }
        Integer divisor = gcd(abs(p), q);
        numerator = p / divisor;
        denominator = q / divisor;
    }
    string fraction() const {
        return to_string(numerator) + (denominator == 1 ? "" : "/" + to_string(denominator));
    }
    string value() const {
        Integer scaled = abs(numerator) * 1000000 / denominator;
        string digits = to_string(scaled % 1000000);
        string decimal = (numerator < 0 ? "-" : "") + to_string(scaled / 1000000) + "." + string(6 - digits.size(), '0') + digits;
        return fraction() + " (" + decimal + ")";
    }
    Rational operator-() const {
        return {-numerator, denominator};
    }
    friend Rational operator+(Rational a, Rational b) {
        return {a.numerator * b.denominator + b.numerator * a.denominator, a.denominator * b.denominator};
    }
    friend Rational operator-(Rational a, Rational b) {
        return a + -b;
    }
    friend Rational operator*(Rational a, Rational b) {
        return {a.numerator * b.numerator, a.denominator * b.denominator};
    }
    friend Rational operator/(Rational a, Rational b) {
        return {a.numerator * b.denominator, a.denominator * b.numerator};
    }
    friend bool operator==(Rational a, Rational b) {
        return a.numerator == b.numerator && a.denominator == b.denominator;
    }
    friend bool operator!=(Rational a, Rational b) {
        return !(a == b);
    }
    friend bool operator<(Rational a, Rational b) {
        return a.numerator * b.denominator < b.numerator * a.denominator;
    }
    Rational& operator+=(Rational b) {
        return *this = *this + b;
    }
    Rational& operator-=(Rational b) {
        return *this = *this - b;
    }
};
using Matrix = vector<vector<Rational>>;
using Column = vector<Rational>;

[[noreturn]] void failure(const string& reason) {
    throw runtime_error(reason);
}
void require(bool condition, const string& reason) {
    if (!condition) failure(reason);
}
vector<string> words(const string& text) {
    istringstream input(text);
    vector<string> result;
    string word;
    while (input >> word) result.push_back(word);
    return result;
}
bool digits(const string& text) {
    return !text.empty() && all_of(text.begin(), text.end(), [](char ch) {
        return ch >= '0' && ch <= '9';
    });
}
Rational number(string text) {
    const string original = text;
    Rational multiplier = 1;
    if (text.size() >= 3 && text.compare(text.size() - 3, 3, "meg") == 0) {
        text.resize(text.size() - 3);
        multiplier = 1000000;
    } else if (!text.empty() && string("kmu").find(text.back()) != string::npos) {
        char suffix = text.back();
        text.pop_back();
        multiplier = suffix == 'k' ? Rational(1000) : suffix == 'm' ? Rational(1, 1000) : Rational(1, 1000000);
    }
    bool negative = !text.empty() && text[0] == '-';
    if (negative) text.erase(0, 1);
    size_t slash = text.find('/'), point = text.find('.');
    Rational result;
    if (slash != string::npos) {
        string top = text.substr(0, slash), bottom = text.substr(slash + 1);
        require(digits(top) && digits(bottom), "invalid value " + original);
        Integer denominator = stoll(bottom);
        require(denominator != 0, "invalid value " + original);
        result = Rational(stoll(top), denominator);
    } else if (point != string::npos) {
        string whole = text.substr(0, point), fractional = text.substr(point + 1);
        require(digits(whole) && digits(fractional), "invalid value " + original);
        Integer denominator = 1;
        for (size_t i = 0; i < fractional.size(); ++i) denominator *= 10;
        result = Rational(stoll(whole + fractional), denominator);
    } else {
        require(digits(text), "invalid value " + original);
        result = Rational(stoll(text));
    }
    return (negative ? -result : result) * multiplier;
}
bool valid_node(const string& name) {
    if (name == "0") return true;
    return !name.empty() && name.size() <= 8 && name[0] >= 'a' && name[0] <= 'z' &&
           all_of(name.begin(), name.end(), [](char ch) {
               return (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9');
           });
}
struct Element {
    string name, n1, n2, c1, c2, control;
    char kind;
    Rational value;
    bool voltage_type() const {
        return kind == 'V' || kind == 'E' || kind == 'H';
    }
    bool independent() const {
        return kind == 'V' || kind == 'I';
    }
    vector<string> terminals() const {
        return kind == 'E' || kind == 'G' ? vector<string>{n1, n2, c1, c2} : vector<string>{n1, n2};
    }
};
vector<string> circuit_nodes(const vector<Element>& elements) {
    set<string> nodes;
    for (const auto& element : elements) for (const auto& terminal : element.terminals()) if (terminal != "0") nodes.insert(terminal);
    return {nodes.begin(), nodes.end()};
}
struct DisjointSet {
    vector<int> parent;
    explicit DisjointSet(int count) : parent(count) {
        iota(parent.begin(), parent.end(), 0);
    }
    int root(int value) {
        return parent[value] == value ? value : parent[value] = root(parent[value]);
    }
    void unite(int a, int b) {
        a = root(a);
        b = root(b);
        if (a > b) swap(a, b);
        parent[b] = a;
    }
};
set<string> reachable(const map<string, vector<string>>& adjacency, const string& start) {
    set<string> result{start};
    queue<string> pending;
    pending.push(start);
    while (!pending.empty()) {
        string current = pending.front();
        pending.pop();
        auto found = adjacency.find(current);
        if (found == adjacency.end()) continue;
        for (const auto& next : found->second) if (result.insert(next).second) pending.push(next);
    }
    return result;
}
vector<string> floating(const vector<Element>& elements, const vector<string>& nodes) {
    map<string, vector<string>> adjacency;
    for (const auto& e : elements) if (e.kind == 'R' || e.voltage_type()) {
        adjacency[e.n1].push_back(e.n2);
        adjacency[e.n2].push_back(e.n1);
    }
    auto grounded = reachable(adjacency, "0");
    vector<string> result;
    for (const auto& node : nodes) if (!grounded.count(node)) result.push_back(node);
    return result;
}
vector<string> voltage_loops(const vector<Element>& elements, const vector<string>& nodes) {
    map<string, int> indices{{"0", 0}};
    for (const auto& node : nodes) indices[node] = indices.size();
    DisjointSet groups(indices.size());
    vector<string> result;
    for (const auto& e : elements) if (e.voltage_type()) {
        int a = indices.at(e.n1), b = indices.at(e.n2);
        if (groups.root(a) == groups.root(b)) result.push_back(e.name);
        groups.unite(a, b);
    }
    return result;
}
void structure(const vector<Element>& elements) {
    auto nodes = circuit_nodes(elements);
    require(!nodes.empty(), "no nodes");
    auto ungrounded = floating(elements, nodes);
    if (!ungrounded.empty()) failure("floating node " + ungrounded[0]);
    auto loops = voltage_loops(elements, nodes);
    if (!loops.empty()) failure("voltage source loop at " + loops[0]);
}
optional<Column> solve(Matrix matrix, Column right) {
    size_t n = matrix.size();
    for (size_t i = 0; i < n; ++i) matrix[i].push_back(right[i]);
    for (size_t k = 0; k < n; ++k) {
        size_t row = k;
        while (row < n && matrix[row][k] == Rational(0)) ++row;
        if (row == n) return nullopt;
        if (row != k) swap(matrix[row], matrix[k]);
        Rational pivot = matrix[k][k];
        for (size_t j = 0; j <= n; ++j) matrix[k][j] = matrix[k][j] / pivot;
        for (size_t i = 0; i < n; ++i) if (i != k && matrix[i][k] != Rational(0)) {
            Rational factor = matrix[i][k];
            for (size_t j = 0; j <= n; ++j) matrix[i][j] -= factor * matrix[k][j];
        }
    }
    Column result;
    for (size_t i = 0; i < n; ++i) result.push_back(matrix[i][n]);
    return result;
}
struct Equations {
    vector<string> nodes, labels, unknowns;
    map<string, int> node_indices, source_indices;
    Matrix matrix;
    Column right;
    int node(const string& name) const {
        return name == "0" ? -1 : node_indices.at(name);
    }
    int source(const string& name) const {
        return source_indices.at(name);
    }
    static void add(Column& column, int row, Rational value) {
        if (row >= 0) column[row] += value;
    }
    void add(int row, int column, Rational value) {
        if (row >= 0 && column >= 0) matrix[row][column] += value;
    }
    Column source_right(const Element& e, Rational value) const {
        Column result(right.size());
        if (e.kind == 'V') result[source(e.name)] += value;
        else {
            add(result, node(e.n1), -value);
            add(result, node(e.n2), value);
        }
        return result;
    }
    Column injection(const string& a, const string& b) const {
        Column result(right.size());
        add(result, node(a), 1);
        add(result, node(b), -Rational(1));
        return *solve(matrix, result);
    }
    Rational voltage(const Column& solution, const string& name) const {
        return name == "0" ? Rational(0) : solution[node(name)];
    }
    Rational current(const Column& solution, const Element& e) const {
        if (e.voltage_type()) return solution[source(e.name)];
        if (e.kind == 'R') return (voltage(solution, e.n1) - voltage(solution, e.n2)) / e.value;
        if (e.kind == 'I') return e.value;
        if (e.kind == 'G') return e.value * (voltage(solution, e.c1) - voltage(solution, e.c2));
        return e.value * solution[source(e.control)];
    }
    explicit Equations(const vector<Element>& elements) {
        nodes = circuit_nodes(elements);
        for (const auto& name : nodes) {
            node_indices[name] = labels.size();
            labels.push_back(name);
            unknowns.push_back("V(" + name + ")");
        }
        for (const auto& e : elements) if (e.voltage_type()) {
            source_indices[e.name] = labels.size();
            labels.push_back(e.name);
            unknowns.push_back("I(" + e.name + ")");
        }
        matrix.assign(labels.size(), Column(labels.size()));
        right.resize(labels.size());
        for (const auto& e : elements) {
            int a = node(e.n1), b = node(e.n2);
            Rational w = e.value;
            if (e.kind == 'R') {
                Rational conductance = Rational(1) / w;
                add(a, a, conductance);
                add(b, b, conductance);
                add(a, b, -conductance);
                add(b, a, -conductance);
            } else if (e.kind == 'I') {
                add(right, a, -w);
                add(right, b, w);
            } else if (e.kind == 'G') {
                int c = node(e.c1), d = node(e.c2);
                add(a, c, w);
                add(b, d, w);
                add(a, d, -w);
                add(b, c, -w);
            } else if (e.kind == 'F') {
                int control = source(e.control);
                add(a, control, w);
                add(b, control, -w);
            } else {
                int s = source(e.name);
                add(a, s, 1);
                add(s, a, 1);
                add(b, s, -Rational(1));
                add(s, b, -Rational(1));
                if (e.kind == 'V') right[s] += w;
                else if (e.kind == 'E') {
                    add(s, node(e.c1), -w);
                    add(s, node(e.c2), w);
                }
                else add(s, source(e.control), -w);
            }
        }
    }
};

class Circuit {
    vector<Element> elements;
    size_t element_index(const string& name) const {
        for (size_t i = 0; i < elements.size(); ++i) if (elements[i].name == name) return i;
        failure("unknown element " + name);
    }
    void node_check(const string& name) const {
        if (name == "0") return;
        auto nodes = circuit_nodes(elements);
        require(find(nodes.begin(), nodes.end(), name) != nodes.end(), "unknown node " + name);
    }
    void add_element(const vector<string>& fields) {
        string name = fields[0];
        char kind = name[0];
        require(string("RVIEGFH").find(kind) != string::npos, "unknown element type " + name);
        size_t count = kind == 'E' || kind == 'G' ? 6 : kind == 'F' || kind == 'H' ? 5 : 4;
        require(fields.size() == count, "wrong field count for " + name);
        for (const auto& e : elements) require(e.name != name, "duplicate element " + name);
        Element e;
        e.name = name;
        e.kind = kind;
        e.n1 = fields[1];
        e.n2 = fields[2];
        if (kind == 'E' || kind == 'G') {
            e.c1 = fields[3];
            e.c2 = fields[4];
        }
        for (const auto& terminal : e.terminals()) require(valid_node(terminal), "invalid node " + terminal);
        if (kind == 'F' || kind == 'H') {
            e.control = fields[3];
            bool found = false;
            for (const auto& existing : elements) if (existing.name == e.control && existing.kind == 'V') found = true;
            require(found, "unknown voltage source " + e.control);
        }
        e.value = number(fields.back());
        require(kind != 'R' || Rational(0) < e.value, "nonpositive resistance " + name);
        elements.push_back(e);
    }
    void equivalent(const string& a, const string& b, ostringstream& output) const {
        auto nodes = circuit_nodes(elements);
        nodes.insert(nodes.begin(), "0");
        map<string, int> index;
        for (size_t i = 0; i < nodes.size(); ++i) index[nodes[i]] = i;
        DisjointSet groups(nodes.size());
        for (const auto& e : elements) if (e.kind == 'V') groups.unite(index.at(e.n1), index.at(e.n2));
        int start = groups.root(index.at(a)), target = groups.root(index.at(b));
        if (start == target) {
            output << "Req = " << Rational(0).value() << '\n';
            return;
        }
        struct Edge {
            int a, b;
            Rational conductance;
        };
        vector<Edge> edges;
        map<int, vector<int>> adjacency;
        for (const auto& e : elements) if (e.kind == 'R') {
            int u = groups.root(index.at(e.n1)), v = groups.root(index.at(e.n2));
            if (u == v) continue;
            edges.push_back({u, v, Rational(1) / e.value});
            adjacency[u].push_back(v);
            adjacency[v].push_back(u);
        }
        set<int> component{start};
        queue<int> pending;
        pending.push(start);
        while (!pending.empty()) {
            int u = pending.front();
            pending.pop();
            for (int v : adjacency[u]) if (component.insert(v).second) pending.push(v);
        }
        if (!component.count(target)) {
            output << "Req = INFINITE\n";
            return;
        }
        map<int, int> columns;
        for (int group : component) if (group != target) columns[group] = columns.size();
        Matrix conductances(columns.size(), Column(columns.size()));
        Column right(columns.size());
        auto add = [&](int row, int column, Rational value) {
            if (row != target && column != target) conductances[columns.at(row)][columns.at(column)] += value;
        };
        for (const auto& edge : edges) if (component.count(edge.a)) {
            add(edge.a, edge.a, edge.conductance);
            add(edge.b, edge.b, edge.conductance);
            add(edge.a, edge.b, -edge.conductance);
            add(edge.b, edge.a, -edge.conductance);
        }
        right[columns.at(start)] = 1;
        auto solution = solve(conductances, right);
        output << "Req = " << (*solution)[columns.at(start)].value() << '\n';
    }
    void reduce(const string& a, const string& b, ostringstream& output) const {
        if (a == b) {
            output << "Req = " << Rational(0).value() << '\n';
            return;
        }
        struct Resistor {
            string name, a, b;
            Rational value;
        };
        vector<Resistor> list;
        map<string, vector<string>> adjacency;
        for (const auto& e : elements) if (e.kind == 'R') {
            list.push_back({e.name, e.n1, e.n2, e.value});
            adjacency[e.n1].push_back(e.n2);
            adjacency[e.n2].push_back(e.n1);
        }
        auto component = reachable(adjacency, a);
        if (!component.count(b)) {
            output << "Req = INFINITE\n";
            return;
        }
        list.erase(remove_if(list.begin(), list.end(), [&](const Resistor& r) {
            return !component.count(r.a);
        }), list.end());
        int created = 0;
        while (true) {
            size_t remove = list.size();
            for (size_t i = 0; i < list.size(); ++i) if (list[i].a == list[i].b) {
                remove = i;
                break;
            }
            map<string, vector<size_t>> ends;
            for (size_t i = 0; i < list.size(); ++i) {
                ends[list[i].a].push_back(i);
                ends[list[i].b].push_back(i);
            }
            if (remove == list.size()) for (const auto& [node, incidents] : ends)
                if (node != a && node != b && incidents.size() == 1) {
                    remove = incidents[0];
                    break;
                }
            if (remove != list.size()) {
                output << "remove " << list[remove].name << '\n';
                list.erase(list.begin() + remove);
                continue;
            }
            size_t first = list.size(), second = list.size();
            for (size_t i = 0; i < list.size() && first == list.size(); ++i)
                for (size_t j = i + 1; j < list.size(); ++j)
                    if ((list[i].a == list[j].a && list[i].b == list[j].b) || (list[i].a == list[j].b && list[i].b == list[j].a)) {
                        first = i;
                        second = j;
                        break;
                    }
            bool parallel = first < list.size();
            string middle;
            if (!parallel) for (const auto& [node, incidents] : ends)
                if (node != a && node != b && incidents.size() == 2) {
                    first = incidents[0];
                    second = incidents[1];
                    middle = node;
                    break;
                }
            if (first == list.size()) break;
            Resistor x = list[first], y = list[second];
            Resistor next;
            next.name = "#" + to_string(++created);
            if (parallel) {
                next.a = x.a;
                next.b = x.b;
                next.value = x.value * y.value / (x.value + y.value);
            } else {
                next.a = x.a == middle ? x.b : x.a;
                next.b = y.a == middle ? y.b : y.a;
                next.value = x.value + y.value;
            }
            output << next.name << " = " << x.name << (parallel ? " || " : " + ") << y.name << " = " << next.value.value() << '\n';
            list.erase(list.begin() + second);
            list.erase(list.begin() + first);
            list.push_back(next);
        }
        if (list.size() == 1) output << "Req = " << list[0].value.value() << '\n';
        else output << "not series-parallel: " << list.size() << " resistors remain\n";
    }
    void check_structure(ostringstream& output) const {
        auto nodes = circuit_nodes(elements);
        if (nodes.empty()) {
            output << "no nodes\n";
            return;
        }
        bool problem = false;
        for (const auto& node : nodes) {
            int count = 0;
            for (const auto& e : elements) count += int(e.n1 == node) + int(e.n2 == node);
            if (count < 2) {
                output << "dangling node " << node << '\n';
                problem = true;
            }
        }
        for (const auto& node : floating(elements, nodes)) {
            output << "floating node " << node << '\n';
            problem = true;
        }
        for (const auto& name : voltage_loops(elements, nodes)) {
            output << "voltage source loop at " << name << '\n';
            problem = true;
        }
        if (problem) return;
        Equations equations(elements);
        output << (solve(equations.matrix, equations.right) ? "ok" : "singular matrix") << '\n';
    }
public:
    string line(const string& text) {
        if (text[0] == '*') return "";
        auto fields = words(text);
        if (text[0] != '.') {
            add_element(fields);
            return "";
        }
        string command = fields[0];
        static const map<string, size_t> arities = {
            {".OP",0},{".CURRENT",1},{".VOLTAGE",2},{".POWER",0},{".KCL",1},{".THEVENIN",2},{".NORTON",2},
            {".MAXPOWER",2},{".TF",2},{".SENS",1},{".ZPARAM",4},{".SUPERPOSITION",1},{".SWEEP",5},{".MATRIX",0},
            {".REQ",2},{".REDUCE",2},{".CHECK",0},{".ALTER",2},{".DELETE",1},{".CLEAR",0},{".NODES",0},{".PRINT",0}
        };
        require(arities.count(command), "unknown command " + command);
        require(fields.size() == arities.at(command) + 1, "wrong argument count for " + command);
        vector<string> args(fields.begin() + 1, fields.end());
        ostringstream output;
        auto write = [&](const string& label, Rational value) {
            output << label << " = " << value.value() << '\n';
        };
        if (command == ".ALTER") {
            size_t i = element_index(args[0]);
            Rational value = number(args[1]);
            require(elements[i].kind != 'R' || Rational(0) < value, "nonpositive resistance " + args[0]);
            output << "altered " << args[0] << ": " << elements[i].value.fraction() << " -> " << value.fraction() << '\n';
            elements[i].value = value;
        } else if (command == ".DELETE") {
            size_t i = element_index(args[0]);
            for (const auto& e : elements) if ((e.kind == 'F' || e.kind == 'H') && e.control == args[0]) failure(args[0] + " is referenced by " + e.name);
            elements.erase(elements.begin() + i);
            output << "deleted " << args[0] << '\n';
        } else if (command == ".CLEAR") {
            output << "cleared " << elements.size() << " elements\n";
            elements.clear();
        } else if (command == ".NODES") {
            set<string> nodes;
            for (const auto& e : elements) for (const auto& terminal : e.terminals()) nodes.insert(terminal);
            if (nodes.empty()) output << "no nodes\n";
            for (const auto& node : nodes) {
                output << node << ':';
                for (const auto& e : elements) {
                    auto terminals = e.terminals();
                    if (find(terminals.begin(), terminals.end(), node) != terminals.end()) output << ' ' << e.name;
                }
                output << '\n';
            }
        } else if (command == ".PRINT") {
            if (elements.empty()) output << "empty netlist\n";
            for (const auto& e : elements) {
                output << e.name << ' ' << e.n1 << ' ' << e.n2;
                if (e.kind == 'E' || e.kind == 'G') output << ' ' << e.c1 << ' ' << e.c2;
                if (e.kind == 'F' || e.kind == 'H') output << ' ' << e.control;
                output << ' ' << e.value.fraction() << '\n';
            }
        } else if (command == ".CHECK") check_structure(output);
        else if (command == ".REQ" || command == ".REDUCE") {
            node_check(args[0]);
            node_check(args[1]);
            if (command == ".REQ") equivalent(args[0], args[1], output);
            else reduce(args[0], args[1], output);
        } else if (command == ".SWEEP") {
            size_t i = element_index(args[0]);
            Rational from = number(args[1]), to = number(args[2]), step = number(args[3]);
            node_check(args[4]);
            require(Rational(0) < step, "invalid sweep step");
            require(!(to < from), "invalid sweep range");
            Rational ratio = (to - from) / step;
            Integer count = ratio.numerator / ratio.denominator + 1;
            require(count <= 20, "too many sweep points");
            require(elements[i].kind != 'R' || Rational(0) < from, "nonpositive resistance " + args[0]);
            structure(elements);
            auto temporary = elements;
            for (Integer k = 0; k < count; ++k) {
                Rational value = from + Rational(k) * step;
                temporary[i].value = value;
                Equations equations(temporary);
                auto solution = solve(equations.matrix, equations.right);
                output << args[0] << " = " << value.fraction() << ": ";
                if (!solution) output << "singular matrix\n";
                else output << "V(" << args[4] << ") = " << equations.voltage(*solution, args[4]).value() << '\n';
            }
        } else {
            if (command == ".CURRENT") element_index(args[0]);
            else if (command == ".TF") {
                node_check(args[0]);
                size_t i = element_index(args[1]);
                require(elements[i].independent(), "not an independent source " + args[1]);
            } else for (const auto& argument : args) node_check(argument);
            structure(elements);
            Equations equations(elements);
            if (command == ".MATRIX") {
                output << "unknowns:";
                for (const auto& name : equations.unknowns) output << ' ' << name;
                output << '\n';
                for (size_t i = 0; i < equations.labels.size(); ++i) {
                    output << equations.labels[i] << ':';
                    for (Rational value : equations.matrix[i]) output << ' ' << value.fraction();
                    output << " | " << equations.right[i].fraction() << '\n';
                }
                return output.str();
            }
            auto solved = solve(equations.matrix, equations.right);
            require(bool(solved), "singular matrix");
            const Column& operating = *solved;
            auto voltage = [&](const string& node) {
                return equations.voltage(operating, node);
            };
            if (command == ".OP") {
                for (const auto& node : equations.nodes) write("V(" + node + ")", voltage(node));
                for (const auto& e : elements) if (e.voltage_type()) write("I(" + e.name + ")", equations.current(operating, e));
            } else if (command == ".CURRENT") {
                const auto& e = elements[element_index(args[0])];
                write("I(" + e.name + ")", equations.current(operating, e));
            } else if (command == ".VOLTAGE") write("V(" + args[0] + "," + args[1] + ")", voltage(args[0]) - voltage(args[1]));
            else if (command == ".POWER") {
                Rational absorbed, delivered, total;
                for (const auto& e : elements) {
                    Rational power = (voltage(e.n1) - voltage(e.n2)) * equations.current(operating, e);
                    write("P(" + e.name + ")", power);
                    if (Rational(0) < power) absorbed += power;
                    if (power < Rational(0)) delivered -= power;
                    total += power;
                }
                write("absorbed", absorbed);
                write("delivered", delivered);
                write("total", total);
            } else if (command == ".KCL") {
                Rational total;
                for (const auto& e : elements) if (e.n1 == args[0] || e.n2 == args[0]) {
                    Rational current = equations.current(operating, e);
                    Rational leaving = e.n1 == e.n2 ? Rational(0) : e.n1 == args[0] ? current : -current;
                    write("I(" + e.name + ") leaving " + args[0], leaving);
                    total += leaving;
                }
                write("sum", total);
            } else if (command == ".THEVENIN" || command == ".NORTON" || command == ".MAXPOWER") {
                Rational vth = voltage(args[0]) - voltage(args[1]);
                Column injection = equations.injection(args[0], args[1]);
                Rational rth = equations.voltage(injection, args[0]) - equations.voltage(injection, args[1]);
                if (command == ".THEVENIN") {
                    write("Vth", vth);
                    write("Rth", rth);
                }
                else if (command == ".NORTON") {
                    require(rth != Rational(0), "zero thevenin resistance");
                    write("In", vth / rth);
                    write("Rn", rth);
                } else {
                    require(Rational(0) < rth, "nonpositive thevenin resistance");
                    write("RL", rth);
                    write("Pmax", vth * vth / (Rational(4) * rth));
                }
            } else if (command == ".TF") {
                const auto& source = elements[element_index(args[1])];
                Column alone = *solve(equations.matrix, equations.source_right(source, 1));
                write("gain", equations.voltage(alone, args[0]));
                if (source.kind == 'V') {
                    Rational current = alone[equations.source(source.name)];
                    if (current == Rational(0)) output << "input resistance = INFINITE\n";
                    else write("input resistance", -Rational(1) / current);
                } else write("input resistance", equations.voltage(alone, source.n2) - equations.voltage(alone, source.n1));
                write("output resistance", equations.voltage(equations.injection(args[0], "0"), args[0]));
            } else if (command == ".SENS") {
                for (const auto& e : elements) {
                    Column derivative(equations.right.size());
                    int a = equations.node(e.n1), b = equations.node(e.n2);
                    if (e.kind == 'R') {
                        Rational value = equations.current(operating, e) / e.value;
                        Equations::add(derivative, a, value);
                        Equations::add(derivative, b, -value);
                    } else if (e.kind == 'I') {
                        Equations::add(derivative, a, -Rational(1));
                        Equations::add(derivative, b, 1);
                    } else if (e.kind == 'G' || e.kind == 'F') {
                        Rational value = e.kind == 'G' ? voltage(e.c1) - voltage(e.c2) : operating[equations.source(e.control)];
                        Equations::add(derivative, a, -value);
                        Equations::add(derivative, b, value);
                    } else {
                        Rational value = e.kind == 'V' ? Rational(1) : e.kind == 'E' ? voltage(e.c1) - voltage(e.c2) : operating[equations.source(e.control)];
                        derivative[equations.source(e.name)] += value;
                    }
                    Column solution = *solve(equations.matrix, derivative);
                    write("dV(" + args[0] + ")/d" + e.name, equations.voltage(solution, args[0]));
                }
            } else if (command == ".ZPARAM") {
                Column first = equations.injection(args[0], args[1]);
                Column second = equations.injection(args[2], args[3]);
                write("z11", equations.voltage(first, args[0]) - equations.voltage(first, args[1]));
                write("z12", equations.voltage(second, args[0]) - equations.voltage(second, args[1]));
                write("z21", equations.voltage(first, args[2]) - equations.voltage(first, args[3]));
                write("z22", equations.voltage(second, args[2]) - equations.voltage(second, args[3]));
            } else if (command == ".SUPERPOSITION") {
                Rational total;
                for (const auto& e : elements) if (e.independent()) {
                    Column alone = *solve(equations.matrix, equations.source_right(e, e.value));
                    Rational value = equations.voltage(alone, args[0]);
                    write(e.name + ": V(" + args[0] + ")", value);
                    total += value;
                }
                write("total: V(" + args[0] + ")", total);
            }
        }
        return output.str();
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    Circuit circuit;
    string line;
    int number = 0;
    while (getline(cin, line) && line != ".END") {
        ++number;
        try {
            cout << circuit.line(line);
        }
        catch (const runtime_error& error) {
            cout << "error: line " << number << ": " << error.what() << '\n';
        }
    }
}
