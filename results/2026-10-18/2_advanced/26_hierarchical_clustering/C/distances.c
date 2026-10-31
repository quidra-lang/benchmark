#include "clustering.h"
#include <math.h>
#include <string.h>

double sequential_sum(const double *values, int count) {
    double total = 0;
    for (int i = 0; i < count; ++i) total += values[i];
    return total;
}
double squared_distance(const double *first, const double *second, int features) {
    double total = 0;
    for (int feature = 0; feature < features; ++feature) {
        double difference = first[feature] - second[feature];
        total += difference * difference;
    }
    return total;
}
void feature_statistics(const Dataset *data, double *means, double *deviations) {
    for (int feature = 0; feature < data->features; ++feature) {
        double total = 0, squares = 0;
        for (int i = 0; i < data->count; ++i) total += data->raw[i][feature];
        means[feature] = total / data->count;
        for (int i = 0; i < data->count; ++i) {
            double difference = data->raw[i][feature] - means[feature];
            squares += difference * difference;
        }
        deviations[feature] = sqrt(squares / (data->count - 1));
    }
}
void analysis_vectors(const Dataset *data, const double *means, const double *deviations, Vectors vectors) {
    bool standardized = !strcmp(data->settings.standardize, "yes");
    for (int i = 0; i < data->count; ++i) for (int feature = 0; feature < data->features; ++feature) {
        vectors[i][feature] = standardized ? (data->raw[i][feature] - means[feature]) / deviations[feature] : data->raw[i][feature];
    }
}
double vector_distance(const double *first, const double *second, int features, const char *kind) {
    if (!strcmp(kind, "euclidean")) return sqrt(squared_distance(first, second, features));
    if (!strcmp(kind, "manhattan")) {
        double total = 0;
        for (int feature = 0; feature < features; ++feature) total += fabs(first[feature] - second[feature]);
        return total;
    }
    double first_mean = sequential_sum(first, features) / features, second_mean = sequential_sum(second, features) / features;
    double cross = 0, first_squares = 0, second_squares = 0;
    for (int feature = 0; feature < features; ++feature) {
        double a = first[feature] - first_mean, b = second[feature] - second_mean;
        cross += a * b;
        first_squares += a * a;
        second_squares += b * b;
    }
    return 1 - cross / sqrt(first_squares * second_squares);
}
void distance_matrix(const Vectors vectors, int count, int features, const char *kind, Matrix matrix) {
    for (int i = 0; i < count; ++i) {
        matrix[i][i] = 0;
        for (int j = i + 1; j < count; ++j) matrix[i][j] = matrix[j][i] = vector_distance(vectors[i], vectors[j], features, kind);
    }
}
