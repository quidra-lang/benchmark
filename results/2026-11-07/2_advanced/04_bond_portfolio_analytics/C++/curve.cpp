#include "bond.hpp"

double ZeroCurve::zero(int day) const {
    if (day <= days.front()) return rates.front(); if (day >= days.back()) return rates.back();
    std::size_t i = 1; while (days[i] < day) ++i; if (days[i] == day) return rates[i];
    return rates[i - 1] + (rates[i] - rates[i - 1]) * (static_cast<double>(day - days[i - 1]) / (days[i] - days[i - 1]));
}
double ZeroCurve::discount(int day, double spread) const {
    double rate = zero(day) + spread, growth = 1; for (int i = 0; i < day / 365; ++i) growth *= 1 + rate;
    return 1 / (growth * (1 + rate * (day % 365) / 365));
}
double ZeroCurve::presentValue(const std::vector<Flow>& flows, double spread) const { double total = 0; for (const Flow& flow : flows) total += flow.amount * discount(flow.days, spread); return total; }
double ZeroCurve::forward(int start, int end) const { return (discount(start) / discount(end) - 1) * 365 / (end - start); }
ZeroCurve ZeroCurve::shifted(const std::vector<double>& deltas) const { ZeroCurve result = *this; for (std::size_t i = 0; i < rates.size(); ++i) result.rates[i] += deltas[i]; return result; }
ZeroCurve bootstrap(int settlement, const std::vector<Pillar>& pillars) {
    ZeroCurve curve;
    for (const Pillar& pillar : pillars) {
        std::vector<int> dates = couponSchedule(settlement, pillar.maturity, pillar.frequency, false, false); std::vector<Flow> flows;
        for (std::size_t i = 1; i < dates.size(); ++i) { Fraction f = yearFraction("30/360", dates[i - 1], dates[i]); double amount = pillar.coupon * static_cast<double>(f.numerator) / (10000 * f.denominator); if (i + 1 == dates.size()) amount += 1; flows.push_back({dates[i] - settlement, amount}); }
        curve.days.push_back(pillar.maturity - settlement);
        double rate = bisect([&](double trial) { ZeroCurve candidate = curve; candidate.rates.push_back(trial); return candidate.presentValue(flows); }, 0, 1, 1);
        curve.rates.push_back(rate);
    }
    return curve;
}
double zSpread(const ZeroCurve& curve, const std::vector<Flow>& flows, double target) { return bisect([&](double spread) { return curve.presentValue(flows, spread); }, -0.5, 0.5, target); }
