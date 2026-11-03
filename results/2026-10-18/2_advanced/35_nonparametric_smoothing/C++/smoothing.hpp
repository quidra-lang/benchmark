#ifndef SMOOTHING_HPP
#define SMOOTHING_HPP
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <functional>
#include <iomanip>
#include <memory>
#include <numeric>
#include <optional>
#include <sstream>
#include <string>
#include <utility>
#include <vector>
using Integer = std::int64_t;
using Vector = std::vector<double>;
using Lines = std::vector<std::string>;
using Optional = std::optional<double>;
struct Data {
    std::vector<int> x, y;
    Vector real_x, real_y;
};
struct Series {
    std::string name;
    Data data;
};
struct TestPoint {
    std::string series;
    int x;
};
struct Params {
    std::array<Lines, 17> rows;
};
struct Input {
    std::vector<Series> series;
    std::vector<TestPoint> tests;
    Params params;
};
int hundredths(const std::string &text);
Input read_input();
enum class Kind { linear, mean, median, nw, ll, loess, spline, isotonic };
struct Parameter {
    std::string text;
    double value = 0;
    int integer = 0;
};
struct Method {
    std::string name;
    Kind kind;
    std::string kernel;
    int degree = 0;
    std::vector<Parameter> candidates;
};
struct KernelResult {
    Optional estimate;
    Vector weights;
    Optional leverage;
};
KernelResult kernel_estimate(const Data &data, const std::string &kernel, int bandwidth, int position,
                             bool local_linear);
struct LocalFit {
    double value, zeta;
    Vector weights;
};
LocalFit local_fit(const Data &data, int position, int span, int degree, const Vector &rho);
double median(Vector values);
struct Robust {
    double scale;
    int zero;
    double change;
};
struct LoessFit {
    Vector fitted, leverage, rho;
    double edf = 0;
    std::vector<Robust> iterations;
};
LoessFit loess_fit(const Data &data, int span, int degree, int iterations);
struct SplineValues {
    Vector fitted, gamma;
};
struct Spline {
    std::vector<int> positions;
    Vector x, h, d, l1, l2;
    double penalty;
    std::vector<SplineValues> basis;
    Spline(std::vector<int> positions, double penalty);
    SplineValues fit(const Vector &values) const;
    double evaluate(const SplineValues &fit, int position) const;
    void prepare_basis();
    Vector leverage();
    Vector weights(int position) const;
};
Optional loo_score(const Vector &observed, const std::vector<Optional> &predictions);
double gcv_score(const Vector &observed, const Vector &fitted, double edf);
std::size_t selected_candidate(const std::vector<Optional> &scores);
struct IsoBlock {
    int first, last;
    Integer sum;
    int count;
};
struct Fit {
    Data data;
    Method method;
    Parameter parameter;
    Vector fitted, leverage, rho;
    Optional edf;
    double intercept = 0, slope = 0, xbar = 0, sxx = 0;
    std::shared_ptr<Spline> spline;
    SplineValues spline_values;
    std::vector<IsoBlock> blocks;
    std::vector<Robust> robust;
    std::string direction;
    double increasing_rss = 0, decreasing_rss = 0;
    bool defined = true;
};
Fit make_fit(const Data &data, const Method &method, const Parameter &parameter, const std::string &direction,
             int robust_iterations, bool full);
Optional estimate(const Fit &fit, int position);
Vector weights(const Fit &fit, int position);
#endif
