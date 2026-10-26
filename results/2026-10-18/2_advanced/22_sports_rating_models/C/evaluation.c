#include "ratings.h"

double sigma(double value) { return 1 / (1 + exp(-value)); }
Link fit_link(const double *features, const Match *matches, int count, Integer iterations) {
    Link link = {0};
    for (Integer iteration = 0; iteration < iterations; ++iteration) {
        double g0 = 0, g1 = 0, h00 = 0, h01 = 0, h11 = 0;
        for (int i = 0; i < count; ++i) {
            double z = features[i], y = match_result(&matches[i]);
            double p = sigma(link.alpha + link.beta * z), w = p * (1 - p);
            g0 += y - p;
            g1 += (y - p) * z;
            h00 += w;
            h01 += w * z;
            h11 += w * z * z;
        }
        double determinant = h00 * h11 - h01 * h01;
        link.alpha += (h11 * g0 - h01 * g1) / determinant;
        link.beta += (h00 * g1 - h01 * g0) / determinant;
    }
    return link;
}
double log_loss(double probability, int y2) {
    if (y2 == 2) return -log(probability);
    if (y2 == 0) return -log(1 - probability);
    return -(log(probability) / 2 + log(1 - probability) / 2);
}
double brier_score(double probability, int y2) {
    double difference = probability - y2 / 2.0;
    return difference * difference;
}
int correctness(double probability, int y2) {
    if (y2 == 1) return 1;
    return (probability > 0.5 && y2 == 2) || (probability < 0.5 && y2 == 0) ? 2 : 0;
}
int comparison_compare(Comparison first, Comparison second) {
    if (first.exact) return fraction_compare(first.fraction, second.fraction);
    return (first.real > second.real) - (first.real < second.real);
}
Fraction kendall_tau(const Comparison *first, const Comparison *second, int count) {
    Integer balance = 0;
    for (int i = 0; i < count; ++i) for (int j = i + 1; j < count; ++j) balance += comparison_compare(first[i], first[j]) * comparison_compare(second[i], second[j]);
    return fraction(balance, count * (count - 1) / 2);
}
static void average_ranks(const Comparison *values, int count, int *doubled) {
    for (int i = 0; i < count; ++i) {
        int greater = 0, equal = 0;
        for (int j = 0; j < count; ++j) {
            int order = comparison_compare(values[j], values[i]);
            greater += order > 0;
            equal += order == 0;
        }
        doubled[i] = 2 * greater + equal + 1;
    }
}
Fraction spearman_rho(const Comparison *first, const Comparison *second, int count) {
    int first_ranks[30], second_ranks[30];
    average_ranks(first, count, first_ranks);
    average_ranks(second, count, second_ranks);
    Integer squares = 0, denominator = (Integer)count * (count * count - 1) * 4;
    for (int i = 0; i < count; ++i) {
        Integer difference = first_ranks[i] - second_ranks[i];
        squares += difference * difference;
    }
    return fraction(denominator - 6 * squares, denominator);
}
