#ifndef STEREO_HPP
#define STEREO_HPP
#include <algorithm>
#include <array>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <limits>
#include <map>
#include <numeric>
#include <set>
#include <sstream>
#include <string>
#include <utility>
#include <vector>
using I = long long;
using Image = std::vector<I>;
using Volume = std::vector<Image>;
using Pixels = std::vector<int>;
using Lines = std::vector<std::string>;
struct PGM {
    int width = 0, height = 0;
    Image pixels;
};
struct Params {
    int minimum = 0, maximum = 0, texture_window = 0, sgm_window = 0, paths = 0, speckle_size = 0,
        speckle_range = 0, fusion_votes = 0, object_range = 0, object_size = 0;
    I texture_threshold = 0, uniqueness = 0, lr = 0, p1 = 0, p2 = 0, gamma = 0, focal = 0,
      baseline = 0;
    int wta_kind = 0, sgm_kind = 0;
    std::array<std::vector<int>, 3> windows;
    std::vector<std::pair<int, int>> samples;
};
extern const std::array<std::pair<int, int>, 8> directions;
PGM read_pgm(const std::string &path);
Params read_parameters();
void write_pgm(const std::string &name, const PGM &image);
void save(const std::string &name, const Lines &lines);
I clamped(const Image &image, int width, int height, int x, int y);
Image box_sum(const Image &image, int width, int height, int window),
    census(const Image &image, int width, int height),
    texture(const Image &image, int width, int height, int window);
Volume cost_volume(const PGM &left, const PGM &right, const Image &cl, const Image &cr, int kind,
                   int window, const Params &p);
Volume path_costs(const Volume &base, const PGM &left, std::pair<int, int> direction,
                  const Params &p);
std::vector<Volume> cumulative_costs(const Volume &base, const PGM &left, const Params &p);
std::string hundredths(I value), two_decimals(I numerator, I denominator = 1);
I depth_hundredths(I disparity, I focal, I baseline);
std::pair<std::string, std::string> subpixel(I disparity, const Image &costs, const Params &p);
struct Regions {
    std::array<Pixels, 3> region;
    Pixels occluded;
};
struct Evaluation {
    I pixels = 0, valid = 0, bad1 = 0, bad2 = 0, error_sum = 0, exact = 0;
};
Regions truth_regions(const PGM &truth);
Evaluation evaluate(const Image &image, const Image &truth, const Pixels &region);
std::string ratio(I numerator, I denominator);
template <class... T> void line(Lines &lines, const T &...values) {
    std::ostringstream out;
    (out << ... << values);
    lines.push_back(out.str());
}
#endif
