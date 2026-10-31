#include "statistics.h"

int compare_integer(const void *first, const void *second) {
    Integer a = *(const Integer *)first, b = *(const Integer *)second;
    return (a > b) - (a < b);
}
int compare_real(const void *first, const void *second) {
    double a = *(const double *)first, b = *(const double *)second;
    return (a > b) - (a < b);
}
Integer sample_sum(Sample values) {
    Integer result = 0;
    for (int i = 0; i < values.n; ++i) result += values.v[i];
    return result;
}
double sequential_sum(Values values) {
    double result = 0;
    for (int i = 0; i < values.n; ++i) result += values.v[i];
    return result;
}
double mean(Sample values) { return (double)sample_sum(values) / (100 * (Integer)values.n); }
Integer doubled_median(Sample values) {
    Integer ordered[values.n];
    memcpy(ordered, values.v, sizeof ordered);
    qsort(ordered, (size_t)values.n, sizeof(*ordered), compare_integer);
    return ordered[(values.n - 1) / 2] + ordered[values.n / 2];
}
double median(Sample values) { return (double)doubled_median(values) / 200; }
double trimmed_mean(Sample values) {
    Integer ordered[values.n], total = 0;
    memcpy(ordered, values.v, sizeof ordered);
    qsort(ordered, (size_t)values.n, sizeof(*ordered), compare_integer);
    int trim = values.n / 10;
    for (int i = trim; i < values.n - trim; ++i) total += ordered[i];
    return (double)total / (100 * (Integer)(values.n - 2 * trim));
}
Moments moments(Sample values) {
    double center = mean(values), second = 0, third = 0, fourth = 0;
    for (int i = 0; i < values.n; ++i) {
        double difference = (double)values.v[i] / 100 - center;
        second += difference * difference;
        third += difference * difference * difference;
        fourth += difference * difference * difference * difference;
    }
    return (Moments){sqrt(second / (values.n - 1)), second / values.n, third / values.n, fourth / values.n};
}
double sd(Sample values) { return moments(values).sd; }
double mad(Sample values) {
    Integer center = doubled_median(values), deviations[values.n];
    for (int i = 0; i < values.n; ++i) deviations[i] = llabs(2 * values.v[i] - center);
    return (double)doubled_median((Sample){deviations, values.n}) / 400;
}
Integer quantile_numerator(Sample values, int percent) {
    Integer ordered[values.n];
    memcpy(ordered, values.v, sizeof ordered);
    qsort(ordered, (size_t)values.n, sizeof(*ordered), compare_integer);
    int position = (values.n - 1) * percent, index = position / 100, fraction = position % 100;
    return 100 * ordered[index] + (fraction ? fraction * (ordered[index + 1] - ordered[index]) : 0);
}
void winsorized(Sample values, Integer *result) {
    Integer ordered[values.n];
    memcpy(ordered, values.v, sizeof ordered);
    qsort(ordered, (size_t)values.n, sizeof(*ordered), compare_integer);
    int trim = values.n / 10;
    Integer low = ordered[trim], high = ordered[values.n - trim - 1];
    for (int i = 0; i < values.n; ++i) result[i] = values.v[i] < low ? low : values.v[i] > high ? high : values.v[i];
}
double mean_difference(Sample first, Sample second) { return (double)contrast(first, second) / (100 * (Integer)first.n * second.n); }
double median_ratio(Sample first, Sample second) { return (double)doubled_median(first) / doubled_median(second); }
double hodges_lehmann(Sample first, Sample second) {
    Integer differences[first.n * second.n];
    int count = 0;
    for (int i = 0; i < first.n; ++i) for (int j = 0; j < second.n; ++j) differences[count++] = first.v[i] - second.v[j];
    return (double)doubled_median((Sample){differences, count}) / 200;
}
double pooled_sd(Sample first, Sample second) {
    double x = sd(first), y = sd(second);
    return sqrt(((first.n - 1) * x * x + (second.n - 1) * y * y) / (first.n + second.n - 2));
}
double cohen_d(Sample first, Sample second) { return mean_difference(first, second) / pooled_sd(first, second); }
double correlation(Sample first, Sample second) {
    double x = mean(first), y = mean(second), cross = 0, squares_x = 0, squares_y = 0;
    for (int i = 0; i < first.n; ++i) {
        double e = (double)first.v[i] / 100 - x, f = (double)second.v[i] / 100 - y;
        cross += e * f;
        squares_x += e * e;
        squares_y += f * f;
    }
    return cross / sqrt(squares_x * squares_y);
}
void group_statistics(Sample sample, double result[4]) {
    result[0] = mean(sample);
    result[1] = median(sample);
    result[2] = trimmed_mean(sample);
    result[3] = sd(sample);
}
void pair_statistics(Sample first, Sample second, double result[4]) {
    result[0] = mean_difference(first, second);
    result[1] = median_ratio(first, second);
    result[2] = hodges_lehmann(first, second);
    result[3] = cohen_d(first, second);
}
void resample_indices(Minstd *generator, int size, int *result) {
    for (int i = 0; i < size; ++i) result[i] = below(generator, size);
}
int *ordinary_indices(Minstd *generator, int size, int count) {
    int *result = allocate((size_t)size * count * sizeof(*result));
    for (int r = 0; r < count; ++r) resample_indices(generator, size, result + r * size);
    return result;
}
int *balanced_indices(Minstd *generator, int size, int count) {
    int *result = allocate((size_t)size * count * sizeof(*result));
    for (int r = 0; r < count; ++r) for (int i = 0; i < size; ++i) result[r * size + i] = i;
    shuffle(generator, result, size * count);
    return result;
}
Sample without(Sample values, int index, Integer *storage) {
    int count = 0;
    for (int i = 0; i < values.n; ++i) if (i != index) storage[count++] = values.v[i];
    return (Sample){storage, count};
}
Sample chosen(Sample values, const int *indices, int count, Integer *storage) {
    for (int i = 0; i < count; ++i) storage[i] = values.v[indices[i]];
    return (Sample){storage, count};
}
Spread mean_and_se(Values values) {
    double average = sequential_sum(values) / values.n, squares = 0;
    for (int i = 0; i < values.n; ++i) { double difference = values.v[i] - average; squares += difference * difference; }
    return (Spread){average, sqrt(squares / (values.n - 1))};
}
double phi(double value) {
    if (value < 0) return 1 - phi(-value);
    double eta = 1 / (1 + 0.2316419 * value);
    double psi = eta * (0.319381530 + eta * (-0.356563782 + eta * (1.781477937 + eta * (-1.821255978 + eta * 1.330274429))));
    return 1 - 0.3989422804014327 * exp(-(value * value) / 2) * psi;
}
double phi_inverse(double probability) {
    if (probability > 0.5) return -phi_inverse(1 - probability);
    double eta = sqrt(-2 * log(probability));
    double numerator = 2.515517 + eta * (0.802853 + eta * 0.010328);
    double denominator = 1 + eta * (1.432788 + eta * (0.189269 + eta * 0.001308));
    return -(eta - numerator / denominator);
}
