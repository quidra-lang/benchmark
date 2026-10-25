#include "spc.hpp"
#include <algorithm>

Zones::Zones(Limits v) : lcl(v.lcl), cl(v.cl), ucl(v.ucl) {
    double upper = (ucl - cl) / 3, lower = (cl - lcl) / 3;
    u1 = cl + upper; u2 = cl + 2 * upper; l1 = cl - lower; l2 = cl - 2 * lower;
}

std::string Zones::name(double v) const {
    if (v > ucl) return "OUT+";
    if (v < lcl) return "OUT-";
    if (v > u2) return "A+";
    if (v > u1) return "B+";
    if (v > cl) return "C+";
    if (v < l2) return "A-";
    if (v < l1) return "B-";
    if (v < cl) return "C-";
    return "C0";
}

std::vector<Signal> checkRules(int chart, const Series& series, Limits limits, const Numbers& rules) {
    const std::array<int, 9> lengths{0,1,3,5,8,6,14,15,8};
    Zones z(limits);
    std::vector<Signal> result;
    for (int k = 1; k <= static_cast<int>(series.values.size()); ++k) for (int rule : rules) {
        int length = lengths[rule], first = k - length;
        if (first < 0) continue;
        const std::vector<double>& v = series.values;
        double last = v[k - 1];
        std::string direction;
        auto all = [&](auto predicate) { return std::all_of(v.begin() + first,v.begin() + k,predicate); };
        if (rule == 1) {
            if (limits.outside(last)) direction = last > z.cl ? "UP" : "DOWN";
        } else if (rule == 2 || rule == 3) {
            double upper = rule == 2 ? z.u2 : z.u1, lower = rule == 2 ? z.l2 : z.l1;
            int needed = rule == 2 ? 2 : 4, up = 0, down = 0;
            for (int j = first; j < k; ++j) { up += v[j] > upper; down += v[j] < lower; }
            if (last > upper && up >= needed) direction = "UP";
            else if (last < lower && down >= needed) direction = "DOWN";
        } else if (rule == 4) {
            if (all([&](double x) { return x > z.cl; })) direction = "UP";
            else if (all([&](double x) { return x < z.cl; })) direction = "DOWN";
        } else if (rule == 5) {
            bool up = true, down = true;
            for (int j = first + 1; j < k; ++j) { up = up && v[j] > v[j - 1]; down = down && v[j] < v[j - 1]; }
            if (up) direction = "UP"; else if (down) direction = "DOWN";
        } else if (rule == 6) {
            bool valid = true;
            for (int j = first + 1; j < k; ++j) {
                if (v[j] == v[j - 1]) valid = false;
                if (j > first + 1 && (v[j] > v[j - 1]) == (v[j - 1] > v[j - 2])) valid = false;
            }
            if (valid) direction = "NONE";
        } else if (rule == 7) {
            if (all([&](double x) { return x > z.l1 && x < z.u1; })) direction = "NONE";
        } else {
            bool up = false, down = false, outside = true;
            for (int j = first; j < k; ++j) { up = up || v[j] > z.u1; down = down || v[j] < z.l1; outside = outside && (v[j] > z.u1 || v[j] < z.l1); }
            if (up && down && outside) direction = "NONE";
        }
        if (!direction.empty()) result.push_back({chart,rule,series.numbers[first],series.numbers[k - 1],last,direction});
    }
    return result;
}
