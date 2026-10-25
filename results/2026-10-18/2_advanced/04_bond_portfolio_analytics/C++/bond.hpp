#pragma once
#include <array>
#include <cstdint>
#include <functional>
#include <map>
#include <set>
#include <string>
#include <vector>

using Integer = std::int64_t;
using Lines = std::vector<std::string>;
bool leap(int year);
int monthLength(int year, int month);
int dayNumber(int year, int month, int day);
std::array<int, 3> civilDate(int day);
bool validDate(const std::string& text);
int parseDate(const std::string& text);
std::string formatDate(int day);
struct Calendar {
    std::set<int> holidays;
    bool business(int day) const;
    int move(int day, int count) const;
    int adjust(int day, const std::string& convention) const;
};
struct Fraction { Integer numerator, denominator; double value() const { return static_cast<double>(numerator) / denominator; } };
Fraction yearFraction(const std::string& convention, int start, int end);
std::vector<int> couponSchedule(int issue, int maturity, int frequency, bool eom, bool longStub);
double bisect(const std::function<double(double)>& function, double low, double high, double target);
struct Risk { double macaulay = 0, modified = 0, convexity = 0, dv01 = 0; };
struct YieldPricer {
    std::vector<double> flows;
    double fraction = 0;
    int frequency = 1;
    Integer outstanding = 1;
    std::vector<double> values(double rate) const;
    double dirty(double rate) const;
    double solve(double target) const;
    Risk risk(double rate) const;
};
struct Flow { int days; double amount; };
struct Pillar { int maturity, coupon, frequency; };
struct ZeroCurve {
    std::vector<int> days;
    std::vector<double> rates;
    double zero(int day) const;
    double discount(int day, double spread = 0) const;
    double presentValue(const std::vector<Flow>& flows, double spread = 0) const;
    double forward(int start, int end) const;
    ZeroCurve shifted(const std::vector<double>& deltas) const;
};
ZeroCurve bootstrap(int settlement, const std::vector<Pillar>& pillars);
double zSpread(const ZeroCurve& curve, const std::vector<Flow>& flows, double target);
struct Options {
    bool eom = false, longStub = false;
    int lag = -1, cap = -1, floor = -1;
    std::vector<std::pair<std::string, Integer>> sinks, calls;
};
struct Period {
    int number, start, end, payment;
    Fraction fraction;
    int rate;
    Integer opening, coupon, principal;
    Integer cash() const { return coupon + principal; }
};
struct Bond {
    std::string code, type;
    int issue, maturity, coupon, frequency;
    std::string daycount, bdc;
    Integer face;
    Options options;
    std::vector<int> schedule;
    std::map<int, Integer> sinks;
    std::vector<std::pair<int, Integer>> calls;
    std::vector<Period> periods;
};
