#include "statistics.h"

Fraction reduced(Integer numerator, Integer denominator) {
    Integer first = numerator, second = denominator;
    while (second) { Integer remainder = first % second; first = second; second = remainder; }
    return (Fraction){numerator / first, denominator / first};
}
Integer contrast(Sample first, Sample second) { return second.n * sample_sum(first) - first.n * sample_sum(second); }
int value_counts(Sample values, Integer *keys, Integer *counts) {
    if (!values.n) return 0;
    Integer ordered[values.n];
    memcpy(ordered, values.v, sizeof ordered);
    qsort(ordered, (size_t)values.n, sizeof(*ordered), compare_integer);
    int count = 0;
    for (int i = 0; i < values.n; ++i) {
        if (!count || ordered[i] != keys[count - 1]) { keys[count] = ordered[i]; counts[count++] = 0; }
        ++counts[count - 1];
    }
    return count;
}
void doubled_ranks(Sample values, Integer *result) {
    if (!values.n) return;
    Integer keys[values.n], counts[values.n], ranks[values.n], smaller = 0;
    int count = value_counts(values, keys, counts);
    for (int i = 0; i < count; ++i) { ranks[i] = 2 * smaller + counts[i] + 1; smaller += counts[i]; }
    for (int i = 0; i < values.n; ++i) {
        int j = 0;
        while (keys[j] != values.v[i]) ++j;
        result[i] = ranks[j];
    }
}
void divide(Sample values, const int *sizes, int count, Sample *result) {
    int start = 0;
    for (int i = 0; i < count; ++i) { result[i] = (Sample){values.v + start, sizes[i]}; start += sizes[i]; }
}
bool next_choice(int *choice, int size, int total) {
    int i = size - 1;
    while (i >= 0 && choice[i] == total - size + i) --i;
    if (i < 0) return false;
    ++choice[i];
    for (++i; i < size; ++i) choice[i] = choice[i - 1] + 1;
    return true;
}
Anova anova(const Sample *samples, int count) {
    Integer total = 0;
    Anova result = {0};
    for (int g = 0; g < count; ++g) { total += sample_sum(samples[g]); result.count += samples[g].n; }
    double grand = (double)total / (100 * (Integer)result.count);
    for (int g = 0; g < count; ++g) {
        Sample sample = samples[g];
        double center = mean(sample), difference = center - grand, within = 0;
        result.means[g] = center;
        result.between += sample.n * (difference * difference);
        for (int i = 0; i < sample.n; ++i) { double residual = (double)sample.v[i] / 100 - center; within += residual * residual; }
        result.within += within;
    }
    result.f = result.between / (count - 1) / (result.within / (result.count - count));
    return result;
}
double kruskal(const Sample *rank_groups, int count, double correction) {
    double total = 0;
    Integer n = 0;
    for (int g = 0; g < count; ++g) {
        Integer rank = sample_sum(rank_groups[g]);
        total += (double)(rank * rank) / (4 * (Integer)rank_groups[g].n);
        n += rank_groups[g].n;
    }
    return (12 * total / (n * (n + 1)) - 3 * (n + 1)) / correction;
}
