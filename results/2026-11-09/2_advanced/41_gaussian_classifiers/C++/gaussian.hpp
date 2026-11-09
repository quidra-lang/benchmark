#ifndef GAUSSIAN_HPP
#define GAUSSIAN_HPP
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <map>
#include <numeric>
#include <sstream>
#include <string>
#include <utility>
#include <vector>
using Vector = std::array<double, 6>;
using Matrix = std::array<Vector, 6>;
using Lines = std::vector<std::string>;
struct Row {
    int id = 0, label = 0;
    Vector values{};
};
using Rows = std::vector<Row>;
using Features = std::vector<int>;
struct Subset {
    std::string name;
    Features features;
};
struct Params {
    bool empirical = true;
    double smoothing = 0, gamma = 0, outlier = 0;
    std::vector<double> smoothing_grid, gamma_grid, calibration, reject;
    std::vector<int> curve;
    int folds = 0, bootstrap = 0, map_width = 0, map_height = 0, plot_width = 0, plot_height = 0;
    std::int64_t seed = 0;
    std::vector<Subset> subsets;
    std::vector<std::pair<int, int>> pairs;
};
struct Dataset {
    Lines features, classes;
    Rows train, test;
    std::array<std::array<double, 5>, 5> costs{};
    Params params;
};
Dataset read_dataset();
Matrix cholesky(const Matrix &matrix, int size);
Vector forward(const Matrix &lower, const Vector &right, int size);
Vector backward(const Matrix &lower, const Vector &right, int size);
double log_determinant(const Matrix &lower, int size);
double quadratic(const Matrix &lower, const Vector &right, int size);
struct Eigen {
    Vector values{};
    Matrix vectors{};
    int sweeps = 0;
};
Eigen jacobi(const Matrix &matrix, int size);
struct Statistics {
    int count = 0, classes = 0, size = 0;
    std::array<int, 5> counts{};
    std::array<Vector, 5> means{};
    std::array<Matrix, 5> scatter{};
    Vector center{}, variance{};
    std::array<double, 5> priors{};
};
Statistics statistics(const Rows &rows, const Features &features, int classes, bool empirical);
struct Model {
    int kind = 0;
    Features features;
    Statistics stats;
    std::array<Matrix, 5> covariance{}, lower{};
    std::array<double, 5> log_det{};
    double max_variance = 0, added = 0;
};
Model train(const Rows &rows, const Features &features, int classes, int kind, bool empirical,
            double smoothing, double gamma);
struct Prediction {
    int predicted = 0, decision = 0;
    std::array<double, 5> posterior{}, log_posterior{}, distance{};
    double confidence = 0;
};
Prediction predict(const Model &model, const Vector &values,
                   const std::array<std::array<double, 5>, 5> &costs);
struct Fraction {
    std::int64_t numerator = 0, denominator = 1;
    Fraction(std::int64_t a = 0, std::int64_t b = 1);
    Fraction add(const Fraction &other) const;
    Fraction divide(std::int64_t value) const;
};
using Confusion = std::array<std::array<int, 5>, 5>;
struct Measures {
    Confusion confusion{};
    std::array<int, 5> support{}, predicted{};
    int correct = 0, total = 0, classes = 0;
    Fraction accuracy, balanced, kappa;
    std::array<Fraction, 5> recall{}, precision{}, f1{};
    double macro_f1 = 0;
};
Measures evaluate(const Rows &rows, const std::vector<int> &prediction, int classes);
struct McNemar {
    int b01 = 0, b10 = 0;
    double chi2 = 0;
};
McNemar mcnemar(const Rows &rows, const std::vector<int> &a, const std::vector<int> &b);
struct Generator {
    std::int64_t state;
    std::int64_t draw();
};
std::string real(double value);
std::string fraction(const Fraction &value);
Lines frame(const Lines &cells);
int cell(double value, double low, double high, int size);
void write_lines(const std::string &name, const Lines &lines);
std::string numbers(const Vector &values, int size);
std::string integers(const std::vector<int> &values);
std::string names(const Features &features, const Lines &names);
#endif
