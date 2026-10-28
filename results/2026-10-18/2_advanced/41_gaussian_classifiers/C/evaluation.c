#include "gaussian.h"
Fraction make_fraction(int64_t a, int64_t b) {
    if (b < 0) {
        a = -a;
        b = -b;
    }
    int64_t x = a < 0 ? -a : a, y = b;
    while (y) {
        int64_t remainder = x % y;
        x = y;
        y = remainder;
    }
    return (Fraction){a / x, b / x};
}
Fraction fraction_add(Fraction a, Fraction b) {
    return make_fraction(a.numerator * b.denominator + b.numerator * a.denominator,
                         a.denominator * b.denominator);
}
Fraction fraction_divide(Fraction value, int64_t divisor) {
    return make_fraction(value.numerator, value.denominator * divisor);
}
Measures evaluate(const Rows *rows, const int *prediction, int classes) {
    Measures out = {.total = rows->count, .classes = classes, .balanced = {0, 1}};
    for (int i = 0; i < rows->count; ++i)
        ++out.confusion[rows->data[i].label][prediction[i]];
    for (int k = 0; k < classes; ++k) {
        for (int j = 0; j < classes; ++j) {
            out.support[k] += out.confusion[k][j];
            out.predicted[k] += out.confusion[j][k];
        }
        out.correct += out.confusion[k][k];
        out.recall[k] = make_fraction(out.confusion[k][k], out.support[k]);
        if (out.predicted[k])
            out.precision[k] = make_fraction(out.confusion[k][k], out.predicted[k]);
        out.f1[k] = make_fraction(2 * out.confusion[k][k], out.support[k] + out.predicted[k]);
        out.balanced = fraction_add(out.balanced, out.recall[k]);
        out.macro_f1 += (double)(2 * out.confusion[k][k]) / (out.support[k] + out.predicted[k]);
    }
    out.accuracy = make_fraction(out.correct, out.total);
    out.balanced = fraction_divide(out.balanced, classes);
    out.macro_f1 /= classes;
    int64_t expected = 0;
    for (int k = 0; k < classes; ++k)
        expected += out.support[k] * out.predicted[k];
    out.kappa = make_fraction(out.total * out.correct - expected, out.total * out.total - expected);
    return out;
}
McNemar mcnemar(const Rows *rows, const int *a, const int *b) {
    McNemar out = {0};
    for (int i = 0; i < rows->count; ++i) {
        bool first = a[i] == rows->data[i].label, second = b[i] == rows->data[i].label;
        out.b01 += first && !second;
        out.b10 += !first && second;
    }
    if (out.b01 != out.b10) {
        int difference = abs(out.b01 - out.b10) - 1;
        out.chi2 = (double)(difference * difference) / (out.b01 + out.b10);
    }
    return out;
}
int64_t draw(Generator *generator) {
    generator->state = (48271 * generator->state) % 2147483647;
    return generator->state;
}
