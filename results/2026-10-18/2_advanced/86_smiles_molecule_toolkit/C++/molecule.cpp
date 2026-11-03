#include "chemistry.hpp"
#include <algorithm>
#include <fstream>
#include <stdexcept>
int Bond::other(int atom) const { return atom == a ? b : a; }
void Molecule::build() {
    std::sort(bonds.begin(), bonds.end(),
              [](const Bond &x, const Bond &y) { return x.a != y.a ? x.a < y.a : x.b < y.b; });
    adjacent.assign(atoms.size(), {});
    for (int i = 0; i < static_cast<int>(bonds.size()); ++i) {
        adjacent[bonds[i].a].push_back(i);
        adjacent[bonds[i].b].push_back(i);
    }
    for (int a = 0; a < static_cast<int>(atoms.size()); ++a)
        std::sort(adjacent[a].begin(), adjacent[a].end(),
                  [&](int x, int y) { return bonds[x].other(a) < bonds[y].other(a); });
}
const Bond *Molecule::bond(int a, int b) const {
    for (int index : adjacent[a])
        if (bonds[index].other(a) == b)
            return &bonds[index];
    return nullptr;
}
int Molecule::base(int a) const {
    int sum = 0;
    for (int index : adjacent[a])
        sum += bonds[index].type == 4 ? 1 : bonds[index].type;
    return sum;
}
int Molecule::multiplicity(int a) const {
    int sum = 0;
    for (int index : adjacent[a])
        sum += bonds[index].multiplicity;
    return sum;
}
bool Molecule::needsPi(int a, const Elements &elements, bool hydrogens) const {
    return atoms[a].aromatic && elements.at(atoms[a].symbol).valences.front() + atoms[a].charge >=
                                    base(a) + (hydrogens ? atoms[a].hydrogens : 0) + 1;
}
std::optional<int> Molecule::organicHydrogens(int a, const Elements &elements) const {
    int total = multiplicity(a);
    for (int valence : elements.at(atoms[a].symbol).valences)
        if (valence >= total)
            return valence - total;
    return std::nullopt;
}
bool ignored(const std::string &line) { return line.empty() || line[0] == '#'; }
std::vector<std::string> readLines(const std::string &name) {
    std::ifstream file(name);
    if (!file)
        throw std::runtime_error("cannot read " + name);
    std::vector<std::string> result;
    std::string value;
    while (std::getline(file, value))
        result.push_back(value);
    return result;
}
std::vector<std::string> split(const std::string &value, char separator) {
    std::vector<std::string> result;
    std::size_t start = 0;
    for (;;) {
        std::size_t end = value.find(separator, start);
        result.push_back(value.substr(start, end == std::string::npos ? end : end - start));
        if (end == std::string::npos)
            return result;
        start = end + 1;
    }
}
std::string join(const std::vector<std::string> &parts, const std::string &separator) {
    std::string result;
    for (std::size_t i = 0; i < parts.size(); ++i) {
        if (i)
            result += separator;
        result += parts[i];
    }
    return result;
}
Elements readElements() {
    Elements elements;
    for (const std::string &line : readLines("input/elements.txt")) {
        if (ignored(line))
            continue;
        std::vector<std::string> a = split(line, ' ');
        Element e{a[0], std::stoi(a[1]), std::stoi(a[2]), {}};
        for (const std::string &v : split(a[3], ','))
            e.valences.push_back(std::stoi(v));
        elements.emplace(e.symbol, std::move(e));
    }
    return elements;
}
