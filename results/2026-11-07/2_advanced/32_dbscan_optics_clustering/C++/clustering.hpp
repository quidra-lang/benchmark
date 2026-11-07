#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <deque>
#include <fstream>
#include <iomanip>
#include <limits>
#include <map>
#include <numeric>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <vector>
using Integer = std::int64_t;
constexpr Integer INF = std::numeric_limits<Integer>::max();
struct Point {
    int id, x, y;
};
using Distances = std::vector<std::vector<Integer>>;
struct Params {
    std::vector<int> eps, extract;
    int min_points, max_eps, xi_u, xi_v, xi_size, width, height, kwidth, kheight, rwidth;
};
struct Input {
    std::vector<Point> points;
    Params params;
};
Input read_input();
Integer distance(const Point &, const Point &);
struct Grid {
    int radius;
    std::map<std::pair<int, int>, std::vector<int>> cells;
    std::vector<std::vector<int>> neighbors;
    std::vector<int> candidates;
    int busiest_x = 0, busiest_y = 0, busiest_count = 0;
    Integer total_candidates = 0, pairs = 0, brute_pairs = 0;
    bool correct = true;
    std::map<int, int> occupancy;
};
Grid build_grid(const std::vector<Point> &, const Distances &, int);
std::vector<int> dbscan(const Grid &, int);
struct Optics {
    std::vector<Integer> core, reach;
    std::vector<int> predecessor, order;
};
Optics optics(const Grid &, const Distances &, int);
std::string fraction(Integer, Integer);
std::string root(Integer);
std::string ari_value(Integer, Integer);
std::vector<std::string> framed(const std::vector<std::string> &);
void write_lines(std::ostream &, const std::vector<std::string> &);
