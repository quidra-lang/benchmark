#include <algorithm>
#include <cctype>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <map>
#include <numeric>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using Integer = std::int64_t;

struct Fraction {
    Integer numerator;
    Integer denominator;

    Fraction(Integer n = 0, Integer d = 1) {
        if (d < 0) { n = -n; d = -d; }
        const Integer divisor = std::gcd(n, d);
        numerator = n / divisor;
        denominator = d / divisor;
    }

    friend Fraction operator+(Fraction a, Fraction b) {
        return {a.numerator * b.denominator + b.numerator * a.denominator,
                a.denominator * b.denominator};
    }
    friend Fraction operator-(Fraction a, Fraction b) {
        return {a.numerator * b.denominator - b.numerator * a.denominator,
                a.denominator * b.denominator};
    }
    friend Fraction operator*(Fraction a, Fraction b) {
        return {a.numerator * b.numerator, a.denominator * b.denominator};
    }
    friend Fraction operator/(Fraction a, Fraction b) {
        return {a.numerator * b.denominator, a.denominator * b.numerator};
    }
    friend bool operator==(Fraction a, Fraction b) {
        return a.numerator == b.numerator && a.denominator == b.denominator;
    }
    friend bool operator!=(Fraction a, Fraction b) { return !(a == b); }
    friend bool operator<(Fraction a, Fraction b) {
        return a.numerator * b.denominator < b.numerator * a.denominator;
    }
    friend bool operator<=(Fraction a, Fraction b) { return !(b < a); }
    friend std::ostream& operator<<(std::ostream& out, Fraction value) {
        return out << value.numerator << '/' << value.denominator;
    }

    Fraction absolute() const {
        return {numerator < 0 ? -numerator : numerator, denominator};
    }

    std::string value() const {
        std::ostringstream out;
        out << *this << '(' << numerator / denominator << '.'
            << std::setfill('0') << std::setw(6)
            << (numerator % denominator) * 1000000 / denominator << ')';
        return out.str();
    }
};

using Row = std::vector<Fraction>;
using Matrix = std::vector<Row>;
using States = std::vector<int>;
using Names = std::vector<std::string>;
using BooleanMatrix = std::vector<std::vector<bool>>;

struct CommandError : std::runtime_error {
    using std::runtime_error::runtime_error;
};

[[noreturn]] void fail(const std::string& message) { throw CommandError(message); }
const char* yes(bool condition) { return condition ? "yes" : "no"; }

Names split(const std::string& text, char delimiter = ' ') {
    std::istringstream input(text);
    Names parts;
    std::string part;
    while (std::getline(input, part, delimiter)) parts.push_back(part);
    return parts;
}

template<class T>
std::string join(const std::vector<T>& values, const std::string& delimiter = " ") {
    std::ostringstream out;
    for (std::size_t i = 0; i < values.size(); ++i) {
        if (i != 0) out << delimiter;
        out << values[i];
    }
    return out.str();
}

Fraction probability(const std::string& text) {
    const Names parts = split(text, '/');
    const Integer numerator = std::stoll(parts[0]);
    const Integer denominator = parts.size() == 2 ? std::stoll(parts[1]) : 1;
    if (denominator == 0 || numerator > denominator) fail("BAD PROBABILITY");
    return {numerator, denominator};
}

Fraction sum(const Row& values) {
    Fraction result;
    for (Fraction value : values) result = result + value;
    return result;
}

Matrix matrix(int rows, int columns) { return Matrix(rows, Row(columns)); }

Matrix identity(int size) {
    Matrix result = matrix(size, size);
    for (int i = 0; i < size; ++i) result[i][i] = 1;
    return result;
}

Matrix multiply(const Matrix& left, const Matrix& right) {
    Matrix result = matrix(static_cast<int>(left.size()), static_cast<int>(right[0].size()));
    for (std::size_t i = 0; i < left.size(); ++i)
        for (std::size_t j = 0; j < right[0].size(); ++j)
            for (std::size_t k = 0; k < right.size(); ++k)
                result[i][j] = result[i][j] + left[i][k] * right[k][j];
    return result;
}

Matrix eliminate(Matrix rows) {
    const int size = static_cast<int>(rows.size());
    const int width = static_cast<int>(rows[0].size());
    for (int column = 0; column < size; ++column) {
        int pivotRow = column;
        while (rows[pivotRow][column].numerator == 0) ++pivotRow;
        std::swap(rows[column], rows[pivotRow]);
        const Fraction pivot = rows[column][column];
        for (int j = 0; j < width; ++j) rows[column][j] = rows[column][j] / pivot;
        for (int i = 0; i < size; ++i) {
            const Fraction factor = rows[i][column];
            if (i == column || factor.numerator == 0) continue;
            for (int j = 0; j < width; ++j)
                rows[i][j] = rows[i][j] - factor * rows[column][j];
        }
    }
    Matrix result;
    for (const Row& row : rows) result.emplace_back(row.begin() + size, row.end());
    return result;
}

