#ifndef CLASSIFIER_HPP
#define CLASSIFIER_HPP
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <numeric>
#include <sstream>
#include <string>
#include <tuple>
#include <vector>
using Point = std::array<double, 2>;
using Field = std::vector<double>;
using Ids = std::vector<int>;
using Matrix = std::vector<Field>;
using Lines = std::vector<std::string>;
struct Example {
    std::string id;
    Point point;
    int label;
};
struct Kernel {
    std::string name, kind;
    int degree = 1;
    double gamma = 0, coef0 = 0;
};
struct Params {
    Field c_grid;
    std::vector<Kernel> kernels;
    double tolerance = 0, epsilon = 0, multi_c = 0, lambda = 0, x_min = 0, x_max = 0, y_min = 0,
           y_max = 0;
    int max_passes = 0, folds = 0, newton_iterations = 0, pegasos_iterations = 0, width = 0,
        height = 0;
    std::int64_t seed = 0;
    Ids learning;
    std::string multi_name;
};
struct Input {
    std::vector<Example> train, test, multi_train, multi_test;
    Params params;
};
Input load();
double kernel_value(const Kernel &kernel, Point a, Point b);
Matrix kernel_matrix(const Kernel &kernel, const std::vector<Example> &data);
std::string kernel_description(const Kernel &kernel);
struct Pass {
    bool full;
    int examined, changed;
    Field alpha;
};
struct Model {
    std::vector<Example> data;
    Kernel kernel;
    Matrix matrix;
    double c = 0, b = 0;
    Field alpha;
    int full = 0, nonbound = 0, examined = 0, steps = 0;
    std::array<int, 3> choices{}, clipping{};
    bool converged = false;
    std::vector<Pass> passes;
    double decision(Point point) const;
    Field training_decisions() const;
};
Model train(const std::vector<Example> &data, const Kernel &kernel, Matrix matrix, double c,
            const Params &params);
struct Multi {
    std::array<Model, 3> rest, pairs;
};
struct MultiPrediction {
    std::array<double, 3> rest, pairs, scores{};
    std::array<int, 3> votes{};
    int ovr = 1, ovo = 1;
    bool tie = false;
};
Multi train_multi(const Input &input, const Kernel &kernel);
MultiPrediction classify(const Multi &models, Point point);
using Confusion = std::array<std::array<int, 3>, 3>;
Confusion confusion_matrix(const std::vector<Example> &data,
                           const std::vector<MultiPrediction> &predictions, bool rest);
int sign(double value);
struct Fold {
    Ids train, test;
};
std::vector<Fold> folds(int count, int k);
struct Evaluation {
    int tp = 0, fp = 0, tn = 0, fn = 0;
    int correct() const { return tp + tn; }
};
Evaluation evaluate(const std::vector<Example> &data, const Field &values);
double auc(const std::vector<Example> &data, const Field &values);
std::string real(double value, int digits), ratio(int numerator, int denominator);
void save(const std::string &name, const Lines &lines);
template <typename... T> void line(Lines &out, const T &...values) {
    std::ostringstream text;
    (text << ... << values);
    out.push_back(text.str());
}
#endif
