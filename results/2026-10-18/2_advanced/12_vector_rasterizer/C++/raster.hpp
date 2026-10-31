#pragma once
#include <array>
#include <optional>
#include <set>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

struct Point {
    int x, y;
    bool operator==(const Point& other) const { return x == other.x && y == other.y; }
    bool operator<(const Point& other) const { return std::tie(x,y) < std::tie(other.x,other.y); }
};
using Points = std::vector<Point>;
using Pixels = std::set<Point>;
using Segment = std::pair<Point, Point>;
using Segments = std::vector<Segment>;
using Color = std::array<int, 4>;
using Rgb = std::array<int, 3>;
using Image = std::vector<std::vector<Rgb>>;
using Lines = std::vector<std::string>;
struct Rect { int x0, y0, x1, y1; bool empty() const; bool contains(Point point) const; Rect intersect(Rect other) const; };
int floorDiv(int numerator, int denominator);
int roundRatio(int numerator, int denominator);
int effectiveAlpha(int alpha, int opacity);
struct Layer {
    int width, height, opacity;
    std::string mode;
    std::vector<std::optional<Color>> colors;
    std::vector<int> lines;
    Layer(int width, int height, int opacity, std::string mode);
    void paint(Point point, Color color, int line);
    bool erase(Point point);
    const std::optional<Color>& colorAt(Point point) const;
    int lineAt(Point point) const;
    int alphaAt(Point point) const;
    Rgb blend(Point point, Rgb current) const;
};
Image composite(const std::vector<Layer>& layers, Color background, int width, int height);
Points bresenham(Point start, Point end);
Points expandSquare(Point point, int width);
Pixels circlePoints(int radius);
Pixels ellipsePoints(int rx, int ry);
Points bezierPoints(const Points& controls, int segments);
std::optional<Segment> clipSegment(Point start, Point end, Rect clip);
Points clipPolygon(Points vertices, Rect clip);
Pixels fillPolygons(const std::vector<Points>& sequences, const std::string& rule, Rect clip);
Pixels fillShape(Point center, const Pixels& shape, Rect clip);
Pixels floodFill(const Layer& layer, Point seed, Rect clip);
void writePpm(const std::string& path, const Image& image);
void writePreview(const std::string& path, const Image& image);