struct Chain {
    Names names;
    Matrix p;

    explicit Chain(Names stateNames = {})
        : names(std::move(stateNames)), p(matrix(size(), size())) {}

    int size() const { return static_cast<int>(names.size()); }

    int state(const std::string& name) const {
        for (int i = 0; i < size(); ++i) if (names[i] == name) return i;
        fail("UNKNOWN STATE " + name);
    }

    States states(const Names& requested) const {
        States result;
        std::set<int> seen;
        for (const std::string& name : requested) {
            const int index = state(name);
            if (!seen.insert(index).second) fail("DUPLICATE STATE " + name);
            result.push_back(index);
        }
        return result;
    }

    Names labels(const States& indices) const {
        Names result;
        for (int index : indices) result.push_back(names[index]);
        return result;
    }

    Fraction blockSum(int state, const States& block) const {
        Fraction result;
        for (int target : block) result = result + p[state][target];
        return result;
    }

    void display(const Matrix& values, const std::string& prefix = "ROW") const {
        std::cout << "STATES " << join(names) << '\n';
        for (int i = 0; i < size(); ++i)
            std::cout << prefix << ' ' << names[i] << ' ' << join(values[i]) << '\n';
    }
    void display() const { display(p); }
};

struct CommunicatingClass {
    States members;
    bool closed = true;
    std::vector<int> levels;
    int period = 0;
};

struct Decomposition {
    BooleanMatrix reach;
    std::vector<CommunicatingClass> classes;
    std::vector<int> classOf;

    explicit Decomposition(const Chain& chain)
        : reach(chain.size(), std::vector<bool>(chain.size())), classOf(chain.size(), -1) {
        const int n = chain.size();
        for (int i = 0; i < n; ++i)
            for (int j = 0; j < n; ++j)
                reach[i][j] = i == j || chain.p[i][j].numerator > 0;
        for (int k = 0; k < n; ++k)
            for (int i = 0; i < n; ++i)
                for (int j = 0; j < n; ++j)
                    reach[i][j] = reach[i][j] || (reach[i][k] && reach[k][j]);
        for (int root = 0; root < n; ++root) {
            if (classOf[root] != -1) continue;
            CommunicatingClass group;
            group.levels.assign(n, -1);
            std::vector<bool> inside(n);
            for (int j = 0; j < n; ++j) {
                if (!reach[root][j] || !reach[j][root]) continue;
                group.members.push_back(j);
                inside[j] = true;
                classOf[j] = static_cast<int>(classes.size());
            }
            for (int u : group.members)
                for (int v = 0; v < n; ++v)
                    if (chain.p[u][v].numerator > 0 && !inside[v]) group.closed = false;
            States queue{root};
            group.levels[root] = 0;
            for (std::size_t head = 0; head < queue.size(); ++head) {
                const int u = queue[head];
                for (int v : group.members) {
                    if (chain.p[u][v].numerator == 0 || group.levels[v] != -1) continue;
                    group.levels[v] = group.levels[u] + 1;
                    queue.push_back(v);
                }
            }
            for (int u : group.members)
                for (int v : group.members)
                    if (chain.p[u][v].numerator > 0)
                        group.period = std::gcd(group.period, group.levels[u] + 1 - group.levels[v]);
            classes.push_back(std::move(group));
        }
    }
};

Row stationary(const Chain& chain, const States& members) {
    const int size = static_cast<int>(members.size());
    Matrix rows = matrix(size, size + 1);
    for (int r = 0; r < size - 1; ++r)
        for (int k = 0; k < size; ++k)
            rows[r][k] = chain.p[members[k]][members[r]] - Fraction(k == r);
    std::fill(rows.back().begin(), rows.back().end(), Fraction(1));
    const Matrix solution = eliminate(std::move(rows));
    Row result;
    for (const Row& row : solution) result.push_back(row[0]);
    return result;
}

Row irreducible(const Chain& chain, const Decomposition& graph) {
    if (graph.classes.size() != 1) fail("NOT IRREDUCIBLE");
    return stationary(chain, graph.classes[0].members);
}

struct Hitting {
    Row probabilities;
    std::vector<std::optional<Fraction>> times;
};

