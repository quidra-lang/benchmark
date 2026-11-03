#pragma once
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstddef>
#include <functional>
#include <map>
#include <memory>
#include <numeric>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

using Integer = std::int64_t;
using Counts = std::vector<Integer>;
using Lines = std::vector<std::string>;
template<class... Parts> std::string text(const Parts&... parts) {
    std::ostringstream stream;
    (stream << ... << parts);
    return stream.str();
}
template<class... Parts> void add(Lines& lines, const Parts&... parts) { lines.push_back(text(parts...)); }
template<class T> std::string join(const std::vector<T>& values, const std::string& separator = " ") {
    std::ostringstream stream;
    for (std::size_t i = 0; i < values.size(); ++i) {
        if (i) stream << separator;
        stream << values[i];
    }
    return stream.str();
}
struct Attribute { std::string name; bool integer; Lines values; };
struct Row { std::string id; Counts values; int label; };
using Rows = std::vector<const Row*>;
struct Settings {
    int maxDepth, minSplit, minLeaf, maxSurrogates, folds, bagTrees, repeats;
    Integer bagSeed, permutationSeed;
    std::vector<int> curve;
};
struct Dataset {
    std::vector<Attribute> attributes;
    std::string target;
    Lines classes;
    std::vector<Row> train, validation, test;
    Settings settings;
};
Dataset loadDataset();
Rows rowPointers(const std::vector<Row>& rows);
struct Fraction { Integer numerator, denominator; };
struct Statistics { Counts counts; Integer size, squares, errors; int prediction; };
Statistics statistics(const Rows& rows, int classes);
int majority(const Counts& counts);
int compare(Fraction a, Fraction b);
Fraction evaluationValue(const Statistics& left, const Statistics& right);
bool improves(Fraction value, const Statistics& parent);
double impurityDecrease(const Statistics& parent, const Statistics& left, const Statistics& right);
struct Split { int attribute; Integer point; };
struct Surrogate { Split split; bool forward; Integer score; };
struct Candidate { Split split; Rows left, right; Fraction value; };
struct Node {
    int number, depth;
    Statistics stats;
    std::optional<Split> split;
    std::vector<Surrogate> surrogates;
    bool defaultLeft = true;
    std::unique_ptr<Node> left, right;
};
bool goesLeft(Split split, const Row& row, const std::vector<Attribute>& attributes);
std::vector<Split> candidates(const Rows& rows, const std::vector<Attribute>& attributes, int attribute);
class TreeBuilder {
    const Dataset& data;
    std::vector<Surrogate> surrogates(const Rows& rows, const Candidate& primary) const;
public:
    explicit TreeBuilder(const Dataset& data) : data(data) {}
    std::optional<Candidate> bestForAttribute(const Rows& rows, int attribute) const;
    std::unique_ptr<Node> grow(const Rows& rows, int number = 1, int depth = 0) const;
};
enum class Method { primary, surrogate, fallback };
struct Step { const Node* node; bool left; Method method; };
struct Route { const Node* leaf; std::vector<const Node*> path; std::vector<Step> steps; };
struct TreeView {
    const Node* root;
    std::set<int> cuts;
    bool isLeaf(const Node* node) const;
    std::vector<const Node*> preorder(const Node* start = nullptr) const;
    std::vector<const Node*> leaves(const Node* start = nullptr) const;
    int depth() const;
    Integer trainingErrors() const;
    Route route(const Row& row, const std::vector<Attribute>& attributes) const;
    int predict(const Row& row, const std::vector<Attribute>& attributes) const;
    Integer correct(const Rows& rows, const std::vector<Attribute>& attributes) const;
};
std::string realText(double value, int places = 4);
std::string ratio(Integer numerator, Integer denominator);
std::string fraction(Fraction value, int places = 4);
Lines classification(const std::string& title, const Rows& rows, const std::vector<int>& predictions, const Lines& classes);
struct Decision { const Node* node; Integer rows, leafError, subtreeError; bool pruned; };
struct PruningResult { TreeView tree; std::vector<Decision> decisions; };
struct SequenceEntry { TreeView tree; Fraction alpha; };
PruningResult reducedError(const Node* root, const Rows& rows, const std::vector<Attribute>& attributes);
std::vector<SequenceEntry> costComplexity(const Node* root);
