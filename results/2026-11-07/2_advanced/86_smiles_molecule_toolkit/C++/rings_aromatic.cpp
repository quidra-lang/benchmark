#include "chemistry.hpp"
#include <algorithm>
#include <functional>
#include <set>
static std::vector<int> canonicalRing(const std::vector<int> &ring) {
    std::size_t first =
        static_cast<std::size_t>(std::min_element(ring.begin(), ring.end()) - ring.begin());
    int n = static_cast<int>(ring.size()),
        direction = ring[(first + 1) % ring.size()] < ring[(first + ring.size() - 1) % ring.size()]
                        ? 1
                        : -1;
    std::vector<int> result;
    for (int i = 0; i < n; ++i)
        result.push_back(ring[(static_cast<int>(first) + direction * i + n) % n]);
    return result;
}
void detectRings(Molecule &m) {
    struct Candidate {
        std::vector<int> atoms;
        std::bitset<300> bonds;
    };
    int n = static_cast<int>(m.atoms.size());
    std::vector<Candidate> candidates;
    std::set<std::string> seen;
    std::map<std::pair<int, int>, int> bondIndex;
    for (int i = 0; i < static_cast<int>(m.bonds.size()); ++i)
        bondIndex[{m.bonds[i].a, m.bonds[i].b}] = i;
    for (int root = 0; root < n; ++root) {
        std::vector<int> parent(n, -2), queue = {root};
        parent[root] = -1;
        for (std::size_t h = 0; h < queue.size(); ++h)
            for (int e : m.adjacent[queue[h]]) {
                int next = m.bonds[e].other(queue[h]);
                if (parent[next] == -2) {
                    parent[next] = queue[h];
                    queue.push_back(next);
                }
            }
        const auto path = [&](int a) {
            std::vector<int> result;
            for (; a >= 0; a = parent[a])
                result.push_back(a);
            return result;
        };
        for (const Bond &bond : m.bonds) {
            if (parent[bond.a] == bond.b || parent[bond.b] == bond.a)
                continue;
            std::vector<int> px = path(bond.a), py = path(bond.b);
            std::set<int> atoms(px.begin(), px.end() - 1);
            bool overlap = false;
            for (auto a = py.begin(); a != py.end() - 1; ++a)
                overlap = overlap || atoms.count(*a) != 0;
            if (overlap)
                continue;
            std::reverse(px.begin(), px.end());
            px.insert(px.end(), py.begin(), py.end() - 1);
            std::bitset<300> vector;
            for (std::size_t i = 0; i < px.size(); ++i) {
                int a = px[i], b = px[(i + 1) % px.size()];
                vector.set(bondIndex.at({std::min(a, b), std::max(a, b)}));
            }
            if (seen.insert(vector.to_string()).second)
                candidates.push_back({std::move(px), vector});
        }
    }
    std::stable_sort(
        candidates.begin(), candidates.end(),
        [](const Candidate &a, const Candidate &b) { return a.atoms.size() < b.atoms.size(); });
    std::array<std::optional<std::bitset<300>>, 300> basis;
    m.ringAtoms.assign(m.atoms.size(), false);
    for (const Candidate &candidate : candidates) {
        std::bitset<300> reduced = candidate.bonds;
        while (reduced.any()) {
            int pivot = static_cast<int>(m.bonds.size()) - 1;
            while (!reduced[pivot])
                --pivot;
            if (basis[pivot])
                reduced ^= *basis[pivot];
            else {
                basis[pivot] = reduced;
                m.rings.push_back(canonicalRing(candidate.atoms));
                for (int atom : candidate.atoms)
                    m.ringAtoms[atom] = true;
                for (std::size_t i = 0; i < m.bonds.size(); ++i)
                    if (candidate.bonds[i])
                        m.bonds[i].ring = true;
                break;
            }
        }
    }
    std::sort(m.rings.begin(), m.rings.end(),
              [](const std::vector<int> &a, const std::vector<int> &b) {
                  return a.size() != b.size() ? a.size() < b.size() : a < b;
              });
}
std::optional<ParseError> kekulize(Molecule &m, const Elements &elements) {
    int n = static_cast<int>(m.atoms.size());
    std::vector<bool> need(n), seen(n);
    std::vector<int> paired(n, -1);
    for (int i = 0; i < n; ++i)
        need[i] = m.needsPi(i, elements, true);
    for (int first = 0; first < n; ++first) {
        if (!need[first] || seen[first])
            continue;
        std::vector<int> system = {first};
        seen[first] = true;
        for (std::size_t h = 0; h < system.size(); ++h)
            for (int e : m.adjacent[system[h]]) {
                const Bond &bond = m.bonds[e];
                int next = bond.other(system[h]);
                if (bond.type == 4 && need[next] && !seen[next]) {
                    seen[next] = true;
                    system.push_back(next);
                }
            }
        std::sort(system.begin(), system.end());
        std::vector<bool> member(n);
        for (int atom : system)
            member[atom] = true;
        const std::function<bool()> match = [&]() {
            int u = -1;
            for (int atom : system)
                if (paired[atom] < 0) {
                    u = atom;
                    break;
                }
            if (u < 0)
                return true;
            for (int e : m.adjacent[u]) {
                const Bond &bond = m.bonds[e];
                int v = bond.other(u);
                if (bond.type != 4 || !member[v] || paired[v] >= 0)
                    continue;
                paired[u] = v;
                paired[v] = u;
                if (match())
                    return true;
                paired[u] = paired[v] = -1;
            }
            return false;
        };
        if (!match())
            return ParseError{"kekulization failed", m.atoms[first].column};
    }
    for (Bond &bond : m.bonds)
        bond.multiplicity = bond.type == 4 ? (paired[bond.a] == bond.b ? 2 : 1) : bond.type;
    return std::nullopt;
}
