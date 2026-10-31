#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <limits>
#include <map>
#include <numeric>
#include <set>
#include <sstream>
#include <string>
#include <utility>
#include <vector>
using Integer = std::int64_t;
using Ints = std::vector<int>;
using Lines = std::vector<std::string>;
using Pair = std::pair<int, int>;
using Triangle = std::array<int, 3>;
struct Point {
    Integer x = 0, y = 0;
};
Integer orient(Point p, Point q, Point r);
Integer incircle(Point a, Point b, Point c, Point d);
Integer d2(Point p, Point q);
Integer dot(Point o, Point p, Point q);
struct Center {
    Integer x = 0, y = 0, d = 1;
};
Center center(Point a, Point b, Point c);
std::string fraction(Integer numerator, Integer denominator);
Point outward(Point u, Point v);
Triangle canonical(Triangle triangle);
struct Insertion {
    int site = 0;
    bool inside = false;
    Triangle containing{};
    int visible = 0, flips = 0, triangles = 0, hull = 0;
};
struct Walk {
    Ints path;
    bool outside = false;
    Pair edge;
};
struct Triangulation {
    std::map<Pair, int> directed;
    void add(int a, int b, int c);
    void remove(int a, int b, int c);
    int third(int a, int b) const;
    std::vector<Triangle> triangles() const;
    std::vector<Pair> hull_edges() const;
    Insertion insert(const std::vector<Point> &points, int site);
    Walk walk(const std::vector<Point> &points, Point query) const;
};
Triangulation initialize(const std::vector<Point> &points);
double radius2(Point a, Point b, Point c);
std::string position(Center vertex, const std::vector<Point> &points, const Ints &hull);
Ints neighbor_order(const Triangulation &triangulation, int site, const Ints &neighbors, int next);
double cell_area(Point site, const std::vector<Center> &vertices, const Ints &sequence);
double clipped_area(const std::vector<Point> &points, int site, const Ints &neighbors);
struct Edge {
    int a = 0, b = 0, left = -1, right = -1;
    Integer length2 = 0;
    bool gabriel = false, rng = false, mst = false;
};
struct Disjoint {
    Ints parent;
    explicit Disjoint(int n);
    int find(int value);
    bool join(int a, int b);
};
Ints nearest(const std::vector<Point> &points, const std::vector<Ints> &neighbors);
Ints kruskal(std::vector<Edge> &edges, int sites);
bool gabriel(const std::vector<Point> &points, const Triangulation &triangulation, int a, int b);
bool relative_neighborhood(const std::vector<Point> &points, int a, int b);
Ints greedy_route(const std::vector<Point> &points, const std::vector<Ints> &neighbors, int source,
                  int target);
struct Paths {
    std::vector<double> distance;
    Ints previous;
};
Paths dijkstra(const std::vector<Point> &points, const std::vector<Ints> &neighbors, int source);
using Grid = std::vector<std::string>;
Grid canvas(int width, int height);
Pair map_point(Point point, int width, int height);
Pair map_center(Center point, int width, int height);
void draw_line(Grid &grid, Pair start, Pair end, char character);
Grid voronoi_plot(const std::vector<Point> &points, int width, int height);
Lines framed(const Grid &grid);
