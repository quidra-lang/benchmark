#ifndef ANALYZER_HPP
#define ANALYZER_HPP
#include <algorithm>
#include <array>
#include <cmath>
#include <complex>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <limits>
#include <numeric>
#include <sstream>
#include <string>
#include <tuple>
#include <vector>
using I = std::int64_t;
using Complex = std::complex<double>;
using Complexes = std::vector<Complex>;
using Values = std::vector<double>;
using Ids = std::vector<int>;
using Lines = std::vector<std::string>;
constexpr double pi = 3.141592653589793;
struct Params {
    int main_length, peak_count, search, welch_length, frame_length, hop, shade, pitch_low, pitch_high,
        band_low, band_high, notch_frequency, notch_width, envelope_low, envelope_high, zoom_low, zoom_high,
        zoom_points, max_lag, third_low, third_high, block_length;
    std::string main_window, welch_window, frame_window;
    double peak_threshold, fundamental, onset_factor;
    Values fir;
    Ids bands;
};
struct Input {
    int fs;
    std::array<Values, 2> signal;
    Params params;
};
struct WindowFigures {
    double s1 = 0, s2 = 0, coherent = 0, enbw = 0, enbw_hz = 0, scalloping = 0;
};
struct Spectrum {
    Values windowed, amplitude;
    Complexes transformed;
    WindowFigures figures;
};
struct Interpolation {
    double position, value;
};
struct Welch {
    Values psd, coherence;
    Complexes transfer;
    int segments = 0;
    double packing_error = 0;
};
struct Frames {
    std::vector<Values> magnitudes;
    double packing_error = 0;
};
Input load();
int pow2(int value);
bool power_of_two(int value);
Complex rot(double angle);
Complexes radix2(Complexes values, bool inverse = false);
Complexes dft(const Complexes &values);
Complexes idft(const Complexes &values);
Complexes packed_real(const Values &values);
Values convolution(const Values &a, const Values &b);
Complexes chirp_z(const Values &windowed, int fs, int low, int high, int points);
Values window(const std::string &name, int length);
WindowFigures window_figures(const Values &values, int fs);
Spectrum spectrum(const Values &signal, int length, const std::string &name, int fs);
Welch welch(const Values &x, const Values &y, const Params &params, int fs);
Frames frames(const Values &x, const Params &params);
bool local_maximum(const Values &values, int index);
Interpolation interpolate(const Values &values, int index, bool logarithmic = true);
double median(Values values);
std::string real(double value);
std::string shade_line(double frequency, const std::vector<Values> &magnitudes, int bin, double maximum,
                       int band);
void save(const std::string &name, const Lines &lines);
#endif
