#include "chemistry.hpp"
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <functional>
#include <numeric>
#include <set>

static std::vector<int> dense(const std::vector<std::vector<int>> &values) {
    std::vector<int> order(values.size()), ranks(values.size());
    std::iota(order.begin(), order.end(), 0);
    std::sort(order.begin(), order.end(), [&](int a, int b) { return values[a] < values[b]; });
    int rank = 0, previous = -1;
    for (int i : order) {
        if (previous < 0 || values[i] != values[previous])
            ++rank;
        ranks[i] = rank;
        previous = i;
    }
    return ranks;
}
static int rankCount(const std::vector<int> &ranks) {
    return *std::max_element(ranks.begin(), ranks.end());
}
static std::vector<int> refine(const Molecule &m, std::vector<int> ranks) {
    for (;;) {
        std::vector<std::vector<int>> values(m.atoms.size());
        for (std::size_t a = 0; a < m.atoms.size(); ++a) {
            std::vector<std::pair<int, int>> neighbors;
            for (int e : m.adjacent[a])
                neighbors.emplace_back(ranks[m.bonds[e].other(static_cast<int>(a))],
                                       m.bonds[e].type);
            std::sort(neighbors.begin(), neighbors.end());
            values[a].push_back(ranks[a]);
            for (const auto &value : neighbors) {
                values[a].push_back(value.first);
                values[a].push_back(value.second);
            }
        }
        std::vector<int> next = dense(values);
        if (rankCount(next) == rankCount(ranks))
            return next;
        ranks = std::move(next);
    }
}
void canonicalRanks(Molecule &m, const Elements &elements) {
    std::vector<std::vector<int>> values;
    for (std::size_t i = 0; i < m.atoms.size(); ++i) {
        const Atom &a = m.atoms[i];
        values.push_back({static_cast<int>(m.adjacent[i].size()), elements.at(a.symbol).number,
                          a.mass, a.charge, a.hydrogens, a.aromatic ? 1 : 0});
    }
    std::vector<int> ranks = refine(m, dense(values));
    m.classes = rankCount(ranks);
    while (rankCount(ranks) < static_cast<int>(m.atoms.size())) {
        std::vector<int> counts(m.atoms.size() + 1);
        for (int rank : ranks)
            ++counts[rank];
        int smallest = 1;
        while (counts[smallest] < 2)
            ++smallest;
        int chosen =
            static_cast<int>(std::find(ranks.begin(), ranks.end(), smallest) - ranks.begin());
        values.clear();
        for (int i = 0; i < static_cast<int>(ranks.size()); ++i)
            values.push_back({2 * ranks[i] - (i == chosen ? 1 : 0)});
        ranks = refine(m, dense(values));
    }
    m.ranks = std::move(ranks);
}
static std::string atomNotation(const Molecule &m, int index, const Elements &elements) {
    const Atom &a = m.atoms[index];
    std::string symbol = a.symbol;
    if (a.aromatic)
        for (char &c : symbol)
            if (c >= 'A' && c <= 'Z')
                c = static_cast<char>(c - 'A' + 'a');
    static const std::set<std::string> organic = {"B", "C", "N",  "O",  "P",
                                                  "S", "F", "Cl", "Br", "I"},
                                       aromatic = {"B", "C", "N", "O", "P", "S"};
    std::optional<int> hydrogens = m.organicHydrogens(index, elements);
    if (organic.count(a.symbol) && (!a.aromatic || aromatic.count(a.symbol)) && a.mass == 0 &&
        a.charge == 0 &&
        (!a.aromatic || m.needsPi(index, elements, true) == m.needsPi(index, elements, false)) &&
        hydrogens && *hydrogens == a.hydrogens)
        return symbol;
    std::string out = "[";
    if (a.mass)
        out += std::to_string(a.mass);
    out += symbol;
    if (a.hydrogens) {
        out += 'H';
        if (a.hydrogens >= 2)
            out += std::to_string(a.hydrogens);
    }
    if (a.charge) {
        out += a.charge > 0 ? '+' : '-';
        if (std::abs(a.charge) >= 2)
            out += std::to_string(std::abs(a.charge));
    }
    return out + "]";
}
static std::string bondNotation(const Molecule &m, const Bond &bond) {
    bool inRing = m.atoms[bond.a].aromatic && m.atoms[bond.b].aromatic && bond.ring;
    if (bond.type == 1)
        return inRing ? "-" : "";
    if (bond.type == 2)
        return "=";
    if (bond.type == 3)
        return "#";
    return inRing ? "" : ":";
}
std::string canonicalSmiles(const Molecule &m, const Elements &elements) {
    int start = static_cast<int>(std::find(m.ranks.begin(), m.ranks.end(), 1) - m.ranks.begin());
    std::vector<bool> visited(m.atoms.size());
    std::vector<int> visitOrder(m.atoms.size()), classification(m.bonds.size());
    std::vector<std::vector<std::pair<int, int>>> children(m.atoms.size());
    int serial = 0;
    const std::function<void(int, int)> visit = [&](int a, int parent) {
        visited[a] = true;
        visitOrder[a] = ++serial;
        std::vector<int> neighbors = m.adjacent[a];
        std::sort(neighbors.begin(), neighbors.end(), [&](int x, int y) {
            return m.ranks[m.bonds[x].other(a)] < m.ranks[m.bonds[y].other(a)];
        });
        for (int e : neighbors) {
            if (e == parent || classification[e] == 2)
                continue;
            int b = m.bonds[e].other(a);
            if (!visited[b]) {
                classification[e] = 1;
                children[a].emplace_back(b, e);
                visit(b, e);
            } else
                classification[e] = 2;
        }
    };
    visit(start, -1);
    std::map<int, int> assignments;
    std::set<int> used;
    const auto numberText = [](int value) {
        if (value <= 9)
            return std::to_string(value);
        char buffer[16];
        std::snprintf(buffer, sizeof(buffer), "%%%02d", value);
        return std::string(buffer);
    };
    const std::function<std::string(int)> write = [&](int a) {
        std::string out = atomNotation(m, a, elements);
        std::vector<int> closures;
        for (int e : m.adjacent[a])
            if (classification[e] == 2)
                closures.push_back(e);
        std::sort(closures.begin(), closures.end(), [&](int x, int y) {
            return visitOrder[m.bonds[x].other(a)] < visitOrder[m.bonds[y].other(a)];
        });
        for (int e : closures) {
            auto found = assignments.find(e);
            if (found != assignments.end()) {
                out += numberText(found->second);
                used.erase(found->second);
                assignments.erase(found);
            } else {
                int number = 1;
                while (used.count(number))
                    ++number;
                assignments[e] = number;
                used.insert(number);
                out += bondNotation(m, m.bonds[e]) + numberText(number);
            }
        }
        for (std::size_t i = 0; i < children[a].size(); ++i) {
            const auto &child = children[a][i];
            std::string branch = bondNotation(m, m.bonds[child.second]) + write(child.first);
            out += i + 1 < children[a].size() ? "(" + branch + ")" : branch;
        }
        return out;
    };
    return write(start);
}
