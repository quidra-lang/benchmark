#ifndef REGRESSION_HPP
#define REGRESSION_HPP
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <limits>
#include <map>
#include <numeric>
#include <set>
#include <sstream>
#include <string>
#include <utility>
#include <vector>
using Vector = std::vector<double>;
using Matrix = std::vector<Vector>;
using Lines = std::vector<std::string>;
struct Cell {
    bool missing = true;
    double number = 0;
    std::string label;
};
using Record = std::vector<Cell>;
struct Dataframe {
    Lines names;
    std::vector<bool> categorical;
    std::vector<Record> rows;
};
struct Params {
    double rank_tol = 0, alpha = 0, confidence = 0, leverage = 0, studentized = 0, cook = 0, dffits = 0,
           vif = 0, durbin = 0, breusch = 0, normality = 0, plot_limit = 0;
    int best_subsets = 0, plot_width = 0, plot_height = 0;
};
struct Input {
    Dataframe data, prediction;
    Lines formulas;
    Params params;
};
Input read_input();
struct Factor {
    std::string name;
    int column = 0, power = 1;
    bool categorical = false;
};
struct Term {
    std::vector<Factor> factors;
    std::string name;
};
struct Formula {
    int response = 0, weight = -1;
    std::string raw;
    std::vector<Term> terms;
};
struct Component {
    std::string name, label;
    int column = 0, power = 1;
    bool categorical = false;
};
struct Column {
    std::string name;
    int term = -1;
    std::vector<Component> components;
};
struct Design {
    Formula formula;
    std::vector<int> used;
    std::map<int, Lines> levels;
    std::vector<Column> columns;
    Matrix x;
    Vector y, weights;
};
Formula parse_formula(const std::string &line, const Dataframe &data);
bool contained(const Term &a, const Term &b);
std::string formula_text(const Formula &formula, const std::vector<int> &terms, const Dataframe &data);
Design build_design(const Formula &formula, const Dataframe &data);
std::vector<int> selected_columns(const Design &design, const std::vector<int> &terms);
Vector record_values(const std::vector<Column> &columns, const Record &record);
bool predictable(const Design &design, const Record &record);
struct Fit {
    int rank = 0;
    std::vector<int> accepted;
    std::vector<bool> alias;
    Vector coefficients, effects, variance, fitted, residuals, weighted_residuals, leverage;
    Matrix triangular, inverse, u, g;
    double rss = 0;
};
Fit fit(const Matrix &x, const Vector &y, const Vector &weights, double tolerance);
double log_gamma(double x);
double beta_fraction(double a, double b, double x);
double beta_i(double x, double a, double b);
double gamma_q(double a, double x);
double p_t(double value, double degrees);
double p_f(double value, double first, double second);
double p_chi(double value, double degrees);
double t_quantile(double confidence, double degrees);
std::string significance(double p);
std::string real(double value);
std::string p_format(double value);
struct Diagnostics {
    Vector standardized, studentized, cooks, dffits;
    std::vector<std::string> flags;
    Matrix dfbetas;
    std::array<int, 4> flag_counts{};
    int any = 0;
    double durbin = 0, bp = 0, bp_p = 0, jb = 0, jb_p = 0, skewness = 0, kurtosis = 0;
    int bp_df = 0;
};
Diagnostics diagnostics(const Matrix &x, const Vector &weights, const Fit &model, const Params &params);
#endif
