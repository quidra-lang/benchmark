#ifndef PHYLOGENY_HPP
#define PHYLOGENY_HPP
#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iomanip>
#include <limits>
#include <map>
#include <numeric>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <vector>
using Names = std::vector<std::string>;
using Lines = Names;
using Mask = unsigned;
using Matrix = std::array<std::array<double, 16>, 16>;
struct Record {
    int line;
    std::string name, sequence;
};
int base_index(char character);
unsigned base_set(char character);
std::vector<Record> read_fasta();
struct Patterns {
    Names text;
    std::vector<std::array<unsigned, 16>> encoded;
    std::vector<int> weights, columns;
    Patterns() = default;
    explicit Patterns(const Names &sequences);
};
struct Classes {
    int constant = 0, variable = 0, informative = 0, gapped = 0, empty = 0;
};
Classes classify(const Names &sequences);
struct Pair {
    int first, second, sites, transitions, transversions;
};
std::vector<Pair> all_pairs(const Names &sequences, const std::vector<int> &weights);
std::pair<double, bool> corrected(int model, const Pair &pair, double replacement);
std::pair<Matrix, std::vector<Pair>> build_matrix(const std::vector<Pair> &pairs, int model,
                                                  double replacement);
struct Tree {
    int size = 0, next = 0, negative = 0;
    std::array<bool, 32> present{};
    std::array<std::array<bool, 32>, 32> adjacent{};
    std::array<std::array<double, 32>, 32> length{};
    explicit Tree(int size = 0) : size(size), next(size) {}
    int internal();
    void connect(int a, int b, double distance = 0);
    double disconnect(int a, int b);
    std::vector<int> taxa() const, internal_nodes() const;
};
struct Rooted {
    int root, outgroup;
    Mask ingroup;
    std::array<int, 32> parents{};
    std::array<std::vector<int>, 32> children;
    std::array<Mask, 32> masks{};
    std::vector<int> order;
    Rooted(const Tree &tree, int outgroup);
    std::set<Mask> splits(const Tree &tree) const;
    std::map<Mask, double> branch_lengths(const Tree &tree) const;
};
Tree star(int size, const std::vector<int> &taxa),
    neighbor_joining(const Matrix &matrix, int size, const std::vector<int> &taxa);
std::array<double, 32> paths(const Tree &tree, int start, bool unit = false);
Matrix patristic(const Tree &tree);
struct Provisional {
    std::array<unsigned, 32> sets{};
    int changes = 0;
};
std::pair<unsigned, int> merge(unsigned a, unsigned b);
Provisional provisional(const Tree &tree, const Rooted &rooted,
                        const std::array<unsigned, 16> &pattern);
std::vector<int> pattern_scores(const Tree &tree, const Patterns &patterns, int outgroup);
int score(const Tree &tree, const Patterns &patterns, int outgroup);
struct Reconstruction {
    std::map<int, std::string> ancestors;
    std::map<std::pair<int, int>, int> changes;
    std::vector<int> sites;
};
Reconstruction reconstruct(const Tree &tree, const Patterns &patterns, int outgroup);
struct Branch {
    Mask mask;
    int first, second;
};
std::vector<Branch> branches(const Tree &tree, int outgroup);
Tree insert(const Tree &tree, int first, int second, int taxon);
struct Swap {
    Mask mask;
    int number;
    Tree tree;
};
std::vector<Swap> nni_candidates(const Tree &tree, int outgroup);
std::string real(double value, int digits), symbols(Mask mask, int size),
    newick(const Tree &tree, const Names &names, int outgroup, bool lengths = false,
           const std::map<Mask, int> *support = nullptr);
Lines cladogram(const Tree &tree, const Names &names, int outgroup,
                const std::map<Mask, int> &support);
void save(const std::string &name, const Lines &lines);
template <class... T> void line(Lines &out, const T &...values) {
    std::ostringstream stream;
    (stream << ... << values);
    out.push_back(stream.str());
}
#endif
