#include "ecg.hpp"
std::vector<Peak> find_peaks(const Signals &signals) {
    std::vector<Peak> out;
    const int size = signals.integrated.size();
    for (int n = 0; n < size; ++n) {
        const Integer value = signals.integrated[n];
        if (value <= 0)
            continue;
        bool maximum = true;
        for (int j = std::max(0, n - 20); j < n; ++j)
            if (signals.integrated[j] >= value)
                maximum = false;
        for (int j = n + 1; j <= std::min(size - 1, n + 20); ++j)
            if (signals.integrated[j] > value)
                maximum = false;
        if (!maximum)
            continue;
        int r = std::max(0, n - 30);
        for (int j = r + 1; j <= n; ++j)
            if (std::abs(signals.bandpass[j]) > std::abs(signals.bandpass[r]))
                r = j;
        Integer slope = 0;
        for (int j = std::max(0, n - 29); j <= n; ++j)
            slope = std::max(slope, std::abs(signals.derivative[j]));
        out.push_back({n, r, value, std::abs(signals.bandpass[r]), slope, 0, 0, PeakClass::pending});
    }
    return out;
}
Integer qrs_width(const Signals &signals, int r) {
    const Integer peak = std::abs(signals.bandpass[r]);
    int first = r, last = r;
    for (int j = std::max(0, r - 25); j <= std::min(int(signals.bandpass.size() - 1), r + 25); ++j)
        if (4 * std::abs(signals.bandpass[j]) >= peak) {
            first = std::min(first, j);
            last = std::max(last, j);
        }
    return 5 * (last - first + 1);
}
Levels initial_levels(const Signals &signals) {
    Integer maximum_i = 0, sum_i = 0, maximum_f = 0, sum_f = 0;
    for (int i = 0; i < 400; ++i) {
        maximum_i = std::max(maximum_i, signals.integrated[i]);
        sum_i += signals.integrated[i];
        const Integer f = std::abs(signals.bandpass[i]);
        maximum_f = std::max(maximum_f, f);
        sum_f += f;
    }
    return {floor_div(maximum_i, 3), floor_div(sum_i, 800), floor_div(maximum_f, 3), floor_div(sum_f, 800)};
}
