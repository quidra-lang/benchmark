#ifndef EPIDEMIC_HPP
#define EPIDEMIC_HPP
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <functional>
#include <iomanip>
#include <limits>
#include <numeric>
#include <sstream>
#include <string>
#include <tuple>
#include <vector>
using I = std::int64_t;
using Field = std::vector<double>;
using States = std::vector<Field>;
using Matrix = std::vector<Field>;
using Ids = std::vector<int>;
using Lines = std::vector<std::string>;
struct Group {
    std::string name;
    I population;
    double fatality;
};
struct Intervention {
    int day;
    double multiplier;
};
struct Scenario {
    std::string name;
    double multiplier;
};
struct ContactChange {
    std::string name, group;
    double factor;
};
struct Params {
    double sigma = 0, gamma = 0, e0 = 0, i0 = 0, beta_min = 0, beta_max = 0, rho_min = 0,
           rho_max = 0, delta_beta = 0, delta_gamma = 0, alpha = 0, chi = 0, psi = 0, omega = 0,
           effect_width = 0, outlier = 0, threshold = 0;
    int beta_count = 0, rho_count = 0, golden = 0, rounds = 0, nelder = 0, holdout = 0,
        death_lag = 0, generation = 0, horizon = 0;
    std::vector<I> milestones;
    std::vector<Scenario> scenarios;
    std::vector<ContactChange> changes;
};
struct Input {
    std::vector<I> cases, deaths;
    std::vector<Group> groups;
    Matrix contacts;
    std::vector<Intervention> interventions;
    Params params;
};
Input load();
void save(const std::string &name, const Lines &lines);
enum class Kind { seird, sir, age, generation };
struct Model {
    Kind kind;
    double beta = 0, gamma = 0, sigma = 0, population = 0, fatality = 0, e0 = 0, i0 = 0;
    std::vector<Group> groups;
    Matrix contacts;
    Field initial() const;
    Field rates(const Field &state, double multiplier) const;
    void reset(Field &state) const;
};
Field rk4(const Model &model, const Field &state, double multiplier);
States simulate(const Model &model, Field state, const Field &multipliers);
struct GoldenRecord {
    double a, b, c, d, fc, fd;
};
struct Golden {
    double point, value;
    std::vector<GoldenRecord> records;
};
Golden golden(const std::function<double(double)> &function, double a, double b, int iterations);
using Point = std::array<double, 2>;
struct Vertex {
    Point point;
    double value;
    int number;
};
struct SimplexRecord {
    std::string operation;
    Vertex best;
};
struct Simplex {
    std::array<Vertex, 3> initial, final;
    std::vector<SimplexRecord> records;
};
Simplex nelder_mead(const std::function<double(Point)> &function, Point start,
                    const Params &params);
std::string real(double value, int digits);
Lines curve_plot(const std::vector<I> &cases, const Field &fitted);
template <typename... T> void line(Lines &lines, const T &...values) {
    std::ostringstream out;
    (out << ... << values);
    lines.push_back(out.str());
}
#endif
