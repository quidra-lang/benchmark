#include "gaussian.hpp"
Fraction::Fraction(std::int64_t a, std::int64_t b) {
    if (b < 0) {
        a = -a;
        b = -b;
    }
    const std::int64_t divisor = std::gcd(a, b);
    numerator = a / divisor;
    denominator = b / divisor;
}
Fraction Fraction::add(const Fraction &other) const {
    return Fraction(numerator * other.denominator + other.numerator * denominator,
                    denominator * other.denominator);
}
Fraction Fraction::divide(std::int64_t value) const {
    return Fraction(numerator, denominator * value);
}
Measures evaluate(const Rows &rows, const std::vector<int> &prediction, int classes) {
    Measures out;
    out.total = rows.size();
    out.classes = classes;
    for (std::size_t i = 0; i < rows.size(); ++i)
        ++out.confusion[rows[i].label][prediction[i]];
    for (int k = 0; k < classes; ++k) {
        for (int j = 0; j < classes; ++j) {
            out.support[k] += out.confusion[k][j];
            out.predicted[k] += out.confusion[j][k];
        }
        out.correct += out.confusion[k][k];
        out.recall[k] = Fraction(out.confusion[k][k], out.support[k]);
        if (out.predicted[k])
            out.precision[k] = Fraction(out.confusion[k][k], out.predicted[k]);
        out.f1[k] = Fraction(2 * out.confusion[k][k], out.support[k] + out.predicted[k]);
        out.balanced = out.balanced.add(out.recall[k]);
        out.macro_f1 += double(2 * out.confusion[k][k]) / (out.support[k] + out.predicted[k]);
    }
    out.accuracy = Fraction(out.correct, out.total);
    out.balanced = out.balanced.divide(classes);
    out.macro_f1 /= classes;
    std::int64_t expected = 0;
    for (int k = 0; k < classes; ++k)
        expected += out.support[k] * out.predicted[k];
    out.kappa = Fraction(out.total * out.correct - expected, out.total * out.total - expected);
    return out;
}
McNemar mcnemar(const Rows &rows, const std::vector<int> &a, const std::vector<int> &b) {
    McNemar out;
    for (std::size_t i = 0; i < rows.size(); ++i) {
        const bool first = a[i] == rows[i].label, second = b[i] == rows[i].label;
        out.b01 += first && !second;
        out.b10 += !first && second;
    }
    if (out.b01 != out.b10) {
        const int difference = std::abs(out.b01 - out.b10) - 1;
        out.chi2 = double(difference * difference) / (out.b01 + out.b10);
    }
    return out;
}
std::int64_t Generator::draw() {
    state = (48271 * state) % 2147483647;
    return state;
}
