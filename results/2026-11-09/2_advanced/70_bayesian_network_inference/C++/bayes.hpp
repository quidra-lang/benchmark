#ifndef BAYES_HPP
#define BAYES_HPP
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <deque>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <limits>
#include <map>
#include <numeric>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <vector>
using I = long long;
using Vars = std::vector<int>;
using Names = std::vector<std::string>;
using Lines = Names;
using Assignment = std::array<int, 15>;
using Evidence = std::vector<std::pair<int, int>>;
using CPT = std::vector<std::vector<double>>;
using Counts = std::vector<std::vector<I>>;
struct Network {
    Names names;
    std::vector<Names> states;
    std::vector<Vars> parents;
    std::vector<std::optional<CPT>> expert;
};
struct Input {
    Network network;
    std::vector<Assignment> samples;
    Lines queries, settings;
};
Names split(const std::string &text, char delimiter = ' ');
Input read_inputs();
I parent_row(const Vars &parents, const Assignment &assignment, const Vars &sizes),
    entry_count(const Vars &variables, const Vars &sizes);
Counts count_samples(int variable, const Vars &parents, const std::vector<Assignment> &samples,
                     const Vars &sizes);
CPT learn(const Counts &counts, double alpha);
double total(const std::vector<double> &values),
    log_likelihood(const Counts &counts, const CPT &cpt),
    family_score(int variable, Vars parents, const std::vector<Assignment> &samples,
                 const Vars &sizes, double alpha);
I parameter_count(const Counts &counts);
Assignment decode(I index, const Vars &variables, const Vars &sizes, Assignment initial = {});
int evidence_state(const Evidence &evidence, int variable);
struct Factor {
    Vars variables;
    std::vector<double> values;
    const Vars *sizes;
    double value(const Assignment &assignment) const;
    Factor reduced(const Evidence &evidence) const, multiplied(const Factor &other) const,
        eliminate(int variable, bool maximize) const;
};
Factor cpt_factor(int variable, const Vars &parents, const CPT &cpt, const Vars &sizes),
    multiply(const std::vector<Factor> &factors, const Vars &sizes);
struct Graph {
    std::array<std::array<bool, 15>, 15> adjacent{};
    std::array<bool, 15> present{};
};
Graph interaction_graph(const std::vector<Factor> &factors);
struct Step {
    int variable, fill;
    Vars scope;
    I size;
};
struct Plan {
    std::vector<Step> steps;
    I maximum = 0, total = 0;
};
Plan make_plan(const std::vector<Factor> &factors, const Vars &eliminate, bool given,
               const Vars &order, const Vars &sizes);
struct Execution {
    Factor final;
    std::vector<std::pair<int, Factor>> products;
};
Execution execute(const std::vector<Factor> &initial, const Plan &plan, const Vars &sizes,
                  bool maximize = false);
Assignment traceback(const Execution &execution, const Vars &sizes);
struct Minstd {
    I state;
    explicit Minstd(I seed) : state(seed) {}
    double uniform();
};
int choose(const std::vector<double> &probabilities, Minstd &random);
std::pair<Assignment, double> weighted_sample(const Vars &topological,
                                              const std::vector<Vars> &parents,
                                              const std::vector<CPT> &cpts, const Vars &sizes,
                                              const Evidence &evidence, Minstd &random);
template <class... T> void line(Lines &out, const T &...values) {
    std::ostringstream stream;
    (stream << ... << values);
    out.push_back(stream.str());
}
#endif