Hitting hitting(const Chain& chain, const States& targets, const BooleanMatrix& reach,
                bool probabilityOnly = false) {
    const int n = chain.size();
    Hitting result{Row(n), std::vector<std::optional<Fraction>>(n)};
    std::vector<bool> inside(n);
    for (int target : targets) {
        inside[target] = true;
        result.probabilities[target] = 1;
        result.times[target] = Fraction(0);
    }
    States unknown;
    for (int i = 0; i < n; ++i) {
        if (inside[i]) continue;
        for (int target : targets) {
            if (!reach[i][target]) continue;
            unknown.push_back(i);
            break;
        }
    }
    if (!unknown.empty()) {
        const int size = static_cast<int>(unknown.size());
        Matrix rows = matrix(size, size + 1);
        for (int r = 0; r < size; ++r) {
            for (int k = 0; k < size; ++k)
                rows[r][k] = Fraction(r == k) - chain.p[unknown[r]][unknown[k]];
            rows[r][size] = chain.blockSum(unknown[r], targets);
        }
        const Matrix solution = eliminate(std::move(rows));
        for (int r = 0; r < size; ++r) result.probabilities[unknown[r]] = solution[r][0];
    }
    if (probabilityOnly) return result;
    States certain;
    for (int i : unknown) if (result.probabilities[i] == Fraction(1)) certain.push_back(i);
    if (!certain.empty()) {
        const int size = static_cast<int>(certain.size());
        Matrix rows = matrix(size, size + 1);
        for (int r = 0; r < size; ++r) {
            for (int k = 0; k < size; ++k)
                rows[r][k] = Fraction(r == k) - chain.p[certain[r]][certain[k]];
            rows[r][size] = 1;
        }
        const Matrix solution = eliminate(std::move(rows));
        for (int r = 0; r < size; ++r) result.times[certain[r]] = solution[r][0];
    }
    return result;
}

struct Absorption {
    States transient;
    States absorbing;
    Matrix fundamental;
    Row means;
    Row variances;
    Matrix probabilities;

    explicit Absorption(const Chain& chain) {
        for (int i = 0; i < chain.size(); ++i)
            (chain.p[i][i] == Fraction(1) ? absorbing : transient).push_back(i);
        const int t = static_cast<int>(transient.size());
        const int a = static_cast<int>(absorbing.size());
        if (t == 0) return;
        Matrix rows = matrix(t, 2 * t);
        for (int i = 0; i < t; ++i) {
            for (int j = 0; j < t; ++j)
                rows[i][j] = Fraction(i == j) - chain.p[transient[i]][transient[j]];
            rows[i][t + i] = 1;
        }
        fundamental = eliminate(std::move(rows));
        for (const Row& row : fundamental) means.push_back(sum(row));
        variances.resize(t);
        probabilities = matrix(t, a);
        for (int i = 0; i < t; ++i) {
            Fraction secondMoment;
            for (int j = 0; j < t; ++j)
                secondMoment = secondMoment + (Fraction(2) * fundamental[i][j] - Fraction(i == j)) * means[j];
            variances[i] = secondMoment - means[i] * means[i];
            for (int j = 0; j < a; ++j)
                for (int l = 0; l < t; ++l)
                    probabilities[i][j] = probabilities[i][j] + fundamental[i][l] * chain.p[transient[l]][absorbing[j]];
        }
    }
};

class Analyzer {
    std::map<std::string, Chain> chains;

    void create(const Names& words) {
        const std::string& name = words[1];
        const Names states(words.begin() + 2, words.end());
        if (states.size() > 10) fail("TOO MANY STATES");
        std::set<std::string> seen;
        for (const std::string& state : states)
            if (!seen.insert(state).second) fail("DUPLICATE STATE " + state);
        chains[name] = Chain(states);
        std::cout << "CHAIN " << name << " states=" << states.size() << '\n';
    }

    void build(const Names& words) {
        const std::string& name = words[1];
        const int order = std::stoi(words[2]);
        if (order != 1 && order != 2) fail("BAD ORDER");
        const int tokenCount = static_cast<int>(words.size()) - 3;
        if (tokenCount <= order) fail("TOO FEW TOKENS");
        Names names;
        States observations;
        for (int i = 0; i < tokenCount - order + 1; ++i) {
            const std::string observation = order == 1 ? words[i + 3] : words[i + 3] + '.' + words[i + 4];
            const Names::const_iterator position = std::find(names.cbegin(), names.cend(), observation);
            const int index = static_cast<int>(position - names.cbegin());
            if (position == names.cend()) names.push_back(observation);
            observations.push_back(index);
        }
        if (names.size() > 10) fail("TOO MANY STATES");
        Chain chain(names);
        const int n = chain.size();
        std::vector<std::vector<int>> counts(n, std::vector<int>(n));
        std::vector<int> totals(n);
        for (std::size_t i = 1; i < observations.size(); ++i) {
            ++counts[observations[i - 1]][observations[i]];
            ++totals[observations[i - 1]];
        }
        for (int i = 0; i < n; ++i) {
            if (totals[i] == 0) chain.p[i][i] = 1;
            else for (int j = 0; j < n; ++j) chain.p[i][j] = Fraction(counts[i][j], totals[i]);
        }
        chains[name] = chain;
        std::cout << "BUILD " << name << " order=" << order << " states=" << n
                  << " transitions=" << observations.size() - 1 << '\n';
        for (int i = 0; i < n; ++i) {
            std::cout << "FROM " << names[i] << " total=" << totals[i];
            if (totals[i] == 0) std::cout << " absorbing";
            else for (int j = 0; j < n; ++j)
                if (counts[i][j] > 0) std::cout << ' ' << names[j] << ':' << counts[i][j];
            std::cout << '\n';
        }
    }

