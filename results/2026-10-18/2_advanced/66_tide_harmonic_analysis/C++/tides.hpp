#ifndef TIDES_HPP
#define TIDES_HPP
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <limits>
#include <map>
#include <numeric>
#include <optional>
#include <sstream>
#include <string>
#include <utility>
#include <vector>
using I = long long;
using Vector = std::vector<double>;
using Matrix = std::vector<Vector>;
using Lines = std::vector<std::string>;
struct Station {
    std::string code, name;
    std::map<int, std::optional<I>> observations;
};
struct Constituent {
    std::string name;
    double speed;
};
struct Params {
    int epoch_day = 0, flat_run = 0, spike_window = 0, spike_count = 0, top = 0, surge_hours = 0,
        start = 0, length = 0, grid = 0, lag = 0, plot_hours = 0, plot_top = 0, plot_bottom = 0,
        plot_step = 0;
    double spike_factor = 0, spike_minimum = 0, rayleigh = 0, snr = 0, surge = 0, min_range = 0;
    std::string reference, plot;
};
struct Input {
    Params params;
    std::vector<Station> stations;
    std::vector<Constituent> constituents;
};
int civil_day(int year, int month, int day), hour(const std::string &value, int epoch_day);
I parse_minutes(const std::string &value);
std::string datetime(int minutes, int epoch_day), date(int day, int epoch_day);
Input read_inputs();
struct Flat {
    int first, last;
    I milli;
};
struct Spike {
    int time;
    double residual, median, mad, limit;
};
struct Gap {
    int first, last;
    std::string cause;
};
double median(Vector values);
std::vector<Flat> flat_runs(const std::map<int, std::optional<I>> &observations, int first,
                            int last, int minimum);
std::vector<Spike> spikes(const std::map<int, double> &residuals, const Params &params,
                          int &tested);
std::vector<Gap> gaps(const std::map<int, std::string> &reasons, int first, int last);
struct Sample {
    int time;
    double value;
};
struct Model {
    Vector speeds, coefficients, amplitudes, phases;
    Matrix inverse;
};
double angle(double speed, double time);
Vector regressors(const Vector &speeds, double time);
Model fit(const std::vector<Sample> &samples, const Vector &speeds);
double prediction(const Model &model, double time);
struct Extremum {
    bool high;
    double mu, height;
    int minute = 0;
    std::string label;
};
std::vector<Extremum> extrema(const Model &model, int start, int length, int grid);
std::string real(double value, int digits);
void save(const std::string &name, const Lines &lines);
Lines plot_lines(const Vector &heights, const Lines &cells, const std::string &axis);
template <class... T> void line(Lines &lines, const T &...values) {
    std::ostringstream out;
    (out << ... << values);
    lines.push_back(out.str());
}
#endif
