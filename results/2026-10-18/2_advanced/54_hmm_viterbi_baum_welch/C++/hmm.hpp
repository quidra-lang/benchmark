#ifndef HMM_HPP
#define HMM_HPP
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <limits>
#include <numeric>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <vector>
using I = std::int64_t;
using Path = std::vector<int>;
using Values = std::vector<double>;
using Lines = std::vector<std::string>;
using Rows = std::vector<Lines>;
using StateValues = std::array<double, 4>;
using Matrix = std::array<StateValues, 4>;
using Emissions = std::array<std::array<double, 8>, 4>;
using Confusion = std::array<std::array<I, 4>, 4>;
struct Model {
    std::string name, states, symbols;
    char missing;
    StateValues initial{};
    Matrix transition{};
    Emissions emission{};
    int k() const {
        return states.size();
    }
    int m() const {
        return symbols.size();
    }
};
struct Input {
    Model model;
    Rows sequences, labeled, parameters;
};
struct Sequence {
    std::string name, role;
    Path observation, truth;
};
struct Params {
    int iterations, folds, min_length, max_missing, segment_state, merge_gap, min_segment, first_motif,
        second_motif, min_rich, min_motif, boundary_tolerance, posterior_samples, sample_count, sample_length;
    I posterior_seed, sample_seed;
    double pseudocount, confidence;
    Values smoothing;
    Lines candidates;
    Path rich;
};
struct FB {
    std::vector<StateValues> forward, backward, posterior, emissions;
    Values scales;
    double loglik = 0;
};
struct Viterbi {
    Path path;
    double logprob = 0;
};
struct Decoding {
    FB fb;
    Viterbi viterbi;
    Path posterior;
    Values confidence;
};
struct Pair {
    Path observation, path;
};
struct Run {
    int state, start, end;
};
struct Region {
    int start, end;
    int length() const {
        return end - start + 1;
    }
};
struct MatchCounts {
    I predicted = 0, truth = 0, matched_predicted = 0, matched_truth = 0;
};
struct Generator {
    I state;
    double uniform();
};
Input load();
void normalize(double *values, int count);
std::string real(double value, int places = 4);
Lines model_lines(const Model &model);
void save(const std::string &name, const Lines &lines);
int maximum(const double *values, int count);
double emission(const Model &model, int observation, int state);
FB forward_backward(const Model &model, const Path &observation);
double transition_posterior(const Model &model, const FB &fb, int position, int state, int next);
Viterbi viterbi(const Model &model, const Path &observation);
Decoding decode(const Model &model, const Path &observation);
Model baum_welch(const Model &model, const std::vector<Path> &observations, double pseudocount);
Model counting(const Model &model, const std::vector<Pair> &pairs, double alpha, const std::string &name);
double total_loglik(const Model &model, const std::vector<Path> &observations);
std::string fraction(I numerator, I denominator);
void accumulate(Confusion &matrix, const Path &truth, const Path &predicted);
I correct(const Path &truth, const Path &predicted);
Lines matrix_lines(const Model &model, const Confusion &matrix);
Lines metric_lines(const Model &model, const Confusion &matrix);
std::vector<Run> runs(const Path &path);
MatchCounts region_counts(const std::vector<Region> &predicted, const std::vector<Region> &truth);
MatchCounts boundary_counts(const Path &predicted, const Path &truth, int tolerance);
int draw(const double *weights, int count, Generator &generator);
Pair synthetic(const Model &model, int length, Generator &generator);
Path posterior_sample(const Model &model, const FB &fb, Generator &generator);
#endif
