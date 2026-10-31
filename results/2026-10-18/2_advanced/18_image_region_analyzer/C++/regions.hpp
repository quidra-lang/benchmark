#pragma once
#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <map>
#include <numeric>
#include <set>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

using Integer = std::int64_t;
using Lines = std::vector<std::string>;
using Pixel = std::pair<int, int>;
using Pixels = std::vector<Pixel>;
using PixelSet = std::set<Pixel>;
template<class... Parts> std::string text(const Parts&... parts) { std::ostringstream stream; (stream << ... << parts); return stream.str(); }
template<class... Parts> void add(Lines& lines, const Parts&... parts) { lines.push_back(text(parts...)); }
template<class T> std::string join(const std::vector<T>& values, const std::string& separator = " ") {
    std::ostringstream stream;
    for (std::size_t i = 0; i < values.size(); ++i) { if (i) stream << separator; stream << values[i]; }
    return stream.str();
}
struct Rational {
    Integer numerator = 0, denominator = 1;
    Rational() = default;
    Rational(Integer numerator, Integer denominator = 1) : numerator(numerator), denominator(denominator) {
        if (this->denominator < 0) { this->numerator = -this->numerator; this->denominator = -this->denominator; }
        Integer divisor = std::gcd(this->numerator, this->denominator);
        this->numerator /= divisor; this->denominator /= divisor;
    }
};
int compare(Rational first, Rational second);
struct Image { std::string name; int width, height, maxval; std::vector<int> pixels; };
struct Mask {
    int width, height;
    std::vector<unsigned char> pixels;
    Mask(int width, int height) : width(width), height(height), pixels(static_cast<std::size_t>(width * height)) {}
    bool inside(int x, int y) const { return x >= 0 && y >= 0 && x < width && y < height; }
    bool at(int x, int y) const { return inside(x, y) && pixels[static_cast<std::size_t>(y * width + x)] != 0; }
    void set(int x, int y, bool value) { pixels[static_cast<std::size_t>(y * width + x)] = static_cast<unsigned char>(value); }
    int count() const { return std::accumulate(pixels.begin(), pixels.end(), 0); }
};
Lines readLines(const std::string& path);
Lines words(const std::string& line);
std::vector<Image> readImages(const std::string& path);
struct Histogram {
    int maxval, pixels, minimum, maximum, median, mode, levels, binWidth;
    Integer total;
    std::vector<Integer> counts, belowCounts, belowSums, bins;
    explicit Histogram(const Image& image);
};
struct Candidate { int cutoff; Integer below, sumBelow, above, sumAbove, numerator, denominator; };
struct Otsu { int cutoff, upper; std::vector<Candidate> candidates; };
Otsu otsu(const Histogram& histogram);
std::pair<int, int> isodata(const Histogram& histogram);
Mask erode(const Mask& mask, const Pixels& offsets);
Mask dilate(const Mask& mask, const Pixels& offsets);
Mask opening(const Mask& mask, const Pixels& offsets);
Mask closing(const Mask& mask, const Pixels& offsets);
PixelSet thin(const Pixels& pixels);
int crossingNumber(const PixelSet& pixels, Pixel point);
struct Labeling { int width, height, count, provisional; std::vector<int> labels; };
Labeling labelComponents(const Mask& mask, int connectivity);
int bitQuadEuler(const Mask& mask, int connectivity);
std::string decimal(Rational value, int digits);
std::string hullAreaText(Integer doubled);
void writeLines(const std::string& name, const Lines& lines);
