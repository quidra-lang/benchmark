#include "ecg.hpp"
Signals filter(const Values &ecg) {
    const int size = ecg.size();
    Signals out;
    out.lowpass.resize(size);
    out.bandpass.resize(size);
    out.derivative.resize(size);
    out.squared.resize(size);
    out.integrated.resize(size);
    Values c(size);
    Integer highpass_sum = 0, square_sum = 0;
    auto at = [](const Values &values, int i) { return i < 0 ? Integer(0) : values[i]; };
    for (int n = 0; n < size; ++n) {
        c[n] = 2 * at(c, n - 1) - at(c, n - 2) + ecg[n] - 2 * at(ecg, n - 6) + at(ecg, n - 12);
        out.lowpass[n] = floor_div(c[n], 32);
        highpass_sum += out.lowpass[n] - at(out.lowpass, n - 32);
        out.bandpass[n] = at(out.lowpass, n - 16) - floor_div(highpass_sum, 32);
        out.derivative[n] = floor_div(2 * out.bandpass[n] + at(out.bandpass, n - 1) -
                                          at(out.bandpass, n - 3) - 2 * at(out.bandpass, n - 4),
                                      8);
        out.squared[n] = out.derivative[n] * out.derivative[n];
        square_sum += out.squared[n] - at(out.squared, n - 30);
        out.integrated[n] = floor_div(square_sum, 30);
    }
    return out;
}
