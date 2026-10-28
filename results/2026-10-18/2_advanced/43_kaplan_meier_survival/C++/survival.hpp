#ifndef SURVIVAL_HPP
#define SURVIVAL_HPP
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <map>
#include <numeric>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <vector>
using Vector = std::array<double, 6>;
using Matrix = std::array<Vector, 6>;
using Lines = std::vector<std::string>;
constexpr double normal_z = 1.959963984540054;
struct Subject {
    int id = 0, group = 0, time = 0, event = 0, age = 0, stage = 0;
    char sex = 'F';
};
using Subjects = std::vector<Subject>;
struct Params {
    Lines groups, subgroups, covariates;
    std::vector<int> report_times;
    int tau = 0, life_width = 0, life_intervals = 0, landmark = 0, residuals = 0, plot_width = 0,
        plot_height = 0, plot_time = 0, plot_divisions = 0;
    std::string strata;
};
struct Dataset {
    Subjects subjects;
    Params params;
};
Dataset read_dataset();
int risk_size(const Subjects &subjects, int time);
int event_count(const Subjects &subjects, int time);
std::vector<int> event_times(const Subjects &subjects);
struct KMRow {
    int time = 0, risk = 0, events = 0, censored = 0;
    double survival = 1, std_err = 0, lower = 0, upper = 0, hazard = 0, hazard_se = 0;
    bool interval_defined = false, error_defined = true;
};
std::vector<KMRow> kaplan_meier(const Subjects &subjects);
KMRow row_at(const std::vector<KMRow> &rows, int time);
struct LifeRow {
    int a, b, risk, events, withdrawn, exposure2;
    double probability, survival, std_err, hazard;
};
std::vector<LifeRow> life_table(const Subjects &subjects, int width, int intervals);
Vector solve(Matrix matrix, Vector right, int size);
Matrix inverse(const Matrix &matrix, int size);
double log_gamma(double a);
double gamma_q(double a, double x);
double p_value(double statistic, int degrees);
struct GroupTest {
    std::vector<int> groups;
    std::array<int, 6> events{};
    Vector observed{}, expected{};
    Matrix covariance{};
    double statistic = 0, p = 1;
    int degrees = 0;
};
GroupTest weighted_test(const Subjects &subjects, const std::vector<int> &groups, int kind,
                        int total_subjects);
GroupTest combine_tests(const std::vector<GroupTest> &tests);
void finalize_test(GroupTest &test);
struct CoxTime {
    int time = 0, events = 0;
    double s0 = 0;
    Vector s1{};
};
struct CoxEvaluation {
    double loglik = 0;
    Vector score{};
    Matrix information{};
    std::vector<double> theta, risks;
    std::vector<CoxTime> times;
};
CoxEvaluation cox_evaluate(const Subjects &subjects, const std::vector<Vector> &design, int size,
                           const Vector &beta);
struct CoxFit {
    Vector beta{};
    CoxEvaluation initial, final;
    std::vector<std::pair<double, Vector>> iterations;
};
CoxFit cox_fit(const Subjects &subjects, const std::vector<Vector> &design, int size);
Lines curve_plot(const std::vector<std::vector<KMRow>> &curves, const std::vector<int> &maximums,
                 const Params &params);
#endif
