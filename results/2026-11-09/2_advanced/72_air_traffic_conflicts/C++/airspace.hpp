#ifndef AIRSPACE_HPP
#define AIRSPACE_HPP
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iomanip>
#include <map>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <vector>
using Integer = std::int64_t;
using Point = std::array<double, 3>;
using Pair = std::pair<int, int>;
using Names = std::vector<std::string>;
using Lines = Names;
struct AircraftType {
    std::string name;
    int climb, descent, minimum;
};
struct Waypoint {
    int x, y;
    std::optional<Integer> level;
};
struct Plan {
    std::string callsign;
    int type;
    Integer departure, delay = 0;
    Integer level, offset = 0;
    int speed_initial, speed;
    std::vector<Waypoint> waypoints;
    Names history;
};
struct Sector {
    std::string name;
    int x1, y1, x2, y2;
    Integer lower, upper;
    Integer capacity;
};
struct Params {
    Integer horizontal, vertical, lookahead, max_delay, level_min, level_max, sample_start,
        sample_end;
    std::array<Integer, 6> radar;
    std::vector<Integer> snapshots;
    Integer leader, alert;
};
struct Input {
    std::vector<Plan> plans;
    std::vector<AircraftType> types;
    std::vector<Sector> sectors;
    Params params;
};
Input read_inputs();
std::vector<Integer> flight_levels(const Plan &plan);
enum class Phase { Climb, Descent, Level };
std::string phase_name(Phase phase);
struct Segment {
    int number, leg;
    Phase phase;
    double start_time, end_time;
    Point start, velocity, end;
};
struct Trajectory {
    std::vector<Segment> segments;
    double arrival, length;
    std::vector<std::pair<double, Integer>> passing;
};
Trajectory build_trajectory(const Plan &plan, const std::vector<AircraftType> &types);
Point position(const Segment &segment, double time);
const Segment *active_segment(const Trajectory &trajectory, double time);
struct Loss {
    double low, high, time, distance, vertical;
};
std::optional<Loss> loss_interval(Point relative, Point velocity, double first, double last,
                                  double horizontal, double vertical);
struct Piece {
    int first_segment, second_segment;
    Loss loss;
};
struct Conflict {
    Pair pair;
    double start, end;
    std::vector<Piece> pieces;
    Piece closest;
    double first_level = 0, second_level = 0, first_track = 0, second_track = 0, angle = 0;
    int geometry = 0, severity = 0, sector = -1;
    std::string outcome;
};
bool conflict_before(const Conflict &left, const Conflict &right);
std::vector<Conflict> pair_conflicts(int first, const Trajectory &first_trajectory, int second,
                                     const Trajectory &second_trajectory, const Params &params);
std::vector<Conflict> all_conflicts(const std::vector<Trajectory> &trajectories,
                                    const Params &params);
enum class ManoeuvreKind { Level, Speed, Delay };
struct Manoeuvre {
    std::string name;
    ManoeuvreKind kind;
    Integer amount;
};
std::vector<Manoeuvre> manoeuvres(Integer max_delay);
std::optional<Plan> propose(const Plan &plan, const Manoeuvre &manoeuvre,
                            const std::vector<AircraftType> &types, const Params &params);
std::array<int, 2> priority_order(int first, int second, const std::vector<Plan> &plans);
std::string decimal(double value, int digits = 3), signed_integer(Integer value),
    joined(const Names &names, const std::string &separator = ",");
void frame(Lines &out, const Names &grid), write_lines(const std::string &name, const Lines &lines);
template <class... T> void line(Lines &out, const T &...values) {
    std::ostringstream stream;
    (stream << ... << values);
    out.push_back(stream.str());
}
#endif
