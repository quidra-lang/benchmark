#include "regression.h"
Integer draw(Minstd *random) {
    random->state = 48271 * random->state % 2147483647;
    return random->state;
}
void shuffle(Minstd *random, Targets *values) {
    for (int size = values->count; size > 1; --size) {
        int index = (int)(draw(random) % size), value = values->values[size - 1];
        values->values[size - 1] = values->values[index];
        values->values[index] = value;
    }
}
Square cholesky(Square matrix) {
    Square lower = {.size = matrix.size};
    for (int j = 0; j < matrix.size; ++j)
        for (int i = j; i < matrix.size; ++i) {
            double total = 0;
            for (int k = 0; k < j; ++k)
                total += lower.values[i][k] * lower.values[j][k];
            double sigma = matrix.values[i][j] - total;
            lower.values[i][j] = i == j ? sqrt(sigma) : sigma / lower.values[j][j];
        }
    return lower;
}
Vector solve(Square lower, Vector right) {
    Vector result = {.count = lower.size}, middle = {.count = lower.size};
    for (int i = 0; i < lower.size; ++i) {
        double total = 0;
        for (int k = 0; k < i; ++k)
            total += lower.values[i][k] * middle.values[k];
        middle.values[i] = (right.values[i] - total) / lower.values[i][i];
    }
    for (int i = lower.size - 1; i >= 0; --i) {
        double total = 0;
        for (int k = i + 1; k < lower.size; ++k)
            total += lower.values[k][i] * result.values[k];
        result.values[i] = (middle.values[i] - total) / lower.values[i][i];
    }
    return result;
}
Trace newton(const Matrix *data, const Targets *targets, double lambda) {
    Vector weights = {.count = data->columns};
    Trace result = {0};
    result.points[result.count++] = (Checkpoint){0, weights};
    for (int iteration = 1; iteration <= 10; ++iteration) {
        Vector delta =
            solve(cholesky(hessian(weights, data, lambda)), gradient(weights, data, targets, lambda));
        for (int j = 0; j < weights.count; ++j)
            weights.values[j] -= delta.values[j];
        result.points[result.count++] = (Checkpoint){iteration, weights};
    }
    return result;
}
Trace gradient_descent(const Matrix *data, const Targets *targets, double lambda, double rate,
                       int iterations) {
    Vector weights = {.count = data->columns};
    Trace result = {0};
    result.points[result.count++] = (Checkpoint){0, weights};
    for (int iteration = 1; iteration <= iterations; ++iteration) {
        Vector g = gradient(weights, data, targets, lambda);
        for (int j = 0; j < weights.count; ++j)
            weights.values[j] -= rate * g.values[j];
        if (iteration % 100 == 0)
            result.points[result.count++] = (Checkpoint){iteration, weights};
    }
    return result;
}
Trace stochastic(const Matrix *data, const Targets *targets, double lambda, const Params *p) {
    Vector weights = {.count = data->columns};
    Trace result = {0};
    result.points[result.count++] = (Checkpoint){0, weights};
    Minstd random = {p->sgd_seed};
    Targets order = {.count = data->rows};
    for (int i = 0; i < data->rows; ++i)
        order.values[i] = i;
    for (int epoch = 1; epoch <= p->epochs; ++epoch) {
        shuffle(&random, &order);
        for (int first = 0; first < data->rows; first += p->batch) {
            Matrix batch = {.columns = data->columns};
            Targets labels_ = {0};
            int end = first + p->batch < data->rows ? first + p->batch : data->rows;
            for (int i = first; i < end; ++i) {
                int id = order.values[i];
                memcpy(batch.values[batch.rows++], data->values[id], (size_t)data->columns * sizeof(double));
                labels_.values[labels_.count++] = targets->values[id];
            }
            Vector g = gradient(weights, &batch, &labels_, lambda);
            for (int j = 0; j < weights.count; ++j)
                weights.values[j] -= p->sgd_rate * g.values[j];
        }
        result.points[result.count++] = (Checkpoint){epoch, weights};
    }
    return result;
}
