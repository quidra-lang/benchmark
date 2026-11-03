#ifndef GEOMETRY_HPP
#define GEOMETRY_HPP
#include <array>
#include <cstdint>
#include <memory>
#include <optional>
#include <ostream>
#include <sstream>
#include <string>
#include <vector>
using Integer = std::int64_t;
struct Fraction {
    Integer numerator = 0, denominator = 1;
    Fraction(Integer = 0, Integer = 1);
    int compare(Fraction) const;
    double real() const;
    Integer rounded() const;
};
std::ostream &operator<<(std::ostream &, Fraction);
struct Point {
    Integer x = 0, y = 0, denominator = 1;
    Point(Integer = 0, Integer = 0, Integer = 1);
    Fraction xValue() const;
    Fraction yValue() const;
    bool operator==(const Point &) const;
};
std::ostream &operator<<(std::ostream &, Point);
bool pointLess(Point, Point);
Integer integerCross(Point, Point, Point);
struct OriginalLine {
    Integer ax, ay, bx, by;
};
OriginalLine originalLine(Point, Point);
OriginalLine reverseLine(OriginalLine);
Integer lineCross(OriginalLine, Point);
Integer directionCross(OriginalLine, OriginalLine);
std::string segmentText(Point, Point);
bool onSegment(Point, Point, Point);
bool touching(Point, Point, Point, Point);
bool overlapping(Point, Point, Point, Point);
struct Intersection {
    Fraction first, second;
    Point point;
};
std::optional<Intersection> crossing(OriginalLine, OriginalLine);
Point lineIntersection(OriginalLine, OriginalLine);
struct Ring {
    std::vector<Point> points;
    std::vector<OriginalLine> edges;
};
using Rings = std::vector<Ring>;
struct Polygon {
    Rings input, rings;
};
using PolygonPtr = std::shared_ptr<const Polygon>;
using PolygonList = std::vector<PolygonPtr>;
struct Result {
    PolygonList polygons;
    PolygonPtr a, b;
};
Ring integerRing(std::vector<Point>);
bool onEdge(Point, const Ring &, std::size_t);
bool insideRing(Point, const Ring &);
bool interior(Point, const Rings &);
bool boundary(Point, const Ring &);
Ring rotateRing(Ring);
bool counterclockwise(const Ring &);
Ring reverseRing(const Ring &);
PolygonPtr canonical(const Rings &);
PolygonList assemble(Rings);
double ringArea(const Ring &);
double ringPerimeter(const Ring &);
Rings flatten(const PolygonList &);
double totalArea(const PolygonList &);
struct Crossing;
struct GhNode {
    Point point;
    int side;
    Crossing *crossing = nullptr;
    bool entering = false;
    OriginalLine outgoing;
    GhNode *next = nullptr, *previous = nullptr, *other = nullptr;
};
struct Crossing {
    Point point;
    GhNode *first, *second;
};
struct GhGraph {
    std::array<Rings, 2> rings;
    std::array<std::vector<std::vector<GhNode *>>, 2> nodes;
    std::array<std::vector<bool>, 2> initialInside;
    std::vector<std::unique_ptr<GhNode>> nodeStorage;
    std::vector<std::unique_ptr<Crossing>> crossingStorage;
    std::vector<Crossing *> crossings;
    int na = 0, nb = 0;
    GhGraph(const Rings &, const Rings &);
    Rings traverse(bool, bool) const;
};
struct Rendered {
    std::vector<std::string> rows;
    int result = 0, a = 0, b = 0, both = 0;
};
Rendered render(const Result &, int, int, int, int, int, int);
template <typename... Values> std::string text(const Values &...values) {
    std::ostringstream out;
    (out << ... << values);
    return out.str();
}
std::vector<std::string> readLines(const std::string &);
std::vector<std::string> words(const std::string &);
std::string join(const std::vector<std::string> &, const std::string &);
std::string fixed(double, int);
void writeLines(const std::string &, const std::vector<std::string> &);
#endif
