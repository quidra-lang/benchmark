#pragma once
#include <array>
#include <cstdint>
#include <map>
#include <string>
#include <vector>

using Integer = std::int64_t;
using Integers = std::vector<Integer>;
using Numbers = std::vector<int>;
using Lines = std::vector<std::string>;
struct Constants { double a2, a3, b3, b4, d3, d4, d2, c4; };
Constants controlConstants(int size);
struct Settings {
    std::string characteristic;
    int lsl, usl, target, size, phase1, passes, span, gap, bin, window, step;
    double cusumK, cusumH, weight, ewmaL, ciZ;
    std::array<Numbers, 7> rules;
};
struct Lot { int number; Integer inspected, defectives, defects; };
struct Dataset { Settings settings; Integers values; std::vector<Lot> lots; };
Dataset readDataset();
struct Subgroup {
    int number;
    Integers values;
    Integer total, squares, range;
    double mean, sd;
};
struct Limits {
    double lcl = 0, cl = 0, ucl = 0;
    bool outside(double value) const { return value > ucl || value < lcl; }
};
using LimitPair = std::array<Limits, 2>;
std::vector<Subgroup> subgroupStatistics(const Integers& values, int size);
LimitPair variableLimits(int family, const Numbers& numbers, const Integers& values,
                         const std::vector<Subgroup>& groups, int size, Constants constants);
struct Zones {
    double lcl, cl, ucl, u1, u2, l1, l2;
    explicit Zones(Limits limits);
    std::string name(double value) const;
};
struct Series { Numbers numbers; std::vector<double> values; };
struct Signal { int chart, rule, start, end; double value; std::string direction; };
std::vector<Signal> checkRules(int chart, const Series& series, Limits limits, const Numbers& rules);
struct Center { int chart; double value, fraction; };
struct LotPoint { double value, lcl, ucl, z; std::string status; };
Center attributeCenter(int chart, const std::vector<Lot>& lots, const Numbers& numbers);
LotPoint attributePoint(const Lot& lot, Center center);
struct HistogramBin { int lower, upper, frequency, length; Lines marks; };
struct Capability {
    int count, below, above;
    double mean, within, sbar, overall, cp, cpu, cpl, cpk, pp, ppu, ppl, ppk, cpm, ppm;
    std::array<double, 2> cpkInterval, ppkInterval;
    std::string verdict;
    std::vector<HistogramBin> bins;
};
Capability capability(const std::vector<Subgroup>& groups, const Settings& settings, Constants constants);
std::string limitsBand(Limits limits, double value, bool signalled);
std::string cusumBand(double upper, double lower, double threshold, bool upperSignal, bool lowerSignal);
std::string widthBand(double scale, double width, double value, double center, bool signalled);
std::string standardBand(double z, bool ok);
