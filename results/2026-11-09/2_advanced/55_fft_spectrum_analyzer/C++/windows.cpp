#include "analyzer.hpp"
Values window(const std::string &name, int length) {
    Values coefficients;
    if (name == "rectangular")
        coefficients = {1};
    else if (name == "hann")
        coefficients = {0.5, 0.5};
    else if (name == "hamming")
        coefficients = {0.54, 0.46};
    else if (name == "blackman")
        coefficients = {0.42, 0.5, 0.08};
    else
        coefficients = {0.21557895, 0.41663158, 0.277263158, 0.083578947, 0.006947368};
    Values out(length);
    for (int n = 0; n < length; ++n)
        for (int j = 0; j < int(coefficients.size()); ++j)
            out[n] += (j % 2 ? -1 : 1) * coefficients[j] * std::cos(2 * pi * j * n / length);
    return out;
}
WindowFigures window_figures(const Values &values, int fs) {
    WindowFigures out;
    Complex sum{};
    const int length = values.size();
    for (int n = 0; n < length; ++n) {
        out.s1 += values[n];
        out.s2 += values[n] * values[n];
        sum += values[n] * rot(pi * n / length);
    }
    out.coherent = out.s1 / length;
    out.enbw = length * out.s2 / (out.s1 * out.s1);
    out.enbw_hz = out.enbw * fs / length;
    out.scalloping = -20 * std::log10(std::abs(sum) / out.s1);
    return out;
}
