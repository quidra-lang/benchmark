#include "seismic.hpp"
std::vector<Pick> detect_station(Station &s, int station, const Params &p) {
    const int count = s.samples.size();
    s.mean = floor_div(std::accumulate(s.samples.begin(), s.samples.end(), I(0)), count);
    std::vector<I> d(count), energy(count), prefix(count + 1);
    Values amplitudes;
    for (int i = 0; i < count; ++i) {
        d[i] = s.samples[i] - s.mean;
        energy[i] = d[i] * d[i];
        prefix[i + 1] = prefix[i] + energy[i];
        amplitudes.push_back(std::abs(d[i]));
        s.peak = std::max(s.peak, std::abs(d[i]));
        s.clipped += std::abs(s.samples[i]) >= p.clip;
    }
    s.noise = median(amplitudes);
    std::vector<Pick> picks;
    bool on = false;
    int beginning = 0;
    double maximum = 0;
    auto finish = [&](int end) {
        ++s.triggers;
        const I duration = end - beginning;
        if (duration < p.min_duration) {
            ++s.short_triggers;
            return;
        }
        int k = beginning;
        while (k - 1 >= beginning - p.sw + 1 && energy[k - 1] >= p.noise)
            --k;
        I amplitude = 0;
        bool clipped = false;
        for (int j = k; j < std::min<I>(k + p.aw, count); ++j) {
            amplitude = std::max(amplitude, std::abs(d[j]));
            clipped = clipped || std::abs(s.samples[j]) >= p.clip;
        }
        picks.push_back({station, s.start + k, duration, amplitude, maximum, clipped});
    };
    for (int i = p.sw + p.lw - 1; i < count; ++i) {
        const I sta = prefix[i + 1] - prefix[i - p.sw + 1],
                lta = prefix[i - p.sw + 1] - prefix[i - p.sw - p.lw + 1];
        if (!on) {
            if (sta * p.lw * p.on_q >= p.on_p * lta * p.sw) {
                on = true;
                beginning = i;
                maximum = double(sta * p.lw) / double(lta * p.sw);
            }
        } else if (sta * p.lw * p.off_q < p.off_p * lta * p.sw) {
            finish(i);
            on = false;
        } else
            maximum = std::max(maximum, double(sta * p.lw) / double(lta * p.sw));
    }
    if (on)
        finish(count);
    return picks;
}
