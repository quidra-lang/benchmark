#include "clustering.h"
#include <math.h>

double correlation(const double *first, const double *second, int count) {
    double first_mean = sequential_sum(first, count) / count, second_mean = sequential_sum(second, count) / count;
    double cross = 0, first_squares = 0, second_squares = 0;
    for (int i = 0; i < count; ++i) {
        double a = first[i] - first_mean, b = second[i] - second_mean;
        cross += a * b;
        first_squares += a * a;
        second_squares += b * b;
    }
    return cross / sqrt(first_squares * second_squares);
}
Fraction fraction(Integer numerator, Integer denominator) {
    if (denominator < 0) { numerator = -numerator; denominator = -denominator; }
    Integer a = numerator < 0 ? -numerator : numerator, b = denominator;
    while (b) { Integer remainder = a % b; a = b; b = remainder; }
    return (Fraction){numerator / a, denominator / a};
}
double fraction_value(Fraction value) { return (double)value.numerator / (double)value.denominator; }
bool fraction_greater(Fraction first, Fraction second) { return first.numerator * second.denominator > second.numerator * first.denominator; }
static Integer pair_count(Integer count) { return count * (count - 1) / 2; }
Fraction adjusted_rand(const int *first, const int *second, int count, int first_groups, int second_groups) {
    Integer table[MAX_OBSERVATIONS][MAX_OBSERVATIONS] = {{0}};
    Integer columns[MAX_OBSERVATIONS] = {0}, same = 0, row_pairs = 0, column_pairs = 0;
    for (int i = 0; i < count; ++i) ++table[first[i] - 1][second[i] - 1];
    for (int row = 0; row < first_groups; ++row) {
        Integer total = 0;
        for (int column = 0; column < second_groups; ++column) {
            total += table[row][column];
            same += pair_count(table[row][column]);
            columns[column] += table[row][column];
        }
        row_pairs += pair_count(total);
    }
    for (int column = 0; column < second_groups; ++column) column_pairs += pair_count(columns[column]);
    Integer pairs = pair_count(count), numerator = 2 * (pairs * same - row_pairs * column_pairs);
    Integer denominator = pairs * (row_pairs + column_pairs) - 2 * row_pairs * column_pairs;
    return denominator ? fraction(numerator, denominator) : fraction(1, 1);
}
void silhouette_values(const int *partition, int count, int groups, const Matrix delta, double *values) {
    int sizes[MAX_OBSERVATIONS + 1] = {0};
    for (int i = 0; i < count; ++i) ++sizes[partition[i]];
    for (int i = 0; i < count; ++i) {
        int own = partition[i];
        values[i] = 0;
        if (sizes[own] == 1) continue;
        double sums[MAX_OBSERVATIONS + 1] = {0};
        for (int j = 0; j < count; ++j) if (j != i) sums[partition[j]] += delta[i][j];
        double inner = sums[own] / (sizes[own] - 1), outer = 0;
        bool first = true;
        for (int group = 1; group <= groups; ++group) if (group != own) {
            double mean = sums[group] / sizes[group];
            if (first || mean < outer) { first = false; outer = mean; }
        }
        values[i] = (outer - inner) / fmax(inner, outer);
    }
}
