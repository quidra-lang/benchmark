#ifndef TRACKER_HPP
#define TRACKER_HPP
#include <algorithm>
#include <array>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <limits>
#include <map>
#include <numeric>
#include <optional>
#include <sstream>
#include <string>
#include <utility>
#include <vector>
using Vector = std::vector<double>;
using Matrix = std::vector<Vector>;
using Position = std::array<double, 2>;
using Estimate = std::array<double, 4>;
using Pair = std::pair<int, int>;
using Lines = std::vector<std::string>;
Matrix zeros(int rows, int columns = -1), identity(int n), diagonal(const Vector &values),
    transpose(const Matrix &a), add(const Matrix &a, const Matrix &b),
    subtract(const Matrix &a, const Matrix &b), product(const Matrix &a, const Matrix &b),
    inverse(const Matrix &a);
Vector add(const Vector &a, const Vector &b), subtract(const Vector &a, const Vector &b),
    product(const Matrix &a, const Vector &b);
double determinant2(const Matrix &a), quadratic2(Position v, const Matrix &a);
struct Params {
    bool ca = false;
    double q_cv = 0, q_ca = 0, sigma = 0, velocity = 0, acceleration = 0, gate = 0, delta = 0,
           cutoff = 0, bound = 0, xmin = 0, xmax = 0, ymin = 0, ymax = 0;
    int confirm = 0, window = 0, deletion = 0, width = 0, height = 0;
    std::array<double, 3> abg{};
    std::array<double, 2> imm_q{}, imm_initial{};
    std::array<std::array<double, 2>, 2> transition{};
    Vector edges;
};
struct Innovation {
    Position residual{};
    Matrix covariance, precision;
    double distance = 0;
};
struct Kalman {
    bool ca;
    double q;
    Vector x, xp;
    Matrix P, Pp, F, H, R;
    Kalman(bool ca, double q, const Params &p, Position measurement);
    void predict(double interval);
    Innovation innovation(Position measurement) const;
    double update(const Innovation &innovation);
};
struct History {
    Vector x, xp;
    Matrix P, Pp, F;
};
Matrix transition(bool ca, double t), process_noise(bool ca, double t, double q);
std::vector<Vector> smooth(const std::vector<History> &history);
std::vector<Pair> minimum_matching(const Matrix &costs);
std::vector<Pair> optimal_assignment(const Matrix &costs,
                                     const std::vector<std::vector<bool>> &usable);
struct IMM {
    std::array<Kalman, 2> models;
    std::array<double, 2> probabilities;
    std::array<std::array<double, 2>, 2> transition;
    IMM(const Params &p, Position measurement);
    void step(double interval, std::optional<Position> measurement);
    Estimate estimate() const;
};
struct Continuity {
    int covered = 0, breaks = 0, swaps = 0, delay = -1;
};
double squared_distance(Position a, Position b), distance(Position a, Position b),
    ospa(const std::vector<Position> &a, const std::vector<Position> &b, double cutoff);
Continuity continuity(const std::vector<int> &labels);
std::string real(double value);
template <class... T> void line(Lines &lines, const T &...values) {
    std::ostringstream out;
    (out << ... << values);
    lines.push_back(out.str());
}
#endif
