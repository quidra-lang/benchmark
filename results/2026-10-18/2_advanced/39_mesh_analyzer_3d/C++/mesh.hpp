#ifndef MESH_HPP
#define MESH_HPP
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <map>
#include <numeric>
#include <set>
#include <sstream>
#include <string>
#include <utility>
#include <vector>
using Integer = std::int64_t;
using Point = std::array<Integer, 3>;
using Lines = std::vector<std::string>;
struct Polygon {
    std::vector<int> vertices;
    int line = 0, group = 0;
};
struct InputError {
    int line;
    std::string kind;
};
struct Object {
    std::vector<Point> vertices{Point{0, 0, 0}};
    std::vector<Polygon> polygons;
    std::vector<std::string> groups;
    std::vector<InputError> errors;
    int lines = 0, ignored = 0;
};
struct Face {
    std::array<int, 3> vertices;
    int polygon = 0, line = 0, group = 0, triangle = 0;
};
struct Removed {
    int triangle, polygon, line;
    std::string reason;
};
struct Cleanup {
    std::vector<Point> snapped, points{Point{0, 0, 0}};
    std::vector<int> representative, new_number;
    std::vector<Face> faces;
    std::vector<Removed> removed;
    int triangles = 0, snapped_count = 0, merged_count = 0;
};
struct Options {
    int snap = 1, fill_holes = 0;
    bool merge = true, degenerate = true, duplicates = true, orient = true, outward = true,
         keep_unused = true;
    Lines sections{"summary", "components"};
    std::vector<Lines> queries;
};
struct Edge {
    int a, b;
    std::vector<int> faces;
};
struct Topology {
    std::vector<Edge> edges;
    std::vector<int> face_component, fans;
    std::vector<std::vector<int>> component_faces, component_vertices, component_edges, vertex_faces,
        vertex_edges, neighbors, fan_components, component_nonmanifold_vertices;
};
struct Loop {
    int component = 0;
    std::vector<int> vertices;
    bool closed = false, filled = false;
    std::string kind = "open";
    int length() const;
};
Lines read_lines(const std::string &path);
Lines words(const std::string &line);
bool integer_word(const std::string &word);
Object read_object();
void write_object(const std::vector<Point> &points, const std::vector<Face> &faces, const Lines &groups);
Topology analyze(const std::vector<Face> &faces, int vertices);
int edge_index(const Topology &topology, int a, int b);
std::vector<Loop> trace_loops(const Topology &topology);
bool directed(const Face &face, int a, int b);
void flip(Face &face);
void orient_faces(std::vector<Face> &faces, const Topology &topology);
std::vector<int> inconsistent_edges(const std::vector<Face> &faces, const Topology &topology);
Point difference(Point a, Point b);
Point cross(Point a, Point b);
Integer dot(Point a, Point b);
Point normal(const Face &face, const std::vector<Point> &points);
Integer determinant(const Face &face, const std::vector<Point> &points);
double area(const std::vector<int> &faces, const std::vector<Face> &mesh, const std::vector<Point> &points);
std::string fraction(Integer numerator, Integer denominator);
std::string real(double value);
std::string point_text(Point point);
std::string centroid(const std::vector<int> &faces, const std::vector<Face> &mesh,
                     const std::vector<Point> &points, Integer volume6);
int winding(Point point, const std::vector<int> &faces, const std::vector<Face> &mesh,
            const std::vector<Point> &points);
std::string triangle_angle(const Face &face, const std::vector<Point> &points);
std::vector<Face> triangulate(const Object &object);
Cleanup cleanup(const Object &object, const Options &options);
std::vector<Face> fill_faces(const Loop &loop, int group);
std::string list(const std::vector<int> &values, int offset = 0);
void write_lines(const std::string &name, const Lines &lines);
#endif