    void gambler(const Names& words) {
        const std::string& name = words[1];
        const int goal = std::stoi(words[2]);
        const int start = std::stoi(words[3]);
        if (goal == 0 || goal > 9) fail("BAD SIZE");
        if (start > goal) fail("BAD START");
        const Fraction chance = probability(words[4]);
        if (chance == Fraction(0) || chance == Fraction(1)) fail("BAD PROBABILITY");
        Names names;
        for (int i = 0; i <= goal; ++i) names.push_back("s" + std::to_string(i));
        Chain chain(names);
        chain.p[0][0] = chain.p[goal][goal] = 1;
        for (int i = 1; i < goal; ++i) {
            chain.p[i][i + 1] = chance;
            chain.p[i][i - 1] = Fraction(1) - chance;
        }
        const Absorption data(chain);
        Row ruin(goal + 1), duration(goal + 1);
        ruin[0] = 1;
        for (int i = 1; i < goal; ++i) {
            ruin[i] = data.probabilities[i - 1][0];
            duration[i] = data.means[i - 1];
        }
        chains[name] = chain;
        std::cout << "GAMBLER " << name << " g=" << goal << " p=" << chance
                  << " start=" << names[start] << " ruin=" << ruin[start].value()
                  << " duration=" << duration[start].value() << '\n';
        for (int i = 0; i <= goal; ++i)
            std::cout << "CAPITAL " << names[i] << " ruin=" << ruin[i].value()
                      << " win=" << (Fraction(1) - ruin[i]).value()
                      << " duration=" << duration[i].value() << '\n';
    }

    bool edit(const Names& words, Chain& chain) {
        const std::string& command = words[0];
        const std::string& name = words[1];
        const int n = chain.size();
        if (command == "P") {
            const int from = chain.state(words[2]);
            const int to = chain.state(words[3]);
            const Fraction value = probability(words[4]);
            chain.p[from][to] = value;
            std::cout << "P " << name << ' ' << words[2] << ' ' << words[3] << ' ' << value
                      << " rowsum=" << sum(chain.p[from]) << '\n';
        } else if (command == "ROW") {
            const int state = chain.state(words[2]);
            if (static_cast<int>(words.size()) - 3 != n) fail("BAD LENGTH");
            Row values;
            for (std::size_t i = 3; i < words.size(); ++i) values.push_back(probability(words[i]));
            chain.p[state] = values;
            std::cout << "ROW " << name << ' ' << words[2] << " rowsum=" << sum(values) << '\n';
        } else if (command == "SHOW") {
            std::cout << "MATRIX " << name << " states=" << n << '\n';
            chain.display();
        } else if (command == "CHECK") {
            std::vector<std::pair<int, Fraction>> bad;
            for (int i = 0; i < n; ++i) {
                const Fraction total = sum(chain.p[i]);
                if (total != Fraction(1)) bad.emplace_back(i, total);
            }
            if (bad.empty()) std::cout << "CHECK " << name << " ok\n";
            else {
                std::cout << "CHECK " << name << " bad=" << bad.size() << '\n';
                for (const std::pair<int, Fraction>& row : bad)
                    std::cout << "BADROW " << chain.names[row.first] << " sum=" << row.second << '\n';
            }
        } else return false;
        return true;
    }

