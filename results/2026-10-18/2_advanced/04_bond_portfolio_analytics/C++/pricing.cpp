#include "bond.hpp"

double bisect(const std::function<double(double)>& function, double low, double high, double target) {
    for (int i = 0; i < 80; ++i) { double middle = (low + high) / 2; if (function(middle) > target) low = middle; else high = middle; } return (low + high) / 2;
}
std::vector<double> YieldPricer::values(double rate) const {
    double first = 1 + fraction * rate / frequency, growth = 1 + rate / frequency, factor = 1;
    std::vector<double> result; for (double cash : flows) { result.push_back(cash / (first * factor)); factor *= growth; } return result;
}
double YieldPricer::dirty(double rate) const { double total = 0; for (double value : values(rate)) total += value; return total * 100 / outstanding; }
double YieldPricer::solve(double target) const { return bisect([this](double rate) { return dirty(rate); }, 0, 1, target); }
Risk YieldPricer::risk(double rate) const {
    double growth = 1 + rate / frequency, total = 0, weighted = 0, curvature = 0; std::vector<double> present = values(rate);
    for (std::size_t i = 0; i < present.size(); ++i) { double years = (i + fraction) / frequency; total += present[i]; weighted += years * present[i]; curvature += years * (years + 1.0 / frequency) * present[i]; }
    double macaulay = weighted / total;
    return {macaulay, macaulay / growth, curvature / (total * growth * growth), (dirty(rate - 0.0001) - dirty(rate + 0.0001)) / 2};
}
