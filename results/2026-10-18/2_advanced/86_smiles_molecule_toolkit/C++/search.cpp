#include "chemistry.hpp"
#include <algorithm>
#include <functional>
#include <numeric>
#include <set>

std::pair<Atom, std::string> patternAtom(const std::string &source, std::size_t at,
                                         std::size_t &next) {
    Atom atom;
    char c = source[at];
    if (c == '*' || c == 'A' || c == 'a') {
        atom.wildcard = c;
        next = at + 1;
        return {atom, ""};
    }
    if (c == '[') {
        std::size_t end = source.find(']', at + 1);
        if (end == std::string::npos)
            return {atom, "unclosed bracket"};
        for (const std::string &part : split(source.substr(at + 1, end - at - 1), ',')) {
            if (part.empty())
                return {atom, "bad bracket atom"};
            auto parsed = organic(part, 0);
            if (!parsed || parsed->second != part.size())
                return {atom, "bad bracket atom"};
            atom.choices.push_back({parsed->first.symbol, parsed->first.aromatic});
        }
        next = end + 1;
        return {atom, ""};
    }
    auto parsed = organic(source, at);
    if (!parsed)
        return {atom, "unexpected character"};
    atom = std::move(parsed->first);
    atom.choices.push_back({atom.symbol, atom.aromatic});
    next = parsed->second;
    return {atom, ""};
}
static bool atomMatches(const Atom &pattern, const Atom &atom) {
    if (pattern.wildcard == '*')
        return true;
    if (pattern.wildcard == 'A')
        return !atom.aromatic;
    if (pattern.wildcard == 'a')
        return atom.aromatic;
    for (const Choice &choice : pattern.choices)
        if (choice.symbol == atom.symbol && choice.aromatic == atom.aromatic)
            return true;
    return false;
}
Molecule moleculePattern(const Molecule &m) {
    Molecule pattern;
    for (const Atom &atom : m.atoms) {
        Atom a;
        a.choices.push_back({atom.symbol, atom.aromatic});
        pattern.atoms.push_back(std::move(a));
    }
    for (const Bond &bond : m.bonds) {
        Bond b{bond.a, bond.b};
        b.match = 1 << bond.type;
        pattern.bonds.push_back(b);
    }
    pattern.build();
    return pattern;
}
Embeddings embeddings(const Molecule &pattern, const Molecule &molecule) {
    Embeddings result;
    if (pattern.atoms.size() > molecule.atoms.size())
        return result;
    std::vector<int> mapping(pattern.atoms.size(), -1);
    std::vector<bool> used(molecule.atoms.size());
    std::set<std::array<std::uint64_t, 2>> sets;
    const std::function<void(int)> search = [&](int index) {
        if (index == static_cast<int>(pattern.atoms.size())) {
            ++result.count;
            if (result.first.empty())
                for (int atom : mapping)
                    result.first.push_back(atom + 1);
            std::array<std::uint64_t, 2> mask{};
            for (int atom : mapping)
                mask[atom / 64] |= std::uint64_t{1} << (atom % 64);
            sets.insert(mask);
            return;
        }
        for (int candidate = 0; candidate < static_cast<int>(molecule.atoms.size()); ++candidate) {
            if (used[candidate] || !atomMatches(pattern.atoms[index], molecule.atoms[candidate]))
                continue;
            bool valid = true;
            for (int e : pattern.adjacent[index]) {
                const Bond &bond = pattern.bonds[e];
                int other = bond.other(index);
                if (other >= index)
                    continue;
                const Bond *actual = molecule.bond(candidate, mapping[other]);
                if (!actual || !(bond.match & (1 << actual->type))) {
                    valid = false;
                    break;
                }
            }
            if (valid) {
                mapping[index] = candidate;
                used[candidate] = true;
                search(index + 1);
                used[candidate] = false;
                mapping[index] = -1;
            }
        }
    };
    search(0);
    result.unique = static_cast<int>(sets.size());
    return result;
}
void fingerprint(Molecule &m, const Elements &elements) {
    std::vector<int> codes;
    for (std::size_t i = 0; i < m.atoms.size(); ++i)
        codes.push_back(16 * elements.at(m.atoms[i].symbol).number + (m.atoms[i].aromatic ? 8 : 0) +
                        static_cast<int>(m.adjacent[i].size()));
    std::vector<bool> visited(m.atoms.size());
    const std::function<void(int, int, int)> visit = [&](int atom, int depth, int hash) {
        ++m.paths;
        m.bits.set(hash % 1024);
        if (depth == 5)
            return;
        for (int e : m.adjacent[atom]) {
            const Bond &bond = m.bonds[e];
            int next = bond.other(atom);
            if (visited[next])
                continue;
            int value = (hash * 31 + bond.type) % 1000003;
            value = (value * 31 + codes[next]) % 1000003;
            visited[next] = true;
            visit(next, depth + 1, value);
            visited[next] = false;
        }
    };
    for (int i = 0; i < static_cast<int>(m.atoms.size()); ++i) {
        visited[i] = true;
        visit(i, 0, codes[i]);
        visited[i] = false;
    }
}
Fraction::Fraction(int numerator, int denominator) {
    int divisor = std::gcd(numerator, denominator);
    n = numerator / divisor;
    d = denominator / divisor;
}
int Fraction::compare(Fraction value) const {
    int left = n * value.d, right = value.n * d;
    return (left > right) - (left < right);
}
std::string Fraction::text() const { return std::to_string(n) + "/" + std::to_string(d); }
Similarity similarity(const Molecule &a, const Molecule &b) {
    int common = static_cast<int>((a.bits & b.bits).count()),
        total = static_cast<int>((a.bits | b.bits).count());
    return {Fraction(common, total), common, total};
}