    void analyze(const Names& words, const Chain& chain) {
        const std::string& command = words[0];
        const std::string& name = words[1];
        const int n = chain.size();
        for (int i = 0; i < n; ++i)
            if (sum(chain.p[i]) != Fraction(1)) fail("NOT STOCHASTIC " + chain.names[i]);
        const Decomposition graph(chain);
        if (command == "CLASSES") {
            std::cout << "CLASSES " << name << " count=" << graph.classes.size() << '\n';
            for (std::size_t index = 0; index < graph.classes.size(); ++index) {
                const CommunicatingClass& group = graph.classes[index];
                std::cout << "CLASS " << index + 1 << ' ' << (group.closed ? "RECURRENT" : "TRANSIENT")
                          << " period=" << group.period << " size=" << group.members.size()
                          << ' ' << join(chain.labels(group.members)) << '\n';
                if (group.period >= 2) {
                    for (int residue = 0; residue < group.period; ++residue) {
                        States cyclic;
                        for (int i : group.members)
                            if (group.levels[i] % group.period == residue) cyclic.push_back(i);
                        std::cout << "CYCLIC " << residue << ' ' << join(chain.labels(cyclic)) << '\n';
                    }
                }
            }
        } else if (command == "CLASSIFY") {
            States absorbing;
            for (int i = 0; i < n; ++i) if (chain.p[i][i] == Fraction(1)) absorbing.push_back(i);
            bool absorbs = !absorbing.empty();
            for (int i = 0; i < n; ++i) {
                bool reaches = false;
                for (int target : absorbing) reaches = reaches || graph.reach[i][target];
                absorbs = absorbs && reaches;
            }
            BooleanMatrix edges(n, std::vector<bool>(n));
            for (int i = 0; i < n; ++i)
                for (int j = 0; j < n; ++j) edges[i][j] = chain.p[i][j].numerator > 0;
            BooleanMatrix power = edges;
            int exponent = 0;
            const int bound = (n - 1) * (n - 1) + 1;
            for (int t = 1; t <= bound; ++t) {
                bool positive = true;
                for (const std::vector<bool>& row : power)
                    for (bool entry : row) positive = positive && entry;
                if (positive) { exponent = t; break; }
                if (t == bound) break;
                BooleanMatrix next(n, std::vector<bool>(n));
                for (int i = 0; i < n; ++i)
                    for (int j = 0; j < n; ++j)
                        for (int l = 0; l < n; ++l)
                            next[i][j] = next[i][j] || (power[i][l] && edges[l][j]);
                power = std::move(next);
            }
            std::cout << "CLASSIFY " << name << " absorbing_states=" << absorbing.size()
                      << " absorbing=" << yes(absorbs) << " ergodic=" << yes(graph.classes.size() == 1)
                      << " regular=" << yes(exponent != 0)
                      << " exponent=" << (exponent == 0 ? "-" : std::to_string(exponent)) << '\n';
        } else if (command == "STEP") {
            const std::string& initial = words[2];
            Row distribution(n);
            if (std::isdigit(static_cast<unsigned char>(initial[0]))) {
                const Names parts = split(initial, ',');
                if (static_cast<int>(parts.size()) != n) fail("BAD LENGTH");
                for (int i = 0; i < n; ++i) distribution[i] = probability(parts[i]);
                if (sum(distribution) != Fraction(1)) fail("BAD DISTRIBUTION");
            } else distribution[chain.state(initial)] = 1;
            const int steps = std::stoi(words[3]);
            for (int t = 0; t < steps; ++t) distribution = multiply(Matrix{distribution}, chain.p)[0];
            std::cout << "STEP " << name << " k=" << steps << '\n';
            for (int i = 0; i < n; ++i)
                std::cout << "PROB " << chain.names[i] << ' ' << distribution[i].value() << '\n';
        } else if (command == "POWER") {
            const int steps = std::stoi(words[2]);
            Matrix power = identity(n);
            for (int t = 0; t < steps; ++t) power = multiply(power, chain.p);
            std::cout << "POWER " << name << " k=" << steps << '\n';
            chain.display(power);
        } else if (command == "STATIONARY") {
            int count = 0;
            for (const CommunicatingClass& group : graph.classes) if (group.closed) ++count;
            std::cout << "STATIONARY " << name << " count=" << count << '\n';
            int number = 0;
            for (std::size_t index = 0; index < graph.classes.size(); ++index) {
                const CommunicatingClass& group = graph.classes[index];
                if (!group.closed) continue;
                const Row pi = stationary(chain, group.members);
                std::cout << "DIST " << ++number << " class=" << index + 1
                          << " size=" << group.members.size() << '\n';
                for (std::size_t i = 0; i < group.members.size(); ++i)
                    std::cout << "PI " << chain.names[group.members[i]] << ' ' << pi[i].value() << '\n';
            }
        } else if (command == "RECURRENCE") {
            const int state = chain.state(words[2]);
            const CommunicatingClass& group = graph.classes[graph.classOf[state]];
            if (!group.closed) fail("TRANSIENT STATE " + words[2]);
            const Row pi = stationary(chain, group.members);
            const std::size_t position = std::find(group.members.begin(), group.members.end(), state) - group.members.begin();
            const Fraction rho = pi[position];
            std::cout << "RECURRENCE " << name << ' ' << words[2] << " pi=" << rho.value()
                      << " mean=" << (Fraction(1) / rho).value() << " period=" << group.period << '\n';
        } else if (command == "ABSORB") {
            States absorbing;
            for (int i = 0; i < n; ++i) if (chain.p[i][i] == Fraction(1)) absorbing.push_back(i);
            if (absorbing.empty()) fail("NO ABSORBING STATE");
            for (int i = 0; i < n; ++i) {
                bool reaches = false;
                for (int target : absorbing) reaches = reaches || graph.reach[i][target];
                if (!reaches) fail("NOT ABSORBING " + chain.names[i]);
            }
            const Absorption data(chain);
            const int count = static_cast<int>(data.transient.size());
            std::cout << "ABSORB " << name << " transient=" << count << " absorbing=" << absorbing.size() << '\n';
            if (count == 0) return;
            std::cout << "TRANSIENT " << join(chain.labels(data.transient)) << '\n';
            std::cout << "ABSORBING " << join(chain.labels(absorbing)) << '\n';
            for (int i = 0; i < count; ++i)
                std::cout << "N " << chain.names[data.transient[i]] << ' ' << join(data.fundamental[i]) << '\n';
            for (int i = 0; i < count; ++i)
                std::cout << "STEPS " << chain.names[data.transient[i]] << " mean=" << data.means[i].value()
                          << " var=" << data.variances[i].value() << '\n';
            for (int i = 0; i < count; ++i)
                std::cout << "B " << chain.names[data.transient[i]] << ' ' << join(data.probabilities[i]) << '\n';
        } else if (command == "HITTING") {
            States targets = chain.states(Names(words.begin() + 2, words.end()));
            std::sort(targets.begin(), targets.end());
            const Hitting result = hitting(chain, targets, graph.reach);
            std::cout << "HITTING " << name << " targets=" << join(chain.labels(targets), ",") << '\n';
            for (int i = 0; i < n; ++i)
                std::cout << "HIT " << chain.names[i] << " prob=" << result.probabilities[i].value()
                          << " time=" << (result.times[i] ? result.times[i]->value() : "inf") << '\n';
        } else if (command == "PASSAGE") {
            const Row pi = irreducible(chain, graph);
            Matrix passage = matrix(n, n);
            for (int j = 0; j < n; ++j) {
                const Hitting result = hitting(chain, States{j}, graph.reach);
                for (int i = 0; i < n; ++i)
                    passage[i][j] = i == j ? Fraction(1) / pi[j] : *result.times[i];
            }
            Fraction kemeny;
            for (int j = 1; j < n; ++j) kemeny = kemeny + pi[j] * passage[0][j];
            std::cout << "PASSAGE " << name << " kemeny=" << kemeny.value() << '\n';
            chain.display(passage, "M");
        } else if (command == "FIRSTPASSAGE") {
            const int from = chain.state(words[2]);
            const int target = chain.state(words[3]);
            const int steps = std::stoi(words[4]);
            if (steps == 0) fail("BAD STEPS");
            Row probabilities(n), first, cumulative;
            for (int i = 0; i < n; ++i) probabilities[i] = chain.p[i][target];
            Fraction total;
            for (int t = 1; t <= steps; ++t) {
                first.push_back(probabilities[from]);
                total = total + probabilities[from];
                cumulative.push_back(total);
                if (t == steps) break;
                Row next(n);
                for (int i = 0; i < n; ++i)
                    for (int u = 0; u < n; ++u)
                        if (u != target) next[i] = next[i] + chain.p[i][u] * probabilities[u];
                probabilities = std::move(next);
            }
            std::cout << "FIRSTPASSAGE " << name << ' ' << words[2] << ' ' << words[3]
                      << " k=" << steps << " total=" << total.value() << '\n';
            for (int t = 0; t < steps; ++t)
                std::cout << "FP " << t + 1 << ' ' << first[t].value() << " cum=" << cumulative[t].value() << '\n';
        } else if (command == "PATHPROB") {
            States path;
            for (std::size_t i = 2; i < words.size(); ++i) path.push_back(chain.state(words[i]));
            Fraction chance(1);
            std::size_t zeroAt = 0;
            for (std::size_t i = 1; i < path.size(); ++i) {
                chance = chance * chain.p[path[i - 1]][path[i]];
                if (chance.numerator == 0 && zeroAt == 0) zeroAt = i;
            }
            std::cout << "PATHPROB " << name << " steps=" << path.size() - 1 << " prob=" << chance.value();
            if (zeroAt != 0) std::cout << " zero_at=" << zeroAt;
            std::cout << '\n';
        } else if (command == "MOSTLIKELY") {
            const int start = chain.state(words[2]);
            const int steps = std::stoi(words[3]);
            if (steps == 0) fail("BAD STEPS");
            Matrix best = matrix(steps + 1, n);
            std::fill(best.back().begin(), best.back().end(), Fraction(1));
            for (int t = steps - 1; t >= 0; --t)
                for (int i = 0; i < n; ++i)
                    for (int j = 0; j < n; ++j) {
                        const Fraction candidate = chain.p[i][j] * best[t + 1][j];
                        if (best[t][i] < candidate) best[t][i] = candidate;
                    }
            States path{start};
            for (int t = 0; t < steps; ++t) {
                const int current = path.back();
                for (int j = 0; j < n; ++j) {
                    if (chain.p[current][j] * best[t + 1][j] != best[t][current]) continue;
                    path.push_back(j);
                    break;
                }
            }
            std::cout << "MOSTLIKELY " << name << ' ' << words[2] << " k=" << steps
                      << " prob=" << best[0][start].value() << '\n';
            std::cout << "PATH " << join(chain.labels(path)) << '\n';
        } else if (command == "REVERSIBLE") {
            const Row pi = irreducible(chain, graph);
            struct Violation { int from; int to; Fraction forward; Fraction backward; };
            std::vector<Violation> violations;
            for (int i = 0; i < n; ++i)
                for (int j = i + 1; j < n; ++j) {
                    const Fraction forward = pi[i] * chain.p[i][j];
                    const Fraction backward = pi[j] * chain.p[j][i];
                    if (forward != backward) violations.push_back({i, j, forward, backward});
                }
            if (violations.empty()) std::cout << "REVERSIBLE " << name << " yes\n";
            else {
                std::cout << "REVERSIBLE " << name << " no violations=" << violations.size() << '\n';
                for (const Violation& violation : violations)
                    std::cout << "VIOLATION " << chain.names[violation.from] << ' ' << chain.names[violation.to]
                              << ' ' << violation.forward.value() << ' ' << violation.backward.value() << '\n';
            }
        } else if (command == "REVERSE") {
            const Row pi = irreducible(chain, graph);
            Chain reversed(chain.names);
            bool reversible = true;
            for (int i = 0; i < n; ++i)
                for (int j = 0; j < n; ++j) {
                    reversed.p[i][j] = pi[j] * chain.p[j][i] / pi[i];
                    if (reversed.p[i][j] != chain.p[i][j]) reversible = false;
                }
            chains[words[2]] = reversed;
            std::cout << "REVERSE " << name << ' ' << words[2] << " reversible=" << yes(reversible) << '\n';
            reversed.display();
        } else if (command == "MIXING") {
            const int steps = std::stoi(words[2]);
            if (steps == 0) fail("BAD STEPS");
            const Fraction epsilon = probability(words[3]);
            const Row pi = irreducible(chain, graph);
            Matrix power = identity(n);
            struct Distance { Fraction value; int state; };
            std::vector<Distance> distances;
            int mixingTime = 0;
            for (int t = 1; t <= steps; ++t) {
                power = multiply(power, chain.p);
                Distance maximum{Fraction(0), 0};
                for (int i = 0; i < n; ++i) {
                    Fraction distance;
                    for (int j = 0; j < n; ++j) distance = distance + (power[i][j] - pi[j]).absolute();
                    distance = distance / Fraction(2);
                    if (maximum.value < distance) maximum = {distance, i};
                }
                distances.push_back(maximum);
                if (mixingTime == 0 && maximum.value <= epsilon) mixingTime = t;
            }
            std::cout << "MIXING " << name << " k=" << steps << " eps=" << epsilon
                      << " time=" << (mixingTime == 0 ? "none" : std::to_string(mixingTime)) << '\n';
            for (int t = 0; t < steps; ++t)
                std::cout << "TV " << t + 1 << ' ' << distances[t].value.value()
                          << " from=" << chain.names[distances[t].state] << '\n';
        } else if (command == "LUMP") {
            std::vector<States> blocks;
            std::set<int> seen;
            for (const std::string& block : split(words[3], '|')) {
                States members;
                for (const std::string& state : split(block, ',')) {
                    const int index = chain.state(state);
                    if (!seen.insert(index).second) fail("BAD PARTITION");
                    members.push_back(index);
                }
                std::sort(members.begin(), members.end());
                blocks.push_back(std::move(members));
            }
            if (static_cast<int>(seen.size()) != n) fail("BAD PARTITION");
            std::sort(blocks.begin(), blocks.end(), [](const States& a, const States& b) { return a[0] < b[0]; });
            States representatives;
            for (const States& block : blocks) representatives.push_back(block[0]);
            Chain lumped(chain.labels(representatives));
            for (std::size_t k = 0; k < blocks.size(); ++k)
                for (std::size_t l = 0; l < blocks.size(); ++l) {
                    const int representative = blocks[k][0];
                    const Fraction expected = chain.blockSum(representative, blocks[l]);
                    for (int state : blocks[k]) {
                        const Fraction actual = chain.blockSum(state, blocks[l]);
                        if (actual == expected) continue;
                        std::cout << "LUMP " << name << " not lumpable block=" << chain.names[representative]
                                  << " target=" << chain.names[blocks[l][0]]
                                  << ' ' << chain.names[representative] << '=' << expected.value()
                                  << ' ' << chain.names[state] << '=' << actual.value() << '\n';
                        return;
                    }
                    lumped.p[k][l] = expected;
                }
            chains[words[2]] = lumped;
            std::cout << "LUMP " << name << ' ' << words[2] << " blocks=" << blocks.size() << '\n';
            lumped.display();
        } else if (command == "REWARD") {
            if (static_cast<int>(words.size()) - 3 != n) fail("BAD LENGTH");
            const Fraction gamma = probability(words[2]);
            if (gamma == Fraction(1)) fail("BAD DISCOUNT");
            Row rewards;
            for (std::size_t i = 3; i < words.size(); ++i) rewards.emplace_back(std::stoll(words[i]));
            Matrix rows = matrix(n, n + 1);
            for (int i = 0; i < n; ++i) {
                for (int j = 0; j < n; ++j) rows[i][j] = Fraction(i == j) - gamma * chain.p[i][j];
                rows[i][n] = rewards[i];
            }
            const Matrix values = eliminate(std::move(rows));
            Row gains(n);
            for (const CommunicatingClass& group : graph.classes) {
                if (!group.closed) continue;
                const Row pi = stationary(chain, group.members);
                Fraction average;
                for (std::size_t j = 0; j < group.members.size(); ++j)
                    average = average + pi[j] * rewards[group.members[j]];
                const Hitting result = hitting(chain, group.members, graph.reach, true);
                for (int i = 0; i < n; ++i) gains[i] = gains[i] + result.probabilities[i] * average;
            }
            std::cout << "REWARD " << name << " gamma=" << gamma << '\n';
            for (int i = 0; i < n; ++i)
                std::cout << "VALUE " << chain.names[i] << " discounted=" << values[i][0].value()
                          << " gain=" << gains[i].value() << '\n';
        } else if (command == "RESTRICT") {
            States selected = chain.states(Names(words.begin() + 3, words.end()));
            std::sort(selected.begin(), selected.end());
            std::vector<bool> inside(n);
            for (int state : selected) inside[state] = true;
            for (int state : selected)
                for (int j = 0; j < n; ++j)
                    if (!inside[j] && chain.p[state][j].numerator > 0) fail("NOT CLOSED " + chain.names[state]);
            Chain restricted(chain.labels(selected));
            for (std::size_t i = 0; i < selected.size(); ++i)
                for (std::size_t j = 0; j < selected.size(); ++j)
                    restricted.p[i][j] = chain.p[selected[i]][selected[j]];
            chains[words[2]] = restricted;
            std::cout << "RESTRICT " << name << ' ' << words[2] << " states=" << selected.size() << '\n';
            restricted.display();
        } else if (command == "SIMULATE") {
            const int start = chain.state(words[2]);
            const int steps = std::stoi(words[3]);
            if (steps == 0) fail("BAD STEPS");
            const Integer seed = std::stoll(words[4]);
            if (seed == 0 || seed >= 2147483647) fail("BAD SEED");
            Integer random = seed;
            int current = start;
            States path{start};
            std::vector<int> visits(n);
            ++visits[start];
            for (int t = 0; t < steps; ++t) {
                Integer common = 1;
                for (Fraction chance : chain.p[current]) common = std::lcm(common, chance.denominator);
                random = 48271 * random % 2147483647;
                const Fraction threshold(random % common);
                Fraction cumulative;
                for (int j = 0; j < n; ++j) {
                    cumulative = cumulative + chain.p[current][j];
                    if (!(threshold < cumulative * Fraction(common))) continue;
                    current = j;
                    break;
                }
                path.push_back(current);
                ++visits[current];
            }
            std::cout << "SIMULATE " << name << ' ' << words[2] << " steps=" << steps << " seed=" << seed
                      << " end=" << chain.names[current] << '\n';
            std::cout << "PATH " << join(chain.labels(path)) << '\n';
            for (int i = 0; i < n; ++i) std::cout << "VISIT " << chain.names[i] << ' ' << visits[i] << '\n';
        }
    }

public:
    void run(const std::string& line) {
        const Names words = split(line);
        if (words[0] == "CHAIN") { create(words); return; }
        if (words[0] == "BUILD") { build(words); return; }
        if (words[0] == "GAMBLER") { gambler(words); return; }
        const auto entry = chains.find(words[1]);
        if (entry == chains.end()) fail("UNKNOWN CHAIN " + words[1]);
        if (!edit(words, entry->second)) analyze(words, entry->second);
    }
};

int main() {
    std::ios::sync_with_stdio(false);
    std::cin.tie(nullptr);
    std::string line;
    std::getline(std::cin, line);
    const int count = std::stoi(line);
    Analyzer analyzer;
    for (int i = 0; i < count; ++i) {
        std::getline(std::cin, line);
        try { analyzer.run(line); }
        catch (const CommandError& error) { std::cout << "ERROR " << error.what() << '\n'; }
    }
}
