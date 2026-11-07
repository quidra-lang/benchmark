#include "spc.hpp"
#include <algorithm>
#include <cmath>
#include <numeric>

Capability capability(const std::vector<Subgroup>& groups, const Settings& s, Constants c) {
    Capability r{};
    Integers values;
    Integer total = 0, ranges = 0;
    double deviations = 0;
    for (const Subgroup& group : groups) {
        values.insert(values.end(),group.values.begin(),group.values.end());
        total += group.total; ranges += group.range; deviations += group.sd;
    }
    r.count = static_cast<int>(values.size());
    r.mean = static_cast<double>(total) / r.count;
    r.within = (static_cast<double>(ranges) / groups.size()) / c.d2;
    r.sbar = (deviations / groups.size()) / c.c4;
    double squares = 0;
    for (Integer value : values) squares += (value - r.mean) * (value - r.mean);
    r.overall = std::sqrt(squares / (r.count - 1));
    r.cp = (s.usl - s.lsl) / (6 * r.within); r.cpu = (s.usl - r.mean) / (3 * r.within);
    r.cpl = (r.mean - s.lsl) / (3 * r.within); r.cpk = std::min(r.cpu,r.cpl);
    r.pp = (s.usl - s.lsl) / (6 * r.overall); r.ppu = (s.usl - r.mean) / (3 * r.overall);
    r.ppl = (r.mean - s.lsl) / (3 * r.overall); r.ppk = std::min(r.ppu,r.ppl);
    double offset = r.mean - s.target;
    r.cpm = (s.usl - s.lsl) / (6 * std::sqrt(r.overall * r.overall + offset * offset));
    auto interval = [&](double index) {
        double delta = s.ciZ * std::sqrt(1.0 / (9 * r.count) + index * index / (2 * (r.count - 1)));
        return std::array<double, 2>{index - delta,index + delta};
    };
    r.cpkInterval = interval(r.cpk); r.ppkInterval = interval(r.ppk);
    for (Integer value : values) { r.below += value < s.lsl; r.above += value > s.usl; }
    r.ppm = static_cast<double>(1000000LL * (r.below + r.above)) / r.count;
    r.verdict = r.cpk >= 1.33 ? "capable" : r.cpk >= 1 ? "marginal" : "incapable";
    int low = s.bin * (std::min<Integer>(*std::min_element(values.begin(),values.end()),s.lsl) / s.bin);
    int high = s.bin * (std::max<Integer>(*std::max_element(values.begin(),values.end()),s.usl) / s.bin) + s.bin;
    Numbers frequencies((high - low) / s.bin);
    for (Integer value : values) ++frequencies[(value - low) / s.bin];
    int top = *std::max_element(frequencies.begin(),frequencies.end());
    for (int j = 0; j < static_cast<int>(frequencies.size()); ++j) {
        int lower = low + j * s.bin, upper = lower + s.bin - 1, frequency = frequencies[j];
        Lines marks;
        if (lower <= s.lsl && s.lsl <= upper) marks.push_back("lsl");
        if (lower <= s.target && s.target <= upper) marks.push_back("target");
        if (lower <= s.usl && s.usl <= upper) marks.push_back("usl");
        r.bins.push_back({lower,upper,frequency,(50 * frequency + top - 1) / top,marks});
    }
    return r;
}
