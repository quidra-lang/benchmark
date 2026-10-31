#ifndef HEAT_HPP
#define HEAT_HPP
#include <algorithm>
#include <array>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <limits>
#include <numeric>
#include <optional>
#include <sstream>
#include <string>
#include <utility>
#include <vector>
using Field = std::vector<double>;
using Ids = std::vector<int>;
using Lines = std::vector<std::string>;
struct Mesh {
    int width = 0, height = 0, count = 0;
    double dx = 0, thickness = 0;
    std::string codes;
    std::vector<std::array<int, 4>> neighbors;
    int cell(int row, int column) const { return row * width + column; }
    std::string coordinates(int point) const;
    std::vector<std::pair<int, int>> segment_faces(const std::string &edge, int start,
                                                   int end) const;
    Ids source_cells(int r1, int c1, int r2, int c2) const;
};
Mesh read_mesh();
struct Material {
    char code;
    std::string name;
    double k, rho, cp;
};
std::vector<Material> read_materials();
double capacity(const Material &material, double dx, double thickness),
    interior(double first, double second, double thickness),
    fixed(double conductivity, double thickness),
    convective(double conductivity, double coefficient, double dx, double thickness);
struct Face {
    int neighbor = -1;
    double g = 0;
    std::optional<double> theta;
};
struct Segment {
    std::string name, edge, kind;
    std::vector<std::pair<int, int>> faces;
    double coefficient = 0, theta = 0;
};
struct Source {
    std::string name;
    Ids cells;
    double power = 0;
    std::vector<std::pair<int, int>> intervals;
    bool operating(int time) const;
    double duty(int end) const;
};
struct Probe {
    std::string name;
    int point;
};
struct Run {
    std::string name, method;
    int step;
};
struct Params {
    double initial = 0, tolerance = 0, omega = 0, alarm = 0, limit = 0;
    int end = 0, probe_every = 0, max_iterations = 0;
    Ids snapshots;
    std::vector<Probe> probes;
    std::vector<Run> runs;
    std::string reference;
    Field bands;
};
struct System {
    Mesh mesh;
    std::vector<Material> materials;
    std::vector<Segment> segments;
    std::vector<Source> sources;
    std::vector<std::array<Face, 4>> faces;
    Ids cell_material;
    std::vector<Ids> material_cells;
    Field capacity, diagonal, beta, source_all;
    double total_power = 0, dt_max = 0;
};
double heat_flow(const System &system, const Field &field, int point, int first, int last);
Field thomas(const Field &lower, const Field &diagonal, const Field &upper, const Field &rhs);
Field sweep(const System &system, double tau, const Field &rhs, bool horizontal);
struct Step {
    Field field, intermediate;
};
Step advance(const System &system, const Field &field, const Field &source, double dt,
             const std::string &method);
double g_value(const System &system, const Field &field, int point);
struct Iteration {
    std::string method;
    Field field, changes;
    double omega;
    bool converged;
};
Iteration iterate(const System &system, const Params &params, const std::string &method,
                  double omega = 1);
std::vector<Field> direct(const System &system, std::vector<Field> right_hand_sides);
double residual(const System &system, const Field &field, const Field &rhs);
std::string real(double value, int digits), time_text(int milliseconds);
int hottest(const Field &field);
std::string summary(const std::string &prefix, const Mesh &mesh, const Field &field);
void field_lines(Lines &lines, const Mesh &mesh, const Field &field);
void isotherms(Lines &lines, const std::string &prefix, const Mesh &mesh, const Field &field,
               const Field &bands);
void save(const std::string &name, const Lines &lines);
template <typename... T> void line(Lines &lines, const T &...values) {
    std::ostringstream out;
    (out << ... << values);
    lines.push_back(out.str());
}
#endif
