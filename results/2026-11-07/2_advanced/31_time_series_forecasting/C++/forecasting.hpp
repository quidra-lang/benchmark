#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <functional>
#include <iomanip>
#include <limits>
#include <map>
#include <numeric>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <vector>
using Vector = std::vector<double>;
using Matrix = std::vector<Vector>;
using Integer = std::int64_t;
struct Params {
    int season, holdout, horizon, cv_start, combo, max_ar, max_lag;
    Vector alpha, beta, gamma, phi;
    std::vector<int> ljung_box;
    double outlier, z80, z95;
};
struct Series {
    std::string name;
    std::vector<std::string> periods;
    Vector raw;
    std::vector<bool> missing;
};
struct Inventory {
    Integer on_hand;
    int lead_time, review;
    double service;
};
struct Input {
    Params params;
    std::vector<Series> series;
    std::map<std::pair<std::string, std::string>, std::string> events;
    std::map<std::string, Inventory> inventory;
};
Input read_input();
std::string next_month(const std::string &);
std::string real(double);
void write_lines(std::ostream &, const std::vector<std::string> &);
double total(const Vector &);
double mean(const Vector &);
double sample_variance(const Vector &);
double rmse(const Vector &);
struct Decomposition {
    Vector trend, additive, multiplicative, residual_add, residual_mult;
};
Decomposition decompose(const Vector &, int);
std::pair<double, double> regression(const Vector &);
struct SmoothParameters {
    double alpha = 0, beta = 0, gamma = 0, phi = 1;
};
struct State {
    double level, slope;
    Vector seasonal;
};
struct Smoothed {
    Vector residuals;
    std::vector<State> states;
};
Smoothed smooth(int, const Vector &, int, SmoothParameters);
Vector smooth_forecast(int, const State &, SmoothParameters, int, int, int);
Vector difference(const Vector &, int, int);
struct Correlation {
    double mean, variance;
    Vector acf;
};
Correlation autocorrelation(const Vector &, int);
struct Levinson {
    Matrix coefficients;
    Vector partial, variance;
};
Levinson durbin_levinson(const Vector &, int);
Vector ar_residuals(const Vector &, double, const Vector &);
Vector ar_forecast(const Vector &, const Vector &, int, int, int, int, double, const Vector &);
std::pair<double, double> ljung_box(const Vector &, int);
double scale_delta(const Vector &, int);
double winkler(double, double, double, double);
struct Accuracy {
    double me = 0, mae = 0, rmse = 0, mape = 0, smape = 0, mase = 0, fva = 0, cv_rmse = 0, winkler80 = 0,
           winkler95 = 0;
    int cover80 = 0, cover95 = 0, rank = 0;
};
Accuracy evaluate(const Vector &, const Vector &, const Vector &, double, double, double);
std::vector<int> rank_accuracy(std::vector<Accuracy> &);
