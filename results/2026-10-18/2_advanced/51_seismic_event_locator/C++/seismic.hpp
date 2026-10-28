#ifndef SEISMIC_HPP
#define SEISMIC_HPP
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <limits>
#include <map>
#include <numeric>
#include <optional>
#include <sstream>
#include <string>
#include <vector>
using I = std::int64_t;
using Ids = std::vector<int>;
using Values = std::vector<double>;
using Solution = std::array<double, 4>;
using Matrix = std::array<Solution, 4>;
constexpr double pi = 3.141592653589793;
struct Params {
    I sw, lw, on_p, on_q, off_p, off_q, min_duration, noise, aw, clip, window, minimum;
    double velocity;
    std::array<I, 3> gx, gy, gz;
    double limit;
    std::array<double, 3> qa, qb;
    std::array<double, 2> cluster;
    std::array<double, 3> local, duration;
    std::array<I, 4> area;
    std::array<I, 2> map_size, section;
    std::array<I, 5> timeline;
};
struct Station {
    std::string code;
    I x = 0, y = 0, elevation = 0, start = 0;
    std::vector<I> samples;
    I mean = 0, peak = 0, clipped = 0;
    double noise = 0;
    int triggers = 0, short_triggers = 0;
    double correction = 0, mag_correction = 0;
    int used = 0, mag_count = 0;
    double first_square = 0, final_square = 0;
};
enum class State { used, dropped, added, rejected, unassociated };
struct Pick {
    int station;
    I sample, duration, amplitude;
    double ratio;
    bool clipped;
    bool assigned = false;
    State state = State::unassociated;
    int event = 0;
    double first_residual = 0, residual = 0;
    double time() const {
        return sample / 100.0;
    }
};
struct Observation {
    int station;
    double time;
};
using Observations = std::vector<Observation>;
struct Iteration {
    Solution solution{};
    double rms = 0;
};
struct Run {
    Solution solution{}, grid{};
    double rms = 0, grid_rms = 0;
    Values profile, residual;
    std::array<Iteration, 8> trace;
};
struct Candidate {
    Ids picks, retained, dropped;
    Values drop_residual;
    int first = 0, event = 0;
    bool rejected = false;
    std::vector<Run> passes;
};
struct Ellipse {
    double smaj, smin, az, erz, ert;
};
struct PickMagnitude {
    double radius, md;
    std::optional<double> ml;
};
struct Frequency {
    std::map<I, int> counts;
    I completeness = 0;
    int nb = 0, n = 0;
    double b, sigma, a, slope, intercept, r, mean_diff;
};
void load(std::vector<Station> &stations, Params &params);
std::vector<Pick> detect_station(Station &station, int index, const Params &params);
std::vector<Candidate> associate(std::vector<Pick> &picks, const Params &params);
double distance(const Solution &solution, const Station &station);
Values residuals(const Solution &solution, const Observations &observations,
                 const std::vector<Station> &stations, double velocity);
double rms(const Solution &solution, const Observations &observations, const std::vector<Station> &stations,
           double velocity);
Run geiger(Solution initial, const Observations &observations, const std::vector<Station> &stations,
           double velocity);
Run locate(const Observations &observations, const std::vector<Station> &stations, const Params &params);
Ellipse ellipse(const Solution &solution, const Observations &observations,
                const std::vector<Station> &stations, double velocity);
double logarithm(double value);
double median(Values values);
PickMagnitude magnitude(const Pick &pick, double radius, const Params &params);
I scaled(double value, int places);
I floor_div(I a, I b);
I class_number(double magnitude);
std::string class_text(I value);
Frequency frequency(const Values &local, const Values &duration);
#endif
