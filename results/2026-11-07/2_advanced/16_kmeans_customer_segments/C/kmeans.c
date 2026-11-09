#include "segments.h"

double squared_distance(const double *first, const double *second, int dimensions) {
    double total = 0;
    for (int f = 0; f < dimensions; ++f) { double difference = first[f] - second[f]; total += difference * difference; }
    return total;
}
void mean_point(Points points, double *result) {
    for (int f = 0; f < points.dimensions; ++f) result[f] = 0;
    for (int i = 0; i < points.n; ++i) for (int f = 0; f < points.dimensions; ++f) result[f] += points.v[i][f];
    for (int f = 0; f < points.dimensions; ++f) result[f] /= points.n;
}
void assign_points(Points points, const Point *centers, int k, int *labels, double *errors) {
    for (int i = 0; i < points.n; ++i) {
        int best = 0;
        double distance = squared_distance(points.v[i], centers[0], points.dimensions);
        for (int j = 1; j < k; ++j) {
            double trial = squared_distance(points.v[i], centers[j], points.dimensions);
            if (trial < distance) { best = j; distance = trial; }
        }
        labels[i] = best; errors[i] = distance;
    }
}
void cluster_sizes(const int *labels, int count, int k, int *sizes) {
    memset(sizes, 0, (size_t)k * sizeof(int));
    for (int i = 0; i < count; ++i) ++sizes[labels[i]];
}
void cluster_center(Points points, const int *labels, int label, double *center) {
    int count = 0;
    for (int f = 0; f < points.dimensions; ++f) center[f] = 0;
    for (int i = 0; i < points.n; ++i) if (labels[i] == label) {
        ++count;
        for (int f = 0; f < points.dimensions; ++f) center[f] += points.v[i][f];
    }
    for (int f = 0; f < points.dimensions; ++f) center[f] /= count;
}
void cluster_centers(Points points, const int *labels, int k, Point *centers) {
    for (int j = 0; j < k; ++j) cluster_center(points, labels, j, centers[j]);
}
int refill(int *labels, double *errors, int count, int k) {
    int sizes[10], reseeds = 0;
    cluster_sizes(labels, count, k, sizes);
    for (int j = 0; j < k; ++j) {
        if (sizes[j]) continue;
        int chosen = -1;
        for (int i = 0; i < count; ++i) if (sizes[labels[i]] >= 2 && (chosen < 0 || errors[i] > errors[chosen])) chosen = i;
        --sizes[labels[chosen]];
        ++sizes[j]; labels[chosen] = j; errors[chosen] = 0; ++reseeds;
    }
    return reseeds;
}
double sse(Points points, const int *labels, const Point *centers) {
    double total = 0;
    for (int i = 0; i < points.n; ++i) total += squared_distance(points.v[i], centers[labels[i]], points.dimensions);
    return total;
}
Lloyd lloyd(Points points, const Point *initial, int k, int limit) {
    Lloyd result = {0};
    double errors[400];
    assign_points(points, initial, k, result.labels, errors);
    while (result.iterations < limit) {
        result.reseeds += refill(result.labels, errors, points.n, k);
        cluster_centers(points, result.labels, k, result.centers);
        ++result.iterations;
        int updated[400];
        assign_points(points, result.centers, k, updated, errors);
        result.converged = !memcmp(result.labels, updated, (size_t)points.n * sizeof(int));
        memcpy(result.labels, updated, (size_t)points.n * sizeof(int));
        if (result.converged) break;
    }
    result.reseeds += refill(result.labels, errors, points.n, k);
    cluster_centers(points, result.labels, k, result.centers);
    result.sse = sse(points, result.labels, result.centers);
    return result;
}
