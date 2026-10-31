#include "ecg.h"
static int maximum(int a, int b) {
    return a > b ? a : b;
}
static int minimum(int a, int b) {
    return a < b ? a : b;
}
Peaks find_peaks(const Signals *signals) {
    Peaks out = {0};
    for (int n = 0; n < signals->count; ++n) {
        Integer value = signals->integrated[n];
        if (value <= 0)
            continue;
        bool peak = true;
        for (int j = maximum(0, n - 20); j < n; ++j)
            if (signals->integrated[j] >= value)
                peak = false;
        for (int j = n + 1; j <= minimum(signals->count - 1, n + 20); ++j)
            if (signals->integrated[j] > value)
                peak = false;
        if (!peak)
            continue;
        int r = maximum(0, n - 30);
        for (int j = r + 1; j <= n; ++j)
            if (llabs(signals->bandpass[j]) > llabs(signals->bandpass[r]))
                r = j;
        Integer slope = 0;
        for (int j = maximum(0, n - 29); j <= n; ++j)
            if (llabs(signals->derivative[j]) > slope)
                slope = llabs(signals->derivative[j]);
        out.data[out.count++] = (Peak){n, r, value, llabs(signals->bandpass[r]), slope, 0, 0, PENDING};
    }
    return out;
}
Integer qrs_width(const Signals *signals, int r) {
    Integer peak = llabs(signals->bandpass[r]);
    int first = r, last = r;
    for (int j = maximum(0, r - 25); j <= minimum(signals->count - 1, r + 25); ++j)
        if (4 * llabs(signals->bandpass[j]) >= peak) {
            if (j < first)
                first = j;
            if (j > last)
                last = j;
        }
    return 5 * (last - first + 1);
}
Levels initial_levels(const Signals *signals) {
    Integer maximum_i = 0, sum_i = 0, maximum_f = 0, sum_f = 0;
    for (int i = 0; i < 400; ++i) {
        if (signals->integrated[i] > maximum_i)
            maximum_i = signals->integrated[i];
        sum_i += signals->integrated[i];
        Integer f = llabs(signals->bandpass[i]);
        if (f > maximum_f)
            maximum_f = f;
        sum_f += f;
    }
    return (Levels){floor_div(maximum_i, 3), floor_div(sum_i, 800), floor_div(maximum_f, 3),
                    floor_div(sum_f, 800)};
}
