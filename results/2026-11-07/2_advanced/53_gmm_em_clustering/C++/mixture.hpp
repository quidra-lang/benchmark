#ifndef MIXTURE_HPP
#define MIXTURE_HPP
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <limits>
#include <numeric>
#include <optional>
#include <sstream>
#include <string>
#include <tuple>
#include <vector>
using I = std::int64_t;
using Vec = std::array<double, 2>;
using Cov = std::array<double, 3>;
using Ids = std::vector<int>;
using Values = std::vector<double>;
using Lines = std::vector<std::string>;
using Grid = std::vector<std::string>;
constexpr double pi = 3.141592653589793;
enum class Type { FULL, TIED, DIAG, SPHERICAL };
struct Point {
    std::string id;
    Vec xy;
};
struct Component {
    double weight;
    Vec mean;
    Cov cov;
};
struct Model {
    std::vector<Component> components;
    Type type = Type::FULL;
};
struct Params {
    Ids ks;
    std::vector<Type> types;
    int iterations, kmeans_max, folds, width, height;
    double epsilon, tolerance, uncertain, low_density, xmin, xmax, ymin, ymax;
    Values gof;
};
struct Input {
    std::vector<Point> points;
    Params params;
    std::array<Model, 5> initial;
};
struct Record {
    std::array<double, 4> responsibility{}, scores{};
    double log_density = 0;
};
struct Expectation {
    std::vector<Record> records;
    double loglik = 0;
};
struct Fit {
    Model model;
    Expectation e;
    Values trace;
    int settled = 0, largest = 1;
    Ids violations;
};
struct Eigen {
    double leading, trailing;
    Vec direction;
    double angle, major, minor, area, correlation;
};
struct Kmeans {
    std::vector<Vec> centers;
    Ids assignment, sizes;
    int iterations = 0;
    double inertia = 0;
};
Input load();
const char *type_name(Type type);
double determinant(Cov cov);
double mahalanobis(Vec point, Vec mean, Cov cov);
double weighted_log(Vec point, const Component &component);
Eigen eigen(Cov cov);
double bhattacharyya(const Component &a, const Component &b);
Model adjust(Model initial, Type type);
Expectation expectation(const std::vector<Point> &points, const Model &model);
Fit run_em(const std::vector<Point> &points, Model initial, Type type, const Params &params);
double distance2(Vec a, Vec b);
double distance(Vec a, Vec b);
Kmeans run_kmeans(const std::vector<Point> &points, const Model &initial, int maximum);
I rounded(double value, int digits = 4);
std::string real(double value, int digits = 4);
void frame(Lines &lines, const Grid &grid);
void save(const std::string &name, const Lines &lines);
#endif
