#include "segments.h"

double *distance_table(Points points) {
    double *table = allocate((size_t)points.n * points.n * sizeof(double));
    for (int i = 0; i < points.n; ++i) for (int j = i + 1; j < points.n; ++j) {
        double value = sqrt(squared_distance(points.v[i], points.v[j], points.dimensions));
        table[i * points.n + j] = value; table[j * points.n + i] = value;
    }
    return table;
}
void silhouettes(const double *table, const int *labels, const int *sizes, int count, int k, double *result) {
    for (int i = 0; i < count; ++i) {
        int own = labels[i];
        if (sizes[own] == 1) { result[i] = 0; continue; }
        double totals[10] = {0};
        for (int j = 0; j < count; ++j) if (i != j) totals[labels[j]] += table[i * count + j];
        double inner = totals[own] / (sizes[own] - 1), outer = INFINITY;
        for (int j = 0; j < k; ++j) if (j != own && totals[j] / sizes[j] < outer) outer = totals[j] / sizes[j];
        double largest = inner > outer ? inner : outer;
        result[i] = largest == 0 ? 0 : (outer - inner) / largest;
    }
}
double calinski_harabasz(Points points, const Point *centers, const int *sizes, int k, double within) {
    Point overall;
    mean_point(points, overall);
    double between = 0;
    for (int j = 0; j < k; ++j) between += sizes[j] * squared_distance(centers[j], overall, points.dimensions);
    return (between / (k - 1)) / (within / (points.n - k));
}
double davies_bouldin(Points points, const int *labels, const Point *centers, const int *sizes, int k) {
    double spreads[10] = {0}, total = 0;
    for (int i = 0; i < points.n; ++i) spreads[labels[i]] += sqrt(squared_distance(points.v[i], centers[labels[i]], points.dimensions));
    for (int j = 0; j < k; ++j) spreads[j] /= sizes[j];
    for (int a = 0; a < k; ++a) {
        double worst = 0;
        for (int e = 0; e < k; ++e) if (e != a) {
            double value = (spreads[a] + spreads[e]) / sqrt(squared_distance(centers[a], centers[e], points.dimensions));
            if (value > worst) worst = value;
        }
        total += worst;
    }
    return total / k;
}
double elbow(int k, int first_k, int last_k, double within, double first, double last) {
    double x = (double)(k - first_k) / (last_k - first_k), y = (within - last) / (first - last);
    return ((1 - x) - y) / sqrt(2);
}
double hartigan(double within, double next, int count, int k) { return (within / next - 1) * (count - k - 1); }
static Integer pairs(Integer count) { return count * (count - 1) / 2; }
double adjusted_rand(const int *first, const int *second, int count) {
    Integer sx = 0, sy = 0, shared = 0, z = pairs(count);
    for (int i = 0; i < count; ++i) {
        bool seen_x = false, seen_y = false, seen_pair = false;
        for (int j = 0; j < i; ++j) {
            if (first[j] == first[i]) seen_x = true;
            if (second[j] == second[i]) seen_y = true;
            if (first[j] == first[i] && second[j] == second[i]) seen_pair = true;
        }
        Integer nx = 0, ny = 0, both = 0;
        for (int j = i; j < count; ++j) {
            if (first[j] == first[i]) ++nx;
            if (second[j] == second[i]) ++ny;
            if (first[j] == first[i] && second[j] == second[i]) ++both;
        }
        if (!seen_x) sx += pairs(nx);
        if (!seen_y) sy += pairs(ny);
        if (!seen_pair) shared += pairs(both);
    }
    Integer numerator = 2 * (z * shared - sx * sy), denominator = z * (sx + sy) - 2 * sx * sy;
    return denominator ? (double)numerator / denominator : 1;
}
