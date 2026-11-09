#include "cart.h"

int majority(const Integer *counts, int classes) {
    int best = 0;
    for (int i = 1; i < classes; ++i) if (counts[i] > counts[best]) best = i;
    return best;
}
Statistics statistics(Rows rows, int classes) {
    Statistics result = { .size = rows.count };
    for (int i = 0; i < rows.count; ++i) ++result.counts[rows.items[i]->label];
    for (int i = 0; i < classes; ++i) result.squares += result.counts[i] * result.counts[i];
    result.prediction = majority(result.counts, classes);
    result.errors = result.size - result.counts[result.prediction];
    return result;
}
int compare(Fraction first, Fraction second) {
    Integer a = first.numerator * second.denominator;
    Integer b = second.numerator * first.denominator;
    return a < b ? -1 : a > b ? 1 : 0;
}
Fraction evaluation_value(Statistics left, Statistics right) {
    return (Fraction){left.squares * right.size + right.squares * left.size, left.size * right.size};
}
bool improves(Fraction value, Statistics parent) { return value.numerator * parent.size > parent.squares * value.denominator; }
double impurity_decrease(Statistics parent, Statistics left, Statistics right) {
    double first = (double)left.squares / left.size;
    double second = (double)right.squares / right.size;
    double whole = (double)parent.squares / parent.size;
    return (first + second) - whole;
}
