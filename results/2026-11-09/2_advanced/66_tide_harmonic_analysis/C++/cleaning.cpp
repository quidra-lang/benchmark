#include "tides.hpp"
double median(Vector values) {
    std::sort(values.begin(), values.end());
    int n = int(values.size());
    return n % 2 ? values[n / 2] : (values[n / 2 - 1] + values[n / 2]) / 2;
}
std::vector<Flat> flat_runs(const std::map<int, std::optional<I>> &observations, int first,
                            int last, int minimum) {
    std::vector<Flat> out;
    int time = first;
    while (time <= last) {
        auto entry = observations.find(time);
        if (entry == observations.end() || !entry->second) {
            ++time;
            continue;
        }
        int start = time;
        I value = *entry->second;
        while (time < last) {
            auto next = observations.find(time + 1);
            if (next == observations.end() || !next->second || *next->second != value)
                break;
            ++time;
        }
        if (time - start + 1 >= minimum)
            out.push_back({start, time, value});
        ++time;
    }
    return out;
}
std::vector<Spike> spikes(const std::map<int, double> &residuals, const Params &p, int &tested) {
    std::vector<Spike> out;
    tested = 0;
    for (const auto &entry : residuals) {
        Vector window;
        for (auto i = residuals.lower_bound(entry.first - p.spike_window);
             i != residuals.end() && i->first <= entry.first + p.spike_window; ++i)
            window.push_back(i->second);
        if (int(window.size()) < p.spike_count)
            continue;
        ++tested;
        double center = median(window);
        Vector deviations;
        for (double value : window)
            deviations.push_back(std::abs(value - center));
        double mad = median(deviations),
               limit = std::max(p.spike_factor * 1.4826 * mad, p.spike_minimum);
        if (std::abs(entry.second - center) > limit)
            out.push_back({entry.first, entry.second, center, mad, limit});
    }
    return out;
}
std::vector<Gap> gaps(const std::map<int, std::string> &reasons, int first, int last) {
    std::vector<Gap> out;
    int time = first;
    while (time <= last) {
        auto entry = reasons.find(time);
        if (entry == reasons.end()) {
            ++time;
            continue;
        }
        int start = time;
        std::string cause = entry->second;
        while (time < last && reasons.count(time + 1)) {
            ++time;
            if (reasons.at(time) != cause)
                cause = "mixed";
        }
        out.push_back({start, time, cause});
        ++time;
    }
    return out;
}
