#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <numeric>
#include <set>
#include <sstream>
#include <string>
#include <utility>
#include <vector>
using Vector = std::vector<double>;
using Ints = std::vector<int>;
using Lines = std::vector<std::string>;
struct Row {
    std::string id;
    Vector values;
    int label;
};
using Rows = std::vector<Row>;
struct Params {
    int rounds = 0, bins = 0, folds = 0, classes = 0, samme_rounds = 0, permutations = 0, bootstrap = 0;
    double smoothing = 0, convergence = 0, clip = 0;
    std::int64_t permutation_seed = 0, noise_seed = 0, bootstrap_seed = 0;
    Lines variants;
    Vector margins, shrinkage;
    Ints noise, sizes;
};
struct Input {
    Rows train, test, multi_train, multi_test;
    Lines names, multi_names;
    Params params;
};
Input read_input();
struct Stump {
    int feature = 0;
    Vector thresholds, values;
    double output(const Vector &row) const;
};
struct Feature {
    Ints order, ends;
    Vector thresholds, cuts;
};
struct Search {
    std::vector<Feature> features;
};
Search prepare(const Rows &rows, int bins);
struct Candidate {
    Stump stump;
    double error = 0;
    int polarity = 0;
};
Candidate discrete_stump(const Rows &rows, const Search &search, const Vector &weights);
Candidate regression_stump(const Rows &rows, const Search &search, const Vector &targets,
                           const Vector &weights);
Candidate multiclass_stump(const Rows &rows, const Search &search, const Vector &weights, int classes);
struct RealCandidate {
    Stump stump;
    double z;
};
RealCandidate real_stump(const Rows &rows, const Search &search, const Vector &weights, int bins,
                         double smoothing);
struct Round {
    Stump stump;
    Vector weights;
    double error = 0, alpha = 0, z = 0, bound = 0, loss = 0;
    int polarity = 0;
};
struct Model {
    std::string variant, stop = "completed";
    std::vector<Round> rounds;
    std::vector<Vector> cuts;
};
Model discrete(const Rows &rows, const Params &p, int maximum, double shrinkage = 1, Vector weights = {});
Model samme(const Rows &rows, const Params &p);
Model variant_train(const Rows &rows, const Params &p, const std::string &variant);
std::string real(double value, int precision = 4);
std::string ratio(std::int64_t a, std::int64_t b);
int prediction(double score);
std::pair<std::int64_t, std::int64_t> auc(const Rows &rows, const Vector &scores);
std::vector<Ints> confusion(const Rows &rows, const Ints &predictions, int classes);
int margin_count(const Vector &margins, double threshold);
void write_lines(const std::string &name, const Lines &lines);
