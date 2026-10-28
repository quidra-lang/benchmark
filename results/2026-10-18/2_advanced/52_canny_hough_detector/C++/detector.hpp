#ifndef DETECTOR_HPP
#define DETECTOR_HPP
#include <algorithm>
#include <array>
#include <cstdint>
#include <fstream>
#include <functional>
#include <map>
#include <numeric>
#include <optional>
#include <queue>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <vector>
using I = std::int64_t;
struct Point {
    I x, y;
    bool operator==(const Point &b) const {
        return x == b.x && y == b.y;
    }
    bool operator<(const Point &b) const {
        return std::tie(y, x) < std::tie(b.y, b.x);
    }
};
using Points = std::vector<Point>;
struct Image {
    int width = 0, height = 0;
    std::vector<I> data;
    Image() = default;
    Image(int w, int h) : width(w), height(h), data(w * h) {
    }
    bool inside(Point p) const {
        return p.x >= 0 && p.x < width && p.y >= 0 && p.y < height;
    }
    I &at(Point p) {
        return data[p.y * width + p.x];
    }
    I at(Point p) const {
        return data[p.y * width + p.x];
    }
};
struct Params {
    I ks, divisor, low, high, r_min, r_max, circle_percent, circle_count, rho_step, vote_threshold,
        line_count, tolerance, max_gap, min_length, junction_distance, junction_angle, angle_tolerance,
        square_tolerance, margin, harris_window, harris_threshold, corner_count, match_distance,
        overlay_divisor;
    std::vector<I> kernel;
};
using Trig = std::array<std::array<I, 2>, 180>;
struct Input {
    Image image;
    Params params;
    Trig trig;
};
struct Gradient {
    Image gx, gy, magnitude;
};
struct Canny {
    Image direction, nms, edges;
    std::vector<Points> components;
    I strong = 0, weak = 0;
};
struct CirclePeak {
    I radius;
    Point center;
    I votes, points;
};
struct CircleVotes {
    std::vector<Points> offsets;
    std::vector<std::vector<I>> votes;
    std::vector<CirclePeak> peaks;
    I candidates = 0;
};
struct LinePeak {
    I theta, rho, votes;
};
struct LineVotes {
    I low, high, maximum = 0;
    Image votes;
    std::vector<LinePeak> peaks;
};
struct Corner {
    Point point;
    I response;
};
struct Corners {
    std::vector<Corner> values;
    I candidates = 0;
};
Input load();
void write_pgm(const std::string &name, const Image &image);
I floor_div(I a, I b);
I clamped(const Image &image, I x, I y);
Image smooth(const Image &image, const Params &params);
Gradient gradient(const Image &image);
Canny canny(const Gradient &gradient, const Params &params);
Points circle_points(I radius);
CircleVotes circle_votes(const Image &edges, const Params &params);
I rho(Point point, I theta, const Trig &trig, const Params &params);
LineVotes line_votes(const Image &edges, const Trig &trig, const Params &params);
Corners corners(const Gradient &gradient, const Params &params);
#endif
