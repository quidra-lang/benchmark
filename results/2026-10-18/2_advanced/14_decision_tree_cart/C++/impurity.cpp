#include "cart.hpp"

int majority(const Counts& counts) {
    return static_cast<int>(std::max_element(counts.begin(), counts.end()) - counts.begin());
}
Statistics statistics(const Rows& rows, int classes) {
    Counts counts(classes);
    for (const Row* row : rows) ++counts[row->label];
    int prediction = majority(counts);
    Integer squares = 0;
    for (Integer count : counts) squares += count * count;
    Integer size = static_cast<Integer>(rows.size());
    return {counts, size, squares, size - counts[prediction], prediction};
}
int compare(Fraction a, Fraction b) {
    Integer first = a.numerator * b.denominator;
    Integer second = b.numerator * a.denominator;
    return first < second ? -1 : first > second ? 1 : 0;
}
Fraction evaluationValue(const Statistics& left, const Statistics& right) {
    return {left.squares * right.size + right.squares * left.size, left.size * right.size};
}
bool improves(Fraction value, const Statistics& parent) { return value.numerator * parent.size > parent.squares * value.denominator; }
double impurityDecrease(const Statistics& parent, const Statistics& left, const Statistics& right) {
    double first = static_cast<double>(left.squares) / left.size;
    double second = static_cast<double>(right.squares) / right.size;
    double whole = static_cast<double>(parent.squares) / parent.size;
    return (first + second) - whole;
}
