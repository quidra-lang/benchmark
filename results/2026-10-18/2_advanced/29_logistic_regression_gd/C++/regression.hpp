#pragma once
#include <algorithm>
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
#include <utility>
#include <vector>
using Integer = std::int64_t;
using Vector = std::vector<double>;
using Matrix = std::vector<Vector>;
struct Row {
    std::string id;
    Vector values;
    int label;
};
struct Table {
    std::vector<std::string> names;
    std::vector<Row> rows;
};
struct Params {
    int positive, degree, gd_iterations, batch, epochs, softmax_iterations, bootstrap, permutations, width,
        height, fp_cost, fn_cost;
    Integer sgd_seed, bootstrap_seed, permutation_seed;
    double threshold, gd_rate, sgd_rate, softmax_rate, softmax_lambda;
    Vector lambdas;
};
struct Feature {
    std::vector<int> indices;
    std::string name;
};
struct Statistics {
    Vector mean, deviation;
};
Table read_table(const std::string &);
Params read_params();
std::vector<Feature> features(const std::vector<std::string> &, int);
Vector expand(const Vector &, const std::vector<Feature> &);
Matrix expanded(const std::vector<Row> &, const std::vector<Feature> &);
Statistics statistics(const Matrix &, int);
Matrix standardize(const Matrix &, const Statistics &, int);
Vector standardize_point(const Vector &, const Statistics &, int);
std::vector<int> labels(const std::vector<Row> &, int);
double score(const Vector &, const Vector &);
double sigmoid(double);
double logistic_loss(double, int);
Vector probabilities(const Vector &, const Matrix &);
double average_loss(const Vector &, const Matrix &, const std::vector<int> &);
double objective(const Vector &, const Matrix &, const std::vector<int> &, double);
Vector gradient(const Vector &, const Matrix &, const std::vector<int> &, double);
Matrix hessian(const Vector &, const Matrix &, double);
double length(const Vector &);
class Minstd {
    Integer state;

  public:
    explicit Minstd(Integer seed) : state(seed) {
    }
    Integer draw();
    void shuffle(std::vector<int> &);
};
Matrix cholesky(const Matrix &);
Vector solve(const Matrix &, const Vector &);
struct Checkpoint {
    int iteration;
    Vector weights;
};
std::vector<Checkpoint> newton(const Matrix &, const std::vector<int> &, double);
std::vector<Checkpoint> gradient_descent(const Matrix &, const std::vector<int> &, double, double, int);
std::vector<Checkpoint> stochastic(const Matrix &, const std::vector<int> &, double, const Params &);
struct SoftPoint {
    Vector probabilities;
    double loss;
    int predicted;
};
SoftPoint soft_point(const Matrix &, const Vector &, int);
double soft_loss(const Matrix &, const Matrix &, const std::vector<int> &);
double soft_objective(const Matrix &, const Matrix &, const std::vector<int> &, double);
Matrix soft_gradient(const Matrix &, const Matrix &, const std::vector<int> &, double);
struct SoftCheckpoint {
    int iteration;
    Matrix weights;
};
std::vector<SoftCheckpoint> train_softmax(const Matrix &, const std::vector<int> &, int, const Params &);
std::string real(double, int = 4);
std::string ratio(Integer, Integer);
struct Fraction {
    Integer numerator, denominator;
    double value() const;
    std::string text() const;
};
struct Confusion {
    Integer tp = 0, fp = 0, tn = 0, fn = 0;
};
Confusion confusion(const Vector &, const std::vector<int> &, double);
Fraction auc(const Vector &, const std::vector<int> &);
struct RocPoint {
    double threshold;
    Integer tp, fp;
};
std::vector<RocPoint> roc(const Vector &, const std::vector<int> &);
