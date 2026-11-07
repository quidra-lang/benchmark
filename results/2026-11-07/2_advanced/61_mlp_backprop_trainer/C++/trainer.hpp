#ifndef TRAINER_HPP
#define TRAINER_HPP
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <limits>
#include <numeric>
#include <sstream>
#include <string>
#include <tuple>
#include <vector>
using Field = std::vector<double>;
using Ids = std::vector<int>;
using Lines = std::vector<std::string>;
using Counts = std::vector<std::vector<int>>;
struct Image {
    std::string id, pixels;
    int label;
    Field input;
};
struct Layer {
    int inputs, units;
    std::string function;
    int weights, biases;
    bool output;
};
struct Network {
    std::string name;
    int inputs = 0, classes = 0, weight_count = 0;
    std::vector<Layer> layers;
    Field initial;
    std::vector<bool> is_weight;
};
void add_layer(Network &network, int units, const std::string &function, bool output);
struct Run {
    std::string name, optimizer;
    int network;
    double eta, decay, mu = 0, beta1 = 0, beta2 = 0, epsilon = 0;
};
struct Params {
    std::int64_t seed = 0;
    int batch = 0, epochs = 0, patience = 0, lr_step = 0, stride = 0, bins = 0;
    double gamma = 0;
    Ids prune, noise;
    std::vector<Run> runs;
};
struct Input {
    int width = 0, height = 0, classes = 0;
    std::vector<Image> train, test;
    std::vector<Network> networks;
    Params params;
};
Input load();
struct Random {
    std::int64_t state;
    std::int64_t draw();
    void shuffle(Ids &order);
};
double activation(const std::string &function, double z),
    derivative(const std::string &function, double z, double a);
Field preactivation(const Field &weights, const Field &input, const Layer &layer);
Field propagate(const Field &weights, const Layer &next, const Field &delta);
struct Output {
    Field scores, delta;
    double loss;
};
Output output_layer(const std::string &function, const Field &z, int label);
struct Forward {
    std::vector<Field> z, activations;
    Field scores, delta;
    double loss;
};
Forward forward(const Network &network, const Field &weights, const Image &image);
struct Backward {
    Field parameters, input;
};
Backward backward(const Network &network, const Field &weights, const Forward &record);
struct Optimizer {
    Field first, second;
    double pi1 = 1, pi2 = 1;
    explicit Optimizer(int count) : first(count), second(count) {}
    void update(Field &weights, const Field &gradient, const Run &run, double eta);
};
double learning_rate(const Run &run, const Params &params, int epoch);
std::string real(double value, int digits), ratio(std::int64_t numerator, std::int64_t denominator);
int prediction(const Field &scores), second_class(const Field &scores, int first);
Counts confusion(const std::vector<Image> &images, const Ids &predictions, int classes);
struct ClassStats {
    int support, predicted, true_positive;
};
ClassStats class_stats(const Counts &matrix, int label);
Lines level_maps(const std::vector<Ids> &levels, int width, int height);
Lines image_lines(const Image &image, int width, int height);
void save(const std::string &name, const Lines &lines);
template <typename... T> void line(Lines &lines, const T &...values) {
    std::ostringstream out;
    (out << ... << values);
    lines.push_back(out.str());
}
#endif
