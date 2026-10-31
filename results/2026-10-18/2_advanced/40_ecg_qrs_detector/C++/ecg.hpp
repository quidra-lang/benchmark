#ifndef ECG_HPP
#define ECG_HPP
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <functional>
#include <iomanip>
#include <map>
#include <numeric>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <vector>
using Integer = std::int64_t;
using Values = std::vector<Integer>;
using Lines = std::vector<std::string>;
struct Params {
    Integer refractory_ms, twave_ms, searchback_percent, premature_percent, qrs_width_ms, match_ms, pause_ms,
        brady_ms, tachy_ms, excerpt_ms, segment_ms, strip_start_ms, strip_ms, strip_rows, chart_rows,
        poincare_size;
};
struct Annotation {
    int sample;
    char label;
    int beat = -1;
};
struct Input {
    Values ecg;
    std::vector<Annotation> annotations;
    Params params;
};
struct Signals {
    Values lowpass, bandpass, derivative, squared, integrated;
};
enum class PeakClass { qrs, searchback, twave, refractory, noise, pending };
struct Peak {
    int time = 0, r = 0;
    Integer integrated = 0, filtered = 0, slope = 0, thr_i = 0, thr_f = 0;
    PeakClass kind = PeakClass::pending;
};
struct Levels {
    Integer spki = 0, npki = 0, spkf = 0, npkf = 0;
};
Input read_input();
void write_lines(const std::string &name, const Lines &lines);
Signals filter(const Values &ecg);
std::vector<Peak> find_peaks(const Signals &signals);
Integer qrs_width(const Signals &signals, int r);
Levels initial_levels(const Signals &signals);
Integer floor_div(Integer a, Integer b);
Integer rdiv(Integer a, Integer b);
std::string decimal2(Integer value);
std::string decimal4(Integer value);
std::string reduced(Integer a, Integer b);
std::string ratio(Integer a, Integer b);
std::string optional_number(bool exists, Integer value);
Integer integer_sqrt(Integer value);
Integer root(Integer numerator, Integer denominator);
Integer mean_scaled(const Values &values);
Integer mean_hr(const Values &intervals);
Integer sample_deviation(const Values &values, Integer multiplier = 1);
Integer rms(const Values &values);
std::map<Integer, int> histogram(const Values &intervals);
std::vector<std::pair<int, int>> ranges(const std::vector<bool> &flags);
#endif
