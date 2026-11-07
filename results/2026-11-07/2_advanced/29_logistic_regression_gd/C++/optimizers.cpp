#include "regression.hpp"
Integer Minstd::draw() {
    state = 48271 * state % 2147483647;
    return state;
}
void Minstd::shuffle(std::vector<int> &values) {
    for (std::size_t size = values.size(); size > 1; --size) {
        const int index = int(draw() % Integer(size));
        std::swap(values[size - 1], values[index]);
    }
}
Matrix cholesky(const Matrix &matrix) {
    const std::size_t size = matrix.size();
    Matrix lower(size, Vector(size));
    for (std::size_t j = 0; j < size; ++j)
        for (std::size_t i = j; i < size; ++i) {
            double total = 0;
            for (std::size_t k = 0; k < j; ++k)
                total += lower[i][k] * lower[j][k];
            const double sigma = matrix[i][j] - total;
            lower[i][j] = i == j ? std::sqrt(sigma) : sigma / lower[j][j];
        }
    return lower;
}
Vector solve(const Matrix &lower, const Vector &right) {
    const int size = int(lower.size());
    Vector middle(size), result(size);
    for (int i = 0; i < size; ++i) {
        double total = 0;
        for (int k = 0; k < i; ++k)
            total += lower[i][k] * middle[k];
        middle[i] = (right[i] - total) / lower[i][i];
    }
    for (int i = size - 1; i >= 0; --i) {
        double total = 0;
        for (int k = i + 1; k < size; ++k)
            total += lower[k][i] * result[k];
        result[i] = (middle[i] - total) / lower[i][i];
    }
    return result;
}
std::vector<Checkpoint> newton(const Matrix &data, const std::vector<int> &targets, double lambda) {
    Vector weights(data[0].size());
    std::vector<Checkpoint> result{{0, weights}};
    for (int iteration = 1; iteration <= 10; ++iteration) {
        const Vector delta =
            solve(cholesky(hessian(weights, data, lambda)), gradient(weights, data, targets, lambda));
        for (std::size_t j = 0; j < weights.size(); ++j)
            weights[j] -= delta[j];
        result.push_back({iteration, weights});
    }
    return result;
}
std::vector<Checkpoint> gradient_descent(const Matrix &data, const std::vector<int> &targets, double lambda,
                                         double rate, int iterations) {
    Vector weights(data[0].size());
    std::vector<Checkpoint> result{{0, weights}};
    for (int iteration = 1; iteration <= iterations; ++iteration) {
        const Vector g = gradient(weights, data, targets, lambda);
        for (std::size_t j = 0; j < weights.size(); ++j)
            weights[j] -= rate * g[j];
        if (iteration % 100 == 0)
            result.push_back({iteration, weights});
    }
    return result;
}
std::vector<Checkpoint> stochastic(const Matrix &data, const std::vector<int> &targets, double lambda,
                                   const Params &p) {
    Vector weights(data[0].size());
    std::vector<Checkpoint> result{{0, weights}};
    Minstd random(p.sgd_seed);
    std::vector<int> order(data.size());
    std::iota(order.begin(), order.end(), 0);
    for (int epoch = 1; epoch <= p.epochs; ++epoch) {
        random.shuffle(order);
        for (int first = 0; first < int(data.size()); first += p.batch) {
            Matrix batch;
            std::vector<int> labels_;
            for (int i = first; i < std::min(first + p.batch, int(data.size())); ++i) {
                batch.push_back(data[order[i]]);
                labels_.push_back(targets[order[i]]);
            }
            const Vector g = gradient(weights, batch, labels_, lambda);
            for (std::size_t j = 0; j < weights.size(); ++j)
                weights[j] -= p.sgd_rate * g[j];
        }
        result.push_back({epoch, weights});
    }
    return result;
}
