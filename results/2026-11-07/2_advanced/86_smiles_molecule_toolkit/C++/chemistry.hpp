#ifndef CHEMISTRY_HPP
#define CHEMISTRY_HPP
#include <array>
#include <cstdint>
#include <bitset>
#include <map>
#include <optional>
#include <sstream>
#include <string>
#include <vector>
struct Element {
    std::string symbol;
    int number, weight;
    std::vector<int> valences;
};
using Elements = std::map<std::string, Element>;
struct Choice {
    std::string symbol;
    bool aromatic = false;
};
struct Atom {
    std::string symbol;
    bool aromatic = false, bracket = false;
    int mass = 0, charge = 0, hydrogens = 0, column = 0;
    std::vector<Choice> choices;
    char wildcard = 0;
};
struct Bond {
    int a, b;
    char symbol = 0;
    int type = 0, multiplicity = 0, match = 0;
    bool ring = false;
    int other(int) const;
};
struct Molecule {
    std::string name;
    std::vector<Atom> atoms;
    std::vector<Bond> bonds;
    std::vector<std::vector<int>> adjacent, rings;
    std::vector<bool> ringAtoms;
    std::vector<int> ranks;
    int classes = 0;
    std::string canonical, scaffold, formula, lipinski;
    int weight = 0, heavy = 0, rotatable = 0, donors = 0, acceptors = 0, charge = 0;
    std::bitset<1024> bits;
    int paths = 0;
    void build();
    const Bond *bond(int, int) const;
    int base(int) const;
    int multiplicity(int) const;
    bool needsPi(int, const Elements &, bool) const;
    std::optional<int> organicHydrogens(int, const Elements &) const;
};
struct ParseError {
    std::string reason;
    int column;
};
struct Parsed {
    std::optional<Molecule> molecule;
    std::optional<ParseError> error;
};
Elements readElements();
bool ignored(const std::string &);
std::vector<std::string> readLines(const std::string &);
std::vector<std::string> split(const std::string &, char);
std::string join(const std::vector<std::string> &, const std::string &);
bool digit(char);
std::optional<std::pair<Atom, std::size_t>> organic(const std::string &, std::size_t);
std::pair<Atom, std::string> bracket(const std::string &, const Elements &);
int symbolType(char);
Parsed parseSmiles(const std::string &, const Elements &, bool);
std::pair<Atom, std::string> patternAtom(const std::string &, std::size_t, std::size_t &);
Molecule moleculePattern(const Molecule &);
void detectRings(Molecule &);
std::optional<ParseError> kekulize(Molecule &, const Elements &);
void canonicalRanks(Molecule &, const Elements &);
std::string canonicalSmiles(const Molecule &, const Elements &);
struct Embeddings {
    int count = 0, unique = 0;
    std::vector<int> first;
};
Embeddings embeddings(const Molecule &, const Molecule &);
void fingerprint(Molecule &, const Elements &);
struct Fraction {
    int n, d;
    Fraction(int = 0, int = 1);
    int compare(Fraction) const;
    std::string text() const;
};
struct Similarity {
    Fraction value;
    int common, total;
};
Similarity similarity(const Molecule &, const Molecule &);
template <typename... Values> std::string text(const Values &...values) {
    std::ostringstream out;
    (out << ... << values);
    return out.str();
}
#endif
